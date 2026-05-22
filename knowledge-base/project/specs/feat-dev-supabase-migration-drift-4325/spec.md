---
issue: 4325
brand_survival_threshold: single-user incident
lane: cross-domain
brainstorm: knowledge-base/project/brainstorms/2026-05-22-dev-supabase-drift-deltas-4325-brainstorm.md
related_prs: [4339]
related_issues: [4338, 4241]
---

# Spec: #4325 — dev-Supabase drift delta bundle

## Problem Statement

`#4325` reports a schema-vs-ledger split on dev-Supabase: `_schema_migrations` claims 053/058/059/060/061 applied while `public.workspaces`, `public.workspace_members`, `public.workspace_member_attestations`, `public.organizations` are missing from the live schema. The drift class is the same one #4338 documented earlier today; PR #4339 (merged 2026-05-22 12:34 UTC) shipped the four-part remediation (probe, preflight, scheduled cron, learning).

#4325 is a duplicate-class instance reported by a parallel /work session on #4230. The drift detection is now in place; the **broken dev state** + **two hardening gaps the post-mortem identified but did not bundle** remain.

## Goals

- **G1:** Recover dev-Supabase to a clean state where `tenant-integration` passes against this PR's branch.
- **G2:** Make the drift class harder to re-introduce by enforcing the canonical Part-2 `to_regclass` precondition pattern via CI lint.
- **G3:** Close the Branch-A partial-apply hazard (`CREATE POLICY` / `ADD CONSTRAINT` re-apply failures) the learning calls out as forensic survivors.
- **G4:** Bring operator-local `run-migrations.sh` invocations to parity with CI's probe coverage.
- **G5:** Close #4325 with proof — green CI + linked PR + linked learning.

## Non-Goals

- **NG1:** Re-implementing drift detection. PR #4339 already shipped the probe, preflight, scheduled cron, and learning.
- **NG2:** Modifying applied migrations (058, 060) in place. That would change their `content_sha` and trip the #4241 filename-vs-main drift probe — the load-bearing invariant we just shipped.
- **NG3:** Automated enforcement against non-runner writes to `_schema_migrations`. The learning's Prevention #1 names this as forbidden; an automated gate is a separate-scope follow-up.
- **NG4:** Audit-log integration with Supabase Management API to forensically attribute the original non-runner write. Out of scope; the timestamp-clustering signal in the learning is sufficient forensics.

## Functional Requirements

