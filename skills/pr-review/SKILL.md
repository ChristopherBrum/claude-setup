---
name: pr-review
description: Review a pull request for correctness, security, and convention adherence, then draft question-shaped inline comments anchored to file and line, post them on a go-ahead, and call an explicit merge verdict. Use when asked to review a PR, check someone's diff before merge, or look over changes on a branch.
argument-hint: [optional PR number]
---

# PR Review

Review a pull request for code quality, correctness, and adherence to project conventions.

## Input

A PR number, if one was given. If not, use the PR associated with the current branch.

## Steps

### 1. Gather context

Run these in parallel:

**PR details:**

```bash
gh pr view <number> --json title,body,headRefName,author,files,additions,deletions
gh pr diff <number>
```

**Existing feedback, which is the baseline:**

```bash
gh api "repos/{owner}/{repo}/pulls/<number>/comments" --paginate \
  --jq '.[] | "\(.user.login) \(.path):\(.line) \(.body)"'
```

Prior human and Copilot comments set the floor. Don't re-raise what someone already said; add
what they missed, and note an unresolved thread in one line rather than opening a second one.

**Ticket:** Extract the ticket number from the `headRefName` field in the `gh pr view` response (not the current local branch), then fetch `<issue_tracker.project_key>-<number>` through the MCP server named in `~/.claude/identity.json` (see
"Issue tracker" in `~/.claude/CLAUDE.md`).

### 2. Understand the intent

Before reviewing code, establish what this PR is supposed to do by reading the Jira ticket description and acceptance criteria alongside the PR description. This is the lens for the entire review — changes should be evaluated against what was asked for, not in the abstract.

**Then check the body against the diff, and let the diff win.** A body that says "rename only", "no behavior change", "idempotent" or "blocked on X" while the diff says otherwise is itself a finding. Never carry a body claim into the review as established fact.

### 3. Active pattern and reuse discovery

Before reviewing the diff, search the codebase for context. Don't rely on passive reading — actively look:

- **Existing patterns**: If the PR adds a new service object, job, serializer, or controller action, find 2–3 existing examples of the same type and compare the structure. Flag deviations that aren't explained by the ticket.
- **Reuse opportunities**: If the PR implements something (a helper method, a query scope, a formatting utility), grep for existing code that does the same or similar thing. Flag duplication that could be avoided. Before recommending existing code be reused, read it to confirm the interface and behavior actually match the use case — don't suggest it based on name alone.
- **Prior art**: If the ticket domain has been touched before (e.g., same model, same workflow), read those files to understand established conventions that may not be in CLAUDE.md.

### 4. Review the diff

**Verify before flagging.** The diff shows what changed, not the full picture. Before raising any issue, confirm it by reading the relevant code — don't rely on what's absent from the diff. Things that look missing are often present in a parent class, concern, callback, `before_action`, or a file not touched by this PR. A finding you haven't verified is a question, not an issue.

Read the full diff and evaluate against these categories. Only flag things that actually matter — do not nitpick style, formatting, or anything this project's linters already enforce.

**Correctness**

- Does the code do what the Jira ticket asks for? Are any acceptance criteria missed?
- Are there logic errors, off-by-one mistakes, or unhandled edge cases?
- Are database queries correct? Watch for N+1s introduced by new associations in serializers or views without corresponding `includes`. Before flagging an N+1, check the controller or scope that loads the data — eager loading may already be in place outside the diff.
- For state machine or workflow changes: are all transitions valid? Are callbacks in the right order?
- Before flagging any behavior as missing: read the full file to confirm it isn't handled in a `before_action`, callback, concern, or parent class.

**Security**

- SQL injection: string interpolation in `where` clauses
- Mass assignment: unpermitted params in controllers, overly broad `permit`
- XSS: use of `raw` or `html_safe` with user input
- Authorization: missing `authorize` calls or Pundit policy checks
- Exposure: sensitive data leaking into serializers, logs, or API responses

**Data integrity**

