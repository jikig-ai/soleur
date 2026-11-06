# Tasks: feat-one-shot-bun-pair-ratchet-accept-cleanup

Plan: `knowledge-base/project/plans/2026-11-06-chore-bun-pair-ratchet-accept-cleanup-plan.md`

## Phase 1: Ratchet verification (no file edit)

- 1.1 Run `bash plugins/soleur/scripts/collision-precheck.sh 10865` and report every hit (expected: #12212, #12217).
- 1.2 Find the newest merge_group `CI` run on main whose `affected-index-ratchet` job executed; read its log (`gh run view <run> --job <id> --log`).
- 1.3 Confirm no `new-pair` / `stale-accept` / `star-row` verdict names a `constraint-scaffold/test/*.test.sh` suite; quote the marker line (`live=<n>`).
- 1.4 Only if a pair-attributed verdict has reappeared: rebuild rows from `audit --all-refs --accept` on the merged tree and add them in sorted (suite, path) position, minimal diff.
- 1.5 Leave the `cloudflare-readonly`, `real-sdk-ask-probe-workflow` and #12212 pairs alone.

## Phase 2: PROMOTED_FILES guidance (CTO-ruled placement)

- 2.1 Extend the `PROMOTED_FILES` bullet in `plugins/soleur/skills/work/references/work-test-harness-sharp-edges.md` with the DEFERRED-dir / `MAX_DEFERRED` sentence (text in the plan, Phase 2).
- 2.2 Run `python3 scripts/lint-skill-body-budget.py --base origin/main` (must exit 0; SKILL.md untouched).
- 2.3 Run the repo markdown-lint on the edited file.

## Phase 3: digest-scrub decision

- 3.1 No issue filed. The ruling and flip criterion live in `decision-challenges.md` (D4, D5).

## Phase 4: Ship

- 4.1 PR body: `Ref #12155`, `Ref #10865`, `Ref #10859`, `Ref #12129`; no `Closes`; Changelog line; carry the final-report notes from the plan (Better Stack incident, untouched issues, #12160, review-trailer finding, feature-tweet gate, #12217 collision).
- 4.2 `git add` and `git commit` in separate calls; check the push exit code.
- 4.3 Required checks: `test`, `lockfile-sync`, `markdown-lint`, `tenant-integration-required`.
- 4.4 Post-merge: merge-commit `CI` run green; no deploy expected (plugin docs only); if a release run fired, verify health.
