---
title: "SECURITY P0: Isolate dev/prd Supabase databases"
type: fix
date: 2026-04-27
issue: 2887
priority: P0
classification: ops-only-prod-write
---

# SECURITY P0: Isolate dev/prd Supabase databases (#2887)

## Enhancement Summary

**Deepened on:** 2026-04-27
**Sections enhanced:** Phase 1 (provisioning approach), Phase 4 (preflight semantics & AGENTS.md byte budget), Sharp Edges (project-ref resolution), Test Scenarios (added strict-mode and prefix-bypass cases).
**Research sources:** Supabase official "Managing Environments" docs, prior learnings (`2026-03-29-doppler-service-token-config-scope-mismatch`, `2026-03-25-doppler-secret-audit-before-creation`, `2026-04-23-hostname-prefix-guard-and-strict-mode-pipefail`, `2026-03-28-unapplied-migration-command-center-chat-failure`), live `gh issue list --label code-review` (returned 0), live Doppler audit, code-grep audit of `ifsccnjhymdmidffkzhl` (12 hits classified).

### Key Improvements (this pass)

1. **Project-ref resolution made explicit.** Custom-domain prd (`api.soleur.ai`) requires CNAME dereference. Preflight Check 5 spec now prescribes `dig +short CNAME` with extraction of first label, mirroring `mu1-cleanup-guard.mjs` exact-hostname pattern (defense against subdomain-bypass per `2026-04-23-hostname-prefix-guard`).
2. **Phase 1 grounded against Supabase docs.** Supabase "Managing Environments" recommends separate projects for dev/staging/prod (not branching for the dev tier on Free). Free tier currently caps at 2 active projects per org — verified against current org count before planning.
3. **AGENTS.md byte-budget strategy concretized.** Two-rule edit (add `hr-dev-prd-distinct-supabase-projects`, strengthen existing `wg` rule WITHOUT changing id). Plan-time measure target: rule body ≤500 bytes; post-edit run `wc -c AGENTS.md` to confirm < 37000.
4. **`run-migrations.sh` bootstrap behavior captured.** The runner has an INSERT-bootstrap for migrations 001–010 only; 011+ apply normally. On a fresh dev DB, bootstrap fires (table empty) and inserts the 10 sentinel rows, then loops apply 011–029_plan_tier… and beyond. Phase 1 acceptance counts `_schema_migrations` rows = 39 after the loop.
5. **SYNTH allowlist coupling located.** `apps/web-platform/test/mu1-integration.test.ts:45` defines `SYNTH_EMAIL_RE`; the regex is email-shaped (not project-ref shaped) so the project-ref rotation does NOT require regex changes. Comment in `mu1-cleanup-guard.mjs` is a defensive coupling note — verify regex and update only if it actually references the ref.
6. **`gh issue close` post-merge ordering pinned.** Issue closes ONLY after Phase 1+2+6 complete in prod, per `cq-ops-remediation-closes-vs-ref` sharp edge.

### New Considerations Discovered

- **Supabase Free tier project limit:** Two active projects per org. Operator needs to confirm the current Soleur org has exactly 1 active project (`ifsccnjhymdmidffkzhl`) before provisioning the second. If more than one already exists, Phase 1 must reconcile.
- **Pooler URL is region-specific:** `DATABASE_URL_POOLER` host differs from direct DB host (e.g., `aws-0-eu-central-1.pooler.supabase.com`). Cannot template — must fetch from new project's dashboard.
- **`ci` config audit is not optional.** Current `verify-required-secrets.sh` runs in `prd`, but workflows like `scheduled-ux-audit.yml` use `DOPPLER_TOKEN_SCHEDULED` against `prd_scheduled` AND inject `prd` Supabase keys. None of the scheduled configs are dev-shaped, but Phase 6 sweeps all 5 configs to confirm.

## Overview

Doppler `soleur/dev` and `soleur/prd` configs both target the **same Supabase project** (`ifsccnjhymdmidffkzhl.supabase.co`). Every dev migration, fixture, integration test, and ad-hoc query has been operating against the user-facing production database. This plan provisions a separate Supabase project for `dev`, rotates Doppler secrets, applies all 39 migrations to the new project, adds permanent enforcement (preflight + AGENTS.md rule + hostname guards), and documents the isolation model in an ADR.

The remediation is operator-driven (Supabase project provisioning + Doppler rotation), but the enforcement scaffolding (preflight check, hostname guard expansion, AGENTS.md rule, ADR, runbook) ships as a pre-merge code change.

## Problem Statement

Confirmed via Doppler at plan time:

```bash
$ doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c dev --plain
https://ifsccnjhymdmidffkzhl.supabase.co
$ doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain
https://ifsccnjhymdmidffkzhl.supabase.co
```

Identical project ref. Identical `DATABASE_URL` host. Discovered during ship of PR #2858. Blast radius — a leak of any dev-scoped credential, a destructive integration test, a Jupyter `SELECT *`, or any migration "rehearsed in dev" — lands directly on the user-facing DB.

### Concrete failure modes already enabled by current state

