# frozen_string_literal: true

require "test_helper"
require "date"
require "fileutils"
require "pathname"
require "tmpdir"

class AgentTest < Minitest::Test
  def test_with_without_changes_returns_self
    agent = build_resolver(entries: {codex: entry(paths: ["~/.codex"])} )[:codex]

    assert_same agent, agent.with
  end

  def test_with_preserves_resolver_context_and_returns_changed_copy
    Dir.mktmpdir do |dir|
      override = File.join(dir, "custom", "codex")
      FileUtils.mkdir_p(override)

      resolver = build_resolver(
        home: dir,
        env: {"CODEX_HOME" => "custom/codex"},
        entries: {
          codex: entry(label: "Codex", env: "CODEX_HOME", paths: ["~/.codex"], verified_on: "2026-08-20")
        }
      )

      agent = resolver[:codex]
      changed = agent.with(label: "Codex CLI")

      assert_equal "Codex", agent.label
      assert_equal "Codex CLI", changed.label
      assert_equal Pathname(override), changed.home
      assert changed.installed?
      assert_equal [Pathname(File.join(dir, ".codex"))], changed.candidates
    end
  end

  def test_with_returns_self_when_allowed_changes_do_not_change_any_facts
    agent = build_resolver(
      entries: {
        codex: entry(label: "Codex", env: "CODEX_HOME", paths: ["~/.codex"], verified_on: "2026-08-20")
      }
    )[:codex]

    assert_same agent, agent.with(label: "Codex", verified_on: Date.new(2026, 8, 20))
  end

  def test_with_returns_self_when_resolver_bound_facts_are_unchanged
    agent = build_resolver(
      entries: {
        codex: entry(label: "Codex", env: "CODEX_HOME", paths: ["~/.codex"], verified_on: "2026-08-20")
      }
    )[:codex]

    assert_same agent, agent.with(name: :codex, env_override: "CODEX_HOME")
  end

  def test_with_allows_verified_on_changes
    agent = build_resolver(
      entries: {
        codex: entry(label: "Codex", env: "CODEX_HOME", paths: ["~/.codex"], verified_on: "2026-08-20")
      }
    )[:codex]

    changed = agent.with(verified_on: Date.new(2026, 8, 21))

    assert_equal Date.new(2026, 8, 20), agent.verified_on
    assert_equal Date.new(2026, 8, 21), changed.verified_on
  end

  def test_with_rejects_resolver_bound_name_and_env_override_changes
    agent = build_resolver(
      entries: {
        codex: entry(label: "Codex", env: "CODEX_HOME", paths: ["~/.codex"], verified_on: "2026-08-20")
      }
    )[:codex]

    {
      name: :claude_code,
      env_override: "CLAUDE_CONFIG_DIR"
    }.each do |field, value|
      error = assert_raises(ArgumentError) { agent.with(field => value) }

      assert_includes error.message, field.to_s
      assert_includes error.message, "resolver-bound"
    end
  end

  def test_with_rejects_unknown_members_clearly
    agent = build_resolver(entries: {codex: entry(paths: ["~/.codex"])} )[:codex]

    error = assert_raises(ArgumentError) do
      agent.with(resolver: Object.new)
    end

    assert_includes error.message, "resolver"
    assert_includes error.message, "Unknown member"
  end

  def test_resolver_fetches_immutable_agent_value_with_documented_members
    label = String.new("Codex")
    env_key = String.new("CODEX_HOME")

    resolver = build_resolver(
      entries: {
        codex: entry(label:, env: env_key, paths: ["~/.codex"], verified_on: "2026-08-20")
      }
    )

    agent = resolver[:codex]

    assert_equal %i[name label env_override verified_on], AgentsHomedir::Agent.members
    assert_instance_of AgentsHomedir::Agent, agent
    assert_equal :codex, agent.name
    assert_equal "Codex", agent.label
    assert_equal "CODEX_HOME", agent.env_override
    assert_equal Date.new(2026, 8, 20), agent.verified_on
    assert_predicate agent, :frozen?
    assert_predicate agent.label, :frozen?
    assert_predicate agent.env_override, :frozen?
  end

  def test_agent_equality_and_hash_are_based_on_public_facts_only
    first = build_resolver(
      home: "/first/home",
      entries: {
        codex: entry(label: "Codex", env: "CODEX_HOME", paths: ["~/.codex"], verified_on: "2026-08-20")
      }
    )[:codex]
    second = build_resolver(
      home: "/second/home",
      entries: {
        codex: entry(label: "Codex", env: "CODEX_HOME", paths: ["~/.codex"], verified_on: "2026-08-20")
      }
    )[:codex]

    assert_equal first, second
    assert_equal first.hash, second.hash
  end

  def test_agent_supports_nil_metadata
    resolver = build_resolver(
      entries: {
        claude: entry(label: "Claude", env: nil, paths: ["~/.claude"], verified_on: nil)
      }
    )

    agent = resolver[:claude]

    assert_nil agent.env_override
    assert_nil agent.verified_on
  end

  def test_agent_delegates_home_installed_and_candidates_to_resolver
    Dir.mktmpdir do |dir|
      override = File.join(dir, "custom", "codex")
      FileUtils.mkdir_p(override)

      resolver = build_resolver(
        home: dir,
        env: {"CODEX_HOME" => "custom/codex"},
        entries: {
          codex: entry(label: "Codex", env: "CODEX_HOME", paths: ["~/.codex"], verified_on: nil)
        }
      )

      agent = resolver[:codex]

      assert_equal Pathname(override), agent.home
      assert agent.installed?
      assert_equal [Pathname(File.join(dir, ".codex"))], agent.candidates
      assert_predicate agent.candidates, :frozen?
    end
  end

  def test_agent_does_not_expose_its_resolver
    agent = build_resolver(entries: {codex: entry(paths: ["~/.codex"])} )[:codex]

    refute_respond_to agent, :resolver
    refute_includes AgentsHomedir::Agent.members, :resolver
  end

  def test_invalid_verified_on_fails_clearly
    resolver = build_resolver(
      entries: {
        codex: entry(label: "Codex", env: "CODEX_HOME", paths: ["~/.codex"], verified_on: "2026-02-30")
      }
    )

    error = assert_raises(ArgumentError) { resolver[:codex] }

    assert_includes error.message, "verified_on"
    assert_includes error.message, "2026-02-30"
  end

  def test_direct_construction_validates_documented_fact_types
    error = assert_raises(ArgumentError) do
      AgentsHomedir::Agent.new(
        name: "codex",
        label: "Codex",
        env_override: "CODEX_HOME",
        verified_on: Date.new(2026, 8, 20),
        resolver: Object.new
      )
    end
    assert_includes error.message, "name"
    assert_includes error.message, "Symbol"

    error = assert_raises(ArgumentError) do
      AgentsHomedir::Agent.new(
        name: :codex,
        label: :codex,
        env_override: "CODEX_HOME",
        verified_on: Date.new(2026, 8, 20),
        resolver: Object.new
      )
    end
    assert_includes error.message, "label"
    assert_includes error.message, "String"

    error = assert_raises(ArgumentError) do
      AgentsHomedir::Agent.new(
        name: :codex,
        label: "Codex",
        env_override: :codex_home,
        verified_on: Date.new(2026, 8, 20),
        resolver: Object.new
      )
    end
    assert_includes error.message, "env_override"
    assert_includes error.message, "String or nil"

    error = assert_raises(ArgumentError) do
      AgentsHomedir::Agent.new(
        name: :codex,
        label: "Codex",
        env_override: "CODEX_HOME",
        verified_on: "2026-08-20",
        resolver: Object.new
      )
    end
    assert_includes error.message, "verified_on"
    assert_includes error.message, "Date or nil"
  end

  def test_agent_facts_are_isolated_from_source_string_mutation
    label = String.new("Codex")
    env_key = String.new("CODEX_HOME")
    verified_on = String.new("2026-08-20")
    entry = entry(label:, env: env_key, paths: ["~/.codex"], verified_on:)
    resolver = build_resolver(entries: {codex: entry})

    label.replace("Mutated")
    env_key.replace("MUTATED_HOME")
    verified_on.replace("1999-01-01")

    agent = resolver[:codex]

    assert_equal "Codex", agent.label
    assert_equal "CODEX_HOME", agent.env_override
    assert_equal Date.new(2026, 8, 20), agent.verified_on
  end

  private

  def build_resolver(env: {}, home: "/home/test", os: :linux, entries: {})
    AgentsHomedir::Resolver.new(env:, home:, os:, entries:)
  end

  def entry(label: "Agent", env: nil, paths:, verified_on: nil)
    {
      label:,
      env:,
      paths:,
      verified_on:
    }
  end
end
