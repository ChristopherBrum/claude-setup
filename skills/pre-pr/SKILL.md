---
name: pre-pr
description: Pre-flight gate before a branch leaves the machine. Runs the project's targeted lint, typecheck, and affected tests on the branch diff, then an adversarial reviewer pass, so nothing reaches CI that a fast local check would have caught. Use before pushing a branch or opening a pull request, including whenever a PR is about to be created, and when asked whether a branch is ready to ship.
argument-hint: [optional base branch]
---

# Pre-PR

The gate to run before pushing or opening a PR. Catches what CI would catch, plus a review pass,
locally and fast.

## Step 0 — Learn this project's toolchain

**Read `.claude/PROJECT.md` before running anything.** Its `## Toolchain` section names the real
commands for this project, and its `## Git` section names the base branch. Do not assume a test
runner, a linter, or a package manager from the language: two projects in the same language
routinely disagree about all three.

Resolve the base in this order: a base branch passed in as an argument, then `PROJECT.md`'s base branch, then
`git.default_base` in `~/.claude/identity.json`, then the remote's default. Diffing against the
wrong base silently reviews someone else's commits.

If `PROJECT.md` is missing, infer the toolchain from the build file (`package.json`, `pom.xml`,
`Gemfile`, `Makefile`, `go.mod`) and **say so in the report**, because an inferred command that
silently does nothing is the failure mode this step exists to prevent. Then offer to write a
`PROJECT.md` so the next run is not guesswork.

## Steps

Only step 1 must finish first. Steps 2-4 are independent of each other, and step 5 reads the
diff rather than the check results, so run all four concurrently: kick off lint, typecheck, and
tests as background Bash and launch the `reviewer` agent in the same batch, then collect in step
6. Don't serialize what has no dependency.

### 1. Scope the diff

```bash
git fetch origin
git diff "$BASE" --diff-filter=d --name-only
```

Group the changed files by type. You only check what changed, and you only run the checks that
apply to the types present: a Ruby-only diff does not need a typecheck.

### 2. Lint the changed files

Use the lint command from `PROJECT.md`, passing only the changed files it applies to. Most
projects have more than one linter covering different file types; run each against its own
subset. The general shape:

```bash
<lint command> $(git diff "$BASE" --diff-filter=d --name-only | grep -E '<pattern for that linter>')
```

Passing an empty file list makes some linters lint the entire repo. Skip the linter instead when
its subset is empty.

### 3. Typecheck

Only if the project has one and the relevant files changed. Use the command from `PROJECT.md`.

### 4. Run the affected tests

`PROJECT.md`'s **Toolchain** section gives the test command and, where the project has a
convention, how source files map to test files. Use the targeted form, not the full suite: CI
runs everything, and the point here is speed.

Where no mapping is documented, fall back to running the tests that changed plus any test file
whose name matches a changed source file, and say in the report that the selection was
heuristic.

### 5. Adversarial review pass

Launch the **`reviewer`** agent (Agent tool, `subagent_type: reviewer`) on the diff. It reads the
same `PROJECT.md` and returns verified, severity-ranked findings.

**Launch `qa-engineer` in the same batch whenever the diff touches money, auth, data integrity,
or a migration.** This is not a judgement call: check the paths, and if any of the four apply,
the agent runs. It answers a different question from `reviewer`: not "is this correct" but "what
could break, and is it covered". When none of the four apply, say so in the report, the same way
a skipped check is reported as skipped rather than as passing.

### 6. Report

**One line per check**, each naming the exact command run and its result. Then the reviewer's
findings, one line each. Then the verdict: **ready to open the PR**, or **fix these first**
(listed). **Cap the whole report at 150 words** excluding command output and failure text.

A gate reports pass or fail. It does not explain what the checks do, summarise the diff, or
narrate what you ran them for.

**A check you skipped is reported as skipped, never as passing.** If a linter had no matching
files, if a command was missing, if `PROJECT.md` was absent, say so. A green summary that quietly
omits a check is worse than a red one.

Do not open or push the PR. This is a gate, not a publisher.

## Rules

- This command runs checks and reviews; it does not edit code. Fix findings separately (yourself,
  or via the stack engineer for that language), then re-run.
- Prefer targeted checks over the full suite. CI runs everything anyway.
- If a command from `PROJECT.md` fails to *run* (missing tool, wrong version, a container not
  started), that is a toolchain problem, not a code problem. Report it as such rather than as a
  failing check, and note what was needed.
