---
type: tasks
date: 2026-05-17
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-05-17-feat-pr-f-inngest-trigger-layer-plan.md
spec: knowledge-base/project/specs/feat-pr-f-inngest-trigger-layer/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-17-pr-f-inngest-trigger-layer-brainstorm.md
branch: feat-pr-f-inngest-trigger-layer
draft_pr: "#3940"
---

# Tasks: PR-F Inngest Trigger Layer

Derived from finalized plan v2 (post-review). Phases TDD-ordered with contract-changing edits before consumers. RED → GREEN → REFACTOR per phase; commit per phase.

## Phase 0 — Preconditions, ADR (proposed), Doppler

- [ ] **0.1** Verify all 5 predecessor PRs MERGED via `gh pr view <N> --json state` for #3240, #3395, #3854, #3883, #3887. Abort on any OPEN.
- [ ] **0.2** Verify worktree HEAD pushed to `origin/feat-pr-f-inngest-trigger-layer`.
- [ ] **0.3** Run `/soleur:architecture create "Adopt Inngest as durable trigger layer for server-side agents"` → writes `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md` with `status: proposed`.
- [ ] **0.4** ADR-030 body MUST include:
    - Chosen substrate (self-hosted OSS Inngest on Hetzner; SQLite; bound 127.0.0.1)
    - Rejected alternatives (Inngest Cloud, LangGraph + custom, Bedrock AgentCore, Cloudflare DO + LISTEN/NOTIFY)
    - Cloud re-evaluation criteria (concurrency-cap pressure OR 3rd hosted founder)
    - Six load-bearing invariants: (a) lease per `step.run`, (b) JWT mint per `step.run`, (c) singleton concurrency per founderId, (d) signature-verify required at startup, (e) "drafts everywhere, sends nowhere" enforced by BOTH code AND `messages_external_tier_status_check` DB constraint, (f) verify-external-state single-pass-only — retry path re-enters from verify, never resumes from a checkpointed verify result.
- [ ] **0.5** Operations task (NOT code): set the following in Doppler `dev` AND `prd`:
    - `INNGEST_SIGNING_KEY` (generated `openssl rand -hex 32`, distinct per env)
    - `INNGEST_EVENT_KEY` (distinct per env)
    - `SOLEUR_FR5_ENABLED=false`
    - `MAX_TURN_DURATION_MS=90000`
    - `INNGEST_BASE_URL=http://127.0.0.1:8288`
- [ ] **0.6 (AC)** Verify: `doppler secrets get INNGEST_SIGNING_KEY -p soleur -c dev --plain` ≠ `... -c prd --plain` (same for `INNGEST_EVENT_KEY`).
- [ ] **0.7** Commit phase: `chore(pr-f): adr-030 proposed + doppler env scaffolding`.

## Phase 1 — Migration 046 (atomic plpgsql kill-switch + drafts-everywhere CHECK constraint)

- [ ] **1.1** **RED**: write `apps/web-platform/test/server/migrations/046-runtime-cost-state.test.ts` covering:
    - **1.1.1** Schema assertions (`runtime_paused_at`, `runtime_cost_cap_cents`, function exists).
    - **1.1.2** Function security shape (`SECURITY DEFINER`, `search_path = public, pg_temp`, revokes).
    - **1.1.3** TOCTOU atomicity: 10 concurrent calls collectively crossing cap-boundary by 1 cent → EXACTLY one `kill_tripped=true`.
    - **1.1.4** CHECK constraint: INSERT into `messages` with `tier='external_brand_critical', status='sent'` raises `23514`; `status='draft'` succeeds.
    - **1.1.5** Cumulative correctness: `prior=1950, this=100, cap=2000` → `cumulative_cents=2050, kill_tripped=true`.
- [ ] **1.2** Run tests → all RED (confirm baseline).
- [ ] **1.3** Write `apps/web-platform/supabase/migrations/046_runtime_cost_state.sql` per plan §Phase 1 implementation. plpgsql with leading `SELECT ... FROM public.users WHERE id = p_founder_id FOR UPDATE`. CHECK constraint on `messages` for external tiers.
- [ ] **1.4 (GREEN)** Apply migration locally; all RED tests now pass.
- [ ] **1.5** Commit: `feat(runtime): migration 046 — atomic plpgsql kill-switch + drafts-everywhere CHECK (PR-F)`.

