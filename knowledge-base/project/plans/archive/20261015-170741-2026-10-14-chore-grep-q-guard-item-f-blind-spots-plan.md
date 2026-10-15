---
title: "chore: grep -q pipe-guard series, Item F (guard blind spots)"
date: 2026-10-14
slug: grep-q-guard-item-f-blind-spots
branch: feat-one-shot-grep-q-pipe-guard-item-f-blind-spots
issue: 9217
type: chore
lane: single-domain
---

## Enhancement Summary

**Deepened on:** 2026-10-15. **Method:** plan-time measurement (J0, J0b, J0c below), a CTO ruling on every fork, a two-seat plan-review panel (simplicity, test-design) with its outcomes recorded as `decision-challenges.md` rows 17 to 20, the deepen-plan mechanical halts (user-brand, observability, PAT, UI, encryption, Guard Contract lint, Scope Check) and live verification of every cited issue, PR, label, rule id and ADR. The all-agent fan-out was not run: every mechanism had already been read against the real guard and its fixtures by the two review seats and by the prototypes, and the remaining agents (Rails, UI, infra) have no surface here.

- Measured, not asserted: the widened reader pattern adds 0 hits over the 1,858-file population (33 equal 33) and passes a 64-line fixture table; the same text matches 38 of 38 bad and 0 of 26 good lines under `git grep -E` as well as `grep -E` (dialect check).
- Prototyped: both linearising passes (`j0-split.awk`, `j0-fence.awk`) reproduce every state row of Guard 2 under gawk default, `--posix` and `--traditional` (`j0-linearisers-check.sh`); mawk, busybox and original-awk are not installed on this host, so CI's awk stays the only reading of those (stated).
- Found by review and fixed in the plan: the sweep reads its own spec dir once item 9 lands (fixtures moved to a data file), `SWEEP_EXTS` built both the pathspec and its witness (a literal count and a typed expected list added), the residual fixture lives in `residual-v2.sh` (not `good-v2.sh`), and the marker pin's population now equals the swept files.
- Verified live: #9217, #7376, #6601, #7797, #9482, #10322, #10081 open; labels `semver:patch` and `app:web-platform` exist; `cq-write-failing-tests-before` is an active rule; ADR-119 exists; the one cited ADR is not an alternative the plan rejects.

## Overview

