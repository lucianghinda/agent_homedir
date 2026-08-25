# Changelog

All notable changes to this project are documented in this file.

## [0.2.0] - 2026-08-25

### Added

- Added `bin/prepare_release` to run tests, regenerate documentation, create
  `llm.txt`, and build the release artifact in one fail-fast workflow.
- Added generated Markdown API documentation and an LLM-oriented entry point.
- Added regression coverage for documentation generation, release command
  ordering, failure handling, and packaged documentation links.
- Added the usage demo image to the README.

### Changed

- Included `llm.txt` and every linked API document in the packaged gem.
- Corrected the gem author email metadata.

## [0.1.0] - 2026-08-25

### Added

- Initial release with home-directory resolution for supported AI coding
  agents, immutable agent values, environment overrides, and OS-aware defaults.
