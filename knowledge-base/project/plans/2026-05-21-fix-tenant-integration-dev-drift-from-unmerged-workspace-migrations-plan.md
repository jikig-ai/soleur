---
title: "fix(ci): tenant-integration suite broken on main by unmerged team-workspace migrations 053-056 applied to dev"
issue: 4241
branch: feat-one-shot-tenant-integration-23514-4241
type: fix
lane: cross-domain
date: 2026-05-21
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(ci): tenant-integration suite broken on main by unmerged team-workspace migrations 053-056 applied to dev

## Enhancement Summary

**Deepened on:** 2026-05-21
**Sections enhanced:** Overview / Root Cause / Phase 1 / Phase 3 / Observability / Risks
**Verification gates executed:** Phase 4.6 (User-Brand Impact — PASS, threshold `none` with explicit non-sensitive-path scope-out reason); Phase 4.7 (Observability — PASS, all 5 fields populated, `discoverability_test.command` does not invoke `ssh`); Phase 4.8 (PAT-shaped variable halt — PASS, zero matches); Phase 4.5 (Network-outage deep-dive — N/A, no SSH/handshake keywords in plan).

### Live verification artifacts (executed at deepen time)

| Claim | Verification command | Result |
|---|---|---|
| Issue #4241 exists and is OPEN | `gh issue view 4241 --json state,title` | `OPEN`, title matches plan |
| PR #4213 (PR-I) merged | `gh pr view 4213 --json state` | `MERGED` |
| PR #4226 (workspace recon) merged | `gh pr view 4226 --json state` | `MERGED` |
| Failing CI run 26225869534 exists | `gh run view 26225869534 --json conclusion,headBranch` | `failure` on `main` |
| Commit `5c2696d4` (Phase 1 forward apply) reachable | `git rev-parse 5c2696d4` | `5c2696d4c8fa979b…` |
| Commit `1a5cc259` (tasks.md dev-apply status) reachable | `git rev-parse 1a5cc259` | `1a5cc259c7d4793…` |
| Commit `2092b9b4` (PR-I merge) reachable | `git rev-parse 2092b9b4` | `2092b9b4a66a1eb…` |
| 4 down-migration files exist on `5c2696d4` | `git show 5c2696d4 --name-only \| grep '\.down\.sql$'` | 4 files: `053..056_*.down.sql` |
| `scope_grants_workspace_id_check` source absent on main | `grep -rn '<constraint>' apps/web-platform/supabase/migrations/` | 0 matches |
| Mig 053 IS on main (template_authorizations) | `git ls-tree origin/main -- apps/web-platform/supabase/migrations/053_template_authorizations.sql` | blob `f4352b63…` |
| Mig 053 (workspace_members) NOT on main | `git ls-tree origin/main -- apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql` | empty (confirms Phase 3.1 gate contract) |
| All 8 cited AGENTS.md rule IDs are ACTIVE | `for id in <ids>; do grep -qE "\[id: $id\]" AGENTS.md && echo OK \|\| echo MISSING; done` | 8/8 OK |

### Key Improvements

1. **Discoverability test bug-fix.** Replaced SQL `LIKE '05_workspace%'` (matches `058workspace…` due to `_` being a single-char wildcard) with explicit `IN (...)` enum. The plan-original LIKE form was an inert false-pass risk on a future apply that lands a mig 058 starting with `workspace`.
2. **Gate-contract pre-verification.** Confirmed `git ls-tree origin/main` returns empty for the unmerged file and a blob hash for the merged file — the Phase 3.1 gate's truth-source mechanism is verified before implementation, not after.
3. **Citation/rule-id correctness gate executed.** 8/8 rule IDs verified active; 4/4 cited commits verified reachable; 3/3 cited PR numbers verified state-correct.
4. **Down-migration glob-skip mechanism documented.** The runner's existing `case "$filename" in *.down.sql) continue ;; esac` (lines 137-138, PR-I precedent) is what makes Phase 2 safe — once the team-workspace branch lands and renumbers to 057-060, the runner will not accidentally apply the paired `.down.sql` files. No new defense needed.

### New Considerations Discovered

- **The PostgrestError `details:` field is the canonical disambiguator.** Issue #4241's body named the wrong CHECK (`scope_grants_tier_check` / `scope_grants_action_class_not_locked`) because the operator pattern-matched against the most-recently-touched constraint. The actual `message:` line of the PostgrestError already names the failing CHECK verbatim (`new row for relation "scope_grants" violates check constraint "scope_grants_workspace_id_check"`). Phase 4.2's learning file captures this triage discipline: read `error.message` BEFORE pattern-matching against recent migrations.
- **`_schema_migrations` is filename-keyed, not content-keyed.** Two `053_*.sql` files with different names coexist without runner complaint. This is the silent-collision risk highlighted in Sharp Edges; renumber-on-rebase is the team-workspace branch's responsibility, but the convention violation surfaces only at filename inspection, never at apply.
- **The gate is opt-in by design.** `ALLOW_UNMERGED_DEV_APPLY=1` is the local-iteration safety valve. Phase 3.2's runtime drift probe (warning, not error) is the always-on backstop. Together they implement the policy "fast-iterate locally is fine; leaving the drift in place is surfaced on every CI run".

