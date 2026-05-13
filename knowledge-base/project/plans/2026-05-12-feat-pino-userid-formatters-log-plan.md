---
name: feat-pino-userid-formatters-log
issue: 3698
spec: knowledge-base/project/specs/feat-pino-userid-redaction-3698/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-12-pino-userid-formatters-log-brainstorm.md
pr: 3701
branch: feat-pino-userid-redaction-3698
date: 2026-05-12
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
type: feature
related: [3638, 3685, 3696, 3708, 3710, 3711]
plan_review_date: 2026-05-12
plan_review_outcome: trim-per-both-panels-fire
---

# Plan: pino `formatters.log()` userId rename hook (#3698)

## Overview

Close PR #3685's deferred-scope-out by pseudonymising every `userId` emission at the pino logger boundary via a `formatters.log()` rename hook, so that PA8 §(c) Article 30 register can read a truthful single-path disclosure on day one of merge. Brand-survival threshold: `single-user incident`.

**Scope decision (plan-review 2026-05-12):** the brainstorm bundled 6 deliverables; the 6-agent plan review (DHH + Kieran + code-simplicity + architecture-strategist + canonical spec-flow + GDPR auditor) found that brand-survival threshold is satisfied by **formatters.log + PA8 §(c) alone**, and the bundled scope-creep risks two P1 architecture findings (formatter throw drops log line; Sentry scope cross-request bleed under custom server). The "both panels fire — prefer delete" heuristic (from `2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md`) triggered on Phase 3 (sentry-scrub), Phase 4 (Sentry.setUser), Phase 5 (helper migration), recursive walker, operator CLI, and PA8 §(f) retention pin. All six are deferred to follow-up issues. The result is a 3-PR split — this is **PR-A**.

**This PR ships:**
1. Shared rename helper `apps/web-platform/server/userid-pseudonymize.ts` (testability + single source of truth)
2. pino `formatters.log()` rename hook in `apps/web-platform/server/logger.ts` (with defensive try/catch per Architecture F2)
3. PA8 §(c) §(ii) wording update in `knowledge-base/legal/article-30-register.md` (single-path disclosure; explicit `formatters.log()` citation per Kieran P1.2)
4. ADR-029 documenting the rename-at-boundary pattern (per Architecture AP-011)
5. CI-enforceable bypass-grep (persistent regression gate per GDPR critical + Architecture F5)

