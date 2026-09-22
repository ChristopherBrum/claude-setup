---
name: ci-check
description: Check CI status for a pull request, categorize each failure, and say whether it is this branch's fault, a flake, or already broken on the base branch. Use when CI is red, a check or build failed, a PR is blocked by a failing job, or someone asks why the pipeline is failing.
argument-hint: [optional PR number]
---

# CI Check — failure analyzer

Check CI for a PR and diagnose the failures. The goal is to save digging through logs, and to
answer the one question that decides what to do next: **is this my change, a flake, or already
broken on the base branch?**

## Input

A PR number, if one was given. If not, use the PR for the current branch.

## Step 0 — Learn this project's toolchain

Read `.claude/PROJECT.md` for the test, lint, and build commands and the base branch. You need
them to reproduce a failure locally and to give an auto-fix command that actually exists here.
Do not infer them from the language.

## Steps

### 1. Identify the PR

```bash
gh pr view --json number,headRefName
```

### 2. Get CI status

```bash
gh pr checks <number>
```

If everything passes, say so and stop.

### 3. Fetch the failed job logs

```bash
gh run view <run-id> --log-failed
```

Fetch multiple failed jobs in parallel.

### 4. Categorize each failure

**Test failure.** Extract the file path, test name, and message. Read the test, and the code it
covers if the message points at a line. Then classify:

- **Caused by this branch** — the diff touches the code under test, or the failure names
  something the diff changed.
- **Flaky** — timing or ordering sensitive, shared state between tests, a fixed sleep, a
  wall-clock or timezone assumption, a browser timeout, a counter shared across runs. Check
  whether the same job has failed intermittently before concluding.
- **Pre-existing** — already failing on the base branch. **Verify rather than assume**: check
  whether the failing file is in the diff at all, and look at the base branch's recent runs.

Reproduce it locally with the project's targeted test command from `PROJECT.md` when the failure
is plausibly real. An observed local failure beats a guess from a log, and a test that passes
locally but fails in CI is itself the finding.

**Lint failure.** List the violations with file paths and rule names, grouped by file. Say which
are auto-fixable and give the project's actual fix command.

**Build or compile failure.** Extract the root cause, not just the last line. A missing
dependency, a stale lockfile, and a real type error read similarly in a log and need different
fixes.

**Timeout or infrastructure.** Which job, how long, and whether it is the job that is slow or
the runner. Not a code failure; say so plainly rather than proposing a code change.

### 5. Report

```
**CI: PR #<number> — <PASS|FAIL>**

**<job name> — FAILED**
• <category>: <one line>
• `<path>:<line>`
• Cause: <this branch | flaky | pre-existing | lint | infra>
• Next: <the specific command or change>
```

For a test failure include the trimmed failure message (the relevant lines, not the whole stack
trace) and whether the file is in this branch's diff.

For a flake, say why you believe it is one, and give the rerun command:
`gh run rerun <run-id> --failed`.

**Do not rerun CI, push, or edit code.** This command diagnoses. Fixing is a separate step, and
rerunning a genuinely failing job just burns time.

**Four lines per failed job, and 150 words for the whole report** excluding quoted log output.
A list of categorized failures with one next step each beats a narrative. Do not explain what the
job does, do not summarise the diff, and do not paste a stack trace when three lines of it carry
the cause.
