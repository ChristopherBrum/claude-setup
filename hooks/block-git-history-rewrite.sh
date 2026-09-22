#!/usr/bin/env bash
# PreToolUse (Bash) guard: block git commands that rewrite history.
#
# Rationale: commits must be append-only so pushes always fast-forward and no
# already-merged commit (yours or a teammate's) is silently rewritten. See
# ~/.claude/skills/commit/SKILL.md. This deterministically enforces that rule
# regardless of what any command file or model decides to do.
#
# Emits a PreToolUse "deny" decision (JSON on stdout) when the command matches
# a history-rewriting pattern; otherwise exits 0 (allow).
set -euo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

has() { printf '%s' "$cmd" | grep -Eq "$1"; }

# git commit --amend
if has 'git[[:space:]]+commit' && printf '%s' "$cmd" | grep -Eq -- '--amend'; then
  deny "Blocked: 'git commit --amend' rewrites an existing commit. Create a new append-only commit with a plain 'git commit' instead. If a pre-commit hook changed files, stage them as a follow-up commit. See ~/.claude/skills/commit/SKILL.md."
fi

# git rebase (allow recovery subcommands)
if has 'git[[:space:]]+rebase' && ! printf '%s' "$cmd" | grep -Eq -- '--(abort|continue|skip|quit)'; then
  deny "Blocked: 'git rebase' rewrites history. Use plain merges/commits instead. Recovery flags (--abort/--continue/--skip/--quit) are allowed. See ~/.claude/skills/commit/SKILL.md."
fi

# git reset --hard
if has 'git[[:space:]]+reset' && printf '%s' "$cmd" | grep -Eq -- '--hard'; then
  deny "Blocked: 'git reset --hard' irreversibly discards commits and working changes. Use a softer reset or create a new commit. See ~/.claude/skills/commit/SKILL.md."
fi

# git push --force / -f / --force-with-lease
if has 'git[[:space:]]+push' && printf '%s' "$cmd" | grep -Eq -- '(--force|--force-with-lease|-f([[:space:]]|$))'; then
  deny "Blocked: force-pushing rewrites remote history. Pushes should always fast-forward. See ~/.claude/skills/commit/SKILL.md."
fi

exit 0
