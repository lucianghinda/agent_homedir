# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"
require_relative "../bin/generate_llm"

class LlmGeneratorTest < Minitest::Test
  def test_generates_sorted_documentation_links_for_doc_and_repository_roots
    with_documentation_tree do |root, main_document|
      stdout = StringIO.new

      assert LlmGenerator.new(root: root, stdout: stdout).call

      expected_main = <<~MARKDOWN
        # Module: AgentsHomedir

        API documentation.

        # Documentation

        - [AgentsHomedir/Agent.md](AgentsHomedir/Agent.md)
        - [AgentsHomedir/Nested/Resolver.md](AgentsHomedir/Nested/Resolver.md)
        - [AgentsHomedir/Registry.md](AgentsHomedir/Registry.md)
      MARKDOWN

      expected_llm = expected_main
        .gsub("[AgentsHomedir/", "[doc/AgentsHomedir/")
        .gsub("(AgentsHomedir/", "(doc/AgentsHomedir/")

      assert_equal expected_main, File.read(main_document)
      assert_equal expected_llm, File.read(File.join(root, "llm.txt"))
      assert_equal "Updated #{main_document} (3 links)\n", stdout.string
    end
  end

  def test_generation_is_idempotent
    with_documentation_tree do |root, main_document|
      generator = LlmGenerator.new(root: root, stdout: StringIO.new)

      assert generator.call
      first_main = File.read(main_document)
      first_llm = File.read(File.join(root, "llm.txt"))

      assert generator.call
      assert_equal first_main, File.read(main_document)
      assert_equal first_llm, File.read(File.join(root, "llm.txt"))
    end
  end

  def test_fails_when_main_document_is_missing
    Dir.mktmpdir do |root|
      stderr = StringIO.new

      refute LlmGenerator.new(root: root, stdout: StringIO.new, stderr: stderr).call
      assert_match %r{Missing .*/doc/AgentsHomedir\.md}, stderr.string
      refute File.exist?(File.join(root, "llm.txt"))
    end
  end

  private

  def with_documentation_tree
    Dir.mktmpdir do |root|
      main_document = File.join(root, "doc", "AgentsHomedir.md")
      FileUtils.mkdir_p(File.join(root, "doc", "AgentsHomedir", "Nested"))
      FileUtils.mkdir_p(File.join(root, "doc", "docs", "superpowers"))
      File.write(main_document, <<~MARKDOWN)
        # Module: AgentsHomedir

        API documentation.

        # Documentation

        - [stale](stale.md)
      MARKDOWN
      File.write(File.join(root, "doc", "AgentsHomedir", "Registry.md"), "Registry")
      File.write(File.join(root, "doc", "AgentsHomedir", "Agent.md"), "Agent")
      File.write(File.join(root, "doc", "AgentsHomedir", "Nested", "Resolver.md"), "Resolver")
      File.write(File.join(root, "doc", "README.md"), "Project README")
      File.write(File.join(root, "doc", "docs", "superpowers", "plan.md"), "Release plan")

      yield root, main_document
    end
  end
end