## Overview

Restore the `Tenant integration (dev-Supabase)` CI workflow to green by reverting four migrations (`053_organizations_and_workspace_members`, `054_workspace_member_attestations`, `055_workspace_keyed_rls_sweep`, `056_current_organization_jwt_hook`) that were applied to dev-Supabase from an in-flight, unmerged branch (`feat-team-workspace-multi-user`, commit `5c2696d4`, 2026-05-21 10:38 UTC). On main, the matching forward migrations and grant_action_class RPC rewrite do NOT exist; dev's schema is now ahead of main and rejects every `grant_action_class` call from main's RPC body with SQLSTATE `23514`.

The fix has two parts:

1. **Mechanical:** drop the team-workspace constraint/columns/policies/tables from dev (via the down-migrations the branch already authored), and delete their `_schema_migrations` tracking rows so the runner re-applies them once the branch lands on main.
2. **Workflow gate:** codify a hard rule that dev-Supabase migrations are applied ONLY from migrations that have either (a) merged to main, or (b) have an open PR whose feature branch is the source of the apply. The team-workspace branch applied to dev with neither — the branch is still in draft and its 053-056 numbering will collide with main's existing `053_template_authorizations.sql` from PR-I (#4213).

## Root Cause

The CI symptom in issue #4241 mis-identified the failing CHECK as `scope_grants_tier_check` or `scope_grants_action_class_not_locked`. The actual failure (from a fresh `gh run view 26225869534 --log-failed`) is:

```
new row for relation "scope_grants" violates check constraint "scope_grants_workspace_id_check"
Failing row contains (…, …, finance.payment_failed, draft_one_click, …, null, null, …, null).
                                                                          ^^^^                  ^^^^
                                                                          workspace_id          NULL
```

This constraint does NOT exist in any migration on `origin/main`. It exists only in commit `5c2696d4:apps/web-platform/supabase/migrations/055_workspace_keyed_rls_sweep.sql:358-360`:

```sql
ALTER TABLE public.scope_grants
  ADD CONSTRAINT scope_grants_workspace_id_check
  CHECK ((founder_id IS NULL AND workspace_id IS NULL) OR (founder_id IS NOT NULL AND workspace_id IS NOT NULL));
```

Per `1a5cc259:knowledge-base/project/specs/feat-team-workspace-multi-user/tasks.md`, all 4 forward migrations were applied to dev via `DATABASE_URL_POOLER` on 2026-05-21 with backfill counts logged (437 orgs / 437 workspaces / 437 members / 71 scope_grants rows backfilled). The branch never merged to main; commit `1a5cc259` is on `feat-team-workspace-multi-user` only.

Main's `grant_action_class` (mig 051 §i, lines 256-295) inserts only `(founder_id, action_class, tier)` — it never references `workspace_id`. After mig 055 was applied to dev, every `grant_action_class` call from main's CI inserts a row with `workspace_id = NULL` AND `founder_id NOT NULL`, which the new CHECK rejects.

## Research Reconciliation — Spec vs. Codebase

