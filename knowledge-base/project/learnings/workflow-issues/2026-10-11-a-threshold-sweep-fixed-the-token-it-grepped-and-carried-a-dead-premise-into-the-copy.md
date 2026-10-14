---
title: The threshold-drift sweep fixed the token it grepped for and carried a dead premise into the re-derived copy
date: 2026-10-11
category: engineering
tags: [test-drift, mig-133, reaper-cadence, derivation-premise, prose-carriers, review-panel]
symptoms: [worktree-lease and slot-trigger nightly legs red on correct dev substrate; tests aged heartbeats 121s/200s against a 240s contract; the remediation's own ~5-minute copy derivation rested on a reaper tick retired four months earlier; an agent-facing `~3 min` tool description escaped the literal-shaped census]
module: apps/web-platform integration suites + liveness copy
synced_to: []
component: process
problem_type: workflow_issue
resolution_type: process-correction
root_cause: drift remediation verified the numeric token under repair but never re-checked the premises of the figure it *re-derived*; and the carrier census was keyed on the literal family (`120`-shaped) instead of the contract's *subject* (staleness/reap bounds in prose)
severity: medium
---

# Re-derive the figure's premises, not just the figure; census the contract's subject, not its literal

## Problem

Scheduled `scheduled-integration-suites` run 38133829366 re-failed `worktree-lease`
and `slot-trigger` identically to the dispatch triage. Diagnosis: migration 133
deliberately raised heartbeat liveness 120s→240s (dev correct); the dormant
env-gated tests still asserted 120s (`ageHeartbeat(121)`, `backdateSlotHeartbeat(…, 200)`).
Deterministic test drift, not substrate cruft — so it does not count toward the
dedicated-dev-project revisit trigger in `test/README.md`.

The remediation itself then produced two new same-class defects the review panel
caught:

1. **The `~5 minutes` derivation rested on a dead premise.** I re-derived the
   `CONCURRENCY_CAP` copy as `60 s reaper tick + 240 s threshold ≈ 5 min` — but
   `STUCK_ACTIVE_CHECK_INTERVAL_MS` was widened 60s→300s by #4801 on
   2026-06-02. True passive bound: 240s staleness + up to one 300s poll ≈ ~9min
   (shipped as `~10 minutes`, conservative). The `~3 minutes` copy it replaced
   had already been ~2.3× understated on main since June. Five seats converged
   independently; the plan doc had recorded the wrong derivation as verified.
2. **A `~3 min` prose-shaped carrier escaped the census.** The deepen sweep
   grepped `120`-family literals; `server/conversations-tools.ts`'s agent-facing
   `conversations_list` description ("older than ~3 minutes is wedged … within
   ~3 min") carried the same contract in prose form and was missed — it took a
   review seat's residual probe to find it.

## Working pattern

- **Re-derive a figure's inputs, not just its shape.** The corpus's falsifier
  gate applies to *premises*: before writing `X + Y ≈ Z` from named constants,
  `grep` each constant's live value (here: `STUCK_ACTIVE_CHECK_INTERVAL_MS`
  at `agent-runner.ts` = `300 * 1_000`, one-line falsifier never run at plan
  time).
- **Census the contract's subject, not its literal.** After fixing `120`-shaped
  carriers, grep the *claim family* — `~\s*\d+\s*(min|minutes)`, `within ~`,
  `wedged|stale|reap|lockout` in copy/tool descriptions. A description fed
  verbatim to LLM consumers is a carrier with extra blast radius.
- **Post-fix-round, re-check what the spec docs prescribe.** `tasks.md`
  retained the pre-correction `~5 min` targets — unchecked items a literal
  resume would have executed, reverting the fix. Three seats flagged it.
  When a review round changes a shipped figure, sweep the plan/tasks/spec
  artifacts for the old target in the same commit.
- **The conservative direction for a `within ~N` user promise is up.** 540s
  worst case → `~10 minutes` copy, `~9 min` internal derivation. Under-bounding
  a reclaim window is the harmful direction.

## Session Errors

1. **Re-derived `~5 min` copy on the retired 60s tick** — Recovery: review
   panel (5-seat convergence) + fix commit re-deriving to ~9/~10min.
   **Prevention:** premise-grep every named constant a derivation cites before
   writing the derivation; the plan's own edit table is where it gets frozen.
2. **`~3 min` prose carrier missed by a literal-keyed census** — Recovery:
   fix-round seat probe; description corrected to `~4 min`/`~9 min` with
   `likely wedged` qualifier (last_active lags the heartbeat signal).
   **Prevention:** census the claim family (`~N min` prose shapes on the
   stale/reap/wedge vocabulary) after the literal sweep.
3. **`tasks.md` prescribed superseded targets** — Recovery: corrected to
   shipped values + marked done in the residual fix commit.
   **Prevention:** treat spec docs as carriers of the same figure the code
   ships; grep them for the superseded target before attesting the round.
4. **`gh issue create` denied by milestone/filing-exit gate** — Recovery:
   refiled with `--milestone` + `--label meta/machinery` → #10012.
   **Prevention:** gate working as designed; no action.
5. **`ensure-semgrep.sh` presence-check passes a broken install** —
   seat-discovered workflow gap (a void SAST pass reads as clean).
   **Prevention:** filed #10012 — execute `semgrep --version`, not just
   `command -v`.
6. **Edit `old_string` missed a `≈` (U+2248) in the plan doc** — the AC8
   line edit failed once; recovered via `cat -A` + exact-match retry.
   **Prevention:** when an edit-tool match fails on a doc line, inspect
   bytes (`cat -A`) before rewriting the match — unicode math symbols
   are the usual culprit.

## Related

- `apps/web-platform/test/README.md` dedicated-dev-project revisit trigger —
  this failure class (deterministic drift on a *correct* substrate) is
  explicitly not substrate cruft; diagnosis recorded on issue #9993.
- `concurrency-heartbeat-backoff.test.ts` AC7/AC8 — exact-value pins that
  justified declining the ~180s bracket-leg advisory.
- Corpus precedent: "sweep keyed on the claim's subject, not its phrasing" —
  this session is the prose-carrier instance of that rule.
