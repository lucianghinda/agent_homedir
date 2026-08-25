# frozen_string_literal: true

require "test_helper"
require "date"
require "fileutils"
require "open3"
require "pathname"
require "rbconfig"
require "timeout"
require "tmpdir"

class ResolverTest < Minitest::Test
  def test_fetch_returns_agent_value
    resolver = build_resolver(
      entries: {
        codex: entry(label: "Codex", env: "CODEX_HOME", paths: ["~/.codex"], verified_on: "2026-08-20")
      }
    )

    agent = resolver[:codex]

    assert_instance_of Agent::Homedir::Entry, agent
    assert_equal :codex, agent.name
    assert_equal "Codex", agent.label
    assert_equal "CODEX_HOME", agent.env_override
    assert_equal Date.new(2026, 8, 20), agent.verified_on
  end

  def test_names_and_agents_are_frozen_registry_ordered_and_memoized
    resolver = build_resolver(
      entries: {
        beta: entry(label: "Beta", paths: ["~/.beta"], verified_on: nil),
        alpha: entry(label: "Alpha", paths: ["~/.alpha"], verified_on: nil)
      }
    )

    assert_equal %i[beta alpha], resolver.names
    assert_predicate resolver.names, :frozen?
    assert_same resolver.names, resolver.names

    agents = resolver.agents
    assert_equal %i[beta alpha], agents.map(&:name)
    assert_predicate agents, :frozen?
    assert_same agents, resolver.agents
  end

  def test_installed_filters_existing_agents_in_order_without_memoizing
    Dir.mktmpdir do |dir|
      alpha_dir = File.join(dir, ".alpha")
      beta_dir = File.join(dir, ".beta")
      gamma_dir = File.join(dir, ".gamma")
      FileUtils.mkdir_p(beta_dir)

      resolver = build_resolver(
        home: dir,
        entries: {
          alpha: entry(label: "Alpha", paths: [alpha_dir], verified_on: nil),
          beta: entry(label: "Beta", paths: [beta_dir], verified_on: nil),
          gamma: entry(label: "Gamma", paths: [gamma_dir], verified_on: nil)
        }
      )

      first_installed = resolver.installed
      assert_equal %i[beta], first_installed.map(&:name)
      assert_predicate first_installed, :frozen?
      assert_same resolver.agents[1], first_installed.first

      FileUtils.mkdir_p(alpha_dir)
      FileUtils.mkdir_p(gamma_dir)

      second_installed = resolver.installed
      assert_equal %i[alpha beta gamma], second_installed.map(&:name)
      assert_predicate second_installed, :frozen?
      assert_same resolver.agents[0], second_installed[0]
      assert_same resolver.agents[1], second_installed[1]
      assert_same resolver.agents[2], second_installed[2]
      refute_same first_installed, second_installed
    end
  end

  def test_agents_first_initialization_is_identity_stable_across_parallel_callers
    resolver = ConcurrentAgentsResolver.new(
      fetch_started: Queue.new,
      fetch_release: Queue.new,
      env: {},
      home: "/home/test",
      os: :linux,
      entries: {
        alpha: entry(label: "Alpha", paths: ["~/.alpha"], verified_on: nil),
        beta: entry(label: "Beta", paths: ["~/.beta"], verified_on: nil)
      }
    )

    ready = Queue.new
    release = Queue.new
    results = Queue.new

    threads = 2.times.map do
      Thread.new do
        ready << true
        release.pop
        results << resolver.agents
      end
    end

    Timeout.timeout(1) { 2.times { ready.pop } }
    2.times { release << true }

    Timeout.timeout(1) { resolver.fetch_started.pop }

    assert_raises(Timeout::Error) do
      Timeout.timeout(0.2) { resolver.fetch_started.pop }
    end

    resolver.fetch_release << true

    Timeout.timeout(1) do
      threads.each do |thread|
        assert thread.join(1), "thread join timed out"
      end
    end

    arrays = 2.times.map { results.pop }
    assert arrays.all?(&:frozen?)
    assert_equal 1, arrays.map(&:object_id).uniq.size

    first_agent_ids = arrays.first.map(&:object_id)
    arrays.each do |agents|
      assert_equal first_agent_ids, agents.map(&:object_id)
    end
  end

  def test_fetch_rejects_malformed_metadata_types
    resolver = build_resolver(
      entries: {
        codex: entry(label: :codex, env: ["CODEX_HOME"], paths: ["~/.codex"], verified_on: nil)
      }
    )

    error = assert_raises(ArgumentError) { resolver[:codex] }

    assert_includes error.message, "label"
  end

  def test_fetch_rejects_every_nonnil_nonstring_verified_on_with_contextual_error
    [Date.new(2026, 8, 20), 12_345, [:not, :a, :string], {iso: "2026-08-20"}].each do |value|
      resolver = build_resolver(
        entries: {
          codex: entry(label: "Codex", env: "CODEX_HOME", paths: ["~/.codex"], verified_on: value)
        }
      )

      error = assert_raises(ArgumentError) { resolver[:codex] }

      assert_includes error.message, "verified_on"
      assert_includes error.message, "codex"
      assert_includes error.message, value.inspect
    end
  end

  def test_default_entries_come_from_registry_when_not_injected
    resolver = Agent::Homedir::Resolver.new(env: {}, home: "/home/test", os: :linux)

    assert_equal Pathname("/home/test/.codex"), resolver.home(:codex)
    assert_equal "Codex CLI", resolver[:codex].label
  end

  def test_expands_top_level_os_selector_hash_without_turning_it_into_key_value_pairs
    resolver = build_resolver(
      entries: {
        codex: entry(
          paths: {
            macos: "~/Library/Application Support/Codex",
            linux: ["~/.codex", {xdg: :config, path: "codex"}],
            windows: {windows_env: "APPDATA", path: "Codex"}
          }
        )
      }
    )

    assert_equal [
      Pathname("/home/test/.codex"),
      Pathname("/home/test/.config/codex")
    ], resolver.candidates(:codex)
  end

  def test_resolver_file_is_independently_requireable
    script = <<~RUBY
      require "agent/homedir/resolver"

      resolver = Agent::Homedir::Resolver.new(
        env: {},
        home: "/home/test",
        os: :linux,
        entries: {
          x: {
            label: "Agent X",
            env: nil,
            paths: ["~/.x"],
            verified_on: "2026-08-20"
          }
        }
      )

      agent = resolver[:x]
      abort("wrong class") unless agent.class == Agent::Homedir::Entry
      abort("wrong label") unless agent.label == "Agent X"
      abort("wrong date") unless agent.verified_on == Date.new(2026, 8, 20)
    RUBY

    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      "-I#{File.expand_path("../lib", __dir__)}",
      "-e",
      script
    )

    assert status.success?, "expected isolated require to succeed, stderr: #{stderr.inspect}, stdout: #{stdout.inspect}"
  end

  def test_home_prefers_relative_env_override_expanded_against_home
    resolver = build_resolver(
      env: {"CODEX_HOME" => "custom/codex"},
      entries: {codex: entry(env: "CODEX_HOME", paths: ["~/.codex"])}
    )

    assert_equal Pathname("/home/test/custom/codex"), resolver.home(:codex)
  end

  def test_home_ignores_blank_env_override
    resolver = build_resolver(
      env: {"CODEX_HOME" => "   "},
      entries: {codex: entry(env: "CODEX_HOME", paths: ["~/.codex"])}
    )

    assert_equal Pathname("/home/test/.codex"), resolver.home(:codex)
  end

  def test_home_prefers_absolute_env_override_even_when_missing
    resolver = Agent::Homedir::Resolver.new(
      env: {"CODEX_HOME" => "/tmp/missing-codex-home"},
      home: "/home/test",
      os: :linux,
      entries: {
        codex: {
          label: "Codex",
          env: "CODEX_HOME",
          paths: ["~/.codex"],
          verified_on: %i[linux]
        }
      }
    )

    assert_equal Pathname("/tmp/missing-codex-home"), resolver.home(:codex)
  end

  def test_home_preserves_nonblank_override_whitespace
    resolver = build_resolver(
      env: {"CODEX_HOME" => " custom/codex "},
      entries: {codex: entry(env: "CODEX_HOME", paths: ["~/.codex"])}
    )

    assert_equal Pathname("/home/test/ custom/codex "), resolver.home(:codex)
  end

  def test_candidates_expand_tilde_paths
    resolver = build_resolver(
      entries: {codex: entry(paths: ["~/.codex", "~/Library/Application Support/Codex"])}
    )

    assert_equal [
      Pathname("/home/test/.codex"),
      Pathname("/home/test/Library/Application Support/Codex")
    ], resolver.candidates(:codex)
    assert_predicate resolver.candidates(:codex), :frozen?
  end

  def test_candidates_expand_literal_tilde_to_home
    resolver = build_resolver(entries: {codex: entry(paths: ["~"])})

    assert_equal [Pathname("/home/test")], resolver.candidates(:codex)
    assert_equal Pathname("/home/test"), resolver.home(:codex)
  end

  def test_candidates_expand_xdg_config_and_data_with_env_and_fallbacks
    resolver_with_env = build_resolver(
      env: {
        "XDG_CONFIG_HOME" => "/xdg/config",
        "XDG_DATA_HOME" => "/xdg/data"
      },
      entries: {
        helper: entry(
          paths: [
            {xdg: :config, path: "helper"},
            {xdg: :data, path: "helper/data"}
          ]
        )
      }
    )

    assert_equal [
      Pathname("/xdg/config/helper"),
      Pathname("/xdg/data/helper/data")
    ], resolver_with_env.candidates(:helper)

    resolver_with_fallbacks = build_resolver(
      entries: {
        helper: entry(
          paths: [
            {xdg: :config, path: "helper"},
            {xdg: :data, path: "helper/data"}
          ]
        )
      }
    )

    assert_equal [
      Pathname("/home/test/.config/helper"),
      Pathname("/home/test/.local/share/helper/data")
    ], resolver_with_fallbacks.candidates(:helper)
  end

  def test_posix_xdg_base_env_values_ignore_relative_and_tilde_forms_and_fall_back_to_home_defaults
    {
      linux: "/home/test",
      macos: "/Users/Test"
    }.each do |os, home|
      {
        "relative/path" => [
          Pathname("#{home}/.config/helper"),
          Pathname("#{home}/.local/share/helper/data")
        ],
        "~/.portable" => [
          Pathname("#{home}/.config/helper"),
          Pathname("#{home}/.local/share/helper/data")
        ]
      }.each do |invalid_value, expected_candidates|
        resolver = build_resolver(
          os:,
          home:,
          env: {
            "XDG_CONFIG_HOME" => invalid_value,
            "XDG_DATA_HOME" => invalid_value
          },
          entries: {
            helper: entry(
              paths: [
                {xdg: :config, path: "helper"},
                {xdg: :data, path: "helper/data"}
              ]
            )
          }
        )

        assert_equal expected_candidates, resolver.candidates(:helper), "expected #{os.inspect} to ignore #{invalid_value.inspect}"
      end
    end
  end

  def test_candidates_preserve_posix_root_when_expanding_tilde_and_xdg_paths
    ["/", "//", "///"].each do |root|
      tilde_resolver = build_resolver(
        home: root,
        entries: {codex: entry(paths: ["~/.codex"])}
      )

      assert_equal [Pathname("/.codex")], tilde_resolver.candidates(:codex)

      xdg_resolver = build_resolver(
        home: root,
        env: {"XDG_CONFIG_HOME" => root},
        entries: {helper: entry(paths: [{xdg: :config, path: "helper"}])}
      )

      assert_equal [Pathname("/helper")], xdg_resolver.candidates(:helper)
    end
  end

  def test_candidates_choose_current_os_specs_and_preserve_order
    resolver = build_resolver(
      entries: {
        codex: entry(
          paths: [
            {macos: "~/Library/Application Support/Codex"},
            {linux: ["~/.codex", {xdg: :config, path: "codex"}]},
            "/opt/codex"
          ]
        )
      }
    )

    assert_equal [
      Pathname("/home/test/.codex"),
      Pathname("/home/test/.config/codex"),
      Pathname("/opt/codex")
    ], resolver.candidates(:codex)
  end

  def test_home_prefers_first_existing_candidate
    Dir.mktmpdir do |dir|
      file_candidate = File.join(dir, "not-a-directory")
      second = File.join(dir, "installed")
      File.write(file_candidate, "resolver")
      FileUtils.mkdir_p(second)

      resolver = build_resolver(
        home: dir,
        entries: {codex: entry(paths: [file_candidate, second])}
      )

      assert_equal Pathname(second), resolver.home(:codex)
    end
  end

  def test_home_falls_back_to_first_candidate_when_none_exist
    Dir.mktmpdir do |dir|
      first = File.join(dir, "missing-first")
      second = File.join(dir, "missing-second")

      resolver = build_resolver(
        home: dir,
        entries: {codex: entry(paths: [first, second])}
      )

      assert_equal Pathname(first), resolver.home(:codex)
    end
  end

  def test_installed_recognizes_existing_override_and_candidate
    Dir.mktmpdir do |dir|
      override = File.join(dir, "override")
      candidate = File.join(dir, "candidate")
      FileUtils.mkdir_p(override)
      FileUtils.mkdir_p(candidate)

      override_resolver = build_resolver(
        home: dir,
        env: {"CODEX_HOME" => override},
        entries: {codex: entry(env: "CODEX_HOME", paths: ["~/.codex"])}
      )

      candidate_resolver = build_resolver(
        home: dir,
        entries: {codex: entry(paths: [File.join(dir, "missing"), candidate])}
      )

      refute build_resolver(entries: {codex: entry(paths: ["~/.codex"])}).installed?(:codex)
      assert override_resolver.installed?(:codex)
      assert candidate_resolver.installed?(:codex)
    end
  end

  def test_home_returns_nonblank_override_even_when_it_names_existing_file
    Dir.mktmpdir do |dir|
      override = File.join(dir, "override-file")
      File.write(override, "resolver")

      resolver = build_resolver(
        home: dir,
        env: {"CODEX_HOME" => override},
        entries: {codex: entry(env: "CODEX_HOME", paths: [File.join(dir, "missing-candidate")])}
      )

      assert_equal Pathname(override), resolver.home(:codex)
      refute resolver.installed?(:codex)
    end
  end

  def test_installed_checks_candidates_when_override_is_missing
    Dir.mktmpdir do |dir|
      override = File.join(dir, "missing-override")
      candidate = File.join(dir, "candidate")
      FileUtils.mkdir_p(candidate)

      resolver = build_resolver(
        home: dir,
        env: {"CODEX_HOME" => override},
        entries: {codex: entry(env: "CODEX_HOME", paths: [File.join(dir, "missing"), candidate])}
      )

      assert resolver.installed?(:codex)
    end
  end

  def test_home_falls_back_to_first_candidate_when_first_is_a_file_and_no_directory_exists
    Dir.mktmpdir do |dir|
      first = File.join(dir, "first-file")
      second = File.join(dir, "missing-second")
      File.write(first, "resolver")

      resolver = build_resolver(
        home: dir,
        entries: {codex: entry(paths: [first, second])}
      )

      assert_equal Pathname(first), resolver.home(:codex)
    end
  end

  def test_installed_ignores_files_and_counts_directory_symlinks
    Dir.mktmpdir do |dir|
      override = File.join(dir, "override-file")
      target = File.join(dir, "target-dir")
      symlink = File.join(dir, "symlink-dir")
      file_candidate = File.join(dir, "candidate-file")
      File.write(override, "resolver")
      FileUtils.mkdir_p(target)
      File.symlink(target, symlink)
      File.write(file_candidate, "resolver")

      resolver = build_resolver(
        home: dir,
        env: {"CODEX_HOME" => override},
        entries: {codex: entry(env: "CODEX_HOME", paths: [file_candidate, symlink])}
      )

      assert resolver.installed?(:codex)
    rescue *symlink_unavailable_errors => error
      skip "symlink creation unavailable on this platform: #{error.class}"
    end
  end

  def test_home_expands_relative_override_against_posix_root
    resolver = build_resolver(
      home: "/",
      env: {"CODEX_HOME" => "custom/codex"},
      entries: {codex: entry(env: "CODEX_HOME", paths: ["~/.codex"])}
    )

    assert_equal Pathname("/custom/codex"), resolver.home(:codex)
  end

  def test_candidates_raise_when_paths_are_missing_for_current_os
    {
      nil => "nil",
      [] => "empty",
      [{macos: "~/Library/Application Support/Codex"}] => "current os"
    }.each do |paths, detail|
      resolver = build_resolver(entries: {codex: entry(paths:)})

      error = assert_raises(ArgumentError) { resolver.candidates(:codex) }

      assert_includes error.message, "codex"
      assert_includes error.message, "linux"
      assert_includes error.message, detail
    end
  end

  def test_initialize_snapshots_mutable_inputs
    env = {"CODEX_HOME" => "custom/codex"}
    home = String.new("/home/test")
    entries = {
      codex: entry(env: "CODEX_HOME", paths: ["~/.codex"])
    }

    resolver = build_resolver(env:, home:, entries:)

    env["CODEX_HOME"] = "mutated"
    home.replace("/mutated/home")
    entries[:codex][:env] = "CLAUDE_HOME"
    entries[:codex][:paths] << "/mutated/path"

    assert_equal Pathname("/home/test/custom/codex"), resolver.home(:codex)
    assert_equal [Pathname("/home/test/.codex")], resolver.candidates(:codex)
  end

  def test_xdg_and_windows_child_paths_must_be_relative
    xdg_resolver = build_resolver(
      entries: {helper: entry(paths: [{xdg: :config, path: "/helper"}])}
    )

    xdg_error = assert_raises(ArgumentError) { xdg_resolver.candidates(:helper) }
    assert_includes xdg_error.message, "relative"

    windows_resolver = build_resolver(
      os: :windows,
      home: "C:/Users/Test",
      env: {"APPDATA" => "C:/Users/Test/AppData/Roaming"},
      entries: {codex: entry(paths: [{windows_env: "APPDATA", path: "C:/Codex"}])}
    )

    windows_error = assert_raises(ArgumentError) { windows_resolver.candidates(:codex) }
    assert_includes windows_error.message, "relative"
  end

  def test_windows_env_overrides_reject_root_relative_and_drive_relative_values
    ["/foo", "\\foo", "C:foo"].each do |override|
      resolver = build_resolver(
        os: :windows,
        home: "C:/Users/Test",
        env: {"CODEX_HOME" => override},
        entries: {codex: entry(env: "CODEX_HOME", paths: ["C:/Users/Test/.codex"])}
      )

      error = assert_raises(ArgumentError) { resolver.home(:codex) }
      assert_includes error.message, "relative"
    end
  end

  def test_windows_xdg_and_windows_env_child_paths_reject_root_relative_and_drive_relative_values
    ["/foo", "\\foo", "C:foo"].each do |child_path|
      xdg_resolver = build_resolver(
        os: :windows,
        home: "C:/Users/Test",
        env: {"XDG_CONFIG_HOME" => "C:/Users/Test/.config"},
        entries: {helper: entry(paths: [{xdg: :config, path: child_path}])}
      )

      xdg_error = assert_raises(ArgumentError) { xdg_resolver.candidates(:helper) }
      assert_includes xdg_error.message, "relative"

      windows_resolver = build_resolver(
        os: :windows,
        home: "C:/Users/Test",
        env: {"APPDATA" => "C:/Users/Test/AppData/Roaming"},
        entries: {codex: entry(paths: [{windows_env: "APPDATA", path: child_path}])}
      )

      windows_error = assert_raises(ArgumentError) { windows_resolver.candidates(:codex) }
      assert_includes windows_error.message, "relative"
    end
  end

  def test_unknown_agent_lists_valid_names
    resolver = build_resolver(
      entries: {
        claude: entry(paths: ["~/.claude"]),
        codex: entry(paths: ["~/.codex"])
      }
    )

    error = assert_raises(Agent::Homedir::UnknownAgent) do
      resolver.home(:cursor)
    end

    assert_includes error.message, "cursor"
    assert_includes error.message, "claude"
    assert_includes error.message, "codex"
  end

  def test_nil_or_blank_home_raises_for_all_path_queries
    [nil, "", "   "].each do |home|
      resolver = build_resolver(
        home: home,
        env: {"CODEX_HOME" => "/absolute/override"},
        entries: {codex: entry(env: "CODEX_HOME", paths: ["~/.codex"])}
      )

      assert_raises(Agent::Homedir::HomeNotResolvable) { resolver.home(:codex) }
      assert_raises(Agent::Homedir::HomeNotResolvable) { resolver.candidates(:codex) }
      assert_raises(Agent::Homedir::HomeNotResolvable) { resolver.installed?(:codex) }
    end
  end

  def test_invalid_os_is_rejected
    error = assert_raises(ArgumentError) do
      build_resolver(os: :plan9)
    end

    assert_includes error.message, "plan9"
  end

  def test_detect_os_supports_windows_without_accepting_cygwin
    assert_equal :macos, Agent::Homedir::Resolver.send(:detect_os, "darwin23.5.0")
    assert_equal :linux, Agent::Homedir::Resolver.send(:detect_os, "linux-gnu")
    assert_equal :windows, Agent::Homedir::Resolver.send(:detect_os, "mswin")
    assert_equal :windows, Agent::Homedir::Resolver.send(:detect_os, "mingw")

    error = assert_raises(ArgumentError) do
      Agent::Homedir::Resolver.send(:detect_os, "x86_64-pc-cygwin")
    end

    assert_includes error.message, "cygwin"
  end

  def test_windows_candidates_expand_appdata_and_localappdata_and_keep_absolute_paths
    resolver = build_resolver(
      os: :windows,
      home: "C:/Users/Test",
      env: {
        "APPDATA" => "C:\\Users\\Test\\AppData\\Roaming",
        "LOCALAPPDATA" => "\\\\server\\share\\LocalAppData"
      },
      entries: {
        codex: entry(
          paths: [
            {windows_env: "APPDATA", path: "Codex"},
            {windows_env: "LOCALAPPDATA", path: "Codex/Cache"}
          ]
        )
      }
    )

    assert_equal [
      Pathname("C:/Users/Test/AppData/Roaming/Codex"),
      Pathname("//server/share/LocalAppData/Codex/Cache")
    ], resolver.candidates(:codex)
  end

  def test_windows_opencode_candidates_use_localappdata_when_appdata_and_xdg_data_home_are_missing
    resolver = Agent::Homedir::Resolver.new(
      env: {
        "LOCALAPPDATA" => "D:/Profiles/Test/Local"
      },
      home: "C:/Users/Test",
      os: :windows
    )

    assert_equal [
      Pathname("C:/Users/Test/AppData/Roaming/opencode"),
      Pathname("D:/Profiles/Test/Local/opencode"),
      Pathname("C:/Users/Test/.local/share/opencode")
    ], resolver.candidates(:opencode)
  end

  def test_windows_opencode_candidates_use_optional_xdg_data_home_before_profile_defaults
    resolver = Agent::Homedir::Resolver.new(
      env: {
        "XDG_DATA_HOME" => "D:/Portable/Data"
      },
      home: "C:/Users/Test",
      os: :windows
    )

    assert_equal [
      Pathname("D:/Portable/Data/opencode"),
      Pathname("C:/Users/Test/AppData/Roaming/opencode"),
      Pathname("C:/Users/Test/AppData/Local/opencode"),
      Pathname("C:/Users/Test/.local/share/opencode")
    ], resolver.candidates(:opencode)
  end

  def test_windows_opencode_candidates_skip_optional_xdg_data_home_when_not_absolute
    ["portable/data", "~/.portable/data"].each do |invalid_value|
      resolver = Agent::Homedir::Resolver.new(
        env: {
          "XDG_DATA_HOME" => invalid_value,
          "APPDATA" => "C:/Users/Test/AppData/Roaming",
          "LOCALAPPDATA" => "D:/Profiles/Test/Local"
        },
        home: "C:/Users/Test",
        os: :windows
      )

      assert_equal [
        Pathname("C:/Users/Test/AppData/Roaming/opencode"),
        Pathname("D:/Profiles/Test/Local/opencode"),
        Pathname("C:/Users/Test/.local/share/opencode")
      ], resolver.candidates(:opencode), "expected windows resolver to skip #{invalid_value.inspect}"
    end
  end

  def test_windows_opencode_candidates_derive_profile_defaults_when_known_env_bases_are_missing
    resolver = Agent::Homedir::Resolver.new(
      env: {},
      home: "C:/Users/Test",
      os: :windows
    )

    assert_equal [
      Pathname("C:/Users/Test/AppData/Roaming/opencode"),
      Pathname("C:/Users/Test/AppData/Local/opencode"),
      Pathname("C:/Users/Test/.local/share/opencode")
    ], resolver.candidates(:opencode)
  end

  def test_windows_cursor_candidate_derives_appdata_from_home_when_env_is_missing
    resolver = Agent::Homedir::Resolver.new(
      env: {},
      home: "C:/Users/Test",
      os: :windows
    )

    assert_equal [Pathname("C:/Users/Test/AppData/Roaming/Cursor")], resolver.candidates(:cursor_ide)
  end

  def test_windows_unknown_missing_base_env_raises_a_descriptive_error
    resolver = build_resolver(
      os: :windows,
      home: "C:/Users/Test",
      env: {},
      entries: {
        codex: entry(paths: [{windows_env: "PROGRAMDATA", path: "Codex"}])
      }
    )

    error = assert_raises(ArgumentError) { resolver.candidates(:codex) }

    assert_includes error.message, "PROGRAMDATA"
    assert_includes error.message, "windows_env"
  end

  def test_relative_path_specs_are_rejected
    resolver = build_resolver(entries: {codex: entry(paths: ["relative/codex"])})

    assert_raises(ArgumentError) { resolver.candidates(:codex) }
  end

  private

  def build_resolver(env: {}, home: "/home/test", os: :linux, entries: {})
    Agent::Homedir::Resolver.new(env:, home:, os:, entries:)
  end

  def entry(env: nil, paths:, label: "Agent", verified_on: %i[linux macos windows])
    {
      label:,
      env:,
      paths:,
      verified_on:
    }
  end

  def symlink_unavailable_errors
    errors = [NotImplementedError, Errno::EPERM, Errno::EACCES]
    errors << Errno::ENOTSUP if defined?(Errno::ENOTSUP)
    errors << Errno::EOPNOTSUPP if defined?(Errno::EOPNOTSUPP)
    errors
  end

  class ConcurrentAgentsResolver < Agent::Homedir::Resolver
    attr_reader :fetch_started, :fetch_release

    def initialize(fetch_started:, fetch_release:, **kwargs)
      @fetch_started = fetch_started
      @fetch_release = fetch_release
      @fetch_count = 0
      @fetch_count_lock = Mutex.new

      super(**kwargs)
    end

    def [](name)
      call_number = @fetch_count_lock.synchronize do
        @fetch_count += 1
      end

      if call_number == 1
        fetch_started << name
        fetch_release.pop
      end

      super
    end
  end
end
