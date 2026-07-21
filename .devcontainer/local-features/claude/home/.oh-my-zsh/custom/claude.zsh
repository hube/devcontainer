# Needed for Claude
export PATH="$HOME/.local/bin:$PATH"

# Setting CLAUDE_CONFIG_DIR ensures all Claude Code config, in particular
# `.claude.json` are stored in the same location, which can then be preserved in
# a volume mount
export CLAUDE_CONFIG_DIR="$HOME/.claude"

# Claude Code seems to default to using Bash
export CLAUDE_CODE_SHELL="/usr/bin/zsh"
