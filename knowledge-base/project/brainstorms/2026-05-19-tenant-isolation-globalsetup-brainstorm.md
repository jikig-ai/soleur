---
title: Tenant-isolation suites — share founders+mints via vitest globalSetup
status: parked-deferred
brand_survival_threshold: single-user incident
lane: cross-domain
issue: 4041
draft_pr: 4060
branch: feat-tenant-isolation-globalsetup-4041
date: 2026-05-19
---

# Brainstorm: tenant-isolation suites — vitest globalSetup refactor

## What We're Building

Nothing, now. **Outcome of this brainstorm: park.**

The proposal in #4041 — move per-suite `service.auth.admin.createUser(...)` + `mintFounderJwt(...)` calls from each of 16 `*.tenant-isolation.test.ts` suites into a single vitest `globalSetup` to reduce GoTrue rate-limit bursts in CI — was evaluated and deferred. Operational mitigations shipped today (#4040 5× rate-limit headroom + #4038 bounded jittered backoff in `mintFounderJwt`) cover the acute pain. CI on `main` is green at SHA d33535cf. The Supabase magiclink runbook itself already classifies this refactor as **tier-3 remediation, warranted only if tiers (1) + (2) prove insufficient**. They haven't.

The brainstorm captures (a) why we're parking, (b) the re-evaluation triggers that would un-park it, and (c) the recommended implementation shape (CTO's Variant C) for whoever picks it up — so the analysis is not re-derived from scratch.

## Why This Approach

**Park, not redesign**, for four reasons:

