#!/usr/bin/env bash
# Test matrix for block-publish-leak.sh
#
# Builds a throwaway repo and identity.json in $TMPDIR, so the test never depends on
# the real employer values and never reads them.
HOOK="$HOME/.claude/hooks/block-publish-leak.sh"
pass=0; fail=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/.claude"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name Test

cat > "$REPO/identity.json" <<'JSON'
{"issue_tracker":{"host":"acme.atlassian.net","project_key":"XYZ"},
 "git":{"owner":"acme","branch_prefix":"tt-xyz"}}
JSON

# identity.json is gitignored in the real repo, so it is never at HEAD. Committing it here
# would make every case deny on the identity file itself rather than on the content tested.
printf 'identity.json\n' > "$REPO/.gitignore"

commit() { printf '%s\n' "$2" > "$REPO/$1"; git -C "$REPO" add -A; git -C "$REPO" commit -qm t; }

check() {
  local want="$1" desc="$2" out got
  out=$(jq -n --arg c "git push -u origin main" --arg w "$REPO" \
    '{tool_input:{command:$c},cwd:$w}' | HOME="$TMP" "$HOOK" 2>&1)
  if [ -z "$out" ]; then
    got="pass-through"
  else
    got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
    [ -n "$got" ] || got="ERROR:$out"
  fi
  if [ "$got" = "$want" ]; then
    pass=$((pass+1)); printf '  ok   %-12s %s\n' "$got" "$desc"
  else
    fail=$((fail+1)); printf '  FAIL want=%s got=%s :: %s\n' "$want" "$got" "$desc"
  fi
}

echo "== MUST DENY =="
commit notes.md 'Disabled in acme-web because of the plugin weight'
check deny "org name in a doc"
commit notes.md 'fetch XYZ-1234 from the tracker'
check deny "ticket key reference"
commit notes.md 'branch follows tt-xyz-<number>'
check deny "branch prefix"

echo "== MUST PASS THROUGH =="
commit notes.md 'The length of this string is unremarkable. See PROJECT.md.'
check pass-through "short key inside an unrelated word (length)"
commit notes.md 'Fetch <issue_tracker.project_key>-<number> via the MCP server.'
check pass-through "genericised placeholders"

# A non-push git command, and a push from any other repo, are none of this hook's business.
out=$(jq -n --arg c "git status" --arg w "$REPO" '{tool_input:{command:$c},cwd:$w}' | HOME="$TMP" "$HOOK")
[ -z "$out" ] && { pass=$((pass+1)); echo "  ok   pass-through non-push command"; } \
              || { fail=$((fail+1)); echo "  FAIL non-push command was judged"; }

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
