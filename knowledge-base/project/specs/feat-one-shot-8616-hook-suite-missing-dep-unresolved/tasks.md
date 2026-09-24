---
title: "Tasks: hook suites that cannot run never report green"
plan: knowledge-base/project/plans/2026-09-24-test-hook-suite-missing-dep-not-green-plan.md
issue: 8616
branch: feat-one-shot-8616-hook-suite-missing-dep-unresolved
lane: procedural
---

# Tasks: #8616 hook-suite missing-dependency verdict

## 1. Setup (RED first)

- 1.1 Write `.claude/hooks/hook-suite-dep-unresolved.test.sh` (mode 100755), following the plan's
  "The regression suite" section.
  - 1.1.1 Header:
    - the taxonomy: tool missing = 3 + `UNRESOLVED: … install <tool>`; file under test missing = 1 +
      `FAIL:`; partial arm = non-zero + an `UNRESOLVED:` line for that arm;
    - the measured `run_suite` classification;
    - the fix is to install the tool, never `--no-verify`;
    - "editing this checker? run the plan's matrix".
  - 1.1.2 Take the roots from `bash scripts/test-all.sh --print-suite-globs`, keeping the entries under
    `.claude/hooks/`. Match guard lines with `(command -v|which) <tool>` plus `||` or `if !`. Exclude
    this suite itself (resolve its path with `cd -P … && pwd -P`, not `realpath`).
  - 1.1.3 Floor, using the exact spellings `counters_of` recognises:
    - `pairs_checked=$((pairs_checked + 1))` at the call site;
    - `MIN_PAIRS=40` on its own line, directly above a multi-line `if [[ … -lt … ]]; then … fi`;
    - on failure, `printf '[FATAL] …' >&2; exit 1` with the remediation text;
    - on success, print `N pairs (floor 40)`.
  - 1.1.4 PATH farm:
    - build it once, with one `ln -s "$d"/* "$farm"/ 2>/dev/null || true` per PATH entry, in order;
    - for each tool, move that tool's link aside, run the checks, then put it back;
    - run suites under `"$BASH"`, with no timeout wrapper, stdin from `</dev/null`, and output written
      to a file under `$ROOT`.
  - 1.1.5 `check_pair`: require `rc != 0` AND a line matching `^\s*UNRESOLVED: <tool> missing`. When
    RED, print the rc, the suite's last line, and the canonical one-liner.
  - 1.1.6 `scan_skip_exit0`: flag a string literal containing case-sensitive `SKIP` followed by
    `exit 0`, on the same line or the next non-blank line.
  - 1.1.7 Fixture self-test. Build fixture text from pieces so the suite never contains the pattern
    literally.
    - R-a: `UNRESOLVED` + `exit 0`. Must go RED.
    - R-b: `SKIP` + `exit 3`. Must go RED.
    - P-a: multi-line, irregular spacing. Must PASS.
    - P-b: peak-RSS SKIP with no exit. Must PASS.
    - P-c: `echo "$_skipnote"` + `exit 0`. Must PASS.
    - Exit 2 if any verdict is wrong or pass()/fail() did not move.
  - 1.1.8 Bash 3.2 compatible. One owning EXIT trap, before any `source`. No `| grep -q` in pipelines.
- 1.2 Add the suite to `PROMOTED_FILES` in `scripts/guard-vacuity-floor.test.sh`, with a comment entry
  in the sibling style. Record the ledger count from that suite's own run, before and after.
- 1.3 Run the new suite against the unconverted tree. Expect:
  - 37 pairs RED at rc 0;
  - 3 pairs RED at rc 1 with no `UNRESOLVED:` line;
  - the sweep listing the 35 one-line and 2 multi-line SKIP arms;
  - the self-test passing.

## 2. Core Implementation

- 2.1 One-liner guards: 18 files, plus `grep-rewrite`, which moves from exit 1 to exit 3. Replace each
  with `{ echo "UNRESOLVED: <tool> missing — this suite asserted nothing; install <tool>"; exit 3; }`.
- 2.2 Multi-line guards:
  - `security_reminder_hook`
  - `session-rules-loader`
  - `settings-hook-exec-bit`: exit 1 becomes exit 3
  - `hook-input-contract`: `summary; exit 3`
- 2.3 File-under-test arms become `FAIL: <path> not found`/`exit 1`:
  - `context-reviewed-gate` `$HOOK`
  - `pre-merge-auto-close-scan` `$SCANNER`
- 2.4 `hookeventname-coverage`: the jq branch prints the `UNRESOLVED:` line for that arm and sets
  `fail=1`. The `exit "$fail"` line stays unchanged.
- 2.5 `pre-merge-rebase-parity`:
  - the jq guard exits 3 (the results line is kept);
  - the git guard moves to the canonical form;
  - `skip()` prints `echo "  UNRESOLVED: $1"`;
  - reword the surrogate-payload arm message and the python3 arm message;
  - leave the counters, the results line and the floor block byte-identical.
- 2.6 Rewrite the rationale comments:
  - `hook-input-contract`: record the reversal of #7190 item 5 under #8616, and answer (a)–(d);
  - `grep-rewrite`;
  - `settings-hook-exec-bit`;
  - `security_reminder_hook`.

## 3. Testing and verification

- 3.1 The new suite exits 0 and prints `40 pairs (floor 40)`. The sweep is clean and the self-test
  passes.
- 3.2 Each of the 25 edited suites exits 0 when run individually on a normal PATH.
- 3.3 Run M1–M10, H1, H1b, H2 and H3 once each, and quote each output line in the PR body.
- 3.4 CI-form lints:
  - `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base HEAD origin/main)"`
  - `python3 scripts/lint-trap-tempfile-ownership.py`, plus `--check-highwater`
  - `bash scripts/lint-orphan-test-suites.sh`
  - `bash scripts/guard-vacuity-floor.test.sh`
  - `shellcheck` on the new suite
  - Nothing to run for eslint (no `.ts` in the diff); say so in the PR.
- 3.5 Neighbour suites:
  - `stub-argv-fidelity`
  - `grep-q-pipe-guard`
  - `settings-hook-exec-bit`
  - `hookeventname-coverage`
  - `memory-backstop`
  - `plugins/soleur/test/fixture-relative-assert.test.sh`
  - Do NOT run `scripts/test-all.sh` unscoped.
- 3.6 Confirm `git diff --quiet origin/main -- scripts/test-all.sh .github/workflows/ci.yml` (AC6).
- 3.7 The PR body has `Closes #8616`, links #8773, and renders `decision-challenges.md`.
