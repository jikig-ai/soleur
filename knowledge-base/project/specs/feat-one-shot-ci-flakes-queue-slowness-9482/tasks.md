# Tasks: pipefail early-exit-consumer flake class (PR-1)

Plan: `knowledge-base/project/plans/2026-10-05-fix-ci-flakes-pipefail-early-exit-consumers-plan.md`
Branch: `feat-one-shot-ci-flakes-queue-slowness-9482`. PR body uses `Ref #N` only, never `Closes`.

## Phase 0: measure RED first

- 0.1 Informational baseline: 24 parallel copies of `reap-archive-persistence.test.sh`; count suites with a
  `FAIL:` line. (Cron never reproduced locally; no cron stress claim.)
- 0.2 Re-run the luks race demo (extract the `reassert` step body, delay the producer 0.4 s, stub that
  does not drain stdin): expect `unavailable unparsed` and a non-zero probe rc. Save output.
- 0.3 Write the new luks race rows and the guard's `FILES_7376` pass first; confirm RED against unfixed suites.

## Phase 1: fixes

- 1.1 `reap-archive-persistence.test.sh`
  - 1.1.1 All 11 sites (3 `ls`, 6 `git log`, 1 `git show`, 1 `git diff`) use one capture-then-here-string
    idiom with a distinct variable name; keep `!` placement.
- 1.2 `cron-egress-firewall.test.sh`
  - 1.2.1 Rewrite the 33 sites (31 lines) `echo "$V" | grep -q... PAT` to `grep -q... PAT <<<"$V"`,
    global and quote-aware; hand-review sites whose `$V` can start with `-`.
  - 1.2.2 Throwaway inverse-transform diff: exactly 33 changed segments; guard rescan finds zero.
- 1.3 `workspaces-luks-verify-workflow.test.sh`
  - 1.3.1 `sshstub` drains stdin at the top (`[[ -p /dev/stdin ]] && cat >/dev/null`), with a comment.
  - 1.3.2 Convert the `tr ... | grep -q` site (line ~722).
  - 1.3.3 New helper (not `hk_mutant`): rewrite the single `printf 'DOPPLER_TOKEN` token to `slow_printf`
    (0.4 s delay), `grep -c` landing check; row 1 delayed body vs draining stub classifies `selftest`;
    row 2 vs `FIXTURE_NO_DRAIN=1` classifies `unavailable/unparsed` with probe rc outside {0,3,127,255}
    (never assert 141: CI ignores SIGPIPE and printf returns 1).
  - 1.3.4 Raise `WF_MIN_ASSERTIONS` to the new exact green count in the same edit.
- 1.4 `.claude/hooks/grep-q-pipe-guard.test.sh`
  - 1.4.0 First update the guard header comment (falsified 64 KiB statements).
  - 1.4.1 `FILES_7376` (three suites), tracked-file check, distinct member count pin (3).
  - 1.4.2 Pass `grep-q-zero-7376-pass` via a DEDICATED scan function (PATTERN + PATTERN_AWK_EXIT, comments
    stripped), not `scan_scorers`; the non-vacuity probe drives the same function.
  - 1.4.3 One runtime control (reuse the `yes | grep -q y` pattern from test-sentry-full-root-apply.sh):
    needle on line 1 plus >= 200 KB after it; old shape non-zero under SIGPIPE default and `trap '' PIPE`;
    here-string and capture shapes return 0; named "environment cannot exhibit the race" result.
  - 1.4.4 Update the header comment (64 KiB statements) with the measured correction.
- 1.5 `bash scripts/test-affected-derive.test.sh`; regenerate the guard's declared-edge block in
  `scripts/lib/test-affected-paths.sh` only if it fails.

## Phase 2: mutation checks (assert each mutation landed with cmp or a grep -c count)

- 2.1 Guard 1 rows 1-5 (checked-in probe fixtures; row 4 with `</dev/null`).
- 2.2 Guard 2 rows 1-4.
- 2.3 Guard 1 harness row (delete the control).
- 2.4 Label any surviving mutant: fixtures do not exercise it, or equivalent (proved).

## Phase 3: verification

- 3.1 Three suites green serially (cron 308/0, reap 45/0, luks 313 plus new rows / 0).
- 3.2 Informational: same recipe as 0.1 on the fixed tree (reap, luks); run the guard control 50 times loaded.
- 3.3 `bash .claude/hooks/grep-q-pipe-guard.test.sh` prints `PASS: grep-q-zero-7376-pass`;
  `python3 scripts/lint-guard-contract.py` and `npx markdownlint-cli2` clean on plan and this file.
- 3.4 Confirm no diff under `infra/github/**` and no ADR-270 edit.

## Phase 4: trackers and PR

- 4.1 Comment on #7376, #7432, #9217 (cross-link #7005/#6601), #8785, #9167, #9170, #8022 and one observation on #9482
  (see the plan's tracker fold list). No new issues.
- 4.2 Compound: extend the existing 2026-09-25 SIGPIPE learning (producer-side variant, `echo` EPIPE evidence,
  ignored-SIGPIPE rc).
- 4.3 PR body: `Ref #7376`, `Ref #7432`, `Ref #9217`; three load-bearing mutation outputs and
  informational stress counts pasted.

## Follow-ups (separate PRs, existing trackers)

- PR-2 e2e (#8785, #9170, #9167): self-host Inter with `next/font/local`, static ban on `next/font/google`,
  scope the `role=status` assertions. Highest queue-ejection lever; start next.
- PR-3 live-verify (#8022): diagnosis-first discriminating FAIL detail in `scripts/live-verify/run.ts`;
  sequence guard in `fetchConversations` only if H-A is confirmed.
