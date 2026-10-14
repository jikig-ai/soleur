---
name: feat-one-shot-4515-flag-set-role-org-targeting
plan: knowledge-base/project/plans/2026-05-27-feat-flag-set-role-org-targeting-plan.md
lane: single-domain
---

# Tasks: Add per-org flag targeting to soleur:flag-set-role skill

## Phase 0: Preconditions

- [x] 0.1 Verify Flagsmith Management API key accessible from Doppler cli_ops
- [x] 0.2 Verify `org-targeted` segment exists in Flagsmith (resolve by name) — ID 1130454
- [x] 0.3 Verify segment rule structure: `rules[0].rules[0].conditions[]` uses EQUAL operator per org (not IN with comma-separated values as plan assumed)
- [ ] 0.4 Verify PUT endpoint with no-op round-trip: GET segment, PUT back unchanged, GET and diff (deferred — verified implicitly via dry-run + implementation)

## Phase 1: Script -- org-targeting branch in flip.sh

- [x] 1.1 Add `--org` inference: after arg parsing, `if [[ -n "$TARGET_ORG" ]]; then TARGET_TYPE="org"; fi`
- [x] 1.2 Add UUID format validation for `$TARGET_ORG`
- [x] 1.3 Add org-targeting branch (early return before role-targeting sections)
  - [x] 1.3.1 Resolve `org-targeted` segment via `resolve_segment_id "org-targeted"`
  - [x] 1.3.2 GET full segment definition, parse `orgId IN [...]` condition value
  - [x] 1.3.3 Compute new org list (add/remove orgId from comma-separated value)
  - [x] 1.3.4 Handle idempotency: "already present" / "not present" early-exit
  - [x] 1.3.5 Handle empty-segment edge case (first org added)
  - [x] 1.3.6 Print dry-run display (current membership, proposed change, new membership)
  - [x] 1.3.7 Dry-run exit / operator ack (reuse existing pattern)
  - [x] 1.3.8 Audit trail (existing code handles `TARGET_TYPE=org`)
  - [x] 1.3.9 PUT updated segment definition (read-modify-write, full body)
  - [x] 1.3.10 Re-verify: re-read segment, confirm orgId present/absent
  - [x] 1.3.11 Skip Doppler mirror + fallback-fidelity check (comment explaining why)

## Phase 2: SKILL.md documentation update

- [x] 2.1 Update Arguments section: add `--org <orgId>` flag documentation
- [x] 2.2 Update When to use section: add org-targeting examples
- [x] 2.3 Update Procedure section: add org-targeting numbered steps
- [x] 2.4 Update Sharp edges: segment is project-level, no Doppler mirror, pagination note
- [x] 2.5 Update description frontmatter if needed (verify word count within budget)

## Phase 3: Verification

- [x] 3.1 Dry-run test: `bash flip.sh team-workspace-invite prd on --org <test-orgId> --dry-run`
- [x] 3.2 Verify output shows current membership and proposed change
- [x] 3.3 Run `bun test plugins/soleur/test/components.test.ts` -- all 1138 tests pass, budget OK
- [x] 3.4 Verify UUID validation rejects invalid format (exit 2)
