# Tasks: argv-bearer follow-ups, registry-restore crane login off argv

Plan: `knowledge-base/project/plans/2026-10-19-fix-argv-bearer-followups-registry-restore-crane-stdin-plan.md`
Ref #9757 (never a closing keyword). Hold: no merge and no production-facing dispatch without the operator's per-command go-ahead; stop at a ready PR.

## Phase 1: Setup and premise check

- [ ] 1.1 Re-fetch `origin/main` and re-run the premise check: `grep -n 'auth login' scripts/registry-restore-from-ghcr.sh` still shows `-p` at the two lines; items 1, 2, 4 and leads (a)-(e) are still converted (the reconciliation table in the plan)
- [ ] 1.2 Measure the baselines: `bash tests/scripts/test-registry-restore-from-ghcr.sh` (expect 85 passed), `bash tests/scripts/test-argv-bearer-sweep.sh` (expect 823), and note `EXPECTED_TESTS`
- [ ] 1.3 Fetch crane `v0.20.2` into the scratchpad and run the one-off `printf '%s' <synthetic> | crane auth login 127.0.0.1:5000 -u <user> --password-stdin --insecure` against a temp `DOCKER_CONFIG`; keep the output for the PR body

## Phase 2: RED tests first (they fail against today's engine)

- [ ] 2.1 Redesign the crane `auth login` stub in `tests/scripts/test-registry-restore-from-ghcr.sh`: accept host, `-u`, `--insecure`, `--password-stdin`; exit 64 on `-p`, `--password`, `--password=*`, glued `-p*`, or a missing `--password-stdin`; read the password with `cat`; keep the `REJECT_ME` sentinel on the stdin value
  - [ ] 2.1.1 Redirect the engine's stdin from `/dev/null` in `run_engine` and in the battery runner
- [ ] 2.2 Add suite rows: token absent from CALLS, `login.err` and engine output (both logins); `REJECT_ME` rows re-pointed (exit 5 sink, exit 2 GHCR); xtrace rows (`bash -x` with ZOT only, GHCR only, `env SHELLOPTS=xtrace`, and the unset case)
- [ ] 2.3 Re-anchor E01 (~429) and its comment (~349) in `tests/scripts/test-registry-gate-mutation-battery.sh`; add E-new-A (revert to `-p` / drop `--password-stdin`), E-new-B (drop the `printf` feeder), E-new-C (delete the xtrace refusal)
- [ ] 2.4 Write stage S8 in `tests/scripts/test-argv-bearer-sweep.sh` (after S7) from the plan's Guard Contract: derived scan with the `$CRANE`/`$DOCKER_BIN` verb alternation, continuation join, comment drop; floor pair measured from the run; mutation rows 1-8; harness row (alternation narrowed turns the floor RED); must-pass rows (comment, flag reorder, real-tree continuation shape, log string)
- [ ] 2.5 Confirm every new row is RED on the unmodified engine (S8 on the real tree, stub exit 64, E rows)

## Phase 3: GREEN engine

- [ ] 3.1 `scripts/registry-restore-from-ghcr.sh`: add the multi-line xtrace refusal right after `set -uo pipefail` (model: `scripts/registry-pull-path-health.sh` ~112); document exit 78 in the header table as "traced invocation only"
- [ ] 3.2 Replace both logins with `printf '%s' "$TOKEN" | $CRANE auth login ... --password-stdin` inside `if !`, keeping `die 5` and `die 2` and the existing redirects; update the stale comment above (~529-545)
- [ ] 3.3 Delete line 40 from `scripts/lint-shell-trace-credential-refusal.baseline.txt`
- [ ] 3.4 Run `python3 scripts/lint-shell-trace-credential-refusal.py scripts/registry-restore-from-ghcr.sh` (0 violations) and `--changed --base origin/main`

## Phase 4: Verify

- [ ] 4.1 Run the three suites (restore, battery, argv sweep); set `EXPECTED_TESTS` to the measured total with a history comment line in the existing ledger style
- [ ] 4.2 Run the new bash once in an `ubuntu:24.04` container; run `plugins/soleur/test/c4-count-parity.test.sh`
- [ ] 4.3 Read the invoking step (`apply-web-platform-infra.yml` ~3642): no `-x`, `SHELLOPTS` or `BASH_ENV`
- [ ] 4.4 `git diff --name-only origin/main...HEAD`: no `apps/web-platform/infra/**`, not the apply workflow, not its jq filter

## Phase 5: Bookkeeping and ship hold

- [ ] 5.1 ADR-280: 3-5 line addendum (S8, registry login verbs, link #10529-#10532 once)
- [ ] 5.2 Re-fetch #9757 and make one line-level body edit: tick items 1, 2, 4 and leads (a)-(e); point (f), (g), (h), (b)-wide at #10531, #10529, #10532, #10530; item 5 as "PR #<N> (pending merge)". Do not close it
- [ ] 5.3 PR body: "Ref #9757", the line-level evidence table, the pinned-crane output, the added battery runtime; mark ready; read the head verdict with `ci-head-verdict.sh`; stop at a ready PR and report the production hold plainly
