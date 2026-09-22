---
name: pr-description
description: Generate or update a pull request description from the branch diff and its ticket, following whatever PR standard the repo has checked in. Use when asked to write, draft, rewrite, or update a PR description or PR body, and before opening a PR that needs one.
argument-hint: [optional PR number to update]
---

# PR Description Generator

Generate a robust PR description for the current branch from the diff and Jira ticket, structured
for both the code reviewer and the QA engineer.

## Input

A PR number, if one was given, whose description should be updated. If not, generate a
description for the current branch.

## Steps

### 1. Gather context

Run these in parallel:

```bash
git rev-parse --abbrev-ref HEAD
BASE="origin/$(jq -r .git.default_base ~/.claude/identity.json)"
git log "$BASE..HEAD" --oneline
git diff "$BASE...HEAD" --stat
git diff "$BASE...HEAD"
```

**Ticket:** Extract the ticket number from the branch name, which follows
`git.branch_prefix` in `~/.claude/identity.json`. Then fetch
`<issue_tracker.project_key>-<number>` through the MCP server that file names (see "Issue
tracker" in `~/.claude/CLAUDE.md`).

If no ticket number is in the branch name and a PR number was provided, check the PR body for a
Jira link.

### 2. Analyze the diff for signals

Scan for the things a reviewer cannot infer from the diff alone. Note which apply, then let the
standard from step 3 decide where each one goes and whether it earns a mention at all.

- **Migrations, backfills, changed defaults** (`db/migrate/*`, schema changes) — always named in
  the body, however short it is.
- **New config, secrets or dependencies** — new `Secret.fetch` / `ENV[...]` keys, credentials,
  `Gemfile` or `package.json` additions. Say what has to exist before the merge is safe.
- **Feature flags** — name the flag and who enables it.
- **UI entry points** — new or changed routes, controllers, GraphQL mutations, React components
  or views. Identify the audience, using whatever portals or app surfaces `PROJECT.md` names,
  and the screen a QA engineer would actually open.
- **API surface** — changes under `app/controllers/api/`, `config/routes/*_api.rb`, `swagger/`,
  or request specs. QA exercises these in Postman, not the UI, so note the routes, verbs, auth
  scheme and error codes.
- **No product surface at all** — background jobs, rake tasks, model-level guards, internal
  refactors. Say so plainly rather than inventing steps.
- **Complex or subtle logic** — a non-obvious tradeoff, a fragile interaction, a decision a
  reviewer would otherwise query. This is the only kind of explanation worth spending words on.

### 3. Follow the repo's description standard

**The format is not this command's to define.** `.claude/PROJECT.md` names the checked-in
standard when the project has one. Only if it does not, search:

```bash
git ls-files | grep -iE 'pull.?request.*(description|standard)' | head
```

If one exists, read it and obey its sections, its length cap, its rules and its anti-patterns.
It is team-owned and it changes; this file is not a second copy of it. The doc outranks this
file on shape and you do not need to ask. It does not outrank `~/.claude/CLAUDE.md`: the length
budgets, the no-em-dash rule and the no-attribution rule survive any team standard. Everything
this command still owns is procedure: gathering context (step 1), reading the diff for signals
(step 2), the voice notes below, and the output mechanics (step 4).

If no such doc exists, fall back to a Jira link and these four sections:

- **Summary** — one paragraph, 4 sentences max. Not a restatement of the ticket, not a
  file-by-file enumeration.
- **Non-obvious details** — omit unless the diff hides a tradeoff, a fragile area, or an
  interaction with existing behavior. Three points max, one or two sentences each.
- **Outside-the-code work** — omit unless merging alone does not ship it: env var, secret,
  migration, feature flag and who enables it, new dependency, coordinated deploy.
- **Testing** — omit when no human can exercise the change. Where it applies it is the one
  section not trimmed for brevity, and it is written for the QA engineer.

**Two traps worth naming, because both have shipped:**

- **QA steps are written for someone who cannot open a console.** Our QA engineers have no Rails
  console access, so console snippets make the section unusable by its own audience. Write UI and
  Postman steps. When a change genuinely has no product surface, say so in one line and split out
  what needs an engineer as an explicit handoff rather than padding with invented steps.
- **Rewriting an existing body means correcting it.** Stale claims in the old description are not
  yours to carry forward. Check every factual claim against the current diff, including example
  counts and file references, and drop anything the code no longer does.

### Voice: plain words, short sentences

"More concise, simpler wording, emphasize readability" is the note this command gets back most
often. Write for that on the first pass:

- **Short sentences.** One idea each. If a sentence has two clauses joined by "and" or "which",
  it is usually two sentences.
- **Plain words over precise-sounding ones.** "uses" not "leverages", "sends" not "dispatches",
  "now" not "at this juncture". No jargon a reviewer outside this area would have to decode.
- **Say the thing, don't frame it.** Cut "This PR", "In order to", "It is worth noting that",
  "As part of this change". Start with the subject.
- **No hedging adverbs** that carry no information: "essentially", "effectively", "simply",
  "just", "basically".
- **A reviewer who did not write this code is the audience.** They need what changed and why,
  not the reasoning path that got you there.

**Before returning it, re-read and cut.** Every sentence that survives should fail this test:
would deleting it lose information the reviewer needs? If not, delete it. Expect to lose a third
of the first draft; that pass is part of the job, not an optional polish.

### 4. Output

**If no PR number was given:** output the description as a copyable markdown block.

**If a PR number was given:** ask the user if they want to update the PR description directly. If
yes, run:

```bash
gh pr edit <number> --body "$(cat <<'EOF'
<description>
EOF
)"
```

Use the HEREDOC form to preserve formatting.

## Rules

- Read the checked-in standard every run; do not cache what it said last time.
- No em dashes.
- Never list changed files or narrate the diff hunk by hunk.
- Never invent content to fill a section. A section the diff does not justify is omitted, not
  filled with "N/A".
- A description where the reader learns nothing the diff doesn't already say is too long.
