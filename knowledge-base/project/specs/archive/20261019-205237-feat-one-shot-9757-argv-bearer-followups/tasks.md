# Tasks: argv-bearer follow-ups, registry-restore crane login off argv

Plan: `knowledge-base/project/plans/2026-10-19-fix-argv-bearer-followups-registry-restore-crane-stdin-plan.md`
Ref #9757 (never a closing keyword). Hold: no merge and no production-facing dispatch without the operator's per-command go-ahead; stop at a ready PR.

## Phase 1: Setup and premise check

- [x] 1.1 Re-fetch `origin/main` and re-run the premise check: `grep -n 'auth login' scripts/registry-restore-from-ghcr.sh` still shows `-p` at the two lines; items 1, 2, 4 and leads (a)-(e) are still converted (the reconciliation table in the plan)
- [x] 1.2 Measure the baselines: `bash tests/scripts/test-registry-restore-from-ghcr.sh` (expect 85 passed), `bash tests/scripts/test-argv-bearer-sweep.sh` (expect 823), and note `EXPECTED_TESTS`; run `bash plugins/soleur/test/fixture-relative-assert.test.sh` for its starting state
- [x] 1.3 Fetch crane `v0.20.2` into the scratchpad and run the one-off checks against a temp `DOCKER_CONFIG`: the happy path (`config.json` decodes to `user:password`, record `stat -c %a`), three failure shapes with a sentinel token (unwritable config, empty stdin, missing username) grepping stderr for the sentinel, and whether real login contacts the registry; keep the output for the PR body

## Phase 2: RED tests first (they fail against today's engine)

- [x] 2.1 Redesign the crane `auth login` stub in `tests/scripts/test-registry-restore-from-ghcr.sh`: accept host, `-u`, `--insecure`, `--password-stdin`; exit 64 on `-p`, `--password`, `--password=*`, glued `-p*`, or a missing `--password-stdin`; read the password with `cat`, trim one `\n` then one `\r`; append `host<TAB>user<TAB>password` to `$CALLS.stdin`; keep the `REJECT_ME` sentinel; never print the password
  - [x] 2.1.1 Redirect the engine's stdin from `/dev/null` in `run_engine` and in the battery runner
- [x] 2.2 Add suite rows (all unconditional): (a) exact stdin value per login with distinct tokens; (b) token absent from the argv log, `login.err` and output; (c) new GHCR rows (happy, rejected exits 2) plus the sink `REJECT_ME` row (exits 5); (d) CR-in-stderr fixture; (e) post-login environment holds none of the four names; (f) xtrace rows with explicit env (`ZOT` only, `GHCR` only, neither)
- [x] 2.3 Battery: re-anchor E01 in single-quoted form on the whole login head (`... | $CRANE auth login "$TARGET"` to `if ! true "$TARGET"`) and fix the comment at ~349; add E-new-A1 (sink `-p`), A2 (GHCR `-p`), B (drop feeder), D (wrong-variable feeder), C1 (xtrace condition to `if false; then`), C2 (GHCR operand dropped). Confirm the pre-flight audit reports M/M with the larger M
- [x] 2.4 Write stage S8 in `tests/scripts/test-argv-bearer-sweep.sh` (after S7) from the plan's Guard Contract: whole-tracked-tree derivation minus `*.test.sh`, `tests/`, `knowledge-base/` (`.md` only under `plugins/`), per-file continuation join, variable-aware verb alternation, strict host-token rule, flags-before-host handled; scratch base copies all counted files; mutations 1-8 with asserted reasons; harness row (alternation narrowed turns the floor RED); baseline-GREEN control; real-tree must-pass rows; floor pair measured from the run
- [x] 2.5 Confirm every new row is RED on the unmodified engine (S8 on the real tree, stub exit 64, suite rows, the battery's pre-flight abort run locally)

## Phase 3: GREEN engine (Phases 2 and 3 land in ONE push)

- [x] 3.1 `scripts/registry-restore-from-ghcr.sh`: add the multi-line xtrace refusal right after `set -uo pipefail` (model: `scripts/registry-pull-path-health.sh` ~112); document exit 78 in the header table as "traced invocation only"
- [x] 3.2 Replace both logins with `printf '%s' "$TOKEN" | $CRANE auth login ... --password-stdin` inside `if !`, keeping `die 5` and `die 2` and the existing redirects; reword both `die` texts (login failed locally; conditional on the 1.3 result); `tr '\r\n' '  '` in `last_err` and both tails; update the stale comment above (~529-545)
- [x] 3.3 Add `unset ZOT_PUSH_TOKEN GHCR_TOKEN DOPPLER_TOKEN GH_TOKEN_FOR_ENGINE` after the GHCR login block
- [x] 3.4 Delete line 40 from `scripts/lint-shell-trace-credential-refusal.baseline.txt`
- [x] 3.5 Run `python3 scripts/lint-shell-trace-credential-refusal.py scripts/registry-restore-from-ghcr.sh` (0 violations) and `--changed --base origin/main`

## Phase 4: Verify

- [x] 4.1 Run the three suites (restore, battery, argv sweep); set `EXPECTED_TESTS` to 823 plus the S8 row count (equal to the measured total) with a history comment line
- [x] 4.2 Run `bash plugins/soleur/test/fixture-relative-assert.test.sh`; regenerate its baseline deliberately only if counts moved
- [x] 4.3 Run the new bash once in an `ubuntu:24.04` container; run `plugins/soleur/test/c4-count-parity.test.sh`
- [x] 4.4 Read every engine caller for `-x`/`SHELLOPTS`/`BASH_ENV`: `registry-pull-path-health.sh:570` (rehearsal, `apply-web-platform-infra.yml` ~2845 and ~3051) and the restore step (~3642)
- [x] 4.5 `git diff --name-only origin/main...HEAD`: no `apps/web-platform/infra/**`, not the apply workflow, not its jq filter

## Phase 5: Bookkeeping and ship hold

- [x] 5.1 ADR-280: edit the false sentence at ~line 466 and add the 3-5 line addendum (S8 corpus, named blind spots, full-run-only selection, link #10529-#10532 once)
- [x] 5.2 `registry-luks-recut-6929.md`: add exit 5/2 ("login failed locally") and exit 78 rows to the restore exit-code table
- [ ] 5.3 Re-fetch #9757 and make one line-level body edit: tick items 1, 2, 4 and leads (a)-(e); point (f), (g), (h), (b)-wide at #10531, #10529, #10532, #10530; item 5 "in progress: PR #<N>" unticked. Do not close it
- [ ] 5.4 PR body: "Ref #9757", the line-level evidence table, the pinned-crane output, the added battery runtime, the full-run-only note for S8; mark ready; read the head verdict with `ci-head-verdict.sh`; stop at a ready PR and report the production hold plainly
- [ ] 5.5 After the operator-approved merge is verified: tick item 5 on #9757 with `gh issue edit` and read the next D10 rehearsal log for no `[FATAL]` and `restored=N`
