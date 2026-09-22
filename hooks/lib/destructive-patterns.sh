#!/usr/bin/env bash
# Shared destructive-command detection for PreToolUse (Bash) hooks.
#
# Sourced by BOTH block-destructive-commands.sh (which enforces it globally) and
# restrict-subagent-bash.sh (so its write-agent auto-allow can never cover a
# data-destroying command). Kept in one file so the two can't drift apart.
#
#   destructive_reason <cmd> <cwd>
#     Prints a reason and returns 0 when the command destroys something that
#     can't be recovered from git or a rebuild -> caller should DENY.
#   risky_reason <cmd>
#     Prints a reason and returns 0 when the command is recoverable but easy to
#     regret -> caller should ASK.
#
# Best-effort by design: a regex can't fully parse a shell. It fails toward
# deny/ask, never toward silently running something destructive.

_dp_has() { printf '%s' "$1" | grep -Eq "$2"; }
_dp_hasi() { printf '%s' "$1" | grep -Eiq "$2"; }

# Every path a bare, sudo'd, or chained `rm` in the command would delete.
# Runs inside a command substitution, so `set -f` (needed so an unquoted `*`
# target isn't glob-expanded into real filenames) stays contained here.
_dp_rm_targets() {
  set -f
  printf '%s\n' "$1" | tr ';&|()' '\n' | grep -E '(^|[[:space:]])rm[[:space:]]' | while IFS= read -r seg; do
    seg=${seg#*rm }
    for t in $seg; do
      case "$t" in
        -* | *'>'* | *'<'*) continue ;;
      esac
      printf '%s\n' "$t"
    done
  done
}

