# Pattern Page Template

Copy to `knowledge-base/project/patterns/<slug>.md`. The filename equals `<slug>`. Delete these instructions and the inline comments from the copy.

```markdown
---
title: "<short pattern name>"
summary: "<one line, <= 200 chars, printable ASCII: problem + root cause + fix>"
status: open            # open | closed
opened_on: "2026-01-31" # quote the date
tags: [tag-one, tag-two]
evidence:               # tracked, non-archived learnings; >= 5 for a seeded page
  - knowledge-base/project/learnings/<file>.md
required_reading: false # true = agents read this page before code generation
# Closed pages only. Both are required; the reason lives in the body:
closed_on: "2026-03-01"
closed_by: 12345        # PR number that fixed or retired the pattern
---
## Root cause

<Technical explanation of why the failure recurs.>

## Fix

<The general approach, with a short wrong-versus-correct example where useful.>

## Evidence

<One line per evidence learning: what it showed.>
```

## Authoring rules

1. Write no names, handles, tester, tenant, or session-derived detail in any field or body section.
2. Cite only learnings that exist, are tracked, and are not archived.
3. Only a human PR edit closes a page (`status: closed` plus `closed_on` and `closed_by`). The weekly cron never writes a pattern page.
4. Add or extend a page through a reviewed PR; never auto-promote from a capture session.
5. Keep `summary` to one line of printable ASCII, at most 200 characters.
