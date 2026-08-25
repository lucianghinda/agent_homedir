# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "open3"
require "pathname"
require "rbconfig"
require "timeout"
require "tmpdir"

class AgentHomedirTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Agent::Homedir::VERSION
  end

  def test_version_string_is_frozen
    assert_predicate Agent::Homedir::VERSION, :frozen?
  end

  def test_default_resolver_is_memoized
    resolver = Agent::Homedir.default_resolver

    assert_instance_of Agent::Homedir::Resolver, resolver
    assert_same resolver, Agent::Homedir.default_resolver
  end

  def test_private_loader_can_eager_load_the_library
    loader = Agent::Homedir.send(:loader)

    assert_kind_of Zeitwerk::Loader, loader
    loader.eager_load
    assert_equal Agent::Homedir::Entry, Agent::Homedir.const_get(:Entry)
    assert_equal Agent::Homedir::Resolver, Agent::Homedir.const_get(:Resolver)
    assert_equal Agent::Homedir::UnknownAgent, Agent::Homedir.const_get(:UnknownAgent)
    assert_equal Agent::Homedir::HomeNotResolvable, Agent::Homedir.const_get(:HomeNotResolvable)
  end

  def test_default_resolver_monitor_constant_is_private
    error = assert_raises(NameError) { Agent::Homedir::DEFAULT_RESOLVER_MONITOR }

    assert_includes error.message, "private constant"
  end

  def test_default_resolver_first_initialization_is_identity_stable_across_parallel_callers
    script = <<~RUBY
      require "agent_homedir"
      require "thread"
      require "timeout"

      resolver_class = Agent::Homedir::Resolver
      class << resolver_class
        alias_method :__test_original_new, :new
      end

      build_count = 0
      build_count_lock = Mutex.new
      build_started = Queue.new
      build_release = Queue.new
      overlapping_builds = Queue.new

      resolver_class.define_singleton_method(:new) do |*args, **kwargs|
        call_number = build_count_lock.synchronize do
          build_count += 1
        end
        build_started << call_number
        overlapping_builds << call_number if call_number > 1
        build_release.pop
        __test_original_new(*args, **kwargs)
      end

      callers_ready = Queue.new
      callers_release = Queue.new
      results = Queue.new

      threads = 8.times.map do
        Thread.new do
          callers_ready << true
          callers_release.pop
          results << Agent::Homedir.default_resolver
        end
      end

      Timeout.timeout(1) { 8.times { callers_ready.pop } }
      8.times { callers_release << true }

      Timeout.timeout(1) { build_started.pop }

      begin
        overlapping_call = Timeout.timeout(0.2) { overlapping_builds.pop }
        abort("expected synchronized first build, got overlapping build \#{overlapping_call}")
      rescue Timeout::Error
      end

      build_release << true

      Timeout.timeout(1) do
        threads.each do |thread|
          abort("thread join timed out") unless thread.join(1)
        end
      end

      resolvers = 8.times.map { results.pop }
      abort("expected one build, got \#{build_count}") unless build_count == 1
      abort("expected one resolver identity") unless resolvers.map(&:object_id).uniq.one?
    RUBY

    assert_isolated_script_success(script)
  end

  def test_default_resolver_snapshots_environment_and_home_on_first_access
    Dir.mktmpdir do |initial_home|
      configured_home = File.join(initial_home, "configured-home")
      later_home = File.join(initial_home, "later-home")
      script = <<~RUBY
        require "agent_homedir"

        ENV["HOME"] = #{configured_home.inspect}
        ENV["CODEX_HOME"] = "post-require/codex"

        first_resolver = Agent::Homedir.default_resolver
        first_home = Agent::Homedir.home(:codex).to_s

        abort("expected first HOME snapshot") unless first_home == #{File.join(configured_home, "post-require/codex").inspect}

        ENV["HOME"] = #{later_home.inspect}
        ENV["CODEX_HOME"] = "changed-after-first-access/codex"

        second_resolver = Agent::Homedir.default_resolver
        second_home = Agent::Homedir.home(:codex).to_s

        abort("expected memoized resolver identity") unless first_resolver.equal?(second_resolver)
        abort("expected same path after ENV mutation") unless second_home == first_home
      RUBY

      assert_isolated_script_success(
        script,
        env: {
          "HOME" => initial_home,
          "CODEX_HOME" => "pre-require/codex"
        }
      )
    end
  end

  def test_home_installed_and_fetch_delegate_to_default_resolver
    agent = Agent::Homedir::Entry.new(
      name: :codex,
      label: "Codex",
      env_override: "CODEX_HOME",
      verified_on: nil,
      resolver: nil_resolver
    )
    resolver = DelegatingResolver.new(
      home: Pathname("/tmp/codex-home"),
      installed: true,
      agent:
    )

    with_default_resolver(resolver) do
      assert_equal Pathname("/tmp/codex-home"), Agent::Homedir.home("codex")
      assert_equal true, Agent::Homedir.installed?(:codex)
      assert_same agent, Agent::Homedir["codex"]
    end

    assert_equal [:codex], resolver.home_calls
    assert_equal [:codex], resolver.installed_calls
    assert_equal [:codex], resolver.fetch_calls
  end

  def test_collection_helpers_delegate_to_default_resolver_with_live_installed_results
    Dir.mktmpdir do |dir|
      alpha_dir = File.join(dir, ".alpha")
      gamma_dir = File.join(dir, ".gamma")
      FileUtils.mkdir_p(gamma_dir)

      resolver = Agent::Homedir::Resolver.new(
        env: {},
        home: dir,
        os: :linux,
        entries: {
          beta: entry(label: "Beta", paths: [File.join(dir, ".beta")]),
          alpha: entry(label: "Alpha", paths: [alpha_dir]),
          gamma: entry(label: "Gamma", paths: [gamma_dir])
        }
      )

      with_default_resolver(resolver) do
        assert_equal %i[beta alpha gamma], Agent::Homedir.names
        assert_predicate Agent::Homedir.names, :frozen?
        assert_same resolver.names, Agent::Homedir.names

        assert_equal %i[beta alpha gamma], Agent::Homedir.agents.map(&:name)
        assert_predicate Agent::Homedir.agents, :frozen?
        assert_same resolver.agents, Agent::Homedir.agents

        first_installed = Agent::Homedir.installed
        assert_equal %i[gamma], first_installed.map(&:name)
        assert_predicate first_installed, :frozen?
        assert_same resolver.agents[2], first_installed.first

        FileUtils.mkdir_p(alpha_dir)

        second_installed = Agent::Homedir.installed
        assert_equal %i[alpha gamma], second_installed.map(&:name)
        assert_predicate second_installed, :frozen?
        assert_same resolver.agents[1], second_installed[0]
        assert_same resolver.agents[2], second_installed[1]
        refute_same first_installed, second_installed
      end
    end
  end

  def test_fetch_raises_unknown_agent_with_valid_names
    resolver = Agent::Homedir::Resolver.new(
      env: {},
      home: "/tmp/home",
      os: :linux,
      entries: {
        alpha: entry(label: "Alpha", paths: ["/tmp/home/.alpha"]),
        beta: entry(label: "Beta", paths: ["/tmp/home/.beta"])
      }
    )

    error = with_default_resolver(resolver) do
      assert_raises(Agent::Homedir::UnknownAgent) { Agent::Homedir[:gamma] }
    end

    assert_includes error.message, "gamma"
    assert_includes error.message, "alpha"
    assert_includes error.message, "beta"
  end

  def test_readme_documents_default_resolver_environment_snapshot_behavior
    readme = File.read(File.expand_path("../README.md", __dir__))

    assert_includes readme, "snapshotted on first access"
    assert_includes readme, "instantiate `Agent::Homedir::Resolver`"
  end

  def test_readme_lists_every_supported_agent
    readme = File.read(File.expand_path("../README.md", __dir__))

    Agent::Homedir.agents.each do |agent|
      assert_includes readme, "| #{agent.label} | `:#{agent.name}` |"
    end
  end

  private

  def entry(label:, paths:)
    {
      label:,
      env: nil,
      paths:,
      verified_on: nil
    }
  end

  def nil_resolver
    @nil_resolver ||= Object.new.tap do |resolver|
      def resolver.home(*) = nil
      def resolver.installed?(*) = false
      def resolver.candidates(*) = [].freeze
    end
  end

  def with_default_resolver(resolver)
    had_original = Agent::Homedir.instance_variable_defined?(:@default_resolver)
    original_resolver = Agent::Homedir.instance_variable_get(:@default_resolver)

    Agent::Homedir.instance_variable_set(:@default_resolver, resolver)
    yield
  ensure
    if had_original
      Agent::Homedir.instance_variable_set(:@default_resolver, original_resolver)
    else
      Agent::Homedir.remove_instance_variable(:@default_resolver)
    end
  end

  def assert_isolated_script_success(script, env: {})
    stdout, stderr, status = Open3.capture3(
      env,
      RbConfig.ruby,
      "-I#{File.expand_path("../lib", __dir__)}",
      "-e",
      script
    )

    assert status.success?, "expected isolated script to succeed, stderr: #{stderr.inspect}, stdout: #{stdout.inspect}"
  end

  class DelegatingResolver
    attr_reader :fetch_calls, :home_calls, :installed_calls

    def initialize(home:, installed:, agent:)
      @home_value = home
      @installed_value = installed
      @agent_value = agent
      @home_calls = []
      @installed_calls = []
      @fetch_calls = []
    end

    def home(name)
      @home_calls << name.to_sym
      @home_value
    end

    def installed?(name)
      @installed_calls << name.to_sym
      @installed_value
    end

    def [](name)
      @fetch_calls << name.to_sym
      @agent_value
    end
  end
end
