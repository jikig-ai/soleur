---
date: 2026-05-12
topic: sentry-userid-hash-art17-erasure
issue: 3638
related: [3603, 3623, 3649]
tags: [gdpr, sentry, observability, pii, art-17, art-30, art-33, pseudonymization]
brand_survival_threshold: single-user incident
lane: cross-domain
---

# Brainstorm: Hash userId in Sentry mirror + Art. 17 erasure hooks (#3638)

## User-Brand Impact

- **Artifact:** raw `userId` + `conversationId` in Sentry `extra` payload + pino → Better Stack log mirror, fired from `mirrorP0Deduped` (breach-attempt class events from `cc-dispatcher.ts:1476` W4-orphan drop).
- **Vector:** user invokes Art. 17 right-to-erasure → DB FK-cascade wipes user rows → Sentry (30–90 day retention) + Better Stack still hold the user's identifier and conversation id. A DSAR (Art. 15) following the erasure request would reveal the residual data.
- **Threshold:** single-user incident — one user discovering residual PII post-deletion is a documented compliance failure with ICO/CNIL complaint risk and brand-trust breach.

## What We're Building

Two-track GDPR remediation for breach-attempt observability mirrors:

**Track A — pseudonymize Sentry payload.** Replace raw `userId` in Sentry `extra` with `HMAC-SHA256(userId, pepper)` (Doppler-stored, quarterly rotation with one-cycle overlap via `PEPPER_PREVIOUS`). Sentry tags expose `userIdHash` for query/purge. Keep raw `userId` in the in-process dedup map (process-local, no PII at rest) and in pino (container-internal until shipped to Better Stack).

**Track B — Art. 17 erasure path.** Extend `apps/web-platform/server/account-delete.ts` (post-cascade, after line 125) to:
1. Compute `userIdHash` with current pepper AND previous pepper.
2. `DELETE /api/0/organizations/{slug}/issues/?query=userIdHash:<hash>` against Sentry (best-effort, fire-and-forget, failure mirrors to Sentry via `reportSilentFallback`).
3. Submit a Better Stack log-purge job keyed on raw `userId` for the user's pino events.
4. Add an entry to `knowledge-base/legal/article-30-register.md` documenting the new processing activity (breach-attempt mirror + the erasure mechanism).

Defer the `security_events` durable audit-log table (Art. 33(5) 6-year retention) to a separate D-durable-audit-log issue — different legal basis, different schema design, blocks this PR if bundled.

## Why This Approach

- **Belt-and-braces over minimum-viable.** CLO confirmed pseudonymous data (Recital 26 + Art. 4(5)) does not strictly require active erasure — Sentry retention expiry would be defensible. CTO confirmed Sentry's tag-based DELETE API works with `event:admin` scope. User chose active purge because the user-brand-critical tag and the one-time engineering cost (single API call, fire-and-forget) make defensive erasure cheap insurance against future audit/regulator inquiries.
- **Real personal-data surface is pino, not Sentry.** Once hashed, Sentry's payload is pseudonymous. Pino → Better Stack still ships raw `userId` (container-internal until export). The Better Stack purge job is the load-bearing Art. 17 control.
- **Single-purpose PR norm.** `security_events` table is Art. 33(5) retention infrastructure — distinct from H6/H7 closure. Bundling delays this PR on schema design and conflates two compliance findings.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Hashing algorithm | HMAC-SHA256 with server-side pepper | Pseudonymous under Recital 26; pepper-side compromise alone doesn't re-identify (must combine with hashed-tag corpus). |
| Pepper storage | Doppler secret (`SENTRY_USERID_PEPPER`) + `PEPPER_PREVIOUS` for one rotation cycle | Matches existing secret-mgmt pattern; rotation requires both peppers for at-rest events in Sentry's retention window. |
| Where to hash | At Sentry emit boundary only (lines 344–350 + `reportSilentFallback` extras) | Keep raw `userId` in in-memory dedup map (process-local) and pino. Don't change dedup-key shape. |
| Sentry erasure mechanism | `DELETE /api/0/organizations/{slug}/issues/?query=userIdHash:<hash>` | Tag-based Discover query is standard Sentry API; `event:admin` scope required. |
| Pino erasure mechanism | Better Stack log-purge job keyed on raw `userId` | Raw userId remains in Better Stack post-export; needs active purge. **Open question:** Better Stack purge-by-query API surface needs verification. |
| Sentry purge failure mode | Fire-and-forget; mirror failure via `reportSilentFallback`; do NOT block account deletion | Art. 17 is best-effort for processor-side data; failure must not regress the user's deletion success. |
| Art. 30 register entry | New row in `knowledge-base/legal/article-30-register.md` covering "breach-attempt observability mirror" | Documents both Sentry (pseudonymous, retention-bound + active purge) and Better Stack (raw, purge-on-delete) flows. |
| `security_events` table | DEFERRED to D-durable-audit-log (separate issue) | Art. 33(5) 6y retention is distinct from Art. 17 erasure; schema design is its own scope. |

