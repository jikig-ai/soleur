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
- **All 7 already import from `./_cron-shared` and already capture `runStartedAt` via `step.run("run-started-at", …)`** in the correct position (after tier2-defer, before mint-installation-token). So the dedup block slots in directly after that step. Held. (Exact insert lines in the Research Reconciliation table.)
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
| 6 crons have NO in-prompt dedup | Confirmed (content-generator, growth-audit, growth-execution, competitive-analysis, seo-aeo-audit). campaign-calendar has a *per-overdue-item* dedup (STEP 2 (a)/(b)) but no *date-wide* digest dedup. | The handler-side `dedup-digest-check` is the load-bearing guard. Add a defensive fresh-LIST in-prompt rule to each as belt-and-suspenders (handler short-circuit means the prompt rarely runs on a dup day, but a manual same-second race could still reach the spawn). |
| Each cron's prompt title prefix matches its `ensureScheduledAuditIssue` `titlePrefix` | Confirmed for 6 (e.g. roadmap-review prompt files `[Scheduled] Weekly Roadmap Review - <date>`, `titlePrefix: "[Scheduled] Weekly Roadmap Review -"`). campaign-calendar is the exception (titlePrefix has no suffix; producer prompt adds ` (heartbeat)`). | Use each cron's `ensureScheduledAuditIssue` `titlePrefix` as the canonical dedup prefix (single source of truth), + suffix for campaign-calendar. |

**Per-cron insert points & prefixes (all verified by file:line read):**

| cron | label / slug | `run-started-at` line | dedup prefix (= its `ensureScheduledAuditIssue` titlePrefix) | suffix | in-prompt rule |
|---|---|---|---|---|---|
| cron-roadmap-review | scheduled-roadmap-review | 213-216 | `[Scheduled] Weekly Roadmap Review -` | `""` | switch `--search`→LIST (l.164-166) |
| cron-content-generator | scheduled-content-generator | 205-208 | `[Scheduled] Content Generator -` | `""` | add LIST rule |
| cron-growth-audit | scheduled-growth-audit | 165-168 | `[Scheduled] Growth Audit -` | `""` | add LIST rule |
| cron-growth-execution | scheduled-growth-execution | 190-193 | `[Scheduled] Growth Execution -` | `""` | add LIST rule |
| cron-competitive-analysis | scheduled-competitive-analysis | 208-211 | `[Scheduled] Competitive Analysis -` | `""` | add LIST rule |
| cron-seo-aeo-audit | scheduled-seo-aeo-audit | 184-187 | `[Scheduled] SEO/AEO Audit -` | `""` | add LIST rule |
| **cron-campaign-calendar** | scheduled-campaign-calendar | 164-167 | `[Scheduled] Campaign Calendar -` | **` (heartbeat)`** | add LIST rule (matches suffixed title) |

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

`SCHEDULED_DIGEST_TITLE_PREFIX = "[Scheduled] Community Monitor -"` stays exported and is passed explicitly by `cron-community-monitor.ts` at its existing `digestIssueExistsForDate` call site (no behavior change). This is a **type-widening of a cross-consumer signature** → per `hr-type-widening-cross-consumer-grep`, grep all consumers (done: only community-monitor handler + `cron-shared.test.ts` + the 7 new call sites) and update each in the same PR.

**FAILED-stub exclusion for campaign-calendar — verified non-collision.** community-monitor's audit fallback files the *byte-identical* dated title (excluded by body). campaign-calendar's audit fallback files the *bare* `${prefix} ${date}` (no suffix) — which the suffixed matcher already rejects on the title check (`title !== "${prefix} ${date} (heartbeat)"`), so the body check is redundant-but-harmless there. The suffixed producer heartbeat (STEP 2.5) is created-and-immediately-closed but `state: "all"` LIST read still sees it → dedup fires correctly on the second same-day invocation. Confirmed against prod issue bodies: the STEP 2.5 heartbeat body is NOT the `Automated FAILED self-report` shape, so it is correctly classified as a real digest.

## User-Brand Impact

