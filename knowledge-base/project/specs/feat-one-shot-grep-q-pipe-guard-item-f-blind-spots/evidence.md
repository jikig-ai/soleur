# Evidence: grep -q pipe-guard, Item F (guard blind spots)

Branch `feat-one-shot-grep-q-pipe-guard-item-f-blind-spots`, draft PR #10327, tracker #9217 (`Ref`, never `Closes`). Measured 2026-10-15 on the branch merged with `origin/main` at `30407a8597`. Each figure carries its command; counts rot, so re-measure before quoting one. The Phase 0 to 5 sections are the first-pass state at `a52a0ebc4a` (the commit the review panel read); the last section, "Review round", gives the final figures and the commands that produce them.

## Phase 0 (read-only, before any guard edit)

| What | Command | Result |
|---|---|---|
| Base guard at merged main | `bash .claude/hooks/grep-q-pipe-guard.test.sh` | exit 0; `1862 files swept`; join `151 derived pairs, 264 producer triples; 23 of 23 drains rows, 129 exempt rows, 152 of 152 rows`; wall time 1m19s at load average 55 (18.6 s at load 7 at plan time) |
| Reader classification over the swept population (PLAN-TIME population: 8 extensions, all of knowledge-base excluded, 1,858 files; the review round re-measured over the guard's 13 extensions, see the last section) | `python3 -I knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-f-blind-spots/j0-measure.py` (at the review round it reads the guard's extension list) | plan time: awk-exit 41 single-line + 13 multi-line, `head -N` 575 `head -1` + 179 other, `read` 3, variable binary with an early flag 1 (a `-hmac`, not a reader), without 709; 25 functions with a stdin early-exit grep body |
| Widened pattern, live tree | `bash knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-f-blind-spots/j0-pattern-prototype.sh` | `shipped=33 widened=33` (0 only in the widened set); fixture table ok; the two stated false positives (`grep -c p -eq`, `xargs echo grep -q p`) still match |
| Marker census | `git -c core.excludesFile=/dev/null grep --no-index --exclude-standard -c -E '<ALLOW_MARKER>' -- <SWEEP_PATHSPEC>` | 25 marked lines in 12 files outside knowledge-base, guard excluded (matches the plan's 25 / 12) |
| Open-PR screen | `bash knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-f-blind-spots/j0-pr-screen.sh` (added lines of each open PR in a newly read file class, widened pattern) | 25 PRs with files in a newly read class, 0 added-line hits (the only matches printed were this branch's own `.txt` fixtures, which are not swept) |

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

Fenced lines outside knowledge-base that match the widened pattern: 18, all in fences without pipefail, in **6** SKILL.md files (the plan said 8); other prose lines: 9 at the first pass (the plan said 12; the final pattern, which also reads `sh -c` behind wrappers, gives 12 again: `j0-md-figures.sh`, last section). Hits under knowledge-base archive directories: **14 in 6** scripts (the plan said 13 in 5; one more script was archived since). Both are written into the guard header with the new figures.

## Review round (PR #10327; panel SHA `a52a0ebc4a`, fix round commits after it)

Ten seats read the pinned SHA (semgrep, agent-native, history, architecture, security, performance, pattern, enumeration, quality, test design). No P1. Every finding was fixed inline except the stated limits below; rulings are rows 21 to 32 of `decision-challenges.md`.

### What changed, by finding class

| Class | Finding | Fix | Pinned by |
|---|---|---|---|
| Predicate narrower than the property | split pass missed `x \| \`, `x \|\`, `x \| # c`, a backslash-continued next line, JS comments between | awk joins all four, skips JS-family comment lines | fixtures `split-backslash`, `-bar-backslash`, `-bar-comment`, `-continued`, `-chain3`, `-js-between`, `-comment-bar`, `-js-comment`; rows G2-12-* |
| | fence pass named an unclosed fence after the NEXT file | file name taken when the fence opens | `md-unclosed-a` / `-neighbor` (a non-last file); G2-10c, G2-10d |
| | markers in a fence exempted a hit with no pin entry | markdown pass never honours the marker | `md-marker`; G2-10g |
| | SHC was a narrower hand copy of lead/wrap/bin/arg/early | built from the shared parts, plus `zsh ksh dash`, a path to the shell, `-o NAME` | 14 `shc-*` cases; rows M5-shc-*, M5-shell-* |
| | EARLY terminator was a fixed class (`grep -q'p'`, `-q>/dev/null` fell out) | any non-word character | 6 `early-term-*` cases; M7e, M7f |
| | comment lists hand-typed, `.js` in both, `*)` read as a JSDoc line, `.tf` `//` read as code | one list per swept extension, pinned by `SWEEP_COMMENT_STYLES`; star rule `\*([[:space:]/]\|$)` | 26 per-extension fixtures; `ts-star-paren`; G3-6* |
| Check that cannot fail | real-tree arm of both passes could be stubbed (0 hits either way) | each awk prints a count; floors with required arguments and literal minimums | ST1 to ST3, F1 to F7; `md-floor-lower-bound`, `md-floor-truncated` |
| | the fixture dispatch could go dead (29 calls inside 4 checks) | call counts pinned, recorders and router driven on a synthetic scan | `ml-dispatch`; G2-13-* |
| | `spec-dir-zero` passed on an empty scan | requires the real scan's `SWEPT` first line | G3-10b |
| | `MD_FLOOR` could drop to 1 and the comparison be disabled | `SWEEP_MD_FLOOR` with `_MIN`, probe calls expecting rc 3 | F1 to F5 |
| Cost | +31 s CPU from two un-prefiltered `git grep -E` scans | `-e '\|' --and -e PATTERN`, split-awk fast reject, marker census prefilter | `pattern-bar-prefilter`; M10, M10b |
| Operand / name handling | awk read a root file `A=b.sh` as an assignment | every operand is `./name`, printed without the prefix | `split-assign-name`; G2-12-assign |
| | git quoted non-ASCII paths (awk could not open them, rc 3 repo-wide) | `core.quotePath=false` | `split-nonascii-name`; G2-12-quote |
| | a non-UTF-8 line became "Binary file matches" and the hit vanished | `-a` on the comment filter and the final pass | `split-nonutf8`; G2-12-binary |
| Mutation blind spots | member-level survivors (`ionice`, `zegrep`, the `d D f A B C` letters, `da`) | one case per member, a row each | 36 new cases; M2-ionice, M5-zegrep, M5-arg-*, M5-shell-* |
| Prose | stale or unreproducible figures, a stale STILL OPEN paragraph, "outside knowledge-base" marker wording | header rewritten, every figure re-measured with its command (below) | `j0-md-figures.sh`, `j0-measure.py` |

### Final figures, with the command that produced each (2026-10-15)

| What | Command | Result |
|---|---|---|
| Swept population | `git grep -al -e ''` under `SWEEP_PATHSPEC` (the guard prints it) | 4,494 files |
| Classification over the 13-extension population | `python3 -I j0-measure.py --samples 0` | `head -N` 760 lines (578 `head -1`) in 290 files; awk exit 42 single-line + 13 multi-line; `read` 6 lines (perl payload strings, jq filters and markdown tables: none a reader); variable binary 866 stages without an early flag, 1 with one (`-hmac`); 25 functions with a stdin early-exit grep body; trailing-bar joined logical lines 82, 9 of them with a reader stage |
| `sed ...q` | `git grep --no-index -anE '\|[[:space:]]*sed[[:space:]]+[^\|]*([0-9$]\|!)q([^[:alnum:]_-]\|$)'` over the swept pathspec, comment lines dropped | 1 line (`plugins/soleur/test/preflight-check10-suite-integrity.test.sh:238`, a `!q` filter) |
| Markdown | `bash j0-md-figures.sh` | 18 matching lines inside fences without pipefail in 6 files, 0 inside a pipefail fence, 12 in prose |
| Extensionless shebang scripts | tracked files without a dot whose first two bytes are `#!` | 6, 0 hits |
| Archived hits | `j0-pattern-prototype.sh`, archived scripts | 14 in 6 scripts |
| Markers | `git grep --no-index -c -E '<ALLOW_MARKER>'` over `SWEEP_PATHSPEC` | the 12 rows of `SWEEP_MARKER_PIN` |
| Real-tree pass counts | guard internals (`SPLITJOINS`, `FENCELINES`, `MDSWEPT`) | 415 joins, 676 fence lines, 21 markdown files; floors 300 / 500 / 18 (minimums 250 / 400 / 15) |
| Widened pattern, live tree | `bash j0-pattern-prototype.sh`; the guard's 0 undeferred hits | shipped = widened hits (33 = 33), 0 new hits |
| Wall and CPU, base vs head back to back (load average 18 to 24, other sessions running) | `time` of the guard under `ulimit -v 6000000`, a `git archive origin/main` copy vs the branch | base 28.2 s real / 31.1 s user; head 31.7 s real / 32.8 s user (the panel's head, before the prefilters: 18 s real / 44 s user at load 5; base 12 s / 17 s) |
| Guard size | `git diff --numstat origin/main -- .claude/hooks/grep-q-pipe-guard.test.sh` | +705 / -82 |
| Pins | recompute recipes in the guard header | `V2_CASE_COUNT=103`, `V2_BAD_LINES=32`, `V2_GOOD_LINES=14`, fp pinned 2, `SWEEP_EXT_COUNT=13`, `SWEEP_CANARY_COUNT=9`, `SWEEP_TEST_CANARY_COUNT=10`, `SWEEP_PROBE_CHECKS=77`, `ML_WANT_CALLS=32`, `ML_NOT_CALLS=19` |

The plan-time and first-pass figures for the `head -N`, awk and variable classes (754 / 41 / 709) were measured over the 8-extension population (1,858 files) while the issue and the header called them the 13-extension figures; the table above is the final population. The first-pass prose figure (9) and the plan's (12) were readings of a changing pattern; 12 is the final pattern's.

### Battery after the fix round (AC-6)

`python3 -I mutation-battery.py`: **161 of 161 rows RED** on the fix-round guard (`battery-results.txt`), both controls green (fast 11 s, full 16 s), one mutant at a time under `ulimit -v 6000000` in a `scripts/soleur-sandbox.sh` sandbox. The environment is pinned to `LC_ALL=C.UTF-8` (the non-UTF-8 fixture only differs from a plain line in a UTF-8 locale). `mutation-rows.json` is the artifact (generated from the guard text by a scratch script that is not committed: its anchors are literal reader shapes, which the sweep would read in this directory); the driver stops the run on any anchor that does not land. Re-aimed after the first run of this round: M4b (a mutant that broke the quoting of the string it edited), M10 (a wrong prefilter trips the split floor first; M10b switches the floor off to show the probe sees it too), G2-12-cmt, G3-2-* and G2-3, G2-5b, G2-7, G2-10f (a mutant that lowers the real-tree join or fence count trips its floor first; the floor is switched off in the mutant so the named fixture is what reds), G3-6b (the star rule and the list are two layers; both are mutated), G2-12-js (the fixture covered the trigger skip but not the skip between the bar and the reader; now a fixture and a row each).

Guard under other environments, same fix-round text: `( trap '' PIPE; ... )` exit 0; `env -i` exit 0; `ubuntu:24.04` with **mawk 1.3.4 20240123** and git 2.43 exit 0 with the same 9 PASS lines (the sandbox copy sweeps 4,488 files: it omits the archived records); gawk 5.4.1 on the host. `shellcheck -S warning`: 0 findings. `lint-shell-capture-exit` (baseline form), `guard-vacuity-floor`, `lint-orphan-test-suites`, `lint-guard-contract`, `lint-infra-no-human-steps` on the plan, and `scripts/test-affected-kb-consumers.test.sh` (30 of 30): exit 0.

### Stated limits (not fixed; the header STATED LIMITS and the `res` / `fp` cases pin each)

A relative or variable-prefixed binary (`./grep`, `"$DIR/grep"`), `/usr/bin/env grep`, an env assignment with a quoted value, `busybox grep`, an array expansion, `ack`, a process-substitution reader, one wrapper with more than four own tokens, a compound-command opener other than `{` and `(`, a split pipe inside a fence, a fence inside a blockquote or `<pre>`, git's regex cost on a physical line over ~100 KB (50 KB 0.4 s, 300 KB 9 s; the longest tracked line is 6 KB), the `--affected` selector's reach for plugins, `.github`, `scripts/*.py` and markdown, and a `pipefail` mention in a comment or `set +o pipefail` marking a fence (an over-read, never a miss).
