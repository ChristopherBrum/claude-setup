#!/usr/bin/env bash
# PostToolUse (Write|Edit) reminder: keep HOW-TO.md in sync with the setup.
#
# Rationale: whenever the custom Claude setup changes in a way that alters how it
# works or how it's used (agents, commands, hooks, settings), the how-to guide at
# ~/.claude/HOW-TO.md must be updated to match. This hook deterministically DETECTS
# such a change and injects a reminder; the actual doc update is done by the model.
# It is non-blocking (additionalContext), so it never interrupts a config edit.
#
# Fires only for edits under ~/.claude/{agents,commands,hooks} or the settings files.
# It intentionally ignores per-agent/shared memory (churns constantly, doesn't change
# how the setup is used) and ignores edits to HOW-TO.md itself (no self-nagging).
set -euo pipefail

input=$(cat)
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
[ -z "$path" ] && exit 0

# Normalize: resolve ~ and compare against the claude config root.
claude_root="$HOME/.claude"

# Ignore anything outside the config root, and the guide itself.
case "$path" in
  "$claude_root"/HOW-TO.md) exit 0 ;;
  "$claude_root"/agents/*.md) : ;;
  "$claude_root"/commands/*.md) : ;;
  "$claude_root"/hooks/*) : ;;
  "$claude_root"/settings.json|"$claude_root"/settings.local.json) : ;;
  "$claude_root"/CLAUDE.md) : ;;
  *) exit 0 ;;
esac

remind() {
  jq -n --arg c "$1" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $c
    }
  }'
  exit 0
}

remind "You just changed the custom Claude setup ($path). If this change alters how the setup works or how it is used (a new/removed/renamed agent or command, a changed hook, or a behavior-affecting setting), update ~/.claude/HOW-TO.md in the same session so the guide stays accurate. If the change does not affect usage (a typo, comment, or internal-only tweak), no update is needed."