1. **No forcing function.** The acute pain (over_request_rate_limit 429s during PR #3984 CI) was eliminated by tier-1 (operational bump) + tier-2 (bounded retry). There is no current flake; the runbook explicitly orders tier-3 last for this reason.

2. **The suites being touched are the cross-tenant safety net.** They verify that Founder A's JWT is denied against Founder B's tenant data. A silent semantic regression — e.g., a suite that passes against an empty result set instead of a populated peer tenant — would let a real RLS leak ship undetected on the next feature PR. The blast radius of a regression here is not "flaky CI"; it is a single-user trust-breach incident at minimum, potentially Article 33 reportable. The CPO assessment was unambiguous: this is "modifying the cross-tenant safety net," not "test infrastructure hygiene."

3. **The mechanically-clean version is bigger than the issue body suggests.** Repo research surfaced that vitest `globalSetup` runs in a **separate process** from worker threads — module-scope state does NOT transfer. The `_setMintFnForTest` shim must still install per-worker; JWT strings would have to transit via env var, file handoff, or vitest's `provide()` channel. The "expose via an opaque handle" line in #4041 obscures that there is no in-memory handle — the channel must be serialized. This is doable but it's not free.

4. **Three orthogonal hardening tracks compete for the same code area.** #3869 tracks positive-control RLS assertions (so a passing test can't be a tautology). The `synthetic-allowlist.ts` helper exists but isn't wired into the per-suite `afterAll` `getUserById` cross-check. A central founder-create helper (no such helper exists today — each suite open-codes it) would be cheaper safety to land first. Touching the suites for a defense-in-depth burst-reduction before any of those land risks consuming the regression budget on the wrong thing.

## Key Decisions

| Decision | Rationale | Status |
|---|---|---|
| Park #4041; no code change now | Tier-3 framing per runbook; CI green; no forcing function | This brainstorm |
| Convert #4041 to a monitor-and-revisit ticket | Preserve the analysis for the next operator; do not close (the work may become correct later) | Phase 3.6 |
| Recommended shape if revisited: **Variant C** (founder-pool only, mint stays per-suite) | Cuts `admin.createUser` 26→2 per run — the loud burst — without touching mint paths or `tenant-jwt-deny`'s opt-out. Lower mechanical complexity than full refactor (no JWT serialization across process boundary) | Captured below |
| Variant C must include negative-control / positive-control assertion hardening (#3869) as a hard prerequisite | The CPO recommendation: if we modify the safety net, we must strengthen its assertions. Refusing this couples a defense-in-depth gain to a load-bearing fidelity loss | Captured below |
| Tautology guard tracked as #3869 — orthogonal to this work, but a prerequisite if Variant C ever ships | Already filed | Existing |
| The deny-list suite (`tenant-jwt-deny.tenant-isolation.test.ts`) stays out of any shared setup | Its `beforeEach` calls `_setMintFnForTest(null)` deliberately; it tests the real-per-call mint path | Always |
| Productize Candidate: none | One-time decision on a single CI workflow; no recurring pattern | n/a |

## Re-Evaluation Triggers (un-park criteria)

Revisit if **any one** of these fires:

1. **CI flake re-emergence:** ≥2 `over_request_rate_limit` 429 failures in the `tenant-integration` job within any rolling 30-day window after the tier-1 bump landed.
2. **Rate-bump challenge:** A reviewer (or Supabase) challenges the dev-project 5× rate-limit bump as masking a real cost/quota problem, or the bump gets rolled back.
3. **Suite-count growth:** A new tenant-isolation suite is added that pushes the per-run `admin.createUser` count from the current 26 toward 50 — at that point the 150/5min ceiling is half-consumed by a single run and headroom is gone.
4. **Tier-2 retry exhausted:** The bounded retry in `mintFounderJwt` (PR #4038) starts logging exhaustion mirrors (`mint.verify_otp_error` with `retries_exhausted: true`) in CI mirror logs.
5. **#3869 ships:** Positive-control RLS assertions land. At that point the regression-detection floor is higher and the safety-net-modification risk on Variant C drops materially — un-parking becomes cheaper.

## Recommended Implementation Shape (if revisited): Variant C

For the next operator. Not a plan — a sketch so the architecture isn't re-derived.

**Scope:** globalSetup creates ONE shared founder pair (`founderA`, `founderB`). Each suite still calls `mintFounderJwt` in its own `beforeAll` and still uses `registerSharedMintCache` per-suite. The opt-outs (`tenant-jwt-deny`, `byok-kill-switch.atomicity`, `kb-route-helpers`) stay untouched.

**Why this scope, not the full refactor:**

- The **loud burst** is `admin.createUser`: it hits the sign-ups/sign-ins per-IP ceiling, and the `over_request_rate_limit` 429 in mirror logs traced primarily to it. Cutting 26→2 admin.createUser calls per run removes ~92% of that burst.
- `verifyOtp` (the mint path) is governed by a separate, less-bursty ceiling. The bounded-retry in #4038 already covers transient 429s on this path. Pooling it would only cut from 26 to 2 — but at the cost of crossing the vitest process boundary AND coupling 13 suites' mint state.
- The cleanest mechanical model is: founder identities are stable across a CI run (cheap to pool); JWTs are suite-local (don't pool).

**Mechanical sketch:**

1. New `apps/web-platform/test/globalSetup.ts` (or per-project under `apps/web-platform/test/global-setup/tenant-isolation.ts`). Configure on the `unit` project in `vitest.config.ts` — CI invokes `--project unit`.
2. globalSetup creates the founder pair via service-role client, writes `{ aId, aEmail, bId, bEmail }` to a JSON handoff file under `node_modules/.cache/tenant-iso/founders.json` (or via `provide()` in vitest 1.5+ if available). Returns a teardown function that deletes the pair.
3. Each migrated suite reads the JSON in its top-level body, replaces its own `service.auth.admin.createUser` calls with the pooled ids, then proceeds as today: `_resetTenantCache(); await mintFounderJwt(aId); registerSharedMintCache([[aId, aMint], ...])`. The `getUserById` email cross-check in `afterAll` becomes a no-op for the shared pair (skip deleteUser — globalSetup owns lifecycle).
4. **Idempotent startup sweep** before globalSetup creates new founders: `DELETE FROM auth.users WHERE email LIKE 'tenant-isolation-%@soleur.test' AND created_at < NOW() - INTERVAL '24h'`. Gated by the `assertSynthetic` allowlist regex. 24h window prevents racing concurrent CI runs.
5. **Branded-handle invariant** in TypeScript: `type FounderA = { id: UserId; email: SyntheticEmail; __brand: 'A' }` distinct from `FounderB`. Prevents a suite from accidentally querying with the wrong founder due to a copy-paste in the post-refactor seed code. (The tautology failure mode.)
6. **Positive-control prerequisite (#3869):** every migrated suite must demonstrate, in `beforeAll` or a per-test setup, that `aClient` can read its own seeded row before asserting `bClient` cannot. No positive-control = test is tautology-prone after pooling. Refuse to land Variant C until #3869 ships.

**Out of scope for Variant C:**

- Pooling JWTs across suites (the proposed full refactor). Re-evaluate only if `verifyOtp` 429s reappear after Variant C.
- Per-test (vs. per-suite) `_resetTenantCache` changes.
- Cross-project globalSetup (component project unaffected — it doesn't touch Supabase).
- Refactoring the 3 opt-out suites.

**Estimated touch:** 1 new file (globalSetup), 1 vitest config edit, 13 suite `beforeAll`/`afterAll` edits, 1 helper for the JSON handoff + cleanup sweep, ~50 lines of new tests for the helper. Roughly +200 / -100 LOC.

## Open Questions (for future revisit)

1. **`provide()` vs JSON file** for the globalSetup→worker handoff: which is more robust under vitest 3.x with `isolate: true`? The repo-research note flagged that the unit project requires `isolate: true` for unrelated tests (#3638), so the handoff must not depend on shared module state.
2. **Cleanup ordering with parallel CI runs:** if two CI runs of `tenant-integration` overlap (e.g., dependabot + a feature PR), the 24h idempotent sweep must not delete in-flight founders. Salt the email with a per-run UUID and only sweep stale.
3. **Should `installSharedMintCache` (currently zero call sites) be deleted from `mint-once.ts`** as dead code before any of this lands? It's been a forward-reference-only export since introduction.
4. **Is there a value in a tiny vitest project split** (`tenant-integration` as its own project with its own setup, distinct from `unit`)? CI already uses path-filter to select these tests; a project split would let globalSetup attach without affecting the rest of the unit project. CTO did not recommend this — it doubles config complexity — but it's worth a sentence in any future plan.

## User-Brand Impact

These suites are the automated guarantee that Founder A cannot read Founder B's data. A semantic regression in any refactor that touches them — a suite that passes against an empty result set instead of a populated peer tenant — would let a cross-tenant RLS leak ship undetected on the next feature PR, producing a single-user trust-breach incident, GDPR Article 33 notification exposure, and irrecoverable brand damage at our pre-beta stage. Therefore: any future un-park of #4041 must treat this as **modification of the cross-tenant safety net**, not test infrastructure. Plan-time and PR-review gates must require each migrated suite to prove it still fails when isolation is intentionally broken (negative-control assertion via #3869), not merely that it still passes. The decision to park today preserves the safety net at its current fidelity, which is the highest-value outcome until a forcing function changes the calculus.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO). Marketing, Operations, Sales, Finance, Support — not relevant (test infrastructure, no user-facing surface, no commercial terms, no operational provisioning).

### Engineering (CTO)

**Summary:** DO NOT ship the full globalSetup refactor as proposed. Variant C (founder-pool only, mint stays per-suite) is the recommended scope if revisited — it captures ~92% of the burst-reduction (the `admin.createUser` ceiling is the loud one) at materially lower mechanical risk than crossing the vitest process boundary with JWT strings. The tautology failure mode is the dominant risk and requires branded-handle types + a positive-control assertion (#3869 prerequisite). The cache-evict opt-out suite (`tenant-jwt-deny`) must stay outside any shared setup. Cleanup contract needs global teardown + idempotent 24h startup sweep, not just teardown.

### Product (CPO)

**Summary:** Park. Frame this work as "modification of the cross-tenant safety net," not "test infrastructure hygiene." Operational mitigations (#4040 5× headroom + #4038 bounded retry) have neutralized the acute pain; CI is green; the cost of waiting is zero. The cost of doing-it-now is non-zero regression risk on the safety net. Defer until a forcing function appears. If it ever lands, require negative-control proof: each migrated suite must demonstrate it still fails when isolation is intentionally broken.

### Legal (CLO)

**Summary:** Low risk. Audit-trail equivalence is preserved if test names + assertion messages still encode the tenant pair under test (e.g., `founderA → tenantB rows: denied`) so a regulator reading the CI report can trace the boundary check. No DSAR, breach, vendor terms, OSS, or MSA triggers. Synthetic-founder orphan accumulation in the dev project is hygiene, not compliance — no PII, no data subjects, no Art. 5(1)(e) storage-limitation trigger. No threshold breach; no specialist dispatch.

## Capability Gaps

None identified. The recommended Variant C is implementable with existing tools (`soleur:atdd-developer`, existing test infra, existing vitest config). The only structural absences flagged by repo research are:

- **No central founder-create / RLS-deny-assert helper** under `apps/web-platform/test/helpers/` today — each suite open-codes the synthetic-email + service-role-client + `assertSynthetic` boilerplate. (Evidence: `git ls-tree HEAD` of `apps/web-platform/test/helpers/` lists `mint-once.ts` as the only tenant-isolation helper; `synthetic-allowlist.ts` exists but has no consumers in `test/server/` per grep.) Extracting this helper is cheaper hardening to land first; it would naturally inform any future Variant C work.
- **No post-job founder-cleanup step in `.github/workflows/tenant-integration.yml`.** Cleanup today is entirely per-suite `afterAll`; a suite that throws after `createUser` succeeds leaks the founder. (Evidence: read of the workflow file shows no cleanup step.) This is an independent hygiene gap; if it grows the dev project's noise floor enough to mask the rate-limit ceiling, it becomes a re-evaluation trigger #6.

Neither is a blocker for the parking decision. Both are candidates for tiny standalone PRs.
