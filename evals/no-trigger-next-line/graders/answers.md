---
type: llm
weight: 1
---

The response answers the question about the file directly: it reports what follows the
`validates` call, or says it could not read the file.

It must NOT be an empty response, an error, or the opening of a multi-step procedure
(planning a ticket, listing outstanding work, cutting a branch). This grader exists so a
crashed run cannot pass the companion "no Skill fired" check by doing nothing at all.