- **FR1:** A CI lint script scans every migration file changed in a PR (`git diff origin/main...HEAD --name-only --filter=AM apps/web-platform/supabase/migrations/*.sql`) and fails when any cross-file `REFERENCES public.<table>` is present without a preceding `to_regclass` `RAISE EXCEPTION` precondition block.
- **FR2:** Self-FK references (target table is `CREATE TABLE`-d in the same file) are excluded from the lint — mirror the same-file-creates subtraction in `run-migrations.sh:285-293`.
- **FR3:** The CI lint failure message names the missing relation, the offending file, and links to `2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md`.
- **FR4:** A forward-only migration (064, or whatever's next free at merge time) provides idempotency hardening for the surviving constructs the learning calls out (`attestations_select_for_members` policy, `workspace_members_attestation_id_fkey` constraint, `user_session_state_owner_select` policy). Detailed shape (single migration vs. helper-function convention) decided at `/soleur:plan` time.
- **FR5:** `MIGRATION_SCHEMA_PRECONDITION_PROBE` defaults to `1` in `run-migrations.sh`. The `--bootstrap=auto` / `--bootstrap=skip` flag pattern remains the documented escape hatch.
- **FR6:** `run-migrations-schema-probe.test.sh` updated to assert the new default + add a `MIGRATION_SCHEMA_PRECONDITION_PROBE=0` opt-out case.

## Technical Requirements

- **TR1:** Lint must run in `tenant-integration.yml` or a new dedicated workflow. Must NOT block `web-platform-release.yml#migrate` (production apply path) — lint is PR-time defensive, not runtime gate.
- **TR2:** Lint regex matches `run-migrations.sh:282-287`'s convention: uppercase DDL keywords, lowercase `public.`-qualified relation names. Dynamic SQL / `EXECUTE format(...)` bypasses lint; this is acknowledged as best-effort consistent with the runtime probe.
- **TR3:** Forward-only migration (FR4) must include its own `to_regclass` preconditions per FR1's pattern (eat own dogfood).
- **TR4:** Forward-only migration body must be safe to re-apply against the live dev schema post-recovery (operator runs Delta 1 first, dev re-applies 053/058/059/060/061, then this migration applies).
- **TR5:** No edit to applied migrations 053/058/059/060/061 in place. New file or helper-function additions only.

## Acceptance Criteria

- **AC1:** Dev recovery proof is captured by the `/tmp/pg-runner/inspect.mjs` output on `_schema_migrations` showing (a) distinct (non-sub-millisecond) `applied_at` timestamps for 053/058/059/060/061/062, (b) `content_sha` matching `origin/main` blob SHAs, (c) `to_regclass` returning the table names for organizations, workspaces, workspace_members, workspace_member_attestations, workspace_member_removals. **Already verified 2026-05-22 — recovery ran out-of-band at 12:30 UTC** (likely as part of PR #4339's session). Tenant-integration green is NOT the proof gate — it has pre-existing failures in sibling features (`workspace_member_actions` AC4, `scope_grants_workspace_id_check`) per `wg-when-tests-fail-and-are-confirmed-pre`.
- **AC2:** A synthetic test migration with an unprotected cross-file `REFERENCES` triggers the FR1 lint and fails CI. A counter-test with a `to_regclass` precondition block passes.
- **AC3:** `MIGRATION_SCHEMA_PRECONDITION_PROBE=0 bash apps/web-platform/scripts/run-migrations.sh --help` succeeds and documents the opt-out (FR5+FR6).
- **AC4:** The forward-only migration (FR4) re-applies cleanly against a dev where the recovery has run — verified by the post-recovery `tenant-integration` green.
- **AC5:** #4325 closed with a comment referencing PR #4339 as the original drift-detection fix and this PR as the hardening delta bundle. Closing reason: "duplicate-class of #4338; delta hardening in PR #4354."

## Sharp Edges

1. **Delta 3 cannot touch 058/060 in place.** Changing the `content_sha` of an applied migration trips the #4241 filename-vs-main drift probe. Forward-only or helper-function only.
2. **Delta 1 must run BEFORE PR ready-for-review.** The green tenant-integration on this PR is the proof gate; without recovery the migration sequence is broken at apply time on dev and CI will stay red regardless of code correctness.
3. **Lint scope is new-files-only.** Existing 062+ migrations are not retroactively linted — the lint is forward-protection. If retroactive coverage is wanted, scope that as a separate sweep PR after this one merges.
4. **The probe + lint cover different surfaces.** Lint is a static check on the PR diff (regex against file text). Probe is a runtime check against the live schema. Both compose — neither replaces the other.

## Test Scenarios

1. **Synthetic lint negative:** Create a temporary migration file with `REFERENCES public.fake_external_table` and no precondition, run lint script — expect non-zero exit + named-relation error.
2. **Synthetic lint positive:** Same migration with prepended `DO $$ BEGIN IF to_regclass('public.fake_external_table') IS NULL THEN RAISE EXCEPTION ... END IF; END $$;` — expect zero exit.
3. **Synthetic lint self-FK exclusion:** Migration with `CREATE TABLE public.foo (id ...) ... REFERENCES public.foo(id)` — expect zero exit (self-FK subtracted).
4. **Default-on probe:** `bash apps/web-platform/scripts/run-migrations.sh` (no env override) — expect probe to fire on a test fixture with a missing cross-file FK target.
5. **Probe opt-out:** `MIGRATION_SCHEMA_PRECONDITION_PROBE=0 bash apps/web-platform/scripts/run-migrations.sh` — expect probe to silently skip.
6. **End-to-end recovery proof:** Operator runs Delta 1 against dev. `tenant-integration` CI run on this PR's branch — expect green. Captured in AC1.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-22-dev-supabase-drift-deltas-4325-brainstorm.md`
- Recovery runbook: `knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md`
- Sibling fix PR: #4339
- Sibling issue: #4338
- Filename-vs-main drift precedent: #4241
