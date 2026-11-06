# Tasks — feat-one-shot-10865-constraint-scaffold-pairs

Plan: `knowledge-base/project/plans/2026-11-06-fix-affected-index-refresh-stage-a-edge-plan.md`
Issue: #10865 (soak tracker, Ref — not closed by this PR) · PR: #12217

## Phase 1 — Setup / sync base

- [x] 1.1 `git fetch origin && git rebase origin/main` (2 commits: #12212 edge declarations, #12149 accept row + test-gate perf). On conflict: accept.tsv = union of additions; test-affected-paths.sh = keep both blocks.
- [x] 1.2 Re-run `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main` — confirm the two foreign pairs (`plugins/soleur ↔ build-inngest-bootstrap-image.yml`, `scripts/lint-gh-dedupe-shape ↔ scheduled-zot-restart-loop.yml`) are gone. If not, STOP and re-triage; do not duplicate #12212's declarations.

## Phase 2 — Core implementation

- [x] 2.1 Insert `AFFECTED_PLUGINS_SOLEUR_SKILLS_CONSTRAINT_SCAFFOLD_TEST_REFRESH_STAGE_A_TEST_SH_PATHS` block in `scripts/lib/test-affected-paths.sh` immediately after the parity block (~line 2422, before the git-worktree block), entries per plan: `plugins/soleur/skills/constraint-scaffold/{references/,scripts/,test/fixtures/}`, suite self, `plugins/soleur/test/lib/git-fixture-env.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/test-all.sh`. Header comment matches sibling convention.
- [x] 2.2 `bash -n scripts/lib/test-affected-paths.sh`.
- [x] 2.3 Ratchet fixpoint: `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main`; for each `new-pair` on `refresh-stage-a.test.sh` (expected: `apps/web-platform/scripts/constraint-gates.sh` anchors ~:129/:368; possibly `apps/web-platform/.github/workflows/constraint-gates.yml`, `fix-constraints-stage-b.yml`, or the `apps/web-platform/.github/workflows` dir literal) add accept rows `suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>false-positive: <reason>` sorted beside existing rows ~629-654. Stop and re-classify if >6 rows or any pair is a real read.

## Phase 3 — Testing / verification

- [x] 3.1 `bash scripts/test-all.sh --print-selection --paths=<each real input>` — suite selected `1 edge:declared` for: `scripts/constraint-scaffold.sh`, `references/fix-constraints-stage-a.template`, `references/fix-constraints-stage-a.emitted.sha256`, `test/fixtures/stage-a.v1.0.236.emitted`, `plugins/soleur/test/lib/git-fixture-env.sh`.
- [x] 3.2 `--paths=apps/web-platform/scripts/constraint-gates.sh` → suite NOT selected.
- [x] 3.3 `bash -n` both edited files; `bash scripts/test-all-affected.test.sh`; `bash scripts/test-affected-kb-consumers.test.sh` — all pass.
- [x] 3.4 Final ratchet on merged tree (`git merge-tree` scratch or post-rebase tip): `exit=0 live=0` (AC3). Re-run after every sibling merge while queued — `feat-one-shot-bun-pair-ratchet-accept-cleanup` is live on the same files.
- [x] 3.5 Confirm diff touches none of: `required-checks.txt`, canonical ruleset JSON, `infra/github`, count pins, `CI_PR_AFFECTED` (#10859 hold).

## Phase 4 — Post-merge

- [ ] 4.1 `gh issue comment 10865` — record: 11 constraint-scaffold pairs classified all-mention (dispositioned on main by #12166 rows 609-654), INDEX-UNBOUND edge declared by this PR for refresh-stage-a.test.sh, live=2 remainder owned by merged #12212, final ratchet state.
