---
date: 2026-05-21
topic: periodic workspace reconciliation with main
issue: 4224
pr: 4226
status: complete
lane: cross-domain
brand_survival_threshold: single-user incident
domain_leaders: [cpo, clo, cto]
---

# Workspace Reconciliation with Main — Brainstorm

## What We're Building

A background reconciliation path that pulls the operator's connected default branch into their server-side workspace clone (`userData.workspace_path`) on every `push` event, so the webapp KB viewer (`app.soleur.ai/dashboard/kb`) reflects merges to main without requiring the operator to start a chat session or perform a KB mutation. The bundle also surfaces a staleness signal in the KB viewer header so the operator never has to guess freshness, and sweeps Sentry-mirroring across all three existing `syncWorkspace` callers — two of which silently swallow failures today.

## Why This Approach

**Approach A (extend webhook strategy table with `push` action class) won unanimously across CPO + CLO + CTO.**

- **CPO:** Only option that defends the seconds-level user-truth-floor. B and C both encode a staleness budget as policy.
- **CLO:** Lowest credential blast radius (per-event `installation_id`, no iteration loop). Cleanest lawful basis under Art 6(1)(b) — the trigger is the operator's own GitHub-signed act. Reuses existing `processed_github_events` dedup and `audit_github_token_use` ledger. No new consent surface required.
- **CTO:** Reuses the polymorphic webhook strategy table from PR-H #3244. GitHub redelivery + existing dedup row absorbs ~99% of delivery loss; the residual gap does not justify shipping a cron backstop unprovable.

Substrate already exists on `main`:

