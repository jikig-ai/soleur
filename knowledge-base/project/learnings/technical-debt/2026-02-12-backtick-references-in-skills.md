---
module: plugins/soleur
date: 2026-02-12
problem_type: best_practice
component: skills
tags: [skills, markdown-links, backtick, convention-violation]
severity: medium
---

# Several Skills Use Backtick References Instead of Markdown Links

## Context

Constitution rule: "Reference files in skills must use markdown links, not backticks." Several skills violate this:

- `dspy-ruby/SKILL.md`: Uses `` `assets/signature-template.rb` `` and `` `references/core-concepts.md` ``
- `compound-docs/SKILL.md`: Uses `` `assets/resolution-template.md` `` and `` `assets/critical-pattern-template.md` ``
- `skill-creator/SKILL.md`: Uses backticks for `scripts/rotate_pdf.py`, `references/finance.md`, `assets/logo.png`

## Expected Pattern

```markdown
[signature-template.rb](./assets/signature-template.rb)
[core-concepts.md](./references/core-concepts.md)
```

## Prevention

Plugin component tests should validate that SKILL.md files use markdown links for file references rather than bare backticks.
