# How to use my custom Claude Code setup

This is the operator's guide to my personal Claude Code configuration (everything under `~/.claude`, applied across every project). It explains what exists, how to invoke it, and how the pieces fit together.

> **Keep this current.** A `PostToolUse` hook (`sync-howto-reminder.sh`) fires whenever an agent, command, hook, or settings file changes and reminds Claude to update this guide. If you change how the setup works or how you use it, this file should change too.

---

## Version control and a new machine

`~/.claude` is a git repo, intended for a personal account.

The `.gitignore` is an **allowlist**: it ignores `*` and then names the config back in. That
direction is deliberate. The directory is ~1.1 GB and only a fraction of it is configuration;
the rest is harness state (`projects/` alone holds ~1 GB of session transcripts, which contain
whatever was pasted into a session). The harness adds new state directories on its own schedule,
so a denylist would silently start tracking the next one.

**Two things are excluded on purpose, and both matter:**

- `repos/` — the per-project layers. They hold project-specific knowledge: module layouts,
  product rules, internal doc paths, vendor integrations. That belongs in a private repo (or
  nowhere), not on a personal account. Only `repos/_template/` ships.
- `identity.json` — employer and machine identity: tracker host, project key, branch prefix,
  git owner. `identity.example.json` documents the shape. Extracting these values is what lets
  the commands themselves be published.

On a new machine:

```bash
git clone <remote> ~/.claude
cp ~/.claude/identity.example.json ~/.claude/identity.json   # then fill it in
~/.claude/bin/bootstrap                                      # or: CODE_DIR=~/src ~/.claude/bin/bootstrap
```

`bootstrap` symlinks each `repos/<name>/` layer into the matching checkout. **This step is not
optional and its failure is silent** — Claude Code discovers agents only at `<cwd>/.claude/`, so
without the symlinks the agents never appear. A layer with no local checkout is reported and
skipped, not an error.

Tracked config carries **no absolute machine paths**. Permission rules use the `~/` home-relative
form, and scripts take `CODE_DIR` (default `~/Documents`) for wherever repos live.

---

## The model: layers by stability

Knowledge is placed by *stability* — stable things live high (rarely change, always read), volatile things live low (change per ticket):

| Layer | Where | Holds |
|---|---|---|
| 1 | `CLAUDE.md` (in each repo) | Repo conventions, patterns, gotchas |
| 2 | `~/.claude/agents/*.md` | How each specialist role works, stack-agnostic |
| 3 | `repos/<project>/PROJECT.md` | What an agent needs to know about *this* project |
| 4 | `~/.claude/skills/*/SKILL.md` | Procedures either of us can start: I type `/name`, or the model reaches for one when its `description` matches |
| 4 | `~/.claude/commands/*.md` | Procedures only I start, kept as commands because auto-firing would be wrong |
| 5 | `docs/` (in repo) | Durable "why" docs, ADRs, spikes |
| 6 | `~/.claude/projects/<slug>/memory/` | Preferences, per-ticket state, references |

Layers 2 and 3 are the split that makes this publishable: the agent carries the **method**, the
project supplies the **context**.

Five mechanisms, each with a job:

- **Hooks** — deterministic guardrails; run no matter what the model decides.
- **Agents** — isolated context windows I delegate to; parallelizable; good for research/review.
- **Skills** — named procedures reachable two ways: `/name`, or the model matching the task to a `description`.
- **Commands** — named procedures I invoke with `/name`, and only I can start.
- **Workflows** — deterministic orchestration of many agents (scale: audits, migrations).
- **Memory** — facts that survive across sessions.

**Key gotcha:** subagents start with a *fresh context* — they do not inherit the conversation or my auto-recalled memory. Each agent's durable knowledge lives in its own prompt, its `PROJECT.md`, and its own notes dir.

---

## Directory map

