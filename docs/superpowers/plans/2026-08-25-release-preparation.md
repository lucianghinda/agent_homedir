# Release Preparation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a self-contained, tested release command that generates Markdown API documentation and `llm.txt` before building the gem.

**Architecture:** Two testable Ruby executables separate document transformation from command orchestration. YARD produces ignored Markdown API files, the generator creates the tracked and packaged `llm.txt`, and the release entrypoint runs validation and build steps in a fail-fast sequence.

**Tech Stack:** Ruby 3.2+, Minitest, Rake, YARD, yard-markdown, RubyGems.

---

## File map

- Create `.yardopts`: deterministic Markdown API-documentation configuration.
- Create `bin/generate_llm.rb`: idempotent API-index and `llm.txt` generator.
- Create `bin/prepare_release`: fail-fast release command orchestrator.
- Create `test/llm_generator_test.rb`: document-generation behavior.
- Create `test/prepare_release_test.rb`: command ordering and failure behavior.
- Modify `Rakefile`: expose the YARD documentation task.
- Modify `agents_homedir.gemspec`: add development dependencies and package
  `llm.txt`.
- Modify `Gemfile.lock`: lock the added development dependencies.
- Modify `test/packaging_test.rb`: require `llm.txt` in the gem manifest.
- Create `llm.txt`: generated API entry document.

### Task 1: Test and implement deterministic LLM document generation

**Files:**
- Create: `test/llm_generator_test.rb`
- Create: `bin/generate_llm.rb`

- [ ] **Step 1: Write failing generator tests**

Add tests that create `doc/AgentsHomedir.md` plus deliberately unordered nested
Markdown documents in a temporary root. Require `bin/generate_llm.rb`, invoke
`LlmGenerator`, and assert:

```ruby
assert generator.call
assert_equal expected_main_document, File.read(main_document)
assert_equal expected_llm_document, File.read(File.join(root, "llm.txt"))
```

Invoke it a second time and compare both files byte-for-byte. Add a separate
test with no main document:

```ruby
refute generator.call
assert_match(/Missing .*doc\/AgentsHomedir\.md/, stderr.string)
refute File.exist?(File.join(root, "llm.txt"))
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `bundle exec ruby -Itest test/llm_generator_test.rb`

Expected: an error because `bin/generate_llm.rb` does not exist.

- [ ] **Step 3: Implement the minimal generator**

Define `LlmGenerator` with injected `root`, `stdout`, and `stderr`. Its `call`
method checks for `doc/AgentsHomedir.md`, sorts `doc/**/*.md` excluding the main
document, replaces the trailing documentation index, writes the main document,
then writes `llm.txt` with `doc/`-prefixed API paths. Guard CLI execution with:

```ruby
if $PROGRAM_NAME == __FILE__
  exit(LlmGenerator.new.call ? 0 : 1)
end
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `bundle exec ruby -Itest test/llm_generator_test.rb`

Expected: all generator tests pass with no warnings.

### Task 2: Test and implement fail-fast release orchestration

**Files:**
- Create: `test/prepare_release_test.rb`
- Create: `bin/prepare_release`

- [ ] **Step 1: Write failing orchestrator tests**

Require `bin/prepare_release`, inject a runner that records commands, and assert
that a successful call runs these commands in order:

```ruby
[
  [ruby, "-S", "bundle", "exec", "rake", "test"],
  [ruby, "-S", "bundle", "exec", "rake", "yard"],
  [ruby, File.join(root, "bin/generate_llm.rb")],
  [ruby, "-S", "gem", "build", "agents_homedir.gemspec"]
]
```

Add a failure test whose runner returns false for the YARD command. Assert the
generator and build commands are not run and stderr identifies the failed
command.

- [ ] **Step 2: Run the tests and verify RED**

Run: `bundle exec ruby -Itest test/prepare_release_test.rb`

Expected: an error because `bin/prepare_release` does not exist.

- [ ] **Step 3: Implement the minimal orchestrator**

Define `ReleasePreparer` with injected `root`, `ruby`, `runner`, and `stderr`.
Build the four command arrays, run each from `root`, and return false immediately
after the first failed command. Make the file executable and guard CLI execution
with `if $PROGRAM_NAME == __FILE__`.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `bundle exec ruby -Itest test/prepare_release_test.rb`

Expected: all release-orchestrator tests pass with no warnings.

### Task 3: Configure documentation and packaging

**Files:**
- Create: `.yardopts`
- Modify: `Rakefile`
- Modify: `agents_homedir.gemspec`
- Modify: `Gemfile.lock`
- Modify: `test/packaging_test.rb`

- [ ] **Step 1: Update the packaging test before the manifest**

Add `llm.txt` to `EXPECTED_PACKAGED_FILES` and assert the generated `doc/` tree
and release scripts remain absent.

- [ ] **Step 2: Run the packaging test and verify RED**

Run: `bundle exec ruby -Itest test/packaging_test.rb`

Expected: manifest mismatch because `llm.txt` is not yet packaged.

- [ ] **Step 3: Add development dependencies and YARD configuration**

Add development requirements `yard ~> 0.9` and `yard-markdown ~> 0.5` to the
gemspec, require `yard` in the Rakefile, define `YARD::Rake::YardocTask.new`, and
configure Markdown output under `doc/` in `.yardopts`.

- [ ] **Step 4: Lock dependencies**

Run: `bundle install`

Expected: `Gemfile.lock` contains YARD, yard-markdown, and their dependencies.

- [ ] **Step 5: Generate documentation and `llm.txt`**

Run: `bundle exec rake yard`

Expected: YARD writes `doc/AgentsHomedir.md` and related Markdown documents.

Run: `bundle exec ruby bin/generate_llm.rb`

Expected: the generator updates the API index and writes root `llm.txt`.

- [ ] **Step 6: Package `llm.txt`**

Add `llm.txt` to the explicit gemspec file manifest. Keep `doc/` and `bin/`
excluded.

- [ ] **Step 7: Run the packaging and full test suites**

Run: `bundle exec ruby -Itest test/packaging_test.rb`

Expected: packaging tests pass.

Run: `bundle exec rake test`

Expected: all tests pass.

### Task 4: Verify the complete release workflow

**Files:**
- Verify: `bin/prepare_release`
- Verify: `llm.txt`
- Verify: generated `agents_homedir-*.gem`

- [ ] **Step 1: Run the release entrypoint**

Run: `bin/prepare_release`

Expected: tests and documentation generation pass, `llm.txt` is regenerated,
and RubyGems builds the current version.

- [ ] **Step 2: Inspect the built gem**

Run: `gem contents --show-install-dir` is not appropriate for an uninstalled
artifact; use RubyGems package inspection to list the `.gem` payload instead.
Assert `llm.txt` is present and no `doc/`, `bin/`, or `test/` path is present.

- [ ] **Step 3: Run syntax and cleanliness checks**

Run Ruby syntax checks on both new executables and inspect `git status --short`.
Expected: syntax is valid and only intentional source, test, lockfile, planning,
and generated `llm.txt` changes remain; `doc/` and `.gem` artifacts are ignored.

- [ ] **Step 4: Commit with Lore trailers**

Commit the completed implementation using an intent-first message. Record the
YARD constraint, rejected README-only approach, confidence, scope risk, tests,
and any remaining verification gap as git-native trailers.
