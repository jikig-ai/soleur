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
- Preserve operator grep capability via the hash (operators compute the hash via the existing `hashUserId` primitive — operator CLI bundling deferred to PR-C).
- Update PA8 §(c) Article 30 register to a truthful single-path description immediately after merge, scoped explicitly to server-side pino emissions.

**Plan-time scope trim (2026-05-12):** the 6-agent plan review applied the both-panels-fire heuristic and deferred the following bundled deliverables to follow-up PRs because (a) the brand-survival threshold is satisfied by formatters.log + PA8 §(c) alone, and (b) Architecture F3 surfaced a Sentry scope-isolation correctness risk under the custom-server boot path that warrants verification in a dedicated PR.

## Non-Goals

- **Sentry.setUser middleware binding** → deferred to PR-B (Architecture F3 + scope-mismatch). Originally FR3.
- **10-site silent-fallback helper migration** → deferred to PR-B (orthogonal to compliance close per DHH/code-simplicity). Originally FR4.
- **Sentry-scrub.ts symmetric `userId` rename coverage** → deferred to PR-B (no direct long-tail verified at plan time).
- **Operator hash-user-id CLI** → deferred to PR-C (tsx-prod-dep gap; orthogonal to compliance close). Originally FR2.
- **PA8 §(f) Hetzner pino retention window pin** → deferred to PR-C (driver-disambiguation gap; SSH-dependent; pre-existing placeholder). Originally FR6.
- **Recursive walker (top-level + 1-level-nested)** → narrowed to **top-level only** (all 11 current sites are top-level; nested behaviour reserved for future widening with intent).
- Client-side `lib/client-observability.ts` pseudonymisation — tracked as #3696, ships AFTER this PR per CLO sequencing.
- `docs/legal/data-protection-disclosure.md` §(l) telemetry user-facing disclosure entry — tracked as #3708.
- Pepper rotation infrastructure / runbook — explicitly deferred in parent #3638 brainstorm (YAGNI).
- `security_events` durable audit-log table (Art. 33(5) 6y retention) — distinct legal basis, parent #3638 deferred.
- Pino → Better Stack shipping — pino stays Hetzner-stdout-only; no off-host log copies introduced by this PR.

## Functional Requirements

### FR1: pino `formatters.log()` rename hook (top-level only)

Add a `formatters.log` config to the pino instance in `apps/web-platform/server/logger.ts` that:

1. Receives each log object before redact runs.
2. Detects keys `userId` and `user_id` at **top level only** (recursion narrowed at plan-review — all 11 current sites are top-level, nested coverage reserved for future widening with intent).
3. Computes `userIdHash = hashUserId(String(value), pepper)` via the existing helper in `apps/web-platform/server/observability.ts`.
4. Replaces the original key with `userIdHash` (drops the raw key entirely).
5. Falls back to the sentinel `"pepper_unset"` when `SENTRY_USERID_PEPPER` is missing (mirroring `observability.ts:35-37`).
6. Handles edge cases: `null` value → `userIdHash: "pepper_unset_null"` (matches `observability.ts:53` codebase behaviour — corrected from the original TR3 "no key added" wording per canonical spec-flow finding); `undefined` value → no-op pass-through; non-string value → coerced via `String()`; missing key → no-op pass-through; both `userId` AND `userIdHash` present → keep `userIdHash`, drop `userId` (defensive).
7. **Try/catch fail-safe (Architecture F2):** the formatter must wrap `renameUserIdToHash` in a try/catch that returns `obj` unchanged on throw + emits a one-time `console.warn` (NOT logger — re-entrancy hazard).

### FR2: PA8 §(c) §(ii) Article 30 register update

Replace the current `knowledge-base/legal/article-30-register.md:157` PA8 §(c) §(ii) wording with a single-path explanation scoped explicitly to server-side pino emissions: pseudonymisation happens at the pino logger boundary via `formatters.log()` for all `logger.{error,warn,info,debug}` emissions across `apps/web-platform/server/**` and `apps/web-platform/app/**`. Wording explicitly cites `formatters.log()` (per Kieran P1.2) so silent regression of the formatter is visibly inconsistent with the legal text. No "follow-up migration" forward-reference. Sentry-side and client-side cross-references point to deferred PR-B and #3696 respectively. Draft in plan §Phase 3.1.

