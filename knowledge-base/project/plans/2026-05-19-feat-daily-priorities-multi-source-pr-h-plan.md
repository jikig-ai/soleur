---
title: "feat: Daily Priorities multi-source (PR-H)"
date: 2026-05-19
status: plan
type: feat
umbrella: "#3244"
brand_survival_threshold: single-user incident
lane: cross-domain
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-05-19-daily-priorities-multi-source-brainstorm.md
spec: knowledge-base/project/specs/feat-daily-priorities-multi-source/spec.md
branch: feat-daily-priorities-multi-source
draft_pr: "#4066"
related_prs: ["#3940", "#3947"]
related_issues: ["#3244", "#3947", "#3948", "#4070", "#4071", "#4072", "#4073", "#4074", "#4075"]
plan_review_applied: true
plan_review_findings: 13
plan_review_dissent: "Split KB-drift into PR-H + PR-H2 (DHH P0) — brainstorm Phase 2 weighed Approach A vs B with full information and chose A; rf-when-a-reviewer-or-user-says-to-keep-a applies."
---

# feat: Daily Priorities multi-source (PR-H) — plan

## Overview

PR-H closes umbrella **#3244**'s outstanding acceptance criterion ("≥3 signal sources + 'let [leader] handle it' one-click delegation") by extending the Today section beyond Stripe-only (PR-F #3940 merged 2026-05-17) with **GitHub** (4 event classes) and **KB-drift** (2 signal classes, direct-action only).

Approach **A** locked in brainstorm: single PR, fully hardened, all CLO blockers inline. Migration 051 inline (`source_ref` + partial-unique dedup index + `audit_github_token_use`). CVE / security-advisory cards render ID + severity only. Hybrid ranking (strict tier → score within tier, cap surface at 7). GitHub App + short-lived install tokens — PAT off-table.

Plan v2 incorporates 13 plan-review findings (P0+P1+P2) from DHH + Kieran + code-simplicity. Single dissent: KB-drift remains bundled in PR-H (brainstorm Phase 2 informed-decision; `rf-when-a-reviewer-or-user-says-to-keep-a`).

## Research Reconciliation — Spec vs. Codebase

