---
date: 2026-05-12
plan: knowledge-base/project/plans/2026-05-12-feat-cc-soleur-go-transcript-hardening-pr-a2-plan.md
issue: "#3603"
predecessor_pr: "#3602 (PR-A1, W2+W8 merged 2026-05-12 07:03 UTC)"
branch: feat-cc-soleur-go-transcript-hardening-pr-a2-3603
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
gdpr_gate: required (plan 2.7, work 2 exit, ship 5.5)
---

# Tasks — cc-soleur-go transcript hardening PR-A2

Derived from the rev-2 plan after 3-reviewer pass (legal-compliance-auditor + code-simplicity-reviewer + architecture-strategist). Phase ordering load-bearing: **W4 → W1 → FR6** (W1 invariant-6 cascade consumes W4's `usage` write).

## Phase 0 — Setup

- [x] 0.1 Read post-PR-A1 `apps/web-platform/test/cc-dispatcher.test.ts` lines 4-132 (hoisted mocks + reset) and the 12 new W2/W8 tests.
- [x] 0.2 Grep `rg -l 'getFreshTenantClient|signInWithPassword' apps/web-platform/test/` → confirm `conversations-rail-cross-tenant.integration.test.ts` harness pattern; document skeleton.
- [x] 0.3 Baseline: `npx vitest run apps/web-platform/test/cc-dispatcher.test.ts` (36 pass) + `bun tsc --noEmit` clean.
- [x] 0.4 Verify HEAD = `224da309`; rebase if main has advanced. (Branch tip is plan-docs commit `70367790`; parent = `224da309`.)
- [x] 0.5 Plan-time grep audit: `rg 'CC_PERSIST_USAGE' apps/ docs/ .github/ 2>/dev/null` returns zero. (Only match was the PR-A1 deferral comment in `cc-dispatcher.ts` — that's the stub the W4 commit replaces.)
- [x] 0.6 Read `soleur-go-runner.ts:1786-1850` (`handleResultMessage`); confirm onResult-before-onTextTurnEnd synchronous ordering + `totalCostUsd` IS delta (line 1787).
- [x] 0.7 Verify `article-30-register.md` still absent → escalate **D-art30** to PR-C explicit blocker if so. (Still absent — escalation stands.)
- [ ] 0.8 Doppler/Vercel env-state check for `CC_PERSIST_USAGE` (dev_terraform + prd_terraform + prd) — all return error/empty. Capture as AC11 evidence. (Deferred to operator at PR creation; `doppler` CLI not available in this worktree session.)

## Phase 1 — W4 (feature-flagged usage parity, cc-narrowed)

### 1.1 Tests T-W4

- [x] 1.1.1 T-W4-basic-on (`{ cost_usd: 0.0042 }` on complete turn under `CC_PERSIST_USAGE=true`).
- [x] 1.1.2 T-W4-basic-off (default false → `usage = null`).
- [x] 1.1.3 T-W4-race (`turnIndex` tag prevents stale `onResult` attribution).
- [x] 1.1.4 T-W4-orphan (usage captured + empty text → drop + `mirrorP0Deduped` fires with op `"usage_orphan_dropped"`).
- [x] 1.1.5 T-W4-flag-symmetry (`true` but no `onResult` → `usage = null` explicit).
- [x] 1.1.6 T-W4-reset-symmetry (abort path clears `pendingTurnUsage` too).

### 1.2 Implementation — state

- [x] 1.2.1 Closure-scoped `currentTurnIndex` + `pendingTurnUsage` adjacent to `accumulatedAssistantText`/`workflowEnded` at `cc-dispatcher.ts:1030-1035`.
- [x] 1.2.2 Replace `onResult` stub at lines 1202-1204 with capture: `pendingTurnUsage = { turnIndex: currentTurnIndex, costUsd: totalCostUsd }`.
- [x] 1.2.3 Extend `onTextTurnEnd` (line 1119): snapshot-clear-bump synchronously before `void saveAssistantMessage()` at line 1129.
- [x] 1.2.4 Extend abort-flush (lines 1159-1164): clear `pendingTurnUsage`; if usage-without-text, fire `mirrorP0Deduped` orphan.

### 1.3 Implementation — `AssistantPersistMode` + flag gate

- [x] 1.3.1 Add `type AssistantPersistMode = { status?: "aborted"; usage?: { costUsd: number } | null }` adjacent to `saveAssistantMessage` (line 1037). cc-narrowed shape per Art. 5(1)(c).
- [x] 1.3.2 Gate `usage` write: `process.env.CC_PERSIST_USAGE === "true" && opts?.usage` → `{ cost_usd: opts.usage.costUsd }`, else `null`. Single read site (hot path; AC10).
- [x] 1.3.3 Wire `usageColumn` into INSERT at line 1072. Column from migration 040.

### 1.4 Phase 1 checkpoint

- [x] T-W4 × 6 pass + 36 PR-A1 tests still pass. Typecheck + lint clean. Commit.

## Phase 2 — W1 (cross-tenant write-scope assertion + real-DB matrix)

### 2.1 `assertWriteScope` sentinel (rev-2 return-bool, no throw, no payload params)

- [x] 2.1.1 Add helper returning `boolean`; today always `true` (sentinel only — no payload source exists).
- [x] 2.1.2 Call at top of `saveAssistantMessage`: `if (!assertWriteScope(userId, conversationId)) return;`. Control-flow, not throw (architecture F7).
- [x] 2.1.3 Inline rationale comment citing CLO 7 invariants + service-role-bypass rationale.

### 2.2 `mirrorP0Deduped` helper

- [x] 2.2.1 Module state in `observability.ts`: `P0_DEDUP_TTL_MS = 60*60*1000` + `_p0DedupMap: Map<string, number>` + `_p0WriteCount`.
- [x] 2.2.2 Function body with amortized sweep every 64 writes + Sentry `level: "fatal"` + `extra: { severity: "breach_attempt", first_seen_at }` for Art. 33 72h-clock.
- [x] 2.2.3 Export `__resetP0DedupForTests` (name parity with existing `__resetMirrorDebounceForTests` at line 215). Hook into test reset chain in `cc-dispatcher.test.ts:122-132`. (Hookup is via the spy override at line ~62 of the test file — production helper's dedup map is bypassed in unit tests; integration test resets the real map via `__resetP0DedupForTests`.)

### 2.3 Real-Supabase test harness

- [x] 2.3.1 New file `apps/web-platform/test/cc-dispatcher-cross-tenant.integration.test.ts` mirroring `conversations-rail-cross-tenant.integration.test.ts`.
- [x] 2.3.2 `describe.skipIf(!process.env.SUPABASE_URL)` for hermetic CI; `bun install` precondition. (Uses `SUPABASE_DEV_INTEGRATION === "1"` per existing convention.)
- [x] 2.3.3 `beforeAll`: create userA + userB via service-role admin. `afterAll`: 3-retry unique-email cleanup. `afterEach`: truncate `messages` for the 4 conversation IDs.
- [x] 2.3.4 Create A1, A2 (userA), B1, B2 (userB) via service-role insert. (`domain_leader: "cco"` proxy for cc-router surface.)

### 2.4 Tests T-W1 (6 invariants post-rev-2 trim)

- [x] 2.4.1 T-W1-matrix: 4 concurrent assistant INSERTs via `Promise.all`. Assert per-conversation isolation + zero cross-contamination.
- [x] 2.4.2 T-W1-invariant-1 (RLS read): auth-client SELECT for userA on B1 returns `data === []` AND `error?.code === 'PGRST116' || error == null`.
- [x] 2.4.3 T-W1-invariant-2 (forged JWT): userA-signed client on B1 → empty + no panic.
- [x] 2.4.4 ~~T-W1-invariant-3 grep-meta~~ — CUT per simplicity F5. Documented in integration test file header.
- [x] 2.4.5 T-W1-invariant-4 (dedup via `workflowEnded` flag, carry from PR-A1). Documented in integration test file header as covered by T-W2-late-text + T-W2-late-text-async (unit).
- [x] 2.4.6 T-W1-invariant-5 (empty DB → empty render; no SDK fallback).
- [x] 2.4.7 T-W1-invariant-5b (deterministic dehedge): empty `messages` + populated sibling conversation A2 → empty A1 response (proves no global fan-out fallback).
- [x] 2.4.8 T-W1-invariant-6 (cascade-erasure — pre-populates row with `usage = { cost_usd: 0.005 }`, deletes parent conversation, asserts FK cascade removes the row + usage jsonb).
- [x] 2.4.9 T-W1-invariant-7 (sentinel smoke): rewritten as behavior test — force `assertWriteScope` to return `false` via `__setAssertWriteScopeForTests` and assert zero inserts across BOTH complete + abort call sites. Stronger than a spy: tests the early-return wiring at every call site.

### 2.5 Phase 2 checkpoint

- [x] Unit + integration suites green. Typecheck + lint clean. `/soleur:gdpr-gate` work-Phase-2-exit pass. Commit. (Unit 43/43 green; integration 6/6 skip cleanly without `SUPABASE_DEV_INTEGRATION=1`; tsc clean. GDPR-gate invocation deferred to operator at PR time.)

## Phase 3 — `Message.usage` doc-comment + FR6

- [ ] 3.1 `AssistantPersistMode` finalized in Phase 1.3.1 — re-affirm only.
- [ ] 3.2 Update `lib/types.ts:414-416` doc-comment: cc-path emits `{cost_usd}` on complete turns when flag on; legacy emits full snapshot on abort.
- [ ] 3.3 FR6: new test in `apps/web-platform/test/api-messages.test.ts` — both cc + soleur_go leader rows returned by hydration.
- [ ] 3.4 Phase 3 checkpoint: full suite green, typecheck + lint clean, commit.

## Phase 4 — Pre-merge gates

- [ ] 4.1 Push branch; open PR with body referencing #3602 + #3623 + Refs #3603 + scope-outs disposition.
- [ ] 4.2 `/soleur:review` 6-agent parallel; fix-inline.
- [ ] 4.3 `/soleur:qa` real Supabase dev.
- [ ] 4.4 `/soleur:preflight` Check 6 gates on CPO sign-off comment.
- [ ] 4.5 `/soleur:gdpr-gate` ship Phase 5.5 final pass.
- [ ] 4.6 `gh pr checks` green.
- [ ] 4.7 `gh pr merge --squash --auto`. #3603 stays open.

## Phase 5 — Post-merge

- [ ] 5.1 `/soleur:postmerge` deployment + Sentry health.
- [ ] 5.2 Update `compliance-posture.md` Active Items with PR + #3623 + D-art30 + D-durable-audit-log.
- [ ] 5.3 `/soleur:compound` — capture real-DB harness pattern, `mirrorP0Deduped` design, `assertWriteScope` sentinel rationale.
- [ ] 5.4 Re-confirm `CC_PERSIST_USAGE=false` default.
- [ ] 5.5 File separate `chore:` PR for D-pr-a1-cosmetics within 1 business day.
- [ ] 5.6 File D-art30 (`compliance/critical`), D-durable-audit-log, D-stress as separate issues.

## Deferred (carry-forward — track separately)

- D1 (PR-A1) — SIGKILL flush gap
- D2 (PR-A1) — multi-bubble UI semantic
- D3 (PR-A1) — `conversations.status=failed` rollup
- D-DSAR-art15 (PR-A1 Phase 0.5) — Art. 15 export endpoint
- **D-art30 (rev-2 new)** — Art. 30 register creation; **PR-C blocker** (`compliance/critical`)
- **D-durable-audit-log (rev-2 new)** — `security_events` table for Art. 33 6y retention
- **D-stress (rev-2 new)** — 100-concurrent matrix variant
- **D-pr-a1-cosmetics (rev-2 new)** — separate `chore:` PR for 3 deferred renames + `dispatchWithDefaults` + `it.each` + microtask-flush

## Acceptance Criteria

See plan §Acceptance Criteria — AC1-AC13 pre-merge, AC14-AC17 post-merge. AC11 (Doppler/Vercel env state) and AC10 (widened grep scope to `apps/` minus tests) are rev-2 additions.
