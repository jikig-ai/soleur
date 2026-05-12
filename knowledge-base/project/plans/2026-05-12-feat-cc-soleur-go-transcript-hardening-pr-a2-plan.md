---
date: 2026-05-12
revision: rev-2 (applied 3-reviewer plan-review + GDPR plan-time audit findings)
issue: "#3603"
predecessor_pr: "#3602 (PR-A1, merged 2026-05-12 07:03 UTC — W2 + W8 shipped)"
branch: feat-cc-soleur-go-transcript-hardening-pr-a2-3603
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
gdpr_gate: required (plan 2.7, work 2 exit, ship 5.5)
type: feat
scope: PR-A2 of the 4-PR sequence under #3603 (W1 cross-tenant matrix + W4-usage feature-flagged + FR6 hydration regression)
supersedes_plan: knowledge-base/project/plans/2026-05-11-feat-cc-soleur-go-transcript-hardening-pra-plan.md (rev-3) for the deferred portion
plan_review_synthesis: legal-compliance-auditor + code-simplicity-reviewer + architecture-strategist (2026-05-12)
---

# Plan: cc-soleur-go transcript hardening — PR-A2 (W1 cross-tenant + W4 usage flagged) — rev-2

## Summary

Closes the engineering hardening pass under #3603 by landing the two workstreams PR-A1 deferred:

| Workstream | Surface | Owner | Risk class |
|---|---|---|---|
| **W1** | Write-boundary tenant-isolation guard + 2×2 real-Supabase matrix test (RLS-enforced auth-client SELECT, 6 invariants post-rev-2 trim, cascade-erasure FK, deterministic hydration empty-DB invariant) | cc-dispatcher write boundary | GDPR Art. 33/34 — single-user breach |
| **W4** | `messages.usage` jsonb parity on cc path, **cc-narrowed shape** (`cost_usd` only on `status: "complete"`), feature-flagged behind `CC_PERSIST_USAGE` (default `false` until PR-C Privacy Policy refresh ships) | cc-dispatcher `onResult` / `onTextTurnEnd` | GDPR Art. 13(3) — new persisted category; Art. 5(1)(c) — data minimization |
| **FR6** | One-line hydration regression test asserting `api-messages.ts` returns cc rows | test-only, no production change | guard against approach-2 regression |

