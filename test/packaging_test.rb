# frozen_string_literal: true

require "test_helper"
require "bundler"
require "fileutils"
require "open3"
require "rubygems"
require "rubygems/package"
require "rbconfig"
require "tmpdir"

class PackagingTest < Minitest::Test
  EXPECTED_PACKAGED_FILES = %w[
    CHANGELOG.md
    LICENSE.txt
    README.md
    doc/AgentsHomedir.md
    doc/AgentsHomedir/Agent.md
    doc/AgentsHomedir/Error.md
    doc/AgentsHomedir/HomeNotResolvable.md
    doc/AgentsHomedir/Resolver.md
    doc/AgentsHomedir/UnknownAgent.md
    doc/CHANGELOG.md
    doc/README.md
    doc/index.csv
    lib/agents_homedir.rb
    lib/agents_homedir/agent.rb
    lib/agents_homedir/error.rb
    lib/agents_homedir/home_not_resolvable.rb
    lib/agents_homedir/registry.rb
    lib/agents_homedir/resolver.rb
    lib/agents_homedir/unknown_agent.rb
    lib/agents_homedir/version.rb
    llm.txt
  ].freeze

  def test_gemspec_exposes_modern_packaging_metadata
    spec = Gem::Specification.load(File.expand_path("../agents_homedir.gemspec", __dir__))

    assert_equal "agents_homedir", spec.name
    assert_equal "0.2.1", spec.version.to_s
    assert_equal "Resolve home directories for AI coding agents.", spec.summary
    assert_equal "DEPRECATED: renamed to agent_homedir. Helpers for resolving and normalizing home directories used by AI coding agents.", spec.description
    assert_equal "agents_homedir has been renamed to agent_homedir: https://github.com/lucianghinda/agent_homedir", spec.post_install_message
    assert_equal "MIT", spec.license
    assert_equal "https://github.com/lucianghinda/agents_homedir", spec.homepage
    assert_equal ">= 3.2", spec.required_ruby_version.to_s
    assert_equal "https://github.com/lucianghinda/agents_homedir", spec.metadata["source_code_uri"]
    assert_equal "https://github.com/lucianghinda/agents_homedir/issues", spec.metadata["bug_tracker_uri"]
    assert_equal "https://github.com/lucianghinda/agents_homedir/blob/main/CHANGELOG.md", spec.metadata["changelog_uri"]
    assert_equal "true", spec.metadata["rubygems_mfa_required"]
    refute spec.metadata.key?("allowed_push_host")

    runtime_dependencies = spec.dependencies.reject { |dependency| dependency.type == :development }.to_h { |dependency| [dependency.name, dependency.requirement.to_s] }
    assert_equal({"zeitwerk" => "~> 2.8"}, runtime_dependencies)

    development_dependencies = spec.dependencies.select { |dependency| dependency.type == :development }.to_h { |dependency| [dependency.name, dependency.requirement.to_s] }

    assert_equal(
      {
        "bundler" => ">= 2.0, < 5",
        "minitest" => "~> 5.0",
        "rake" => "~> 13.0",
        "yard" => "~> 0.9",
        "yard-markdown" => "~> 0.9"
      },
      development_dependencies
    )
  end

  def test_current_release_is_documented_in_the_changelog
    changelog_path = File.expand_path("../CHANGELOG.md", __dir__)

    assert File.exist?(changelog_path), "expected CHANGELOG.md to exist"
    assert_includes File.read(changelog_path), "## [0.2.0] - 2026-08-25"
  end

  def test_gemspec_manifest_is_explicit_and_buildable_without_git_repository
    with_non_git_copy do |copy_dir|
      Dir.chdir(copy_dir) do
        spec = Gem::Specification.load("agents_homedir.gemspec")

        assert_equal EXPECTED_PACKAGED_FILES, spec.files.sort
        refute_includes spec.files, "CODE_OF_CONDUCT.md"
        refute_includes spec.files, "Gemfile"
        refute_includes spec.files, "Gemfile.lock"
        refute_includes spec.files, "Rakefile"
        refute_includes spec.files, ".gitignore"
        refute spec.files.any? { |path| path.start_with?("bin/") }
        refute spec.files.any? { |path| path.start_with?("test/") }

        built_gem = Gem::Package.build(spec)
        assert File.exist?(File.join(copy_dir, built_gem)), "expected #{built_gem.inspect} to be built in #{copy_dir.inspect}"
      end
    end
  end

  def test_built_gem_installs_and_requires_as_an_isolated_artifact
    with_non_git_copy do |copy_dir|
      built_gem = Dir.chdir(copy_dir) do
        spec = Gem::Specification.load("agents_homedir.gemspec")
        Gem::Package.build(spec)
      end

      gem_home = File.join(copy_dir, "tmp", "gems")
      gem_path = gem_home
      FileUtils.mkdir_p(gem_home)
      copy_installed_gem(Gem::Specification.find_by_name("zeitwerk"), gem_home)

      stdout = stderr = status = nil
      Bundler.with_unbundled_env do
        stdout, stderr, status = Open3.capture3(
          {"GEM_HOME" => gem_home, "GEM_PATH" => gem_path},
          RbConfig.ruby,
          "-S",
          "gem",
          "install",
          "--install-dir",
          gem_home,
          "--local",
          "--ignore-dependencies",
          "--no-document",
          File.join(copy_dir, built_gem)
        )
      end
      assert status.success?, "expected gem install to succeed, stderr: #{stderr.inspect}, stdout: #{stdout.inspect}"

      script = <<~RUBY
        gem "agents_homedir"
        require "agents_homedir"

        abort("expected frozen version") unless AgentsHomedir::VERSION.frozen?
        AgentsHomedir.send(:loader).eager_load
        abort("expected resolver constant") unless defined?(AgentsHomedir::Resolver)
        abort("expected codex home") unless AgentsHomedir::Resolver.new(
          env: {"CODEX_HOME" => "/tmp/codex"},
          home: "/tmp/home",
          os: :linux
        ).home(:codex).to_s == "/tmp/codex"
      RUBY

      stdout = stderr = status = nil
      Bundler.with_unbundled_env do
        stdout, stderr, status = Open3.capture3(
          {"GEM_HOME" => gem_home, "GEM_PATH" => gem_path},
          RbConfig.ruby,
          "-e",
          script
        )
      end
      assert status.success?, "expected installed gem require to succeed, stderr: #{stderr.inspect}, stdout: #{stdout.inspect}"
    end
  end

  def test_llm_document_links_only_to_packaged_files
    spec = Gem::Specification.load(File.expand_path("../agents_homedir.gemspec", __dir__))
    llm_document = File.read(File.expand_path("../llm.txt", __dir__))
    linked_files = llm_document.scan(%r{\]\((doc/[^)]+)\)}).flatten

    refute_empty linked_files
    linked_files.each { |path| assert_includes spec.files, path }
  end

  def test_travis_configuration_is_removed
    refute File.exist?(File.expand_path("../.travis.yml", __dir__))
  end

  private

  def copy_installed_gem(spec, gem_home)
    gems_dir = File.join(gem_home, "gems")
    specifications_dir = File.join(gem_home, "specifications")
    FileUtils.mkdir_p(gems_dir)
    FileUtils.mkdir_p(specifications_dir)
    FileUtils.cp_r(spec.full_gem_path, File.join(gems_dir, spec.full_name))
    FileUtils.cp(spec.spec_file, File.join(specifications_dir, "#{spec.full_name}.gemspec"))
  end

  def with_non_git_copy
    Dir.mktmpdir do |dir|
      project_root = File.expand_path("..", __dir__)

      Dir.children(project_root).sort.each do |entry|
        next if entry == ".git"

        FileUtils.cp_r(File.join(project_root, entry), File.join(dir, entry))
      end

      yield dir
    end
  end
end
