#!/usr/bin/env bash
# Test matrix for block-sensitive-writes.sh
#
# Two invariants with different scopes, which is the thing most likely to rot: secrets
# are denied to EVERY file tool including Read, while generated artifacts are denied
# only to the writing tools. A change that collapses the two would either leak a secret
# to Read or make schema.rb unreadable.
HOOK="${HOOK:-$HOME/.claude/hooks/block-sensitive-writes.sh}"
pass=0; fail=0

check() {                          # check <want> <tool> <path>
  local want="$1" tool="$2" path="$3" out got
  out=$(jq -n --arg t "$tool" --arg p "$path" \
    '{tool_name:$t,tool_input:{file_path:$p}}' | "$HOOK" 2>&1)
  if [ -z "$out" ]; then
    got="pass-through"
  else
    got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
    [ -n "$got" ] || got="ERROR:$out"
  fi
  if [ "$got" = "$want" ]; then
    pass=$((pass+1)); printf '  ok   %-12s %-9s %s\n' "$got" "$tool" "$path"
  else
    fail=$((fail+1)); printf '  FAIL want=%s got=%s  %s :: %s\n' "$want" "$got" "$tool" "$path"
  fi
}

echo "== SECRETS: denied to every file tool, reads included =="
for tool in Read Edit Write MultiEdit; do
  check deny "$tool" '/repo/.env'
done
check deny Read  '/repo/.env.test'
check deny Read  '/repo/.env.production.local'
check deny Write '/repo/config/master.key'
check deny Read  '/repo/config/credentials.yml.enc'
check deny Read  '/repo/config/credentials/production.key'

echo "== NEAR MISSES THAT MUST STAY USABLE =="
check pass-through Read  '/repo/.env.example'
check pass-through Read  '/repo/.env.sample'
check deny         Read  '/repo/.env.example.bak'   # exemption is suffix-anchored
check pass-through Read  '/repo/app/models/environment.rb'
check pass-through Read  '/repo/docs/credentials-howto.md'
check pass-through Edit  '/repo/spec/fixtures/dotenv_spec.rb'

echo "== GENERATED ARTIFACTS: writes denied, reads allowed =="
check deny         Edit  '/repo/db/schema.rb'
check deny         Write '/repo/db/schema.rb'
check deny         Edit  '/repo/app/assets/builds/application.js'
check pass-through Read  '/repo/db/schema.rb'
check pass-through Read  '/repo/app/assets/builds/application.js'

echo "== NOT GENERATED, JUST NEARBY =="
check pass-through Edit  '/repo/db/migrate/20260101_add_column.rb'
check pass-through Edit  '/repo/db/seeds.rb'
check pass-through Edit  '/repo/app/assets/stylesheets/application.css'

echo "== NO PATH, NO OPINION =="
out=$(jq -n '{tool_name:"Bash",tool_input:{command:"cat .env"}}' | "$HOOK" 2>&1)
[ -z "$out" ] && { pass=$((pass+1)); echo "  ok   pass-through Bash      (no file_path; the subagent hook owns shell)"; } \
              || { fail=$((fail+1)); echo "  FAIL judged a call with no file_path"; }

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
