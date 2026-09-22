---
name: ticket-plan
description: Take a ticket from assigned to ready-to-work. Fetches it, offers the working branch, surfaces blockers, and produces a code-grounded implementation plan. Use when starting work on a ticket or issue by key ("let's start ABC-1234", "pick up 1234", "what's involved in ABC-1234"), before writing code for it.
argument-hint: 1234 or KEY-1234 [large]
---

# Ticket Planning

Fetch a ticket, get onto a branch for it, surface what would block the work, and produce an
implementation plan. You should finish this command on the right branch with a plan in hand.

## Input

Required: a ticket number, bare (`923`) or prefixed with the key from `~/.claude/identity.json`. Optionally a complexity hint: `923 large` forces multi-approach output.

## Setup

Read the tracker and branch settings once; never hardcode them:

```bash
ID=~/.claude/identity.json
KEY=$(jq -r .issue_tracker.project_key "$ID")     # e.g. ABC
PREFIX=$(jq -r .git.branch_prefix "$ID")          # e.g. xx-abc
BASE=$(jq -r .git.default_base "$ID")             # e.g. main
```

## Steps

### 1. Gather context

**The ticket:** fetch `$KEY-<number>` through the tracker's MCP server. See "Issue tracker" in
`~/.claude/CLAUDE.md`. Accept the number bare or prefixed; derive both forms.

**Current branch state:**
```bash
git branch --list "*<number>*"
git status --porcelain
git log --oneline -10
```

### 2. Get onto the right branch

Skip this entirely if the current branch already matches the ticket number; say so and move on.

Otherwise compute `$PREFIX-<number>-<slug>`, where the slug comes from the ticket title:
downcase, replace any run of non-alphanumeric characters with a single `-`, strip leading and
trailing `-`. Drop filler from a long title but keep it identifiable without opening the ticket.

**Creating or switching a branch always needs an explicit go-ahead.** Show the computed name and
wait. This is one of the few things that is not covered by a standing authorization.

```bash
git fetch origin "$BASE"
git checkout -b "$PREFIX-<number>-<slug>" "origin/$BASE"
```

- **Uncommitted changes: stop and surface them.** Never stash, never discard, never branch on top
  of them.
- **A branch matching `*<number>*` already exists:** check it out instead of creating a duplicate,
  and say which one you found.
- Branch creation and checkout are append-only, so nothing here rewrites history.

Planning without cutting a branch is legitimate — if the user declines, carry on to step 3 and plan anyway.

### 3. Understand the ticket

Read the full ticket: summary, description, acceptance criteria, and any linked tickets or comments. Establish:
- **Goal**: What is this ticket trying to accomplish? One sentence.
- **Acceptance criteria**: List each criterion verbatim from the ticket.
- **Scope boundary**: What is explicitly out of scope or not mentioned?

### 4. Identify blockers and ambiguities

Review the acceptance criteria and description critically. Flag anything that would slow down or block implementation:

**Blockers** — things that prevent starting work:
- Missing access, credentials, or environment setup
- Dependencies on other tickets that aren't merged yet
- Migrations or data changes that need coordination

**Ambiguities** — things that need clarification before or during implementation:
- Acceptance criteria that could be interpreted multiple ways
- Edge cases not covered by the description (e.g. "what happens when X is nil?")
- Unstated assumptions about existing behavior
- Missing details: error handling, loading states, empty states, permissions
- Whether existing tests need updating or new tests are expected

**Questions for the team** — things worth asking before diving in:
- Design or UX decisions not specified in the ticket
- Performance implications if the feature touches hot paths
- Whether related features are planned that would change the approach

For each item, be specific about *what* is unclear and *why* it matters for implementation. Don't flag things you can answer by reading the codebase — do that reading first.

**Report at most 5, and only ones that change what you would do.** This section is a decision
aid, not a catalogue of everything conceivably underspecified. A blocker that stops work and an
edge case you can pick a sensible default for are not the same thing: raise the first, decide the
second and note the assumption in one line. Most tickets should surface one or two items, and
"None identified" is a common and correct answer.

### 5. Explore the codebase

