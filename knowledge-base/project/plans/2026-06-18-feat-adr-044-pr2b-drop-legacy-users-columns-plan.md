<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "feat(adr-044): PR-2b — drop legacy users repo-connection columns (FINAL, irreversible)"
date: 2026-06-18
type: feat
issue: 5437
adr: ADR-044
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
migration_number: 111
status: planned
---

# feat(adr-044): PR-2b — DROP legacy `users` repo-connection columns 🗃️

> **FINAL step of the ADR-044 arc. IRREVERSIBLE — this removes the revert net.**
> Migration #111 drops the migration-052 partial-UNIQUE index on
> `users.github_installation_id`, then `DROP COLUMN github_installation_id,
> repo_url, workspace_path` from `public.users`. The `.down.sql` is
> **SCHEMA-ONLY** rollback: it re-creates the three columns + the index, but the
> **COLUMN DATA IS NOT RECOVERABLE**.

`Closes #5437` (completes the umbrella's final acceptance criterion — the
column DROP that PR-2a / the team write-cutover unblocked).

---

## Enhancement Summary

**Deepened on:** 2026-06-18
**Review agents:** data-migration-expert, data-integrity-guardian,
deployment-verification-agent, user-impact-reviewer, verify-the-negative pass.
**Verdict:** APPROVE — all load-bearing safety claims verified live on
`origin/main`; no blocking P0. The destructive drop is safe to proceed once the
Phase-0 gates are re-run at work-start.

### Key findings applied
1. **Runtime cross-tenant guard is verifiably LIVE** (4-of-5 consensus): the
   `{found|none|ambiguous|db-error}` resolver (`>1` fail-closed) + the
   `github_webhook_founder_ambiguous` Sentry rule at
   `apps/web-platform/infra/sentry/issue-alerts.tf:576` both exist — the dropped
   index's guarantee is genuinely replaced. (One reviewer's "file absent" P0 was a
   false negative from a bare path; resolved.)
2. **AC0.5 / Observability / prose now use the full `apps/web-platform/` path** for
   the Sentry rule — a bare `infra/sentry/...` grep falsely reads "guard absent".
