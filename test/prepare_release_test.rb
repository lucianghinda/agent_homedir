# frozen_string_literal: true

require "test_helper"
require "stringio"
load File.expand_path("../bin/prepare_release", __dir__)

class PrepareReleaseTest < Minitest::Test
  def test_runs_validation_generation_and_build_commands_in_order
    calls = []
    runner = lambda do |command, working_directory|
      calls << [command, working_directory]
      true
    end

    assert ReleasePreparer.new(root: root, ruby: ruby, runner: runner).call
    assert_equal expected_commands.map { |command| [command, root] }, calls
  end

  def test_stops_after_the_first_failed_command
    calls = []
    stderr = StringIO.new
    runner = lambda do |command, working_directory|
      calls << [command, working_directory]
      command != expected_commands.fetch(1)
    end

    refute ReleasePreparer.new(root: root, ruby: ruby, runner: runner, stderr: stderr).call
    assert_equal expected_commands.first(2).map { |command| [command, root] }, calls
    assert_equal "Release preparation failed: #{expected_commands.fetch(1).join(" ")}\n", stderr.string
  end

  private

  def root
    "/project"
  end

  def ruby
    "/ruby"
  end

  def expected_commands
    [
      [ruby, "-S", "bundle", "exec", "rake", "test"],
      [ruby, "-S", "bundle", "exec", "rake", "yard"],
      [ruby, File.join(root, "bin", "generate_llm.rb")],
      [ruby, "-S", "gem", "build", "agents_homedir.gemspec"]
    ]
  end
end