Item F of the grep -q pipe-guard series (tracker #9217; also #7376, #6601, #7797, #9482). `.claude/hooks/grep-q-pipe-guard.test.sh` finds `producer | grep -q` by a LINE regex (`PATTERN_V2`) over about 1,860 files, asserted zero outside a deferral table. Item F is what that search cannot see. The brief names nine blind spots; each either gets a detection row plus a mutation-pinned test, or is recorded as NOT fixed with its reason in the PR body and on #9217. The guard's own header names a tenth under Item F (the unbounded `# sigpipe-demo: intentional` marker); it is the last, cuttable arm.

Dispositions (rulings in `decision-challenges.md`, rows 1 to 13; measurements in `j0-plan-time-output.txt` and `j0-plan-time-pattern-output.txt` in the spec dir):

| # | Blind spot | Live sites | Disposition |
|---|---|---|---|
| 1 | Wrappers around the reader (sudo, doas, time, nohup, setsid, xargs, env/nice/timeout/stdbuf with flags, command -p, `sh -c '...'`, zgrep, rg, ag, ugrep, pcregrep) | 0 | CLOSE: widen WRAP and BIN, add `sh -c` alternative |
| 2 | Flag order (`grep P -q`, `-d skip -q`, `--context N -q`, `-5q`, `--qui`, `--max=1`) | 0 | CLOSE: one bare operand allowed between flags, quote-aware, long-option abbreviations |
| 3 | `head -N` as the early-exit reader | 754 lines (575 `head -1`), 306 files | NOT FIXED in the sweep; residual pin; the chain `x \| head -1 \| grep -q p` is already caught by its grep half and gets a fixture |
| 4 | Split-line pipe (pipe ends the line) | 0 of 219 joins | CLOSE: join pass, folded into `scan_sweep` |
| 5 | Multi-line awk with early exit (and awk exit across the sweep) | 13 multi-line + 41 single-line | NOT FIXED: needs a program-extent parser, protects value-extraction captures; wave issue filed at ship |
| 6 | Reader behind a variable or function | 0 and 0 | CLOSE the GREP-named variable rule; NOT FIXED: other variable binaries (709 stages, no early flag), function readers (25 candidates, 0 call sites) |
| 7 | `.md` fenced command examples | 18 fenced lines (0 in a pipefail fence), 12 inline | CLOSE as a property: a fence that holds pipefail AND an early-exit pipe; the 30 pipefail-free lines NOT FIXED |
| 8 | `.ts` files that shell out | 1 real (a bash stub string in a test), 1 JSDoc comment | CLOSE: extension list gains ts tsx mjs cjs py, per-language comment filter, convert the one stub line |
| 9 | kb scripts | 0 non-archive; 13 in 5 archived scripts | CLOSE for code extensions outside `archive/`; the 13 archived hits NOT FIXED (frozen records) |
| 10 | Marker hole | 25 marked lines in 12 files | Per-file pinned block (last, cuttable) |

## Research Insights

**Premise validation (Phase 0.6).** #9217, #7376, #6601, #7797, #9482 are open (`gh issue view`); PRs #10322 and #10081 are open and touch the guard only in the join table and its pins (`gh pr diff`: rows plus `PJ_TRIPLES`). The brief's guard figures (150 pairs / 263 triples / 151 rows) are one merge stale: the guard at base `b39ab6cd40` prints 151 pairs / 264 triples / 152 rows and exits 0. The mechanism (extend a line regex) is not in an ADR's rejected alternatives (ADR corpus grep for pipe-guard, pipefail grep: ADR-119 only, which bans the idiom). Open-PR screen (28 PRs, 27 touching a newly read file class): 0 added lines match the widened pattern in a newly read class.

**Property list (Phase 0.6b).** P1: a reader in any listed spelling is reported wherever the sweep reads. P2: the sweep reads every file class that carries shell text a person or an agent runs. P3: a hole that stays is stated with its measurement and pinned so widening it is a visible edit. P4: a new unreported bypass of the sweep cannot land silently (marker).

**Self-sweep (plan-review P1).** Once item 9 lands, the sweep reads non-archive `knowledge-base/**` code files, which includes this spec dir. A fixture heredoc inside a spec-dir script would match the widened pattern (the prototype's did: 5 lines under the shipped pattern, about 28 widened). Fixtures therefore live in data files (`j0-pattern-fixtures.txt`; `.txt` is not swept) and any script in the spec dir (`mutation-battery.sh`) builds mutants with `printf` from data, never as a literal shape; Guard 3 carries a `spec-dir-zero` row.

**Cut list.** A derived function-reader set (CTO: an unsound shell parser for 0 call sites); a multi-line awk detector (program-extent parser, 13 sites); a `head -N` ratchet (churns, buys no property); file-exact deferral rows for the 18 fenced lines (documents harmless snippets); converting the SKILL.md fences (fenced files, body budget); a second `PATTERN_V3` (leaves V2 dead); a shell lexer (S7c cut it).

**Plan-time measurements (commands in the spec dir).** `python3 -I j0-measure.py` classifies the reader stage of every logical line (1,858 swept files); `bash j0-pattern-prototype.sh` runs the shipped and the widened pattern over the same population: shipped 33 hits, widened 33 hits, 0 only in the widened set, and a 60-line fixture table passes. Two rows of the first tool are its own false positives (one `-hmac`, one quoted `-q` inside a pattern) and are not sites. The unbounded operand run adds 24 hits (quoted test strings), a quote-aware run adds 5, one operand adds 0, which is why the design is one operand. Fences: `18` fenced and `12` inline lines match outside knowledge-base, 0 of the 18 sit in a fence that mentions pipefail. Marker: 25 lines in 12 files outside knowledge-base and the guard file. Guard wall time 18.6 s at load 7.

**Deepen additions (J0c).** `j0-split.awk` and `j0-fence.awk` are the two linearisers as POSIX awk; `bash j0-linearisers-check.sh` builds the Guard 2 state rows with `printf` and runs them through each awk present plus the shared widened pattern: split reports exactly the three joins that must report (past a comment line, past a blank line, a `|&` end) and none of `||`, a block-scalar indicator, a lone bar line or EOF; the fence pass reports the pipefail fences (backtick, tilde, indented, a longer fence that a shorter backtick run does not close, unclosed at EOF, pipefail after the hit) and not the fence without pipefail or the prose line. A lone bar line is read as a block-scalar indicator (stated limit).

**Learnings applied.**
- `2026-10-12-a-guard-parsed-under-one-awk-...`: the guard derived zero pairs under mawk after a gawk-only awk construct. The two new awk passes use POSIX awk only (no `\b`, `gensub`, 3-argument `match`, no `awk -v` regex with backslashes) and the guard is run under every second awk interpreter that exists, with `( trap '' PIPE; ... )` and `env -i`.
- `2026-09-17-awk-word-boundary-backslash-b-is-backspace`, `2026-05-17-ac-vocabulary-regex-blind-spots-and-awk-portability`: give each awk arm a positive and a negative fixture.
- `2026-10-10-a-negative-row-passed-for-the-wrong-reason-...`: a must-not row proves the guard only when it is the sole reason for the refusal, so one fixture per conjunct.
- `2026-09-10-i-graded-lines-when-the-unit-was-the-command`, `2026-10-07-extract-the-last-step-...`: a script path written in a comment drags a suite into the battery closure; cite without the suffix, run `bash scripts/test-affected-kb-consumers.test.sh`.
- `2026-10-06-a-line-anchored-extractor-cannot-see-a-prefixed-assignment`: docs prose is itself an executable surface; floors come from measured counts.

## Research Reconciliation: Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Brief: guard at main reads 150 pairs / 263 triples / 151 rows | 151 / 264 / 152 at base `b39ab6cd40` (a merge since the brief) | Re-read at head after merging main; pins recomputed from a green run, never by hand |
| Guard header: "`.md` fences (29), `.ts` (2), knowledge-base scripts (13)" | `.md` outside knowledge-base 30 lines (18 fenced, 12 inline); `.ts` 2 lines (1 stub string, 1 JSDoc comment); kb code 13 lines, all in `archive/` | Dispositions 7 to 9 use the measured split, not the header's totals |
| Brief item "head-N pipes (`\| head -1 \| grep -q`)" | The chain is already matched by its `grep -q` half; the blind spot is `head` as the reader | Fixture for the chain, NOT FIXED for the reader |
| Header: "head -N 1561 lines, 1022 `head -1`" | 754 lines (575 `head -1`) by the tokenising classifier, logical lines, comments and marked lines dropped | Header rewritten with the new command and counts |
| Header: awk exit "59 single-line stages" | 41 single-line, 13 multi-line (the awk form is read only by the four named passes, never by the sweep) | NOT FIXED, stated with both numbers |
| #9217 comment: "kb scripts (13)" | 13 hits, all under `knowledge-base/project/specs/archive/`; non-archive kb code files: 4, 0 hits | Exclusion narrowed to `archive/` segments |
| Brief: labels `app:web-platform` | Satisfied by the one test-file conversion (`apps/web-platform/test/scripts/...`) | Item 8 edits that file |

## Implementation Phases

Phase 0 (read-only, first commit is `evidence.md`). On the branch merged with current main (`git merge origin/main`, then re-run): `bash .claude/hooks/grep-q-pipe-guard.test.sh` (record pairs, triples, rows, `SWEPT`), `python3 -I j0-measure.py`, `bash j0-pattern-prototype.sh` (shipped equals widened), the open-PR screen (re-run `gh pr list --state open --json number,files`, then scan each relevant diff's added lines with the widened pattern), and the marker census (`git grep -c` over the marker regex outside knowledge-base and the guard). Any difference from the plan-time figures is explained in `evidence.md`; a new live hit in a newly read class is converted or recorded before its arm lands.

Phase 1 (red first, `cq-write-failing-tests-before`). In the guard, before any pattern or pathspec change: the case tables (Guard 1), the split and fence fixtures and their `scan_sweep` wiring check (Guard 2), the extension witness, kb witness, comment-filter and marker-pin checks (Guard 3). Run once under `ulimit -v 6000000` and record each new check's first result: every must-detect case reads FAIL by name, every must-not case reads PASS.

Phase 2 (one commit per item, in this order so the cuts of the CTO ruling are clean reverts). Each commit leaves the guard green.
1. Item 1 (WRAP, BIN, `sh -c`), then item 2 (ARG one-operand rule, EARLY cluster and abbreviations), then item 6a (GREP-named variable in BIN). The text starts from `j0-pattern-prototype.sh`; the five parts stay separate variables. The three lines in `residual-v2.sh` that the widening now matches (`env -i grep -q p`, `sudo grep -q p`, `grep p -q`) move to `bad-v2.sh` (`V2_BAD_LINES` rises, `V2_GOOD_LINES` stays 14); `residual-v2.sh` is rewritten to the new residual (`head -1`, `awk '...exit'`, `sed 1q`, `read x`, each pinned as NOT matching); the existing false-positive fixture (`grep -e "a -q b"`) is closed by the quote-aware operand and replaced by the two stated false positives of the prototype (`grep -c p -eq`, `xargs echo grep -q p`), so `fp_hits` is pinned at 2.
2. Item 8 (ts half): `SWEEP_EXTS` array builds `SWEEP_PATHSPEC` and the extension witness; ts tsx mjs cjs added; `_strip_comments` gains the js-family filter; the stub line in the test file is converted in the same commit; `SWEEP_FLOOR` and the test canary list follow the measured population.
3. Item 9: the pathspec entry `':(exclude)knowledge-base'` becomes `':(exclude,glob)knowledge-base/**/archive/**'`. `.md` under knowledge-base stays unread because the extension list has no `md`.
4. Item 8 (py half), then item 4 (`scan_split`), then item 7 (`scan_md`), then item 10 (marker block). Reverse of this order is the cut order.
5. Header and limits wording (below). `SWEEP_PROBE_CHECKS` recomputed with the header recipe.

Design notes that are not obvious from the contract.
- `scan_split` and `scan_md` are awk LINEARISERS: they emit `path:NN:text` lines and the existing filter chain (the widened `PATTERN_V2` through `grep -E`, then `_strip_comments --marker`) does the matching. No regex travels through `awk -v` (backslash processing differs across awks). `scan_sweep` appends their output, so `sweep_verdict` ownership, UNRESOLVED routing and the FAIL text apply unchanged, and `SWEEP_DEFERRALS` gains no row.
- `scan_split` lists files with `sweep_git_grep "$root" -alE -e '(^|[^|])\|[[:space:]]*$'`, joins a trailing single bar (not `||`, not a YAML block-scalar indicator, not a comment line) to the next non-comment line as `| <next line stripped>`, and reports the bar's line number.
- `sweep_git_grep` is parameterised by pathspec (default `SWEEP_PATHSPEC`) so the md listing uses the same flags (`--no-index --exclude-standard`, `core.excludesFile=/dev/null`); the `tc_hidden` ignore check and the test-canary listing read the md pathspec too. `MD_FLOOR` is an optional third argument of `sweep_main` (default 0, so the seven scratch roots without md files stay clean); the `return-wiring` text pins at the end of the guard (the `sweep_main` / `sweep_fold` statements) are updated in that commit and re-measured.
- `scan_md` lists `*.md` outside knowledge-base that contain `pipefail` (`git grep -l`), tracks fences (backtick and tilde, indented, closed at EOF), emits a fence's code lines only if the fence text holds the token `pipefail`, and the widened pattern picks the readers. Prose outside a fence is never emitted.
- The kb exclusion is path-segment exact. `.md` under knowledge-base stays out because the extension list has no `md`.
- The marker pin is a literal block of `path:count` lines compared to a `git grep -c` over the marker regex derived through `sweep_git_grep` (so its population is exactly the swept files: kb code files are in, the guard file is out by the same pathspec); on mismatch the FAIL prints the recomputed block. Update policy, in the pin's comment: a new marker needs the reason in the PR body.

Phase 3 (wording). Rewrite the "WHAT A LINE REGEX CANNOT CLOSE" paragraph and the STATED LIMITS lines of the header to the Item F state with the new commands and counts, update the stale `KNOWN HOLE (Item F ...)` comment at `ALLOW_MARKER`, keep the series open (Items D, E, G, I, H, the carriers, #9639, #9638) and do not write that it is finished. A script path named in a comment is written without its suffix, then `bash scripts/test-affected-kb-consumers.test.sh` once (about 95 s).

Phase 4 (battery). A scripted harness in the spec dir (`mutation-battery.sh`) runs every row of the Guard Contract on a scratch clone, one mutant at a time under `ulimit -v 6000000`, asserting first that the mutation landed (the file changed) and that the unmutated control exits 0; a row is graded RED only when the guard exits non-zero AND prints the row's named FAIL substring or case name. Mutants only edit new guard code, never the trap or signal helpers; any row that would touch those runs through `bash scripts/soleur-sandbox.sh run-isolated`. Also run the guard under each additional awk interpreter present (mawk, busybox, original-awk), under `( trap '' PIPE; bash ... )`, and under `env -i`; if `docker` exists, once in `ubuntu:24.04`. Results in `evidence.md`.

Phase 5 (the test file). `cd apps/web-platform && npx vitest run test/scripts/run-migrations-unmerged-gate.test.ts` at base and at head, assertion counts equal. No `ulimit` on this run.

Phase 6 (ship). Merge `origin/main`, re-run the guard, recompute pins, then lints (AC-9), the pre-push ratchet lane on the merged tree, `decision-challenges.md`, a tracker comment on #9217 with each figure and its command and the NOT-fixed list, one new issue for the awk and `head` reader wave (milestone from the roadmap, linked to #9217), the PR body per AC-10, `soleur:ship`.

## Files to Edit

- `.claude/hooks/grep-q-pipe-guard.test.sh` (the pattern parts, `SWEEP_EXTS` and `SWEEP_PATHSPEC`, `_strip_comments`, `scan_sweep` plus the two linearisers, the kb exclusion, the marker block, the fixtures and witnesses, `SWEEP_FLOOR`, `SWEEP_TEST_CANARIES`, `V2_*` and `SWEEP_PROBE_CHECKS` pins, the header)
- `apps/web-platform/test/scripts/run-migrations-unmerged-gate.test.ts` (one stub line: `if echo "${*}" | grep -qi "SELECT count(\\*)"` becomes a here-string)
- `scripts/test-affected-kb-consumers.baseline.txt` only by the gate's own regeneration, if the gate names a reference one hop away

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-item-f-blind-spots/{tasks.md,evidence.md,session-state.md,mutation-battery.sh}` (`decision-challenges.md`, `j0-measure.py`, `j0-pattern-prototype.sh`, `j0-pattern-fixtures.txt`, `j0-split.awk`, `j0-fence.awk`, `j0-linearisers-check.sh` and the two `j0-plan-time-*.txt` outputs already exist there; every script here is sweep-clean, see Self-sweep)
- `knowledge-base/project/learnings/test-failures/2026-10-14-<slug>.md` only if a non-obvious finding occurs

## Files to Delete

None.

Not touched, on purpose: `plugins/soleur/skills/work/SKILL.md`, `plugins/soleur/skills/plan/SKILL.md`, `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/lib/scratch-root.sh`, `plugins/soleur/test/skill-body-budget.json`, `AGENTS*.md`, every file under `.github/`, `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`, every SKILL.md whose fence holds a pipefail-free early-exit pipe (the 18 lines are recorded, not converted), and the main checkout's `.mcp.json` and untracked `apps/web-platform/1000:` and `500` files. `SWEEP_DEFERRALS` gains and loses no row.

## Open Code-Review Overlap

None. 93 open `code-review` issues were queried (two-stage `gh ... --json` then `jq --arg`) for the guard path, the bare guard name, the test file path and its bare name.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing; a regression is a CI false-red (the guard flags a line it should not, or a vitest case in one test file fails) or a false-green on a test-hygiene gate, seen by contributors as a red `test` check.
**If this leaks, the user's data is exposed via:** no vector; the diff edits one drift guard and one test file, handles no credential or user data.
**Brand-survival threshold:** none
threshold: none, reason: the diff edits a repo-internal drift guard and the stub text of one unit test; no runtime, data or credential surface is touched.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.

## Guard Contract

The deliverable is a guard (a widened reader grammar, two linearising passes, a wider population and a marker pin). One entry per property; the matrix is written from the design before the guard. Each entry carries a row against its own dispatch, a second-member row, a window or reorder row where the property is about a window, must-PASS rows that are not the canonical, and a row on the remediation's own text (the new fixtures and messages must satisfy the guard that reads them: the guard file is excluded from the sweep, so AC-8 runs the widened pattern over the guard's added lines). A row is graded RED only when the guard exits non-zero AND prints the named FAIL substring or case name; a different failure is a wrong-reason RED and is re-aimed, never counted.

### Guard 1 — the reader grammar closes over every spelling it names

**Property.** Every pipe whose reader is an early-exit grep (the grep family, behind any listed wrapper word with its flags, a GREP-named variable, or `sh -c`, with the early flag in any position GNU permutation allows within one stage and in any unambiguous long-option abbreviation) is matched by the one pattern in the sweep, in the fixture check and under `git grep -E`, and none of the must-not shapes matches.

**Assembly.** One string, `PATTERN_V2`, built from five named parts (LEAD, WRAP, BIN, ARG, EARLY) plus the `sh -c` alternative. Its consumers are structural: `scan_sweep` through `sweep_git_grep`, the final filter of `scan_split`, the final filter of `scan_md`, the case-table check (`grep -E`), and `v2-git-dialect` (`git grep -E`); the scratch-root fixtures; the residual fixture. A mutation of one part must red through a case that names it, and each consumer must read the same string (a private copy in a linearising pass is the defect the wiring rows below drive). The chokepoint is the part variables; the case tables are the second members.

**Mutation matrix.**

| # | Mutation | Expected RED |
| --- | --- | --- |
| M1 | Own dispatch: empty the case table, or a part variable made empty | `v2-cases ... ran 0 cases` (count pinned by `V2_CASE_COUNT`); a part that breaks the compile reads `UNRESOLVED: PATTERN_V2 does not compile` (exit 3) |
| M2 | Remove `sudo` from the wrapper words | case `wrap-sudo` named |
| M3 | Second member and bound: `{0,4}` to `{0,1}` and to `{0,3}` | cases `wrap-env-i-path` (`env -i PATH=/bin grep -q p`) and `wrap-4-tokens` (a 4-token run, must match) named; a 5-token run is pinned as the stated residual `wrap-5-tokens` |
| M4 | Widen the one-operand rule to any run of tokens | must-not case `quoted-context-pipe` (the `cron-egress` shape: a pipe inside a quoted test string followed by more quoted words and `-eq`) named; the live tree also reds with `outside the deferral table` |
| M5 | Remove one wrapper word, one binary (`zgrep`, `rg`, `ag`, `ugrep`, `pcregrep`) or the `sh -c` alternative at a time | one named case each (`wrap-doas`, `wrap-xargs`, `bin-zgrep`, `bin-rg`, `bin-ag`, `bin-ugrep`, `bin-pcregrep`, `shc-single`, `shc-lc`); `shc-count` (`sh -c 'grep -c p'`) must not match |
| M6 | GREP-named variable rule widened to any variable name | must-not cases `var-hook`, `var-hmac` named |
| M7 | EARLY loses digits in the cluster, or loses the long-option abbreviations, or widens to `--s[a-z]*` / `--max[a-z-]*` | cases `early-5q`, `early-qui`; must-not `rg-sort`, `rg-max-depth` |
| M8 | Residual flip: make EARLY accept `-[0-9]` or `-n N` and add `head` to BIN (`head` in BIN alone stays green because EARLY needs q or m) | `residual-v2` names the flipped line (`head -1`, `awk '...exit'`, `sed 1q`, `read x` pinned as NOT matching) |
| M9 | Consumer wiring: `scan_split` or `scan_md` filters with the old `PATTERN`, or a private copy of the pattern | the must-REPORT cases of Guard 2 that use a V2-only spelling (`split-sudo`, `md-env-i`) named (a must-not row cannot red a narrower pattern), plus `pattern-single-source` (the pattern text appears in exactly one assignment) |
| H1 | Harness: delete one bad case but keep the pinned counts | `v2-fixtures` count pin |
| H2 | Harness: a deliberately wrong pattern (V2 with WRAP removed) is run through the same case loop; the loop must report at least the wrapper cases as misses | `v2-cases-negative` (a loop that cannot fail reads RED) |
| H3 | Must-PASS non-canonical: `x \| sudo tee f`, `x \| time cat`, `x \| command -v grep`, `x \| sh -c 'grep -c p'`, `x \| grep -cF 'a -q b' >/dev/null` | all stay unmatched (a regression of any reds its case) |

Anchor. The case tables live in the file they protect, so one diff can move both; what must also move for a weakening to pass is the live-tree equality (the sweep reads 0 undeferred hits on the real tree: `SWEEP_DEFERRALS` is unchanged and a widened pattern that over-matches reds there) and the committed `j0-plan-time-pattern-output.txt` (shipped 33, widened 33). This proves consistency plus a live-tree witness, not integrity; stated.

### Guard 2 — the multi-line passes see what a line search cannot

**Property.** (a) An early-exit grep on the line after a trailing single bar is reported at the bar's line, owned by the same deferral rows as any other hit. (b) In a `.md` file outside knowledge-base, a fenced block that contains `pipefail` and an early-exit pipe is reported; a fence without pipefail, a pipefail in a different fence, prose outside a fence and a comment line are not.

**Assembly.** Two awk linearisers (`scan_split`, `scan_md`), one shared filter chain after them (widened `PATTERN_V2`, `_strip_comments --marker`), the fold into `scan_sweep`'s output (so `sweep_verdict` applies), the two listings (`sweep_git_grep` for split, a second pathspec for md), and the states each tracks: join states (block-scalar indicator, `||`, comment line next, blank line next, EOF after a bar) and fence states (backtick, tilde, indented, nested list, unclosed at EOF, tag or none). More than one injection path feeds the verdict, so each has its own row.

**Mutation matrix.**

| # | Mutation | Expected RED |
| --- | --- | --- |
| G2-1 | Own dispatch: the md listing is empty (pathspec typo), or the linearisers are never called | `split-must-report` / `md-must-report` named; an md population below `MD_FLOOR` reads `UNRESOLVED` |
| G2-2 | Drop the join (emit nothing) | `split-must-report` named |
| G2-3 | Second member: stop after the first trailing-bar line of a file | `split-second-site` named |
| G2-4 | Drop the block-scalar exclusion (`run: \|` then `grep -q p "$f"`) | must-not `split-block-scalar` named |
| G2-5 | Report the next line's number instead of the bar's | `split-line-number` (exact `path:NN` compared) |
| G2-6 | Window row: whole-file pipefail test instead of per-fence, and a variant where the state is not reset at a fence close | must-not `md-pipefail-other-fence` named |
| G2-7 | Reorder row: look for pipefail only above the hit | `md-pipefail-after-hit` named (pipefail after the pipe in the same fence still reports) |
| G2-8 | Drop the pipefail requirement | must-not `md-no-pipefail`; the live tree reds (18 lines) |
| G2-9 | Drop fence tracking (scan prose) | must-not `md-prose`; the live tree reds (12 lines) |
| G2-10 | Drop the comment filter, or treat an unclosed fence at EOF as not scanned | `md-comment-line` / `md-unclosed-fence` named |
| G2-11 | State rows, one fixture each: trailing `\|\|` (no join), comment line next (no join), blank line next, EOF after a bar, `\|&` at line end; fences: indented and list-nested, a tilde opener closed by a backtick (not closed), a longer closing fence | `split-or-or`, `split-comment-next`, `split-blank-next`, `split-eof`, `split-pipe-amp`, `md-indented`, `md-tilde-mismatch`, `md-long-fence` named |
| H4 | Harness: `scan_sweep` stops appending the two passes | `sweep-wiring-multiline` (a scratch root with one split file and one md file must report both) |
| H5 | Must-PASS non-canonical: pipefail spelled `set -euo pipefail`, `set -o pipefail`, a ~~~ fence, a ```bash fence, CRLF line ends, each with a V2-only reader spelling | all report; a `\| grep -c p` in the same fence does not |

Anchor. Both passes read 0 hits on the real tree today, so a wiring break is not visible there; H4's scratch-root witness is the anchor, and `MD_FLOOR` (measured md count) stops a truncated listing from reading as clean.

### Guard 3 — the population and the bypass pin

**Property.** Every file of every extension in `SWEEP_EXTS` (sh bash bats yml yaml tf template js ts tsx mjs cjs py), anywhere outside `knowledge-base/**/archive/**`, is read; a comment filter applies only to its own languages; every marked line outside knowledge-base (guard file excluded) is pinned per file.

**Assembly.** `SWEEP_EXTS` (one array builds the pathspec and the witness), the kb exclusion entry, `_strip_comments`, the marker block and its derivation, `SWEEP_FLOOR`, `SWEEP_TEST_CANARIES`, the scratch-root plants. More than one thing can hide a file (an extension missing from the list, a pathspec exclusion, an ignore rule, a comment filter), so each has a row.

**Mutation matrix.**

| # | Mutation | Expected RED |
| --- | --- | --- |
| G3-1 | Own dispatch: `SWEEP_EXTS` empty, or the witness root holds no file | `ext-witness ... read 0 files` / `UNRESOLVED` |
| G3-2 | Drop one extension from `SWEEP_EXTS` (every one in turn, including `py` last and an older one such as `bats`) | `ext-count` (a literal `SWEEP_EXT_COUNT=13` pinned beside the array) and `ext-expected` (the array compared with a separately typed expected list) name it: the pathspec and the witness are built from the same array, so only a literal outside it can see the drop |
| G3-3 | Restore `':(exclude)knowledge-base'` whole | `kb-witness` (a planted `knowledge-base/project/specs/feat-x/bootstrap.sh` hit not read) named |
| G3-4 | Window row: exclusion by `*archive*` glob, and drop of the archive exclusion | `kb-archive-lookalike` (a `knowledge-base/x/archived-notes/y.sh` hit must still be read) / `kb-archive-must-not` (a hit under `archive/` must not report); the live tree also reds (13 archived hits) |
| G3-5 | Comment filter made extension-blind (or applied to sh) | must-not `ts-hash-line` (a `#` line in a .ts file is code) and `py-slash-line` (a `//` line in a .py file is code) named |
| G3-6 | Drop the JSDoc `*` filter; apply the `*` filter to .sh (a `*)` case arm that pipes into grep -q must still report); apply the js-family filter beyond its family; drop the py `#` filter | the live tree reds on the existing comment line of a plugin test; `sh-case-arm`, `py-hash-comment` named |
| G3-7 | Marker: add a marker to a pinned file; delete one; add one in an unlisted file (including a kb code file); derive the pin outside `sweep_git_grep` | `marker-pin` prints the recomputed block in each case |
| G3-8 | A pathspec exclusion that spares the other canaries but hides the new ts canary | `test-canaries` names it (`SWEEP_TEST_CANARY_COUNT` 9 to 10) |
| G3-9 | Revert the stub conversion in the test file | `outside the deferral table` names the test file; the vitest run reds nothing (behaviour equal), which is why the guard row is the pin |
| G3-10 | Self-sweep: a fixture heredoc or a literal reader shape in a script of the spec dir | `spec-dir-zero` (the sweep reads the live spec dir and reports 0) |
| H6 | Harness: lower `SWEEP_FLOOR` toward the old 1400 | `floor-lower-bound` (a literal `SWEEP_FLOOR_MIN=3500` beside it: the floor can only move with a visible edit of that literal); a truncated population of 3,000 files must read `below the floor` |
| H7 | Must-PASS non-canonical: a tracked `knowledge-base/project/specs/archive/x/y.sh` with a hit; a `.ts` file whose only match is a `//` comment line | both unreported |

Anchor. The marker pin and the extension list sit in the file they protect (consistency, not integrity). What must also move for a weakening to pass: the real tree's 0 undeferred hits, the 25-line marker block (a visible diff line per marker), and `SWEEP_FLOOR` against the measured file count.

## Observability

The deliverable is a drift guard that runs in the CI test group; the plan's edit list touches no path of the plan Phase 2.9 trigger set (`apps/*/server`, `apps/*/src`, `apps/*/infra`, `plugins/*/scripts`), so this block is declared for completeness under deepen-plan 4.7 and is deliberately small. The guard itself takes 18.6 s at load 7, above preflight Check 10's 15 s cap, so it is not declared as the probe (a suite is the right command to TEST the guard and the wrong one to DISCOVER its signal).

```yaml
liveness_signal:
  what: the guard prints PASS: grep-q-sweep-probe-pass (and its other PASS lines) on every PR and merge_group run of the test group
  cadence: per PR and per merge_group run
  alert_target: the required test check turns red on the PR, which blocks merge and ejects a queue entry
  configured_in: .claude/hooks/grep-q-pipe-guard.test.sh (the passes), registered by the hooks suite glob of the repo's test runner
error_reporting:
  destination: CI job log of the test check (repo-hygiene guard, no error-tracker surface)
  fail_loud: a FAIL line naming the case, the row or the recomputed pin, exit 1; an empty listing, a population below its floor, or a pattern that does not compile prints UNRESOLVED and exits 3
failure_modes:
  - mode: a new early-exit pipe lands in a swept file in a spelling the pattern names
    detection: the sweep prints the path and line under "outside the deferral table"
    alert_route: required test check red on the PR
  - mode: a pattern part, a pass, an extension or the marker pin is narrowed or neutered
    detection: the case, witness or control that names it prints its name (Guard Contract matrices)
    alert_route: required test check red on the PR
  - mode: the converted stub changes the unit test's behaviour
    detection: the vitest file at base and head, equal assertion counts (AC-5)
    alert_route: the web-platform test check on the PR
logs:
  where: CI job logs of the test check; locally the stdout of the guard
  retention: GitHub Actions log retention
discoverability_test:
  command: git grep -c grep-q-sweep-probe-pass -- .claude/hooks
  expected_output: grep-q-pipe-guard.test.sh:1
```

The probe checks that the guard still declares its signal line (a static, sub-second read); whether CI ran the guard is read on the PR's test check.

## Alternative Approaches Considered

| Alternative | Why not |
| --- | --- |
| A second `PATTERN_V3` and a second scan | Cut List: leaves V2 dead and doubles the sweep (CTO ruling 12) |
| Any-token flag permutation | Measured +24 hits (+5 with quote-aware tokens) on quoted test strings; one operand adds 0 |
| A derived function-reader set | Cut List: an unsound bash parser for 0 call sites |
| Gate or ratchet `head -N` and awk exit | Cut List: 754 + 54 lines, no static separation; the guard header already calls it a review item |
| Eight file-exact deferral rows for the fenced lines | Cut List: documents harmless snippets and adds a three-place edit per row |
| Convert the 18 SKILL.md fenced lines | Fenced files and the body budget; they are agent-run snippets without pipefail |
| Pin the marker as one total | An add-one-delete-one swap across files would pass |

## Follow-on slices (listed, not planned here)

Items D, E, G, I and H of the series brief, the carrier rows (gated on a host replace), and the #9639 and #9638 triage stay later slices on #9217. The `head -N` and awk-exit readers are filed as one wave issue at ship; function readers, non-GREP variable binaries, archived kb scripts and pipefail-free fenced lines are recorded in the tracker comment.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "extend the guard's blind spots in .claude/hooks/grep-q-pipe-guard.test.sh" [brief] | Files to Edit, Phases 1 to 3 | mapped |
| 2 | "wrappers around grep -q" [brief] | Disposition 1, Guard 1 M2 to M5 | mapped |
| 3 | "flag order (grep -F -q vs -qF vs --quiet)" [brief] | Disposition 2, Guard 1 M4, M7 | mapped |
| 4 | "head-N pipes (\| head -1 \| grep -q)" [brief] | Disposition 3, Guard 1 M8 (residual pin and chain fixture), NOT fixed list | mapped |
| 5 | "split-line pipes (pipe at line end or continuation)" [brief] | Disposition 4, Guard 2 G2-2 to G2-5 | mapped |
| 6 | "multi-line awk with early exit" [brief] | Disposition 5, residual pin, NOT fixed list, wave issue | mapped |
| 7 | "a reader behind a variable or function" [brief] | Disposition 6, Guard 1 M6, NOT fixed list | mapped |
| 8 | ".md fenced command examples" [brief] | Disposition 7, Guard 2 G2-6 to G2-10 | mapped |
| 9 | ".ts files that shell out" [brief] | Disposition 8, Guard 3 G3-1, G3-2, G3-5, G3-9, Phase 5 | mapped |
| 10 | "kb scripts" [brief] | Disposition 9, Guard 3 G3-3, G3-4 | mapped |
| 11 | "Each item either gets a detection row plus a mutation-pinned test or is recorded as not fixed with the reason in the PR body and on #9217." [brief] | Dispositions table, Guard Contract, Phase 6, NOT fixed list | mapped |
| 12 | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table in knowledge-base/project/specs/<branch>/decision-challenges.md" [brief] | `decision-challenges.md` | mapped |
| 13 | "Mutation batteries under ulimit -v 6000000, one mutant at a time; never run a mutant of a signal-sending or file-removing helper outside scripts/soleur-sandbox.sh run-isolated; never put ulimit -v on the gate" [brief] | Phase 4, AC-6 | mapped |
| 14 | "Do not edit (plan must not schedule edits to): plugins/soleur/skills/work/SKILL.md, scripts/test-all.sh, ..." [brief] | Not touched list | mapped |
| 15 | "merge origin/main and rerun the guard before pushing" and "don't name a script path in a guard comment without running `bash scripts/test-affected-kb-consumers.test.sh`" [brief] | Phase 3, Phase 6, AC-3, AC-9 | mapped |
| 16 | "Any new test line must not itself pipe into grep -q" [brief] | AC-8, Sharp Edges | mapped |
| 17 | "Open PRs #10322 and #10081 also touch the guard file (they add/move rows) — plan for rebase/pin movement." [brief] | Phase 6, Sharp Edges | mapped |
| 18 | "PR body: `Ref #9217` only, never Closes; labels semver:patch and app:web-platform; no soak/outage/production/Pro vocabulary in the PR body." [brief] | AC-10 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Guard edit (pattern parts, linearisers, population) | "extend the guard's blind spots" (ask 1) | asked |
| Test-file conversion in `run-migrations-unmerged-gate.test.ts` | ".ts files that shell out" (ask 9) and "labels semver:patch and app:web-platform" (ask 18) | asked |
| Residual fixture and chain fixture for head, awk, sed, read | "recorded as not fixed with the reason" (ask 11) | asked |
| Marker pin (disposition 10) | — | inferred — justification: the guard's own header and four prior plans name the marker pin as the content of Item F, and the marker is a way to hide any line from the sweep, so leaving it open makes the other nine rows bypassable |
| `SWEEP_EXTS` array and a witness for every extension, old and new | "a detection row plus a mutation-pinned test" (ask 11) | inferred — justification: a pathspec entry dropped from the list must red, and the six pre-existing extensions have no witness today (the gap the S4 review measured) |
| `SWEEP_FLOOR` and canary-count changes | — | inferred — justification: a floor of 1,400 on a 4,488-file population stops guarding truncation, so it follows the measured figure |
| `mutation-battery.sh` in the spec dir | "Mutation batteries under ulimit -v 6000000, one mutant at a time" (ask 13) | asked |
| Wave issue for head and awk-exit readers | — | inferred — justification: CTO ruling 5 requires the conversion wave to be tracked, and a deferral without an issue is invisible |
| `evidence.md`, `tasks.md`, `session-state.md`, `decision-challenges.md` | "Persist every decision as a row" (ask 12) and "in the PR body and on #9217" (ask 11) | asked |

### Split Assessment

- Subsystems touched: 3 — `.claude/hooks`, `apps/web-platform` (one test file), the knowledge-base spec dir
- Planned files: 2 edited, 4 created | Estimated changed lines: about 400 added to the guard (case tables, two linearisers, witnesses, pins, header), 1 in the test file
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — under every threshold; commits are one per item so the CTO cut order (marker pin, then fences, then split pass, then the py half) is a clean revert at ship time, and a split of items 4 and 7 is taken only if the added guard lines pass about 450

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC-1 `evidence.md` is the first commit that touches the spec dir after the plan: the guard run on the tree merged with main (pairs, triples, rows, `SWEPT`), `j0-measure.py` and `j0-pattern-prototype.sh` re-run with their commands and outputs (shipped hits equal widened hits, 0 only in the widened set), the open-PR screen, the marker census, and the reconciliation of every difference from the plan-time figures.
- [ ] AC-2 The red-first run is recorded: each must-detect case reads FAIL by name, each must-not case reads PASS, before any pattern or pathspec edit.
- [ ] AC-3 `bash .claude/hooks/grep-q-pipe-guard.test.sh` exits 0 on a clean checkout (`git status --porcelain` empty) of the branch merged with current main, prints the same `DEFERRED:` lines as base, and prints its PASS lines; the join figures equal the merged tree's own (they move only with main).
- [ ] AC-4 `SWEEP_DEFERRALS` is byte-identical to base (`git diff origin/main -- .claude/hooks/grep-q-pipe-guard.test.sh` shows no change inside the array, `GATED_TEST_ROWS` or `GATED_PROD_ROWS`).
- [ ] AC-5 `run-migrations-unmerged-gate.test.ts` passes under vitest at base and at head with equal assertion counts; its diff is the one stub line.
- [ ] AC-6 Every Guard Contract row (M1 to M9, H1 to H3, G2-1 to G2-11, H4, H5, G3-1 to G3-10, H6, H7) is graded RED by the committed guard, one at a time under `ulimit -v 6000000` on a scratch clone, each asserting the mutation landed and the unmutated control exits 0; the harness accepts rc 1 or 3 as RED, treats 126, 127, 134, 137 and 139 as instrument failures, and allocates its scratch clone with `bash scripts/soleur-sandbox.sh new`; a row that cannot run is listed UNVERIFIED with the reason, never counted. The guard also runs green under every second awk present, under `( trap '' PIPE; ... )`, under `env -i`, and once in `ubuntu:24.04` if docker exists.
- [ ] AC-7 `V2_BAD_LINES` (up), `V2_GOOD_LINES` (14), the fp pin (2), the new pins `V2_CASE_COUNT`, `MD_FLOOR`, `SWEEP_EXT_COUNT` (13) and `SWEEP_FLOOR_MIN`, `SWEEP_FLOOR`, and `SWEEP_TEST_CANARY_COUNT` (9 to 10) equal the measured values (`SWEEP_CANARY_COUNT` stays 9: no root canary is added), and `SWEEP_PROBE_CHECKS` equals `grep -vE '^[[:space:]]*#' .claude/hooks/grep-q-pipe-guard.test.sh | grep -cE '(\|\||&&)[[:space:]]+sweep_probe_fail\+=\('` (54 at base), recomputed after drafting; the guard's wall time before and after is recorded plain, with `uptime` beside each figure.
- [ ] AC-8 (a manual check recorded in `evidence.md`, not a standing gate: the guard file is excluded from the sweep) The guard's own added lines satisfy the widened pattern: the widened `PATTERN_V2` run over `git diff origin/main -U0 -- .claude/hooks/grep-q-pipe-guard.test.sh` added lines, minus the fixture and message text, reports 0 (no new test line pipes into `grep -q`; rows are selected into a variable and matched by here-string).
- [ ] AC-9 Repo-global lints pass against the base: `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`, `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, `shellcheck -S warning` findings on the guard unchanged from base, `python3 scripts/lint-guard-contract.py` and `python3 scripts/lint-infra-no-human-steps.py` on this plan, `bash scripts/pre-push-ratchet-lane.sh` on the merged tree, and `bash scripts/test-affected-kb-consumers.test.sh` once before the push.
- [ ] AC-10 PR body: `Ref #9217` (never a closing keyword), the NOT-fixed list, a `Filed:` line for the wave issue, cites the spec dir's `evidence.md` and not this plan's path; labels `semver:patch` and `app:web-platform`; no soak, outage, production or Pro vocabulary (write "non-test" for the older word) and no bullet starting with an operator verb.

### Post-merge

- [ ] AC-11 `soleur:postmerge` per its skill; then a tracker comment on #9217 with the dispositions table, each figure with its command, the matrix results, the NOT-fixed list and the next slice named (the tracker is the re-evaluation record).

## NOT fixed here (carried into the PR body and the tracker comment)

- `head -N` as a reader (754 lines, 306 files): no static property separates the harmful pipes from the harmless; residual-pinned.
- awk with an early `exit`, single-line (41) and multi-line (13), across the sweep, and a multi-line detector for the four named passes: needs a program-extent parser, protects value-extraction captures; filed as one wave with `head -N`, `sed q` (1) and `| read` (0 real).
- A reader behind a function (25 candidate functions, 0 call sites) and behind a variable not named like grep (709 stages with no early flag).
- Pipefail-free fenced command examples (18 lines in 8 SKILL.md files) and inline prose (12): the hazard needs pipefail in the executing shell; the files are fenced or budgeted. A shell whose environment sets `SHELLOPTS` is outside the repo's control.
- The 13 hits in 5 scripts under `knowledge-base/**/archive/**`: frozen records, never run.
- The marker's in-string and trailing-text holes (the pin is the compensating control); a swap of one marker for another inside one file; the pin and the table live in the file they protect (consistency, not integrity).
- A process-substitution reader (`cmd > >(grep -q p)`), an extensionless script (6 shebang files, no hit), a stack of two wrappers longer than the bounded run, and a quoted `-q` inside a pattern (the stated false positive).
- Items D, E, G, I and H; the carrier rows; #9639 and #9638.

## Test Scenarios

- Given `x | sudo grep -q p`, `x | env -i PATH=/bin grep -q p`, `x | grep p -q`, `x | "$GREP" -q p` or `x | sh -c 'grep -q p'` in a scratch root, then the sweep reports each as outside the deferral table.
- Given `x |` ending a line and `grep -q p f` on the next, then the sweep reports the bar's line; given `run: |` then `grep -q p "$f"`, it does not.
- Given a `.md` fence with `set -o pipefail` and `x | grep -q p`, then the sweep reports it; the same pipe in a fence without pipefail, or in prose, is not reported.
- Given a `.ts` file with `// x | grep -q p` and a `.py` file with that same text on a `#` line, then neither reports; a `#` line in the `.ts` file and a `//` line in the `.py` file report.
- Given a hit under `knowledge-base/project/specs/feat-x/` and one under `.../archive/`, then only the first reports.
- Given one marker added to a pinned file, one removed, or one added to an unlisted file, then `marker-pin` prints the recomputed block.
- Given the repository after Phase 5, then the converted stub test passes at the same assertion count as base.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan`; this one carries `threshold: none` with a reason.
- The new code and fixtures must themselves be pipe-guard clean: select rows into a variable and match by here-string, read files with `git grep` or a process substitution, never `... | grep -q`. CI flagged that on a prior PR.
- The guard is a line scanner by construction: no regex goes through `awk -v` (backslash processing differs between gawk and mawk), POSIX awk only, and every awk arm has a positive and a negative fixture.
- The wire pins read the whole file's non-comment lines at column 0: fixtures and messages are indented or built with `printf`; recompute `SWEEP_PROBE_CHECKS` with the header recipe after drafting, never by hand.
- Pins move whenever main adds or removes a producer or suite: merge `origin/main` and re-run the guard before pushing; #10322 and #10081 edit the join table and `PJ_TRIPLES` (the region at the end of the file), so their rebase conflicts are in rows and that one pin, not in the regions this plan edits. A join row that names a glob-collected suite in full pulls it into battery-tag-authorship's closure: spell the file column `name~.sh`. A script path named in a guard comment is written without its suffix, then `bash scripts/test-affected-kb-consumers.test.sh`.
- `git grep` reads the working tree (`--no-index`); the join reads tracked files. A scratch plant that is untracked is seen by the sweep and not by the join; run from a clean checkout.
- The sweep reads this plan's own spec dir after item 9: a script there must not hold a reader shape as text (fixtures are `.txt` data); re-run the guard with the spec dir present before every push.
- Counts rot: every figure in this plan carries its command in the spec dir; re-measure before quoting one.
- Never put `ulimit -v` on the full gate (it crashes bun and vitest); the vitest run in Phase 5 has none. A hook blocks Bash text containing the secrets-CLI verb or the infrastructure-apply verb, sleep-chained waits, and `pgrep -f` / `pkill -f`: write such a command to a file with the Write tool and run it by path.
- A red merge_group run dequeues the PR: read the failing job, re-arm once if it is a known flake, and stop and report if it dequeues twice.
