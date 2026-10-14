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
