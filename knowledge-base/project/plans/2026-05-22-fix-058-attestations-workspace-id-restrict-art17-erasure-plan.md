---
deepened_on: 2026-05-22
deepen_gates_passed: [4.5-network-outage-N/A, 4.6-user-brand-impact-PASS, 4.7-observability-PASS, 4.8-pat-shaped-PASS]
---

## Enhancement Summary

**Deepened on:** 2026-05-22
**Sections enhanced:** 6 (Risks, Phases 0/2/3, Acceptance Criteria, Sharp Edges, Files to Edit)
**Research probes:** 6 (063 sister-table FK shape, 063 anonymise pattern, FK constraint name convention, Postgres ALTER ordering, PA-2 reference count, account-delete cascade map)

### Key Improvements

1. **CRITICAL DISCOVERY — 063 has the same RESTRICT defect class.** `apps/web-platform/supabase/migrations/063_workspace_member_actions.sql:51` defines `workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE RESTRICT`. When account-delete step 3.92 (`anonymise_organization_membership`) issues `DELETE FROM public.workspaces`, the 063 audit rows pointing at those workspaces will block the DELETE in EXACTLY the same way as 058 attestations. The PR plan currently scopes ONLY to 058 per #4329's wording. Deepen recommendation: **add a Phase 0.5 gate that confirms scope decision (058-only fix vs 058+063 fix) BEFORE Phase 1 RED**. See expanded §Risks + new §Pre-implementation Decision Gate.
2. **063 uses a pure-reject WORM trigger (NOT structural-shape).** Unlike 058+062, the 063 trigger at `063:116-124` is a `RAISE EXCEPTION` always-reject; bypass is `SET LOCAL session_replication_role='replica'` (no NULL-transition admit-arm exists). If we fold 063 into this PR, the fix shape DIFFERS from 064 — 063 only needs the FK demotion + DROP NOT NULL, NOT a trigger rewrite (the `session_replication_role='replica'` bypass already handles the ON DELETE SET NULL transition because replica-role disables all triggers).
3. **ALTER ordering load-bearing.** `ALTER COLUMN workspace_id DROP NOT NULL` MUST precede the cascade firing in production. The single-statement multi-clause ALTER TABLE form (`DROP CONSTRAINT …, ADD CONSTRAINT …, ALTER COLUMN …`) is atomic at the statement level; using separate ALTER TABLE statements creates a window where the NEW SET NULL FK could fire on a NOT NULL column. Even outside a cascade-fire window, the migration runner applies statements sequentially — combine into one ALTER TABLE.
4. **AC4 awk-range self-match risk.** The original AC4 `awk '/CREATE OR REPLACE FUNCTION public\.workspace_member_attestations_no_mutate/{flag=1} flag{print} /^\$\$;/{flag=0; exit}'` form is flag-based (not range), so the awk self-match Sharp Edge from plan SKILL does not apply. Verified safe.
5. **Constraint-name verification feasibility.** The Phase 0.4 plan to verify FK name divergence via Postgres `\d` cannot run offline. Mitigation already in plan (preflight DO-block in §2 of migration). Adding to AC: probe with Supabase MCP at Phase 0 IF a dev/prd connection is available, otherwise rely on the migration's own preflight RAISE.
6. **PA-2 register edit conflict risk.** PA-2's co-member note already references the cascade fn name twice. The plan-prescribed edit appends a sentence; verified at deepen time that no other plan/PR currently has a pending edit to PA-2 (no open PRs touching `article-30-register.md` PA-2 section per `gh pr list --search "article-30-register" --state open`).

### New Considerations Discovered

- **Issue scope decision required.** #4329 explicitly says "058 sister-table" but the architectural symmetry argument extends to 063. If we close #4329 with 058-only, we ship a known-defective 063. If we extend scope, the PR title + AC + ADR updates need to mention BOTH tables. The cheaper path is to file #4329-A for 063 immediately after merging 058's fix, but the operator gate at flag-flip (#4284) MUST gate on both. Recommendation: **scope this PR to 058-only (faithful to #4329's body), file follow-up issue for 063 IMMEDIATELY at /work Phase 0, block #4284 on both being merged**.
- **The WORM-trigger rewrite must also preserve the existing 5-column PII transition admit-arm.** The plan correctly captures this in §2.1 §4 but the lint test must NOT regress the existing structural-shape coverage that was load-bearing for `anonymise_workspace_member_attestations` PII NULL-sets at 058:342-362. AC11 should explicitly verify all 5 PII column NULL transitions remain admitted post-rewrite.
- **`anonymise_workspace_member_attestations` does NOT need code changes.** The RPC (058:342-362) NULLs the 5 PII columns; that operation already passes the existing trigger (NOT NULL → NULL admitted). Post-064 the same RPC continues to work; the only new admitted transition is on workspace_id, which the RPC does NOT touch. No code-side test changes needed beyond the migration-shape lint.
- **Cascade ordering verification.** Cascade order is preserved: 3.90 attestations PII NULL → 3.91 members DELETE → 3.92 orgs/workspaces DELETE → SET NULL cascades back to attestations.workspace_id. The new admit-arm fires AT 3.92 (not earlier).

---

issue: 4329
title: "fix(supabase): mig 064 058-attestations workspace_id RESTRICT FK → SET NULL to unblock Art. 17 orphan-org cleanup"
type: bug-fix
classification: gdpr-art17-blocker
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user-incident
target_users: workspace owners + invited workspace members + any user invoking GDPR Art. 17 erasure
related:
  - 4329  # this issue
  - 4230  # PR #4294 sister-table fix (workspace_member_removals)
  - 4229  # team-workspace umbrella
  - 4225  # PR that introduced 058
  - 4284  # FLAG_TEAM_WORKSPACE_INVITE=1 flag-flip (GATED on this issue)
  - 4289  # legal scaffolding (PR-shipped)
adrs:
  - ADR-038-team-workspace-multi-user-organizations-and-workspace-members
  - ADR-039-departed-member-removal-ledger
migrations:
  - apps/web-platform/supabase/migrations/064_fix_058_attestations_workspace_id_set_null.sql
  - apps/web-platform/supabase/migrations/064_fix_058_attestations_workspace_id_set_null.down.sql
plan_review_date: 2026-05-22
---

# Plan: fix 058 `workspace_member_attestations.workspace_id` RESTRICT FK blocking Art. 17 orphan-org cleanup

Closes #4329. Re-evaluation trigger fired: prerequisite to #4284 (`FLAG_TEAM_WORKSPACE_INVITE=1` rollout in prd) per the deferred-scope-out's re-evaluation criterion. PR #4294 has merged (`feat(dsar): departed-workspace-member coverage`) and #4289 is also merged; #4329 is the last DSAR/Art-17 blocker remaining for #4284.

## Overview

`workspace_member_attestations.workspace_id REFERENCES public.workspaces(id) ON DELETE RESTRICT` (mig `058_workspace_member_attestations.sql:43`) causes a deterministic Art. 17 erasure failure for any account-delete cascade whose user is the **sole owner of a workspace that has at least one prior attestation row** (any invite the owner ever issued or accepted).