### FR3: ADR-029 (rename-at-boundary) — rename-at-boundary pattern

Create `knowledge-base/engineering/architecture/decisions/ADR-029-rename-at-boundary-userid-pseudonymisation.md` per architecture-strategist AP-011 advisory. Documents the pattern (rename-not-redact, single-source-of-truth helper, top-level boundary, try/catch fail-safe, PA8 §(c) coupling) for future contributors. Cross-references #3638/#3685/#3698/#3696/ADR-026.

### FR4: Persistent CI bypass-grep gate

Add a CI step to `.github/workflows/lint.yml` (or equivalent PR-triggered workflow) that runs the bypass-grep against PR diffs in `apps/web-platform/(server|app)/`. Fails PR if a direct `logger.{error,warn,info,debug}({...userId...})` site is added outside the known leave-and-cover allowlist (currently 1 site: `auth/github-resolve/callback/route.ts:157`). Replaces the original spec's one-time AC verification with a persistent regression gate per GDPR auditor critical finding + Architecture F5.

### FR5: Shared `userid-pseudonymize.ts` helper

Create `apps/web-platform/server/userid-pseudonymize.ts` exporting `renameUserIdToHash(obj)` (top-level only) and `hashUserIdValue(rawValue): string` primitive (per Kieran P1.4 — value-level primitive avoids per-key allocation if future callers need it). `observability.ts:hashExtraUserId` refactored to delegate to the shared helper (zero behaviour change; existing tests are the regression gate).

## Technical Requirements

### TR1: Reuse existing pseudonymisation primitives

- Hashing function: `hashUserId(userId, pepper?)` from `apps/web-platform/server/observability.ts:35`. Do NOT introduce a parallel hash function.
- Doppler secret: `SENTRY_USERID_PEPPER`. Already module-cached at `observability.ts:5`; no per-emit Doppler round-trip.
- Fail-closed sentinel: `"pepper_unset"`. Mirror `observability.ts:35-37`. The recursive walker must emit the sentinel for the `userIdHash` field when the pepper is unset.

### TR2: pino `formatters.log()` placement

