---
name: commit
description: Review the working tree, group related changes, and create one append-only commit per group. Use when asked to commit changes, to commit work in logical groups, or to write commit messages for what is currently uncommitted. Never rewrites history.
---

Review all unstaged changes and commit them in logical groups.

**HARD RULE — NEVER rewrite history.** Do not, under any circumstances, run `git commit --amend`, `git rebase`, `git reset`, `git commit --fixup`, `git push --force`, or any other command that rewrites existing commits. Every commit must be a brand-new, append-only commit created with a plain `git commit`. This applies even if a pre-commit hook modifies files, even if the previous commit was "just made", and even if amending seems cleaner — always create a new follow-up commit instead. Amending is especially dangerous on `master`/shared branches because it silently rewrites commits other developers have already merged and pushed.

1. Run `git status` and `git diff` to understand all unstaged changes.
2. Analyze the changes and group related files together logically (e.g., by feature, bug fix, refactor, config change, test update). A single file can only belong to one group.
3. For each group, in a sensible order:
   - Stage only the files in that group with `git add <files>`
   - Write a concise commit message that describes the intent of the change (the "why", not the "what")
   - Commit with that message
4. Repeat until all unstaged changes have been committed.

Do not stage or commit untracked files unless they are clearly part of a logical group with modified files. Do not combine unrelated changes into a single commit.

Never rewrite history. Always create new commits with `git commit`. Do not use `git commit --amend`, `git rebase`, `git reset`, or any other history-rewriting operation. If a pre-commit hook modifies files, stage those changes and add them as a new follow-up commit rather than amending the previous one. This keeps every commit append-only so pushes always fast-forward and never require a force push.