The cascade ordering in `apps/web-platform/server/account-delete.ts` is:

```
3.90  anonymise_workspace_member_attestations  -- NULLs invitee + inviter user_id only; workspace_id LEFT POPULATED
3.905 anonymise_workspace_member_removals      -- 062 sister; ALSO leaves attestations.workspace_id alone
3.91  anonymise_workspace_members              -- DELETEs membership rows
3.92  anonymise_organization_membership        -- 058:419-468; orphan-org branch issues `DELETE FROM public.workspaces WHERE organization_id = …`
4     auth.admin.deleteUser
```

Step 3.92's `DELETE FROM public.workspaces` (058:445) is blocked by ANY attestation row whose `workspace_id` points at that workspace, regardless of whether the PII columns are already NULL. The auth-delete never fires; the cascade returns `{ success: false, error: "Account deletion failed. Please try again." }`. The user receives a generic error and their data is not erased — a **single-user incident** brand-survival failure for GDPR Art. 17(1).

PR #4294 already solved this exact class for the sibling table `workspace_member_removals` per ADR-039 §Invariants.1 carve-out (DISSENT-flip during multi-agent review): `workspace_id` FK demoted `RESTRICT → SET NULL` + WORM trigger extended to permit the implicit `NOT NULL → NULL` transition. This plan applies the identical carve-out to 058's `workspace_member_attestations.workspace_id` as a new migration 064, mirroring 062's structural shape verbatim except in scope (ALTER not CREATE TABLE).

## User-Brand Impact

**If this lands broken, the user experiences:** clicking "Delete my account" returns a generic error toast; the cascade aborts mid-flight at step 3.92; their account is NOT deleted; their PII (attestation_text, ip_hash, user_agent, conversation history, BYOK keys) persists indefinitely past their stated wish to erase. Repeated retries do not recover. Operator must hand-anonymise via direct SQL.

**If this leaks, the user's [erasure right / GDPR Art. 17 entitlement] is exposed via:** Soleur retaining the user's data past their Art. 17 erasure request. The breach surface is not a *new* data exposure but a *failure to erase*, which is itself a controller breach under Art. 5(1)(d) accuracy + Art. 17(1) erasure obligation. Notifiable to supervisory authorities under Art. 33 if the cascade aborts and the user is not informed; potentially notifiable to data subjects under Art. 34 depending on supervisory-authority guidance on "high risk" framing.

**Brand-survival threshold:** single-user incident — one user who attempts account deletion, cannot complete it, and contacts a privacy regulator or publishes the failure on social media is unrecoverable for trust in our Art. 17 substrate. The defect is **dormant** today because `FLAG_TEAM_WORKSPACE_INVITE=0` means no non-jikigai user has accepted an invite + has attestation rows; flag-flip without this fix is unsafe.

CPO sign-off required at plan time before `/work` begins (per `requires_cpo_signoff: true`). `user-impact-reviewer` MUST be invoked at PR review.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue-body claim | Codebase reality (verified at plan time) | Plan response |
|---|---|---|
| Defect is at `058:43` | Confirmed — `workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE RESTRICT` at line 43 of `apps/web-platform/supabase/migrations/058_workspace_member_attestations.sql` | Migration 064 ALTERs both the constraint AND the NOT NULL |
| Orphan-org DELETE is at `058:419-468` | Confirmed — `DELETE FROM public.workspaces WHERE organization_id = v_org_rec.org_id` at 058:445 inside `anonymise_organization_membership` loop | No change needed in 058 RPC; the FK demotion alone is sufficient |
| Issue body proposes Option (i): single migration mirroring PR #4294's approach to attestations | PR #4294's actual implementation is migration 062 with ALTERs to existing trigger + REVOKE rebuild. For 058 the equivalent is mig 064 with an ALTER TABLE on the existing `workspace_member_attestations`. | Plan adopts Option (i) verbatim |
| Issue body says "trigger update relaxes workspace_id lineage immutability to NOT NULL → NULL admissible" | Confirmed — current 058:97-99 hard-rejects ANY `workspace_id` change via "audit lineage is immutable". Must be replaced by the same shape as 062:180-196 (lineage immutable EXCEPT for the `ON DELETE SET NULL`-driven NOT NULL → NULL transition) | Plan replaces `workspace_member_attestations_no_mutate()` with the 062-style structural-shape body |
| Issue body says "Update lint test, ADR-038, PA-2 entry to match the carve-out" | Lint test for 058 does NOT exist as a standalone file (verified via `find apps/web-platform/test -name "*058*"`). PR #4294 added `062-workspace-member-removals.test.ts` as the canonical migration-shape lint pattern. ADR-038 §Invariants does NOT presently mention the RESTRICT-vs-SET-NULL contract for 058's workspace_id. PA-2 entry's "Workspace co-member data category" note in `article-30-register.md:67` references the 058 cascade and needs an updated description of the workspace_id carve-out + cross-reference to PA-19. | Plan creates `test/supabase-migrations/064-fix-058-attestations-workspace-id-set-null.test.ts` as the new migration-shape lint (mirrors 062's structure); adds ADR-038 §Invariants update; updates PA-2 co-member note + PA-19 cross-reference |
| Issue body proposes "DROP CONSTRAINT … workspace_member_attestations_workspace_id_fkey, ADD FOREIGN KEY … ON DELETE SET NULL" | Constraint name follows the Postgres-default convention `<tablename>_<columnname>_fkey`. Verified by `psql \d public.workspace_member_attestations` is unavailable offline; the migration must use the conventional name and tolerate failure via `IF EXISTS` for safety. | Migration uses `ALTER TABLE … DROP CONSTRAINT IF EXISTS workspace_member_attestations_workspace_id_fkey, ADD CONSTRAINT workspace_member_attestations_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE SET NULL` as a single ALTER batch |
| Issue body assumes the WORM-trigger 062-style structural-shape pattern can be copied verbatim | Verified — 062:140-212 trigger function is self-contained and reusable. Lineage columns for attestations are `(id, accepted_at)` (not `(id, removed_at)` from 062). PII column set is 5: `(inviter_user_id, invitee_user_id, attestation_text, ip_hash, user_agent)` (not 2 from 062). | Plan adapts 062's pattern with the correct column set; tests assert each PII column's NULL transition separately |
| Issue body says "Both FK columns (removals)" but for attestations there are 3 user FKs | Confirmed — attestations has `(workspace_id, inviter_user_id, invitee_user_id)` as FK columns. workspace_id is the only one being changed. inviter/invitee_user_id stay `ON DELETE RESTRICT` (their carve-out is via existing `anonymise_workspace_member_attestations` PII NULL-set; FK is broken before auth-delete). | No change to inviter/invitee FK shape; only workspace_id ALTERed |

## Files to Edit

