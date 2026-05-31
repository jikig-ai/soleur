---
title: "fix: Correct cloud-task-heartbeat TASK_INVENTORY to eliminate false-positive [cloud-task-silence] alerts"
type: fix
date: 2026-05-31
branch: feat-one-shot-heartbeat-inngest-run-history
lane: cross-domain
brand_survival_threshold: none
status: ready
---

# fix: Correct `cloud-task-heartbeat` TASK_INVENTORY to eliminate false-positive `[cloud-task-silence]` alerts

> Spec lacks valid `lane:` (no spec.md for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-05-31
**Sections enhanced:** Research Reconciliation, Risks & Sharp Edges, Precedent-Diff
**Gates passed:** 4.4 precedent-diff (Inngest cron is canonical, already in use — no trigger change), 4.6 User-Brand Impact (threshold `none` + sensitive-path scope-out present), 4.7 Observability (5 fields, non-placeholder, no SSH), 4.8 PAT-shaped (no match)

### Key Improvements
1. **Strict-mode crash is a bash-era artifact — does NOT apply.** The original GHA watchdog crashed under `set -euo pipefail` on `[[ $n -gt $malformed ]]` (learning `2026-04-21-cloud-task-silence-watchdog-pattern.md` §T10, fixed in PR #2716 commit `dc57a601`). The TR9 Inngest migration replaced that with TypeScript `daysSince > task.maxGapDays` (`cron-cloud-task-heartbeat.ts:130`) — no bash, no strict-mode crash. The plan must NOT prescribe a bash numeric guard; a future maintainer should not re-introduce one.
2. **Removing the 3 non-producers is reinforced by the foundational learning.** Learning Prevention #2 states "audit-issue labels are a contract; every scheduled-task prompt must produce a labeled audit issue on BOTH success and failure paths." The 3 non-producers structurally violate this contract (dry-run / PR-only / label-only) — they can never satisfy it, so removing them is the correct resolution. Their liveness is covered by per-function Sentry monitors (#4708), not the heartbeat.
3. **Threshold-doc co-location (learning Prevention #3) is satisfied** by the runbook `## Threshold Derivation` update in Phase 3.

### New Considerations Discovered
- The `daysSince === null → silent: true` branch (`:111-119`) is exactly why a non-producer false-fires forever: a task that never creates a labeled issue always returns 0 issues → `daysSince === null` → `silent: true`. Removing it from the inventory is the only fix (the branch itself is correct for genuine producers that have truly never fired).
- community-monitor 9→3 tightening improves dead-man's-switch latency, consistent with the learning's "conservative threshold defeats the point" note (§Key design choices).

## Overview

The `cron-cloud-task-heartbeat` Inngest function (`apps/web-platform/server/inngest/functions/cron-cloud-task-heartbeat.ts`) watches for "scheduled task went silent" by querying GitHub for the most-recent issue labeled `scheduled-<task>` and comparing its age against a per-task `maxGapDays`. When the gap is exceeded — or **when no such labeled issue has ever existed** — it files a `[cloud-task-silence] <task> silent` issue.

The watchdog is currently producing **false-positive** alerts because its `TASK_INVENTORY` is wrong on two axes:

1. **Non-producer tasks are in the inventory.** Three of the nine listed tasks **never create a `scheduled-<task>`-labeled issue by design**. The heartbeat can never observe an output artifact that is never produced, so it false-fires forever (the `daysSince === null → silent: true` branch at `cron-cloud-task-heartbeat.ts:111-119`). These MUST be removed.
2. **Stale thresholds.** Several producers carry a `maxGapDays` that does not match their real cron cadence. The headline defect: `legal-audit` runs **quarterly** (`0 11 1 1,4,7,10 *`) but has a **9-day** threshold, guaranteeing a silence alert ~9 days into every quarter.

This fix **corrects the inventory and thresholds only**. It explicitly does **NOT** switch to Inngest run-history: the Inngest `/v1/*` introspection API is loopback-gated and unreachable from the app container (proven in **#4708** / HEAD commit `8535bdf1`, which retired the sibling `cron-inngest-cron-watchdog.ts` to a liveness-only beacon for exactly this reason). The "did the cron fire" liveness question is already covered separately by the per-function Sentry cron monitors (see #4708). The heartbeat's job is narrowed to its only valid signal: **"did this output-producing task produce its expected `scheduled-<task>` issue artifact within its cadence window?"**

This is a pure code + test + docs change against an already-provisioned surface. No new infrastructure, no new secrets, no new vendor, no migration.

## Research Reconciliation — Prior Investigation vs. Source

Each claim in the task framing was re-verified by reading the actual cron function source. **No discrepancies found** — source confirms all three flagged non-producers and the quarterly/9-day legal-audit defect.

| Prior claim | Source reality (file:line) | Plan response |
| --- | --- | --- |
| bug-fixer is a non-producer (opens bot-fix PRs, no labeled issue) | **CONFIRMED.** `cron-bug-fixer.ts` — `scheduled-bug-fixer` appears only as the Sentry monitor slug (`:73`) and header comments. Issue creation uses `labels: "${priority},type/bug"` (`:254`) and PR-side `labels: ["bot-fix/review-required"]` (`:376,:419`). No `scheduled-bug-fixer` label is ever attached to a created issue. | **REMOVE** from inventory. |
| ux-audit is a non-producer (`UX_AUDIT_DRY_RUN=true` → Supabase/stdout, no issue) | **CONFIRMED.** `cron-ux-audit.ts:285` hardwires `UX_AUDIT_DRY_RUN: "true"`; prompt (`:80-81`) says dry-run "writes findings to stdout and to" Supabase `ux-audit-artifacts` bucket (`:143,:169`). No `scheduled-ux-audit` issue is created in dry-run. `scheduled-ux-audit` appears only as Sentry slug (`:55`). | **REMOVE** from inventory. |
| daily-triage is a non-producer (labels existing issues only; prompt forbids creating issues/PRs) | **CONFIRMED.** `cron-daily-triage.ts:60` "You must NOT write code, create PRs, or modify any files"; `:112` "NEVER close, reopen, delete, or assign issues. Only add labels and comments"; allowlist `:140` is `Bash(gh issue list/view/edit/comment:*)` only — **no `gh issue create`**. `scheduled-daily-triage` is the Sentry slug only (`:153`). | **REMOVE** from inventory. |
| legal-audit runs quarterly but has a 9-day threshold | **CONFIRMED.** `cron-legal-audit.ts:303` → `{ cron: "0 11 1 1,4,7,10 *" }` (1st of Jan/Apr/Jul/Oct). Inventory threshold is 9. | **FIX** threshold to ~95 days. |

**Producer status of all 9 tasks (empirically verified):**

| Task | Cron (file:line) | Cadence | Producer? | Evidence |
| --- | --- | --- | --- | --- |
| content-generator | `0 10 * * 2,4` (`:235`) | Twice weekly (Tue, Thu) | **YES** | Prompt `:74,:93` create issue with label `scheduled-content-generator` |
| daily-triage | `0 4 * * *` (`:305`) | Daily | **NO** | Labels-only; create forbidden (see above) |
| strategy-review | `0 8 * * 1` (`:669`) | Weekly (Mon) | **YES** | `REVIEW_LABEL = "scheduled-strategy-review"` (`:76`), `octokit POST /issues` with `labels: [REVIEW_LABEL]` (`:477,:482`) |
| legal-audit | `0 11 1 1,4,7,10 *` (`:303`) | Quarterly | **YES** | Prompt creates issue labeled `scheduled-legal-audit` (`:143`) |
| competitive-analysis | `0 9 1 * *` (`:292`) | Monthly (1st) | **YES** | Prompt `:126` create issue with label `scheduled-competitive-analysis` |
| community-monitor | `0 8 * * *` (`:327`) | Daily | **YES** | Prompt `:177` create issue labeled `scheduled-community-monitor` |
| roadmap-review | `0 9 * * 1` (`:316`) | Weekly (Mon) | **YES** | Prompt `:159` create issue labeled `scheduled-roadmap-review` |
| ux-audit | `0 9 1 * *` (`:374`) | Monthly (1st) | **NO** | Dry-run, no issue (see above) |
| bug-fixer | `0 6 * * *` (`:837`) | Daily | **NO** | Bot-fix PRs, no labeled issue (see above) |

**Note — community-monitor was not classified in the task framing.** Source confirms it IS a producer (creates `scheduled-community-monitor` issues, daily cadence with a 24h dedup window). It STAYS in the inventory. Its alert (#4683-class, if any) is not in either the close-list or keep-open-list; no alert issue exists for it in the provided set, so no post-merge action is needed for it.

## Threshold Derivation (remaining 6 producers)

Rule of thumb: `maxGapDays = (max expected inter-issue gap) + slack for a single missed firing`. Cron cadence is the source of truth, not the current value.

| Task | Cadence | Max inter-fire gap | Current | New `maxGapDays` | Rationale |
| --- | --- | --- | --- | --- | --- |
| content-generator | Tue + Thu | 5 days (Thu→Tue) | 4 | **9** | 4 is **too tight** — the Thu→Tue gap alone is 5d, so a single on-time week false-fires. 9 = ~one full cadence cycle (5d max gap) + one missed firing of slack. |
| strategy-review | Weekly (Mon) | 7 days | 9 | **9** (unchanged) | 7d cadence + 2d slack. Correct. |
| legal-audit | Quarterly (1st Jan/Apr/Jul/Oct) | 92 days (Jul→Oct) | 9 | **95** | **Headline defect.** Longest quarter gap is 92 days (92 between Jul 1 and Oct 1); 95 = 92 + 3d slack. |
| competitive-analysis | Monthly (1st) | 31 days | 32 | **40** | 31d max month + slack for one missed firing. 32 is borderline (a single missed month false-fires at day 32); 40 gives one-missed-firing headroom. |
| community-monitor | Daily (24h dedup) | 1 day | 9 | **3** | Daily cadence; 9 is far too loose (a 9-day true outage would go unnoticed for 9 days). 3 = 1d cadence + 2d slack (weekend/transient). Tightening is safe — community-monitor IS a daily producer. |
| roadmap-review | Weekly (Mon) | 7 days | 9 | **9** (unchanged) | 7d cadence + 2d slack. Correct. |

**Decision points for plan-review / deepen-plan:**
- content-generator 4→9 and competitive-analysis 32→40 are *loosenings* that fix false-positives.
- community-monitor 9→3 is a *tightening* that improves true-positive latency. It is in scope as part of "re-derive every producer's threshold against its real cadence" (task requirement #2: "Verify each other producer's threshold against its real cadence too and correct any mismatch"). If a reviewer prefers minimal scope, community-monitor MAY be left at 9 (it does not false-fire), but the plan's default is to correct it.

## Corrected `TASK_INVENTORY` (target state — 6 producers)

```ts
export const TASK_INVENTORY: TaskEntry[] = [
  { name: "content-generator", label: "scheduled-content-generator", maxGapDays: 9 },
  { name: "strategy-review", label: "scheduled-strategy-review", maxGapDays: 9 },
  { name: "legal-audit", label: "scheduled-legal-audit", maxGapDays: 95 },
  { name: "competitive-analysis", label: "scheduled-competitive-analysis", maxGapDays: 40 },
  { name: "community-monitor", label: "scheduled-community-monitor", maxGapDays: 3 },
  { name: "roadmap-review", label: "scheduled-roadmap-review", maxGapDays: 9 },
];
```

Removed (non-producers): `daily-triage`, `ux-audit`, `bug-fixer`.

## User-Brand Impact

- **If this lands broken, the user experiences:** a recurring stream of false `[cloud-task-silence]` issues cluttering the operator's GitHub issue list, training the (solo, non-technical) operator to ignore the watchdog entirely — so a *real* scheduled-task outage gets lost in the noise. This is an internal-ops watchdog; no end-user-facing surface.
- **If this leaks, the user's data/workflow/money is exposed via:** N/A — the change touches no PII, no auth, no schema. The heartbeat reads issue metadata (`created_at`, labels) via an installation-scoped Octokit token and writes only `[cloud-task-silence]` ops issues.
- **Brand-survival threshold:** `none` — internal ops watchdog tuning. **Reason (sensitive-path scope-out):** the diff touches only `apps/web-platform/server/inngest/functions/cron-cloud-task-heartbeat.ts` (a cron watchdog, not an auth/API/schema surface), its test, and a runbook; no regulated-data surface, no auth flow, no migration.

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-cloud-task-heartbeat.ts` — replace `TASK_INVENTORY` (lines 42-52) with the 6-producer corrected inventory + thresholds above. No other logic changes (detection mechanism, issue handling, Sentry heartbeat all unchanged).
- `apps/web-platform/test/server/inngest/cron-cloud-task-heartbeat.test.ts` — update the `TASK_INVENTORY` assertions (lines 37-70) to expect **6** tasks with corrected thresholds; add a **non-producer-exclusion guard** test (assert removed names are absent) and a **cadence-vs-threshold consistency** test. (This file matches the vitest node glob `test/**/*.test.ts` per `apps/web-platform/vitest.config.ts:44`.)
- `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` — document the monitors-only-producers scoping, the Sentry-liveness split (cite #4708), and the loopback-gated `/v1/*` non-use. Natural edit points: `## Task Inventory` (`:42`), `## Threshold Derivation` (`:425`), `## Updating the Watchdog` (`:450`). The loopback-gating is already documented at `:388-395`; add a heartbeat-specific cross-reference.

## Files to Create

None.

## Open Code-Review Overlap

None. (No open `code-review`-labeled issues reference these files. `gh issue list --label code-review --state open` returned no overlap with the three edited paths.)

## Implementation Phases (TDD — failing tests first)

### Phase 0 — Preconditions (verify, do not code)
- Re-confirm the 9 cron schedules and producer status are unchanged on `origin/main` (the source reads above were against the worktree HEAD; cheap re-grep if main has diverged).
- Confirm test runner: `apps/web-platform` uses **vitest** (`vitest.config.ts`), node project glob `test/**/*.test.ts`. Run command: `./node_modules/.bin/vitest run test/server/inngest/cron-cloud-task-heartbeat.test.ts` from `apps/web-platform/` (NOT `bun test` — `apps/web-platform/bunfig.toml` ignores all paths).

### Phase 1 — RED (write failing tests against current code)
Edit `cron-cloud-task-heartbeat.test.ts` to encode the *target* state. Against the current (9-task) inventory these MUST fail:
1. `TASK_INVENTORY` has length **6** (currently 9 → fails).
2. `it.each` table updated to the 6 producers with corrected thresholds (legal-audit 95, content-generator 9, competitive-analysis 40, community-monitor 3, strategy-review 9, roadmap-review 9) → fails on thresholds and on missing/extra rows.
3. **Non-producer exclusion guard:** `for (const removed of ["daily-triage", "ux-audit", "bug-fixer"]) expect(TASK_INVENTORY.find(t => t.name === removed)).toBeUndefined();` → fails (all three present now).
4. **Cadence consistency anchor:** assert `legal-audit` threshold `>= 92` (quarterly floor) to lock the headline defect → fails (currently 9).

Run vitest; capture the failures (RED proof).

### Phase 2 — GREEN (correct the inventory)
Replace `TASK_INVENTORY` (lines 42-52) in `cron-cloud-task-heartbeat.ts` with the 6-producer corrected block. No other code changes. Re-run vitest → all green.

Also run the full `apps/web-platform` vitest suite (or at least the inngest test dir) to confirm no cross-test breakage (e.g., a registry-count test that enumerates monitored tasks).

### Phase 3 — Runbook
Update `cloud-scheduled-tasks.md`:
- (a) State that the heartbeat monitors **only output-producing scheduled tasks**, observed via their `scheduled-<task>` issue label; list the 6 producers and explicitly name the 3 excluded non-producers (daily-triage, ux-audit, bug-fixer) with one-line reasons.
- (b) State that cron **liveness** for ALL tasks is covered separately by the per-function Sentry cron monitors (cite **#4708**); the heartbeat covers only the orthogonal "did it produce output" question.
- (c) State that Inngest `/v1/*` run-history is **loopback-gated** and intentionally NOT used by the heartbeat (cross-reference the existing `:388-395` H9a note).
- Update the `## Threshold Derivation` table to match the new thresholds and the cadence basis.

### Phase 4 — Post-merge follow-up (documented, NOT a code change)
See "Post-merge (operator/automation)" acceptance criteria below.

## Acceptance Criteria

### Pre-merge (PR)
- [x] `TASK_INVENTORY` in `cron-cloud-task-heartbeat.ts` contains exactly 6 entries, all producers, with thresholds: content-generator 9, strategy-review 9, legal-audit 95, competitive-analysis 40, community-monitor 3, roadmap-review 9.
- [x] `daily-triage`, `ux-audit`, `bug-fixer` are absent from `TASK_INVENTORY`.
- [x] Heartbeat detection/issue-handling/Sentry logic is otherwise byte-unchanged (diff is limited to the inventory array + comments).
- [x] Test file asserts 6 entries, the corrected thresholds, the non-producer exclusion guard, and the legal-audit `>= 92` cadence anchor; full inngest vitest dir is green (1154/1154) via `./node_modules/.bin/vitest run`; tsc clean.
- [x] Runbook documents (a) producers-only scoping + the 3 excluded non-producers, (b) Sentry-liveness split citing #4708, (c) loopback-gated `/v1/*` non-use.
- [ ] PR body uses `Ref #2714` (the heartbeat tracking issue), and references #4708 for the liveness/loopback rationale. *(ship phase)*

### Post-merge (operator/automation — `gh` CLI, automatable)
**Automation: feasible via `gh issue close` + `gh issue comment` (Bash). Bake into ship post-merge verification, not operator-manual.**
- [ ] Close the false-positive alerts for removed/corrected tasks, each with a comment referencing this PR and the root cause:
  - `#4691` (bug-fixer) — removed: non-producer (opens bot-fix PRs, never a `scheduled-bug-fixer` issue).
  - `#4690` (ux-audit) — removed: non-producer (`UX_AUDIT_DRY_RUN=true`, writes Supabase/stdout, no issue).
  - `#4685` (daily-triage) — removed: non-producer (labels existing issues only; prompt forbids `gh issue create`).
  - `#4687` (legal-audit) — corrected: silence was solely the 9d-vs-quarterly threshold; now 95d.
- [ ] **Leave OPEN** (genuine cadence drift, separate investigation): `#4689` (roadmap-review), `#4688` (competitive-analysis), `#4686` (strategy-review), `#4684` (content-generator). Do NOT close these.

## Test Scenarios

| # | Scenario | Input / Setup | Expected | Type |
| --- | --- | --- | --- | --- |
| TS1 | Inventory cardinality | Import `TASK_INVENTORY` | length === 6 | unit (RED-first) |
| TS2 | Producer membership | Import `TASK_INVENTORY` | names === {content-generator, strategy-review, legal-audit, competitive-analysis, community-monitor, roadmap-review} | unit (RED-first) |
| TS3 | Non-producer exclusion | Import `TASK_INVENTORY` | daily-triage, ux-audit, bug-fixer all `undefined` via `.find()` | unit (RED-first) |
| TS4 | legal-audit quarterly threshold | Import entry `legal-audit` | `maxGapDays === 95` AND `>= 92` | unit (RED-first) |
| TS5 | content-generator threshold ≥ Thu→Tue gap | Import entry `content-generator` | `maxGapDays === 9` (was 4; 4 < 5d cadence gap → false-fire) | unit (RED-first) |
| TS6 | competitive-analysis monthly threshold | Import entry `competitive-analysis` | `maxGapDays === 40` (≥ 31d month + slack) | unit (RED-first) |
| TS7 | community-monitor daily threshold | Import entry `community-monitor` | `maxGapDays === 3` | unit (RED-first) |
| TS8 | each entry well-formed | Iterate `TASK_INVENTORY` | every entry has non-empty `name`, `label === "scheduled-"+name`, `maxGapDays > 0` | unit |
| TS9 | label-name coupling | Iterate `TASK_INVENTORY` | `t.label === "scheduled-" + t.name` for all 6 (guards future typos) | unit (new) |
| TS10 | registration smoke unchanged | Import `cronCloudTaskHeartbeat` | defined, object (existing test still green) | unit |
| TS11 | source-shape anchors unchanged | Read SUT source | cron `30 9 * * *`, slug, `[cloud-task-silence]`, `#2714` still present | unit (existing) |
| TS12 | full-suite regression | `vitest run` over `apps/web-platform/test/server/inngest/` | no other inngest test references the removed task names | integration |

## Observability

```yaml
liveness_signal:
  what: "Sentry cron check-in posted by step 'sentry-heartbeat' (postSentryHeartbeat, ok=silentCount===0)"
  cadence: "daily at 09:30 UTC (cron '30 9 * * *', unchanged)"
  alert_target: "Sentry cron monitor slug 'scheduled-cloud-task-heartbeat' (missed check-in → Sentry alert)"
  configured_in: "apps/web-platform/server/inngest/functions/cron-cloud-task-heartbeat.ts:31,256-263"
error_reporting:
  destination: "Sentry via reportSilentFallback (per-task check failure + issue-handling failure)"
  fail_loud: "yes — reportSilentFallback mirrors to Sentry per cq-silent-fallback-must-mirror-to-sentry"
failure_modes:
  - mode: "Octokit token mint fails"
    detection: "step.run throws; Inngest run marked failed; Sentry heartbeat not posted → missed check-in alert"
    alert_route: "Sentry cron monitor missed-check-in"
  - mode: "per-task issues GET fails"
    detection: "reportSilentFallback(err) at :135; task pushed as silent:true (conservative)"
    alert_route: "Sentry message 'Failed to check task <name>'"
  - mode: "false-positive silence (the bug being fixed)"
    detection: "[cloud-task-silence] issue volume; post-fix, only genuine producer drift fires"
    alert_route: "GitHub issue label 'cloud-task-silence'"
logs:
  where: "Inngest run logs + pino logger.info('Task is silent — issue filed/commented')"
  retention: "Inngest dashboard run history (host-side); Sentry 90d"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-cloud-task-heartbeat.test.ts"
  expected: "TASK_INVENTORY length 6, thresholds match, non-producer guard passes — all green"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal ops/tooling change (cron watchdog inventory tuning). No user-facing surface, no schema, no auth, no pricing/legal/marketing impact.

## Infrastructure (IaC)

Skipped — no new infrastructure. The change edits only `apps/web-platform/server/...` (already-provisioned runtime), its test, and a runbook. No server, service, cron resource, secret, vendor, or DNS record introduced. The Inngest cron itself is already registered (unchanged `30 9 * * *` trigger).

## Risks & Sharp Edges

- **Removing a task from inventory silences its watchdog entirely.** That is the intended behavior for the 3 non-producers (they have no observable output artifact). Liveness for those 3 crons is still covered by their per-function Sentry cron monitors (#4708) — the heartbeat was never the liveness signal. Document this explicitly so a future maintainer does not "restore" them.
- **community-monitor 9→3 is a tightening, not a loosening.** It will surface a real outage faster but could fire on a transient 2-day gap. 3d (= 1d cadence + 2d slack) absorbs a weekend. If plan-review prefers strictly-minimal scope, leaving it at 9 is acceptable (it does not false-fire) — but the default corrects it per task requirement #2.
- **`Ref #2714`, not `Closes #2714`.** #2714 is the umbrella heartbeat tracking issue; this PR does not resolve it. The post-merge alert closures (#4691/#4690/#4685/#4687) happen via `gh issue close` after merge, not via PR body keywords.
- **Do NOT close #4689/#4688/#4686/#4684.** These are genuine cadence drift for separate investigation (real producers that have actually gone silent). Closing them would hide a real problem.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This section is filled (threshold `none` with sensitive-path scope-out reason).
- **Test path must satisfy the vitest glob.** `apps/web-platform/test/server/inngest/cron-cloud-task-heartbeat.test.ts` matches `test/**/*.test.ts` (node project). Do not co-locate the test next to the source — vitest would skip it. `bun test` will report "filter did not match" (bunfig ignores all) — use `vitest run`.
- **Do NOT re-introduce a bash numeric guard.** The original GHA watchdog crashed under `set -euo pipefail` when `maxGapDays` was non-numeric (`[[ $n -gt $malformed ]]`; learning §T10, PR #2716 `dc57a601`). The current code is TypeScript — `maxGapDays` is a typed `number` literal in `TASK_INVENTORY` and the comparison at `:130` is JS `>`, which cannot crash a step. No regex guard is needed or wanted.
- **Precedent-diff (deepen Phase 4.4):** No new scheduled-job pattern is introduced. `cron-cloud-task-heartbeat` is already an Inngest cron function (canonical per ADR-033); 32 sibling `cron-*.ts` functions exist. The trigger (`30 9 * * *`) is unchanged. This is an in-place data edit to an existing canonical-pattern file — no precedent decision required.
- **Sensitive-path note (deepen Phase 4.6):** the diff path `apps/web-platform/server/inngest/...` matches the preflight sensitive-path regex prefix, but the threshold is `none` with an explicit one-sentence scope-out reason in `## User-Brand Impact` (a cron watchdog is not an auth/API/schema surface). This satisfies preflight Check 6 at ship time.

## References
- `apps/web-platform/server/inngest/functions/cron-cloud-task-heartbeat.ts` (SUT)
- `apps/web-platform/test/server/inngest/cron-cloud-task-heartbeat.test.ts` (test)
- `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` (runbook, esp. `:375` Sentry-liveness, `:388-395` loopback-gating)
- #4708 / commit `8535bdf1` — sibling watchdog retired to liveness-only beacon; loopback-gating proof
- #2714 — heartbeat umbrella tracking issue
- Alert issues: close #4691/#4690/#4685/#4687; keep open #4689/#4688/#4686/#4684