**If this lands broken, the user experiences:** the dedup matcher silently no-ops (especially campaign-calendar if the suffix is wrong) → the cohort keeps double-filing `[Scheduled]` digests — the exact recurring noise this PR removes; OR (the dangerous direction) the matcher over-suppresses → a cron files ZERO digests for a day, blinding the only signal that the eval ran (the #5751 zero-digest hazard).
**If this leaks, the user's data is exposed via:** N/A — no user data, no new secret, no new external surface. Operates only on the bot's own `[Scheduled]` issues in the project repo via the existing probe octokit.
**Brand-survival threshold:** aggregate pattern. The harm is the recurring duplicate-filing pattern across 7 crons, not a single-user incident. (No sensitive-path touch; no `threshold: none` scope-out bullet required.)

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1 — exactly-one-digest invariant per cron.** A parametrized regression test drives each of the 7 real `cron<Name>Handler`s through a fake octokit issue STORE (the `cron-community-monitor-dedup.test.ts` pattern): two serialized same-day invocations → `spawnClaudeEvalSpy` called exactly once → exactly 1 real digest in the store. Asserted via a `realDigestCount()` predicate keyed on the cron's exact `${prefix} ${date}${suffix}` title, NOT a "mock fired" proxy.
- [ ] **AC2 — fail-OPEN.** For each cron, a LIST-read error (`fakeRequest.mockRejectedValueOnce`) → spawn still runs (digest filed), and `reportSilentFallback` called with `op: "digest-dedup-read-failed"`.
- [ ] **AC3 — FAILED-stub exclusion.** For each cron, a pre-existing FAILED-audit stub (same dated title, `Automated FAILED self-report` body) in the store does NOT suppress the real digest (spawn still runs).
- [ ] **AC4 — campaign-calendar suffix match.** `isRealScheduledDigest({title: "[Scheduled] Campaign Calendar - 2026-06-15 (heartbeat)", body:"…"}, "2026-06-15", "[Scheduled] Campaign Calendar -", " (heartbeat)") === true`; and the bare-suffix title (`… 2026-06-15`, no suffix) → `false` (it is the FAILED-audit fallback shape). Both as explicit `cron-shared.test.ts` unit cases.
- [ ] **AC5 — community-monitor unchanged.** Existing `cron-shared.test.ts` `isRealScheduledDigest`/`digestIssueExistsForDate` cases (lines 1145-1278) updated to pass the now-required `titlePrefix` arg explicitly and still pass byte-identically (same true/false outcomes). `cron-community-monitor-dedup.test.ts` and `cron-community-monitor-heartbeat.test.ts` still green.
- [ ] **AC6 — handler wiring present (source anchors).** Each of the 7 per-cron test files gains an anchor assertion that the SUT source contains `step.run("dedup-digest-check"` and `digestIssueExistsForDate(` and (campaign-calendar only) `titleSuffix: " (heartbeat)"` (matching the existing readFileSync source-anchor style in those files).
- [ ] **AC7 — in-prompt rule switched.** `cron-roadmap-review.ts` prompt no longer contains `--search` (`git grep -c "\-\-search" cron-roadmap-review.ts` returns 0); the 6 others contain a fresh `gh issue list --label scheduled-<slug> --state all` dedup rule (source anchor per file).
- [ ] **AC8 — typecheck clean.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [ ] **AC9 — no regression.** `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/` is green for all 7 per-cron tests + `cron-shared.test.ts` + the new dedup test + the 2 community-monitor tests. (Per the #5751 learning Session-Error #1: if `cron-claude-eval-mcp-flags.test.ts` flakes under parallel workers, re-run it in isolation; isolation-green + untouched-by-diff = pre-existing flake, CI is authoritative.)

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
3. In-prompt rule: roadmap-review drop `--search` and widen `--state open`→`all` (AC7); the other 5 add a fresh `gh issue list --label scheduled-<slug> --state all --json number,title,createdAt` DEDUP RULE before the issue-create step.
4. Each per-cron test file: add the AC6 source-anchor assertion(s).

### Phase 3 — Wire cron-campaign-calendar (suffix variant)
1-4 as Phase 2, but the `dedup-digest-check` call passes `titleSuffix: " (heartbeat)"` (canonical prefix `[Scheduled] Campaign Calendar -`). The in-prompt LIST rule must match the suffixed title. The per-cron test asserts `titleSuffix: " (heartbeat)"` is present in source (AC6).

### Phase 4 — Parametrized dedup regression test (the AC1/AC2/AC3 producer)
Create `test/server/inngest/cron-cohort-dedup.test.ts` modeled on `cron-community-monitor-dedup.test.ts` (fake octokit STORE + mocked spawn that writes the cron's exact title into the store + `vi.useFakeTimers` frozen Date). Parametrize over a table of 7 `{handler, label, titlePrefix, titleSuffix, cronName}` rows so the "2 invocations → 1 digest", "fail-OPEN", and "FAILED-stub does not suppress" cases run once per cron through the **real handler** (each cron's wiring is exercised). Keep ONE shared test body, 7 `it.each` rows — not 7 near-identical files.

### Phase 5 — Verify
Run AC8 (`tsc`) and AC9 (`vitest run test/server/inngest/`). Apply the #5751 flake-isolation discipline if an untouched test fails under parallel workers.

## Test Strategy (RED-first)

- **Helper level (`cron-shared.test.ts`):** unit cases for the widened matcher, incl. campaign-calendar suffix true/false + community-monitor byte-identical preservation. RED before Phase 1.2.
- **Handler level (ONE parametrized `cron-cohort-dedup.test.ts`):** the observable invariant — 2 same-day invocations of the **real handler** → 1 digest in a fake store — proven once per cron via `it.each` rows. This exercises each cron's actual `dedup-digest-check` wiring (not a copy-paste of 7 files; not a mock-call-count proxy). Mirrors the precedent dedup test's fake-store substrate.
- **Source-anchor (per-cron files):** lightweight `toContain` assertions matching the existing readFileSync style in those files, so a future silent removal of the dedup block fails CI.
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
- `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` — import + dedup block (after l.216) + drop `--search` (l.164-166).
- `apps/web-platform/server/inngest/functions/cron-content-generator.ts` — import + dedup block (after l.208) + add LIST rule.
- `apps/web-platform/server/inngest/functions/cron-growth-audit.ts` — import + dedup block (after l.168) + add LIST rule.
- `apps/web-platform/server/inngest/functions/cron-growth-execution.ts` — import + dedup block (after l.193) + add LIST rule.
- `apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts` — import + dedup block (after l.211) + add LIST rule.
- `apps/web-platform/server/inngest/functions/cron-seo-aeo-audit.ts` — import + dedup block (after l.187) + add LIST rule.
- `apps/web-platform/server/inngest/functions/cron-campaign-calendar.ts` — import + dedup block (after l.167, suffix `" (heartbeat)"`) + add LIST rule.
- `apps/web-platform/test/server/inngest/cron-shared.test.ts` — widened-signature unit cases (incl. campaign-calendar suffix) + update existing CM cases.
- `apps/web-platform/test/server/inngest/cron-roadmap-review.test.ts` … `cron-campaign-calendar.test.ts` (all 7) — add source-anchor for the dedup block.

## Files to Create
- `apps/web-platform/test/server/inngest/cron-cohort-dedup.test.ts` — ONE parametrized (7-row `it.each`) handler-level dedup regression test through a fake octokit store.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above; threshold = aggregate pattern.)
- **Campaign-calendar suffix is the single most likely silent failure.** The exact-anchor matcher means a wrong/missing suffix → dedup no-ops with NO error (fail-open by design). AC4 (unit true/false) + AC1 (real-handler invariant seeded with the prod title) both guard it. Do not "simplify" the suffix away.
- **Do not collapse the producer dedup and the audit-fallback dedup into one read** (#5751 learning rule 2): they need OPPOSITE predicates over a byte-identical title for the 6 suffix-free crons (producer EXCLUDES the FAILED stub by body; audit COUNTS it). The widened matcher preserves this — the body-exclusion arm is unchanged.
- **Test-runner discovery:** the new test lives at `test/server/inngest/cron-cohort-dedup.test.ts`, which matches vitest's `test/**/*.test.ts` node-project glob (verified `vitest.config.ts:44`). Runner is `vitest` (not bun — `bunfig.toml` ignores `**`).
