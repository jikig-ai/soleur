# Tasks: feat(6178) — enroll the ADR-100 Phase-4 soak in the follow-through sweeper

Plan: `knowledge-base/project/plans/2026-09-19-feat-inngest-soak-6178-followthrough-enrollment-plan.md`
(the plan's §Exit contract, §Guard Contract and §Acceptance Criteria are the authority; this file
is the checklist). Constraints: never edit `apps/web-platform/infra/*`, any `.tf`,
`scripts/sweep-followthroughs.sh`, `.github/workflows/scheduled-followthrough-sweeper.yml`, or the
convention runbook; no SSH; no destructive dispatch; population slicing only; `Ref #6178`, never
`Closes`.

## Phase 0: Preconditions

- [x] 0.1 `git merge-base --is-ancestor 3ea78bd59 HEAD` (PR #8321 merged into the branch); `bash scripts/lint-followthrough-varq-ban.sh` clean before any edit.
- [x] 0.2 `command -v jq curl openssl awk`; `jq --version` ≥ 1.6.
- [x] 0.3 `doppler run -p soleur -c prd_terraform -- bash -c '…'` prints `WEBHOOK_DEPLOY_SECRET set`, `CF_ACCESS_CLIENT_ID set`, `CF_ACCESS_CLIENT_SECRET set` (names only).

## Phase 1: Population file

- [x] 1.1 Extract the 52 ids from runs 34974655656 and 35415585389 (plan Phase 1 command); `diff` empty; count 52; all UUID-shaped; no duplicates.
- [x] 1.2 Write `scripts/followthroughs/inngest-soak-6178.function-ids.txt`: `#` provenance header (both run ids, extraction command, the deleted `CUTOVER_DOUBLEFIRE_FUNCTION_IDS` variable, the dealing rule, "reorder only by re-measuring"), then 52 ids sorted by the measured density ranking (`-count, id`; see plan §Measured density ranking).
- [x] 1.3 Verify: `grep -vE '^\s*(#|$)' <file> | grep -cE '^[0-9a-f]{8}-…$'` = 52, `sort -u` = 52, set-equal to 1.1.

## Phase 2: RED — the harness

- [x] 2.1 Write `scripts/followthroughs/inngest-soak-6178.test.sh` mirroring `inngest-host-not-serving-7674.test.sh` (pass/fail helpers, instrument self-test, `passes`-keyed FLOOR, `passes + fails == checks`) with `assert_never_close_verb` from `ccla-representative-icla-7922.test.sh` applied after every run.
- [x] 2.2 PATH-stubbed `curl` (from `send-failed-alert-probe-8097.test.sh`): honours `-o`/`-w '%{http_code}'`, logs argv to `calls.log`, exits 64 without `-X GET` / `X-Signature-256: sha256=` / both CF-Access headers / (for slices) the pinned URL prefix with `from=2026-09-15T12:40:00Z`, exits 64 on > 11 ids, serves `registry.json` for the registry URL and `slice-<k>.json` + `.code` by call ordinal, honours `curl.rc`; `run()` resets `calls.log` + the ordinal, ALWAYS exports `INNGEST_SOAK_NOW_EPOCH` (default 1790000000), is the only launcher (C13's `bash -x` included), and calls `assert_never_close_verb` after every run.
- [x] 2.3 Fixture helpers `slice_fixture` (pinned window 2026-09-18T00–16Z, `total_count` = distinct-id count, 16 ticks/id, MIXED `startedAt` precision none/`.08Z`/`.101119Z`, one run at 2026-09-15T12:40:00Z, unique ULID ids), `append_runs <k> <json-array>`, `--no-window-head`; explicit `total_count` override for C10; a default `registry.json` with `function_count:70` and the 52 ids.
- [x] 2.4 Cases H1 (both `expect` and `expect_absent` driven to mismatch), H2, H3 (invariant self-test), H4 (`INNGEST_SOAK_NOW_EPOCH=` present in the suite), C0/C0b/C0c/C0d (registry), C1–C5, C5b+C5c as a pair, C5e, C6/C6b/C6c, C7 (asserts `slice_unreadable cause=probe_fatal` + extracted tokens), C8–C17, C11/C12 pinned to rc 2, C12b/C12c (bad run shape), C18/C18b, C9b, C20, C22, C23 (`jq_failed`); C2 asserts the verdict line LAST and the `SCOPE:` line second-to-last; FLOOR = measured pass count (≥ 40); `chmod +x`.
- [x] 2.5 Run against the absent probe → FATAL "probe not found" (exit 1) — RED confirmed.

## Phase 3: GREEN — the probe

- [x] 3.1 Write `scripts/followthroughs/inngest-soak-6178.sh` to the plan's §Exit contract: header (WHY, credential posture, anchor provenance incl. the QUALIFIED 09-15 class + ADR-146, the three declared-novel mechanisms, `WHY -uo AND NOT -euo`, `RETIREMENT:` with the close+14 d timing, EXIT CONTRACT never-0/never-1), xtrace refusal on `$-` FIRST then `${VAR:+x}` tests only (78), `set -uo pipefail`, `WORK=""` + single EXIT-only `trap on_exit` (cleanup + rc filter to {2,3,5,78}, else 3 `unmapped_exit`), constants (`SOAK_FROM`, `SOAK_END`, `PERIOD=1200`, `SLICE_MAX=11`, `POPULATION_SIZE=52`, `REGISTRY_COUNT=70`, `RUN_FLOOR=800`, exact `EXPLAINED` triples, four image ids), seams (`INNGEST_SOAK_NOW_EPOCH` digits-validated, `INNGEST_SOAK_POPULATION_FILE` parsed with the `LC_ALL=C` strict UUID regex), credential check (3), population parse (3 on malformed), registry GET + drift gate (3 `registry_unreadable`/`registry_drift`), round-robin dealer `(NR-1)%5`, slice loop with `curl --proto '=https'` and `curl_rc` captured separately, FATAL substring check BEFORE any jq parse, `.runs` array check, run-shape validation (`id`/`functionID` UUID/`startedAt` ISO or null → `bad_run_shape`), regex `total_count` check, `run_jq` rc capture at every jq site, per-slice vacuity + `deduped >= total_count`, spool `.runs` arrays → `jq -s '[.[][]]'` union, `RUN_FLOOR`, window-head check, op=verify 2.6 dedupe/bucket jq byte-for-byte, bucket `^[0-9]+$` guard before the ISO render, exact explained split, `body_class`/printable-filtered excerpt, reading block before every verdict, date branch (2 / 5 clean / 5 investigate) with the anchor-provenance, horizon, P2-c residual, close-LAST ordering, one `remedy=` per `reason=`, and the `SCOPE:` + verdict lines LAST; `chmod +x`.
- [x] 3.2 Suite green; `grep -E '^\s*exit (0|1)\b'` empty; every literal exit ∈ {2,3,5,78}.
- [x] 3.3 Hand-run the 13 ★ mutation rows (Guard 1 matrix: 1, 2, 3, 4 both directions, 6, 7, 8, 10, 13, 19 with the `set -u` abort form, 24, 25) one at a time; each reds the named case; record rc/first-line pairs for the PR body; revert each.

## Phase 4: Register and lint

- [x] 4.1 Add `run_suite "scripts/inngest-soak-6178" bash scripts/followthroughs/inngest-soak-6178.test.sh` to `scripts/test-all.sh` after the 7674 registration, with a two-line WHY comment.
- [x] 4.2 Green: `bash scripts/lint-orphan-test-suites.sh`, `bash scripts/lint-followthrough-varq-ban.sh`, `bash scripts/followthrough-exec-bit.test.sh`, the trap-tempfile lint's CI invocation, `bash scripts/followthrough-predicate-parity.test.sh`.

## Phase 5: ADR-100 addendum

- [x] 5.1 Append `## Addendum — 2026-09-19 (#6178) — the soak reading at day 3.5 and what the day-7 probe measures` after the 2026-09-18 addendum with the content order in plan Phase 5 (day-3.5 reading, attribution, why the startedAt proxy flags it, the 03:30Z re-read, what the day-7 probe measures, anchor provenance, the premature-close hazard, status stays `adopting`, the 07-07 PASS/FAIL prescription superseded).
- [x] 5.2 `git diff origin/main -- <ADR> | grep -c '^[-+]status:'` = 0; `python3 scripts/lint-infra-no-human-steps.py <ADR>` OK.

## Phase 6: Live interim reading (read-only)

- [x] 6.1 Run the probe under the sweeper's `env -i` shape via `doppler run` (plan Phase 6 command): `rc=2`, registry GET 200 with `function_count=70`, five slices 200 and non-vacuous, ≥ 826 distinct runs, exactly the two explained groups, zero UNEXPLAINED, global `min(startedAt)` = 2026-09-15T12:40:00Z.
- [x] 6.2 Record the per-slice `total_count` line with its UTC timestamp in the population file header.

## Phase 7: Enrollment at ship time (before `gh pr ready`, after push)

- [ ] 7.1 Fetch the #6178 body; append two blank lines + the single-line column-0 directive (`earliest=2026-09-22T13:23:00Z` unless DC1 in `decision-challenges.md` is resolved otherwise); `diff` shows only `>` lines.
- [ ] 7.2 Re-fetch and `cmp` against the original (abort and restart on any change), then `gh issue edit 6178 --body-file … --add-label follow-through`.
- [ ] 7.3 Readback: last non-blank line of the live body is the directive; `[.labels[].name]` contains `follow-through`; `parse_directive` sourced from the sweeper prints the `script`, `earliest`, `secrets` lines.
- [ ] 7.4 Precondition `git diff --quiet origin/main -- .github/workflows/scheduled-followthrough-sweeper.yml scripts/sweep-followthroughs.sh` (exit 0), then `gh workflow run scheduled-followthrough-sweeper.yml --ref feat-one-shot-6178-soak-followthrough -f dry_run=true`; the run log for issue #6178 shows `directive found (…)` then either `not yet reached … skipping` (before SOAK_END) or `exit=<2|3|5>` + `DRY_RUN — would comment` (at/after), and no `missing in repo HEAD` / `not executable` / `refused` / `INSIDE A CODE FENCE` line.
- [ ] 7.5 AC11 sweep: no open PR body carries `Closes|Fixes|Resolves #6178`; this PR body says `Ref #6178` and cites no other open tracker with `Ref`/`Tracks`.

## Phase 8: Acceptance

- [ ] 8.1 Walk AC1–AC14 in the plan; AC12/AC13 diff-scope checks against `origin/main`.
- [ ] 8.2 Session errors → learning or workflow fix (wg-every-session-error-must-produce-either).
- [ ] 8.3 Deferred #8349 (sweeper has no sentry-heartbeat) is cited in the PR body as a bare `#8349` (never `Ref`), and `decision-challenges.md` (DC1, T1–T3) is rendered by ship Phase 6.

## Work-phase record (2026-09-19)

- Harness: 85 passed / 0 failed (FLOOR=85); CI=1 and SOLEUR_SUBAGENT=1 re-runs identical.
- ★ mutation rows (scratch copy, md5-verified landing, control 85/0 before and after): 1 KILLED (C2 rc=3), 2 SURVIVED at first (the EXIT trap rewrote the exit-1 to 3 — equivalent by rc; C6 now asserts no `unmapped_exit` accompanies a mapped reason → KILLED), 3 KILLED (C7 cause=probe_fatal missing), 4a/4b KILLED (C5b / C5c respectively), 6 KILLED (C2 rc=2), 7 KILLED (C9), 8 KILLED (C10 rc=2), 10 KILLED (C23 rc=2 with the jq error on stderr), 13 KILLED (C0 population_thin — one slice), 19ctl (set -u abort, trap intact) → C6 reads `unmapped_exit rc=1` exit 3, 19 (second trap installed) KILLED by the INVARIANT (rc=1), 24 KILLED (C0 population_thin — last slice only), 25 KILLED (C0b rc=2), 26 KILLED (C13 `p-secret` printed).
- Phase 2 exit gate: `TEST_GROUP=scripts` 435/439 (0 failed, 4 declined, 3 REPORT observations), `TEST_GROUP=bun` 7/7; ratchets fixture-relative-assert / fixture-dir-operand-assert green after the WORK single-assignment fix; varq-ban, orphan-suites, exec-bit, predicate-parity, trap-tempfile, trace-credential, capture-exit all clean.
- Live Phase 6 run at 2026-09-19T04:18:06Z: rc=2, registry 70/70, s1=374 s2=125 s3=114 s4=113 s5=112, 838 distinct runs, explained=2, UNEXPLAINED=0.
- Session errors so far: (1) `'"'"'` quote idiom used inside double-quoted strings (bash -n red); (2) `hook_get` set CURL_RC inside `$(…)` — lost in the subshell; (3) `cannot_establish` inside `$(run_jq …)` exited only the subshell → a throwing jq fell through to NOT YET (caught by C23, the case written for it); (4) `${x%%.*}Z` doubled the Z on whole-second instants (C5e); (5) `local k="$1" f="$WORK/slice-$k.json"` expanded $k before binding; (6) the first mutation battery's three-layer quoting made every anchor miss — it reported "not landed" rather than a verdict, then was rewritten as a file-based mutator; (7) a backtick in a double-quoted assertion label was command-substituted away; (8) the P1b ratchet flagged the trap's rm -rf on a twice-assigned WORK.

## Review record (2026-09-19, 10 seats report-only; 4 P1 / 13 P2 / ~20 P3, all fixed inline)

- Structural-cause roll-up: ONE gap — "the explained pin is columns, not members" (test-design P1-1 + data-integrity's run-id join). Closed by pinning the two groups as exact run-id SETS joined to `routine_runs.run_id`; `26e6836b` = cron-ghcr-token-minter and `2e625d3c` = cron-anthropic-credit-probe are now proven by join.
- P1s: runner-path credentials unexercised since 2026-07-02 → DC1 flipped, enrol at the enrollment instant (architecture); `.bucket`/member-set unpinned → C5d/C5f (test-design); `bad_run_shape` excerpt could print a host value at offset 0 → body withheld + C12d (test-design); `expect()` substring branch un-self-tested → H1b (test-design).
- P2s applied: registry growth → UNMEASURED + QUALIFIED verdict, refuse only on a vanished id; `SOAK_STALE` horizon guard before any GET; verbs re-ordered flip → re-read → release → close; jq stderr captured (was republishing a host value + tmp path); body file created before curl (no bash redirect error on the comment); `unreadable()` hoisted; probe wall-clock budget + curl connect/max-time; C2 tokens asserted on the verdict LINE; `jq_failed` reserved for jq (`date_failed`/`shape_failed` elsewhere); `union_mismatch`, `window_underrun`, `null_started` ceiling, `foreign_function_id`, bounded `INT_RE`, `bash -n` self-check, registry FATAL class, `comm` rc captured; manual-trigger residual documented; "byte-for-byte" claim corrected; 7922's `-uo` banner verbatim; ADR readings 826/831/838 all cited.
- Mutation battery after the pass (scratch copies, md5-verified, control 117/0 before and after): 26 rows — 23 KILLED; 3 SURVIVED and labelled EQUIVALENT: rows 4a/4b (`count ==` → `<=`/`>=`) are subsumed by the run-id-set conjunct, and row 24 (`jq -s add`) concatenates ARRAYS identically to `[.[][]]` now that the spool holds per-slice arrays.
- Harness: 117 passed (FLOOR=117); CI=1 identical; lints/ratchets all green; shellcheck clean.
