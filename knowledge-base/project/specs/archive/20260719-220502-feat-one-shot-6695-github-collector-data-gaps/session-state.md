# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-19-fix-github-collector-data-gaps-plan.md
- Status: complete

### Errors
- Halt gate 4.6 rejected the v2 draft — plan edits `apps/web-platform/server/…` (sensitive path) at threshold `none` while claiming no sensitive path is touched. Fixed with the required scope-out bullet; telemetry emitted.
- v1's scope argument was wrong — the "-87% undercount" was measured at `days=41`; production runs `days=1`. Pagination (RC4) and the `days` change (RC5) were cut.
- v1's AC3 was unachievable and harmful — `grep -c '2>&1' → 0` would have broken `cmd_discussions`' graceful path and blanked five error diagnostics. Every v3 AC was subsequently executed and its expected value recorded.
- v2's D7 wording was itself a leak — EXIT traps are global and singular; the per-file form leaks all but the last. Also caught a bug in the reviewer's own suggested accumulator helper (subshell append loses the array).
- Environment: `/tmp` hit 100% mid-session (9,470 leaked files, 1.9 GB) from an unrelated suite; reclaimed stale entries to unblock. Logged as a follow-up, not folded in.

### Decisions
- Scope is three defects, not five: RC1 (E2BIG), RC2 (stderr poisoning), RC3 (LLM fabrication). Net diff ≈ five `--argjson` bindings, one `2>&1`, three prompt anchors, a sidecar, and a test helper.
- Root cause pinned to `MAX_ARG_STRLEN` (131,072 B/arg), not `ARG_MAX` (2 MB) — bisected. Explains why it fires on 10 commits and recurs every run, and why the 2026-03-28 learning's wrong threshold model meant the original fix was never back-propagated. Correcting that learning is in scope.
- The monitored signal must not pass through the LLM. Replaced the unbuildable `resolveOutputAwareOk` route with a collector-status JSONL sidecar plus a deterministic fabrication detector (collector `exit != 0` + a stat in the digest → Sentry + RED).
- Scope claim verified, not asserted — a sibling sweep across all `--argjson` sites confirms no other script shares the defect.
- Reference, don't close #6695 — it's a scheduled digest whose remaining content is unrelated; PR body uses `Ref`, not `Closes`.

### Components Invoked
- Skills: `soleur:plan`, `soleur:deepen-plan`
- Agents: `Explore`, `general-purpose` @ `model: fable`, `soleur:engineering:review:code-simplicity-reviewer`, `soleur:engineering:review:kieran-rails-reviewer`, `pr-review-toolkit:silent-failure-hunter`
- Gates: 4.6 (User-Brand Impact — fired), 4.7 (Observability), 4.8 (PAT-shaped), 4.9 (UI wireframe); 4.5/4.55 not triggered
- Tools: `gh`, `jq`/`bash`, `git`
