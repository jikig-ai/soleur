---
adr: 030
title: Inngest as durable trigger layer for server-side agents
status: accepted
date: 2026-05-17
related: [3244, 3940, 3947, 3948, 5450]
related_adrs: [ADR-005, ADR-023, ADR-027, ADR-046]
related_plans:
  - knowledge-base/project/plans/2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md
  - knowledge-base/project/plans/2026-05-17-feat-pr-f-inngest-trigger-layer-plan.md
brand_survival_threshold: single-user incident
---

# ADR-030: Inngest as durable trigger layer for server-side agents

## Status

**Accepted** (2026-05-17, PR #3940).

Flipped from `proposed` at Phase 6 of `2026-05-17-feat-pr-f-inngest-trigger-layer-plan.md` after the substrate landed green: Inngest client + serve route (Phase 2), CFO function with single-pass verify + per-step lease (Phase 3), Stripe `invoice.payment_failed` → `inngest.send` bridge gated by `SOLEUR_FR5_ENABLED` (Phase 4), `/api/dashboard/today` + page-level disclosure banner (Phase 5).

## Context

PR-A through PR-E (#3240, #3395, #3854, #3883, #3922) shipped the security/isolation hardening required to safely run autonomous agents on behalf of multiple founders: user-scoped Supabase JWT minting, `audit_byok_use` writer at every BYOK SDK call path, `is_jti_denied` JWT-mint consumer, RLS-bound attachments. The runtime is now safe to run *synchronous* workloads on behalf of a logged-in founder.

The parent epic (#3244) calls for *autonomous* leaders that react to inbound events while the founder sleeps:

- Inbound-event-to-leader pipelines (Stripe failed-payment, GitHub issue created, KB drift detected).
- Cross-domain priority arbitration ("Today" surface).
- Cron-driven background analyses.

Without a durable trigger substrate, these are unbuildable. PR-F (this slice) chooses the substrate.

Brand-survival threshold: `single-user incident`. Operator (2026-05-17) confirmed all-of-the-above failure framing — cross-tenant data leak, BYOK credential leak, wrong-action while founder sleeps, billing surprise. The substrate decision is load-bearing for all four vectors.

## Decision

**Adopt Inngest as the durable trigger layer for server-side agents. Deploy the OSS `inngest` server binary (`inngest start`) self-hosted alongside the existing Node process on the Hetzner host. ~~SQLite for state persistence (alpha-default).~~ Bound to `127.0.0.1` only.**

> **Amended 2026-06-17 (#5450, `adopting`).** State/queue persistence flipped from bundled SQLite + in-memory Redis (ephemeral root disk) to **Supabase Postgres** (`--postgres-uri`, dedicated EU project `soleur-inngest-prd`, Supavisor **session pooler :5432**) for config/history **+ self-hosted Redis** (`--redis-uri`, AOF on the persistent `/mnt/data` volume) for the durable queue/run-state. This executes the Postgres migration this ADR deferred (see Trade-offs). Empirically required: the Phase-0 spike proved Postgres-alone loses armed future-`ts` reminders on a host re-provision; durable Redis is what survives (runbook § Durable backend). `status: adopting` until the Phase-2 cutover wiped-volume invariant verifies in prod.

The Node application uses `inngest@^3` SDK and exposes `/api/inngest` via `serve()`. Events are sent via `inngest.send(...)` to the local server endpoint `http://127.0.0.1:8288`.

## Rejected alternatives

### Inngest Cloud (Hobby / Pro)

**Rejected.** Routing founder-tagged event payloads (Stripe `customer_email`, draft response text, `founderId`) through Inngest Cloud creates a 5th sub-processor and a corresponding DPA / Article 30 / Privacy Policy / DPD / GDPR Policy / sub-processor-page / breach-runbook update cycle. PR-B→E spent five increments keeping founder data off external substrates inside the EU-only Hetzner posture; inverting that ladder for alpha velocity contradicts the brand-survival threshold.

**Re-evaluation criteria** (operator-confirmed):

1. **Concurrency cap pressure.** Hobby tier limits to 5 concurrent steps; Pro is $75/mo (corrected from umbrella spec's $25 — verified at plan time). When self-hosted concurrency on the Hetzner box becomes the bottleneck OR a tenant-cost-fairness primitive requires Cloud-hosted multi-tenant queuing, re-open.
2. **Third hosted founder onboarded.** At 3 active founders, the operational cost of running the OSS Inngest server (process supervision, upgrades, SQLite-to-Postgres migration if needed, debugging UI absence) MAY exceed the legal-surface cost of a 5th sub-processor. Re-evaluate.

### LangGraph + custom orchestration

**Rejected.** Operationally heavy (separate worker pool, separate state store, separate retry semantics). Forces a duplicate "what's next" implementation alongside the existing `step.run` model. Inngest's batteries-included primitives (concurrency CEL, schema versioning, signed webhooks, replay-window, dashboard) ship correctness PR-F would otherwise hand-roll.

### Bedrock AgentCore (AWS)

**Rejected.** AWS vendor lock; no EU-residency parity with the current Hetzner posture; would add AWS as a sub-processor (same disclosure cycle as Inngest Cloud above).

### Cloudflare Durable Objects + LISTEN/NOTIFY

**Rejected.** Cannot host the Claude Agent SDK long-running process (DO execution model is incompatible with multi-minute SDK turns). LISTEN/NOTIFY in Supabase Postgres lacks durable replay and would require custom dead-letter + retry implementation on top.

## Load-bearing invariants

The following invariants are LOAD-BEARING. Violation = brand-survival regression at `single-user incident` threshold. Each is enforced by code, test, or DB constraint per PR-F's implementation plan.

### I1 — BYOK lease opened INSIDE each `step.run` that calls the Anthropic SDK

`AsyncLocalStorage` at `apps/web-platform/server/byok-lease.ts:115` does NOT survive across Inngest step-replay boundaries. Every `step.run("name", async () => { ... })` that calls the SDK MUST open its own `runWithByokLease(founderId, async (lease) => { ... })` scope. Outer-scope lease reuse triggers the sync-escape check at `byok-lease.ts:133–139` → `ByokLeaseError("escape")` → fail-closed.

**Enforced by:** the existing `byok-audit-writer-sweep.test.ts` CI sentinel + the new alias-rename extension (RV3 / Phase 2 of PR-F plan).

### I2 — User-scoped Supabase JWT minted INSIDE each `step.run` that touches tenant data

`getFreshTenantClient(event.data.founderId)` runs per-step. The `is_jti_denied` consumer at `apps/web-platform/lib/supabase/tenant.ts:341` fires automatically on every fresh-client call. **Never cache JWTs across step boundaries via `event.data` or step return values.**

**Enforced by:** code review at PR-F Phase 3 + Phase 4 tests.

### I3 — Singleton concurrency per founderId (per function-name)

Each Inngest function declares `concurrency: [{ scope: "fn", key: "event.data.founderId", limit: 1 }]`. Function-name namespace is implicit (each function triggers on one event-name; Inngest v3 has no wildcard triggers).

**Enforced by:** the CEL key in the function declaration + a test asserting 5 events same `founderId` → exactly 1 runs, 4 blocked.

### I4 — Signature verification REQUIRED at startup

`serve()` is configured with `signingKey: process.env.INNGEST_SIGNING_KEY`. Missing key = throw at process boot, NOT log-and-continue. The Inngest server binary also requires the key, read from the `INNGEST_SIGNING_KEY` **environment variable** (the `signkey-prod-` prefix stripped for the self-hosted server) — see I7; it is NOT passed on argv.

**Enforced by:** `apps/web-platform/server/inngest/client.ts` module-load throw + `apps/web-platform/app/api/inngest/route.ts` module-load throw.

### I7 — Server secrets delivered via the environment, never argv (#5560)

inngest-server reads `INNGEST_POSTGRES_URI`, `INNGEST_REDIS_URI`, `INNGEST_SIGNING_KEY`, and `INNGEST_EVENT_KEY` from the **inherited environment** (`doctor`/self-hosting docs), never the `inngest start` argv. argv is world-readable via `/proc/<pid>/cmdline` (mode 0444); the env is owner-only (`/proc/<pid>/environ`, mode 0400). The `inngest-bootstrap.sh` ExecStart therefore passes **no** secret flag — `--signing-key`/`--event-key`/`--postgres-uri`/`--redis-uri` are all absent; the doppler-run wrapper injects the values, with `INNGEST_REDIS_URI` constructed from `INNGEST_REDIS_PASSWORD` and `INNGEST_SIGNING_KEY` re-exported stripped. The durable backend is detected on argv by the **non-secret** `--postgres-max-open-conns` sentinel (ci-deploy.sh, inngest-inventory.sh, inngest-wiped-volume-verify.sh). The SQLite-only fail-safe `unset INNGEST_POSTGRES_URI` so inngest does not connect to Postgres when Redis is unready.

**Enforced by:** `apps/web-platform/infra/inngest.test.sh` (#5560 security invariant: ExecStart carries no secret flag + uses `exec`) + the durability drift-guard in `inngest-inventory.test.sh`.

### I5 — "Drafts everywhere, sends nowhere" — DB-level CHECK constraint AND code

The `messages_external_tier_status_check` constraint on `public.messages` (migration 046) enforces `status IN ('draft', 'archived')` for `tier IN ('external_brand_critical', 'external_low_stakes')`. Any future code attempting to INSERT `status='sent'` on an external-tier row is rejected at DB level with SQLSTATE 23514.

**Future auto-send capability** (e.g., a class that would transition from `draft` → `sent` for an external tier) requires (a) explicit migration to DROP and replace this constraint, (b) Article 22(3) right-to-human-review notice and DPD update, (c) re-amendment of this ADR.

**Enforced by:** Postgres CHECK constraint + Phase 1 test.

### I6 — Verify-external-state is single-pass-only

`step.run` memoizes results. On a 6h-deadlettered retry, a checkpointed verify result becomes stale (Stripe state may have moved `failed → succeeded → refunded`). PR-F's CFO function therefore does NOT split verify into a `step.run` artifact that downstream steps consume by reference; verify lives in the function body and is recomputed on each pass.

Any future code adding a step.run-checkpointed verify whose result feeds a downstream draft MUST first amend this ADR to either (a) split verify into a watchdog + last-call-before-fire pattern, or (b) bound the deadletter window such that staleness is acceptable.

**Enforced by:** code review at PR-F Phase 3 + a test asserting any retry path re-enters from verify.

## Implementation references

- Plan: `knowledge-base/project/plans/2026-05-17-feat-pr-f-inngest-trigger-layer-plan.md` (v2, post-review)
- Spec: `knowledge-base/project/specs/feat-pr-f-inngest-trigger-layer/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-17-pr-f-inngest-trigger-layer-brainstorm.md`
- Parent plan (Increment 3 is PR-F): `knowledge-base/project/plans/2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md` §3.1–3.5
- Parent epic: [#3244](https://github.com/jikig-ai/soleur/issues/3244)
- Predecessor PRs (all MERGED, verified /work Phase 0.1 2026-05-17): #3240, #3395, #3854, #3883, #3922
- Follow-up issues: #3947 (PR-G cohort onboarding), #3948 (cron migration TR9)

## Trade-offs accepted

- **Operational cost.** Self-hosted Inngest adds a sidecar process (systemd unit, upgrade cadence, no debugging UI for non-Pro). Mitigated by: SQLite default (zero new persistence config), `Restart=always`, `127.0.0.1` binding.
- **No Cloud dashboard.** The OSS server has a basic UI; not the Pro debugging surface. Acceptable for alpha (operator + 1 dogfood founder). Re-evaluate per criteria above.
- **SQLite single-host limitation.** ~~State persistence is local-disk; no high-availability. Mitigated by: Hetzner backups, Inngest's redelivery semantics (Stripe redelivers webhooks for ~3 days; missed events recoverable). Migration to Postgres-backed Inngest deferred to future PR if/when warranted.~~ **Corrected + resolved 2026-06-17 (#5450):** the "Hetzner backups" mitigation was falsified — `hcloud_server.web` carries `lifecycle { ignore_changes = [user_data, ssh_keys, image] }` (server.tf), so SQLite state is NOT lost on every `terraform apply`; it is lost only on an explicit `terraform apply -replace` (or a replace-forcing change), which boots a fresh root disk with **no backup restore path** (Hetzner volume snapshots cover `/mnt/data`, not the root disk where SQLite lived). Rarer than implied, but real and silent — and the redelivery semantics do NOT cover HTTP-armed `event-scheduled-reminder` events (they have no upstream to redeliver). **Resolved** by the durable-backend amendment above. The deferral's re-eval trigger fired not on the original "3rd founder / 5th-sub-processor" criterion but on the **#5450 durability gap**; the migration adds **no new sub-processor** (Supabase is already the primary DB + an existing sub-processor; Redis is self-hosted on our own host), which dissolves the deferral's sole legal-surface objection.
- **Availability coupling (new, permanent — #5450).** Post-cutover Inngest **cannot start** without Supabase + Redis reachable (the in-memory fallback is gone — proven fail-closed in the Phase-0 spike). Pre-migration it survived a Supabase outage on local SQLite; it no longer will. Knowingly traded for durability + Supabase PITR + closing this deferral. The dedicated Inngest Supabase project + co-located Redis keep the blast radius off the main app's project.

## Updates / amendment log

- **2026-06-18 (#5560) — secrets via environment, not argv (security hardening; no backend change).** The durable-backend ExecStart (#5450) expanded `INNGEST_POSTGRES_URI` / `INNGEST_REDIS_PASSWORD` / `INNGEST_SIGNING_KEY` / `INNGEST_EVENT_KEY` into the `inngest start` argv, exposing them via world-readable `/proc/<pid>/cmdline`. Hardened to env-delivery (new invariant **I7**): inngest reads all four from the inherited (owner-only) environment; the ExecStart passes no secret flag. Durable detection moved from the now-env-only `--postgres-uri`/`--redis-uri` argv substrings to the non-secret `--postgres-max-open-conns` sentinel across all three runtime parsers (kept lockstep by the existing drift-guard). The SQLite-only fail-safe `unset INNGEST_POSTGRES_URI`. No backend, sub-processor, or C4 change (secret-delivery is an attribute of the already-modeled `doppler -> inngest "Injects secrets"` edge). Exposed creds rotated post-deploy (`terraform taint` for Redis; Supabase Management API for the inngest-project Postgres password).
- **2026-06-17 (#5450, PR #5459) — durable backend; `status: adopting`.** Flipped state/queue persistence from SQLite + in-memory Redis to **Supabase Postgres (dedicated EU project, session pooler :5432) + self-hosted Redis (AOF on /mnt/data)**; see the amended `## Decision` + `## Trade-offs accepted`. Corrected the falsified "Hetzner backups" mitigation (root-disk SQLite is not backed up; loss trigger is `terraform apply -replace`, not every apply). Recorded the "Supabase already a sub-processor → no 5th sub-processor" reframe (the deferral's sole objection) and the new permanent **availability-coupling** trade-off (in-memory fallback removed → fail-closed on backend down). Phase-0 spike verdicts in `knowledge-base/engineering/operations/runbooks/inngest-server.md` § Durable backend. **Cross-ref ADR-046:** its "bounded by single-host SQLite durability (ADR-030)" line now points at the durable backend; the boot-arm/re-arm-every-deploy (ADR-046 I4) remains correct as the dedup-window recovery path — NOT made redundant. Reverts to `accepted` once the Phase-2 cutover wiped-volume invariant verifies in prod.
- **2026-06-17 (#5450) — no-SSH cutover orchestration (execution mechanism, no new decision).** The Phase-2 cutover's host-side steps (enumerate still-armed reminders; the opt-in wiped-volume durability verify) run through **HMAC-gated webhook hooks** on the existing `deploy.soleur.ai` ingress + a `workflow_dispatch` driver (`.github/workflows/cutover-inngest.yml`), mirroring the `infra-config` / `restart-inngest-server` pattern — NOT operator SSH (`hr-no-ssh-fallback-in-runbooks`) and NOT the `ci-deploy.sh` 4-field command parser. New host scripts (`inngest-enumerate-reminders.sh`, `inngest-rearm-reminders.sh`, `inngest-wiped-volume-verify.sh`, `cat-inngest-verify-state.sh`) reach `/usr/local/bin` via the no-SSH `infra-config` push (FILE_MAP↔DEST_SPEC lockstep); the stop/start sudoers grant (B3) is root-managed. No new sub-processor and **no new secret** (reuses `WEBHOOK_DEPLOY_SECRET` + CF-Access). This is the execution surface for the durable-backend decision above, not a new architectural decision. C4: no model change (the `deploy.soleur.ai`→host webhook edge already exists; no `.c4` enumerates individual hooks).
