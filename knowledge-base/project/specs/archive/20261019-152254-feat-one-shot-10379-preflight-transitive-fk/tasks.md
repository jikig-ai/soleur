# Tasks: extend preflight-worm-cascade-contradiction gate to transitive (non-users) FK chains

Plan: `knowledge-base/project/plans/2026-10-15-fix-preflight-transitive-fk-plan.md`
Branch: `feat-one-shot-10379-preflight-transitive-fk`. Draft PR: #10417. Issue: #10379 (Closes).
RED edits are local only; every pushed commit is green. Stop at PR ready — no merge, no workflow dispatch; ask the operator for merge approval.

## Phase 0: Rulings and baselines (read-only)

- 0.1 Land the pending `soleur:engineering:cto` rulings from decision-challenges.md (cone-refuse severity; all-tables scan scope; `confdeltype='d'` grouping). Record verdicts in the Ruling column before implementing.
- 0.2 Green-baseline `bash apps/web-platform/scripts/preflight-worm-cascade-contradiction.test.sh` on this worktree; record pass/fail count.
- 0.3 Confirm the audit census on the LIVE dev schema is unchanged since issuecomment-6193176714: read-only `psql` query listing all FKs on the 18 WORM-gated tables (`*_no_mutate` trigger carriers) with confrelid + confdeltype. Assert the dormant set is exactly {`dsar_export_audit_pii.job_id→dsar_export_jobs`, `action_sends.grant_id→scope_grants`} plus RESTRICT shapes on email_triage_items/template_authorizations. Any NEW row → stop and re-triage.

## Phase 1: Gate extension (RED then GREEN) [commit 1]

- 1.1 RED: extend `preflight-worm-cascade-contradiction.test.sh` — new `MOCK_ROWS` schema (`class|tbl|trg|fn|fk|action|level|timing|parent`), new mutation rows per plan §Test Scenarios #1–8, existing 6 tests re-pinned to the new schema. Run suite; new rows must fail against the unmodified gate (row-schema mismatch proves the gate still parses the old shape — a vacuous-pass guard).
- 1.2 Extend `preflight-worm-cascade-contradiction.sh`:
  - Add `WITH RECURSIVE del` CTE (roots `auth.users`,`public.users`; propagate `confdeltype='c'` only; `UNION` dedup terminates FK cycles — say so in the comment).
  - Widen census: all FKs (`contype='f'`) on tables carrying a raising UPDATE/DELETE trigger; emit `class` ∈ {`cone-refuse`, `cone-write-stmt`, `cone-write-row`, `dormant`} + `parent_table`; do NOT emit `confrelid ∈ {public.users, auth.users}` with `confdeltype ∈ ('r','a')` (sanctioned pre-anonymise shape).
  - Group `'d'` (SET DEFAULT) with the write-firing actions; fix the stale comment at lines 108–109.
  - Bash disposition: `cone-refuse`/`cone-write-stmt` + `owned_by_ref` → `::error::` + exit 1; not owned → leave-behind `::warning::`. `cone-write-row` and `dormant` → `::warning::` (dormant lines must name the parent and say "file a tracking issue").
  - Update header: new envelope description; close out limitation (b) at lines 62–65 (`auth.users` now in-cone); document the four classes + the silent `user-anchor` carve.
- 1.3 GREEN: run the fixture suite until all rows pass; run `bash -n` / shellcheck-equivalent lint used by repo hooks (lefthook).

## Phase 2: Live verification + ride-alongs [commit 1 or 2]

- 2.1 Read-only run of the extended query against dev (`doppler run -p soleur -c dev_scheduled`): assert `dormant` rows == the audited set from 0.3, `cone-write-row` includes `action_sends.message_id→messages` + `dsar_export_audit_pii.user_id→auth.users` residue, and ZERO `cone-refuse`/`cone-write-stmt` rows. Cite the raw output in the PR body.
- 2.2 File tracking issues for the two dormant anchors (`dsar_export_audit_pii.job_id` SET NULL non-carved; `action_sends.grant_id` NO ACTION) + the all-tables cone-scan follow-up if the CTO ruling keeps WORM-only scope. Link them in the warning text emitted by the gate and in the PR body.
- 2.3 Ride-along (drop if contested): `account-delete.ts:411` comment fix `RESTRICT` → `NO ACTION` for `action_sends.grant_id`.
- 2.4 CODEOWNERS pin for the gate script + test — only if the `operator (scope)` ruling says yes.

## Phase 3: Docs and PR

- 3.1 Update the gate's run-comment references if the workflow step comments mention "FK to public.users" (`tenant-integration.yml` ~:654 comment says "FK to public.users" — one-line wording fix, no logic change).
- 3.2 PR body: `## Changelog` section (semver:patch — bug-fix class), `Closes #10379`, raw dev-census output from 2.1, link the filed tracking issues.
- 3.3 Tick session-state.md Progress; emit resume prompt.
