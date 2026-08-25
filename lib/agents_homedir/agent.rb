# frozen_string_literal: true

require "date"

module AgentsHomedir
  class Agent < Data.define(:name, :label, :env_override, :verified_on)
    # Equality and hash intentionally cover only public facts.
    # Resolver-specific caches should key by resolver and agent name.
    def initialize(name:, label:, env_override:, verified_on:, resolver:)
      validate_name!(name)
      validate_label!(label)
      validate_env_override!(env_override)
      validate_verified_on!(verified_on)

      @resolver = resolver

      super(
        name: name,
        label: snapshot_string(label),
        env_override: snapshot_string(env_override),
        verified_on:
      )
    end

    def home = @resolver.home(name)

    def installed? = @resolver.installed?(name)

    def candidates = @resolver.candidates(name)

    def with(**changes)
      return self if changes.empty?

      unknown_members = changes.keys - self.class.members
      fail ArgumentError, "Unknown member(s) for #{self.class}: #{unknown_members.map(&:inspect).join(', ')}" if unknown_members.any?
      reject_resolver_bound_changes!(changes)

      updated = to_h.merge(changes)
      return self if updated == to_h

      self.class.new(**updated, resolver: @resolver)
    end

    private

    def reject_resolver_bound_changes!(changes)
      [:name, :env_override].each do |field|
        next unless changes.key?(field)
        next if changes[field] == public_send(field)

        fail ArgumentError, "#{field} is resolver-bound and cannot be changed via #with"
      end
    end

    def validate_name!(value)
      fail ArgumentError, "name must be a Symbol" unless value.is_a?(Symbol)
    end

    def validate_label!(value)
      fail ArgumentError, "label must be a String" unless value.is_a?(String)
    end

    def validate_env_override!(value)
      return if value.nil? || value.is_a?(String)

      fail ArgumentError, "env_override must be a String or nil"
    end

    def validate_verified_on!(value)
      return if value.nil? || value.is_a?(Date)

      fail ArgumentError, "verified_on must be a Date or nil"
    end

    def snapshot_string(value)
      return if value.nil?

      value.dup.freeze
    end
  end
end
