---
name: comments
description: Fetch every review comment on a pull request, from humans and from Copilot, validate each one against the actual code, and return a prioritized plan for addressing them. Use when asked what the reviewers said, to triage or work through PR feedback, or to decide which review comments are worth acting on.
argument-hint: [optional PR number]
---

# PR Comments — Reviewer Feedback Analyzer

Fetch all review comments left on a pull request (from GitHub Copilot and human reviewers), assess each comment's validity against the actual code, and produce a prioritized plan for addressing them.

## Input

A PR number, if one was given. If not, use the PR associated with the current branch.

## Steps

### 1. Identify the PR

If no PR number was given:

```bash
gh pr view --json number,title,headRefName,baseRefName,headRepositoryOwner,headRepository
```

Extract the PR number, owner login, and repo name from the response. If a PR number was given, fetch the same fields for that number to get the owner/repo context.

### 2. Fetch all review feedback in one query

Use the GraphQL API to get review threads (with resolved/outdated state), review summaries, and top-level PR comments together:

```bash
gh api graphql -F owner='<owner>' -F repo='<repo>' -F number=<number> -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      title
      author { login }
      reviews(first: 50) {
        nodes {
          author { login }
          body
          state
          submittedAt
        }
      }
      reviewThreads(first: 100) {
        nodes {
          isResolved
          isOutdated
          comments(first: 50) {
            nodes {
              author { login }
              body
              path
              line
              originalLine
              createdAt
              url
            }
          }
        }
      }
      comments(first: 100) {
        nodes {
          author { login }
          body
          createdAt
        }
      }
    }
  }
}'
```

This returns three categories of feedback in one request:

- **Review summaries** under `reviews` — top-level "APPROVED", "CHANGES_REQUESTED", or "COMMENTED" submissions with an optional summary body
- **Inline diff comments** under `reviewThreads` — grouped into threads with `isResolved` and `isOutdated` flags
- **Issue-style PR comments** under `comments` — top-level non-review chatter

**Filter aggressively before analyzing:**

- Skip threads where `isResolved: true` — already addressed
- Skip threads where `isOutdated: true` — code has moved on
- Skip comments authored by the PR author (`comments[].author.login == pullRequest.author.login`) — these are usually replies or status updates from the engineer themselves

### 3. Read the diff for context

```bash
gh pr diff <number>
```

This is the lens for assessing comments — without seeing what changed, you can't judge whether a comment is on point.

### 4. Assess each unresolved comment

For each unresolved comment, do this in order:

1. **Read the code** at `path:line` (use the `originalLine` if `line` is null — happens on outdated lines that aren't fully outdated). Don't take the reviewer's claim at face value; verify by reading the actual surrounding code.
2. **Classify** the comment:
   - **Bug/Correctness** — points to a real defect, missing edge case, or broken behavior
   - **Suggestion** — proposes an alternative or improvement that doesn't indicate a bug
   - **Question** — asks for rationale or clarification; doesn't necessarily require a code change
   - **Style/Preference** — naming, formatting, or opinion-level
   - **False positive** — common with Copilot: generic "consider null check / extract method / add error handling" advice that doesn't fit the actual context
3. **Assign a priority**:
   - **High** — bugs, security issues, missing acceptance criteria, anything blocking merge
   - **Medium** — clear improvements worth taking, valid convention deviations called out in CLAUDE.md
   - **Low** — stylistic suggestions, optional refactors
   - **Dismiss** — false positives, suggestions that conflict with project conventions, questions you can answer without a code change

**Be especially skeptical of GitHub Copilot reviews.** Copilot pattern-matches against generic best practices and frequently surfaces suggestions that contradict the codebase's actual conventions (e.g. "you should validate this input" when validation happens in a parent class, "consider extracting this" for code that's already in its own service object). Use CLAUDE.md and the surrounding code as the source of truth, not the comment.

### 5. Output the plan

Structure the output like this:

```
**PR Comments: #<number> — <title>**

**Reviewers**: <distinct author logins, comma-separated>
**Threads**: <unresolved-count> unresolved / <total-count> total (<resolved-or-outdated-count> already handled)

## Blocking: <n>
<one line each: `file:line` — what must change. Or "None — nothing here blocks merge.">

## Non-blocking: <n>
<one line each, no detail>

---

### High priority
**`<file>:<line>`** — @<reviewer>  ([thread](<url>))
> <short quote or paraphrase of the comment>

**Assessment**: <real bug, confirmed issue, etc. — one or two sentences>
**Plan**: <concrete action — what code to change, what to update, where>

### Medium priority
**`<file>:<line>`** — @<reviewer>  ([thread](<url>))
...

### Low priority
**`<file>:<line>`** — @<reviewer>  ([thread](<url>))
...

### Dismiss or push back
**`<file>:<line>`** — @<reviewer>  ([thread](<url>))
> <quote>

**Why dismiss**: <false positive, conflicts with project pattern X, already handled elsewhere, etc.>
**Reply suggestion**: <what to say in response if a reply is warranted>
```

**Rules:**

- **Lead with the blocking split and never make me ask for it.** Every comment is blocking or it
  is not, and that is the only question that decides what happens next. Blocking means: a real
  defect, a security or data-integrity problem, a missing acceptance criterion, or a reviewer who
  will not approve without it. A valid suggestion that does not hold up the merge is not
  blocking, however good it is.
- **When nothing blocks, say "None" and say it first.** That is the most useful output this
  command produces and it should not be buried under four priority sections.
- Read the code at each `path:line` before assessing — don't trust the comment alone. Verifying takes seconds and prevents acting on bad input.
- **Two sentences per assessment, two per reply suggestion.** A draft reply longer than that gets
  sent back to be cut, every time.
- Group by priority, not by reviewer or thread — the engineer wants to know what to fix first.
- Quote sparingly. Paraphrase if the original comment is long; quote verbatim only when the exact wording matters for nuance.
- Be specific about the plan. "Update `foo` to use `bar` at `file.rb:42`" is useful; "address this comment" is not.
- For questions, the "plan" is the answer to give back, not a code change.
- If the PR has zero unresolved threads, say so and stop — no analysis needed.
- Acknowledge good work where it shows up. If a reviewer left a positive comment ("nice fix here"), it's fine to mention briefly under a "Notes" section at the end — but don't manufacture this.
