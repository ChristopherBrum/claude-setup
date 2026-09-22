#!/usr/bin/env bash
# Test matrix for block-git-history-rewrite.sh
#
# The rule is append-only history. The interesting cases are the recovery flags, which
# must stay usable: a hook that blocks `git rebase --abort` strands the user mid-rebase
# with the one command that would get them out.
HOOK="${HOOK:-$HOME/.claude/hooks/block-git-history-rewrite.sh}"
pass=0; fail=0

check() {
  local want="$1" cmd="$2" out got
  out=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | "$HOOK" 2>&1)
  if [ -z "$out" ]; then
    got="pass-through"
  else
    got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
    [ -n "$got" ] || got="ERROR:$out"
  fi
  if [ "$got" = "$want" ]; then
    pass=$((pass+1)); printf '  ok   %-12s %s\n' "$got" "$cmd"
  else
    fail=$((fail+1)); printf '  FAIL want=%s got=%s :: %s\n' "$want" "$got" "$cmd"
  fi
}

echo "== MUST DENY =="
check deny 'git commit --amend'
check deny 'git commit --amend --no-edit'
check deny 'git rebase origin/master'
check deny 'git rebase -i HEAD~3'
check deny 'git reset --hard HEAD~1'
check deny 'git push --force origin main'
check deny 'git push --force-with-lease'
check deny 'git push -f'

echo "== RECOVERY FLAGS MUST STAY USABLE =="
check pass-through 'git rebase --abort'
check pass-through 'git rebase --continue'
check pass-through 'git rebase --skip'
check pass-through 'git rebase --quit'

echo "== ORDINARY GIT IS UNTOUCHED =="
check pass-through 'git commit -m "a new commit"'
check pass-through 'git push origin main'
check pass-through 'git push -u origin main'
check pass-through 'git reset HEAD~1'
check pass-through 'git status'
check pass-through 'git log --oneline -5'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
