---
title: "ADR-245: Records that state at-rest posture are bound to the ledger by an equality clause"
status: accepted
date: 2026-09-23
issue: 8532
supersedes: []
amends:
  - ADR-140
tags: [encryption-posture, ledger, article-30, c4, gdpr, art-30, art-32]
---

# ADR-245: Records that state at-rest posture are bound to the ledger by an equality clause

## Status

`accepted`, implemented by the #8532 ledger PR (PR-3 of its plan). The ordinal is provisional
and gets re-checked against `origin/main` at merge. **Renumbered 2026-09-24 from ADR-243**, which
`main` assigned to the Inngest/Cloudflare streaming decision (#8611). Issue comments and PR text
written before this date say "ADR-243" and mean this record.

## Context

The Article 30 register and `model.c4` both restate each store's at-rest posture in
hand-written prose. Nothing tied that prose to the encryption-posture ledger, so the two could
drift, and any check over them would have been a bespoke grep. Prose also cannot be checked by
regex. The register is additive-only, so an amended cell keeps the superseded text next to the
current text. Measured, 8 of 10 windows around one store id contain both `LUKS` and
`plaintext`. The same store is also stated under several processing activities: up to six for
the Inngest Redis volumes.

## Decision

1. **A visible, self-describing clause** marks each statement of posture:
   `(encryption-posture ledger: <store id> — at rest: <mechanism>)`. Its mechanism must
   **equal** the row's `at_rest.mechanism`. It is compared as a string, never matched against
   prose. In `model.c4` the clause is a `//` comment, since that DSL has no HTML comments. C4
   is an internal record, so the visibility rule the register follows does not apply there.
2. **Anchors are per section.** A markdown surface is split at its H1/H2 headings, ignoring
   headings inside fenced code; an H3 or deeper is a sub-part of its section. Each section may
   carry at most one clause per store. A non-markdown surface such as `model.c4` is one section,
   so it can anchor each store once, and posture stated in a relationship cannot be anchored. A row's
   `records` entries are `<path>` or `<path>#<heading prefix>`. A prefix selects exactly one
   heading and must end at a non-alphanumeric character, so `Processing Activity 1` never
   selects `Processing Activity 13`.
3. **The check runs in both directions.** Forward (`check_records_resolve`): every record
   resolves to exactly one clause, and that clause agrees with the row. Reverse
   (`check_record_anchors_named`): every clause in every surface parses, names a live row, and
   sits in a section that row lists. A renamed store therefore cannot leave an orphan clause,
   and no clause can exist that no forward check reads. The one exception is the exact template
   `(encryption-posture ledger: <store id> — at rest: <mechanism>)`, which the register's
   maintenance section quotes; anything else clause-shaped must parse.
4. **The surface list lives in the ledger** (`record_surfaces`), not in the script, so the
   check can be tested with synthesized fixtures. Dropping a surface reds the forward check for
   every row still recording it; the test suite pins the two canonical paths, so a replaced
   surface also reds. CODEOWNERS rows on the ledger, the schema, the lint, the register and
   `model.c4` add review routing, which binds only once branch protection requires code-owner
   review.
5. **Assert-only.** No script writes into `knowledge-base/legal/**`. Changing a store's
   posture means amending the record cell and the ledger row in the same PR.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| A regex over the prose around each store id | The register is additive-only, and measured, most windows hold both polarities |
| File-level uniqueness, as for `disclosed_as` | One store is stated under several activities. Only one cell could be anchored, leaving the rest as ungated prose |
| A likec4 tag or metadata anchor | `c4-count-parity` already reads the `.c4` source, so a comment clause is enough and needs no export field |
| Hard-coding the surfaces in the script | The check could not be tested with synthesized fixtures |

## Consequences

- At merge, 46 register clauses in 11 sections and 12 `model.c4` clauses are gated. A posture
  change that touches only one side reds the sweep.
- **Retiring a store** removes its row, its `records`, and every clause naming it, in one PR.
  The register cell keeps its prose and gains a dated marker recording the retirement; only
  the clause goes, because a clause asserts the store is live.
- **The published legal documents are not record surfaces.** `privacy-policy.md` and the data
  protection disclosure restate the workspace posture in several places; only the anchored
  `disclosed_as` line is checked. Whether they become surfaces is part of #8624.
- A section that only mentions a store, without stating its posture, carries no clause. The
  CLO recorded which ones were left un-anchored, and why, in the register's #8532 markers.
