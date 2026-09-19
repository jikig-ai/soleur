# Tasks: feat(6178) — enroll the ADR-100 Phase-4 soak in the follow-through sweeper

Plan: `knowledge-base/project/plans/2026-09-19-feat-inngest-soak-6178-followthrough-enrollment-plan.md`
(the plan's §Exit contract, §Guard Contract and §Acceptance Criteria are the authority; this file
is the checklist). Constraints: never edit `apps/web-platform/infra/*`, any `.tf`,
`scripts/sweep-followthroughs.sh`, `.github/workflows/scheduled-followthrough-sweeper.yml`, or the
convention runbook; no SSH; no destructive dispatch; population slicing only; `Ref #6178`, never
`Closes`.

## Phase 0: Preconditions

- [ ] 0.1 `git merge-base --is-ancestor 3ea78bd59 HEAD` (PR #8321 merged into the branch); `bash scripts/lint-followthrough-varq-ban.sh` clean before any edit.
- [ ] 0.2 `command -v jq curl openssl awk`; `jq --version` ≥ 1.6.
- [ ] 0.3 `doppler run -p soleur -c prd_terraform -- bash -c '…'` prints `WEBHOOK_DEPLOY_SECRET set`, `CF_ACCESS_CLIENT_ID set`, `CF_ACCESS_CLIENT_SECRET set` (names only).

## Phase 1: Population file

- [ ] 1.1 Extract the 52 ids from runs 34974655656 and 35415585389 (plan Phase 1 command); `diff` empty; count 52; all UUID-shaped; no duplicates.
- [ ] 1.2 Write `scripts/followthroughs/inngest-soak-6178.function-ids.txt`: `#` provenance header (both run ids, extraction command, the deleted `CUTOVER_DOUBLEFIRE_FUNCTION_IDS` variable, the dealing rule, "reorder only by re-measuring"), then 52 ids sorted by the measured density ranking (`-count, id`; see plan §Measured density ranking).
- [ ] 1.3 Verify: `grep -vE '^\s*(#|$)' <file> | grep -cE '^[0-9a-f]{8}-…$'` = 52, `sort -u` = 52, set-equal to 1.1.

## Phase 2: RED — the harness

- [ ] 2.1 Write `scripts/followthroughs/inngest-soak-6178.test.sh` mirroring `inngest-host-not-serving-7674.test.sh` (pass/fail helpers, instrument self-test, `passes`-keyed FLOOR, `passes + fails == checks`) with `assert_never_close_verb` from `ccla-representative-icla-7922.test.sh` applied after every run.
- [ ] 2.2 PATH-stubbed `curl` (from `send-failed-alert-probe-8097.test.sh`): honours `-o`/`-w '%{http_code}'`, logs argv to `calls.log`, exits 64 without `-X GET` / `X-Signature-256: sha256=` / both CF-Access headers / the pinned URL prefix with `from=2026-09-15T12:40:00Z`, exits 64 on > 11 ids, serves `slice-<k>.json` + `.code` by call ordinal, honours `curl.rc`.
- [ ] 2.3 Fixture builder `slice_fixture`: `{runs, total_count}` over the pinned window 2026-09-18T00–16Z, `total_count` = distinct-id count, 16 ticks/id (832-run union), one run at 2026-09-15T12:40:00Z, microsecond `startedAt`, unique ULID ids; explicit `total_count` override for C10.
- [ ] 2.4 Cases H1, H2, C1–C17 (as listed in plan Phase 2), C18/C18b, C9b, C20, C22, C23, C5c, C5e; FLOOR = measured pass count (≥ 32); `chmod +x`.
- [ ] 2.5 Run against the absent probe → FATAL "probe not found" (exit 1) — RED confirmed.

## Phase 3: GREEN — the probe

- [ ] 3.1 Write `scripts/followthroughs/inngest-soak-6178.sh` to the plan's §Exit contract: header (WHY, credential posture, anchor provenance, `RETIREMENT:` with the close+14 d timing, EXIT CONTRACT never-0/never-1), xtrace refusal (78), `set -uo pipefail`, `WORK=""` + single `trap on_exit EXIT` (cleanup + rc filter to {2,3,5,78}, else 3 `unmapped_exit`), constants (`SOAK_FROM`, `SOAK_END`, `PERIOD=1200`, `SLICE_MAX=11`, `POPULATION_SIZE=52`, `RUN_FLOOR=800`, exact `EXPLAINED` triples, four image ids), seams (`INNGEST_SOAK_NOW_EPOCH` digits-validated, `INNGEST_SOAK_POPULATION_FILE`), credential check (3), population parse (3 on malformed), round-robin dealer `(NR-1)%5`, slice loop with `curl_rc` captured separately, FATAL substring check, `.runs` array check, regex `total_count` check, `run_jq` rc capture at every jq site, string `.id`/`.functionID` refusal, per-slice vacuity + `deduped >= total_count`, spool → `jq -s '[.[][]]'` union, `RUN_FLOOR`, window-head check, op=verify 2.6 dedupe/bucket jq byte-for-byte, exact explained split, reading block before every verdict, date branch (2 / 5 clean / 5 investigate) with the anchor-provenance and horizon sentences and one `remedy=` per `reason=`; `chmod +x`.
- [ ] 3.2 Suite green; `grep -E '^\s*exit (0|1)\b'` empty; every literal exit ∈ {2,3,5,78}.
- [ ] 3.3 Hand-run the 12 ★ mutation rows (Guard 1 matrix: 1, 2, 3, 4, 6, 7, 8, 10, 13, 19, 24 + row 2's invariant twin) one at a time; each reds the named case; record rc/first-line pairs for the PR body; revert each.

## Phase 4: Register and lint

- [ ] 4.1 Add `run_suite "scripts/inngest-soak-6178" bash scripts/followthroughs/inngest-soak-6178.test.sh` to `scripts/test-all.sh` after the 7674 registration, with a two-line WHY comment.
- [ ] 4.2 Green: `bash scripts/lint-orphan-test-suites.sh`, `bash scripts/lint-followthrough-varq-ban.sh`, `bash scripts/followthrough-exec-bit.test.sh`, the trap-tempfile lint's CI invocation, `bash scripts/followthrough-predicate-parity.test.sh`.

## Phase 5: ADR-100 addendum

- [ ] 5.1 Append `## Addendum — 2026-09-19 (#6178) — the soak reading at day 3.5 and what the day-7 probe measures` after the 2026-09-18 addendum with the content order in plan Phase 5 (day-3.5 reading, attribution, why the startedAt proxy flags it, the 03:30Z re-read, what the day-7 probe measures, anchor provenance, the premature-close hazard, status stays `adopting`, the 07-07 PASS/FAIL prescription superseded).
- [ ] 5.2 `git diff origin/main -- <ADR> | grep -c '^[-+]status:'` = 0; `python3 scripts/lint-infra-no-human-steps.py <ADR>` OK.

## Phase 6: Live interim reading (read-only)

- [ ] 6.1 Run the probe under the sweeper's `env -i` shape via `doppler run` (plan Phase 6 command): `rc=2`, five slices 200 and non-vacuous, ≥ 826 distinct runs, exactly the two explained groups, zero UNEXPLAINED, global `min(startedAt)` = 2026-09-15T12:40:00Z.
- [ ] 6.2 Record the per-slice `total_count` line with its UTC timestamp in the population file header.

## Phase 7: Enrollment at ship time (before `gh pr ready`, after push)

- [ ] 7.1 Fetch the #6178 body; append two blank lines + the single-line column-0 directive (`earliest=2026-09-22T13:23:00Z` unless DC1 in `decision-challenges.md` is resolved otherwise); `diff` shows only `>` lines.
- [ ] 7.2 Re-fetch and `cmp` against the original (abort and restart on any change), then `gh issue edit 6178 --body-file … --add-label follow-through`.
- [ ] 7.3 Readback: last non-blank line of the live body is the directive; `[.labels[].name]` contains `follow-through`; `parse_directive` sourced from the sweeper prints the `script`, `earliest`, `secrets` lines.
- [ ] 7.4 `gh workflow run scheduled-followthrough-sweeper.yml --ref feat-one-shot-6178-soak-followthrough -f dry_run=true`; the run log for issue #6178 shows `directive found (…)` then either `not yet reached … skipping` (before SOAK_END) or `exit=<2|3|5>` + `DRY_RUN — would comment` (at/after), and no `missing in repo HEAD` / `not executable` / `refused` / `INSIDE A CODE FENCE` line.
- [ ] 7.5 AC11 sweep: no open PR body carries `Closes|Fixes|Resolves #6178`; this PR body says `Ref #6178` and cites no other open tracker with `Ref`/`Tracks`.

## Phase 8: Acceptance

- [ ] 8.1 Walk AC1–AC14 in the plan; AC12/AC13 diff-scope checks against `origin/main`.
- [ ] 8.2 Session errors → learning or workflow fix (wg-every-session-error-must-produce-either).