Before planning, understand the existing code that this ticket touches:
- Find the relevant models, services, controllers, components, and tests
- Read the key files to understand current behavior
- Identify existing patterns this work should follow
- Note any tech debt or complexity that will affect the approach

Use the `explorer` agent (via the Agent tool, `subagent_type: explorer`) for broader searches; it reads `.claude/PROJECT.md` and its own notes for this project. Be thorough here — plan quality depends on understanding what exists.

For a Large ticket, or one whose shape is genuinely open, use `architect` instead: it returns ranked options with a recommendation, which is what step 6's multi-approach output wants anyway.

### 6. Produce the plan

**Sizing**: Based on the ticket scope and codebase exploration, classify as:
- **Small** (< 1 day): Straightforward change, clear path, limited files. Produce a single plan.
- **Medium** (1-3 days): Multiple files/layers involved but approach is clear. Produce a single plan with callouts for decisions.
- **Large** (3+ days): Significant scope, multiple valid approaches, or architectural decisions needed. Produce 2-3 approach options.

If the user passed `large` as a hint, always produce multiple approaches regardless of sizing.

#### For Small/Medium tickets

```
## Ticket Plan: $KEY-<number> — <title>

**Goal**: <one sentence>

**Size**: Small | Medium — <brief justification>

### Blockers & Ambiguities
<from step 4, or "None identified" if clean>

### Implementation Plan

**Step 1: <description>**
- Files: `<path>`, `<path>`
- What: <concrete description of the change>
- Why: <how this satisfies which acceptance criterion>

**Step 2: <description>**
...

### Testing Strategy
<omit unless there is something non-obvious: a hard-to-reach path, a fixture that needs
building, a case the existing suite will not catch>

### Risks & Callouts
<omit unless real — a migration, a hot path, a shared component, an irreversible write>
```

#### For Large tickets

```
## Ticket Plan: $KEY-<number> — <title>

**Goal**: <one sentence>

**Size**: Large — <brief justification>

### Blockers & Ambiguities
<from step 4>

### Approach A: <name>
**Summary**: <1-2 sentences>
**Trade-offs**: <pros and cons>
**Steps**:
1. <step with files and rationale>
2. ...
**Estimated scope**: <number of files, rough complexity>

### Approach B: <name>
**Summary**: <1-2 sentences>
**Trade-offs**: <pros and cons>
**Steps**:
1. ...
**Estimated scope**: <number of files, rough complexity>

### Approach C (if applicable): <name>
...

### Recommendation
<which approach and why — but frame it as a recommendation, not a decision>

### Testing Strategy
- <what tests to add or update across any approach>

### Risks & Callouts
- <anything to watch for>
```

### 7. Rules

**Length.** A Small plan is under 200 words, Medium under 350, Large under 600 excluding code
paths. These are caps, not targets.

- **Omit a section rather than fill it.** `Testing Strategy` and `Risks & Callouts` are for a
  plan that has something real to say in them. On a Small ticket they usually do not: drop the
  heading instead of writing "standard unit tests" or "no significant risks", which tell the
  reader nothing and cost them a read.
- **One line per step.** Files, what, why. If a step needs a paragraph it is two steps, or it is
  a decision that belongs under Blockers.
- **No restating the ticket.** The reader has it open. Quote acceptance criteria only where the
  plan turns on the exact wording.
- **Ground the plan in code.** Every step should reference specific files and existing patterns. Don't plan in the abstract.
- **Don't plan linting, formatting, or boilerplate.** Focus on the meaningful decisions and changes.
- **Be honest about unknowns.** If you can't determine something from the codebase, say so — don't guess.
- **Respect existing patterns.** The plan should follow conventions in CLAUDE.md and match how similar features were built. Call out when you're suggesting a deviation and why.
- **Keep it actionable.** Someone should be able to pick up this plan and start working. Steps should be ordered, concrete, and small enough to be a single commit.
- **Use the team.** For large tickets, frame trade-offs in terms the team can evaluate — performance vs. simplicity, short-term vs. long-term, scope risk, etc. The goal is to give the team enough to make a quick decision, not to write a design doc.
