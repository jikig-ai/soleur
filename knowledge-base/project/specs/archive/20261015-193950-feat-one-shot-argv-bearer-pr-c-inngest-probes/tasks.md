# Tasks: argv-bearer sweep PR C (inngest heartbeat and three probe scripts)

Plan: `knowledge-base/project/plans/2026-10-15-fix-argv-bearer-pr-c-inngest-heartbeat-and-probe-scripts-plan.md`
Branch: `feat-one-shot-argv-bearer-pr-c-inngest-probes`. Draft PR: #10356. Issue references are `Ref` only: #10120, #10093, #9757.
RED edits are local only; every pushed commit is green. No tag mint or push, no workflow dispatch, no terraform, no auto-merge, no merge: the PR ends at a ready, green (GuardA sanctioned-window exception evidenced) state with the Operator Holds Gates in its body.

## Phase 0: Baselines (read-only; all measured at plan time, re-measure now)

- 0.1 `git fetch origin main`; confirm `git merge-base --is-ancestor 8c8401e6fa HEAD`; `git log HEAD..origin/main` for movement in the touched files.
- 0.2 Green-baseline: `inngest.test.sh` (451/451), the three probe suites (303, 55, 169), `tests/scripts/test-argv-bearer-sweep.sh` (811), `cloud-init-inngest-bootstrap.test.sh` (266/269, three named red rows), `c4-count-parity.test.sh`, `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`.
- 0.3 Re-run the read-only baselines (pin literal, latest `vinngest-v*`, four web monitors plus two inngest monitors via `arm-heartbeats.sh --status` with the read-scope token, web-1 `boot_id` from `SOLEUR_PRIVATE_NIC`, counts-only Doppler shape check of the seven stored URLs); write them to a scratch file for the PR body. Print no URL, token or hash.
- 0.4 `bash scripts/test-all.sh --print-selection` once the first edit exists; record the selection.

## Phase 1: Inngest heartbeat body (issue 10120) [commit 1]

- 1.1 RED: in `apps/web-platform/infra/inngest.test.sh` re-type the preserved rows from `git show b48247d559` against current neighbours: https canary, absent-URL attribution to the guard, `--config` census exception, recording curl stub via rewritten `/usr/bin/curl` in a rendered copy, twelve hostile values, limiter re-emit, own-stamp, static POSIX-shape rows, `LOG_TAG` derivation intact. Observe RED against the unfixed script.
- 1.2 Dash row: pinned ubuntu image authoritative and CI fail-closed; labelled local-dash fallback; loud counted skip otherwise (CTO ruling 2).
- 1.3 GREEN: re-type the heartbeat block in `apps/web-platform/infra/inngest-bootstrap.sh` (C1 in the plan); rewrite the comment block above it.
- 1.4 Re-measure `INNGEST_MIN_ASSERTIONS` as a two-tier floor (skipped dash rows do not count); the inngest absent-URL row asserts `reason=empty`; drop `exec` before curl in the pipeline.

## Phase 2: The three probe scripts (issue 10093 last part) [one commit per script]

- 2.1 `web-zot-consumer-probe.sh`: RED rows first (stub extended: heartbeat call prints nothing, honours `-f`, `STUB_HB_RC`); `_hb_url_ok`, `_hb_curl`, optional window argument on `_window_open`, refusal marker `/run/web-zot-consumer-probe.refusal` at 3600 s; raise `MIN_ASSERTS` from the measured count (keep the terraform-skip margin).
- 2.2 `inngest-consumer-probe.sh`: add the recording curl stub and the registry fixture seam to its suite; same row set; own `_refusal_due` (not `_fault`), marker `/run/inngest-consumer-probe.refusal`.
- 2.3 `web-private-nic-guard.sh`: repoint the stub ping branch to stdin (read stdin once, add a non-empty `STUB_PING` row); update `transport_audit` golden argv (`--disable --noproxy '*' -gfsS -m 10 -o /dev/null --config -`, no tail) and its stdin golden; repoint the vacuous X1/X3/X6 negative rows; refusal rows; rewrite the "#9639" comment; `_refusal_due` with `SOLEUR_NIC_REFUSAL_MARKER`.
- 2.4 For each edited suite run, before its first commit: `fixture-relative-assert.test.sh`, `fixture-dir-operand-assert.test.sh`, `lint-shell-capture-exit.py --baseline ... <file>`; use `assert_fixture_dir` byte-for-byte.

