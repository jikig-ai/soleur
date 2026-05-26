---
title: "fix(cc): V2 Command Center hardening — safe-bash module, mirror debounce, idle-reaper, wall-clock budget"
date: 2026-05-11
issue: 3040
type: fix
classification: code-hardening
requires_cpo_signoff: false
---

# fix(cc): V2 Command Center hardening — safe-bash module, mirror debounce, idle-reaper, wall-clock budget

Closes #3040.

## Enhancement Summary

**Deepened on:** 2026-05-11
**Sections enhanced:** 7 (Approach Selection, Files to Edit, Tests to Edit, Acceptance Criteria, Risks, Sharp Edges, Implementation Phases)
**Verified live:** PR #3020 (MERGED), PR #3225 (MERGED 2026-05-05), issues #3369 (OPEN), #3344 (OPEN), #3343 (OPEN); AGENTS.md rule IDs `hr-weigh-every-decision-against-target-user-impact`, `rf-review-finding-default-fix-inline`, `cq-silent-fallback-must-mirror-to-sentry` (all ACTIVE); learning files `2026-05-05-defense-relaxation-must-name-new-ceiling.md`, `2026-05-05-trace-callgraph-from-entrypoint-when-placing-guards.md`, `2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md` (all present).

### Key Improvements (from deepen pass)

1. **Existing test drift surfaced for Finding 4.** Three sites in `soleur-go-runner-awaiting-user.test.ts` (line 46 docstring, line 332 inline comment, AC9 at line 291 — `5s + 20s + 30s` per-window assertion) plus three doc-comments in `soleur-go-runner.ts` (lines 829, 1233, the `firstToolUseAt = now()` re-stamp at line 2518) pin the existing **per-window** wall-clock semantic. The plan's Finding 4 changes that to **cumulative**; ALL six sites must be updated. Per the 2026-05-05 defense-relaxation learning, missing one is the canonical drift class. Promoted from a sharp-edge note to an explicit AC and Phase 4 task list.
2. **Existing silent-fallback test pinned at `notifyAwaitingUser` line 407** explicitly asserts `mockReportSilentFallback.mock.calls.filter(([, ctx]) => ctx?.feature === "soleur-go-runner" && ctx?.op === "notifyAwaitingUser").toHaveLength(1)`. Finding 2 changes the helper from `reportSilentFallback` to `mirrorWithDebounce` — this test must change to mock+assert against `mirrorWithDebounce` instead. Added to Phase 3 tasks.
3. **`vi.mock` pattern confirmed:** `vi.mock("@/server/observability", () => ({ reportSilentFallback, mirrorWithDebounce }))` is the established project pattern (3+ existing test files). Tests for Phase 2 should use this shape, not a fresh-spawn mock factory.
4. **`mirrorWithDebounce` re-arming arithmetic recipe (R2 risk):** preferred shape is "re-arm if too-early at fire time" rather than "compute effective anchor at arm time". The arm-time-anchor shape is fragile against the `pausedAt → null` transition (need to re-arm at that boundary too); the fire-time-recheck shape is symmetric on both arm and fire and only has one decision site. AC10/AC11 test against this shape.
5. **`closeQuery` location verified at line 1524**, not 1715 as initially stated. Files-to-Edit corrected.
6. **`recordAssistantBlock` first-block-of-turn reset semantic:** the existing code at line 1456-1458 stamps `firstToolUseAt` on the first block of a turn. Resetting `totalPausedMs` here means "new turn starts a new compute budget". Verified consistent with the existing `armTurnHardCap`-fires-once-per-turn intent (line 1463-1465). Confirmed in Phase 4 task 4.4.
7. **`NEAR_MISS_STATE: WeakMap<CanUseToolContext, ...>` cyclic-import risk:** `CanUseToolContext` is declared in `permission-callback.ts` (line 320). Moving the WeakMap to `safe-bash.ts` would force `safe-bash.ts → permission-callback.ts → safe-bash.ts`. Plan keeps the near-miss telemetry helpers + WeakMap inside `permission-callback.ts`; only the pure regex + `isBashCommandSafe` move. Promoted from R7 to a Files-to-Edit annotation.

### New Considerations Discovered

- AC9 in the existing test (line 291) is a load-bearing per-window assertion — must be rewritten to cumulative shape, not just added-to. Without the rewrite, the test fails at GREEN and the plan looks broken.
- The `mirrorWithDebounce` 5-min TTL is per-`(userId, errorClass)` key. The new `errorClass: "notify-awaiting-no-active-query"` will share its TTL bucket with no existing keys (verified: grep `errorClass` across cc-dispatcher.ts callsites — they use `"agent-sandbox:sdk-startup"`, `"dispatch:${...}"`, distinct namespaces).
- Vitest fake-timers project convention is `vi.setSystemTime(0)` + `vi.advanceTimersByTime(...)` + `flushMicrotasks()` await; this is the deterministic baseline for AC10/AC11.

## Overview

PR #3020 shipped three QA fixes for the Command Center (Soleur Concierge) — a narrow `safe-bash` allowlist, a wall-clock pause on review-gate, and a Concierge rename. Four hardening findings deferred from that review are tracked here:

1. **Extract `SAFE_BASH_PATTERNS` from `permission-callback.ts`** into a sibling `safe-bash.ts` module, following the existing `tool-tiers.ts` / `tool-path-checker.ts` / `review-gate.ts` extraction convention. Preserves the regex grammar; pure file-organization refactor that drops ~100 lines out of an 840-line callback file.
2. **Route `soleur-go-runner`'s `notifyAwaitingUser` silent-fallback through `mirrorWithDebounce`** so a misconfigured prod cannot flood Sentry. Resolves overlap with open issue #3369 (extract `mirrorWithDebounce` to `observability.ts`) by performing that extraction first, then both `cc-dispatcher.ts` and `soleur-go-runner.ts` import the canonical helper.
3. **Idle-reaper consults `awaitingUser`** so a Bash review-gate awaiting human review for >10 min is not reaped while the user is still reading. Without this, the SDK subprocess closes, `abortableReviewGate` awaits indefinitely until the 5-min safety-net rejects, and the user's eventual click is dropped via `respondToToolUse` returning `false`.
4. **Wall-clock budget on rapid status flap** — each `notifyAwaitingUser(false)` currently resets `state.firstToolUseAt = now()`. A workflow that rapidly toggles `waiting_for_user` ↔ `active` accumulates ~zero compute time across `tool_use` events. Pick **Approach A** (preserve original `firstToolUseAt`, subtract paused intervals) to give the 90s `wallClockTriggerMs` cumulative semantics across pauses. This preserves the existing 10-min `DEFAULT_MAX_TURN_DURATION_MS` ceiling unchanged (per the 2026-05-05 defense-relaxation learning).

All four are pre-existing-or-V2-deferred, low to medium blast radius, and ship together in one PR scoped to `apps/web-platform/server/`. No DB migrations, no SDK contract changes, no MCP tool additions, no user-facing copy changes.

## Research Reconciliation — Spec vs. Codebase