```
~/.claude/
├── HOW-TO.md              # this guide
├── CLAUDE.md              # personal cross-project instructions + agent routing policy,
│                          #   including hard output rules that override harness reminders
│                          #   (e.g. never write Claude attribution into published work)
├── settings.json          # model, hooks, plugins, permissions (user-level)
├── identity.json          # GITIGNORED: tracker host, project key, branch prefix, git owner
├── identity.example.json  # the shape, committed
├── .gitignore             # ALLOWLIST: ignores everything, names the config back in
├── agents/                # stack-agnostic specialist subagents (Layer 2)
├── skills/<name>/SKILL.md # procedures the model can also reach for on its own (Layer 4)
├── commands/              # slash commands I alone invoke (Layer 4)
├── hooks/                 # deterministic guardrail scripts, with lib/ for shared rules
├── workflows/             # saved multi-agent Workflow scripts
├── bin/bootstrap          # run once per machine after cloning: links every project layer
├── bin/link-personal-claude   # symlinks repos/<project>/ into one clone or worktree
├── bin/test-hooks         # run every hook regression matrix; `test-hooks <filter>` for one
├── bin/lint-assets        # frontmatter lint for skills/agents/commands (silent-failure catcher)
├── bin/pr-diff-lines      # new-side line numbers for a file in a PR diff (comment anchors)
├── bin/claude-usage       # what the setup DID: delegations, commands, declared vs used
├── bin/claude-prompts     # what I ASKED FOR: imperatives, corrections, and --questions
├── worklogs/              # GITIGNORED: /worklog output + feedback.jsonl
├── repos/<project>/       # GITIGNORED per-project layer: PROJECT.md, agents, agent-notes,
│                          #   settings.local.json — symlinked into <checkout>/.claude/
│                          #   and excluded via .git/info/exclude, never committed
├── _archive/              # retired agents, commands, hooks, docs. Outside every scanned dir
└── projects/<slug>/memory/    # shared memory, keyed per project by the harness
```

> There is no top-level `~/.claude/memory/`. Claude Code stores the shared memory **per project**,
> under `~/.claude/projects/<slug>/memory/`, where the slug is the project's absolute path with
> `/` replaced by `-`.

**`_archive/` has to live outside the scanned directories.** Archiving into a subdirectory
*inside* `~/.claude/commands/` does NOT unload anything: commands reload namespaced as
`_archive:name` and still cost the same context.

---

## How agents are invoked (orchestration)

Three ways, and you rarely need the first:

1. **Explicit** — type `@explorer <question>` to target one directly.
2. **Automatic (the default)** — the main thread routes by question, per the table in
   `~/.claude/CLAUDE.md`. The bias is toward inline work, because delegation costs a full
   context-priming round trip.
3. **Via commands** — `/review-queue` and `/pre-pr` hard-wire the relevant agents.

**Write agents are deployed on their own for implementation work**, not only when asked.
One-line edits stay inline. Every implementation, inline or delegated, is test-first: failing
spec, then code (see `## Tests` in `~/.claude/CLAUDE.md`).

The one hard rule for write agents: they are auto-*deployed* but never auto-*committed*. They
edit the working tree (uncommitted) and their `git diff` is always presented for review first.

**Long-running work goes in-session, not to another session.** `Bash(run_in_background: true)`
for a full test suite, asset builds, and long migrations. It persists across turns and re-invokes
the model on completion.

---

## Agents

Read-only agents have no Edit/Write tools, so "read-only" is structurally enforced, not just
requested. `agent_clone_boundary.rb` denies their writes a second time as belt-and-braces.