## Phase 3: Battery stage S6-HB and ratchets [commit]

- 3.1 `tests/scripts/test-argv-bearer-sweep.sh`: read the whole S6-HB block first. `S6H_CONVERTED` gains the four scripts; `S6H_ALLOW=()`, `S6H_ALLOW_CEIL=0`; ceiling row `0 == 0` plus grow-by-one mutant; stale mutation re-anchored on an injected synthetic entry; growth mutation re-anchored; new rows for Guard 1 mutations 1 (inngest body and one probe), 2, 3; update header and converted-set comments.
- 3.2 Set `EXPECTED_TESTS` from the measured total of a full green run; record pre (811) and post in the PR body.
- 3.3 Re-measure `.claude/hooks/grep-q-pipe-guard.test.sh` derivation, `fixture-relative-assert.baseline.txt`, `scripts/guard-vacuity-floor.test.sh`, `lint-shell-trace-credential-refusal.test.sh`, ADR-280 census rows; fix code before baselines.

## Phase 3b: Deepen-pass test and hardening tasks

- 3b.1 Repoint every existing assertion that pins the old argv shape (the plan's C3 list: zot P13 920 `curl_words` 3 to 2; NIC stub 136-139, T1 314, golden 262-263 and 285-292, X2 461-467, negatives T2/T3/X1/X3/X6 backed by `TA_PING`; inngest 309, 577-580, 588-598, 608, 637-640, 674-677). Shared `CANARY_URL` becomes https; scope the stub rewrite to the `--config -` line.
- 3b.2 Zot stub: heartbeat calls recorded to their own files; one defect per hostile-value row with a per-row `reason=` assertion; stamp-age pairs bounded (1700/1900, 2000/3700); raise NIC `MIN_CASES` and zot `MIN_ASSERTS` from measured counts.
- 3b.3 `LC_ALL=C` before the case in the POSIX body; NIC refusal stamp under `${SOLEUR_NIC_TEST_ROOT:-}/run/`; unwritable-stamp row in each suite.
- 3b.4 Dash row: reuse the git-data rehearsal image layer, bounded pull retry, suite comment giving the reason.
- 3b.5 ADR-232 dated addendum (named-row GuardA predicate) alongside the ADR-280 paragraph; ADR text states the `/proc/<pid>/environ` residual (root for the web-1 probes, `deploy` for the inngest heartbeat unit; corrected in the review round), web-2 and inngest-host delivery timing.

## Phase 4: ADR-280 paragraph and gates

- 4.1 Append `### 2026-10-15 follow-ups - PR C (#10120, probe scripts of #10093)` to ADR-280 (after PR B's section); add a superseded note to the stale 2026-10-12 sentence about the three probe scripts.
- 4.2 Run the lead gate: `bash scripts/test-all.sh --affected`; read the selection against `--print-selection` and the BREAKDOWN line; run the directly named suites and the repo-wide ratchets of the plan's Acceptance Criteria; `bash plugins/soleur/test/c4-count-parity.test.sh`; `npx markdownlint-cli2` on touched markdown; `python3 scripts/lint-shell-trace-credential-refusal.py --changed`.
- 4.3 Run `cloud-init-inngest-bootstrap.test.sh` on the head; record the exact `FAIL:` lines and the drifted list; evaluate Gate 3.

## Phase 5: PR body and handoff

- 5.1 PR body: first line (merge fires the tag mint and three web-1 re-deliveries, opens the GuardA window), `Ref #10120`, `Ref #10093`, `Ref #9757`, the `### Pre-merge baseline` block, the #10330 e2e measurement, the sibling-PR rebase note (#10294, #10320), `Ruled by CTO agent, 2026-10-15` entries, pre/post `EXPECTED_TESTS`, and a final `## Operator Holds` section with Gates 1-6. No closing keyword anywhere.
- 5.1b PR body also: coupling note (the merge cuts a web release; web-2 and the inngest host are not re-delivered), Gate 7 (merge-tree evaluation, one open pin PR on the max tag), #10363 deferral, #10330 e2e measurement.
- 5.2 Mark ready only when every non-Gate-3 check is green; do not arm auto-merge; do not merge.