## Phase 2 — Inngest substrate (deps + client + serve route + writer-sweep alias extension)

- [ ] **2.1** **RED**: write `apps/web-platform/test/server/inngest/client-startup.test.ts`:
    - **2.1.1** Module load with `INNGEST_SIGNING_KEY` unset throws.
    - **2.1.2** Module load with `INNGEST_EVENT_KEY` unset throws.
    - **2.1.3** Module load with malformed `INNGEST_BASE_URL` throws.
    - **2.1.4** All-present load returns valid `Inngest` instance with `id: "soleur-runtime"`.
- [ ] **2.2** **RED**: write `apps/web-platform/test/server/inngest/signature-verify.test.ts`:
    - **2.2.1** Invalid signature → 401 BEFORE dispatch; `reportSilentFallback` mirrored.
    - **2.2.2** Stale timestamp (>5 min) → 401.
- [ ] **2.3** **RED**: write `apps/web-platform/test/fixtures/inngest-bypass-alias-rename.ts.fixture` containing `import { runWithByokLease as openLease } from "../../server/byok-lease"; openLease(...)`. Extend `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts` with `ALIAS_IMPORT_RE = /import\s*\{[^}]*\brunWithByokLease\s+as\s+\w+/`. Assert: fixture-loaded run classifies the alias file as sweepable AND fails the persistTurnCost-or-marker check.
- [ ] **2.4** Run tests → all RED.
- [ ] **2.5** Add `inngest@^3` to `apps/web-platform/package.json`. Regenerate `bun.lock` AND `package-lock.json` (both confirmed present 2026-05-17).
- [ ] **2.6** Write `apps/web-platform/server/inngest/client.ts` per plan §Phase 2 skeleton.
- [ ] **2.7** Write `apps/web-platform/app/api/inngest/route.ts` per plan §Phase 2 skeleton. Imports `cfoOnPaymentFailed` from Phase 3 file (will error until 3.6 — keep build green by stubbing or sequencing 3.6 before 2.7 in commit order).
- [ ] **2.8** Apply writer-sweep extension to the production test.
- [ ] **2.9 (GREEN)** All Phase 2 RED tests pass.
- [ ] **2.10** Commit: `feat(runtime): inngest substrate + writer-sweep alias-rename extension (PR-F)`.

## Phase 3 — CFO function `cfo-on-payment-failed.ts`

- [ ] **3.1** **RED**: write `apps/web-platform/test/server/inngest/cfo-on-payment-failed.test.ts`:
    - **3.1.1** Lease per `step.run`: mock step boundary; outer-scope lease must NOT survive; sync-escape (`byok-lease.ts:133-139`) verified.
    - **3.1.2** JWT mint per step: `getFreshTenantClient(event.data.founderId)` called inside each tenant-touching step; never cached across boundaries.
    - **3.1.3** Schema-gate (non-throwing step): `v: "2"` → `{deadletter: true}`, early-return; `v: "0"` → same; `v: "1"` → proceed. NO BYOK turn consumed on mismatch.
    - **3.1.4** Single-pass verify: implementation forbids splitting verify into a stepped artifact other steps consume by reference. Verify lives in function body.
    - **3.1.5** Verify 2s timeout → no draft; `reportSilentFallback` with `feature: "trust-tier-verify"`.
    - **3.1.6** Verify mismatch (live `succeeded` vs webhook `failed`) → no draft; no re-queue (PR-F shape).
    - **3.1.7** Cost-gate: `record_byok_use_and_check_cap` returns `kill_tripped=true` → function aborts at next step boundary.
    - **3.1.8** CEL concurrency: 5 events same founderId → exactly 1 runs, 4 blocked.
