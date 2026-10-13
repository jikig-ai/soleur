---
date: 2026-05-12
topic: pino-userid-formatters-log
issue: 3698
related: [3638, 3685, 3696]
tags: [gdpr, pino, observability, pii, recital-26, art-30, pseudonymization, formatters-log, hetzner]
brand_survival_threshold: single-user incident
lane: cross-domain
---

# Brainstorm: pino `formatters.log()` userId rename hook (#3698)

## User-Brand Impact

- **Artifact:** raw `userId` (Supabase `auth.users.id` UUID) emitted to pino stdout on the Hetzner Finland container host, from 10 direct `logger.error|warn|info|debug({ userId, ... })` call sites in `apps/web-platform/app/api/**/route.ts` and `apps/web-platform/app/(auth)/callback/route.ts` that bypass the silent-fallback helpers added in PR #3685.
- **Vector:** any party with operator log access (Soleur engineers, Hetzner-host root, future log-aggregator) can read a paying user's stable internal identifier in plaintext. Under Art. 4(1) GDPR this is personal data; Art. 5(1)(c) data minimisation requires this to be pseudonymised or removed. PA8 §(c) Article 30 register currently over-claims that the helper-boundary pseudonymisation covers the server, when in reality 10 app/ HTTP-handler sites remain.
- **Threshold:** single-user incident — one user's userId persisted in cleartext on disk on a regulator-relevant log volume meets the GDPR Art. 4(1) bar. The `user-impact-reviewer` agent is auto-invoked at PR review for this threshold per `plugins/soleur/skills/review/SKILL.md`.

## What We're Building

A single pino `formatters.log()` hook in `apps/web-platform/server/logger.ts` that intercepts every log object, detects `userId` / `user_id` keys at top level **and recursively in nested objects**, computes `userIdHash = HMAC-SHA256(value, pepper)` via the existing `hashUserId()` helper, and emits `{userIdHash: <hex>}` in place. This covers all 10 direct call sites and any future site without per-call-site edits, preserving operator grep capability (via hash) and matching the naming contract from `observability.ts`.

