---
title: "fix: cron cohort follow-ups — community-monitor DEDUP RULE removal + cohort-wide digest-title date pin"
date: 2026-07-07
type: fix
branch: feat-one-shot-6143-cron-dedup-cohort-followups
lane: single-domain
brand_survival_threshold: none
issue: 6143
status: draft
---

# 🐛 fix: cron cohort follow-ups — community-monitor DEDUP RULE removal + cohort-wide digest-title date pin

Closes #6143. Two coupled cron follow-ups deferred from PR #6139 (the roadmap-review DEDUP-RULE
removal), both gated on "#6139 validates the always-create pattern in production" — now satisfied
(PR #6139 merged 2026-07-07T08:18 UTC).

**Plan-review panel (2026-07-07):** DHH, Kieran, code-simplicity, architecture-strategist, spec-flow,
cto + a scoped fable advisor. All correctness claims CONFIRMED against code (cohort = 9; injected
title date == dedup key byte-exact via a shared memoized `runStartedAt`; keep-`updated_at` sound).
Findings folded below; two Taste challenges (drop Part 2? / tighten to `created_at`?) recorded in
`knowledge-base/project/specs/feat-one-shot-6143-cron-dedup-cohort-followups/decision-challenges.md`.

## Enhancement Summary

**Deepened on:** 2026-07-07 · **Review depth:** 6-agent plan-review panel (DHH, Kieran,
code-simplicity, architecture-strategist, spec-flow, cto) + a scoped `fable` advisor consult.
Deepen-plan hard gates all pass: 4.4 (Inngest-cron canonical — modifies existing handlers, no new
scheduled workflow) · 4.6 (User-Brand Impact, threshold `none` + scope-out) · 4.7 (Observability
5-field schema, non-placeholder, no-ssh discoverability) · 4.8 (no PAT-shaped var) · 4.9 (no UI
surface). 4.5/4.55 not triggered. Cited PRs/issues resolved live: #6139 MERGED, #5786/#5751/#4468
CLOSED — all attributions accurate.

### Key improvements applied (from the review pass)
1. **Kieran HIGH — three `DEDUP RULE` literals, not one.** `cron-community-monitor.ts` carries the
   token at `:45`, `:229–234`, AND a `#5751` code-comment `:325`. AC1's whole-file grep and AC2's
   `not.toContain` are unpassable unless all three are scrubbed — Files-to-Edit #1 enumerates them.
2. **campaign-calendar refutes the issue's "remove the filter" premise.** STEP 2(b) is a live
   comment-bump output path (`git grep "counts via updated_at"` → only campaign-calendar); the
   `updated_at`/`since` filter stays, the citation re-points to the **stable marker** `counts via
   updated_at` (CTO P2), and a `cron-shared.test.ts` assertion **test-enforces** the coupling.
3. **Cohort is 9, not 7** (two predicates agree; `compound-promote`/`rule-prune` correctly excluded).
   Part 2 pins all 9; the drift-guard is **discovery-based** (`readdirSync` + `digestIssueExistsForDate`
   grep — CTO P1) so cron #10 cannot silently escape.
4. **`injectRunDate` throws on a missing sentinel** (advisor C2a) — a forgotten wiring is loud, not a
   silent literal-`{{RUN_DATE}}` title that defeats dedup+verify.

### New considerations discovered
- **runStartedAt is `step.run`-memoized in all 9 crons** → the injected title date and the dedup key
  read the SAME value, byte-identical across Inngest retries (resolves the advisor's retry-drift concern).
- **community-monitor `YYYY-MM-DD` token collision** (arch/spec-flow): title `:220` (pin) and
  digest-file `:196` share the literal — anchor the edit on the full title string.
- **arch-diagram-sync `:87` "use `<today>` throughout"** competes with the pinned title (spec-flow) →
  reconcile to file-body scope (AC10).
- **Observability `fail_loud` narrowed** (spec-flow): the no-platform FAILED path stays green
  (pre-existing label-vs-title asymmetry) — claim corrected.
- Two Taste challenges (drop Part 2? / per-cron `created_at`?) rejected on code evidence + panel
  consensus; rationale in decision-challenges.md.

## Overview

**Part 1 — `cron-community-monitor` DEDUP-RULE removal (bug fix).** community-monitor carries the
identical prompt-level DEDUP RULE #6139 removed from roadmap-review (`cron-community-monitor.ts:229–234`:
a 24h `gh issue list` → *"post your findings as a comment on the most recent existing issue and exit"*).
Same defect: the comment-and-exit path produces **no dated digest**, and its
`gh issue list --state all` cannot tell a real digest from a FAILED-fallback stub (same
`scheduled-community-monitor` label), so a prior red run can self-perpetuate. **Fix:** delete the
prompt DEDUP RULE block; rely on the already-present code-level **same-date** dedup
(`dedup-digest-check`, `:335–342`, `digestIssueExistsForDate({date: runStartedAt.slice(0,10)})`)
which short-circuits genuine same-day duplicates with a green heartbeat *before* the eval spawns.
community-monitor's prompt step 5 (`:220`) already creates the issue **unconditionally** — there is
NO conditional `## Output` preamble (unlike roadmap-review), so Part 1's prompt edit is a
single-block deletion, no `## Output` rewrite. (spec-flow confirmed: 24h→calendar-date narrowing is a
net improvement — the old 24h rule could `comment-and-exit` the *next day's* cron and skip a whole
day's digest; removing it *reduces* zero-digest risk. The `{scope:"fn",limit:1}` concurrency is now
the sole TOCTOU race-closer for the same-day case — a regression-guard AC pins it.)

**Part 1 coupling — `_cron-shared.ts` citation (comment/test accuracy, NOT a filter change).** The
issue anticipated that after Part 1 "no cron relies on `verifyScheduledIssueCreated`'s
`updated_at`-crediting-of-a-comment path, so the `updated_at`/`since` filter should be
re-evaluated/removed." **The plan refutes this** (Research Reconciliation row 3): `cron-campaign-calendar`
**STEP 2(b)** is a by-design comment-bump output path — *"If found, comment with a heartbeat note.
Do NOT create a new issue"* (`cron-campaign-calendar.ts:96`), documented in its handler as
*"comment-bump via STEP 2(b), both of which `verifyScheduledIssueCreated` counts via updated_at"*
(`:304–314`). `git grep -l "counts via updated_at" cron-*.ts` → only campaign-calendar. So the
`updated_at`/`since` filter is **still load-bearing** — for campaign-calendar, not community-monitor.
**Decision: KEEP the filter unchanged; re-point the stale `_cron-shared.ts:680–688` citation** from
community-monitor's DEDUP RULE to campaign-calendar's comment-bump path — citing the **stable marker
strings** `counts via updated_at` / `Do NOT create a new issue` (NOT the volatile "STEP 2(b)" step
number, which renumbers silently on any prompt reword — CTO P2). **Add a `cron-shared.test.ts`
assertion that campaign-calendar source still carries the comment-bump marker**, so the coupling is
*test-enforced*: if campaign-calendar ever drops STEP 2(b), CI goes red and tells the next engineer
the filter may now be removable — the durable form of the re-evaluation #6143 requested. (Tightening
to `created_at` is rejected — Alternative A1 + decision-challenges.md #2.)

**Part 2 — cohort-wide digest-title date pin (determinism fix).** All 9 crons in the digest cohort
derive their `[Scheduled] … - <date>` **issue-title date from the eval's own container clock** (a
static prompt const with an agent-computed `<today>` / `YYYY-MM-DD`), while the code-level same-date
dedup key is `runStartedAt.slice(0,10)` (host UTC, captured in the handler). Across a UTC-midnight
boundary the two diverge, so `isRealScheduledDigest`'s exact-title match
(`title === \`${titlePrefix} ${date}${titleSuffix}\``) can MISS (→ duplicate) or OVER-suppress. This
is the DHH plan-review #2 finding #6139's precedent-diff gate deferred cohort-wide
(`…/feat-one-shot-roadmap-review-dedup-output-contract/decision-challenges.md`). **Fix (the
non-snowflake path):** a distinctive sentinel `{{RUN_DATE}}` at each cron's issue-title date position
+ a thin shared `injectRunDate(prompt, runStartedAt)` substitution (which **throws** if the sentinel
is absent — advisor C2a) applied at each `spawnClaudeEval` call site. Because the injected date and
the dedup key **both read the same `step.run("run-started-at")`-memoized `runStartedAt`** (replay/retry-stable
— verified in all 9 handlers), they are byte-identical by construction, across Inngest retries.
Prompts stay static, inspectable consts (a full prompt-builder refactor was deferred by #6139's
decision record). Pin the **issue-title date ONLY** — the sole input to the dedup key.