3. **Type trim corrected to SAFE straight-delete** — synthesized objects use the
   local `KbRouteContext.userData` shape, not `interface User`; `tsc --noEmit` is
   the backstop (Sharp Edge #1 / AC4 reworded).
4. **Migrate-before-deploy window** scoped out (safe because PR-2a removed all live
   readers from the deployed image; `dsar-export.ts:462` `select("*")` degrades).
5. **Added AC13:** 24h post-deploy `op="founder-ambiguous"` Sentry watch — the
   load-bearing signal that the runtime replacement actually fires (verify/111 only
   proves the index is gone).
6. AC9/AC12 relabeled (dev REST probe vs prod psql verify); down.sql COMMENT
   restored verbatim from mig-052; rollback-doc + PGRST205 cache notes added.

---

## Overview

ADR-044 relocated repo-connection state from `users.*` to `workspaces.*`. The
arc landed in slices:

- **PR-1 (mig 079/080/081):** additive `workspaces` repo columns + solo-only
  backfill + Art-17 cascade. Status `adopting`.
- **PR-2a / team write-cutover (mig 110, PRs #5466, #5481, #5482, #5491):**
  relocated every connect-time WRITE and the last `users.*` repo READ off
  `users` onto `workspaces`. After this, `users.{github_installation_id,
  repo_url, workspace_path}` are dead columns with stale/frozen data.
- **PR-2b (THIS plan, mig 111):** drop the three dead columns + the dead index.

The structural guarantee the dropped mig-052 partial-UNIQUE index provided
(one founder per installation; the webhook `.maybeSingle()` would otherwise
silently mis-attribute on a 1:N collision) is **already replaced at runtime**
by the webhook `>1`-fail-closed founder resolver
(`apps/web-platform/server/resolve-founder-for-installation.ts`, the
`resolveSoloFounderForInstallation` `{found|none|ambiguous|db-error}` union, `>1`
fail-closed at `:108`) + the `op="founder-ambiguous"` `Sentry.captureException`
(fired from `app/api/webhooks/github/route.ts:342`) and the
`github_webhook_founder_ambiguous` paging rule
(`apps/web-platform/infra/sentry/issue-alerts.tf:576`, value `"founder-ambiguous"`)
(ADR-044 Amendment 2026-06-17b, R7/R8). **All three are verified live on
`origin/main`** (multi-agent deepen-plan review, 2026-06-18). The drop does **not** reintroduce the
cross-tenant hazard — the guard moved from DB-constraint to application code by
design.

This PR also **flips ADR-044 status `adopting` → `accepted`** and adds a dated
closure amendment, and **hand-trims the `users` row type** in `lib/types.ts`
(there is NO generated `database.types.ts` — types are hand-written).

### Scope guard (do NOT drop)

- **KEEP** `users.role`, `users.workspace_status`, `users.tc_accepted_at`,
  `users.email`, `users.github_username`, `users.health_snapshot` — all live.
- **KEEP** `workspaces.{repo_url, repo_status, repo_provider,
  repo_last_synced_at, github_installation_id}` — the cutover TARGET. Mig 111
  touches **only `public.users`**, never `public.workspaces`.
- **KEEP** `conversations.repo_url` (mig 029) — a different column on a different
  table. `lib/types.ts:594` `Conversation.repo_url` is OUT OF SCOPE.
- **DROP set is exactly three columns + one index**, all on `public.users`.

---

## Research Reconciliation — Spec vs. Codebase

| Premise (from task brief) | Codebase reality (verified 2026-06-18) | Plan response |
|---|---|---|
| Index name "likely `users_github_installation_id_unique_idx`" | **Confirmed** at `migrations/052_multi_source_dedup.sql:159-161`: `CREATE UNIQUE INDEX IF NOT EXISTS users_github_installation_id_unique_idx ON public.users (github_installation_id) WHERE github_installation_id IS NOT NULL` | Drop by exact name; recreate identically in `.down.sql`. |
| `workspace_path text NOT NULL DEFAULT ''` / `repo_url text` / `github_installation_id bigint` | **Confirmed.** `workspace_path` = `001_initial_schema.sql:9` (`text not null default ''`); `repo_url` = `011_repo_connection.sql:6` (`text`); `github_installation_id` = `011_repo_connection.sql:8` (`bigint`). | `.down.sql` re-adds with these exact types/defaults. |
| Hand-trim generated `lib/database.types.ts` | **No such file exists.** Types are hand-written in `apps/web-platform/lib/types.ts`. `interface User` (line 552) contains **only `workspace_path: string`** (line 555); it does NOT contain `github_installation_id` or `repo_url`. | Types task narrows to the `interface User` field — BUT see Sharp Edge #1: live resolver-synthesized objects are typed against this field. Treat as a review-gated decision (data-migration-expert), not a blind line delete. |
| "0 live readers/writers of the three columns on main" | **Confirmed by precise multi-line sweep** (`rg -nU 'from("users")[\s\S]{0,400}?\b(github_installation_id\|repo_url\|workspace_path)\b' app server lib` returns only comments + DIFFERENT-column selects + `workspaces` reads). The 4th stranded reader (`settings/page.tsx` multi-line select) was closed in Amendment 2026-06-17b. | Re-run BOTH the multi-line sweep AND the dual-shape `.eq()`/`.in()` lookup sweep at work-start as a hard gate (Phase 0). |
| Migration number | Highest on local AND `origin/main` (fetched 2026-06-18) is **110**. No sibling claimed 111. | **Use 111.** Re-run collision check at work-start (rebase-before-ship class). |
| Apply mechanics: `run-migrations.sh` writes tracking row in same txn | **Confirmed** `scripts/run-migrations.sh:336-346`: migration body + `INSERT INTO _schema_migrations (filename, content_sha)` are piped together through `psql … --single-transaction`. | Do NOT add top-level `BEGIN;`/`COMMIT;` to the body (mirror mig 110, NOT mig 108). Dev apply via the script (or mirror its tracking-row write). |
| `repo_status`/`repo_last_synced_at`/`repo_provider` are NOT users columns to drop | These live on `workspaces` now; the `users` versions (if any) are NOT in PR-2b's named set. | Explicitly excluded from the DROP list. |

---

## User-Brand Impact

**If this lands broken, the user experiences:** a 500 / blank screen on the
settings page, repo-connect flow, KB upload, or agent spawn — OR, worse, a
**silent cross-tenant mis-attribution** (founder A's GitHub PRs land on founder
B's dashboard) if the dropped index's structural guarantee is not actually
replaced by the runtime resolver. A wrong DROP or a missed live reader = broken
GitHub auth / KB / agent runtime for **every** user.

**If this leaks, the user's workflow/credentials are exposed via:** the
`github_installation_id` is a GitHub App installation-token grant (repo write
access). Dropping the UNIQUE index without the working `>1`-fail-closed resolver
would re-open the 1:N cross-tenant attribution window — a single user's repo
actions routed to another tenant.

**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time before `/work` begins (carried forward
> from the ADR-044 brainstorm framing; `brand_survival_threshold: single-user
> incident` is set in ADR-044 frontmatter). `user-impact-reviewer` runs at
> review time.

---

## Acceptance Criteria

### Pre-apply gates (work Phase 0 — HARD BLOCK, re-verify; do NOT trust the brief)

- [ ] **AC0.1 — Reader sweep (multi-line):** `rg -nU 'from\("users"\)[\s\S]{0,400}?\b(github_installation_id\|repo_url\|workspace_path)\b' apps/web-platform/{app,server,lib}` returns ZERO *live* readers (comments + different-column selects + `workspaces`/synthesized-object reads are allowed; a live `.from("users").select(...one of the three...)` is a BLOCK). A sibling PR could have added one since the cutover. **The 400-char window over-matches** — it bleeds into adjacent comments/statements (e.g. `agent-runner.ts:1047` selects `email`, the `github_installation_id` nearby is a comment). Inspect the column-of-SELECT on EACH hit manually; do NOT trust exit code (deepen-plan review note).
- [ ] **AC0.2 — Lookup-shape sweep (dual-shape):** `git grep -nE "\.eq\([\"']?(github_installation_id\|repo_url\|workspace_path)\b" -- 'apps/web-platform/{app,server,lib}'` shows every hit is on a `workspaces` query or a synthesized object — ZERO live `users`-table `.eq()`/`.in()`/`.match()` filters on the three columns (the stranded-lookup class, learning `2026-06-17-column-relocation-reader-sweep-and-stranded-eq-lookups.md`).
- [ ] **AC0.3 — `workspace_path` consumer trace:** every `userData.workspace_path` / `access.workspacePath` consumer (`kb/upload`, `kb/file`, `kb/c4`, `agent-runner`, `sandbox`, `dsar-export`) reads from a **resolver-synthesized** object (`resolveActiveWorkspaceKbRoot` / active-workspace resolver), NOT a `users` SELECT. Confirmed example: `kb/upload/route.ts:104` builds `userData = { workspace_path: access.workspacePath }`, typed against the **local `KbRouteContext.userData` inline shape** (`server/kb-route-helpers.ts:23-27`), NOT `lib/types.ts interface User`. (Sharp Edge #1 — the trim is therefore SAFE, see below.) Also confirm `dsar-export.ts:462` `.from("users").select("*")` is the only wildcard `users` reader — it is **drop-safe** (PostgREST `*` returns whatever columns exist; no 42703 on a dropped column).
- [ ] **AC0.4 — Drift gate COUNT=0:** re-run the ADR-044 §"Pre-decommission drift gate" against PROD read-only (Doppler `DATABASE_URL_POOLER`, session mode `:5432`, node-pg, `ssl: { rejectUnauthorized: false }`): `SELECT count(*) FROM users u JOIN workspaces w ON w.id = u.id WHERE u.repo_url IS DISTINCT FROM w.repo_url OR u.github_installation_id IS DISTINCT FROM w.github_installation_id` returns **0**. Capture the count + timestamp in the PR body. Any non-zero BLOCKS the drop.
- [ ] **AC0.5 — Runtime guard live:** confirm `apps/web-platform/server/resolve-founder-for-installation.ts` exports the `{found|none|ambiguous|db-error}` resolver (`>1` fail-closed at `:108`) AND `apps/web-platform/infra/sentry/issue-alerts.tf:576` carries the `github_webhook_founder_ambiguous` rule on `op="founder-ambiguous"` — the replacement for the dropped index's structural guarantee, on `origin/main`. **Use the full `apps/web-platform/` path prefix** — a bare `infra/sentry/...` grep from repo root returns zero and falsely reads as "guard absent" (deepen-plan review false-negative). Already verified present 2026-06-18.
- [ ] **AC0.6 — Collision check:** `git fetch origin main` then `git ls-tree origin/main -- apps/web-platform/supabase/migrations/ | grep -oE '[0-9]{3}_' | sort -u | tail` confirms 110 is the max and 111 is free.

### Migration artifacts (pre-merge)

- [ ] **AC1 — Up migration exists** at `apps/web-platform/supabase/migrations/111_drop_legacy_users_repo_columns.sql` with: a header comment block (filename, ADR-044 ref, **IRREVERSIBLE/DATA-NOT-RECOVERABLE** warning, LAWFUL_BASIS, no-CONCURRENTLY note), `DROP INDEX IF EXISTS public.users_github_installation_id_unique_idx;`, then a single `ALTER TABLE public.users DROP COLUMN IF EXISTS github_installation_id, DROP COLUMN IF EXISTS repo_url, DROP COLUMN IF EXISTS workspace_path;`. **No top-level `BEGIN;`/`COMMIT;`** (mirror mig 110; the runner's `--single-transaction` wraps it).
- [ ] **AC2 — Down migration exists** at `…/111_drop_legacy_users_repo_columns.down.sql`: re-adds the three columns with exact original types (`github_installation_id bigint`, `repo_url text`, `workspace_path text NOT NULL DEFAULT ''` — use `ADD COLUMN IF NOT EXISTS`), then recreates the partial-UNIQUE index identically (`CREATE UNIQUE INDEX IF NOT EXISTS users_github_installation_id_unique_idx ON public.users (github_installation_id) WHERE github_installation_id IS NOT NULL`) and re-adds its `COMMENT ON INDEX`. Header states **SCHEMA-ONLY rollback; column DATA is NOT recoverable**.
- [ ] **AC3 — Verify sentinel** at `apps/web-platform/supabase/verify/111_drop_legacy_users_repo_columns.sql` mirrors verify/110's UNION-of-`(check_name, bad::int)` shape (every `bad` column INTEGER — no boolean/integer UNION mismatch, per the verify/110 NOTE) asserting **post-apply**: (a) `users.github_installation_id` column count = 0, (b) `users.repo_url` count = 0, (c) `users.workspace_path` count = 0, (d) index `users_github_installation_id_unique_idx` count = 0 (via `pg_indexes`). Any `bad > 0` fails `run-verify.sh`.
- [ ] **AC4 — Type trim:** remove `workspace_path: string` from `interface User` (`apps/web-platform/lib/types.ts:555`) — deepen-plan review confirmed this is a SAFE straight deletion (synthesized objects use the local `KbRouteContext.userData` shape, not `interface User`; Sharp Edge #1). `Conversation.repo_url` (line 594) is UNTOUCHED. `tsc --noEmit` clean (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`) is the backstop confirming no consumer broke.
- [ ] **AC5 — ADR status flip:** `ADR-044-workspace-repo-ownership.md` frontmatter `status: adopting` → `status: accepted`.
- [ ] **AC6 — Closure amendment:** a dated `## Amendment 2026-06-18 — PR-2b column DROP (arc CLOSED)` section records: the drop migration number (111), the verified drift-gate COUNT=0 + timestamp, the final reader-sweep result (0 live readers), and that the dropped index's guarantee is carried by the runtime resolver + Sentry rule.
- [ ] **AC7 — PR body** uses `Closes #5437` (this is the umbrella's final criterion; mig 111 IS the change, applied pre-deploy by the release pipeline — `Closes`, not `Ref`, is correct because the resolution lands at merge via the `migrate` job, not a separate post-merge operator step).

### Dev apply + verification (work phase, in-session)

- [ ] **AC8 — Dev apply:** migration applied to DEV via `apps/web-platform/scripts/run-migrations.sh` (or a tracking-row-mirroring apply) using Doppler `DATABASE_URL_POOLER` rewritten to session mode `:5432`. Do NOT bare a `BEGIN; <migration>; COMMIT;` apply (phantom-applied state — the tracking row must land in the same transaction as the DDL). If 111 is not yet on `origin/main`, the unmerged-apply gate requires `ALLOW_UNMERGED_DEV_APPLY=1` ack AND a dev-schema revert plan before push (learning `2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`).
- [ ] **AC9 — Columns GONE (dev manual discoverability probe — REST/42703):** `curl -s "$SUPABASE_URL/rest/v1/users?select=github_installation_id&limit=1" -H "apikey: $ANON"` returns HTTP 400 with `{"code":"42703", … "column users.github_installation_id does not exist"}`; same for `repo_url` and `workspace_path`. This is a **dev sanity probe**, distinct from the prod psql gate (AC12).
- [ ] **AC10 — verify/111 green on dev:** `run-verify.sh` (psql against dev `DATABASE_URL_POOLER`) reports `bad=0` for all four checks post-apply.

### Post-merge (operator/pipeline — automatable, NOT operator-manual)

- [ ] **AC11 — Prod apply:** the `web-platform-release.yml` `#migrate` job (`doppler run -c prd -- bash …/run-migrations.sh`) applies mig 111 to PROD on merge (path-filtered on `apps/web-platform/**`), BEFORE the deploy job (deploy `needs: migrate`). No separate operator step. `Automation: handled by release pipeline.`
- [ ] **AC12 — Prod verify (psql, NOT REST):** the `#verify-migrations` job (`needs: migrate`) runs `run-verify.sh` which executes verify/111 via **psql** (`run-verify.sh:55`, not a REST probe) and reports `bad=0` for all four checks against prod. `Automation: pipeline verify step.`
- [ ] **AC13 — Post-deploy 24h cross-tenant watch:** the `github_webhook_founder_ambiguous` Sentry rule (`apps/web-platform/infra/sentry/issue-alerts.tf:576`) is the load-bearing post-drop signal — verify/111 only proves the index is GONE, not that its runtime replacement FIRES. Verdict rule: **ANY `op="founder-ambiguous"` event in the first 24h = a 1:N installation collision the dropped UNIQUE index used to block → investigate.** `Automation: existing Sentry paging rule; no operator dashboard-watch.`

---

## Implementation Phases

### Phase 0 — Pre-apply gates (HARD BLOCK)
Run AC0.1–AC0.6. Any failure aborts before any file is written. The drift gate
+ reader sweep are the load-bearing safety gates: a missed live reader or a
non-zero drift = single-user incident on drop. Capture all evidence into the PR
body draft.

### Phase 1 — Author the up migration (`111_…sql`)
Mirror mig 110's header conventions (filename comment, `feat-adr-044 … #5437`,
ADR-044 ref, "Supabase wraps each migration file in ONE transaction; no explicit
BEGIN/COMMIT and no CONCURRENTLY"). Add an explicit **IRREVERSIBLE — column DATA
is NOT recoverable; `.down.sql` restores SCHEMA ONLY** banner + a LAWFUL_BASIS
note (Art. 5(1)(e) storage-limitation / data-minimisation: dropping dead
credential + path columns whose data is relocated and now stale). Body:
```sql
DROP INDEX IF EXISTS public.users_github_installation_id_unique_idx;

ALTER TABLE public.users
  DROP COLUMN IF EXISTS github_installation_id,
  DROP COLUMN IF EXISTS repo_url,
  DROP COLUMN IF EXISTS workspace_path;
```

### Phase 2 — Author the down migration (`111_….down.sql`)
Header: SCHEMA-ONLY rollback warning. Body re-adds columns + index with the
exact original definitions:
```sql
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS github_installation_id bigint,
  ADD COLUMN IF NOT EXISTS repo_url text,
  ADD COLUMN IF NOT EXISTS workspace_path text NOT NULL DEFAULT '';

CREATE UNIQUE INDEX IF NOT EXISTS users_github_installation_id_unique_idx
  ON public.users (github_installation_id)
  WHERE github_installation_id IS NOT NULL;

COMMENT ON INDEX public.users_github_installation_id_unique_idx IS
  'PR-H (#3244) — Cross-tenant attribution guard. The GitHub webhook '
  'resolves founder via .maybeSingle() on github_installation_id; '
  'without this index a 1:N mapping (two founders, same installation) '
  'would silently route to one of them. WHERE NOT NULL keeps the '
  'constraint compatible with pre-install rows.';
```
> Restore the **verbatim** mig-052 COMMENT text (above, from `052:163-168`) — a
> faithful schema restore reproduces the original comment, not a placeholder
> (deepen-plan review P2).
> Note: `workspace_path … NOT NULL DEFAULT ''` re-adds cleanly because all
> existing rows take the default (`''`); no backfill trap.

### Phase 3 — Verify sentinel (`verify/111_…sql`)
Mirror verify/110 UNION shape; all `bad` columns `::int`. Four checks
(3 columns absent + 1 index absent).

### Phase 4 — Type trim (`lib/types.ts`)
Resolve the Sharp Edge #1 question per the data-migration-expert review:
the safest default is to retain `User.workspace_path` only if it genuinely types
a resolver-synthesized object, otherwise remove it and point consumers at the
resolved-access type. `tsc --noEmit` clean. Do NOT touch `Conversation.repo_url`.

### Phase 5 — ADR closure
Flip frontmatter `status: adopting` → `accepted`; append dated closure amendment
(AC6). No `.c4` edit (the connection-owner edge is C4-implicit and already
recorded in ADR-044 prose; `model.c4`/`views.c4` carry no column-level repo edge
— verified empty grep).

### Phase 6 — Dev apply + verify (AC8–AC10), then ship.

---

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-044** (`knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md`):
flip `status: adopting → accepted` and add `## Amendment 2026-06-18 — PR-2b
column DROP (arc CLOSED)`. This is an in-scope task of THIS PR (not a deferred
issue, per learning `2026-06-16-adr-c4-update-is-a-plan-deliverable-not-a-deferred-issue.md`).
The decision being recorded: the repo-connection ownership boundary has fully
moved `users → workspaces`; the DB-constraint uniqueness guarantee is permanently
replaced by the runtime fail-closed resolver + Sentry paging (already adopted in
Amendment 2026-06-17b R7/R8).

### C4 views
**No `.c4` model edit required.** Grep of `model.c4`/`views.c4`/`spec.c4` for
`installation|repo_url|github_installation|workspace_path` returns empty — the
connection-owner relationship is not modeled at column granularity, and
ADR-044's prose already records the workspace-sourced edge. Record this
no-op-with-rationale in the closure amendment so a future reader is not misled.

### Sequencing
The ADR flip to `accepted` lands WITH the drop (the amendment chain explicitly
said the flip lands with PR-2b). No further slice is gated.

---

## Infrastructure (IaC)

**Skip — no new infrastructure** (Phase 2.8 reviewed; ack comment at file head).
This is a pure schema-DDL change against the already-provisioned Supabase
project, applied by the existing `web-platform-release.yml #migrate` job. No new
server, secret, vendor, cron, or persistent process is introduced. All Doppler
usage is **read-only** (`doppler run` injecting the existing
`DATABASE_URL_POOLER` for the migration runner) — no secret is created or
mutated. Phase 2.8 trigger scan: no `ssh`, no secret-write CLI, no systemd, no
vendor-dashboard step.

---

## Observability

```yaml
liveness_signal:
  what: web-platform-release.yml #migrate job exit status + #verify (run-verify.sh) bad=0
  cadence: once per merge to main touching apps/web-platform/**
  alert_target: CI failure (deploy job blocked on migrate success) — GitHub Actions run failure
  configured_in: .github/workflows/web-platform-release.yml (#migrate, #verify jobs)
error_reporting:
  destination: migrate job fails the release pipeline (deploy gated on needs.migrate); verify/111 bad>0 fails run-verify.sh
  fail_loud: true (a failed DROP rolls back via --single-transaction; deploy never proceeds on a half-applied schema)
failure_modes:
  - mode: a live users.* reader missed at Phase 0 leads to 42703 on that route post-deploy
    detection: existing route Sentry capture (the route throws; Sentry event on first hit)
    alert_route: Sentry issue-alerts (web-platform project)
  - mode: cross-tenant mis-attribution if the runtime resolver guard is not live
    detection: resolveSoloFounderForInstallation `>1` branch leads to Sentry.captureException op="founder-ambiguous"
    alert_route: apps/web-platform/infra/sentry/issue-alerts.tf:576 github_webhook_founder_ambiguous paging rule (R7/R8) — load-bearing 24h post-deploy watch (AC13)
  - mode: prod DROP fails (lock contention / unexpected dependency)
    detection: "#migrate job non-zero exit; --single-transaction auto-rolls-back"
    alert_route: GitHub Actions release-pipeline failure notification
logs:
  where: GitHub Actions #migrate + #verify job logs; Sentry for route-level 42703
  retention: GitHub Actions default; Sentry per project retention
discoverability_test:
  command: curl -s "$SUPABASE_URL/rest/v1/users?select=github_installation_id&limit=1" -H "apikey: $ANON"  # expect HTTP 400 / 42703 (no remote shell needed)
  expected_output: '{"code":"42703",...,"message":"column users.github_installation_id does not exist"}'
```

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| **IRREVERSIBLE data loss.** `.down.sql` restores schema only; the dropped column values (installation grants, repo URLs, paths) are gone. | High | (1) Stale-data argument: PR-2a relocated all writes, so `users.*` values are already frozen/stale and superseded by `workspaces.*` — the canonical copy is NOT lost. (2) Drift gate COUNT=0 (AC0.4) proves `users.*` == `workspaces.*` pre-drop, so nothing unique is destroyed. (3) State this explicitly in the migration header + here. |
| **Missed live reader** (sibling PR added one since cutover) leading to 42703 on a user-facing route. | High | AC0.1 multi-line sweep + AC0.2 dual-shape `.eq()` sweep + AC0.3 consumer trace, ALL at work-start, NOT trusting the brief. |
| **Cross-tenant re-attribution** if the index's guarantee isn't actually carried by the resolver. | High | AC0.5 confirms the `{found\|none\|ambiguous\|db-error}` resolver + `founder-ambiguous` Sentry rule are live on main before drop. |
| **Type trim breaks resolver-synthesized consumers** (Sharp Edge #1). | Medium | AC4 routes the `User.workspace_path` decision through data-migration-expert; `tsc --noEmit` gate. |
| **Top-level `BEGIN;`/`COMMIT;`** would break the tracking-row atomicity. | Medium | Mirror mig 110 (no txn control); learning `2026-05-25-migration-body-no-top-level-begin-commit.md`. |
| **Migrate-before-deploy window** — `#migrate` (drops columns) runs before `#deploy` (new code), so old (currently-deployed) code briefly runs against the dropped schema. | Low | **Safe because PR-2a's cutover already removed every live `users.*`{3-col} reader from the deployed image** (AC0.1); the only `users` wildcard reader (`dsar-export.ts:462` `select("*")`) degrades gracefully (PostgREST `*` returns extant columns, no 42703). This is an unstated dependency on PR-2a being **deployed to prod**, not merely merged — confirm at work-start. |
| **Rollback reality** — `.down.sql` restores schema only; data gone. | — | If the drop breaks prod, the lever is **code-revert** (revert the deploy), NOT schema restore — the dropped columns are dead, so reverting code recovers behavior; `workspaces.*` is canonical. `apps/web-platform/docs/migration-rollback.md` is forward-only and does not mention per-migration `.down.sql` or the irreversible-data class — note this in the PR body so an operator isn't misled. |
| **Dev drift** from applying an unmerged migration. | Low | AC8 honors the `ALLOW_UNMERGED_DEV_APPLY` gate + dev-revert-before-push. |
| Migration-number collision on rebase. | Low | AC0.6 re-runs the collision check at work-start. |
| PostgREST schema-cache staleness (PGRST205) post-DROP (~10 min). | Low | Self-heals; optionally run `postgrest-reload-schema.sh` post-migrate. Note in PR body so the ~10-min window isn't mistaken for an incident. |

---

## Domain Review

**Domains relevant:** Engineering (CTO), Legal/Compliance (data-minimisation /
GDPR). Product surface: NONE (no UI file in Files-to-Edit; the settings-render
reader was already cut over in PR-2a — this PR touches only SQL + a type
interface + the ADR).

### Engineering (CTO)
**Status:** carry-forward from ADR-044 brainstorm/Amendment 2026-06-17b (CTO
binding ruling transcribed in the ADR).
**Assessment:** the drop is unblocked only because all four `users.*` readers
were relocated and the `>1` fail-closed resolver replaces the index. The single
most important invariant: the runtime resolver guard MUST be live on main before
the index drops (AC0.5).

### Legal / Compliance
**Status:** routed to `gdpr-gate` (Phase 2.7 below).
**Assessment:** dropping dead credential + path columns is
data-minimisation-positive (Art. 5(1)(e) storage limitation). No new processing.
The Art-17 cascade (mig 081) already nulls the relocated
`workspaces.github_installation_id` on erasure — unaffected.

### Product/UX Gate
**Tier:** none. No `## Files to Create` / `Files to Edit` path matches a
UI-surface glob (`components/**`, `app/**/page.tsx`, `app/**/layout.tsx`). The
plan touches `supabase/migrations/*.sql`, `supabase/verify/*.sql`,
`lib/types.ts`, and the ADR markdown only.

---

## Files to Create
- `apps/web-platform/supabase/migrations/111_drop_legacy_users_repo_columns.sql`
- `apps/web-platform/supabase/migrations/111_drop_legacy_users_repo_columns.down.sql`
- `apps/web-platform/supabase/verify/111_drop_legacy_users_repo_columns.sql`

## Files to Edit
- `apps/web-platform/lib/types.ts` — `interface User` field trim (Sharp Edge #1 / AC4)
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — status flip + closure amendment

## Open Code-Review Overlap
None (the Files-to-Edit are migration/verify/type/ADR artifacts; no open
`code-review` issue tracks these specific paths at the column-DROP layer).

---

## Review Phase Routing (MANDATORY)

This plan's review MUST route through, in addition to the standard panel:
- **data-migration-expert** — the DROP + down.sql + type trim correctness.
- **data-integrity-guardian** — irreversibility, drift-gate sufficiency, the
  schema-only rollback contract.
- **deployment-verification-agent** — pre/post-deploy checklist + REST-probe
  verification + rollback procedure.
- **gdpr-gate** (Phase 2.7) — schema/PII surface; data-minimisation framing.
- **user-impact-reviewer** — `single-user incident` threshold enumeration.

Per the single-user-incident exit-gate rule, this plan SHOULD run
`/soleur:deepen-plan` (the deepen triad catches substance-level findings —
SQL/index dependency holes, type-trim blast radius — that style plan-review
misses).

---

## Sharp Edges

1. **`User.workspace_path` removal is SAFE — the synthesized objects are NOT
   typed against `interface User`.** Deepen-plan review (3 agents) corrected the
   initial framing: `kb/upload/route.ts:104` builds `userData = { workspace_path:
   access.workspacePath, … }` as a plain inline object literal typed against the
   **local `KbRouteContext.userData` shape** (`server/kb-route-helpers.ts:23-27`),
   NOT `lib/types.ts interface User`. No `.workspace_path` consumer annotates a
   variable `: User` and reads the field. Therefore **removing `User.workspace_path`
   (`lib/types.ts:555`) does NOT break `tsc` on the synthesized-object sites** — the
   straight deletion is correct; the `tsc --noEmit` gate (AC4) is the backstop that
   confirms it. `github_installation_id` is NOT in `interface User`; `repo_url` at
   `lib/types.ts:594` is `Conversation.repo_url` (mig 029, out of scope).
2. **No top-level `BEGIN;`/`COMMIT;` in the migration body.** Mig 108 uses them
   (older pattern); mig 110 explicitly does NOT. The runner's `--single-transaction`
   (`run-migrations.sh:343`) wraps the body + tracking-row INSERT; a body `COMMIT;`
   ends the txn early and strands the ledger row (learning
   `2026-05-25-migration-body-no-top-level-begin-commit.md`). Mirror **110**.
3. **verify/111 UNION type pinning.** Every UNION branch's `bad` column must be
   the SAME type — cast boolean predicates `::int` (the verify/110 NOTE; commit
   e21066864 / #5474 was a release-blocking boolean-vs-integer UNION mismatch).
4. **The `## User-Brand Impact` section is load-bearing** — empty/placeholder
   fails `deepen-plan` Phase 4.6.
5. **Down-migration `workspace_path NOT NULL DEFAULT ''`** re-adds cleanly (all
   rows take the default); the restored column is EMPTY — schema only, as the
   header must state.
