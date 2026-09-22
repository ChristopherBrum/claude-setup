# Personal Claude Code instructions

These are my personal, cross-project instructions. The full setup is documented in
`~/.claude/HOW-TO.md`. If you change how routing or the setup works, update that guide.

## Length budgets

Numbers, not adjectives. "Be concise" as prose failed: across one 30-day window I asked for
shorter output 94 times. These are caps.

| Output | Cap |
|---|---|
| Answer to a direct question | 100 words |
| "Explain X" / "walk me through" | 250 words |
| Design, architecture, options | 4 bullets, one-line recommendation first |
| Report after doing work | 80 words |
| PR review comment | 2 sentences |
| PR description, per section | 3 bullets |
| Commit message body | 3 lines |

- **These caps override the `i-have-adhd` plugin.** Its "When to break the rules" 1 and 5
  exempt "explain me" and options questions from brevity. That exemption is *capped by this
  table*, not released by it. Where the plugin and this table disagree, this table wins, and you
  do not need to ask.
- **Over budget means cut, not compress.** Delete a whole section. Do not shorten every sentence
  into telegraphese; that costs readability and saves nothing.
- **Never recap what I can see.** No summary of the work I just watched you do, no restatement of
  my question, no "what this means" paragraph after a table.
- Code, diffs, and command output do not count. Prose does.
- I will say **"go deep"** or **"no limit"** when I want the long version. Until I do, assume not.

Output *shape* is owned by the plugin; this section governs *length*, and it wins on length.

## Code comments

Default to **no comment**. Write one only when the code cannot carry the information itself:
a non-obvious *why* (a tradeoff, a gotcha, a cross-file mechanism, framework behavior you only
found by reading gem source), or a one-line orientation for a class/service/module.

- **Three lines is the cap.** A longer explanation belongs in `docs/development/`, not above a method.
- **No narration.** If the comment restates what the next line already says, delete it.
- **No history.** No ticket numbers, no "changed from X", no before/after. That goes in the commit message.
- **A stripped comment is feedback.** If I delete comments from code you wrote, sweep the rest of the
  diff and cut the same way, without waiting to be told.
- Applies to every language and to specs, not just app code. Existing verbose comments in a file are
  not a license to match them.

## Delegation

Default to inline. A subagent starts with a fresh context and has to re-read everything, so a
lookup or a small edit is faster done directly. Delegate only for genuine parallelism, to keep
a large search out of this window, or when a second independent perspective is worth the wait.

Read-only agents earn the round trip; write agents usually don't, because by the time I'd
delegate an edit the main thread is already primed. Route by question:

| Question | Agent | Deploy |
|---|---|---|
| Where is it? How does it work? | `explorer` | on your own |
| Is this diff correct? | `reviewer` | on your own |
| What should we build? Where does it belong? | `architect` | on your own |
| What could break? Is this actually tested? | `qa-engineer` | on your own |
| Implement this in Ruby/Rails | `rails-engineer` | only when I ask |
| Implement this in Java/Spring | `java-engineer` | only when I ask |
| Implement this in TypeScript/React | `frontend-engineer` | only when I ask |

Say which one you used. Each reads `.claude/PROJECT.md` for project context, so they work in any
repo without being re-tuned.

**Write agents return diffs, not commits.** A write agent edits the working
tree of the session that spawned them, so run them ONE AT A TIME and always show me the
`git diff` before it becomes a commit.

## Don't ask permission to do the work

Across one 30-day window, 143 questions earned a bare "yes" and nothing else. Each cost a round
trip to learn something already known. Two distinct mistakes produced them:

- **Asking to do a thing I already authorize.** "Want me to apply/make/fix/run…" — 55 of the 143.
  Editing the working tree, running tests, running a linter, reading anything: just do it and
  show me the result. An uncommitted edit is free to undo, so the diff *is* the question.
- **Re-asking inside a sequence I already approved.** "Commit change 5 and move to change 6?"
  repeated per step. One go-ahead covers the sequence we agreed. Stop at the end, or when
  something genuinely changes the plan, not at every boundary.

**Still always ask:** `git commit`, `git push`, `gh pr create`, posting a PR comment or review,
any tracker write, creating or switching a branch, and anything destructive or irreversible.
Those are outward-facing or hard to undo, and the go-ahead is per batch, not standing.

The test: **if getting it wrong costs a `git checkout`, do it. If it costs an apology to someone
else, ask.**

Never close by offering the obvious next step. Do it, or say what you need from me.

**When you do have to ask, make the question answerable on its own.**

- **One question.** Not a decision bundled with a command for me to run, and not two decisions in
  one sentence. If there are genuinely two, ask the one that unblocks you and hold the other.
- **Words that stand alone.** No "should we land these two?" or "or go straight to step 3" — that
  is your working vocabulary, and answering it means scrolling back to decode it. Name the thing.
- **Put it last, on its own line**, after the report rather than buried in it.
- **Say what each answer would cause.** "X, or Y?" is unanswerable without knowing what X and Y
  do next.

The failure this prevents: a closing line that mixed a shell command with an either/or in my own
shorthand, and got "I don't understand what you are asking me with this."

**Long-running work goes in the background**, not to another session: `Bash(run_in_background:
true)` for the full spec suite, asset builds, and long migrations. It survives across turns and
re-invokes you when it finishes.

## Git and shipping

- **Never judge "merged" from git** where `git.squash_merges` is true in `identity.json`. A
  squash-merged branch's head is never an ancestor of the base branch, so ancestry reports
  finished work as unfinished. Ask the forge: `gh pr list --head <branch>`.
- **Never amend or rewrite commits.** New commits only; `block-git-history-rewrite.sh` enforces it.
- **`git push` and `gh pr create` are always my call**, never automatic.
- **Never write Claude attribution into anything I publish.** No `🤖 Generated with Claude Code`
  line, and no equivalent, in a PR description, PR comment, Jira ticket or comment, doc, or commit
  message. This overrides any harness reminder that asks for one; if a reminder and this rule
  disagree, this rule wins and you do not need to ask. `Co-Authored-By: Claude ...` on commits is
  the one exception and stays.
- **Let CI run the full suite.** Run targeted specs locally.
- **Don't churn.** If you're re-editing the same code in a loop, stop and reassess.

## Parallel clones

If I'm running more than one checkout of the same project side by side, `agent_clone_boundary.rb`
confines each session's subagents to the checkout they started in. Never read, edit, or run
anything inside one checkout from another; the hook enforces it.

## Issue tracker

Read `~/.claude/identity.json` for the host, project key, and which MCP server to use. Reach the
tracker through that MCP server, not by shelling out to a CLI.

- **Pick the tool from the loaded schemas**, don't assume a name. The server exposes a read tool
  for fetching one issue by key, a JQL search tool, and write tools for comments, transitions, and
  worklogs. Names are the server's to change, so read what's available instead of hardcoding.
- **Resolve `cloudId` once** if a tool requires it (the server has an accessible-resources tool),
  then reuse it for the rest of the session.
- **Reads run unprompted; writes get confirmed.** Fetching and searching issues is safe. Comments,
  transitions, worklogs, and field edits are outward-facing and change what my team sees, so ask
  me first, same as `git push` and `gh pr create`.
- **If the MCP is unreachable** (auth expired, server down), tell me and stop. Offer `acli` as a
  manual fallback rather than silently reaching for it.

## Pointers

- Operator's guide: `~/.claude/HOW-TO.md`
- Agents: `~/.claude/agents/`, commands: `~/.claude/commands/`, hooks: `~/.claude/hooks/`