| Spec claim / draft assumption | Reality found at plan-time | Plan response |
|---|---|---|
| Spec TR6: "Apply redaction at INSERT time, NOT at render time. Render-time is the fallback." | Brainstorm CLO recommended **render-time + ephemeral cache** for GDPR Art. 14 minimization. Best-practices research (EDPB Guidelines 3/2025) confirms render-time + short TTL cache minimizes Art. 14 surface vs persist-redacted. Spec TR6 contradicts the brainstorm CLO mitigation. | **Reverse TR6.** Plan implements belt-and-suspenders: INSERT-time redaction (audit-trail integrity) PLUS render-time redaction (load-bearing Art. 14 gate). `Cache-Control: private, max-age=60` on the Today response. **Spec.md is amended in this PR** (see `## Files to Edit`). |
| Spec TR3: "switch on `event.headers['x-github-event']`". | Webhook handler must `await req.text()` BEFORE `JSON.parse` (HMAC needs raw bytes). The `x-github-event` header is on the request, not the parsed body — accessible via `req.headers.get("x-github-event")`. | No change to spec; plan Phase 3 step order explicitly mirrors Stripe's verify-FIRST, dedup-SECOND order. |
| Spec FR8: "INSERT … ON CONFLICT DO NOTHING; if zero rows affected, return 200 (duplicate)." | Kieran P0: supabase-js `.insert()` returns `data: null` (NOT empty array) on `ON CONFLICT DO NOTHING` without `.select()`. The "rows affected" check is unreliable. Stripe path at `webhooks/stripe/route.ts:117-122` uses plain `.insert()` and catches `PG_UNIQUE_VIOLATION (23505)` — the correct idiom. | **Adopt Stripe idiom.** Phase 3 INSERTs without `ON CONFLICT`, catches `23505`, returns 200 on duplicate. ADR-037 amended accordingly. |
| Webhook handler error vs delivery_id row. | Kieran P0: Stripe path has `releaseDedupRow()` on 5xx (`webhooks/stripe/route.ts:144-159`) — without an equivalent, a transient `inngest.send` failure leaves the delivery_id row, GitHub redelivers, the redelivery 200s as "duplicate", event dropped. **Production data-loss risk.** | **Mirror Stripe's `releaseDedupRow()` pattern.** On any error AFTER successful INSERT and BEFORE `inngest.send` returns success, DELETE the `processed_github_events` row to allow GitHub's redelivery to be processed. Phase 3 step 124 carries the explicit ordering. |
| Spec TR2 lists `GITHUB_APP_*` secrets in Doppler `prd`. | Terraform-architect produced a complete IaC manifest: 5 keys map to `prd` (4 operator-supplied + 1 `random_id` for the webhook secret); `KB_DRIFT_INGEST_SIGNING_KEY` lives in NEW `prd_kb_drift_walker` Doppler config for blast-radius scoping. Single manual gate: GitHub App creation in github.com/settings/apps UI. | Folded into `## Infrastructure (IaC)` below; Phase 2 covers operator preflight + IaC apply atomically. |
| Spec FR8 references "Inngest's 24h window". | Best-practices: Inngest's 24h `event.id` dedup is FIXED (not configurable on self-hosted). DB-side `processed_github_events` retention MUST cover the gap (autovacuum + 30-day partition rotation, NOT an explicit TTL daemon). | ADR-037 documents the 24h-Inngest + Postgres-natural-cleanup pair; no TTL cron in scope. |
| Spec TR3 implies module-scope Octokit App client. | Next.js App Router has documented module-scope singleton inconsistency (vercel/next.js#65350). Octokit's `@octokit/auth-app` v7 auto-refreshes installation tokens at `expires_at - 60s` internally — **manual 55-min cache double-caches and risks mid-request expiry**. | **Per-request factory only**; explicit "no module-scope singleton" comment in `app-client.ts`. Manual cache deleted from plan; trust the auth strategy. |

## User-Brand Impact

Carry-forward from brainstorm `## User-Brand Impact` (operator re-affirmed 2026-05-19 with all-of-the-above).

**If this lands broken, the user experiences:** a high-confidence Today card delegating to the wrong leader; cross-tenant GitHub repo/PR titles rendering on the wrong founder's dashboard; a CVE advisory card leaking secret-looking strings on shoulder-surf or screenshare; OR a flood of low-signal cards burying the one P0 that actually matters.

**If this leaks, the user's [GitHub source code + customer issue bodies + payment context] is exposed via:** GitHub App private-key compromise (full org read); webhook-signing-secret leak (forged events from a third party); cross-tenant `messages` row exposure (RLS bypass); render-time `draft_preview` exposure (Art. 14 surface for incidentally-uploaded customer PII in issue/PR bodies).

**Brand-survival threshold:** `single-user incident` (inherited).

**Sign-off:** CPO sign-off carried from brainstorm Phase 0.5. `user-impact-reviewer` invoked at PR review-time per `plugins/soleur/skills/review/SKILL.md` conditional-agent block. Preflight Check 6 fires on `apps/web-platform/app/api/webhooks/github/**` + `apps/web-platform/server/inngest/functions/github-on-event*` + migration 051.

## Implementation Phases (6)

PR-H sized for a single merged PR (Approach A; KB-drift bundled per brainstorm Phase 2 decision). Phases run sequentially; commits within phases are flexible; the merge is atomic.

### Phase 1 — Migration 051 + redaction extension

**Goal:** schema groundwork + GDPR-blocker artifacts.

**Files created:**
- `apps/web-platform/supabase/migrations/051_multi_source_dedup.sql` — ALTER `messages` ADD `source_ref text` (nullable for backfill safety); partial-unique index `messages_active_draft_dedup_idx ON messages (user_id, source, source_ref) WHERE status='draft' AND source_ref IS NOT NULL`; new table `audit_github_token_use(founder_id, installation_id, repo_full_name, endpoint, ts, response_status)` with RLS + RPC `record_github_token_use(...)` (`SECURITY DEFINER` + `SET search_path=public, pg_temp`); new table `processed_github_events(delivery_id text PRIMARY KEY, received_at timestamptz DEFAULT now())` — retention via Postgres autovacuum + 30-day partition rotation (no explicit TTL daemon).
- `apps/web-platform/supabase/migrations/051_multi_source_dedup.test.ts` — shape test asserting new columns + RLS policies + index + audit table + RPC search_path pinning + processed-events table.

**Files edited:**
- `apps/web-platform/lib/safety/redaction-allowlist.ts` — add NEW export `redactGithubSourcedText(s: string, opts?: { source?: 'pr_title'|'issue_body'|'cve_description' }): string`. Co-located with PR-A's existing exports (single module, two threat models: LLM-output-scoped vs third-party-ingested-scoped). Stripe/CFO paths unchanged (different export, no signature change to existing functions).
- `apps/web-platform/lib/safety/redaction-allowlist.test.ts` — golden fixtures per `source` variant; PII shapes per learning `2026-04-17-pii-regex-scrubber-three-invariants` (max-input bound, alphabet-aware UUID match, no `/g`+`.test()` gate).
- `apps/web-platform/lib/messages/tiers.ts` — add `MESSAGE_SOURCE_GITHUB = 'github'`, `MESSAGE_SOURCE_KB_DRIFT = 'kb-drift'`, `MESSAGE_OWNING_DOMAIN_KNOWLEDGE = 'knowledge'`.

**Exit:** migration 051 shape tests green; redaction allowlist tests green (existing + new variants).

### Phase 2 — Operator preflight + IaC apply

**Goal:** unblock credential availability via the single manual gate + canonical IaC apply.

**The single manual gate.** GitHub does not expose an App-creation API to any Terraform provider; operator creates the App once at `https://github.com/settings/apps/new`. Per `hr-never-label-any-step-as-manual-without`, the gate carries an issue link for future automation — filed as part of Phase 2 deferred-issue creation.

**Operator steps (tracked in runbook):**
1. Operator creates GitHub App `Soleur-Concierge`: webhook URL `https://soleur.ai/api/webhooks/github`; webhook secret = Soleur-generated (paste the `random_id` output AFTER step 3). Permissions: `pull_requests:read`, `issues:read`, `metadata:read`, `actions:read`, `repository_advisories:read`, `secret_scanning_alerts:read`. Events: `pull_request`, `workflow_run`, `issues`, `repository_advisory`, `secret_scanning_alert`. Installable on founder's own account/orgs only.
2. Operator downloads PEM (one-shot reveal), captures App ID + Client ID + Client Secret; exports as `TF_VAR_github_app_*`.
3. Canonical Terraform apply (per learning `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan`):
   ```bash
   export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
   export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
   cd apps/web-platform/infra && terraform init -input=false
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply
   ```
4. Operator copies the `random_id` webhook-secret output back into the GitHub App configuration (closes the loop).

**Files created:**
- `apps/web-platform/infra/github-app.tf` — 5 `doppler_secret` resources in `prd` + 1 `random_id` (webhook secret). `lifecycle.ignore_changes = [value]` on the 4 operator-supplied secrets; NO ignore on `random_id`-derived (rotation = `terraform apply -replace=random_id.github_webhook_secret`).
- `apps/web-platform/infra/kb-drift.tf` — single `doppler_secret` in NEW `prd_kb_drift_walker` config + `github_actions_secret` (provider `integrations/github`) publishing the Doppler service-token as repo Actions secret `DOPPLER_TOKEN_KB_DRIFT`.
- `apps/web-platform/infra/alerts-github-webhook.tf` — three `betteruptime_*` resources gated by `count = var.betterstack_paid_tier ? 1 : 0`; free-tier paths via existing `cq-silent-fallback-must-mirror-to-sentry` Sentry mirror.
- `knowledge-base/operations/runbooks/github-app-provisioning.md` — canonical operator runbook for the manual gate; references the deferred-automation issue.

**Files edited:**
- `apps/web-platform/infra/main.tf` — add `github = { source = "integrations/github", version = "~> 6.0" }` to `required_providers`.
- `apps/web-platform/infra/variables.tf` — append 4 `sensitive=true` GitHub App vars + 1 `github_actions_token`.
- `apps/web-platform/infra/outputs.tf` — surface `github_app_webhook_url` (static; no DNS change).

**Exit:** all 6 Doppler keys present in `prd` + `prd_kb_drift_walker`; `gh secret list --repo jikig-ai/soleur | grep DOPPLER_TOKEN_KB_DRIFT` returns 1 row; `terraform plan` returns clean; `var.betterstack_paid_tier` value confirmed pre-apply.

### Phase 3 — GitHub webhook route + signature verification + dedup + scope-grant gate + ADRs

**Goal:** the canonical ingress, mirroring `webhooks/stripe/route.ts:71-159, 437-516` exactly (verify-FIRST, dedup-SECOND, scope-grant-THIRD, send-FOURTH, release-on-error).

**Webhook handler order of operations** (load-bearing; mirrors Stripe):

1. `const rawBody = await req.text()` (raw bytes for HMAC; BEFORE `JSON.parse`).
2. `crypto.timingSafeEqual(Buffer.from(received), Buffer.from(computed))` — **NEVER** `===`. Fail-closed on mismatch or missing secret (401).
3. INSERT into `processed_github_events(delivery_id)` — plain `.insert()` (NO `ON CONFLICT`). Catch `PG_UNIQUE_VIOLATION (23505)` → return 200 (duplicate). All other errors propagate.
4. `JSON.parse(rawBody)` + switch on `req.headers.get("x-github-event")`.
5. Resolve `founderId` via `github_installation_id → users.id`. If unknown, 404 (no scope, no row written).
6. `isGranted(supabase, founderId, "<scope-grant-kind>")` — fail-closed on no-grant OR DB-error (log + return 200 without dispatch).
7. `await inngest.send({ id: "github-${deliveryId}", name, v: "1", data: {...} })`.
8. **On ANY error in steps 5-7 AFTER step 3 INSERT succeeded:** DELETE the `processed_github_events` row (mirror of Stripe's `releaseDedupRow()` at `webhooks/stripe/route.ts:144-159`) so GitHub's redelivery can be processed cleanly.

**Files created:**
- `apps/web-platform/app/api/webhooks/github/route.ts` — implements steps 1-8.
- `apps/web-platform/app/api/webhooks/github/route.test.ts` — covers: signature-verify positive + negative; missing-secret fail-closed; duplicate `delivery_id` returns 200 without `inngest.send`; no-grant fail-closed; `inngest.send` failure DELETEs the dedup row + propagates 500; signature-verify-failure mirrored to Sentry at `level: "error"` (per `cq-silent-fallback-must-mirror-to-sentry`).
- `apps/web-platform/server/github/app-client.ts` — per-request factory `createGitHubAppClient(installationId): Promise<Octokit>` using `@octokit/auth-app` v7. **NO manual token caching** — auth strategy auto-refreshes at `expires_at - 60s` internally; double-caching would risk mid-request expiry. **NO module-scope singleton** (vercel/next.js#65350); per-request instantiation only.
- `apps/web-platform/server/github/app-client.test.ts` — per-request semantics; rate-limit-aware retry; explicit "no module-scope" assertion via fresh-import-per-test.
- `knowledge-base/engineering/architecture/decisions/ADR-036-github-app-webhook-as-second-multi-source-ingress.md` — webhook over polling; App over PAT; status `accepted`. Lands in same commit as the webhook route it describes.
- `knowledge-base/engineering/architecture/decisions/ADR-037-messages-source-ref-composite-unique-for-multi-source-dedup.md` — partial-unique index pattern; CATCH `PG_UNIQUE_VIOLATION` (not `ON CONFLICT DO NOTHING`); release-on-error pattern; processed-events natural cleanup via autovacuum; status `accepted`.

**Files edited:**
- `apps/web-platform/server/scope-grants/grant-kinds.ts` — add 5 new kinds: `engineering.pr_review_pending`, `engineering.ci_failed`, `triage.p0p1_issue`, `security.cve_alert`, `knowledge.kb_drift`.
- `apps/web-platform/package.json` + `package.json` (root) — add `@octokit/app@^15`, `@octokit/auth-app@^7`. Verify peer-deps via `npm view <pkg> peerDependencies` (per plan SKILL.md sharp edge).

**Exit:** webhook route accepts signed events, rejects unsigned with 401, replays return 200 without dispatch, release-on-error verified via mocked `inngest.send` failure; AC1-AC2-AC3 satisfied.

### Phase 4 — Single GitHub Inngest dispatcher

**Goal:** one Inngest function handles all 4 event classes via a strategy table — collapses PR-H plan-review P1 consensus.

**Why one function not four** (plan-review triad consensus): the 4 event classes share ~90% boilerplate (schema-gate → verify-state → BYOK lease → redact → persist-draft). Per-class deltas are encoded in a `Record<EventClass, EventStrategy>` table. Concurrency parallelism per-(founder, event-class) is preserved via the CEL-key change below.

**Files created:**
- `apps/web-platform/server/inngest/functions/github-on-event.ts` — single `inngest.createFunction({id: "github-on-event", concurrency: [{scope:"fn", key:"event.data.founderId + ':' + event.name", limit:1}, {scope:"account", limit:50}], retries:1}, {event: ["engineering.pr_review_pending", "engineering.ci_failed", "triage.p0p1_issue", "security.cve_alert"]}, handler)`. The CEL key (`founderId:event.name`) preserves parallel processing for the same founder across different event classes — a CI-failed event does NOT queue behind a PR-review event for the same founder.
- `apps/web-platform/server/inngest/functions/github-event-strategies.ts` — strategy table:
  ```ts
  export const GITHUB_EVENT_STRATEGIES = {
    "engineering.pr_review_pending": { verifyState, draftPrompt, owningDomain: "engineering", sourceRefPrefix: "pr-", urgency: "normal", redactSource: "pr_title" },
    "engineering.ci_failed": { verifyState, draftPrompt, owningDomain: "engineering", sourceRefPrefix: "ci-", urgency: "high" },
    "triage.p0p1_issue": { verifyState, draftPrompt, owningDomain: (label) => label === "type/feature" ? "product" : "engineering", sourceRefPrefix: "issue-", urgency: "critical", redactSource: "issue_body" },
    "security.cve_alert": { verifyState, draftPrompt, owningDomain: "engineering", sourceRefPrefix: "cve-", urgency: "critical", redactSource: "cve_description" },
  } as const;
  ```
- `apps/web-platform/server/inngest/functions/github-on-event.test.ts` — 4 × N matrix tests (event class × state-verify outcome × grant-tier × persist-draft success). Schema-gate non-throwing, verify-state outside `step.run` (ADR-030 I3), BYOK lease per-step (ADR-030 I1), redact INSERT-time (Phase 1 helper), persist-draft via `getFreshTenantClient(founderId)` (ADR-030 I2).
- `apps/web-platform/server/inngest/functions/github-event-strategies.test.ts` — pure-function strategy resolution (owningDomain label routing, redactSource correctness).

**Files edited:**
- `apps/web-platform/app/api/inngest/route.ts` — register the new dispatcher in the `serve()` array. **This edit lands in Phase 4** (per Kieran P1 — registration must follow the consumer it registers, not precede in Phase 3).

**Exit:** dispatcher unit tests green; `inngest dev` shows 1 new function registered handling 4 event classes; mocked end-to-end event → DB INSERT works for each strategy; AC11 (ADR-036, ADR-037) already satisfied in Phase 3.

### Phase 5 — KB-drift walker + GH Actions workflow + internal ingest

**Goal:** ship the second source (direct-action UI affordance, no leader delegation).

**Files created:**
- `scripts/kb-drift-walker.sh` — bash walker. Two checks:
  - **Broken intra-KB links:** `grep -rEo '\]\([^)]+\.md[^)]*\)' knowledge-base/ | xargs -I{} test -e {}` (existence-only per spec FR4; semantic re-anchor deferred to #4073).
  - **Code-anchor drift:** parse `AGENTS.md` `[id: ...]` rule bodies + `knowledge-base/project/learnings/**/*.md` for `path/to/file.ext:line` anchors; `test -e` each anchor path. Skip `archive/` and `.git/`.
- `tests/scripts/test-kb-drift-walker.sh` — golden fixture (3 broken-link + 2 broken-anchor + 5 healthy controls); assert exact count + payload shape. Test path co-located with implementation per orphan-suite invariant (`scripts/test-all.sh` picks it up).
- `.github/workflows/kb-drift-walker.yml` — cron `0 3 * * *` UTC. Reads `secrets.DOPPLER_TOKEN_KB_DRIFT` (Phase 2 IaC published). Runs `doppler run -p soleur -c prd_kb_drift_walker -- scripts/kb-drift-walker.sh > findings.json`, then POSTs to `/api/internal/kb-drift-ingest` with HMAC-SHA256 header signed by `KB_DRIFT_INGEST_SIGNING_KEY`.
- `apps/web-platform/app/api/internal/kb-drift-ingest/route.ts` — `POST` handler. HMAC verify (signing key from Doppler `prd_kb_drift_walker`). For each finding, INSERT `messages` row with `source='kb-drift'`, `source_ref='link-<sha256(source+target)[:16]>'` or `'anchor-<...>'`, `tier='external_low_stakes'`, `status='draft'`, `owning_domain='knowledge'`, `urgency='low'`, `trust_tier='internal_infra_auto'` (the implicit `knowledge.kb_drift` grant kind is granted-by-default — internal-only data; no per-founder opt-in needed).
- `apps/web-platform/app/api/internal/kb-drift-ingest/route.test.ts` — HMAC positive/negative, payload shape, dedup behavior (same `source_ref` doesn't double-insert via Phase 1 partial-unique index).

**Exit:** seeded fixture run produces exactly 3 broken-link cards + 2 code-anchor cards (matches golden fixture); nightly schedule active; AC4 satisfied.

### Phase 6 — TodayCard variants + inline ranking + render-time redaction + legal docs

**Goal:** user-facing surface that closes umbrella AC; render-time GDPR Art. 14 gate; all CLO legal-doc blockers.

**TodayCard render variants (source-aware):**
- `stripe`/`cfo` → existing "let CFO handle it" — unchanged.
- `github`/* → "let CTO handle it" (button label by `source_ref` prefix): Spawn-review-agent / Spawn-fix-agent / Spawn-triage-agent / Spawn-CVE-bump-agent. Same Send/Edit/Discard surface for the resulting draft.
- `kb-drift`/`knowledge` → **direct-action**: "Fix link" / "Update anchor" button opens a scoped one-file PR via the existing fix-issue skill. No leader name on the card.
- **CVE redaction:** for `source='github'` AND `source_ref` starts with `cve-` or `secret-scan-`, `<CardBody>` renders ONLY `<span>{cveId}</span> <SeverityBadge>{severity}</SeverityBadge>` — never the full advisory body. `draftPreview` reveals on "Edit" click only (modal).

**Inline ranking** (replaces the separate `today-ranking.ts` module — plan-review P2 simplification): the sort + slice lives directly in `today/route.ts`. ~15 LoC.
1. Strict-tier sort: `urgency='critical' > 'high' > 'normal' > 'low'`.
2. Within tier, score = `recency_weight × severity_weight × leader_confidence`. Tie-break `created_at DESC`.
3. Cap surface at 7. Items 8+ in `response.extras: TodayItem[]` for client-side "Show N more".

**Render-time redaction** (load-bearing Art. 14 gate): `<TodayCard>` applies `redactGithubSourcedText(draftPreview, {source: strategy.redactSource})` BEFORE display — even though Phase 4 already redacted at INSERT-time (belt-and-suspenders).

**Files edited:**
- `apps/web-platform/components/dashboard/today-card.tsx` — source-aware variant switch + render-time redact + CVE ID-only render.
- `apps/web-platform/app/api/dashboard/today/route.ts` — inline ranking + slice + `extras` field; add `Cache-Control: private, max-age=60` response header (60s TTL minimizes Art. 14 surface, prevents re-redact-thrash on rapid refresh).
- `apps/web-platform/test/components/today-card.test.tsx` — 3 source × N owning_domain matrix; CVE-render-ID-only assertion.
- `knowledge-base/legal/compliance-posture.md` — Article 30 Processing Activity 14 (GitHub-sourced priority signals; Art. 6(1)(f) legitimate interest; sub-processor: GitHub Inc.).
- `docs/legal/data-protection-disclosure.md` — GitHub Inc. as sub-processor (US-stored, SCC-reliant for EU founders); "display third-party repo content as-is and do not re-process" clause.
- `docs/legal/privacy-policy.md` — "Data we collect from third parties" section.
- `docs/legal/acceptable-use-policy.md` — card-screenshot-redaction clause.
- `knowledge-base/project/specs/feat-daily-priorities-multi-source/spec.md` — **TR6 amendment** (per plan-review Kieran P1): reverse "INSERT-time, not render-time" to "INSERT-time + render-time belt-and-suspenders; render-time is the load-bearing Art. 14 gate."
- `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts` — add `audit_github_token_use` to writer-sweep inventory.

**Exit:** Today section renders cards from 3 sources with source-correct affordances; CVE cards render ID + severity only; ranking caps at 7 with `extras` populated; component matrix tests green; 4 legal docs updated; spec TR6 amended; AC5-AC10 satisfied; umbrella #3244 AC ready to flip `[x]` (AC12) on flag flip.

## Files to Create (21)

```
apps/web-platform/supabase/migrations/051_multi_source_dedup.sql
apps/web-platform/supabase/migrations/051_multi_source_dedup.test.ts
apps/web-platform/app/api/webhooks/github/route.ts
apps/web-platform/app/api/webhooks/github/route.test.ts
apps/web-platform/app/api/internal/kb-drift-ingest/route.ts
apps/web-platform/app/api/internal/kb-drift-ingest/route.test.ts
apps/web-platform/server/inngest/functions/github-on-event.ts
apps/web-platform/server/inngest/functions/github-on-event.test.ts
apps/web-platform/server/inngest/functions/github-event-strategies.ts
apps/web-platform/server/inngest/functions/github-event-strategies.test.ts
apps/web-platform/server/github/app-client.ts
apps/web-platform/server/github/app-client.test.ts
scripts/kb-drift-walker.sh
tests/scripts/test-kb-drift-walker.sh
.github/workflows/kb-drift-walker.yml
apps/web-platform/infra/github-app.tf
apps/web-platform/infra/kb-drift.tf
apps/web-platform/infra/alerts-github-webhook.tf
knowledge-base/engineering/architecture/decisions/ADR-036-github-app-webhook-as-second-multi-source-ingress.md
knowledge-base/engineering/architecture/decisions/ADR-037-messages-source-ref-composite-unique-for-multi-source-dedup.md
knowledge-base/operations/runbooks/github-app-provisioning.md
```

## Files to Edit (16)

```
apps/web-platform/app/api/inngest/route.ts                 # register github-on-event dispatcher (Phase 4)
apps/web-platform/app/api/dashboard/today/route.ts         # inline ranking + Cache-Control: private, max-age=60 (Phase 6)
apps/web-platform/components/dashboard/today-card.tsx      # source-aware variants + render-time redact + CVE ID-only (Phase 6)
apps/web-platform/lib/safety/redaction-allowlist.ts        # add redactGithubSourcedText export (Phase 1)
apps/web-platform/lib/safety/redaction-allowlist.test.ts   # golden fixtures per source variant (Phase 1)
apps/web-platform/lib/messages/tiers.ts                    # MESSAGE_SOURCE_* + MESSAGE_OWNING_DOMAIN_KNOWLEDGE (Phase 1)
apps/web-platform/server/scope-grants/grant-kinds.ts       # 5 new scope-grant kinds (Phase 3)
apps/web-platform/infra/main.tf                            # integrations/github provider ~> 6.0 (Phase 2)
apps/web-platform/infra/variables.tf                       # 4 sensitive vars + github_actions_token (Phase 2)
apps/web-platform/infra/outputs.tf                         # github_app_webhook_url (Phase 2)
apps/web-platform/package.json                             # @octokit/app, @octokit/auth-app (Phase 3)
package.json                                               # peer-dep alignment (Phase 3)
apps/web-platform/test/server/byok-audit-writer-sweep.test.ts  # audit_github_token_use inventory (Phase 6)
knowledge-base/legal/compliance-posture.md                 # Article 30 PA 14 (Phase 6)
docs/legal/data-protection-disclosure.md                   # sub-processor + ingested-third-party clause (Phase 6)
docs/legal/privacy-policy.md                               # "Data from third parties" (Phase 6)
docs/legal/acceptable-use-policy.md                        # card-screenshot-redaction clause (Phase 6)
knowledge-base/project/specs/feat-daily-priorities-multi-source/spec.md  # TR6 amendment (Phase 6)
```

## Open Code-Review Overlap

Verified via `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json` (72 open) cross-referenced against every path in `## Files to Edit` + `## Files to Create`. **None.** No open code-review issues touch any planned file. Closest adjacencies are #3947 (PR-G dependency, not a scope-out) and the 5 deferred-from-brainstorm issues #4070-#4074 (explicitly out of scope).

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO), Legal (CLO), Operations (COO).

**Carry-forward source:** Brainstorm `## Domain Assessments` (2026-05-19) — focused-refresh sign-offs from all 4 leaders at brainstorm Phase 0.5 step 4. Plan-review (DHH + Kieran + code-simplicity) added 13 findings folded into v2.

**Product/UX Gate** — ADVISORY tier auto-accepted (pipeline mode). No new files match `components/**/*.tsx`; extending existing `today-card.tsx`. If operator wants wireframe-level fidelity on the new button affordances (especially KB-drift "Fix link" / "Update anchor"), run `ux-design-lead` BEFORE Phase 6.

## GDPR / Compliance Gate (Phase 2.7)

Trigger: plan touches all 5 canonical-regex surfaces. Plan-time advisory (3 load-bearing rows; remaining items carried forward from brainstorm CLO):

| Lens | Finding | Placement |
|---|---|---|
| Article 30 | New PA 14: GitHub-sourced priority signals. Distinct purpose; distinct data category; Art. 6(1)(f) legitimate interest. | Phase 6 — `knowledge-base/legal/compliance-posture.md`. |
| Article 14 | Display-only + render-time redaction + 60s TTL cache MINIMIZES surface. Plan TR6-amendment + Phase 6 implementation are the load-bearing controls. | Phase 6 — `today-card.tsx` + `today/route.ts`. |
| Sub-processor disclosure | GitHub Inc. as new sub-processor (US-stored, SCC-reliant). DPD + Privacy Policy updates. | Phase 6 — `docs/legal/data-protection-disclosure.md` + `privacy-policy.md`. |

**Carried forward from brainstorm CLO** (no plan-time delta): Art. 33 breach blast radius (short-lived install tokens reduce vs PAT); Art. 5(2) accountability (`audit_github_token_use` table + RPC); AUP card-screenshot-redaction clause; TS-05 storage cleanup deferred to follow-up R5.

**Mandatory disclaimer:** plan-time gate is advisory; does not substitute for legal counsel. CPO sign-off + CLO advisory at single-user threshold both carried from brainstorm.

## Infrastructure (IaC)

### Terraform changes

Root: `apps/web-platform/infra/` (existing R2 backend `main.tf:2-14`, providers `main.tf:16-41`).

| Doppler key | Config | Provenance |
|---|---|---|
| `GITHUB_APP_ID` | `prd` | operator-supplied |
| `GITHUB_APP_PRIVATE_KEY` | `prd` | operator-supplied (PEM, one-shot reveal at App creation) |
| `GITHUB_APP_WEBHOOK_SECRET` | `prd` | `random_id` (Soleur-generated; copied INTO GitHub App after Phase 2 step 3) |
| `GITHUB_APP_CLIENT_ID` | `prd` | operator-supplied |
| `GITHUB_APP_CLIENT_SECRET` | `prd` | operator-supplied |
| `KB_DRIFT_INGEST_SIGNING_KEY` | `prd_kb_drift_walker` (NEW) | `random_id` |

### Apply path

Canonical Doppler+Terraform invocation (per learning `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan`); migration 051 applies via existing CI `migrate` job in `web-platform-release.yml`. `.github/workflows/kb-drift-walker.yml` reads `secrets.DOPPLER_TOKEN_KB_DRIFT` (published by Phase 2 IaC).

### Distinctness / drift safeguards

- `lifecycle.precondition` on each `doppler_secret`: assert `prd` PEM / webhook secret are NOT in `dev`.
- `lifecycle.ignore_changes = [value]` on the 4 operator-supplied secrets; NO ignore on `random_id`-derived (rotation = `terraform apply -replace=random_id.github_webhook_secret`).
- KB-drift uses separate `prd_kb_drift_walker` Doppler config: leaked KB-drift token cannot read GitHub App PEM.

### Vendor-tier reality check

Better Stack free tier rejects `betteruptime_policy` (per learning `2026-05-15`). All 3 alert resources `count = var.betterstack_paid_tier ? 1 : 0`. Pre-apply gate: confirm `var.betterstack_paid_tier` current value in `prd_terraform`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `/api/webhooks/github` accepts signed `pull_request` / `workflow_run` / `issues` / `repository_advisory` / `secret_scanning_alert` events; rejects unsigned with 401.
- [ ] **AC2** Scope-grant gate fail-closed: no active grant OR DB error → `logger.error` invoked + `Sentry.captureMessage(..., {level: "error"})` invoked + return 200 without `inngest.send`. Test asserts both log and Sentry calls.
- [ ] **AC3** 5 scope-grant kinds registered in `server/scope-grants/grant-kinds.ts` enum.
- [ ] **AC4** KB-drift walker writes EXACTLY 3 broken-link cards + EXACTLY 2 code-anchor-drift cards on `tests/scripts/test-kb-drift-walker.sh` golden fixture.
- [ ] **AC5** `TodayCard` renders 3 sources × N owning_domain matrix; tests pass for every (source, owning_domain) combination.
- [ ] **AC6** CVE / secret-scanning cards render CVE ID + severity only; `await screen.findByTestId("today-card-cve")` shows `cve-id` + `severity-badge` but NOT `draft-preview-body`.
- [ ] **AC7** `today/route.ts` returns ≤ 7 items per call (inline ranking + slice); items 8+ in `extras` field. Test: 30 mock items → `result.items.length === 7` AND `result.extras.length === 23`.
- [ ] **AC8** Migration 051 shape test green: new columns, partial-unique index, `audit_github_token_use` + RPC + `processed_github_events`.
- [ ] **AC9** RPC `record_github_token_use` uses `SECURITY DEFINER` + `SET search_path = public, pg_temp`; shape test asserts `pg_proc.proconfig` contains the search_path pin.
- [ ] **AC10** Article 30 + DPD + Privacy + AUP updates merged in PR-H (4 file edits in `## Files to Edit`).
- [ ] **AC11** ADR-036 + ADR-037 land at `status: accepted` in same commits as the code they describe (Phase 3).
- [ ] **AC12** `terraform plan` returns clean diff against `prd_terraform` after PR-H code lands.
- [ ] **AC13** Webhook handler's release-on-error path verified: mocked `inngest.send` failure causes DELETE of the `processed_github_events` row; subsequent redelivery of the same `delivery_id` is processed (no false-duplicate).
- [ ] **AC14** Octokit `app-client.ts` test asserts NO module-scope state — fresh-import-per-test, no shared cache.
- [ ] **AC15** Spec.md TR6 amendment merged in PR-H (`## Files to Edit` lists spec).

### Post-merge (operator)

- [ ] **AC-PM1** Operator creates GitHub App per `knowledge-base/operations/runbooks/github-app-provisioning.md`. Tracks deferred-automation issue.
- [ ] **AC-PM2** Operator runs canonical Terraform apply; confirms 5 `doppler_secret` + 1 `random_id` + 3 Better Stack monitors (paid-tier) or Sentry-mirror fallbacks + 1 `github_actions_secret`.
- [ ] **AC-PM3** Operator flips `SOLEUR_FR5_GITHUB_ENABLED=true` in Doppler `prd` ONLY AFTER PR-G #3947 ships and its scope-grant UI is live.
- [ ] **AC-PM4** Operator installs GitHub App on test repo, pushes fake PR, verifies Today card within 60s; `audit_github_token_use` + `processed_github_events` rows written. **Automation:** `gh api` + Supabase MCP available — folded into `/soleur:ship` Phase 5.5 verification.
- [ ] **AC-PM5** Umbrella #3244 AC line 6 flips `[x]`.

## Test Strategy

- **Unit:** webhook route, KB-drift ingest route, `github-on-event` dispatcher, `github-event-strategies` table, `app-client.ts`, `redactGithubSourcedText`.
- **Component:** `TodayCard` 3 source × N owning_domain; CVE-render-ID-only assertion; inline-ranking slice + `extras` shape.
- **Migration shape:** 047 (columns + index + audit table + RPC + processed-events).
- **Webhook integration:** signature-verify, dedup-replay, scope-grant fail-closed, release-on-error.
- **KB-drift walker:** golden fixture (3 broken-link + 2 broken-anchor + 5 healthy controls); exact-count assertion (per AC4 plan-review fix).
- **E2E (flagged):** `SOLEUR_FR5_GITHUB_ENABLED=true` — install on test repo, push fake PR, assert Today card within 60s. Nightly E2E job; CI default off.

Test framework: `bun test` for TS; `bash` (`.test.sh`) for shell. No new framework.

## Risks

- **R1 (high)** — Multi-org install (brainstorm OQ1). GitHub App is per-org-install. **Mitigation:** Phase 2 step 1 verifies `app/api/auth/github-resolve/` callback shape; if 1-to-many unsupported, constrain MVP + file follow-up.
- **R2 (medium)** — Redaction extension regression in CFO drafts. **Mitigation:** `redactGithubSourcedText` is a NEW export in the existing `redaction-allowlist.ts`; existing exports untouched; Stripe/CFO paths verified by existing tests.
- **R3 (medium)** — KB-drift FP rate on intentional file moves. **Mitigation:** path in card body for one-click dismiss; track 30-day FP rate; #4073 covers semantic re-anchor upgrade.
- **R4 (low)** — Inngest event-volume break-even (~3k/day per COO). Single-tenant well under; flag for 5+ tenants.
- **R5 (medium)** — KB-drift draft retention. No expiration policy at MVP. **Mitigation:** track 30 days; file TS-05 cleanup follow-up at exit-gate compound.

## Dependencies

- **PR-G #3947** must merge BEFORE `SOLEUR_FR5_GITHUB_ENABLED=true` in `prd`. PR-H ships flag default off.
- Existing GitHub App primitive (tests reference `GITHUB_APP_ID`/`GITHUB_APP_PRIVATE_KEY`; the OAuth flow at `auth/github-resolve/` is unrelated to the new App webhook flow).
- Better Stack on-call wired from PR-F.
- Inngest self-hosted Hetzner running from PR-F.
- Doppler `prd_terraform` (existing).

## Sharp Edges

- `## User-Brand Impact` section is populated and threshold is set — verified before requesting deepen-plan or `/work`.
- If operator wants wireframe-level fidelity on Phase 6 button affordances, run `ux-design-lead` BEFORE Phase 6.
- Single manual gate (GitHub App creation in UI) — tracked for future automation via deferred-automation issue filed at Phase 2.
- INSERT-time + render-time redaction is belt-and-suspenders. If you must drop one, drop INSERT-time. **NEVER drop render-time** — it is the load-bearing Art. 14 gate.
- Migration 051 `processed_github_events` retention is natural (autovacuum + 30-day partition rotation). No explicit TTL daemon. Self-hosted Inngest's 24h `event.id` dedup window is fixed — the DB-side dedup is the load-bearing replay defense beyond Inngest's window.
- Per-request Octokit App factory only. Module-scope singletons break across Next.js App Router worker boundaries (vercel/next.js#65350) AND `@octokit/auth-app` v7 already auto-refreshes tokens internally — DO NOT add a manual token cache.
- `KB_DRIFT_INGEST_SIGNING_KEY` lives in `prd_kb_drift_walker` Doppler config (NEW), NOT `prd` or `prd_terraform`. Blast-radius scope.
- **Release-on-error pattern is load-bearing** for the webhook idempotency story. The `processed_github_events` INSERT happens BEFORE `inngest.send`; if `inngest.send` fails, the row MUST be DELETEd so GitHub's redelivery can be processed. Without this, transient failures silently drop events.

## Post-merge follow-up issues to file at exit gate

1. `feat: KB-drift draft retention policy (TS-05)` — R5 mitigation.
2. `chore: track GitHub App creation Terraform provider availability` — the single manual gate's automation gate (file at Phase 2 start).
3. (Conditional) `fix: constrain GitHub App to one install per founder` if Phase 2 OQ1 resolves to "1-to-many not supported."

## Source of truth and amendments

- **Spec** at `knowledge-base/project/specs/feat-daily-priorities-multi-source/spec.md` is the FR/TR enumeration anchor. PR-H edits spec.md to amend TR6 (render-time redaction supersedes INSERT-time-only stance).
- **This plan v2** incorporates 13 plan-review findings (P0+P1+P2) from DHH + Kieran + code-simplicity. Dissent recorded in frontmatter: KB-drift remains bundled per brainstorm Phase 2's informed Approach-A decision.
- **Brainstorm** at `knowledge-base/project/brainstorms/2026-05-19-daily-priorities-multi-source-brainstorm.md` is the K1-K12 decision anchor + User-Brand Impact source.