**One folded scope-out:** introduce `AssistantPersistMode` type alias (PR-A1 review #3623 deferral #3). It is **not a cosmetic fold** — W4 changes `saveAssistantMessage`'s signature to carry typed `usage`, so the alias is a Phase 1 necessity, not a Phase 3 refactor.

**Deferred to a separate `chore:` PR** per code-simplicity F6 + architecture-strategist concurrence: the 3 remaining PR-A1 cosmetic scope-outs (rename `workflowEnded` → `assistantTurnPersisted`, rename `accumulatedAssistantText` → `latestAssistantText`, extract `dispatchWithDefaults` test helper). Their inclusion in a GDPR-gated PR would dilute the review surface for zero load-bearing benefit. The plan body below uses the original `accumulatedAssistantText` / `workflowEnded` names that exist at HEAD.

**Why now:** PR-A1 (#3602) shipped the highest-user-impact W2+W8 fix in one session. The deferred work — cross-tenant invariants + new persisted column — carries the GDPR-gated risk and was sized for its own focused PR per DHH "ship the fix, don't perform the fix" framing.

## Provenance

- **Issue umbrella:** #3603 (stays OPEN until PR-A2 + PR-B + PR-C all ship)
- **Predecessor:** PR #3602 merged 2026-05-12 07:03 UTC at commit `224da309`
- **Source-of-truth plan (rev-3 deferred portion):** `knowledge-base/project/plans/2026-05-11-feat-cc-soleur-go-transcript-hardening-pra-plan.md` §1.2, §1.4, §1.5
- **Spec:** `knowledge-base/project/specs/feat-cc-assistant-turn-persistence-3258/spec.md` (FR2/W1, FR5/W4, FR6 hydration regression)
- **Brainstorm:** `knowledge-base/project/brainstorms/2026-05-11-cc-soleur-go-transcript-hardening-brainstorm.md` (USER_BRAND_CRITICAL framing)
- **PR-A1 review audit:** #3623 (6-reviewer parallel pass, 6 deferrals named)
- **AC11 verification:** PASSED 2026-05-11 (conversation `36df3694-9f0c-4e1e-905f-c0846b52749e`)
- **rev-2 plan review:** legal-compliance-auditor + code-simplicity-reviewer + architecture-strategist (2026-05-12; 8 findings applied inline, 2 deferred as new D-* items)

## User-Brand Impact

**If this lands broken, the user experiences:**
- (W1) User A reloads the chat surface and sees User B's assistant message as their own conversation history — "this is not my data" trust collapse and GDPR Art. 33/34 notifiable breach.
- (W4) Token-count + cost data persists to `messages.usage` before the Privacy Policy acknowledges this new personal-data category — Art. 13(3) transparency defect; data subjects exercising Art. 15 export get a payload the policy doesn't describe.

**If this leaks, the user's data is exposed via:**
- (W1) Cross-tenant INSERT path: cc-dispatcher uses the service-role client (`supabase()` at line 454), which **bypasses RLS on writes**. A bug routing User A's dispatch with User B's `conversation_id` would write into B's conversation undetected. RLS catches reads, not writes.
- (W4) Token-usage telemetry leaking into Art. 15 DSAR exports before the user-facing disclosure naming this category.

**Brand-survival threshold:** `single-user incident`. One screenshot of cross-tenant content ends recruitment per CPO; one Art. 13(3) disclosure miss is a CLO ack-able violation regardless of cohort size.

**Carry-forward from brainstorm Phase 0.1 — failure modes ranked:**
1. Cross-tenant leak — low probability, unbounded blast radius, Art. 33/34 notifiable. W1 closes via `assertWriteScope` at the INSERT boundary.
2. Silent transcript truncation on abort — *closed in PR-A1*; container-kill SIGKILL is accepted residual D1.
3. Pre-disclosure new-category persistence — medium probability if flag default flips by accident. W4 `CC_PERSIST_USAGE=false` default + plan-time grep audit + Doppler/Vercel env-state AC forces flag-flip to be a deliberate PR-C-merge action.

**CPO sign-off required at plan time** before `/work` begins. `user-impact-reviewer` invoked at review-time per `plugins/soleur/skills/review/SKILL.md` conditional-agent block.

## Research Reconciliation — Spec vs. Codebase (post-PR-A1 HEAD = 224da309)

Repo research surfaced six symbol/line drifts from rev-3 plan and three GAPs that PR-A2 introduces. rev-2 of this plan adds one more verified gap: the **Art. 30 register file does not exist** in the worktree.

| Spec / rev-3 plan / rev-1 claim | Reality at HEAD (2026-05-12) | Plan response |
|---|---|---|
| Stage-3 deferral comment at `cc-dispatcher.ts:1137-1139` | Comment now at `cc-dispatcher.ts:1203-1204` (in `events.onResult` body) | All cites in Phase 1 use 1203-1204 |
| `handleResultMessage` at `soleur-go-runner.ts:1682-1735` | Moved to `soleur-go-runner.ts:1786-1850` (`onResult` 1836, `onTextTurnEnd?.()` 1848) | Phase 0.6 cites the new range |
| `mirrorWithDebounce` "1-hour TTL Set dedup bypass" | **No bypass wrapper** in `observability.ts` | Introduce `mirrorP0Deduped(err, ctx)` (Phase 2.3) — rev-2 rename per architecture F8 (called from non-cross-tenant orphan site too, so name describes dedup contract not scope) |
| Existing test seam name | `__resetMirrorDebounceForTests` at `observability.ts:215` | Mirror exactly: `__resetP0DedupForTests` |
| `currentTurnIndex` counter | Not present | Introduce as closure-scoped (Phase 1.2) |
| `pendingTurnUsage` state box | Not present | Introduce as closure-scoped (Phase 1.2) |
| `CC_PERSIST_USAGE` env flag | Not present anywhere in `apps/` | Add gated read in `saveAssistantMessage` (Phase 1.3); AC9/AC10 + Doppler/Vercel state AC enforce default-false at merge |
| `assertWriteScope` helper | Not present | Introduce in `cc-dispatcher.ts` (Phase 2.1) — rev-2 returns `boolean` (architecture F7 fix: no throw across `void` boundary) |
| `Message.usage` typed shape | Documented at `types.ts:414-416` as "Set only when `status === 'aborted'`" — **contradicts W4 cc-path write on complete turns** | rev-2 Phase 3.2: narrow the doc-comment to acknowledge cc-path emits `{cost_usd}` on complete turns; data-minimization per Art. 5(1)(c) |
| `article-30-register.md` exists for Art. 30 update reference | **CRITICAL GAP — file does not exist** anywhere in the worktree | rev-2 PR-C blocker: register must be created (or located if hidden) BEFORE flag-flip; logged in Deferred items as **D-art30** and `compliance-posture.md` Active Item |
| cc-dispatcher uses RLS-enforced INSERT | rev-3 implied parity with agent-runner | cc-dispatcher.ts:1072 uses `supabase()` = **service-role** (RLS bypass). `assertWriteScope` is load-bearing (Phase 2.1 rationale) |
| `cc-dispatcher-real-factory.test.ts` is a real-DB integration | Exists (622 lines) but is an SDK-mock unit test | Build NEW harness `cc-dispatcher-cross-tenant.integration.test.ts` mirroring `conversations-rail-cross-tenant.integration.test.ts` (Phase 2.4) |
| `Message.usage` typed as raw jsonb | Typed as `{ input_tokens, output_tokens, cost_usd, completed_actions[] }` at `types.ts:417+` | Phase 1.3.1 narrows cc-path write to `{ cost_usd }` only — data-minimization; doc-comment updated in 3.2 |
| User-prompt mention of "W8 preamble filter" | Spec rev-1 framing — superseded by spec rev-2 PR-A1 shipped W8 as **replace-not-append**, not filter | No W8 work in PR-A2 |

**Hard rule applied:** every cite in Phases 0-3 below grep-verified against worktree HEAD at draft time.

## Spec reconciliation

Spec FR2 (cross-tenant matrix) and FR5 (usage parity) carry forward — design is locked by PR-A1's plan rev-2 multi-reviewer pass + GDPR audit. Spec FR1 satisfied (AC11 PASSED). Spec FR3 (W2), FR5b (W8) closed by PR-A1.

**rev-2 spec amendment** (Phase 3.2 of this plan): the `Message.usage` doc-comment at `lib/types.ts:414-416` is incorrect — it says "Set only when `status === 'aborted'`" but W4 persists `cost_usd` on `complete` turns too. The doc-comment must be updated in the same commit as W4's type-shape narrowing.

## Goals

- Establish a write-boundary tenant-isolation invariant that gates every future change to cc-path persistence.
- Land `messages.usage` parity behind a default-off feature flag with **cc-narrowed shape** (cost_usd only, per Art. 5(1)(c) data-minimization) so the new category isn't persisted before the user-facing disclosure (PR-C) ships.
- Add a one-line hydration regression test guarding against approach-2 redux (accidental cc-row filter).

## Non-Goals

- **`/usage` aggregate-cost reader.** Separate workstream.
- **`UNIQUE (conversation_id, turn_id)` DB constraint.** Per DEC8: in-process protection only.
- **Decompose `cc-dispatcher.ts` into focused modules** (#3243). Large refactor; **acknowledged** — separate cycle.
- **`tool_use` WS raw-name field** (#3242). Orthogonal; **acknowledged**.
- **`conversation_messages` MCP tool** (#3289). Orthogonal; **acknowledged**.
- **3 cosmetic refactors from PR-A1 review** (rename × 2 + `dispatchWithDefaults`): defer to a separate `chore:` PR per code-simplicity F6 + architecture-strategist concurrence. **Acknowledged.**
- **`it.each` 6-status conversion + microtask-flush** (PR-A1 deferred). Test-quality only; same `chore:` cycle as above.
- **DSAR Art. 15 export endpoint** (D-DSAR-art15). Pre-existing gap.
- **`security_events` durable audit-log table** (rev-2 new — D-durable-audit-log). Art. 33 6-year retention can't be satisfied by Sentry alone (typical 30-90d retention). Defer table design to a follow-up cycle.
- **100-concurrent stress matrix variant** (rev-2 new — D-stress, carried from PR-A1 CLO question). Interleaved 4-dispatch matrix proves isolation; stress is a separate workstream.

## TDD ordering (mandatory per `cq-write-failing-tests-before`)

RED → GREEN → REFACTOR. Test + implementation in the same commit per DHH.

**Phase-order load-bearing** (learning `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`): W4 introduces the `messages.usage` write contract that W1's cascade-erasure test consumes. **W4 first**, then W1, then FR6. Architecture-strategist F4 confirms: runtime call order is `assertWriteScope → CC_PERSIST_USAGE gate → INSERT` (scope before flag, flag inside write — both directions consistent).

## Phase 0 — Setup

- [ ] 0.1 Read post-PR-A1 `apps/web-platform/test/cc-dispatcher.test.ts` lines 4-132 (hoisted mocks + reset) and the 12 new W2/W8 tests.
- [ ] 0.2 Grep for the closest real-DB harness: `rg -l 'getFreshTenantClient\|signInWithPassword' apps/web-platform/test/`. Expected: `conversations-rail-cross-tenant.integration.test.ts` (architecture F5 verified — flat `*.integration.test.ts` is the convention). Document the harness skeleton in this plan before Phase 2.4.
- [ ] 0.3 Baseline: `npx vitest run apps/web-platform/test/cc-dispatcher.test.ts` → all 36 pass. `bun tsc --noEmit` → clean.
- [ ] 0.4 Verify worktree HEAD = `224da309`. Rebase if main has advanced.
- [ ] 0.5 **Plan-time grep audit** (learning `2026-04-24-guard-surface-audit-before-coding.md`): `rg 'CC_PERSIST_USAGE' apps/ docs/ .github/ 2>/dev/null` → must return zero. Confirms greenfield introduction.
- [ ] 0.6 Read `soleur-go-runner.ts:1786-1850` (`handleResultMessage`) verbatim and confirm: (a) `onResult` fires synchronously before `onTextTurnEnd?.()` inside the same body, (b) `onResult({ totalCostUsd: delta })` at line 1836 — `totalCostUsd` IS a per-turn delta (`soleur-go-runner.ts:1787` proves), (c) cost-cap `onWorkflowEnded` fires AFTER both callbacks. If any fails, halt — W4 race protection design depends on this ordering.
- [ ] 0.7 **rev-2 — Art. 30 register existence check:** `find . -name 'article-30-register*' -o -name '*art-30*' 2>/dev/null`. Result must NOT change the PR-A2 scope, but if the file STILL doesn't exist at /work start time, escalate **D-art30** to a PR-C explicit blocker. (Carry-forward from this plan's rev-2 review — same outcome expected.)
- [ ] 0.8 **rev-2 — Doppler/Vercel env-state check:** `doppler secrets get CC_PERSIST_USAGE --project soleur --config dev_terraform --plain 2>&1`, same for `prd_terraform` and `prd`. Each must return error or empty (key absent). Captured as AC11 evidence in PR body. (Per GDPR Review 5 — pipeline-leak foot-gun.)

## Phase 1 — W4 RED+GREEN (feature-flagged usage parity, cc-narrowed)

Commit: `feat(cc-dispatcher): W4 messages.usage parity behind CC_PERSIST_USAGE flag — #3603`.

### 1.1 Tests (T-W4)

`apps/web-platform/test/cc-dispatcher.test.ts`:

- [ ] **1.1.1 T-W4-basic-on:** `CC_PERSIST_USAGE=true`. SDK fires `onResult({ totalCostUsd: 0.0042 })` then `onTextTurnEnd`. Assert exactly one row with `usage = { cost_usd: 0.0042 }` — narrow shape, no `input_tokens`/`output_tokens`/`completed_actions` on complete turns (Art. 5(1)(c)).
- [ ] **1.1.2 T-W4-basic-off:** `CC_PERSIST_USAGE=false` (default). Same SDK trace. Assert row has `usage = null`. Status still `complete`.
- [ ] **1.1.3 T-W4-race** (Kieran PR-A1 P0-3 carry-forward): sequence `onResult(turnN, 0.001) → onTextTurnEnd(turnN) → onResult(turnN+1 LATE, 0.002) → onTextTurnEnd(turnN+1)`. Assert turn-N row has `cost_usd=0.001`, turn-N+1 row has `cost_usd=0.002`. `turnIndex` tag on `pendingTurnUsage` enforces.
- [ ] **1.1.4 T-W4-orphan:** `onResult` fires (usage captured) → `onWorkflowEnded(runner_runaway)` before any text → no abort row (empty-content drop per PR-A1 contract at `cc-dispatcher.ts:1041-1042`). Assert: zero inserts, ONE Sentry mirror with op-slug literal `"usage_orphan_dropped"` via `mirrorP0Deduped`. Dedup-keyed on `(userId, "usage_orphan_dropped", conversationId)` with 1h TTL.
- [ ] **1.1.5 T-W4-flag-symmetry:** `CC_PERSIST_USAGE=true` but `onResult` not fired → row writes `usage = null` (explicit-null contract per learning `2026-05-04-telemetry-join-format-mismatch-caught-by-orphan-counter.md`).
- [ ] **1.1.6 T-W4-reset-symmetry:** PR-A1's abort-flush path MUST clear `pendingTurnUsage` so a half-captured usage from a prior turn cannot attach later. Covers learning `2026-05-11-debounce-cache-needs-eviction-and-symmetric-state-reset.md`.

### 1.2 Implementation — state

`apps/web-platform/server/cc-dispatcher.ts`, adjacent to `accumulatedAssistantText` (line 1030) and `workflowEnded` (line 1035):

- [ ] **1.2.1**
  ```ts
  let currentTurnIndex = 0;
  let pendingTurnUsage: { turnIndex: number; costUsd: number } | null = null;
  ```
- [ ] **1.2.2** Implement `events.onResult` (replace stub at lines 1202-1204):
  ```ts
  events.onResult = ({ totalCostUsd }) => {
    pendingTurnUsage = { turnIndex: currentTurnIndex, costUsd: totalCostUsd };
  };
  ```
- [ ] **1.2.3** Extend `events.onTextTurnEnd` (line 1119) — snapshot-then-clear-then-bump synchronously BEFORE the async save at line 1129:
  ```ts
  const turnSnapshot = currentTurnIndex;
  const usageSnapshot = pendingTurnUsage?.turnIndex === turnSnapshot ? pendingTurnUsage : null;
  pendingTurnUsage = null;
  currentTurnIndex = turnSnapshot + 1;
  void saveAssistantMessage({ usage: usageSnapshot });
  ```
- [ ] **1.2.4** Extend abort-flush at lines 1159-1164:
  ```ts
  if (accumulatedAssistantText.length > 0 && end.status !== "completed") {
    const usageSnapshot = pendingTurnUsage?.turnIndex === currentTurnIndex ? pendingTurnUsage : null;
    pendingTurnUsage = null;
    workflowEnded = true;
    void saveAssistantMessage({ status: "aborted", usage: usageSnapshot });
  } else if (pendingTurnUsage && accumulatedAssistantText.length === 0) {
    // Orphan: usage without text → drop + P0 mirror (1h dedup)
    pendingTurnUsage = null;
    mirrorP0Deduped(new Error("usage_orphan_dropped"), { op: "usage_orphan_dropped", userId, conversationId });
  }
  ```
  Reset symmetry: every site clearing `accumulatedAssistantText` must also clear `pendingTurnUsage` (learning cited above).

### 1.3 Implementation — `AssistantPersistMode` + flag gate

- [ ] **1.3.1** Add typed alias adjacent to `saveAssistantMessage` (line 1037):
  ```ts
  type AssistantPersistMode = {
    status?: "aborted";
    /** cc-path narrows the type-wide `Message.usage` shape to cost-only on complete turns (Art. 5(1)(c) data-minimization). On abort, may extend to legacy snapshot shape if needed by future migration; PR-A2 emits cost-only in both branches. */
    usage?: { costUsd: number } | null;
  };
  async function saveAssistantMessage(opts?: AssistantPersistMode): Promise<void> { … }
  ```
- [ ] **1.3.2** Gate `usage` write on flag, single read site (AC10 enforced):
  ```ts
  const usageColumn = process.env.CC_PERSIST_USAGE === "true" && opts?.usage
    ? { cost_usd: opts.usage.costUsd }
    : null;
  ```
  Exact-match `"true"` only (any other truthy string → off). Hot-path read intentional per architecture F6 (enables runtime rollback flip without restart, load-bearing for a GDPR-rollback scenario).
- [ ] **1.3.3** Wire `usageColumn` into the INSERT at line 1072. Column name from migration 040 is `usage`.

### 1.4 Phase 1 checkpoint

- [ ] `npx vitest run apps/web-platform/test/cc-dispatcher.test.ts` — T-W4 × 6 pass; 36 PR-A1 tests still pass.
- [ ] `bun tsc --noEmit` clean. `bun run lint` clean on touched files.
- [ ] Commit.

## Phase 2 — W1 RED+GREEN (cross-tenant write-scope assertion + real-DB matrix)

Commit: `feat(cc-dispatcher): W1 cross-tenant invariants + assertWriteScope — #3603`.

### 2.1 `assertWriteScope` helper — rev-2 return-bool design

`apps/web-platform/server/cc-dispatcher.ts` near `saveAssistantMessage`:

- [ ] **2.1.1** Extract (rev-2 simplifications: drop `payload*` params per simplicity F1, return `boolean` per architecture F7 fix, no typed error class per simplicity F2):
  ```ts
  /** Cross-tenant write-boundary guard. Returns true when safe to proceed.
   * Returns false (and mirrors P0) if the dispatch closure's userId/conversationId
   * disagrees with any future SDK-payload-derived identifier we add. Today the
   * dispatch closure is the only source of truth — this helper is a sentinel that
   * runs at every write call site, ready to enforce when a payload source appears.
   * Load-bearing because cc-dispatcher.ts:1072 uses supabase() = service-role
   * (RLS-bypass on writes). RLS catches reads; this guard catches writes. */
  function assertWriteScope(dispatchUserId: string, dispatchConversationId: string): boolean {
    // Sentinel: today no payload source exists, so this is always true. The call
    // site exists so a future regression introducing a payload-derived field
    // has exactly one place to wire the comparison into.
    return true;
  }
  ```
  When a future SDK callback exposes payload `user_id`/`conversation_id`, extend signature with those params + add the mismatch check + `mirrorP0Deduped` call inside — single edit, two-line diff.
- [ ] **2.1.2** Call at the **top** of `saveAssistantMessage`, control-flow style (NOT throw):
  ```ts
  if (!assertWriteScope(userId, conversationId)) return;
  ```
  Architecture F7: the throw-from-void-saveAssistantMessage shape would create unhandled rejections at call sites 1129 + 1163. Return-bool keeps the halt semantic without exception-as-control-flow.
- [ ] **2.1.3** Inline doc-comment at the call site: `// Per CLO 7 invariants (issue #3603 W1). cc-path uses service-role for INSERT (RLS-bypass on writes). Sentinel call site for future write-boundary enforcement.`

### 2.2 `mirrorP0Deduped` — bypass-debounce P0 helper

`apps/web-platform/server/observability.ts`:

- [ ] **2.2.1** Add exported function. Module-level state:
  ```ts
  const P0_DEDUP_TTL_MS = 60 * 60 * 1000;  // 1 hour
  const _p0DedupMap = new Map<string, number>();
  let _p0WriteCount = 0;
  ```
- [ ] **2.2.2** Function body (rev-2 — adds `severity` + `firstSeenAt` for Art. 33 72h-clock evidence trail per GDPR Review 2; renamed from rev-1's `mirrorP0CrossTenant` per architecture F8):
  ```ts
  export function mirrorP0Deduped(err: Error, ctx: { op: string; userId: string; conversationId: string }): void {
    const key = `${ctx.userId}:${ctx.op}:${ctx.conversationId}`;
    const now = Date.now();
    const last = _p0DedupMap.get(key);
    if (last !== undefined && now - last < P0_DEDUP_TTL_MS) return;
    _p0DedupMap.set(key, now);

    // Amortized sweep every 64 writes — bounded memory per learning
    // 2026-05-11-debounce-cache-needs-eviction-and-symmetric-state-reset.md.
    _p0WriteCount++;
    if (_p0WriteCount % 64 === 0) {
      for (const [k, t] of _p0DedupMap) if (now - t > P0_DEDUP_TTL_MS) _p0DedupMap.delete(k);
    }

    // P0 to Sentry — bypasses mirrorWithDebounce 5-min window.
    // `firstSeenAt` starts the Art. 33 72h notifiability clock at the first
    // observation, even if subsequent re-fires are dedup-suppressed.
    Sentry.captureException(err, {
      level: "fatal",
      tags: { op: ctx.op, scope: "p0_deduped" },
      extra: { ...ctx, severity: "breach_attempt", first_seen_at: new Date(now).toISOString() },
    });
  }
  export function __resetP0DedupForTests(): void { _p0DedupMap.clear(); _p0WriteCount = 0; }
  ```
  Naming mirrors the existing `__resetMirrorDebounceForTests` at `observability.ts:215` (verified — not `_drain*`).
- [ ] **2.2.3** Hook `__resetP0DedupForTests` into the test reset chain in `cc-dispatcher.test.ts:122-132`.

### 2.3 Real-Supabase test harness — `cc-dispatcher-cross-tenant.integration.test.ts`

NEW file: `apps/web-platform/test/cc-dispatcher-cross-tenant.integration.test.ts`.

- [ ] **2.3.1** Mirror the harness shape from `conversations-rail-cross-tenant.integration.test.ts` (Phase 0.2 verified existence; architecture F5 confirmed convention).
- [ ] **2.3.2** Prerequisites:
  - Env: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`. Skip-if-absent: `describe.skipIf(!process.env.SUPABASE_URL)` so CI without secrets doesn't redbar.
  - `bun install` precondition (learning `2026-03-18-bun-test-segfault-missing-deps.md`).
- [ ] **2.3.3** `beforeAll`: create `userA` + `userB` via service-role auth admin. `afterAll`: cleanup with up-to-3 retries on unique-email collision. **rev-2 addition (GDPR Note 2 — robustness):** `afterEach` truncates `messages` for the 4 conversation IDs as belt-and-braces against partial cleanup.
- [ ] **2.3.4** Create A1, A2 (`user_id=userA.id`), B1, B2 (`user_id=userB.id`). Service-role insert; cascade cleans on conversation delete.

### 2.4 Tests (T-W1) — 6 invariants post-rev-2 (was 7 in rev-1; invariant-3 grep-meta cut per simplicity F5)

- [ ] **2.4.1 T-W1-matrix:** dispatch concurrently across A1/A2/B1/B2 via `Promise.all` with **interleaved** `onText` + `onTextTurnEnd` ticks (deliberate cross-fire — sequential awaits would not validate concurrent isolation per Art. 32 evidentiary bar). Assert every assistant row's `conversation_id` matches its dispatch; no row in B's conversations has content from A's dispatches.
- [ ] **2.4.2 T-W1-invariant-1 (RLS read enforcement):** `getFreshTenantClient(userA.id)` on `conversation_id=A1` → returns A1 rows. Same client on `conversation_id=B1` → returns ZERO rows. **Assertion shape (per learning `2026-05-06-rls-zero-policies-anon-delete-204-semantic.md`):** `expect(result.data).toEqual([])` AND `expect(result.error?.code === 'PGRST116' || result.error == null).toBe(true)` — RLS-deny returns empty rows, not an error. Distinguishes from auth-fail per learning `2026-04-12-silent-rls-failures-in-team-names.md` (auth client should NOT silently fail).
- [ ] **2.4.3 T-W1-invariant-2 (forged JWT):** auth client signed-in as userA but querying `conversation_id=B1` → assert empty result + no panic. Re-confirms RLS predicate at `001_initial_schema.sql:79-86` (exists-clause via FK).
- [ ] **2.4.4 ~~T-W1-invariant-3 (grep-meta)~~ — CUT per simplicity F5.** The `readFileSync` regex was brittle (broke on any `events.on*` rename or formatting drift) and tautological. Replaced by a **TypeScript-level invariant**: ensure `DispatchEvents` callback args at `soleur-go-runner.ts:653-690` do NOT carry `user_id` or `conversation_id` fields. Phase 0.6 already reads this range; rev-2 adds explicit grep here: `rg -n 'user_id|conversation_id' apps/web-platform/server/soleur-go-runner.ts | head -10` must show zero matches on callback argument types. If a future callback adds those fields, the type system + this grep gate catches it; no test needed.
- [ ] **2.4.5 T-W1-invariant-4 (dedup):** force abort → late `onTextTurnEnd` → assert exactly ONE row with status `aborted`. Closure flag `workflowEnded` is the dedup mechanism, not `turn_id`. (Carry-forward from PR-A1 W2; included here for completeness against the W1 invariant matrix.)
- [ ] **2.4.6 T-W1-invariant-5 (hydration empty-DB → empty render):** pre-populate empty `messages` for A1. Call `api-messages.ts` `handleConversationMessages`. Assert empty response. SDK session content is NOT a hydration fallback (covers learning `2026-05-05-kb-chat-resume-hydration-race-strict-mode-and-prefetch-clobber.md`).
- [ ] **2.4.7 T-W1-invariant-5b (deterministic, was hedged in rev-1):** **rev-2 dehedge per simplicity F9.** SDK session is read-only on the hydration path (verified by repo research: `api-messages.ts:76-88` SELECT is the only hydration source; no SDK session roundtrip exists). Assertion: pre-populate empty `messages` + populate an SDK session — assert hydration response is empty AND NO Sentry mirror fires (because no write-back path exists for `assertWriteScope` to catch). If a future change introduces an SDK→write roundtrip, this test will need its assertion updated to expect the mirror — that's the right shape for a future-regression test, not a hedged-conditional today.
- [ ] **2.4.8 T-W1-invariant-6 (cascade-erasure — consumes W4 contract):** with `CC_PERSIST_USAGE=true` in this test only, pre-populate A1 with one assistant row carrying `usage = { cost_usd: 0.005 }`. DELETE the parent `conversations` row. Assert the `messages` row is gone via FK cascade (`001_initial_schema.sql:75` `on delete cascade`), including its `usage` column. No orphan messages (learning `account-deletion-cascade-order-20260402.md`).
- [ ] **2.4.9 T-W1-invariant-7 (sentinel call-site smoke):** **rev-2 simplification.** Since `assertWriteScope` is sentinel-only at HEAD (no payload params), the original P0-mirror assertion has no live failure mode to trigger. Replaced with a sentinel test: call `saveAssistantMessage` once → assert `assertWriteScope` was invoked (spy on the helper) AND that the existing INSERT succeeded. Guards against a future refactor that removes the sentinel call site. When a future payload source is wired in, this test is extended with a mismatch scenario asserting `mirrorP0Deduped` fires.

### 2.5 Phase 2 checkpoint

- [ ] `npx vitest run apps/web-platform/test/cc-dispatcher.test.ts` — unit suite green.
- [ ] `npx vitest run apps/web-platform/test/cc-dispatcher-cross-tenant.integration.test.ts` — integration green against real Supabase dev (operator-run with env set).
- [ ] `bun tsc --noEmit` clean.
- [ ] `/soleur:gdpr-gate` on cumulative diff (work Phase 2 exit per TR7).
- [ ] Commit.

## Phase 3 — FR6 + `Message.usage` doc-comment narrowing

Commit: `chore(types): narrow Message.usage doc-comment for cc-path + FR6 hydration regression — #3603`. Smaller than rev-1 (renames + `dispatchWithDefaults` deferred to a separate `chore:` PR per simplicity F6 + architecture concurrence).

### 3.1 `AssistantPersistMode` finalization

- [ ] Already authored in Phase 1.3.1. Re-affirm doc-comment is correct after Phase 2 changes.

### 3.2 `Message.usage` doc-comment update

`apps/web-platform/lib/types.ts:414-416`:

- [ ] Replace `/** Aborted-turn snapshot: token cost + completed-actions chip-list. / *  Set only when 'status === aborted'. ...` with:
  ```ts
  /** Persistence: cc-path emits `{ cost_usd: number }` on `'complete'` turns
   *  when `CC_PERSIST_USAGE=true` (PR #3603 W4, default off). Legacy
   *  agent-runner path emits the full snapshot ({input_tokens, output_tokens,
   *  cost_usd, completed_actions[]}) on `'aborted'` turns per migration 040.
   *  Shape documented in `UsageSnapshot` in `agent-runner.ts`. Optional in
   *  type so existing fixtures don't churn. */
  ```
  Per GDPR Review 3: doc-comment now reflects reality; cc-narrowed shape (Art. 5(1)(c)) acknowledged.

### 3.3 FR6 hydration regression test

- [ ] New test in `apps/web-platform/test/api-messages.test.ts` (verify file exists in Phase 0; if not, create). Pre-populate one row `leader_id="cc_router"` + one row `leader_id="soleur_go"` for the same `conversation_id`. Call the `handleConversationMessages` handler. Assert BOTH rows returned.
- [ ] One-line invariant comment: `// Guards against approach-2 regression: cc rows must NOT be filtered from hydration.`

### 3.4 Phase 3 checkpoint

- [ ] Full test suite: `npx vitest run apps/web-platform/test/` — all green.
- [ ] `bun tsc --noEmit` + `bun run lint` clean.
- [ ] Commit.

## Phase 4 — Pre-merge gates

- [ ] 4.1 Push branch + open PR. PR body cites `#3623` (Closes — covers `AssistantPersistMode` deferral #3 only; the other 5 PR-A1 deferrals stay open) and `Refs #3603`. Cosmetic `chore:` PR for renames + `dispatchWithDefaults` filed as separate scope-out.
- [ ] 4.2 `/soleur:review` (6-agent parallel) over `cc-dispatcher.ts`, `observability.ts`, `lib/types.ts`, both test files. Findings fix-inline.
- [ ] 4.3 `/soleur:qa` against real Supabase dev — W1 matrix requires real DB. Operator-run; output attached to PR.
- [ ] 4.4 `/soleur:preflight` — Check 6 (User-Brand Impact) gates on `requires_cpo_signoff: true`. CPO sign-off comment required.
- [ ] 4.5 `/soleur:gdpr-gate` final pass (ship Phase 5.5).
- [ ] 4.6 `gh pr checks <pr#>` all green.
- [ ] 4.7 `gh pr merge <pr#> --squash --auto`. #3603 stays OPEN for PR-B + PR-C.

## Phase 5 — Post-merge

- [ ] 5.1 `/soleur:postmerge` — verify deployment + no new Sentry error classes.
- [ ] 5.2 `knowledge-base/legal/compliance-posture.md` — one Active Items bullet pointing at PR + #3623 + D-art30 + D-durable-audit-log.
- [ ] 5.3 `/soleur:compound` capture: real-DB integration harness pattern, `mirrorP0Deduped` design, `assertWriteScope` sentinel-pattern rationale.
- [ ] 5.4 Confirm `CC_PERSIST_USAGE=false` is merged default (re-grep `apps/.env*.example`).
- [ ] 5.5 File the separate `chore:` PR for the 3 deferred PR-A1 cosmetic refactors. Link from #3623.

## Open Code-Review Overlap

4 open scope-outs touch PR-A2 file surfaces. Dispositions:

- **#3623** (PR-A1 6-reviewer audit) — **PARTIAL FOLD**: closes deferral #3 (`AssistantPersistMode`, Phase 1.3.1). Deferrals #1, #2, #4, #5, #6 (rename × 2, `dispatchWithDefaults`, `it.each` 6-status, microtask-flush) go to a separate `chore:` PR per code-simplicity F6. PR body partial `Closes` and explicit cite of the deferral split.
- **#3243** (decompose cc-dispatcher.ts) — **ACKNOWLEDGE**: Large refactor; deliberate non-fold to keep GDPR-gated review focused.
- **#3242** (tool_use WS raw name) — **ACKNOWLEDGE**: orthogonal.
- **#3289** (conversation_messages MCP tool) — **ACKNOWLEDGE**: orthogonal.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| **Assert cross-tenant isolation at RLS layer only** (no `assertWriteScope`) | cc-dispatcher.ts:1072 uses service-role (RLS bypass on writes). RLS catches reads, not the cc-path writes. Sentinel call site is the right shape — runs today, ready when a future SDK payload introduces a comparison source. |
| **`UNIQUE (conversation_id, turn_id)` DB constraint** instead of in-process closure flag | Per DEC8: Postgres unique-violation surfaced to user is worse UX. PR-A1's `workflowEnded` flag handles the only observed race. |
| **Persist `usage` unflagged + refresh Privacy Policy in same PR** | Crosses competence boundary. PR-C is legal-doc-only by design; default-off flag closes Art. 13(3) gap without bundling. |
| **Route P0 via `mirrorWithDebounce`** with different errorClass | 5-min dedup key is `${userId}:${errorClass}` — wrong scope; cross-tenant events from the SAME user would dedup together. 1h dedup keyed on `(userId, op, conversationId)` is the right scope per CLO TR1.7. |
| **rev-1: throw `CrossTenantWriteError` from `assertWriteScope`** | Architecture F7: `void saveAssistantMessage()` call sites at lines 1129+1163 turn throws into unhandled promise rejections. rev-2 returns boolean; halt is `if (!assertWriteScope(...)) return`. |
| **rev-1: full `Message.usage` snapshot on cc complete-turn writes** | GDPR Review 3 / Art. 5(1)(c): data-minimization argues for cost-only on complete turns. rev-2 narrows to `{ cost_usd }` and updates the `Message.usage` doc-comment to reflect cc-vs-legacy semantics. |

## Deferred items

- [ ] **D1** (carry from PR-A1) — Container-kill / SIGKILL flush gap. Heartbeat-based detection.
- [ ] **D2** (carry from PR-A1) — Multi-bubble-per-turn UI semantic.
- [ ] **D3** (carry from PR-A1) — `conversations.status="failed"` rollup despite per-message success.
- [ ] **D-DSAR-art15** (carry from PR-A1 Phase 0.5) — DSAR Art. 15 export endpoint. Pre-existing gap.
- [ ] **D-art30** (rev-2 new — GDPR Critical) — `article-30-register.md` does not exist in the worktree. PR-C MUST create or locate the Art. 30 register BEFORE `CC_PERSIST_USAGE` flag-flip. File as `compliance/critical` issue against PR-C scope.
- [ ] **D-durable-audit-log** (rev-2 new — GDPR Review 4) — `security_events` table or append-only log under `knowledge-base/security/` for Art. 33 6-year retention. Sentry retention (30-90d) is inadequate for breach-attempt evidence beyond the 72h notifiability window.
- [ ] **D-stress** (rev-2 new — carry PR-A1 CLO question) — 100-concurrent matrix variant. Interleaved 4-dispatch matrix proves isolation; stress-variant is a separate workstream.
- [ ] **D-pr-a1-cosmetics** (rev-2 new — code-simplicity F6) — separate `chore:` PR for: rename `workflowEnded` → `assistantTurnPersisted`, rename `accumulatedAssistantText` → `latestAssistantText`, extract `dispatchWithDefaults`, `it.each` 6-status conversion, microtask-flush replacement of `setTimeout(10ms)`. Lands before or after PR-A2; no contract change.

## Files to edit

| File | Purpose | Phase |
|---|---|---|
| `apps/web-platform/server/cc-dispatcher.ts` | W4 state + flag + `onResult`/`onTextTurnEnd`/orphan handling + `AssistantPersistMode`; W1 `assertWriteScope` sentinel + call site | 1, 2 |
| `apps/web-platform/server/observability.ts` | `mirrorP0Deduped` + `__resetP0DedupForTests` | 2.2 |
| `apps/web-platform/lib/types.ts` | `Message.usage` doc-comment narrowing (Phase 3.2) | 3.2 |
| `apps/web-platform/test/cc-dispatcher.test.ts` | T-W4 × 6, T-W1-invariant-7 sentinel, `__resetP0DedupForTests` hookup | 1, 2 |

## Files to create

| File | Purpose | Phase |
|---|---|---|
| `apps/web-platform/test/cc-dispatcher-cross-tenant.integration.test.ts` | Real-Supabase 2×2 matrix, T-W1 invariants 1, 2, 5, 5b, 6 | 2.3-2.4 |
| `apps/web-platform/test/api-messages.test.ts` (only if absent at Phase 0) | FR6 hydration regression | 3.3 |

## Files NOT touched

- `apps/web-platform/server/soleur-go-runner.ts` — read in Phase 0.6 for `handleResultMessage` ordering verification only.
- `apps/web-platform/server/agent-runner.ts` — read for parity contract at 396-411 + 1841 + 2044-2055; legacy behavior unchanged.
- `apps/web-platform/server/api-messages.ts` — FR6 adds a test against existing handler; no production change.
- `apps/web-platform/supabase/migrations/*` — no new migration; `status`+`usage` columns from migration 040; RLS from migration 001.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1:** T-W4 × 6 pass (basic-on, basic-off, race, orphan, flag-symmetry, reset-symmetry).
- **AC2:** T-W1 unit tests pass (invariant-7 sentinel).
- **AC3:** T-W1 integration tests pass against real Supabase dev (matrix, invariants 1, 2, 5, 5b, 6 cascade-erasure). Operator-run via `/soleur:qa`.
- **AC4:** FR6 hydration regression passes.
- **AC5:** All 36 PR-A1 tests still pass.
- **AC6:** `bun tsc --noEmit` clean. `bun run lint` clean on touched files.
- **AC7:** `/soleur:gdpr-gate` PASS at plan 2.7, work 2 exit (Phase 2.5), ship 5.5 (Phase 4.5). Zero BLOCKs at each invocation.
- **AC8:** `/soleur:review` 6-agent parallel: 0 P0/P1 critical; P2 resolved inline.
- **AC9:** `rg 'CC_PERSIST_USAGE=true' apps/.env*` returns zero. Default-off at merge.
- **AC10 (rev-2 widened per GDPR Review 4):** `rg 'CC_PERSIST_USAGE' apps/ --type ts -g '!**/*.test.ts'` returns exactly ONE match (the single read site in `saveAssistantMessage`). Catches any leak into `apps/web-platform/lib/` or edge functions.
- **AC11 (rev-2 new per GDPR Review 5):** Doppler+Vercel env-state check produces evidence in PR body: `doppler secrets get CC_PERSIST_USAGE --project soleur --config <dev_terraform|prd_terraform|prd> --plain` returns error/empty for each config. No environment has the flag set pre-PR-C.
- **AC12:** CPO sign-off comment on the PR before `/soleur:preflight` Check 6 passes (`requires_cpo_signoff: true` enforced).
- **AC13:** PR body has: link to #3602 + #3623 predecessors, `Refs #3603`, partial `Closes #3623` cite, container-kill residual carry-forward note, Alternatives table, 4 scope-outs disposition list, D-art30 + D-durable-audit-log + D-stress + D-pr-a1-cosmetics filed as separate issues with `compliance/critical` (D-art30 only) + `chore` labels.

### Post-merge (operator)

- **AC14:** `knowledge-base/legal/compliance-posture.md` updated with Active Items entry citing PR + #3623 + D-art30 + D-durable-audit-log.
- **AC15:** `/soleur:postmerge` confirms no new Sentry error classes within 24h of merge.
- **AC16:** `/soleur:compound` session learnings captured (Phase 5.3).
- **AC17:** `chore:` PR opened for D-pr-a1-cosmetics within 1 business day of PR-A2 merge.

## Sharp edges

- **cc-dispatcher uses service-role for INSERT.** RLS protects reads, not writes from this path. `assertWriteScope` is the sentinel — do not delete on a future "RLS covers this" cleanup. Inline doc-comment makes rationale explicit.
- **`pendingTurnUsage` reset symmetry across every clear-site.** Every site that clears `accumulatedAssistantText` MUST also clear `pendingTurnUsage` — currently 3 sites post-W4 (onTextTurnEnd snapshot, abort flush text-path, abort flush orphan-path). A future fourth clear-site (e.g., `closeConversation`) MUST clear both (learning `2026-05-11-debounce-cache-needs-eviction-and-symmetric-state-reset.md`).
- **Closure cardinality ceiling.** Post-W4 the `dispatchSoleurGo` closure holds 4 per-turn state fields (`accumulatedAssistantText`, `workflowEnded`, `currentTurnIndex`, `pendingTurnUsage`). **Crossing 6 fields triggers extraction to `class DispatchSession`** (architecture F3). At 5 fields the reset-symmetry sharp edge above becomes mandatory ADR-grade; at 6 the closure is the wrong shape.
- **SDK `onResult.totalCostUsd` is a delta** (`soleur-go-runner.ts:1787`). A future SDK upgrade to cumulative would silently sum across turns. Phase 0.6 verifies at plan time; fresh verification belongs in any SDK-bump PR review.
- **`mirrorP0Deduped` dedup Map needs amortized sweep.** Per learning, `mirrorWithDebounce`'s unbounded Map was an actual bug. The new helper's `_p0WriteCount % 64 === 0` sweep + `__resetP0DedupForTests` is mandatory.
- **Sentry retention ≠ Art. 33 6-year evidence retention** (GDPR Review 4). Sentry retention is typically 30-90 days; Art. 33(5) requires breach documentation indefinitely (de facto 6y aligning with SoR retention). `mirrorP0Deduped` events age out before regulator inquiry. D-durable-audit-log filed for `security_events` table.
- **vitest-mocked Supabase chains can't catch GRANT/RLS violations** (learning `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`). W1 auth-client SELECT MUST go through `getFreshTenantClient` against real Supabase dev. A "let's just mock it" reviewer suggestion must be rejected — that's the exact failure mode this workstream defends against.
- **Anon DELETE returns 204 under zero-policies RLS** (learning `2026-05-06-rls-zero-policies-anon-delete-204-semantic.md`). T-W1 status assertions use bracketed sets or row-shape, never `=~ ^40[13]$` regex.
- **New columns silently inherit permissive RLS** (learning `rls-column-takeover-github-username-20260407.md`). Invariant-6 cascade covers `usage` as a child of parent `conversations`. A future migration adding a `messages` column needs its own invariant — document as known follow-up.
- **`CC_PERSIST_USAGE` hot-path env-read is intentional.** Architecture F6: enables runtime rollback flip without process restart, load-bearing for a GDPR-rollback scenario after PR-C. A "cache at dispatch entry" refactor would break the rollback contract.
- **Art. 30 register is a phantom citation in the rev-1 plan.** rev-2 flags as **D-art30** (`compliance/critical` against PR-C). The register MUST exist before flag-flip.
- **Hard rule (User-Brand Impact section).** Empty/`TBD` `## User-Brand Impact` fails `deepen-plan` Phase 4.6 and ship Phase 5.5 Check 6. Threshold `single-user incident` declared in frontmatter; do not silently relax.
- **PR-A1 cosmetic scope-outs deferred to a separate `chore:` PR** (rev-2). Renaming `workflowEnded` + `accumulatedAssistantText` + extracting `dispatchWithDefaults` are 3 mechanical edits that would dilute this PR's GDPR-gated review surface. Same logic applies to `it.each` + microtask-flush.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm + PR-A1 plan-time GDPR audit). No fresh leader spawn — Phase 2.5 brainstorm-carry-forward.

**Brainstorm-recommended specialists:** none new. PR-A2 backend-only; Product/UX Gate = none.

### Engineering (CTO) — carry-forward + rev-2 architecture review

**Status:** reviewed. **Assessment:** rev-2 applied architecture F1 (sentinel `assertWriteScope`), F2 (drop typed error class), F7 (return-bool not throw), F8 (helper rename + payload fields). Closure cardinality at 4/6 ceiling — `DispatchSession` extraction deferred to a future cycle once a 6th field is needed. No new ADR.

### Product (CPO) — carry-forward + sign-off required

**Status:** reviewed. **Assessment:** CPO sign-off required at plan-time per `requires_cpo_signoff: true`. Comment on the PR before `/soleur:preflight` Check 6 can pass.

### Legal (CLO) — carry-forward + rev-2 GDPR audit applied

**Status:** reviewed. **Assessment:** rev-2 applied GDPR audit findings 1-5: (1) Art. 30 register CRITICAL filed as D-art30 PR-C blocker; (2) Art. 33 72h-clock supported by `severity` + `firstSeenAt` in Sentry payload; (3) Art. 5(1)(c) data-minimization via cc-narrowed `{ cost_usd }` shape + doc-comment update; (4) Sentry retention gap filed as D-durable-audit-log; (5) Doppler/Vercel env-state AC11 closes pipeline-leak foot-gun. Outstanding: D-art30 must complete before PR-C flag-flip.

### Product/UX Gate

**Tier:** none. Backend-only persistence change. Auto-accepted.

## GDPR Gate (Phase 2.7 — output, rev-2)

`/soleur:gdpr-gate` invocation at plan-time scoped to W1 (Art. 33/34 + Art. 32) and W4 (Art. 13(3) + Art. 5(1)(c)) — synthesized into this section from the legal-compliance-auditor agent run on 2026-05-12.

**Findings:**

- **CRITICAL — D-art30** filed. `docs/legal/article-30-register.md` and equivalents do not exist in the worktree. PR-C MUST create or locate the Art. 30 register before flag-flip. Filed as `compliance/critical` issue; written to `compliance-posture.md` Active Items operator-acknowledged.
- **REVIEW — `Message.usage` doc-comment drift** (Phase 3.2 applied inline).
- **REVIEW — Art. 33 72h-clock evidence** (Phase 2.2.2 — `severity` + `firstSeenAt` extras applied).
- **REVIEW — Sentry retention vs Art. 33(5) 6y** (D-durable-audit-log filed).
- **REVIEW — `CC_PERSIST_USAGE` pipeline-leak vector** (AC11 added; Doppler+Vercel env-state evidence in PR body).
- **NOTE — Concurrent-fire matrix is adequate, not stress-grade** (D-stress filed for follow-up).
- **NOTE — Test-fixture cleanup robustness** (Phase 2.3.3 added `afterEach` truncate as belt-and-braces).

**Disclaimer:** This audit is advisory and non-binding per `hr-gdpr-gate-on-regulated-data-surfaces`. Final compliance posture requires qualified counsel review at PR-C close (Privacy Policy refresh + register creation).

**Suitability for ship:** PR-A2 as rev-2 closes Art. 33/34 cross-tenant write-boundary adequately AND Art. 13(3) sequencing on `messages.usage`. **PR-A2 itself ships under GDPR Art. 33/34/13(3)/5(1)(c)** provided (a) D-art30 is filed as `compliance/critical` against PR-C scope (DONE per Deferred Items), (b) `Message.usage` doc-comment drift corrected in Phase 3.2 (DONE per plan), (c) `CC_PERSIST_USAGE=false` remains the merged default per AC9-11 (enforced).

## References

- Predecessor PR: #3602 (PR-A1, merged 2026-05-12 07:03 UTC)
- PR-A1 review audit: #3623
- Predecessor plan (rev-3 deferred portion): `knowledge-base/project/plans/2026-05-11-feat-cc-soleur-go-transcript-hardening-pra-plan.md`
- Spec: `knowledge-base/project/specs/feat-cc-assistant-turn-persistence-3258/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-11-cc-soleur-go-transcript-hardening-brainstorm.md`
- AC11 verification: `gh issue view 3603` comment 2026-05-11

### rev-2 plan-review record (2026-05-12)

- legal-compliance-auditor: 1 CRITICAL (D-art30), 5 REVIEW, 2 NOTE — all applied or filed.
- code-simplicity-reviewer: F1 (drop payload* params), F2 (drop typed error class), F5 (drop grep-meta invariant-3), F6 (defer cosmetic refactors), F9 (drop /* future fields */ + named op slugs) — all applied; F3 + F4 + F7 + F8 kept (load-bearing).
- architecture-strategist: F7 (return-bool, no throw across void), F8 (rename helper + naming parity) — applied. F1, F4, F5, F6 — confirmed correct as drafted. F3 — captured as Sharp Edge cardinality ceiling.

### Code anchors (HEAD = 224da309, grep-verified at draft time)

- `cc-dispatcher.ts:135-158` — `ABORT_FLUSH_STATUSES` + exhaustiveness rail
- `cc-dispatcher.ts:454-458` — `supabase()` service-role factory
- `cc-dispatcher.ts:1030` — `accumulatedAssistantText` declaration
- `cc-dispatcher.ts:1035` — `workflowEnded` flag
- `cc-dispatcher.ts:1037` — `saveAssistantMessage` signature
- `cc-dispatcher.ts:1041-1042` — snapshot-then-reset (empty-drop)
- `cc-dispatcher.ts:1072` — INSERT call site (service-role)
- `cc-dispatcher.ts:1078-1087` — `mirrorWithDebounce` invocation
- `cc-dispatcher.ts:1092` — `events.onText` (W8 `=` at 1096)
- `cc-dispatcher.ts:1119` — `events.onTextTurnEnd` (workflowEnded guard 1124-1127)
- `cc-dispatcher.ts:1129` — `void saveAssistantMessage()` call site (one of two; F7 reasoning)
- `cc-dispatcher.ts:1148` — `events.onWorkflowEnded` (abort-flush 1159-1164)
- `cc-dispatcher.ts:1163` — second `void saveAssistantMessage({status:"aborted"})` call site
- `cc-dispatcher.ts:1202-1204` — Stage-3 deferral comment (W4 replaces)
- `soleur-go-runner.ts:653-690` — `DispatchEvents` interface
- `soleur-go-runner.ts:1786-1850` — `handleResultMessage` (onResult 1836, onTextTurnEnd?.() 1848)
- `soleur-go-runner.ts:1787` — `delta = msg.total_cost_usd ?? 0` (totalCostUsd is delta)
- `agent-runner.ts:396-411` — `saveMessage` parity contract
- `agent-runner.ts:1841` — completion-path call
- `agent-runner.ts:2044-2055` — `writeAbortedAssistant` legacy contract
- `api-messages.ts:60-69` — auth.uid → conversation user_id check
- `api-messages.ts:76-88` — hydration SELECT (no `active_workflow` filter)
- `lib/types.ts:414-423` — `Message.status` + `Message.usage` (doc-comment narrowed in 3.2)
- `lib/supabase/tenant.ts:236` — `getFreshTenantClient(userId)` (W1 auth-client)
- `observability.ts:82-102` — `reportSilentFallback`
- `observability.ts:183-210` — `mirrorWithDebounce`
- `observability.ts:215` — `__resetMirrorDebounceForTests` (naming parity for `__resetP0DedupForTests`)
- `migrations/001_initial_schema.sql:68-95` — `messages` table + RLS
- `migrations/040_message_status_aborted.sql:22-37` — `status` check + `usage` jsonb columns

### Learnings cited

- `2026-05-12-pr-a1-implementation-and-multi-reviewer-convergence.md` (SDK `onText` cumulative)
- `2026-05-11-debounce-cache-needs-eviction-and-symmetric-state-reset.md` (amortized sweep + reset symmetry)
- `2026-05-11-plan-research-reconciliation-must-grep-full-render-tree.md` (RLS guard load-bearing)
- `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md` (W4 before W1)
- `2026-05-09-llm-authored-plans-cite-fabricated-and-retired-rule-ids.md` (grep-verify cites)
- `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md` (W1 real-DB)
- `2026-05-06-rls-zero-policies-anon-delete-204-semantic.md` (bracketed sets)
- `2026-05-06-cap-coupling-between-adjacent-prs.md` (PR-A1 → PR-A2 → PR-C audit)
- `security-issues/2026-04-18-rls-for-all-using-applies-to-writes.md` (FOR ALL USING)
- `security-issues/rls-column-takeover-github-username-20260407.md` (new columns inherit RLS)
- `logic-errors/account-deletion-cascade-order-20260402.md` (cascade-erasure design)
- `integration-issues/2026-05-05-cc-dispatcher-assistant-persistence-asymmetry.md` (FR6)
- `ui-bugs/2026-05-05-kb-chat-resume-hydration-race-strict-mode-and-prefetch-clobber.md` (invariant-5)
- `2026-04-12-silent-rls-failures-in-team-names.md` (empty-rows vs auth-fail)
- `2026-02-21-cookie-free-analytics-legal-update-pattern.md` (lockstep flag-flip + legal-doc)
- `2026-03-18-bun-test-segfault-missing-deps.md` (Phase 0 bun-install)
- `2026-04-24-guard-surface-audit-before-coding.md` (plan-time grep audit)
- `2026-05-04-telemetry-join-format-mismatch-caught-by-orphan-counter.md` (orphan-counter as own-validation)
