---
name: feat-pino-userid-redaction-3698
issue: 3698
related: [3638, 3685, 3696]
lane: cross-domain
brand_survival_threshold: single-user incident
date: 2026-05-12
status: ready-for-plan
---

# Feature: pino userId pseudonymisation at logger boundary (#3698)

## Problem Statement

PR #3685 centralised server-side `userId → userIdHash` pseudonymisation inside the silent-fallback helpers (`reportSilentFallback`, `warnSilentFallback`, `mirrorP0Deduped` in `apps/web-platform/server/observability.ts`). Multi-agent review identified that ~10 direct `logger.error|warn|info|debug({ userId, ... })` call sites in `apps/web-platform/app/api/**/route.ts` and `apps/web-platform/app/(auth)/callback/route.ts` bypass the helpers and continue to emit raw `user_id` to pino stdout on the Hetzner Finland container host. PA8 §(c) Article 30 register was narrowed inline in #3685 to scope the pseudonymisation claim to the helper boundaries, with a forward-reference to this issue. The remaining direct emissions violate GDPR Art. 5(1)(c) data minimisation and produce a continuing Art. 30(1) register-accuracy gap until closed.

## Goals

- Pseudonymise `userId` at the pino logger boundary so all direct call sites emit `userIdHash` without per-site edits.
- Preserve operator grep capability via the hash (operator computes hash via CLI + greps Hetzner stdout).
- Update PA8 §(c) Article 30 register to a truthful single-path description immediately after merge.
- Pin PA8 §(f) Hetzner pino retention window (currently a "re-confirm" placeholder).
- Bundle `Sentry.setUser({id: hashUserId(user.id)})` middleware so Sentry events auto-carry pseudonymous identity (none exists today).
- Migrate the 10 known direct call sites to the silent-fallback helpers so each gets Sentry mirror per `cq-silent-fallback-must-mirror-to-sentry`.
- Add operator hash-user-id CLI for runbook coherence.

## Non-Goals

- Client-side `lib/client-observability.ts` pseudonymisation — tracked as #3696, ships AFTER this PR per CLO sequencing.
- `docs/legal/data-protection-disclosure.md` §(l) telemetry user-facing disclosure entry — pre-existing gap surfaced by CLO; separate follow-up issue (filed at Phase 3.6).
- Pepper rotation infrastructure / runbook — explicitly deferred in parent #3638 brainstorm (YAGNI).
- `security_events` durable audit-log table (Art. 33(5) 6y retention) — distinct legal basis, parent #3638 deferred.
- Pino → Better Stack shipping — pino stays Hetzner-stdout-only; no off-host log copies introduced by this PR.

## Functional Requirements

### FR1: pino `formatters.log()` rename hook

Add a `formatters.log` config to the pino instance in `apps/web-platform/server/logger.ts` that:

1. Receives each log object before redact runs.
2. Detects keys `userId` and `user_id` at top level AND one level deep in nested objects (e.g., `extra.userId`, `context.userId`, `request.userId`).
3. Computes `userIdHash = hashUserId(String(value), pepper)` via the existing helper in `apps/web-platform/server/observability.ts`.
4. Replaces the original key with `userIdHash` (drops the raw key entirely).
5. Falls back to the sentinel `"pepper_unset"` when `SENTRY_USERID_PEPPER` is missing (mirroring `observability.ts:35-37`).
6. Handles edge cases: `null`/`undefined` value (skip transform), non-string value (coerce via `String()`), missing key (no-op pass-through).

### FR2: Operator hash-user-id CLI

Add `apps/web-platform/scripts/hash-user-id.ts` (~5 lines) that reads the first CLI arg, computes `createHmac("sha256", process.env.SENTRY_USERID_PEPPER!).update(arg).digest("hex")`, prints to stdout. Wire `pnpm hash-user-id <uuid>` as a package script in `apps/web-platform/package.json`. Operator usage: `doppler run -p soleur -c prd -- pnpm hash-user-id <uuid>` returns the hex hash for `grep <stdout>`.