Bundled deliverables in the same PR (belt-and-braces — same brand-survival-threshold reasoning as #3638):

1. **`formatters.log()` rename hook** in `apps/web-platform/server/logger.ts`. Recursive walker. Fail-closed `"pepper_unset"` sentinel mirroring `observability.ts:35-37`.
2. **Operator CLI:** `apps/web-platform/scripts/hash-user-id.ts` (~5 lines) + `pnpm hash-user-id <uuid>` package script. Operator usage: `doppler run -p soleur -c prd -- pnpm hash-user-id <uuid>` returns the hex hash for `grep <stdout>`.
3. **Sentry `setUser` middleware binding:** wire `Sentry.setUser({id: hashUserId(user.id)})` in a server middleware (Next.js route-handler wrapper or `instrumentation.ts`) so every Sentry event auto-carries pseudonymous identity. Today, **no** `Sentry.setUser` call exists server-side (verified via grep). This is the highest-leverage defence-in-depth piece CPO surfaced.
4. **Migrate 10 app/ call sites to helpers** (`reportSilentFallback` / `warnSilentFallback`) so each gets the `cq-silent-fallback-must-mirror-to-sentry` Sentry mirror (today they only emit to pino). The `formatters.log()` hook still applies as defence-in-depth.
5. **PA8 §(c) Article 30 register update** at `knowledge-base/legal/article-30-register.md:157` — replace the narrowed-scope-out wording with a single-path explanation: pseudonymisation now happens at the logger boundary for all sites.
6. **PA8 §(f) Hetzner pino retention window** — pin the concrete window via journalctl/Docker log-driver investigation. CLO flagged blocking. Update in same PR.

## Why This Approach

- **Pino `formatters.log()` runs before `redact`** and operates on the composed log object. It is the natural single boundary for transforming all `userId` emissions — repo-research confirmed `logger.ts:15-30` currently uses neither `formatters` nor `serializers`, and pino's `pino.d.ts:366,470` exposes both. This mirrors PR #3685's "helper boundary" pattern from `observability.ts` but at the logger layer instead of at three call-site helpers.
- **Single touch point covers 10 known sites + every future site for free.** Per-site migration (issue body's Option A) is reviewer-fatiguing and drift-prone; pino-level redaction with default censor (issue body's Option B/C) loses the value entirely (`[Redacted]`), breaking operator grep. `formatters.log()` is strictly better than either: same compliance posture as redaction with default censor, plus preserves queryability.
- **Recital 26 pseudonymisation is stronger than Art. 5(1)(c) redaction** for operator workflows: the hash remains a deterministic identifier for incident response (operators compute hash via the CLI and grep stdout), while the controller cannot re-identify from hash alone without the Doppler pepper (Recital 26 — pepper held in Doppler, not shared with the processor).
- **No off-host log copies today.** Per `production-observability-sentry-pino-health-web-platform-20260328.md` + `2026-05-12-plan-time-api-contract-verification-and-pipeline-via-package-json.md`, pino does NOT ship to Better Stack (Better Stack is `/health` uptime monitor only). Raw `userId` stays on Hetzner stdout, ages out naturally per host retention. This narrows Art. 17 obligations: erasure for the helper-side Sentry/Better-Stack mirror is already in flight under #3638's Track B, but pino erasure is satisfied by natural age-out — provided the retention window is documented (PA8 §(f) pin).
- **Belt-and-braces matches the brand-survival-threshold pattern from parent #3638**, which chose to ship Track A + Track B together rather than minimum-viable.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Transformation mechanism | pino `formatters.log()` rename hook (NEW Option D) | Renames `userId → userIdHash` in place; preserves queryability via hash; single source of truth at logger boundary. Strictly better than REDACT_PATHS default censor (`[Redacted]` loses value) and pino `redact` censor function (keeps `userId` key, breaks naming contract with `observability.ts`). |
| Hashing function | Reuse `hashUserId()` from `apps/web-platform/server/observability.ts:35` | Same HMAC-SHA256, same Doppler `SENTRY_USERID_PEPPER`, same `"pepper_unset"` sentinel. Single hash function for helper-emit, formatters.log, Sentry middleware, and CLI. |
| Pepper rotation | Reuse existing pepper (no rotation infra) | Parent #3638 brainstorm explicitly deferred rotation runbook (YAGNI). `hashUserId(userId, pepper?)` already accepts pepper as 2nd arg for operator hash-lookup during rotation (observability.ts:31-33 docstring). |
| Field-name shape | Emit `{userIdHash: <hex>}` — drop original `userId` key | Matches `observability.ts` helper-emit shape (extras carry `userIdHash`, never `userId`). Consistent naming everywhere; no two-path Grafana/Loki query rewrites. |
| Recursive walker scope | Top-level + nested keys (`userId`, `user_id`) | Current 10 sites are top-level only, but defensive nested-walk closes future drift (e.g., `extra.userId`, `context.user.id`). Cost is negligible (~10 lines + tests). |
| Operator CLI | Bundle in this PR | `apps/web-platform/scripts/hash-user-id.ts` + `pnpm hash-user-id <uuid>`. Operator-runbook coherence demands it land the same moment grep behavior changes. CPO + CTO both flagged as prerequisite. |
| `Sentry.setUser` middleware | Bundle in this PR | Zero `setUser` calls today (verified). Adding `Sentry.setUser({id: hashUserId(user.id)})` in server middleware makes Sentry a durable identification channel — defence-in-depth for the long tail. CPO's highest-leverage item. |
| Per-site helper migration | Bundle in this PR (belt-and-braces) | 10 sites migrated to `reportSilentFallback`/`warnSilentFallback` so each gets Sentry mirror (`cq-silent-fallback-must-mirror-to-sentry`). `formatters.log()` is defence-in-depth; helper migration is the architectural correctness. |
| PA8 §(c) wording | Single-path explanation: "userId pseudonymised at the pino formatters.log() boundary AND at helper extras" | Truthful immediately after merge. No "follow-up migration" forward-reference (everything ships in one PR). |
| PA8 §(f) retention window | Pin via journalctl/Docker log-driver investigation in same PR | CLO flagged blocking. Concrete window required for "natural age-out satisfies Art. 17" framing to be defensible. |
| Sequencing vs #3696 | #3698 ships first | CLO: keep PA8 server-side wording locked before #3696 introduces client-side wording. |
| #3696 client-side parallel | Out of scope (separate issue, OPEN) | Different code path (`lib/client-observability.ts`), different transport. Tracked as #3696. |

## Open Questions

1. **`formatters.log()` performance overhead.** HMAC-SHA256 per log line is ~microseconds, negligible for app routes but worth a sanity check at high throughput (ws-handler is already pre-migrated). Verify at plan time via a brief benchmark or order-of-magnitude reasoning.
2. **Hetzner pino retention window concrete value.** Plan-time task: SSH the prod host, check `journalctl --disk-usage` + Docker log driver config (`max-size`, `max-file` in `daemon.json`), document the rolling window in PA8 §(f). If retention is unbounded or weeks-long, the brainstorm framing of "natural age-out satisfies Art. 17" needs revisiting.
3. **`Sentry.setUser` placement.** Next.js 15 server components vs. route handlers vs. `instrumentation.ts` — verify where the user session is available + Sentry scope is per-request. Plan-time research task.
4. **Recursive walker semantics.** Should the walker stop at the first matching key (replace and return) or rewrite every matching key in deep nesting? Top-level + first-match is simpler; deep-nest-rewrite is more defensive but adds edge cases (cycles, large objects). Recommend first-match top-level, then explicit recursion one level deep for `extra.*` / `context.*` / `request.*` patterns commonly seen in Sentry-style log objects.
5. **Test fixture surface.** Mirror PR #3631's "synthesized only" test rule (`cq-test-fixtures-synthesized-only`) and the lesson from `2026-05-12-multi-agent-review-catches-load-bearing-redaction-primitive-bypasses.md` — fixtures must cover: top-level `userId`, top-level `user_id`, nested `extra.userId`, mixed case, missing pepper (sentinel emit), null/undefined value, non-string value coerced via `String()`.

## Domain Assessments

**Assessed:** Engineering, Legal, Product (user-brand-critical triad). Marketing, Operations, Sales, Finance, Support not relevant for this PR.

### Engineering (CTO)

**Summary:** Pino `formatters.log()` (or censor-function variant) is materially viable — the issue body underplayed it. Pepper is already module-cached (no Doppler round-trip per emit). Inventory is 10 sites / 7 files (not 27); all in `app/api/**/route.ts` + `app/(auth)/callback/route.ts`. Highest practical risk is silent breakage of operator grep without the hash-user-id CLI. Recommends formatters.log over censor-function because the latter keeps the same key name, breaking the `userIdHash` naming contract. Per-file vs per-feature-area batching: with Option D, no batching needed — single PR covers everything.

### Legal (CLO)

**Summary:** Option D (formatters.log) is the Art. 5(1)(c) data-minimisation improvement: ships strictly less identifiable data on day one. PA8 §(c) becomes truthful immediately with a single-path explanation. Recital 26 pseudonymisation is achieved at the logger boundary; controller cannot re-identify without Doppler pepper. PA8 §(f) retention window must pin in same PR. DPD `docs/legal/data-protection-disclosure.md` lacks a telemetry entry — pre-existing gap, separate follow-up issue (not in #3698 scope). Sequencing: #3698 before #3696 to keep PA8 wording stable.

### Product (CPO)

**Summary:** Operator runbook regresses without the hash-user-id CLI (no such tool exists today). Sentry is NOT a fallback channel today — no `Sentry.setUser` is called anywhere server-side. Adding the middleware binding is the highest-leverage defence-in-depth piece. With formatters.log + CLI + Sentry middleware bundled, the operator UX is *improved* (Sentry now auto-carries user identity, hash CLI enables grep). Inventory is broader than #3698 claims (the helper-migration follow-up, separately, should target the 10 sites for Sentry mirror compliance).

## Capability Gaps

None blocking. All required tooling exists:
- `hashUserId()` in `observability.ts:35` — evidence: `git grep -n 'export function hashUserId' apps/web-platform/server/observability.ts` returns the symbol at line 35.
- `SENTRY_USERID_PEPPER` Doppler secret — evidence: `observability.ts:5` reads `process.env.SENTRY_USERID_PEPPER`; `.env` (worktree-copied) contains the dev pepper.
- Pino `formatters` + `serializers` API — evidence: `pino.d.ts:366` (`serializers`), `pino.d.ts:470` (`formatters.log`).
- `apps/web-platform/scripts/` directory exists for the operator CLI placement — evidence: `ls apps/web-platform/scripts/` returns existing scripts.

Deliverables in #3698 PR (not capability gaps):
- Operator hash-user-id CLI (`apps/web-platform/scripts/hash-user-id.ts`) — file does not yet exist; ~5 lines.
- Server `Sentry.setUser` middleware binding — no such call exists today; placement TBD (Next.js middleware vs. `instrumentation.ts`).
- PA8 §(f) concrete retention window — currently `"short rolling window (re-confirm with infra runbook)"`; needs SSH/journalctl probe.

## Sub-Issues (deferred from this PR)

Filed as separate issues at Phase 3.6:

1. **#3696** — `feat(observability): pseudonymize userId in lib/client-observability.ts (follow-up to #3638)`. Status: OPEN, parallel client-side track. Ships AFTER #3698 per CLO sequencing decision.
2. **DPD gap (NEW)** — Add `docs/legal/data-protection-disclosure.md` §(l) "Operational telemetry & breach detection" entry mirroring PA8 §(c) in user-readable form. Pre-existing gap surfaced by CLO; not in #3698 scope.

## References

- Issue #3698 — this brainstorm's tracking issue (OPEN, P2-medium, deferred-scope-out from PR #3685 review)
- Issue #3638 — parent (Sentry pseudonymisation + Art. 17 erasure)
- PR #3685 — introducer of `observability.ts` helper module (MERGED 2026-05-12)
- Issue #3696 — parallel client-side track (OPEN)
- `apps/web-platform/server/observability.ts` — existing helper module, source of `hashUserId()` (L35) and `"pepper_unset"` sentinel (L36)
- `apps/web-platform/server/sensitive-keys.ts` — `REDACT_PATHS` config (L90-96), NOT the path chosen here
- `apps/web-platform/server/logger.ts` — pino instance, target of `formatters.log()` edit (L15-30)
- `apps/web-platform/sentry.server.config.ts` — Sentry init, target of `setUser` middleware binding (18 lines, no current `setUser` call)
- `knowledge-base/legal/article-30-register.md` — PA8 §(c) at L157, §(f) at L162
- `knowledge-base/project/brainstorms/archive/20260512-183402-2026-05-12-sentry-userid-hash-art17-erasure-brainstorm.md` — parent brainstorm
- `knowledge-base/project/learnings/security-issues/2026-05-12-multi-agent-review-catches-load-bearing-redaction-primitive-bypasses.md` — defines the multi-agent review pattern this PR will pass through
- `knowledge-base/project/learnings/2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md` — names #3698 as the explicit follow-up
- `knowledge-base/project/learnings/2026-05-12-plan-time-api-contract-verification-and-pipeline-via-package-json.md` — pino does NOT ship to Better Stack (Hetzner stdout only)
- `knowledge-base/project/learnings/best-practices/2026-04-28-sentry-payload-pii-and-client-observability-shim.md` — "typed-only enum fields in extras" rule, applies to migrated sites
- AGENTS.md `hr-weigh-every-decision-against-target-user-impact` — this brainstorm's enforcement layer
- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` — the rule the per-site helper migration satisfies
