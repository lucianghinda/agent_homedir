# frozen_string_literal: true

module AgentsHomedir
  module Registry
    class << self
      def entries
        @entries ||= deep_freeze(
          {
            claude_code: agent("Claude Code", env: "CLAUDE_CONFIG_DIR", paths: "~/.claude", verified_on: "2026-08-05"),
            codex: agent("Codex CLI", env: "CODEX_HOME", paths: "~/.codex", verified_on: "2026-07-21"),
            gemini: agent("Gemini CLI", paths: "~/.gemini"),
            antigravity_cli: agent("Antigravity CLI", paths: "~/.gemini/antigravity-cli"),
            antigravity_ide: agent("Antigravity IDE", paths: "~/.gemini/antigravity-ide"),
            antigravity_app: agent("Antigravity App", paths: "~/.gemini/antigravity"),
            qwen: agent("Qwen Code", paths: "~/.qwen"),
            pi: agent("Pi", env: "PI_CODING_AGENT_DIR", paths: "~/.pi/agent", verified_on: "2026-07-21"),
            amp: agent("Amp", paths: [xdg_data("amp")], verified_on: "2026-07-21"),
            opencode: agent(
              "OpenCode",
              env: "OPENCODE_DATA_DIR",
              paths: {
                macos: [xdg_data("opencode"), "~/Library/Application Support/opencode"],
                linux: [xdg_data("opencode")],
                windows: [
                  windows_env("XDG_DATA_HOME", "opencode", optional: true),
                  windows_env("APPDATA", "opencode"),
                  windows_env("LOCALAPPDATA", "opencode"),
                  "~/.local/share/opencode"
                ]
              },
              verified_on: "2026-07-21"
            ),
            cursor: agent("Cursor", paths: "~/.cursor", verified_on: "2026-07-21"),
            cursor_ide: agent(
              "Cursor IDE",
              paths: {
                macos: "~/Library/Application Support/Cursor",
                linux: xdg_config("Cursor"),
                windows: windows_env("APPDATA", "Cursor")
              }
            ),
            github_copilot_cli: agent("GitHub Copilot CLI", paths: "~/.copilot"),
            vscode_copilot_chat: agent(
              "VS Code Copilot Chat",
              paths: {
                macos: "~/Library/Application Support/Code/User",
                linux: xdg_config("Code/User"),
                windows: windows_env("APPDATA", "Code/User")
              }
            ),
            cline: agent("Cline", paths: "~/.cline"),
            cline_vscode: agent(
              "Cline for VS Code",
              paths: {
                macos: "~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev",
                linux: xdg_config("Code/User/globalStorage/saoudrizwan.claude-dev"),
                windows: windows_env("APPDATA", "Code/User/globalStorage/saoudrizwan.claude-dev")
              }
            ),
            grok_build: agent("Grok Build", paths: "~/.grok"),
            vibe: agent("Vibe", paths: "~/.vibe"),
            muse: agent("Muse Code", paths: [xdg_data("muse")]),
            prime_agent: agent("Prime Agent", paths: "~/.prime/agent"),
            deepseek_harness: agent("DeepSeek Harness", env: "DSH_HOME", paths: "~/.dsh"),
            hermes: agent("Hermes Agent", env: "HERMES_HOME", paths: "~/.hermes"),
            factory_droid: agent("Factory Droid", paths: "~/.factory"),
            devin_cli: agent("Devin CLI", paths: "~/.config/devin"),
            devin_desktop: agent("Devin Desktop", paths: "~/.codeium/windsurf")
          }
        )
      end

      private

      def agent(label, env: nil, paths:, verified_on: nil)
        {
          label:,
          env:,
          paths:,
          verified_on:
        }
      end

      def xdg_config(path)
        {xdg: :config, path:}
      end

      def xdg_data(path)
        {xdg: :data, path:}
      end

      def windows_env(env_key, path, optional: false)
        spec = {windows_env: env_key, path:}
        optional ? spec.merge(optional: true) : spec
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested), copy|
            copy[deep_freeze(key)] = deep_freeze(nested)
          end.freeze
        when Array
          value.map { deep_freeze(_1) }.freeze
        when String
          value.dup.freeze
        else
          value
        end
      end
    end
  end

  private_constant :Registry
end
