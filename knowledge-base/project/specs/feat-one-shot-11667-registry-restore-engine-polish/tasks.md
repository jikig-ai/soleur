# Tasks — feat-one-shot-11667-registry-restore-engine-polish

Plan: `knowledge-base/project/plans/2026-10-31-chore-registry-restore-engine-polish-plan.md`

## Phase 0 Preconditions

- [ ] 0.1 `git fetch origin main`; record `wc -c .github/workflows/apply-web-platform-infra.yml` (490,228); never edit it
- [ ] 0.2 Baselines in separate calls: wiring suite 89/0; engine suite 98/0; pull-path-health suite
- [ ] 0.3 One grep `runs only the restore step` (expect only `.claude/hooks/grep-q-pipe-guard.test.sh` line ~2225)

## Phase 1 RED

- [ ] 1.1 Wiring suite: add controls `eng-hdr-row1-removed` and `eng-emit-sites1-removed` after `engine-extra-code` (failure-only landed checks, one passing row each)
- [ ] 1.2 Engine suite: separate pass/fail pair after the DNS rc check asserting `stay in the sink`
- [ ] 1.3 Run both; record both new controls and the engine assertion RED

## Phase 2 GREEN

- [ ] 2.1 Wiring suite: delete both `| grep -vx 1`; drop ", both without 1"; rewrite comments ~349-351 and ~357; `EXPECTED_ASSERTIONS` from a green run (91 expected)
- [ ] 2.2 `tests/scripts/lib/restore-engine-header.sh`: comments only, no counts
- [ ] 2.3 `tests/scripts/test-registry-pull-path-health.sh`: message at ~302 to "1 plus the header rows"
- [ ] 2.4 Engine: reword the source-resolution NETWORK message; one comment sentence under the EXIT CODES preamble (codes 2-6); exit-3 row unchanged
- [ ] 2.5 `.claude/hooks/grep-q-pipe-guard.test.sh` ~2225: reword the reason, keep `text-only` and `(1 non-test producers)`
- [ ] 2.6 Engine suite: `MIN_ASSERTIONS` from a green run (99 expected)

## Phase 3 Verification

- [ ] 3.1 Each suite alone, the hook test, `lint-guard-contract.py`, shellcheck, `bash -n`; engine non-comment diff is the one `die 2` line
- [ ] 3.2 Rebase on post-#11690 main, THEN launch the ~860 s battery detached in its own call; read log and rc; if queued, CI `test` is the gate
- [ ] 3.3 Passive note only: next `registry-luks-recut` run, confirm no `[FATAL]` and `restored=N`; do NOT dispatch a recut

## Phase 4 Ship

- [ ] 4.1 Wait for #11690 / #11687 (never touch the workflow, never admin-merge); report a multi-hour stall
- [ ] 4.2 `prepush-secret-scan.sh`, push, PR body with `Ref #11667` and `Ref #9757` only
- [ ] 4.3 `gh pr merge <N> --squash --auto` (own call, no `--delete-branch`)
- [ ] 4.4 Deploy-arm check, `soleur:postmerge`, cleanup-merged
- [ ] 4.5 Comment on #11667 (stays open): what landed, arm 3 residue cited by string