- [ ] **3.2** Run tests → all RED.
- [ ] **3.3** Write `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts` per plan §Phase 3 skeleton. Inline `PaymentFailedPayload` type (RV3). Inline `const TIER = "draft_one_click"` (RV4). Schema-gate as non-throwing `step.run`. Verify in function body. AbortSignal plumbed to SDK call.
- [ ] **3.4** Add helper at `apps/web-platform/server/cost-writer.ts` (or wherever `persistTurnCost` lives) to expose `recordByokUseAndCheckCap(invocationId, founderId, agentRole, tokenCount, unitCostCents)` calling the new RPC and returning `{cumulativeCents, killTripped}`.
- [ ] **3.5 (GREEN)** All Phase 3 RED tests pass.
- [ ] **3.6** Commit: `feat(runtime): cfo-on-payment-failed inngest function (PR-F)`.

## Phase 4 — Stripe webhook integration

- [ ] **4.1** **RED**: write `apps/web-platform/test/server/webhooks/stripe-payment-failed-inngest.test.ts`:
    - **4.1.1** `SOLEUR_FR5_ENABLED=false` → webhook returns 200, no `inngest.send`, existing log retained.
    - **4.1.2** `=true` → `inngest.send` fires with correct envelope after `processed_stripe_events` dedup.
    - **4.1.3** Redelivery (same `event.id`): `inngest.send` fires ONCE.
    - **4.1.4** Minimization: `event.data.payload` has NO `@`, NO `payment_method`; retains 4 fields.
    - **4.1.5** Inngest unreachable: `reportSilentFallback` fires; webhook returns 200.
- [ ] **4.2** Run tests → all RED.
- [ ] **4.3** Edit `apps/web-platform/app/api/webhooks/stripe/route.ts` at lines 415-426 per plan §Phase 4 skeleton. Inline minimization (hash `customer_email`, drop `payment_method`, keep `amount`/`currency`/`failure_code`/`invoice_id`).
- [ ] **4.4** Add `resolveFounderIdFromCustomer(customerId)` helper (or use existing if present).
- [ ] **4.5 (GREEN)** All Phase 4 RED tests pass.
- [ ] **4.6** Commit: `feat(runtime): wire stripe invoice.payment_failed to inngest CFO (PR-F)`.

## Phase 5 — Today section (route + banner + card)

- [ ] **5.1** **RED**: write `apps/web-platform/test/server/dashboard/today-route.test.ts`:
    - **5.1.1** `GET /api/dashboard/today` returns caller's `tier='external_brand_critical', status='draft'` messages only.
    - **5.1.2** RLS isolation: caller A never sees caller B's rows.
    - **5.1.3** Empty state: `{ items: [] }`.
- [ ] **5.2** **RED**: write `apps/web-platform/test/components/today-banner.test.tsx`:
    - **5.2.1** Renders the imported `RUNTIME_COST_DISCLOSURE` constant (gate via import, not free literal).
- [ ] **5.3** **RED**: write `apps/web-platform/test/components/today-card.test.tsx`:
    - **5.3.1** Renders source / owning leader / draft preview / urgency / Send / Edit / Discard.
- [ ] **5.4** Run tests → all RED.
- [ ] **5.5** Write `apps/web-platform/lib/legal/disclosures.ts` exporting `RUNTIME_COST_DISCLOSURE = "disclaims warranty for runtime cost"` constant.
- [ ] **5.6** Write `apps/web-platform/app/api/dashboard/today/route.ts` (HTTP handlers only). Inline `async function todayQuery(tenant, userId)` performs the tenant-scoped query (RV8). Route uses `getFreshTenantClient(auth.uid())`.
- [ ] **5.7** Write `apps/web-platform/components/dashboard/today-banner.tsx` rendering `RUNTIME_COST_DISCLOSURE`.
- [ ] **5.8** Write `apps/web-platform/components/dashboard/today-card.tsx` rendering source / leader / preview / urgency / 3 action buttons.
- [ ] **5.9** Edit `apps/web-platform/app/(dashboard)/dashboard/page.tsx`: add `useEffect` fetching `/api/dashboard/today` on mount; render `<TodayBanner />` once above the Today list; render `<TodayCard>` per row. Place ABOVE existing inbox + foundation sections.
- [ ] **5.10 (GREEN)** All Phase 5 RED tests pass.
- [ ] **5.11** Commit: `feat(runtime): /dashboard today section + banner disclosure (PR-F)`.

## Phase 6 — Legal amendments + ADR flip + preflight + review + merge

