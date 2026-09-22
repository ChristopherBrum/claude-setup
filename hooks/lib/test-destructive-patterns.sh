#!/usr/bin/env bash
# Test matrix for block-destructive-commands.sh
HOOK="$HOME/.claude/hooks/block-destructive-commands.sh"
# Any repo path works; the hook cares about the shape of the command, not which repo.
CODE_DIR="${CODE_DIR:-$HOME/Documents}"
CWD="$CODE_DIR/some-repo"
pass=0; fail=0

check() {
  local want="$1" cmd="$2"
  local out got
  out=$(jq -n --arg c "$cmd" --arg w "$CWD" '{tool_input:{command:$c},cwd:$w}' | "$HOOK" 2>&1)
  if [ -z "$out" ]; then
    got="pass-through"
  else
    got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null) || got="ERROR:$out"
    [ -n "$got" ] || got="ERROR:$out"
  fi
  if [ "$got" = "$want" ]; then
    pass=$((pass+1)); printf '  ok   %-6s %s\n' "$got" "$cmd"
  else
    fail=$((fail+1)); printf '  FAIL want=%s got=%s :: %s\n' "$want" "$got" "$cmd"
  fi
}

echo "== MUST DENY =="
check deny 'bundle exec rails db:drop'
check deny 'bin/rails db:setup'
check deny 'bin/rails db:schema:load'
check deny 'rails db:reset'
check deny 'bundle exec rake db:migrate:reset'
check deny 'rails db:seed:replant'
check deny 'dropdb myapp_development'
check deny 'psql -d myapp_development -c "DROP TABLE orders"'
check deny 'psql myapp_development -c "truncate table orders cascade"'
check deny 'bin/rails runner "Order.where(id: 1).delete_all"'
check deny 'bin/rails runner "Order.destroy_all"'
check deny 'redis-cli FLUSHALL'
check deny 'redis-cli flushdb'
check deny 'RAILS_ENV=production bundle exec rails db:migrate'
check deny 'heroku run rails console -a myapp'
check deny 'heroku pg:reset DATABASE -a myapp'
check deny 'terraform destroy'
check deny 'kubectl delete pod foo'
check deny 'sudo rm /etc/hosts'
check deny 'rm -rf /'
check deny 'rm -rf ~'
check deny 'rm -rf ~/Documents'
check deny 'rm -rf $HOME/.claude'
check deny 'rm -rf .'
check deny 'rm -rf *'
check deny 'rm -rf ./*'
check deny 'rm -rf ../sibling-repo'
check deny 'rm -rf .git'
check deny "rm -rf $CWD"
check deny "rm -rf $CODE_DIR/other-repo"
check deny 'rm -rf app'
check deny 'rm -rf spec'
check deny 'rm -rf app/models'
check deny 'yarn build && rm -rf /tmp/../etc'
check deny 'git clean -fdx'
check deny 'git clean -fd'
check deny 'git checkout .'
check deny 'git checkout -- .'
check deny 'git restore .'
check deny 'git checkout -f master'
check deny 'git stash clear'
check deny 'git stash drop stash@{0}'
check deny 'echo x > .env'
check deny 'cat foo > config/database.yml'
check deny 'mkfs.ext4 /dev/disk2'
check deny 'dd if=/dev/zero of=/dev/disk2'

echo "== MUST ASK =="
check ask 'bundle exec rails db:rollback'
check ask 'find tmp -name "*.log" -delete'
check ask 'find . -name "*.tmp" -exec rm {} \;'
check ask 'git ls-files | xargs rm'
check ask 'git branch -D old-branch'
check ask 'git gc --prune=now'
check ask 'git reflog expire --expire=now --all'
check ask 'bin/rails runner "Order.update_all(status: 1)"'
check ask 'pkill -9 postgres'
check ask 'truncate -s 0 log/development.log'

echo "== MUST PASS THROUGH (normal work) =="
check pass-through 'bundle exec rspec spec/models/order_spec.rb'
check pass-through 'RAILS_ENV=test bundle exec rails db:reset'
check pass-through 'RAILS_ENV=test bundle exec rails db:drop db:create db:schema:load'
check pass-through 'bin/rails db:test:prepare'
check pass-through 'bundle exec rails db:migrate'
check pass-through 'bundle exec rails db:create'
check pass-through 'git status --short'
check pass-through 'git add -A && git commit -m "feat: thing"'
check pass-through 'git checkout -b xx-abc-1450-foo'
check pass-through 'git checkout master'
check pass-through 'git stash list'
check pass-through 'git diff origin/master --name-only'
check pass-through 'rm -rf app/assets/builds/*'
check pass-through 'rm -rf node_modules && yarn install'
check pass-through 'rm -rf spec/fixtures/vcr_cassettes/christopher/'
check pass-through 'rm /tmp/scratch.txt'
check pass-through 'yarn build:css'
check pass-through 'bundle exec rubocop -a app/models/order.rb'
check pass-through 'grep -rn "db:reset" docs/'
check pass-through 'bin/rails runner "puts Order.count"'
check pass-through 'psql -c "select count(*) from orders" myapp_development'
check pass-through 'gh pr view 123'
check pass-through 'bin/rails db:rollback RAILS_ENV=test'

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
