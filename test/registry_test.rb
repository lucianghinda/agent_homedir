# frozen_string_literal: true

require "test_helper"
require "date"
require "pathname"

class RegistryTest < Minitest::Test
  def test_entries_match_the_exact_ordered_catalog
    registry = registry_entries
    expected_catalog = [
      [:claude_code, "Claude Code", "CLAUDE_CONFIG_DIR", "~/.claude", "2026-08-05"],
      [:codex, "Codex CLI", "CODEX_HOME", "~/.codex", "2026-07-21"],
      [:gemini, "Gemini CLI", nil, "~/.gemini", nil],
      [:antigravity_cli, "Antigravity CLI", nil, "~/.gemini/antigravity-cli", nil],
      [:antigravity_ide, "Antigravity IDE", nil, "~/.gemini/antigravity-ide", nil],
      [:antigravity_app, "Antigravity App", nil, "~/.gemini/antigravity", nil],
      [:qwen, "Qwen Code", nil, "~/.qwen", nil],
      [:pi, "Pi", "PI_CODING_AGENT_DIR", "~/.pi/agent", "2026-07-21"],
      [:amp, "Amp", nil, [{xdg: :data, path: "amp"}], "2026-07-21"],
      [
        :opencode,
        "OpenCode",
        "OPENCODE_DATA_DIR",
        {
          macos: [{xdg: :data, path: "opencode"}, "~/Library/Application Support/opencode"],
          linux: [{xdg: :data, path: "opencode"}],
          windows: [
            {windows_env: "XDG_DATA_HOME", path: "opencode", optional: true},
            {windows_env: "APPDATA", path: "opencode"},
            {windows_env: "LOCALAPPDATA", path: "opencode"},
            "~/.local/share/opencode"
          ]
        },
        "2026-07-21"
      ],
      [:cursor, "Cursor", nil, "~/.cursor", "2026-07-21"],
      [
        :cursor_ide,
        "Cursor IDE",
        nil,
        {
          macos: "~/Library/Application Support/Cursor",
          linux: {xdg: :config, path: "Cursor"},
          windows: {windows_env: "APPDATA", path: "Cursor"}
        },
        nil
      ],
      [:github_copilot_cli, "GitHub Copilot CLI", nil, "~/.copilot", nil],
      [
        :vscode_copilot_chat,
        "VS Code Copilot Chat",
        nil,
        {
          macos: "~/Library/Application Support/Code/User",
          linux: {xdg: :config, path: "Code/User"},
          windows: {windows_env: "APPDATA", path: "Code/User"}
        },
        nil
      ],
      [:cline, "Cline", nil, "~/.cline", nil],
      [
        :cline_vscode,
        "Cline for VS Code",
        nil,
        {
          macos: "~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev",
          linux: {xdg: :config, path: "Code/User/globalStorage/saoudrizwan.claude-dev"},
          windows: {windows_env: "APPDATA", path: "Code/User/globalStorage/saoudrizwan.claude-dev"}
        },
        nil
      ],
      [:grok_build, "Grok Build", nil, "~/.grok", nil],
      [:vibe, "Vibe", nil, "~/.vibe", nil],
      [:muse, "Muse Code", nil, [{xdg: :data, path: "muse"}], nil],
      [:prime_agent, "Prime Agent", nil, "~/.prime/agent", nil],
      [:deepseek_harness, "DeepSeek Harness", "DSH_HOME", "~/.dsh", nil],
      [:hermes, "Hermes Agent", "HERMES_HOME", "~/.hermes", nil],
      [:factory_droid, "Factory Droid", nil, "~/.factory", nil],
      [:devin_cli, "Devin CLI", nil, "~/.config/devin", nil],
      [:devin_desktop, "Devin Desktop", nil, "~/.codeium/windsurf", nil]
    ]

    assert_equal expected_catalog.map(&:first), registry.keys

    actual_catalog = registry.map do |name, entry|
      [name, entry[:label], entry[:env], entry[:paths], entry[:verified_on]]
    end

    assert_equal expected_catalog, actual_catalog
  end

  def test_entries_are_deeply_frozen_plain_values
    entries = registry_entries

    assert_predicate entries, :frozen?
    assert_equal Hash, entries.class

    assert_plain_frozen_data(entries, context: "registry entries")
  end

  def test_registry_entries_are_structurally_sound_across_supported_targets
    registry_entries.each do |name, entry|
      assert_equal Symbol, name.class, "#{name.inspect}: entry name must be a Symbol"
      assert_equal %i[label env paths verified_on], entry.keys, "#{name.inspect}: entry keys must match the registry schema"

      assert_nonblank_frozen_string(entry[:label], "#{name.inspect}: label")

      env_key = entry[:env]
      assert_nil_or_nonblank_frozen_string(env_key, "#{name.inspect}: env")

      paths = entry[:paths]
      refute_nil paths, "#{name.inspect}: paths must not be nil"
      refute paths.respond_to?(:empty?) && paths.empty?, "#{name.inspect}: paths must not be empty"
      assert_path_spec(paths, context: "#{name.inspect}: paths")

      verified_on = entry[:verified_on]
      assert_nil_or_canonical_iso8601_date_string(verified_on, "#{name.inspect}: verified_on")

      %i[macos linux windows].each do |os|
        resolver = build_resolver(os:, home: target_home(os), env: target_env(os, name, entry))
        context = "#{name.inspect} on #{os}"

        candidates = resolver.candidates(name)
        assert_predicate candidates, :frozen?, "#{context}: candidates must be frozen"
        refute_empty candidates, "#{context}: candidates must not be empty"

        candidates.each do |candidate|
          assert_instance_of Pathname, candidate, "#{context}: candidate must be a Pathname"
          assert_target_absolute_path(candidate, os:, context: "#{context}: candidate")
        end

        home = resolver.home(name)
        assert_instance_of Pathname, home, "#{context}: home must be a Pathname"
        assert_target_absolute_path(home, os:, context: "#{context}: home")

        agent = resolver[name]
        expected_verified_on = verified_on && Date.iso8601(verified_on)

        if expected_verified_on
          assert_equal expected_verified_on, agent.verified_on, "#{context}: verified_on must match registry metadata"
          assert_instance_of Date, agent.verified_on, "#{context}: verified_on must resolve to a Date"
        else
          assert_nil agent.verified_on, "#{context}: verified_on must stay nil"
        end
      end
    end
  end

  def test_registry_excludes_project_local_and_non_home_entries
    entries = registry_entries
    excluded = %i[
      smallcode
      claude_cowork
      shared_agent_skills
      devin_project_local
      devin_app_bundle
    ]

    excluded.each do |name|
      refute_includes entries.keys, name
    end

    refute_includes entries.fetch(:pi).inspect, "PI_CODING_AGENT_SESSION_DIR"
    refute_includes entries.fetch(:prime_agent).inspect, "PRIME_AGENT_SESSION_DIR"
    refute_includes entries.fetch(:devin_cli).inspect, ".devin"
    refute_includes entries.fetch(:devin_desktop).inspect, "Application Support/Devin"
  end

  def test_registry_constant_is_private_but_default_resolver_still_works
    error = assert_raises(NameError) do
      Agent::Homedir::Registry
    end

    assert_includes error.message, "private constant"

    resolver = build_resolver(os: :linux, home: "/home/test")

    assert_equal Pathname("/home/test/.codex"), resolver.home(:codex)
  end

  def test_default_resolver_exposes_registry_metadata_as_agent_facts
    resolver = build_resolver(
      os: :linux,
      home: "/home/test",
      env: {
        "APPDATA" => "C:/Users/Test/AppData/Roaming",
        "LOCALAPPDATA" => "C:/Users/Test/AppData/Local"
      }
    )

    claude = resolver[:claude_code]
    cursor = resolver[:cursor]

    assert_equal "Claude Code", claude.label
    assert_equal "CLAUDE_CONFIG_DIR", claude.env_override
    assert_equal Date.new(2026, 8, 5), claude.verified_on
    assert_equal "Cursor", cursor.label
    assert_nil cursor.env_override
    assert_equal Date.new(2026, 7, 21), cursor.verified_on
  end

  def test_default_resolver_uses_expected_representative_candidates_across_oses
    linux = build_resolver(os: :linux, home: "/home/test")
    macos = build_resolver(os: :macos, home: "/Users/Test")
    windows = build_resolver(
      os: :windows,
      home: "C:/Users/Test",
      env: {
        "APPDATA" => "C:/Users/Test/AppData/Roaming",
        "LOCALAPPDATA" => "C:/Users/Test/AppData/Local"
      }
    )

    assert_equal [Pathname("/home/test/.local/share/amp")], linux[:amp].candidates
    assert_equal [
      Pathname("/Users/Test/.local/share/opencode"),
      Pathname("/Users/Test/Library/Application Support/opencode")
    ], macos[:opencode].candidates
    assert_equal [
      Pathname("C:/Users/Test/AppData/Roaming/opencode"),
      Pathname("C:/Users/Test/AppData/Local/opencode"),
      Pathname("C:/Users/Test/.local/share/opencode")
    ], windows[:opencode].candidates
    assert_equal [Pathname("/home/test/.cursor")], linux[:cursor].candidates
    assert_equal [Pathname("/home/test/.config/Cursor")], linux[:cursor_ide].candidates
    assert_equal [Pathname("/Users/Test/Library/Application Support/Code/User")], macos[:vscode_copilot_chat].candidates
    assert_equal [Pathname("C:/Users/Test/AppData/Roaming/Code/User/globalStorage/saoudrizwan.claude-dev")], windows[:cline_vscode].candidates
    assert_equal [Pathname("/home/test/.config/devin")], linux[:devin_cli].candidates
    assert_equal [Pathname("/Users/Test/.codeium/windsurf")], macos[:devin_desktop].candidates
  end

  private

  def registry_entries
    Agent::Homedir.const_get(:Registry, false).entries
  end

  def build_resolver(env: {}, home:, os:)
    Agent::Homedir::Resolver.new(env:, home:, os:)
  end

  def target_home(os)
    {
      macos: "/Users/Test",
      linux: "/home/test",
      windows: "C:/Users/Test"
    }.fetch(os)
  end

  def target_env(os, name, entry)
    env = {
      "XDG_CONFIG_HOME" => os == :windows ? "C:/Users/Test/.config" : "#{target_home(os)}/.config",
      "XDG_DATA_HOME" => os == :windows ? "C:/Users/Test/.local/share" : "#{target_home(os)}/.local/share",
      "APPDATA" => "C:/Users/Test/AppData/Roaming",
      "LOCALAPPDATA" => "C:/Users/Test/AppData/Local"
    }

    return env unless entry[:env]

    env.merge(entry[:env] => override_home_for(os, name))
  end

  def override_home_for(os, name)
    base =
      case os
      when :macos
        "/Users/Test/Overrides"
      when :linux
        "/home/test/overrides"
      when :windows
        "C:/Users/Test/Overrides"
      else
        raise ArgumentError, "Unsupported OS #{os.inspect}"
      end

    "#{base}/#{name}"
  end

  def assert_plain_frozen_data(value, context:)
    case value
    when Hash
      assert_predicate value, :frozen?, "#{context}: hash must be frozen"
      value.each do |key, nested|
        assert_plain_frozen_data(key, context: "#{context} key #{key.inspect}")
        assert_plain_frozen_data(nested, context: "#{context}[#{key.inspect}]")
      end
    when Array
      assert_predicate value, :frozen?, "#{context}: array must be frozen"
      value.each_with_index do |nested, index|
        assert_plain_frozen_data(nested, context: "#{context}[#{index}]")
      end
    when String
      assert_predicate value, :frozen?, "#{context}: string must be frozen"
    when Symbol, NilClass, TrueClass, FalseClass
      nil
    else
      flunk "#{context}: unsupported plain-data type #{value.class}"
    end
  end

  def assert_nonblank_frozen_string(value, context)
    assert_instance_of String, value, "#{context} must be a String"
    assert_predicate value, :frozen?, "#{context} must be frozen"
    refute_empty value.strip, "#{context} must not be blank"
  end

  def assert_nil_or_nonblank_frozen_string(value, context)
    return if value.nil?

    assert_nonblank_frozen_string(value, context)
  end

  def assert_nil_or_canonical_iso8601_date_string(value, context)
    return if value.nil?

    assert_nonblank_frozen_string(value, context)
    assert_equal value, Date.iso8601(value).iso8601, "#{context} must be canonical ISO-8601"
  rescue Date::Error
    flunk "#{context} must be a canonical ISO-8601 date String: #{value.inspect}"
  end

  def assert_path_spec(spec, context:)
    case spec
    when Array
      refute_empty spec, "#{context}: path array must not be empty"
      spec.each_with_index do |nested, index|
        assert_path_spec(nested, context: "#{context}[#{index}]")
      end
    when String
      assert_nonblank_frozen_string(spec, context)
    when Hash
      assert_supported_spec_hash(spec, context:)
    else
      flunk "#{context}: unsupported path spec type #{spec.class}"
    end
  end

  def assert_supported_spec_hash(spec, context:)
    keys = spec.keys
    symbol_keys = keys.select { _1.is_a?(Symbol) }
    nonsymbol_keys = keys - symbol_keys

    assert_empty nonsymbol_keys, "#{context}: path spec keys must be Symbols, got #{nonsymbol_keys.inspect}"

    if (symbol_keys & %i[macos linux windows]).any?
      assert_exact_symbol_keys(symbol_keys, expected: %i[macos linux windows], context:, label: "selector")

      spec.each do |os, nested|
        assert_includes %i[macos linux windows], os, "#{context}: selector key #{os.inspect} is not supported"
        assert_path_spec(nested, context: "#{context}[#{os}]")
      end
    elsif exact_symbol_keys?(symbol_keys, %i[path xdg])
      assert_includes %i[config data], spec.fetch(:xdg), "#{context}: xdg must be :config or :data"
      assert_nonblank_relative_child(spec.fetch(:path), "#{context}: xdg path")
    elsif exact_symbol_keys?(symbol_keys, %i[path windows_env]) || exact_symbol_keys?(symbol_keys, %i[optional path windows_env])
      assert_nonblank_frozen_string(spec.fetch(:windows_env), "#{context}: windows_env")
      assert_nonblank_relative_child(spec.fetch(:path), "#{context}: windows path")
      assert_includes [true, false], spec.fetch(:optional, false), "#{context}: optional must be boolean when present"
    else
      flunk "#{context}: unsupported path spec keys #{keys.inspect}"
    end
  end

  def assert_target_absolute_path(path, os:, context:)
    assert target_absolute_path?(path.to_s, os:), "#{context} must be absolute for #{os}: #{path}"
  end

  def target_absolute_path?(path, os:)
    return Pathname(path).absolute? unless os == :windows

    windows_absolute_path?(path)
  end

  def windows_absolute_path?(path)
    return true if path.match?(/\A[A-Za-z]:(?:\/|\\)/)
    return false if path.match?(/\A[A-Za-z]:(?!\/|\\)/)

    path.match?(/\A(?:\\\\|\/\/)[^\/\\]+(?:\/|\\)[^\/\\]+(?:(?:\/|\\).*)?\z/)
  end

  def exact_symbol_keys?(actual, expected)
    (actual - expected).empty? && (expected - actual).empty?
  end

  def assert_exact_symbol_keys(actual, expected:, context:, label:)
    unexpected = actual - expected
    missing = expected - actual
    return if unexpected.empty? && missing.empty?

    flunk "#{context}: #{label} keys must be exactly #{expected.inspect}; unexpected #{unexpected.inspect}, missing #{missing.inspect}"
  end

  def assert_nonblank_relative_child(value, context)
    assert_nonblank_frozen_string(value, context)

    normalized = value.tr("\\", "/")
    refute normalized.start_with?("/"), "#{context} must be relative"
    refute_match(/\A[A-Za-z]:/, normalized, "#{context} must be relative")

    normalized.split("/").each do |segment|
      refute_includes [".", ".."], segment, "#{context} must use ordinary relative path segments"
      refute_empty segment, "#{context} must not contain empty path segments"
    end
  end
end