- `apps/web-platform/server/account-delete.ts` — update step 3.90 docstring (lines 369-396) to note that attestations.workspace_id is now `ON DELETE SET NULL` (mirrors 062 pattern); remove the comment claim at 3.91 (line 432) that "workspaces stay live" since 064 now permits `workspace_id` NULL transition. No behavioural change — the cascade order is unchanged, only the comments reflect the new shape.
- `knowledge-base/engineering/architecture/decisions/ADR-038-team-workspace-multi-user-organizations-and-workspace-members.md` — add a `§Invariants` subsection (mirror of ADR-039 §Invariants.1) documenting the `workspace_member_attestations.workspace_id` carve-out: `ON DELETE SET NULL` + WORM trigger permits implicit `NOT NULL → NULL` transition; rationale = orphan-org cleanup in `anonymise_organization_membership` (058:419-468). Cross-reference ADR-039 §Invariants.1 (the sister-table carve-out).
- `knowledge-base/engineering/architecture/decisions/ADR-039-departed-member-removal-ledger.md` — update §Invariants.1's parenthetical claim "Pre-existing parallel: `workspace_member_attestations.workspace_id` (058:43) keeps its `ON DELETE RESTRICT` FK shape; that's the sister-table defect tracked as a separate pre-existing-unrelated finding against `main`." → change to "Sister-table 058 attestations.workspace_id resolved in mig 064 (#4329) via mirror carve-out."
- `knowledge-base/legal/article-30-register.md` — update PA-2 "Workspace co-member data category" note (line 67) to add: "Attestations `workspace_id` FK is `ON DELETE SET NULL` (mig 064, #4329) — orphan-org cleanup permitted; mirrors PA-19's workspace_id carve-out per ADR-038 §Invariants and ADR-039 §Invariants.1." Update PA-19 (line 352) "the sister-table `workspace_member_attestations.workspace_id` at 058:43 keeps its pre-existing RESTRICT shape, tracked separately" → "resolved in mig 064 (#4329); both tables now share the workspace_id carve-out shape per ADR-038/039."
- `knowledge-base/legal/compliance-posture.md` — update the active item tracking #4329 (line 97 area) from "Scope-split: …Sister-table defect on 058… filed at #4329 (pre-existing-unrelated)" → "Closed via PR #<TBD> mig 064 (#4329); 058 + 062 now share the workspace_id carve-out shape."
- `knowledge-base/project/specs/feat-one-shot-4329-attestations-fk-art17-erasure/spec.md` — derived from this plan (created by spec-templates skill at plan-time).
- `knowledge-base/project/specs/feat-one-shot-4329-attestations-fk-art17-erasure/tasks.md` — derived from this plan.

## Files to Create

- `apps/web-platform/supabase/migrations/064_fix_058_attestations_workspace_id_set_null.sql` — ALTER TABLE attestations: `DROP CONSTRAINT … workspace_member_attestations_workspace_id_fkey, ADD CONSTRAINT … FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE SET NULL`; `ALTER COLUMN workspace_id DROP NOT NULL`; `CREATE OR REPLACE FUNCTION public.workspace_member_attestations_no_mutate()` body replaced with 062:140-212-style structural-shape (lineage = id + accepted_at only; workspace_id NOT NULL → NULL admissible; PII = 5 columns NOT NULL → NULL admissible).
- `apps/web-platform/supabase/migrations/064_fix_058_attestations_workspace_id_set_null.down.sql` — Reverse migration with 0-row guard (mirror 062 down's data-integrity-guardian P2-1 pattern at 062 down.sql:11-32). Revert: `ALTER COLUMN workspace_id SET NOT NULL` (preconditional on no NULL rows); `DROP CONSTRAINT … ADD CONSTRAINT … ON DELETE RESTRICT`; restore the original 058:72-125 trigger function body verbatim.
- `apps/web-platform/test/supabase-migrations/064-fix-058-attestations-workspace-id-set-null.test.ts` — Migration-shape lint test (vitest, no live DB) mirroring `062-workspace-member-removals.test.ts` (1:1 structure) but scoped to the ALTER + trigger replacement. Asserts:
  - workspace_id FK is `ON DELETE SET NULL`
  - workspace_id is NULL-able post-ALTER (DROP NOT NULL)
  - Trigger function body matches the structural-shape pattern: lineage = `(id, accepted_at)` only; workspace_id transition admits `NOT NULL → NULL`; 5 PII columns each admit `NOT NULL → NULL`
  - Trigger function does NOT reference `current_user` (per learning 2026-05-18)
  - Triggers re-attached (BEFORE UPDATE + BEFORE DELETE)
  - REVOKE matrix on trigger function preserved
  - Down migration includes the 0-row guard + restores the original trigger body
  - **Carve-out parity test**: asserts the 064 trigger body's structural-shape pattern matches 062:140-212's structural-shape pattern (same predicate skeleton, different column set) — defends against drift between sister-tables.

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --json number,title,body --limit 200` then jq-grep for each Files-to-Edit path.

| File | Open code-review issue | Disposition |
|---|---|---|
| `apps/web-platform/supabase/migrations/058_workspace_member_attestations.sql` | #4329 (this issue) | Folded in — the resolution IS this PR. `Closes #4329` in PR body. |
| `apps/web-platform/server/account-delete.ts` | None open against this file's cascade ordering | N/A |
| `knowledge-base/legal/article-30-register.md` | None against PA-2/PA-19 | N/A |
| ADR-038 / ADR-039 | None | N/A |

No new overlap beyond #4329 itself. (Plan-time grep ran; explicit `None` for the remaining edited files.)

## Acceptance Criteria

### Pre-merge (PR)

- **AC1: Migration shape lint passes.** `cd apps/web-platform && bun x vitest run test/supabase-migrations/064-fix-058-attestations-workspace-id-set-null.test.ts` returns exit 0. Every assertion in the lint test passes.

- **AC2: workspace_id FK ALTER is the canonical-shape ALTER.**
  ```bash
  grep -E "ALTER\s+TABLE\s+public\.workspace_member_attestations[\s\S]*?DROP\s+CONSTRAINT\s+IF\s+EXISTS\s+workspace_member_attestations_workspace_id_fkey[\s\S]*?ADD\s+CONSTRAINT\s+workspace_member_attestations_workspace_id_fkey\s+FOREIGN\s+KEY\s*\(workspace_id\)\s+REFERENCES\s+public\.workspaces\(id\)\s+ON\s+DELETE\s+SET\s+NULL" apps/web-platform/supabase/migrations/064_fix_058_attestations_workspace_id_set_null.sql
  ```
  Returns ≥1 match.

- **AC2.5: FK swap + NULL drop are in the SAME ALTER TABLE statement (deepen-added).** Single multi-clause ALTER atomicity prevents window where new SET NULL FK could fire on still-NOT NULL column. Single regex spans both clauses:
  ```bash
  grep -E "ALTER\s+TABLE\s+public\.workspace_member_attestations[\s\S]{0,1500}?DROP\s+CONSTRAINT\s+IF\s+EXISTS[\s\S]{0,200}?ADD\s+CONSTRAINT[\s\S]{0,300}?ON\s+DELETE\s+SET\s+NULL[\s\S]{0,300}?ALTER\s+COLUMN\s+workspace_id\s+DROP\s+NOT\s+NULL\s*;" apps/web-platform/supabase/migrations/064_fix_058_attestations_workspace_id_set_null.sql
  ```
  Returns ≥1 match (single statement spans all 3 clauses, terminated by single `;`).

- **AC3: workspace_id is NULL-able post-ALTER.**
  ```bash
  grep -E "ALTER\s+TABLE\s+public\.workspace_member_attestations\s+ALTER\s+COLUMN\s+workspace_id\s+DROP\s+NOT\s+NULL" apps/web-platform/supabase/migrations/064_fix_058_attestations_workspace_id_set_null.sql
  ```
  Returns ≥1 match.

- **AC4: Trigger function does NOT reference `current_user` (per learning 2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing).**
  ```bash
  awk '/CREATE OR REPLACE FUNCTION public\.workspace_member_attestations_no_mutate/{flag=1} flag{print} /^\$\$;/{flag=0; exit}' apps/web-platform/supabase/migrations/064_fix_058_attestations_workspace_id_set_null.sql | grep -c 'current_user' | grep -q '^0$'
  ```
  Returns exit 0 (zero matches inside the function body).

- **AC5: Cascade ordering preserved + comments updated.**
  ```bash
  grep -nE "step 3\.90|step 3\.91|step 3\.92|step 3\.905" apps/web-platform/server/account-delete.ts | wc -l
  ```
  Returns ≥4 (existing markers preserved). Additionally, the 3.91 comment block (line ~428-433) MUST no longer claim "workspaces stay live" without qualification — grep returns 0:
  ```bash
  awk '/3\.91 Anonymise workspace_members/,/^  try \{$/' apps/web-platform/server/account-delete.ts | grep -c "workspaces stay live"
  # expected: 0 (replaced with: "workspaces may be deleted by anonymise_organization_membership in 3.92 — attestations.workspace_id ON DELETE SET NULL admits the cascade post-mig 064")
  ```

- **AC6: ADR-038 §Invariants section added.**
  ```bash
  grep -cE "## Invariants|### Invariants|workspace_member_attestations\.workspace_id.*SET NULL|mig 064" knowledge-base/engineering/architecture/decisions/ADR-038-team-workspace-multi-user-organizations-and-workspace-members.md
  ```
  Returns ≥3.

- **AC7: ADR-039 §Invariants.1 cross-reference updated.**
  ```bash
  grep -cE "mig 064|#4329|resolved.*mig 064|both tables now share" knowledge-base/engineering/architecture/decisions/ADR-039-departed-member-removal-ledger.md
  ```
  Returns ≥1.

- **AC8: article-30-register.md PA-2 + PA-19 cross-references updated.**
  ```bash
  grep -cE "mig 064|#4329" knowledge-base/legal/article-30-register.md
  ```
  Returns ≥2 (one in PA-2 co-member note, one in PA-19 cross-reference).

- **AC9: compliance-posture.md active item updated.**
  ```bash
  grep -cE "#4329.*(Closed|resolved|mig 064)" knowledge-base/legal/compliance-posture.md
  ```
  Returns ≥1.

- **AC10: Down migration parity.**
  ```bash
  test -f apps/web-platform/supabase/migrations/064_fix_058_attestations_workspace_id_set_null.down.sql && \
    grep -cE "0-row guard|Refusing to drop|NULL rows present|ALTER COLUMN workspace_id SET NOT NULL" apps/web-platform/supabase/migrations/064_fix_058_attestations_workspace_id_set_null.down.sql
  ```
  Returns ≥2 (0-row guard + SET NOT NULL).

- **AC11: Carve-out parity assertion in lint test.** The 064 lint test includes one explicit test that reads BOTH `062_workspace_member_removals_and_remove_rpc_update.sql` AND `064_*.sql` trigger bodies and asserts both contain the structural-shape pattern (`OLD.workspace_id IS NULL AND NEW.workspace_id IS NOT NULL` rejection arm). Verified by the test passing.

- **AC12: No new write sites to attestations.** Re-run the existing `apps/web-platform/scripts/check-workspace-members-write-sites.sh` (or its attestations-sibling if it exists) returns exit 0.
  ```bash
  bash apps/web-platform/scripts/check-workspace-members-write-sites.sh
  ```
  Exit 0.

- **AC13: existing 058 + 062 lint tests still pass** (regression check).
  ```bash
  cd apps/web-platform && bun x vitest run test/supabase-migrations/062-workspace-member-removals.test.ts test/dsar-allowlist-completeness.test.ts
  ```
  All pass.

- **AC14: Migration runner test still passes** (the schema-probe gate `apps/web-platform/scripts/run-migrations-schema-probe.test.sh` was added by PR #4294 — re-run after 064 lands):
  ```bash
  bash apps/web-platform/scripts/run-migrations-schema-probe.test.sh
  ```
  Exit 0.

- **AC15: `Ref #4329` in PR body** (not `Closes #4329`) per `wg-use-closes-n-in-pr-body-not-title-to` + the ops-remediation-class Sharp Edge. The operator action at flag-flip time (#4284) gates on this issue being verified-applied to prd, not just merged to main. Issue closes after the post-merge migration-apply verification (AC16).

  Update: Standard Closes #4329 is acceptable here because `web-platform-release.yml#migrate` auto-applies migrations on merge to main (verified via the auto-apply pattern at PR #4294's AC9). The migration runs in CI immediately on merge; no operator-attested post-merge step is required. Use `Closes #4329` in PR body.

### Post-merge (CI-automated; operator verifies)

- **AC16: Migration 064 applied to prd by `web-platform-release.yml#migrate` job.** Verified via:
  ```bash
  gh run list --workflow=web-platform-release.yml --branch=main --limit=1 --json status,conclusion,databaseId,jobs \
    | jq -r '.[0].jobs[] | select(.name == "migrate") | .conclusion'
  # expected: success
  ```
  Plus mcp__plugin_supabase_supabase__execute_sql against prd:
  ```sql
  SELECT confdeltype FROM pg_constraint
   WHERE conname = 'workspace_member_attestations_workspace_id_fkey';
  -- expected: 'n' (SET NULL)
  ```
  AND
  ```sql
  SELECT is_nullable FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name = 'workspace_member_attestations'
     AND column_name = 'workspace_id';
  -- expected: 'YES'
  ```
  Both queries are automatable via the Supabase MCP server; no SSH, no dashboard eyeballing.

## Implementation Phases

### Phase 0 — Pre-implementation Decision Gate (NEW, deepen-added)

0.0. **Sister-table 063 scope decision.** Confirmed at deepen time that `apps/web-platform/supabase/migrations/063_workspace_member_actions.sql:51` has the SAME `workspace_id NOT NULL REFERENCES public.workspaces(id) ON DELETE RESTRICT` defect class as 058. The orphan-org DELETE in step 3.92 will be blocked by 063 audit rows in the same way as 058 attestations.

**Decision (recommended):** Scope THIS PR to 058 only (faithful to #4329's body). File follow-up issue #4329-A immediately at /work Phase 0 with title `fix(supabase): mig 065 063-workspace_member_actions workspace_id RESTRICT → SET NULL (Art. 17 erasure unblock, sister to #4329)`. Block #4284 flag-flip on both #4329 + #4329-A being merged.

**Rationale for split:**
- Single-concern PR discipline (`cm-delegate-verbose-exploration`-class) keeps review surface focused.
- 063's fix shape DIFFERS from 064 — 063's WORM trigger is pure-reject at 063:116-124 (raises on ALL UPDATE/DELETE); bypass is `SET LOCAL session_replication_role='replica'` already used inside `anonymise_workspace_member_actions` at 063:313. For 063, the FK demotion + DROP NOT NULL alone is sufficient — NO trigger rewrite needed because the implicit ON DELETE SET NULL cascade fires WITHOUT routing through the trigger (the trigger only fires on application-level UPDATE/DELETE; FK cascades fire as system actions that the pure-reject trigger would BLOCK — this needs verification at #4329-A plan time).
- Splitting de-risks: if 063's trigger pattern requires a different approach (e.g., the pure-reject trigger needs an explicit cascade-time admit-arm), it does not block 058's Art. 17 unblock.

**Alternative (extended scope):** Fold 063 into THIS PR by adding migration 065. Estimate +2h work, +1 review cycle. Reject UNLESS multi-agent review at PR-open time CONCURs that single-issue scope is unsafe.

**Operator gate:** #4329-A MUST exist and be linked as blocker to #4284 before THIS PR's merge — otherwise #4284 follow-through could fire on #4329-A still being open.

### Phase 0.1 — Preconditions (no code edits)

0.1.0. **Verify ALTER ordering** (deepen-added). The 064 migration MUST issue ALTER COLUMN DROP NOT NULL + the FK shape change as ONE multi-clause ALTER TABLE statement (Postgres atomic at statement-level). Verified at deepen time:
- Postgres docs: `ALTER TABLE` accepts multiple comma-separated clauses; all execute as a single transaction step.
- The single-statement form prevents the window where the NEW SET NULL FK could fire against a still-NOT-NULL column (would raise NOT NULL violation).
- Migration shape: `ALTER TABLE public.workspace_member_attestations DROP CONSTRAINT IF EXISTS workspace_member_attestations_workspace_id_fkey, ADD CONSTRAINT workspace_member_attestations_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE SET NULL, ALTER COLUMN workspace_id DROP NOT NULL;`
- AC2 + AC3 already verify each clause's presence; deepen-added AC2.5 confirms they're in the same ALTER TABLE statement (regex spans both).

0.1. Verify the current state at the defect site:
```bash
grep -n "workspace_id\s\+uuid\s\+NOT NULL\s\+REFERENCES\s\+public\.workspaces(id)\s\+ON DELETE RESTRICT" \
  apps/web-platform/supabase/migrations/058_workspace_member_attestations.sql
# expected: 058:43
```

0.2. Verify next migration number is 064:
```bash
ls apps/web-platform/supabase/migrations/ | grep -E "^06[3-9]" | sort
# expected: 063_workspace_member_actions.sql + .down.sql only (no 064 yet)
```

0.3. Read the canonical 062 reference end-to-end (one Read per file):
- `apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql` lines 140-212 (trigger function pattern to mirror)
- `apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.down.sql` lines 11-32 (0-row guard pattern)
- `apps/web-platform/test/supabase-migrations/062-workspace-member-removals.test.ts` (entire file — lint structure to mirror)

0.4. Probe FK constraint default name convention. Postgres-default naming for an inline `REFERENCES` is `<tablename>_<columnname>_fkey`. For attestations.workspace_id this is `workspace_member_attestations_workspace_id_fkey`. Verify by reading the down migration of 058 (which DROPs constraints) — `apps/web-platform/supabase/migrations/058_workspace_member_attestations.down.sql` shows no explicit FK constraint drop for attestations.workspace_id (only the `workspace_members_attestation_id_fkey` ALTER), confirming the constraint was created with the default name and is dropped implicitly with the table. The ALTER form in 064 MUST use `DROP CONSTRAINT IF EXISTS` (defense-in-depth) — if the default name diverged on prd, the migration aborts with a loud "constraint does not exist" rather than silently leaving RESTRICT in place. Add a fail-loud guard.

### Phase 1 — RED: Write the migration-shape lint test

1.1. Create `apps/web-platform/test/supabase-migrations/064-fix-058-attestations-workspace-id-set-null.test.ts`. Use 062's lint test as the structural template (1:1 layout, adapted column set). Test groups:
- "AC2: workspace_id FK is ON DELETE SET NULL"
- "AC3: workspace_id DROP NOT NULL"
- "AC1: trigger function rewrite — structural-shape pattern"
  - Lineage = `(id, accepted_at)` only (NOT `(id, workspace_id, accepted_at)` per the pre-064 body)
  - workspace_id NOT NULL → NULL admissible
  - workspace_id NULL → NOT NULL OR value-change rejected (with the exact P0001 message text)
  - Each of 5 PII columns: NOT NULL → NULL admissible
  - No `current_user` reference inside the function body
- "AC11: Carve-out parity vs. 062"
  - Read BOTH 062 + 064 trigger bodies; assert both contain the canonical workspace_id NULL-transition admit-arm
- "Down migration"
  - 0-row guard against silent destroy
  - Restores original 058:72-125 trigger body verbatim
  - Restores `ALTER COLUMN workspace_id SET NOT NULL` only if 0-row guard passes
  - Restores `ON DELETE RESTRICT` FK

1.2. Run the test — it MUST fail (064 migration does not exist yet). Capture failure mode in tasks.md as the RED checkpoint.

### Phase 2 — GREEN: Write the migration

2.1. Create `apps/web-platform/supabase/migrations/064_fix_058_attestations_workspace_id_set_null.sql`. Structure:
- Header comment (mirror 062:1-58 style): purpose, ADR-038 + ADR-039 references, learning citations, cascade-order rationale, GDPR Art. 17 motivation, "sister-table 062 pattern verbatim" note.
- §1 Preflight DO-block: verify `public.workspace_member_attestations` exists; abort with self-describing RAISE EXCEPTION + recovery hint if not (mirror 062:75-83 pattern). Verify the constraint `workspace_member_attestations_workspace_id_fkey` exists; if absent, RAISE EXCEPTION with explicit hint that the constraint may have a divergent name on this database — operator must `\d public.workspace_member_attestations` and rename in this migration before re-applying.
- §2 ALTER TABLE: `DROP CONSTRAINT IF EXISTS workspace_member_attestations_workspace_id_fkey, ADD CONSTRAINT workspace_member_attestations_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE SET NULL`.
- §3 ALTER COLUMN: `ALTER COLUMN workspace_id DROP NOT NULL`.
- §4 CREATE OR REPLACE FUNCTION `public.workspace_member_attestations_no_mutate()`. Body adapted from 062:140-212:
  - DELETE arm: unchanged from 058 (DELETE always rejected — attestations has no retention sweep)
  - UPDATE arm: lineage = `(id, accepted_at)` only (workspace_id REMOVED from lineage); workspace_id NOT NULL → NULL admit / NULL → NOT NULL or value-change reject (P0001); 5 PII columns each NOT NULL → NULL admit (verbatim from existing 058:108-117).
  - No `current_user` reference.
- §5 Re-attach triggers (DROP + CREATE TRIGGER, mirror 058:129-137).
- §6 REVOKE ALL ON FUNCTION (mirror 058:127).

2.2. Run the lint test from Phase 1. MUST pass.

### Phase 3 — Down migration

3.1. Create `apps/web-platform/supabase/migrations/064_fix_058_attestations_workspace_id_set_null.down.sql`. Structure (mirror 062 down at 062 down.sql:11-128):
- §0 0-row guard. For attestations the guard is different from 062's "table has rows" — attestations is expected to have rows; the guard is "no rows have workspace_id IS NULL". If any row has workspace_id NULL (because anonymise_organization_membership has fired on it since 064 was applied), `SET NOT NULL` would fail loudly anyway, but the explicit guard surfaces the class with a clearer message:
  ```sql
  IF EXISTS (
    SELECT 1 FROM public.workspace_member_attestations WHERE workspace_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Refusing to revert mig 064: % rows have workspace_id NULL (set by orphan-org cleanup). Down-migration would either re-link them to dead workspaces (impossible) or fail at SET NOT NULL. Restore from backup OR delete affected rows after CLO sign-off.', (SELECT count(*) FROM public.workspace_member_attestations WHERE workspace_id IS NULL)
      USING ERRCODE = 'P0001';
  END IF;
  ```
- §1 Restore original 058 trigger body verbatim (paste 058:72-125).
- §2 Re-attach triggers.
- §3 ALTER COLUMN workspace_id SET NOT NULL.
- §4 ALTER TABLE: DROP CONSTRAINT … ADD CONSTRAINT … ON DELETE RESTRICT.

3.2. Run the lint test. MUST pass (down-migration assertions now satisfied).

### Phase 4 — Comment + doc updates

4.1. Update `apps/web-platform/server/account-delete.ts`:
- §3.90 docstring (lines 369-396): add a line noting "Post-mig 064 (#4329): attestations.workspace_id is `ON DELETE SET NULL`; the workspace DELETE in 3.92 cascades the NULL-set to surviving attestation rows. The WORM trigger admits this transition per ADR-038 §Invariants."
- §3.91 docstring (lines 428-433): replace "workspaces stay live (they're cleaned up by anonymise_organization_membership in 3.92 if they orphan)" with "workspaces may be deleted by anonymise_organization_membership in 3.92; attestations.workspace_id ON DELETE SET NULL (mig 064, #4329) admits the cascade."

4.2. Update `knowledge-base/engineering/architecture/decisions/ADR-038-team-workspace-multi-user-organizations-and-workspace-members.md`. Add a `### Invariants` subsection after the existing structural sections. Mirror ADR-039 §Invariants.1 wording adapted for attestations. Explicit content:
- **WORM (write-once, anonymise-only).** Structural-shape pattern. DELETE always rejected. UPDATE allowed for NULL transitions on the 5 PII columns AND on workspace_id. Strict-immutable lineage = `(id, accepted_at)` only. workspace_id carve-out (mig 064, #4329) admits orphan-org cleanup from anonymise_organization_membership.
- Cross-reference ADR-039 §Invariants.1 as the sister-table pattern.

4.3. Update `knowledge-base/engineering/architecture/decisions/ADR-039-departed-member-removal-ledger.md` §Invariants.1: replace the parenthetical "Pre-existing parallel: `workspace_member_attestations.workspace_id` (058:43) keeps its `ON DELETE RESTRICT` FK shape; that's the sister-table defect tracked as a separate pre-existing-unrelated finding against `main`." with "Sister-table parallel: `workspace_member_attestations.workspace_id` resolved in mig 064 (#4329); both tables now share the workspace_id NOT NULL → NULL admissible carve-out per ADR-038 §Invariants and this ADR §Invariants.1."

4.4. Update `knowledge-base/legal/article-30-register.md` PA-2 + PA-19 entries:
- PA-2 "Workspace co-member data category" (line 67): append "Attestations.workspace_id FK is `ON DELETE SET NULL` (mig 064, #4329) — admits the orphan-org cleanup in anonymise_organization_membership; mirrors PA-19's workspace_id carve-out per ADR-038 §Invariants + ADR-039 §Invariants.1."
- PA-19 (c) categories (line 352): change "the sister-table `workspace_member_attestations.workspace_id` at 058:43 keeps its pre-existing RESTRICT shape, tracked separately" → "the sister-table `workspace_member_attestations.workspace_id` was resolved in mig 064 (#4329); both tables now share the workspace_id `ON DELETE SET NULL` + WORM-trigger NOT NULL → NULL admissible carve-out per ADR-038 §Invariants and ADR-039 §Invariants.1".

4.5. Update `knowledge-base/legal/compliance-posture.md` row for #4329: change "Sister-table defect on 058 (workspace_member_attestations.workspace_id RESTRICT) filed at #4329 (pre-existing-unrelated; CONCUR'd by reviewer)" → "Sister-table defect on 058 closed via PR #<TBD> mig 064 (#4329); 058 + 062 now share the workspace_id carve-out shape."

### Phase 5 — Verification (all ACs)

5.1. Run each AC verification command from §Acceptance Criteria. Capture output.

5.2. Run the full lint suite for migrations:
```bash
cd apps/web-platform && bun x vitest run test/supabase-migrations/
```

5.3. Run the schema-probe gate:
```bash
bash apps/web-platform/scripts/run-migrations-schema-probe.test.sh
```

5.4. Type-check + build:
```bash
cd apps/web-platform && bun x tsc --noEmit
```

### Phase 6 — PR open + multi-agent review

6.1. Push branch. Open PR with title `fix(supabase): mig 064 058-attestations workspace_id RESTRICT → SET NULL (Art. 17 erasure unblock, #4329)`.

6.2. PR body MUST include:
- Cross-reference to PR #4294 as the sister-table pattern this mirrors.
- Cross-reference to #4284 as the gated-on follow-through.
- `Closes #4329`
- "Brand-survival threshold: single-user-incident — `user-impact-reviewer` MUST run."

6.3. Spawn multi-agent review (5-agent panel per `wg-when-an-audit-identifies-pre-existing`-class fixes at single-user-incident threshold):
- `data-integrity-guardian` (FK shape, WORM trigger correctness)
- `user-impact-reviewer` (Art. 17 erasure end-to-end coverage)
- `code-simplicity-reviewer` (no over-engineering; the ALTER is the simple form)
- `architecture-strategist` (carve-out parity vs. 062; ADR-038/039 alignment)
- `git-history-analyzer` (citation correctness for #4294, #4230, ADR-038/039)

6.4. Fix-inline on every P0/P1 finding. Re-run AC commands after each fix.

### Phase 7 — Merge + post-merge verify

7.1. `gh pr merge --auto --squash` after CI green.

7.2. Wait for `web-platform-release.yml#migrate` to complete on main. Verify success via:
```bash
gh run list --workflow=web-platform-release.yml --branch=main --limit=1 --json status,conclusion
```

7.3. Run prd-state probe via Supabase MCP (AC16). If either query returns the wrong shape, open a high-priority incident issue and notify operator. Issue close gates on AC16 PASS.

7.4. `gh issue close 4329` with a verification comment summarising AC16 PASS state.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO)

### Engineering / Data Integrity (CTO surface)

**Status:** reviewed (carry-forward from PR #4294 review panel; sister-defect was explicitly named at that time as CONCUR'd by code-simplicity-reviewer)
**Assessment:** The mirror-062 approach is the architecturally minimal change. Risk surface is bounded to:
- The constraint name `workspace_member_attestations_workspace_id_fkey` matching Postgres-default convention — mitigated by `DROP CONSTRAINT IF EXISTS` + Phase 0.4 preflight DO-block.
- The trigger function rewrite correctly admitting workspace_id NOT NULL → NULL on every ON DELETE SET NULL cascade — mitigated by AC11 carve-out parity test against the proven 062 pattern.
- Existing attestation rows in dev/prd retaining their populated workspace_id — fully backward-compatible because the ALTER only widens the admissible state-space; existing rows stay valid.

### Legal / Compliance (CLO surface)

**Status:** reviewed (CLO sign-off via brainstorm-domain carry-forward from the PR #4294 multi-agent review where the sister-table defect was explicitly named)
**Assessment:** Art. 17 erasure is currently broken for the dormant flag-OFF window. Fix is required before #4284 flag-flip. The WORM contract (audit-lineage immutability for `id` + `accepted_at`) is preserved post-fix; only the workspace_id transition is widened. PA-2 + PA-19 register entries updated to reflect the carve-out. ADR-038 §Invariants documents the contract for future readers. No new lawful-basis required (existing Art. 6(1)(a) + 6(1)(c) basis unchanged).

### Product / UX Gate

**Tier:** none (NO new user-facing UI; this is a SQL/cascade fix invisible to the user)
**Decision:** auto-accepted (no UI surface)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

No new pages, components, or modals. The user-visible effect is that account-delete now succeeds where it previously silently failed — pure correctness fix. spec-flow-analyzer skipped (no UI flows changed).

### CPO sign-off (single-user-incident threshold)

`requires_cpo_signoff: true` in YAML frontmatter. The brand-survival framing was established at PR #4294 brainstorm time and inherited here. CPO must ack the plan as written before /work begins; ack is recorded in the PR body via `cpo-signoff: 2026-05-22` line at PR-open time.

## GDPR / Compliance Gate

[skill-enforced: gdpr-gate at plan Phase 2.7]

Trigger: this plan edits `apps/web-platform/supabase/migrations/064_*.sql` (a regulated-data surface per `hr-gdpr-gate-on-regulated-data-surfaces`) AND the brand-survival threshold is `single-user-incident`.

**gdpr-gate findings (advisory; verify against current `compliance-posture.md` before treating as authoritative):**

- **AP-04 (Art. 17 right to erasure).** This PR is the FIX for an existing Art. 17 violation, not a new processing activity. No new gap created; gap closed.
- **AP-05 (Art. 5(1)(d) accuracy).** Removing the workspace_id NOT NULL constraint is admissible because the workspace_id NULL state is itself a faithful representation of "the workspace this attestation referenced no longer exists" — same semantics as 062's workspace_id NULL state.
- **AP-06 (Art. 5(1)(e) storage limitation).** Unchanged — attestations remain indefinite-retention WORM (no retention sweep on this table by design; the lineage value justifies indefinite hold).
- **T-04 (sub-processor disclosure).** Unchanged (no new sub-processor).
- **DL-02 (Article 30 register).** PA-2 + PA-19 updates in §Files to Edit close the disclosure axis.
- **TS-03 (technical safeguard documentation).** ADR-038 §Invariants addition closes the documentation axis.

No new critical findings. No new `compliance-posture.md` Active Item required beyond updating the existing #4329 row to closed.

## Infrastructure (IaC)

Not applicable. This plan touches ONLY application-layer SQL migrations + TS + docs. No new infrastructure, no new vendor, no new secret, no new persistent runtime process, no Terraform changes. Skipped per Phase 2.8 trigger-set absence.

## Observability

Not applicable for the migration itself (DB-shape change with no runtime emit surface). The runtime path that consumes the change is `apps/web-platform/server/account-delete.ts` step 3.92 — which is ALREADY instrumented (existing `log.error` mirror + Sentry capture on every cascade-step failure, present from PR #4225). The fix changes the failure surface from "cascade aborts at 3.92" to "cascade succeeds"; existing observability covers both states. No new instrumentation required.

```yaml
liveness_signal:    existing — account-delete success rate visible via existing log line `user-deletion-success {userId}` at account-delete.ts:end / cadence per-request / alert_target Sentry route-error / configured_in apps/web-platform/server/account-delete.ts
error_reporting:    existing — every cascade-step throws → log.error + return { success: false }; UI surfaces generic error / fail_loud yes
failure_modes:
  - {mode: "FK constraint mismatch on prd (constraint named differently)", detection: "AC16 prd-state probe returns confdeltype != 'n'", alert_route: "post-merge verification step Phase 7.3"}
  - {mode: "WORM trigger rejects orphan-org cleanup UPDATE", detection: "anonymise_organization_membership P0001 in server logs", alert_route: "existing Sentry capture on cascade-step throw"}
discoverability_test:
  command: "mcp__plugin_supabase_supabase__execute_sql --project prd --query \"SELECT confdeltype FROM pg_constraint WHERE conname = 'workspace_member_attestations_workspace_id_fkey'\""
  expected_output: "confdeltype = 'n' (SET NULL)"
logs:               existing — account-delete pino stream, retained per existing PA-8 envelope (24mo)
retention:          existing PA-8 envelope (no change)
```

No SSH required for verification — Supabase MCP server provides direct SQL probe; `gh run list` provides workflow-run status. Both fully automatable.

## Test Strategy

Test runner: `vitest` (confirmed via `apps/web-platform/package.json` script `"test": "vitest"`; runs as `bun x vitest run <path>` in CI per existing pattern). No new test framework.

Test files:
- **New:** `apps/web-platform/test/supabase-migrations/064-fix-058-attestations-workspace-id-set-null.test.ts` — mirror of `062-workspace-member-removals.test.ts` (1:1 layout). Offline SQL-text lint; no live DB required.

Existing tests touched (regression):
- `apps/web-platform/test/supabase-migrations/062-workspace-member-removals.test.ts` — no edits; re-run for parity.
- `apps/web-platform/test/dsar-allowlist-completeness.test.ts` — no edits; re-run for regression.
- `apps/web-platform/test/server/account-delete.test.ts` — no edits expected (cascade ordering preserved, only comments changed).

Integration test path: `apps/web-platform/scripts/run-migrations.sh` + `apps/web-platform/scripts/run-migrations-schema-probe.test.sh` validate that 064 applies cleanly atop dev's existing schema. CI runs these on every PR push.

Live behavioural verification (post-merge): AC16 prd-state probe via Supabase MCP confirms the FK shape + NULL-ability. No CAPTCHA, no interactive OAuth — fully automated.

## Risks

- **Constraint name divergence on prd.** Mitigated by `DROP CONSTRAINT IF EXISTS` + Phase 0.4 preflight DO-block that raises a self-describing P0001 if the constraint is absent. If divergent name detected post-merge, hotfix migration 065 manually renames + retries — but the default-name precedent across 058 + 062 makes this very unlikely.
- **An attestation row created between PR-merge and migration-apply on prd referencing a since-deleted workspace.** Cannot happen because the FK is enforced both before and after the ALTER; the only state widening is the cascade behaviour, not the insert-time invariant.
- **An existing row with workspace_id IS NULL.** Cannot exist pre-migration because the column is currently NOT NULL. Post-migration, only orphan-org cleanup creates such rows; the down-migration's 0-row guard handles this with a loud rejection.
- **Sister-table 063 (`workspace_member_actions`) HAS the same defect class — CONFIRMED at deepen time.** `apps/web-platform/supabase/migrations/063_workspace_member_actions.sql:51`:
  ```sql
  workspace_id    uuid         NOT NULL REFERENCES public.workspaces(id) ON DELETE RESTRICT,
  ```
  When account-delete step 3.92 issues `DELETE FROM public.workspaces`, 063 audit rows pointing at those workspaces ALSO block it — same failure mode as 058. Per the deepen-added Phase 0.0 decision gate, THIS PR scopes to 058 only; **file follow-up issue #4329-A at /work Phase 0** for the 063 fix (migration 065) with explicit gate-on-#4284 linkage. The 063 fix shape DIFFERS from 064 — see Phase 0.0 rationale.
- **063 trigger is pure-reject not structural-shape.** The 063 trigger at `063:116-124` raises on ALL UPDATE/DELETE; bypass is `SET LOCAL session_replication_role='replica'` (session-replication-role disables ALL triggers, including pure-reject ones). At deepen-time, **unverified whether implicit FK cascade UPDATE (from ON DELETE SET NULL) routes through the trigger or bypasses it.** This needs verification at #4329-A plan time — if cascade UPDATEs DO route through the trigger, 063 needs either a structural-shape rewrite OR a trigger DISABLE around the cascade-fire window OR a different mitigation. This unknown is the load-bearing reason to split, not fold.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan declares `single-user incident` explicitly and is non-empty.
- **The constraint-rename ALTER form (`DROP CONSTRAINT … ADD CONSTRAINT …`) must run as a single ALTER TABLE batch.** Splitting into two statements creates a window where the table has no FK on workspace_id. Postgres allows multi-clause ALTER TABLE; use the comma-separated form per the AC2 grep pattern.
- **Sister-table 063 audit before /work.** Phase 0.5 (RED test) MUST include a grep against 063 to determine whether the same defect class applies; do NOT silently widen scope of this PR if it does — file follow-up issue per the single-concern PR rule.
- **Down-migration 0-row guard target predicate.** `WHERE workspace_id IS NULL` not `count(*) > 0` — attestations is expected to have rows; the guard targets the specific class that breaks `SET NOT NULL`.
- **Plan-time PA-vs-PA citation.** PA-2's co-member note + PA-19 (workspace_member_removals) BOTH need updates; PA-18 in the register is `template_authorizations`, NOT attestations. Verified at plan time via `grep -nE "^## (Processing Activity)" knowledge-base/legal/article-30-register.md`.
- **Sister-table 063 follow-up gating (deepen-added).** #4329-A must be filed BEFORE THIS PR merges, with explicit `blocks: 4284` linkage. Without it, the flag-flip follow-through (#4284) could fire on a half-fixed substrate where 058 is correct but 063 still raises RESTRICT on orphan-org DELETE. Recommendation: at /work Phase 0, create #4329-A as the first action after CWD verification.
- **063 trigger admit-arm unknown (deepen-added).** It is currently unverified whether Postgres ON DELETE SET NULL implicit UPDATE routes through BEFORE UPDATE triggers (which would hit 063's pure-reject). #4329-A plan time must verify empirically — `psql` test: `CREATE TEMP TABLE parent (id int PRIMARY KEY); CREATE TEMP TABLE child (parent_id int REFERENCES parent ON DELETE SET NULL); CREATE TRIGGER ... BEFORE UPDATE ON child ... RAISE; INSERT both; DELETE FROM parent`. If trigger fires, 063 needs structural rewrite, not just FK demotion. If trigger does NOT fire, 063's fix is FK-only.

## References

- `apps/web-platform/supabase/migrations/058_workspace_member_attestations.sql:43, 72-141, 419-468` — defect site + trigger to rewrite + orphan-cleanup branch this fix unblocks.
- `apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql:140-212` — canonical structural-shape WORM-trigger pattern this mirrors.
- `apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.down.sql:11-32` — 0-row guard pattern this mirrors.
- `apps/web-platform/test/supabase-migrations/062-workspace-member-removals.test.ts` — canonical lint-test pattern this mirrors.
- `apps/web-platform/server/account-delete.ts:369-510` — cascade step 3.90 → 3.93 + comments to update.
- `knowledge-base/engineering/architecture/decisions/ADR-038-team-workspace-multi-user-organizations-and-workspace-members.md` — receives §Invariants addition.
- `knowledge-base/engineering/architecture/decisions/ADR-039-departed-member-removal-ledger.md:71-76` — §Invariants.1 receives cross-reference update.
- `knowledge-base/legal/article-30-register.md:67, 350-358` — PA-2 co-member note + PA-19 cross-reference receive updates.
- `knowledge-base/legal/compliance-posture.md:97-area` — Active Item for #4329 receives close note.
- `knowledge-base/project/learnings/2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md` — pg_cron-runs-as-postgres learning informing trigger pattern.
- `knowledge-base/project/learnings/2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md` — no-current_user-gate learning informing trigger pattern.
- `knowledge-base/project/learnings/2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md` — no-RLS-insert-policy learning informing REVOKE preservation.
- Issue #4329 — this issue (deferred-scope-out filed during PR #4294 review with explicit re-evaluation trigger fired now).
- PR #4294 — sister-table fix that established the pattern + filed this defect as pre-existing-unrelated.
- #4284 — `FLAG_TEAM_WORKSPACE_INVITE=1` follow-through, gated on this issue closing.
- #4229 — team-workspace umbrella.
