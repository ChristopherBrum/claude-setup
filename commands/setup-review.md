# Setup Review — find drift between what my config claims and what I actually use

Audit this Claude setup against real usage and propose specific changes. The output is a ranked
list of edits, not a diary.

## Input

$ARGUMENTS — Optional: a focus area (`agents`, `commands`, `permissions`, `docs`), or a repo name.
Default: everything.

## Step 1 — Gather the facts

```bash
~/.claude/bin/claude-usage               # what ran: delegations, commands, declared vs used
~/.claude/bin/claude-prompts --summary   # what I asked for: imperatives, corrections
~/.claude/bin/claude-prompts --questions # what was asked that only earned a one-word reply
cat ~/.claude/worklogs/*.md 2>/dev/null  # per-session findings, if /worklog has been run
```

Those are the only sources of usage numbers. **Do not estimate usage from memory of this
conversation** — you see one session, the scripts read every one in the window.

The two scripts answer different questions and you need both. `claude-usage` shows what the setup
*did*; `claude-prompts` shows what I *asked for*, which is where a missing command shows up. A
repeated short imperative with no command behind it is the highest-value finding available here.
A correction that repeats across sessions is the second.

Two traps it warns about, and you must carry both into the report:

- **The window is a rolling ~30 days.** `cleanupPeriodDays` is unset, so the harness default
  applies and older transcripts are already deleted. `0 uses` means "unused in this window",
  never "never used". Say the date range in the report.
- **A transcript's project directory is fixed at session launch; `cwd` is not.** Agent discovery
  follows `cwd`. So a repo-scoped agent is only reachable when `cwd` is inside that repo, and the
  `scoped` vs `total` columns exist to show that gap. A high `total` with `scoped: 0` means the
  agent is defined where the work never happens.

## Step 2 — Read what the config claims

```bash
ls ~/.claude/agents/ ~/.claude/repos/*/agents/ ~/.claude/commands/ 2>/dev/null
grep -n "uses)" ~/.claude/HOW-TO.md
```

Also skim `~/.claude/CLAUDE.md` for stated policy, and each repo's
`~/.claude/repos/<repo>/settings.local.json`.

## Step 3 — Find the drift

Look for these five things, in this order. The first two are the ones that actually cost money.

1. **Defined where the work isn't.** An agent or command whose `scoped` count is 0 while its
   `total` is high. This is a reachability bug, not disuse: it means the definition sits in a repo
   you never launch or `cd` into. Propose either moving it or changing how sessions start.
2. **Permissions that contradict stated policy.** Cross-read every `settings.local.json` allow
   list against `~/.claude/CLAUDE.md`. An allow rule that auto-approves something the policy says
   to ask about is a silent hole. Known shape: a broad prefix like `Bash(gh pr:*)` swallowing
   `gh pr create`, or an MCP write tool allowlisted when the policy says writes get confirmed.
3. **Documentation that states a number.** `HOW-TO.md` carries usage counts in its agent table.
   Compare each against the script. A stale count is worse than none, because it gets trusted.
4. **Dead weight.** Zero-use agents and commands, orphaned agent-notes directories, archived
   agents still referenced from live files, duplicate permission entries across scopes.
5. **Missing coverage.** A short imperative that repeats in `claude-prompts --summary` with no
   command behind it. Check whether one already exists first: a command that exists and is not
   used is a naming or discoverability problem, and the fix is different.
6. **Repeated corrections.** Cluster the corrections by topic. A theme that recurs across
   sessions means a rule is missing, too vague, or living in the wrong file. Name the file it
   belongs in. This is a finding about the setup, not about the model, and it should be reported
   without softening.
7. **Questions that earned only a one-word reply.** From `--questions`. Separate the two causes,
   because the fixes differ: a question about work already authorized (stop asking), versus a
   question re-asked at each step of an approved sequence (stop re-asking). Count each. The raw
   share of bare approvals on its own is not a finding; what was *asked* is.

## Step 4 — Report

**A finding is a change you would actually make.** Everything else is data, and data goes at the
bottom or nowhere. Most runs should produce one to three findings. Zero is a valid and useful
answer; say "nothing to change" and stop.

```markdown
# Setup review — <date>  ·  <oldest> to <newest>, <N> sessions

**<one sentence: the single thing most worth changing, or "nothing to change">**

1. **<the change>**
   <the number that proves it> → <the exact edit: file and what to write>

2. **<the change>**
   ...

Not changing: <one line, comma-separated, only things a previous run flagged or that
visibly look like drift and are not>
```

Rules for the report:

- **Lead with the single most important change**, in one sentence, before the list. If a reader
  stops after that line they should have the point.
- **Every finding carries its number.** "`test-author`, 0 uses in 30 days" not "seems unused".
- **Name the file and the edit.** "Delete `~/.claude/repos/<project>/agents/<name>.md`" not
  "consider pruning unused agents".
- **Never write a finding you then retract.** "0 uses, but it was added yesterday so that means
  nothing" is not a finding: it is noise that cost the reader a paragraph. Filter it out before
  writing, not after.
- **No section you have to fill.** There is one list. If something does not belong in it, it does
  not go in the report. Do not add "Consider", "Notes", "Observations", or a closing paragraph
  about methodology.
- **`Not changing:` is one line, not a section**, and only for things that genuinely look like
  drift: a previous run's rejected proposal, or a zero count that is correct. Omit it entirely
  when there is nothing to say.
- **A low-use command is not automatically dead.** Per-incident tools (`/ci-check`, `/create-docs`)
  are used when the incident happens. Only propose deleting one if you can say what replaced it.
- Safety rails are exempt. A `deny` rule that never fired is a rule that worked.
- **Raw script output does not go in the report.** The user can run the scripts. Cite the one
  number each finding rests on.

## Step 5 — Offer, don't apply

List the proposed edits and stop. Apply only what the user picks. Config changes are
behaviour changes, and a wrong one is discovered days later in a way that is hard to trace back.

If the user applies anything that changes how the setup works, update `HOW-TO.md` in the same
session — `sync-howto-reminder.sh` will ask for it anyway.
