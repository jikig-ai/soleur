---
title: Fix auth.users delete-cascade CI failure — revert dev-Supabase orphan-migration drift + block recurrence
type: fix
date: 2026-06-15
issue: 5372
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# Fix auth.users delete-cascade CI failure (#5372) — dev-Supabase orphan-migration drift

## Enhancement Summary

**Deepened on:** 2026-06-15
**Root cause established by live reproduction against dev-Supabase** (not hypothesis): orphan unmerged
migration `104_routine_runs.sql` (from open WIP PR #5342) applied to dev, whose WORM `no_update` trigger
contradicts its `ON DELETE SET NULL` FK, aborts every `auth.users` delete with `P0001`.

### Key Improvements (deepen pass)
1. Confirmed the drift probe is warning-only today (the hole) and pinned the fix to `push:main`-only
   blocking (warning on PR) so legitimate in-flight migration PRs don't red-flag themselves.
2. Confirmed the revert script is novel (no `_schema_migrations`-delete precedent) → modeled on
   `run-migrations.sh` `run_sql`/supabase-js path; flagged for reviewer scrutiny.
3. Verified `denied_jti.founder_id ON DELETE RESTRICT` is the one real main-side Art-17 fold-in.

### New Considerations Discovered
- The premise in the one-shot ARGUMENTS ("bisect merged migrations", "missing ON DELETE", "ship a fix
  migration") was materially wrong; corrected in Research Reconciliation.
- This is a recurrence of #4241 (prior learning 2026-05-21); the warning-only severity + absent cleanup
  step are why it recurred.

# (plan body follows)

The `Tenant integration (dev-Supabase)` workflow has been deterministically red on `main`
since ~15:31 UTC on 2026-06-15. Every test that tears down a tenant user fails because the
GoTrue admin `deleteUser` returns `status=500 code=unexpected_failure` after exhausting all 5
`withGoTrueRetry` attempts ("Database error deleting user"). This is the GDPR Art-17 account-
delete / DSAR cascade.

**Root cause (reproduced locally against dev, evidence-grounded — NOT the one-shot's stated
hypothesis):** the failure is **dev-Supabase schema-vs-ledger DRIFT**, not a code bug on `main`.
An **unmerged** migration `104_routine_runs.sql` (from open WIP PR #5342 `feat-routines-management`,
commit `4c7f6691c`) was applied to dev at **2026-06-15 14:02 UTC** via `ALLOW_UNMERGED_DEV_APPLY=1`
and never reverted. It created an **empty** table `public.routine_runs` carrying:
- `actor_id` / `delegating_principal uuid REFERENCES public.users(id) ON DELETE SET NULL`, and
- WORM triggers `routine_runs_no_update` / `routine_runs_no_delete` (fn `routine_runs_no_mutate`,
  raises `P0001`, with **no `app.worm_bypass` GUC carve-out for the cascade path**).

These two facts are mutually contradictory: the FK is `ON DELETE SET NULL` (a `users` delete
cascades an **UPDATE** that nulls the columns), but the WORM `no_update` trigger **forbids UPDATE**.
So *every* `auth.users` delete that cascades through `public.users → routine_runs.actor_id`
trips `P0001: routine_runs is append-only (WORM)`, which aborts `auth.admin.deleteUser` and
surfaces as the GoTrue `500 unexpected_failure`. The table being **empty** is irrelevant — the
FK cascade path is evaluated regardless of row count, so *all* users (including brand-new
minimal ones) are un-deletable on dev.

The merged `104_outbound_email.sql` (#5326, 15:10 UTC) and the session-resume commit
`4209e11f8` (#5350, 15:31 UTC) cited in the issue are **red herrings** — coincidental timing.
`main`'s migrations and `account-delete.ts` cascade are internally consistent.

## Verified reproduction (the load-bearing evidence)

All against `cd apps/web-platform && doppler run -p soleur -c dev`:

1. `auth.admin.deleteUser(uid)` on a **brand-new minimal user** → `AuthApiError status=500
   code=unexpected_failure` (GoTrue wrapper hides the SQLSTATE).
2. Running all 20 cascade anonymise RPCs in order (as `account-delete.ts` does), then
   `DELETE FROM public.users WHERE id=uid` → **`P0001: routine_runs is append-only (WORM)`**.
3. Dev `_schema_migrations` ledger shows `104_routine_runs.sql` (applied 14:02 UTC) and
   `105_turn_summary_message_kind.sql` (18:09 UTC) — **neither exists in `main`'s migrations dir.**
4. The repro test (`account-delete.cascade.integration.test.ts`) fails 3/3 locally with the
   anchor error `Account deletion failed at auth-delete`.

## User-Brand Impact

- **If this lands broken, the user experiences:** an Art-17 erasure / DSAR account-deletion
  request silently fails ("Account deletion failed at auth-delete. Please try again."), leaving
  the user with a live auth record they explicitly asked to be erased. If the same orphan-
  migration drift class ever reaches the prod-apply path, right-to-erasure breaks for **every**
  prod user — a statutory (GDPR Art. 17) violation, not a UX glitch.
- **If this leaks, the user's data is exposed via:** retained `auth.users` + `public.users`
  rows (email, identity) and all FK-children that should have been cascaded/anonymised, persisting
  past a confirmed erasure request — exactly the data the DSAR cascade exists to remove.
- **Brand-survival threshold:** `single-user incident`

> CPO sign-off required at plan time before `/work` begins. Confirm CPO has reviewed (or invoke
> CPO domain leader). `user-impact-reviewer` runs at review-time (review/SKILL.md conditional-agent block).

## Research Reconciliation — Spec vs. Codebase

| Premise (from one-shot ARGUMENTS / issue #5372) | Reality (reproduced) | Plan response |
|---|---|---|
| "A migration applied to dev around 15:31; bisect migrations merged just before `4209e11f8`." | The culprit migration was **never merged** — it's on open WIP PR #5342. Bisecting *merged* migrations would never find it. | Don't bisect main. Revert the dev orphan; harden the apply/drift gate; fix the bug in PR #5342. |
| "Likely a broken trigger or an FK to auth.users **without ON DELETE handling**." | The FK *has* ON DELETE handling (`SET NULL`). The bug is a **WORM `no_update` trigger contradicting `ON DELETE SET NULL`** — the cascade's nulling UPDATE is forbidden. | Fix is WORM-bypass-aware (or FK-rule) in PR #5342, not "add ON DELETE". |
| "Ship a fix migration plus a regression gate." | `main`'s schema is correct; a fix migration **on main** would be wrong (no main-side defect to migrate). | Remedy = (a) revert dev drift, (b) make the drift gate BLOCKING, (c) regression test that asserts a minimal-user delete succeeds on dev. |
| Issue body: "mig 065/066 founder_id assertions fail" as a candidate independent cause. | Those founder_id assertions are **downstream symptoms** of the same auth-delete abort (the cascade never reaches them). | One root cause; no separate mig-065/066 fix needed. |
| `104_outbound_email.sql` (#5326) is the suspect migration. | **Sound.** Both anonymise RPCs null the only RESTRICT FK col; WORM bypass uses the privilege-free `app.worm_bypass` GUC (post-087 pattern); `account-delete.ts` steps 3.98/3.99 wire both. | No change to 104 or its cascade steps. |
| (Not in premise) — latent gap. | `denied_jti.founder_id` (mig 037:124) is `REFERENCES users(id) ON DELETE RESTRICT` with **no anonymise step** in `account-delete.ts` and no downgrade. Not exercised by the 3 failing tests (no `denied_jti` rows seeded), so **not** the #5372 cause, but a real Art-17 cascade gap. | Fold-in (small) — see Phase 4. |

## Open Code-Review Overlap

2 open `code-review` issues touch files this plan modifies:
- **#3370** (Dev Supabase `_schema_migrations` tracking-table drift: 034/035 applied untracked, 036 unapplied untracked) — touches `run-migrations.sh`. **Acknowledge:** same *drift family* but a distinct symptom (tracking-table desync vs orphan-migration pollution). This plan's BLOCKING drift gate + dev-revert procedure reduces but does not fully close #3370's untracked-apply concern; leave it open and add a re-eval note linking #5372.
- **#3364** (add postgres-role ownership guard to `run-migrations.sh`, PR #3355 follow-up) — touches `run-migrations.sh`. **Defer:** orthogonal concern (role ownership, not drift severity). Do not fold in; the drift-gate edit is line-disjoint. Add a note that #5372's `run-migrations.sh` edit landed nearby.

## Observability

```yaml
liveness_signal:
  what: "Tenant integration (dev-Supabase) GitHub Actions workflow (.github/workflows/tenant-integration.yml) — the account-delete cascade integration suite is the canary for Art-17 deletability on dev"
  cadence: "per push to main touching server/** or supabase/migrations/**, plus per matching PR"
  alert_target: "ci/main-broken issue label + the workflow's required-check status on the run"
  configured_in: ".github/workflows/tenant-integration.yml:229 (Run tenant-isolation tests step)"
error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN — account-delete.ts already mirrors every cascade-step failure via reportSilentFallback/warnSilentFallback (op: account-delete/*)"
  fail_loud: "GoTrue deleteUser 500 surfaces as withGoTrueRetry log lines (attempt N/5 code=unexpected_failure) and reportSilentFallback op=auth-delete to Sentry; the new BLOCKING drift gate emits ::error:: + non-zero exit in CI"
failure_modes:
  - mode: "Orphan unmerged migration applied to dev (this incident's class)"
    detection: "BLOCKING dev-migration-drift gate (this plan) — fails the workflow when _schema_migrations has a row whose file is absent from origin/main"
    alert_route: "CI red on tenant-integration + scheduled-dev-migration-drift.yml; ci/main-broken triage"
  - mode: "auth.admin.deleteUser 500 on dev (Art-17 cascade abort)"
    detection: "account-delete cascade integration regression test (this plan) asserts a minimal-user deleteAccount returns success=true"
    alert_route: "tenant-integration workflow failure"
  - mode: "WORM-trigger-vs-cascade contradiction in a future WORM table"
    detection: "the regression test exercises a full minimal-user delete end-to-end, catching any WORM/FK contradiction on the live dev schema"
    alert_route: "tenant-integration workflow failure"
logs:
  where: "GitHub Actions run logs for tenant-integration.yml; Sentry web-platform issues (op=account-delete/*); dev Postgres logs via Supabase dashboard (last resort, not in runbook path)"
  retention: "GH Actions logs 90d default; Sentry per project retention"
discoverability_test:
  command: "cd apps/web-platform && doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run test/server/account-delete.cascade.integration.test.ts"
  expected_output: "Test Files 1 passed (1); Tests 3 passed (3) — deleteAccount(soloUser) returns success=true and CASCADE clears auth+public.users"
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Dev drift reverted (the actual fix).** The orphan `public.routine_runs` table (and its
      triggers `routine_runs_no_update`/`routine_runs_no_delete`, fn `routine_runs_no_mutate`, the
      `write_routine_run` RPC if present, and any `routine_runs`-related grants/indexes) is dropped
      from the **dev** Supabase project, and the `104_routine_runs.sql` + `105_turn_summary_message_kind.sql`
      rows are removed from dev `public._schema_migrations`. Verified by the discoverability_test passing
      AND by re-querying the dev ledger showing no row whose file is absent from `origin/main`. Reversion
      runs via an **idempotent, automatable** procedure (a checked-in revert script invoked through Doppler,
      or — preferred — the BLOCKING gate's auto-surface + a one-call MCP/`run-migrations`-style revert),
      NOT a hand-typed dashboard SQL session. (Drop only the empty orphan; do NOT touch any table that
      exists on `origin/main`.)
- [ ] **AC2 — Repro test green on dev.** `account-delete.cascade.integration.test.ts` passes 3/3 when run
      against dev after AC1 (the exact one-shot repro command). Captured in the PR body.
- [ ] **AC3 — Drift gate is BLOCKING, not warning-only.** `.github/actions/dev-migration-drift-probe/action.yml`
      (or a wrapping step in `tenant-integration.yml`) emits `::error::` and exits non-zero when
      `_schema_migrations` contains a row whose migration file is absent from `origin/main` — closing the
      hole that let this incident normalize red for ~4h. Severity change is justified in the action header
      comment (supersedes the 2026-05-21 "warning-by-design" decision with the recurrence evidence). The
      blocking gate runs **before** the test step so a poisoned schema fails fast with a named relation,
      not an opaque GoTrue 500.
- [ ] **AC4 — Regression gate (minimal-user delete).** A new/extended integration assertion proves a
      **brand-new minimal user** (only `handle_new_user` auto-provisioned rows) is fully deletable via
      `deleteAccount` end-to-end on dev — the cheapest invariant that would have caught this incident at
      the source. It must assert `result.success === true` AND the `auth.users` + `public.users` rows are
      gone. (Most likely already covered by `account-delete.cascade.integration.test.ts`'s
      `deleteAccount(soloUser)` case — confirm via `git grep`; only add a case if the minimal-user path
      is not already asserted.)
- [ ] **AC5 — `denied_jti.founder_id` Art-17 fold-in.** `account-delete.ts` gains an anonymise step for
      `denied_jti.founder_id` (mig 037:124, `ON DELETE RESTRICT`, currently un-handled), OR the FK is
      downgraded to `SET NULL` via a forward migration on `main`, so any user with a `denied_jti` row is
      deletable. Choice + rationale recorded; a deterministic test seeds a `denied_jti` row and asserts
      the cascade succeeds. (This IS a `main`-side change — the only one — and is genuinely required for
      Art-17 completeness, distinct from the dev-drift root cause.)
- [ ] **AC6 — PR body uses `Ref #5372`, not `Closes #5372`** if any acceptance step (AC1 dev-revert) is
      executed post-merge; the issue is closed by a post-merge step after the revert is verified. If AC1
      is fully automatable pre-merge (revert script + dev verify in CI), `Closes #5372` is acceptable.
- [ ] **AC7 — Typecheck.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.

### Post-merge (operator) — only if AC1 cannot run in CI pre-merge

- [ ] **AC8 — Dev revert applied + verified** via the checked-in revert script (`doppler run -p soleur -c dev`),
      then `gh issue close 5372` after the discoverability_test passes. `Automation:` the revert is a single
      idempotent SQL script invoked through Doppler — fully automatable; this subsection exists only if the
      pipeline cannot reach dev at merge time.

## Implementation Phases

> Phase order is load-bearing: revert dev (unblock CI) → make the gate blocking (prevent re-normalization)
> → regression test (lock the invariant) → main-side `denied_jti` fold-in (Art-17 completeness).

### Phase 1 — Revert the dev orphan drift (the unblock)
- Author an idempotent revert script at `apps/web-platform/scripts/` (mirror the `run-migrations.sh`
  Doppler/`DATABASE_URL` invocation convention; reuse the supabase-js service-client pattern used by the
  repro probes since `psql` is not on the runner). It must: drop `routine_runs_no_update`/`_no_delete`
  triggers, drop fn `routine_runs_no_mutate()`, drop the `write_routine_run` RPC if present, drop table
  `public.routine_runs`, and delete the `104_routine_runs.sql` + `105_turn_summary_message_kind.sql`
  rows from `public._schema_migrations`. Guard every drop with `IF EXISTS` and a `to_regclass`/catalog
  check; refuse to run if any target object also exists on `origin/main` (defense against dropping a
  real table).
- Run it against dev; confirm the discoverability_test passes (AC1, AC2).
- **Reference the prior-art revert recipe** in `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md` for the exact ledger-row-delete + object-drop sequence.

### Phase 2 — Make the drift gate BLOCKING (prevent re-normalization)
- Edit `.github/actions/dev-migration-drift-probe/action.yml` (or wrap in `tenant-integration.yml`):
  escalate the orphan-file branch from `::warning::` to `::error::` + non-zero exit **only on the
  `push:main` path** (`github.event_name == 'push' && github.ref == 'refs/heads/main'`); keep
  `::warning::` on `pull_request` runs. This is load-bearing: the probe reads applied
  `_schema_migrations` and cross-refs `git ls-tree origin/main`, so a PR's own in-flight migration
  (applied under `ALLOW_UNMERGED_DEV_APPLY=1`) shows as orphan on its own `pull_request` run — blocking
  there would red every legitimate migration PR. Blocking on `main` matches the incident. Keep the
  `drift-detected` output. Update the header comment to cite #5372 as the recurrence that justifies
  escalation over the 2026-05-21 warning-by-design, and pass the trigger context into the action (add an
  input or read `github.*` in the wrapping step, since composite actions don't see `github.event_name`
  directly — verify the cleanest wiring at /work).
- In `tenant-integration.yml`, ensure the drift step runs **before** "Run tenant-isolation tests" (it
  already runs at L141, before tests at L229 — verify ordering survives) so a poisoned schema fails fast.
- Verify the `scheduled-dev-migration-drift.yml` cron consumer still functions with the new severity
  (it should surface the same `::error::` and fail the scheduled run loudly).

### Phase 3 — Regression test (lock the invariant)
- Confirm `account-delete.cascade.integration.test.ts` already asserts the minimal-user `deleteAccount`
  path (`deleteAccount(soloUser)` case). If yes, AC4 is satisfied by making it green; if a minimal-user-
  only assertion is missing, add one. Verify the test path matches `vitest.config.ts` `include:` globs
  (`test/**/*.test.ts`) — it already lives at `test/server/`.

### Phase 4 — `denied_jti.founder_id` Art-17 fold-in (main-side completeness)
- Decide: anonymise-RPC step in `account-delete.ts` (mirrors the existing 037/044/048 anonymise pattern;
  needs a `anonymise_denied_jti`-style SECURITY DEFINER RPC + a forward migration to add it) **vs.**
  downgrade the FK to `ON DELETE SET NULL` (forward migration; `founder_id` becomes nullable on cascade).
  Prefer the FK-downgrade if `denied_jti.founder_id` is not load-bearing for the deny-list's correctness
  (the jti index, not founder_id, is the deny key — verify via `036_*`/`068_*` deny-list migrations).
- Add the forward migration (next free integer prefix on `main`, with the `to_regclass('public.users')`
  precondition per the FK-precondition lint), wire the cascade step if RPC-based, and add a deterministic
  test seeding a `denied_jti` row.

### Phase 5 — Fix the bug at its source in PR #5342 (cross-PR follow-through)
- File a comment / required change on **PR #5342** (`feat-routines-management`): its `routine_runs`
  migration must (a) resolve the prefix-104 collision (renumber), and (b) resolve the WORM-vs-SET-NULL
  contradiction — either add an `app.worm_bypass` GUC carve-out to `routine_runs_no_mutate` (post-087
  pattern, so the `ON DELETE SET NULL` cascade's UPDATE is permitted) AND a corresponding
  `anonymise_routine_runs` step in `account-delete.ts`, OR change the FK to `ON DELETE CASCADE` with a
  WORM `no_delete` carve-out. Without this, #5342 will re-break the cascade the moment it merges.
- This is a tracking action, not code in this PR; record it as a blocking note on #5342 + a `Ref`.

## Test Scenarios

- Given a brand-new minimal user (only `handle_new_user` rows) on dev, when `deleteAccount(uid, email)`
  runs, then it returns `success: true` and both `auth.users` and `public.users` rows are gone.
- Given dev `_schema_migrations` contains a row whose file is absent from `origin/main`, when the
  tenant-integration workflow runs, then the drift step exits non-zero with an `::error::` naming the
  orphan file (BEFORE the test step).
- Given a user with a `denied_jti` row, when `deleteAccount` runs, then the cascade succeeds (Art-17
  completeness; Phase 4).
- Given PR #5342's `routine_runs` migration as written, when applied, then a minimal-user delete must
  still succeed (the carve-out / FK-rule fix is in place) — the contract #5342 must satisfy before merge.

## Research Insights (deepen-plan)

Verified live against `main` / dev during the deepen pass (all confirms):

- **Drift probe is warning-only today (confirmed).** `.github/actions/dev-migration-drift-probe/action.yml`
  header + L113-128: the orphan-file branch emits only `::warning::`, never `::error::`, never `exit 1`.
  This is the exact hole that let #5372 normalize red for ~4h. AC3's severity bump is the fix.
- **`main` has no `routine_runs` migration (confirmed).** `ls … | grep routine` and `git grep -l
  routine_runs -- …/migrations/` both empty → the orphan is dev-only; no main-side migration revert needed.
- **`denied_jti.founder_id ON DELETE RESTRICT` un-handled (confirmed).** `037_audit_byok_use.sql:124`;
  no `denied_jti`/`anonymise_denied` reference in `account-delete.ts` → AC5 fold-in is real.
- **BLOCKING-gate-on-PR risk is real and the mitigation is sound (confirmed).** The probe reads applied
  `_schema_migrations` and cross-refs `git ls-tree origin/main`, so a PR's own in-flight migration (applied
  under `ALLOW_UNMERGED_DEV_APPLY=1`) WOULD show as orphan on a `pull_request` run. The workflow runs on
  BOTH `push:main` and `pull_request` (`tenant-integration.yml:33-45`). **Decision: escalate to `::error::`
  + non-zero exit ONLY on the `push:main` path; keep `::warning::` on `pull_request`.** This matches the
  incident (the failure was on `main`) and preserves the local-iteration valve. Implement via
  `github.event_name == 'push'` (or `github.ref == 'refs/heads/main'`) condition in the action/step.
- **Revert script: no precedent; pattern is novel (confirmed).** No script under
  `apps/web-platform/scripts/` deletes from `_schema_migrations` or drops migration objects. The prior
  learning (`2026-05-21-…`) documents the manual reconcile pattern in prose but ships no script. Model the
  new revert on `run-migrations.sh`'s `run_sql`/Doppler-`DATABASE_URL` invocation convention; since `psql`
  is absent on the runner/workstation, use the supabase-js service-client SQL path (the repro probes proved
  this works). Reviewers should scrutinize the novel drop sequence — guard every drop with `IF EXISTS` +
  an `origin/main`-presence refusal.
- **Prior learning is the recurrence record (confirmed).** `2026-05-21-dev-supabase-drift-from-unmerged-
  feature-branch-migrations.md:68` states warning severity was *intentional* ("surfaces drift on every CI
  run without blocking the local-iteration valve") and ships NO automated dev-drift cleanup. #5372 is the
  recurrence that justifies (a) escalating severity on `main` and (b) adding the missing cleanup script.

## Risks & Mitigations

- **Dropping a real table by mistake (dev revert).** Mitigation: the revert script refuses to drop any
  object that also exists on `origin/main`; only the two ledger rows whose files are absent from main are
  targeted; `IF EXISTS` everywhere.
- **Drift gate becomes BLOCKING and breaks a legitimate in-flight migration PR** (the PR's own new
  migration is "not on origin/main" by definition during PR CI). Mitigation: the gate's orphan check reads
  `_schema_migrations` (applied state), not the PR diff; a PR's own in-flight file is applied under
  `ALLOW_UNMERGED_DEV_APPLY=1` and is expected to be on `origin/main` once merged — but it WILL show as
  orphan on the PR run. **This must be handled:** scope the BLOCKING error to orphans whose file is absent
  from BOTH `origin/main` AND the current PR's migration dir (i.e., truly abandoned), or only escalate to
  blocking on `push: main` runs (not `pull_request`). Decide at /work; the `pull_request`-only-warning /
  `push:main`-blocking split is the safest shape and matches the incident (the failure was on `main`).
- **PR #5342 follow-through is cross-PR** and out of this PR's merge gate. Mitigation: Phase 5 files a
  blocking note on #5342; the now-BLOCKING drift gate + minimal-user regression test will catch a
  re-occurrence at #5342's own CI.

## Domain Review

**Domains relevant:** Engineering, Legal (GDPR Art-17), Product (CPO sign-off at single-user threshold)

### Engineering (CTO)
**Status:** carried-forward from investigation
**Assessment:** Root cause is CI/infra-class dev-drift, not application logic. The fix is operationally
shaped (revert + gate severity + regression test) with one small main-side Art-17 completeness change
(`denied_jti`). Architectural concern: the drift gate's BLOCKING-on-`main` vs warning-on-PR split (Risks)
must be encoded precisely to avoid breaking legitimate in-flight migration PRs.

### Legal (GDPR Art-17)
**Status:** relevant — gdpr-gate invoked at Phase 2.7 (regulated-data surface: account-delete cascade,
migrations, auth flow). Right-to-erasure is the directly impacted statutory right. The `denied_jti` fold-in
(AC5) closes a real (if currently-unexercised) erasure gap.

### Product/UX Gate
**Tier:** none
**Decision:** N/A — no user-facing UI surface created or modified (CI/DB/infra + server-side cascade only).
No file under `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` is touched.
**Pencil available:** N/A (no UI surface)

#### Findings
CPO sign-off is required by the `single-user incident` threshold (statutory erasure), not by a UI surface.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or
  omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled (threshold:
  single-user incident).
- The repro command MUST include `-p soleur` (`doppler run -p soleur -c dev …`) — the issue's quoted
  command omits `-p` and fails with "You must specify a project" in a worktree without a default project
  scope.
- `psql` is NOT installed on the dev workstation or the GH runner — the revert script and any DB
  introspection MUST use the supabase-js service client (or PostgREST), not `psql`.
- The drift gate severity bump is BLOCKING — verify it does not red every legitimate migration-PR run
  (see Risks: scope to `push:main` or to files-absent-from-both-main-and-PR).
- Do NOT add a "fix migration" to `main` for the dev-drift root cause — `main`'s schema is correct. The
  only legitimate main-side migration here is the `denied_jti` Art-17 fold-in (Phase 4), which is a
  separate, independently-motivated change.
- `routine_runs` being EMPTY (0 rows) does not make it safe — the FK cascade path is evaluated regardless
  of row count, so the WORM-vs-SET-NULL contradiction blocks ALL deletes. Don't reason "empty table =
  harmless."
