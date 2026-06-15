---
title: "fix: stream-replay silent fallback (op=ownership-mismatch) false-positive severity miscalibration"
date: 2026-06-15
type: fix
status: planned
branch: feat-one-shot-stream-replay-silent-fallback-ownership-mismatch
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
sentry_issue: 4bbd7379131f4399b784d0b8465fb2a7
relates_to: ["#5290 (ADR-059)", "PR #4816 (deferred-creation precedent)"]
deepened: 2026-06-15
---

# 🐛 fix: stream-replay `op=ownership-mismatch` is firing error-level Sentry events for benign reconnect races

## Enhancement Summary

**Deepened on:** 2026-06-15 | **Agents:** silent-failure-hunter, observability-coverage-reviewer, architecture-strategist, git-history-analyzer, code-simplicity-reviewer.

All 8 premise-validation claims **confirmed** by git-history-analyzer (emit origin #5290/`5c908a8a6` not `b1c7d1eff`; no IaC alert on the op; `sessionKind` lines; `getCurrentRepoUrl` no-workspaceId call; helper line numbers; `.single()` sibling; `6a54dda7a` ancestor of #5290). The plan's diagnosis is sound and architecturally approved.

**Material changes applied from review:**
1. **Op scheme simplified + security hole closed (resolves silent-failure-hunter P1 + code-simplicity headline).** Collapsed the proposed 4-op split toward 2 stable ops + a `level` discriminator + an `extra.cause` field, mirroring the cited #4816 precedent (which kept ONE op and downgraded the level), AND closed the genuine-cross-user downgrade hole by keeping the genuine "row owned by another / DB error" case at `error`. See revised Phase 1.
2. **Double-emit reconciliation (resolves observability-coverage P1).** `getCurrentRepoUrl` ALREADY emits `feature=repo-scope, op=read-current-repo-url.tenant-mint` at **error** level before returning `null` (`current-repo-url.ts:38-43`, `:57-63`) — that upstream emit is the actual transient-null noise source. The handler must NOT re-mirror the null case (double-count); it falls back silently and lets the upstream emit own detection. The handler's own job is only to downgrade the upstream from error→warning at the source (a small follow-up in scope).
3. **Observable deferral criterion (resolves silent-failure-hunter P1 + architecture P3).** The owned-by-another deferral's re-eval trigger rewritten to a *falsifiable* metric: "if `feature=stream-replay` warning volume does not drop ≥90% after the Phase 2 client gate deploys, investigate the residual as potential probes." Tracking issue filed in-PR.
4. **Drift-guard + RLS tests added (resolves observability-coverage P1/P2 + silent-failure-hunter P3).** Added an op-contract test (mirrors `sentry-kb-db-error-alert-op-contract.test.ts`) pinning genuine-error ops at error level, and an explicit RLS-denial (42501) test asserting the DB-error path stays `error`.
5. **Citation fix.** The cited learning `2026-05-27-sentry-warning-level-still-triggers-alert-rules.md` was flagged "fabricated" by two agents — **verified it DOES exist** at `knowledge-base/project/learnings/best-practices/`. The agents checked the wrong path; citation is real. Path made explicit below.

**Disagreement resolved:** architecture-strategist defended the 4-op split (op-split de-noises an op-keyed alert); code-simplicity argued for 2 ops + level (no op-keyed alert exists, so level alone de-noises, and 4 slugs add permanent contract surface that ADR/tests/future-alert must track in lockstep). **Resolution: simpler scheme** — no IaC alert keys on the op (premise-validated), so the level field de-noises today; the `extra.cause` field preserves Sentry-side triage distinguishability without minting 4 parallel slugs. This also makes the security-hole fix cleaner (the genuine case stays one error op, not buried among warning slugs).

## Overview

A production Sentry error — **"stream-replay silent fallback"**, `feature=stream-replay`, `op=ownership-mismatch`, `level=error`, web-platform@0.129.1 — is paging operations for what is almost certainly a **benign reconnect race**, not the cross-user attack the op was designed to flag.

The emit site is `apps/web-platform/server/ws-handler.ts` `handleResumeStream` (introduced by **PR #5290 / commit `5c908a8a6`**, ADR-059 "stream-since-disconnect replay buffer"). There are **two** `reportSilentFallback(op:"ownership-mismatch")` calls, both at **error** level:

1. **`ws-handler.ts:1373-1380`** — the `(id, user_id).single()` conversation lookup returns `convErr || !conv`.
2. **`ws-handler.ts:1389-1393`** — `convRepoUrl !== currentRepoUrl` (repo-scope mismatch).

ADR-059 §"Failure mode" deliberately classified ownership-mismatch as "**P1, potential cross-user attempt**". That is correct for a genuine cross-user/cross-tab attempt — but **both emit sites also fire on legitimate, recoverable conditions** that produce no harm (the client transparently falls back to the v1 honest persisted-history refetch). At `error` level on a hot reconnect path, this floods the alert stream and masks the next real regression — the exact failure mode of the near-identical precedent **PR #4816** (`history-fetch-404-not-owned-or-missing`).

**This plan re-calibrates severity by cause (the proven #4816 pattern: keep the genuine-attack signal at `error`, downgrade the benign races to `warning`/`info`, and split the op slug so the two are distinguishable), adds a client-side discriminator so the most common benign race never reaches the server, and fixes a latent correctness bug where a transient `getCurrentRepoUrl` null is misread as a repo-scope mismatch.** It does NOT change the deferred-creation model, the replay-buffer mechanism, or the "never lie" correctness floor.

## Premise Validation

Checked the feature description's cited references against current repo state:

- **Cited relation to leader-liveness commit `b1c7d1eff` (#5306, merged 2026-06-15):** **STALE / DISPROVEN by blame.** `b1c7d1eff` is a **client-side** `chat-state-machine.ts` watchdog fix; it does NOT touch `ws-handler.ts` or the ownership-mismatch emit. `git log -S 'op: "ownership-mismatch"' -- apps/web-platform/server/ws-handler.ts` attributes the emit solely to **`5c908a8a6` (PR #5290, ADR-059)**, merged 2026-06-14. The two share a theme (reconnect/replay/liveness) but not causation. The plan proceeds against #5290 as the true origin; the `b1c7d1eff` relationship is informational only.
- **Cited release `web-platform@0.129.1 (6a54dda7a)`:** plausible — `6a54dda7a` is `HEAD~4` on main and post-dates the #5290 merge that introduced the emit. Consistent.
- **ADR-059 exists** at `knowledge-base/engineering/architecture/decisions/ADR-059-stream-since-disconnect-replay-buffer.md` and is the design source of truth (verified read).
- **Self-capability claim verified (`hr-verify-repo-capability-claim-before-assert`):** confirmed no Terraform-managed Sentry alert filters on `op=ownership-mismatch` or `feature=stream-replay` (`git grep` over `apps/web-platform/infra/sentry/` returned zero) — so a severity recalibration or op-split will NOT dark an IaC monitor. The op-IS-IN-style alerts only exist for `kb-db-error`, `kb-sync`, `workspace-sync-health` (per `test/sentry-*-op-contract.test.ts`).

## Research Reconciliation — Spec vs. Codebase

| Claim (feature description) | Reality (verified) | Plan response |
|---|---|---|
| "Relates to leader-liveness / stuck-watchdog work (b1c7d1eff)" | Emit introduced by #5290 (`5c908a8a6`), not b1c7d1eff. b1c7d1eff is client-side state-machine only. | Treat #5290/ADR-059 as origin. Note b1c7d1eff as thematic-only. |
| "Replayed stream attributed to / claimed by the wrong owner/leader" | Not a leader/ownership *attribution* bug. The lookup is correctly owner-scoped (`.eq("user_id", userId)`). The event fires because the row legitimately doesn't exist yet (deferred creation) OR `currentRepoUrl` is transiently `null`. | Re-frame as a **severity-calibration + transient-null** bug, not an attribution bug. |
| "Silent fallback no longer silently triggered" | The fallback path (client refetch) is correct and must stay; only the **severity/labeling** of the mirror is wrong. | Keep the fallback; fix the mirror's severity + op + add client gate. |

## User-Brand Impact

**If this lands broken, the user experiences:** no direct user-facing breakage from the *fix* (the user already sees the correct honest-refetch fallback today). If the fix is wrong, the risk is the inverse: a genuine cross-user replay attempt gets downgraded to `warning`/`info` and stops paging — a security-observability regression.

**If this leaks, the user's data is exposed via:** the `extra` payload of the mirror already carries `userId` (hashed via `hashExtraUserId`) + `conversationId`; no new PII is added. The genuine-attack path (a real cross-user `conversationId`) MUST remain `error`-level so a true cross-tenant probe stays loud.

**Brand-survival threshold:** single-user incident. Rationale: this is the chat product's core reconnect path; mis-calibrating it either (a) buries the next real regression under benign-race noise (status quo) or (b) silences a genuine cross-user attempt (the fix's failure mode). Both are single-user-incident class. `requires_cpo_signoff: true`; `user-impact-reviewer` will run at review time.

## Root Cause

`handleResumeStream` re-verifies ownership + repo-scope before replaying buffered frames. Both guards are correct *as gates* (they must never replay another user's frames), but their **error-level mirror over-classifies recoverable conditions**:

### Cause A — transient `getCurrentRepoUrl` null misread as repo-scope mismatch (most probable)
`ws-handler.ts:1357` calls `getCurrentRepoUrl(userId)` with **no `workspaceId` argument**. `current-repo-url.ts:37-43` returns `null` on a transient `RuntimeAuthError` (tenant-mint blip) and on a workspaces query error (`:57-63`). At `:1386`, `convRepoUrl !== currentRepoUrl` then evaluates `"<real-url>" !== null` → **true** → `op=ownership-mismatch` at `error` level, even though the conversation's repo is fine and the user is the legitimate owner. A reconnect is *exactly* the moment a tenant-mint is most likely to transiently fail. This is a latent correctness bug, not just a noise bug: a transient auth blip is reported as a cross-scope attack.

### Cause B — deferred-creation race (`.single()` returns empty)
Conversations are created **lazily on the first chat message** (`ws-handler.ts:1619-1621`; row materializes at `:1995-2001`). The client sets `realConversationIdRef.current` from `session_started` (`ws-client.ts:1053`) and re-sends `resume_stream` on every reconnect (`ws-client.ts:822-828`) **without gating on session kind**. If the socket drops in the window between `session_started` and the first message persisting the row, the server's `(id, user_id).single()` finds nothing → `op=ownership-mismatch` at `error` level. This is the identical class to **PR #4816** (`history-fetch-404-not-owned-or-missing`), where the fix was a client-side `sessionKind` discriminator + severity downgrade. The discriminator already exists in `ws-client.ts` (`sessionKind` state, set `"fresh"`@1067 / `"resumed"`@1092, reset@656) — it is wired into the history-fetch effect (`:1561`) but **NOT** into the `resume_stream` send.

### Cause C — genuine cross-user / cross-repo attempt (intended P1)
A real cross-user `conversationId`, or a legitimate post-stream workspace/repo switch, also reaches these guards. This is the case ADR-059's P1 classification was written for and MUST stay loud.

The fix must **distinguish A and B (benign, recoverable) from C (genuine, page-worthy)** rather than collapsing all three into one error-level op.

## Open Code-Review Overlap

4 open code-review issues touch files this plan edits; none fixes this bug. Disposition for each:

- **#3374** (slot_reclaimed WS frame) — touches `ws-handler.ts` + `ws-client.ts`. **Acknowledge** — unrelated (ledger-divergence recovery frame), different concern, own cycle.
- **#2191** (clearSessionTimers helper + timer jitter) — touches `ws-handler.ts`. **Acknowledge** — unrelated timer refactor.
- **#3280** (useWebSocket history-fetch reducer refactor) — touches `ws-client.ts`. **Acknowledge** — adjacent (same hook) but a structural refactor of a *different* effect; folding in would balloon scope. Note: if #3280 lands first it may relocate the `sessionKind` read — re-verify the gate site at /work time.
- **#3739** (reportSilentFallbackWithUser helper extraction) — touches `observability.ts`. **Acknowledge** — this plan adds no new helper; it reuses existing `reportSilentFallback` / `warnSilentFallback` / `infoSilentFallback`. No conflict.

## Implementation Phases

### Phase 1 — Server: recalibrate severity by cause (`ws-handler.ts handleResumeStream`)

The contract change (op + severity) lands first so the test phase asserts against it. **Scheme (post-deepen, simplified per code-simplicity + security per silent-failure-hunter):** two stable ops, severity by `level`, cause-distinguished via an `extra.cause` string (groupable/filterable in Sentry without minting 4 parallel slugs that ADR/tests/future-alert must track in lockstep). No IaC alert keys on the op (premise-validated), so `level` is what de-noises today.

| op (stable) | level | when | cause (extra) |
|---|---|---|---|
| `ownership-mismatch` | **error** | genuine: row owned by another user, OR a real DB error (outage/RLS) | `cause: "db-error"` or `cause: "owned-by-another-or-absent"` |
| `ownership-mismatch` | **warning** | benign: deferred-not-yet-materialized (post Phase-2-gate this is rare) | `cause: "not-materialized"` |
| `repo-scope-mismatch` | **error** | genuine cross-repo: both URLs non-null and differ | `cause: "url-differs"` |
| (no emit) | — | transient `currentRepoUrl === null` | already mirrored upstream — see step 3 |

1. **Cause B (conversation lookup, `:1371-1383`):** switch `.single()` → `.maybeSingle()` so a zero-row result yields `{data:null, error:null}` (no PGRST116 wrapped as `convErr`). Classify:
   - `convErr` (real DB error — outage, **RLS denial 42501**): `reportSilentFallback(op:"ownership-mismatch", extra:{cause:"db-error"})` at **error**. The `pg_code` tag (helper `observability.ts:197`) keeps SQLSTATE queryable — RLS denial stays loud.
   - `!conv && !convErr` (row absent): **this is the security-sensitive branch** — it covers BOTH the benign deferred race AND a genuine cross-user `conversationId` (a real row owned by someone else returns `!conv` via the `.eq("user_id", userId)` filter; the two are indistinguishable here without a privileged query). **Resolution (closes silent-failure-hunter P1):** Phase 2's client gate removes the *only legitimate* source of a post-gate `!conv` (the fresh-deferred reconnect). After the gate ships, a `resume_stream` arriving for a `!conv` row is anomalous — the client only sends it for `sessionKind==="resumed"` (a row it believes is its own and materialized). Therefore: emit at **warning** with `extra:{cause:"not-materialized"}` during the transition (defense-in-depth, the benign source dominates pre-gate), and the observable deferral criterion (Non-Goals) gates the decision to escalate the residual to `error` once the gate has demonstrably drained the benign volume. Do NOT silence it below warning.
2. Preserve the existing **dashboard message string** verbatim (`cq-silent-fallback-must-mirror-to-sentry` / #4816 helper-`message` carry-forward). Each emit MUST pass an explicit `message:` (the current `"resume_stream: conversation not found or not owned"`).
3. **Cause A — transient `currentRepoUrl === null` (repo-scope guard, `:1357`, `:1386-1396`): do NOT re-mirror in the handler (closes observability-coverage P1, double-emit).** `getCurrentRepoUrl` ALREADY calls `reportSilentFallback(feature:"repo-scope", op:"read-current-repo-url.tenant-mint")` (error) on `RuntimeAuthError` (`current-repo-url.ts:38-43`) and `op:"read-current-repo-url"` (error) on query error (`:57-63`) BEFORE returning `null`. The handler re-mirroring the same blip would double-count. Instead:
   - If `currentRepoUrl === null`: **silently** `fallback(verifiedConvId)` — the upstream `feature=repo-scope` emit owns detection. The handler does not claim a repo-scope mismatch on a null (the current `convRepoUrl !== null` → `true` false-positive is fixed by this guard).
   - **In-scope follow-up (the actual transient-null noise fix):** the upstream `getCurrentRepoUrl` emits the `tenant-mint` blip at **error** today (`current-repo-url.ts:39`). That is itself over-classified for a transient retryable auth blip on a reconnect. Downgrade the `read-current-repo-url.tenant-mint` emit from `reportSilentFallback`→`warnSilentFallback` at the source (the genuine query-error path `:57-63` stays `error`). This is the single highest-volume contributor to the Sentry issue per Cause A and belongs in this PR (`rf-review-finding-default-fix-inline`).
   - If `currentRepoUrl !== null && convRepoUrl !== currentRepoUrl`: genuine cross-repo — `reportSilentFallback(op:"repo-scope-mismatch", extra:{cause:"url-differs"})` at **error**.
4. Add an inline comment at the `.maybeSingle()` site noting the deliberate asymmetry with the sibling `resume_session` `.single()` (`:1788`) — different contract — so a future consistency sweep doesn't reintroduce the PGRST116 conflation (architecture P2).
5. **Files to Edit:** `apps/web-platform/server/ws-handler.ts` (`handleResumeStream`, ~`:1355-1396`); `apps/web-platform/server/current-repo-url.ts` (`:38-43` tenant-mint emit downgrade).

### Phase 2 — Client: gate `resume_stream` send on `sessionKind === "resumed"` (`ws-client.ts`)

Mirror the #4816 fix: a fresh deferred conversation must not request replay of a row that doesn't exist yet.

1. The `resume_stream` send (`ws-client.ts:822-828`) lives in the `auth_ok` message handler, defined inside the `connect` useCallback whose dep array (`:1286`) does NOT include `sessionKind`. So the `sessionKind` useState (`:499`) is **captured stale** in that closure — architecture-strategist confirmed a ref is genuinely required (the existing handler reads `realConversationIdRef`/`hasConnectedBeforeRef` for exactly this reason; the history-fetch gate at `:1561` can read `sessionKind` state directly only because it is a `useEffect` with `sessionKind` in its dep array `:1566`). **Add a `sessionKindRef`** declared adjacent to `realConversationIdRef` (`:523`), set in the same places as the state (`"fresh"`@1067, `"resumed"`@1092, reset@656).
2. In the `auth_ok` reconnect branch, use a **positive allowlist** gate: only send `resume_stream` when `sessionKindRef.current === "resumed"` (a real, materialized, owned row). Enumerate all three union members explicitly (`null`→skip, `"fresh"`→skip, `"resumed"`→send) per the #4816 single-literal-gate corollary — do NOT use `!== "fresh"`. For the skip cases dispatch plain `live` (a fresh deferred conversation has no buffered turn worth replaying and no DB row to verify).
3. Keep the ref paired with `realConversationIdRef` resets so the gate survives future refactors (#4816 corollary).
4. **Files to Edit:** `apps/web-platform/lib/ws-client.ts` (`auth_ok` handler ~`:819-843`; ref declaration + set/reset sites).

### Phase 3 — Tests (RED before GREEN, `cq-write-failing-tests-before`)

Extend `apps/web-platform/test/server/ws-handler-resume-stream.test.ts` (vitest; run `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/ws-handler-resume-stream.test.ts`). Existing coverage: ownership not-owned (`:165`), repo-scope mismatch (`:181`), cursor-evicted (`:147`), abusive ackSeq (`:200`), second-tab (`:226`). Add:

1. **Transient null repo-url (no double-emit):** `vi.mocked(getCurrentRepoUrl).mockResolvedValueOnce(null)` → assert the **handler** emits NO Sentry mirror (neither `reportSilentFallback` nor `warnSilentFallback` from `ws-handler`), AND `stream_replay{incomplete}` still sent. (Detection is owned by the upstream `getCurrentRepoUrl` `feature=repo-scope` emit, exercised in its own test — see test 6.)
2. **Deferred-not-materialized:** conversation lookup `.maybeSingle()` returns `{data:null,error:null}` → assert `warnSilentFallback(op:"ownership-mismatch", extra:{cause:"not-materialized"})` (warning), fallback sent.
3. **Genuine DB error (incl. RLS denial 42501):** lookup returns `{data:null, error:<dbErr>}` for both a generic error AND a 42501 RLS-denial error → assert `reportSilentFallback(op:"ownership-mismatch", extra:{cause:"db-error"})` (error) fires with the `pg_code` tag — genuine signal stays loud (silent-failure-hunter P3).
4. **Genuine repo-scope mismatch:** `getCurrentRepoUrl` returns repo-A, conv repo-B (both non-null) → assert `reportSilentFallback(op:"repo-scope-mismatch", extra:{cause:"url-differs"})` (error).
5. **Client:** assert a `"fresh"` (and `null`) sessionKind reconnect does NOT emit `resume_stream`, and a `"resumed"` reconnect does (paired positive/negative for the gate). Verify the include glob (`vitest.config.ts` collects `test/**/*.test.ts` (node) + `lib/**/*.test.ts`) before choosing the path; place the test where the runner discovers it.
6. **`current-repo-url.ts` tenant-mint downgrade:** assert the `RuntimeAuthError` path now emits `warnSilentFallback(op:"read-current-repo-url.tenant-mint")` (warning), and the query-error path stays `reportSilentFallback(op:"read-current-repo-url")` (error). New/extended test for the source-side downgrade (Phase 1 step 3).
7. **Op-contract drift-guard (observability-coverage P1):** add `apps/web-platform/test/sentry-stream-replay-severity-op-contract.test.ts` mirroring `sentry-kb-db-error-alert-op-contract.test.ts` — pin the contract: `op:"ownership-mismatch"` and `op:"repo-scope-mismatch"` MUST be reachable via `reportSilentFallback` (error), failing closed if a future edit downgrades a genuine-error op. This is the durable guard the in-suite cases (tests 2-4) cannot provide.
8. To assert severity, spy on the observability helpers (`reportSilentFallback`/`warnSilentFallback`) — already mock-friendly at the module boundary (existing tests do this).

### Phase 4 — Update ADR-059 + verify no consumer darks

Sweep for `ownership-mismatch` usage beyond the emit (`git grep -rn "ownership-mismatch" -- apps/web-platform/ knowledge-base/`). Confirmed today (git-history-analyzer): only `ws-handler.ts` (2 emits) + ADR-059/prior-plan prose; no Terraform alert, no op-contract test. The op slugs are **kept stable** (no rename) — `ownership-mismatch` + `repo-scope-mismatch` — so no consumer can dark; the change is `level` + `extra.cause` + the transient-null no-re-mirror. Update ADR-059 §"Failure mode on cap overflow" to document the severity-by-cause scheme (genuine cause → error; `not-materialized` → warning; transient null → handled by upstream `feature=repo-scope`, no handler re-mirror). No IaC/UI alert keys on the op (verified), so no alert-config follow-up is required (see Observability `alert_route` honesty note).

## Acceptance Criteria

### Pre-merge (PR)
- [x] AC1 — `handleResumeStream` conversation lookup uses `.maybeSingle()` (verified by `git grep -n "maybeSingle" apps/web-platform/server/ws-handler.ts` showing the resume_stream lookup), so a zero-row result does not populate `convErr`.
- [x] AC2 — the deferred/not-materialized case (`!conv && !convErr`) emits `warnSilentFallback(op:"ownership-mismatch", extra:{cause:"not-materialized"})` (**warning**); the genuine-DB-error case (`convErr`, incl. RLS 42501) stays `reportSilentFallback(op:"ownership-mismatch", extra:{cause:"db-error"})` (**error**) with the `pg_code` tag. (Asserted by vitest tests 2 + 3.)
- [x] AC3 — the repo-scope guard emits **no handler-side mirror** when `currentRepoUrl === null` (no double-emit; upstream `feature=repo-scope` owns detection), and `reportSilentFallback(op:"repo-scope-mismatch", extra:{cause:"url-differs"})` (error) only when both URLs are non-null and differ. (Asserted by vitest tests 1 + 4.)
- [x] AC4 — `current-repo-url.ts` `RuntimeAuthError`/tenant-mint emit downgraded from `reportSilentFallback`→`warnSilentFallback` (the query-error path stays error). (Asserted by vitest test 6.)
- [x] AC5 — client uses a positive-allowlist gate: does NOT send `resume_stream` on reconnect when `sessionKindRef.current` is `"fresh"` or `null`; sends it only when `"resumed"`. All three union members handled explicitly. (Asserted by client test 5.)
- [x] AC6 — every new/changed emit passes an explicit `message:` (no reliance on the `"<feature> silent fallback"` default); verified by reading each call.
- [x] AC7 — `sentry-stream-replay-severity-op-contract.test.ts` exists and pins `op:"ownership-mismatch"` + `op:"repo-scope-mismatch"` as error-level emit slugs (fails closed on a future downgrade). (Test 7.)
- [x] AC8 — `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/ws-handler-resume-stream.test.ts` is green (all new + existing cases); plus the new op-contract test green.
- [x] AC9 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [x] AC10 — ADR-059 §"Failure mode" updated to document the severity-by-cause scheme (genuine→error, `not-materialized`→warning, transient-null→upstream-only).
- [x] AC11 — no Terraform Sentry monitor references the op (`git grep -n "ownership-mismatch\|stream-replay" apps/web-platform/infra/sentry/` returns 0 — already true; re-verify post-edit; op slugs unchanged so nothing darks regardless).
- [x] AC12 — tracking issue for the deferred owned-by-another enumeration is filed in this PR with the observable re-eval criterion (see Non-Goals): **#5324**. `Ref #5324` in PR body.

### Post-merge (operator)
- [ ] AC13 — confirm Sentry production: `feature=stream-replay` **error**-level event rate drops to near-zero (only genuine DB-error / cross-repo), and `feature=repo-scope op=read-current-repo-url.tenant-mint` flips from error→warning. **Automation:** read-only via Sentry API (`mcp__*` / events query) — pull per-op event counts + levels for the 48h post-deploy window; do NOT eyeball the dashboard (`hr-no-dashboard-eyeball-pull-data-yourself`). Deploy + container restart handled by `web-platform-release.yml` on merge to main touching `apps/web-platform/**` — no separate operator restart.
- [ ] AC14 — verify the observable deferral criterion: `feature=stream-replay` **warning** volume (`cause:"not-materialized"`) drops ≥90% vs the pre-deploy baseline once the Phase-2 client gate is live. If it does NOT drop, the residual is candidate cross-user probes → escalate per the tracking issue. **Automation:** Sentry API event-count comparison (read-only).

## Domain Review

**Domains relevant:** Engineering (CTO) only.

Assessed all 8 domains against the plan (semantic sweep). This is a server/client observability-severity + reconnect-race bug fix in `apps/web-platform`. No new user-facing page/flow/component (the user-visible fallback behavior is unchanged). No legal/compliance surface change (no new data captured; `userId` already hashed). No marketing/sales/finance/ops/support implication. CTO lens carried in Root Cause + Sharp Edges.

### Product/UX Gate
**Mechanical UI-surface override:** `## Files to Edit` contains `lib/ws-client.ts` (a hook, not a `components/**/*.tsx` / `app/**/page.tsx` / `app/**/layout.tsx` file) — does NOT match the UI-surface glob superset. No `.tsx` page/component/layout file is created or edited. The change is reconnect-control-flow + observability, with **no change to rendered UI** (the fallback the user sees is identical). **Tier: NONE.** Skip Product/UX Gate.

## Observability

```yaml
liveness_signal:
  what: stream-replay resume_stream handler outcome events (per-op)
  cadence: per reconnect attempt (event-driven, not periodic)
  alert_target: Sentry (web-platform project), feature=stream-replay tag
  configured_in: apps/web-platform/server/ws-handler.ts (reportSilentFallback/warnSilentFallback/infoSilentFallback)
error_reporting:
  destination: Sentry via reportSilentFallback (level=error) for genuine ownership-mismatch (DB error/RLS, cause=db-error) + repo-scope-mismatch (cause=url-differs)
  fail_loud: yes — genuine cross-user DB error and genuine cross-repo mismatch stay error-level; helper mirror failures are swallowed by design (observability.ts) but the primary signal is loud
failure_modes:
  - mode: genuine — conversation lookup DB error / RLS denial 42501 (or row owned-by-another, pre-enumeration)
    detection: reportSilentFallback op=ownership-mismatch level=error extra.cause=db-error (pg_code tag carries SQLSTATE)
    alert_route: "Sentry error event, feature=stream-replay — NO issue-alert configured (search-only); see AC12 tracking issue for the alert decision"
  - mode: genuine cross-repo stale cursor (both URLs non-null, differ)
    detection: reportSilentFallback op=repo-scope-mismatch level=error extra.cause=url-differs
    alert_route: "Sentry error event — NO issue-alert configured (search-only)"
  - mode: transient currentRepoUrl resolve failure (RuntimeAuthError tenant-mint)
    detection: warnSilentFallback feature=repo-scope op=read-current-repo-url.tenant-mint (warning) — emitted UPSTREAM in current-repo-url.ts; handler does NOT re-mirror (no double-emit)
    alert_route: Sentry warning-level (informational, does not page)
  - mode: deferred conversation not yet materialized (post Phase-2-gate: rare)
    detection: warnSilentFallback op=ownership-mismatch level=warning extra.cause=not-materialized
    alert_route: Sentry warning-level (informational); volume tracked by AC14 deferral criterion
logs:
  where: pino structured logs (logger.error/warn inside the helpers) + Sentry
  retention: existing web-platform Sentry retention (unchanged)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/server/ws-handler-resume-stream.test.ts"
  expected_output: "all cases pass, including the severity-by-cause + op-contract + tenant-mint-downgrade assertions (no ssh required)"
```

## Test Scenarios

1. Transient `getCurrentRepoUrl` null → handler emits NO mirror, fallback sent (upstream `feature=repo-scope` owns detection; no double-emit).
2. Deferred row absent (`.maybeSingle` → null/null) → warning `ownership-mismatch` `cause=not-materialized`, fallback sent, NO error event.
3. Genuine DB error on lookup (generic + RLS 42501) → error `ownership-mismatch` `cause=db-error` with `pg_code` tag (stays loud).
4. Genuine repo-A-vs-repo-B mismatch (both non-null) → error `repo-scope-mismatch` `cause=url-differs` (stays loud).
5. Client reconnect with `sessionKind="fresh"` (and `null`) → no `resume_stream` sent.
6. Client reconnect with `sessionKind="resumed"` → `resume_stream` sent (regression guard for the happy path).
7. `current-repo-url.ts` tenant-mint path → warning (downgraded); query-error path → error (unchanged).
8. Op-contract test: genuine-error ops pinned at error level (fails closed on future downgrade).
9. Existing: cursor-evicted (warning, unchanged), abusive ackSeq clamp (unchanged), second-tab no-interleave (unchanged), live-agent-not-aborted invariant (unchanged).

## Non-Goals / Deferred

- **Deeper genuine-cross-user detection** (distinguishing "row exists, owned by another user" from "row absent" at the `resume_stream` layer): currently both return `!conv` due to the `.eq("user_id", userId)` filter. A dedicated owned-by-another probe (service-role count without the user filter, debounced per-user via `mirrorWithDebounce`) would let the genuine-attack case stay error while the deferred case is warning — but it adds a privileged query on a reconnect path. **Defer** to a tracking issue with an **observable** re-evaluation criterion (rewritten per silent-failure-hunter P1 — the original "dominated by real attempts" criterion was unfalsifiable): **"if `feature=stream-replay` warning volume (`cause:not-materialized`) does NOT drop ≥90% in the 7 days after the Phase-2 client gate deploys, the residual is candidate cross-user probes — escalate the owned-by-another probe."** The Phase-2 gate removes the only legitimate source of a post-gate `!conv`, so a non-drop is itself the falsifiable signal. File the issue in the same PR with `Ref #<n>` in the PR body (`wg-when-deferring-a-capability-create-a`).
- **Replay-buffer mechanism / caps / TTL** (ADR-059) — unchanged.
- **Agent/MCP transport parity for replay** — already deferred by ADR-059 to a V2 issue.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan fills it: threshold `single-user incident`.)
- **Severity downgrade ≠ alert silence** (learning `knowledge-base/project/learnings/best-practices/2026-05-27-sentry-warning-level-still-triggers-alert-rules.md` — verified exists; two deepen agents flagged it "fabricated" by checking the wrong path): a Sentry alert filtering on `feature`+`op` only (no `level` filter) still fires on warning events. Here the op slugs are **kept stable** and `level` does the de-noising because — premise-validated — **no IaC or op-contract alert keys on `op=ownership-mismatch` or `feature=stream-replay`** (so warning events don't page through any current rule). Re-verify at /work; the op-contract drift-guard test (Phase 3 test 7) is the durable defense against a future alert author downgrading a genuine-error op.
- **Double-emit on transient null (resolved):** `getCurrentRepoUrl` already mirrors the transient `null` upstream (`current-repo-url.ts:38`); the handler MUST NOT re-mirror. The actual transient-null fix is downgrading the UPSTREAM `tenant-mint` emit error→warning (Phase 1 step 3), not adding a handler emit.
- **`.single()` → `.maybeSingle()` changes the `convErr` semantics**: with `.single()`, zero rows populates `convErr` (PGRST116); with `.maybeSingle()`, zero rows yields `{data:null, error:null}`. The Phase-1 classification depends on this switch — change the resume_stream lookup ONLY; the sibling `resume_session` lookup at `:1788` keeps `.single()` (different contract — it returns a user-facing error frame, no severity classification) and is out of scope. Add the inline comment (Phase 1 step 4) so a future consistency sweep doesn't "fix" the asymmetry.
- **`sessionKind` is `useState`, not a ref — a `sessionKindRef` IS required** (architecture-strategist confirmed): the `auth_ok` handler lives in the `connect` useCallback whose dep array (`:1286`) excludes `sessionKind`, so the state is captured stale. A naive copy of the #4816 state-read gate (which works at `:1561` only because that's a `useEffect` with `sessionKind` in deps) would silently no-op here. Use the ref; positive-allowlist gate (`=== "resumed"`), all three union members enumerated.
- **Genuine-attack regression risk (the fix's failure mode):** genuine cross-user (DB error/RLS) and genuine cross-repo (both URLs non-null) MUST stay `error`-level. The `!conv && !convErr` warning branch also catches genuine owned-by-another rows (indistinguishable pre-enumeration) — this is consciously deferred behind the **observable** AC14 criterion, NOT silenced. The negative-control tests (AC2/AC3/AC7 op-contract) are the regression guard; do not collapse them.
