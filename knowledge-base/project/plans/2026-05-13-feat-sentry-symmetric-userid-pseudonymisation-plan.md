---
issue: 3710
parent_pr: 3701
parent_issue: 3698
type: feat
classification: code
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adrs: [ADR-029]
date: 2026-05-13
---

# feat(observability): Sentry symmetric userId pseudonymisation + setUser binding + 10-site helper migration

> **Why this plan exists.** PR #3701 (PR-A of #3698) closed the pino-side `userId → userIdHash` boundary at the logger. Sentry events from direct `Sentry.captureException` / `Sentry.captureMessage` sites and route-handler events that lack `setUser` still carry raw `user_id` exposure to the processor. ADR-029 §"Consequences — Negative" explicitly defers this surface to PR-B. This plan implements the three remaining deliverables under one PR.

## Overview

Three coupled deliverables that close the symmetric Sentry-side `userId → userIdHash` coverage promised by ADR-029 and PA8 §(c)(ii):

1. **`Sentry.setUser` server binding** at `apps/web-platform/server/with-user-rate-limit.ts:65` (the HOC's `getUser()` exit) AND inline at each of the 10 helper-migrated sites from deliverable 2.
2. **Migrate 10 direct `logger.{error,warn}` sites** in `apps/web-platform/app/**` to `reportSilentFallback` / `warnSilentFallback` so each gets Sentry mirror per `cq-silent-fallback-must-mirror-to-sentry`.
3. **`sentry-scrub.ts:scrubRecursive` rename special-case** — symmetric `userId` / `user_id` → `userIdHash` rewrite at the Sentry `beforeSend` / `beforeBreadcrumb` boundary, defence-in-depth for any direct `Sentry.captureException({extra: {userId}})` site that bypasses the helpers (e.g., `ws-handler.ts`).

The Architecture **F3 gate** (Sentry scope cross-request bleed under the custom-server boot path at `apps/web-platform/server/index.ts`) is load-bearing: until proved otherwise, every `getCurrentScope().setUser` call MUST be wrapped in `Sentry.withIsolationScope(() => { ... })`. Verification is a 2-request scope-isolation integration test that lands BEFORE any setUser code.

## User-Brand Impact

- **If this lands broken, the user experiences:** a `Sentry.setUser({id: hashUserId(userA)})` from request A leaking into a Sentry event captured during request B's lifecycle (cross-request bleed under the custom `http.createServer` boot path), causing user A's pseudonymous identifier to be attributed to user B's error event in Sentry dashboards. Symptom: incident-response attribution becomes unreliable; a regulator audit treats the bleed as Art. 5(1)(d) accuracy breach.
- **If this leaks, the user's raw `user_id` is exposed via:** any of the ~13 direct `Sentry.captureException` / `Sentry.captureMessage` sites in `apps/web-platform/server/ws-handler.ts` + `server/index.ts` + the 10 helper-migration target sites in `app/(auth)/callback/route.ts` and `app/api/**/route.ts` — events fire to Sentry processor (US data centre per current DSN) with raw `extra.userId` until `sentry-scrub.ts` learns the rename special-case.
- **Brand-survival threshold:** `single-user incident` (carry-forward from PR-A / parent #3698 brainstorm; `user-impact-reviewer` mandatory at PR review per `plugins/soleur/skills/review/SKILL.md` conditional-agent block).

## Research Reconciliation — Spec vs. Codebase

Reconciles the issue body's framing against verified codebase reality.

| Issue body claim | Codebase reality | Plan response |
|---|---|---|
| ADR reference: "**ADR-028** — knowledge-base/engineering/architecture/decisions/ADR-028-rename-at-boundary-userid-pseudonymisation.md" | The on-disk ADR is **ADR-029** (`ADR-029-rename-at-boundary-userid-pseudonymisation.md`). ADR-028 is `ADR-028-dsar-export-substrate-and-audit-retention.md` — a deliberately distinct primitive (ADR-029 §I10 documents the two-primitive separation). | All plan references use **ADR-029**. PA8 §(c)(ii) update wording cites ADR-029 (not ADR-028) for the boundary contract; ADR-028 referenced only when discussing the DSAR cross-tenant path. |
| "Inject after `supabase.auth.getUser()` resolves in `with-user-rate-limit.ts:65` (**primary mount; covers every route via the HOC**)" | `git grep -rln 'withUserRateLimit' apps/web-platform/app/` returns **4 routes only**: `conversations/route.ts`, `kb/search/route.ts`, `kb/tree/route.ts`, `chat/thread-info/route.ts`. The HOC is NOT a primary mount covering every route — Next.js route handlers in `app/**` adopt it explicitly per route. | Wire setUser at the HOC (4 routes) **AND** inline at each of the 10 helper-migrated sites (which do NOT use the HOC). Net coverage = 14 documented authenticated emission sites. Future routes that adopt the HOC get coverage for free; future direct routes need an explicit setUser call. CI gate (`pr-quality-guards.yml#userid-bypass-lint`) already blocks raw `userId` in logger calls; no auto-coverage for Sentry-side direct emits — accepted as defence-in-depth ceiling, not perimeter. |
| "Zero `Sentry.setUser` calls anywhere in server code" | Verified: `grep -rn "Sentry.setUser" apps/web-platform/ --include="*.ts"` returns no results. | No conflict; documented as plan-time baseline. |
| Issue body cites 10 emission sites | Re-verified each line number under §"Inventory" below; all 10 exist verbatim. One drift: `auth/github-resolve/callback/route.ts:157` is `logger.info` success-path (issue body acknowledges; stays direct, covered by `formatters.log`). | Plan inventory mirrors issue body verbatim with line-number re-confirmation. |
| F3 gate: "before any setUser code lands, ship a 2-request integration test against `withUserRateLimit` proving Sentry scope isolation under the custom-server boot path" | Sentry SDK v10 (Sentry/sentry-javascript context7 docs): **automatic per-request isolation requires Node.js 22.12.0+ AND Sentry.init **before** the server bootstrap**. Manual fallback: wrap inner handler in `Sentry.withIsolationScope(...)`. Codebase: `apps/web-platform/Dockerfile` uses `node:22-slim@sha256:4f77a690...`. The slim tag is **`node:22-slim`** (not pinned to `22.12+`), and the bundler entry esbuilds with `--target=node22`. The Sentry init IS first import (`server/index.ts:3`). Conclusion: automatic isolation MAY hold on `node:22-slim` at current minor (which is 22.12+ as of 2026-02), but cannot be relied on without empirical proof, AND the custom `http.createServer` flow bypasses `@sentry/nextjs`'s Next.js request wrapper which is where `withIsolationScope` is auto-called by the SDK in standard Next deployments. | Plan ships **defensively**: wrap every setUser binding in explicit `Sentry.withIsolationScope(() => { ... })` regardless of the integration test outcome. The integration test is preserved as belt-and-braces: assert isolation under the actual prod boot path. If the test PASSES with bare `getCurrentScope().setUser`, keep `withIsolationScope` anyway (defence-in-depth, future-proof against Sentry SDK minor bumps that might tighten isolation requirements). If the test FAILS, the `withIsolationScope` wrap is load-bearing. |

## Open Code-Review Overlap

`gh issue list --label code-review --state open` ⇒ 75 issues; `jq` per-path search across the 11 paths the plan edits returned:

- **#3703** — `review: add client-pii-grep CI + lefthook gate (follow-up to #3696)`. Matches because the issue body contextually references `apps/web-platform/server/observability.ts`. The actual files in scope for #3703 are CLIENT-side (`lib/client-observability.ts`, `sentry.client.config.ts`, lefthook.yml, pr-quality-guards.yml). **Disposition: Acknowledge.** Different concern (client-side regression-detection gate vs. server-side coverage symmetric to ADR-029). #3703 remains open; this PR does not extend to its scope.

No other matches across the 10 site-paths or the 3 server-side edit targets (`with-user-rate-limit.ts`, `sentry-scrub.ts`, `userid-pseudonymize.ts`).

## Domain Review

**Domains relevant:** Engineering, Legal, Product (user-brand-critical triad).

Domain assessments carry forward from the parent #3698 brainstorm (`knowledge-base/project/brainstorms/2026-05-12-pino-userid-formatters-log-brainstorm.md` §"Domain Assessments"). This PR implements the deliverables that brainstorm explicitly carved out as PR-B (post-PR-A bundling). No re-spawn at plan time; status `reviewed (carry-forward)`.

### Engineering (CTO) — reviewed (carry-forward)

Brainstorm summary: pino `formatters.log` viable, but Sentry-side coverage is a separate boundary. CTO recommended setUser binding via server middleware (placement TBD). This plan resolves the placement: HOC primary mount + inline at helper-migrated sites. F3 risk identified by PR-A review as the load-bearing concern — addressed via `withIsolationScope` defensive wrap AND integration test.

### Legal (CLO) — reviewed (carry-forward)

Brainstorm summary: PA8 §(c)(ii) "symmetric coverage tracked under follow-up #3710" forward-reference exists at line 157 AND 157 of `knowledge-base/legal/article-30-register.md` — closes when this PR ships. PR makes the disclosure single-path-truthful (no forward references for the Sentry side). No new regulated-data processing introduced; existing Sentry processor relationship (Sentry GmbH; EU-DPA in place) unchanged. CLO does not re-sign at plan time (per lifecycle staging — brainstorm-time CLO sign-off carries forward).

### Product (CPO) — reviewed (carry-forward)

Brainstorm summary: CPO identified `Sentry.setUser` middleware binding as the highest-leverage defence-in-depth piece (#3710 deliverable #1). Operator runbook does not regress (existing hash-user-id flow continues to work; setUser surfaces pseudonymous identity to Sentry dashboards for incident triage). **CPO sign-off required at plan time per `requires_cpo_signoff: true`** — invoked at /work Phase 0 via Domain Review carry-forward gate (the brainstorm already collected CPO sign-off under `USER_BRAND_CRITICAL=true`; this plan inherits).

### Product/UX Gate

**Tier:** NONE
**Decision:** skipped — no user-facing UI surface. Sentry-side pseudonymisation is an internal observability transform; no new components, no flow changes.

## GDPR / Compliance Gate

**Trigger evaluation:** PA8 §(c)(ii) wording change touches the Article 30 register; brand-survival threshold is `single-user incident`; LLM-summarisation surface unchanged. Triggers (b) (threshold) AND the canonical regex surface (`apps/web-platform/server/sentry-scrub.ts` is auth-adjacent observability infrastructure for authenticated routes).

**Gate invocation:** `/soleur:gdpr-gate` runs at plan Phase 2.7 (here) AND at work Phase 2 exit per `hr-gdpr-gate-on-regulated-data-surfaces`.

**Plan-time findings (advisory; full output captured in `/work` Phase 2 exit):**

- Art. 5(1)(c) data minimisation: this PR REDUCES identifiable data exposure (raw `userId` → `userIdHash` symmetric at Sentry boundary). Net improvement.
- Art. 4(5) pseudonymisation: HMAC-SHA256 with Doppler-held pepper qualifies under Recital 26 (controller cannot re-identify without pepper). Pepper is shared with PR-A — no new key material.
- Art. 32 security of processing: defence-in-depth (`sentry-scrub` rename special-case) is a security improvement.
- No Art. 9 special-category data touched.
- No Art. 30 trigger for new processing activity — extends existing pino/helper-boundary pseudonymisation to Sentry-side symmetric coverage.

**Verdict:** advisory-only; no Critical findings expected. No `compliance/critical` issue filing required.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **F3 gate: scope-isolation integration test ships FIRST.** New file `apps/web-platform/test/sentry-scope-isolation.test.ts` exercises a 2-request sequence through a stub `withUserRateLimit`-wrapped handler:
  1. Request A authenticates as `userA`, captures a Sentry event, assert event carries `user.id = hashUserId(userA.id)`.
  2. Request B captures a Sentry event WITHOUT prior auth, assert event carries `user.id === undefined` (NOT `hashUserId(userA.id)`).
  3. Concurrent variant: requests A and B interleaved via `Promise.all`, each captures one event; assert each event's `user.id` matches its own request, not the other's.
  The test MUST exercise the EXACT placement form chosen in deliverable 1 (i.e., bare `getCurrentScope().setUser` if proved isolated, OR `Sentry.withIsolationScope(...)` wrap if needed). All 3 assertions green before any production setUser code lands.

- [ ] **Deliverable 1: `Sentry.setUser` binding.**
  - [ ] `apps/web-platform/server/with-user-rate-limit.ts:65` (after `getUser()` resolves, before `counter.isAllowed`) calls:
    ```ts
    return Sentry.withIsolationScope(async () => {
      Sentry.getCurrentScope().setUser({ id: hashUserIdValue(user.id) });
      // ...existing rate-limit + handler body...
    });
    ```
  - [ ] Inline at each of the 10 helper-migrated sites (deliverable 2) — every `reportSilentFallback`/`warnSilentFallback` call site preceded by `Sentry.getCurrentScope().setUser({ id: hashUserIdValue(userId) })`. The helper itself already pseudonymises `extra.userId` (ADR-029 / `observability.ts:hashExtraUserId`); setUser is the parallel binding for Sentry's first-class `user` context field.
  - [ ] Imports `hashUserIdValue` from `@/server/userid-pseudonymize` (the shared primitive — single source of truth per ADR-029 I4).

- [ ] **Deliverable 2: 10-site helper migration.** Each of the following sites replaced with `reportSilentFallback` (for `logger.error` of an Error) or `warnSilentFallback` (for `logger.warn` of a degraded condition):
  - [ ] `apps/web-platform/app/(auth)/callback/route.ts:310` (`reportSilentFallback`, feature `"auth-callback"`, op `"user-upsert-fallback"`)
  - [ ] `apps/web-platform/app/(auth)/callback/route.ts:323` (`reportSilentFallback`, feature `"auth-callback"`, op `"workspace-provisioning"`)
  - [ ] `apps/web-platform/app/api/services/route.ts:103` (`reportSilentFallback`, feature `"services"`, op `"token-store"`)
  - [ ] `apps/web-platform/app/api/services/route.ts:133` (`reportSilentFallback`, feature `"services"`, op `"list"`)
  - [ ] `apps/web-platform/app/api/services/route.ts:198` (`reportSilentFallback`, feature `"services"`, op `"token-delete"`)
  - [ ] `apps/web-platform/app/api/workspace/route.ts:68` (`reportSilentFallback`, feature `"workspace"`, op `"provisioning"`)
  - [ ] `apps/web-platform/app/api/webhooks/stripe/route.ts:180` (`reportSilentFallback`, feature `"stripe-webhook"`, op `"checkout.session.completed"`)
  - [ ] `apps/web-platform/app/api/repo/setup/route.ts:196` (`reportSilentFallback`, feature `"repo-setup"`, op `"clone"`)
  - [ ] `apps/web-platform/app/api/auth/github-resolve/callback/route.ts:153` (`reportSilentFallback`, feature `"github-resolve"`, op `"callback"`)
  - [ ] `apps/web-platform/app/api/accept-terms/route.ts:73` (`reportSilentFallback`, feature `"accept-terms"`, op `"user-row-missing"`)
  - [ ] `auth/github-resolve/callback/route.ts:157` (logger.info success path) **NOT migrated** (issue-body-acknowledged scope-out; covered by `formatters.log` defence-in-depth).

- [ ] **Deliverable 3: `sentry-scrub.ts` rename special-case.**
  - [ ] `apps/web-platform/server/sentry-scrub.ts:43-49` — inside `Object.entries(value)` loop of `scrubRecursive`, BEFORE the `SENSITIVE_LOWER.has()` branch, add:
    ```ts
    const keyLower = k.toLowerCase();
    if (keyLower === "userid" || keyLower === "user_id") {
      out["userIdHash"] = hashUserIdValue(v);
      continue;
    }
    ```
  - [ ] Imports `hashUserIdValue` from `@/server/userid-pseudonymize`.
  - [ ] Inline comment block documents ADR-029 I8 (`userIdHash` is a reserved emit-key) AND that the rename special-case wins over `SENSITIVE_KEY_NAMES` membership (defensive precedence; case-insensitive key detection mirrors the existing `SENSITIVE_LOWER` pattern).

- [ ] **Tests (new file `apps/web-platform/test/sentry-scrub.test.ts`)** covering:
  - [ ] `scrubSentryEvent({extra: {userId: "abc"}})` → `{extra: {userIdHash: "<hex>"}}` (top-level rename in extras)
  - [ ] `scrubSentryEvent({tags: {user_id: "abc"}})` → `{tags: {userIdHash: "<hex>"}}` (snake_case rename in tags)
  - [ ] Mixed: `{extra: {userId: "abc", apiKey: "secret"}}` → `{extra: {userIdHash: "<hex>", apiKey: "[Redacted]"}}` (rename + redact both apply)
  - [ ] Case-insensitive: `{extra: {UserId: "abc"}}` → `{extra: {userIdHash: "<hex>"}}`
  - [ ] Nested: `{contexts: {request: {extra: {userId: "abc"}}}}` → all nested `userId` keys renamed (recursive walk inherits the rename)
  - [ ] Cycle / shared-DAG: object referenced from two sub-trees gets renamed consistently (uses the existing `Map<object, scrubbed>` memo)
  - [ ] Both `userId` and `userIdHash` present: `{extra: {userId: "raw", userIdHash: "preset"}}` — preserves existing `userIdHash`, drops raw `userId` (defensive precedence; aligns with `renameUserIdToHash` defensive branch)
  - [ ] Null/undefined value: `{extra: {userId: null}}` → `{extra: {userIdHash: "pepper_unset_null"}}` (mirrors `hashUserIdValue` sentinel)
  - [ ] Missing pepper: skip if `process.env.SENTRY_USERID_PEPPER` cannot be deleted in test isolation — verify via the pre-existing `observability-pepper-unset.test.ts` pattern.

- [ ] **No regressions on existing suites:**
  - [ ] `apps/web-platform/test/observability.test.ts` — 100% green.
  - [ ] `apps/web-platform/test/observability-pepper-unset.test.ts` — 100% green.
  - [ ] `apps/web-platform/test/observability-mirror-debounce.test.ts` — 100% green.
  - [ ] `apps/web-platform/test/userid-pseudonymize.test.ts` (PR-A test file) — 100% green.
  - [ ] `apps/web-platform/test/logger-formatters.test.ts` (PR-A test file) — 100% green.
  - [ ] `apps/web-platform/test/with-user-rate-limit.test.ts` — 100% green AFTER the wrapper code change (test may need updates for `withIsolationScope` wrap; preserve isolation semantics).
  - [ ] `bash scripts/test-all.sh` full project suite — green.
  - [ ] `tsc --noEmit` in `apps/web-platform/` — green.

- [ ] **Article 30 register PA8 §(c) update** (`knowledge-base/legal/article-30-register.md:157`):
  - [ ] §(c)(i) line "migration to the helpers is tracked under the follow-up issue" → drop the forward-reference; replace with "Server-side direct `Sentry.captureException` / `Sentry.captureMessage` payloads are sanitised through the `sentry-scrub.ts:scrubRecursive` boundary which renames top-level and nested `userId`/`user_id` keys to `userIdHash` via the shared `hashUserIdValue` primitive (ADR-029 I4). Authenticated request handlers bind `Sentry.getCurrentScope().setUser({id: hashUserIdValue(user.id)})` at the per-user-rate-limit HOC and at each helper-migration site (10 sites; full inventory in PR #<this-PR>)."
  - [ ] §(c)(ii) line "symmetric direct-capture coverage at the Sentry scrub layer is tracked under follow-up #3710" → drop the forward-reference; replace with "Symmetric direct-capture coverage is enforced at the `sentry-scrub.ts:scrubRecursive` boundary which renames `userId`/`user_id` to `userIdHash` regardless of nesting depth, complementing the pino `formatters.log` top-level boundary."
  - [ ] Both lines audited via `grep -n "tracked under" knowledge-base/legal/article-30-register.md` returning zero `#3710` forward-references after edit.

- [ ] **CI gate sanity:** existing `userid-bypass-lint` (`.github/workflows/pr-quality-guards.yml`) continues to pass — the 10 sites no longer emit raw `userId` to `logger.{error,warn}` (they now route through helpers which hash at the emit boundary).

- [ ] **Issue-link convention:** PR body uses `Closes #3710` (this PR closes the deferred-scope-out cleanly post-merge; not an ops-remediation that needs `Ref #N`).

### Post-merge (operator) — automation-feasibility gate applied

Per the automation-feasibility gate, each candidate operator action checked against available MCP/CLI tooling:

- **Sentry event inspection (verify `setUser` actually carries `userIdHash`).** Automatable via Sentry REST API (`SENTRY_AUTH_TOKEN` in Doppler). Wire as a `gh workflow run sentry-post-merge-smoke.yml` triggered automatically by `/soleur:ship` Phase 7 — assertion: fire a synthetic `Sentry.captureException` on prod boot (already exists at `server/index.ts:120`), fetch the event via Sentry API, assert `user.id` matches `hashUserIdValue(<known-test-user-uuid>)`. Place in /work Phase 4 verification, not "operator manual".
- **Prod SSH stdout grep (verify raw `userId` absent from pino).** PR-A already covers this; no additional post-merge check needed for THIS PR's pino-side scope (we are NOT modifying pino emission paths — the 10-site migration routes through helpers which inherit `formatters.log`).
- **PA8 §(c) wording audit.** Done at /work Phase 5 via `grep -n "#3710" knowledge-base/legal/article-30-register.md` returning empty.

No genuinely operator-only steps remain.

## Implementation Phases

### Phase 0 — Setup & domain-review carry-forward

1. `/soleur:gdpr-gate` plan-time run (this section, already complete).
2. Verify CPO sign-off carry-forward from parent #3698 brainstorm: `grep -A 3 "CPO" knowledge-base/project/brainstorms/2026-05-12-pino-userid-formatters-log-brainstorm.md | head -20`. Status: confirmed.
3. Re-run path-existence sweep (`hr-when-a-plan-specifies-relative-paths-e-g`): every file path cited in the plan must `test -f` green before /work begins.

### Phase 1 — F3 scope-isolation integration test (load-bearing gate)

1. Create `apps/web-platform/test/sentry-scope-isolation.test.ts`. Use `vitest` (existing test framework — verified via `cat apps/web-platform/package.json | grep -E '"test"|vitest'`).
2. Mock `@sentry/nextjs`: capture all `Sentry.captureException` / `captureMessage` calls into a per-test array; capture `getCurrentScope().setUser` calls; assert `user` payload on each captured event.
3. Stub a `withUserRateLimit`-wrapped handler that calls `setUser` per the candidate placement form (bare vs. `withIsolationScope`). Default to `Sentry.withIsolationScope(...)` wrap.
4. Implement the 3 assertion shapes from the AC.
5. Tests green BEFORE any production setUser code lands. **TDD invariant:** if Phase 1 tests fail at any point in Phase 2, halt Phase 2 and either tighten the wrap form (e.g., promote to `withIsolationScope` if started with bare) or escalate to architecture-strategist via multi-agent review.

### Phase 2 — `Sentry.setUser` HOC binding + helper-migration setUser inlines

1. Edit `apps/web-platform/server/with-user-rate-limit.ts`:
   - Import `Sentry` from `@sentry/nextjs`, `hashUserIdValue` from `@/server/userid-pseudonymize`.
   - Wrap the post-`getUser` body in `Sentry.withIsolationScope(async () => { Sentry.getCurrentScope().setUser({id: hashUserIdValue(user.id)}); return ...existing... })`.
   - Add inline comment block citing ADR-029 + the F3 gate rationale + a pointer to `sentry-scope-isolation.test.ts`.
2. For each of the 10 migration sites (Phase 3 below), preceding the `reportSilentFallback`/`warnSilentFallback` call, emit `Sentry.getCurrentScope().setUser({id: hashUserIdValue(userId)})`. Wrap in `Sentry.withIsolationScope(...)` ONLY if the site is NOT already inside a route that's wrapped (today no Phase-3 migration sites use the HOC; all 10 need explicit isolation).
3. Run Phase 1 test suite → must remain green.

### Phase 3 — 10-site helper migration

For each site in the AC list:

1. Read the surrounding context (full route handler).
2. Replace `logger.error({ err, userId, ...rest }, "<msg>")` with `reportSilentFallback(err, { feature: "...", op: "...", extra: { userId, ...rest } })`. The helper hashes `userId` at its boundary (`hashExtraUserId`) → emit shape is `extra.userIdHash` automatically.
3. Replace `logger.warn(...)` with `warnSilentFallback(...)` analogously.
4. Add the `Sentry.withIsolationScope(...) { Sentry.getCurrentScope().setUser(...); ... }` wrap from Phase 2 step 2 around the migrated call.
5. Verify each site individually: route handler unit test (if exists) green; full app suite green.
6. After all 10 sites migrated, run `grep -nE 'logger\.(error|warn)\(.*userId' apps/web-platform/app/` — expect zero matches (the migration is complete). One known exception: `auth/github-resolve/callback/route.ts:157` (logger.info success path, scope-out per issue body).

### Phase 4 — `sentry-scrub.ts` rename special-case + tests

1. Create `apps/web-platform/test/sentry-scrub.test.ts` with the 8 test scenarios from the AC. Tests fail initially (RED).
2. Edit `apps/web-platform/server/sentry-scrub.ts:43-49` to add the rename special-case BEFORE `SENSITIVE_LOWER.has()`.
3. Tests green (GREEN).
4. Verify cycle/shared-DAG memoisation: the rename special-case writes `out["userIdHash"]` instead of recursing on the original `userId` value (which would be a primitive anyway). Memo continues to work for sibling sub-trees.

### Phase 5 — PA8 §(c) wording update + reconciliation grep

1. Edit `knowledge-base/legal/article-30-register.md:157` per the AC wording.
2. `grep -n "#3710\|tracked under follow-up\|symmetric coverage tracked" knowledge-base/legal/article-30-register.md` — expect zero matches for the forward-references.
3. `grep -n "ADR-029" knowledge-base/legal/article-30-register.md` — expect at least one match (cites the boundary contract).
4. Run `/soleur:gdpr-gate` work-phase exit per `hr-gdpr-gate-on-regulated-data-surfaces`.

### Phase 6 — Verification & tsc + tests + multi-agent review

1. `bash scripts/test-all.sh` full project suite.
2. `tsc --noEmit` clean in `apps/web-platform/`.
3. Spawn multi-agent review with focus on: security-sentinel (Sentry-side coverage symmetry), architecture-strategist (F3 isolation + `withIsolationScope` placement correctness), user-impact-reviewer (carries over from brand-survival threshold), data-integrity-guardian (rename semantic in `scrubRecursive` cycle/shared-DAG cases), code-simplicity-reviewer.
4. Address P1s inline before pushing for review.

### Phase 7 — Ship

1. `/soleur:ship` Phase 5.5 conditional gates fire (regulated data, brand threshold).
2. CPO sign-off carry-forward verified.
3. `user-impact-reviewer` agent fires per single-user-incident threshold.
4. `gh pr merge --squash --auto` after CI green.

## Files to Edit

- `apps/web-platform/server/with-user-rate-limit.ts` — add `Sentry.withIsolationScope` + `setUser` binding after `getUser()` resolves; imports `Sentry` from `@sentry/nextjs` and `hashUserIdValue` from `@/server/userid-pseudonymize`.
- `apps/web-platform/server/sentry-scrub.ts` — add `userId`/`user_id` rename special-case in `scrubRecursive` (BEFORE the `SENSITIVE_LOWER.has()` branch); import `hashUserIdValue`.
- `apps/web-platform/app/(auth)/callback/route.ts` (lines 310, 323) — migrate to `reportSilentFallback` + inline `setUser`.
- `apps/web-platform/app/api/services/route.ts` (lines 103, 133, 198) — migrate to `reportSilentFallback` + inline `setUser`.
- `apps/web-platform/app/api/workspace/route.ts` (line 68) — migrate to `reportSilentFallback` + inline `setUser`.
- `apps/web-platform/app/api/webhooks/stripe/route.ts` (line 180) — migrate to `reportSilentFallback` + inline `setUser`.
- `apps/web-platform/app/api/repo/setup/route.ts` (line 196) — migrate to `reportSilentFallback` + inline `setUser`.
- `apps/web-platform/app/api/auth/github-resolve/callback/route.ts` (line 153) — migrate to `reportSilentFallback` + inline `setUser`.
- `apps/web-platform/app/api/accept-terms/route.ts` (line 73) — migrate to `reportSilentFallback` + inline `setUser`.
- `knowledge-base/legal/article-30-register.md` (line 157) — drop `#3710` forward-reference; document Sentry-side symmetric coverage via `sentry-scrub.ts` + `setUser` binding.
- `apps/web-platform/test/with-user-rate-limit.test.ts` — adapt fixtures to the `withIsolationScope` wrap shape (preserve isolation semantics).

## Files to Create

- `apps/web-platform/test/sentry-scope-isolation.test.ts` — F3 gate: 2-request and concurrent scope-isolation assertions under stubbed `withUserRateLimit` wrapper.
- `apps/web-platform/test/sentry-scrub.test.ts` — 8 scenarios from the AC (rename, mixed, case, nested, cycle, both-keys, null sentinel, missing-pepper guard).

## Test Strategy

- **Framework:** `vitest` (verified — package.json `test` script invokes `vitest`; existing observability tests use it).
- **Mocking:** `vi.mock("@sentry/nextjs", () => { ... })` capturing `captureException`/`captureMessage`/`withIsolationScope`/`getCurrentScope().setUser` calls into per-test arrays — pattern matches the existing `apps/web-platform/test/observability.test.ts` setup.
- **Pepper:** existing test pepper from `apps/web-platform/test/setup.ts` (or equivalent) — DO NOT add a new test pepper; consistency with PR-A test surface is load-bearing.
- **No new dependencies.** All test infrastructure (vitest, `@sentry/nextjs` mock, `userid-pseudonymize` import) already present.

## Risks

- **F3 scope cross-request bleed.** Mitigated by `Sentry.withIsolationScope` wrap (defensive default) + integration test (load-bearing AC).
- **Stripe webhook auth context.** `apps/web-platform/app/api/webhooks/stripe/route.ts:180` runs inside the webhook handler where the authenticated user comes from `event.data.object.metadata.userId` (Stripe metadata), NOT a Supabase session. Verify at /work time that `setUser` placement reads from the correct source and does not assume a `supabase.auth.getUser()` resolution.
- **`logger.info` success path (`auth/github-resolve/callback/route.ts:157`) coverage.** Scoped out by issue body; covered by PR-A's `formatters.log` defence-in-depth — no Sentry-side mirror exists for `logger.info` (intentional; helper migration is for `logger.error`/`logger.warn` only). No risk of regression.
- **`renameUserIdToHash` defensive branch already drops raw `userId` when `userIdHash` is present.** The new `sentry-scrub` rename mirror does NOT introduce a double-hash path because (a) `scrubRecursive` is called on Sentry event payloads which never contain a pre-computed `userIdHash` from upstream code (helpers emit `extra.userIdHash` directly; `userId` keys reach the scrubber only via direct `Sentry.captureException({extra: {userId}})` from sites that bypass the helpers). The dual-write contract is therefore one-way at the scrub boundary.
- **CI gate `userid-bypass-lint` blocks raw `userId` only in `logger.*` calls** (pino path). Sentry-side direct emits are NOT yet linted. Defence-in-depth is `sentry-scrub.ts` runtime rewrite. Filing a follow-up `userid-bypass-lint` extension for direct `Sentry.captureException({extra: {userId}})` sites is OUT OF SCOPE for this PR — track as `#3710-followup-sentry-lint` if it surfaces during multi-agent review.

## Sharp Edges

- **The `## User-Brand Impact` section is required and verified at deepen-plan Phase 4.6 + preflight Check 6.** A plan whose section is empty, contains only `TBD`/`TODO`, or omits the threshold will fail. This plan's section is fully populated — sharp-edge satisfied.
- **The F3 gate AC ships the integration test BEFORE any production `setUser` code.** Skipping the test and shipping bare `getCurrentScope().setUser` risks merging a cross-request bleed under the custom-server boot path. The `Sentry.withIsolationScope` defensive wrap is the belt; the integration test is the braces. Keep both.
- **PA8 §(c) wording update is part of THIS PR.** Letting the PR merge without the §(c) edit leaves `#3710` as a stale forward-reference in the Article 30 register — CLO surface drift.
- **The `sentry-scrub` rename special-case wins over `SENSITIVE_LOWER`.** `userId` is NOT in `SENSITIVE_KEY_NAMES` today (verified at `apps/web-platform/server/sensitive-keys.ts:26-78`). If a future PR adds `userId` to `SENSITIVE_KEY_NAMES`, the rename branch still fires first (placement before `SENSITIVE_LOWER.has()`). Document the precedence inline.
- **The HOC binding only covers 4 routes (NOT every route)** — see Research Reconciliation. Inline `setUser` at each of the 10 helper-migration sites is load-bearing for symmetric coverage. Future routes that do NOT adopt `withUserRateLimit` AND do NOT migrate to silent-fallback helpers will NOT carry `setUser`. The 3-layer defence remains: (1) HOC binding for `withUserRateLimit`-wrapped routes, (2) helper-migration setUser inlines, (3) `sentry-scrub` rename special-case as runtime backstop for any direct `Sentry.captureException({extra: {userId}})` from a site that bypasses both.
- **Loader-class fit (`AGENTS.md` class loader):** this plan edits `apps/web-platform/**` (code), `knowledge-base/legal/article-30-register.md` (docs), `apps/web-platform/test/**` (code). Multi-class diff → all sidecars load (fail-closed per `feat-agents-md-change-class-loader` spec).
- **TWO-primitive separation (ADR-029 §I10) preserved.** This PR uses `hashUserIdValue` (the pino-helper primitive). The DSAR cross-tenant path (`mirrorCrossTenantViolation` → `hashUserIdForSentry`) is a DELIBERATELY DISTINCT primitive emitting `offendingUserIdHash` / `expectedUserIdHash`. Do NOT consolidate; the split reflects two threat models.

## References

- Issue #3710 (this) — PR-B follow-up to #3698
- PR #3701 — PR-A (MERGED 2026-05-13 10:48 UTC); establishes ADR-029 rename-at-boundary pattern this PR extends
- Issue #3698 — parent (closed by PR #3701)
- Parent brainstorm (carry-forward source): `knowledge-base/project/brainstorms/2026-05-12-pino-userid-formatters-log-brainstorm.md`
- ADR-029 — `knowledge-base/engineering/architecture/decisions/ADR-029-rename-at-boundary-userid-pseudonymisation.md` (note: ADR is 029, NOT 028 as the issue body mentions; ADR-028 is the unrelated DSAR substrate)
- ADR-028 — `knowledge-base/engineering/architecture/decisions/ADR-028-dsar-export-substrate-and-audit-retention.md` (referenced only for the two-primitive separation table in ADR-029 §I10)
- PR-A plan: `knowledge-base/project/plans/2026-05-12-feat-pino-userid-formatters-log-plan.md`
- PR-A spec: `knowledge-base/project/specs/feat-pino-userid-redaction-3698/spec.md`
- Sentry SDK v10 isolation docs (context7 `/getsentry/sentry-javascript`): `withIsolationScope`, `getCurrentScope`, manual request isolation for Node <22.12 / custom-server boot paths
- Related PRs: PR-C #3711 (operator CLI + PA8 §(f) retention), #3708 (DPD §(l) telemetry user-facing entry), #3696 (client-side parallel)
- Open code-review overlap: #3703 (acknowledged; different concern)
- Learnings cited:
  - `knowledge-base/project/learnings/2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md` — informed the two-clause AC structure (helper-routed + direct-bypass coverage)
  - `knowledge-base/project/learnings/2026-05-12-plan-time-api-contract-verification-and-pipeline-via-package-json.md` — informed the Sentry SDK API verification via context7
  - `knowledge-base/project/learnings/2026-05-12-brainstorm-issue-body-option-and-inventory-staleness-pino-userid.md` — informed the Research Reconciliation discipline (ADR-028 vs ADR-029 drift; HOC coverage claim audit)