1. **`mu1-runbook-cleanup.test.sh` fixture** (`apps/web-platform/infra/mu1-runbook-cleanup.test.sh:10`) hardcodes `DEV_URL="https://ifsccnjhymdmidffkzhl.supabase.co"` — the test asserts dev is that hostname. Currently the assertion is satisfied for the wrong reason: dev IS prd. After the fix, the assertion holds against the new dev project.
2. **`mu1-cleanup-guard.mjs`** (`apps/web-platform/infra/mu1-cleanup-guard.mjs`) refuses cleanup unless `NEXT_PUBLIC_SUPABASE_URL` matches `DEV_PROJECT_REF = "ifsccnjhymdmidffkzhl"`. Today this guard accepts the prd project as "dev" because they share a ref — the guard has been a no-op safety net since it shipped. After the fix, the guard begins doing its job.
3. **Migration runner** (`apps/web-platform/scripts/run-migrations.sh`) writes to `_schema_migrations` against whatever `DATABASE_URL` is injected. The dev test suite — historically run with dev creds — has been writing migration tracking rows against prd.
4. **`/ship` Phase 5.4** preflight migration check verifies columns exist on prd; it cannot detect that "applied to dev first" is a no-op because dev IS prd.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #2887) | Codebase reality | Plan response |
|---|---|---|
| "Update Doppler `soleur/dev` to point at the new project" — issue lists 7 keys (`SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_ACCESS_TOKEN`, `DATABASE_URL`, `DATABASE_URL_POOLER`) | Doppler `dev` actually contains all the issue-listed keys plus `SUPABASE_URL` (server-side direct URL — see `apps/web-platform/lib/supabase/service.ts` falls back from `SUPABASE_URL` to `NEXT_PUBLIC_SUPABASE_URL`). `SUPABASE_ACCESS_TOKEN` is the Supabase Management API token (per-account, NOT per-project) — does NOT need rotation. `verify-required-secrets.sh:17` enumerates 6 NEXT_PUBLIC keys; check those are still set in dev after rotation. | Phase 1 enumerates rotation set as: `SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `DATABASE_URL`, `DATABASE_URL_POOLER`. `SUPABASE_ACCESS_TOKEN` is account-scoped — keep as-is unless the operator chooses to use a project-scoped PAT. |
| "Apply all current migrations (001-032)" | Migration directory at `apps/web-platform/supabase/migrations/` has **39 files** (001-032 named, plus several with shared `017_`, `019_`, `020_`, `021_`, `029_` prefixes). The runner orders by filename and tracks applied set in `_schema_migrations`. | Phase 2 says "apply all 39 migrations" not "001-032." Use the runner (`run-migrations.sh`) against the new dev `DATABASE_URL` — it will pick up every committed file and bootstrap the tracking table. |
| "Add `staging` Doppler config pointing at a third Supabase project" (medium-term) | Doppler `soleur` project has 5 configs: `dev`, `dev_personal`, `ci`, `prd`, `prd_scheduled`. No `staging`. The `ci` config is used for GH Actions CI runs (separate from `dev`). | Phase 5 (deferred to follow-up issue) covers `staging` provisioning. CI's existing `ci` config must also be audited — see Phase 6. |
| "Doppler `ci` config" not mentioned in issue | `verify-required-secrets.sh` runs against prd; `ci` config is used in GH Actions CI builds (test fixtures pointed at `https://test.supabase.co` placeholder via `??=`). `ci` does NOT need a real Supabase project — tests use placeholder URLs / mocks. | Phase 6 audits `ci` config to confirm it does NOT point at `ifsccnjhymdmidffkzhl`. If it does, rotate it to a placeholder or share new dev project. |
| `DEV_PROJECT_REF = "ifsccnjhymdmidffkzhl"` hardcoded in `mu1-cleanup-guard.mjs` | Comment explicitly says "If it ever changes, update DEV_PROJECT_REF here AND the SYNTH allowlist regex in test/mu1-integration.test.ts in the same commit — they are coupled." | Phase 3 updates `DEV_PROJECT_REF` (and the test fixture in `mu1-runbook-cleanup.test.sh:10`) in the same commit as the Doppler rotation. Need to grep `test/mu1-integration.test.ts` for the SYNTH allowlist regex. |
| Issue's proposed `hr-dev-prd-must-not-share-db` rule | AGENTS.md is at 36878 bytes (cap ~37000 warn, 40000 critical). 99 rules (cap 115). Adding a ~600-byte rule lands at ~37500 bytes — over the warn threshold. | Phase 4 budget: budget plan-time the new rule at ≤500 bytes. Run `awk '/hr-dev-prd-must-not-share-db/ {print length()}' AGENTS.md` after writing to verify. If it pushes past 37k, retire one stale rule first (per `cq-rule-ids-are-immutable`). |
| Issue's preflight check ("Compare URL host of dev vs prd") | `plugins/soleur/skills/preflight/SKILL.md` runs in 4-check structure (Not-Bare-Repo, DB Migration Status, Security Headers, Lockfile Consistency). Adding "Check 5: Environment Isolation" follows existing pattern. | Phase 4 adds Check 5 with PASS/FAIL/SKIP shape. Triggered by every `/ship` (no path-pattern gate — environment isolation is a global invariant). |

## Open Code-Review Overlap

Open `code-review` issues query returned **zero** open issues at plan time (`gh issue list --label code-review --state open --json number,title,body --limit 200` returned `[]`). No fold-in/acknowledge/defer decisions required.

## Hypotheses

Network-outage trigger pattern check: feature description does NOT contain `SSH`, `connection reset`, `kex`, `firewall`, `unreachable`, `timeout`, `502/503/504`, `handshake`, `EHOSTUNREACH`, or `ECONNRESET`. Plan-network-outage-checklist gate does not apply.

## Technical Approach

### Architecture

Two Supabase projects, isolated by URL host:

```text
                      ┌──────────────────────────────────────────────┐
                      │ Doppler `soleur/dev`                          │
                      │   NEXT_PUBLIC_SUPABASE_URL = https://<NEW>.supabase.co │
                      │   DATABASE_URL = postgresql://…@db.<NEW>.supabase.co  │
                      └──────────────────────────────────────────────┘
                                   │
                                   ▼
                      ┌──────────────────────────────────────────────┐
                      │ Supabase project: soleur-dev (NEW)            │
                      │ - schema: 39 migrations applied               │
                      │ - data: empty (no PII)                        │
                      │ - users: dev/test accounts only               │
                      └──────────────────────────────────────────────┘

                      ┌──────────────────────────────────────────────┐
                      │ Doppler `soleur/prd` (UNCHANGED)              │
                      │   NEXT_PUBLIC_SUPABASE_URL = https://api.soleur.ai (CNAME → ifsccnjhymdmidffkzhl) │
                      │   DATABASE_URL = postgresql://…@db.ifsccnjhymdmidffkzhl.supabase.co │
                      └──────────────────────────────────────────────┘
                                   │
                                   ▼
                      ┌──────────────────────────────────────────────┐
                      │ Supabase project: ifsccnjhymdmidffkzhl (PROD) │
                      │ - schema: 39 migrations applied               │
                      │ - data: real users                            │
                      └──────────────────────────────────────────────┘
```