| Issue-body claim | Codebase reality | Plan response |
|---|---|---|
| Finding 2 cites `soleur-go-runner.ts:993-1009` for `reportSilentFallback`-direct call | Today at `soleur-go-runner.ts:2483-2522` (`notifyAwaitingUser` function body). The 993-1009 range was the line range at the time PR #3020 was reviewed; the file has grown ~1500 lines since for chapter-chunked PDF + interactive prompts. | Plan §"Files to Edit" references the symbol (`notifyAwaitingUser`), not the line range. The `reportSilentFallback` call site is unambiguous — there is exactly one such call inside `notifyAwaitingUser` (the `Error("notifyAwaitingUser: no active query")` branch). |
| Finding 3 cites `soleur-go-runner.ts:936-947` for the 10-min idle reaper | Today at `soleur-go-runner.ts:2426-2437` (`reapIdle` function). | Same — reference by symbol. |
| Finding 4 cites `soleur-go-runner.ts:1018-1024` for the `notifyAwaitingUser(false)` reset of `firstToolUseAt` | Today at `soleur-go-runner.ts:2510-2522` (`notifyAwaitingUser` body, `if (state.firstToolUseAt !== null) state.firstToolUseAt = now()`). | Same — reference by symbol. |
| Finding 4 says "30s `wallClockTriggerMs` safety net" | The 30s value was load-bearing at PR #3020 ship time, but PR #3225 relaxed `DEFAULT_WALL_CLOCK_TRIGGER_MS` to **90s** AND added `DEFAULT_MAX_TURN_DURATION_MS = 10 min` as a separate absolute ceiling. See learning `2026-05-05-defense-relaxation-must-name-new-ceiling.md`. | Plan uses 90s (per-block reset) + 10-min absolute ceiling (anchored on `firstToolUseAt`, NOT reset by per-block). Finding 4's threat surface is unchanged — rapid flap still re-anchors `firstToolUseAt` to `now()` on every `notifyAwaitingUser(false)`, neutralizing both the 90s window AND the 10-min absolute ceiling. Both must be preserved through the pause/resume cycle (see §"Approach Selection" below). |

## User-Brand Impact

- **If this lands broken, the user experiences:** Command Center conversations either (a) silently drop user clicks on review-gate options (reaper closes the SDK Query while user reads), (b) emit ~144k Sentry events/day in a misconfigured-prod loop, or (c) escape the runaway/turn-duration ceilings via rapid status flap — a runaway agent never trips its safety net.
- **If this leaks, the user's data is exposed via:** N/A — no new data surfaces, no auth, no payment, no multi-tenant boundary touched. The four findings are scoped to in-process state on a per-user `ActiveQuery`.
- **Brand-survival threshold:** `none` — all four changes harden existing in-process invariants. A regression is a single-user UX issue (extra-prompt UX or one Sentry flood) recoverable by a follow-up patch. The 30s→90s relaxation analyzed under `2026-05-05-defense-relaxation-must-name-new-ceiling.md` already happened in #3225; this PR does NOT relax any defense — it tightens three of them.

`threshold: none, reason: All four findings tighten existing defenses (sentry flood cap, reaper consults awaiting flag, paused-interval subtraction preserves wall-clock budget, refactor preserves regex grammar). No auth/payment/BYOK/multi-tenant boundary touched; no defense relaxed. A regression is a single-user UX issue, not a brand-survival event.`

## Approach Selection

### Finding 1 — extract vs. rewrite

Two approaches surfaced at #3020 review:

- **A (architecture-strategist):** extract to `apps/web-platform/server/safe-bash.ts` (sibling module). Preserves regex grammar. ~100 lines moved.
- **B (code-simplicity-reviewer):** replace regex grammar with fixed-string `Set` + prefix list (~15 LOC). Smaller policy surface; loses pattern flexibility (`git log --oneline -5` would need a separate entry).

**Choose A.** Reasoning:

- The regex grammar in the existing file is load-bearing for the BNF allowlist shape that #3344 (open: widen safe-bash for KB exploration parity) will extend. Killing the grammar now forces #3344 to rebuild it.
- Per-tool regex is the unit of audit reviewers (security-sentinel) look for — a fixed-string `Set` flattens the audit surface. Operators can grep `SAFE_BASH_PATTERNS` for a single source of truth.
- The 107-case `permission-callback-safe-bash.test.ts` already pins the grammar's edge cases. Moving the regex into a sibling module is a 1-import-rewrite; switching to a `Set` is a 107-case rewrite.
- Tradeoff acknowledged: Approach A does NOT shrink the policy surface. That is acceptable — the policy surface IS the point. See `2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md` precedent: security-relevant allowlists should be co-located with their tests.

### Finding 2 — per-runner DI vs. process-wide TTL

Issue body proposes:

- **A:** extend `SoleurGoRunnerDeps` with `mirrorSilentFallback?: (err, ctx) => void` injection. Per-runner blast radius.
- **B:** bake the debounce TTL into `reportSilentFallback` itself. Process-wide blast radius.

**Choose neither directly — fold in #3369.** Reasoning:

- Open issue #3369 already proposes extracting `mirrorWithDebounce` from `cc-dispatcher.ts` to `observability.ts` so other modules (e.g., `kb-document-resolver.ts`) can use the same debounce without circular import. That extraction is the canonical-location fix Approach B is reaching for, WITHOUT changing `reportSilentFallback`'s contract (no implicit debounce in the canonical mirror — opt-in via a separate exported function).
- After extracting per #3369, `soleur-go-runner.ts`'s `notifyAwaitingUser` no-active-query branch imports `mirrorWithDebounce(err, ctx, userId, errorClass)` directly with `errorClass: "notify-awaiting-no-active-query"`. No new dep, no process-wide implicit-debounce surprise.
- This folds in #3369 (Closes #3369) as part of this PR — see §"Open Code-Review Overlap".

### Finding 3 — bump `lastActivityAt` vs. skip reaper entry

Issue body proposes:

- **A:** bump `state.lastActivityAt = now()` in `notifyAwaitingUser(true)`.
- **B:** skip reaper entries with `awaitingUser === true`.

**Choose B.** Reasoning:

- (A) muddles the contract of `lastActivityAt` — its name says "last activity", and writing `now()` for a no-activity transition will mislead future readers + log readers. Sentry/observability already keys on `lastActivityAt` as a behavioral signal.
- (B) is one if-clause inside `reapIdle` and reads exactly as the intent: "do not reap a conversation that is paused for the user". Operators monitoring "reaped count" will not see paused conversations dropped. Tests can assert `reapIdle()` returns 0 when the only active query has `awaitingUser=true` and `lastActivityAt < cutoff`.
- (B) plus the 5-min `REVIEW_GATE_TIMEOUT_MS` safety net (`review-gate.ts:19`) means a stuck-paused conversation eventually transitions back to `active` (timeout rejects `abortableReviewGate`, the catch path closes the Query via `emitWorkflowEnded`), AND the next `reapIdle` tick after that transition reaps normally. No new "paused forever" leak surface.

### Finding 4 — cumulative budget vs. per-window

Issue body proposes:

- **A:** preserve original `firstToolUseAt`, subtract paused intervals (`pausedAt → resumedAt` duration) from elapsed. Cumulative budget.
- **B:** accept "per-active-window" semantics; document explicitly.

**Choose A.** Reasoning:

- (B) is what we have today — and it is the exact gap Finding 4 describes. A runaway agent interleaving cheap user prompts with heavy compute escapes the wall-clock entirely. (B) accepts the gap; (A) closes it.
- Per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`: when a defense's reset semantic changes, the plan body must name the new ceiling. (B) is a defense relaxation we cannot afford a second time. (A) preserves the agent-compute-time-only invariant from the existing comment ("agent compute time only, not human read time").
- Implementation: add `state.pausedAt: number | null` and `state.totalPausedMs: number` to `ActiveQuery`. On `notifyAwaitingUser(true)`, stamp `pausedAt = now()`. On `notifyAwaitingUser(false)`, if `pausedAt !== null`, accumulate `totalPausedMs += now() - pausedAt; pausedAt = null`. Compute "effective elapsed" as `now() - firstToolUseAt - totalPausedMs - (pausedAt ? now() - pausedAt : 0)` in both `armRunaway` and `armTurnHardCap`. The wall-clock 90s window and 10-min absolute ceiling both bound EFFECTIVE elapsed, not wall-clock elapsed.
- The 10-min `DEFAULT_MAX_TURN_DURATION_MS` ceiling is NOT relaxed; it just no longer counts human-read time toward its budget. Per the 2026-05-05 learning, a defense whose VALUE is unchanged but whose SCOPE narrows is a defense relaxation IFF the narrowed scope dissolves a side-effect role. The side-effect role of the absolute ceiling is "bound a chatty-but-stalled agent". A chatty-but-stalled agent is by definition NOT paused (it is emitting blocks) — so subtracting paused intervals does not affect that role. Documented in §Risks R4.

## Open Code-Review Overlap

3 open scope-outs touch these files:

- **#3369 — Extract `mirrorWithDebounce` to `observability.ts`:** **Fold in.** Finding 2's selected approach requires `mirrorWithDebounce` to be importable from a non-circular location. #3369 ships the extraction; this PR follows by adding a third caller in `soleur-go-runner.ts`. Plan §"Files to Edit" includes `observability.ts` + the dispatcher migration. `Closes #3369` in PR body.
- **#3344 — Widen cc-path safe-bash allowlist for KB exploration parity:** **Acknowledge.** Different concern (add new verbs: `find`, `grep`, `rg`, `wc`, `sort`, `uniq`, `head`, `tail` with path-scoped variants + re-enable `Bash` on the cc path via the new `safe-bash.ts` module). Finding 1's extraction is a clean substrate for #3344 — but the verb-set + re-enable decision is out of scope for this hardening PR. #3344 stays open.
- **#3343 — case-insensitive `</document>` escape across cc + leader prompt builders:** **Acknowledge.** Unrelated concern (case-sensitivity of the `</document>` tag-breakout defense in `buildSoleurGoSystemPrompt` / `agent-runner.ts`). Touches `soleur-go-runner.ts` but in a different code region (prompt assembly, not runner state). Stays open.
- **#3243 (decompose cc-dispatcher.ts) + #2955 (process-local state ADR) + #3345 (intent-shaped Bash UX) + #3242 (raw tool_use name field):** Not in scope; these are large refactors / ADRs / UX work, not hardening.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Four findings are all on the `apps/web-platform/server/` runner+dispatcher trust boundary. No DB schema change, no SDK contract change, no auth/payment touched. Approach selections preserve existing test surfaces (107-case safe-bash, awaiting-user invariants) and pin the new pause-interval-subtraction with new tests. Wall-clock semantics are bounded by an absolute ceiling that does NOT relax (per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`); operators get an unchanged ceiling on the chatty-stalled threat surface.

**Brainstorm-recommended specialists:** none (no brainstorm; planner direct-author per ultrathink signal).

**Skipped specialists:** none.

### Product/UX Gate

Not relevant — no user-facing surface changes. No new pages, no new components, no copy.

## Files to Edit