- `apps/web-platform/app/api/webhooks/github/route.ts` — webhook handler (PR-H #3244 Phase 3), installation→founder routing, signature verification, dedup.
- `apps/web-platform/server/inngest/functions/github-on-event.ts` — strategy-table fan-out for the 4 existing action classes.
- `apps/web-platform/server/kb-route-helpers.ts:282` — reusable `syncWorkspace(installationId, workspacePath, log, ctx)` that does `git pull --ff-only` via `gitWithInstallationAuth`.
- `apps/web-platform/server/session-sync.ts:326,389` — existing `syncPull` / `syncPush` for session-boundary, plus `recordKbSyncHistory` (`session-sync.ts:266`) writing to `users.kb_sync_history` JSONB.

The work is a fifth strategy row, not new infrastructure.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | **Approach A (push webhook → Inngest → syncWorkspace)** as primary | Unanimous leader recommendation; lowest blast radius; reuses existing substrate |
| 2 | **Include UI staleness signal in scope** ("Synced N ago" badge + manual "Sync now" button in KB viewer header) | CPO: backend alone is a partial fix — swaps "definitely stale" for "probably fresh, no way to confirm" |
| 3 | **Sentry-mirror sweep across ALL three `syncWorkspace` callers**, not just the new one | Per `cq-silent-fallback-must-mirror-to-sentry`. CTO flagged existing two callers as silently broken; fix inline, don't defer |
| 4 | **Per-`installation_id` in-process mutex** to coalesce concurrent pulls | `git index.lock` collision otherwise surfaces as noisy `{ok:false}` + Sentry alert; pulls are idempotent so coalescing is correct |
| 5 | **Unified `kb_sync_history` JSONB rows** with `trigger: "session" \| "kb_mutation" \| "webhook_push"` discriminator | One audit timeline per operator; splitting columns by trigger fragments the audit story |
| 6 | **Default-branch filter from webhook payload** (`repository.default_branch`), NOT hardcoded `main` | Operator's default branch is whatever GitHub reports for their repo |
| 7 | **`git pull --ff-only` is sacred** — no auto-reset, no auto-rebase | Desync surfaces as operator-visible error, never silent data loss |
| 8 | **Article 30 PA-17 cell amendment + DPD §2.3(r) sentence at PR-merge time** | Sub-processor recipient unchanged (GitHub Inc.); reconciliation extends timing of an inventoried processing activity, not its categories |
| 9 | **Reuse `audit_github_token_use` ledger** with `sync_source` attribution for per-event audit writes | Migration 052 already has WORM trigger + Art. 17 cascade — do not create a new audit table |
| 10 | **`assertWriteScope`-equivalent test** on the `installation_id → user_id → workspace_path` boundary | CLO load-bearing TOM under Art. 32: if reconciliation writes to the wrong operator's workspace path, that is a notifiable breach |
| 11 | **Defer cron backstop (Approach B)** gated on 30-day webhook-delivery telemetry showing >0.1% drift | File as deferred-scope-out issue. Telemetry MUST ship in this PR — without `(installation_id, push_received_at, sync_completed_at, sync_result)` rows, the deferral has no exit criterion |
| 12 | **Reject Approach C (lazy sync on `/api/kb/tree`)** | Couples sync to read path; degrades p99 unpredictably on cold workspace; encodes staleness budget as policy |
| 13 | **No new consent surface** ("background sync" toggle) | CLO: covered by existing operator-data agreement under Art. 6(1)(b); adding a toggle would actively misrepresent existing PA-2/PA-17 contract framing |

## Open Questions

1. **Debounce window for rapid pushes?** CTO recommended relying on `--ff-only` idempotency over a 5s coalescing window — confirm at plan time. The mutex (decision 4) handles overlap; debounce is the next question if observed.
2. **`kb_sync_history` JSONB array cap.** CTO suggested last 100 entries to bound row size; need to confirm against existing `recordKbSyncHistory` truncation behavior.
3. **`workspace_desync` UI affordance** when `--ff-only` fails (force-push / non-ff state). Decision 2 covers the freshness badge; the desync-recovery affordance ("workspace out of sync — reconnect") is a separate UX surface that should land in this PR if implementation cost is low, or a follow-up if it requires a new flow.
4. **Telemetry source-of-truth.** Is `kb_sync_history` adequate for the 30-day drift analysis (decision 11), or do we need a separate `webhook_delivery_metrics` table? Plan-time decision.

## Domain Assessments

**Assessed:** Product (CPO), Legal (CLO), Engineering (CTO). Operations / Sales / Finance / Marketing / Support not relevant to this internal sync feature.

### Product (CPO)

**Summary:** Approach A is the only option that holds the seconds-level user-truth-floor; B and C reframe a correctness bug as an SLA. UI staleness signal MUST be in scope — backend without signal is a partial fix. Cross-tenant concern is a test obligation (assert founder lookup is install-scoped and fails closed), not a design constraint. Reject "sync now button only" as standalone — shifts correctness burden to operator vigilance.

### Legal (CLO)

**Summary:** Approach A wins on legal grounds — per-event installation_id scoping = lowest credential blast radius; trigger is operator's signed GitHub act = cleanest lawful basis under Art. 6(1)(b). Reconciliation is not a new processing activity; PA-17 cell amendment + DPD §2.3(r) sentence suffice (deferrable to PR-merge time). Approach B's iteration loop is a new credential-iteration surface that would require `assertWriteScope`-equivalent CI sentinel. Approach C is identical to existing session-sync legally. Load-bearing TOMs: write-scope assertion, audit ledger reuse, Sentry-mirror failures.

### Engineering (CTO)

**Summary:** Ship A only; defer B explicitly behind 30-day telemetry; reject C. Default branch from webhook payload, NOT hardcoded. `--ff-only` is sacred. Sentry-mirror sweep across all three callers is non-negotiable (existing two are silently broken — workflow gate: fix inline). Per-installation mutex coalesces concurrent pulls. Unified `kb_sync_history` rows with `trigger` discriminator. No ADR required — adding a third sync trigger does not change architecture. **Note:** CTO's "substrate verification BLOCKER" claim was a false negative caused by stale CWD/branch state in the agent's read; all cited files verified present on the worktree HEAD before this brainstorm document was written.

## Capability Gaps

None identified. All required substrate exists on `main` (verified via `ls` + targeted `grep` from the worktree at HEAD `8923ba78`, off `origin/main` `e3502145`):

- Webhook handler: `apps/web-platform/app/api/webhooks/github/route.ts` (197 LOC matched `installation` / `push` / `workspace` patterns).
- Inngest strategy table: `apps/web-platform/server/inngest/functions/github-on-event.ts` (4 existing action classes via `GITHUB_EVENT_STRATEGIES`).
- `syncWorkspace`: `apps/web-platform/server/kb-route-helpers.ts:282`.
- `syncPull` / `syncPush` + `recordKbSyncHistory`: `apps/web-platform/server/kb-route-helpers.ts` → `session-sync.ts:326,389,266`.
- Audit ledger: `audit_github_token_use` (migration 052, WORM + Art. 17 cascade).
- Dedup: `processed_github_events` table.

## User-Brand Impact

- **Artifact exposed:** stale KB tree contents in the webapp KB viewer (deletions / renames / uploads on operator's default branch not reflected; merges to main missing).
- **Vector:** server-side workspace clone falls behind operator's connected default branch with no UI signal of staleness. Operator may act on stale source-of-truth (trust breach) — e.g., reference a deleted policy file the viewer still shows.
- **Brand-survival threshold:** single-user incident. Operator endorsed all three failure modes including cross-tenant / credential exposure during sync — escalating from the issue body's original "none" floor. Mitigated by: (a) install-scoped `gitWithInstallationAuth` (existing), (b) `assertWriteScope`-equivalent test on `installation_id → user_id → workspace_path` boundary (load-bearing, this PR), (c) per-installation mutex (no overlap across operators since each mutex key is installation-scoped), (d) Sentry-mirror sweep across all three callers so silent failures surface.

## Productize Candidate

None. Workspace reconciliation is a one-shot infrastructure addition; the work pattern is not recurring.