### FR3: Sentry `setUser` middleware binding

Add a server middleware (Next.js route-handler wrapper OR `apps/web-platform/instrumentation.ts`, TBD at plan time) that calls `Sentry.setUser({id: hashUserId(user.id)})` when a session is available. Today no `Sentry.setUser` call exists anywhere (verified). After this PR, every Sentry event auto-carries `user.id = <hash>` for free.

### FR4: Migrate 10 app/ call sites to helpers

Migrate each of the 10 direct `logger.error|warn|info|debug({ userId, ... })` sites in `apps/web-platform/app/api/**/route.ts` and `apps/web-platform/app/(auth)/callback/route.ts` to `reportSilentFallback`/`warnSilentFallback` for `error|warn` (sites that fit the silent-fallback shape) or `mirrorP0Deduped` (sites that are P0-mirror-shaped). For `info|debug` sites that don't fit either shape, keep the direct `logger.*` call — FR1's `formatters.log` covers them as defence-in-depth.

Known sites (from `git grep -nE '(log|logger)\.(error|warn|info|debug).*\buserId\b' apps/web-platform/app/`):

- `apps/web-platform/app/(auth)/callback/route.ts:310`, `:323`
- `apps/web-platform/app/api/services/route.ts:103`, `:133`, `:198`
- `apps/web-platform/app/api/workspace/route.ts:68`
- `apps/web-platform/app/api/webhooks/stripe/route.ts:180`
- `apps/web-platform/app/api/repo/setup/route.ts:196`
- `apps/web-platform/app/api/auth/github-resolve/callback/route.ts:153`
- `apps/web-platform/app/api/accept-terms/route.ts:73`

Plan-time task: re-run the grep to confirm inventory hasn't drifted since 2026-05-12.

### FR5: PA8 §(c) Article 30 register update

Replace the current `knowledge-base/legal/article-30-register.md:157` PA8 §(c) §(ii) wording with a single-path explanation: pseudonymisation now happens at the pino logger boundary for all direct sites (via `formatters.log`) AND at the helper extras boundary (via `observability.ts`). No "follow-up migration" forward-reference. Draft wording in brainstorm doc.

### FR6: PA8 §(f) Hetzner pino retention window pin

Investigate concrete Hetzner journalctl / Docker log-driver retention window via SSH to the prod host. Document the window in `knowledge-base/legal/article-30-register.md:162` PA8 §(f). If unbounded or weeks-long, the brainstorm's "natural age-out satisfies Art. 17" framing needs revisiting and CLO must re-sign-off.

## Technical Requirements

### TR1: Reuse existing pseudonymisation primitives

- Hashing function: `hashUserId(userId, pepper?)` from `apps/web-platform/server/observability.ts:35`. Do NOT introduce a parallel hash function.
- Doppler secret: `SENTRY_USERID_PEPPER`. Already module-cached at `observability.ts:5`; no per-emit Doppler round-trip.
- Fail-closed sentinel: `"pepper_unset"`. Mirror `observability.ts:35-37`. The recursive walker must emit the sentinel for the `userIdHash` field when the pepper is unset.

### TR2: pino `formatters.log()` placement

Single edit to `apps/web-platform/server/logger.ts`. The `formatters.log` runs BEFORE `redact`, so it must NOT also wire `userId` into `REDACT_PATHS` — that would double-process. Confirm at plan time via pino docs (`pino.d.ts:470`).

### TR3: Test fixture surface (synthesised only per `cq-test-fixtures-synthesized-only`)

Test cases for the `formatters.log` hook:

