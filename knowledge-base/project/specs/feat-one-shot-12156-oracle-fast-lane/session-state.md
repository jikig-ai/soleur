# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-12156-oracle-fast-lane/knowledge-base/project/plans/2026-11-05-ci-oracle-only-fast-lane-plan.md
- Status: complete

### Errors
- `git commit`/`git add` rejected twice by tool-level main/master guard (does not resolve `workdir`/`$VAR` paths inside a worktree). Resolved via `git -C <literal-absolute-worktree-path>` per the hook's repair text. Commits fd818a82ca + 8461f064ee pushed.
- No Task/Agent tool in subagent: every prescribed spawn (research, domain leaders, plan-review panel, deepen-plan fan-outs) executed inline per the harness note; mechanical halt gates run for real (lint-guard-contract.py green, 4 guards). Technical rulings that would have gone to `soleur:engineering:cto` recorded `pending - assumed:` in decision-challenges.md.
- Collision precheck reported PR #12166 and foreign `test-all.sh` processes — #12166 is this branch's own pipeline draft (not a duplicate); foreign processes are unrelated worktrees.

### Decisions
- New dedicated driver `scripts/ci-oracle-lane.sh` + `oracle-selection` job (not an edit to S4's `ci-pr-selection.sh`, which is pull_request/doc-only scoped and still activation-locked); lane dark+locked behind `CI_ORACLE_LANE=on` + `ORACLE_LANE_LOCKED=1` per `wg-dark-launch-deploy-gates` and ADR-276 3(c)(d).
- Oracle surface = accept.tsv + baseline.tsv + `AFFECTED_*_PATHS` array extents in `test-affected-paths.sh` (hunk-level, base AND head images so new-array repairs like #12150 qualify) + the stage-1 doc allowlist; replay.py, test-all.sh, ci.yml, lint-ratchet.py and all out-of-extent hunks fail closed — sentinel-pinned.
- Skip set = five heavy `test` legs + `shard-totality-mutations` on BOTH pull_request and merge_group via a new ORACLE-ONLY-SKIP aggregator tolerance; `e2e`, `encryption-posture` and all guard/lint jobs keep running; new `oracle-index-check` leg (inside `test`'s needs) runs the census/manifest so oracle edits stay gated on the queue.
- merge_group arm narrows ADR-276 Decision 5 → a dated ADR-276 amendment is an in-scope deliverable (required by ADR-276 3(g)); push-dedupe proof tightened so an oracle-reduced merge_group green never elides the push run.
- `brand_survival_threshold: single-user incident` + `requires_cpo_signoff: true`; sign-off recorded as pending operator item O1 (headless). All deepen-plan halt gates (4.6–4.13) pass.

### Components Invoked
- Skills run as checklists: `soleur:plan` (all phases incl. premise validation, mechanism-minimality gate, skeleton checkpoint, scope check, domain sweep, User-Brand Impact, Observability, Guard Contract, ADR gate, code-review overlap), `soleur:deepen-plan` (halt gates 4.6–4.13 + enhancement summary).
- Inline agent roles: repo-research, learnings research, functional-overlap, engineering domain-leader assessment, condensed plan-review self-pass.
- Scripts: `cloud-detect.sh`, `collision-precheck.sh 12156`, `lint-guard-contract.py`; plus `gh issue/pr view`, `gh variable list`, `gh issue list --label code-review`.
- Artifacts: plan file, `specs/feat-one-shot-12156-oracle-fast-lane/tasks.md`, `decision-challenges.md` — pushed to the branch.

## Review phase (2026-11-05, PR #12166)

Design pass (design-risk): code-simplicity f672069c, architecture 6e323eca, performance-oracle c8b90c1a — no P1.
Panel (8 seats, dedup'd): git-history 1e2a6387, pattern-recognition ddf8f42d, security fffc27d9, data-integrity
a03b80da, agent-native 413ca83b, code-quality a7c53594, test-design 984a309e, user-impact 04fe5776.

P1s fixed: (a) candidate-tree forgery — driver now sourced from base image (git show HEAD^1:/$MERGE_GROUP_BASE_SHA:);
(b) binary-diff vacuous extent pass — ^Binary files fails closed in check_hunks.
P2s fixed: element grammar ELEM_RE ($/backtick excluded inside quotes after sentinel caught the first form),
self-exclusions, manifest argv 387-599, G4 ci-oracle family + exclusion note, ocensus .if whitelist, y-orasel mutants,
GITHUB_SHA bind rows, extent_parse fixtures, remedy-line rows, pagination total_count<=100, baseline.tsv doc drift
(5 sites), runbook gh-syntax/audit-block/four-leg variant, plan RATCHET_ORACLE overclaim, CODEOWNERS rows,
suite-durations floor row, ALWAYS_RUN_JOBS +2, pr-fanout-ledger 30.
Deferred (recorded, not fixed): RUNNER_TEMP fallback port back to ci-pr-selection.sh (sibling-file scope),
serial-manifest merge-queue wall-clock bound (bounded by timeout-minutes:30; activation-gated concern),
oracle-index-check skip diagnostic nuance on push, reordered.txt tac fallback, mutate_otol bash -n.
Suites green: ci-oracle-lane 4837/4837 (31/31 mutants), push-dedupe 268, draft-light 209, aggregator 249 (47/47).
