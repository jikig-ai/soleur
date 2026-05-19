---
title: Tasks — Daily Priorities multi-source (PR-H)
date: 2026-05-19
status: tasks
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-05-19-feat-daily-priorities-multi-source-pr-h-plan.md
spec: knowledge-base/project/specs/feat-daily-priorities-multi-source/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-19-daily-priorities-multi-source-brainstorm.md
branch: feat-daily-priorities-multi-source
draft_pr: "#4066"
---

# Tasks — Daily Priorities multi-source (PR-H)

Derived from finalized plan v2 (post plan-review). Six phases; commits flexible within phase; merge atomic. Pre-merge ACs (15) + post-merge operator ACs (5) in the plan.

## Phase 1 — Migration 051 + redaction extension

- [x] **1.1** Create `apps/web-platform/supabase/migrations/051_multi_source_dedup.sql`:
  - [x] 1.1.1 ALTER `messages` ADD `source_ref text` (nullable).
  - [x] 1.1.2 CREATE UNIQUE INDEX `messages_active_draft_dedup_idx ON messages (user_id, source, source_ref) WHERE status='draft' AND source_ref IS NOT NULL`.
  - [x] 1.1.3 CREATE TABLE `audit_github_token_use(founder_id, installation_id, repo_full_name, endpoint, ts, response_status)` with RLS policies.
  - [x] 1.1.4 CREATE FUNCTION `record_github_token_use(...)` `SECURITY DEFINER` with `SET search_path = public, pg_temp` (per `cq-pg-security-definer-search-path-pin-pg-temp`).
  - [x] 1.1.5 CREATE TABLE `processed_github_events(delivery_id text PRIMARY KEY, received_at timestamptz DEFAULT now())`.
- [x] **1.2** Write `apps/web-platform/supabase/migrations/051_multi_source_dedup.test.ts`:
  - [x] 1.2.1 Assert new columns + partial-unique index.
  - [x] 1.2.2 Assert audit table + RLS policies.
  - [x] 1.2.3 Assert RPC `pg_proc.proconfig` contains `search_path=public, pg_temp`.
  - [x] 1.2.4 Assert `processed_github_events` table + primary key.
- [x] **1.3** Edit `apps/web-platform/lib/safety/redaction-allowlist.ts`:
  - [x] 1.3.1 Add NEW export `redactGithubSourcedText(s: string, opts?: { source?: 'pr_title'|'issue_body'|'cve_description' }): string`.
  - [x] 1.3.2 NO changes to existing exports (Stripe/CFO paths unchanged — R2 mitigation).
- [x] **1.4** Edit `apps/web-platform/lib/safety/redaction-allowlist.test.ts`:
  - [x] 1.4.1 Golden fixtures per `source` variant.
  - [x] 1.4.2 Three invariants (max-input bound, alphabet-aware UUID match, no `/g`+`.test()` gate per learning `2026-04-17-pii-regex-scrubber-three-invariants`).
  - [x] 1.4.3 Existing Stripe/CFO tests still pass unmodified.
- [x] **1.5** Edit `apps/web-platform/lib/messages/tiers.ts`:
  - [x] 1.5.1 Add `MESSAGE_SOURCE_GITHUB = 'github'`, `MESSAGE_SOURCE_KB_DRIFT = 'kb-drift'`, `MESSAGE_OWNING_DOMAIN_KNOWLEDGE = 'knowledge'`.
- [ ] **1.6** Commit & push Phase 1.

**Exit gate:** `bun test apps/web-platform/test/server/migration-051*` + `bun test apps/web-platform/lib/safety/redaction-allowlist.test.ts` green.

## Phase 2 — Operator preflight + IaC apply

- [ ] **2.1** File the deferred-automation issue:
  - [ ] 2.1.1 `gh issue create --title "chore: track GitHub App creation Terraform provider availability" --label deferred-scope-out --milestone "Post-MVP / Later"`. Body: "Single manual gate per `hr-never-label-any-step-as-manual-without`. Revisit when `integrations/github` Terraform provider supports App creation."
