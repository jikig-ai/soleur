---
title: "feat: S4 affected-index PR1b, widen the audit's reach before the ratchet (Ref #10448, Ref #9729)"
date: 2026-10-20
slug: s4-affected-index-pr1b-audit-reach
branch: feat-one-shot-s4-affected-index-pr1b-audit-reach
issue: 10448
lane: cross-domain
type: feat
brand_survival_threshold: none
---

Spec lacks valid `lane:` (no spec.md exists for this branch): defaulted to `cross-domain` (fail-closed). All PR text says `Ref #9729` and `Ref #10448`; nothing in this work uses a closing keyword.

## Enhancement Summary

**Deepened on:** 2026-10-20
**Sections enhanced:** Phase 0-3, Guard Contract (all three guards), Handoff to PR3, Sibling PR Overlap, Acceptance Criteria
**Review agents used:** plan-review panel (DHH, Kieran, code-simplicity), then soleur:engineering:review:architecture-strategist, soleur:engineering:review:test-design-reviewer, soleur:engineering:research:git-history-analyzer (every attribution), and a second CTO round (two forks); mechanical halts 4.6-4.12 run and green.

### Key Improvements
1. The reach definition is now a measured, CTO-ruled one (C plus D-code) instead of the parent ruling read literally (which would have added up to 100,232 pairs): see `## Research Insights` and decision-challenges.md rows 1-5.
2. Walk files also follow `source` hops (CTO round 2, measured +16 pairs), and the read order is canonicalised before numbering so accept-row ordinals cannot depend on selector row order.
3. The Guard matrices were made implementable in this harness: malformed edge arms are isolated one per row, `mutate` rows are written in Phase 2 against anchors that exist, the cost instrument asserts linear scaling, fixtures live in their own repo, and the generator row uses a fixture old-SUT.
4. Row-local walk state, hop-memo keying, the regenerator consumer (`audit-differential.py`), the pinned-versus-final-tree number split and four more PR3/PR4/PR5 hand-off lines were added.

### New Considerations Discovered
- The parent plan's ruling-29 thresholds (622 and 1,244) were absolute figures; they are now relative to the baseline measured at PR1b's start.
- `#10414` ("S4 PR D") is an issue, not a pull request.
- PRs #10376 and #7390 edit both `scripts/lib/test-affected-paths.sh` and `scripts/test-all.sh`.
- The replay suite takes about seven minutes (225 of 225 mutants killed, measured by the test-design pass), far above its `floor` row in `scripts/suite-durations.tsv`.

## Overview