> **Cohort is 9, not 7 (Research Reconciliation row 1 — trust the code).** `git grep -l
> digestIssueExistsForDate apps/web-platform/server/inngest/functions/cron-*.ts` → **9**: the issue/#6139's
> "7" plus **`community-monitor`** (already in the cohort) and **`architecture-diagram-sync`** (omitted
> from #6139's illustrative table). Pinning only 7 leaves the exact snowflakes the issue says to avoid.
> Over-inclusion checked: `compound-promote`/`rule-prune` use `runStartedAt.slice(0,10)` but not
> `digestIssueExistsForDate` → correctly excluded (arch-strategist confirmed).

**Scope:** the two follow-ups only. No change to the heartbeat contract, the dedup predicates, the
Sentry monitors, or any cron's schedule/allowlist/token. Part 2 pins only the issue-title date;
secondary agent-derived dates (digest **file** names, `publish_date` frontmatter, audit-report
paths) stay agent-derived (Non-Goals).

## Research Reconciliation — Issue #6143 vs. Codebase (verified 2026-07-07)

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "All **7** always-create cohort crons derive the title date from the eval's clock." | **9** call `digestIssueExistsForDate` + `date: runStartedAt.slice(0,10)` with an agent-derived title: the 7 + **`community-monitor`** + **`architecture-diagram-sync`**. Two predicates agree (`git grep -l 'digestIssueExistsForDate'` and `'isRealScheduledDigest\|dedup-digest-check'` → same 9). `compound-promote`/`rule-prune` excluded (no dedup title). | Part 2 pins **all 9** (canonical table in §Precedent-Diff). |
| community-monitor's fix mirrors #6139 ("remove DEDUP RULE, adjust `## Output`"). | community-monitor's prompt has **no conditional `## Output`** — step 5 (`:220`) creates unconditionally. The DEDUP RULE is a standalone block (`:229–234`). BUT the literal `DEDUP RULE` also appears at `:45` (SHAPE-DIFF header) and `:325` (a `#5751` code-comment) — Kieran HIGH: a whole-file grep/`SUT_SOURCE.not.toContain` gate fails unless **all three** are scrubbed. | Part 1 deletes `:229–234` AND `:45`, and rewords `:325`'s comment to drop the literal. No `## Output` rewrite. |
| "After Part 1, no cron relies on the `updated_at`-crediting-of-a-comment path → the `updated_at`/`since` filter should be removed." | **FALSE.** `cron-campaign-calendar` STEP 2(b) (`:96`) comments-instead-of-creates; its handler (`:304–314`) documents `verifyScheduledIssueCreated` crediting it via `updated_at`. `git grep -l "counts via updated_at"` → only campaign-calendar. arch-strategist: `updated_at` is a strict superset of `created_at`, and the FAILED-stub false-GREEN is orthogonal to the axis — tightening fixes nothing it doesn't also break. | **KEEP the filter.** Re-point the `:680–688` citation to campaign-calendar via the *stable* `counts via updated_at` marker; add a coupling-invariant test. Reject `created_at` (A1). |
| (implicit) community-monitor's comment-and-exit is "deterministically RED." | Fragile, not deterministic (same as #6139): `verifyScheduledIssueCreated`'s `updated_at` window *credits* a landed dedup-comment green; it reddens only when the comment fails/mis-places. Either way, no dated digest. | Fix unchanged: the defect is "digest presence depends on LLM comment-placement instead of a deterministic dated artifact" + FAILED-self-perpetuation. |

## Root Cause (verified 2026-07-07)

- **Part 1:** `cron-community-monitor.ts:229–234` — the redundant prompt DEDUP RULE (worse than the
  code-level same-date dedup at `:335–342`, which runs before the eval spawns). Stale `DEDUP RULE`
  literals also at `:45` and `:325`.
- **Part 1 coupling:** `_cron-shared.ts:680–688` — the `verifyScheduledIssueCreated` rationale
  (re-pointed to community-monitor by #6139) is stale once community-monitor loses its rule; the true
  remaining `updated_at`-crediting consumer is `cron-campaign-calendar` STEP 2(b).
- **Part 2:** each of the 9 cohort crons lets the eval self-compute the title date while the dedup
  key is `runStartedAt.slice(0,10)` (host UTC) → cross-UTC-midnight skew in `isRealScheduledDigest`.

## Files to Edit

### Part 1 — community-monitor DEDUP-RULE removal + citation re-point

1. **`apps/web-platform/server/inngest/functions/cron-community-monitor.ts`** — scrub **all three**
   `DEDUP RULE` literals (Kieran HIGH): (a) delete the prompt block `:229–234`; (b) delete the
   SHAPE-DIFF header line `:45` (`//   - DEDUP RULE uses 24h window …` — moot once the rule is gone);
   (c) reword the `#5751` code-comment at `:324–328` to drop the two words `DEDUP RULE` (e.g.
   *"…compounded by H-C the stale-search-index in-prompt dedup fallback"*). Leave step 5 (unconditional
   create), the `dedup-digest-check` step, `{scope:"fn",limit:1}` concurrency, and all other guards
   intact. (Part 2 also edits this file — the title pin at `:220`; sequence Part 1 first.)

2. **`apps/web-platform/test/server/inngest/cron-community-monitor.test.ts`** — remove the three
   `it.each` safety-guard rows asserting the removed strings: `"DEDUP RULE"` (`:156–159`),
   `"within the last 24 hours"` (`:160–163`), `"post your findings as a comment on the most recent
   existing issue"` (`:168–171`); update the file-header comment (`:11`). **Add** a regression-guard
   `describe` (mirror `cron-roadmap-review.test.ts:128–144`): `SUT_SOURCE` does NOT contain those
   three strings (`.not.toContain`). Keep the existing unconditional-create prefix anchor
   `"[Scheduled] Community Monitor"` (`:123` — note: **no trailing ` -`**, Kieran). No full-date title
   literal is asserted anywhere for community-monitor, so no title-anchor update is needed here.

3. **`apps/web-platform/server/inngest/functions/_cron-shared.ts` (comment `:680–688`)** — re-point
   the `verifyScheduledIssueCreated` rationale from community-monitor's DEDUP RULE to
   *cron-campaign-calendar's comment-bump path*, citing the **stable markers** `counts via updated_at`
   and `Do NOT create a new issue` (NOT "STEP 2(b)"). No behavior change; the `since`/`updated_at`
   filter (`:715–733`) is untouched.

4. **`apps/web-platform/test/server/inngest/cron-shared.test.ts` (`:230–244`)** — surgically flip the
   "credits a dedup-comment" test's fixture `label` at **`:239` only** (`scheduled-community-monitor`
   → `scheduled-campaign-calendar`; the label is passthrough — many other lines carry the string, do
   NOT blind-replace) and update its rationale comment to campaign-calendar. Assertion unchanged
   (`toBe(true)`). **Add a coupling-invariant assertion** (CTO P2): read `cron-campaign-calendar.ts`
   source and assert it still contains `Do NOT create a new issue` (+ `counts via updated_at`) — if
   that path is ever removed, this test reddens and flags the `updated_at` filter as removable.

### Part 2 — cohort-wide title-date pin (9 crons)

5. **`apps/web-platform/server/inngest/functions/_cron-shared.ts`** — add the sentinel + injector
   (near the digest-dedup helpers, `~:781`):
   ```ts
   /** Platform-injected run-date sentinel. `injectRunDate` replaces it at spawn time with
    *  runStartedAt.slice(0,10) (host UTC) so the digest ISSUE-TITLE date is PINNED to the same value
    *  as the code-level same-date dedup key. Eliminates the cross-UTC-midnight skew between the
    *  eval's agent-derived title date and the key. THROWS if the sentinel is absent so a forgotten
    *  wiring is loud (a literal "{{RUN_DATE}}" title would silently defeat dedup + verify). */
   export const RUN_DATE_SENTINEL = "{{RUN_DATE}}";
   export function injectRunDate(prompt: string, runStartedAt: string): string {
     if (!prompt.includes(RUN_DATE_SENTINEL)) {
       throw new Error(`injectRunDate: prompt is missing ${RUN_DATE_SENTINEL}`);
     }
     return prompt.replaceAll(RUN_DATE_SENTINEL, runStartedAt.slice(0, 10));
   }
   ```
   (`{{RUN_DATE}}` is collision-free — verified: no `{{`/`}}` token exists in any cohort prompt.
   tsconfig is ES2022/esnext so `.replaceAll` is available — already used at `_cron-shared.ts:202`.)

6–14. **The 9 cohort cron handlers** — in each, (i) replace the **issue-title** date placeholder with
   `{{RUN_DATE}}` (title line ONLY — leave file-path/frontmatter dates agent-derived), and (ii) change
   the `spawnClaudeEval({ … prompt: X_PROMPT … })` call site to `prompt: injectRunDate(X_PROMPT, runStartedAt)`.
   Locate every title line + call site with `grep -n '\[Scheduled\]' <file>` / `grep -n 'prompt: .*_PROMPT' <file>`
   at /work — line numbers drift. Per-cron notes (title-line / call-site references as of 2026-07-07):
   - `cron-community-monitor.ts` — title `:220` **`"[Scheduled] Community Monitor - YYYY-MM-DD"`**;
     call site `:417`. **HIGHEST-RISK edit (arch/spec-flow):** `YYYY-MM-DD` also appears at `:196`
     (`YYYY-MM-DD-digest.md`, the digest FILE — must stay agent-derived). Anchor the replace on the
     **full title literal** `[Scheduled] Community Monitor - YYYY-MM-DD`, never the bare `YYYY-MM-DD`.
   - `cron-roadmap-review.ts` — `Title format: [Scheduled] Weekly Roadmap Review - YYYY-MM-DD` (`:164`,
     title-only, no file-path collision); call site `:311`.
   - `cron-architecture-diagram-sync.ts` — title `"${SCHEDULED_ISSUE_TITLE_PREFIX} <today>"` (`:107`);
     call site `:255`. **spec-flow MED:** line `:87` says *"Compute today's date yourself … and use
     that literal value as `<today>` throughout."* Pinning the title while this stands lets the eval
     re-derive/override it. **Reconcile:** narrow `:87` to file-body dates (e.g. *"…use as `<today>`
     for the diagram `last-verified` comments below; the issue title is pre-filled by the platform"*)
     so the pinned title is authoritative. Also the `// last-verified: <today>` diagram comment
     (`:105`) stays agent-derived.
   - `cron-campaign-calendar.ts` — STEP 2.5 title `"[Scheduled] Campaign Calendar - <today> (heartbeat)"`
     (`:103`) → `… - {{RUN_DATE}} (heartbeat)` (**canary: the ` (heartbeat)` suffix is OUTSIDE the
     sentinel** — injected `… - 2026-07-07 (heartbeat)` == `${prefix} ${date}${suffix}`, AC8). Leave
     STEP 2(c) `[Content] Overdue: … (was scheduled for <publish_date>)` (that date is the item's
     publish_date, not today). Call site `:275`. (See Non-Goals: the pin benefits campaign-calendar's
     quiet-day heartbeat path only — its overdue-day path is a documented partial-dedup asymmetry.)
   - `cron-competitive-analysis.ts` — `"[Scheduled] Competitive Analysis - <today's date in YYYY-MM-DD format>"`
     (`:141`) → `… - {{RUN_DATE}}`; call site `:316`.
   - `cron-content-generator.ts` — the **two** title occurrences `"[Scheduled] Content Generator - <today>"`
     (`:107`, `:124`) → `{{RUN_DATE}}` (`.replaceAll` handles both). **Leave** frontmatter
     `publish_date: <today>` (`:115`) agent-derived. Add an inline marker (CTO P3):
     `<!-- {{RUN_DATE}} = platform-pinned title date; the <today> below stays agent-derived -->`. Call site `:303`.
   - `cron-growth-audit.ts` — title `"[Scheduled] Growth Audit - <today>"` (`:105`) → `{{RUN_DATE}}`.
     **Leave** the 4 audit-report `<today>` file paths (`:93–102`) agent-derived; add the CTO-P3 inline
     marker. Call site `:263`.
   - `cron-growth-execution.ts` — `"[Scheduled] Growth Execution - <today>"` (`:131`) → `{{RUN_DATE}}`; call site `:298`.
   - `cron-seo-aeo-audit.ts` — `"[Scheduled] SEO/AEO Audit - <today>"` (`:130`) → `{{RUN_DATE}}`; call site `:292`.

## Files to Create

1. **`apps/web-platform/test/server/inngest/cron-cohort-title-date-pin.test.ts`** — a **discovery-based**
   drift-guard (CTO P1; precedent `test/server/inngest/sentry-monitor-iac-parity.test.ts:53`), plus the
   `injectRunDate` unit test:
   - **Discover the cohort dynamically:** `readdirSync(FUNCTIONS_DIR).filter(f => f.startsWith("cron-")
     && f.endsWith(".ts") && readFileSync(f).includes("digestIssueExistsForDate"))`. Assert the set is
     non-empty (sanity: === 9 today, but derived, not hardcoded). For **each discovered file**, assert
     its source contains `{{RUN_DATE}}` AND `injectRunDate(` at the spawn edge. This fails the moment a
     future digest cron lands without the pin — the only mechanism that makes the convention
     discoverable (a hardcoded 9-path array would let cron #10 escape silently — DHH/CTO).
   - **`injectRunDate` unit test:** multi-sentinel substitution
     (`injectRunDate("a {{RUN_DATE}} b {{RUN_DATE}}", "2026-07-07T23:59:00Z")` === `"a 2026-07-07 b 2026-07-07"`,
     no residual sentinel) AND **throws** when the sentinel is absent. (This is why the unit test is
     not stdlib-testing — it pins the multi-occurrence + throw contract.)

## Implementation Phases

**Phase A — Part 1 (bug fix first).**
- A1. Scrub all three `DEDUP RULE` literals in `cron-community-monitor.ts` (`:45` delete, `:229–234`
  delete, `:324–328` reword).
- A2. Update `cron-community-monitor.test.ts`: remove the 3 stale rows + header; add the regression
  guard (absence of the 3 strings).
- A3. Re-point `_cron-shared.ts:680–688` comment (stable-marker citation → campaign-calendar).
- A4. `cron-shared.test.ts`: surgical fixture-label flip at `:239` + rationale; add the campaign-calendar
  comment-bump coupling-invariant assertion.

**Phase B — Part 2 (injector first, then call sites — contract-before-consumer + `tsc` order).**
- B1. Add `RUN_DATE_SENTINEL` + `injectRunDate` (throw-on-absent) to `_cron-shared.ts`; write the
  Files-to-Create test RED first (`cq-write-failing-tests-before`).
- B2. For each of the 9 crons: title-line sentinel swap + `injectRunDate(...)` call-site wrap; the
  arch-sync `:87` reconciliation + the content-generator/growth-audit inline markers.
- B3. Add `cron-cohort-title-date-pin.test.ts` (discovery-based + unit).

**Phase C — Verify.**
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-community-monitor.test.ts test/server/inngest/cron-community-monitor-dedup.test.ts test/server/inngest/cron-community-monitor-heartbeat.test.ts test/server/inngest/cron-shared.test.ts test/server/inngest/cron-cohort-dedup.test.ts test/server/inngest/cron-cohort-title-date-pin.test.ts test/server/inngest/cron-roadmap-review.test.ts`
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`

## User-Brand Impact

**If this lands broken, the user experiences:** the founder's daily community digest and/or the 8
other scheduled digests stop being filed on manual/duplicate/cross-midnight runs, or a per-cron
Sentry/Better Stack monitor false-pages RED (or goes dark) — eroding trust in the cron observability
signal (an alarm the sole operator learns to ignore, or a missed real failure).

**If this leaks, the user's data / workflow / money is exposed via:** N/A — internal cron prompts + a
shared substitution helper + tests only. No user data moved; no auth/schema/migration/API-route
surface; the evals already run under the operator installation token with an unchanged env allowlist.

**Brand-survival threshold:** none.
- `threshold: none, reason: internal operator-only cron observability contract; no customer data, no auth/schema/migration/API-route surface, single-operator blast radius (edits under apps/web-platform/server/inngest + tests only).`

## Observability

```yaml
liveness_signal:
  what: per-cron Sentry cron-monitor check-in (postSentryHeartbeat), UNCHANGED by this PR. Green on
        every run-day that produces its dated digest; the code-level same-date dedup-skip path also
        posts green without spawning.
  cadence: community-monitor daily "0 8 * * *" UTC; roadmap-review weekly "0 9 * * 1"; the other 7 on
           their existing schedules + each cron's manual-trigger event.
  alert_target: existing per-cron Sentry monitors (scheduled-community-monitor, scheduled-roadmap-review,
                scheduled-campaign-calendar, …) — apps/web-platform/infra/sentry/cron-monitors.tf. No Terraform change.
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (existing; UNCHANGED).
error_reporting:
  destination: Sentry via reportSilentFallback / warnSilentFallback (existing op tags:
               scheduled-output-missing, handler-body-threw, ensure-audit-issue-failed,
               digest-dedup-read-failed). No new op slug; no emit site removed. Part 2's injectRunDate
               throw-on-absent surfaces via the handler's existing catch → handler-body-threw + RED.
  fail_loud: partial — a run that reaches the eval and produces NEITHER a dated digest NOR a FAILED
             issue emits scheduled-output-missing + RED. NOTE (spec-flow MED): the no-platform path
             creates "[Scheduled] Community Monitor - FAILED" and stops; verifyScheduledIssueCreated
             filters by label+updated_at WITHOUT isRealScheduledDigest, so it credits that FAILED
             issue GREEN. This is a pre-existing label-vs-title asymmetry, NOT introduced or changed
             here — flagged so the claim is not overstated.
failure_modes:
  - mode: (Part 1) community-monitor eval reaches the code but files no scheduled-community-monitor issue at all
    detection: resolveOutputAwareOk finds no labeled issue touched in the run window
    alert_route: Sentry op:scheduled-output-missing + monitor RED + FAILED audit issue
  - mode: (Part 1) same-day duplicate (08:00 cron + operator manual-trigger)
    detection: {scope:"fn",limit:1} serializes → 2nd run's dedup-digest-check sees the 1st's issue → skip
    alert_route: green heartbeat, no spawn (healthy) — replaces the removed prompt rule
  - mode: (Part 2) cross-UTC-midnight run
    detection: title now == dedup key by construction (both read the same memoized runStartedAt)
    alert_route: correct same-date dedup; skew class eliminated
  - mode: (Part 2) a cron ships the sentinel but injectRunDate not wired (or a typo'd sentinel)
    detection: cron-cohort-title-date-pin.test.ts (discovery-based) fails at CI; injectRunDate throws at runtime
    alert_route: CI red pre-merge (primary) / handler-body-threw + RED at runtime (belt-and-suspenders)
logs:
  where: Sentry events (durable); pino app logs on the Hetzner host (existing; folded into Sentry extras via formatTailForSentry).
  retention: Sentry default project retention.
discoverability_test:
  command: >-
    curl -s "https://sentry.io/api/0/organizations/<org>/monitors/scheduled-community-monitor/checkins/?per_page=1"
    -H "Authorization: Bearer $SENTRY_API_TOKEN" | jq '.[0].status'
  expected_output: "ok" on the run-day following a successful community digest creation (no ssh required).
```

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 (Part 1 removal, all 3 literals)** — `cron-community-monitor.ts` contains **none** of
      `DEDUP RULE`, `within the last 24 hours`, `post your findings as a comment on the most recent
      existing issue`. Verify:
      `grep -cE 'DEDUP RULE|within the last 24 hours|post your findings as a comment on the most recent existing issue' apps/web-platform/server/inngest/functions/cron-community-monitor.ts` → `0`.
      (Whole-file grep is the correct gate — it fails unless `:45` + `:229–234` + the `:325` comment
      are all scrubbed. Scope to this ONE file; `_cron-shared.ts` legitimately still contains "DEDUP RULE".)
- [x] **AC2 (Part 1 regression guard)** — `cron-community-monitor.test.ts` has a describe block asserting
      `SUT_SOURCE.not.toContain` for each of the three removed strings, and still asserts the prefix
      anchor `"[Scheduled] Community Monitor"` (no trailing dash) is present.
- [x] **AC3 (Part 1 code-level dedup intact)** — the `dedup-digest-check` step +
      `digestIssueExistsForDate({ …, date: runStartedAt.slice(0,10) })` are unchanged.
      Verify: `grep -c 'dedup-digest-check' apps/web-platform/server/inngest/functions/cron-community-monitor.ts` → `≥1`.
- [x] **AC4 (Part 1 concurrency race-closer)** — community-monitor registration still carries
      `{ scope: "fn", limit: 1 }` (now the sole same-day TOCTOU guard). Assert the anchor in
      `cron-community-monitor.test.ts` (mirror `cron-roadmap-review.test.ts:152`).
- [x] **AC5 (Part 1 coupling — filter KEPT + citation + invariant)** — `_cron-shared.ts:680–688` now
      cites campaign-calendar via the stable `counts via updated_at` marker; the `since`/`updated_at`
      filter body (`:715–733`) is unchanged; `cron-shared.test.ts`'s dedup-comment test uses fixture
      label `scheduled-campaign-calendar` and asserts `true`; and a new assertion confirms
      `cron-campaign-calendar.ts` source still contains `Do NOT create a new issue`.
- [x] **AC6 (Part 2 injector)** — `injectRunDate("a {{RUN_DATE}} b {{RUN_DATE}}", "2026-07-07T23:59:00Z")`
      === `"a 2026-07-07 b 2026-07-07"` with no residual sentinel, AND `injectRunDate` **throws** on a
      prompt lacking `{{RUN_DATE}}` (cron-cohort-title-date-pin.test.ts).
- [x] **AC7 (Part 2 cohort completeness, discovery-based)** — the discovery-based drift-guard asserts
      **every** `cron-*.ts` whose source contains `digestIssueExistsForDate` also contains `{{RUN_DATE}}`
      AND `injectRunDate(`. (Cross-check today: three `git grep -l` sets — `digestIssueExistsForDate`,
      `{{RUN_DATE}}`, `injectRunDate(` over `cron-*.ts` — are byte-equal and count 9; `_cron-shared.ts`
      is excluded by the `cron-*.ts` glob.)
- [x] **AC8 (Part 2 campaign-calendar canary)** — for `runStartedAt` `2026-07-07T…`,
      `injectRunDate(CAMPAIGN_CALENDAR_PROMPT, …)` yields the substring
      `[Scheduled] Campaign Calendar - 2026-07-07 (heartbeat)`, equal to `${titlePrefix} ${date}${titleSuffix}`
      with `titleSuffix " (heartbeat)"` (assert in the pin test).
- [x] **AC9 (Part 2 secondary dates untouched)** — the sentinel did not leak into non-title dates:
      `cron-community-monitor.ts` still contains `YYYY-MM-DD-digest.md`; `cron-content-generator.ts`
      still contains `publish_date: <today>`; `cron-growth-audit.ts` still contains `<today>-content-audit.md`.
- [x] **AC10 (Part 2 arch-sync reconciliation)** — `cron-architecture-diagram-sync.ts`'s `:87`-style
      "use `<today>` throughout" instruction no longer applies to the issue title (title is pinned/authoritative).
- [x] **AC11** — targeted suite green:
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-community-monitor.test.ts test/server/inngest/cron-community-monitor-dedup.test.ts test/server/inngest/cron-community-monitor-heartbeat.test.ts test/server/inngest/cron-shared.test.ts test/server/inngest/cron-cohort-dedup.test.ts test/server/inngest/cron-cohort-title-date-pin.test.ts test/server/inngest/cron-roadmap-review.test.ts`.
      (The behavioral `cron-cohort-dedup.test.ts` is a **no-regression sanity run**, not coverage of
      this PR — its mocks ignore prompt text; AC6/AC7/AC8 are the load-bearing Part-2 gates.)
- [x] **AC12** — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [x] **AC13 (scope guard)** — `git diff --name-only` lists only the 9 cron `.ts` files, `_cron-shared.ts`,
      and files under `apps/web-platform/test/server/inngest/`. No cron schedule/allowlist/token or
      Sentry Terraform file modified.

## Open Code-Review Overlap

None. Checked `gh issue list --label code-review --state open` against the planned paths + symbols
(`cron-community-monitor`, `_cron-shared`, `cron-roadmap-review`, `digestIssueExistsForDate`,
`runStartedAt`, title-date, date-pin) — zero matches. Re-run at /work if in doubt.

## Domain Review

**Domains relevant:** none. Infrastructure/tooling change — internal cron prompts + a shared
substitution helper + test-accuracy edits on an already-provisioned observability surface. No
user-facing UI (Files-to-Edit are `.ts` under `server/inngest/` + tests; no `components/**`, no
`app/**/page.tsx` — mechanical UI-surface override did not fire). Product/UX Gate: NONE.

## Architecture Decision (ADR/C4)

**No architectural decision.** Part 1 removes a redundant prompt mechanism (aligns community-monitor
with the #6139 code-level same-date dedup contract; no ADR governs the cron dedup/heartbeat contract
— it lives in code comments + #5751/#5786/#6139 + learnings). Part 2 adds a thin shared substitution
utility — not a substrate, ownership boundary, resolver, or trust boundary. Reverses/extends no ADR.

**No C4 impact.** Read all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):
the model has an `inngest` container (model.c4:174) and a `betterstack` system, but models **no
individual cron handler, per-cron Sentry monitor, dedup/output contract, or prompt element**.
Enumerated the change's actors/systems: **no** new external human actor, **no** new external
system/vendor (Sentry/Better Stack already modeled, unchanged), **no** container/data-store change,
**no** actor↔surface access-relationship change (the evals' operator-token authorization is
unchanged). No `.c4` edit required.

## Non-Goals / Deferrals

- **Tightening `verifyScheduledIssueCreated` to `created_at`** (the issue's implied "remove the
  filter"). Rejected on evidence — campaign-calendar STEP 2(b) still relies on `updated_at`, and
  `updated_at ⊇ created_at` so keeping it only over-credits, never loses a signal; the FAILED-stub
  false-GREEN is orthogonal. Recorded as Alternative A1 + decision-challenges.md #2. No tracking issue.
- **Pinning secondary agent-derived dates** (digest FILE names, `publish_date` frontmatter,
  audit-report paths). Only the issue TITLE feeds the dedup key. arch-strategist Q4: leaving them
  agent-derived introduces a NEW but **cosmetic/traceability-only** divergence direction — for
  `cron-content-generator`, the (now host-UTC) title and the (still container-clock) `publish_date`
  frontmatter can differ across midnight; `publish_date` feeds cron-content-publisher's scheduling
  while the title feeds dedup, so they are independent and the divergence pages nothing. Pinning
  `publish_date` is deliberately excluded to avoid perturbing content-publisher's date parsing.
- **campaign-calendar's overdue-day (NEW>0) path** (spec-flow Q4). The pin hardens only its quiet-day
  STEP 2.5 heartbeat digest (the thing its dedup compares). On overdue days it writes
  `[Content] Overdue:` issues and no heartbeat digest — a documented `PARTIAL-DEDUP ASYMMETRY`
  (fail-OPEN, `cron-campaign-calendar.ts:176–183`), unchanged and out of scope. The "cohort-wide,
  closes the miss/over-suppress window" framing applies to the 8 always-create siblings + campaign-calendar's
  quiet-day path.
- **A full shared prompt-builder / factory refactor.** Deferred by #6139's decision record + the
  prompt-const-with-canary-tests convention. `injectRunDate` is a substitution utility, not a builder.
- **`cron-content-generator` DEDUP RULE** — verified none (create-only). Nothing to fix.

## Test Strategy

- Runner is **vitest** (`apps/web-platform/node_modules/.bin/vitest`); include globs `test/**/*.test.ts`
  (node project) — all targets under `test/server/inngest/` match.
- Source-anchor discipline (`cq-test-fixtures-synthesized-only`): the community-monitor regression
  guard + the pin drift-guard read the real SUT via `readFileSync`. Per
  `2026-05-06-source-grep-drift-guards-break-after-buildtime-interpolation.md`, the pin test asserts
  **sentinel presence in the const + `injectRunDate(` at the call edge** (not a resolved date), so
  build-time substitution doesn't break the guard. The drift-guard is **discovery-based** (readdirSync
  + `digestIssueExistsForDate` grep) so cron #10 cannot silently escape (CTO P1; precedent
  `sentry-monitor-iac-parity.test.ts:53`).
- Behavioral gates stay the existing `cron-cohort-dedup.test.ts` + `cron-community-monitor-dedup.test.ts`
  (their mocks ignore prompt text — a no-regression sanity run, NOT coverage of these edits). Do NOT
  duplicate behavioral handler tests.

## Sharp Edges

- **Three `DEDUP RULE` literals in community-monitor, not one** (Kieran HIGH): `:45`, `:229–234`, and
  the `:325` `#5751` code-comment. AC1's whole-file grep → 0 and AC2's `not.toContain` FAIL unless all
  three are scrubbed. Any rewording that keeps the two words re-breaks both.
- **community-monitor's title (`:220`) and digest-file path (`:196`) share the literal `YYYY-MM-DD`**
  (arch/spec-flow): a naive `replaceAll("YYYY-MM-DD", …)` corrupts the file path and fails AC9. Anchor
  on the full title literal `[Scheduled] Community Monitor - YYYY-MM-DD`. (roadmap-review's `YYYY-MM-DD`
  is title-only — safe.)
- **arch-sync's "use `<today>` throughout" (`:87`) competes with the pinned title** (spec-flow MED):
  scope that instruction to file-body dates / mark the title platform-pinned, or the eval may
  re-derive and defeat the pin.
- **The `{{RUN_DATE}}` sentinel is collision-free** (verified: no `{{` in any cohort prompt) but reads
  like template-engine syntax — the docstring + inline markers (content-generator/growth-audit) note it
  is one `String.replaceAll`, resolved before the eval ever sees it.
- **injectRunDate throws on a missing sentinel** — a forgotten wiring is loud (CI drift-guard first,
  runtime throw → RED second) rather than a silent literal-`{{RUN_DATE}}` title that defeats dedup+verify.
- **Sequence Part 1 before Part 2 in `cron-community-monitor.ts`** (both edit it; non-overlapping
  ranges, so ordering is cosmetic — but Part 1's DEDUP-removal *exposes* the same-date skew that
  Part 2 closes, so they MUST ship in one PR).
- **Label flip is surgical** — `scheduled-community-monitor` appears at many `cron-shared.test.ts`
  lines; flip only the dedup-comment test at `:239`.
- **A plan whose `## User-Brand Impact` is empty or omits the threshold fails deepen-plan Phase 4.6.**
  Filled (threshold none + scope-out reason).
- **Line numbers drift** — locate every title-line, call-site, and test-row edit by grep at /work.

## Precedent-Diff — Cohort Consistency (canonical enumeration, all 9)

`git grep -l digestIssueExistsForDate apps/web-platform/server/inngest/functions/cron-*.ts` = the cohort.
Each title is agent-derived today; Part 2 pins each to `{{RUN_DATE}}` → `injectRunDate`.

| Cron | Title placeholder today | titlePrefix / titleSuffix | Comment-bump output path? | Part 2 |
|---|---|---|---|---|
| cron-roadmap-review | `YYYY-MM-DD` (`:164`) | `[Scheduled] Weekly Roadmap Review -` / `""` | no (removed #6139) | `{{RUN_DATE}}` |
| cron-content-generator | `<today>` ×2 (`:107`,`:124`) | `[Scheduled] Content Generator -` / `""` | no | `{{RUN_DATE}}` ×2 |
| cron-growth-audit | `<today>` (`:105`) | `[Scheduled] Growth Audit -` / `""` | no | `{{RUN_DATE}}` |
| cron-growth-execution | `<today>` (`:131`) | `[Scheduled] Growth Execution -` / `""` | no | `{{RUN_DATE}}` |
| cron-competitive-analysis | `<today's date …>` (`:141`) | `[Scheduled] Competitive Analysis -` / `""` | no | `{{RUN_DATE}}` |
| cron-seo-aeo-audit | `<today>` (`:130`) | `[Scheduled] SEO/AEO Audit -` / `""` | no | `{{RUN_DATE}}` |
| cron-campaign-calendar | `<today>` (`:103`) | `[Scheduled] Campaign Calendar -` / `" (heartbeat)"` | **YES — STEP 2(b) (keeps the updated_at filter)** | `{{RUN_DATE}}` (canary) |
| cron-community-monitor | `YYYY-MM-DD` (`:220`) | `[Scheduled] Community Monitor -` / `""` | was YES (DEDUP RULE — removed here) | `{{RUN_DATE}}` (title/file token collision) |
| **cron-architecture-diagram-sync** | `<today>` (`:107`) | `${SCHEDULED_ISSUE_TITLE_PREFIX}` / `""` | no | `{{RUN_DATE}}` (**#6139's table omitted this — the reconciliation catch; also `:87` reconcile**) |

**Conclusion:** pinning all 9 in one change is the non-snowflake path #6139's decision record
prescribed. campaign-calendar is the sole `updated_at`-filter consumer post-Part-1; arch-diagram-sync
is the cron #6139's illustrative table omitted.

## Alternative Approaches Considered

| Alternative | Decision | Rationale |
|---|---|---|
| **A1. Per-cron `verify` mode (`created_at` for the 8 creators, `updated_at` for campaign-calendar).** | **Rejected (blanket-keep).** | Scoped-advisor proposed it; the eng panel + code converged against: `updated_at ⊇ created_at` (over-credits, never loses a signal), the false-GREEN vector is narrow/pre-existing/shrinking, the FAILED-stub false-GREEN is orthogonal. Instead the plan test-enforces the coupling (campaign-calendar comment-bump assertion). decision-challenges.md #2. |
| **A2. Pin ALL agent-derived dates** (title + files + frontmatter). | **Rejected (title-only).** | Only the title feeds the dedup key; `publish_date` feeds content-publisher; the residual title↔file/frontmatter skew is a cosmetic #5786 paper-cut. |
| **A3. Inline `.replaceAll` at each call site (no shared helper).** | **Rejected (shared `injectRunDate`).** | One tested substitution point (with throw-on-absent + discovery drift-guard) beats 9 hand-rolled sites; not a "prompt-builder." |
| **A4. Split into two PRs.** | **Rejected (one PR).** | #6143 needs both (`Closes #6143`); `cron-community-monitor.ts` is edited by both; Part 1's DEDUP removal exposes the skew Part 2 closes → must ship atomically. |
| **A5. Convert prompts to `buildPrompt(date)` factories.** | **Rejected/deferred.** | Deferred by #6139's decision record + the prompt-const-with-canary convention. |
| **A6. Drop Part 2 entirely (skew is near-unreachable).** | **Rejected (keep).** | DHH's YAGNI challenge; #6143 is the issue that judges the pin worth doing, it is cheap, and eliminates the class. decision-challenges.md #1. |