destructive_reason() {
  cmd="$1"
  cwd="${2:-}"

  # --- Databases -------------------------------------------------------------
  # Rails/rake tasks that drop or reload a database. The test env is exempt: the
  # test DB is disposable and the spec workflow legitimately rebuilds it.
  if _dp_has "$cmd" '(rails|rake)[^;&|]*db:(drop|reset|setup|purge|truncate_all|schema:load|structure:load|migrate:reset|seed:replant)' &&
    ! _dp_has "$cmd" '(RAILS_ENV=test|db:test:)'; then
    printf '%s' "this drops or reloads a database and destroys the local data in it"
    return 0
  fi
  if _dp_has "$cmd" '(^|[^[:alnum:]_])dropdb([[:space:]]|$)'; then
    printf '%s' "'dropdb' deletes an entire PostgreSQL database"
    return 0
  fi
  if _dp_has "$cmd" 'pg_restore' && _dp_has "$cmd" '(--clean|--create|(^|[[:space:]])-c([[:space:]]|$))'; then
    printf '%s' "'pg_restore --clean' drops existing objects before restoring"
    return 0
  fi
  # Raw destructive SQL, but only when something in the command can execute it.
  if _dp_has "$cmd" '(psql|dbconsole|mysql|(rails|rake)[[:space:]]+(runner|r|c|console)|ruby[[:space:]]+-e)' &&
    _dp_hasi "$cmd" '(drop[[:space:]]+(database|schema|table)|truncate[[:space:]]|delete[[:space:]]+from)'; then
    printf '%s' "this executes destructive SQL (DROP / TRUNCATE / DELETE FROM)"
    return 0
  fi
  # Mass ActiveRecord destruction through a runner or console.
  if _dp_has "$cmd" '((rails|rake)[[:space:]]+(runner|r|c|console)|ruby[[:space:]]+-e)' &&
    _dp_has "$cmd" '\.(destroy_all|delete_all)([^[:alnum:]_]|$)'; then
    printf '%s' "this mass-deletes records via destroy_all/delete_all"
    return 0
  fi
  if _dp_hasi "$cmd" '(flushall|flushdb)'; then
    printf '%s' "flushing Redis wipes the cache and every queued Sidekiq job"
    return 0
  fi

  # --- Production / remote infrastructure ------------------------------------
  if _dp_has "$cmd" 'RAILS_ENV=(production|staging)'; then
    printf '%s' "this runs against a deployed environment, not local development"
    return 0
  fi
  if _dp_has "$cmd" '(^|[^[:alnum:]_])heroku[[:space:]]' &&
    _dp_has "$cmd" '(pg:(reset|psql|copy|upgrade|backups:restore)|run[[:space:]:]|apps:destroy|addons:(destroy|detach)|config:(set|unset)|ps:(scale|stop|restart)|releases:rollback|maintenance)'; then
    printf '%s' "this mutates a Heroku app or its database"
    return 0
  fi
  if _dp_has "$cmd" '(terraform[[:space:]]+destroy|kubectl[[:space:]]+delete|aws[[:space:]]+(s3[[:space:]]+(rm|rb)|rds[[:space:]]+delete)|gcloud[[:space:]]+[a-z-]+[[:space:]]+delete)'; then
    printf '%s' "this deletes cloud infrastructure"
    return 0
  fi

  # --- Whole-machine hazards -------------------------------------------------
  if _dp_has "$cmd" '(^|[[:space:]]|[;&|])sudo([[:space:]]|$)'; then
    printf '%s' "'sudo' escalates to root, which nothing in this session needs"
    return 0
  fi
  if _dp_has "$cmd" '(mkfs|diskutil[[:space:]]+(erase|reformat|partition)|dd[[:space:]]+[^;&|]*of=/dev/|chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/([[:space:]]|$)|:\(\)[[:space:]]*\{)'; then
    printf '%s' "this can damage the filesystem or the machine"
    return 0
  fi

  # --- Local work that git can't get back ------------------------------------
  if _dp_has "$cmd" 'git[[:space:]]+clean[^;&|]*-[a-zA-Z]*[fdx]'; then
    printf '%s' "'git clean' deletes untracked files, which are not in git and cannot be restored"
    return 0
  fi
  if _dp_has "$cmd" 'git[[:space:]]+(checkout|restore)[^;&|]*([[:space:]]|--[[:space:]]+)(\.|\*)([[:space:]]|$)' ||
    _dp_has "$cmd" 'git[[:space:]]+checkout[[:space:]]+(-f|--force)'; then
    printf '%s' "this discards every uncommitted change in the working tree"
    return 0
  fi
  if _dp_has "$cmd" 'git[[:space:]]+stash[[:space:]]+(drop|clear)'; then
    printf '%s' "this permanently deletes stashed work"
    return 0
  fi

  # --- Clobbering secrets or generated config via shell redirection ----------
  if _dp_has "$cmd" '>[[:space:]]*[^[:space:];&|]*(\.env|config/master\.key|config/credentials|config/database\.yml|db/schema\.rb)'; then
    printf '%s' "this overwrites a secrets or generated-config file that isn't reproducible"
    return 0
  fi

  # --- rm with a dangerous target -------------------------------------------
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    tn=$t
    [ "$tn" = "/" ] || tn=${tn%/}
    case "$tn" in
    '~' | '~/'* | '$HOME'* | '${HOME}'* | "$HOME")
      printf '%s' "'rm' targets your home directory ($t)"
      return 0
      ;;
    . | .. | '*' | '.*' | './*' | '../'* | */..)
      printf '%s' "'rm' targets the current or parent directory ($t)"
      return 0
      ;;
    *'/..'* | '..'/*)
      printf '%s' "'rm' escapes the working directory via '..' ($t)"
      return 0
      ;;
    .git | ./.git | */.git | */.git/*)
      printf '%s' "'rm' targets the .git directory, which holds all of your history ($t)"
      return 0
      ;;
    app | spec | config | db | lib | bin | gems | public | vendor | docs | .claude | app/* | db/migrate)
      case "$tn" in
      app/assets/builds*) ;; # rebuildable, and CLAUDE.md documents clearing it
      *)
        printf '%s' "'rm' targets a top-level source directory ($t)"
        return 0
        ;;
      esac
      ;;
    /tmp/* | /private/tmp/* | /var/folders/* | /dev/null) ;; # scratch space, fine to delete
    /*)
      if [ -z "$cwd" ]; then
        printf '%s' "'rm' targets an absolute path ($t) and the working directory is unknown"
        return 0
      fi
      case "$tn" in
      "$cwd")
        printf '%s' "'rm' targets the repository root ($t)"
        return 0
        ;;
      "$cwd"/*) ;; # inside the working directory, leave it to normal permissions
      *)
        printf '%s' "'rm' targets an absolute path outside the working directory ($t)"
        return 0
        ;;
      esac
      ;;
    esac
  done <<RM_TARGETS
$(_dp_rm_targets "$cmd")
RM_TARGETS

  return 1
}

risky_reason() {
  cmd="$1"

  if _dp_has "$cmd" '(rails|rake)[^;&|]*db:rollback' && ! _dp_has "$cmd" '(RAILS_ENV=test|db:test:)'; then
    printf '%s' "rolling back a migration can drop columns or tables and lose their data"
    return 0
  fi
  if _dp_has "$cmd" 'find[^;&|]*(-delete|-exec[[:space:]]+rm)'; then
    printf '%s' "'find -delete' / 'find -exec rm' deletes every match, and the match set isn't visible up front"
    return 0
  fi
  if _dp_has "$cmd" 'xargs[^;&|]*rm([[:space:]]|$)'; then
    printf '%s' "'xargs rm' deletes whatever the upstream command emitted"
    return 0
  fi
  if _dp_has "$cmd" 'git[[:space:]]+branch[[:space:]]+-[Dd]'; then
    printf '%s' "deleting a branch can orphan commits that were never pushed"
    return 0
  fi
  if _dp_has "$cmd" 'git[[:space:]]+(gc[^;&|]*--prune|reflog[[:space:]]+expire|worktree[[:space:]]+remove|update-ref[[:space:]]+-d)'; then
    printf '%s' "this prunes git's safety net, which is what recovers lost commits"
    return 0
  fi
  if _dp_has "$cmd" '\.update_all([^[:alnum:]_]|$)'; then
    printf '%s' "'update_all' rewrites every matching row with no callbacks or validations"
    return 0
  fi
  if _dp_has "$cmd" '(^|[^[:alnum:]_])(pkill|killall)([[:space:]]|$)'; then
    printf '%s' "this kills processes by name and may take down more than intended"
    return 0
  fi
  if _dp_has "$cmd" '(^|[^[:alnum:]_])truncate[[:space:]]+(-s|--size)'; then
    printf '%s' "'truncate' empties a file in place"
    return 0
  fi

  return 1
}
