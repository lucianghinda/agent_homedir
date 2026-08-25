
# frozen_string_literal: true

require_relative "lib/agent/homedir/version"

Gem::Specification.new do |spec|
  spec.name          = "agent_homedir"
  spec.version       = Agent::Homedir::VERSION
  spec.authors       = ["Lucian Ghinda"]
  spec.email         = ["lucian@ghinda.com"]

  spec.summary       = "Resolve home directories for AI coding agents."
  spec.description   = "Helpers for resolving and normalizing home directories used by AI coding agents."
  spec.homepage      = "https://github.com/lucianghinda/agent_homedir"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files         = Dir.chdir(File.expand_path("..", __FILE__)) do
    (%w[CHANGELOG.md LICENSE.txt README.md llm.txt] + Dir.glob("doc/**/*.{csv,md}") + Dir.glob("lib/**/*.rb")).sort
  end
  spec.require_paths = ["lib"]
  spec.add_dependency "zeitwerk", "~> 2.8"

  spec.add_development_dependency "bundler", ">= 2.0", "< 5"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "yard", "~> 0.9"
  spec.add_development_dependency "yard-markdown", "~> 0.9"
end
