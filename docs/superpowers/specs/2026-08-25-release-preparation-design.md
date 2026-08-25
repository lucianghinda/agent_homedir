# Release Preparation Design

## Context

`agent_skill_parser` has a release entrypoint that generates Markdown API
documentation, derives an LLM-oriented document, and builds the gem. This gem
needs the same outcome, but the workflow should be self-contained and should
produce the requested `llm.txt` artifact consistently.

The reference implementation has two gaps that this design deliberately avoids:
its release entrypoint assumes YARD documentation already exists, and its
generator writes `llm.txt` even though that repository now tracks `llm.md`.

## Goals

- Provide one executable command, `bin/prepare_release`, for validating and
  building a release artifact.
- Generate Markdown API documentation from the Ruby source.
- Generate a deterministic, idempotent root-level `llm.txt` whose API links
  resolve into the generated `doc/` tree.
- Package `llm.txt` and its generated `doc/` link targets with the gem while
  keeping release scripts out of the gem.
- Fail immediately when tests, documentation generation, LLM generation, or
  gem building fails.

## Non-goals

- Publishing the gem to RubyGems.
- Changing the gem version or maintaining a changelog.
- Adding runtime dependencies.

## Architecture

### API documentation

YARD and `yard-markdown` are development dependencies. `.yardopts` defines
Markdown output under `doc/`, includes protected APIs, excludes private APIs
and internal planning documents, and uses `README.md` as the extra landing-page
content. A YARD Rake task removes stale output before exposing clean generation
as `bundle exec rake yard`.

`yard-markdown` stays on its current `0.9.x` release line. This produces clean,
stable Markdown and declares the RDoc dependency Ruby 4 needs explicitly.

### LLM document generator

`bin/generate_llm.rb` owns transformation of generated API documentation into
`llm.txt`. It reads `doc/AgentsHomedir.md`, discovers the remaining Markdown
documents recursively, sorts them for deterministic output, and replaces any
existing final `# Documentation` section with a fresh link index.

The updated main document retains paths relative to its own `doc/` directory.
The root `llm.txt` copy prefixes those paths with `doc/`, so the same links work
from the repository and packaged-gem root. Running the generator repeatedly
produces byte-for-byte identical output. A missing main document is reported to
standard error and returns a failing exit status.

### Release orchestrator

`bin/prepare_release` is a Ruby executable. From the repository root it runs,
in order:

1. `bundle exec rake test`
2. `bundle exec rake yard`
3. `bin/generate_llm.rb` using the active Ruby interpreter
4. Build `agents_homedir.gemspec` with RubyGems' in-process `Gem::Package` API.

Each command inherits normal output. The first failed command stops the
pipeline, reports the command, and makes the entrypoint exit unsuccessfully.
The build stays in the release script's Ruby process, preventing the system
`gem` launcher and globally installed documentation gems from leaking into the
release process. The script only builds the gem; it never publishes it.

## Packaging

The explicit gemspec manifest gains `llm.txt` and the generated Markdown/CSV
files under `doc/`, ensuring every relative link in `llm.txt` resolves in a
clean checkout and an installed gem. It continues to omit `bin/`, `test/`, and
configuration. YARD dependencies are development-only and therefore do not
affect users of the gem.

## Testing

Generator tests use temporary documentation trees and verify deterministic link
ordering, correct root-relative paths, idempotence, and missing-input failure.
Orchestrator tests inject a command runner to verify the exact command sequence
and fail-fast behavior without performing a real release build.

The existing packaging test is extended to require `llm.txt` in the built gem.
Final verification runs the focused tests, full test suite, release entrypoint,
and inspects the resulting gem contents.

## Risks

- YARD output can change between dependency versions. Version requirements and
  the lockfile keep local generation reproducible within the selected release
  line.
- `llm.txt` and `doc/` are generated, so API changes can make tracked documents
  stale until release preparation is run. The release entrypoint always cleans
  and regenerates both before the gem is built.
