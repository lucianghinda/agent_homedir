# frozen_string_literal: true

require "test_helper"
require "stringio"
load File.expand_path("../bin/prepare_release", __dir__)

class PrepareReleaseTest < Minitest::Test
  def test_runs_validation_generation_and_build_commands_in_order
    events = []
    runner = lambda do |command, working_directory|
      events << [:command, command, working_directory]
      true
    end
    builder = lambda do |working_directory|
      events << [:build, working_directory]
      true
    end

    assert ReleasePreparer.new(root: root, ruby: ruby, runner: runner, builder: builder).call
    expected_events = expected_commands.map { |command| [:command, command, root] }
    expected_events << [:build, root]
    assert_equal expected_events, events
  end

  def test_stops_after_the_first_failed_command
    calls = []
    stderr = StringIO.new
    runner = lambda do |command, working_directory|
      calls << [command, working_directory]
      command != expected_commands.fetch(1)
    end
    builder = ->(_working_directory) { flunk "builder should not run after a failed command" }

    refute ReleasePreparer.new(root: root, ruby: ruby, runner: runner, builder: builder, stderr: stderr).call
    assert_equal expected_commands.first(2).map { |command| [command, root] }, calls
    assert_equal "Release preparation failed: #{expected_commands.fetch(1).join(" ")}\n", stderr.string
  end

  def test_fails_when_gem_building_fails
    stderr = StringIO.new
    runner = ->(_command, _working_directory) { true }
    builder = ->(_working_directory) { false }

    refute ReleasePreparer.new(root: root, ruby: ruby, runner: runner, builder: builder, stderr: stderr).call
    assert_equal "Release preparation failed: build agent_homedir.gemspec\n", stderr.string
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
      [ruby, File.join(root, "bin", "generate_llm.rb")]
    ]
  end
end
