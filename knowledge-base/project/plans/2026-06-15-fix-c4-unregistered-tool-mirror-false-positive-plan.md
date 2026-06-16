---
title: "fix: edit_c4_diagram spurious unregistered-tool Sentry mirror"
issue: 5388
branch: feat-one-shot-5388
type: bug
lane: single-domain
brand_survival_threshold: none
created: 2026-06-15
---

# 🐛 fix: `edit_c4_diagram` fires a spurious "unregistered-tool-invoked" Sentry/pino mirror on every legitimate c4 edit

Closes #5388.

## Enhancement Summary

**Deepened on:** 2026-06-15
**Mandatory gates:** 4.6 User-Brand Impact ✅ (threshold `none` + sensitive-path scope-out bullet present — `apps/web-platform/server/` matches the canonical sensitive regex), 4.7 Observability ✅ (5 fields, no ssh in discoverability_test), 4.8 PAT-shaped vars ✅ none, 4.9 UI-wireframe ✅ N/A (no UI surface).

### Verification pass (Phase 4.45 verify-the-negative + Phase 4.4 precedent-diff)

A sonnet verification agent checked all 10 load-bearing code claims + the learning citation against `cc-dispatcher.ts` / `soleur-go-runner.ts` on this branch. **All CONFIRM; zero contradictions.** Key confirmations:

- `CC_REGISTERED_PLATFORM_TOOL_NAMES` = `[NARRATE_TOOL_FQN, SUMMARIZE_TOOL_FQN]` at `cc-dispatcher.ts:270-273`; consumed at `:2852`.
- c4 registration gate is **two-step**: `effectiveInstallationId !== null && owner && repo` (`:1724`) THEN `c4Enabled` (`:1748`) → `c4ToolName` set `:1756`. The plan's "resolve the FULL precondition set (installation + owner/repo + flag)" guidance already reflects this — do not collapse to a flag-only check.
- `c4ToolName` already threaded into `canUseTool` as `platformToolNames` at `:2064` (existing cross-boundary precedent for the c4 value).
- **Warm-query factory non-invocation CONFIRMED**: `deps.queryFactory` runs only inside `if (!state)` (`soleur-go-runner.ts:2484-2539`); no other call site. This is the load-bearing fact behind rejecting the issue's factory-publish suggestion.

### Phase 4.4 precedent-diff (per-dispatch re-resolution is the canonical form in THIS file)

The chosen mechanism is NOT novel — it is the established pattern in the same function:

| Cell | Resolver | Cold path | Warm path | "COLD conversation" comment |
|---|---|---|---|---|
| `bashAutonomousPosture` | `resolveBashAutonomous(userId)` | factory publishes via `setBashAutonomous` | per-dispatch `void resolveBashAutonomous` (`:2615`) | `:2603-2614` verbatim |
| `reprovisionOutcome` | `reprovisionWorkspaceOnDispatch(userId)` | factory self-heal | per-dispatch `void reprovision…` (`:2643`) | `:2627-2642` verbatim |
| `registeredPlatformToolNames` (this plan) | shared `resolveC4Eligible`/`resolveRegisteredPlatformToolNames(userId)` | factory reuses helper to build tool | per-dispatch resolve appends c4 FQN | to be added (mirror the above) |

The factory-publish-only pattern (`setDelegationContext`) is cold-only and was correctly rejected. No precedent for a factory-publish-only registered-tool cell exists; the per-dispatch resolve has two in-file precedents.

### Key improvements over the v1 plan
1. Confirmed (not assumed) the warm-query factory-non-invocation that makes the issue's suggested mechanism insufficient.
2. Confirmed the two-step c4 gate so the implementer resolves installation+owner+repo+flag, not flag-only (the AC2 false-suppression regression guard).
3. Tabulated the two in-file precedents for the chosen per-dispatch pattern so /work has copy-from references.

## Overview

The cc-router's SDK iterator hook (`onToolUse` inside `dispatchSoleurGo`, `apps/web-platform/server/cc-dispatcher.ts:2852`) mirrors a `feature: "cc-mcp-tier", op: "unregistered-tool-invoked"` Sentry event (debounced per-`(userId, errorClass)` at a 5-min TTL) plus a pino line whenever a `mcp__soleur_platform__*` tool name is not in the module constant `CC_REGISTERED_PLATFORM_TOOL_NAMES` (`cc-dispatcher.ts:270`).

