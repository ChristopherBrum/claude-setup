# repos/_template

The shape of a per-project layer. Copy it to `repos/<project-name>/`, where `<project-name>`
matches the checkout's directory name, then run `bin/bootstrap`.

Every other `repos/<project>/` directory is gitignored: those hold project-specific knowledge
(module layouts, product rules, internal doc paths, vendor integrations) that does not belong in
a repo on a personal account. Only this template ships.

```
repos/<project>/
├── PROJECT.md            the context the user-level agents read on startup
├── settings.local.json   permissions for tools that only exist in THIS project
├── agents/               optional: project agents, override a user agent by name
├── skills/               optional
├── commands/             optional
└── agent-notes/<name>/   per-agent notes, written by the agents themselves
```

`bin/link-personal-claude` symlinks whichever of these exist into `<checkout>/.claude/` and adds
them to `.git/info/exclude`, which is per-clone and never pushed. So the layer is discoverable by
Claude Code (which only looks at `<cwd>/.claude/`) while staying invisible to the team repo.

## settings.local.json

Only tools that exist in this project and nowhere else. A generic tool (`git`, `gh`, `yarn`,
`npx`) is allowlisted once at user level; duplicating it here is how an allowlist rots.

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash(./mvnw test:*)",
      "Bash(make test-unit:*)"
    ]
  }
}
```

Avoid a broad prefix that swallows something you want to stay promptable: `Bash(gh pr:*)` also
matches `gh pr create`.

## agents/

Prefer not to. A `PROJECT.md` plus the four user-level agents covers most projects, and three
near-duplicate agent definitions is the thing that arrangement exists to avoid. Add one only when
a generic role genuinely does not fit; a project agent wins over a user agent of the same name.
