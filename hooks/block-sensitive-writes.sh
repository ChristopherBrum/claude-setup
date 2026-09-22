#!/usr/bin/env bash
# PreToolUse (Read|Edit|Write) guard: block access to secrets and edits to
# generated files.
#
# Rationale: this is the security floor for the whole setup (and especially the
# write-capable agents). Two deterministic invariants:
#   1. Never read OR write secret/credential files (.env*, config/master.key,
#      config/credentials*). Secrets are fetched at runtime via Secret.fetch, never
#      read through the assistant. (CLAUDE.md rule.)
#   2. Never EDIT generated artifacts (db/schema.rb, app/assets/builds/*) — those are
#      produced by migrations / the asset build, and hand-edits are always a mistake.
#
# Scope is intentionally narrow: it does NOT touch normal Bash (git push, yarn add,
# curl, etc. stay usable on the main thread). Destructive/network protection for the
# write agents comes from their least-privilege tools + worktree isolation, not here.
#
# Emits a PreToolUse "deny" decision (JSON on stdout) on a match; else exits 0 (allow).
set -euo pipefail

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
[ -z "$path" ] && exit 0

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

matches() { printf '%s' "$path" | grep -Eq "$1"; }

# 1. Secrets/credentials — deny for ANY file tool (Read, Edit, Write).
#
# `.env.example` and its siblings are the documented shape of the env, carry no values,
# and are committed. Denying them blocks the legitimate "which vars does this project
# need" read with no secret at stake, so they are exempt by suffix.
if matches '(^|/)\.env($|\.)' && ! matches '\.(example|sample|template|dist)$'; then
  deny "Blocked: '$path' is a secret/credential file. Do not read or write it through the assistant. Fetch secrets at runtime via Secret.fetch (see CLAUDE.md)."
fi
if matches '(^|/)config/master\.key$' \
  || matches '(^|/)config/credentials([/.][^/]*)*$'; then
  deny "Blocked: '$path' is a secret/credential file. Do not read or write it through the assistant. Fetch secrets at runtime via Secret.fetch (see CLAUDE.md)."
fi

# 2. Generated files — deny only for edits (Edit/Write), not reads.
case "$tool" in
  Edit|Write|MultiEdit)
    if matches '(^|/)db/schema\.rb$' \
      || matches '(^|/)app/assets/builds/'; then
      deny "Blocked: '$path' is a generated artifact. Regenerate it via a migration (schema.rb) or the asset build (app/assets/builds) rather than editing it by hand."
    fi
    ;;
esac

exit 0