- Migrations: are they reversible? Do they need `safety_assured`? Are indexes added for new foreign keys or columns used in lookups?
- Are there changes that could break existing data? (e.g. removing a column that's still referenced, changing a default)
- Are background jobs idempotent?

**Deployment safety**

- Long-running migrations that could lock tables: adding columns with defaults on large tables, indexing without `CONCURRENTLY`, removing NOT NULL constraints
- Background job argument changes while old jobs may still be enqueued — are old argument shapes still handled?
- Any ordering dependency between the deploy and a migration that could cause downtime?

**Dependencies**

- Is the lockfile diff reviewed, not just the manifest? One direct bump pulls transitives.
- For a version bump: does the PR cite the changelog, or only the version number? A patch release can still carry a behavior change.
- For a new dependency: does the existing stack already do this?

**Performance**

- New queries on large tables without indexes
- Expensive operations inside loops
- Missing eager loading for associations used in serializers
- Background jobs that should be async but are inline (or vice versa)

**Concurrency and race conditions**

- State machine transitions that aren't atomic — can two requests race to the same transition?
- Background jobs that read-then-write without a lock
- Counter cache updates or balance calculations that could race under concurrent requests

**Frontend/backend contract**

- If a serializer field is added, removed, or renamed — or a GraphQL type changes — are the frontend consumers updated in the same PR?
- If the diff only touches the backend, flag any serializer/type changes that may silently break the frontend

**Test quality**

- Do new tests actually exercise the critical paths introduced? A test that only checks `have_http_status(:ok)` is not meaningful coverage.
- Are edge cases and failure paths tested, not just the happy path?
- Are tests using real objects and factories rather than mocks where possible?

**Structure**

- Is a new conditional bolted onto an unrelated flow? Repeated conditionals on the same shape mean a missing model or dispatcher, not a nit.
- Does a refactor reduce complexity or relocate it? Count the concepts a reader has to hold to follow the change; an unchanged count means it isn't cleaner.
- Is feature-specific logic landing in a shared module, or is this a near-duplicate of an existing canonical helper?

**Conventions** (only flag deviations from CLAUDE.md patterns)

- Service objects: do they follow `ServiceName.new(params).call`?
- Serializers: inheriting from `BaseSerializer`, using `delegate` for simple attributes?
- Tests: using factories, real objects over mocks, correct `context` wording?
- GraphQL: using Input Objects instead of strong params?
- Before flagging a convention violation, find an actual example of the correct pattern in the codebase to confirm your understanding — don't rely solely on CLAUDE.md descriptions.

**Debug artifacts**

- Grep the diff for: `binding.pry`, `byebug`, `binding.irb`, `console.log`, `debugger`, `puts`, `p ` — flag any that remain.

**Scope**

- Are there changes that go beyond the Jira ticket? Unrelated refactors, drive-by fixes, or feature creep?
- Is anything from the acceptance criteria missing from the diff?

### 5. Read related code and assess caller impact

Don't review the diff in isolation. For any change that touches a model, service, or controller:

- Read the full file (not just the diff) to understand surrounding context
- Before flagging missing test coverage: search for the spec file and read what's already covered — don't assume it's absent because it's not in the diff
- If a method signature, return value, or serializer shape changed: grep for all callers, then **read them** — don't just list the files. Determine whether each caller actually needs updating before flagging it as an issue. A caller that already handles the new shape is not a problem.

### 6. Output the review

The deliverable is **inline comments anchored to a specific file and line**, not a prose report. Default to `event: COMMENT` so nothing blocks merge.

**Where the team's standard governs, and where it doesn't.** `.claude/PROJECT.md` names the project's checked-in review standard when one exists. It owns the order of work and what a review has to cover; read it every run rather than caching what it said. It does not own the comment voice. Findings stay question-shaped here, and the blocking / `NB:` split *is* this review's answer to a must-fix versus nit separation. Do not adopt a standard's severity tags (`**[Critical]**`) or its `Fix:` lines, and do not treat the difference as drift to be corrected.

**Comment style. This is the whole point:**

- **Every finding is a question**, even the ones you are certain about. "Can a photo still be added after the quote is paid?" not "This allows photos after payment."
- **One or two sentences.** If it needs a paragraph, it needs a conversation, not a comment.
- **Don't explain the code back to the author.** They wrote it. The mechanism, the trace, and the failure scenario were how *you* got confident; they are not the comment. Ask the question the trace led you to.
- **No severity tags, no "Suggested fix:", no preamble.** One exception: decide blocking-or-not per finding *before* drafting, and prefix every non-blocking one with `NB: ` so the author can triage the thread at a glance. Blocking findings post unprefixed. This applies to a top-level body too when the body itself is non-blocking.

Good:

> Can someone burn through the limit on a notice they don't own and lock the real loader out?
> Should `create` be authorized the way `new` is?
> Is `location` always present here?

Bad:

> **[Critical]** The throttle key is the availability notice id with no caller component, so an unauthenticated attacker who guesses a sequential id can send 60 requests and exhaust the bucket, causing the legitimate driver's acceptance to 429 for the rest of the window. Suggested fix: include `req.ip` in the key.

**Resolving anchors.** A comment only posts if its line is part of the diff. Get new-side line numbers for a file:

**Resolve the repo and your login once, never hardcode them.** A baked-in slug silently reports
on the wrong repository when the command runs from another checkout:

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
ME=$(gh api user --jq .login)
```

If either fails (not a repo, no remote, not authenticated), say so and stop rather than falling
back to a default.

```bash
~/.claude/bin/pr-diff-lines <pr> <path> [first] [last]
```

It resolves the repo itself and prints only new-side numbers, which are the only ones a comment
can anchor to. Exit 2 means the file is not in the diff. Use the script rather than an inline
`gh api | awk` pipeline: a one-line shell function trips the expansion-obfuscation check and
prompts on every review.

If the code you want to point at isn't in the diff, anchor on the nearest changed line that introduces the risk and name the real location inside the question ("Will `order_spec.rb:1262` fail on overnight CI runs?").

**Draft first, then post.** Show every draft in chat with its `file:line` anchor and wait for a go-ahead. Posting is outward-facing, same rule as `git push` and `gh pr create`. Then:

```bash
gh api "repos/$REPO/pulls/<number>/reviews" --input - <<'JSON'
{"event":"COMMENT","comments":[
{"path":"config/initializers/rack_attack.rb","line":83,"side":"RIGHT","body":"Can someone burn through the limit on a record they don't own and lock the real user out?"}
]}
JSON
```

Verify what landed instead of trusting the exit code:

```bash
gh api "repos/$REPO/pulls/<number>/comments" --paginate \
  --jq --arg me "$ME" '[.[] | select(.user.login==$me and (.created_at > "<iso8601>"))] | length'
```

**Hand the PR back.** Posting comments moves the ball to the author, so swap the assignment in the same step:

```bash
gh pr edit <number> \
  --add-assignee "$(gh pr view <number> --json author --jq '.author.login')" \
  --remove-assignee "$ME"
```

Leave any other assignees in place; only your own comes off. Confirm with `gh pr view <number> --json assignees,reviewDecision`.

**Call the merge verdict, in chat, not on the PR.** Every review ends with a straight answer to "is this OK to merge as-is?" Never a pile of observations the reader has to score themselves. One of three:

- **Merge it.** Nothing in the diff should change. Open questions are fine here, but say plainly that none of them would alter the code, so they don't read as blockers.
- **Merge after one change.** Name the change and the smallest version of it.
- **Don't merge.** Name what breaks and who it breaks for.

Then note any acceptance criteria gaps and what you verified as clean, so neither gets re-litigated. Keep a *ticket*-closure problem separate from a *merge* problem: an AC that can't be satisfied is not automatically a reason to hold the code.

**The chat summary is capped at 150 words.** Verdict line, the findings as one line each, AC gaps, and a short "verified clean" list. It is a summary of comments the reader can already see on the PR, so anything that restates a comment in full is waste. No preamble, and no closing paragraph about what the change means.

**Approving** happens only on an explicit ask. When the verdict is "merge it," say so and offer.

**Rules:**

- Verify before you ask. The verification work still happens in full, it just doesn't ship in the comment.
- Order comments most severe first, and lead the chat summary with the worst one.
- Don't pile on. The same pattern across five files gets one comment noting it applies elsewhere.
- More than about five comments on one PR means the review belongs in a conversation, not a comment thread.
- Skip anything a linter already enforces. `.claude/PROJECT.md` names which linters this project runs; a comment on something a tool catches automatically is noise on every PR.
- If it's clean, post nothing and say so.
