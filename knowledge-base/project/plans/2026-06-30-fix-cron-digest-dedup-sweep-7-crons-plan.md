---
title: "fix: extend producer-side digest dedup to 7 claude-eval crons (#5786)"
type: fix
issue: 5786
branch: feat-one-shot-5786-cron-digest-dedup-sweep
date: 2026-06-30
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# fix: 7 claude-eval crons double-file their daily `[Scheduled]` digest — extend the #5751 dedup to the cohort

## Enhancement Summary (deepen-plan 2026-06-30)

**Reviewers:** architecture-strategist, spec-flow-analyzer (proxy-vs-invariant lens), code-simplicity-reviewer. No P0 design blockers; approach (widen the shared matcher with per-cron `titlePrefix` + optional `titleSuffix`) confirmed correct over per-cron variants.

**Key improvements folded in:**
1. **P0 (spec-flow) — campaign-calendar cohort-test fidelity.** The `(heartbeat)` suffix is fail-OPEN-on-error (no RED monitor if mis-wired), so the cohort test is the ONLY gate. Pinned: the campaign-calendar `it.each` row's spawn-mock must seed the byte-identical suffixed title, `realDigestCount` must key on it, and a **mutation assertion** must prove dropping `titleSuffix` reds the row. See AC1/AC1c.
2. **P1 (spec-flow) — test-rigor guards** the precedent has that the first draft omitted: per-row LIST-route assertion (`fakeRequest` called `GET …/issues`), partial `importOriginal` mock of `_cron-shared` (so `digestIssueExistsForDate` stays REAL, not stubbed → AC1 can't pass vacuously), and a GREEN-heartbeat skip-path assertion (`?status=ok`, `{ok:true}`, executed `sentry-heartbeat`, NOT `claude-eval`). See AC1b.
3. **P1 (architecture) — campaign-calendar partial-dedup asymmetry.** Its `(heartbeat)` digest is minted ONLY when NEW==0; on an overdue day (NEW>0) no heartbeat digest exists, so the dedup correctly no-ops (fail-OPEN, safe) — a structurally weaker guarantee than the 6 always-create crons. Documented in Design Decision + dedup-block comment; AC1 adds an overdue-day row proving the no-suppression is intentional.
4. **P1 (architecture) — blast-radius completeness.** Named the 2 extra test consumers (`cron-community-monitor-heartbeat.test.ts:68` untyped mock — resilient; `cron-community-monitor-dedup.test.ts:133` inlines the predicate — a drift surface `tsc` can't guard).
5. **Simplicity — scope trim.** Dropped the 6 NEW in-prompt LIST rules (the `concurrency:fn:limit:1` serialization already precludes the same-second race, and #5751's own lesson is "move dedup OUT of the non-deterministic prompt"). Kept ONLY roadmap-review's stale `--search` removal (a real bug). Replaced the redundant AC6 dedup-block source-anchors (subsumed by AC1's behavioral test) with the one anchor AC1 *can't* cover: `concurrency:{scope:"fn",limit:1}` registration presence per cron (the serializer both guards depend on; a fake-store test can't exercise real Inngest concurrency).

**Precedent-diff:** the dedup block is a verbatim mirror of `cron-community-monitor.ts:334-351` (no novel pattern). All 7 handlers share the uniform `cron<Name>Handler({step, logger, attempt, maxAttempts})` signature and the `spawnClaudeEval` substrate, so the parametrized cohort test reuses the precedent's `makeStep`/`invoke`/frozen-clock harness wholesale.

🐛 **Bug sweep.** Follow-up to #5751 (which fixed `cron-community-monitor`). An audit found the same duplicate-digest bug in 7 more crons in the `resolveOutputAwareOk` + `ensureScheduledAuditIssue` per-run-digest cohort: when a cron is invoked more than once for a day (operator manual-trigger + scheduled fire, or doubled delivery), it files **two** `[Scheduled] <Name> - <date>` issues because the only guard is an unreliable in-prompt dedup (stale GitHub **search** index, or none at all).

The reusable helper (`digestIssueExistsForDate` + `isRealScheduledDigest`) and the reference wiring (`cron-community-monitor.ts` pre-spawn `dedup-digest-check` step + the in-prompt `--search`→LIST switch) already exist. This plan extends them to the 7-cron cohort, with **one design choice forced by `cron-campaign-calendar`'s title shape**.

## Overview

For each of the 7 affected crons, add a pre-spawn `step.run("dedup-digest-check", …)` that calls `digestIssueExistsForDate({label: SENTRY_MONITOR_SLUG, titlePrefix, titleSuffix, date: runStartedAt.slice(0,10), cronName})` and early-returns a GREEN sentry heartbeat (skipping the claude spawn) when a real digest already exists for the date. Plus switch the one stale in-prompt `--search` rule (roadmap-review) to the fresh LIST form, and add a fresh-LIST dedup rule to the 6 crons with none.

The work is **uniform** across 6 crons; `cron-campaign-calendar` needs special handling because its producer digest title carries a trailing ` (heartbeat)` suffix that the exact-anchor matcher does not currently accept.

**Brand-survival threshold: `aggregate pattern`.** A duplicate digest is a single-operator paper-cut (per the #5751 learning, the dangerous axis is OVER-suppression → zero digests, which every design choice here biases against). The harm is the *recurring* duplicate-filing pattern across the cohort, not a single-user data incident. No per-PR CPO sign-off required; the section below is still present.

## Premise Validation

Checked (Phase 0.6):

- **#5751 (precedent) is merged.** `digestIssueExistsForDate` + `isRealScheduledDigest` exist at `_cron-shared.ts:739-787`; the reference wiring is `cron-community-monitor.ts:318-351` (a `run-started-at` step, then a `dedup-digest-check` step, early-returning a GREEN heartbeat). Held.
- **All 7 cron files exist** under `apps/web-platform/server/inngest/functions/` and each exports a testable `cron<Name>Handler` function (`cronRoadmapReviewHandler`, …, `cronCampaignCalendarHandler`). Held.
- **All 7 use `scheduledIssueLabel: SENTRY_MONITOR_SLUG`** = their `scheduled-<slug>` (verified per-file: `cron-campaign-calendar.ts:47 = "scheduled-campaign-calendar"`, etc.). Held.
- **All 7 have `concurrency: [{scope:"fn",limit:1}, {scope:"account",key:'"cron-platform"',limit:1}]`** — same serialization the #5751 fix relies on (so invocation #2's fresh LIST read runs after #1's create). Held.
- **All 7 already import from `./_cron-shared` and already capture `runStartedAt` via `step.run("run-started-at", …)`** in the correct position (before mint-installation-token). So the dedup block slots in directly after that step. Held. (Exact insert lines + per-cron tier2-defer presence in the Research Reconciliation table — note roadmap-review has NO `deferIfTier2Cron`, and `TIER2_DEFERRED_CRONS` is empty so the defer is a no-op for all; every handler reaches the dedup block.)
- **ADR corpus (Phase 0.6 mechanism check):** `ADR-033` (Inngest cron → child-process spawn), `ADR-030` (Inngest durable trigger). No ADR governs the digest-dedup mechanism; this is a bug fix that extends an already-merged in-codebase precedent, not a new architectural decision. No ADR rejected this approach.
- **Campaign-calendar caveat resolved by prod evidence (see Research Reconciliation).** `gh issue view 5366/5368/5712/5713` → BOTH prod duplicate digests carry the ` (heartbeat)` suffix. This is decisive for the title-shape design choice below.

No stale premises.

## Research Reconciliation — Spec vs. Codebase

The issue body's "campaign-calendar caveat" is the load-bearing claim. Verified against prod + code:

| Issue claim | Reality (verified) | Plan response |
|---|---|---|
| campaign-calendar digest title is `[Scheduled] Campaign Calendar - <date> (heartbeat)`; "two title shapes coexist on the label" | **Confirmed.** `gh issue view 5366/5368/5712/5713` → all four prod duplicates are `[Scheduled] Campaign Calendar - <date> (heartbeat)`. The bare `[Scheduled] Campaign Calendar - <date>` shape appears ONLY on the handler's FAILED-audit fallback (`ensureScheduledAuditIssue` `titlePrefix`, no suffix). The normal-run always-create artifact is the STEP 2.5 heartbeat issue (prompt line 102), **suffixed**. | `isRealScheduledDigest` exact-anchors on `${prefix} ${date}` → it would NEVER match campaign-calendar's suffixed producer digest → silent no-op. **Generalize the matcher to accept an optional `titleSuffix`**; campaign-calendar passes `" (heartbeat)"`. |
| `isRealScheduledDigest` "already lives in `_cron-shared.ts`, generalized" | Partially. The function exists but is **hardcoded** to `SCHEDULED_DIGEST_TITLE_PREFIX` (community-monitor's constant), takes only `(issue, date)`. | Widen its signature to `(issue, date, titlePrefix, titleSuffix?)`; thread per-cron prefix from each handler. Preserve community-monitor by passing its existing constant explicitly. |
| roadmap-review has a stale `--search` in-prompt rule | Confirmed: `cron-roadmap-review.ts:164-166` uses `gh issue list --label scheduled-roadmap-review --state open --search 'Weekly Roadmap Review in:title'`. The `--search` clause is the stale half. | Switch to `gh issue list --label scheduled-roadmap-review --state all --json number,title,createdAt` (drop `--search`, widen `--state open`→`all`). |
| 6 crons have NO in-prompt dedup | Confirmed (content-generator, growth-audit, growth-execution, competitive-analysis, seo-aeo-audit). campaign-calendar has a *per-overdue-item* dedup (STEP 2 (a)/(b)) but no *date-wide* digest dedup. | The handler-side `dedup-digest-check` is the sole load-bearing guard. Do NOT add new in-prompt rules to these 6 (simplicity review): `concurrency:{scope:"fn",limit:1}` already serializes invocations so #2's handler read sees #1's create; a non-deterministic prompt rule defends a race the serialization precludes and contradicts #5751's "move dedup OUT of the prompt" lesson. |
| Each cron's prompt title prefix matches its `ensureScheduledAuditIssue` `titlePrefix` | Confirmed for 6 (e.g. roadmap-review prompt files `[Scheduled] Weekly Roadmap Review - <date>`, `titlePrefix: "[Scheduled] Weekly Roadmap Review -"`). campaign-calendar is the exception (titlePrefix has no suffix; producer prompt adds ` (heartbeat)`). | Use each cron's `ensureScheduledAuditIssue` `titlePrefix` as the canonical dedup prefix (single source of truth), + suffix for campaign-calendar. |

**Per-cron insert points & prefixes (all verified by file:line read):**

| cron | label / slug | `run-started-at` line | tier2-defer before insert? | dedup prefix (= its `ensureScheduledAuditIssue` titlePrefix) | suffix | in-prompt rule |
|---|---|---|---|---|---|---|
| cron-roadmap-review | scheduled-roadmap-review | 213-216 | NO (no `deferIfTier2Cron`; insert right after run-started-at) | `[Scheduled] Weekly Roadmap Review -` | `""` | switch `--search`→LIST (l.164-166) |
| cron-content-generator | scheduled-content-generator | 205-208 | yes | `[Scheduled] Content Generator -` | `""` | none (handler-only) |
| cron-growth-audit | scheduled-growth-audit | 165-168 | yes | `[Scheduled] Growth Audit -` | `""` | none (handler-only) |
| cron-growth-execution | scheduled-growth-execution | 190-193 | yes | `[Scheduled] Growth Execution -` | `""` | none (handler-only) |
| cron-competitive-analysis | scheduled-competitive-analysis | 208-211 | yes | `[Scheduled] Competitive Analysis -` | `""` | none (handler-only) |
| cron-seo-aeo-audit | scheduled-seo-aeo-audit | 184-187 | yes | `[Scheduled] SEO/AEO Audit -` | `""` | none (handler-only) |
| **cron-campaign-calendar** | scheduled-campaign-calendar | 164-167 | yes | `[Scheduled] Campaign Calendar -` | **` (heartbeat)`** | none (handler-only; suffix matches the STEP 2.5 title) |

Note: `TIER2_DEFERRED_CRONS` is currently EMPTY (`_cron-shared.ts:608`), so `deferIfTier2Cron` is a no-op for all 7 — every handler reaches the dedup block and spawn, which is what AC1 requires. roadmap-review simply has no `deferIfTier2Cron` call at all; the others have one but it returns false.

All 7 already import `postSentryHeartbeat` from `_cron-shared`; all 7 need to add `digestIssueExistsForDate` to their existing import block.

## Design Decision — campaign-calendar title shape (the forced choice)

Two options were considered:

- **(A) Keep `isRealScheduledDigest` exact-anchor; normalize campaign-calendar's prompt** to drop the ` (heartbeat)` suffix so its producer digest becomes the bare `${prefix} ${date}`. — **Rejected.** (1) Two prod-confirmed title shapes already coexist on the live label (suffixed producer + bare FAILED-audit), and historical issues #5366/#5368/#5712/#5713 keep their suffix forever; changing only the *prompt* leaves a mixed corpus the matcher still must handle. (2) The ` (heartbeat)` suffix is a deliberate UX signal (STEP 2.5 mints+closes a heartbeat issue so the watchdog sees activity); dropping it conflates the heartbeat issue with a real refresh. (3) An LLM-prompt change is non-deterministic — the exact behavior the #5751 learning says to move OUT of the prompt.

- **(B) Generalize the matcher to accept a per-cron `titlePrefix` and an optional `titleSuffix`.** — **CHOSEN.** Deterministic, code-side, single-sourced from each cron's `ensureScheduledAuditIssue` titlePrefix. Preserves the three #5751 invariants (positive full-title anchor, FAILED-stub exclusion by body, fail-OPEN on drift). Community-monitor is preserved by passing its existing prefix constant + empty suffix (byte-identical match to today's behavior).

**New signature (preserve community-monitor semantics):**

```ts
// _cron-shared.ts
export function isRealScheduledDigest(
  issue: { title?: string | null; body?: string | null },
  date: string,
  titlePrefix: string,            // NEW — per-cron canonical prefix
  titleSuffix = "",               // NEW — "" for 6 crons + community-monitor; " (heartbeat)" for campaign-calendar
): boolean {
  const title = (issue.title ?? "").trim();
  // Positive anchor: ONLY the exact canonical digest title for THIS date counts.
  // Fail-OPEN on title drift → a duplicate paper-cut, never zero-digest.
  if (title !== `${titlePrefix} ${date}${titleSuffix}`) return false;
  if ((issue.body ?? "").startsWith(AUDIT_SELF_REPORT_BODY_PREFIX)) return false;
  return true;
}

export async function digestIssueExistsForDate(args: {
  label: string;
  date: string;
  cronName: string;
  titlePrefix: string;            // NEW
  titleSuffix?: string;           // NEW (default "")
  octokit?: Awaited<ReturnType<typeof createProbeOctokit>>;
}): Promise<boolean> { /* …same body; pass titlePrefix/titleSuffix into isRealScheduledDigest… */ }
```

`SCHEDULED_DIGEST_TITLE_PREFIX = "[Scheduled] Community Monitor -"` stays exported and is passed explicitly by `cron-community-monitor.ts` at its existing `digestIssueExistsForDate` call site (no behavior change). This is a **type-widening of a cross-consumer signature** → per `hr-type-widening-cross-consumer-grep`, grep all consumers and update each in the same PR. **Full consumer list (verified):** the community-monitor handler call site (`cron-community-monitor.ts:335` — the one production site that breaks on the new required param; `:535` `ensureScheduledAuditIssue` is a different fn, unaffected) + the 7 new call sites + three test files: `cron-shared.test.ts` (~10 call sites, must all carry the new arg in one atomic edit or the suite won't compile), `cron-community-monitor-dedup.test.ts:133` (RESILIENT — inlines its own `realDigestCount` predicate, does NOT call `isRealScheduledDigest`; note this is a *second* hand-maintained copy of the matcher logic, a drift surface `tsc` cannot guard), and `cron-community-monitor-heartbeat.test.ts:68` (RESILIENT — untyped `vi.fn().mockResolvedValue(false)`).

**Campaign-calendar partial-dedup asymmetry (architecture review P1-B — document, do not "fix").** Campaign-calendar's `(heartbeat)` digest is minted ONLY when NEW==0 (`cron-campaign-calendar.ts:100`, prompt "STEP 2.5 — runs when NEW == 0"). On an overdue day (NEW>0), invocation #1 files `[Content] Overdue: …` issues and NO `(heartbeat)` digest at all, so invocation #2's dedup check (anchored on the suffixed title) finds nothing → re-spawns. This is **NOT a regression** — it fails OPEN (the safe direction; the in-prompt STEP 2(b) per-item dedup bounds the duplicate-issue damage), but it means campaign-calendar's producer-side dedup only fires on quiet (NEW==0) days — a structurally weaker guarantee than the 6 always-create crons. Note the contrast with `cron-campaign-calendar.ts:258-267`: the *output-aware heartbeat* counts ANY label artifact (per-overdue, comment-bump, OR heartbeat), while the dedup matcher deliberately counts only the heartbeat-digest one. **This asymmetry MUST be stated in the campaign-calendar dedup-block comment** so a future reader does not assume campaign-calendar has the same exactly-one guarantee as the cohort. AC1d exercises this overdue-day no-suppression path.

**FAILED-stub exclusion for campaign-calendar — verified non-collision.** community-monitor's audit fallback files the *byte-identical* dated title (excluded by body). campaign-calendar's audit fallback files the *bare* `${prefix} ${date}` (no suffix) — which the suffixed matcher already rejects on the title check (`title !== "${prefix} ${date} (heartbeat)"`), so the body check is redundant-but-harmless there. The suffixed producer heartbeat (STEP 2.5) is created-and-immediately-closed but `state: "all"` LIST read still sees it → dedup fires correctly on the second same-day invocation. Confirmed against prod issue bodies: the STEP 2.5 heartbeat body is NOT the `Automated FAILED self-report` shape, so it is correctly classified as a real digest.

## User-Brand Impact

**If this lands broken, the user experiences:** the dedup matcher silently no-ops (especially campaign-calendar if the suffix is wrong) → the cohort keeps double-filing `[Scheduled]` digests — the exact recurring noise this PR removes; OR (the dangerous direction) the matcher over-suppresses → a cron files ZERO digests for a day, blinding the only signal that the eval ran (the #5751 zero-digest hazard).
**If this leaks, the user's data is exposed via:** N/A — no user data, no new secret, no new external surface. Operates only on the bot's own `[Scheduled]` issues in the project repo via the existing probe octokit.
**Brand-survival threshold:** aggregate pattern. The harm is the recurring duplicate-filing pattern across 7 crons, not a single-user incident. (No sensitive-path touch; no `threshold: none` scope-out bullet required.)

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1 — exactly-one-digest invariant per cron.** The parametrized `cron-cohort-dedup.test.ts` drives each of the 7 real `cron<Name>Handler`s through a fake octokit issue STORE (the `cron-community-monitor-dedup.test.ts` pattern, with `_cron-shared` **partial-mocked via `importOriginal`** so `digestIssueExistsForDate` stays REAL — NOT stubbed, or AC1 passes vacuously): two serialized same-day invocations → `spawnClaudeEvalSpy` called exactly once → exactly 1 real digest in the store. Asserted via a `realDigestCount()` predicate keyed on the row's **derived** title `${row.titlePrefix} ${TODAY}${row.titleSuffix}` (NOT a hardcoded constant — a hardcoded seed lets a wrong per-cron prefix pass vacuously). The spawn-mock for each row writes that same row-derived title into the store. Each row also asserts (a) the precedent's LIST-route guard `fakeRequest.mock.calls.some(c => c[0] === "GET /repos/{owner}/{repo}/issues")` (proves the fresh-LIST read ran, not a stale `--search`) and (b) `step.executed` contains `dedup-digest-check` (proves no upstream defer swallowed the run).
- [ ] **AC1b — GREEN-heartbeat skip path per cron.** On the second (deduped) invocation, each row asserts: handler returns `{ok: true}`, `step.executed` contains `sentry-heartbeat`, `step.executed` does NOT contain `claude-eval`, and the posted heartbeat URL is `?status=ok`. **campaign-calendar caveat:** its dedup early-return block must post the heartbeat (via the `postSentryHeartbeat` form the community-monitor early-return uses) BEFORE the return — it must NOT fall through to `verify-output`/`finalizeOutputAwareHeartbeat` (which would false-RED the skip). The test asserts the skip path did NOT execute `verify-output` for campaign-calendar.
- [ ] **AC1c — campaign-calendar suffix is a HANDLER invariant (mutation-proof).** The campaign-calendar cohort row seeds the byte-identical prod title `[Scheduled] Campaign Calendar - <TODAY> (heartbeat)`; `realDigestCount` keys on the suffixed title; and the test is constructed so that if the handler's `digestIssueExistsForDate` call omitted `titleSuffix: " (heartbeat)"`, invocation #2 would compare the suffixed seed against a bare anchor → `false` → spawn twice → `realDigestCount` == 2 → RED. (This promotes the suffix from an AC6 string-proxy to a behavioral handler invariant; AC4 only proves it at the pure-function level.)
- [ ] **AC1d — campaign-calendar overdue-day (NEW>0) no-suppression.** A cohort row where the store contains NO `(heartbeat)` digest (only an `[Content] Overdue: …` issue) → the dedup correctly does NOT fire → spawn runs (fail-OPEN, intentional). Proves the documented partial-dedup asymmetry is intended behavior, not a missed suppression.
- [ ] **AC2 — fail-OPEN.** For each cron row, a LIST-read error (`fakeRequest.mockRejectedValueOnce`) → spawn still runs (digest filed), and `reportSilentFallback` called with `op: "digest-dedup-read-failed"`.
- [ ] **AC3 — FAILED-stub exclusion.** For each cron row, a pre-existing FAILED-audit stub (same dated title, `Automated FAILED self-report` body) in the store does NOT suppress the real digest (spawn still runs).
- [ ] **AC4 — campaign-calendar suffix match (matcher unit).** `isRealScheduledDigest({title: "[Scheduled] Campaign Calendar - 2026-06-15 (heartbeat)", body:"…"}, "2026-06-15", "[Scheduled] Campaign Calendar -", " (heartbeat)") === true`; and the bare title (`… 2026-06-15`, no suffix) → `false` (it is the FAILED-audit fallback shape). Both as explicit `cron-shared.test.ts` unit cases.
- [ ] **AC5 — community-monitor unchanged.** Existing `cron-shared.test.ts` `isRealScheduledDigest`/`digestIssueExistsForDate` cases (lines 1145-1278) updated to pass the now-required `titlePrefix` arg explicitly (a single atomic edit across all ~10 call sites — the suite will not compile until every call carries the new arg) and still pass byte-identically (same true/false outcomes). `cron-community-monitor-dedup.test.ts` (resilient — inlines its own predicate at l.133, does not call `isRealScheduledDigest`) and `cron-community-monitor-heartbeat.test.ts` (resilient — untyped `vi.fn()` mock of `digestIssueExistsForDate` at l.68) still green.
- [ ] **AC6 — concurrency-serialization anchor (the one AC1 can't cover).** Each of the 7 per-cron test files gains a source-anchor assertion that the registration contains `{ scope: "fn", limit: 1 }` (verified present in all 7). This is the serializer BOTH the handler dedup and the cohort test's "invocation #2 sees #1's create" invariant depend on; a fake-store test serializes by calling the handler twice in sequence, so it cannot exercise real Inngest concurrency. campaign-calendar's file additionally anchors `titleSuffix: " (heartbeat)"` as cheap future-deletion insurance. (The generic `dedup-digest-check`/`digestIssueExistsForDate` presence anchors are dropped — subsumed by AC1's strictly-stronger behavioral test.)
- [ ] **AC7 — roadmap-review stale `--search` removed.** `cron-roadmap-review.ts` prompt no longer contains `--search` (`git grep -c "\-\-search" cron-roadmap-review.ts` returns 0) and its DEDUP RULE uses `--state all` (LIST/fresh-index form). No in-prompt rule is added to the other 6 (their handler-side `dedup-digest-check` + `concurrency:fn:limit:1` is the load-bearing guard; adding non-deterministic prompt rules to defend a race the serialization precludes contradicts the #5751 "dedup out of the prompt" lesson).
- [ ] **AC8 — typecheck clean.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0 (the new required `titlePrefix` param errors loudly at any missed call site — the type-widening blast-radius guard).
- [ ] **AC9 — no regression.** `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/` is green for all 7 per-cron tests + `cron-shared.test.ts` + `cron-cohort-dedup.test.ts` + `cron-community-monitor-dedup.test.ts` + `cron-community-monitor-heartbeat.test.ts`. (Per the #5751 learning Session-Error #1: if `cron-claude-eval-mcp-flags.test.ts` flakes under parallel workers, re-run it in isolation; isolation-green + untouched-by-diff = pre-existing flake, CI is authoritative.)

## Implementation Phases

> **Phase order is load-bearing** (`2026-05-10` learning): the contract-changing edit (Phase 1, widen `isRealScheduledDigest`) MUST land before the consumer edits (Phases 2-3) — the RED tests in Phase 1 reference the new signature.

### Phase 1 — Widen the shared matcher (contract change) — RED first
1. Write/extend `cron-shared.test.ts`: add RED cases for the new `(issue, date, titlePrefix, titleSuffix?)` signature — including AC4's campaign-calendar suffix case — and update the existing 6 `isRealScheduledDigest` + 4 `digestIssueExistsForDate` cases to pass `CM_PREFIX` explicitly (AC5).
2. `_cron-shared.ts`: widen `isRealScheduledDigest(issue, date, titlePrefix, titleSuffix="")` and `digestIssueExistsForDate({…, titlePrefix, titleSuffix?})` per the Design Decision signatures. Keep `SCHEDULED_DIGEST_TITLE_PREFIX` exported. Update the doc-comment block (lines 720-752) to describe the per-cron prefix/suffix and the campaign-calendar suffixed-producer case.
3. `cron-community-monitor.ts:335`: pass `titlePrefix: SCHEDULED_DIGEST_TITLE_PREFIX` (and no suffix) at the existing call site. → Phase 1 GREEN.

### Phase 2 — Wire the 6 suffix-free crons
For each of cron-roadmap-review, cron-content-generator, cron-growth-audit, cron-growth-execution, cron-competitive-analysis, cron-seo-aeo-audit (insert points in the Research Reconciliation table):
1. Add `digestIssueExistsForDate` to the `./_cron-shared` import block.
2. After the existing `run-started-at` step, insert the `dedup-digest-check` block (mirror `cron-community-monitor.ts:334-351`): `digestIssueExistsForDate({label: SENTRY_MONITOR_SLUG, titlePrefix: "<this cron's ensureScheduledAuditIssue titlePrefix>", date: runStartedAt.slice(0,10), cronName: "<cron-name>"})`; if true → `postSentryHeartbeat({ok:true,…})` and `return {ok:true}`.
3. In-prompt rule: ONLY roadmap-review — drop `--search` and widen `--state open`→`all` (AC7). The other 5 get NO new in-prompt rule (handler-side dedup is the sole guard; see simplicity review).
4. Each per-cron test file: add the AC6 `concurrency:{scope:"fn",limit:1}` source-anchor assertion.

### Phase 3 — Wire cron-campaign-calendar (suffix variant)
1-2 as Phase 2, but the `dedup-digest-check` call passes `titleSuffix: " (heartbeat)"` (canonical prefix `[Scheduled] Campaign Calendar -`), and the dedup-block comment states the **partial-dedup asymmetry** (fires only on NEW==0 days; see Design Decision). The early-return MUST post `postSentryHeartbeat({ok:true,…})` BEFORE returning — it must NOT fall through to `verify-output`/`finalizeOutputAwareHeartbeat` (AC1b). No in-prompt rule added. The per-cron test asserts both `concurrency:{scope:"fn",limit:1}` and `titleSuffix: " (heartbeat)"` in source (AC6).

### Phase 4 — Parametrized cohort regression test (the AC1/AC1b/AC1c/AC1d/AC2/AC3 producer)
Create `test/server/inngest/cron-cohort-dedup.test.ts` modeled on `cron-community-monitor-dedup.test.ts`: fake octokit STORE + **partial `importOriginal` mock of `_cron-shared`** (keep `digestIssueExistsForDate` REAL — do NOT full-mock it, or AC1 passes vacuously) + per-row spawn mock that writes the **row-derived** title `${row.titlePrefix} ${TODAY}${row.titleSuffix}` into the store + `vi.useFakeTimers({toFake:["Date"]})` frozen Date. Parametrize over 7 `{handler, label, titlePrefix, titleSuffix, cronName}` rows via `it.each`. Per row assert: 2 invocations → spawn once → `realDigestCount()` (keyed on the same row-derived title) == 1; the LIST-route guard fired; `step.executed` contains `dedup-digest-check`; the skip path posts GREEN (AC1b). Add the campaign-calendar-specific rows: AC1c (mutation — dropping `titleSuffix` would red it) and AC1d (overdue-day NEW>0 → no suppression). ONE shared body, parametrized — not 7 files.

### Phase 5 — Verify
Run AC8 (`tsc`) and AC9 (`vitest run test/server/inngest/`). Apply the #5751 flake-isolation discipline if an untouched test fails under parallel workers.

## Research Insights (deepen-plan)

**Precedent-diff gate — the dedup block is a verbatim mirror (no novel pattern).** `cron-community-monitor.ts:334-351` is the canonical form: `step.run("dedup-digest-check", …) → digestIssueExistsForDate(…)`; if true → `step.run("sentry-heartbeat", …)` posting `ok:true` → `return {ok:true}`. All 7 crons get the byte-identical block with their own `label`/`titlePrefix`/`cronName` (+ campaign-calendar's `titleSuffix`). No new pattern is introduced — this is precedent extension, scrutiny is low-risk.

**All 7 handlers share a uniform invocation signature** (verified): `cron<Name>Handler({step, logger, attempt, maxAttempts})`. Combined with the precedent test's `makeStep()` / `invoke()` / frozen-clock (`vi.useFakeTimers({toFake:["Date"]})`) harness and the `vi.mock("@/server/github/probe-octokit", () => ({createProbeOctokit: () => Promise.resolve({request: fakeRequest})}))` injection, the parametrized cohort test reuses ALL of the precedent test's scaffolding — only the 7-row `it.each` table (`{handler, label, titlePrefix, titleSuffix, cronName}`) and the per-cron spawn-writes-the-title mock differ. The spawn fn is uniform (`spawnClaudeEval` via `_cron-claude-eval-substrate`, mocked per precedent).

**roadmap-review's existing in-prompt rule** (`cron-roadmap-review.ts:164-166`) uses a 6-day window + comment-on-existing semantics with `--state open --search 'Weekly Roadmap Review in:title'`. The fix is surgical: drop the `--search` clause and widen `--state open`→`all` so the LIST read hits the fresh primary index (the #5751 root-cause). The 6-day comment-on-existing behavior is orthogonal and preserved; the handler-side dedup is the load-bearing guard regardless.

**Applied learnings:** `2026-06-30-cron-digest-double-file-stale-search-index-and-opposite-dedup-predicates.md` (the #5751 precedent — three reusable rules: LIST-not-search, opposite producer-vs-audit predicates over a byte-identical title, positive full-title anchor fail-open-on-drift — all preserved by this plan). `2026-05-13-npm-workspaces-flag-fails-…` + the tsc-form Sharp Edge (AC8 uses `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`, not `npm run -w`). #5751 Session-Error #1 (parallel-worker flake isolation discipline) folded into AC9.

## Test Strategy (RED-first)

- **Helper level (`cron-shared.test.ts`):** unit cases for the widened matcher, incl. campaign-calendar suffix true/false + community-monitor byte-identical preservation. RED before Phase 1.2.
- **Handler level (ONE parametrized `cron-cohort-dedup.test.ts`):** the observable invariant — 2 same-day invocations of the **real handler** → 1 digest in a fake store — proven once per cron via `it.each` rows. Fidelity guards (spec-flow review): partial `importOriginal` mock keeps `digestIssueExistsForDate` REAL (no vacuous pass); spawn-mock seeds + `realDigestCount` keys on the **row-derived** title (catches a wrong per-cron prefix); per-row LIST-route guard + `dedup-digest-check`-executed assertion; AC1b skip-path-GREEN assertion. campaign-calendar gets the AC1c mutation row + AC1d overdue-day row. This is the SOLE behavioral gate — the per-cron files are anchor-only.
- **Source-anchor (per-cron files):** lightweight `toContain` assertions matching the existing readFileSync style. AC6 anchors `concurrency:{scope:"fn",limit:1}` (the serializer AC1's fake-store test cannot exercise) + campaign-calendar's `titleSuffix`. The generic dedup-block presence anchors are dropped — AC1 is strictly stronger.
- **No-regression:** existing community-monitor dedup/heartbeat tests + the 7 per-cron smoke tests must stay green; the only intended change to community-monitor is the explicit `titlePrefix` arg.

## Risks & Mitigations
- **Type-widening blast radius** (`hr-type-widening-cross-consumer-grep`): `isRealScheduledDigest`/`digestIssueExistsForDate` consumers are community-monitor handler + `cron-shared.test.ts` + the 7 new call sites — all updated in this PR. `tsc --noEmit` (AC8) catches any missed call site (the new required `titlePrefix` param errors loudly).
- **Suffix matcher wrong** → campaign-calendar dedup silent no-op. Mitigated by AC4 (explicit true/false suffix unit case) + AC1 (real-handler 2-invocation invariant pulled from a store seeded with the prod-confirmed suffixed title).
- **Replay stability:** date anchor is `runStartedAt.slice(0,10)` (memoized across the `retries:1` replay) — unchanged from the precedent.
- **Fail-OPEN preserved:** the `digestIssueExistsForDate` catch arm is unchanged; AC2 asserts it per cron.

## Domain Review

**Domains relevant:** none

No cross-domain implications — server-side infrastructure/tooling bug fix on the bot's own scheduled-issue dedup. No UI surface (no files under `components/**`, `app/**/page.tsx`, etc.), no user data, no schema/migration, no new vendor/secret/runtime process.

## Architecture Decision (ADR/C4)

No architectural decision. This is a bug fix that extends an already-merged in-codebase precedent (#5751) — same mechanism, more call sites, one matcher generalization. The cron substrate, the dedup mechanism, and the actors (the bot, the project repo) are unchanged. **C4 completeness check:** the actors/systems involved (the Inngest cron substrate, the GitHub issues store via probe octokit, the `[Scheduled]` digest issues) are pre-existing and already modeled by ADR-033/ADR-030's container view; this PR adds no external human actor, no new external system/vendor, no new data store, and no changed access relationship. No `.c4` edit required. A competent engineer reading the existing ADRs + C4 would NOT be misled about the system after this ships.

## Observability

```yaml
liveness_signal:
  what: each cron posts its Sentry cron heartbeat (ok:true) on the dedup early-return path (postSentryHeartbeat with the cron's SENTRY_MONITOR_SLUG)
  cadence: per cron invocation (existing schedule unchanged)
  alert_target: existing Sentry cron monitors scheduled-<slug> (one per cron, already provisioned)
  configured_in: apps/web-platform/server/inngest/functions/cron-<name>.ts (existing sentry-heartbeat step)
error_reporting:
  destination: Sentry via reportSilentFallback (op "digest-dedup-read-failed") on the fail-OPEN path
  fail_loud: true (mirrored to Sentry; the read failure is visible without SSH, then dedup fails OPEN so no missed digest)
failure_modes:
  - mode: GitHub LIST read throws during dedup
    detection: reportSilentFallback op="digest-dedup-read-failed" in Sentry
    alert_route: Sentry issue stream (non-paging; fail-OPEN means the digest still files)
  - mode: matcher silently over-suppresses (zero digest for a day)
    detection: the cron's output-aware heartbeat goes RED (no scheduled-<slug> issue in the run window) → existing Sentry cron monitor pages
    alert_route: existing scheduled-<slug> Sentry cron monitor
  - mode: matcher silently under-matches (still double-files)
    detection: duplicate [Scheduled] issues visible on the label (the symptom this PR removes); AC1 regression test guards it pre-merge
    alert_route: manual / weekly digest review
logs:
  where: app stdout (Inngest step logs) + Sentry breadcrumbs via reportSilentFallback
  retention: Sentry default project retention
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-cohort-dedup.test.ts
  expected_output: all 7 it.each rows green (2-invocation → 1-digest invariant per cron); NO ssh
```

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` cross-referenced against all 7 cron paths + `_cron-shared` → zero matches.

## Files to Edit
- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — widen `isRealScheduledDigest` + `digestIssueExistsForDate` signatures; update doc-comment.
- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — pass explicit `titlePrefix` at the existing call site (l.335).
- `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` — import + dedup block (after l.216) + drop `--search`, widen `--state open`→`all` (l.164-166).
- `apps/web-platform/server/inngest/functions/cron-content-generator.ts` — import + dedup block (after l.208). No in-prompt rule.
- `apps/web-platform/server/inngest/functions/cron-growth-audit.ts` — import + dedup block (after l.168). No in-prompt rule.
- `apps/web-platform/server/inngest/functions/cron-growth-execution.ts` — import + dedup block (after l.193). No in-prompt rule.
- `apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts` — import + dedup block (after l.211). No in-prompt rule.
- `apps/web-platform/server/inngest/functions/cron-seo-aeo-audit.ts` — import + dedup block (after l.187). No in-prompt rule.
- `apps/web-platform/server/inngest/functions/cron-campaign-calendar.ts` — import + dedup block (after l.167, `titleSuffix: " (heartbeat)"` + asymmetry comment, heartbeat-before-return). No in-prompt rule.
- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — pass explicit `titlePrefix` at `:335` (already listed above).
- `apps/web-platform/test/server/inngest/cron-shared.test.ts` — widened-signature unit cases (incl. AC4 campaign-calendar suffix) + update existing ~10 CM call sites to pass explicit `titlePrefix` (atomic).
- `apps/web-platform/test/server/inngest/cron-roadmap-review.test.ts` … `cron-campaign-calendar.test.ts` (all 7) — add AC6 `concurrency:{scope:"fn",limit:1}` source-anchor (+ `titleSuffix` anchor for campaign-calendar).

## Files to Create
- `apps/web-platform/test/server/inngest/cron-cohort-dedup.test.ts` — ONE parametrized (7-row `it.each`) handler-level dedup regression test through a fake octokit store.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above; threshold = aggregate pattern.)
- **Campaign-calendar suffix is the single most likely silent failure.** The exact-anchor matcher means a wrong/missing suffix → dedup no-ops with NO error, NO RED monitor (fail-open by design — there is no observability backstop, the test is the ONLY gate). AC4 (matcher unit true/false) + AC1c (HANDLER mutation invariant — dropping `titleSuffix` reds the cohort row) both guard it. Do not "simplify" the suffix away.
- **The cohort test is the SOLE behavioral gate** (all 7 per-cron test files are source-anchor/readFileSync only — none invoke the handler). Two fidelity traps: (1) full-mocking `_cron-shared` instead of partial `importOriginal` stubs `digestIssueExistsForDate` → AC1 passes vacuously; keep it REAL. (2) hardcoding the spawn-mock's seeded title instead of deriving it from `${row.titlePrefix} ${TODAY}${row.titleSuffix}` lets a wrong per-cron prefix pass vacuously; derive it, and key `realDigestCount` on the same expression.
- **Campaign-calendar's skip-path heartbeat differs structurally.** Its normal flow uses `finalizeOutputAwareHeartbeat`, not the inline `postSentryHeartbeat` of community-monitor. The dedup early-return block MUST post `postSentryHeartbeat({ok:true})` BEFORE returning — falling through to `verify-output` would false-RED the skip (the #5751 line 330-332 hazard). AC1b asserts the skip path does NOT execute `verify-output` for campaign-calendar.
- **Campaign-calendar dedup is PARTIAL by design** (fires only on NEW==0 days). On an overdue day no `(heartbeat)` digest exists, so the dedup correctly no-ops (fail-OPEN). Document this in the dedup-block comment; AC1d proves it is intended, not a missed suppression.
- **Do not collapse the producer dedup and the audit-fallback dedup into one read** (#5751 learning rule 2): they need OPPOSITE predicates over a byte-identical title for the 6 suffix-free crons (producer EXCLUDES the FAILED stub by body; audit COUNTS it). The widened matcher preserves this — the body-exclusion arm is unchanged.
- **Test-runner discovery:** the new test lives at `test/server/inngest/cron-cohort-dedup.test.ts`, which matches vitest's `test/**/*.test.ts` node-project glob (verified `vitest.config.ts:44`). Runner is `vitest` (not bun — `bunfig.toml` ignores `**`).
