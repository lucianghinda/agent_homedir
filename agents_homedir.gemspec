
# frozen_string_literal: true

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "agents_homedir/version"

Gem::Specification.new do |spec|
  spec.name          = "agents_homedir"
  spec.version       = AgentsHomedir::VERSION
  spec.authors       = ["Lucian Ghinda"]
  spec.email         = ["lucian@ghinda.com"]

  spec.summary       = "Resolve home directories for AI coding agents."
  spec.description   = "Helpers for resolving and normalizing home directories used by AI coding agents."
  spec.homepage      = "https://github.com/lucianghinda/agents_homedir"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files         = Dir.chdir(File.expand_path("..", __FILE__)) do
    (%w[LICENSE.txt README.md llm.txt] + Dir.glob("doc/**/*.{csv,md}") + Dir.glob("lib/**/*.rb")).sort
  end
  spec.require_paths = ["lib"]
  spec.add_dependency "zeitwerk", "~> 2.8"

  spec.add_development_dependency "bundler", ">= 2.0", "< 5"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "yard", "~> 0.9"
  spec.add_development_dependency "yard-markdown", "~> 0.9"
end
