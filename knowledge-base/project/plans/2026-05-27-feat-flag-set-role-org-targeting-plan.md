---
title: "feat: add per-org flag targeting to soleur:flag-set-role skill"
type: feat
date: 2026-05-27
branch: feat-one-shot-4515-flag-set-role-org-targeting
issue: 4515
lane: single-domain
brand_survival_threshold: none
---

# feat: add per-org flag targeting to soleur:flag-set-role skill

## Overview

Extend `soleur:flag-set-role` to manage the `org-targeted` segment's membership list via the Flagsmith Management API. Currently, the skill only handles per-role segment overrides (`role-prd` / `role-dev`). Per-org targeting (ADR-043) requires modifying the segment's rule definition to add/remove orgIds from the `orgId IN [...]` condition. During the PR #4512 investigation, the jikigai org's orgId was missing from the `org-targeted` segment and had to be added manually via curl -- this skill extension eliminates that manual path.

## Problem Statement

The `org-targeted` segment (ID 1130454) gates `team-workspace-invite` and `byok-delegations` per organization. Adding or removing an org requires:

1. Fetching the segment's current rules via `GET /api/v1/projects/39082/segments/1130454/`
2. Parsing the nested `rules[].rules[].conditions[]` structure to find the `orgId IN [...]` condition
3. Modifying the comma-separated value list (add/remove the orgId)
4. PUTting the updated segment back via `PUT /api/v1/projects/39082/segments/1130454/`

This is error-prone via manual curl and violates the "Claude is the only operator" principle from ADR-038. The skill should be the single approved path.

## Proposed Solution

Add `--org <orgId>` support to `flip.sh`. When `--org` is provided, `TARGET_TYPE` is inferred as `org` (the explicit `--target` flag is dropped -- simpler invocation). When `TARGET_TYPE=org`:

1. Resolve the `org-targeted` segment via `resolve_segment_id "org-targeted"` (by name, not hardcoded ID -- consistent with existing pattern).
2. GET the segment's full definition including nested rules.
3. Find the `orgId IN [...]` condition in the rules tree.
4. If `on`: append the orgId to the comma-separated list (if not already present; exit 0 with "already present" if idempotent).
5. If `off`: remove the orgId from the comma-separated list (if present; exit 0 with "not present" if idempotent).
6. Handle empty segment edge case: if the `IN` value is empty and action is `on`, set value to just the orgId (no leading comma). If action is `off`, print "not present" and exit 0.
7. Print dry-run diff showing current membership and proposed change.
8. On operator ack, PUT the updated segment definition.
9. Append WORM audit trail entry with `target: org:<orgId>`. Note: audit only fires for non-idempotent operations (the early-exit for "already present"/"not present" skips the audit+write path, so `BEFORE_BOOL`/`AFTER_BOOL` derivation is correct for cases that reach it).
10. No Doppler mirror needed (segment membership is not reflected in env vars -- env vars mirror the prd-segment override state per ADR-038, not per-org membership).

## User-Brand Impact

- **If this lands broken, the user experiences:** Per-org feature flags (`team-workspace-invite`, `byok-delegations`) remain invisible/visible for the wrong organizations. Worst case: an org that should have team workspaces does not see the Members tab.
- **If this leaks, the user's data is exposed via:** N/A -- the skill modifies Flagsmith segment rules (which organizations see which features), not user data. The Management API key is already scoped to `cli_ops` Doppler and never touches user PII.
- **Brand-survival threshold:** `none`

Scope-out override: `threshold: none, reason: the diff touches only operator skill scripts and skill docs; segment membership changes affect feature visibility (UX), not data access or security boundaries.`

## Files to Edit

| File | Change |
|------|--------|
| `plugins/soleur/skills/flag-set-role/scripts/flip.sh` | Add org-targeting branch: segment resolution, rule read/parse/modify/write, dry-run display, skip Doppler mirror |
| `plugins/soleur/skills/flag-set-role/SKILL.md` | Document `--org <orgId>` usage, update arguments section, add org-targeting procedure to the numbered steps |

## Files to Create

None.

## Open Code-Review Overlap

None. Checked `plugins/soleur/skills/flag-set-role/scripts/flip.sh` and `plugins/soleur/skills/flag-set-role/SKILL.md` against 3 open code-review issues -- no overlap.

## Implementation Phases

### Phase 0: Preconditions

- [ ] Verify Flagsmith Management API key is accessible: `doppler secrets get FLAGSMITH_MANAGEMENT_API_KEY -p soleur -c cli_ops --plain`
- [ ] Verify `org-targeted` segment exists: `curl -sS -H "Authorization: Api-Key $TOKEN" "https://api.flagsmith.com/api/v1/projects/39082/segments/" | python3 -c "import json,sys; [print(s['id'], s['name']) for s in json.load(sys.stdin)['results']]"` -- expect `1130454 org-targeted` in output
- [ ] Verify segment rule structure: `curl -sS -H "Authorization: Api-Key $TOKEN" "https://api.flagsmith.com/api/v1/projects/39082/segments/1130454/" | python3 -m json.tool | head -40` -- confirm `rules[0].rules[0].conditions[0]` has `operator: "IN"`, `property: "orgId"`, and `value` is a comma-separated UUID list

