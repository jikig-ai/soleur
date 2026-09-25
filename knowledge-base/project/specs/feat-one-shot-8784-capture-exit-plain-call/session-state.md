# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-25-chore-capture-exit-dead-rc-read-plan.md
- Status: recovered from partial-artifact (planning subagent interrupted mid-run; plan body + tasks.md were committed on disk at ea87b83a29)
- Plan artifact: complete (selector=branch)

### Errors
Planning subagent canceled by user interrupt after committing the plan; no Session Summary emitted. Recovery per one-shot plan-artifact-recovery: `## Acceptance Criteria` present at line 401 → planning complete, continue to work.

### Decisions
- Work target: #8784 (lint-shell-capture-exit fn-then-rc-$? shape); the companion pin-drift issue cited by the operator was already closed upstream — not a work target.

### Components Invoked
- worktree-manager.sh create + draft-pr (PR #8836)
- plan + deepen-plan (via interrupted subagent, artifacts committed)

## Work Phase
- Status: implementation complete, in verify
- Branch: feat-one-shot-8784-capture-exit-plain-call (PR #8836, draft)

### Implemented
- `scripts/lint-shell-capture-exit.py`: two-pass `scan()` (state-before-line + paren depth), `set_errexit_verdict` with unquoted-comment strip + cluster/-o parsing, S3 dead-status-read class, S4 status-leaking function-tail class, baseline `--write-baseline` set() dedup.
- `scripts/lint-shell-capture-exit.test.sh`: S3/S4 fixtures; MIN_ASSERTIONS 24->50; 50/50 green.
- Live-bug fixes (not baselined): `ci-deploy.sh` docker-exec `exec_rc` read (if-form), `worktree-manager.sh` `git branch -D` rc read (if-form), `ci-deploy.test.sh` 7 unguarded grep captures (`|| true`).
- Baseline regenerated: 218 unique keys (+50 S3/S4, -39 stale/dup S1 rows). Old-vs-new S1/S2 finding set byte-identical (199 each).
- `--baseline` run: `[OK]` 0 new findings, 250 suppressed.

### Pending
- `test-all.sh --affected` running in background
- review -> qa -> compound -> ship -> merge -> postmerge

## Review Phase
- Panel: 4/8 dominant seats via Devin run_subagent (code-quality, architecture, test-design, security+blast-radius); trailer emitted degraded 4/8 (87c6352b8c).
- Findings: ~20 deduped (1 P1 same-line set-ordering miss, ~8 P2 detector/model bugs, rest P3 coverage). All resolved inline in c2649419bb.
- Live bugs the gate found and this PR fixes: worktree-manager.sh `git branch -D`, ci-deploy.sh `docker exec`, guardrails.sh `git diff --cached`, sdk-bump-sandbox-gate.sh `git log`, + 15 unguarded captures in test files (`|| true`).
- S4 count dropped 18->10 after `}`-mis-pop fix (7 false tails in git-data-cutover-access.test.sh). PIPESTATUS exemption retired the ci-deploy.sh:3455 baseline candidate.
- QA: auto-skipped (prose-only Test Scenarios; coverage in unit suite).
- Compound: learning written (2026-09-25-the-errexit-model-must-be-judged-at-the-commands-position...).

### Remaining
- ship -> merge -> postmerge
