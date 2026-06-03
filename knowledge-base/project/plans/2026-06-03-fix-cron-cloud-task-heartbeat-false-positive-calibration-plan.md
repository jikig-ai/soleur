---
title: "fix(cron): calibrate cloud-task-heartbeat — never-produced grace + drop strategy-review"
type: fix
date: 2026-06-03
branch: feat-one-shot-cron-heartbeat-false-positive-calibration
lane: cross-domain
tracks: 2714
closes: [4874, 4875]
---

# fix(cron): calibrate cloud-task-heartbeat watchdog — never-produced grace + drop conditional-producer strategy-review

> Spec lacks valid `lane:` (no spec.md) — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

On 2026-06-03 the `cron-cloud-task-heartbeat` Inngest watchdog filed **five** `[cloud-task-silence]` issues (#4873–#4877). Three are **genuine** task failures already fixed by merged PRs and will self-heal on next fire. **Two are false positives** rooted in the watchdog itself — the scope of this PR:

1. **#4875 legal-audit** — a quarterly producer (`0 11 1 1,4,7,10 *`) migrated to Inngest 2026-05-25 that has **never** produced a `scheduled-legal-audit` issue (next real fire 2026-07-01). The watchdog's `daysSince === null → silent: true` branch fires immediately on a never-yet-run task. This regresses documented old-GHA-watchdog behavior ("label exists but never applied → emit warning, do NOT flag silence; correct for newly added tasks" — runbook *When NOT to use* §3). **Fix:** restore a **never-produced grace** — when `daysSince === null` (zero issues ever), report the task as `pending-first-run` (warn to Sentry, do NOT file or keep open a silence issue). legal-audit STAYS in `TASK_INVENTORY`; once it fires 2026-07-01 the normal 95-day threshold applies.

2. **#4874 strategy-review** — a weekly producer (`0 8 * * 1`) whose Sentry monitor `scheduled-strategy-review` checked in OK on 2026-06-01 (it ran). It created no issue because `cron-strategy-review.ts` is a **conditional / idempotent producer**: it walks knowledge-base markdown files and opens an issue ONLY per file that needs review (title-dedup, skips `up_to_date`), so quiet weeks legitimately yield zero issues. Issue-presence is the wrong silence signal for it — same class as the already-excluded conditional/non-producers daily-triage, ux-audit, bug-fixer. **Fix:** remove strategy-review from `TASK_INVENTORY` and document it in the runbook's *Excluded NON-PRODUCERS (do not re-add)* table as a conditional producer whose liveness is covered by its Sentry cron monitor `scheduled-strategy-review`.

**SCOPE GUARD:** the watchdog ONLY. Do **not** modify any `cron-*.ts` task handlers. The three genuine failures (#4873 content-generator, #4876 community-monitor, #4877 roadmap-review) are already fixed by merged **PR #4770** (`CRON_WORKSPACE_ROOT=/workspaces` relocation off the 256 MB `/tmp` tmpfs) and **PR #4870** (community max-turns 50→80), deployed by 2026-06-03 09:48; they self-heal on next scheduled fire via the watchdog's existing recovery branch. Leave them alone.

## Premise Validation

All cited references were checked at plan time and held:

- **#4873–#4877** — all `OPEN`, titled `[cloud-task-silence] <task> silent`. ✓
- **#4770** — MERGED PR, *"fix(cron): relocate ephemeral workspaces off the 256 MB /tmp tmpfs onto /workspaces"*. ✓ (GitHub unified numbering — resolves as a PR via `gh issue view`.)
- **#4870** — MERGED PR, *"fix(cron): raise community-monitor --max-turns 50→80 to fix silent digest dropout"*. ✓
- **#2714** — `CLOSED` tracking issue (*"ops: scheduled-content-generator workflow not firing since 2026-03-24"*). The watchdog's silence-issue body and the runbook cite it as `**Tracks:** #2714` (a *reference*, not a `Closes`); the closed state does not invalidate the reference. PR body uses `references #2714`, never `Closes #2714`.
- **`cron-strategy-review.ts`** — confirmed a conditional producer: returns counts `created / skipped / up_to_date / errors` (`:191`), dedups by title (`:253-270`), creates an issue ONLY inside `for (const filePath of files)` (`:365`) and skips when an open issue already exists (`:441` "Skipping: open issue already exists"). Quiet weeks → zero issues. ✓
- **`warnSilentFallback` exists** at `apps/web-platform/server/observability.ts:241` (warning level, same `SilentFallbackOptions` contract as `reportSilentFallback`). ✓

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Codebase reality | Plan response |
|---|---|---|
| "warn to Sentry via `reportSilentFallback`" | Both `reportSilentFallback` (error level) and `warnSilentFallback` (warning level) exist; observability.ts:241 documents `warnSilentFallback` as "degraded-but-expected paths … worth observing but shouldn't count as an error". | Use **`warnSilentFallback`** for the pending-first-run grace. A never-yet-run task is expected, not an error — an error-level mirror would re-create the false-alarm noise in Sentry that we are removing from GitHub. Note this as a deliberate refinement of the brief in the PR body. |
| "remove strategy-review and keep parity assertions green; check cron-shared.test.ts too" | `cron-shared.test.ts:142` references `scheduled-strategy-review` only as a **fixture label** for the `verifyScheduledIssueCreated` / `resolveOutputAwareOk` helper tests — NOT a `TASK_INVENTORY` parity assertion. `TASK_INVENTORY` is referenced ONLY by `cron-cloud-task-heartbeat.ts` + its own test. | No change to `cron-shared.test.ts` (the fixture label is independent of inventory membership). All inventory parity assertions live in `cron-cloud-task-heartbeat.test.ts` and are updated there. |
| recovery/close path will close #4875 once legal-audit is `not silent` | The never-produced grace makes legal-audit `silent: false` (pending-first-run) but the recovery branch only closes an existing open silence issue when `existing` is found AND `result.silent === false`. With the grace, legal-audit becomes `silent: false`, so the **existing recovery branch will auto-close #4875** on the next watchdog fire. However, strategy-review is removed from `results` entirely, so its recovery branch never runs → **#4874 will NOT auto-close**. | Close **both** #4874 and #4875 explicitly in the post-merge step (deterministic, no dependence on next-fire timing). For #4875 the grace also closes it on next fire — explicit close is idempotent and avoids waiting. |

## User-Brand Impact

**If this lands broken, the user experiences:** the founder's GitHub issue tracker keeps accumulating false `[cloud-task-silence]` alerts (alarm fatigue → real outages get ignored), OR — if the never-produced grace is too broad — a genuinely-dead newly-migrated producer goes unmonitored until its first real fire.

**If this leaks, the user's data is exposed via:** N/A — the watchdog reads/writes only repo issue metadata via an installation-scoped token; no user data, no PII, no regulated surface is touched.

**Brand-survival threshold:** `none` — internal ops observability tuning. No sensitive-path diff (watchdog is `apps/web-platform/server/inngest/functions/`, not auth/schema/API-route/migration). Reason: this change only adjusts which scheduled-task monitor states file a GitHub issue vs. a Sentry warning; it carries no user-facing or data-exposure surface.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — never-produced grace.** In `cron-cloud-task-heartbeat.ts`, when `daysSince === null` AND the task threw no error (zero issues ever found), the result is reported as `pending-first-run`: `silent: false`, with a `warnSilentFallback(...)` call at `op: "task-pending-first-run"`. The issue-handling step files NO new `[cloud-task-silence]` issue for such a task and does NOT comment on / keep open an existing one. (The `catch`-branch `daysSince: null` for an actual API error MUST remain `silent: true` — error ≠ pending.)
- [ ] **AC2 — strategy-review removed.** `TASK_INVENTORY` no longer contains a `strategy-review` entry. The INVENTORY SCOPE comment block in `cron-cloud-task-heartbeat.ts` is updated to add strategy-review to the excluded conditional-producer rationale (cite: conditional/idempotent producer; liveness via Sentry `scheduled-strategy-review`).
- [ ] **AC3 — legal-audit retained.** `TASK_INVENTORY` STILL contains the `legal-audit` entry (`label: "scheduled-legal-audit", maxGapDays: 95`). The grace, not removal, fixes its false positive.
- [ ] **AC4 — tests: cardinality.** `cron-cloud-task-heartbeat.test.ts` `toHaveLength(N)` updated `6 → 5`; the `it.each` table drops the strategy-review row; `legal-audit` row retained; the existing non-producer guard (`daily-triage`, `ux-audit`, `bug-fixer`) extended to also assert `strategy-review` is excluded. The `legal-audit threshold clears the 92-day floor` anchor retained.
- [ ] **AC5 — tests: grace coverage.** New test(s) in `cron-cloud-task-heartbeat.test.ts` assert the never-produced→pending-first-run behavior: a task with **zero** matching issues yields `silent: false` and triggers a `warnSilentFallback` at `op: "task-pending-first-run"`, and the issue-handling step issues NO `POST /repos/{owner}/{repo}/issues`. A control case (an issue older than `maxGapDays`) still yields `silent: true`. A control case (catch-branch API error) still yields `silent: true`. (Drive the handler through mocked Octokit + mocked `step.run`, mirroring the existing test harness; observability spies mirror `cron-shared.test.ts` `warnSilentFallbackSpy`.)
- [ ] **AC6 — source-shape anchors stay green.** The existing registration/source-shape anchor `it.each` blocks (`id`, `cron`, `event`, `scope`, `retries`, Sentry slug, `[cloud-task-silence]`, `#2714`) remain unchanged and pass.
- [ ] **AC7 — cron-shared parity untouched.** `cron-shared.test.ts` passes with no edit; its `scheduled-strategy-review` fixture label is independent of `TASK_INVENTORY` membership. (Run it to confirm.)
- [ ] **AC8 — runbook.** `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md`: (a) strategy-review row removed from the *Task Inventory* table AND the *Threshold Derivation* table; (b) strategy-review added to the *Excluded NON-PRODUCERS (do not re-add)* table with reason "Conditional/idempotent producer: opens an issue only per KB file needing review (title-dedup, skips `up_to_date`); quiet weeks legitimately yield zero issues. Liveness via Sentry monitor `scheduled-strategy-review`."; (c) a note added (near *When NOT to use* §3 / the Excluded-Non-Producers block) documenting the **never-produced grace** for newly-migrated producers, using legal-audit as the worked example (migrated 2026-05-25, first real fire 2026-07-01, `pending-first-run` until then).
- [ ] **AC9 — full suite green.** `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-cloud-task-heartbeat.test.ts test/server/inngest/cron-shared.test.ts` passes; `tsc --noEmit` clean for the touched file.
- [ ] **AC10 — PR body.** Summarizes all 5 alerts #4873–#4877; 3 genuine + already-fixed-and-self-healing (links PR #4770 / #4870); 2 false positives fixed here; `Closes #4874` `Closes #4875`; `references #2714`. Notes the rejected alternative (keep strategy-review but raise threshold) and the `warnSilentFallback`-vs-`reportSilentFallback` refinement.

### Post-merge (operator → automated)

- [ ] **AC11 — close #4874.** `gh issue close 4874 --comment "False positive: strategy-review ran OK 2026-06-01 (Sentry monitor scheduled-strategy-review checked in). cron-strategy-review.ts is a conditional/idempotent producer (issue-per-KB-file-needing-review, title-dedup, skips up_to_date) so quiet weeks yield zero issues — issue-presence is the wrong silence signal. Removed from TASK_INVENTORY and documented as an Excluded NON-PRODUCER (liveness via Sentry). See PR #<this-PR>."` (Automatable via `gh` — `Automation: feasible`.)
- [ ] **AC12 — close #4875.** `gh issue close 4875 --comment "False positive: legal-audit migrated to Inngest 2026-05-25 and has never fired (next real fire 2026-07-01; Sentry monitor scheduled-legal-audit has zero check-ins). The watchdog's daysSince===null branch flagged a never-yet-run task as silent. Restored a never-produced grace: zero-issues-ever → pending-first-run (Sentry warn, no GitHub issue). legal-audit stays in TASK_INVENTORY; the 95-day threshold applies once it fires Jul 1. See PR #<this-PR>."` (The grace also auto-closes #4875 on the next watchdog fire; explicit close is idempotent and avoids waiting.)

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-cloud-task-heartbeat.ts`
  - Add `warnSilentFallback` to the `@/server/observability` import.
  - In `check-task-silence`: when `issues.length === 0`, push `{ ..., silent: false, daysSince: null }` (pending-first-run) instead of `silent: true`, and call `warnSilentFallback(null, { feature: "cron-cloud-task-heartbeat", op: "task-pending-first-run", message: \`Task ${task.name} has never produced a ${task.label} issue — pending first run\`, extra: { fn: "cron-cloud-task-heartbeat", task: task.name } })`. Keep the `catch`-branch push as `silent: true` (real API error, distinct from pending). **Design note:** the discriminator is "did the issues query succeed with zero rows" (pending) vs "did the query throw" (error) — these are already two distinct code paths (the `if (issues.length === 0)` arm vs the `catch`), so no new flag is needed; only the `silent` value on the zero-rows arm changes.
  - In `issue-handling`: the `result.silent` gate already skips issue-filing for `silent: false` results, and the recovery (`else`) branch already closes an existing open silence issue — so a pending-first-run task (now `silent: false`) will neither file nor keep open an issue, and will auto-close any stale one. Verify the recovery comment text reads sensibly for the `daysSince === null` case (it currently interpolates `last issue was ${result.daysSince} days ago` → would render `null days ago`). Guard the recovery-comment detail so `daysSince === null` reads `pending first run (never produced an issue)` instead of `null days ago`.
  - Remove the `strategy-review` entry from `TASK_INVENTORY`.
  - Update the INVENTORY SCOPE comment: add strategy-review to the excluded-non-producer list with the conditional-producer rationale; add a one-line note on the never-produced grace.
- `apps/web-platform/test/server/inngest/cron-cloud-task-heartbeat.test.ts`
  - `toHaveLength(6)` → `toHaveLength(5)`; header comment `6 output-producing tasks` → `5`.
  - Drop the `["strategy-review", "scheduled-strategy-review", 9]` row from the `it.each` value table.
  - Extend the non-producer exclusion guard `it.each(["daily-triage", "ux-audit", "bug-fixer"])` → add `"strategy-review"` (with an inline comment: conditional producer, liveness via Sentry).
  - Add a new `describe` block exercising the handler: never-produced→`silent:false`+`warnSilentFallback(op:"task-pending-first-run")`+no `POST /issues`; control over-threshold→`silent:true`; control catch-branch error→`silent:true`. Mirror the mocked-Octokit + observability-spy harness from `cron-shared.test.ts`.
- `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md`
  - *Task Inventory* table (line ~55): delete the strategy-review row.
  - *Threshold Derivation* table (line ~456): delete the strategy-review row.
  - *Excluded NON-PRODUCERS* table (line ~71): add a strategy-review row with the conditional-producer reason.
  - Add the never-produced-grace note (worked example: legal-audit) — co-locate with *When NOT to use* §3 ("Label exists but has never been applied") and/or the Excluded-Non-Producers block, since the grace IS the in-watchdog implementation of that documented behavior.

## Files to Create

None.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` returned no issue whose body references `cron-cloud-task-heartbeat`.

## Alternative Approaches Considered

| Alternative | Why rejected |
|---|---|
| Keep strategy-review in `TASK_INVENTORY`, just raise `maxGapDays` | A conditional producer can legitimately go many weeks with zero issues (all KB docs `up_to_date`); no finite threshold is correct. Removing it is the right model — same as the existing daily-triage / ux-audit / bug-fixer exclusions. Liveness is already covered by the Sentry monitor. (Noted in PR body per brief.) |
| Remove legal-audit too (treat like strategy-review) | legal-audit IS an unconditional quarterly producer — it WILL create a `scheduled-legal-audit` issue every quarter once it fires. The only problem is the pre-first-fire window. The grace fixes exactly that window and preserves real coverage from 2026-07-01 onward. |
| Use `reportSilentFallback` (error level) for the grace, per the brief's literal wording | A never-yet-run task is expected, not an error; an error-level Sentry mirror re-introduces the alarm-fatigue we are removing. `warnSilentFallback` (warning level) matches the "do NOT flag silence" intent. Refinement documented in PR body. |
| Add a new `pending: boolean` field to `TaskCheckResult` | Unnecessary — the zero-rows arm and the catch arm are already distinct code paths; `silent: false` + a `warnSilentFallback` at the zero-rows arm fully expresses pending-first-run without widening the result shape (YAGNI). |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal ops/observability watchdog tuning. No UI surface (no file under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`), no product/marketing/legal/security/data-model surface. Product/UX Gate not triggered (mechanical UI-surface override did not fire — all edited files are `server/inngest/`, `test/`, runbook markdown).

## Infrastructure (IaC)

N/A — no new infrastructure. Pure code change against the already-provisioned `cron-cloud-task-heartbeat` Inngest function. No new server, secret, vendor, cron, or persistent runtime process. The function is path-filtered into `web-platform-release.yml` and re-registers on merge-to-main (container restart is the deploy mechanism — no operator step).

## Observability

```yaml
liveness_signal:
  what: "cron-cloud-task-heartbeat posts a Sentry cron check-in (slug scheduled-cloud-task-heartbeat, ok=silentCount===0) every run"
  cadence: "daily 09:30 UTC (cron: 30 9 * * *)"
  alert_target: "Sentry cron monitor scheduled-cloud-task-heartbeat (missed/error check-in pages)"
  configured_in: "apps/web-platform/server/inngest/functions/cron-cloud-task-heartbeat.ts (postSentryHeartbeat, step sentry-heartbeat)"
error_reporting:
  destination: "Sentry via warnSilentFallback (op: task-pending-first-run, warning level) for the new grace; reportSilentFallback (error level) retained for actual check-task / issue-handling failures; pino mirror to container stdout / Better Stack"
  fail_loud: "issue-handling and check-task errors still mirror to Sentry; the grace deliberately downgrades pending-first-run from a GitHub issue to a Sentry warning (visible, non-paging)"
failure_modes:
  - mode: "newly-migrated producer never fires (genuine dead cron, not just pre-first-run)"
    detection: "the producer's OWN per-function Sentry cron monitor (e.g. scheduled-legal-audit) shows missed check-ins"
    alert_route: "Sentry cron monitor for that function — orthogonal to this watchdog (which only checks output, not firing)"
  - mode: "grace too broad — masks a real producer that should have output by now"
    detection: "warnSilentFallback op:task-pending-first-run keeps firing every day for a task whose first-fire date has passed; queryable in Sentry by op tag"
    alert_route: "Sentry warning search op:task-pending-first-run; runbook note instructs operator to confirm against the task's own Sentry monitor"
  - mode: "real silence on an established producer (legal-audit after Jul 1 misses a quarter)"
    detection: "daysSince > maxGapDays → silent:true → [cloud-task-silence] GitHub issue filed (unchanged existing path)"
    alert_route: "GitHub issue label cloud-task-silence + runbook"
logs:
  where: "pino structured logs (container stdout → Better Stack) + Sentry; GitHub issues labeled cloud-task-silence for genuine silence"
  retention: "Sentry default; Better Stack per plan; GitHub issues persistent"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-cloud-task-heartbeat.test.ts"
  expected_output: "all tests pass incl. TASK_INVENTORY length 5, strategy-review excluded, never-produced→pending-first-run (silent:false, warnSilentFallback op:task-pending-first-run, no POST /issues)"
```

## Test Scenarios

1. **Never-produced grace (legal-audit case):** Octokit returns `[]` for `scheduled-legal-audit` → result `silent:false, daysSince:null`; `warnSilentFallback` called with `op:"task-pending-first-run"`; issue-handling makes NO `POST /repos/{owner}/{repo}/issues`; if a stale open silence issue exists, it is closed via the recovery branch with a `pending first run` comment (not `null days ago`).
2. **Over-threshold silence (real positive):** Octokit returns one issue `created_at` older than `maxGapDays` → `silent:true`; issue filed/commented as before.
3. **Catch-branch API error:** the issues request throws → `reportSilentFallback` at `op:"check-task"`, `silent:true` (error ≠ pending — must NOT be downgraded to the grace).
4. **strategy-review excluded:** `TASK_INVENTORY.find(t => t.name === "strategy-review")` is `undefined`; length is 5; non-producer guard passes for all four names.
5. **legal-audit retained:** present with `maxGapDays: 95`, clears the 92-day quarterly floor.
6. **cron-shared parity:** `cron-shared.test.ts` passes unedited.

## Sharp Edges

- The brief says "warn via `reportSilentFallback`"; the implementation uses `warnSilentFallback` (warning level) — confirm this in the PR body so a reviewer doesn't read it as a deviation. Both share `SilentFallbackOptions`; only the Sentry level differs (`error` vs `warning`).
- The recovery (`else`) branch interpolates `last issue was ${result.daysSince} days ago` — for a `daysSince === null` pending task this renders `null days ago`. Guard the comment text for the null case (see Files to Edit).
- `cron-shared.test.ts:142` mentions `scheduled-strategy-review` as a FIXTURE label, not an inventory parity assertion — do NOT delete or edit it when removing strategy-review from `TASK_INVENTORY`. (Verified: `TASK_INVENTORY` is imported only by the heartbeat function + its own test.)
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Section is filled above; threshold `none` with a one-sentence reason, no sensitive-path diff.)
- Vitest, not bun: run the suite with `./node_modules/.bin/vitest run <path>` from `apps/web-platform/`. The node project's `include` glob is `test/**/*.test.ts` — the existing test path already matches.

## Test Strategy

- Framework: **vitest** (verified `apps/web-platform/package.json scripts.test === "vitest"`; node project glob `test/**/*.test.ts`). No new dependency.
- Existing harness in `cron-cloud-task-heartbeat.test.ts` (import-time smoke + exported-constant + source-shape anchors) is extended, not replaced.
- Behavioral grace tests drive the exported `cronCloudTaskHeartbeatHandler` with mocked `step.run` (pass-through) + mocked `@octokit/core` `Octokit.request` + observability spies (`warnSilentFallback`, `reportSilentFallback`), mirroring `cron-shared.test.ts`'s `octokitReturning(...)` + `*Spy` pattern.
- Write the failing grace test first (RED), then implement the `silent` flip + `warnSilentFallback` call (GREEN), per `cq-write-failing-tests-before`.
