# Tasks — feat-one-shot-10859-pr3b-required-context

Plan: `knowledge-base/project/plans/2026-11-07-ci-s4-pr3b-required-ratchet-context-plan.md`
Issue: #10859 (go-ahead: issuecomment-6710852889). ONE commit for all registry + ci.yml edits.

## Phase 1 — Registry enrollment (single commit, coe + names)

- 1.1 `.github/workflows/ci.yml`: delete `continue-on-error: true` (~line 521) on `affected-index-ratchet`; rewrite advisory comment block (~505-518) to required-state wording; keep `if:` exactly `pull_request || merge_group`.
- 1.2 `scripts/required-checks.txt`: add `affected-index-ratchet` before `# CLA Required ruleset`, with a `# #10859` CONTENT-SCOPED/UNREACHABLE justification block naming the disjointness test + the Phase-4-preflight residual trigger.
- 1.3 `scripts/ci-required-ruleset-canonical-required-status-checks.json`: append `{"context": "affected-index-ratchet", "integration_id": 15368}`.
- 1.4 `infra/github/ruleset-ci-required.tf`: append `required_check` block (dated #10859 comment); fix "the 10 `context` strings" header → 11.
- 1.5 `plugins/soleur/test/required-checks-canonical-parity.test.sh`: Test-1c floors `-ge 10` → `-ge 11`.
- 1.6 `plugins/soleur/test/fixtures/admin-merge-ready/`: add context to ruleset 14145388 in `rules-branches-main.json`; add green `affected-index-ratchet` run (app.id 15368, head_sha 319c22bf…) to `check-runs.json`; dated README note.
- 1.7 `tests/scripts/test-audit-ruleset-bypass.sh`: T-rsc-7 `n == "10"` → `"11"` + bump-chain comment.
- 1.8 `scripts/pr-fanout-ledger.txt`: dated clause on ci.yml row (context required; declared job count unchanged at 21).

## Phase 2 — Unreachability assertion

- 2.1 `scripts/ci-pr-affected-replay.py`: add `audit --print-files-read` (sorted repo-relative `index.raws` keys, one per line; exit 0 on a completed census, 2 on degraded) + `--help` line.
- 2.2 `plugins/soleur/test/ci-pr-affected-replay.test.sh`: rewrite advisory pins (`row_wf_coe` chk ~2944, `row_wf_dark` chk ~2949 → required-state, `row_wf_dark_mutant` ~2954, `coe-gone` mutant ~2955); unit rows for `--print-files-read`; disjointness row — parse `ALLOWED_PATHS` from `.github/actions/bot-pr-with-synthetic-checks/action.yml`, run `audit --print-files-read` on the repo root, assert ∩ = ∅ + read-set ≥ 500 + members tracked; mutant (inject a read path) must red. Check `--rows` shard ranges in test-all.sh still cover appended rows.
- 2.3 `plugins/soleur/test/required-checks-merge-group-coverage.test.sh`: `contexts=12 producers=11` → `contexts=13 producers=12` (9 literals); optional `engine_green 12` → 13.
- 2.4 `scripts/probe-merge-group-coverage.sh`: `MIN_CONTEXTS_DEFAULT = 12` → 13 + comment update.
- 2.5 `scripts/required-check-wallclock-bounds.tsv`: seed `affected-index-ratchet` row (bounds = measured p90 rounded up; verify with `watch-wallclock-p90-11774.sh --dry-run`; margin 0.30).

## Phase 3 — Records

- 3.1 `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`: rewrite §The dark phase → required state; update §2 status line + advisory wording (~line 214).
- 3.2 ADR-276 `### Stage status`: dated 2026-11-07 PR3b line.
- 3.3 `infra/github/README.md`: CI context-count mentions 10 → 11.

## Phase 4 — Verify & ship

- 4.1 Run touched suites locally (parity, merge-group-coverage, audit-ruleset-bypass, admin-merge-ready, ci-pr-affected-replay legs, ci-draft-light, ci-push-dedupe).
- 4.2 `bash scripts/probe-merge-group-coverage.sh` → `merge-group-coverage=OK contexts=13 producers=12` (pre-merge gate).
- 4.3 Record pre-merge live ruleset read (bypass_actors + conditions) for post-apply comparison.
- 4.4 PR body: `Closes #10859`; states merge auto-applies ruleset via apply-github-infra.yml; cites go-ahead comment URL; no `[ack-destroy]` (addition only).
- 4.5 Post-merge: verify live ruleset has 11 contexts, bypass_actors/conditions unchanged; comment on #10448 + #10859.

## Do NOT touch

`scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/ci-pr-selection.sh`, `CI_PR_AFFECTED`, #10414, `_cron-safe-commit.ts` SYNTHETIC_CHECK_NAMES, job `if:`/`timeout-minutes`/permissions.
