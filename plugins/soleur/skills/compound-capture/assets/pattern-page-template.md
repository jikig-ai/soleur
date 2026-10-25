# Pattern Page Template

Copy to `knowledge-base/project/patterns/<slug>.md`. The filename equals `<slug>`. Delete these instructions and the inline comments from the copy.

## Open page

```markdown
---
title: "<short pattern name>"
summary: "<one line: problem + root cause + fix>"
status: open            # open | closed
opened_on: "2026-01-31" # quote the date
tags: [tag-one, tag-two]
evidence:               # tracked, non-archived learnings; >= 5 for EVERY page
  - knowledge-base/project/learnings/<file>.md
required_reading: false # true = agents read this page before code generation
---
## Root cause

<Technical explanation of why the failure recurs.>

## Fix

<The general approach, with a short wrong-versus-correct example where useful.>

## Evidence

<One line per evidence learning: what it showed.>
```

An open page must NOT carry `closed_on` or `closed_by`.

## To close a page (human PR)

Open the PR first, then set `closed_by` to its number in a follow-up commit. Both keys are required on a closed page and only there; the reason lives in the body.

```yaml
status: closed
closed_on: "2026-03-01"
closed_by: 12345        # positive integer: the PR number that fixed or retired the pattern
```

## Validator limits

The loader (`apps/web-platform/server/compound-promote-patterns.ts`) and the live-tree test drop or reject a page that breaks any of these:

- At least 5 evidence entries on EVERY page. A page left with fewer than 5 surviving keys is dropped.
- Evidence paths are unique, canonical (no `.`, empty or `..` segments), tracked and not archived.
- `title`: at most 120 printable ASCII characters. `summary`: at most 200 printable ASCII characters.
- `tags`: 1 to 12, each matching `^[a-z0-9][a-z0-9-]{0,40}$`.
- `slug` (the file name): `^[a-z0-9][a-z0-9-]{0,80}$`.
- Allowed frontmatter keys only: `title`, `summary`, `status`, `opened_on`, `tags`, `evidence`, `required_reading`, `closed_on`, `closed_by`.
- At most 16 KiB per page. The tree holds at most 8 pages (CI).

Body sections are not validated and are never sent to the model; only the title, summary, tags, evidence keys and the evidence learnings are.

## Authoring rules

1. Write no names, handles, tester, tenant, or session-derived detail in any field or body section.
2. Cite only learnings that exist, are tracked, and are not archived. The PR that archives a learning must update or delete any page (including a closed one) that cites it.
3. Only a human PR edit closes a page. The weekly cron never writes a pattern page.
4. Add or extend a page through a reviewed PR; never auto-promote from a capture session.
