---
name: new-ticket
description: Draft a tracker ticket in the house format (goal, user + developer story, context, bulleted AC) and create it in the configured project after confirmation. Use when asked to write, file, draft, or open a ticket or issue, or to reformat an existing ticket into the house shape.
argument-hint: short description of the work, or an existing KEY-1234 to reformat
---

# New Ticket

Turn a rough idea into a tracker ticket, in the project named by `issue_tracker.project_key` in
`~/.claude/identity.json`. Terse, not lossy: every section is the fewest words that
still carry the information, and no information is dropped to get there.

## Input

A rough description of the work, or a `KEY-1234` key to reformat an existing ticket
in place.

If it is a ticket key, fetch it with the `atlassian` MCP server and rewrite the description in
place. Every existing fact either fits the template or moves to a section below the AC.

## Steps

### 1. Ground it in the code

Before drafting, find the files, models, endpoints, or flags the work touches. Context bullets
name real things (`app/services/orders/…`, `order_services`, a flag name), never generic
placeholders. If you cannot find the surface, say so and ask rather than inventing one.

When reformatting, re-verify every `file:line`, method, and constant the ticket already cites;
they drift. Correct what moved, and say so in the ticket where a premise no longer holds (a
renamed class, a restructured CI job) rather than silently rewriting around it.

### 2. Draft

```markdown
<1-2 sentences: the goal. What changes and why. No preamble, no restating the title.>

## User Story

**User:** As a <role>, I want <capability> so that <outcome>.

**Developer:** As a developer, I need <technical change> so that <system outcome>.

## Context

- **Surface:** <portal / endpoint / model / job, plus any feature flag>
- **Today:** <current behavior, one line>
- **Expected:** <what it should do instead, one line>
- **Impact:** <who is blocked or harmed, and how badly>

<optional table, only when the bug is a chain, see rules>
| Step | Location |
|---|---|
| <what happens> | `file:line` or `Class#method` |

## Acceptance Criteria

- <observable, verifiable outcome>
- <one per criterion>

<sections the four Context bullets cannot hold, each under its own heading: Evidence,
Measurement, History, Decision needed, Out of scope. Verbatim detail lives here.>
```

Rules for the draft:

- **Context** is those four bullets, in that order, one line each. The labels are fixed: never
  invent a new one. Implementation hints belong in the developer story or an AC line.
- **Detail that will not fit those four goes below the AC**, under its own heading. Never delete
  it: query output, trace IDs, probe transcripts, code snippets and option analysis are the
  expensive part of a ticket. Context stays scannable; the proof sits underneath.
- **The optional table** appears only for a defect worth tracing as a chain, with homogeneous
  columns (`Step | Location`) and no cell longer than one line. Never a key/value table of mixed
  facts; if you are writing sentences in a cell, it was a bullet.
- **User story** is exactly two lines, one each. If the change has no end user (refactor, job,
  internal API), the user line names the indirect beneficiary (ops, QA, a partner) and says so.
- **Acceptance criteria** are plain bullets, 3 to 7, each verifiable by someone who has not read
  the code. State the observable outcome, not the implementation. No "code is reviewed", no
  "tests pass": those are process, not criteria.
- **An open question becomes an AC line**, phrased so it can be checked off: "whether X applies
  is decided and recorded on this ticket". A ticket blocked on a decision says so in its AC.
- Title: imperative, under 80 characters, no ticket prefix.
- No em dashes anywhere in the ticket.
- If a sentence would only tell the reader what the title already says, cut it.

### 3. Confirm, then create

Show the draft. Creating and editing Jira issues is outward-facing, so wait for an explicit go
ahead (see "Jira access" in `~/.claude/CLAUDE.md`), then create it in project `ENG` with the
`atlassian` MCP write tool. Ask for issue type only if it is not obvious from the work.

Write the AC as a plain markdown bullet list. Checkboxes cannot survive this tool: `- [ ]` and
`[]` come back as literal brackets, an ADF `taskList` is dropped, and `☐` reads worse than a
bullet. Only the Jira editor converts them, client side. Do not retry these.

Return the issue key and URL.

## Rules

- Never create or edit a Jira issue without the user's go ahead.
- One *new* ticket per invocation: scope creeping into a second means saying so, not writing
  both. Reformatting a batch of existing tickets is fine.
- Unknowns go to the user as questions before the draft, not into the ticket as vague AC.
