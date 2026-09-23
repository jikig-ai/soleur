---
title: "ADR-243: Records that state at-rest posture are bound to the ledger by an equality clause"
status: accepted
date: 2026-09-23
issue: 8532
supersedes: []
amends:
  - ADR-140
tags: [encryption-posture, ledger, article-30, c4, gdpr, art-30, art-32]
---

# ADR-243: Records that state at-rest posture are bound to the ledger by an equality clause

## Status

`accepted`, implemented by the #8532 ledger PR (PR-3 of its plan). The ordinal is provisional
and gets re-checked against `origin/main` at merge.

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
2. **Anchors are per section.** A markdown surface is split at its headings, and each section
   may carry at most one clause per store. A non-markdown surface is one section. A row's
   `records` entries are `<path>` or `<path>#<heading prefix>`. A prefix selects exactly one
   heading and must end at a non-alphanumeric character, so `Processing Activity 1` never
   selects `Processing Activity 13`.
3. **The check runs in both directions.** Forward (`check_records_resolve`): every record
   resolves to exactly one clause, and that clause agrees with the row. Reverse
   (`check_record_anchors_named`): every clause in every surface parses, names a live row, and
   sits in a section that row lists. A renamed store therefore cannot leave an orphan clause,
   and no clause can exist that no forward check reads. The one exception is a template whose
   id starts with `<`, which the register's maintenance section uses to document the form.
4. **The surface list lives in the ledger** (`record_surfaces`), not in the script, so the
   check can be tested with synthesized fixtures. It is protected by a surface-count floor in
   the test suite, which reports directly, and by CODEOWNERS rows on the ledger, the schema,
   the lint, the register and `model.c4`.
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

- 44 register clauses in 11 sections and 12 `model.c4` clauses are gated. A posture change that
  touches only one side reds the sweep.
- A section that only mentions a store, without stating its posture, carries no clause. The
  CLO recorded which ones were left un-anchored, and why, in the register's #8532 markers.