| Spec/Issue claim | Reality | Plan response |
|---|---|---|
| Issue body identifies the failing CHECK as `scope_grants_tier_check` OR `scope_grants_action_class_not_locked`. | Failing CHECK is `scope_grants_workspace_id_check`, defined nowhere on main. | Plan addresses the actual constraint via revert of the source migration; issue body's investigation-entry-point ②/③ would have surfaced this once the operator ran the `pg_get_constraintdef` query against dev. |
| Issue body lists 4 candidate PRs landed in the 08:44-10:46 UTC window (#4227, #4209, #4207, #4218). | None of these touch `scope_grants` or migrations. The dev-side migration was applied by `git push origin feat-team-workspace-multi-user` at 10:38 UTC — invisible to a `git log origin/main` query. | Plan adds workflow-gate scope to detect "dev-applied migrations not on origin/main" so the next occurrence surfaces inside the issue triage tool, not via a manual `pg_constraint` snapshot. |
| Tasks.md on team-workspace claims "Apply status (dev): all 4 forward migrations applied … prd apply deferred". | Confirmed by `git show 1a5cc259:knowledge-base/project/specs/feat-team-workspace-multi-user/tasks.md`. dev was the sole apply target; prd is untouched. | Plan scope excludes prd. |
| Main has `053_template_authorizations.sql` (PR-I, mig 053). Team-workspace has `053_organizations_and_workspace_members.sql` (same number). | Confirmed via `ls apps/web-platform/supabase/migrations/053*`. The two `053`s have different filenames so `_schema_migrations` (filename-keyed) tracks them as distinct; the runner happens to apply both without complaint. But once team-workspace rebases onto main, the two `053_*.sql` files coexist with the same number prefix. | Out-of-scope for THIS plan (it's a team-workspace rebase concern). The plan body raises it as a sharp-edge note so the team-workspace work picks it up. |

## User-Brand Impact

**If this lands broken, the user experiences:** continued red CI on every PR that touches `apps/web-platform/server/**` or `apps/web-platform/test/server/**.tenant-isolation.test.ts`. No production user impact — prd Supabase is unaffected; CI is the only consumer of dev. The downstream impact is to engineering velocity: PRs cannot merge with confidence because the tenant-integration gate is broken.

**If this leaks, the user's data is exposed via:** N/A — no production data path involved. Dev-Supabase contains only synthetic `tenant-isolation-*@soleur.test` fixtures (per `cq-test-fixtures-synthesized-only`).

**Brand-survival threshold:** none — this is a CI-only regression on a dev-only Supabase project. Per `hr-dev-prd-distinct-supabase-projects`, dev and prd are distinct projects; the scope_grants schema drift exists only on dev. Production posture is fine (confirmed by issue body §"Workaround / Status"). Threshold scope-out reason: CI tooling failure on a dev-only schema; no operator/customer data or workflow touched.

## Hypotheses (ruled in/out)

- **H1 (ruled in):** A migration applied to dev between 08:44 and 10:46 UTC on 2026-05-21 added `scope_grants_workspace_id_check`. The migration is `055_workspace_keyed_rls_sweep.sql` on branch `feat-team-workspace-multi-user`, commit `5c2696d4`, applied via `DATABASE_URL_POOLER` per tasks.md `1a5cc259`. Evidence: error log row `workspace_id = NULL` + grep of `scope_grants_workspace_id_check` returns only this branch's mig 055.
- **H2 (ruled out):** PR #4214 (action-class titles) tightened a CHECK. Reading the diff: the PR is UI-copy-only (`lib/messages/action-class-copy.ts`, page.tsx, modal). No SQL touched. Confirmed via `git show 43d41f07 --stat -- apps/web-platform/supabase/`.
- **H3 (ruled out):** PR #4227 (TR9 PR-3 Inngest oauth-probe migrate) altered a constraint. Diff is `.github/workflows/`, `apps/web-platform/server/inngest/functions/`. No SQL touched.
- **H4 (ruled out):** PR-I (#4213) introduced the regression. PR-I's mig 053 (template_authorizations) ships unchanged. The tenant-integration run that failed at 10:46 UTC (after PR-I merge) failed for the SAME reason that the runs at 11:12 / 12:10 / 12:27 failed — `scope_grants_workspace_id_check`. PR-I's `template-authorizations-worm.test.ts` calls `grant_action_class` in its `beforeAll`; the workspace_id constraint short-circuits the test before any PR-I logic runs.

## Implementation Phases

### Phase 0 — Preconditions

- [ ] **0.1** Confirm worktree CWD is `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-tenant-integration-23514-4241` and branch is `feat-one-shot-tenant-integration-23514-4241`. Per `hr-when-in-a-worktree-never-read-from-bare`, all paths in this plan are relative to that worktree root.
- [ ] **0.2** Re-grep `apps/web-platform/supabase/migrations/` on the current branch (HEAD = main) for `scope_grants_workspace_id_check` and confirm 0 matches. Confirms the constraint has no source on main and the fix is dev-only.

  ```bash
  grep -rn "scope_grants_workspace_id_check" apps/web-platform/supabase/migrations/ 2>/dev/null | wc -l
  # Expected: 0
  ```

- [ ] **0.3** Confirm the dev Doppler config and assert `environment=dev` before any psql call (mirrors `.github/workflows/tenant-integration.yml:88-114`):

  ```bash
  env_name=$(doppler configs get dev_scheduled -p soleur --json | jq -r '.environment // empty')
  test "$env_name" = "dev" || { echo "ABORT: dev_scheduled resolves to ${env_name}, expected dev"; exit 1; }
  ```

  Per `hr-dev-prd-distinct-supabase-projects` and `hr-menu-option-ack-not-prod-write-auth`, this is a dev-only write; no prd flag flips.

- [ ] **0.4** Snapshot dev's current `pg_constraint` set for `scope_grants` so the revert is verifiable:

  ```bash
  doppler run -p soleur -c dev_scheduled -- psql "$DATABASE_URL_POOLER" -c "
    SELECT conname, pg_get_constraintdef(oid)
      FROM pg_constraint
     WHERE conrelid = 'public.scope_grants'::regclass
     ORDER BY conname;" | tee /tmp/scope_grants_before.txt
  ```

### Phase 1 — Run the down-migrations against dev (revert order: 056 → 055 → 054 → 053)

The team-workspace branch authored paired `*.down.sql` files for each forward migration. Apply them in strict reverse order so each down-migration sees the schema state its forward partner produced.

- [ ] **1.1** Read `git show 5c2696d4:apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.down.sql` (and 054/055/056 down files) in full; confirm each ends with an explicit `DROP CONSTRAINT IF EXISTS scope_grants_workspace_id_check` (in 055.down) and that 053.down drops `organizations` / `workspaces` / `workspace_members` LAST. The down-migrations are NOT on main; fetch them from the team-workspace branch via `git show 5c2696d4:<path>`.

  ```bash
  for n in 056 055 054 053; do
    git show 5c2696d4:apps/web-platform/supabase/migrations/${n}_*.down.sql \
      > /tmp/down-${n}.sql
  done
  # Inspect /tmp/down-{056,055,054,053}.sql before running.
  ```

- [ ] **1.2** Apply down-migrations to dev via `DATABASE_URL_POOLER` (session-mode :5432 — transaction mode :6543 rejects multi-statement DDL):

  ```bash
  doppler run -p soleur -c dev_scheduled -- bash -c '
    set -euo pipefail
    for n in 056 055 054 053; do
      echo "== Applying down-${n} =="
      psql "$DATABASE_URL_POOLER" -v ON_ERROR_STOP=1 -f /tmp/down-${n}.sql
    done
  '
  ```

- [ ] **1.3** Delete `_schema_migrations` rows for the four reverted migrations so `run-migrations.sh` does NOT skip them when team-workspace eventually merges to main (the runner is filename-keyed; a stale row would silently leave the schema un-applied on a fresh apply).

  ```bash
  doppler run -p soleur -c dev_scheduled -- \
    psql "$DATABASE_URL_POOLER" -v ON_ERROR_STOP=1 -c "
      DELETE FROM public._schema_migrations
       WHERE filename IN (
         '053_organizations_and_workspace_members.sql',
         '054_workspace_member_attestations.sql',
         '055_workspace_keyed_rls_sweep.sql',
         '056_current_organization_jwt_hook.sql'
       );"
  ```

- [ ] **1.4** Verify reversion: re-snapshot `pg_constraint` for `scope_grants` and `diff` against `/tmp/scope_grants_before.txt`. The only delta MUST be `scope_grants_workspace_id_check` removed. `organizations`, `workspaces`, `workspace_members`, `workspace_member_attestations` MUST NOT exist:

  ```bash
  doppler run -p soleur -c dev_scheduled -- psql "$DATABASE_URL_POOLER" -c "
    SELECT to_regclass('public.organizations'),
           to_regclass('public.workspaces'),
           to_regclass('public.workspace_members'),
           to_regclass('public.workspace_member_attestations');"
  # Expected: 4 NULLs.
  ```

### Phase 2 — Re-run the tenant-integration suite locally against dev to confirm green

Per `hr-no-dashboard-eyeball-pull-data-yourself`, do NOT wait for the next push to confirm; trigger the suite from the worktree.

- [ ] **2.1** Run the dev-Supabase tenant-isolation suite locally (mirrors `.github/workflows/tenant-integration.yml:147-152`):

  ```bash
  cd apps/web-platform
  doppler run -p soleur -c dev_scheduled -- \
    env TENANT_INTEGRATION_TEST=1 \
    npm run test:ci -- test/server/ --project unit --reporter=verbose
  ```

  Expected: all 15+ previously-failing suites pass; `grant_action_class(userA)` returns `{ error: null }`.

- [ ] **2.2** Spot-check the three suites the issue body called out by name:
  - `test/server/scope-grants/lifecycle.test.ts` (4 cases)
  - `test/server/template-authorizations-worm.test.ts`
  - `test/server/scope-grants/cross-tenant-read-denied.test.ts`

### Phase 3 — Workflow gate: detect "dev-applied migrations not on origin/main"

The detection here closes the loop on `wg-when-a-workflow-gap-causes-a-mistake-fix` — the current workflow has no mechanism to catch "branch X applied migrations to dev but never merged". The team-workspace branch did this; the tenant-integration suite caught it incidentally (because both branches share a Postgres role on dev). A fresh gate makes it visible at apply time.

- [ ] **3.1** Add a precondition to `apps/web-platform/scripts/run-migrations.sh` that, when run against dev (config `dev_scheduled` or `dev`), AND when the target migration filename is NOT present on `origin/main`, REQUIRES an environment variable `ALLOW_UNMERGED_DEV_APPLY=1` to proceed. The gate is opt-in (operator must ack), aligns with `hr-menu-option-ack-not-prod-write-auth`'s precedent for prd writes but applied to dev migration applies. The ack semantic is "I have read the team-workspace plan, I accept the dev-vs-main drift this creates, and I will revert if my PR doesn't merge within N days".

  Files to edit:
  - `apps/web-platform/scripts/run-migrations.sh`: add the gate near the top of the apply loop. The gate uses `git ls-tree origin/main -- apps/web-platform/supabase/migrations/${filename}` to determine merged status; absent (exit code 1, empty stdout) means "not on main".

  ### Research Insights — Phase 3.1 gate implementation

  **Insertion site (verified live).** The apply loop in `run-migrations.sh` starts at line 125 (`for migration_file in "$MIGRATIONS_DIR"/*.sql; do`). The existing `*.down.sql` skip lives at lines 137-138 (PR-I precedent — added because mig 053's down file `DROP TRIGGER ... ON public.template_authorizations` failed before the forward `.sql` ran). The unmerged-gate must be inserted BETWEEN the `*.down.sql` skip AND the `already_applied` query (line 142) so a filename that is both already-applied AND unmerged still goes through the gate semantics, not a silent skip.

  **Local-fetch caveat.** `git ls-tree origin/main` reads the local fetch's `refs/remotes/origin/main` — it does NOT round-trip to GitHub. If the operator's local clone has not fetched recently, the gate could false-positive a file that has since merged. Mitigation: prepend `git fetch --quiet origin main 2>/dev/null || true` to the gate body (the `|| true` keeps the runner usable offline; the worst case is a false-positive that the operator overrides with `ALLOW_UNMERGED_DEV_APPLY=1`). Acceptable per `cq-silent-fallback-must-mirror-to-sentry`'s spirit (Sentry mirror not required here — this is a CLI shell tool, not a server emit boundary).

  **Reference shape (drop-in):**

  ```bash
  # Inserted between *.down.sql skip and already_applied query (~line 140).
  # Block apply of unmerged migration filenames against dev, per #4241.
  # Operator ack via ALLOW_UNMERGED_DEV_APPLY=1 (local-iteration valve).
  git fetch --quiet origin main 2>/dev/null || true
  if [[ -z "$(git ls-tree origin/main -- "apps/web-platform/supabase/migrations/$filename" 2>/dev/null)" ]]; then
    if [[ "${ALLOW_UNMERGED_DEV_APPLY:-0}" != "1" ]]; then
      echo "::error::Migration $filename is NOT on origin/main."
      echo "          Applying unmerged migrations to dev creates dev-vs-main drift"
      echo "          (precedent: #4241). To proceed, re-run with"
      echo "          ALLOW_UNMERGED_DEV_APPLY=1 and revert before vacation."
      exit 1
    fi
    echo "  WARNING: $filename is not on origin/main; proceeding under ALLOW_UNMERGED_DEV_APPLY=1."
  fi
  ```

  **What the gate does NOT do.** It does not detect renames or content drift — a file with the same name on a feature branch and on main passes the gate even if their contents differ. This is fine because `_schema_migrations` is filename-keyed; once an apply of a "same-named" file lands on dev, the post-merge re-apply will skip it. The convention is "filename = identity"; the gate enforces only the identity-on-main check.

- [ ] **3.2** Add a `tenant-integration.yml` smoke probe that, on every workflow run, asserts `_schema_migrations` rows on dev are a SUBSET of the migrations present on `origin/main`. If dev has a row whose file is NOT on main, echo `::warning::` (not `::error::`) with the file list and a link to issue #4241 as precedent. This is the post-detection equivalent of #3.1's pre-detection — even if `ALLOW_UNMERGED_DEV_APPLY=1` is used, the next CI run surfaces the drift instead of swallowing it.

  Files to edit:
  - `.github/workflows/tenant-integration.yml`: add a `Detect dev-vs-main migration drift` step before the `Apply migrations to dev` step.

  ### Research Insights — Phase 3.2 probe implementation

  **Probe shape (drop-in step, inserted before `Apply migrations to dev`):**

  ```yaml
  - name: Detect dev-vs-main migration drift
    working-directory: apps/web-platform
    env:
      DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_DEV_SCHEDULED }}
    run: |
      set -uo pipefail
      applied=$(doppler run -p soleur -c dev_scheduled -- \
        psql "$DATABASE_URL_POOLER" -tAc \
        "SELECT filename FROM public._schema_migrations ORDER BY filename;")
      drift=""
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        if [[ -z "$(git ls-tree origin/main -- "apps/web-platform/supabase/migrations/$f")" ]]; then
          drift+="$f"$'\n'
        fi
      done <<<"$applied"
      if [[ -n "$drift" ]]; then
        echo "::warning::dev-Supabase has _schema_migrations rows that are NOT on origin/main."
        echo "::warning::See #4241 for the precedent (team-workspace branch applied to dev pre-merge)."
        echo "::warning::Drift list:"
        printf '::warning::  - %s\n' $drift
      else
        echo "No dev-vs-main migration drift detected."
      fi
  ```

  **Why `::warning::` not `::error::`.** During the team-workspace rebase window (after this PR merges, before team-workspace renumbers and re-applies), dev will be temporarily clean. If a different feature branch then applies its own pre-merge migrations to dev (the local-iteration valve case from 3.1), this probe should NOT block CI — it should surface the drift so the next triage-time reader sees it. `::warning::` is the right severity per `cq-silent-fallback-must-mirror-to-sentry`'s spirit applied to dev-only CI: visible, not blocking.

  **What this catches that 3.1 cannot.** The 3.1 gate runs at apply time via `run-migrations.sh`. If a migration was applied to dev via direct `psql` (bypassing the runner) — the team-workspace operator's tasks.md `1a5cc259` records the forward apply via `DATABASE_URL_POOLER` without saying which CLI wrapper was used; the rollback.md cites a `bun run scripts/apply-migration.ts` wrapper that does not exist anywhere in the tree (verified: `find apps/web-platform/scripts -name 'apply-migration*'` returns empty on main AND on commit `5c2696d4`) — the 3.1 gate never fires. The 3.2 probe reads dev's `_schema_migrations` state directly and is independent of how rows got there. (Sharp edge for the team-workspace branch: the rollback.md cites a wrapper script it never authored; the actual revert path in Phase 1.2 of THIS plan uses `psql -v ON_ERROR_STOP=1 -f` against `$DATABASE_URL_POOLER` — same shape `run-migrations.sh` itself uses internally.)

### Phase 4 — Documentation: warn the team-workspace branch about the 053 collision

The team-workspace branch's `053_organizations_and_workspace_members.sql` shares a number prefix with main's `053_template_authorizations.sql` (PR-I, merged 2026-05-21 in commit `2092b9b4`). Once team-workspace rebases onto main, both `053_*.sql` files will sit in the same directory. `_schema_migrations` is filename-keyed so the runner will apply both, but the convention (per learning `2026-04-18-supabase-migration-concurrently-forbidden` and sibling plans) is one migration per number prefix.

- [ ] **4.1** Update `knowledge-base/project/specs/feat-team-workspace-multi-user/tasks.md` with a sharp-edge note in Phase 1 stating: "Renumber 053-056 → 057-060 on rebase. Mig 053 on main is now `053_template_authorizations.sql` (PR-I #4213, merged 2026-05-21). Re-run dev-apply after renumber." This file is on a feature branch, not on main; cherry-pick the edit to that branch in a follow-up. For THIS plan, capture the directive in `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md` so it surfaces in future `/soleur:plan` runs.

- [ ] **4.2** Write the learning file `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md` capturing: (a) the symptom (23514 on grant_action_class), (b) the root cause (apply-to-dev from a non-main branch with no gate), (c) the misdiagnosis trap (issue body named the wrong CHECK because the operator pattern-matched against the most-recently-touched constraint instead of reading the `details:` line of the PostgrestError), (d) the fix (revert via paired down-migrations + delete `_schema_migrations` rows), (e) the workflow gate (3.1 + 3.2 above). Per `cq-test-fixtures-synthesized-only`, no real user data appears in the learning.

## Files to Edit

- `apps/web-platform/scripts/run-migrations.sh` — Phase 3.1 gate.
- `.github/workflows/tenant-integration.yml` — Phase 3.2 drift probe.

## Files to Create

- `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md` — Phase 4.2.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `grep -rn "scope_grants_workspace_id_check" apps/web-platform/supabase/migrations/` returns 0 matches on the PR's HEAD (no source for the constraint on main).
- [ ] **AC2** `doppler run -p soleur -c dev_scheduled -- psql "$DATABASE_URL_POOLER" -c "SELECT to_regclass('public.organizations');"` returns NULL (Phase 1.4 result post-revert; captured in PR body as a `<details>` block).
- [ ] **AC3** `doppler run -p soleur -c dev_scheduled -- env TENANT_INTEGRATION_TEST=1 npm run test:ci -- test/server/scope-grants/lifecycle.test.ts --project unit --reporter=verbose` exits 0 with `grant_action_class` errors null on all 4 lifecycle cases.
- [ ] **AC4** The next push of this PR's branch to GitHub produces a green `Tenant integration (dev-Supabase)` check (full 15+ suites pass).
- [ ] **AC5** `bash apps/web-platform/scripts/run-migrations.sh --bootstrap=skip` against `dev_scheduled` without `ALLOW_UNMERGED_DEV_APPLY=1` exits non-zero when run against a migration filename that is not on `origin/main` (test by creating a tmp file `apps/web-platform/supabase/migrations/099_test_unmerged.sql` locally — verify the gate fires; remove the tmp file before push).
- [ ] **AC6** The `Detect dev-vs-main migration drift` step in `tenant-integration.yml` exits 0 with a `::warning::` (not `::error::`) when invoked on the post-revert dev state (no unmerged rows remain).

### Post-merge (operator)

- [ ] **AC7** Within 24 hours of merge, operator opens a follow-up issue against `feat-team-workspace-multi-user` requesting the 053→057 renumber + re-apply-after-rebase note in that branch's tasks.md. Tracking-only; not a code change in this PR.

## Test Scenarios

- **TS1 — Revert restores dev schema.** Phase 1.1-1.4 + Phase 2.1: down-migrations applied; pg_constraint diff shows only `scope_grants_workspace_id_check` removed; 4 tables absent; full tenant-integration suite green.
- **TS2 — Workflow gate blocks unmerged apply.** AC5: synthetic `099_test_unmerged.sql` triggers the gate; `ALLOW_UNMERGED_DEV_APPLY=1` bypasses it (intentional opt-in).
- **TS3 — Drift probe surfaces residual unmerged rows.** Manually `INSERT INTO _schema_migrations (filename) VALUES ('999_synthetic.sql')` against dev, re-run workflow, confirm `::warning::` emitted. (Don't ship this synthetic insert; verify locally and reset.)
- **TS4 — Re-apply after team-workspace lands.** Once `feat-team-workspace-multi-user` merges to main (post-renumber), the runner re-applies 057-060 (or whatever they renumber to) to dev cleanly because the `_schema_migrations` rows for the old 053-056 names were deleted in Phase 1.3.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. The fix is a dev-only schema revert + a workflow gate; no user-facing surface, no compliance or legal artifact, no marketing/sales/finance touchpoint. Skipped per the Phase 2.5 NONE branch.

## Observability

| Field | Value |
|---|---|
| `liveness_signal` | The `Tenant integration (dev-Supabase)` GitHub Actions workflow on every push/PR that touches the path filter. Cadence: per-push. Alert target: GitHub Checks status (red → merge blocked). Configured in: `.github/workflows/tenant-integration.yml:38-46`. |
| `error_reporting` | Workflow failure surfaces a red check on the PR; the `Apply migrations to dev` step echoes the failing SQL filename via `psql -v ON_ERROR_STOP=1`. Fail-loud: yes (no `\|\| true` swallowing). |
| `failure_modes` | (1) Drift returns — operator applies migrations to dev from another unmerged branch. Detection: Phase 3.2's `Detect dev-vs-main migration drift` step emits `::warning::` with file list. Alert route: GitHub Actions warning annotation. (2) `_schema_migrations` row leak after a revert. Detection: same drift probe. (3) Down-migration partial-apply (e.g., network drop mid-DDL). Detection: pg_constraint snapshot in Phase 1.4 diverges from expected. Alert route: operator re-runs Phase 1.1-1.4 until clean. |
| `logs` | `psql -v ON_ERROR_STOP=1` outputs are captured in the GitHub Actions step log (retention: 90 days per default). `pg_constraint` snapshots in `/tmp/scope_grants_*.txt` are session-local. |
| `discoverability_test` | `doppler run -p soleur -c dev_scheduled -- psql "$DATABASE_URL_POOLER" -c "SELECT count(*) FROM public._schema_migrations WHERE filename IN ('053_organizations_and_workspace_members.sql', '054_workspace_member_attestations.sql', '055_workspace_keyed_rls_sweep.sql', '056_current_organization_jwt_hook.sql');"` — expected output: `0` post-revert. No SSH required. (Original draft used `LIKE '05_workspace%'`; SQL `_` is a single-char wildcard and would also match e.g. `058_workspace…` — replaced with an explicit `IN (...)` enum.) |

## Risks

- **R1: Phase 1.2 fails partway through.** The down-migrations are paired with explicit `DROP IF EXISTS` so re-running is safe; mitigation: re-run the failing down-migration. Lower risk because the team-workspace branch's `rollback.md` explicitly tested the down-migration chain on dev (per `bc3879c7` Phase 5.1 commit + rollback.md Step 2).
- **R2: A second unmerged branch has also applied to dev.** Phase 3.2's drift probe surfaces any residual `_schema_migrations` rows that aren't on main. If found, scope-out into a follow-up issue per `hr-menu-option-ack-not-prod-write-auth` (don't bundle into THIS PR).
- **R3: The team-workspace branch refuses to renumber on rebase.** Out of scope for this PR. The learning file in Phase 4.2 + the follow-up tracking issue in AC7 cover the directive.
- **R4: `ALLOW_UNMERGED_DEV_APPLY=1` becomes a no-op rubber-stamp.** Mitigation: Phase 3.2's runtime drift probe surfaces the drift regardless, with a link back to issue #4241 in the warning text. The gate is opt-in for the local-experiment case (fast-iterate against dev before opening a PR), and the runtime probe catches the "forgot to revert before going on vacation" case.

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for f in apps/web-platform/scripts/run-migrations.sh .github/workflows/tenant-integration.yml; do
  jq -r --arg path "$f" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

None. (Probe to be re-run inline at /work time — record `None` if no matches; otherwise enumerate with fold-in/acknowledge/defer dispositions per Phase 1.7.5.)

## Sharp Edges

- The team-workspace branch's `053_organizations_and_workspace_members.sql` collides with main's `053_template_authorizations.sql` (PR-I) by number prefix. The runner is filename-keyed so both rows coexist in `_schema_migrations`, but the convention is one migration per integer prefix. Once team-workspace rebases onto main, renumber the four files to 057-060 (or whatever follows main's highest at rebase time) BEFORE running the apply again. Note in Phase 4.2's learning file.
- `DATABASE_URL_POOLER` on Supabase pooler `:6543` is transaction-mode and rejects multi-statement DDL. Phase 1.2's down-migrations use `:5432` session-mode via the Doppler-injected `DATABASE_URL_POOLER` (which is the `:5432` rewrite in `dev_scheduled` per the team-workspace rollback.md). Verify the URL string contains `:5432` BEFORE applying; aborting via a manual `grep -q ':5432' <<<"$DATABASE_URL_POOLER"` is cheap insurance.
- A `## User-Brand Impact` section whose threshold resolves to `none` AND whose diff touches a non-sensitive path (per preflight Check 6 canonical regex — this plan's diff touches `apps/web-platform/scripts/run-migrations.sh`, `.github/workflows/tenant-integration.yml`, and `knowledge-base/`; none match `apps/web-platform/server/`, `**/migrations/**`, `**/auth/**`, `**/api/**`). No `threshold: none, reason:` scope-out required.
- Per `wg-use-closes-n-in-pr-body-not-title-to`, the PR body uses `Closes #4241` (this issue resolves at merge — the dev schema is restored at Phase 1, before merge; the workflow gate that prevents recurrence lands at merge).
- Per `hr-no-ssh-fallback-in-runbooks`: all discoverability and apply paths use `doppler run -- psql` and `gh run view`. No SSH. The Phase 3.1 gate's verification is `git ls-tree origin/main` — local-only, no remote shell.

## References

- Issue: #4241
- Commits: `5c2696d4` (team-workspace Phase 1 forward apply), `1a5cc259` (team-workspace tasks.md dev-apply status), `2092b9b4` (main's PR-I merge — same date, same number collision), `de4ab71c` (team-workspace Phase 4 — feature-flag gate, not yet a concern for this fix).
- Migrations on team-workspace (NOT on main):
  - `053_organizations_and_workspace_members.{sql,down.sql}`
  - `054_workspace_member_attestations.{sql,down.sql}`
  - `055_workspace_keyed_rls_sweep.{sql,down.sql}` ← source of `scope_grants_workspace_id_check`
  - `056_current_organization_jwt_hook.{sql,down.sql}`
- Failing log lines: `gh run view 26225869534 --log-failed` — search for `23514` and `scope_grants_workspace_id_check`.
- Migration runner: `apps/web-platform/scripts/run-migrations.sh`
- Workflow: `.github/workflows/tenant-integration.yml`
- Related hard rules: `hr-dev-prd-distinct-supabase-projects`, `hr-menu-option-ack-not-prod-write-auth`, `hr-no-ssh-fallback-in-runbooks`, `hr-no-dashboard-eyeball-pull-data-yourself`.
- Related workflow gates: `wg-when-a-workflow-gap-causes-a-mistake-fix`, `wg-use-closes-n-in-pr-body-not-title-to`.

