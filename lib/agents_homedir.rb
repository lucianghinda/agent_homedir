# frozen_string_literal: true

require "monitor"
require "zeitwerk"

module AgentsHomedir
end

loader = Zeitwerk::Loader.for_gem
loader.setup
AgentsHomedir.const_set(:LOADER, loader)

module AgentsHomedir
  DEFAULT_RESOLVER_MONITOR = Monitor.new
  private_constant :DEFAULT_RESOLVER_MONITOR, :LOADER

  class << self
    # Returns the memoized default resolver built from the current environment.
    # ENV and HOME are snapshotted on first access and reused for process lifetime.
    #
    # @return [AgentsHomedir::Resolver]
    # @raise [ArgumentError] if the current host OS is unsupported
    def default_resolver
      return @default_resolver if @default_resolver

      DEFAULT_RESOLVER_MONITOR.synchronize do
        @default_resolver ||= Resolver.new
      end
    end

    # Returns the configured home directory for the named agent.
    #
    # @param name [String, Symbol]
    # @return [Pathname]
    # @raise [AgentsHomedir::UnknownAgent] if the name is not registered
    # @raise [AgentsHomedir::HomeNotResolvable] if HOME is missing, blank, or not absolute
    def home(name)
      default_resolver.home(name)
    end

    # Returns whether the named agent is currently installed.
    #
    # @param name [String, Symbol]
    # @return [Boolean]
    # @raise [AgentsHomedir::UnknownAgent] if the name is not registered
    # @raise [AgentsHomedir::HomeNotResolvable] if HOME is missing, blank, or not absolute
    def installed?(name)
      default_resolver.installed?(name)
    end

    # Returns the named agent from the default registry.
    #
    # @param name [String, Symbol]
    # @return [AgentsHomedir::Agent]
    # @raise [AgentsHomedir::UnknownAgent] if the name is not registered
    def [](name)
      default_resolver[name]
    end

    # Returns all known agents in registry order.
    #
    # @return [Array<AgentsHomedir::Agent>]
    def agents
      default_resolver.agents
    end

    # Returns currently installed agents in registry order.
    #
    # @return [Array<AgentsHomedir::Agent>]
    # @raise [AgentsHomedir::HomeNotResolvable] if HOME is missing, blank, or not absolute
    def installed
      default_resolver.installed
    end

    # Returns all known agent names in registry order.
    #
    # @return [Array<Symbol>]
    def names
      default_resolver.names
    end

    private

    def loader
      LOADER
    end
  end
end
