#!/usr/bin/env bash
# Regression matrix for agent_clone_boundary.rb.
#
# Run after ANY change to the boundary hook:
#   bash ~/.claude/hooks/lib/test-clone-boundary.sh
#
# The hook is the only thing keeping a subagent out of a neighbouring checkout, so it gets
# must-deny, must-allow, and must-never-block-on-garbage cases, all asserted.
#
# Fixtures are throwaway directories containing a bare `.git` marker, because the hook
# locates a checkout by walking up for `.git` and never runs git itself. That keeps this
# suite portable: no assumptions about which repos exist on the machine.
set -uo pipefail

HOOK="ruby ${HOME}/.claude/hooks/agent_clone_boundary.rb"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
A="$TMP/repo-a"
B="$TMP/repo-b"
mkdir -p "$A/.git" "$A/app" "$B/.git" "$B/app" "$TMP/not-a-repo"

pass=0; fail=0

t() { # t <label> <ALLOW|DENY> <json> [env-prefix]
  local out got
  out=$(printf '%s' "$3" | eval "${4:-} $HOOK" 2>&1)
  if printf '%s' "$out" | grep -q '"deny"'; then got=DENY; else got=ALLOW; fi
  if [ "$got" = "$2" ]; then
    printf '  PASS  %-58s %s\n' "$1" "$got"; pass=$((pass+1))
  else
    printf '  FAIL  %-58s got=%s want=%s\n' "$1" "$got" "$2"; fail=$((fail+1))
  fi
}

w() { # w <cwd> <file_path> [agent_type]
  printf '{"tool_name":"Write","agent_type":"%s","cwd":"%s","tool_input":{"file_path":"%s"}}' \
    "${3:-rails-engineer}" "$1" "$2"
}
b() { # b <cwd> <command> [agent_type]
  printf '{"tool_name":"Bash","agent_type":"%s","cwd":"%s","tool_input":{"command":"%s"}}' \
    "${3:-rails-engineer}" "$1" "$2"
}

echo "WRITE confinement"
t "subagent writes in own checkout"       ALLOW "$(w "$A" "$A/app/x.rb")"
t "absolute write into sibling checkout"  DENY  "$(w "$A" "$B/app/x.rb")"
t "relative ../ escape into sibling"      DENY  "$(w "$A" "../repo-b/app/x.rb")"
t "relative path inside own checkout"     ALLOW "$(w "$A" "app/x.rb")"
t "write from a subdirectory of own repo" ALLOW "$(w "$A/app" "x.rb")"
t "write to a path in no checkout at all" DENY  "$(w "$A" "$TMP/not-a-repo/x.rb")"

echo "SHARED_WRITABLE carve-outs"
t "per-project layer (agent notes)"       ALLOW "$(w "$A" "$HOME/.claude/repos/p/agent-notes/reviewer/x.md")"
t "per-project memory"                    ALLOW "$(w "$A" "$HOME/.claude/projects/-slug/memory/x.md")"
t "scratch"                               ALLOW "$(w "$A" "$HOME/.claude/scratch/x.md")"
t "tmp"                                   ALLOW "$(w "$A" "/tmp/x.md")"
t "NOT the rest of ~/.claude"             DENY  "$(w "$A" "$HOME/.claude/settings.json")"

echo "read-only agents"
t "reviewer may not Write"                DENY  "$(w "$A" "$A/app/x.rb" reviewer)"
t "explorer may not Write"                DENY  "$(w "$A" "$A/app/x.rb" explorer)"
t "architect may not Write"               DENY  "$(w "$A" "$A/app/x.rb" architect)"
t "qa-engineer may not Write"             DENY  "$(w "$A" "$A/app/x.rb" qa-engineer)"
t "reviewer may still run Bash"           ALLOW "$(b "$A" "bundle exec rspec" reviewer)"

echo "BASH confinement"
t "relative command in own cwd"           ALLOW "$(b "$A" "bundle exec rspec spec/x_spec.rb")"
t "absolute path into own checkout"       ALLOW "$(b "$A" "cat $A/app/x.rb")"
t "absolute path into sibling checkout"   DENY  "$(b "$A" "cat $B/app/x.rb")"
t "git -C into sibling checkout"          DENY  "$(b "$A" "git -C $B status")"
t "path under home that is not a repo"    ALLOW "$(b "$A" "cat $TMP/not-a-repo/notes.txt")"
t "peer read via remote name"             ALLOW "$(b "$A" "git fetch peer && git show peer/main:app/x.rb")"

echo "top-level sessions are untouched"
t "no agent_type writes into sibling"     ALLOW '{"tool_name":"Write","cwd":"'"$A"'","tool_input":{"file_path":"'"$B"'/app/x.rb"}}'
t "no agent_type bash into sibling"       ALLOW '{"tool_name":"Bash","cwd":"'"$A"'","tool_input":{"command":"cat '"$B"'/app/x.rb"}}'
t "cwd outside any checkout"              ALLOW "$(w "$TMP/not-a-repo" "$B/app/x.rb")"

echo "sibling_repos opt-in (identity.json)"
FAKE="$TMP/fakehome"
mkdir -p "$FAKE/.claude"
printf '{"code_dir":"%s","git":{"sibling_repos":["repo-b"]}}' "$TMP" > "$FAKE/.claude/identity.json"
t "sibling allowed when configured"       ALLOW "$(w "$A" "$B/app/x.rb")" "HOME=$FAKE"
printf '{"code_dir":"%s","git":{}}' "$TMP" > "$FAKE/.claude/identity.json"
t "sibling denied when not configured"    DENY  "$(w "$A" "$B/app/x.rb")" "HOME=$FAKE"
printf 'not json at all' > "$FAKE/.claude/identity.json"
t "malformed identity does not block own" ALLOW "$(w "$A" "$A/app/x.rb")" "HOME=$FAKE"

echo "SAFETY (must never block)"
t "malformed json"                        ALLOW 'not json at all'
t "empty file_path"                       ALLOW "$(w "$A" "")"
t "no cwd at all"                         ALLOW '{"tool_name":"Write","agent_type":"rails-engineer","tool_input":{"file_path":"/x.rb"}}'
t "unknown tool"                          ALLOW '{"tool_name":"WebFetch","agent_type":"rails-engineer","cwd":"'"$A"'","tool_input":{}}'

echo
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
