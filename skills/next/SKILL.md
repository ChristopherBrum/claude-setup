---
name: next
description: Answer "what should I work on now" with a ranked list of what is actually outstanding across the tracker, open PRs, and the local checkout. Use when asked what is next, what else there is to do, what is outstanding, where things stand, or what is left before this branch ships.
argument-hint: [optional: a repo, or "setup" to rank setup work instead of product work]
---

# Next

Answer the question from durable state, never from what happens to be in this conversation.
Rebuilding the list from memory is how the same item gets raised three times in a day and a
finished one gets raised again.

## Input

Nothing, normally: rank across the tracker, open PRs, and the current checkout. Given `setup`,
rank work on this Claude setup instead, from the worklogs and the open items this guide records.

## 1. Gather, in parallel

Read `~/.claude/identity.json` first for the tracker host, project key, and default base. Resolve
the repo with `gh repo view --json nameWithOwner`; never hardcode a slug.

```bash
git status --short                                  # uncommitted work
git log --oneline @{u}..HEAD 2>/dev/null            # committed, unpushed
gh pr list --author @me --state open --json number,title,reviewDecision,statusCheckRollup,url
gh pr list --search "review-requested:@me" --state open --json number,title,author,url
```

For the tracker, query issues assigned to me that are not done, through the MCP server named in
`identity.json`. Reads run unprompted; this skill never writes to the tracker.

For `setup`: read the newest file in `~/.claude/worklogs/` and take its **Still open** section,
plus anything `HOW-TO.md` marks unproven or unverified.

## 2. Rank

Sort by who is blocked, not by what is interesting:

1. **Blocking someone else.** A PR awaiting my review, or a comment thread waiting on my reply.
2. **Blocked on me, mine.** My PR with changes requested, failing CI, or unaddressed comments.
3. **In flight.** Uncommitted or unpushed work in this checkout. Name the branch and its ticket.
4. **Ready to start.** An assigned ticket that nothing depends on yet.
5. **Deferred.** Anything raised before and consciously postponed. Include it only if the reason
   it was postponed no longer holds, and say what changed.

Within a tier, oldest first. Age is the signal that something is being avoided.

## 3. Output

**Five items maximum, one line each, most blocking first.** Each line: what it is, why it is at
that rank, and the one command or skill that starts it.

```
1. PR #18971 has 3 unanswered review comments from Tuesday   → /comments 18971
2. ENG-1450 is In Progress with nothing pushed for 4 days    → /ticket-plan 1450
3. 2 PRs awaiting your review                                → /review-queue
```

Then stop. Do not summarise the list, do not explain the ranking, and do not ask which one to
start. The reader picks one and says so.

## Rules

- **Say when there is nothing.** "Nothing is blocking and nothing is assigned" is a valid and
  useful answer. Never pad the list to five.
- **Every item cites its evidence**: a PR number, a ticket key, a branch, a file count. An item
  that cannot be traced to one of the sources above does not belong on the list.
- **Never invent a deadline or a priority the tracker does not carry.** Rank by blocking, and if
  two items tie, say they tie.
- **A finished item is not "next".** Check `gh pr list --head <branch>` before calling branch work
  outstanding: squash merges mean git ancestry reports merged branches as unfinished.