- [ ] **2.2** Operator creates GitHub App `Soleur-Concierge` at github.com/settings/apps/new per `knowledge-base/operations/runbooks/github-app-provisioning.md`:
  - [ ] 2.2.1 Permissions: `pull_requests:read`, `issues:read`, `metadata:read`, `actions:read`, `repository_advisories:read`, `secret_scanning_alerts:read`.
  - [ ] 2.2.2 Events: `pull_request`, `workflow_run`, `issues`, `repository_advisory`, `secret_scanning_alert`.
  - [ ] 2.2.3 Webhook URL: `https://soleur.ai/api/webhooks/github`.
  - [ ] 2.2.4 Installable: founder's own account/orgs only.
  - [ ] 2.2.5 Capture App ID + PEM (one-shot download) + Client ID + Client Secret.
- [ ] **2.3** Create `knowledge-base/operations/runbooks/github-app-provisioning.md` — canonical operator runbook for the manual gate; references the deferred-automation issue from 2.1.
- [ ] **2.4** Create `apps/web-platform/infra/github-app.tf`:
  - [ ] 2.4.1 5 `doppler_secret` resources in `prd` (App ID, PEM, Client ID, Client Secret, webhook secret).
  - [ ] 2.4.2 1 `random_id` resource for webhook secret (Soleur-generated).
  - [ ] 2.4.3 `lifecycle.ignore_changes = [value]` on the 4 operator-supplied; NO ignore on the `random_id`-derived.
  - [ ] 2.4.4 `lifecycle.precondition` blocks asserting these secrets are NOT also in `dev` config.
- [ ] **2.5** Create `apps/web-platform/infra/kb-drift.tf`:
  - [ ] 2.5.1 `doppler_secret` `KB_DRIFT_INGEST_SIGNING_KEY` in NEW `prd_kb_drift_walker` config.
  - [ ] 2.5.2 `random_id` for the signing key.
  - [ ] 2.5.3 `github_actions_secret` publishing the Doppler service-token as repo Actions secret `DOPPLER_TOKEN_KB_DRIFT`.
- [ ] **2.6** Create `apps/web-platform/infra/alerts-github-webhook.tf`:
  - [ ] 2.6.1 3 `betteruptime_*` resources for webhook 4xx/5xx, signature-failure pager, GitHub API 429 sustained.
  - [ ] 2.6.2 All gated `count = var.betterstack_paid_tier ? 1 : 0`.
- [ ] **2.7** Edit `apps/web-platform/infra/main.tf` — add `github = { source = "integrations/github", version = "~> 6.0" }` to `required_providers`.
- [ ] **2.8** Edit `apps/web-platform/infra/variables.tf` — append 4 `sensitive=true` GitHub App vars + `github_actions_token`.
- [ ] **2.9** Edit `apps/web-platform/infra/outputs.tf` — surface `github_app_webhook_url`.
- [ ] **2.10** Pre-apply gate: confirm `var.betterstack_paid_tier` current value in `prd_terraform`.
- [ ] **2.11** Run canonical Terraform apply triplet (per learning `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan`):
  - [ ] 2.11.1 `export AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` via `doppler secrets get -p soleur -c prd_terraform --plain`.
  - [ ] 2.11.2 `terraform init -input=false`.
  - [ ] 2.11.3 `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -out=plan.tfplan` + review.
  - [ ] 2.11.4 `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply plan.tfplan`.
- [ ] **2.12** Operator copies the `random_id` webhook-secret output INTO the GitHub App configuration (closes the loop).
- [ ] **2.13** Verify Phase 2 deliverables:
  - [ ] 2.13.1 6 Doppler keys present in `prd` + `prd_kb_drift_walker`.
  - [ ] 2.13.2 `gh secret list --repo jikig-ai/soleur | grep DOPPLER_TOKEN_KB_DRIFT` returns 1 row.
  - [ ] 2.13.3 `terraform plan` returns clean diff.
- [ ] **2.14** Commit & push Phase 2.

**Exit gate:** all Doppler keys + GitHub Actions secret + Terraform resources in place; clean `terraform plan`.

## Phase 3 — GitHub webhook route + signature verification + dedup + scope-grant gate + ADRs