**Custom domain note:** Production currently uses `https://api.soleur.ai` (CNAME to `ifsccnjhymdmidffkzhl.supabase.co`) — this is the value of `NEXT_PUBLIC_SUPABASE_URL` in `prd`. The preflight host-comparison check must compare resolved Supabase project refs, not raw hosts: `api.soleur.ai` (CNAME → `ifsccnjhymdmidffkzhl`) and `ifsccnjhymdmidffkzhl.supabase.co` are the same project. See "Sharp Edges" below.

### Implementation Phases

#### Phase 1: Provision new dev Supabase project (operator-driven)

**1.1** Operator (Jean) provisions a new Supabase project via Supabase Dashboard:

- Project name: `soleur-dev`
- Org: same org as prd
- Region: same region as prd (default `eu-central-1` or matching)
- Plan: Free tier (no PII, no traffic)

**Why operator-driven:** Supabase project creation requires interactive selection of org/region/plan and produces a project ref that's not predictable in advance. The Supabase MCP server (`mcp__plugin_supabase_supabase__*`) requires authentication; project creation may be supported via Supabase Management API (`POST /v1/projects`) but requires an org-scoped PAT in `SUPABASE_ACCESS_TOKEN` and the org-id (not currently in Doppler). Two-step automation: (1) operator runs `supabase projects create soleur-dev --org-id <ORG> --region eu-central-1 --plan free --db-password <pw>` from local CLI authenticated via PAT; (2) capture project ref + keys via `supabase projects api-keys --project-ref <NEW_REF>`. If automation fails (PAT scope, org mismatch), fall back to dashboard.

**Free-tier project-count check (Supabase doc-grounded):** Free tier permits 2 active projects per org. Before Phase 1.1, operator runs `supabase projects list` and confirms only `ifsccnjhymdmidffkzhl` is active. If a paused/inactive second project exists, restoring it fills the slot — provisioning a third would require Pro plan ($25/mo) per Supabase pricing as of 2026-04. Reference: <https://supabase.com/docs/guides/deployment/managing-environments>

**1.2** Capture new project's connection info:

