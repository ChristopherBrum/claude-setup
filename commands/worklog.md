---
name: worklog
description: Capture what this session actually asked for and what it revealed about the setup — manual patterns worth automating, corrections worth acting on, traps worth recording. Not a diary.
argument-hint: [optional notes to include]
---

# Worklog

Record what this session revealed about **how I work with Claude**, so `/setup-review` has
something to aggregate. The point is not what got built; git already knows that. The point is
what I had to ask for by hand, where I had to correct course, and what tripped us up.

## Input

$ARGUMENTS — Optional: anything I want included that you would not infer.

## Step 1 — Read the session, don't recall it

```bash
~/.claude/bin/claude-prompts --session "$CLAUDE_CODE_SESSION_ID"
```

**That output is ground truth and outranks your memory of this session.** If they disagree, it is
right and you were compacted. It spans the whole session including any pre-compact stretch, which
is exactly the part you no longer remember.

If it returns nothing, say so in the entry and fall back to recall, clearly labelled. A
paraphrase presented as a quote is worse than an admission.

For what was delegated and which commands ran:

```bash
~/.claude/bin/claude-usage | sed -n '/DELEGATIONS/,/SLASH/p'
```

## Step 2 — Write the entry

Append to `~/.claude/worklogs/$(date +%F).md`, creating the file if needed. Multiple sessions in
one day each get their own `## Session HH:MM` heading; never overwrite an earlier one.

```markdown
## Session <HH:MM> — <project>  ·  `<branch>`

**<one sentence: the one thing this session revealed about the setup, or "nothing new">**

### Worth changing
- **<what>** — <what happened, with a count> → <the file it belongs in>

### Traps
- **<the trap>** — <the symptom, so it is recognisable next time> → <where it is recorded, or
  "not recorded">

### Still open
- <unfinished work, decisions owed>

<details><summary>What I typed (N prompts)</summary>

```
HH:MM  <verbatim, oldest first, ~150 chars>
```
</details>
```

## Rules

- **Lead with the single finding.** If a reader stops after the bold line they should have the
  point. "Nothing new" is a valid and common answer for a routine session, and writing it is
  more useful than manufacturing three bullets.
- **Only sections that have content.** Drop any heading with nothing under it. Do not write
  "none" to fill a section, and do not add a section the template does not list.
- **No "Done" section.** Git and the PR already record what was built. This file exists for what
  the session revealed about *how we work*, which is the part nothing else captures.
- **Each entry under "Worth changing" names the file it belongs in**: `CLAUDE.md`, a
  `PROJECT.md`, a specific agent, a specific command. A finding with nowhere to go is an
  observation, and observations do not go in this file.
- **Separate the two kinds of correction, and only log the second.** I changed my mind =
  task-specific, skip it. A rule that exists and did not fire, or does not exist yet = a finding.
- **Quote me verbatim** in the collapsed prompt list, and keep it collapsed and last. It is a
  memory aid for a reader who ran several sessions that day, not the substance.
- **Delegation only when there was any.** One line: agent, count, what for, and whether you
  verified its load-bearing claims. `No` is legitimate and more useful than a flattering answer.
  Omit the heading when nothing was delegated, and note the absence in the lead sentence if it is
  itself surprising.
- **Do not log ticket status or code detail.** That belongs in the tracker and the PR.
- Worklogs live outside every repo, in `~/.claude/worklogs/`, gitignored. They quote real work,
  so they never belong in a published config repo.

## Step 3 — Report

Tell me: the file path, the manual patterns you found (these are the candidates), and any
correction you classified as a setup gap. Keep it to a few lines; the file has the detail.

## Step 4 — Ask how it went, once

One `AskUserQuestion`, at the very end, never mid-session:

- **Header:** `Session` · **Question:** "How did this session go?"
- **Options:** `5 — went well` / `3 — mixed` / `1-2 — something went wrong` / `Skip`

If I pick a rating, ask inline for one line on why, then append to
`~/.claude/worklogs/feedback.jsonl`:

```json
{"date":"YYYY-MM-DD","time":"HH:MM","project":"<name>","rating":N,"tag":"approach|quality|communication|scope|general","note":"<my words>"}
```

Use **my** words for the note, not your paraphrase. Pick the tag from what I said. If I skip,
write nothing and do not ask again this session.

A low rating is the valuable case. Record it plainly, do not argue with it, and do not append
your own explanation to my note.
