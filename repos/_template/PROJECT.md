# PROJECT.md — <project name>

What an agent needs to know about this project. The user-level agents (`explorer`, `reviewer`,
`architect`, `qa-engineer`) read this file on startup; it is the context half of the split that
keeps the agent definitions themselves stack-agnostic.

Symlinked into the checkout as `.claude/PROJECT.md` by `bin/link-personal-claude`, and excluded
via `.git/info/exclude`, so nothing here reaches the team repo.

Keep it short. An agent reads this every run, and a fact that is already obvious from the build
file is a fact that costs tokens and can go stale. Write down what is *hard to infer*.

## Toolchain

The exact commands. `/pre-pr` and `/ci-check` read this section instead of assuming a runner from
the language, and an agent runs these rather than guessing.

```
test:           <e.g. make test, ./mvnw verify, yarn test, bundle exec rspec>
test (fast):    <the narrow loop, if there is one>
lint:           <...>
typecheck:      <...>
build:          <...>
```

**Which linter takes which files**, if there is more than one, or if a linter ignores the file
list you pass it. Note explicitly when a tool does *not* exist — "there is no formatter here"
stops a command inventing a no-op step and reporting it green.

**Affected tests from a diff.** How a changed source file maps to the test that covers it: a
mirrored tree, colocated files, a module flag. Also name the case where the mapping does not
hold and the full suite is the only honest answer (a boundary check, a shared fixture, a
generated artifact that must be rebuilt first).

Anything that must be running first (a database, Docker, a specific node version) goes here, with
the symptom if it is missing. "Tests fail with X when Docker isn't running" saves a debugging
session.

## Git

```
base branch:    <the branch PRs target — often not `main`>
branch naming:  <convention, if any>
squash merges:  <yes/no — decides whether git ancestry can tell you what shipped>
```

## Layout

A map, not an inventory. Where the boundaries are and what owns what. An agent can list files
itself; what it cannot infer is which directory is the seam and which is an implementation detail.

## Hard conventions

Rules that fail a build or a review here. Prefer the ones that are non-obvious or specific to
this codebase over general good practice the agent already knows.

## Locked decisions

Product or architectural choices that are settled, and where they are recorded. This is what
stops `reviewer` filing a deliberate behaviour as a bug and `architect` proposing something
already rejected.

## Traps

Things that have already cost someone an hour. The most valuable section and the hardest to write
in advance, so add to it as they turn up:

- A command that silently no-ops instead of failing
- A generated file that looks hand-editable
- A test that passes for the wrong reason
- A tool that reports success while doing nothing
