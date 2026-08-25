# Agent::Homedir

Find the home folder an AI coding agent uses, without reading contents.

<img width="1400" height="850" alt="agent_homedir-demo" src="https://github.com/user-attachments/assets/62fa43bc-5df6-42c0-af2c-1f25ea7070a1" />


## Installation

Use Ruby 3.2 or newer. The gem ships with one runtime dependency: Zeitwerk 2.8.

Add this line to your application's **Gemfile**:

```ruby
gem "agent_homedir"
```

Then run:

```sh
bundle install
```

Or install it directly:

```sh
gem install agent_homedir
```

## Quick Start

Get a home path:

```ruby
require "agent_homedir"

Agent::Homedir.home(:claude_code)
```

Check installation:

```ruby
require "agent_homedir"

Agent::Homedir.installed?(:codex)
```

Expect a `Pathname` and a boolean.

The module facade is snapshotted on first access.
That snapshots `ENV` and `HOME` for the rest of the process.
If you need a different snapshot, instantiate `Agent::Homedir::Resolver` directly.

## Usage

Fetch an agent:

```ruby
require "agent_homedir"

agent = Agent::Homedir[:codex]

agent.name
agent.label
agent.home
```

Discover the catalog:

```ruby
require "agent_homedir"

Agent::Homedir.names
Agent::Homedir.agents
Agent::Homedir.installed
```

Expect ordered, frozen arrays.

### Supported agents

Use these names with every lookup method:

| Agent | Name |
| --- | --- |
| Claude Code | `:claude_code` |
| Codex CLI | `:codex` |
| Gemini CLI | `:gemini` |
| Antigravity CLI | `:antigravity_cli` |
| Antigravity IDE | `:antigravity_ide` |
| Antigravity App | `:antigravity_app` |
| Qwen Code | `:qwen` |
| Pi | `:pi` |
| Amp | `:amp` |
| OpenCode | `:opencode` |
| Cursor | `:cursor` |
| Cursor IDE | `:cursor_ide` |
| GitHub Copilot CLI | `:github_copilot_cli` |
| VS Code Copilot Chat | `:vscode_copilot_chat` |
| Cline | `:cline` |
| Cline for VS Code | `:cline_vscode` |
| Grok Build | `:grok_build` |
| Vibe | `:vibe` |
| Muse Code | `:muse` |
| Prime Agent | `:prime_agent` |
| DeepSeek Harness | `:deepseek_harness` |
| Hermes Agent | `:hermes` |
| Factory Droid | `:factory_droid` |
| Devin CLI | `:devin_cli` |
| Devin Desktop | `:devin_desktop` |

Inspect agent facts:

```ruby
require "agent_homedir"

agent = Agent::Homedir[:claude_code]

agent.env_override
agent.verified_on
agent.candidates
```

Resolution order:

- Use a nonblank native override.
- Use the first existing directory candidate.
- Use the first candidate otherwise.

Agent facts:

- `name` is a `Symbol`.
- `label` is a `String`.
- `home` returns a `Pathname`.
- `installed?` returns a boolean.
- `candidates` returns an ordered, frozen array of `Pathname` objects.
- `env_override` is a `String` or `nil`.
- `verified_on` is a `Date` or `nil`.

Errors:

- Catch `Agent::Homedir::UnknownAgent` to list valid names.
- Catch `Agent::Homedir::HomeNotResolvable` for missing, blank, or nonabsolute `HOME`.

## Testing

Pass `env`, `home`, and `os` explicitly.
Instantiate a fresh resolver when you need a different environment snapshot.
Do not stub global `ENV`.

```ruby
require "agent_homedir"

resolver = Agent::Homedir::Resolver.new(
  env: { "CODEX_HOME" => "custom/codex" },
  home: "/Users/me",
  os: :linux
)

resolver.home(:codex)
# => #<Pathname:/Users/me/custom/codex>
```

## Contributing

Activate Ruby 3.2 or newer.

Run the tests before sending a change.

```sh
bundle install
bundle exec rake test
```

## License

MIT
