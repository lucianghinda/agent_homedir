# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

class DocumentationTaskTest < Minitest::Test
  def test_yard_task_replaces_stale_output_and_excludes_internal_plans
    with_project_copy do |root|
      doc_directory = File.join(root, "doc")
      FileUtils.mkdir_p(File.join(doc_directory, "docs", "superpowers"))
      File.write(File.join(doc_directory, "stale.md"), "stale")
      File.write(File.join(doc_directory, "docs", "superpowers", "plan.md"), "plan")

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        "-S",
        "bundle",
        "exec",
        "rake",
        "yard",
        chdir: root
      )

      assert status.success?, "expected YARD task to pass, stderr: #{stderr.inspect}, stdout: #{stdout.inspect}"
      assert File.exist?(File.join(doc_directory, "Agent.md"))
      assert File.exist?(File.join(doc_directory, "Agent", "Homedir.md"))
      assert File.exist?(File.join(doc_directory, "Agent", "Homedir", "Entry.md"))
      refute File.exist?(File.join(doc_directory, "stale.md"))
      refute File.exist?(File.join(doc_directory, "docs"))
    end
  end

  private

  def project_root
    File.expand_path("..", __dir__)
  end

  def with_project_copy
    Dir.mktmpdir do |root|
      %w[.yardopts Gemfile Gemfile.lock README.md Rakefile agent_homedir.gemspec docs lib].each do |entry|
        FileUtils.cp_r(File.join(project_root, entry), File.join(root, entry))
      end

      yield root
    end
  end
end