PR1 of the five-PR series for the S4 affected-index completion (#10448, Ref #9729) merged as #10572. This is the
mandatory follow-on the CTO scoped in review round 1 (rulings 29, 33): the audit-definition changes that must land
before the ratchet PR, because after the ratchet a reach change would red every PR or force baseline growth.

## Research Insights

**Premise Validation.** Checked on 2026-10-20: #10448 is open and carries the budget owner's option (i) decision of 2026-10-19 and the PR1-merged comment of 2026-10-20 that names PR1b ("selector `pats` closure, comment stripping by extension, dirname hops, edge parity", "lands before the ratchet", "declared limits go in the ADR-276 amendment (PR3)"). PR #10572 (PR1) is merged (`624a07ff58`); #9729 is open; "PR D" (issue #10414) and the lock are untouched. The audit entry points the scope names all exist on main: `suite_inputs`, `suite_texts`, `suite_refs`, `audit_census`, `edge_hit`, `strip_comments`, `SOURCE_HOP`, `RUNNER_TRIGGERS` in `scripts/ci-pr-affected-replay.py`. No PR1b exists on `origin/main` (`git log origin/main` shows none) and the only PR for this branch is the auto-created draft #10671. ADR corpus: ADR-276 (the amendment target; its 2026-10-16 item 5 is the entry condition) and ADR-290 (the shrink-only ratchet pattern PR3 reuses) were grepped for the mechanism words "pats", "closure" and "reach"; neither rejects an audit-reach widening. Stale: the parent series' figures. Its 622 and 1,244 thresholds were measured on a tree with 1,244 gap pairs; the live tree at PR1b's start is 653 selector rows, 199 gap suites and 1,264 gap pairs, and the CTO re-based the thresholds on it (decision-challenges.md rows 1 and 3). The sharper stale premise: parent row 29 read as "scan every file listed in `pats`" does not hold up, because `pats` mixes executed code with declared data files (decision-challenges.md row 1).

**Property List.**
1. P1 (reach): a literal tracked path named by a registered suite, by a library it sources to depth 8, or by a code file that its selector row lists and that scanned text names literally (walk to depth 8), is either declared by an edge, accepted by a live anchor-keyed row, or reported as a gap.
2. P2 (credit parity): the audit credits an edge exactly when the selector would select the suite for a diff naming that path: never more (a dead glob, a substring entry read as exact) and never less (a malformed glob that widens, a non-caret substring entry).
3. P3 (comments): a path named only in a real comment of the file's own language is a mention, and a line that is a comment in a different language is not blanked.
4. P4 (measured and bounded): the reach change is quantified against the baseline measured at the start commit, with the CTO's thresholds (re-split at 50 percent, stop at 100 percent) enforced by a mechanical check on the committed receipt, and the audit stays inside the PR1 scan budget (30 s for the scan on the pinned tree).
5. P5 (frozen, documented): the reach definition and its declared limits are written where an operator reads them (script docstring, runbook) and handed to PR3's ADR-276 amendment; nothing about CI activation changes.

**Cut List** (mechanism, property, what already covers it):
- Scan every tracked file in `pats` (parent row 29 read literally) -> P1 -> cut by the CTO ruling: measured +9,248 to +100,232 pairs, mostly data files the suite never reads (row 1).
- A selector change that tags derived versus declared edges -> P1 -> the C plus D-code walk approximates it inside the audit; editing `scripts/test-all.sh` is a runner-changed diff and changes the row shape the replay tooling and the derive cache consume (row 6).
- A pats-independent "any file a suite names" walk -> P1 -> measured +10,270 on 997 files (scripts name runbooks and ADRs in messages): infeasible to drain.
- Shebang sniffing for extensionless scripts -> P3 -> unknown extension strips nothing, which over-reports (the safe direction); measured 0 live effect.
- A second implementation of the glob matcher -> P2 -> `edge_hit` stays the single credit function; the bash-versus-python differential proves it against the real `_diff_edge_hit`.
- A parity floor that counts iterations -> P4 -> the generator compares set sizes (added pairs versus the baseline) and the receipt lists the pairs themselves, not loop counts.
- Permanent stored-text re-check of the receipt header in the suite -> P4 -> cut at plan review: it can only fail if the header is hand-edited; the generator enforces the stop line where the numbers are produced.
- Value-proposition measurement (0.6c): not applicable, nothing here claims a saving. The numbers this plan owns are reach numbers, produced by named commands: `python3 scripts/ci-pr-affected-replay.py audit --list <rows>` (7 s on a saved rows file) after `env -u CI -u TEST_GROUP bash scripts/test-all.sh --print-selection --paths=README.md > <rows>` (5m13s wall on a loaded machine).

**Measured reach (this worktree, 653 rows saved from the command above, prototypes in the session scratchpad; the implementer re-measures on its own tree).**

| Reach definition | Gap pairs | Added | Suites with a gap | Files read beyond today |
|---|---|---|---|---|
| Today (PR1 merged) | 1,264 | 0 | 199 | 0 (660 files read) |
| A: every tracked file in `pats` | 101,496 | +100,232 | 423 | 962 |
| A-prime: A without the two runner triggers | 10,512 | +9,248 | 402 | 962 |
| B: A-prime, code extensions only | 4,608 | +3,344 | 378 | not measured |
| C: source closure to depth 8, operands resolved against the including file | 1,318 | +54 | not measured | 26 |
| D-all: naming walk over `pats` files of any extension | 7,478 | +6,214 | 298 | 565 |
| D-code: naming walk over code files of `pats` | 2,202 | +938 | 264 | 322 |
| **C plus D-code (ruled)** | **2,256** | **+992** | **291** | **340** |
| Comment stripping by extension | 1,264 | 0 | 199 | 0 |

Top additions of the ruled definition are real undeclared reads, not phantoms: `scripts/lib/scratch-root.sh` (40 suites), `AGENTS.md` (27), `package.json` (20), `.gitignore` (19), `CLAUDE.md` (19); 158 suites with no gap today gain one. Edge kinds in the live `pats`: 3,180 exact, 619 directory, 59 glob; no non-caret and no malformed entry, so the parity work has no live effect on the number.

**Mechanics (file anchors by content).**
- Rows: `AFFECTED_SELECTED<TAB>label<TAB>sel<TAB>class<TAB>edge|edge|...`; `pats` is that fifth field split on `|`; its first element is the suite's own file or directory. The selector's closure is its `_affected_derive` loop (bounded `_depth < 8`) over `_affected_file_edges`; its operand resolution lives in `_affected_edge_token` (the `$HERE`, `$SCRIPT_DIR`, `$REPO_ROOT`, `$ROOT_DIR` and `$(dirname ...)` replacements).
- Edge credit in the selector: `_diff_touches` sends a `^` entry to `_diff_edge_hit` and tests a non-caret entry as a substring of the diff names; `_diff_edge_hit` has the three kinds with every malformed glob shape returning a match.
- Audit chokepoints: `audit_census` -> `suite_inputs` -> `suite_texts` (reads) -> `suite_refs` (names) -> `edge_hit` (credit); every read goes through `try_read`/`read_bytes` (containment, regular file, 8 MiB cap), every judgement through `judge_rules`.
- Test harness: `plugins/soleur/test/ci-pr-affected-replay.test.sh` (2,040 lines; `mkf`, `srow`, `saudit`, `audit`, `row_*`, `mutate <name> <old> <new> <row>` with 225 existing mutation rows that each require their edit to land exactly once).
- The parent PR's receipts (archived): `knowledge-base/project/specs/archive/20261019-222512-feat-one-shot-s4-affected-index-completion/receipts/{audit-differential.py,audit-differential.tsv,spike.md}`.

**Institutional learnings applied** (from `knowledge-base/project/learnings/`):
- `2026-10-19-the-audit-a-ratchet-trusts-reached-less-than-its-name-and-both-p1s-were-in-the-fixes.md` (this PR's own motivation): state the reach bound and freeze it; a fix commit is the least-audited surface, so every new helper (hop resolver, walk, parity function) gets its own mutation rows and an independent instrument; a ruling applied literally can destroy real reads, so regenerate the per-occurrence receipt after the change.
- `2026-10-18-sole-copy-drift-check-fixes-were-the-least-audited-surface.md`: each new bound (depth 8, the extension sets, the operand table) needs a test asking what value of the mutated input still passes, with suffix and prefix garbage cases.
- `2026-10-15-a-sampled-list-was-restated-as-a-universal-claim-in-the-audits-own-summary.md`: the docstring, runbook and PR body say "literal-name completeness over the selector closure, necessary but not sufficient", never "index complete".
- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`: enumerate the grammar branches (exact, dir, glob, malformed arms, non-caret) and mutate each.
- `2026-07-15-widening-a-guard-to-accept-a-future-mechanism-is-a-fail-open-unless-self-validating.md`: every accepted edge form is checked against the selector's own `_diff_edge_hit`, not against its spelling.
- `2026-07-22-widening-a-lint-repo-wide-shipped-three-fail-opens-my-green-suite-missed.md`: a widened scanner needs a non-empty assertion per surface class (shell, python, ts) so a class that scans zero files cannot pass.
- `2026-05-31-worm-bypass-migration-comment-literal-trips-comment-stripped-test.md`: comment stripping leaves quoted strings and `${#var}` alone; fixtures include `#` inside quotes and `$#`.
- `2026-05-12-hyphenated-python-modules-and-plan-precondition-verification.md`: `ci-pr-affected-replay.py` cannot be imported by name; every Python probe loads it with `importlib.util.spec_from_file_location`.

## Research Reconciliation: Spec vs. Codebase

| Claim in the brief, issue or parent plan | Reality on main | Plan response |
|---|---|---|
| Parent row 29: "scan every existing tracked file listed in the selector row `pats` (files only)" | `pats` mixes the suite file, executed code, declared DATA inputs and the two runner triggers; reading it literally gives 101,496 gap pairs (+100,232), or 10,512 (+9,248) without the runner triggers | CTO re-ruling 2026-10-20 (decision-challenges.md row 1): C plus D-code (+992), data inputs a declared limit (row 4) |
| Parent row 29: re-split at more than 622 pairs, stop at more than 1,244 | those were 50 and 100 percent of a 1,244 baseline; the live baseline is 1,264 (653 rows, 199 gap suites) | thresholds re-based on the baseline measured at PR1b's own start: re-split at 632, stop at 1,264 (row 3); the ruled definition measures +992, so it proceeds unsplit |
| "dirname hops" resolve `$(dirname "$0")/`, `$SCRIPT_DIR/`, `$DIR/` | PR1's `SOURCE_HOP` accepts any `$VAR/` prefix and resolves it against the REPO ROOT, so a `$SCRIPT_DIR/` source of a sibling is looked up at the root and silently skipped; one hop only | resolve against the including file, for the selector's own operand set plus `$DIR`, closure to depth 8 (row 9) |
| "edge parity with `_diff_edge_hit`" | `edge_hit` strips an optional `^` and treats every entry as caret-anchored; it translates `?` to a wildcard and treats a malformed `^glob:` as a plain glob; a non-caret entry is a substring in the selector, a literal-equal here | rewrite `edge_hit` to the selector's grammar; prove it with a bash-versus-python differential (row 7); no live effect today (no non-caret or malformed entry in the 3,858 live edges) |
| "comment stripping by extension" | `strip_comments` blanks `#` and `//` lines in every file | extension table (row 8); measured 0 live effect |
| Parent tasks 1b.6: "report the new `SOLEUR_PR_AFFECTED_AUDIT` line" | the line already carries `refs=` and `files_read=` | no format change; the reach-differential receipt carries the added-pair list |
| The audit takes about 5.5 minutes | the audit itself is 7 s on a saved rows file; 5m13s is the `--print-selection` pre-pass (cold, loaded machine) | PR1b reuses a saved rows file for every measurement and quotes the pre-pass time separately |
| Other open PRs touch the affected area | PRs 10566, 10546, 9640 and 6778 edit `scripts/test-all.sh`, PRs 10376 and 7390 edit both `scripts/lib/test-affected-paths.sh` and `scripts/test-all.sh` (registration or declaration edits); none lists `scripts/ci-pr-affected-replay.py`, its test or the runbook (`gh pr view <n> --json files` loop over all open PRs) | no file overlap; re-measure the live numbers on the rebased tree because those PRs move the row set |

## Technical Rulings

One CTO round on 2026-10-20 (spawned with "do NOT use AskUserQuestion"); the rows are persisted in `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr1b-audit-reach/decision-challenges.md`. Summary:

1. Reach = C plus D-code. C: from each suite input follow `source`/`.` hops to depth 8, operands resolved against the including file, read from any tracked file, no use of `pats`. D-code: then walk to depth 8 over code files (`.sh .bash .py .ts .tsx .js .mjs .cjs .mts .cts .rb`) that appear in the row's `pats` AND are named literally by an already-scanned text; runner triggers are never nodes; files only.
2. Non-code declared inputs are never scanned (a declared limit); a data table with a code extension is scanned by the extension rule.
3. Thresholds: relative to the baseline at PR1b's start commit; re-split PR4 and PR5 by gap class at 50 percent, stop the series at 100 percent. The ruled definition measures +992 on 1,264.
4. Drain-reveal: reach is frozen as a definition but its result moves through declared edges (declaring a code file makes it read). PR4 and PR5: accept-row when the suite does not read or execute the file, declare an edge only when it does, and re-run the audit to a fixpoint inside the PR. Worst case if every code gap were declared: 5,526 code edges and 4,273 non-code gaps.
5. Lead decisions (taste, rows 6-11): no selector edit; full `_diff_edge_hit` parity with a bash-versus-python differential; comment table; operand forms; reach-differential receipt; the ADR-276 amendment text stays a PR3 task and this PR documents the same limits in the docstring and the runbook.
6. CTO round 2 (rows 15-16, deepen-plan): walk files also follow `source` hops (measured +16 pairs; the declared limit narrows to match), and the read order is canonicalised before numbering (per row input, its closure, then walk files by level and sorted path; rows of a label ordered by first pattern; de-duplicated by real path) so accept-row ordinals cannot depend on selector row order.
7. Operator hold (row 12): no flip of `CI_PR_AFFECTED`, no lock removal, no replay or go/no-go re-run, no PR D; nothing in this PR touches a variable, workflow, lock or `scripts/required-checks.txt`.

## Implementation Phases

One normal feature PR off `main`, never stacked. PR text ends `Ref #9729` and `Ref #10448` and never uses a closing keyword. All edits are to the audit tooling, its suite, one runbook and the spec receipts; `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `.github/workflows/ci.yml` and `scripts/required-checks.txt` are NOT edited.

### Phase 0 - baseline on the PR's own tree

1. `git fetch origin main`, rebase if main moved, and record the start commit (`git rev-parse HEAD`).
2. Save the old SUT: `git show HEAD:scripts/ci-pr-affected-replay.py > <scratch>/old-sut.py` and its blob sha (`git rev-parse HEAD:scripts/ci-pr-affected-replay.py`); the receipt records the sha so it can be regenerated.
3. Build the rows once, from a DETACHED CHECKOUT of the start commit, never the working tree (the selector derives `pats` from working-tree text, including this suite's own file, which Phase 1 edits; building in place would mix two trees): `git worktree add --detach <scratch>/pin <start commit>`, then `cd <scratch>/pin && env -u CI -u TEST_GROUP bash scripts/test-all.sh --print-selection --paths=README.md > <scratch>/rows.txt` (minutes; run it in the background and poll its output with the Monitor tool, never a foreground wait; remove the pinned worktree afterwards). Record `sha256sum <scratch>/rows.txt` for the receipt header. Every later measurement uses `--root <scratch>/pin --list <scratch>/rows.txt` (7 s), so the audited tree is the pinned one too.
4. Baseline numbers from the OLD SUT: `python3 <scratch>/old-sut.py audit --list <scratch>/rows.txt | tail -1`. Expect about `suites=653 gap_suites=199 gap_refs=1264`; whatever it prints is the PR's baseline `B`, with re-split line `ceil(B/2)` and stop line `B`.

### Phase 1 - failing tests first (RED)

In `plugins/soleur/test/ci-pr-affected-replay.test.sh`, add a section `audit reach (PR1b)` after the PR1 audit sections, with scratch `git init` repos built by the existing `mkf`/`srow`/`saudit` helpers (`GIT_CEILING_DIRECTORIES` set as the PR1 fixtures do). Fixtures live in their OWN scratch repo `$RREPO` (never the shared `$SREPO`/`$AREPO`: new tracked files would change the populations the existing mutation rows and the 20,000-path fixture depend on). Every fixture sits beside a positive control. RED-first applies to the behaviour rows below (reach, comment table, edge parity, cost): run them against the PR1 SUT before any SUT edit and keep the RED list in the PR body. The `mutate` rows of the Guard matrices need an `old` anchor that appears exactly once in the NEW code, so they are written in Phase 2 as each helper lands, not in Phase 1. Table-driven loops emit one named `pass`/`fail` per table row (a single verdict per table would hide which form broke). The bash oracle is computed once at the start of the section; per-mutant work re-runs only the python side (the suite already takes about seven minutes, 1.3 s per mutant, and the new rows add roughly one to one and a half minutes).

1. Hop closure: a chain `suite -> lib1 -> lib2 -> lib3` where only `lib3` names `data/deep.txt` (reported as a gap; PR1 reads one hop), a 9-lib chain pinning depth 8 in both directions (the path named in the 8th library is reported, the one in the 9th is not), a file with two `source` lines where only the second uses `$SCRIPT_DIR/`, and a cycle (`a` sources `b` sources `a`) whose `--all-refs` output lists each library's line exactly once; plus a fan-out lattice (k libraries each sourcing all k) read under the operation-count instrument, so a dropped visited set shows as work growing with k factorial-style paths, not as a hang.
2. Operand forms in ONE table-driven loop (row: form, library directory, expected target), each library in a directory that differs from the suite's, with a two-hop variant (suite -> library in directory A -> target in A, so that "resolved against the suite's directory" is distinguishable from "against the including file"), a floor on the table size: `$(dirname "$0")/`, `$(dirname "${BASH_SOURCE[0]}")/`, `$SCRIPT_DIR/`, `${SCRIPT_DIR}/`, `$HERE/`, `${HERE}/`, `$DIR/`, `${DIR}/` (resolved against the including file, `..` normalised), `$REPO_ROOT/`, `${REPO_ROOT}/`, `$ROOT_DIR/`, a bare `./lib/x.sh` (the repo root), and ONE unknown `$X/` prefix (tried at the repo root, as PR1 did; live files use `$PROJECT_DIR/`, `${ROOT}/`, `$W/` and similar, and only a tracked target is ever read). Negatives: an untracked target is not read, `scripts/test-all.sh` as a target is never read, a prose line `see. lib/x.sh` is not a hop, and a hop in a comment is not a hop.
3. `pats` walk: a code file listed in `pats` and named by the suite is read (and its named path reported); the same code file NOT listed in `pats` is not read; a code file listed in `pats` but named by nothing is not read; a `.md`, `.yml` and `.tsv` file listed in `pats` and named by the suite is NOT read (declared limit, negative control); a 9-level naming chain of pats code files pins depth 8; `scripts/lib/test-affected-paths.sh` (a stub trigger in the fixture repo) in `pats` is never read even when named, asserted by the ABSENCE of the path only the stub names; a `glob:` or `dir/` entry in `pats` is never a node; the per-row walk: two selector rows with the same label where row A lists `helper.sh` in `pats` and declares the path it names, and row B does not list `helper.sh`; the correct verdict is no gap, and a mutant that unions `pats` across the rows (or reads `helper.sh` for row B) produces one.
4. Unreadable reach: a tracked hop target at depth 3 that is a dangling symlink makes only that suite `unaudited unreadable:<rel>` (exit 1) while a neighbouring suite is still scanned; same for a pats code file.
5. Comment table: `# docs/a.md` in a `.sh`, `.py`, `.rb`, `.yml` is blanked, `// docs/a.md` in a `.ts`, `.tsx`, `.js`, `.mjs` is blanked, `// docs/a.md` in a `.sh` and `# docs/a.md` in a `.ts` are KEPT, a `.md`, `.tsv`, `.txt` and an extensionless file strip nothing, tab-indented and CRLF comment lines follow the PR1 shapes, `#` inside quotes and `$#`/`${#x}` are never comments, and line numbers survive (the `--all-refs` ref line carries the physical number). The existing re-anchored rows (`comment-line-deleted`, `audit-comments-counted`) already cover "line deleted" and "never stripped"; no duplicate rows are added.
6. Edge credit parity: a table of (edge, path, expected) rows GENERATED from the grammar's arms (one row per kind and per arm, not hand-typed volume), run twice, once through `python3` calling the SUT's `edge_hit` (the `$SUT` copy the mutation harness edits, not `$REAL_SUT`) and once through the real selector code (see Guard 2). Rows: exact, `dir/`, `^dir` without the slash (exact), well-formed `glob:` with `*` crossing `/`, each malformed arm built so that ONLY its own arm can fire (arms mask each other: `glob:dir/a?b/*` also trips the head arm, so a mutant without the charset arm would survive; put the clean `dir/` head first and the bad byte in the tail, for example `glob:scripts/*/a?.sh` with path `scripts/x/zz.sh`) and with a path that the well-formed reading REJECTS (so the PR1 behaviour and the new one differ): a byte outside `[A-Za-z0-9_./*-]` (`?`, `[`, space, `+`), a head that is absolute, starts `./`, starts `../`, or contains `//`, `/./`, `/../` (six alternatives, one row each), a head not ending in `/` (`glob:*.sh`, a bare `glob:`), a tail ending in `/`, a tail with no `*` (reachable only as `glob:dir/`); non-caret rows: a substring entry, a non-caret `glob:` entry (dead), the empty non-caret entry (matches everything) and the bare `^` (exact empty string, matches nothing). Names holding a tab, quote or newline are excluded (the selector normalises them) and the exclusion is stated in the suite.
7. Order and ordinals: for each suite input in order, the input then its source closure (breadth first, discovery order), then, after all inputs, the pats-walk files level by level (sorted within a level); this keeps the PR1 order for directory suites (`input1, libs1, input2, libs2`). Identical reading lines in the suite, a closure library and a walk file get ordinals 1, 2, 3, asserted through the FILE printed on each `--all-refs` ref line (the liveness check keys on anchor and ordinal only, so a swap shows in the file column, not in staleness); the same fixture with its two selector rows presented in both orders must print identical `ref` lines.
8. Summary and marker: the `SOLEUR_PR_AFFECTED_AUDIT` line keeps exactly its PR1 field list (a regex over the line), `files_read` and `refs` rise on the reach fixture, and a per-surface assertion on a SYNTHETIC fixture (the suite is fully synthetic; a live selection takes minutes and would drift with sibling PRs): one `.sh`, one `.py` and one `.ts` file each reached through the walk are read, so a class that scans zero files fails.
9. Cost instrument: drive `reach_texts` (and `audit_census` on a one-row list) under the PR1 `settrace` line-event counter plus `index.ops` (the existing `row_scan_ops` reaches only `scan_text`). Assert LINEAR scaling in the width of `pats` (400 versus 4,000 entries: at most about 12x, because building the `code_pats` set is one pass over `pats`) and, separately, that work does not multiply by files or levels (an 8-level chain with every file listed). The intersection is taken from the named side (`named & code_pats`), never by looping `pats` per node. The depth-8 chain is bounded by the cap and is not a cost axis; the fan-out lattice covers the visited set.

### Phase 2 - implementation (GREEN) in `scripts/ci-pr-affected-replay.py`

1. Comment table. `COMMENT_PREFIX` maps an extension to its line-comment prefix (`#` for `.sh .bash .py .rb .yml .yaml`; `//` for `.ts .tsx .js .jsx .mjs .cjs .mts .cts`, the last group matching `BUN_TEST` so directory-suite members are covered); `strip_comments(text, prefixes)` blanks a whole-line comment only when the file's own prefix matches; an empty tuple strips nothing. `read_text` passes the REAL path's extension (a symlink and its target are one read). Keep the PR1 line handling (`\n` split only, CRLF only at the line feed, blank-not-delete).
2. Hop resolver. Replace `SOURCE_HOP` by one pattern for the keyword (`source` as a word, or `.` not preceded by a word character or `.`) and one operand table; `hop_targets(rel, text)` returns normalised repo-relative targets: dir-relative forms resolve against `dirname(rel)`, root forms and every other `$VAR/` and bare path against the repo root; only `.sh`/`.bash` targets, only tracked ones, never `RUNNER_TRIGGERS`; memoise the RAW matches (form, operand) per real path on the index (`index.hops`), unexcluded, and resolve them per call against the LOGICAL including path (the selector resolves `$SCRIPT_DIR` against the file's logical directory; a symlinked library memoised with a resolved target would use whichever name was seen first); one symlinked-library fixture pins it.
3. Closure. `suite_texts` follows the hops breadth first to depth 8 per suite input (a visited set keyed on the real path ends cycles), appending in discovery order, each file once, so the order stays `input1, its closure, input2, its closure` as in PR1; a tracked target that cannot be read lands in `bad` exactly as a one-hop library does today. Walk files (step 4) get the same closure, sharing the 8-level cap (CTO round 2, decision-challenges.md row 15: measured +16 pairs, the selector follows every file's edges, so leaving walk files out left a gap the selector does not have). The audit reads text up to distance 8 while the selector's own loop reads up to distance 7 (`_depth < 8`); the audit is the wider one, which over-reports and is the safe direction, and the docstring says so.
4. `pats` walk. `reach_texts(root, inputs, pats, index, bad)` = `suite_texts` then the walk: `code_pats` = the ordered, de-duplicated tracked files named by caret entries of `pats` that are not `glob:`, not `dir/`, in the code extension set and not runner triggers; per level (up to 8) every file added by the previous level contributes `index.refs` (the same memoised scan `suite_refs` uses); each named member of `code_pats` not yet read is read through `try_read` (sorted within the level) and appended. `audit_census` calls it per selector row with that row's `pats`. All state is ROW-LOCAL: `reach_texts` keeps a per-call `seen` set keyed on the real path; `PathIndex.raws`/`views`/`refs` supply contents only and are never the "already read" test (otherwise row B would skip a file row A read and verdicts would depend on row order). Before numbering, `audit_census` puts `texts_of[path]` into the canonical order (CTO round 2, row 15): per row, the input then its closure in discovery order, then walk files (and their hop closures) by level and sorted path; rows of a label ordered by their first pattern; de-duplicated by real path. `suite_texts` keeps meaning "closure only, no walk" and its 4-tuple `(real, full, light, written)` shape is frozen, because `receipts/audit-differential.py` (archived PR1 receipts) unpacks it.
5. Edge credit. Rewrite `edge_hit(pt, path)` to the selector's grammar: a non-caret entry is `pt in path`; a caret entry is `glob:` (apply the charset arm, the head arms, the tail arms, then a `*`-crosses-`/` match on the whole path), `dir/` (prefix) or exact; every malformed arm returns True. One function, one call site (`audit_census`); keep the name.
6. Docstring and `--help` (the SINGLE source of the reach definition and the declared limits; the runbook points at it, PR3's amendment quotes it): replace "`source` hops are one level" and the "suite file, then sourced libraries in hop order" ordinal sentence; add the reach definition and the DECLARED LIMITS list (see Handoff to PR3) and the sentence "literal-name completeness over the selector closure, necessary but not sufficient".
7. Re-anchor the existing mutation rows whose edit text moved (they must each land exactly once and still kill): `audit-comments-counted`, `comment-trailing-stripped`, `comment-tab-indent-kept`, `comment-line-deleted`, `audit-edge-as-regex`, `audit-edge-as-regex-exact`, `audit-glob-not-a-glob`, `scan-library-hop-dropped`, plus any row the suite reports as `edit-failed`.

### Phase 3 - receipts and the numbers

1. Commit `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr1b-audit-reach/receipts/reach-differential.py` (standard library only; loads both SUTs with `importlib`; usage `reach-differential.py ROOT ROWS_FILE --old-sut PATH [--sut PATH] [--out TSV]`; both audits run through `audit_census` with no accept file) and the generated `reach-differential.tsv`: header `# old_sut=<blob sha> tree=<start commit> rows_sha256=<hash> base_pairs=B new_pairs=N added=A removed=R`, then one row per added pair: `suite<TAB>path<TAB>path_class<TAB>via`, `path_class` = `code` or `non-code` (the gap-class split PR4 and PR5 use), `via` = the first `file:line` that `Census.ref_lines` gives for the pair (the SUT's own location data; the script re-implements no walk). `added` is GROSS (pairs in the new audit that are not in the old one, the ruling's definition); `removed` is listed row by row too, because the comment table and edge parity can only narrow, and every removal must be justified in the PR body (expected 0), so net is `added - removed`.
2. The stop line is enforced where the numbers are produced, not by a permanent suite row over a frozen file: `reach-differential.py` writes nothing and exits 1 when `added >= base_pairs`, and prints the re-split note (and exits 0) when `added >= ceil(base_pairs / 2)`; the suite keeps at most one row that runs the script on a scratch repo against a FIXTURE old SUT (a mutate-copy or stub of the SUT: the real old blob is absent in a shallow CI clone) and checks the header counts equal the data rows and the exit codes at the four boundaries `ceil(B/2)-1`, `ceil(B/2)`, `B-1` and `B`, plus `B=0`, asserting no file is written at `B` (decision-challenges.md row 13).
3. The `reach-differential` numbers come from the PINNED tree only. The final-tree full audit (Phase 5) also reads this PR's own new fixture text and files, which name tracked paths, so it is expected to be somewhat larger; quote it as a separate figure and never mix the two. Quote in the PR body and as a comment on #10448: the new `SOLEUR_PR_AFFECTED_AUDIT` line, `added`/`removed`, the code versus non-code split, the top ten additions, wall time of `audit --list` (target 30 s or less for the scan) and of the `--print-selection` pre-pass reported separately.

### Phase 4 - documentation

1. `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`: a short paragraph in the audit section: the reach in one sentence, the drain-reveal rule, "`gap_suites=0` is literal-name completeness over the selector closure, necessary but not sufficient", and a pointer to `python3 scripts/ci-pr-affected-replay.py --help` for the full definition and the declared limits (the docstring is the single source, so the list cannot drift between four copies). No edit of earlier ADR text.
2. Nothing else: no ADR edit (PR3), no workflow, no variable.

### Phase 5 - verification before ready

`bash plugins/soleur/test/ci-pr-affected-replay.test.sh` green (including the unchanged PR1 receipt check, the `row_regen` rows that run `receipts/audit-differential.py` against the changed SUT, and every re-anchored mutation row); read `scripts/suite-durations.tsv` row semantics and edit that row only if the shard-totality census requires it; the audit against the pinned rows file, then `reach-differential.py` on the same pinned tree and rows (it enforces the stop line), then a full `python3 scripts/ci-pr-affected-replay.py audit` once on the final tree; `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch`; the acceptance commands below.

## Files to Edit

- `scripts/ci-pr-affected-replay.py` (comment table, hop resolver and closure, pats walk, edge credit, docstring)
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` (new `audit reach (PR1b)` section, re-anchored mutation rows, one generator row for the reach receipt)
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` (one paragraph: reach, drain-reveal rule, pointer to `--help`)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr1b-audit-reach/receipts/reach-differential.py`
- `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr1b-audit-reach/receipts/reach-differential.tsv`
- `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr1b-audit-reach/{tasks.md,decision-challenges.md}` (pipeline artifacts)

Glob check (`hr-when-a-plan-specifies-relative-paths-e-g`): the three Edit paths were confirmed with `git ls-files`; the Create paths are new. The receipt directory is archived with the spec at ship, so the suite's one generator row finds the script with `find "$SPECS" -path '*/receipts/reach-differential.py'` under both the live and the archive spec roots (as the PR1 regenerator row does for `audit-differential.py`) and FAILS, never skips, when it finds none. The replay suite stays glob-registered (`plugins/soleur/test/*.test.sh`), so no registration, `scripts/suite-shard-legs.tsv` or `scripts/suite-durations.tsv` edit is needed.

## Sibling PR Overlap

None on the planned files. Open PRs touching the affected area (verified live with `gh pr view <n> --json files,state` by the git-history pass): #10566, #10546, #9640, #6778 (`scripts/test-all.sh`) and #10376, #7390 (both `scripts/lib/test-affected-paths.sh` and `scripts/test-all.sh`); none lists `scripts/ci-pr-affected-replay.py`, `plugins/soleur/test/ci-pr-affected-replay.test.sh` or the runbook. They move the selector row set, so every PR1b number is re-measured on the rebased tree. Re-check with the `gh pr list` plus `gh pr view <n> --json files` loop at the start of Phase 5.

## Open Code-Review Overlap

None. The `code-review` open issues were queried (`gh issue list --label code-review --state open`) and none names `scripts/ci-pr-affected-replay.py`, `plugins/soleur/test/ci-pr-affected-replay.test.sh`, the runbook or `scripts/audit-suite-reads.sh`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "implement PR1b (audit reach) now, on a fresh branch from main" [brief] | Phases 0-5 on `feat-one-shot-s4-affected-index-pr1b-audit-reach` | mapped |
| 2 | "PR1b (selector `pats` closure, comment stripping by extension, dirname hops, edge parity) lands before the ratchet" [#10448 comment of 2026-10-20] | Phase 2 steps 4, 1, 2-3, 5 | mapped (the `pats` closure is narrowed by the CTO re-ruling, row 1) |
| 3 | "The CI_PR_AFFECTED lever stays dark" [brief] | no variable, workflow or `required-checks.txt` edit; AC | mapped |
| 4 | "do NOT remove the lock, and do NOT re-run the replay or the go/no-go ... leave them as operator holds (file/keep an action-required note, never execute)" [brief] | Non-Goals; decision-challenges.md row 12; post-merge comment keeps the hold | mapped |
| 5 | "Use \"Ref #10448\" in the PR body, not \"Closes\"" [brief] | AC (grep) | mapped |
| 6 | "declared limits go in the ADR-276 amendment (PR3)" [#10448 comment] | Handoff to PR3; docstring and runbook carry the same list now | mapped |
| 7 | "never ask the operator a technical question" [brief] | one batched CTO round, rows 1-5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Hop closure with dirname-aware operands | "dirname hops" | asked |
| `pats` walk (D-code) | "selector `pats` closure" | asked (shape set by the CTO re-ruling) |
| Comment table | "comment stripping by extension" | asked |
| `edge_hit` parity and the bash-versus-python differential | "edge parity" | asked (the differential is how parity is proven: inferred - justification: the selector's grammar is restated in five places and a hand-written fixture table can drift from the real function) |
| Reach-differential receipt generator (it enforces the stop line itself) | "PR1b adding more than ... pairs re-splits PR4 and PR5" [parent ruling] | inferred - justification: the thresholds are measured on added pairs, so the list is the evidence, PR4 and PR5 need the code versus non-code split, and a generator that refuses to write past the stop line keeps the series guard executable without a permanent suite row over a frozen file |
| Runbook and docstring limits | "declared limits go in the ADR-276 amendment (PR3)" | inferred - justification: the audit's documentation says "source hops are one level" today and would contradict the code the moment this lands |

### Split Assessment

- Subsystems touched: 3 - `scripts`, `plugins/soleur`, `knowledge-base`
- Planned files: 6 (3 edits, 3 creates incl. artifacts) | Estimated changed lines: about 700 of code and tests, plus a generated receipt of roughly a thousand data rows
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - below every threshold; the receipt is generated data

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-visible. A mis-scoped audit gives the founder a wrong "gap list" while the lever is dark; a mis-credited edge could later let the ratchet pass over an undeclared read, which only matters after activation (explicitly out of scope).
- **If this leaks, the user's data is exposed via:** no vector. The tooling reads tracked file names and suite text and prints repository paths; no credential, personal data or customer content is read, stored or logged.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the work changes no runtime behaviour while `CI_PR_AFFECTED` is unset; the harm class (a skipped suite letting a regression land) exists only after activation, which needs its own go-ahead.

threshold: none, reason: the touched paths are CI audit tooling, its shell test and a runbook, with no web-platform runtime, no credential or workflow-secret path, and no workflow file is edited.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO agent ruled the reach fork on 2026-10-20 in one batched round after the planner measured that the parent ruling, read literally, breaches its own stop line by two orders of magnitude (see `## Technical Rulings`). No Product/UX surface exists (no UI file in Files to Edit or Create); Marketing, Sales, Legal, Finance, Operations and Support have no implication (internal CI tooling; no vendor, spend or customer-facing change; the budget owner's funding decision is recorded on #10448).

## Architecture Decision (ADR/C4)

### ADR

No new ADR and no ADR edit in this PR. This PR changes no boundary, substrate, trust boundary or existing ADR decision; it fixes the definition of an audit that ADR-276's 2026-10-16 item 5 already names as the entry condition. The decision record for that definition (frozen reach, the declared limits, the drain-reveal rule, the re-based thresholds) is the dated `## Amendment` the series assigns to PR3 (parent tasks 3.7 and 3.9, and the budget owner's comment on #10448: "declared limits go in the ADR-276 amendment (PR3)"). That is a task in the same plan series with its text prepared in `## Handoff to PR3` below, not a follow-up issue; ADR-276 is append-only and PR3 writes the amendment.

### C4 views

No C4 impact. Read in full: `knowledge-base/engineering/architecture/diagrams/{spec.c4,views.c4}` and the element and relationship declarations of `model.c4` (`founder`, `contributor`, `platform.plugin`, `github` "Source control, CI/CD, issue tracking, and releases"). Checked: (a) external human actors - none added or changed; (b) external systems or vendors - none (the audit runs offline over tracked files; `github` is already modeled and no edge is added); (c) containers or data stores - none (a receipt TSV in the spec directory is not a modeled store); (d) actor-to-surface access relationships - unchanged. `bash plugins/soleur/test/c4-count-parity.test.sh` was run on this branch and passes (`Failed: 0`), and no workflow, job or monitor is added, so no derived cardinality moves.

### Sequencing

The ADR text lands with PR3 describing the definition as built here; PR1b lands first because the definition must be frozen before the baseline exists.

## Guard Contract

Plan-review (2026-10-20) trimmed the matrices to one mutant per property failure and made the harness, not the plan, responsible for scoring: every row carries a pristine control at the expected exit on the same fixture, asserts the exact rc and a distinct output token (several rows share rc 1), and a mutant that crashes is `crashed`, not `killed` (the PR1 `mutant_outcome` scoring). Rows that edit the SUT use `mutate`; rows that edit the suite or the selector oracle are harness rows.

### Guard 1 - audit reach (closure plus pats walk)

**Property.** Every tracked path that a registered suite names literally, directly or through a library it sources to depth 8 or through a code file its own selector row lists and scanned text names (depth 8), is reported as a gap unless an edge, a live anchor-keyed accept row or the runner trigger list covers it, and no file outside that closure is read (data files in `pats`, runner triggers, untracked targets).

**Assembly.** The population is every non-always-on row the selector prints, not a list of current suites. Chokepoints, in the order a path reaches the verdict: `suite_inputs` (the suite file or a directory suite's test files), `hop_targets` and the closure inside `suite_texts`, the `pats` walk inside `reach_texts`, the read chokepoint `try_read`/`read_bytes` (every read, with containment, regular-file and 8 MiB checks), `suite_refs` (names), `edge_hit` (credit), `judge_rules` (accept rows). Members that must flow through the one chokepoint: suites with a file first pattern, directory suites, sourced libraries at every depth, pats code files at every level, rows that share a label (per-row reach, per-label verdict). Everything that adds a gap enters through `suite_refs`; the only stored value is the accept file, validated against the live census.

**Mutation matrix.**

| # | Edit (must drive the guard RED) | Expected red |
|---|---|---|
| M1 | reach narrows: the closure stops after one hop (PR1 behaviour), and separately `reach_texts` returns only the suite inputs (the guard's own dispatch) | the three-level chain fixture no longer reports `data/deep.txt`; the synthetic per-class fixture (a `.sh`, a `.py` and a `.ts` file reached through the walk) reads none of them and its floor reds; pristine control green |
| M2 | depth cap changed to 7, and separately to unbounded | the 9-library chain: the path in library 8 vanishes (cap 7), the path in library 9 appears (unbounded); two sub-rows |
| M3 | the resolver stops at the first matching hop of a file (first-member stop) | a file with a root-relative first `source` and a `$SCRIPT_DIR/` second reports only the first |
| M4 | dir-relative forms resolved against the repo root (PR1 behaviour), and separately against the SUITE's directory instead of the including file | a library in another directory sourcing its sibling: the sibling's path vanishes (first), the nested-library row misreads (second); the table-driven operand loop reds on the affected forms |
| M5 | the pats walk ignores `pats` (reads any named code file), and separately reads data files in `pats` | the code file named but not listed is read (a gap appears); the `.md`, `.yml` and `.tsv` controls appear as gaps |
| M6 | the walk reads a runner trigger when named and listed | the stub trigger in the fixture repo names `zz/only-from-trigger.txt`; the path appears as a gap when it must be absent |
| M7 | the walk is not per row (it unions `pats` across rows that share a label) | the two-row fixture of Phase 1 item 3 (row A lists and declares, row B does not list) reports a gap where the correct verdict is none |
| M8 | an unreadable hop target or pats code file is skipped silently | `unaudited ... unreadable:<rel>` missing and exit 0 instead of 1; the neighbouring suite is still scanned in the pristine control |
| M9 | closure and walk order swapped (REORDER row: ordinals), and separately the canonical sort of `texts_of` removed | the identical-lines fixture prints the wrong file on the ref line of ordinals 1, 2 and 3 (asserted through the file column, because liveness keys on anchor and ordinal only); the same two rows presented in both orders must print identical `ref` lines |
| M11 | the two depth constants (hop closure and pats walk) share one name and one is edited, or the `RUNNER_TRIGGERS` exclusion is dropped inside `hop_targets` | the 9-library chain and the 9-level naming chain are separate rows, so each constant is pinned alone; `scripts/test-all.sh` named as a hop target must stay unread |
| M12 | the walk keeps its "already read" set in `index.raws` instead of a per-call set | row B (audited second, lists `helper.sh`) silently skips a file row A read; the fixture runs both row orders |
| M10 | the visited set is dropped | only the fan-out lattice under the line-event cap (an `OverflowError` guard) kills it: the cycle fixture's output is identical either way (the per-call de-duplication and the depth cap hide the mutant), so the cycle row stays as a terminates-and-listed-once control, not as the kill |

**Harness rows.** Edit the suite, not the guard: delete the three-level chain fixture and the 9-library fixture; the section's per-form floors (an assertion count per fixture family and a "control reported" check) must go RED. Must-PASS non-canonical inputs: a library sourced as `"${SCRIPT_DIR}/../lib/x.sh"` (a `..` segment), a library whose `source` line is indented with a tab, and a pats code file listed in `pats` while the suite names it through a longer path prefix; all must exit as predicted, so a guard that rejects everything cannot pass.

**Anchor.** Nothing here is a stored-value comparison: the reach is recomputed from the tree each run. The controls outside the commit are (a) the reach-differential receipt, regenerated by a reviewer from the OLD SUT blob recorded in its header, whose generator refuses to write when `added >= base_pairs`, and (b) human review of the top additions. The receipt lists the set of added pairs, not only a count, so a swap of one pair for another is visible.

### Guard 2 - edge credit parity with the selector

**Property.** `edge_hit(pt, path)` returns True exactly when `_diff_touches` with the single entry `pt` would return 0 for a diff whose only name is `path`.

**Assembly.** The selector's two entry forms in `_diff_touches` (caret and non-caret), the three kinds in `_diff_edge_hit` (`glob:`, `dir/`, exact) and each malformed arm of the glob kind (charset, non-repo-relative head, head not `/`-terminated, tail ending `/`, tail without `*`); the audit has exactly one credit function and one call site (`audit_census`), checked by a grep row in the suite. The scan fixtures and the live `pats` use only well-formed caret entries today, so the generated table, not the live data, is the proof. Oracle mechanics: the suite extracts from `scripts/test-all.sh`, by content anchors, the line `_NL=$'\n'` (it sits ABOVE `_DEH_SRC=""`; without it the exact and dir arms silently degrade to substring matches), the `_DEH_SRC=""`/`_DEH_N=""` initialisers, the whole `_diff_edge_hit` function and the whole `_diff_touches` function; it sets `_diff_names=<path>`, `_diff_detect_ok=1`, `_diff_head_ok=1`, `_FULL_GATE=0`, `_ENUMERATE=0`, unsets `CI` and `SOLEUR_TEST_FORCE_ALL` (their early returns would answer "match" for every non-caret row) and runs under `LC_ALL=C`. If `_diff_touches` proves too brittle to extract, the non-caret rows are marked spec-backed (not oracle-backed) in the suite output instead of being dropped.

**Mutation matrix.**

| # | Edit (must drive the guard RED) | Expected red |
|---|---|---|
| M1 | `?` dropped from the rejected-byte charset, so it falls through to the wildcard translation (PR1 behaviour) | the row with a `?` glob and a path the well-formed reading rejects: bash says match, python says no |
| M2 | one mutant per malformed arm, each on its own source line so every `mutate` anchor lands once (charset; each of the six head alternatives; head not slash-terminated; tail ending slash; tail without star) that returns False for that arm only | each arm's row reds, and the others stay green, so a mutant that handles only the first arm still reds on the second (second member after a compliant first) |
| M3 | a non-caret entry compared by equality, and separately a non-caret `glob:` entry treated as a live glob | the substring row and the dead-glob row |
| M4 | `*` does not cross `/` in a well-formed glob | the `knowledge-base/**.sh` versus `knowledge-base/a/b/c.sh` row |

**Harness rows.** Run against `$SUT`, the copy the mutation harness edits, never `$REAL_SUT`. Edit the oracle, not the guard: point the extractor at a copy of `scripts/test-all.sh` with `_diff_edge_hit` renamed; the suite must FAIL with a named reason, never skip (dispatch row, a harness row because `mutate` edits only the SUT); and shrink the generated table to one row; the table-size floor reds. Must-PASS non-canonical: a caret-less entry that IS a substring of a longer path (credited), and `^dir` without the trailing slash (exact, not a prefix), both as the selector decides.

**Anchor.** The real `_diff_edge_hit` and `_diff_touches` in `scripts/test-all.sh`, extracted at test time by content anchors, are the independent oracle: a stored copy would only prove consistency. A selector edit that changes the grammar reds this suite; if the anchors move, the suite fails with the named reason and the fix is to re-anchor in the same PR.

### Guard 3 - comment stripping by extension

**Property.** A whole-line comment of the file's own language is blanked (line number kept), and nothing else is: a comment line of a different language, any line of a file with an unknown extension, and `#` inside quotes or `$#` are kept.

**Assembly.** `COMMENT_PREFIX`, `strip_comments`, and the single call site in `read_text` (every file the audit reads, suite or library or walk file, passes through it); the extension is taken from the real path.

**Mutation matrix.**

| # | Edit (must drive the guard RED) | Expected red |
|---|---|---|
| M1 | both prefixes stripped for every file (PR1 behaviour) | a `// docs/a.md` line in a `.sh` and a `# docs/a.md` line in a `.ts` disappear; both fixtures red |
| M2 | unknown extensions strip `#` | the `.md`, `.tsv` and extensionless fixtures red |
| M3 | the stripped line is replaced by a non-blank placeholder or deleted by the new code path | the `--all-refs` physical line number shifts (the existing `comment-line-deleted` and `audit-comments-counted` rows are re-anchored, not duplicated) |

**Harness rows.** The suite generates one expected row per extension in the table from a SUT-independent list (otherwise dropping `.tsx`, `.rb` or `.yaml` from `COMMENT_PREFIX` survives), plus a symlink row (`link.txt` pointing at a real `.sh`: the real path's extension decides), a dotfile and a double-extension row (`x.test.ts`, `x.ts.snap`). Edit the suite: delete the `.tsv` control; the extension-class floor reds. Must-PASS non-canonical: a CRLF `.ts` file whose comment line ends `\r\n`, and a tab-indented `# ` comment in a `.py`.

**Anchor.** Outside the commit: the live-tree measurement (0 pairs added or removed, quoted in the receipt header as `removed=`), reviewed in the PR.

## Observability

This is CI audit tooling with no runtime service; the surface is the audit's marker line and the replay suite's result in the `test-scripts` leg. (Plan Phase 2.9's code-path list does not name root `scripts/`, but the schema is declared for parity with the parent plan.)

```yaml
liveness_signal:
  what: the SOLEUR_PR_AFFECTED_AUDIT marker line printed by the audit, and the replay suite's pass line in the test-scripts leg log
  cadence: every pull_request and merge_group run of ci.yml runs the replay suite (it is glob-registered); the audit itself is operator-run until the ratchet lands in PR3
  alert_target: the required `test` context turns red on the PR or the merge-queue entry
  configured_in: plugins/soleur/test/ci-pr-affected-replay.test.sh (glob-registered by plugins/soleur/test/*.test.sh)
error_reporting:
  destination: the audit exit code (1 gaps, unaudited or stale, 2 usage or value error, 3 a failed read, 4 internal) and its stderr in the Actions log
  fail_loud: an unreadable reach member is `unaudited unreadable:<rel>` and exit 1, never a skip; an uncaught Python error is rc 4, never rc 1
failure_modes:
  - mode: the reach silently narrows (a resolver form stops matching)
    detection: the reach fixtures and the synthetic per-class fixture (a .sh, a .py and a .ts file read through the walk) fail
    alert_route: required `test` context red
  - mode: the reach silently widens past the series guard
    detection: reach-differential.py exits 1 and writes nothing when added pairs reach the baseline (run in Phase 5 and quoted in the PR body); its exit codes are exercised by one suite row on a scratch repo
    alert_route: the PR is not opened or marked ready (operator-visible in the PR body), and the suite row reds if the generator stops enforcing the line
  - mode: edge credit drifts from the selector
    detection: the bash-versus-python differential over the real _diff_edge_hit
    alert_route: required `test` context red
logs:
  where: GitHub Actions job logs for the test-scripts leg that runs the replay suite
  retention: GitHub Actions default log retention (90 days)
discoverability_test:
  command: bash -c "python3 scripts/ci-pr-affected-replay.py audit --list <(printf 'AFFECTED_SELECTED\tx\t1\talways_on\t\n')"
  expected_output: SOLEUR_PR_AFFECTED_AUDIT
```

## Test Scenarios

1. A suite sources `lib/a.sh`, which sources `"$SCRIPT_DIR/b.sh"` (a sibling in `lib/`), which names `data/deep.txt`: the audit reports the gap (PR1 reported nothing).
2. A suite names `tools/helper.sh`, which is in its row's `pats`; the helper names `docs/x.md`: reported. Remove `tools/helper.sh` from `pats` (a variant row): not reported. Replace the helper by `lefthook.yml` in `pats`: not reported, even though the file names paths.
3. A `.sh` suite with a line `// see docs/x.md`: the line is a real read (kept); the same text as `# see docs/x.md` is a mention (blanked).
4. Edge `^glob:scripts/a?b/x.sh`: the selector treats it as malformed and selects on any diff, so the audit credits every path for that suite; `glob:` without the caret never credits.
5. A cycle of three libraries terminates and each file is read once.
6. Live tree: `python3 scripts/ci-pr-affected-replay.py audit --list <rows>` prints a `SOLEUR_PR_AFFECTED_AUDIT` line with `gap_refs` about 2,256 (B plus 992 at the time of planning) and the receipt's `added` equals the difference of the two audits' pair sets.
7. A hostile-width case: 4,000 entries in `pats` with the same text as a 40-entry case do the same walk work (operation-count fixture).

## Acceptance Criteria

Pre-merge:
- [ ] The PR body contains `Ref #10448` and `Ref #9729` and none of `Closes`, `Fixes`, `Resolves`: `body=$(gh pr view --json body --jq .body)` must exit 0 first (a failed `gh` must not read as a clean body), then `printf '%s' "$body" | grep -ciE '(closes|fixes|resolves) #'` prints 0 (`grep -c` exits 1 on a zero count; the criterion is the printed 0).
- [ ] No commit carries the identity `s@example.invalid` (`git log origin/main..HEAD --format='%ae %ce' | grep -c 's@example.invalid'` prints 0; the `git log` itself must exit 0).
- [ ] The lever, the lock and the required checks are untouched: `git diff origin/main...HEAD --stat -- scripts/required-checks.txt .github/workflows/ci.yml scripts/ci-pr-selection.sh scripts/test-all.sh scripts/lib/test-affected-paths.sh` prints nothing (pipeline artifacts under `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr1b-audit-reach/` are outside this check).
- [ ] RED first: the PR body lists the new reach rows that failed against the PR1 SUT before the SUT edit (Phase 1), and every new mutation row of Guards 1-3 is killed (the suite's `mutant_outcome` report shows `killed`, not `survived`, `invalid` or `crashed`) and every re-anchored PR1 row still lands exactly once.
- [ ] `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` exits 0; the PR1 receipt check over `audit-differential.tsv` is unchanged and green.
- [ ] Guard 2 differential: the suite extracts `_diff_edge_hit` from `scripts/test-all.sh` by content anchors and the python and bash answers agree on every row of the table (at least 40 rows, every kind and every malformed arm); a missing function fails the suite, never skips it.
- [ ] The reach numbers are quoted from the PR's own pinned tree: the baseline `B` (old SUT), the new `SOLEUR_PR_AFFECTED_AUDIT` line, `added` (gross) and `removed`, the code versus non-code split and the top ten additions, all from `reach-differential.py`, which exits 1 and writes nothing when `added >= B` (the stop line: the series halts for a re-ruling and this PR is not marked ready) and notes the re-split line at `added >= ceil(B / 2)` (the PR body then states that PR4 and PR5 are re-split by gap class). The receipt header carries `old_sut`, `tree` and `rows_sha256` so a reviewer can regenerate it.
- [ ] `removed` is explained: every pair the new audit drops versus the old one is listed in the receipt and justified (expected 0).
- [ ] The scan stays inside the PR1 budget: `time python3 scripts/ci-pr-affected-replay.py audit --list <rows>` is recorded (the PR1 scan target was 30 s or less for the scan on the pinned tree; today 7 s), the operation-count fixture covers the new axes, and the `--print-selection` pre-pass time is reported separately.
- [ ] The `SOLEUR_PR_AFFECTED_AUDIT` field list is unchanged (a regex row in the suite).
- [ ] The docstring (the single source) no longer says "`source` hops are one level" (`grep -c 'hops are one' scripts/ci-pr-affected-replay.py` prints 0) and carries the reach definition and the declared limits of `## Handoff to PR3`; the runbook paragraph has the phrase "necessary but not sufficient" and the pointer to `--help` (`grep -c 'necessary but not sufficient' knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` prints at least 1).
- [ ] `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` prints `[PASS]`.
- [ ] `scripts/test-all-orphan-log-retention` red alone on a PR run is re-run and recorded as the known flake, not treated as a regression.

Post-merge:
- [ ] #10448 receives a comment with the live audit line, `added`, the gap-class split, the re-split decision for PR4 and PR5, and the Handoff list; the issue stays open and the operator hold on the flip, the lock, the replay and the go/no-go stays recorded (ship keeps or files the action-required note; nothing is executed).

## Handoff to PR3 (and PR4, PR5)

PR3's ADR-276 amendment, the runbook and the ratchet's failure text must carry these, taken from the rulings so nothing is rediscovered:
1. The frozen reach definition: per suite input (a file, or a directory suite's bun-discoverable test files) the input then its source closure (depth 8, operands resolved against the including file, `.sh`/`.bash` targets, tracked only), then, after all inputs, the pats-walk over code files (extension set above, depth 8, named literally by scanned text, runner triggers never nodes). Ordinal order is that order. The docstring of `scripts/ci-pr-affected-replay.py` is the single source; PR3's amendment quotes it. PR3 reads every oracle input from the PR tree (parent row 32) and prints `oracle-inputs-changed:`.
2. Declared limits, stated as mechanisms not counts: suites the runner declines (gated by their own `_diff_touches --pr-gated` blocks, ADR-262); directory and glob reads; variable-built names and variable-indirect hop operands; `cd ... && pwd` spellings; bun helper files and the bunfig preload; the registration-only and staged-diff premise behind `RUNNER_TRIGGERS`; non-code declared inputs (their contents are never scanned, row 4); hop targets that are not `.sh` or `.bash`; an unknown `$X/` operand prefix is tried at the repo root (only a tracked target is read); `$DIR/` and `${DIR}/` are resolved by the audit although the selector's own operand set does not include them (the audit is the wider reader, which over-reports); the audit reads text at distance 8 where the selector reads distance 7 (over-report); ANSI-glued paths (`\033[0m<path>` is display text); block comments, docstrings and heredoc bodies (over-report); extensionless files strip no comments (over-report); a hostile 255-character tracked name against a hostile suite (cost).
3. The drain-reveal rule for PR4 and PR5 (row 5): accept a false-positive row when the suite does not read or execute the file, declare an edge only when it does, and re-run the audit to a fixpoint inside the PR; the baseline moves only through that.
4. The measured numbers of this PR as the starting point: `B`, `added`, the code versus non-code split, so PR4 and PR5 re-split by class if the re-split line was crossed.
5. The wording: "literal-name completeness over the selector closure, necessary but not sufficient"; never "index complete".
6. More hand-off facts (deepen-plan): a drain PR that declares an edge edits `scripts/lib/test-affected-paths.sh`, a runner trigger, so PR4 and PR5 are runner-changed diffs that run the full battery once; removing a declared edge is self-guarding (the file the suite names becomes a gap), so PR3 adds no redundant guard; one unreadable walk file makes its whole label `unaudited` and withholds its accept-row judgements (wider blast radius than a single library); suite rows depend on `--paths=README.md` relevance declines (a declined suite prints no row); `edge_hit` is a sixth restatement of the glob grammar next to the five the `_diff_edge_hit` comment lists, held equal by the Guard 2 differential, and the site count in that comment is updated by whichever PR next edits the selector; a PR that edits a suite to name a new code file reveals pairs against the baseline, which is the ratchet working as intended; ordinals shift when a walk file is added or removed (the canonical order bounds this to identical-anchor lines).
7. Parent floors still open for PR3 (parent rows 29, 32, 36, 37): rows printed equal `AFFECTED_SUMMARY of=`; malformed or space-prefixed rows are counted; `c.extra` lines; a fixture pinning what a registration-only diff selects.

## Rollback

The change is one commit-able unit in three files plus receipts and is independently revertible: `git revert` restores the PR1 audit. Because no baseline or ratchet exists yet, a revert has no CI consequence; after PR3 a revert of the reach would change the live gap set and is therefore a baseline event (PR3's runbook section covers it). The receipts are archived with the spec and cited by name, so a revert leaves them as history.

## Non-Goals

- Flipping `CI_PR_AFFECTED`, removing the activation lock, "PR D" (issue #10414), per-suite selection, re-running the escape replay, the saving measurement, the reader audit or the go/no-go re-ruling (each needs the budget owner's go-ahead naming the exact command; operator hold, row 12).
- The ratchet, the baseline file, the accept file and the ADR-276 amendment (PR3), the index drain (PR4, PR5), and the conditional right-boundary precision PR (not opened, 4 pairs measured against a threshold of 30).
- Editing `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, any workflow, `scripts/required-checks.txt` or the selector's row format.
- Auditing paths assembled from variables, declared-data contents, or suites the runner declines (declared limits, not defects to fix here).

## Risks and Sharp Edges

- Drain-reveal: the pats walk makes the audit result depend on `pats`, so PR4 and PR5 can reveal pairs by declaring an edge (worst case 5,526 code edges and 4,273 non-code gaps if every code gap were declared). The rule in row 5 is the control; the amendment must state it.
- The 225 existing mutation rows are text anchors into the SUT. Edits to `strip_comments`, `SOURCE_HOP` and `edge_hit` move their anchors; a row that stops landing reports `edit-failed`, and a row that lands but no longer kills must be re-aimed, not deleted. Re-anchor them in the same commit as the SUT edit.
- A fix commit is the least-audited surface (parent learning): every helper added here (resolver, closure, walk, parity function) gets mutation rows and an independent instrument, and the final verification re-runs the receipt generator rather than trusting the plan's numbers.
- The numbers in this plan (1,264 base, +992) were measured at plan time on `0aa14862af`; the rows move whenever a sibling PR registers a suite. The thresholds are relative on purpose: re-measure `B` on the PR's own tree.
- `decision-challenges.md` rows must keep the shape `Ruled by CTO agent, <date>: ` with nothing before the colon and no literal pipe inside a cell; run `technical-ruling-gate.sh --branch` before returning.
- Hyphenated module name: Python probes load `scripts/ci-pr-affected-replay.py` with `importlib.util.spec_from_file_location`; a plain `import` cannot reach it.
- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it.
