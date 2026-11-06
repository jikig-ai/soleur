# Tasks: ADR-282 addendum 2026-10-28 (Hetzner project-deletion coverage)

Plan: `knowledge-base/project/plans/2026-10-28-docs-adr-282-hetzner-project-deletion-addendum-plan.md`
Ref #9927, Ref #10112. No closing keyword.

## Phase 1: Re-measure (read-only)

- 1.1 WebFetch the cancellations-hetzner-console page; read the whole "Deleting a project" section; confirm the sentence word for word (else record what was read, do not quote the old sentence).
- 1.2 curl the Cloud API spec to the scratchpad; with jq count paths, distinct top-level path segments, project-named paths; read the token/project sentence.

## Phase 2: Write

- 2.1 Append `## Addendum - 2026-10-28 (#9927)` to ADR-282 (append-only; about 25 lines; measured table, still-true paragraph, not-measured list, claim limits, three owner-side follow-ups not started and not decided).

## Phase 3: Local checks

- 3.1 `bash scripts/markdown-lint.sh <ADR>` (or state the refusal; CI is the gate).
- 3.2 `bash scripts/check-adr-ordinals.sh`.
- 3.3 `bash plugins/soleur/test/sole-copy-drift-check.test.sh`.
- 3.4 `bash apps/web-platform/infra/inngest-redis-luks-import-rehearsal.test.sh`.
- 3.5 Append-only proof: zero removed lines against origin/main in the ADR; only ADR + plan/spec files changed.

## Phase 4: Ship

- 4.1 PR #11414 body: Measured / Not measured with dates; Ref lines only; #9927 stays open for the owner.
