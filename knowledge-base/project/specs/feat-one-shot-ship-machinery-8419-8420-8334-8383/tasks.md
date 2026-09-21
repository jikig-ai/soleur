# Tasks — ship machinery cleanup (#8383, #8419/#8438, #8420/#7961, #8334)

Plan: `knowledge-base/project/plans/2026-09-21-refactor-ship-machinery-behind-sync-budget-monitor-pir-plan.md`

## Phase 1 — Monitor liveness (#8420, #7961)

- [ ] 1.1 RED: add cases 31–35 plus `expire_task`/`fail_task` helpers (measured `queue-operation` shape) to `.claude/hooks/monitor-supersede-guard.test.sh`; `MIN_CASES=35`
- [ ] 1.2 GREEN: `task_is_terminal()` with `grep -cE '<status>(completed|failed)</status>|<event>\[Monitor (expired after [0-9]+|timed out)'`
- [ ] 1.3 Replace the advisory's "every task listed was still running" parenthetical; update the header's route-3 note
- [ ] 1.4 Run mutation rows T1–T5 once as RED proofs

## Phase 2 — Negation-aware PIR scan (#8334)

- [ ] 2.1 Baseline: run the unmodified gate over every plan (recursive); record the count and the list
- [ ] 2.2 RED: Guard 2 fixtures + `denial-specimen-8334.md`, with verdict rows in `ship-incident-pir-gate.test.ts`
- [ ] 2.3 GREEN: `neg_strip()` (two-word cue window + `not that` / `rather than` / `instead of` clause phrases), sentinel lines, whole-line sentinel removal, `PIR-OUTAGE-NEGATION-SUPPRESSED` stderr note
- [ ] 2.4 Add mutation rows N1–N8 to `scripts/ship-incident-pir-gate-mutation.test.sh`
- [ ] 2.5 Re-measure; classify the flips; drop cues with no hit or that flip a plan a post-mortem cites; record the numbers in the script header

## Phase 3 — Postmerge headroom (#8419)

- [ ] 3.1 Move the Phase 3.6 body to `postmerge/references/sentry-error-count-delta.md`; keep the trigger, directive, vocabulary and Graceful Degradation rows inline
- [ ] 3.2 Update the `scripts/sentry-issue.sh` pointer
- [ ] 3.3 Run the budget lint against the merge base; record headroom

## Phase 4 — One BEHIND executable (#8383, #8419 ship half)

- [ ] 4.0 Gate: `git fetch origin main`; #8458 is MERGED and the `cd "$REPO_ROOT"` line is gone on origin/main; `git merge origin/main` (if #8458 is still open, commit Phases 1–3 and arm a Monitor)
- [ ] 4.1 RED: `--step` cases in `sync-pr-behind.test.sh` (exits 0/2/5/6/7/9/10, stdout tags carrying git's rc, 25-line status, `--help`); also run them against the `SYNC_MOCKS` text
- [ ] 4.2 GREEN: `sync_step`, strict argv, `--help`, `|| true` display pipes, fence argv, header prose; standalone loop calls `sync_step`
- [ ] 4.3 RED (fixture): `set -a`/`export -f`/`CLAUDE_PLUGIN_ROOT`, `$MOCK_STATE/cwd` + ceiling, mock strict-mode fixes, static no-inline assertion, git-argv-has-a-mock check, scenarios 6i and 13, token-list move, must-match row updates
- [ ] 4.4 GREEN (fences): three-arm BEHIND arm plus the `SYNC_SH` precondition (bare `${CLAUDE_PLUGIN_ROOT}` + `--help | grep -- --step`) in ship and merge-pr
- [ ] 4.5 Replace the Auto-sync on BEHIND steps 1–4 with a pointer; update `pr-merge-poll.ts` wording and add a `--step` assertion to its test
- [ ] 4.6 Measure ship headroom; if below 4396 B, apply the §C hatch contingency (reference file + `hatch_check` line)
- [ ] 4.7 Run mutation rows M1–M7 and H1 once as RED proofs

## Phase 5 — Close-out

- [ ] 5.1 Run the touched suites and the budget lint (plan Phase 5 list)
- [ ] 5.2 Route-to-definition probe: append a ~300 B bullet to ship and to postmerge, lint, then revert
- [ ] 5.3 PR body: one `Closes` per line for #8383, #8419, #8438, #8420, #7961, #8334; note #7801 (fixed by #7806); `OUTAGE_RE` vocabulary in backticks only; confirm `ship-incident-pir-gate.sh --pr <N>` exits 1
- [ ] 5.4 Find or file a tracking issue for the tension between Monitors run from a detached worktree and the BEHIND arm
