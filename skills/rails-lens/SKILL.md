---
name: rails-lens
description: Explain Java, Spring Boot, Spring Modulith, JPA, or Maven concepts and code in this codebase through a Ruby on Rails comparison. Use when asked "what is this in Rails terms", "how does X work in Java/Spring", "explain this class/annotation/bean", "what's the Rails equivalent of", or any learning question about a Java/Spring codebase from someone who knows Rails.
argument-hint: a question, a class name, an annotation, or file:line
---

# Rails Lens

The reader is a senior Rails engineer who is new to Java and Spring. Explain the
Java/Spring thing by anchoring it to the closest Rails concept, then say exactly where the
analogy breaks. A comparison that hides the difference is worse than none.

## Steps

1. **Read `.claude/agent-notes/rails-lens/GLOSSARY.md`** if present. Reuse its mappings so the
   vocabulary stays consistent across questions.
2. **Ground it in this codebase.** Find one real example (`file:line`) of the thing asked about
   before explaining it. Read `.claude/PROJECT.md` for layout. Never explain from memory alone
   when the repo has an instance.
3. **Answer in this shape:**
   - **Rails equivalent:** one line. "Closest to X" when there is no true equivalent.
   - **Here:** the real example, with a short excerpt.
   - **Same:** what transfers from Rails intuition.
   - **Different:** where Rails intuition will mislead. This is the most important part.
   - **Rails snippet** only when a side-by-side makes the difference obvious. Keep it short.
4. **Update the glossary.** When the answer introduces a term not in it, append one row. Create
   the file from the header below if it does not exist. Never rewrite existing rows.

## Rules

- Follow the length caps in `~/.claude/CLAUDE.md` ("Explain X" = 250 words) unless told "go deep".
- Name the Java/Spring version behavior when it matters (Java 25 records, pattern matching,
  virtual threads; Spring Boot auto-configuration). Check `pom.xml` rather than guessing versions.
- Magic is the usual confusion. When Spring does something implicitly (component scan, proxies
  around `@Transactional`, auto-configuration), say what triggers it, the way you would explain
  Rails autoloading or callbacks.
- Answering a question needs no permission. Read anything needed.

## Glossary header

```markdown
# Rails → Spring glossary

| Spring / Java | Closest Rails | Key difference | Example here |
|---|---|---|---|
```