That constant currently lists only `NARRATE_TOOL_FQN` and `SUMMARIZE_TOOL_FQN` (the always-registered narration tools, added in #5370). The flag+repo-gated `edit_c4_diagram` tool — registered into the *same* `soleur_platform` MCP server when the `c4-visualizer` flag resolves true for the dispatch user (`cc-dispatcher.ts:1748-1776`) — is **not** in that list. So every genuine c4 diagram edit by an eligible user emits a false "unregistered tool" mirror.

**Pre-existing, not a #5370 regression.** On `main` before #5370, `CC_REGISTERED_PLATFORM_TOOL_NAMES = []` while `edit_c4_diagram` was already registered, so c4 already false-positived. #5370 fixed narrate/summarize and left c4. This is a latent pre-existing bug surfaced by review of PR #5363.

### Why it cannot be fixed by editing the module constant

`CC_REGISTERED_PLATFORM_TOOL_NAMES` is a module-level constant; the `onToolUse` predicate reads it at `:2852`. But whether `edit_c4_diagram` was actually registered **this dispatch** is per-dispatch state: it depends on the `c4-visualizer` flag resolved against the dispatch user's real role, AND on the user having a connected repo with a resolvable installation id. That state (`c4ToolName`) is computed inside `realSdkQueryFactory` (`cc-dispatcher.ts:1707-1756`), a **different function** from the `dispatchSoleurGo` `events`/`onToolUse` closure.

- **Unconditionally adding the c4 FQN to the module constant is wrong** — it would suppress a *genuine* unregistered-call mirror when the c4 flag is OFF (the exact silent-failure surface #2909 FR2 was built to catch).
- The predicate must therefore be fed a **per-dispatch** registered-tool list that includes the c4 FQN only when c4 was actually registered for this dispatch.

### Research Reconciliation — Spec vs. Codebase

| Issue-body claim | Codebase reality (verified) | Plan response |
|---|---|---|
| `CC_REGISTERED_PLATFORM_TOOL_NAMES` is a module constant read by `onToolUse` | True — defined `cc-dispatcher.ts:270`, consumed `:2852` via `shouldMirrorUnregisteredPlatformToolUse` | Replace the constant arg at `:2852` with a per-dispatch value |
| `c4ToolName` is computed in `realSdkQueryFactory`, a separate function | True — `cc-dispatcher.ts:1707`, set `:1756`; already threaded into `canUseTool` as `platformToolNames` at `:2064` | Reuse the same flag-resolution; publish/derive the registered set per dispatch |
| Suggested fix: thread `registeredPlatformToolNames` from factory through `runner.dispatch` into the `events` closure | The factory is invoked **only on COLD conversations** (`soleur-go-runner.ts:2486` `if (!state)`); a factory-published cell stays fail-closed on **warm-query reuse** | **Diverge from the suggested mechanism.** Use the per-dispatch re-resolution pattern already used for `bashAutonomousPosture`/`reprovisionOutcome` (correct on cold AND warm) instead of the factory-publish-only pattern used for `setDelegationContext` (cold-only). See Sharp Edge. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-visible — this is a server-side observability false-positive. A still-broken fix means the operator's Sentry `cc-mcp-tier:unregistered-tool` signal stays noisy and the genuine-unregistered-call alert keeps getting buried under c4 false positives (alert-fatigue / dark-monitor risk), but no end-user surface changes.

**If this leaks, the user's data / workflow / money is exposed via:** no new data path. The mirror payload already redacts the tool name via `sanitizeToolNameForLog` and carries only `userId`/`conversationId`/`leaderId` already present in the existing mirror. No new field is added.

**Brand-survival threshold:** none.

> `threshold: none, reason: server-side observability false-positive with no user-facing surface and no new data-movement; the only failure mode is operator alert-noise, not a user incident.`

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — c4 registered ⇒ no mirror.** A `mcp__soleur_platform__edit_c4_diagram` `tool_use` does NOT trigger `shouldMirrorUnregisteredPlatformToolUse(...) === true` when the per-dispatch registered set includes the c4 FQN. Verified by a vitest case in `apps/web-platform/test/cc-mcp-tier-allowlist.test.ts`: `shouldMirrorUnregisteredPlatformToolUse("mcp__soleur_platform__edit_c4_diagram", [NARRATE_TOOL_FQN, SUMMARIZE_TOOL_FQN, "mcp__soleur_platform__edit_c4_diagram"])` returns `false`.
- [x] **AC2 — c4 NOT registered ⇒ mirror still fires.** `shouldMirrorUnregisteredPlatformToolUse("mcp__soleur_platform__edit_c4_diagram", [NARRATE_TOOL_FQN, SUMMARIZE_TOOL_FQN])` returns `true` (genuine-unregistered-call mirror preserved when the flag is off). This is the regression-guard against the wrong "just add it to the constant" fix.
- [x] **AC3 — narrate/summarize unaffected.** Existing assertions in `cc-mcp-tier-allowlist.test.ts` for narrate/summarize still pass (no behavioral change to the always-registered tools).
- [x] **AC4 — warm-query correctness.** The registered-set used at the `:2852` call site is derived from per-dispatch state available on BOTH cold and warm dispatches (NOT exclusively from a factory-published cell). Verified by code inspection + a test/assertion that the c4 flag resolution feeding the registered set lives in (or is re-invoked from) the `dispatchSoleurGo` per-dispatch scope, mirroring `resolveBashAutonomous`. Document the cold/warm reachability in a code comment at the resolution site.
- [x] **AC5 — fail-closed.** If the per-dispatch c4 eligibility resolution throws, the registered set falls back to `[NARRATE_TOOL_FQN, SUMMARIZE_TOOL_FQN]` (c4 excluded) AND the error is mirrored via `reportSilentFallback` per `cq-silent-fallback-must-mirror-to-sentry`. Fail-closed means a c4 edit during a resolution failure produces a (benign) false-positive rather than silently suppressing a genuine unregistered call — never the reverse.
- [x] **AC6 — typecheck clean.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [x] **AC7 — targeted test green.** `cd apps/web-platform && ./node_modules/.bin/vitest run test/cc-mcp-tier-allowlist.test.ts` passes.
- [x] **AC8 — no new direct callers of the module constant.** `git grep -n "CC_REGISTERED_PLATFORM_TOOL_NAMES" apps/web-platform/server/cc-dispatcher.ts` shows the constant is either (a) retained only as the base list the per-dispatch set is built from, or (b) removed if fully superseded — no orphaned `:2852`-style direct read remains.

## Implementation Phases

> TDD: write the failing test first (`cq-write-failing-tests-before`). The predicate `shouldMirrorUnregisteredPlatformToolUse` is already pure and exported, so AC1/AC2/AC3 are cheap unit tests with no SDK in the loop.

### Phase 1 — RED: failing predicate tests
- **File:** `apps/web-platform/test/cc-mcp-tier-allowlist.test.ts`
- Add a `describe("edit_c4_diagram registration (#5388)")` block with the AC1 (registered ⇒ `false`) and AC2 (unregistered ⇒ `true`) cases, plus an assertion that the c4 FQN literal equals `mcp__soleur_platform__${EDIT_C4_DIAGRAM_TOOL}` (import `EDIT_C4_DIAGRAM_TOOL` from `../server/c4-concierge-tools` to avoid a hardcoded-string drift).
- AC1 fails today because nothing builds a per-dispatch list containing the c4 FQN; the predicate itself is already correct, so the RED here is really about the *call-site* wiring proven indirectly — keep these as the predicate-contract tests and add the call-site assertion in Phase 3.

### Phase 2 — GREEN: per-dispatch registered-tool set
Choose the **per-dispatch re-resolution** mechanism (see Sharp Edge for why the factory-publish mechanism the issue suggests is insufficient).

- **File:** `apps/web-platform/server/cc-dispatcher.ts`
- In the `dispatchSoleurGo` per-dispatch scope (near the `resolveBashAutonomous` / `reprovisionWorkspaceOnDispatch` fire-and-forget resolves at `:2615`/`:2643`), add a `registeredPlatformToolNames` closure cell initialized to the always-registered base `[NARRATE_TOOL_FQN, SUMMARIZE_TOOL_FQN]`, and a per-dispatch resolve that appends the c4 FQN when c4 is eligible for this user/dispatch.
- **Extract the c4-eligibility resolution** currently inlined in `realSdkQueryFactory` (`:1724-1748`: `effectiveInstallationId !== null && owner && repo`, then `getFreshTenantClient` → role → `getRuntimeFlag(C4_VISUALIZER_FLAG, …)`) into a small shared helper (e.g. `resolveC4Eligible(userId): Promise<boolean>` or `resolveRegisteredPlatformToolNames(userId)`) so the factory and the per-dispatch resolve share ONE source of truth and cannot drift. The factory keeps using it to decide whether to build the tool; the dispatcher uses it to decide whether to advertise the FQN to the predicate.
  - **Note on owner/repo/installation:** the factory's c4 gate also requires a connected repo + resolvable installation id. The shared helper must resolve the same preconditions (or the dispatcher resolve must, at minimum, not advertise the c4 FQN more permissively than the factory registers it — over-advertising would re-introduce the false-suppression bug AC2 guards against). Resolve the full precondition set (installation + owner/repo + flag), not just the flag.
- Fail-closed: wrap in try/catch → leave the c4 FQN out + `reportSilentFallback({ feature: "cc-dispatcher", op: "c4-registered-resolve", extra: { userId, conversationId } })` (AC5).

### Phase 3 — GREEN: swap the predicate arg at the call site
- **File:** `apps/web-platform/server/cc-dispatcher.ts:2852`
- Replace `shouldMirrorUnregisteredPlatformToolUse(block.name, CC_REGISTERED_PLATFORM_TOOL_NAMES)` with the per-dispatch `registeredPlatformToolNames` cell.
- Keep `CC_REGISTERED_PLATFORM_TOOL_NAMES` as the base list the cell is seeded from (its doc-comment about preventing drift between allowlist source and predicate is still accurate); update the comment to note c4 is appended per-dispatch.
- Add a code comment at the resolve site documenting cold+warm reachability (mirroring the `:2603` `setBashAutonomous` warm-query note).

### Phase 4 — Verify
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (AC6).
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/cc-mcp-tier-allowlist.test.ts` (AC7).
- `git grep -n "CC_REGISTERED_PLATFORM_TOOL_NAMES" apps/web-platform/server/cc-dispatcher.ts` (AC8).

## Files to Edit

- `apps/web-platform/server/cc-dispatcher.ts` — extract shared c4-eligibility helper; add per-dispatch `registeredPlatformToolNames` cell + fail-closed resolve in the `dispatchSoleurGo` scope; swap the `:2852` predicate arg; update the constant's doc-comment.
- `apps/web-platform/test/cc-mcp-tier-allowlist.test.ts` — add `#5388` describe block (AC1/AC2/AC3, FQN-literal assertion).

## Files to Create

- None.

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200` then `jq` `contains("apps/web-platform/server/cc-dispatcher.ts")` and `contains("apps/web-platform/test/cc-mcp-tier-allowlist.test.ts")`. **None** — no open code-review scope-out names either file.

## Observability

```yaml
liveness_signal:
  what: Sentry event `feature: cc-mcp-tier, op: unregistered-tool-invoked` (debounced 5-min per userId+errorClass)
  cadence: on every genuine unregistered mcp__soleur_platform__* tool_use (post-fix: c4 edits no longer counted)
  alert_target: existing Sentry cc-mcp-tier alert (operator)
  configured_in: apps/web-platform/server/cc-dispatcher.ts onToolUse (mirrorWithDebounce) — no new monitor added
error_reporting:
  destination: Sentry via reportSilentFallback (new op "c4-registered-resolve") + mirrorWithDebounce (existing op "unregistered-tool-invoked")
  fail_loud: yes — resolution failure mirrors to Sentry and fails closed (c4 excluded → benign false-positive, never false-suppression)
failure_modes:
  - mode: c4-eligibility resolution throws (Supabase/flag RTT failure)
    detection: reportSilentFallback Sentry event op=c4-registered-resolve
    alert_route: existing cc-dispatcher silent-fallback Sentry alert
  - mode: dispatcher advertises c4 FQN more permissively than factory registers it
    detection: AC2 unit test (unregistered ⇒ mirror) + code-review of precondition parity
    alert_route: pre-merge CI (vitest); post-merge would re-surface as suppressed genuine-unregistered mirror (silent) — mitigated by sharing one resolver helper
logs:
  where: pino structured log line at the unregistered-tool mirror site (existing); reportSilentFallback pino+Sentry
  retention: Better Stack / Sentry default
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/cc-mcp-tier-allowlist.test.ts"
  expected_output: "all cc-mcp-tier tests pass incl. #5388 c4 registered/unregistered cases (no ssh)"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — server-side observability bug fix, no UI surface (no file under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`), no user-facing copy, no schema/migration/auth/API-route change, no new infrastructure or secret. Engineering-only.

## Infrastructure (IaC)

Skipped — no new infrastructure. Pure code change against already-provisioned surfaces (`apps/web-platform/server/`, `apps/web-platform/test/`). No server, service, cron, secret, vendor account, DNS, or firewall change.

## Sharp Edges

- **The issue's suggested mechanism (thread the registered set from the factory through `runner.dispatch` into the `events` closure) is cold-only and therefore insufficient.** `realSdkQueryFactory` is invoked **only when `!state`** — i.e. on a COLD conversation (`soleur-go-runner.ts:2486`, `queryReused = false`). On warm-query reuse the factory is not re-invoked, so a factory-published cell (the `setDelegationContext`/`setBashAutonomous` factory-write pattern) would stay at its fail-closed initial value and a c4 edit on a warm conversation would AGAIN false-positive. The correct precedent is the **per-dispatch re-resolution** pattern this same file already uses for `bashAutonomousPosture` (`:2603-2625`, with an explicit "factory runs ONLY on a COLD conversation … re-resolve per-dispatch here" note) and `reprovisionOutcome` (`:2627-2646`). The plan deliberately diverges from the issue's suggestion for this reason. `setBashAutonomous` is published from BOTH the factory (cold) and the per-dispatch resolve (warm) for idempotency; the c4 resolve should do the same OR be the single per-dispatch source.
- **Precondition parity is load-bearing.** The factory registers the c4 tool only when `effectiveInstallationId !== null && owner && repo && c4Enabled` (`:1724-1748`). If the dispatcher's "should I advertise the c4 FQN to the predicate" resolve checks only the flag (`c4Enabled`) and skips the installation/owner/repo preconditions, it will advertise the FQN in cases where the factory did NOT register the tool — re-introducing the AC2 false-suppression bug for those cases. Resolve the FULL precondition set, or share ONE helper between factory and dispatcher (preferred — eliminates drift by construction). This is a guard-placement / trace-the-value concern per `2026-05-05-trace-callgraph-from-entrypoint-when-placing-guards.md`: trace what makes `c4ToolName` truthy, not just the flag.
- **`onToolUse` may fire before the per-dispatch c4 resolve completes.** The narration/`reprovision` resolves are fire-and-forget; `onToolUse` for the FIRST tool block could in principle race the resolve. In practice the SDK must construct the Query and emit text/tool blocks before any `tool_use` surfaces (the existing `workspacePath`/`bashAutonomous` resolves rely on this same ordering, documented at `:2546-2551`). Confirm the c4 resolve completes before a c4 `tool_use` can land — c4 edits are never the very first block (the model emits the addendum-driven call mid-turn) — and if any residual race exists, fail-closed (cell still seeded with narrate/summarize) yields a benign false-positive, never a false-suppression. Document this ordering assumption in the resolve-site comment.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is complete with `threshold: none` + reason.)

## Alternative Approaches Considered

| Approach | Verdict | Rationale |
|---|---|---|
| Add `edit_c4_diagram` FQN unconditionally to `CC_REGISTERED_PLATFORM_TOOL_NAMES` | Rejected | Suppresses the genuine-unregistered mirror when the c4 flag is OFF — defeats #2909 FR2 (the AC2 regression guard exists specifically to block this). |
| Thread registered set from factory → `runner.dispatch` → `events` closure (issue's suggestion) | Rejected as primary | Cold-only: factory not re-invoked on warm-query reuse, so warm c4 edits still false-positive. |
| Per-dispatch re-resolution in `dispatchSoleurGo` scope, sharing one c4-eligibility helper with the factory | **Chosen** | Correct on cold AND warm; mirrors the existing `bashAutonomous`/`reprovision` warm-query fix; single source of truth prevents factory↔dispatcher drift. |

## Test Scenarios

1. c4 registered (flag on, repo connected) → c4 `tool_use` → predicate returns `false` → no mirror (AC1).
2. c4 NOT registered (flag off) → c4 `tool_use` → predicate returns `true` → genuine mirror fires (AC2).
3. narrate/summarize `tool_use` → predicate returns `false` (unchanged) (AC3).
4. c4-eligibility resolve throws → cell stays `[narrate, summarize]`, `reportSilentFallback` fires, c4 edit yields benign false-positive (AC5).
5. Unknown `mcp__soleur_platform__bogus` → predicate returns `true` (genuine mirror preserved).