Single edit to `apps/web-platform/server/logger.ts`. The `formatters.log` runs BEFORE `redact` (verified at `pino/lib/tools.js:161-200`), so it must NOT also wire `userId` into `REDACT_PATHS` — that would double-process. Node signature at `pino.d.ts:642-663` (the brainstorm's L470 cite was the browser variant — corrected).

### TR3: Test fixture surface (synthesised only per `cq-test-fixtures-synthesized-only`)

Test cases for `renameUserIdToHash` + the `formatters.log` integration (6 fixtures per plan-review trim):

- Top-level `userId` key (string) — renamed to `userIdHash` (64-hex).
- Top-level `user_id` key (string) — renamed to `userIdHash`.
- `null` value — renamed to `userIdHash: "pepper_unset_null"` (matches `observability.ts:53` codebase behaviour — **corrected from earlier "no key added" wording** per canonical spec-flow finding).
- Missing pepper — `userIdHash: "pepper_unset"`.
- Both `userId` AND `userIdHash` present — keep `userIdHash`, drop `userId` (defensive: prevents double-hash).
- Empty object / no `userId` key / nested `{extra: {userId}}` — pass-through unchanged (asserts top-level boundary; nested coverage deferred to PR-B if needed).

**Adversarial fixture (Architecture F2):** stub `hashUserId` to throw; `formatters.log` returns `obj` unchanged + one `console.warn` recorded (NOT logger — re-entrancy hazard).

### TR4: Verify pino does NOT ship off-host

Confirm at plan time that pino is `pino-pretty` (dev) + stdout (prod) ONLY. No Better Stack adapter, no Loki shipper, no OpenTelemetry log exporter. Confirmed via `package.json` grep at plan time. If any off-host shipping is introduced after this PR, PA8 §(c) must be re-narrowed and a separate retention/erasure analysis is required.

### TR5: Performance sanity check

HMAC-SHA256 per log line is ~microseconds. Pre-merge dev smoke test exercises one route handler. Formal load benchmark is not required for #3698; if a hotspot surfaces post-merge via Sentry latency dashboards, fast-path skip (early-return when obj lacks `userId`/`user_id` at top level) is a one-line addition.

### TR6: Sentry `setUser` placement — DEFERRED to PR-B

Original TR was a plan-time research task. Plan-time investigation surfaced Architecture F3 (Sentry scope cross-request bleed risk under custom-server boot path; AsyncLocalStorage isolation needs verification). Decision: defer to PR-B with a load-bearing 2-request scope-isolation test as gate. This decoupling keeps PR-A's brand-survival compliance close on the critical path.

## Out-of-Scope (Tracked Elsewhere)

- **#3696** — Client-side `lib/client-observability.ts` pseudonymisation. OPEN, parallel track. Ships AFTER this PR.
- **#3708** — DPD §(l) telemetry user-facing entry mirroring PA8 §(c).
- **PR-B follow-up** (filed pre-merge) — Sentry.setUser binding + 10-site helper migration + sentry-scrub.ts symmetric `userId` rename. Architecture F3 scope-isolation verification gate.
- **PR-C follow-up** (filed pre-merge) — Operator hash-user-id CLI + PA8 §(f) Hetzner pino retention window pin + `compliance-posture.md` line 88 refresh.
- **`security_events` durable audit-log table** — Art. 33(5) 6y retention. Distinct legal basis. Deferred in parent #3638.
- **Pepper rotation runbook** — YAGNI per parent #3638. `hashUserId(userId, pepper?)` already accepts pepper as 2nd arg for future rotation lookup.
- **Recursive walker (1-level-nested)** — narrowed to top-level only at plan-review. If a nested `{extra: {userId}}` site appears, widen with intent.

## Acceptance Criteria

1. **FR1 + FR5** — `apps/web-platform/server/userid-pseudonymize.ts` exists; `renameUserIdToHash(obj)` + `hashUserIdValue(rawValue)` exported; `observability.ts:hashExtraUserId` delegates to the shared helper.
2. **FR1 + Architecture F2** — `apps/web-platform/server/logger.ts` wires `formatters.log` with try/catch fail-safe that returns `obj` unchanged on throw and emits one `console.warn`.
3. **Two-clause AC (per `2026-05-12-centralized-at-helper-boundary-...md`)** — (i) helper-routed test suite all green; (ii) bypass-grep returns exactly the expected 11 sites (10 emit + 1 leave-and-cover at github-resolve:157).
4. **FR4 — Persistent CI gate** lands in `.github/workflows/lint.yml` (or equivalent) and rejects future direct-emit additions outside the allowlist.
5. **FR2 — PA8 §(c) §(ii)** at `article-30-register.md:157` reflects single-path pino pseudonymisation, cites `formatters.log()` explicitly, no forward-reference to follow-up migration.
6. **FR3 — ADR-029** created at `knowledge-base/engineering/architecture/decisions/ADR-029-rename-at-boundary-userid-pseudonymisation.md`.
7. Test fixtures cover TR3 surface (6 fixtures, synthesised UUIDs only) + Architecture F2 adversarial throw-safety fixture.
8. Multi-agent review (per `brand_survival_threshold: single-user incident`) signs off — `user-impact-reviewer` mandatory.
9. PR-B + PR-C follow-up issues filed pre-merge.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-12-pino-userid-formatters-log-brainstorm.md`
- Issue: #3698 (this spec's tracking issue)
- Parent: #3638 (Sentry pseudonymisation), #3685 (introducer of helpers, MERGED)
- Parallel: #3696 (client-side, OPEN)
- Helper module: `apps/web-platform/server/observability.ts`
- Target file: `apps/web-platform/server/logger.ts`
- Sentry init: `apps/web-platform/sentry.server.config.ts`
- PA8: `knowledge-base/legal/article-30-register.md`