- [ ] **3.1** Edit `apps/web-platform/package.json` + root `package.json`: add `@octokit/app@^15`, `@octokit/auth-app@^7`. Verify peer-deps via `npm view <pkg> peerDependencies` (per `cq-before-pushing-package-json-changes`).
- [ ] **3.2** Edit `apps/web-platform/server/scope-grants/grant-kinds.ts`: add 5 new scope-grant kinds — `engineering.pr_review_pending`, `engineering.ci_failed`, `triage.p0p1_issue`, `security.cve_alert`, `knowledge.kb_drift`.
- [ ] **3.3** Create `apps/web-platform/server/github/app-client.ts`:
  - [ ] 3.3.1 Per-request factory `createGitHubAppClient(installationId): Promise<Octokit>` using `@octokit/auth-app` v7.
  - [ ] 3.3.2 NO manual token cache (auth strategy auto-refreshes at `expires_at - 60s` per Kieran P1).
  - [ ] 3.3.3 NO module-scope singleton (per learning `2026-05-12` + vercel/next.js#65350); per-request instantiation only.
  - [ ] 3.3.4 Explicit comment naming the threat (cross-tenant token leak across worker boundaries).
- [ ] **3.4** Create `apps/web-platform/server/github/app-client.test.ts`:
  - [ ] 3.4.1 Per-request semantics (fresh App per call).
  - [ ] 3.4.2 NO module-scope state assertion (fresh-import-per-test) — AC14.
  - [ ] 3.4.3 Rate-limit-aware retry on 403/secondary-rate.
- [ ] **3.5** Create `apps/web-platform/app/api/webhooks/github/route.ts` — implement 8-step order (verify-FIRST, dedup-SECOND, release-on-error):
  - [ ] 3.5.1 Step 1: `const rawBody = await req.text()` BEFORE `JSON.parse`.
  - [ ] 3.5.2 Step 2: `crypto.timingSafeEqual(Buffer.from(received), Buffer.from(computed))` — NEVER `===`. Fail-closed 401 on mismatch or missing secret.
  - [ ] 3.5.3 Step 3: Plain `.insert()` into `processed_github_events(delivery_id)` (NO `ON CONFLICT`). Catch `PG_UNIQUE_VIOLATION (23505)` → return 200 (duplicate).
  - [ ] 3.5.4 Step 4: `JSON.parse(rawBody)` + switch on `req.headers.get("x-github-event")`.
  - [ ] 3.5.5 Step 5: Resolve `founderId` via `github_installation_id → users.id` — 404 if unknown.
  - [ ] 3.5.6 Step 6: `isGranted(supabase, founderId, "<kind>")` — fail-closed on no-grant OR DB-error (`logger.error` + `Sentry.captureMessage(level: "error")` + return 200 without dispatch).
  - [ ] 3.5.7 Step 7: `inngest.send({ id: "github-${deliveryId}", name, v: "1", data: {...} })`.
  - [ ] 3.5.8 Step 8: On ANY error in steps 5-7 AFTER step 3 INSERT, DELETE the `processed_github_events` row (mirror of Stripe's `releaseDedupRow` pattern at `webhooks/stripe/route.ts:144-159`).
- [ ] **3.6** Create `apps/web-platform/app/api/webhooks/github/route.test.ts`:
  - [ ] 3.6.1 Signature-verify positive (good HMAC → 200).
  - [ ] 3.6.2 Signature-verify negative (bad HMAC → 401).
  - [ ] 3.6.3 Missing secret → fail-closed 500.
  - [ ] 3.6.4 Duplicate `delivery_id` (replay) → 200 without `inngest.send` — AC1.
  - [ ] 3.6.5 No-grant fail-closed → 200, `logger.error` + `Sentry.captureMessage` invoked — AC2.
  - [ ] 3.6.6 Mocked `inngest.send` failure → DELETE of `processed_github_events` row + propagate 500 — AC13.
  - [ ] 3.6.7 Subsequent redelivery of same `delivery_id` after release-on-error → processed (no false-duplicate).
- [ ] **3.7** Create `knowledge-base/engineering/architecture/decisions/ADR-031-github-app-webhook-as-second-multi-source-ingress.md` — webhook over polling; App over PAT; `status: accepted`. **Same commit as 3.5 webhook route.**
- [ ] **3.8** Create `knowledge-base/engineering/architecture/decisions/ADR-032-messages-source-ref-composite-unique-for-multi-source-dedup.md` — partial-unique index pattern; CATCH `PG_UNIQUE_VIOLATION` (not `ON CONFLICT DO NOTHING`); release-on-error; natural cleanup via autovacuum; `status: accepted`. **Same commit as 3.5 webhook route.**
- [ ] **3.9** Commit & push Phase 3.

**Exit gate:** webhook accepts signed events, rejects unsigned, replays return 200, release-on-error verified; AC1-AC2-AC3-AC13-AC14 satisfied.

## Phase 4 — Single GitHub Inngest dispatcher

- [ ] **4.1** Create `apps/web-platform/server/inngest/functions/github-event-strategies.ts`:
  - [ ] 4.1.1 `GITHUB_EVENT_STRATEGIES` record keyed by event name (4 entries: `engineering.pr_review_pending`, `engineering.ci_failed`, `triage.p0p1_issue`, `security.cve_alert`).
  - [ ] 4.1.2 Each entry: `{ verifyState, draftPrompt, owningDomain, sourceRefPrefix, urgency, redactSource }`.
  - [ ] 4.1.3 `owningDomain` for `triage.p0p1_issue` is a function of label (`type/feature` → `product`; default `engineering`).
- [ ] **4.2** Create `apps/web-platform/server/inngest/functions/github-event-strategies.test.ts`:
  - [ ] 4.2.1 Pure-function tests for owningDomain label routing.
  - [ ] 4.2.2 Pure-function tests for redactSource correctness per event.
- [ ] **4.3** Create `apps/web-platform/server/inngest/functions/github-on-event.ts`:
  - [ ] 4.3.1 `inngest.createFunction(...)` with `concurrency: [{scope:"fn", key:"event.data.founderId + ':' + event.name", limit:1}, {scope:"account", limit:50}], retries:1`. Per-(founder, event-class) CEL key preserves parallel processing across event classes for the same founder.
  - [ ] 4.3.2 `event` parameter is the array `["engineering.pr_review_pending", "engineering.ci_failed", "triage.p0p1_issue", "security.cve_alert"]`.
  - [ ] 4.3.3 Handler steps: schema-gate (non-throwing `step.run`) → verify-state outside `step.run` (ADR-030 I3) → BYOK lease wrapped SDK call (ADR-030 I1) → redact INSERT-time via `redactGithubSourcedText(draft, {source: strategy.redactSource})` → persist-draft via `getFreshTenantClient(founderId)` (ADR-030 I2) — INSERT messages row with strategy-derived `owning_domain`, `sourceRefPrefix + gh-id`, `urgency`.
- [ ] **4.4** Create `apps/web-platform/server/inngest/functions/github-on-event.test.ts`:
  - [ ] 4.4.1 4 × N matrix (event class × state-verify outcome × grant-tier × persist-draft success).
  - [ ] 4.4.2 BYOK lease wraps SDK call (no escape into step boundaries).
  - [ ] 4.4.3 Redaction is applied BEFORE persist (INSERT-time gate).
  - [ ] 4.4.4 `messages.trust_tier` pinned at webhook-fire time (grant tier carried through event payload).
- [ ] **4.5** Edit `apps/web-platform/app/api/inngest/route.ts`: register `githubOnEvent` in `serve()` array. **This edit lands in Phase 4 (NOT Phase 3) per Kieran P1 — registration follows consumer.**
- [ ] **4.6** Commit & push Phase 4.

**Exit gate:** dispatcher unit tests green; `inngest dev` shows 1 new function registered; AC11 satisfied (ADRs already landed in Phase 3).

## Phase 5 — KB-drift walker + GH Actions workflow + internal ingest

- [ ] **5.1** Create `scripts/kb-drift-walker.sh`:
  - [ ] 5.1.1 Broken-link check: walk `knowledge-base/`, extract markdown link targets, `test -e` each.
  - [ ] 5.1.2 Code-anchor check: parse `AGENTS.md` `[id: ...]` rule bodies + `knowledge-base/project/learnings/**/*.md` for `path/to/file.ext:line` anchors; existence-only check.
  - [ ] 5.1.3 Skip `archive/` and `.git/`.
  - [ ] 5.1.4 Emit findings as JSON to stdout.
- [ ] **5.2** Create `tests/scripts/test-kb-drift-walker.sh`:
  - [ ] 5.2.1 Golden fixture: 3 broken-link + 2 broken-anchor + 5 healthy controls.
  - [ ] 5.2.2 Assert EXACTLY 3 broken-link + EXACTLY 2 broken-anchor in output (per AC4 plan-review fix).
  - [ ] 5.2.3 Assert ingest-payload JSON shape.
- [ ] **5.3** Create `.github/workflows/kb-drift-walker.yml`:
  - [ ] 5.3.1 Cron `0 3 * * *` UTC.
  - [ ] 5.3.2 Read `secrets.DOPPLER_TOKEN_KB_DRIFT`.
  - [ ] 5.3.3 Run `doppler run -p soleur -c prd_kb_drift_walker -- scripts/kb-drift-walker.sh > findings.json`.
  - [ ] 5.3.4 POST to `/api/internal/kb-drift-ingest` with HMAC-SHA256 header (signed by `KB_DRIFT_INGEST_SIGNING_KEY`).
- [ ] **5.4** Create `apps/web-platform/app/api/internal/kb-drift-ingest/route.ts`:
  - [ ] 5.4.1 HMAC-SHA256 verify against `KB_DRIFT_INGEST_SIGNING_KEY` (timingSafeEqual).
  - [ ] 5.4.2 For each finding, INSERT `messages` row with `source='kb-drift'`, `source_ref='link-<sha256[:16]>'` or `'anchor-<sha256[:16]>'`, `tier='external_low_stakes'`, `status='draft'`, `owning_domain='knowledge'`, `urgency='low'`, `trust_tier='internal_infra_auto'`.
  - [ ] 5.4.3 Idempotency via Phase 1 partial-unique index (`messages_active_draft_dedup_idx`).
- [ ] **5.5** Create `apps/web-platform/app/api/internal/kb-drift-ingest/route.test.ts`:
  - [ ] 5.5.1 HMAC positive/negative.
  - [ ] 5.5.2 Payload shape validation.
  - [ ] 5.5.3 Dedup behavior (same `source_ref` doesn't double-insert).
- [ ] **5.6** Run walker against seeded fixture; verify 3 broken-link + 2 code-anchor cards in `messages` table.
- [ ] **5.7** Commit & push Phase 5.

**Exit gate:** seeded fixture run produces exactly 3+2 cards; nightly schedule active; AC4 satisfied.

## Phase 6 — TodayCard variants + inline ranking + render-time redaction + legal docs + spec amendment

- [ ] **6.1** Edit `apps/web-platform/components/dashboard/today-card.tsx`:
  - [ ] 6.1.1 Source-aware variant switch: `stripe`/`cfo` unchanged; `github`/* → "let CTO handle it" with button label by `source_ref` prefix; `kb-drift`/`knowledge` → "Fix link" / "Update anchor" direct-action.
  - [ ] 6.1.2 Render-time redaction: apply `redactGithubSourcedText(draftPreview, {source: strategy.redactSource})` BEFORE display.
  - [ ] 6.1.3 CVE branch: for `source='github'` AND `source_ref` startsWith `cve-` or `secret-scan-`, render `<span>{cveId}</span> <SeverityBadge>{severity}</SeverityBadge>` — full `draftPreview` only on "Edit" modal click.
- [ ] **6.2** Edit `apps/web-platform/app/api/dashboard/today/route.ts`:
  - [ ] 6.2.1 Inline ranking (15 LoC): strict tier (`urgency='critical' > 'high' > 'normal' > 'low'`) → within tier `score = recency × severity × leader_confidence` → tie-break `created_at DESC`.
  - [ ] 6.2.2 `slice(0, 7)` for `items`; remainder in `extras` array.
  - [ ] 6.2.3 Add `Cache-Control: private, max-age=60` response header.
- [ ] **6.3** Create / edit `apps/web-platform/test/components/today-card.test.tsx`:
  - [ ] 6.3.1 Matrix test: 3 sources × N owning_domain — assert button affordance per (source, owning_domain).
  - [ ] 6.3.2 CVE render: assert `cve-id` + `severity-badge` testIds present; assert `draft-preview-body` NOT present.
  - [ ] 6.3.3 Render-time redaction: assert redaction helper invoked with correct `source` opt.
- [ ] **6.4** Create / edit `apps/web-platform/test/server/today-route.test.ts`:
  - [ ] 6.4.1 Feed 30 mock items → assert `items.length === 7` AND `extras.length === 23` (AC7).
  - [ ] 6.4.2 Tier-strict ordering: `critical` always before `high` etc.
  - [ ] 6.4.3 Cache-Control header on response.
- [ ] **6.5** Edit `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts` — add `audit_github_token_use` to writer-sweep inventory.
- [ ] **6.6** Edit `knowledge-base/legal/compliance-posture.md` — Article 30 Processing Activity 14 (GitHub-sourced priority signals; Art. 6(1)(f); sub-processor GitHub Inc.).
- [ ] **6.7** Edit `docs/legal/data-protection-disclosure.md` — GitHub Inc. as sub-processor (US-stored, SCC-reliant); "display third-party repo content as-is and do not re-process" clause.
- [ ] **6.8** Edit `docs/legal/privacy-policy.md` — "Data we collect from third parties" section.
- [ ] **6.9** Edit `docs/legal/acceptable-use-policy.md` — card-screenshot-redaction clause.
- [ ] **6.10** Edit `knowledge-base/project/specs/feat-daily-priorities-multi-source/spec.md` — **TR6 amendment** (reverse to "INSERT-time + render-time belt-and-suspenders; render-time is the load-bearing Art. 14 gate"). **AC15 ship-blocker.**
- [ ] **6.11** Commit & push Phase 6.

**Exit gate:** Today section renders 3 sources with source-correct affordances; CVE cards render ID + severity only; ranking caps at 7; 4 legal docs updated; spec amendment merged; AC5-AC10-AC15 satisfied.

## Pre-merge ship gate

- [ ] **S.1** All 15 pre-merge ACs (AC1-AC15) green.
- [ ] **S.2** Run `bun test apps/web-platform/` — full suite passes.
- [ ] **S.3** Run `tsc --noEmit` — clean.
- [ ] **S.4** Run multi-agent review (`/soleur:review`) and fold findings inline.
- [ ] **S.5** Confirm `terraform plan` returns clean diff against `prd_terraform` (AC12).
- [ ] **S.6** Verify `## User-Brand Impact` section populated + threshold set (deepen-plan Phase 4.6 gate; should already be green from this plan).
- [ ] **S.7** PR body includes `## Changelog` section + `Ref #3244` (NOT `Closes #3244` — umbrella stays open until operator AC-PM5 flips).

## Post-merge operator tasks (tracked separately)

These map to AC-PM1 through AC-PM5 in the plan. Folded into `/soleur:ship` Phase 5.5 verification where automation feasibility exists (Supabase MCP + `gh api` for AC-PM4):

- [ ] **P.1 (AC-PM1)** Operator creates GitHub App per runbook (manual gate; deferred-automation tracked).
- [ ] **P.2 (AC-PM2)** Operator runs canonical Terraform apply triplet.
- [ ] **P.3 (AC-PM3)** Operator flips `SOLEUR_FR5_GITHUB_ENABLED=true` in Doppler `prd` AFTER PR-G #3947 ships.
- [ ] **P.4 (AC-PM4)** Operator installs GitHub App on test repo, pushes fake PR, verifies Today card within 60s; `audit_github_token_use` + `processed_github_events` rows written.
- [ ] **P.5 (AC-PM5)** Umbrella #3244 AC line 6 flips `[x]`.

## Exit gate (compound + ship)

- [ ] **E.1** `/soleur:compound` — capture session learnings.
- [ ] **E.2** File post-merge follow-up issues:
  - [ ] E.2.1 `feat: KB-drift draft retention policy (TS-05)` — R5 mitigation.
  - [ ] E.2.2 (Conditional) `fix: constrain GitHub App to one install per founder` if Phase 2 OQ1 resolves to "1-to-many not supported."
- [ ] **E.3** `/soleur:ship` — preflight Check 6 + verification + auto-merge gate.

## Source of truth

- **Plan** (v2, post plan-review): `knowledge-base/project/plans/2026-05-19-feat-daily-priorities-multi-source-pr-h-plan.md`
- **Spec** (FR/TR enumeration): `knowledge-base/project/specs/feat-daily-priorities-multi-source/spec.md` (TR6 to be amended in 6.10)
- **Brainstorm** (K1-K12 + User-Brand Impact): `knowledge-base/project/brainstorms/2026-05-19-daily-priorities-multi-source-brainstorm.md`
