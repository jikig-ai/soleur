# Tasks: pipefail early-exit-consumer flake class (PR-1)

Plan: `knowledge-base/project/plans/2026-10-05-fix-ci-flakes-pipefail-early-exit-consumers-plan.md`
Branch: `feat-one-shot-ci-flakes-queue-slowness-9482`. PR body uses `Ref #N` only, never `Closes`.

## Phase 0: measure RED first (informational)

- 0.1 Reap suite only: 24 parallel copies with `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE`; count
  suites with a `FAIL:` line (the suite exits 97 on an inherited git-location variable). Cron never reproduced
  locally; no cron stress claim.
- 0.2 Luks race demo: extract the `reassert` step body, hold the producer, non-draining stub; expect
  `unavailable unparsed` and a non-zero probe rc.

## Phase 1: fixes (one commit per suite; floor bump in the commit with its rows)

- 1.1 `reap-archive-persistence.test.sh`: all 11 sites become `grep -q X < <(producer)` (keeps the one-line
  shape in the `if ... \` chains at 370 and 499; negations keep `!`).
- 1.2 `cron-egress-firewall.test.sh`
  - 1.2.1 Rewrite the 33 sites (31 lines) `echo "$V" | grep -q... PAT` to `grep -q... PAT <<<"$V"`, global and
    quote-aware; hand-review sites whose `$V` can start with `-`.
  - 1.2.2 Throwaway inverse diff over changed lines only: 33 segments; afterwards 34 here-string sites, 0 pipe-fed.
  - 1.2.3 Discriminating sandbox row: flip the census pattern at the `m$k` site; the suite must go RED.
- 1.3 `workspaces-luks-verify-workflow.test.sh`
  - 1.3.1 `drive()`: add `</dev/null` to the `bash -e "${REASSERT:-...}"` call (:690).
  - 1.3.2 `sshstub` probe arm drains stdin unless `FIXTURE_NO_DRAIN=1`; export the knob through `drive`'s env
    list; comment cites the real-ssh contract.
  - 1.3.3 Line 722: `grep -q ... < <(tr '\r' '\n' < "$f")`.
  - 1.3.4 `slow_printf` helper (handshake on a sentinel touched only by the no-drain stub on the
    `luks-monitor.sh` call, bounded ~5 s); rewrite the single `printf 'DOPPLER_TOKEN` call; landing check
    (`^slow_printf 'DOPPLER_TOKEN` exactly once, body differs); row 1 slow body vs draining stub = `selftest`;
    row 2 vs `FIXTURE_NO_DRAIN=1` = `unavailable/unparsed`, probe rc outside {0,3,127,255}; both under
    `(trap '' PIPE; ...)`; no conditional rows.
  - 1.3.5 Raise `WF_MIN_ASSERTIONS` to the exact new green count in the same commit.
- 1.4 `.claude/hooks/grep-q-pipe-guard.test.sh`
  - 1.4.1 Header first: correct the falsified 64 KiB statements; state luks producer-side is held by the race
    rows; cross-reference T4 (`tests/scripts/test-sentry-full-root-apply.sh:340-380`) for the runtime control.
  - 1.4.2 `FILES_7376` (three suites), tracked-file check, distinct member-count pin (3).
  - 1.4.3 Pass `grep-q-zero-7376-pass` via a DEDICATED scan function (PATTERN + PATTERN_AWK_EXIT, comments
    stripped), not `scan_scorers`; non-vacuity probe drives it; add negated-site and `< <(` good/bad pairs.
  - 1.4.4 No new runtime control; no `sigpipe-demo` marker needed; do not add the guard file to `FILES_7376`.
- 1.5 Hand-add the three suite paths to `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS`
  (`scripts/lib/test-affected-paths.sh`, ~line 1399); `bash scripts/lint-orphan-test-suites.sh`.
- 1.6 Ratchets: `bash plugins/soleur/test/fixture-relative-assert.test.sh` (baseline: luks 18, cron 5, reap 1,
  exact), trap-ownership lint, shellcheck on the three suites.

## Phase 2: mutation checks (prove each mutation landed; tree clean afterwards)

- 2.1 Guard 1: wiring row per real file (append a bad line in place, restore via trap, `git diff --numstat`
  shows 1 added line), dispatch row (wrong array / empty / renamed; run with `</dev/null`), second-member
  heredoc probe, shape-variety probe.
- 2.2 Guard 2: delete drain; rewrite matches nothing or twice; delete a race row; unrewritten new pipe;
  `sleep 20 | timeout 8 bash <suite>` with `</dev/null` removed (one-off).
- 2.3 Label any surviving mutant: fixtures do not exercise it, or equivalent (proved).

## Phase 3: verification

- 3.1 Suites green serially (cron 308/0, reap 45/0, luks 313 plus 2 rows / 0).
- 3.2 Informational loaded runs (reap, luks).
- 3.3 Guard prints `grep-q-zero-7376-pass`; `bash scripts/test-affected-derive.test.sh`;
  `python3 scripts/lint-guard-contract.py`; `npx markdownlint-cli2` on plan and this file.
- 3.4 No diff under `infra/github/**`; ADR-270 untouched.
- 3.5 Open the DRAFT PR; its first Infra Validation and `test-scripts` runs are the verification gate.

## Phase 4: trackers and PR (after the legs are green)

- 4.1 Idempotent comments (marker check first), PR linked as pending merge: #7376, #7432, #9217 (cross-link
  #7005/#6601), #8785, #9167, #9170, #8022, one observation on #9482. No new issues.
- 4.2 Compound: extend the existing 2026-09-25 SIGPIPE learning (producer-side variant, `echo` EPIPE evidence,
  ignored-SIGPIPE rc 1).
- 4.3 PR body: `Ref #7376`, `Ref #7432`, `Ref #9217`; three load-bearing mutation outputs; informational
  stress counts.

## Follow-ups (separate PRs, existing trackers)

- PR-2 e2e (#8785, #9170, #9167): self-host Inter with `next/font/local`, static ban on `next/font/google`,
  scope the `role=status` assertions. Highest queue-ejection lever; starts right after this PR is opened, not
  gated on it.
- PR-3 live-verify (#8022): diagnosis-first discriminating FAIL detail in `scripts/live-verify/run.ts`;
  sequence guard in `fetchConversations` only if H-A is confirmed.