**Deferred to follow-up issues:**
- **PR-B (#3710) — Sentry-side pseudonymisation:** Sentry.setUser binding + 10-site helper migration + sentry-scrub symmetric coverage. Sentry.setUser requires plan-time verification that scope isolation holds under the custom-server boot path (Architecture F3) — separate PR can do this safely with a 2-request scope-isolation test as gate.
- **PR-C (#3711) — Hetzner retention + operator UX:** PA8 §(f) retention window pin + operator hash-user-id CLI + compliance-posture.md line 88 refresh.

## User-Brand Impact

**If this lands broken, the user experiences:** raw Supabase `auth.users.id` UUIDs continue to be emitted to pino stdout on the Hetzner Finland container host from 11 direct call sites in `apps/web-platform/app/api/**/route.ts` and `apps/web-platform/app/(auth)/callback/route.ts`, contradicting the Article 30 register PA8 §(c) post-#3685 forward-reference. Any party with operator log access reads a paying user's stable internal identifier in plaintext.

**If this leaks, the user's identity is exposed via:** live `journalctl --user=app | grep <uuid>` against the Hetzner host stdout; Docker log driver historical rotation (retention window currently undocumented — pinned by deferred PR-C); any future off-host log shipping introduced after this PR (none today — pino is stdout-only per `2026-05-12-plan-time-api-contract-verification-...md`). Worst-case unrelated vector: a regulator-driven audit during the migration window finds the PA8 disclosure over-claims pseudonymisation scope. This PR closes that risk for the pino server-side boundary; client-side `lib/client-observability.ts` (#3696) and direct `Sentry.captureException` long-tail (deferred PR-B) remain separately tracked.

**Brand-survival threshold:** `single-user incident`. Auto-invokes `user-impact-reviewer` at PR review per `plugins/soleur/skills/review/SKILL.md` conditional-agent block. CPO sign-off carried forward from brainstorm Phase 0.5.

## Research Reconciliation — Spec vs. Codebase

Plan-time grep against worktree `main` HEAD surfaced these deltas. Each is resolved inline; no fictional infrastructure remains.

| Spec / brainstorm claim | Codebase reality (plan-time grep / Read) | Plan response |
|---|---|---|
| Inventory: 10 sites / 7 files | `git grep -nE '(log\|logger)\.(error\|warn\|info\|debug).*\buserId\b' apps/web-platform/app/` → 11 hits / 7 files. The 11th (`auth/github-resolve/callback/route.ts:157`) is a `logger.info` success path. | All 11 sites covered by `formatters.log` at the pino boundary. No per-site migration in this PR. |
| pino formatters.log signature at `pino.d.ts:470` | Line 470 is the **browser** interface. Node signature at `pino.d.ts:642-663`: `log?: (object: Record<string, unknown>) => Record<string, unknown>` | Plan cites L662. Ordering verified at `pino/lib/tools.js:161-200` — formatters.log runs before redact. |
| Recursive walker: top-level + 1-level nested | All 11 current sites are top-level only. `grep -rnE "\b(targetUserId\|actorUserId\|byUserId\|forUserId\|invitedUserId)\b" apps/web-platform/` → **zero hits**. Plan-review (DHH, Kieran, specflow) all flag 1-level-nested as YAGNI. | **Top-level only.** If a nested site appears, widen with intent. Test explicitly asserts `{extra: {userId}}` is NOT renamed. |
| Spec TR3 `null` handling: "no-op pass-through (no `userIdHash` key added)" | `observability.ts:53` shipped behaviour: nullable userId → `userIdHash: "pepper_unset_null"` sentinel | Plan + spec align with codebase: emit `userIdHash: "pepper_unset_null"` for null. Spec TR3 wording is wrong; corrected in spec update bundled with this plan. |
| `scrubSentryEvent` wiring uncertain | `apps/web-platform/sentry.server.config.ts:12-16` invokes `scrubSentryEvent` in `beforeSend` AND `scrubSentryBreadcrumb` in `beforeBreadcrumb`. Confirmed wired. | Out of this PR's scope (sentry-scrub coverage deferred to PR-B); confirmation noted for future plan. |
| `Sentry.setUser` placement options | `instrumentation.ts` documented no-op for custom server. No `sentry.edge.config.ts`. `withUserRateLimit` at `with-user-rate-limit.ts:50-80` wraps `getUser()`. **Architecture F3:** Sentry's AsyncLocalStorage scope isolation may not apply to the custom-server boot path — cross-request bleed risk requires verification. | **Deferred to PR-B.** Plan-time scope verification is non-trivial; safer to ship in a dedicated PR with the 2-request scope-isolation test as gate. |
| PA8 §(c) §(ii) at `article-30-register.md:157` | Confirmed (Markdown table cell with (i)/(ii)/(iii) sub-clauses). AC6 grep tightened per Kieran P1.1 — line-anchored awk would not match mid-cell. | AC uses `grep -n "formatters.log()" ...` + negative regression assertion. |

## Approach

**Architecture (one-line per layer):**

1. **Single rename helper.** New `apps/web-platform/server/userid-pseudonymize.ts` exports `renameUserIdToHash(obj)` (top-level only) and `hashUserIdValue(rawValue)` primitive (per Kieran P1.4 — extract value-level primitive to avoid per-key allocation in any future caller). Handles `userId` and `user_id` keys, null/undefined → `"pepper_unset_null"` sentinel, missing pepper → `"pepper_unset"` sentinel via the existing `hashUserId()` in `observability.ts`.
2. **Pino logger boundary** (`logger.ts`). Add `formatters.log: (obj) => safeRename(obj)` where `safeRename` wraps the rename in try/catch (per Architecture F2). Throw → return `obj` unchanged + one-time `console.warn` to avoid logger re-entrancy.
3. **PA8 §(c) §(ii) wording update.** Single-path disclosure scoped explicitly to `apps/web-platform/server/**` pino emissions. Cites `formatters.log()` by name (per Kieran P1.2) so silent regression of the formatter would be visibly inconsistent with the legal text.
4. **ADR-029.** Documents the rename-at-boundary pattern for future contributors (per Architecture AP-011).
5. **Persistent CI gate.** `.github/workflows/lint.yml` (or equivalent) adds a `pnpm lint:userid-bypass` step that runs the bypass-grep against PR diffs. Stops silent regression after merge (per GDPR critical + Architecture F5).

**Why Option D (formatters.log) — Risks-section justification per learnings-researcher caution:** formatters.log is net-new pino infrastructure in this codebase (verified — zero `formatters:` hits in `apps/`). The trade-off vs. per-site migration (Option A) is justified because: (a) covers all 11 current sites + future sites for free; (b) preserves operator grep via hash; (c) enables PA8 §(c) single-path disclosure on day one. The brainstorm explicitly weighed this; the YAGNI counter (DHH/code-simplicity) was considered and rejected because the AC two-clause structure makes Option A more code-fragile under the brand-survival threshold framing.

## Files to Create

1. `apps/web-platform/server/userid-pseudonymize.ts` — shared `renameUserIdToHash(obj)` + `hashUserIdValue(rawValue)` helpers.
2. `apps/web-platform/test/userid-pseudonymize.test.ts` — synthesised-UUID-only fixtures (per `cq-test-fixtures-synthesized-only`); ~6 fixtures.
3. `apps/web-platform/test/logger-formatters.test.ts` — vitest integration test wiring pino + formatters.log; uses `vi.hoisted` per `observability.test.ts:5-42` pattern.
4. `knowledge-base/engineering/architecture/decisions/ADR-029-rename-at-boundary-userid-pseudonymisation.md` — documents the pattern.
5. `.github/workflows/lint-userid-bypass.yml` OR a step appended to existing CI — runs the bypass-grep on PR diff for persistent enforcement.

## Files to Edit

1. `apps/web-platform/server/observability.ts` — refactor `hashExtraUserId` (L48-55) to delegate to the shared `renameUserIdToHash`. Zero behaviour change; existing tests are the regression gate.
2. `apps/web-platform/server/logger.ts` — add `formatters: { log: safeRename }` where `safeRename` is a try/catch wrapper around `renameUserIdToHash`. Wire into pino factory (L15-30).
3. `knowledge-base/project/specs/feat-pino-userid-redaction-3698/spec.md` — narrow FR scope to match this PR. FR1 (formatters.log) + FR5 (PA8 §(c)) stay. FR2/FR3/FR4/FR6 marked as deferred to PR-B/PR-C with linked issues. Correct TR3 null-handling row (currently contradicts codebase per canonical spec-flow finding).
4. `knowledge-base/legal/article-30-register.md` — PA8 §(c) §(ii) at L157 (single-path rewrite; cites `formatters.log()` explicitly).

## Open Code-Review Overlap

1 open code-review issue intersects `sensitive-keys.ts`, but this PR does **NOT** edit that file (brainstorm rejected the REDACT_PATHS path; rename happens via `renameUserIdToHash`, not via the sensitive-keys list).

- **#3363 — Migrate runtime JWT minting from legacy HS256 secret to Supabase asymmetric sign.** Touches `sensitive-keys.ts`. Disposition: **Acknowledge — zero file overlap with this PR.** #3363 remains open and orthogonal.

## Implementation Phases

Phase order is contract-changing-before-consumer per `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`. Each phase ships green tests before the next begins.

### Phase 0 — Preflight

- [ ] **0.1** Re-run inventory grep against worktree HEAD:
   ```bash
   git grep -nE '(log|logger)\.(error|warn|info|debug).*\buserId\b' apps/web-platform/app/ apps/web-platform/server/
   ```
   Expected: 11 hits across 7 files. If drift, update scope.
- [ ] **0.2** Confirm pino formatters.log signature at `apps/web-platform/node_modules/pino/pino.d.ts:642-663`. Confirm ordering at `apps/web-platform/node_modules/pino/lib/tools.js:161-200`. If pino major has changed since plan (currently 10.3.1), re-verify.
- [ ] **0.3** Confirm shared rename module path is free:
   ```bash
   ls apps/web-platform/server/userid-pseudonymize.ts 2>/dev/null && echo COLLISION || echo FREE
   ```

### Phase 1 — Shared rename helper (`userid-pseudonymize.ts`)

- [ ] **1.1** Write failing tests in `apps/web-platform/test/userid-pseudonymize.test.ts`:
   - top-level `userId` (string) → renamed to `userIdHash` (64 hex)
   - top-level `user_id` (string) → renamed to `userIdHash`
   - `null` value → `userIdHash: "pepper_unset_null"` (matches `observability.ts:53` behaviour)
   - missing pepper → `userIdHash: "pepper_unset"`
   - both `userId` AND `userIdHash` present → keep `userIdHash`, drop `userId` (defensive)
   - empty object `{}` → unchanged (no `userIdHash` key added)
   - object with keys but no userId/user_id → unchanged
   - nested `{extra: {userId}}` → **NOT** rewritten (asserts top-level boundary)
   - Use synthesised UUID fixtures only (`cq-test-fixtures-synthesized-only`).
- [ ] **1.2** Implement `renameUserIdToHash(obj)` and `hashUserIdValue(rawValue): string` in `apps/web-platform/server/userid-pseudonymize.ts`. Pure functions; no side effects. Imports `hashUserId` from `./observability`.
- [ ] **1.3** Refactor `hashExtraUserId` in `observability.ts:48-55` to delegate to the shared helper. Run `bun test apps/web-platform/test/observability*.test.ts` — must stay green.

### Phase 2 — Pino `formatters.log()` rename hook (with try/catch)

- [ ] **2.1** Write failing tests in `apps/web-platform/test/logger-formatters.test.ts`:
   - emit `logger.error({userId: "uuid-1", err: new Error("x")}, "msg")` → captured line contains `userIdHash: <hash(uuid-1)>` and NOT `userId`
   - emit `logger.info({user_id: "uuid-2"}, "msg")` → captured line contains `userIdHash: <hash(uuid-2)>`
   - emit `logger.warn({extra: {userId: "uuid-3"}}, "msg")` → captured line still contains nested `{extra: {userId: "uuid-3"}}` (top-level boundary)
   - **Throw safety (Architecture F2):** stub `hashUserId` (via `vi.mock`) to throw; emit `logger.error({userId: "x"}, "msg")` → captured line emits the message + raw `{userId: "x"}` (NOT dropped); one `console.warn` recorded.
   - Use `vi.hoisted` for env discipline per `observability.test.ts` pattern.
- [ ] **2.2** Wire `formatters.log` into the pino factory at `logger.ts:15-30`:
   ```ts
   formatters: {
     log: (obj) => {
       try {
         return renameUserIdToHash(obj);
       } catch (err) {
         // Re-entrancy hazard if we use the logger here; use console.warn once.
         if (!formatterErrorReported) {
           formatterErrorReported = true;
           console.warn("[logger] formatters.log threw; falling back to raw object", err);
         }
         return obj;
       }
     },
   },
   ```
   `formatterErrorReported` is module-scope. Pure-function try/catch around the rename.
- [ ] **2.3** Smoke-test in dev: `doppler run -c dev -- pnpm dev`; trigger one route handler that emits `logger.info({userId, ...})` (e.g., POST `/api/accept-terms` after auth). Confirm dev console (`pino-pretty`) shows `userIdHash`, not `userId`.

### Phase 3 — PA8 §(c) §(ii) wording update

- [ ] **3.1** Edit `knowledge-base/legal/article-30-register.md:157`. Replace the existing §(ii) sub-clause wording (currently: "remaining direct `logger.error({ userId, ... })` call sites in `apps/web-platform/server/` and `apps/web-platform/app/` continue to log raw `user_id` to Hetzner Finland stdout pending the follow-up migration") with:

   > **(ii) pino stdout (Hetzner-resident, EU-only):** structured app logs — `conversation_id`, request metadata, and a `userId` field. From the deployment timestamp of #3698 forward, every `logger.{error,warn,info,debug}` emission across `apps/web-platform/server/**` and `apps/web-platform/app/**` is pseudonymised at the pino logger boundary via the `formatters.log()` rename hook in `apps/web-platform/server/logger.ts` (HMAC-SHA256 with a server-side pepper held in Doppler and not shared with the processor — Recital 26 pseudonymisation, retained as pseudonym to support breach-investigation linkage under PA8 §(b)(ii)). Every direct call site emits `userIdHash`; no raw `user_id` reaches stdout via the pino path. Pre-deployment historical lines remain on the Hetzner host until they age out per the retention window in §(f); no off-host copies are taken. Sentry-event payloads are pseudonymised at the helper boundary (`reportSilentFallback` / `warnSilentFallback` / `mirrorP0Deduped` in `apps/web-platform/server/observability.ts`); symmetric direct-capture coverage at the Sentry scrub layer is tracked under follow-up #3710.


### Phase 4 — ADR-029 (rename-at-boundary) + persistent CI gate

- [ ] **4.1** Create `knowledge-base/engineering/architecture/decisions/ADR-029-rename-at-boundary-userid-pseudonymisation.md`. Documents the pattern: rename-not-redact, single-source-of-truth helper, top-level boundary by design, try/catch fail-safe, PA8 §(c) coupling. Cross-references #3638, #3685, #3698 (this PR), #3696, ADR-026 (pii-gate).
- [ ] **4.2** Add a CI gate that runs the bypass-grep on every PR diff. Implementation: add a step to `.github/workflows/lint.yml` (or whichever workflow runs on `pull_request`):
   ```yaml
   - name: Lint userId bypass
     run: |
       set -euo pipefail
       hits=$(git diff --name-only origin/main...HEAD | grep -E '^apps/web-platform/(server|app)/' || true)
       if [[ -z "$hits" ]]; then exit 0; fi
       offenders=$(echo "$hits" | xargs git grep -nE '(log|logger)\.(error|warn|info|debug).*\buserId\b' \
                  | grep -vE 'reportSilentFallback|warnSilentFallback|mirrorP0Deduped|userIdHash\b|github-resolve/callback/route\.ts:1\d+' || true)
       if [[ -n "$offenders" ]]; then
         echo "::error::Direct userId emit detected (formatters.log covers it, but raw source readability suffers):"
         echo "$offenders"
         exit 1
       fi
   ```
   Tolerates the known github-resolve:157 leave-and-cover. Future direct-emit sites must explicitly opt-in via an inline grep-allowlist comment OR migrate to a helper.

### Phase 5 — Verification, multi-agent review, fix-inline + file follow-ups

- [ ] **5.1** Follow-up issues filed pre-plan-finalisation (already linked from this plan):
   - **#3710 (PR-B)** — Sentry.setUser + helper migration + sentry-scrub symmetric coverage. Body cites Architecture F3 scope-isolation verification as a load-bearing prereq.
   - **#3711 (PR-C)** — operator hash-user-id CLI + PA8 §(f) Hetzner pino retention pin + compliance-posture.md line 88 refresh.
   - **Spec TR3 null-handling row correction** folded inline into this PR's spec update.
- [ ] **5.2** Run full test suite: `bun test apps/web-platform/` — all green.
- [ ] **5.3** Type check: `cd apps/web-platform && tsc --noEmit` — zero errors.
- [ ] **5.4** Mark PR #3701 ready for review. `/soleur:review` invokes multi-agent panel; `user-impact-reviewer` auto-invokes per `brand_survival_threshold: single-user incident`.
- [ ] **5.5** Address review findings inline per `rf-review-finding-default-fix-inline`.
- [ ] **5.6** Two-clause verification (per `2026-05-12-centralized-at-helper-boundary-...md` Process Insight):
   ```bash
   # (i) Helper-routed sites covered: tests assert rename applied at every layer
   bun test apps/web-platform/test/userid-pseudonymize.test.ts apps/web-platform/test/logger-formatters.test.ts apps/web-platform/test/observability.test.ts

   # (ii) Direct-bypass coverage: assert no raw userId reaches stdout from any unguarded site
   # (After Phase 2 ships, formatters.log covers ALL emissions. The CI gate at Phase 4.2 prevents future regression.)
   git grep -nE '(log|logger)\.(error|warn|info|debug).*\buserId\b' apps/web-platform/app/ apps/web-platform/server/ \
     | grep -v "userIdHash\b"
   # Expected: 11 hits (10 emit sites + 1 success-info site at github-resolve:157). All are covered by formatters.log at the boundary. The CI gate enforces this expected set.
   ```

### Phase 6 — Merge + post-merge verification

- [ ] **6.1** Squash-merge PR #3701 to main after all gates pass. Use `Closes #3698` in the PR body.
- [ ] **6.2** Post-merge: SSH the prod host (via `ssh-fail2ban-unban.md` runbook); confirm a fresh pino line from a real request emits `userIdHash`, not `userId`:
   ```bash
   ssh root@135.181.45.178 'docker logs --tail 200 web-platform-app | grep -E "userIdHash|userId" | head -20'
   ```
- [ ] **6.3** Verify the CI gate fires on a smoke regression: file a throwaway PR adding `logger.error({userId: "x"})` to a scratch file; confirm the `lint-userid-bypass` step rejects.
- [ ] **6.4** Close #3698. File deferred follow-ups from Phase 5.1 if not already filed.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `apps/web-platform/server/userid-pseudonymize.ts` exists; exports `renameUserIdToHash(obj)` and `hashUserIdValue(rawValue)`. `observability.ts:hashExtraUserId` delegates to it. Verified by `grep -n "renameUserIdToHash\b" apps/web-platform/server/observability.ts apps/web-platform/server/logger.ts` returns ≥2 matches.
- [ ] **AC2 (two-clause per `2026-05-12-centralized-at-helper-boundary-...md`)**:
   - **(i) Helper-routed coverage:** `bun test apps/web-platform/test/{userid-pseudonymize,logger-formatters,observability,observability-pepper-unset,observability-mirror-debounce}.test.ts` all green.
   - **(ii) Direct-bypass coverage:** the Phase 5.6 grep returns exactly the expected 11 sites (10 emit + 1 leave-and-cover at github-resolve:157). Persistent enforcement via Phase 4.2 CI gate.
- [ ] **AC3** `formatters.log` in `logger.ts` wraps `renameUserIdToHash` in try/catch + `console.warn` fallback (Architecture F2). Verified by:
   ```bash
   grep -A 15 "formatters:" apps/web-platform/server/logger.ts | grep -E "try \{|catch|console\.warn"
   ```
   returns ≥3 matches.
- [ ] **AC4** `tsc --noEmit` passes for `apps/web-platform/`; `bun test apps/web-platform/` — no regressions.
- [ ] **AC5** `knowledge-base/legal/article-30-register.md:157` PA8 §(c) §(ii) wording matches the Phase 3.1 draft:
   ```bash
   grep -n "formatters.log()" knowledge-base/legal/article-30-register.md  # ≥1 match
   grep -n "pending the follow-up migration" knowledge-base/legal/article-30-register.md  # 0 matches
   ```
- [ ] **AC6** ADR-029 created at `knowledge-base/engineering/architecture/decisions/ADR-029-rename-at-boundary-userid-pseudonymisation.md`; cross-references #3638/#3685/#3698/#3696.
- [ ] **AC7** Persistent CI gate landed: `.github/workflows/lint.yml` (or equivalent) includes a step that runs the bypass-grep and fails on disallowed matches. Verified by inspecting the YAML for the `lint-userid-bypass` step name.
- [ ] **AC8** `user-impact-reviewer` auto-invoked at PR review per `brand_survival_threshold: single-user incident`; review concludes via the standard fix-inline flow.
- [ ] **AC9** PR body uses `Closes #3698` (NOT `Ref` — this is a code change closing the issue at merge).
- [ ] **AC10** Follow-up issues filed pre-merge (PR-B, PR-C, spec TR3 correction if not folded inline). Each has a milestone; each is linked from the PR description.

### Post-merge (operator)

- [ ] **POST1** SSH the prod host; confirm a fresh request's pino line shows `userIdHash` (Phase 6.2).
- [ ] **POST2** CI gate smoke test (Phase 6.3): a throwaway PR adding direct `logger.error({userId})` is rejected by `lint-userid-bypass`.
- [ ] **POST3** Close #3698 with reference to the merged PR.
- [ ] **POST4** Confirm PR-B and PR-C follow-up issues exist and are queued for next sprint.

## Test Strategy

**Unit tests** (`userid-pseudonymize.test.ts`): 6 fixtures (per code-simplicity cut list). Top-level userId/user_id rename, null→sentinel, missing-pepper→sentinel, double-hash defensive, empty-object pass-through, nested-NOT-renamed boundary. Pure-function tests; synthesised UUIDs only.

**Integration tests** (`logger-formatters.test.ts`): spin up a pino instance with formatters.log wired; emit; capture stdout via vitest mock; assert emit shape. Adversarial fixture: stub `hashUserId` to throw, assert pass-through + one `console.warn`. Uses `vi.hoisted` for env discipline per `observability.test.ts` pattern.

**Refactor regression**: `observability.test.ts` + `observability-pepper-unset.test.ts` + `observability-mirror-debounce.test.ts` run unchanged after `hashExtraUserId` is refactored to delegate. Green = zero behaviour change at the helper boundary.

## Risks

- **formatters.log() net-new infra.** First pino formatter in the codebase (verified — zero `formatters:` hits in `apps/`). Trade-off vs. per-site migration justified in the Approach section. Mitigation: try/catch (Architecture F2) + tests + Phase 2.3 dev smoke + persistent CI gate.
- **formatters.log() performance overhead.** HMAC-SHA256 per log line is ~microseconds. Risk that this adds measurable latency under load on `ws-handler.ts` (highest-volume pino caller). Mitigation: Phase 2.3 smoke test exercises one route; review-time `performance-oracle` invocation if hot. Fast-path skip (early-return when obj lacks userId/user_id key) is a one-line addition if hot.
- **Recursive walker explicitly out of scope.** Top-level only by design. If a future caller logs `{extra: {userId}}`, the Phase 1.1 test catches the silent leak and forces an explicit widening decision. CI gate at Phase 4.2 also catches direct-emit drift.
- **Deferred follow-ups carry residual risk.** PR-B (Sentry-side) and PR-C (Hetzner retention + operator CLI) ship later; until they land, (a) direct `Sentry.captureException({extra: {userId}})` sites outside helpers emit raw userId to Sentry (already-existing risk; not introduced here), (b) operators lose `userId` grep on direct-emit sites until they switch to `userIdHash` grep, (c) PA8 §(f) retention window remains the "re-confirm with infra runbook" placeholder. None of these block #3698's brand-survival-threshold compliance close.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO) — user-brand-critical triad carried forward from brainstorm Phase 0.5.

**Brainstorm carry-forward:** the brainstorm document's `## Domain Assessments` is the source of truth. Plan-time scope-trim per plan-review heuristic (both panels fire → prefer delete) shifted Sentry.setUser + helper migration + sentry-scrub coverage + operator CLI + PA8 §(f) to deferred follow-ups. CPO/CLO/CTO findings remain valid for those scope items in PR-B/PR-C; the narrowed PR-A scope inherits the triad's recommendation that Option D (formatters.log) is the right architecture for the pino boundary.

### Engineering (CTO — carry-forward)

**Summary:** Option D (pino formatters.log) is the canonical placement. Plan-time pivot resolves: shared helper extracted; try/catch added per Architecture F2; CI gate landed for persistent enforcement. Phase 4.2 setUser binding deferred to PR-B because plan-time Architecture F3 surfaced a scope-isolation correctness risk under the custom-server boot path that warrants verification in a dedicated PR.

### Legal (CLO — carry-forward + plan-time additions)

**Summary:** Option D is the Art. 5(1)(c) data-minimisation improvement; ships strictly less identifiable data on day one. PA8 §(c) §(ii) wording (Phase 3.1) tightened per Kieran P1.2 — explicitly cites `formatters.log()` and scopes the claim to server-side pino. GDPR-auditor critical findings folded inline: persistent CI gate at Phase 4.2 (replaces one-time AC), explicit Recital 26 "retained as pseudonym for breach-investigation linkage" rationale in PA8 wording. Compliance-posture.md line 88 refresh deferred to PR-C. DPD §(l) telemetry user-facing entry remains separate (#3708).

### Product/UX Gate

**Tier:** none. **Decision:** skipped (no user-facing surface — server-side telemetry only). Plan creates ZERO files in `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`.

### Product (CPO — carry-forward)

**Summary:** Operator runbook regression is deferred-acceptable: PR-C bundles the hash-user-id CLI. In the interim, oncall can compute a hash via `node -e "..."` (the same one-liner the CLI wraps). PA8 §(c) wording is truthful on day one of merge.

**Brainstorm-recommended specialists:** None named for non-UX-Gate invocation.

## Sharp Edges

- The Phase 4.2 CI gate is **load-bearing** for the AC2(ii) enforcement contract. Do NOT widen its grep scope past `apps/web-platform/(server|app)/` without re-deriving the expected baseline (currently 11 sites; only github-resolve:157 in the explicit allowlist).
- The recursive walker depth boundary (top-level only) is explicit per design. If a future caller logs `{extra: {userId}}`, the Phase 1.1 nested-boundary fixture catches it and forces an explicit widening decision. Top-level scope was chosen because all 11 current sites are top-level (verified via grep); 1-level-nested was rejected at plan review as YAGNI.
- PA8 §(c) §(ii) wording is a load-bearing legal disclosure. Phase 3.1 wording explicitly cites `formatters.log()` by name (Kieran P1.2) — silent regression of the formatter would surface as a wording inconsistency at the next CLO audit. Do NOT remove the citation without coordinating with CLO.
- `formatters.log()` runs synchronously on every log line. The try/catch wrapper at Phase 2.2 must NOT introduce async I/O. The `renameUserIdToHash` helper is pure (no I/O); confirmed at Phase 1.2.
- `console.warn` is used inside the formatter try/catch (not `logger.warn`) to avoid re-entrancy. Do NOT change to `logger` calls — pino's formatter throwing during a logger emit while the recovery path also emits via the same logger is a guaranteed hang/recursion.
- ADR-029 names follow-up issues by number. Update those numbers when PR-B and PR-C land.

## References

- **Issue:** #3698 (OPEN, P2-medium, deferred-scope-out, type/security)
- **Spec:** `knowledge-base/project/specs/feat-pino-userid-redaction-3698/spec.md` (narrowed inline with this plan)
- **Brainstorm:** `knowledge-base/project/brainstorms/2026-05-12-pino-userid-formatters-log-brainstorm.md`
- **PR:** #3701 (draft)
- **Parent PR:** #3685 (MERGED 2026-05-12)
- **Parent issue:** #3638 (Sentry pseudonymisation + Art. 17 erasure)
- **Parallel:** #3696 (client-side `lib/client-observability.ts`, OPEN — ships AFTER #3698)
- **Follow-up:** #3708 (DPD §(l) telemetry user-facing entry)
- **Pending follow-ups (filed at Phase 5.1):** PR-B (Sentry.setUser + helper migration + sentry-scrub), PR-C (operator CLI + PA8 §(f) + compliance-posture)
- **Plan-review findings (consolidated):** DHH, Kieran (P1.1/P1.2 applied; P1.6 rejected as inventory verified), code-simplicity (cuts applied), architecture-strategist F2/F3/F5 (applied), canonical spec-flow (TR3 null correction applied; AC regex tightened), legal-compliance-auditor (PA8 wording polish applied + CI gate; compliance-posture refresh deferred to PR-C)
- **Helper module:** `apps/web-platform/server/observability.ts` (L35 hashUserId, L48-55 hashExtraUserId — refactored to delegate)
- **Logger:** `apps/web-platform/server/logger.ts` (L15-30 pino factory — formatters.log target)
- **PA8 §(c) target:** `knowledge-base/legal/article-30-register.md` (L157 §(ii) sub-clause)
- **Pino types (Node):** `apps/web-platform/node_modules/pino/pino.d.ts:642-663`
- **Pino source (formatters→redact ordering):** `apps/web-platform/node_modules/pino/lib/tools.js:161-200`
- **Sentry init (server):** `apps/web-platform/sentry.server.config.ts:12-16` (`scrubSentryEvent` wired as `beforeSend` — confirmed)
- **SSH runbook:** `knowledge-base/engineering/ops/runbooks/ssh-fail2ban-unban.md`
- **Learnings (load-bearing):**
  - `knowledge-base/project/learnings/2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md` — two-clause AC pattern
  - `knowledge-base/project/learnings/security-issues/2026-05-12-multi-agent-review-catches-load-bearing-redaction-primitive-bypasses.md` — adversarial-fixture pattern, vi.hoisted discipline
  - `knowledge-base/project/learnings/2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md` — phase ordering
  - `knowledge-base/project/learnings/2026-05-12-plan-time-api-contract-verification-and-pipeline-via-package-json.md` — pino does NOT ship off-host
  - `knowledge-base/project/learnings/2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md` — both-panels-fire = prefer delete heuristic (triggered this plan's scope-trim)
  - `knowledge-base/project/learnings/2026-05-12-brainstorm-issue-body-option-and-inventory-staleness-pino-userid.md` — option-space + inventory verification
- **AGENTS.md rules:** `hr-weigh-every-decision-against-target-user-impact`, `hr-gdpr-gate-on-regulated-data-surfaces`, `cq-test-fixtures-synthesized-only`, `rf-review-finding-default-fix-inline`
