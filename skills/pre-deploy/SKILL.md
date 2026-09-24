---
name: pre-deploy
description: Turn a release range into a deploy checklist: pre-deploy gates with owners, a risk table ranked by blast radius with what to watch and when to act, and any post-deploy action. Use before cutting a release or deploying to production, when asked what is going out, whether it is safe to deploy, or to check the release diff.
argument-hint: [<from-tag-or-sha>..<to-ref>]
---

# Pre-Deploy

`/pre-pr` asks whether one branch is correct. This asks a different question: **given everything
merged since the last release, what breaks when it ships, and what has to be true before it
does.** Every PR in the range already passed review. What is left is the batch, the ordering, and
the things that are not in the diff at all.

Read-only. It never deploys, tags, pushes, or edits anything outside its own output doc.

## Input

`<from>..<to>`, if given. Otherwise `<from>` is the latest release and `<to>` is the base branch:

```bash
BASE="origin/$(jq -r .git.default_base ~/.claude/identity.json)"
FROM=$(gh release view --json tagName -q .tagName 2>/dev/null) \
  || FROM=$(git tag -l 'v*' | sort -V | tail -1)
```

`.claude/PROJECT.md` overrides this when it names how the project defines a deploy.

## 1. Resolve the range

```bash
git fetch -q origin
git log --oneline "$FROM..$BASE"
git diff --stat "$FROM..$BASE" | tail -1
```

Squash merges are the norm, so one commit per PR and the subject carries `(#NNNN)`. Map each PR
to its ticket: `gh pr view NNNN --json title,body,headRefName`, then fetch the key through the MCP
server named in `~/.claude/identity.json`. **If the range is empty, say so and stop.**

## 2. Extract the facts

Delegate this to `explorer` with the range and the list below. It returns facts, not prose, and it
keeps a wide `git diff` out of the main window.

- **Migrations** — `db/migrate`. For each: reversible, lock duration, backfill needed, and whether
  the currently-released code survives it.
- **Data and maintenance tasks** — anything meant to run once, and whether before or after.
- **Config and env** — `config`, `.env.example`. New keys have to exist before the first request.
- **Feature flags** — grep each touched flag's name across `app/` and `config/` for its *current
  default*. Never infer the default from a PR title.
- **API surface** — routes, GraphQL, serializers, `swagger/`. The consumers you do not deploy
  (mobile, partner integrations, an embedded or cached frontend) do not update with you.
- **Background jobs** — added or changed. An argument change while old-shaped jobs sit enqueued
  means both shapes must work.
- **Silent-by-design changes.** Anything that removes, no-ops, or re-gates error reporting,
  logging, or an alert path. A clean migration diff does not mean a clean release, and a
  zero-exception graph on the day reporting was gated off is a failure signal, not a win.
- **Removed guards** in webhook or job entry points: a deleted `unless`/`return` is a behavior
  change even when its replacement is meant to be safe.
- **Infra-dependent primitives** — advisory locks, session variables, prepared statements. These
  assume something about production pooling. That assumption is a gate, not a footnote.

## 3. Read every PR body for deploy caveats

```bash
gh pr view NNNN --json body
```

**The diff never shows these.** A webhook subscription to add, an env var to set, a dashboard
toggle, a value that must already be live. Each one becomes a gate row with a named owner. This
step finds the gates that nothing else in this skill would catch.

## 4. Rank by blast radius, and check the fact that would downgrade it

Order by likelihood × impact, never by PR number or diff size. **For every High row, name the one
fact that would drop it a level, then go verify that fact before finalising the row.** A risk you
did not try to talk yourself out of is not ranked, it is guessed.

## 5. Baseline, before anything ships

Record the current open and in-progress incident count through the AppSignal MCP, and print both
`date` and `date -u`. AppSignal renders every timestamp in UTC; a comparison anchored on local
time reads clean when it is not.

## 6. Output

Write `docs/plans/deploy-checklist-<YYYY-MM-DD>-<from>-to-<to>.md`. Confirm the path is untracked
(`git check-ignore -q` or an existing convention) and never `git add` it.

```markdown
# Deploy Checklist — <from> → <to> (<date>)

<N> PRs. <N> migration(s). Compare: <compare URL>

## Pre-deploy gates

| # | Check | Owner | Why |
|---|---|---|---|

**Migration:** <the statement, and why it is or is not safe: rewrite, lock, backfill>

## Post-deploy watch (ranked by blast radius)

| # | PR | Risk | Watch | Act if |
|---|---|---|---|---|

## Post-deploy action: <name>

<precondition that must hold first, params anchored on the deploy marker time rather than
merge time, expected runtime, and the before/after query>

## Notes

<behavior changes a reader would otherwise mistake for noise, and anything QA cannot reach>
```

Every PR number is a markdown link. Rows are one line each. A `None` risk row (docs, config,
`.claude/`) still gets a row, so the reader can see it was considered and dismissed.

Then, in chat, **at most 10 lines**: the range and ticket count, the top three risks one line
each, gate status (clear, or blocked on what), and anything that cannot be rolled back.

## Rules

- **Verify before flagging.** Read the migration, the job, the caller. A false blocker delays a
  release, which is expensive in the other direction.
- **Do not re-review what review already covered.** Style, naming, coverage, ordinary correctness.
  Out of scope unless the batch makes them dangerous.
- **Do not invent repo paths.** Confirm with `git diff --name-only` before citing one.
- **Anchor every timing instruction on the deploy marker**, never merge time. The gap between
  merge and deploy is hours, and a task run `until` merge time double-applies work the live code
  already did.
- **Late merges.** Record the last-checked SHA. On "more merged", diff `<last-sha>..$BASE` only,
  run steps 2 to 4 on the new commits, and merge the rows into the existing doc. Report the real
  new-commit count when it differs from what was expected.
- **Say when it is clean.** A release with nothing to gate is the normal case and its doc is short.
