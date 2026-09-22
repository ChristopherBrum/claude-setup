#!/usr/bin/env bash
# Test matrix for restrict-subagent-bash.sh
#
# Three decisions to keep straight: "deny" stops the command, "allow" runs it with no
# prompt, and pass-through (empty output) means the hook abstains so normal prompting
# applies. An allow that should have been a pass-through is the dangerous direction:
# it removes the human from a command nobody vetted.
HOOK="${HOOK:-$HOME/.claude/hooks/restrict-subagent-bash.sh}"
CODE_DIR="${CODE_DIR:-$HOME/Documents}"
CWD="$CODE_DIR/some-repo"
pass=0; fail=0

# check <want> <agent_type|-> <command>   ("-" means main thread: no agent_id)
check() {
  local want="$1" agent="$2" cmd="$3" out got
  if [ "$agent" = "-" ]; then
    out=$(jq -n --arg c "$cmd" --arg w "$CWD" \
      '{tool_input:{command:$c},cwd:$w}' | "$HOOK" 2>&1)
  else
    out=$(jq -n --arg c "$cmd" --arg w "$CWD" --arg a "$agent" \
      '{tool_input:{command:$c},cwd:$w,agent_id:"a1",agent_type:$a}' | "$HOOK" 2>&1)
  fi
  if [ -z "$out" ]; then
    got="pass-through"
  else
    got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
    [ -n "$got" ] || got="ERROR:$out"
  fi
  if [ "$got" = "$want" ]; then
    pass=$((pass+1)); printf '  ok   %-12s %-18s %s\n' "$got" "$agent" "$cmd"
  else
    fail=$((fail+1)); printf '  FAIL want=%s got=%s  %s :: %s\n' "$want" "$got" "$agent" "$cmd"
  fi
}

echo "== MAIN THREAD IS NEVER TOUCHED =="
check pass-through - 'git push origin main'
check pass-through - 'rm -rf node_modules'

echo "== DESTRUCTIVE: denied before the write-agent allow can reach it =="
check deny rails-engineer 'bin/rails db:drop'
check deny rails-engineer 'psql myapp_development -c "TRUNCATE orders"'

echo "== DANGEROUS FOR EVERY SUBAGENT, WRITE AGENTS INCLUDED =="
check deny rails-engineer 'git push'
check deny rails-engineer 'git commit -m "wip"'
check deny frontend-engineer 'yarn add lodash'
check deny rails-engineer 'bundle install'
check deny explorer 'curl https://example.com/data.json'
check deny rails-engineer 'rm -rf tmp/cache'
check deny explorer 'cat .env'
check deny reviewer 'cat config/master.key'

echo "== WRITE AGENTS: everything else runs unprompted =="
check allow rails-engineer 'sed -i "" "s/a/b/" app/models/order.rb'
check allow frontend-engineer 'echo "export const x = 1" > app/javascript/x.ts'
check allow java-engineer './mvnw -q test'
check pass-through rails-engineer 'bin/rails db:rollback'

echo "== READ-ONLY AGENTS: reads allowed, mutation denied =="
check allow reviewer 'cat app/models/order.rb'
check allow explorer 'rg "def call" app/services'
check allow qa-engineer 'bundle exec rspec spec/models/order_spec.rb'
check deny reviewer 'mv app/a.rb app/b.rb'
check deny reviewer 'sed -i "" "s/a/b/" app/models/order.rb'
check deny explorer 'echo broken > app/models/order.rb'
check deny architect 'cp config/a.yml config/b.yml'

echo "== READ-ONLY ESCAPE HATCHES: own notes, /tmp, /dev/null =="
check allow explorer 'echo "trap: counter caches" >> .claude/agent-notes/explorer/NOTES.md'
check allow reviewer 'ls app/models > /dev/null'
check allow qa-engineer 'echo scratch > /tmp/qa-notes.txt'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
