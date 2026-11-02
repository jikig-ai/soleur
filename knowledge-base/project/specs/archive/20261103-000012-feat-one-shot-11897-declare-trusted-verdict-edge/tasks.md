# Tasks — feat-one-shot-11897-declare-trusted-verdict-edge

Plan: `knowledge-base/project/plans/2026-11-02-fix-affected-index-ratchet-trusted-verdict-edge-plan.md`
Issue: #11897 (last residual `new-pair`; this change greens the ratchet on main)

## Phase 1 — Declare the edge

- [x] 1.1 Edit `scripts/lib/test-affected-paths.sh`: insert the
      `AFFECTED_SCRIPTS_INNGEST_A5_A6_OWNER_ASK_10136_PATHS` array (with its comment block)
      immediately after `AFFECTED_SCRIPTS_INNGEST_PROBE_HEARTBEAT_FEEDER_PATHS` (closing `)` at
      line 3332), exactly as specified in the plan's `## Files to Edit` code block.
- [x] 1.2 Confirm no other file changes: `git diff --name-only origin/main...HEAD` lists only
      `scripts/lib/test-affected-paths.sh` plus pipeline artifacts under
      `knowledge-base/project/{plans,specs}/`.

## Phase 2 — Verify

- [x] 2.1 `bash scripts/test-all.sh --print-selection --paths=scripts/lib/trusted-verdict.sh` → row
      `AFFECTED_SELECTED\tscripts/inngest-a5-a6-owner-ask-10136\t1\tedge:declared` containing
      `^scripts/lib/trusted-verdict.sh`.
- [x] 2.2 `python3 -I scripts/ci-pr-affected-replay.py ratchet` → exit 0,
      `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass`.
- [x] 2.3 `bash scripts/lint-orphan-test-suites.sh` → exit 0.
- [x] 2.4 `bash scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh` → exit 0.
- [x] 2.5 `git diff --quiet origin/main...HEAD -- scripts/ci-pr-affected-audit.accept.tsv scripts/ci-pr-affected-audit.baseline.tsv` → exit 0.

## Phase 3 — Notes

- The index edit is an oracle input: the PR's `--affected` gate degrades to the full battery once
  (`INDEX-UNBOUND` → `runner-changed`); expected.
- `Closes #11897` belongs in the PR body — this is the last live pair
  (`live=1510 baseline=1510` post-change).
