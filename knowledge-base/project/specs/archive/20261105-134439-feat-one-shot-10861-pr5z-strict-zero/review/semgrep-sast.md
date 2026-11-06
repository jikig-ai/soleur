# Semgrep SAST — PR #12127 (feat-one-shot-10861-pr5z-strict-zero)

Seat: `soleur:engineering:review:semgrep-sast` · report-only
Worktree: `/data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-10861-pr5z-strict-zero` @ `79db88e18b`
Base: `origin/main` (fetched during review)

## Rule packs / tools used

- `semgrep 1.181.0` (OSS) — `scripts/ci-pr-affected-replay.py`
  - `--config plugins/soleur/skills/review/references/semgrep-custom-rules.yaml` (5 custom `soleur.*` rules; JS/TS-focused, contributed as multilang)
  - `--config auto` (registry: 1074 community rules → 245 python + 47 multilang applicable; 292 rules run, ~100% of lines parsed, 1 target)
- `shellcheck 0.11.0` (`-x`, SC1091 excluded) — the three `.sh` files, since OSS semgrep cannot parse shell end-to-end:
  - `plugins/soleur/test/ci-pr-affected-replay.test.sh`
  - `scripts/lib/test-affected-paths.sh`
  - `scripts/test-all.sh`

## Verdict

**0 findings attributable to this PR's diff hunks.** Nothing at P1/P2/P3 on changed lines.

## Raw tool output vs diff intersection

| File | Changed lines (new side) | Tool findings | Findings inside hunks |
|---|---|---|---|
| `scripts/ci-pr-affected-replay.py` | 140, 149, 151, 2058–2060 | 1 (see below) | 0 |
| `plugins/soleur/test/ci-pr-affected-replay.test.sh` | 77, 2285, 2473–2474, 2503, 2511, 2515, 2681, 2683, 2899–2900, 4889–4892 | 29 (28 note, 1 warning) | 0 |
| `scripts/lib/test-affected-paths.sh` | 519–523 | 0 | 0 |
| `scripts/test-all.sh` | 7376 | 22 (8 warning, 14 note) | 0 |

## Pre-existing findings (out-of-diff, informational only)

- **P3** `scripts/ci-pr-affected-replay.py:1859` — `python.lang.security.audit.exec-detected` (WARNING): `exec(compile(p.stdout, "<merge-base>/" + RATCHET_LINT, "exec", …), mod.__dict__)` executes the merge-base copy of `lint-ratchet.py` read via `git show`. Identical line exists at `origin/main:scripts/ci-pr-affected-replay.py:1859`; not touched by this PR. Input is committed content at the resolved merge-base SHA, not external/user-controlled input, and the surrounding code deliberately refuses PR-tree copies. No action required by this PR.
- **P3** `plugins/soleur/test/ci-pr-affected-replay.test.sh:3795` — `SC2209` (warning): `OW_COMM=comm` reads as intended (literal assignment, not command substitution); shellcheck heuristic only. Line 3795 is not in the diff (nearest hunk 2899–2900 / 4889+).
- 28 remaining `note`-level findings in the test file (SC2086 unquoted vars, SC2012 `ls`, SC2006 backticks, SC1003) and 22 in `scripts/test-all.sh` (SC1010, SC2053, SC2319, SC2155, SC2004, SC2086, SC2018/2019, SC1001) — all on unchanged lines; pre-existing test-harness style noise.

## In-diff security review of the new code

The only executable change is the new `baseline-reintroduced` finding block (`scripts/ci-pr-affected-replay.py:2058-2060`): a `findings.append` building marker/remedy strings via `%`-formatting over `q(rel)`/`rel` — the same quote-then-render pattern as the adjacent `baseline-deleted` block, no subprocess, no eval/exec, no new file or network access. The `.sh` hunks are comment text, a `DECLARED_TOTAL` constant bump, a `--rows` range bound, a new `AFFECTED_*` path array, and test-row/mutant registrations — no new quoting or injection surface.

## Tool coverage notes

- Semgrep OSS has no bash parser: all three `.sh` files were covered by `shellcheck` instead, per seat instructions. `scripts/lib/test-affected-paths.sh` parsed clean (0 findings); the other two produced only pre-existing note/warning noise outside the hunks.
- The custom rules file ships JS/TS TOCTOU rules (`soleur.js-*`); they loaded (5 rules) but have no applicable target in this Python/shell-only diff — expected, not a gap.
- Control: the zero-in-diff result is backed by a live-fire control on the same config set — the packs fired `exec-detected` on this very file, proving rules are active and parsing is complete (~100%). A synthetic known-bad control was not needed.
- `Ran N rules on 0 files` void condition did not occur (1 target scanned, 292 rules).
- The large test file lives under `plugins/soleur/test/` but was never semgrep-scanned (shell only), so the `.semgrepignore` test-path void does not apply; shellcheck covered it fully.

## Summary

This PR turns the "base absent / HEAD present" baseline state from silent adoption into an unconditional `baseline-reintroduced` exit-1 verdict (strict zero end-state), updates the replay test battery to pin the new behavior (including mutants for tolerated/live-gated/content-weakened variants), adds an affected-paths array for a new wiring test, and bumps the row-count constants. Semgrep (custom + auto packs, 292 rules) and shellcheck together report **zero findings on any changed line**; the single semgrep hit (`exec-detected`, line 1859) and all shellcheck items are pre-existing and out-of-diff. No security concerns introduced by this diff.
