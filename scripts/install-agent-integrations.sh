#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BIN="$HOME/Applications/Stratus.app/Contents/MacOS/Stratus"
SKILL_SRC="$ROOT_DIR/.agents/skills/stratus/SKILL.md"

if [[ ! -x "$APP_BIN" ]]; then
  echo "Error: Stratus.app not found at $APP_BIN. Run ./scripts/build-app.sh --release --install first." >&2
  exit 1
fi

# 1. Install `stratus` CLI symlink
mkdir -p "$HOME/.local/bin"
ln -sf "$APP_BIN" "$HOME/.local/bin/stratus"
echo "Linked CLI: $HOME/.local/bin/stratus -> $APP_BIN"

# 2. Install Stratus SKILL.md for Antigravity (agy), Claude Code (Fairy), and Codex (Fairy)
for skill_dir in \
  "$HOME/.gemini/config/skills/stratus" \
  "$HOME/.claude/skills/stratus" \
  "$HOME/.codex/skills/stratus"; do
  mkdir -p "$skill_dir"
  cp "$SKILL_SRC" "$skill_dir/SKILL.md"
  echo "Installed skill: $skill_dir/SKILL.md"
done

# 3. Register MCP server in Antigravity (`agy mcp add`)
if command -v agy >/dev/null 2>&1; then
  agy mcp add stratus "$APP_BIN" -- --mcp
  echo "Registered MCP server 'stratus' in Antigravity (agy)."
else
  echo "Warning: 'agy' CLI not found; skipping Antigravity MCP registration."
fi

# 4. Register MCP server in Claude Code / Fairy (~/.claude.json)
CLAUDE_JSON="$HOME/.claude.json"
if [[ -f "$CLAUDE_JSON" ]]; then
  python3 - "$CLAUDE_JSON" "$APP_BIN" << 'PY'
import json, sys
path, app_bin = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
servers = data.setdefault("mcpServers", {})
servers["stratus"] = {
    "command": app_bin,
    "args": ["--mcp"]
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"Registered MCP server 'stratus' in {path}")
PY
fi

# 5. Register MCP server in Codex / Fairy (~/.codex/config.toml)
CODEX_TOML="$HOME/.codex/config.toml"
if [[ -f "$CODEX_TOML" ]]; then
  python3 - "$CODEX_TOML" "$APP_BIN" << 'PY'
import re, sys
path, app_bin = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()
block = f'[mcp_servers.stratus]\ncommand = "{app_bin}"\nargs = ["--mcp"]\n'
if "[mcp_servers.stratus]" in text:
    text = re.sub(r'\[mcp_servers\.stratus\][^\[]*', block + "\n", text, flags=re.MULTILINE)
else:
    if text and not text.endswith("\n"):
        text += "\n"
    text += "\n" + block
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
print(f"Registered MCP server 'stratus' in {path}")
PY
fi

echo "All agent integrations installed."