- Top-level `userId` key — hashed.
- Top-level `user_id` key — hashed.
- Nested `extra.userId` — hashed.
- Nested `context.userId` — hashed.
- Nested `request.userId` — hashed.
- Missing pepper — emits `userIdHash: "pepper_unset"`.
- `null` value — no-op pass-through (no `userIdHash` key added).
- `undefined` value — no-op pass-through.
- Non-string value (number, object) — coerced via `String()`.
- Mixed case (`UserId`, `USER_ID`) — out of scope; project does not use these shapes (confirm via grep at plan time).
- No `userId` key at all — pass-through unchanged.
- Both `userId` AND `userIdHash` present — keep `userIdHash`, drop `userId` (defensive: prevents double-hash).

### TR4: Sentry `setUser` placement decision

Plan-time research task. Three candidate locations:

- `apps/web-platform/instrumentation.ts` (Next.js 15 init hook) — runs once per request, simplest.
- A route-handler wrapper (HOC) imported into each route — explicit, traceable.
- Server middleware in `apps/web-platform/middleware.ts` (if exists) — runs at edge.

Plan-time must verify where Sentry scope is per-request vs. per-process, and where the user session is available without blocking.

### TR5: Verify pino does NOT ship off-host

Confirm at plan time that pino is `pino-pretty` (dev) + stdout (prod) ONLY. No Better Stack adapter, no Loki shipper, no OpenTelemetry log exporter. If any off-host shipping is introduced after this PR, PA8 §(c) must be re-narrowed and a separate retention/erasure analysis is required.

### TR6: Performance sanity check

HMAC-SHA256 per log line is ~microseconds. Pre-merge, run a brief throughput sanity check on the highest-volume logger (the ws-handler / agent-runner paths, which are already migrated but exercise the `formatters.log` hook regardless). No formal benchmark required unless plan-time research surfaces a hotspot.

## Out-of-Scope (Tracked Elsewhere)

- **#3696** — Client-side `lib/client-observability.ts` pseudonymisation. OPEN, parallel track. Ships AFTER this PR.
- **DPD telemetry entry** — `docs/legal/data-protection-disclosure.md` §(l) "Operational telemetry & breach detection" entry mirroring PA8 §(c) in user-readable form. Filed as separate issue at Phase 3.6.
- **`security_events` durable audit-log table** — Art. 33(5) 6y retention. Distinct legal basis. Deferred in parent #3638.
- **Pepper rotation runbook** — YAGNI per parent #3638. Operator hash-lookup script accepts pepper as 2nd arg already (`observability.ts:31-33`).

## Acceptance Criteria

1. `apps/web-platform/server/logger.ts` has a `formatters.log` config that pseudonymises `userId`/`user_id` at top level + one-level-nested via `hashUserId`.
2. `apps/web-platform/scripts/hash-user-id.ts` exists; `pnpm hash-user-id <uuid>` works under `doppler run`.
3. `Sentry.setUser({id: hashUserId(user.id)})` is called server-side (placement per TR4).
4. 10 direct call sites in `app/api/**/route.ts` + `app/(auth)/callback/route.ts` are migrated to helpers OR confirmed defence-in-depth-covered by `formatters.log` if they don't fit the silent-fallback shape (`info`/`debug`).
5. PA8 §(c) §(ii) at `knowledge-base/legal/article-30-register.md:157` reflects single-path pino pseudonymisation, no forward-reference to follow-up migration.
6. PA8 §(f) at `knowledge-base/legal/article-30-register.md:162` carries a concrete Hetzner pino retention window.
7. Test fixtures cover TR3 surface (synthesised UUIDs only).
8. Multi-agent review (per `brand_survival_threshold: single-user incident`) signs off — `user-impact-reviewer` mandatory.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-12-pino-userid-formatters-log-brainstorm.md`
- Issue: #3698 (this spec's tracking issue)
- Parent: #3638 (Sentry pseudonymisation), #3685 (introducer of helpers, MERGED)
- Parallel: #3696 (client-side, OPEN)
- Helper module: `apps/web-platform/server/observability.ts`
- Target file: `apps/web-platform/server/logger.ts`
- Sentry init: `apps/web-platform/sentry.server.config.ts`
- PA8: `knowledge-base/legal/article-30-register.md`
