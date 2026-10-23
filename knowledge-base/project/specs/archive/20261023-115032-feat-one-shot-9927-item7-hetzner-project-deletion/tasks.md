# Tasks: ADR-282 Hetzner project-deletion residual (#9927 item 7)

Plan: `knowledge-base/project/plans/2026-10-23-docs-adr-282-hetzner-project-deletion-residual-plan.md`

## Phase 1: Edit

- 1.1 Re-read `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` (the residual at "Hetzner project deletion or account loss" and the last addendum).
- 1.2 Replace "is unverified" in that residual with the CTO wording: planning posture "plan as if project deletion or account loss destroys the volume regardless of delete protection", fact "not established; Hetzner docs read 2026-10-23 are silent", pointer to the new addendum.
- 1.3 Append `## Addendum — 2026-10-23 (#9927 item 7, Hetzner project-deletion coverage, documentation read only)`:
  - 1.3.1 measured / not-measured table with the three documentation URLs and the retrieval date 2026-10-23
  - 1.3.2 the scratch-volume detach proof is dropped; the first sanctioned inngest-host-replace proves detach under protection only
  - 1.3.3 the non-binding support-question route and the "Ruled by CTO agent, 2026-10-23" line
  - 1.3.4 status stays `accepted`; no other residual or table changes

## Phase 2: Verify

- 2.1 Run the grep checks AC1 to AC5 from the plan.
- 2.2 Run `bash apps/web-platform/infra/inngest-redis-luks-import-rehearsal.test.sh`, `bash plugins/soleur/test/sole-copy-drift-check.test.sh` and `bash scripts/check-adr-ordinals.sh`, one at a time.
- 2.3 Run `npx markdownlint-cli2` on the ADR.

## Phase 3: Ship

- 3.1 `soleur:review`, then `soleur:ship`; PR body states what was measured and not, with dates; `Ref #9927` and `Ref #10112`, no closing keyword.
- 3.2 After merge: comment on #9927 (names and dates only), then print the resume prompt for item 2 (#10664 site C).
