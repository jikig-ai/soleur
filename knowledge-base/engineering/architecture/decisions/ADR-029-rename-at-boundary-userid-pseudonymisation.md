---
title: Rename-at-boundary userId pseudonymisation
status: accepted
date: 2026-05-12
related: [3638, 3685, 3698, 3696]
related_adrs: [ADR-026, ADR-028]
---

# ADR-029: Rename-at-boundary `userId` pseudonymisation

> Renumbered from ADR-028 → ADR-029 post-rebase: PR #3634 (`ADR-028-dsar-export-substrate-and-audit-retention.md`) had already claimed ADR-028 on `main` before this PR landed.

## Status

Accepted (2026-05-12, PR #3701 closing #3698).

## Context

PR #3685 (closing #3638) introduced server-side `userId → userIdHash` pseudonymisation inside the silent-fallback helpers (`reportSilentFallback`, `warnSilentFallback`, `mirrorP0Deduped` in `apps/web-platform/server/observability.ts`). Multi-agent review found ~11 direct `logger.{error,warn,info,debug}({userId, ...})` call sites in `apps/web-platform/app/api/**/route.ts` and `apps/web-platform/app/(auth)/callback/route.ts` that bypass the helpers and continue to emit raw `userId` to pino stdout on the Hetzner Finland container host. Article 30 register PA8 §(c) §(ii) carried a forward-reference to this follow-up (#3698).

Four architectural shapes were available:

- **A — Per-site caller migration.** Migrate each of the 11 sites to the existing helpers (`reportSilentFallback` etc.). 11 judgment calls; PR-Reviewer fatigue; compliance close only when last site lands.
- **B — Pino `redact` with default censor.** Add `userId`/`user_id` to `REDACT_PATHS`. Emits `[Redacted]` (drops value); breaks operator grep workflow.
- **C — Pino `redact` with custom `censor` function.** Compute hash via censor callback. Limitation: censor function keeps the same key name (`{userId: "<hash>"}`); breaks the `userIdHash` naming contract established by the helper module.
- **D — Pino `formatters.log()` rename hook.** Runs BEFORE redact (verified at `pino/lib/tools.js:161-200`); renames `userId → userIdHash` in place. Single source of truth at the logger boundary. Covers all current sites + future sites for free.

## Decision

Adopt **Option D — rename-at-boundary via pino `formatters.log()`**.

### Architectural shape

A single shared helper (`apps/web-platform/server/userid-pseudonymize.ts`) exports `renameUserIdToHash(obj)` and `hashUserIdValue(rawValue): string`. Four consumers depend on it (three TS, one VRL):

1. **`observability.ts:hashExtraUserId`** — delegates to the shared helper. Pre-existing per-call helper for `extras` payload sites that go through `reportSilentFallback`/`warnSilentFallback`/`mirrorP0Deduped`.
2. **`logger.ts:formatters.log`** — wraps the shared helper in a try/catch fail-safe; wired into pino factory. Covers ALL `logger.{error,warn,info,debug}` emissions across the server-side code.
3. **`sentry-scrub.ts:scrubRecursive`** — adds a `userId`/`user_id` rename special-case before the `SENSITIVE_LOWER.has()` branch. **Deferred to PR-B** (Sentry-side symmetric coverage); architectural contract established here for that PR to follow.
4. **Vector VRL (`apps/web-platform/infra/vector.toml` `pii_scrub_structured` transform; PR #4293)** — defensive backstop at the journald → Better Stack Logs boundary. Top-level `userId`/`user_id` only (matches the TS scope byte-for-byte per §I2). Reuses `SENTRY_USERID_PEPPER` via VRL `get_env_var("SENTRY_USERID_PEPPER")` and computes `encode_base16(hmac(value, pepper, algorithm: "SHA-256"))` to match TS `crypto.createHmac("sha256", pepper).update(userId).digest("hex")` bit-for-bit (asserted in `apps/web-platform/test/infra/vector-pii-scrub.test.sh` AC4 — openssl + TS `hashUserId` import). Fail-safe: pepper-unset leaves the raw line and tags `+skipped_pepper_unset` (operator-detectable via Better Stack saved query); null userId emits the `pepper_unset_null` sentinel mirroring TS `hashUserIdValue`.

### Invariants

- **I1 — Rename, not redact.** Recital 26 pseudonymisation preserves operator-grep linkage via hash; full `[Redacted]` would drop the value entirely. The legal basis for retaining the pseudonym is breach-investigation linkage (PA8 §(b)(ii)).
- **I2 — Top-level boundary.** The walker handles top-level `userId`/`user_id` only. All current call sites are top-level (verified via grep at plan time). Nested `{extra: {userId}}` shapes are NOT renamed; if they appear in future, widen the walker with intent (test fixture asserts the boundary).
- **I3 — Try/catch fail-safe.** `formatters.log` must NOT propagate throws — pino drops the entire log line if the formatter throws. The catch path returns `obj` unchanged + emits one `console.warn` (NOT `logger.*` — re-entrancy hazard). The `err` value handed to `console.warn` MUST be serialised to a primitive string first (`err.stack ?? err.message`) to prevent `util.inspect` from walking caller-supplied getters / Proxy traps and re-entering the logger via a getter side-effect.
- **I4 — Single source of truth.** All three consumers import from `userid-pseudonymize.ts`. Hash function (`hashUserId`) remains in `observability.ts` (cyclic-import-safe since `userid-pseudonymize.ts` imports it one-way).
- **I5 — PA8 §(c) coupling.** The Article 30 register §(c) §(ii) wording explicitly cites `formatters.log()` by name. Silent regression of the formatter would surface as a wording inconsistency at the next CLO audit.
- **I8 — `userIdHash` is a reserved emit-key.** Callers MUST NOT use `userIdHash` for anything other than the post-rename HMAC-pseudonymous value emitted by this boundary. The defensive branch in `renameUserIdToHash` (drops `userId` when `userIdHash` is already present) silently discards the raw `userId` if a caller emits both — a future caller emitting `{userId, userIdHash: <other-domain-hash>}` would lose the raw identifier without diagnostic. Treat `userIdHash` as owned by the pino boundary.
- **I10 — Two-primitive separation (pino-helper path vs DSAR cross-tenant path).** The codebase deliberately ships TWO distinct pseudonymisation primitives with two distinct key materials and two distinct emit field names. Do NOT consolidate them — the split reflects two threat models, not duplicate code.

  | Aspect | `hashUserId` (this ADR) | `hashUserIdForSentry` (ADR-028 / DSAR) |
  |---|---|---|
  | Construction | HMAC-SHA256(pepper, userId) | SHA-256(salt ‖ \x00 ‖ userId)[:16] |
  | Key material | `SENTRY_USERID_PEPPER` (Doppler) | `SOLEUR_SENTRY_PII_SALT` (Doppler) |
  | Output | 64-hex (full digest) | 16-hex (64-bit truncation) |
  | Consumers | pino `formatters.log`, helper `extra.userId` | `mirrorCrossTenantViolation` only |
  | Emit field | `userIdHash` | `offendingUserIdHash` / `expectedUserIdHash` |
  | Failure mode | fail-safe sentinel (`pepper_unset`) | fail-loud (throws in production) |
  | Linkability | cross-deploy linkable (pepper stable) — supports PA8(b)(ii) breach investigation | salt-rotatable, dedup-class; alarm-only |

  Cross-surface correlation between the two requires operator access to BOTH Doppler secrets — this is intentional separation under Art. 32. PA8 §(c)(ii) discloses the domain-distinct field names.

### Future consumer protocol

When adding a new pseudonymisation boundary:

1. Import `renameUserIdToHash` from `apps/web-platform/server/userid-pseudonymize.ts`.
2. Use top-level rename; widen with intent + test if nested is needed.
3. Update PA8 §(c) §(ii) to reflect the new boundary coverage.
4. Add a fixture to the relevant test file mirroring the adversarial throw-safety pattern.

## Consequences

### Positive

- All 11 known direct call sites covered in one PR; brand-survival compliance close on day one of merge.
- Operator grep workflow preserved via hash (operator computes `hashUserId(uuid)` → greps stdout).
- PA8 §(c) §(ii) becomes a truthful single-path disclosure (no "follow-up migration" forward-reference).
- Future direct-emit sites covered automatically by the logger-boundary hook; CI gate (`.github/workflows/lint.yml`) prevents regression.
- Single source of truth (`userid-pseudonymize.ts`) reduces drift risk across pino + Sentry-scrub + helper paths.

### Negative

- Net-new pino infrastructure pattern (first `formatters` use in the codebase). Future contributors must understand the formatters.log → redact ordering.
- Try/catch fail-safe is invisible to readers of the logger module — must be documented (this ADR + inline comment).
- Top-level boundary is implicit; nested shapes silently pass through. Test fixture catches the regression; CI gate catches direct-emit drift.
- Sentry-side (`sentry-scrub.ts` symmetric coverage) and middleware-side (`Sentry.setUser` binding) deferred to PR-B. Until those land, direct `Sentry.captureException({extra: {userId}})` sites and route-handler events without setUser carry the legacy behaviour.

### Risks

- **F2 (formatters.log throw drops log line):** mitigated by the try/catch wrapper. Adversarial fixture in `logger-formatters.test.ts` asserts pass-through on throw.
- **F3 (Sentry scope cross-request bleed under custom server):** deferred to PR-B. The PR-A scope does not introduce setUser; ADR-029's invariants do not depend on F3 resolution.
- **Performance:** HMAC-SHA256 per log line is ~microseconds; ws-handler is the highest-volume caller. Fast-path skip (early-return if no `userId`/`user_id` key) is a one-line addition if hot.

## References

- Issue: #3698 (closing) — PR #3701
- Parent: PR #3685 (helper module introduction), #3638 (parent erasure work)
- Parallel: #3696 (client-side `lib/client-observability.ts` track)
- Follow-ups: PR-B (Sentry-side symmetric + setUser; filed pre-merge), PR-C (operator CLI + PA8 §(f) retention + compliance-posture refresh; filed pre-merge), #3708 (DPD §(l) telemetry user-facing entry)
- Related ADR: ADR-026 (PII gate as plan/work phase skill with diff hook)
- Plan: `knowledge-base/project/plans/2026-05-12-feat-pino-userid-formatters-log-plan.md`
- Spec: `knowledge-base/project/specs/feat-pino-userid-redaction-3698/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-12-pino-userid-formatters-log-brainstorm.md`
- Pino Node types: `apps/web-platform/node_modules/pino/pino.d.ts:642-663`
- Pino source (formatters→redact ordering): `apps/web-platform/node_modules/pino/lib/tools.js:161-200`
- Sentry init (server, `beforeSend` wired): `apps/web-platform/sentry.server.config.ts:12-16`
