# Evidence: grep -q pipe-guard, Item F (guard blind spots)

Branch `feat-one-shot-grep-q-pipe-guard-item-f-blind-spots`, draft PR #10327, tracker #9217 (`Ref`, never `Closes`). Measured 2026-10-15 on the branch merged with `origin/main` at `30407a8597`. Each figure carries its command; counts rot, so re-measure before quoting one.

## Phase 0 (read-only, before any guard edit)

| What | Command | Result |
|---|---|---|
| Base guard at merged main | `bash .claude/hooks/grep-q-pipe-guard.test.sh` | exit 0; `1862 files swept`; join `151 derived pairs, 264 producer triples; 23 of 23 drains rows, 129 exempt rows, 152 of 152 rows`; wall time 1m19s at load average 55 (18.6 s at load 7 at plan time) |
| Reader classification over the swept population | `python3 -I knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-f-blind-spots/j0-measure.py` | 1,858 files (plan time) / same classes: awk-exit 41 single-line + 13 multi-line, `head -N` 575 `head -1` + 179 other, `read` 3, variable binary with an early flag 1 (a `-hmac`, not a reader), without 709; 25 functions with a stdin early-exit grep body |
| Widened pattern, live tree | `bash knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-f-blind-spots/j0-pattern-prototype.sh` | `shipped=33 widened=33` (0 only in the widened set); fixture table ok; the two stated false positives (`grep -c p -eq`, `xargs echo grep -q p`) still match |
| Marker census | `git -c core.excludesFile=/dev/null grep --no-index --exclude-standard -c -E '<ALLOW_MARKER>' -- <SWEEP_PATHSPEC>` | 25 marked lines in 12 files outside knowledge-base, guard excluded (matches the plan's 25 / 12) |
| Open-PR screen | `bash /var/tmp/itemf/pr-screen.sh` (added lines of each open PR in a newly read file class, widened pattern) | 25 PRs with files in a newly read class, 0 added-line hits (the only matches printed were this branch's own `.txt` fixtures, which are not swept) |

Reconciliation with the plan-time figures: no difference. The brief's guard figures (150 / 263 / 151) were one merge stale; the plan's base figures (151 / 264 / 152) are the merged tree's own. Join figures move only with main (#10322, #10081 edit the join table and `PJ_TRIPLES`).

## Notes carried forward

- The guard takes about 80 s at the load this host reaches during the full-gate queue; a wall-time claim needs `uptime` beside it.
- `scan_split` finds 8 trailing-bar logical lines whose joined text holds a reader stage by the classifier's loose test; the guard's own pass applies the widened pattern to the joined line, so the figure that matters is the guard's `split` result, recorded in the red-first and green runs below.
- Self-sweep (task 0.5): the widened pattern over every script in this spec dir (`*.sh`, `*.py`, `*.awk`) reports 0 lines; fixtures stay in `.txt` data and mutants are built with `printf`.

## Phase 1: red-first run (AC-2)

The case tables, the multi-line and population fixtures and the witnesses were added to the guard with the pattern, the pathspec and the comment filter unchanged. One run under `ulimit -v 6000000` (`bash .claude/hooks/grep-q-pipe-guard.test.sh`, RC=1). Verdict block, trimmed to the check names and the cases they name (the full lines carry long hint text):

| Check | First result |
|---|---|
| `v2-cases` | FAIL, 37 named cases: the 15 `wrap-*`, `bin-zgrep` `bin-rg` `bin-rg-long` `bin-ag` `bin-ugrep` `bin-pcregrep`, `var-dq` `var-brace` `var-bare` `var-default`, `arg-after-operand` `arg-context` `arg-d-skip`, `early-5q` `early-qui` `early-sil` `early-max` `early-max-c`, `shc-single` `shc-lc`, and the two stated false positives (`fp-eq`, `fp-xargs-echo`, which the old pattern does not match). Every `good` and `res` case reads PASS already (no `[good ..]` or `[res ..]` entry) |
| `v2-cases-negative` | PASS (the loop misses the wrapper cases when the wrapper part is removed) |
| `split-must-report` | FAIL: split-sudo split-line-number split-second-site (both sites) split-comment-next split-blank-next split-pipe-amp |
| `split-must-not` | PASS (nothing is joined yet) |
| `md-must-report` | FAIL: md-env-i md-pipefail-after-hit md-tilde md-indented md-long-fence (both lines) md-tilde-mismatch md-unclosed-fence md-crlf |
| `md-must-not` | PASS |
| `sweep-wiring-multiline` | FAIL (0 split-pass lines, 0 markdown-pass lines) |
| `ext-witness` | FAIL: ts tsx mjs cjs py not read |
| `floor-lower-bound` | FAIL (1400 against the literal 3500) |
| `kb-population` | FAIL: kb-witness, kb-archive-lookalike (the archive records stay unread, as wanted) |
| `comment-filter` | FAIL: ts-hash-line, py-slash-line (not read); no comment line kept |
| `test-canaries` | FAIL: the new `.test.ts` canary is not in the population |
| `ext-count`, `ext-expected`, `floor-truncated`, `marker-pin`, `spec-dir-zero` | PASS (their targets already hold) |
| `probe-count` | FAIL: 70 checks against the pinned 54 (recomputed at the end) |

Every must-detect case reads FAIL by name and every must-not case reads PASS, as the plan requires.

## Phase 2 to 5: results (AC-3 to AC-9)

| What | Result |
|---|---|
| Guard on the branch, clean tree (`git status --porcelain` empty), merged with main at `30407a8597` | exit 0, 9 PASS lines; `4493 files swept`; join `151 / 264 / 152` unchanged; wall time **24.4 s** at load average 12.9 (base **17.3 s** at 12.5, same host, measured back to back) |
| `SWEEP_DEFERRALS`, `GATED_TEST_ROWS`, `GATED_PROD_ROWS`, `GATED_PROD_GLOBS` (AC-4) | byte-identical to base (`git diff origin/main` shows no line inside any of them) |
| Stub test, `cd apps/web-platform && ./node_modules/.bin/vitest run test/scripts/run-migrations-unmerged-gate.test.ts` (AC-5) | base 8 passed, head 8 passed; its diff is the one stub line |
| Pins (AC-7) | `V2_BAD_LINES=32` (29 + the three moved residuals), `V2_GOOD_LINES=14`, false positives pinned at 2, `V2_CASE_COUNT=67`, `MD_FLOOR=18` (21 measured), `SWEEP_EXT_COUNT=13`, `SWEEP_FLOOR=4000` with `SWEEP_FLOOR_MIN=3500` (4,493 measured), `SWEEP_TEST_CANARY_COUNT=10`, `SWEEP_CANARY_COUNT=9`, `SWEEP_PROBE_CHECKS=71` (recomputed with the header recipe: 54 at base + 16 + 1) |
| Mutation battery (AC-6) | `python3 -I mutation-battery.py`: **85 of 85 rows RED** on the committed guard, one mutant at a time under `ulimit -v 6000000` in a scratch sandbox, both controls green (fast 10 s, full 25 s), each graded by the row's named substring; per-row lines in `battery-results.txt`; rows in `mutation-rows.json` |
| Guard under other environments (AC-6) | `( trap '' PIPE; ... )` exit 0; `env -i` exit 0; `ubuntu:24.04` with **mawk 1.3.4** and git 2.43 exit 0 with the same 9 PASS lines. gawk 5.4.1 is the only awk on this host besides that; busybox and original-awk are not installed (stated) |
| Guard's own added lines (AC-8) | the widened pattern over `git diff origin/main -U0` added lines matches only case-table text, fixture heredocs, planted-file writes and one comment line; no executable test line pipes into a grep reader (rows are selected into a variable or matched by here-string) |
| Repo-global lints (AC-9) | `lint-shell-capture-exit` (baseline form), `guard-vacuity-floor`, `lint-orphan-test-suites`, `lint-guard-contract` and `lint-infra-no-human-steps` on the plan, and `shellcheck -S warning` on the guard: all exit 0 / 0 findings. `test-affected-kb-consumers` reddened on three rows after the spec dir gained code files and the guard named the archive glob (main is green); `--write-baseline` adds exactly those three rows, no other change |

### Rows the first battery pass graded wrong, and what they taught

- **M3a** (`{0,4}` to `{0,1}`) first read WRONG-REASON on `wrap-env-i-path`: `env -i PATH=/bin` needs one wrapper token, because `PATH=/bin` is the separate `VAR=x` alternative. The two-token `sudo -u root` is the case that kills `{0,1}`; the row now names it. `wrap-env-i-path` stays as a case for the `VAR=x` arm.
- **M4** (unbounded operand run) first read WRONG-REASON: the must-not case closed its own quote, so no run length matched. The case is now the real cron-egress shape (a pipe inside a quoted argument, more quoted words, then `-eq`): one operand does not match it, an unbounded run does.
- **G2-11-orbar** survived: a logical OR is kept out by TWO layers (the file listing regex and the awk), so mutating the awk alone is an equivalent mutant. The row now mutates all three places.
- **G2-11-eof** survived: a bar at the end of a file is attributed to the NEXT file (awk's `FILENAME` is the current file when the join prints), and the next file must itself be listed. The fixture is now a pair, with a trailing bar in the second file, and a second must-not names the next file.
- **G3-4b** expected a live-tree red that the sandbox cannot show (the copy omits archived records); it now expects the named `kb-archive-must-not`.

### Corrections to plan-time figures (re-measured 2026-10-15)

Fenced lines outside knowledge-base that match the widened pattern: 18, all in fences without pipefail, in **6** SKILL.md files (the plan said 8); other prose lines: 9 (the plan said 12). Hits under knowledge-base archive directories: **14 in 6** scripts (the plan said 13 in 5; one more script was archived since). Both are written into the guard header with the new figures.