- **`apps/web-platform/server/permission-callback.ts`** — DELETE `SHELL_METACHAR_DENYLIST`, `PATH_TRAVERSAL_DENYLIST`, `SAFE_BASH_MAX_INPUT_LENGTH`, `PATH_TOKEN`, `ECHO_TOKEN`, `SAFE_BASH_PATTERNS`, `SAFE_BASH_VERBS`, `SAFE_BASH_NEAR_MISS_PREFIX`, `NEAR_MISS_PER_CTX_BUDGET`, `NEAR_MISS_LEADING_TOKEN_MAX`, `NearMissState`, `NEAR_MISS_STATE`, `isBashCommandSafe`, and the near-miss telemetry helpers (the contiguous ~100-line block at lines 100-275). Replace with `import { isBashCommandSafe, SAFE_BASH_PATTERNS } from "./safe-bash"`. Keep the doc comment that explains WHY the metachar denylist exists at the call site (1 sentence + reference to `safe-bash.ts`).
- **`apps/web-platform/server/observability.ts`** — ADD `mirrorWithDebounce(err, ctx, userId, errorClass)` export (per #3369). Move `MIRROR_DEBOUNCE_MS = 5 * 60 * 1000` and the `_mirrorLastReportedAt: Map<string, number>` module-local cache here. Document `feature: "*", op: "*"` audit contract.
- **`apps/web-platform/server/cc-dispatcher.ts`** — DELETE local `mirrorWithDebounce` declaration (lines 105-197) + `_mirrorLastReportedAt` + `MIRROR_DEBOUNCE_MS`. Replace with `import { mirrorWithDebounce } from "./observability"`. Verify all three existing call sites (`mirrorWithDebounce(err, { feature: ... }, args.userId, "...")` at lines 668, 1039, 1185) still compile against the imported signature.
- **`apps/web-platform/server/soleur-go-runner.ts`** —
  - In `notifyAwaitingUser` no-active-query branch (currently lines 2486-2497), replace `reportSilentFallback(new Error("..."), { ... })` with `mirrorWithDebounce(new Error("..."), { ... }, /* userId */ "unknown", NOTIFY_AWAITING_NO_ACTIVE_QUERY_ERROR_CLASS)`. **userId-availability:** `notifyAwaitingUser` receives only `conversationId`, NOT `userId`. The cc-dispatcher caller at `cc-dispatcher.ts:578-580` HAS the userId (`args.userId`) but the no-active-query branch fires precisely when no `state` exists — i.e., the runner cannot derive `userId` from `conversationId`. Pass the literal `"unknown"` for that branch. Debounce coalesces per `"unknown:notify-awaiting-no-active-query"` — a single 5-min slot — which is the intended behavior (this branch indicates a server bug; flooding Sentry doesn't help).
  - Export `NOTIFY_AWAITING_NO_ACTIVE_QUERY_ERROR_CLASS = "notify-awaiting-no-active-query"` at the top of the runner module so the test (AC12) can assert against the const, not a magic string.
  - **Doc-comment drift sweep (Finding 4 semantic change):** update the per-window-resume narrative at lines 825-836 (`notifyAwaitingUser` interface JSDoc), lines 1229-1236 (`awaitingUser` field JSDoc), and the inline comment block at line 2511-2516 to describe the new cumulative semantic ("the wall-clock and turn-hard-cap subtract `totalPausedMs + (pausedAt ? now() - pausedAt : 0)` so paused intervals do not count toward either ceiling"). Without this sweep, the next reader will see contradictory contract docs.
  - In `reapIdle` (currently lines 2426-2437), change the predicate `if (state.lastActivityAt < cutoff)` to `if (state.lastActivityAt < cutoff && !state.awaitingUser)`. Add log line `log.debug({ conversationId: state.conversationId, awaitingUser: true }, "reapIdle: skipping paused conversation")` so operators see paused-skip in logs.
  - In `ActiveQuery` interface (currently lines 1199-1266), add:
    ```ts
    /**
     * Finding 4 (#3040) — cumulative wall-clock budget across rapid status flap.
     * On `notifyAwaitingUser(true)`: stamp `pausedAt = now()`.
     * On `notifyAwaitingUser(false)`: `totalPausedMs += now() - pausedAt; pausedAt = null`.
     * Reset to `pausedAt: null, totalPausedMs: 0` on `recordAssistantBlock`
     * first-block-of-turn (new turn = new compute budget) AND in `closeQuery`
     * (defense-in-depth against stale-closure access).
     * `armRunaway` and `armTurnHardCap` subtract `totalPausedMs + (pausedAt ? now() - pausedAt : 0)`
     * from elapsed before firing, re-arming for the difference if below threshold.
     */
    pausedAt: number | null;
    totalPausedMs: number;
    ```
  - In `notifyAwaitingUser` body (currently lines 2483-2522), on transition to `true`: stamp `state.pausedAt = now()` (BEFORE `clearRunaway` and `clearTurnHardCap`). On transition to `false`: if `state.pausedAt !== null`, `state.totalPausedMs += now() - state.pausedAt; state.pausedAt = null`. **Remove** the `state.firstToolUseAt = now()` re-stamp at line 2518 — the new semantics preserve the original turn origin. Keep the `armRunaway(state)` + `armTurnHardCap(state)` calls.
  - In `armRunaway` (currently lines 1468-1506), keep the `setTimeout(..., wallClockTriggerMs)` shape unchanged at arm time. Inside the timeout callback, after the `state.closed` and `state.awaitingUser` guards, compute `const elapsedMs = (now() - (state.firstToolUseAt ?? now())) - state.totalPausedMs - (state.pausedAt ? now() - state.pausedAt : 0)`. If `elapsedMs < wallClockTriggerMs`, the timer fired too early (paused intervals accumulated since arm). Re-arm via `state.runaway = setTimeout(<same-callback>, wallClockTriggerMs - elapsedMs)` and `return`. Otherwise fire `emitWorkflowEnded` with `reason: "idle_window"` as today. Use `elapsedMs` (not wall-clock) in the log payload. **Why the re-check shape over arm-time effective anchor:** the arm-time anchor would need re-computation on every `pausedAt → null` transition (i.e., another `armRunaway` call); the fire-time recheck is symmetric and has one decision site.
  - In `armTurnHardCap` (currently lines 1417-1444), apply the same paused-interval-subtraction: at fire time inside the timeout callback, compute `const elapsedMs = (now() - turnOriginAt) - state.totalPausedMs - (state.pausedAt ? now() - state.pausedAt : 0)`; if `elapsedMs < maxTurnDurationMs`, re-arm with the difference and `return`; otherwise fire as today with `reason: "max_turn_duration"`.
  - In `recordAssistantBlock` (currently lines 1451-1466), when `isFirstBlockOfTurn`, ALSO reset `state.totalPausedMs = 0; state.pausedAt = null`. Place the reset INSIDE the `if (isFirstBlockOfTurn)` branch immediately after `state.firstToolUseAt = now()` to keep the per-turn budget contract obvious.
  - In `closeQuery` (located at line 1524, NOT 1715 as initially stated — verified via `grep -n "function closeQuery"`), explicitly reset `state.pausedAt = null; state.totalPausedMs = 0` for defense-in-depth (the entry is about to be deleted, but a future GC-late code path should not see stale paused state).
  - In `ActiveQuery` initializer at `dispatch()` (currently lines 1919-1923), initialize `pausedAt: null, totalPausedMs: 0`. Place adjacent to the existing `firstToolUseAt: null` line for visual co-location.
- **`apps/web-platform/server/kb-document-resolver.ts`** — per #3369: replace direct `reportSilentFallback` calls with `mirrorWithDebounce(err, ctx, userId, errorClass)` where the `errorClass` derives from the `extractPdfText` failure class (`empty_text`, `oversized_buffer`, etc.). userId is available from the resolver's input args.

## Files to Create

- **`apps/web-platform/server/safe-bash.ts`** — new file holding `SHELL_METACHAR_DENYLIST`, `PATH_TRAVERSAL_DENYLIST`, `SAFE_BASH_MAX_INPUT_LENGTH`, `PATH_TOKEN`, `ECHO_TOKEN`, `SAFE_BASH_PATTERNS`, `SAFE_BASH_VERBS`, `SAFE_BASH_NEAR_MISS_PREFIX`, `NEAR_MISS_PER_CTX_BUDGET`, `NEAR_MISS_LEADING_TOKEN_MAX`, `NearMissState`, `NEAR_MISS_STATE` (use a `WeakMap<object, NearMissState>` keyed via opaque-key abstraction OR re-export the WeakMap and accept that the near-miss tracker stays in `permission-callback.ts` if `CanUseToolContext` is too cyclic to move — pick whichever has zero cyclic imports), and `isBashCommandSafe(command: unknown): boolean`. Re-export type signatures.

## Files to Move

None — pure extraction; the consumer `permission-callback.ts` keeps its existing exports.

## Tests to Edit

- **`apps/web-platform/test/permission-callback-safe-bash.test.ts`** — change imports from `@/server/permission-callback` to `@/server/safe-bash`. The 107 test cases should pass byte-identical against the moved regex set. Add 1 new test: `import` from `permission-callback` ALSO works (re-export verification) so any downstream consumer (e.g., `permission-callback-bash-batch.test.ts`) does not break.
- **`apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts`** — drift-rewrite + new tests:
  - **REWRITE (Finding 4 semantic-change drift):** test at line 291 (the existing "AC9: runaway re-arms after notify(false) — only ACTIVE compute time counts (5s + 30s = 35s, paused 20s in middle)") is a load-bearing **per-window** assertion. Under the new cumulative semantic, the runaway should fire at `5s + 30s = 35s` of EFFECTIVE compute time (i.e., `5s active + 20s paused + 30s active` = 55s wall-clock fires at 30s post-resume only when `wallClockTriggerMs - 5s = 25s` post-resume — NOT 30s). Rewrite the test to: dispatch first block at t=0, advance 5s, pause, advance 20s, resume, advance 25s minus 1ms (no fire), advance 2ms (fire). The narrative shifts from "post-resume 30s window" to "cumulative active = 30s threshold". Rename the test from "AC9" to "AC9 (cumulative)" to mark the semantic change in test history.
  - **REWRITE (Finding 2):** test at line 407 ("silent-fallback: notifyAwaitingUser on unknown conversationId mirrors to Sentry via reportSilentFallback") currently asserts against `mockReportSilentFallback.mock.calls.filter(([, ctx]) => ctx?.feature === "soleur-go-runner" && ctx?.op === "notifyAwaitingUser")`. Change to mock `mirrorWithDebounce` from `@/server/observability` and assert the call shape `mirrorWithDebounce(<Error>, { feature, op }, "unknown", NOTIFY_AWAITING_NO_ACTIVE_QUERY_ERROR_CLASS)`. Verify the `mirrorWithDebounce` 5-min-TTL coalescing by calling `notifyAwaitingUser` twice for the same unknown conversationId and asserting only one mirror call.
  - **REWRITE (Finding 4 narrative):** inline comments at line 332 ("Resume — re-arms with fresh firstToolUseAt = now()") and the test-header narrative at line 46 ("re-arms with `firstToolUseAt = now()` so the elapsed counter resets") must be updated to describe the cumulative semantic.
  - **NEW AC11:** `reapIdle()` skips an `awaitingUser=true` conversation even when `lastActivityAt < cutoff`. Verify `runner.reapIdle()` returns 0, `runner.hasActiveQuery(convId)` returns true, `state.closed` is still false. After `notifyAwaitingUser(convId, false)`, advance `idleReapMs + 1ms`, and verify `runner.reapIdle()` returns 1.
  - **NEW AC12:** absolute 10-min ceiling subtracts paused intervals. Set `maxTurnDurationMs: 30_000`. Dispatch first block at t=0. Advance 5s active. Pause. Advance 20s paused. Resume. Advance 25s minus 1ms — `turnHardCap` does NOT fire (effective elapsed = 30s minus 1ms). Advance 2ms — `turnHardCap` fires with `reason: "max_turn_duration"`.
  - **NEW AC13:** multi-turn paused-budget reset. Set `wallClockTriggerMs: 30_000`. Turn 1: first block at t=0, pause 10s, resume, advance 10s, dispatch terminal result (clears `firstToolUseAt`). Turn 2: dispatch first block at t=25s wall-clock. Advance 30s minus 1ms — no fire (turn 2 has its own fresh budget; `totalPausedMs` reset to 0 by `recordAssistantBlock`). Advance 2ms — fire. Confirms the per-turn reset contract.
  - **NEW AC14:** `mirrorWithDebounce` 5-min TTL on `"unknown:notify-awaiting-no-active-query"`. Use `vi.setSystemTime(0)`, call `notifyAwaitingUser("unknown-conv", true)` 3 times within 100ms — assert `mirrorWithDebounce` called exactly once. Advance `5 * 60 * 1000 + 1ms`. Call again — assert second mirror call.
- **`apps/web-platform/test/cc-dispatcher.test.ts`** — verify the local `mirrorWithDebounce` was removed and the imported one wires through. No new tests needed beyond a compile check; the 3 existing call sites should pass byte-identical.
- **`apps/web-platform/test/permission-callback-bash-batch.test.ts`** — verify it still imports `isBashCommandSafe` from `permission-callback.ts` (via re-export) without churn.

## Tests to Create

- **`apps/web-platform/test/safe-bash.test.ts`** — optional thin smoke test (the 107-case suite already covers the regex grammar). Spec the file's public exports: `isBashCommandSafe`, `SAFE_BASH_PATTERNS`. Mark as scope-out if `permission-callback-safe-bash.test.ts` is moved over cleanly.
- **`apps/web-platform/test/observability-mirror-debounce.test.ts`** — extracted from the dispatcher test surface. Pin: (a) first call mirrors; (b) second call within 5min for same `(userId, errorClass)` no-ops; (c) call after 5min mirrors again; (d) different `errorClass` for same `userId` mirrors independently; (e) different `userId` for same `errorClass` mirrors independently.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1:** New file `apps/web-platform/server/safe-bash.ts` exports `isBashCommandSafe`, `SAFE_BASH_PATTERNS`, and the supporting regex constants. `permission-callback.ts` re-exports the same names so downstream consumers don't break. Verify via `git grep -n 'from "@/server/permission-callback"' apps/web-platform/ | grep -E 'isBashCommandSafe|SAFE_BASH_PATTERNS'` returns ≥1 hit AND `tsc --noEmit` passes.
- [ ] **AC2:** `permission-callback.ts` line count drops by ≥80 lines (the safe-bash block extraction). Verify via `wc -l apps/web-platform/server/permission-callback.ts` before/after.
- [ ] **AC3:** `mirrorWithDebounce` is exported from `apps/web-platform/server/observability.ts`. The local copy in `cc-dispatcher.ts` is deleted. All 3 existing dispatcher call sites + the new `kb-document-resolver.ts` call site + the new `soleur-go-runner.ts` call site import from `observability`. Verify via `git grep -n 'mirrorWithDebounce' apps/web-platform/server/` shows the import in each file and zero local declarations outside `observability.ts`.
- [ ] **AC4:** `soleur-go-runner.ts`'s `notifyAwaitingUser` no-active-query branch routes through `mirrorWithDebounce` with `errorClass: NOTIFY_AWAITING_NO_ACTIVE_QUERY_ERROR_CLASS` (the exported const). Pinned by REWRITE-3 (test at line 407) + NEW AC14 (TTL coalescing) in `soleur-go-runner-awaiting-user.test.ts`.
- [ ] **AC5:** `reapIdle()` skips `awaitingUser=true` entries. Pinned by NEW AC11 test.
- [ ] **AC6:** Wall-clock and turn-hard-cap timers subtract `totalPausedMs + (pausedAt ? now() - pausedAt : 0)` from elapsed before firing, **re-arming** for the difference if below threshold (fire-time recheck shape, not arm-time effective-anchor). Pinned by NEW AC12 (10-min absolute ceiling) and the REWRITE of existing AC9 (90s cumulative window). The original `firstToolUseAt` is preserved across pause/resume — verify by deleting the `state.firstToolUseAt = now()` re-stamp at the existing line 2518 AND asserting via a test seam (e.g., `runner.__getActiveQuery(convId)?.firstToolUseAt` if such a seam exists; otherwise add `firstToolUseAt` to a debug-only export).
- [ ] **AC7:** `ActiveQuery.pausedAt` and `ActiveQuery.totalPausedMs` are initialized in the `dispatch()` ActiveQuery initializer AND reset in `recordAssistantBlock` on first block of a turn AND reset in `closeQuery`. Code-grep `state.pausedAt = null` and `state.totalPausedMs = 0` to confirm all four sites. Pinned by NEW AC13 (multi-turn reset).
- [ ] **AC8 — semantic-change test sweep (per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`):** ALL tests pinning the old per-window semantic must be rewritten, not just extended. Concretely: (a) `soleur-go-runner-awaiting-user.test.ts` line 291 ("AC9: only ACTIVE compute time counts") rewritten to cumulative shape; (b) line 332 inline comment rewritten; (c) line 46 test-header narrative rewritten; (d) docstring at `soleur-go-runner.ts:825-836` (`notifyAwaitingUser` interface JSDoc) rewritten; (e) docstring at `soleur-go-runner.ts:1229-1236` (`awaitingUser` field) rewritten; (f) inline comment at `soleur-go-runner.ts:2511-2516` rewritten. Verify via `git grep -E "fresh firstToolUseAt|per-active-window|only ACTIVE compute" apps/web-platform/` returning zero hits after the rewrite.
- [ ] **AC9:** All existing tests pass: 107-case safe-bash suite, awaiting-user invariants (with REWRITES applied), cc-dispatcher tests, soleur-go-runner-lifecycle, soleur-go-runner-tool-result-idle-reset. Run `bun test apps/web-platform/test/permission-callback-safe-bash.test.ts apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts apps/web-platform/test/soleur-go-runner-lifecycle.test.ts apps/web-platform/test/soleur-go-runner-tool-result-idle-reset.test.ts apps/web-platform/test/cc-dispatcher.test.ts apps/web-platform/test/cc-dispatcher-bash-gate.test.ts apps/web-platform/test/cc-dispatcher-real-factory.test.ts apps/web-platform/test/cc-dispatcher-prefill-guard.test.ts apps/web-platform/test/cc-dispatcher-session-id-writer.test.ts apps/web-platform/test/cc-dispatcher-concierge-context.test.ts apps/web-platform/test/observability-mirror-debounce.test.ts apps/web-platform/test/permission-callback-bash-batch.test.ts` and confirm 0 failures.
- [ ] **AC10:** `bash scripts/test-all.sh` passes (parity with PR #3020 acceptance).
- [ ] **AC11:** `bun tsc --noEmit` clean against `apps/web-platform/`. **Why both `tsc` and `bun test` are required:** Finding 4 widens the `ActiveQuery` interface; any missed initializer site fails `tsc` strict-property-init OR fails an exhaustiveness test. Per `2026-05-07-tsc-not-source-grep-enumerates-exhaustiveness-rails.md`: source-grep undercounts; `tsc` is the canonical enumerator.
- [ ] **AC12:** Multi-agent review (architecture-strategist + code-simplicity-reviewer + data-integrity-guardian at minimum) on the wall-clock subtraction logic. Wall-clock arithmetic is the most subtle change — review must specifically verify: (a) AC12's 20s-paused + 25s-active-on-30s-ceiling test fires at the right boundary, (b) the re-arm-on-too-early-fire shape doesn't infinite-loop if `now() - turnOriginAt - totalPausedMs` somehow stays below threshold on a runaway-skew scenario (mitigation: re-arm always for at least 1ms minimum, log every re-arm at `log.debug`), (c) the no-pause path (when `totalPausedMs === 0 && pausedAt === null`) is byte-identical to today's behavior — pinned by the existing AC8 test at line 243 ("AC8: runaway timer is PAUSED while awaitingUser=true (no fire after 60s); resumes cleanly on result after notify(false)") which must still pass byte-identical.
- [ ] **AC13:** PR body uses `Closes #3040 #3369` and acknowledges `Refs #3344 #3343` (#3344 stays open per scope-out; #3343 stays open per scope-out). Per `wg-use-closes-n-in-pr-body-not-title-to`: `Closes` in body, not title.

### Post-merge (operator)

- [ ] **AC14:** Operator dogfood — start a Command Center conversation, issue a `pwd` Bash request, click "Approve" after a >30s read time. Verify (a) no `runner_runaway` event fires (idle reaper skipped the paused conversation), (b) Sentry shows no `notifyAwaitingUser: no active query` event (no race between reap and resume), (c) subsequent `tool_use` requests in the same turn still fire the wall-clock check correctly (paused 30s + active 90s ≈ wall-clock fires after ~120s real-time, not 90s).
- [ ] **AC15:** Sentry event-rate check 24h post-deploy on `feature: "soleur-go-runner", op: "notifyAwaitingUser"` — confirm the 5-min debounce coalescing took effect (no >1 event per `(userId, "notify-awaiting-no-active-query")` per 5-min window).

## Test Strategy

- **Framework:** Vitest (existing convention — `permission-callback-safe-bash.test.ts` uses `import { test, expect, describe } from "vitest"`). Verified via `grep -l "from \"vitest\"" apps/web-platform/test/` returning the relevant files. No new framework dependency.
- **Mock strategy:**
  - For `mirrorWithDebounce` test, use Vitest `vi.mock("./observability")` to capture call args. The existing `cc-dispatcher.test.ts` already uses this pattern — re-use.
  - For wall-clock pause-interval tests, use the existing `vi.useFakeTimers()` + `vi.advanceTimersByTime(ms)` pattern from `soleur-go-runner-awaiting-user.test.ts`. The runner's `deps.now` injection seam allows deterministic clock control.
- **Fixtures:** No new fixtures. Existing 107-case safe-bash table moves to `safe-bash.test.ts` (or stays in `permission-callback-safe-bash.test.ts` if the test file moves with the module — preferred to minimize churn).

## Risks

- **R1 — `userId` not available at `notifyAwaitingUser` no-active-query branch:** the `mirrorWithDebounce(err, ctx, userId, errorClass)` shape needs a userId. For the no-active-query branch, `state` does not exist by definition. Plan response: pass `"unknown"` for that branch. Debounce key becomes `"unknown:notify-awaiting-no-active-query"` — a single 5-min slot, which is what we want (this branch indicates a server bug; flooding Sentry doesn't help us). Document in code comment.
- **R2 — Re-arming the wall-clock against an effective-anchor is subtle:** the `setTimeout` call still fires against wall-clock time, not effective-elapsed time. Plan response: at fire time, recompute `elapsedMs = (now() - turnOriginAt) - state.totalPausedMs`. If `elapsedMs < wallClockTriggerMs`, the timer fired too early — re-arm with `setTimeout(..., wallClockTriggerMs - elapsedMs)` and return without firing the runaway. Pinned by AC10 test.
- **R3 — `closeQuery` reset of paused fields:** if `state` is GC'd-but-referenced by a stale closure (e.g., a pending `setTimeout` callback), reset prevents acting on stale state. Belt-and-suspenders; the existing `state.closed = true` guard is the primary protection.
- **R4 — Wall-clock 90s + abs 10-min ceiling on cumulative-budget semantics:** the abs ceiling now bounds cumulative agent-compute-time, not wall-clock time. A 9-min-active + 8-min-paused turn would now run 17-min wall-clock but only 9-min effective — within the 10-min budget. Per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`: this is intentional and matches the existing `awaitingUser` comment ("agent compute time only, not human read time"). The threat the abs ceiling bounds (chatty-but-stalled agent) is unaffected — a chatty-stalled agent is by definition not paused.
- **R5 — Test for paused-interval-subtraction is timing-sensitive:** real-clock tests would flake; mock-clock tests are deterministic. Plan response: use `vi.useFakeTimers()` consistently in AC10 + AC11; avoid any test that relies on real `setTimeout`.
- **R6 — #3369 extraction lands inside this PR — risk of dispatcher test regression:** the 3 dispatcher call sites of `mirrorWithDebounce` move from a local import to an external import. The existing dispatcher tests `cc-dispatcher.test.ts`, `cc-dispatcher-bash-gate.test.ts`, `cc-dispatcher-real-factory.test.ts`, `cc-dispatcher-prefill-guard.test.ts`, `cc-dispatcher-session-id-writer.test.ts`, `cc-dispatcher-concierge-context.test.ts` must all still pass. Plan response: AC8 explicitly runs all of these.
- **R7 — Module move of `NEAR_MISS_STATE: WeakMap<CanUseToolContext, ...>`:** the WeakMap is keyed by `CanUseToolContext` which is declared in `permission-callback.ts`. Moving to `safe-bash.ts` would introduce a cyclic import. Plan response: keep `NEAR_MISS_STATE` + the near-miss telemetry helper INSIDE `permission-callback.ts` since they depend on `CanUseToolContext`. Only move the purely-mechanical regex/constants/`isBashCommandSafe` to `safe-bash.ts`. AC2's 80-line target is achievable without moving the WeakMap.
- **R8 — Compound risk on combining 4 changes in one PR:** each finding is independent but all four touch `soleur-go-runner.ts`. Plan response: phase the implementation so each finding lands in its own commit with its own test; review-time it's easy to bisect a regression. Phase order: Phase 1 = Finding 1 (extract), Phase 2 = Finding 2 (mirror debounce; folds in #3369), Phase 3 = Finding 3 (reaper consults awaiting), Phase 4 = Finding 4 (paused interval subtraction). Phase order is load-bearing because Finding 4's tests rely on Finding 3's reaper skip (otherwise the test fixture conversations would be reaped mid-test).

## Sharp Edges

- The 5-min `REVIEW_GATE_TIMEOUT_MS` safety net (`review-gate.ts:19`) is the absolute upper bound on how long an `awaitingUser=true` conversation can stay paused. Verify (manual reading) that the timeout-reject path in `abortableReviewGate` eventually transitions the conversation back through the normal close flow so the new `reapIdle` skip-paused logic does not produce a permanent leak. Code reading is enough — no test needed beyond AC9.
- The `recordAssistantBlock` reset of `totalPausedMs = 0` on first block of a turn is load-bearing for the per-turn semantics. Without it, paused intervals from previous turns would leak into the current turn's wall-clock budget. Pin via a multi-turn test (AC11 extended): pause turn 1 for 5min, complete turn 1, dispatch turn 2, verify turn 2's wall-clock budget is fresh.
- Defense-relaxation invariant: this plan must NOT relax the 90s `wallClockTriggerMs` window NOR the 10-min `maxTurnDurationMs` ceiling. Verify via test that the effective-elapsed arithmetic returns the SAME fire boundary when `totalPausedMs === 0` and `pausedAt === null` — i.e., the no-pause case is byte-identical to today's behavior.
- Per `2026-05-05-trace-callgraph-from-entrypoint-when-placing-guards.md`: the `notifyAwaitingUser` callsite chain is `cc-dispatcher.ts:578-580` → `_runner.notifyAwaitingUser(convId, awaiting)`. The dispatcher's `_runner` is process-singleton (lazy `getSoleurGoRunner`). The new `state.userId` lookup is via `activeQueries.get(conversationId)` — verified that `ActiveQuery` already carries `userId` at line 1201.
- An `## User-Brand Impact` section that becomes empty after a deepen-plan rewrite will fail Phase 4.6. Fill it before requesting `/work`.
- The `mirrorWithDebounce` extraction shares a `_mirrorLastReportedAt` Map across the entire process. After extraction, that Map will see traffic from `cc-dispatcher` paths + `kb-document-resolver` paths + `soleur-go-runner.notifyAwaitingUser`. The key shape `${userId}:${errorClass}` guarantees no cross-feature collision provided each feature picks a distinct `errorClass`. Document the registry of errorClass strings in `observability.ts`'s doc comment.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Finding 1 — replace regex grammar with fixed-string `Set` (code-simplicity reviewer) | Loses pattern flexibility (`git log --oneline -5`); forces #3344 to rebuild the grammar. |
| Finding 2 — bake debounce into `reportSilentFallback` itself (Approach B) | Process-wide implicit-debounce surprise; future callers expect their mirror to fire and silently get coalesced. Better to keep `reportSilentFallback` as the "always mirror" primitive and `mirrorWithDebounce` as the opt-in coalescer. |
| Finding 3 — bump `lastActivityAt` in `notifyAwaitingUser(true)` (Approach A) | Muddles the contract of `lastActivityAt`; observability writes a misleading value. |
| Finding 4 — accept per-active-window semantics (Approach B) | Per the 2026-05-05 defense-relaxation learning, this is a defense relaxation that dissolves the "bound rapid-flap runaway" role. Cannot accept twice. |
| All four findings in separate PRs | Higher review overhead; the 4 findings share `soleur-go-runner.ts` and 2 share `notifyAwaitingUser` directly — easier to land cohesively. |
| Land just Findings 2 + 3 + 4 and defer Finding 1 (the extraction) | Extraction is the lowest-risk of the four. Splitting it out as a separate PR would just delay the substrate #3344 needs. |

## Non-Goals

- **Not** widening the safe-bash allowlist (verbs `find`, `grep`, `rg`, etc.) — tracked separately by #3344.
- **Not** decomposing `cc-dispatcher.ts` into 5 focused modules — tracked separately by #3243.
- **Not** introducing a startup-time guard for process-local state — tracked separately by #2955.
- **Not** redesigning the Bash approval modal UX — tracked separately by #3345.
- **Not** changing the SDK contract, MCP tool surface, or canUseTool boundary.
- **Not** touching the `REVIEW_GATE_TIMEOUT_MS = 5 min` safety net.
- **Not** touching `DEFAULT_IDLE_REAP_MS` (10 min), `DEFAULT_WALL_CLOCK_TRIGGER_MS` (90s), or `DEFAULT_MAX_TURN_DURATION_MS` (10 min) constants.
- **Not** changing the case-sensitivity of `</document>` escape (tracked by #3343).

## Hypotheses

This is a hardening PR with no hypotheses to validate — the four findings each have a deterministic root cause already enumerated at #3040 (the issue body documents the exact lines and behavior). The "hypothesis" surface is reserved for diagnostic plans (e.g., SSH outage, perf regression triage).

## Out of Scope

See §Non-Goals above. Plus:

- No frontend changes.
- No copy changes.
- No telemetry/observability instrumentation beyond the new `mirrorWithDebounce` callsite.
- No new feature flags.

## Open Questions

- Q1: Should the `notifyAwaitingUser` signature widen to `notifyAwaitingUser(conversationId, userId, awaiting)` or should we lookup `userId` via `activeQueries.get(conversationId)?.userId`? **Answer (planner pick):** lookup. The dispatcher caller does not have a strong reason to pass userId explicitly (it can — `args.userId` is in scope at `cc-dispatcher.ts:578`), but the lookup keeps the runner's contract narrow. Confirmed: `ActiveQuery` already has `userId` (line 1201).
- Q2: Should `errorClass: "notify-awaiting-no-active-query"` be exported as a const for cross-test consistency? **Answer (planner pick):** yes — `export const NOTIFY_AWAITING_NO_ACTIVE_QUERY_ERROR_CLASS = "notify-awaiting-no-active-query"` in `soleur-go-runner.ts` so the test asserts against the constant.

## Implementation Phases

### Phase 1 — Extract `safe-bash.ts` (Finding 1)

1. Create `apps/web-platform/server/safe-bash.ts` with the regex constants + `isBashCommandSafe` function. Keep `NEAR_MISS_STATE: WeakMap<CanUseToolContext, ...>` in `permission-callback.ts` (cyclic import avoidance).
2. Update `permission-callback.ts` to import from `./safe-bash` and re-export the public symbols.
3. Move `apps/web-platform/test/permission-callback-safe-bash.test.ts`'s imports to `@/server/safe-bash`. Keep the 107 cases as-is.
4. Run `bun test apps/web-platform/test/permission-callback-safe-bash.test.ts apps/web-platform/test/permission-callback-bash-batch.test.ts` to confirm zero regression.
5. Commit: `refactor(safe-bash): extract regex allowlist module from permission-callback`.

### Phase 2 — `mirrorWithDebounce` extraction + new caller (Findings 2 + #3369)

1. Add `mirrorWithDebounce` export to `apps/web-platform/server/observability.ts` along with `MIRROR_DEBOUNCE_MS` and `_mirrorLastReportedAt`.
2. Delete the local `mirrorWithDebounce` from `cc-dispatcher.ts`. Add `import { mirrorWithDebounce } from "./observability"`. Verify the 3 dispatcher call sites compile.
3. Migrate `kb-document-resolver.ts` to use `mirrorWithDebounce` with `errorClass` derived from the `extractPdfText` failure class (per #3369). Add `userId` plumbing if not already present.
4. Create `apps/web-platform/test/observability-mirror-debounce.test.ts` with the 5 cases listed under "Tests to Create".
5. Run `bun test apps/web-platform/test/cc-dispatcher.test.ts apps/web-platform/test/observability-mirror-debounce.test.ts`.
6. Commit: `refactor(observability): extract mirrorWithDebounce for cross-module debounced Sentry mirror (Closes #3369)`.

### Phase 3 — `reapIdle` consults `awaitingUser` + `notifyAwaitingUser` debounce (Finding 3 + Finding 2 runner integration)

1. Add the `!state.awaitingUser` predicate in `reapIdle` at `soleur-go-runner.ts:2426-2437`.
2. Add `log.debug` for the paused-skip case.
3. Route `notifyAwaitingUser` no-active-query branch through `mirrorWithDebounce(err, ctx, "unknown", NOTIFY_AWAITING_NO_ACTIVE_QUERY_ERROR_CLASS)`. Import `mirrorWithDebounce` from `./observability` (Phase 2 must have landed for this import to resolve).
4. Export `const NOTIFY_AWAITING_NO_ACTIVE_QUERY_ERROR_CLASS = "notify-awaiting-no-active-query"` at top of `soleur-go-runner.ts`.
5. **Rewrite existing test at `soleur-go-runner-awaiting-user.test.ts:407`** ("silent-fallback: notifyAwaitingUser on unknown conversationId mirrors via reportSilentFallback") — change to mock `mirrorWithDebounce` and assert the new call shape including `errorClass: NOTIFY_AWAITING_NO_ACTIVE_QUERY_ERROR_CLASS` and `userId: "unknown"`.
6. Add NEW AC11 (reaper-skip-paused) test.
7. Run `bun test apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts apps/web-platform/test/soleur-go-runner-lifecycle.test.ts`.
8. Commit: `fix(cc): idle-reaper skips paused conversations + notify-awaiting silent fallback debounced (#3040)`.

### Phase 4 — Paused-interval subtraction (Finding 4)

1. Add `pausedAt` and `totalPausedMs` to `ActiveQuery` interface with the JSDoc shown in §"Files to Edit".
2. Update `notifyAwaitingUser` to stamp `pausedAt` on true / accumulate `totalPausedMs` on false. **Remove** the `state.firstToolUseAt = now()` re-stamp at line 2518.
3. Update `armRunaway` + `armTurnHardCap` fire-time callbacks to compute `elapsedMs = (now() - turnOriginAt) - state.totalPausedMs - (state.pausedAt ? now() - state.pausedAt : 0)` and re-arm via `setTimeout(<callback>, Math.max(1, threshold - elapsedMs))` if `elapsedMs < threshold`. Log every re-arm at `log.debug` for observability.
4. Update `recordAssistantBlock` (inside `if (isFirstBlockOfTurn)`) to reset `totalPausedMs = 0; pausedAt = null`.
5. Update `closeQuery` + `dispatch()` initializer to set/reset the new fields.
6. **Drift sweep (the semantic-change tax):**
   - Rewrite test at `soleur-go-runner-awaiting-user.test.ts:291` ("AC9: only ACTIVE compute time counts") to the cumulative shape per Tests-to-Edit REWRITE.
   - Rewrite inline comment at `soleur-go-runner-awaiting-user.test.ts:332`.
   - Rewrite test-header narrative at `soleur-go-runner-awaiting-user.test.ts:46`.
   - Rewrite docstring at `soleur-go-runner.ts:825-836` (`notifyAwaitingUser` interface JSDoc).
   - Rewrite docstring at `soleur-go-runner.ts:1229-1236` (`awaitingUser` field).
   - Rewrite inline comment at `soleur-go-runner.ts:2511-2516`.
   - Verify via `git grep -E "fresh firstToolUseAt|per-active-window|only ACTIVE compute" apps/web-platform/` returns zero hits.
7. Add NEW AC11 (reaper skip), NEW AC12 (10-min ceiling cumulative), NEW AC13 (multi-turn reset), NEW AC14 (mirror debounce TTL).
8. Run `bun test apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts apps/web-platform/test/soleur-go-runner-lifecycle.test.ts apps/web-platform/test/soleur-go-runner-tool-result-idle-reset.test.ts`.
9. Commit: `fix(cc): wall-clock subtracts paused intervals across rapid status flap + drift-sweep per-window→cumulative narrative (#3040)`.

### Phase 5 — Full test sweep + multi-agent review

1. `bash scripts/test-all.sh` (24/24 suites passing parity).
2. `bun tsc --noEmit` clean.
3. Push branch, open PR with `Closes #3040 #3369` + acknowledgments.
4. Multi-agent review: architecture-strategist + code-simplicity-reviewer + data-integrity-guardian on the paused-interval arithmetic.
5. Address review findings inline (per `rf-review-finding-default-fix-inline`).

### Phase 6 — Operator dogfood post-merge (AC13 + AC14)

1. Deploy to prd.
2. Exercise the Command Center per AC13.
3. 24h Sentry event-rate check per AC14.
4. Close #3040 + #3369 with verification notes; leave #3344 + #3343 open as scope-outs.

## Telemetry

- New errorClass: `notify-awaiting-no-active-query` (debounced via the existing `mirrorWithDebounce` 5-min TTL).
- New log line: `reapIdle: skipping paused conversation` at `log.debug` — operators can grep for this when investigating "why was conversation X not reaped at the 10-min cutoff".
- No new Sentry tags, no new structured-log fields.

## Versioning

No version bump. This PR is internal hardening; no plugin component count change, no skill description change.

## Research Insights

### Live-verified facts (deepen pass, 2026-05-11)

```bash
# PR/issue state
$ gh pr view 3020 --json state,title
# → MERGED — "fix(command-center): permissions UX + runaway pause + rename to Soleur Concierge"
$ gh pr view 3225 --json state,title,mergedAt
# → MERGED 2026-05-05 — "fix(kb-concierge): raise idle window to 90s with per-block reset + max-turn ceiling"
$ gh issue view 3369 --json state,title  # → OPEN — Extract mirrorWithDebounce
$ gh issue view 3344 --json state,title  # → OPEN — Widen cc-path safe-bash allowlist
$ gh issue view 3343 --json state,title  # → OPEN — case-insensitive </document> escape

# AGENTS.md rule IDs cited in this plan
$ for id in hr-weigh-every-decision-against-target-user-impact rf-review-finding-default-fix-inline cq-silent-fallback-must-mirror-to-sentry; do
    grep -q "\[id: $id\]" AGENTS.md && echo "ACTIVE: $id"
  done
# → ACTIVE: all three
```

### Existing wall-clock defaults (verified)

```ts
// apps/web-platform/server/soleur-go-runner.ts:454-464
export const DEFAULT_IDLE_REAP_MS = 10 * 60 * 1000;      // 10 min
export const DEFAULT_WALL_CLOCK_TRIGGER_MS = 90 * 1000;   // 90s (raised from 30s in PR #3225)
export const DEFAULT_MAX_TURN_DURATION_MS = 10 * 60 * 1000; // 10 min (added in PR #3225)
```

### Existing `mirrorWithDebounce` shape (verified, `cc-dispatcher.ts:116-197`)

```ts
const MIRROR_DEBOUNCE_MS = 5 * 60 * 1000;
const _mirrorLastReportedAt = new Map<string, number>();

function mirrorWithDebounce(
  err: unknown,
  ctx: Parameters<typeof reportSilentFallback>[1],
  userId: string,
  errorClass: string,
): void {
  const key = `${userId}:${errorClass}`;
  const now = Date.now();
  const last = _mirrorLastReportedAt.get(key);
  if (last !== undefined && now - last < MIRROR_DEBOUNCE_MS) return;
  _mirrorLastReportedAt.set(key, now);
  reportSilentFallback(err, ctx);
}
```

The migration to `observability.ts` is verbatim — no signature change. Three existing call sites in `cc-dispatcher.ts` (lines 668, 1039, 1185); one new site each in `kb-document-resolver.ts` (#3369) and `soleur-go-runner.ts` (this PR, Finding 2).

### Vitest fake-timers pattern (verified, existing project convention)

```ts
// apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts:234-241
beforeEach(() => {
  vi.useFakeTimers();
  mockReportSilentFallback.mockClear();
});

afterEach(() => {
  vi.useRealTimers();
});

// Per-test pattern (line 246):
vi.setSystemTime(0);
// ... dispatch + emit ...
vi.advanceTimersByTime(60_000);
await flushMicrotasks();
```

### `vi.mock("@/server/observability")` shape (3+ existing test files)

```ts
// e.g., apps/web-platform/test/cc-concierge-pdf-summarize-e2e.test.ts:50
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  // After this PR's Phase 2:
  mirrorWithDebounce: mockMirrorWithDebounce,
}));
```

### Sibling extraction precedent (Finding 1)

```bash
$ head -5 apps/web-platform/server/tool-tiers.ts
# Tool tier classification for platform MCP tools (#1926).
# Extracted from agent-runner.ts for unit testability (following the
# tool-path-checker.ts and review-gate.ts extraction pattern).

$ head -10 apps/web-platform/server/tool-path-checker.ts
# Tool classification and path extraction for canUseTool workspace sandbox.
# Extracted from agent-runner.ts for unit testability without SDK/Supabase
# dependencies. Follows the same extraction pattern as sandbox.ts and
# error-sanitizer.ts.
```

The `safe-bash.ts` extraction follows the same convention — doc comment naming the predecessor module.

### Defense-relaxation cross-check (per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`)

Finding 4 changes the wall-clock semantic from per-window to cumulative. Per the 2026-05-05 learning:

> When a plan relaxes or removes a load-bearing defense, plan/deepen-plan must enumerate "what was the previous defense protecting against, and what's the new ceiling for the same threat?"

The previous (per-window) semantic bounded a separate threat: "a single active window never exceeds 90s of agent compute". The cumulative semantic preserves that ceiling (it's still 90s per active window — the window just spans pauses). The new threat surface is "cumulative active time across a turn exceeds the absolute 10-min ceiling" — bounded by `DEFAULT_MAX_TURN_DURATION_MS` which is also cumulative under this change. No defense is dropped; both ceilings are preserved with semantics that match the user-facing comment "agent compute time only, not human read time".

## References

- Issue: #3040
- Closed by this PR: #3369
- Acknowledged (stay open): #3344, #3343
- Predecessor PR: #3020 (the source of all four findings)
- Related learnings:
  - `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md` — Finding 4's defense-relaxation analysis.
  - `knowledge-base/project/learnings/best-practices/2026-05-05-trace-callgraph-from-entrypoint-when-placing-guards.md` — verifying the `notifyAwaitingUser` callsite chain.
  - `knowledge-base/project/learnings/best-practices/2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md` — co-locate security allowlists with their tests (Finding 1).
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-022-sdk-as-router.md` (2026-04-29 follow-up records V2 list including this hardening bundle).