- [ ] **6.1** Amend `knowledge-base/legal/article-30-register.md`: add one paragraph describing new processing activity ("Autonomous agent triggers on Stripe failed-payment events; CFO leader drafts customer response inside founder's own runtime context on Hetzner-hosted Inngest server with SQLite persistence, no external sub-processor").
- [ ] **6.2** Amend `docs/legal/data-protection-disclosure.md`: add one bullet under existing processing-activities section.
- [ ] **6.3** Amend `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`: mirror bullet (CLO finding 2 copies).
- [ ] **6.4 (AC)** Verify: `git diff -- knowledge-base/legal/sub-processors.md docs/legal/sub-processors.md 2>/dev/null` shows ZERO changes (self-hosted Inngest = no new sub-processor).
- [ ] **6.5** Flip ADR-030 status: `status: proposed` → `status: accepted`.
- [ ] **6.6** Commit: `docs(pr-f): article 30 + DPD amendments + adr-030 accepted`.
- [ ] **6.7** Run `/soleur:preflight` → green; Check 6 fires on sensitive paths.
- [ ] **6.8** Run `/soleur:gdpr-gate` against the diff → no Critical findings.
- [ ] **6.9** Run `/soleur:qa` → functional verification green.
- [ ] **6.10** Mark PR #3940 ready: `gh pr ready 3940`.
- [ ] **6.11** Invoke `/soleur:review` — multi-agent review including `user-impact-reviewer` (mandatory per brand-survival threshold).
- [ ] **6.12** Resolve all P1/P2 review findings inline OR explicitly scope-out with tracking issue.
- [ ] **6.13** Verify `user-impact-reviewer` summary visible in PR review thread.
- [ ] **6.14** `gh pr merge --auto --squash 3940`.

## Post-merge (operator)

- [ ] **P1** Install `inngest-cli` on Hetzner host (pinned release tag).
- [ ] **P2** Configure systemd unit `inngest-server.service`:
    ```
    [Service]
    ExecStart=/usr/local/bin/inngest start \
      --host 127.0.0.1 \
      --event-key ${INNGEST_EVENT_KEY} \
      --signing-key ${INNGEST_SIGNING_KEY}
    Restart=always
    EnvironmentFile=/etc/inngest/env
    ```
- [ ] **P3** Verify port binding: `ss -tlnp | grep -E '8288|8289'` shows `127.0.0.1` only (NOT `0.0.0.0`).
- [ ] **P4** Set `SOLEUR_FR5_ENABLED=true` in Doppler `prd` and restart Node app.
- [ ] **P5** Send a synthesized Stripe `invoice.payment_failed` from operator's own Stripe TEST mode against operator's own customer record. Verify CFO Today card appears within ~60s.
- [ ] **P6** Verify `audit_byok_use` row written for the CFO turn(s) via Supabase Studio query.
- [ ] **P7** Wire Better Stack Incidents on-call rotation (free tier) to alert on:
    - Inngest server outage (process down OR port 8288 unreachable)
    - `runtime_paused_at` flip events (per-tenant cost cap exceeded)
- [ ] **P8** Close follow-up tracking only after P1–P7 verified.

## Cross-cutting (any phase)

- [ ] **X1** Every commit message includes `Ref #3244` (NOT `Closes` — umbrella stays open for PR-G).
- [ ] **X2** PR body links: brainstorm, spec, plan v2, ADR-030, predecessor PRs, follow-up issues #3947 + #3948.
- [ ] **X3** Run `compound` skill at end of work to capture any plan-time learnings (e.g., the v1→v2 reviewer-driven simplification pattern if novel).

## Risk Watchpoints (carry-forward from plan)

| Risk | Watch during | Verification |
|------|--------------|--------------|
| R1 ALS escape across step.run | Phase 3.1.1 test | Sync-escape throws confirmed |
| R2 sends-nowhere slip | Phase 1.1.4 test | CHECK constraint rejects `status='sent'` for external tiers |
| R3 kill-switch race | Phase 1.1.3 test | 10-concurrent atomicity exact-once |
| R5 verify staleness | Phase 3.1.4 test | Verify recomputed per retry path |
| R9 port-binding | Post-merge P3 | `ss -tlnp` shows 127.0.0.1 only |