## Open Questions

1. **Better Stack purge API surface.** Does Better Stack expose a per-tenant log-purge API keyed on JSON field (`userId`)? Plan skill must verify and either commit to the API call or downgrade to "documented residual retention" with a separate retention-bound disclosure. See `knowledge-base/project/learnings/integration-issues/production-observability-sentry-pino-health-web-platform-20260328.md`.
2. **Pepper rotation cadence.** Quarterly chosen by analogy to other secrets; should the rotation be tied to Sentry's retention window (30/60/90d) instead so PEPPER_PREVIOUS is always usable for at-rest events? Plan skill to confirm with Sentry retention setting.
3. **Sequencing vs. PR-C.** PR-A2's plan declared D-art30 a PR-C blocker. The Art. 30 entry added here partially overlaps; recommend #3638 lands FIRST and PR-C consumes the entry. Flag on PR-C before merging this.
4. **D-art30 issue status.** Search returned no open issue matching D-art30 by name — `knowledge-base/legal/article-30-register.md` exists (219 lines). The PR-A2 plan's "D-art30 PR-C blocker" likely refers to an additional entry for the breach-attempt mirror, not the whole register. Plan skill to confirm scope and either file D-art30 or rename the dependency.

## Domain Assessments

**Assessed:** Legal, Engineering, Product (user-brand-critical triad). Marketing, Operations, Sales, Finance, Support not relevant for this PR.

### Legal (CLO)

**Summary:** Track A pseudonymizes Sentry payload under Recital 26 (closes H6). Real Art. 17 surface is pino → Better Stack (raw `userId`); the active purge there is the load-bearing control. Sentry active-purge is legally unnecessary for pseudonymous data but engineering chose belt-and-braces given user-brand-critical tag. `security_events` table is Art. 33(5), distinct scope — defer.

### Engineering (CTO)

**Summary:** Hash on emit, not in dedup key (preserve in-memory raw `userId` for debounce). Doppler pepper with `PEPPER_PREVIOUS` for one rotation cycle. Sentry tag-based DELETE API confirmed feasible (`event:admin` scope). Better Stack purge API needs verification (plan-time). Defer `security_events` table — different scope.

### Product (CPO)

**Summary:** Sentry/Better Stack already disclosed as sub-processors via #1048 — no privacy-policy gap to bundle. No user-visible surface required for this PR. Track A alone would have been sufficient as a fast privacy improvement; user chose full Track B as belt-and-braces. Sequencing: ship #3638 before PR-C so PR-C's Art. 30 work consumes this PR's register entry.

## Capability Gaps

None — `soleur:gdpr-gate` skill covers Art. 17/30 audit during preflight. Engineering execution is in-scope for `soleur:plan` + `soleur:work`. Better Stack purge API verification is a plan-time research task, not a missing capability.