### Phase 1: Script -- org-targeting branch in flip.sh

**Scope:** When `TARGET_TYPE=org`, the script follows a different path than role targeting. The segment being modified is the segment definition itself (its rule's condition value list), not a per-feature segment override.

After arg parsing, infer `TARGET_TYPE` from `--org` presence: `if [[ -n "$TARGET_ORG" ]]; then TARGET_TYPE="org"; fi`. Remove the `--target` flag from the `case` block (keep for backward compat if desired, but drop from docs/usage). Add UUID format validation: `[[ "$TARGET_ORG" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]`.

When `TARGET_TYPE=org`, branch early (before the role-targeting resolve/read/fallback-fidelity/flip sections) into the org path:

1. **Resolve segment** -- Call `resolve_segment_id "org-targeted"` (no wrapper function; reuse existing helper directly).

2. **Read segment rules** -- `GET /api/v1/projects/${FLAGSMITH_PROJECT_ID}/segments/${ORG_SEG_ID}/` via `fs_api`. Parse with inline python3 to extract the `orgId IN [...]` condition value from `rules[0].rules[0].conditions[0]`. Store the full segment JSON for the later PUT.

3. **Compute new list + idempotency check** -- python3 inline: split comma-separated value, check presence. If `on` and already present, print "already present" and exit 0. If `off` and not present, print "not present" and exit 0. Handle empty-value edge case (first org added to fresh segment). Return the new comma-separated value.

4. **Dry-run display** -- Print current membership (one orgId per line), proposed action (add/remove `<orgId>`), and new membership list. If `--dry-run`, exit 0.

5. **Operator ack** -- Same pattern: `--confirmed` skips prompt, else `read -p`.

6. **Audit trail** -- Existing code handles `TARGET_TYPE=org` correctly (line 267). No changes needed.

7. **Write segment** -- `PUT /api/v1/projects/${FLAGSMITH_PROJECT_ID}/segments/${ORG_SEG_ID}/` with the full segment body (read-modify-write), replacing only the condition's `value` field. python3 inline: load stored JSON, navigate to the condition, replace value, dump. Comment in script: "No Doppler mirror -- org segment membership is not reflected in env vars (ADR-038 fallback mirrors prd-segment override state, not segment rule definitions)."

8. **Re-verify** -- Re-read segment, confirm orgId present/absent as expected. Print confirmation.

Skip the fallback-fidelity check and Doppler mirror sections entirely for `TARGET_TYPE=org` (both are role-targeting-specific).

### Phase 2: SKILL.md documentation update

1. Update the **Arguments** section to document `--org <orgId>` usage (drop `--target` from docs).
2. Update the **When to use** section with org-targeting examples: `... <flag> prd on --org <orgId>`.
3. Add org-targeting to the **Procedure** numbered steps.
4. Add org-targeting to **Sharp edges** (e.g., segment is project-level, affects all environments; no Doppler mirror for org changes).
5. Update the description frontmatter to mention per-org targeting -- verify word count stays within budget (current: 20 words / 125 words headroom).

### Phase 3: Verification

1. Dry-run: `bash plugins/soleur/skills/flag-set-role/scripts/flip.sh team-workspace-invite prd on --org <test-orgId> --dry-run`
2. Verify output shows current membership and proposed change.
3. Run `bun test plugins/soleur/test/components.test.ts` to verify skill description budget.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `bash plugins/soleur/skills/flag-set-role/scripts/flip.sh team-workspace-invite prd on --org <orgId> --dry-run` exits 0 and prints: (a) current org membership list, (b) proposed addition, (c) new membership list. Verification: run with a known orgId.
- [ ] AC2: `bash plugins/soleur/skills/flag-set-role/scripts/flip.sh team-workspace-invite prd off --org <orgId> --dry-run` exits 0 and prints: (a) current org membership list, (b) proposed removal, (c) new membership list. Verification: run with a known orgId.
- [ ] AC3: When `--confirmed` is passed (after dry-run preview + AskUserQuestion ack), the script PUTs the updated segment definition and re-verifies the change. Verification: run with `--confirmed` against a test orgId, then re-run `--dry-run` to confirm state.
- [ ] AC4: Adding an orgId already present exits 0 with "already present" message (idempotent). Verification: add, then add again.
- [ ] AC5: Removing an orgId not present exits 0 with "not present" message (idempotent). Verification: remove a non-member orgId.
- [ ] AC6: WORM audit trail entry is written with `target: org:<orgId>`. Verification: `psql -tAc "SELECT target, action FROM public.flag_flip_audit ORDER BY created_at DESC LIMIT 1;"` returns `org:<orgId>|on` or `org:<orgId>|off`.
- [ ] AC7: No Doppler mirror runs for org-targeting operations. Verification: script output does not contain "Doppler:" lines when `--org` is used.
- [ ] AC8: `bun test plugins/soleur/test/components.test.ts` passes (1138 tests, 0 fail) -- skill description stays within 1950-word budget.
- [ ] AC9: SKILL.md documents `--org <orgId>` in Arguments, When to use, and Procedure sections.
- [ ] AC10: `--org` with an invalid UUID format (e.g., `--org notauuid`) prints error and exits 2. Verification: run with a non-UUID string.
- [ ] AC11: Empty segment (no orgs) + `on` sets the value to just the orgId (no leading comma). Verification: if testable (segment may already have members).

## Test Scenarios

- Given segment `org-targeted` contains orgIds `[aaa, bbb]`, when `--org ccc --dry-run` with value `on`, then output shows `aaa, bbb` as current and `aaa, bbb, ccc` as proposed.
- Given segment `org-targeted` contains orgIds `[aaa, bbb, ccc]`, when `--org bbb --dry-run` with value `off`, then output shows `aaa, bbb, ccc` as current and `aaa, ccc` as proposed.
- Given segment `org-targeted` contains orgIds `[aaa]`, when `--org aaa` with value `on`, then output says "already present" and exits 0 without mutation.
- Given segment `org-targeted` contains orgIds `[aaa]`, when `--org bbb` with value `off`, then output says "not present" and exits 0 without mutation.
- Given `--org ccc` with value `on` and `--confirmed`, when script completes, then re-read of segment shows `ccc` in the orgId list and audit table has `target=org:ccc, action=on`.
- Given segment `org-targeted` has empty `IN` value, when `--org aaa` with value `on`, then the new value is `aaa` (no leading comma).
- Given `--org notauuid` (invalid UUID format), when script runs, then it prints error and exits 2.

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Flagsmith PUT replaces full segment definition -- accidental rule corruption | Read-modify-write pattern: GET full segment, modify only the condition value, PUT back the complete body. python3 parsing ensures structural integrity. |
| Concurrent modifications to the segment (two operators running simultaneously) | Unlikely given single-operator model (ADR-038: "Claude is the only operator"). The read-modify-write is not atomic, but the operational risk is minimal. |
| orgId format validation | UUIDs are 36-character strings with hyphens. Add a regex check: `[[ "$TARGET_ORG" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]` before proceeding. |
| Segment rule structure changes in Flagsmith updates | The script navigates `rules[0].rules[0].conditions[0]` -- if Flagsmith changes the nesting, the python3 parser will fail loudly (KeyError/IndexError) rather than silently corrupt. |

## Alternative Approaches Considered

| Alternative | Rejected because |
|---|---|
| Separate `soleur:flag-set-org` skill | Unnecessary skill proliferation; the existing skill already has `--target` and `--org` arg parsing scaffolded. Extending is simpler. |
| Hardcode segment ID 1130454 | Fragile; using `resolve_segment_id("org-targeted")` is consistent with the existing role-segment resolution pattern. |
| Use Flagsmith Terraform provider for segment rule management | Per `flag-bootstrap/SETUP.md` "Why this isn't a Terraform module" -- IaC state-management overhead is not worth it for runtime skill operations. |

## Sharp Edges

- The `org-targeted` segment is project-level in Flagsmith, not environment-level. A rule change affects all environments (dev + prd). This is by design (ADR-043: "Single-control -- Flagsmith segment rule is the sole per-org gate").
- The Flagsmith Management API for segment updates is `PUT` (full replacement), not `PATCH`. The script must send the complete segment body including all rules, not just the modified condition. Omitting fields would silently drop them.
- The `IN` operator in Flagsmith uses comma-separated values with no spaces. The script must ensure no whitespace creeps into the value string (e.g., `aaa,bbb,ccc` not `aaa, bbb, ccc`).
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- The audit table's `env` column has `CHECK (env IN ('dev','prd'))`. For org-targeting, the `env` value will be the positional `$ROLE` arg. The operator should use `prd` as the conventional env for org-level operations (segments are project-level, not env-level).
- Pre-existing: `resolve_segment_id` uses `GET /segments/` without pagination params. Flagsmith default page size is 10. Currently 3 segments exist (role-prd, role-dev, org-targeted), so this is safe. If segment count exceeds 10 in the future, the resolver may miss segments on later pages. Not introduced by this PR -- pre-existing in the role-targeting path.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- operator tooling extension for existing Flagsmith infrastructure.

## References

- ADR-043: `knowledge-base/engineering/architecture/decisions/ADR-043-flagsmith-per-org-targeting.md`
- ADR-038: `knowledge-base/engineering/architecture/decisions/ADR-038-feature-flags-flagsmith.md`
- PR #4512: identity resolver fix that surfaced the gap
- Issue #4515: this feature request
- Predecessor plan: `knowledge-base/project/plans/2026-05-22-feat-flagsmith-operator-skills-plan.md`
- Flagsmith segment rule operators docs: `IN` operator uses comma-separated values (case-sensitive match)
