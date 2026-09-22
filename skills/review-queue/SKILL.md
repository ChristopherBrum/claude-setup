---
name: review-queue
description: Pull the pull requests awaiting my review, run an adversarial first pass on each with the reviewer agent, then hand off to pr-review and comments for the one I choose. Use when asked what is in the review queue, what needs reviewing, or which waiting PR to pick up next.
argument-hint: [optional repo or PR number]
---

# Review Queue

Turn "you have N reviews waiting" into a triaged, pre-analyzed queue.

## Input

Optionally a repo (`owner/name`) to scope to, or a single PR number to jump
straight to. Default: PRs awaiting my review in the current repo.

## Steps

### 1. Find PRs awaiting my review

```bash
gh pr list --search "review-requested:@me" --state open --json number,title,author,url,updatedAt
gh pr list --search "assignee:@me" --state open --json number,title,author,url,updatedAt
```

For a cross-repo view, use `gh search prs "review-requested:@me" --state open`. De-duplicate by
PR URL. If a specific PR was named in the request, skip discovery and go straight to it.

### 2. Adversarial first pass (parallel)

For each PR, launch the **`reviewer`** agent (via the Agent tool, `subagent_type: reviewer`) so
the passes run concurrently. Give each agent the PR context and its diff:

```bash
gh pr diff <number>
```

Each `reviewer` returns severity-ranked, verified findings (CONFIRMED/PLAUSIBLE) with concrete
failure scenarios. Do not fix anything here — this is analysis.

### 3. Present the triaged queue

**Three lines per PR, maximum**: number, title and author; the reviewer's verdict; its worst
finding. Order by how much attention each needs, confirmed correctness issues first and clean
PRs last.

This is a queue, not a set of reviews. Its job is to decide which PR to open next, so a clean one
gets a single line and detail waits for `/pr-review`. Never restate a finding the chosen PR's
review will cover in full a minute later.

### 4. Hand off

Ask which PR to work. For the chosen one, run the `/pr-review` flow (full quality/convention
review) and `/comments` (validate and act on existing review comments). The `reviewer` output
from step 2 feeds directly into that review.

## Rules

- Read-only — this command reviews; it never pushes commits or approves/merges PRs.
- Keep the first pass adversarial: prefer a short list of confirmed issues over a long list of
  speculative ones (the `reviewer` agent already enforces this).
