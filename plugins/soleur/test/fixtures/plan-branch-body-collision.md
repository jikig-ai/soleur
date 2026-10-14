---
title: "fixture: a plan whose BODY documents the cursor key"
date: 2026-08-10
slug: fixture-plan-cursor-body-collision
branch: fixture-frontmatter-branch
---

# Fixture — the cursor key appears in the body, never in the frontmatter

This fixture is the regression artifact for a bug that actually shipped: v1 of the
`#7418` plan prescribed a **line-anchored** frontmatter reader, and that reader —
run against the plan document itself — returned a cursor value harvested from a
fenced YAML *example* in the body, while the real frontmatter carried no such key.
A plan that merely *documents* the mechanism was therefore misread as in-flight.

Any document that explains a frontmatter key will contain that key in its body.
The two lines below sit at **column 0** and must be invisible to a
frontmatter-bounded reader:

branch: fixture-body-branch

They also appear inside a fenced block, which is how the original defect was
introduced:

```yaml
branch: fixture-fenced-branch
```

A correct reader extracts `pipeline_resume` as empty (the frontmatter has no such
key) and `branch` as `fixture-frontmatter-branch` (never `fixture-body-branch` or
`fixture-fenced-branch`).