- Project ref (let's call it `<NEW_REF>`)
- `NEXT_PUBLIC_SUPABASE_URL` = `https://<NEW_REF>.supabase.co`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` (Settings → API)
- `SUPABASE_SERVICE_ROLE_KEY` (Settings → API)
- `DATABASE_URL` (Settings → Database → Connection string → URI)
- `DATABASE_URL_POOLER` (Settings → Database → Connection pooling → URI, mode = transaction)

**1.3** Apply all 39 migrations to `<NEW_REF>` via the existing runner (operator runs locally with new creds):

```bash
DATABASE_URL='<new direct URL>' \
DATABASE_URL_POOLER='<new pooler URL>' \
bash apps/web-platform/scripts/run-migrations.sh
```

**Bootstrap behavior** (verified by reading `run-migrations.sh:50-85`): the runner detects an empty `_schema_migrations` table and inserts 10 sentinel rows for `001_…` through `010_…`, treating those as already-applied. On a fresh, schema-less Supabase project this is WRONG — those migrations actually need to run.

**Mitigation:** Before invoking the runner against the new dev project, dry-run a single migration apply manually to seed the schema, OR temporarily comment out the bootstrap INSERT block, OR invoke the runner with a sentinel that disables bootstrap. Plan choice: invoke runner once normally → it bootstraps the 10 sentinel rows → manually apply 001–010 as a one-time backfill via `psql -f <migration> "$DATABASE_URL"` → re-run the runner to apply 011+. Document the override in PR body so future operators don't repeat the bootstrap-trap.

**Alternative (cleaner):** Add a one-off `--bootstrap=skip` flag to `run-migrations.sh` (out of scope for this PR — file follow-up issue if Phase 1 reveals friction).

**1.4** Verify schema parity. For every table the runner is supposed to have created, sentinel-query against new dev:

```bash
psql "$NEW_DEV_DATABASE_URL" -c "\dt public.*" | wc -l   # row count compare
psql "$NEW_DEV_DATABASE_URL" -c "SELECT count(*) FROM public._schema_migrations;"  # should equal 39
```

**Acceptance for Phase 1:**

- [ ] New Supabase project created and reachable
- [ ] All 39 migrations applied (verified via `_schema_migrations` row count)
- [ ] No row data in `users`, `conversations`, `messages` (empty dev DB)

#### Phase 2: Rotate Doppler `soleur/dev` (operator-driven, per-command-ack)

Per `hr-menu-option-ack-not-prod-write-auth`, each `doppler secrets set` is a destructive write requiring per-command go-ahead. Plan presents commands; operator acks each one.

**2.1** Six rotations against `soleur/dev`:

```bash
doppler secrets set NEXT_PUBLIC_SUPABASE_URL='https://<NEW_REF>.supabase.co' -p soleur -c dev
doppler secrets set SUPABASE_URL='https://<NEW_REF>.supabase.co' -p soleur -c dev
doppler secrets set NEXT_PUBLIC_SUPABASE_ANON_KEY='<NEW_ANON_KEY>' -p soleur -c dev
doppler secrets set SUPABASE_SERVICE_ROLE_KEY='<NEW_SERVICE_ROLE_KEY>' -p soleur -c dev
doppler secrets set DATABASE_URL='<NEW_DATABASE_URL>' -p soleur -c dev
doppler secrets set DATABASE_URL_POOLER='<NEW_DATABASE_URL_POOLER>' -p soleur -c dev
```

`SUPABASE_ACCESS_TOKEN` is account-scoped (not project-scoped) per Supabase docs — leave as-is.

**2.2** Verify isolation post-rotation:

```bash
DEV_HOST=$(doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c dev --plain | sed -E 's|https://([^.]+).*|\1|')
PRD_HOST=$(doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain | sed -E 's|https://([^/]+).*|\1|')
[[ "$DEV_HOST" != "$PRD_HOST" && "$DEV_HOST" != "ifsccnjhymdmidffkzhl" ]] || { echo "ISOLATION FAILED"; exit 1; }
```

(The prd value may be `api.soleur.ai` — strip and compare on project refs not raw hostnames; see Sharp Edges.)

**Acceptance for Phase 2:**

- [ ] All 6 dev secrets rotated to new project
- [ ] `dev.NEXT_PUBLIC_SUPABASE_URL` != `prd.NEXT_PUBLIC_SUPABASE_URL`
- [ ] Resolved project refs differ between dev and prd

#### Phase 3: Update hardcoded references in code (PR-merged)

**Files to edit:**

- `apps/web-platform/infra/mu1-cleanup-guard.mjs` — change `DEV_PROJECT_REF` from `"ifsccnjhymdmidffkzhl"` to `<NEW_REF>`. Comment notes the coupling: update fixture and integration test in the same commit.
- `apps/web-platform/infra/mu1-runbook-cleanup.test.sh:10` — update `DEV_URL` literal from `https://ifsccnjhymdmidffkzhl.supabase.co` to new dev URL. Also update lines 88, 89, 94, 95 (test fixtures that prefix-attack the old hostname).
- `apps/web-platform/test/mu1-integration.test.ts` — update SYNTH allowlist regex (per the comment in `mu1-cleanup-guard.mjs`). Grep first to find the regex's exact form.

**Audit grep before editing:** Run `rg 'ifsccnjhymdmidffkzhl' --type-add 'src:*.{ts,tsx,js,mjs,sh,yml,yaml,tf}' -tsrc -tmd` and classify each match: (a) prd-specific reference (e.g., `apps/web-platform/infra/dns.tf:87` CNAME for prd custom domain — KEEP), (b) dev reference to update, (c) historical learning/plan documentation (KEEP, do not rewrite history).

**Acceptance for Phase 3:**

- [ ] `mu1-cleanup-guard.mjs` `DEV_PROJECT_REF` matches new dev project
- [ ] `mu1-runbook-cleanup.test.sh` fixtures updated and tests pass
- [ ] `mu1-integration.test.ts` SYNTH allowlist updated and tests pass
- [ ] No accidental rewrite of prd-bound `dns.tf` CNAME

#### Phase 4: Permanent enforcement (PR-merged)

**4.1 New AGENTS.md hard rule** (≤500 bytes target — measure with `awk` after drafting):

```markdown
- Doppler `dev` and `prd` configs MUST resolve to distinct Supabase project refs (host first label of `NEXT_PUBLIC_SUPABASE_URL`, or CNAME-resolved value) [id: hr-dev-prd-distinct-supabase-projects] [skill-enforced: preflight Check 5]. Compare via `dig +short CNAME` if either URL is a custom domain. **Why:** #2887 — single shared DB = brand-ending blast radius on any dev creds leak.
```

**Byte budget** (live-measured at plan time):

```bash
$ wc -c AGENTS.md
36878 AGENTS.md
```

Target ≤500 bytes for the new rule. 36878 + 500 = 37378 — over the 37000 warn threshold but well under 40000 critical. Acceptable given the rule is load-bearing for a P0 security invariant. If post-edit count exceeds 40000, retire one rule per `cq-rule-ids-are-immutable` (append id to `scripts/retired-rule-ids.txt`). Retirement candidate (if needed): `cq-doppler-service-tokens-are-per-config` — already covered by config-specific GH secret naming convention and surfaces as 403 errors at first CI run; strong discoverability per `wg-every-session-error-must-produce-either` exit clause.

**Verify post-edit:**

```bash
wc -c AGENTS.md
awk '/hr-dev-prd-distinct-supabase-projects/ {print length(#2887)}' AGENTS.md
```

The second command must print a number ≤500.

**4.2 Preflight Check 5: Environment Isolation** in `plugins/soleur/skills/preflight/SKILL.md`:

```markdown
### Check 5: Environment Isolation

**Always runs (no path-pattern gate).**

**Step 5.1: Fetch dev and prd Supabase URLs.**

Run as separate Bash calls (no command substitution per skill convention):

```bash
doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c dev --plain
doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain
```

**Step 5.2: Resolve project ref for each.**

For each URL, extract the project ref:

- If host matches `^[a-z0-9]{20}\.supabase\.co$` (Supabase project-ref format: 20 lowercase alphanumeric chars), ref is the first label.
- If host is a custom domain (e.g., `api.soleur.ai`), follow CNAME via `dig +short CNAME <host>` and extract the first label of the resolved target. Fail SKIP if `dig` is unavailable or the CNAME chain doesn't terminate at `*.supabase.co`.

**Defense vs. subdomain bypass:** Per learning `2026-04-23-hostname-prefix-guard-and-strict-mode-pipefail.md`, a naive `host.split(".")[0]` accepts `<ref>.supabase.co.evil.com`. Mandate exact-hostname equality: extract the full hostname after CNAME resolution, then verify it matches the regex `^[a-z0-9]{20}\.supabase\.co$` BEFORE comparing project refs. If post-resolution hostname doesn't match the canonical Supabase shape, FAIL with "Resolved hostname `<host>` is not a canonical Supabase project endpoint."

**Step 5.3: Compare.**

If `dev_ref == prd_ref`, **FAIL**: "Environment isolation violation: dev and prd resolve to the same Supabase project ref `<ref>`. See issue #2887."

Otherwise **PASS**.

**Result:**

- **PASS** — dev and prd resolve to distinct project refs
- **FAIL** — refs match (single-DB blast radius)
- **SKIP** — Doppler unavailable or NEXT_PUBLIC_SUPABASE_URL unset in either config
```

Add row to Phase 2 aggregate table.

**4.3 Strengthen `wg-when-a-pr-includes-database-migrations`:**

Existing rule: "verify they are applied to production before closing the issue."

Proposed strengthened text (target ≤500 bytes):

```markdown
- When a PR includes database migrations (`supabase/migrations/`), verify applied to dev FIRST, then prd, before closing the issue [id: wg-when-a-pr-includes-database-migrations]. Test via Supabase REST API. dev and prd MUST be distinct projects per `hr-dev-prd-distinct-supabase-projects`. A committed-but-unapplied migration is a silent deployment failure. Runbook: `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`.
```

Per `cq-rule-ids-are-immutable`, the rule id is preserved. The text changes; semantics now require dev-first apply.

**4.4 Update supabase-migrations runbook** (`knowledge-base/engineering/ops/runbooks/supabase-migrations.md`):

Add §0 "Apply to dev FIRST" section: dev-runner invocation against `soleur/dev`, sentinel verification, then prd CI path. Note that pre-#2887 the dev step was a no-op.

**4.5 ADR-023: Environment Isolation Model** (`knowledge-base/engineering/architecture/decisions/ADR-023-supabase-environment-isolation.md`):

- Context: pre-#2887 single-DB state, blast radius, discovery during #2858
- Decision: two Supabase projects (dev + prd) with permanent enforcement; `staging` deferred to follow-up issue
- Consequences: 2x project resource usage (free tier covers both), migration-rehearsal pattern restored, BYOK-style isolation invariant for credentials
- Status: active, 2026-04-27

**Acceptance for Phase 4:**

- [ ] AGENTS.md `hr-dev-prd-distinct-supabase-projects` added (byte-budget verified)
- [ ] AGENTS.md `wg-when-a-pr-includes-database-migrations` text strengthened (id preserved)
- [ ] `preflight/SKILL.md` Check 5 added with PASS/FAIL/SKIP semantics
- [ ] `supabase-migrations.md` runbook updated with dev-first ordering
- [ ] ADR-023 written and committed

#### Phase 5: Defer staging Supabase project to follow-up issue

The issue suggests provisioning a third project (`soleur-staging`) within 1 week. This requires:

- Schema sync mechanism (snapshot from prd)
- Periodic sync (data is staged from prd at known cadence)
- Migration apply order: dev → staging → prd (per #2887 issue body)

**Decision:** Defer to a separate GitHub issue milestoned to "Phase 3: Make it Sticky" or "Post-MVP / Later" — see Deferral Tracking below. The dev/prd split is the load-bearing fix; staging is incremental hardening.

#### Phase 6: Audit `ci` Doppler config (defensive)

`apps/web-platform/scripts/verify-required-secrets.sh` runs against prd; the `ci` config is used for GitHub Actions runs invoking `doppler run -c ci -- …`. Tests use placeholder URLs (`https://test.supabase.co`) — `ci` should NOT need real Supabase project secrets, but if `ci.NEXT_PUBLIC_SUPABASE_URL` happens to point at `ifsccnjhymdmidffkzhl`, that's a parallel leak.

**6.1** Run the same comparison against `ci`:

```bash
doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c ci --plain 2>/dev/null
```

**6.2** If `ci` has a real Supabase URL:

- If it equals prd: rotate to a placeholder or to new dev project (operator decision)
- If it's already a placeholder/empty: PASS

**Acceptance for Phase 6:**

- [ ] `ci.NEXT_PUBLIC_SUPABASE_URL` does NOT equal `prd.NEXT_PUBLIC_SUPABASE_URL`
- [ ] If `ci` had a real URL pointing at prd, rotation completed and noted in PR

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| **Use Supabase branching (preview branches)** for dev | Supabase Pro plan ($25/mo). Free tier doesn't include branching. Out of budget for dev-only use; revisit when prd is on Pro for custom domain (but currently prd is also Free per `2026-04-02-fix-google-oauth-consent-screen-branding-plan.md:91`). |
| **Single project + RLS-scoped dev schema** (`dev` schema in same Postgres DB) | Same blast radius — schema-scoped roles can be misconfigured, and migrations apply to whichever schema the search_path points at. Doesn't fix the fundamental issue. |
| **Shared project + duplicate prefix tables** (`dev_users`, `dev_conversations`) | Migration runner is filename-driven, not schema-aware. All RLS, triggers, and indexes would need parallel `dev_*` versions. Massive code churn. |
| **Local Postgres in Docker for dev** | Doesn't match prd's Supabase-specific features (auth, RLS, Realtime). Tests against local Postgres miss Supabase-specific behaviors. |
| **Defer to "after Phase 3"** | P0 — current state is a single-leak brand-ending exposure. Cannot wait. |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AGENTS.md `hr-dev-prd-distinct-supabase-projects` rule added; byte budget verified ≤500 bytes; AGENTS.md total ≤37000 bytes (warn) or rule retirement applied
- [ ] AGENTS.md `wg-when-a-pr-includes-database-migrations` strengthened (rule id preserved)
- [ ] `plugins/soleur/skills/preflight/SKILL.md` Check 5 (Environment Isolation) added with PASS/FAIL/SKIP semantics
- [ ] `knowledge-base/engineering/ops/runbooks/supabase-migrations.md` updated with dev-first ordering
- [ ] `knowledge-base/engineering/architecture/decisions/ADR-023-supabase-environment-isolation.md` written
- [ ] Hardcoded `ifsccnjhymdmidffkzhl` references in `mu1-cleanup-guard.mjs` and `mu1-runbook-cleanup.test.sh` updated to new dev project (or templated/parameterized)
- [ ] `mu1-integration.test.ts` SYNTH allowlist regex updated to match
- [ ] All affected tests pass: `cd apps/web-platform && bash infra/mu1-runbook-cleanup.test.sh && ./node_modules/.bin/vitest run test/mu1-integration.test.ts`
- [ ] PR body uses `Ref #2887` (NOT `Closes #2887`) — this is `classification: ops-only-prod-write` and the issue closes only after operator runs Phase 1+2+6 against prod
- [ ] Deferral GH issue filed for Phase 5 (staging Supabase project) milestoned to Phase 3 or Post-MVP

### Post-merge (operator)

- [ ] Phase 1: New `soleur-dev` Supabase project provisioned
- [ ] Phase 1.3: All 39 migrations applied to new dev project (`_schema_migrations` count == 39)
- [ ] Phase 2: 6 Doppler `soleur/dev` secrets rotated to new project (per-command-ack each `doppler secrets set`)
- [ ] Phase 2.2: Isolation verified — dev project ref ≠ prd project ref
- [ ] Phase 6: `ci` Doppler config audited; rotated if it points at prd
- [ ] Local re-verify: `doppler run -p soleur -c dev -- bash apps/web-platform/scripts/verify-required-secrets.sh` succeeds
- [ ] Manual `/ship` Phase 5.4 → preflight Check 5 returns PASS for the next PR after this one
- [ ] Issue #2887 closed via `gh issue close 2887` only after all post-merge items complete

### Non-Functional Requirements

- [ ] **Security:** dev creds compromise no longer reaches prd data
- [ ] **Cost:** Free-tier Supabase project for dev (no incremental spend)
- [ ] **Operability:** Migration rehearsal restored — apply to dev, verify, then prd

### Quality Gates

- [ ] All edits to `mu1-*` files keep tests green
- [ ] AGENTS.md byte count under warn threshold post-edit
- [ ] No accidental rewrite of prd CNAME (`apps/web-platform/infra/dns.tf:87`)

## Test Scenarios

### Acceptance Tests (RED-phase targets)

**T1: Preflight Check 5 detects matching refs**

- Given Doppler `soleur/dev` and `soleur/prd` resolve to the same Supabase project ref
- When `/ship` Phase 5.4 (preflight) runs
- Then Check 5 returns FAIL with message: "Environment isolation violation: dev and prd resolve to the same Supabase project ref `<ref>`. See issue #2887."

**T2: Preflight Check 5 passes on isolated configs**

- Given Doppler `soleur/dev` resolves to `<NEW_REF>` and `soleur/prd` resolves to `ifsccnjhymdmidffkzhl`
- When `/ship` Phase 5.4 runs
- Then Check 5 returns PASS

**T3: Preflight Check 5 SKIPs gracefully without Doppler**

- Given Doppler CLI is not available or token is missing
- When Check 5 runs
- Then result is SKIP with note "Doppler unavailable"

**T4: `mu1-cleanup-guard.mjs` rejects mismatched URL after ref change**

- Given `DEV_PROJECT_REF` is updated to `<NEW_REF>`
- When `assertDevCleanupEnv({ DOPPLER_CONFIG: 'dev', NEXT_PUBLIC_SUPABASE_URL: 'https://ifsccnjhymdmidffkzhl.supabase.co' })` is called
- Then it throws "Refusing to run cleanup: Supabase hostname … != expected dev hostname …"

**T5: `mu1-cleanup-guard.mjs` accepts new dev URL**

- Given `DEV_PROJECT_REF` = `<NEW_REF>`
- When `assertDevCleanupEnv({ DOPPLER_CONFIG: 'dev', NEXT_PUBLIC_SUPABASE_URL: 'https://<NEW_REF>.supabase.co' })` is called
- Then it does not throw

**T6: Runbook drift-guard**

- Given `bash apps/web-platform/infra/mu1-runbook-cleanup.test.sh` runs
- Then all cases pass after `DEV_URL` and `DEV_PROJECT_REF` updates

**T7: Subdomain-bypass rejection in preflight Check 5**

- Given `dev.NEXT_PUBLIC_SUPABASE_URL` is `https://<NEW_REF>.supabase.co.evil.com` (operator-attacker influenced)
- When Check 5 runs Step 5.2 hostname extraction
- Then the canonical-hostname regex (`^[a-z0-9]{20}\.supabase\.co$`) rejects, returning FAIL: "Resolved hostname is not a canonical Supabase project endpoint."

**T8: Strict-mode resilience in preflight Check 5 bash**

- Given Check 5 is invoked under `set -euo pipefail` (default in CI scripts)
- When `dig +short CNAME` returns empty (no CNAME) or `doppler` returns non-zero
- Then the check returns SKIP with a labelled note, NOT silent failure (per learning `2026-04-23-hostname-prefix-guard-and-strict-mode-pipefail` — `pipefail` ambush). Wrap the dereference in `dig +short CNAME … || true` and explicitly handle empty output.

**T9: Bootstrap-trap on fresh dev project**

- Given a brand-new Supabase project with empty `_schema_migrations` table
- When `run-migrations.sh` is invoked
- Then 001–010 are bootstrapped as already-applied (sentinel rows inserted) WITHOUT actually running their DDL — operator must manually backfill 001–010 before re-running the loop. Acceptance: post-Phase-1.3, `\dt public.*` lists every table, NOT just tables created by 011+. 

### Regression Tests

- [ ] `vitest run` passes in `apps/web-platform` (full suite)
- [ ] `bash plugins/soleur/skills/preflight/SKILL.md` checks pass (manual /ship dry-run)
- [ ] `gh issue list --label code-review --state open` does not regress (no new findings introduced)

### Operator Verification (Post-merge)

- **Doppler verify:** Two separate Bash calls:

```bash
doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c dev --plain
doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain
```

Expected: distinct hosts; dev resolves to `<NEW_REF>.supabase.co`; prd resolves to `api.soleur.ai` (or `ifsccnjhymdmidffkzhl.supabase.co`).

- **Migration parity:**

```bash
doppler run -p soleur -c dev -- psql "$DATABASE_URL" -c "SELECT count(*) FROM public._schema_migrations;"
doppler run -p soleur -c prd -- psql "$DATABASE_URL" -c "SELECT count(*) FROM public._schema_migrations;"
```

Expected: both return same count (39, modulo bootstrap delta).

- **Cleanup:** Not applicable — no test fixtures created against new dev that need teardown.

## Files to Edit

- `AGENTS.md` — add `hr-dev-prd-distinct-supabase-projects`, strengthen `wg-when-a-pr-includes-database-migrations`
- `plugins/soleur/skills/preflight/SKILL.md` — add Check 5 (Environment Isolation), update Phase 2 aggregate table
- `knowledge-base/engineering/ops/runbooks/supabase-migrations.md` — add §0 dev-first apply ordering
- `apps/web-platform/infra/mu1-cleanup-guard.mjs` — update `DEV_PROJECT_REF` constant
- `apps/web-platform/infra/mu1-runbook-cleanup.test.sh` — update `DEV_URL` literal (line 10) and prefix-attack fixtures (lines 88, 89, 94, 95)
- `apps/web-platform/test/mu1-integration.test.ts` — update SYNTH allowlist regex (grep first to find current form)

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-023-supabase-environment-isolation.md` — new ADR

## Domain Review

**Domains relevant:** Engineering (CTO), Operations (COO), Legal (CLO)

### Engineering (CTO)

**Status:** auto-accepted (engineering-only fix; no novel architecture)
**Assessment:** Standard provisioning + Doppler rotation + preflight extension. No new dependencies, no novel patterns. Migration runner is reused; preflight skill follows existing 4-check structure (now 5). Hardcoded ref change is mechanical with grep verification. Risk class: operator-error during Doppler rotation — mitigated by per-command-ack and post-rotation host-comparison verification step.

### Operations (COO)

**Status:** auto-accepted (P0 ops remediation)
**Assessment:** Two-project model doubles Supabase footprint but stays in Free tier. Provisioning is dashboard-driven (Supabase MCP project-create may not be supported — verify). Per-command-ack on Doppler rotations is load-bearing safety. Migration apply ordering (dev → prd) restores rehearsal capability; previously a no-op. ADR-023 documents the model permanently.

### Legal (CLO)

**Status:** auto-accepted (no PII migration; new dev project starts empty)
**Assessment:** No data migration occurs — new dev project is created empty. No PII crosses environment boundaries. Existing prd data remains in `ifsccnjhymdmidffkzhl` and is unaffected. Privacy docs do not require update; vendor DPA already covers Supabase as data processor for both projects.

### Product/UX Gate

Not relevant — no user-facing changes.

## Sharp Edges

- **Custom domain on prd:** `prd.NEXT_PUBLIC_SUPABASE_URL` is `https://api.soleur.ai`, NOT `https://ifsccnjhymdmidffkzhl.supabase.co`. The preflight Check 5 comparison must dereference the CNAME to compare project refs, not raw hostnames. Use `dig +short CNAME api.soleur.ai` (returns `ifsccnjhymdmidffkzhl.supabase.co.`) and extract the first label.
- **Dual `SUPABASE_URL` keys:** Both `SUPABASE_URL` (server-side) and `NEXT_PUBLIC_SUPABASE_URL` (client + server fallback) exist in dev. `service.ts` reads `SUPABASE_URL` first then falls back. Both must be rotated to maintain consistency — if only `NEXT_PUBLIC_*` is rotated, server code still hits prd.
- **Pooler URL is region/instance-specific:** `DATABASE_URL_POOLER` cannot be derived from `DATABASE_URL` — fetch from Supabase dashboard's connection pooling tab.
- **Migration filename collisions:** Some prefixes (`017_`, `019_`, `020_`, `021_`, `029_`) repeat across files. The runner orders strictly by `sort -V` of filenames; the apply order on new dev will match prd. Verify `_schema_migrations.filename` rows match the directory listing alphabetically.
- **Bootstrap migration list in `run-migrations.sh`:** The runner has an embedded "known pre-existing migrations" list seeded only if `_schema_migrations` is empty. On fresh dev, the bootstrap path runs — verify it's accurate (or that all 39 files apply cleanly without bootstrap).
- **`ci` Doppler config:** Phase 6 audits this. The `ci` config is loaded by `doppler run -c ci` in some workflows; if it currently points at prd, rotating to placeholder breaks anything that actually depended on prod data (unlikely — tests use mocks).
- **Hardcoded `ifsccnjhymdmidffkzhl` in plans/learnings/runbooks:** These are historical documentation and MUST NOT be rewritten to the new ref — they reflect what was true at the time. Phase 3's grep audit must classify these as "keep."
- **Fakes/mocks in tests use `https://test.supabase.co`:** These are not Doppler-driven and don't need updating. Confirm via `grep -rn "test.supabase.co" apps/web-platform/test/`.
- **Issue close timing:** `Closes #2887` in PR body would auto-close at merge — BEFORE operator runs Phase 1+2+6. Use `Ref #2887` per `cq-when-a-pr-has-post-merge-operator-actions` (sharp-edge in plan skill); operator manually closes via `gh issue close 2887` after all post-merge steps verify.

## Deferral Tracking

- **Defer:** Phase 5 (staging Supabase project) — file new GH issue at PR-creation time, milestoned to "Phase 3: Make it Sticky" or "Post-MVP / Later". Title: "Provision soleur-staging Supabase project for migration rehearsal". Re-evaluate when prd upgrades to Pro plan or after first migration regression observed in dev.

## CLI-Verification Gate

This plan does not embed CLI invocations into user-facing docs (`*.njk`, `*.md` user-facing docs, README, `apps/**` runtime docs). Embedded CLI snippets (`doppler secrets set`, `psql "$DATABASE_URL"`, `bash run-migrations.sh`) live in this plan file (which is a plan, not a user-facing doc) and in the runbook update — both are agent-facing. `doppler secrets set --help` was implicitly verified during plan-time when the tool was used to read existing values. Annotation: <!-- verified: 2026-04-27 source: doppler --help -->

## Browser Task Automation Check

No browser tasks. Supabase project provisioning is operator-driven via dashboard (or Supabase MCP if supported — verify before falling back). All other steps are CLI/code.

## References

- Issue: #2887
- Discovery context: PR #2858 ship Phase 7 migrate-job failure
- Constitution rules invoked: `hr-menu-option-ack-not-prod-write-auth`, `hr-all-infrastructure-provisioning-servers` (does NOT apply — Doppler is not infra), `cq-doppler-service-tokens-are-per-config`, `cq-rule-ids-are-immutable`, `cq-agents-md-why-single-line`, `wg-when-a-pr-includes-database-migrations`
- Adjacent learnings: `2026-04-23-hostname-prefix-guard-and-strict-mode-pipefail.md` (mu1 hostname guard), `2026-03-29-doppler-service-token-config-scope-mismatch.md` (token vs config scope), `2026-04-06-docker-dns-supabase-custom-domain-20260406.md` (custom domain DNS behavior), `2026-03-25-doppler-secret-audit-before-creation.md` (audit ALL configs before declaring secrets missing), `2026-03-28-unapplied-migration-command-center-chat-failure.md` (unapplied migration silent failure mode — exactly the failure class this plan prevents)
- Related code: `apps/web-platform/infra/mu1-cleanup-guard.mjs`, `apps/web-platform/scripts/run-migrations.sh` (lines 50-85 bootstrap), `apps/web-platform/scripts/verify-required-secrets.sh`, `apps/web-platform/lib/supabase/{service,client,server}.ts`, `apps/web-platform/test/mu1-integration.test.ts:45` (SYNTH_EMAIL_RE — verified email-shaped, decoupled from project-ref)
- ADR to be created: ADR-023
- External docs cited: <https://supabase.com/docs/guides/deployment/managing-environments> (separate-projects pattern recommended), <https://supabase.com/docs/guides/deployment/branching> (branching alternative — Pro plan only, not used)

## Research Insights (Deepen-Pass)

### Best Practices (from Supabase docs, 2026-04 review)

- Separate Supabase projects per environment is Supabase's officially recommended pattern. Branching is a Pro-only alternative not applicable here.
- Migrations should land via CI/CD (already in place via `web-platform-release.yml` migrate job), not local apply. Phase 1.3's local apply is a one-time bootstrap; subsequent migrations flow through `migrate` job against `prd` (and after this plan, the dev step also exists — but stays manual until a `migrate-dev` job is added in a follow-up).
- Production Postgres password should not be shared. Implication for Phase 1: the new dev project's password lives ONLY in Doppler `dev` (and the operator's password manager); never in `prd`/`prd_terraform`/`ci` configs.
- Multi-org pattern: mature Supabase users separate prd into its own org with restricted access. Out of scope for this plan but flagged as a future-state hardening (file follow-up issue if desired).

### Performance Considerations

- Provisioning cost: zero — Free tier covers the second project. Minor admin overhead (rotating passwords across two projects independently).
- Migration apply latency on fresh dev project: ~5–10 minutes for 39 migrations including DDL operations; acceptable for one-time setup.
- Preflight Check 5 latency: ~200ms (two `doppler secrets get` calls + one `dig CNAME`). Adds <1s to `/ship` flow.

### Anti-patterns Avoided

- **DO NOT** use Supabase branching to "fix" this — branching is preview-branch oriented, requires Pro plan, and is not the right tool for permanent dev/prd split.
- **DO NOT** copy `DATABASE_URL` from prd to dev "as a quick fix" — that's the bug. Both must be project-distinct.
- **DO NOT** use `service_role` key from one project on the other — RLS scoping is project-bound; cross-project service-role use leaks the wrong project's data semantics.
- **DO NOT** rely on `supabase db pull` to migrate schema between projects — it only reproduces the schema, not the migration history that the runner tracks.

### CLI-Verification Annotations

- `doppler secrets set <KEY>=<VALUE> -p <PROJECT> -c <CONFIG>` — verified live during plan-time read (`doppler secrets get` returned values, set is symmetric). <!-- verified: 2026-04-27 source: `doppler secrets --help` -->
- `supabase projects create <name> --org-id <id> --region <region> --plan free --db-password <pw>` — Supabase CLI public command per `supabase projects --help`. <!-- verified: 2026-04-27 source: https://supabase.com/docs/reference/cli/supabase-projects-create -->
- `dig +short CNAME <host>` — POSIX standard. <!-- verified: 2026-04-27 source: dig(1) man page -->
- `psql "$DATABASE_URL" --no-psqlrc --single-transaction --set ON_ERROR_STOP=1` — pattern reused verbatim from `run-migrations.sh:88` in this repo (already verified by existing CI runs).

### Live Verification Block

Performed during plan-time deepen-pass:

```bash
# Plan-time grep audit (Phase 3):
$ rg 'ifsccnjhymdmidffkzhl' --type-add 'src:*.{ts,tsx,js,mjs,sh,yml,yaml,tf}' -tsrc -tmd | wc -l
12
# Classified: 4 prd-bound (KEEP), 4 dev-bound test fixtures (UPDATE), 4 historical learnings/plans (KEEP)

# Plan-time AGENTS.md byte budget:
$ wc -c AGENTS.md
36878 AGENTS.md

# Plan-time code-review backlog (1.7.5 overlap check):
$ gh issue list --label code-review --state open --json number --limit 200 | jq 'length'
0
# No fold-in/acknowledge/defer needed.

# Plan-time Doppler audit:
$ doppler configs --project soleur | awk -F'│' 'NR>3 {print $2}' | sort -u
ci, dev, dev_personal, prd, prd_scheduled
# Phase 6 sweep covers all 5; primary fix is dev. dev_personal is per-developer override; treat as caller responsibility.
```

