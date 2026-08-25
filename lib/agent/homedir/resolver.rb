# frozen_string_literal: true

require "agent/homedir"
require "date"
require "monitor"
require "pathname"
require "rbconfig"

module Agent
  module Homedir
    class Resolver
      VALID_OSES = %i[macos linux windows].freeze
      WINDOWS_DRIVE_PATH = /\A[A-Za-z]:[\/\\]/.freeze
      WINDOWS_UNC_PATH = /\A[\/\\]{2}[^\/\\]+[\/\\]+[^\/\\]+/.freeze

      class << self
        def default_os
          @default_os ||= detect_os(RbConfig::CONFIG["host_os"])
        end

        private

        def detect_os(host_os)
          case host_os
          when /darwin/i
            :macos
          when /linux/i
            :linux
          when /mswin|mingw/i
            :windows
          else
            fail ArgumentError, "Unsupported host OS: #{host_os.inspect}"
          end
        end
      end

      def initialize(env: ENV.to_h, home: ENV["HOME"], os: self.class.default_os, entries: Registry.entries)
        fail ArgumentError, "Invalid OS #{os.inspect}; expected one of #{VALID_OSES.inspect}" unless VALID_OSES.include?(os)

        @env = snapshot_value(env)
        @home = snapshot_value(home)
        @os = os
        @entries = snapshot_value(entries)
        @memoization_monitor = Monitor.new
      end

      def home(name)
        ensure_home_root!

        override = env_override_for(name)
        return override if override

        available_candidates = candidates(name)
        find_directory_candidate(available_candidates) || available_candidates.first
      end

      def installed?(name)
        ensure_home_root!

        override = env_override_for(name)
        return true if directory_path?(override)

        candidates(name).any? { directory_path?(_1) }
      end

      def candidates(name)
        home_root = ensure_home_root!
        specs = path_specs_for(name)
        expanded = expand_specs(specs, home_root)
        fail ArgumentError, no_paths_message(name, "current os paths are empty") if expanded.empty?

        expanded.freeze
      end

      def [](name)
        key = name.to_sym
        entry = entry_for(key)

        Entry.new(
          name: key,
          label: entry.fetch(:label),
          env_override: entry[:env],
          verified_on: parse_verified_on(key, entry[:verified_on]),
          resolver: self
        )
      end

      def names
        return @names if @names

        @memoization_monitor.synchronize do
          @names ||= @entries.keys.freeze
        end
      end

      def agents
        return @agents if @agents

        @memoization_monitor.synchronize do
          @agents ||= names.map { self[_1] }.freeze
        end
      end

      def installed
        agents.select(&:installed?).freeze
      end

      private

      def entry_for(name)
        key = name.to_sym
        entry = @entries[key]
        return entry if entry

        valid = @entries.keys.map(&:inspect).sort.join(", ")
        fail UnknownAgent, "Unknown agent #{name.inspect}. Valid agents: #{valid}"
      end

      def path_specs_for(name)
        specs = entry_for(name).fetch(:paths)
        fail ArgumentError, no_paths_message(name, "paths are nil") if specs.nil?
        fail ArgumentError, no_paths_message(name, "paths are empty") if specs.respond_to?(:empty?) && specs.empty?

        specs
      end

      def env_override_for(name)
        entry = entry_for(name)
        env_key = entry[:env]
        return unless env_key

        raw = @env[env_key]
        return if blank?(raw)

        Pathname(resolve_path(raw, ensure_home_root!, allow_relative: true))
      end

      def ensure_home_root!
        raw_home = @home.to_s
        fail HomeNotResolvable, "HOME is not resolvable" if blank?(raw_home)

        normalized = normalize_separators(raw_home)
        fail HomeNotResolvable, "HOME is not resolvable" unless absolute_path?(normalized)

        normalized
      end

      def expand_specs(specs, home_root)
        return specs.flat_map { expand_spec(_1, home_root) } if specs.is_a?(Array)

        expand_spec(specs, home_root)
      end

      def expand_spec(spec, home_root)
        case spec
        when Array
          expand_specs(spec, home_root)
        when String
          [Pathname(resolve_registry_path(spec, home_root))]
        when Hash
          if os_selector?(spec)
            selected = spec[@os]
            selected ? expand_spec(selected, home_root) : []
          elsif spec.key?(:xdg)
            [Pathname(resolve_xdg_path(spec, home_root))]
          elsif spec.key?(:windows_env)
            resolved = resolve_windows_env_path(spec)
            resolved ? [Pathname(resolved)] : []
          else
            fail ArgumentError, "Unsupported path spec #{spec.inspect}"
          end
        else
          fail ArgumentError, "Unsupported path spec #{spec.inspect}"
        end
      end

      def os_selector?(spec)
        !(spec.keys & VALID_OSES).empty?
      end

      def resolve_registry_path(spec, home_root)
        if spec == "~" || spec.start_with?("~/", "~\\")
          expand_tilde(spec, home_root)
        else
          normalized = normalize_separators(spec)
          ensure_absolute!(normalized)
        end
      end

      def resolve_xdg_path(spec, home_root)
        base =
          case spec.fetch(:xdg)
          when :config
            resolve_xdg_base("XDG_CONFIG_HOME", join_path(home_root, ".config"))
          when :data
            resolve_xdg_base("XDG_DATA_HOME", join_path(home_root, ".local/share"))
          else
            fail ArgumentError, "Unsupported XDG base #{spec[:xdg].inspect}"
          end

        join_child_path(base, spec.fetch(:path), "XDG")
      end

      def resolve_xdg_base(env_key, fallback)
        value = @env[env_key]
        return fallback if blank?(value)

        normalized = normalize_separators(value.to_s)
        return fallback unless absolute_path?(normalized)

        normalized
      end

      def resolve_windows_env_path(spec)
        env_key = spec.fetch(:windows_env)
        base_value = @env[env_key]

        if blank?(base_value)
          fallback_suffix = windows_home_fallback_suffix(env_key)
          base_value = join_child_path(ensure_home_root!, fallback_suffix, env_key) if fallback_suffix
        end

        return if blank?(base_value) && spec.fetch(:optional, false)
        fail ArgumentError, "Missing windows_env #{env_key} for #{spec.inspect}" if blank?(base_value)

        if optional_windows_xdg_env?(env_key, spec)
          normalized = normalize_separators(base_value.to_s)
          return unless absolute_path?(normalized)

          base_value = normalized
        end

        base = resolve_path(base_value, ensure_home_root!, allow_relative: false)
        join_child_path(base, spec.fetch(:path), env_key)
      end

      def resolve_path(raw_path, home_root, allow_relative:)
        normalized = normalize_separators(raw_path.to_s)
        return expand_tilde(normalized, home_root) if normalized == "~" || normalized.start_with?("~/", "~\\")
        return normalized if absolute_path?(normalized)
        fail ArgumentError, "Resolved path must be an ordinary relative path: #{raw_path.inspect}" if invalid_relative_join_path?(normalized)

        if allow_relative
          join_relative(home_root, normalized)
        else
          fail ArgumentError, "Resolved path must be absolute: #{raw_path.inspect}"
        end
      end

      def expand_tilde(path, home_root)
        suffix = path == "~" ? "" : path[2..]
        suffix.empty? ? home_root : join_relative(home_root, suffix)
      end

      def join_child_path(base, child, source_name)
        child_path = normalize_separators(child.to_s)
        fail ArgumentError, "#{source_name} child path must be relative: #{child.inspect}" if blank?(child_path)
        fail ArgumentError, "#{source_name} child path must be relative: #{child.inspect}" if absolute_path?(child_path)
        fail ArgumentError, "#{source_name} child path must be relative: #{child.inspect}" if invalid_relative_join_path?(child_path)

        join_relative(base, child_path)
      end

      def join_relative(base, relative)
        relative_path = normalize_separators(relative.to_s)
        return ensure_absolute!(relative_path) if absolute_path?(relative_path)
        fail ArgumentError, "Resolved path must not stay relative: #{relative.inspect}" if relative_path.empty?

        joined = join_path(base, relative_path)
        ensure_absolute!(joined)
      end

      def join_path(base, suffix)
        cleaned_base = normalize_separators(base)
        cleaned_suffix = normalize_separators(suffix).sub(%r{\A/+}, "")
        return "/" if posix_root_path?(cleaned_base) && cleaned_suffix.empty?
        return "/#{cleaned_suffix}" if posix_root_path?(cleaned_base)

        cleaned_base = cleaned_base.sub(%r{/+\z}, "")

        [cleaned_base, cleaned_suffix].reject(&:empty?).join("/")
      end

      def ensure_absolute!(path)
        normalized = normalize_separators(path)
        fail ArgumentError, "Resolved path must be absolute: #{path.inspect}" unless absolute_path?(normalized)

        normalized
      end

      def absolute_path?(path)
        return windows_absolute_path?(path) if @os == :windows

        Pathname(path).absolute?
      end

      def windows_absolute_path?(path)
        normalized = normalize_separators(path)
        normalized.match?(WINDOWS_DRIVE_PATH) || normalized.match?(WINDOWS_UNC_PATH)
      end

      def invalid_relative_join_path?(path)
        return false unless @os == :windows
        return false if absolute_path?(path)

        path.start_with?("/") || drive_relative_path?(path)
      end

      def drive_relative_path?(path)
        path.match?(/\A[A-Za-z]:(?!\/)/)
      end

      def find_directory_candidate(candidates)
        candidates.find { directory_path?(_1) }
      end

      def windows_home_fallback_suffix(env_key)
        {
          "APPDATA" => "AppData/Roaming",
          "LOCALAPPDATA" => "AppData/Local"
        }[env_key]
      end

      def optional_windows_xdg_env?(env_key, spec)
        spec.fetch(:optional, false) && env_key.start_with?("XDG_")
      end

      def directory_path?(path)
        path&.directory? || false
      end

      def normalize_separators(path)
        return path.tr("\\", "/") if @os == :windows

        path
      end

      def posix_root_path?(path)
        @os != :windows && path.match?(%r{\A/+\z})
      end

      def no_paths_message(name, detail)
        "No paths configured for #{name.inspect} on #{@os.inspect}: #{detail}"
      end

      def parse_verified_on(name, value)
        return if value.nil?
        fail ArgumentError, "Invalid verified_on for #{name.inspect}: #{value.inspect}" unless value.is_a?(String)

        Date.iso8601(value)
      rescue Date::Error
        fail ArgumentError, "Invalid verified_on for #{name.inspect}: #{value.inspect}"
      end

      def blank?(value)
        value.nil? || value.to_s.strip.empty?
      end

      def snapshot_value(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested), copy|
            copy[snapshot_value(key)] = snapshot_value(nested)
          end.freeze
        when Array
          value.map { snapshot_value(_1) }.freeze
        when String
          value.dup.freeze
        else
          value
        end
      end
    end
  end
end