> **Run `/setup-review` for usage numbers.** This guide deliberately no longer carries counts:
> they were hand-tallied over different windows and drifted badly in both directions. The command
> reads every transcript in the window instead, and reports `scoped` (uses from a cwd inside that
> agent's own project, the only place a project-scoped agent is reachable) alongside `total`. A
> high `total` with `scoped: 0` means the agent is defined where the work never happens.

All seven are user-level and stack-agnostic. There are no project-scoped agents.

### By role, read-only — auto-deployed

| Agent | Owns | Explicitly not |
|---|---|---|
| `explorer` | Where is it, how does it work, what calls this | correctness, design, coverage |
| `reviewer` | Is this diff correct | locating, pre-code design, test strategy |
| `architect` | What should we build, where does it belong, ranked options | reviewing existing code, implementing |
| `qa-engineer` | What could break, is this actually tested | writing tests, implementation correctness |

### By stack, write-capable — opt-in

| Agent | Owns |
|---|---|
| `rails-engineer` | Ruby and Rails: models, controllers, services, jobs, migrations, specs |
| `java-engineer` | Java and Spring: services, controllers, entities, migrations, tests |
| `frontend-engineer` | TypeScript and React: components, hooks, state, API clients, tests |

These are deliberately **not** marked `PROACTIVELY`. Read-only agents earn the round trip and
account for essentially all measured delegation; every write agent has sat at zero over a 30-day
window. They are here to be asked for, and `/setup-review` will say in a month whether they
earned their place.

**Two of the four read-only agents also sat at zero, and the cause was wording, not the agent.**
Over the same window `reviewer` ran 146 times and `explorer` 26, while `architect` and
`qa-engineer` ran never, even though both were already wired into skills that run often.
`/pre-pr` said "**consider** `qa-engineer` when the diff touches money, auth, data integrity or a
migration", and `/ticket-plan` said to use `architect` "**instead**" of `explorer` on a large or
open-shaped ticket. A verb like *consider* is advisory, so it loses every time, and *instead*
made an either-or out of two agents that answer different questions. Both were rewritten on
2026-09-21 into conditions that are checkable rather than weighable: name the trigger, say the
agent runs when it is met, and require the skip to be reported. Before deleting an agent for zero
usage, read the sentence that is supposed to launch it.

### How the split works

Each agent reads **`.claude/PROJECT.md`** on startup: toolchain commands, layout, conventions,
locked decisions, traps. The agent carries the *method*, the project supplies the *context*. That
is what keeps one definition working across every repo, and what keeps the definitions
publishable while the project knowledge stays private.

If `PROJECT.md` is absent an agent infers from the build file and directory shape, and says so in
its report, because it changes how much to trust its claims.

The "explicitly not" column is load-bearing. With seven agents the `description:` field *is* the
routing mechanism, and a vague one means the wrong agent gets picked or none does.

**A project agent still wins over a user agent of the same name**, so
`repos/<project>/agents/<name>.md` remains the escape hatch when a generic role genuinely does not
fit. Prefer not to: three near-duplicate reviewers is the thing this arrangement replaced.

Per-agent notes live in `repos/<project>/agent-notes/<name>/`, gitignored in the checkout, so a
shared agent definition never hardcodes a personal home path.

---

## Skills and commands

Both are invoked with `/name` and both are user-level (available in every project) unless noted.
The difference is who else can start them: a **skill**'s `description` is loaded into every
session, so the model can reach for it when the task matches ("let's start ABC-1234" gets
`ticket-plan` without the slash). A **command** is inert until typed.

**The rule for choosing.** Default to a skill, because it is a strict superset: `/name` still
works, the model can also start it, and it can carry scripts and reference files beside
`SKILL.md`. The one cost is that its `description` occupies context in every session forever.
So the real question is never "is this worth being a skill" but **"would it be bad if the model
fired this on its own?"** Three cases where the answer is yes, and the thing stays a command:

1. **Expensive or slow**, and the moment should be mine to pick (`/setup-review` reads the whole
   transcript corpus).
2. **The trigger phrase is too common** to write a `description` narrow enough to avoid false
   fires.
3. **It writes something outward-facing** without a go-ahead in its own body.

Nine of these converted from commands to skills on 2026-09-21. Do not judge that call by how
often a `/name` was typed: the typed count only measures the path that existed, never whether
the spoken one would have been preferred.

Two sources keep both stack-agnostic, and neither is a hardcoded value:

- **`identity.json`** for who and where: tracker host, project key, branch prefix, base branch.
- **`.claude/PROJECT.md`** for how this project builds: the test, lint, typecheck and build
  commands, which linter takes which files, and how a changed file maps to its tests.
  `/pre-pr` and `/ci-check` read it rather than assuming a runner from the language. It also
  names any **checked-in PR standard** the repo owns: `/pr-description` follows that doc on
  shape, and `/pr-review` follows it on coverage and order of work while keeping the
  question-shaped comment voice, which stays personal and is not drift.

The repo slug is resolved with `gh repo view --json nameWithOwner`, never hardcoded, because a
baked-in slug silently reports on the wrong repository from another checkout.

When `PROJECT.md` is missing, a command infers from the build file and **says so in its report**.
An inferred command that silently does nothing is exactly the failure these commands exist to
catch, so a skipped check is always reported as skipped, never as passing.

**Commands** (`~/.claude/commands/*.md`, typed only):

| Command | What it does |
|---|---|
| `/worklog` | Records what this session revealed about the setup: manual patterns worth automating, corrections worth acting on, traps worth recording. Reads the transcript, not recall. Writes to `~/.claude/worklogs/` |
| `/setup-review` | Aggregates the worklogs and the transcript corpus: unreachable agents, missing commands, repeated corrections, permission rules that contradict stated policy, stale doc claims, dead weight. Proposes edits, applies none |

**Skills** (`~/.claude/skills/<name>/SKILL.md`, typed or model-invoked):

| Skill | What it does |
|---|---|
| `/pr-review` | Reviews a PR for quality, correctness, convention adherence; drafts one-question inline comments per `file:line`, posts them on your go-ahead, calls an explicit merge verdict, and reassigns the PR to its author |
| `/ticket-plan` | Fetches a ticket, offers the working branch, flags blockers, produces an implementation plan. Absorbed `/start-ticket` on 2026-09-18 |
| `/comments` | Pulls all PR review comments, validates each against code, produces an action plan |
| `/commit` | Groups unstaged changes and commits each group (append-only; never rewrites history) |
| `/pr-description` | Generates/updates a PR description from the branch diff + ticket |
| `/ci-check` | Fetches failing CI checks/logs, categorizes each failure, reports fixes |
| `/review-queue` | Pulls PRs awaiting my review; spawns `reviewer` per PR, then `/pr-review` + `/comments` |
| `/pre-pr` | Pre-flight gate: targeted lint + typecheck + affected tests + `reviewer` pass |
| `/pre-deploy` | Turns a release range into a checklist doc: gates with owners, risks ranked by blast radius with watch and act-if, post-deploy actions. Batch-level rollout risk, not a second code review |
| `/rails-lens` | Explains Java, Spring, JPA and Maven through the closest Rails concept, and says where the analogy breaks |
| `/next` | Ranks what is outstanding across tracker, open PRs and the checkout, by who is blocked. `/next setup` ranks setup work from the worklogs instead |
| `/new-ticket <idea\|KEY-n>` | Drafts a ticket in the house format; creates it on your go-ahead. Given a key, reformats in place losslessly |

**Archived commands live at `~/.claude/_archive/commands/`.** Restore with
`mv ~/.claude/_archive/commands/<name>.md ~/.claude/commands/`.

**A skill needs frontmatter to exist at all.** `name` and `description` in a `---` block at the
top of `SKILL.md`; without them the harness does not register the file and `/name` silently does
nothing. `$ARGUMENTS` is a command-only token, so a converted file has to describe its input in
prose instead.

---

## Hooks

Deterministic scripts in `~/.claude/hooks/`, wired in `settings.json`. Shared rule
logic lives in `~/.claude/hooks/lib/`.

| Hook | Event | Enforces |
|---|---|---|
| `block-destructive-commands.sh` | PreToolUse (Bash) | Denies commands that destroy unrecoverable data, and prompts on recoverable-but-regrettable ones. Runs FIRST in the Bash chain, for the main thread AND every subagent. Rules in `lib/destructive-patterns.sh` |
| `block-git-history-rewrite.sh` | PreToolUse (Bash) | Denies `git commit --amend`, `rebase`, `reset --hard`, force-push — commits stay append-only. Recovery flags (`--abort/--continue/--skip/--quit`) stay usable. Regression matrix: `bash ~/.claude/hooks/lib/test-git-history-rewrite.sh` (18 cases) |
| `block-publish-leak.sh` | PreToolUse (Bash, `git push*`) | Denies a push of `~/.claude` whose tracked content at HEAD names the employer. Terms are derived at runtime from `identity.json` (tracker host label, git owner, branch prefix, and the project key only as `KEY-1234`), plus optional extras in the gitignored `.publish-blocklist`, so the hook itself stays publishable. Regression matrix: `bash ~/.claude/hooks/lib/test-publish-guard.sh` (6 cases) |
| `block-sensitive-writes.sh` | PreToolUse (Read\|Edit\|Write\|MultiEdit) | Denies reading/writing secrets (`.env*`, key and credential files) and editing generated files. Global (main thread too). `.env.example|sample|template|dist` are exempt: they carry no values and are committed. Regression matrix: `bash ~/.claude/hooks/lib/test-sensitive-writes.sh` (24 cases) |
| `agent_clone_boundary.rb` | PreToolUse (Write\|Edit\|MultiEdit\|Bash) | Confines a subagent to the checkout its session started in. Regression matrix: `bash ~/.claude/hooks/lib/test-clone-boundary.sh` (32 cases) |
| `restrict-subagent-bash.sh` | PreToolUse (Bash) | For subagents ONLY (via `agent_id`): auto-*allows* safe commands so agents don't prompt, while denying the dangerous set (`git commit`/`push`, installs, outbound network, `rm -rf`, secret-file reads) for all agents, plus repo/system-mutating shell for read-only agents (their `agent-notes/` + `/tmp` scratch stay writable). Also sources `lib/destructive-patterns.sh` *before* the write-agent auto-allow, so that allow can never cover a destructive command. Main-thread bash is unaffected. Regression matrix: `bash ~/.claude/hooks/lib/test-subagent-bash.sh` (26 cases) |
| `sync-howto-reminder.sh` | PostToolUse (Write\|Edit) | Reminds Claude to update this guide when an agent/command/hook/setting/CLAUDE.md changes |
| `length-budget.sh --measure` | Stop | Logs the prose word count of the turn that just ended to `worklogs/response-lengths.tsv` (override with `LENGTH_BUDGET_LOG`). Regression matrix: `bash ~/.claude/hooks/lib/test-length-budget.sh` (12 cases) |
| `length-budget.sh --remind` | UserPromptSubmit | Injects the CLAUDE.md caps plus the measured trailing average, but only when the average is over budget |

**Length enforcement has to happen before the response, not after.** A `Stop` hook cannot retract
what is already on screen: blocking there makes the model *append* a second answer, which is
worse than the long one. So `Stop` only measures, and `UserPromptSubmit` carries the nudge into
the next turn with the measured average attached, because a number changes behaviour where an
adjective does not. It stays silent while the trailing average is inside budget, and it never
blocks.

**The leak guard is a hook, not a checklist.** `~/.claude` is public and lives on a personal
account, while every session runs inside employer repos, so employer terms drift into it: an
audit on 2026-09-21 found six in about three weeks (an org name in this guide, four hardcoded
ticket keys, one set of internal portal names). That is a recurring rate, not an incident, and a
command you have to remember to run does not catch a recurring rate. The terms live only in
`identity.json`, which means the guard is portable: someone else cloning this repo gets their
own blocklist by filling in their own identity.

**Nothing destroys data without you.** `block-destructive-commands.sh` is the backstop added
after a local development database was wiped by a command that never prompted — both the
`settings.json` allowlist and the write-agent auto-allow in `restrict-subagent-bash.sh` covered
it. Permission rules are opt-in prefixes and can't express "anything but this", so the stop has
to be a hook.

- **Denied** (unrecoverable): `db:drop|reset|setup|purge|truncate_all|schema:load|structure:load|migrate:reset|seed:replant`, `dropdb`, `pg_restore --clean`, raw `DROP`/`TRUNCATE`/`DELETE FROM` through `psql`/a runner, `destroy_all`/`delete_all` in a runner, `FLUSHALL`/`FLUSHDB`, `RAILS_ENV=production|staging`, `heroku run`/`pg:reset`/`apps:destroy`, `terraform destroy`, `kubectl delete`, `aws s3 rm|rb`, `sudo`, `mkfs`/`dd of=/dev/`, `git clean -fd`, `git checkout|restore .`, `git checkout -f`, `git stash drop|clear`, shell redirects over secret or generated files, and any `rm` whose target is `/`, `~`, `.`, `..`, a bare glob, `.git`, the repo root, a top-level source dir, or an absolute path outside the working directory.
- **Prompts** (recoverable but easy to regret): `db:rollback`, `find -delete`/`-exec rm`, `xargs rm`, `git branch -D`, `git gc --prune`/`reflog expire`/`worktree remove`, `update_all`, `pkill`/`killall`, `truncate -s`.
- **Deliberately still allowed**: anything test-env (the test DB is disposable and the suite rebuilds it), `db:migrate`, `db:create`, `rm -rf` of `node_modules`/build output/paths under `/tmp`, and normal git/test/lint work.
- Deny messages tell Claude to hand the command back to you (`! <command>` in the prompt) rather than route around it. The same patterns are mirrored into `permissions.deny` in `settings.json` as defense in depth, since a `deny` rule beats any `allow`.
- Regression matrix: `bash ~/.claude/hooks/lib/test-destructive-patterns.sh` (79 cases — must-deny, must-ask, and must-still-work). Re-run after any change to `lib/destructive-patterns.sh`; add a case for anything new you want blocked.

**The checkout boundary locates a project by walking up for `.git`.** It confines a *subagent* to
the nearest enclosing checkout, which is what makes the rule hold for any project without naming
one. A top-level session is deliberately untouched — that is the human driving. Write/Edit
confinement is HARD, since the target path is resolved before comparison, so
`../other-checkout/...` is caught. Bash confinement is SOFT because only the command string is
visible: it denies absolute paths into a different checkout, but a bare relative command in the
inherited cwd gets through. Peer reads are expected to go through git remote *names*, which carry
no paths. Carve-outs: the per-project layer, project memory, scratch, `/tmp`, plus any
`git.sibling_repos` in `identity.json` for work that genuinely spans two repos.

**Auto mode is the default.** `permissions.defaultMode` is `"auto"` in `settings.json`, so a safety classifier decides routine actions instead of prompting per call. It sits *above* everything below: the deny hooks and `permissions.deny` still fire, and `git push` / `gh pr create` stay promptable. The mode must live in the user file — an `"auto"` defaultMode in a project or local settings file is ignored as repo-controllable. If auto mode is ever unavailable (unsupported model, org kill switch), the CLI falls back to default mode with a notice.

**Reads are globally allowed.** `settings.json` allows `Read(//**)`, so file reads never prompt (in any project, main thread or subagent). This is safe because `block-sensitive-writes.sh` still denies reads of secret files — a hook `deny` overrides an allowlist entry.

**Assistant-owned scratch and memory writes are allowed.** `settings.json` allows `Write`/`Edit` under `~/.claude/repos/**` (the per-project layer, including `agent-notes/`), `~/.claude/projects/**` (per-project memory), `~/.claude/scratch/**`, and `/tmp/**`. These are the paths only Claude and its agents use, so persisting a fact or parking an intermediate file no longer prompts. Deliberately excluded: everything else under `~/.claude` (hooks, agent definitions, `settings.json` itself, this guide), which stays promptable because editing it changes how the setup behaves.

**Permissions are scoped by tool, not by project.** A generic tool (`git`, `gh`, `yarn`, `npx`) is allowlisted once at user level. A tool that only exists in one project (`./mvnw`, a `make` target, `bundle exec`, `pnpm -r`) belongs in that project's `settings.local.json`. Getting this backwards produces duplicate rules across scopes, which is how an allowlist rots. Intentionally NOT allowlisted anywhere: `git push` and `gh pr create` — outward-facing, kept promptable. Beware broad prefixes that swallow them: `Bash(gh pr:*)` also matches `gh pr create`.

---

## Verifying the setup

Two runners, both exit 0 or 1, both safe to run any time:

```bash
~/.claude/bin/test-hooks              # every hook matrix (7 suites, ~197 cases, ~18s)
~/.claude/bin/test-hooks length       # only suites whose name matches
~/.claude/bin/lint-assets             # frontmatter for skills, agents, commands (instant)
bash ~/.claude/hooks/lib/test-<name>.sh   # one suite directly
```

**What these are.** Table-driven bash matrices, no framework, `jq` the only dependency. Each case
builds the JSON payload Claude Code really sends a hook, pipes it to the real script, and asserts
the decision. Three outcomes, and the distinction matters: `deny` stops the command, `allow` runs
it with no prompt, and **pass-through** (empty output) means the hook abstains so normal prompting
applies. An `allow` that should have been a pass-through is the dangerous direction, because it
removes the human from a command nobody vetted.

**A hook gets a spec; a skill gets an eval.** A hook is a pure function of its input JSON, so the
right answer is deterministic and cheap to pin. Whether the model *picks* the right skill, or
writes a review comment as a question, is not deterministic and cannot be tested this way. Those
need evals, which this repo does not have yet.

**Green on the first run means nothing until you break the hook on purpose.** Every matrix here
was mutation-tested: drop `mv` from the read-only deny in `restrict-subagent-bash.sh` and case 20
must fail; restore the `\x00` turn marker in `length-budget.sh` and five counting cases must fail.
Copy the hook to a temp file, mutate it, and run with `HOOK=/tmp/mutant bash lib/test-<name>.sh`.
Each suite honours that override for exactly this reason.

**The lint exists because the failure is silent.** A `SKILL.md` with no frontmatter is never
registered: `/name` does nothing and the model never sees it. Four skills sat in that state for
part of 2026-09-21 and the only symptom was absence. `lint-assets` also fails when it checked zero
assets, since a lint that silently inspects nothing looks exactly like a passing one.

**Nothing runs these automatically yet.** That is the open gap, not an oversight to route around.

### Evals: the half a spec cannot reach

```bash
~/.claude/bin/run-evals                      # every case, 1 run each
~/.claude/bin/run-evals --case 'trigger-*'   # a subset
EVAL_RUNS=3 ~/.claude/bin/run-evals          # 3 samples per case, the CLI default
```

The runner is the built-in `claude plugin eval`, not something written here. It already has
the grader this setup needs (`type: tool_used`, `tool: Skill`) and an **ablation arm**: every
case also runs against a no-plugin baseline, so the result says whether a skill fired *because
of its description* or whether plain Claude would have done the same thing unaided. That delta
is the only thing that justifies a `description` occupying context in every session.

**`run-evals` builds a clean copy first, and that is not incidental.** `claude plugin eval`
treats its whole target directory as the plugin and copies it into a sandbox. Pointed at
`~/.claude` it fails outright, because `file-history/` uses hard links and the runner rejects
them, and if it had succeeded it would have copied 1.1 GB of session transcripts into a sandbox.
The build assembles 188 KB from the manifest, `skills/`, `agents/` and `evals/`. Nothing else is
under test, and nothing private travels.

**A negative case needs two graders, not one.** "This prompt must not fire a skill" is satisfied
by a run that crashed and did nothing, which is how a broken suite reports green. Every
`no-trigger-*` case therefore pairs `min: 0, max: 0` with an LLM grader asserting the question
was actually answered. `max: 0` alone does not work: the minimum stays 1 and the range reads
`1..0`, which nothing can satisfy.

**Runs are not free and not runnable from inside a session.** Each case spawns a full `claude`
child on your credential; started from a Claude Code session it dies with `Not logged in`. Run
them yourself. Budget with `--max-cost-usd`, gate CI with `--threshold`.

---

## Workflows

Saved multi-agent orchestrations in `~/.claude/workflows/`, run via the Workflow tool
(`Workflow({name: '...', args: {...}})`) when a task needs deterministic fan-out.

| Workflow | What it does |
|---|---|
| `flaky-test-hunter` | Runs suspect specs N times each in parallel, classifies each as flaky/failing/stable. Args: `{ specs: [...], runs: 5 }` |

---

## Memory

- **Shared store** (`~/.claude/projects/<slug>/memory/`) — used by the main thread. Categories:
  `user_*` (who I am), `feedback_*` (my preferences and corrections), `project_*` (per-ticket
  state), `reference_*` (durable pointers). Indexed by `MEMORY.md`.
- **Per-agent notes** (`repos/<project>/agent-notes/<name>/`, reached as
  `.claude/agent-notes/<name>/` from inside the checkout) — each specialist's private store of
  role-specific craft, scoped to one project. The agent reads its `NOTES.md` index on startup and
  writes durable facts on finish. Cross-cutting facts go to the shared store instead.

**Altitude rule:** durable repo facts → `CLAUDE.md`/`docs/`; a preference or correction →
`feedback_*`; per-ticket state → `project_*`; role-specific craft → that agent's notes dir.

**Two checkouts can share one memory store.** The store is keyed by cwd, so a session started in
a second repo gets an empty store and loses every accumulated fact. Where two repos are really one
body of work, symlink the `memory/` subdirectory of one project slug to the other. Link only
`memory/`, not the whole project directory, so session transcripts stay separate per repo.

---

## Typical flows

- **Start a ticket:** `/ticket-plan <n>` (branch + plan) → implement in the main thread → `/pre-pr` → `/commit` → `/pr-description`.
- **Review others' PRs:** `/review-queue` → adversarial first pass per PR → `/pr-review` + `/comments`.
- **Design before building:** `@architect` for ranked options → `@explorer` to ground them in the code → implement.
- **Before opening a PR:** `@qa-engineer` on the diff, especially if it touches money, auth, or data integrity.
- **Improve the setup:** `/worklog` at the end of a substantial session → `/setup-review` monthly
  to aggregate them → prune what sits at zero, build what keeps getting asked for by hand.

### The improvement loop

`/worklog` and `/setup-review` exist to answer "how do I use this thing, and what should change".
They read the transcripts rather than asking you, because the transcripts are ground truth and
recall is not: an audit of a similar setup found self-reported delegation understated the real
volume by ~5×.

Two scripts back them, and they answer different questions:

| Script | Question | Finds |
|---|---|---|
| `bin/claude-usage` | What did the setup *do*? | Unused agents and commands, unreachable definitions, orphaned notes |
| `bin/claude-prompts` | What did I *ask for*? | Repeated manual asks with no command, correction themes, and (`--questions`) the questions that earned only a one-word reply |

A repeated short imperative with no command behind it is the strongest finding. A correction
theme that recurs across sessions is the second. Both are invisible to `claude-usage` alone,
which is why the prompt side exists.

The window is a rolling ~30 days, because that is the transcript retention. Every count means
"in the window", never "ever".

---

## Plugins & integrations

- **i-have-adhd** (plugin, user-level) — output-shaping ruleset, always-on via the flag file
  `~/.claude/.i-have-adhd-always`. It costs ~1,200 words per session and owns output shape, so
  `CLAUDE.md` deliberately does not restate its rules.
  - Turn off for one session: say "stop adhd mode". Turn off for good: delete the flag file.
  - **It shapes output, it does not shorten it.** Rules 1 and 5 under "When to break the rules"
    exempt "explain this" and "what are my options" from brevity, and rule 5 fires on most
    design, architecture, and comparison questions whether or not you asked for options.
  - **The "Be concise" section in `CLAUDE.md` is the counterweight.** It overrides rule 5 (ranked
    one-liners, expand on request) and deliberately leaves rule 1 intact, so "explain X" still
    gets a real explanation. The plugin owns shape, `CLAUDE.md` owns length.
- **ponytail** (plugin, user-level) — forces the laziest solution that actually works. Pairs with
  the altitude rule above: it governs what gets built, not how output is written.
- **Figma** (plugin) — design ↔ code. **Disabled at user level**, because it loaded a large
  instruction block plus ~10 skills into every session including backend-only work. Re-enable
  per-project in that project's `.claude/settings.json`.
- **frontend-design** (plugin, project-level) — UI design guidance. **Disabled in my main work
  repo** (`false` in that repo's `settings.local.json`): zero invocations across 50 sessions.
  Flip it back to `true` there if UI work picks up.
- **Issue tracker** (MCP server, user scope) — configured in `identity.json`. The rules live in
  the "Issue tracker" section of `CLAUDE.md`: pick tools from the server's own schemas rather than
  hardcoding names, resolve any workspace id once per session, reads run unprompted, and **writes
  (comments, transitions, worklogs, field edits) need confirmation** since they're outward-facing.
  There is deliberately no whole-server entry in the `settings.json` allowlist — that would also
  greenlight those writes.
- **AppSignal** (MCP server) — production traces and incidents, for debugging a real report rather
  than inferring a root cause from code.
