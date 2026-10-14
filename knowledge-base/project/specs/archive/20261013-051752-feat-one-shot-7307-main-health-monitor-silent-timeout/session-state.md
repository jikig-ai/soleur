# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-09-fix-main-health-monitor-silent-timeout-plan.md`
- Status: recovered from partial-artifact (subagent stalled at the stream watchdog mid-deepen-plan self-audit; the plan body and every deepen-plan section were on disk).

### Errors
- Planning subagent stalled: no progress for 600s (stream watchdog did not recover). Its last emitted line was "All gates pass. Now the deepen research passes — the post-edit self-audit is high-value here after three rewrites", i.e. plan + deepen had already written their output; only the `## Session Summary` emission was lost.
- Recovery: partial-artifact check per one-shot Steps 1-2 fallback. Plan file present with frontmatter, Overview, Acceptance Criteria and all deepen-plan sections; `tasks.md` present. Scope verified — `git diff origin/main...HEAD --name-only` lists only `knowledge-base/project/{plans,specs}/` paths, no product-code breach.
- Pre-planning environment defect (fixed inline, out of scope for #7307): git reported every worktree in this clone as bare, blocking `worktree-manager.sh draft-pr`. `ensure_bare_config` skips its `core.bare` surgery when `git_dir` is a `.git` *directory*, which this bare-in-`.git` layout satisfies, so `core.bare=true` remained in the shared `.git/config` and bled into every linked worktree. Unset there per the script's own documented invariant ("core.bare must ONLY exist in .git/config.worktree"); the bare root's verdict is unchanged via its own `config.worktree`. To be filed as a separate issue at compound.

### Decisions
- The issue's stated timing band (14m49s-15m26s) is **right-censored** and cannot size the new ceiling — every run over 15m was killed at 15m, so the band measures the old ceiling. Phase 1 dispatches the modified workflow from the branch to measure real per-step durations; Phase 3 derives the ceilings from that.
- A defect not in the issue is the more consequential one: `bash scripts/test-all.sh 2>&1 | tee …` under GitHub's default `bash -e {0}` shell (no `pipefail`) discards the suite's exit code, so a red suite reports `success` and the closer auto-closes human-filed `ci/main-broken` trackers. Fixed with the house `set +e` / `${PIPESTATUS[0]}` / `set -e` / `exit "$rc"` idiom.
- Infra coverage lands as a **second step** with `TEST_GROUP=infra` (which runs *only* infra, not "also infra"), preceded by an explicit toolchain assertion — registered infra suites self-skip with exit 0 and the runner prints PASS, so a bare runner would go green over absent coverage.
- Filer condition widens to `!= 'success'` (covers `cancelled`); closer stays strict at `== 'success'`; the two arms are exhaustive and disjoint. `cancel-in-progress` flips to `false` so concurrency stops manufacturing `cancelled` conclusions.
- Nothing currently watches the watcher: scheduling moved to Inngest and the workflow carries only `workflow_dispatch:`, so a dropped dispatch is 100% invisible. A `sentry_cron_monitor` plus a terminal heartbeat step covers it, and both must land in one commit (`prod-version-drift-check.test.sh` B10g).

### Components Invoked
- `soleur:plan`
- `soleur:deepen-plan`
