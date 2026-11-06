---
title: "watch follow-ups: scope the census allowlist, close git egress shapes, two small guards"
type: fix
date: 2026-11-02
slug: watch-census-scope-and-git-egress
branch: feat-one-shot-11439-watch-followups
issue: 11439
closes: 11439
priority: p3
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# watch follow-ups: scope the census allowlist, close git egress shapes, two small guards

`lane:` note: no `spec.md` exists for this branch, so the lane defaulted to `cross-domain` (fail-closed); the work is single-domain engineering tooling.

## Enhancement Summary

**Deepened on:** 2026-11-02
**Sections enhanced:** Research Reconciliation, Implementation Phases 1-5, Guard Contract (4 guards), Test Scenarios, Acceptance Criteria, new Observability section
**Agents used:** CTO (three rulings plus two re-rules), DHH, Kieran and code-simplicity reviewers, a sharp-edges verification pass, security-sentinel, test-design-reviewer, learnings-researcher

### Key Improvements

1. Item 4's remedy was wrong as first ruled: the trigger-2 window is anchored at the tracker's creation date and never slides, so a forged-header state does not clear by renaming or deleting the path. Message and workflow note now say so, trigger 1's hold is documented, and one follow-up issue covers a NUL-safe parser.
2. The plumbing pins are operand-level, not verb-level: `worktree add` needs `--detach`, no `-b`/`-B` and `-C "$REPO_ROOT"`; `update-ref` takes exactly `--no-deref HEAD <one word>`; exactly one `-C` operand; `-c` never feeds the directory list.
3. Test design: every new regex alternation has an isolating probe; `chk_envfail` is three registered scenarios with a `PATH`-only control; the parity row carries vacuity guards; fixture-ratchet traps (`git -C "$WT"` literals, `probe.txt` rename) are named with runnable checks.

### New Considerations Discovered

- `reset` is used by no watcher file; dropping it costs nothing.
- Eight further bypass classes sit outside the issue and the tripwire contract; ONE follow-up issue holds them (CTO option A), with `-c` config injection and `--output=` listed first.
- Process-substitution exit status is invisible here because the script runs without errexit, not because of `set -e`.

## Overview

Issue #11439 collects four low-priority follow-ups from the review of the follow-up watchers (PR #11288). All four tighten a static guard or its documentation; none changes what the watchers write to GitHub (the only write stays `gh issue comment` on each script's own tracker).

1. The static census in the first watcher's suite lets a set of local plumbing verbs through in every watcher file, although only the third watcher needs them.
2. The census misses three git egress shapes that its `gh` rules already catch.
3. The third watcher's environment scrub loop has no failure check on `env -0`.
4. A forged commit header in the tracked-path stream keeps trigger 2 at exit 3 with no operator guidance.

Binding constraints from the brief: the workflow cron line (`17 9 * * 1`) is not changed; the PR body carries the literal line `Ref #10331` with no closing keyword; `Closes #11439` appears in the PR body only, never the title; no edit to `plugins/soleur/skills/work/SKILL.md`; no stash; no gate-bypass env. Technical forks were ruled by the CTO agent on 2026-11-02 (table in `knowledge-base/project/specs/feat-one-shot-11439-watch-followups/decision-challenges.md`).

## Research Reconciliation - Spec vs. Codebase

| Issue claim | Reality (measured 2026-11-02 against the extracted census and this branch's files) | Plan response |
|---|---|---|
| `%ro` lets `update-ref`, `reset`, `read-tree`, `update-index`, `hash-object`, `worktree` pass in every watcher file | True: `git update-ref -d refs/heads/main`, `git -C "$REPO_ROOT" reset --hard`, `git worktree prune` each score 0 findings. Also: **`reset` is used by no watcher file at all**; the only users are in script 3: `gitx -C "$REPO_ROOT" worktree` (`add` or `remove`), and `gitx -C "$WT"` with `read-tree`, `hash-object`, `update-index`, `update-ref --no-deref HEAD` (lines 151, 365, 369, 371, 398, 417) | Drop `reset` from every list; scope the other five to script 3's basename and pin their operand shapes (CTO option C) |
| `\git fetch`, `g=git; $g push`, `GIT=git; "$GIT" push` pass | True, all three score 0. `\git push` is caught today only by the broad `git[[:space:]]+push` egress regex, so the backslash gap is in the perl command-position scan. **Extra shapes found, same family:** `'git' fetch`, `"git" fetch`, `G=$(command -v git)`, `git_bin=git` also score 0 | Close all of them (CTO option (i)); `command git fetch` is already caught |
| `env -0` has no failure check | True: the script runs `set -uo pipefail` with no errexit, and the exit status of `done < <(env -0)` is never observed, so a BSD `env` without `-0` leaves the numbered variables set | Seen-flag, `exit 3` before any git call or post |
| A forged header keeps trigger 2 at exit 3 "with no visible notice" | **Partly stale, and worse than the issue says:** `t2_collect` already prints `::error::the commit stream does not match the first-parent list (a tracked path named like a commit header, or history changed during the run); cannot establish trigger 2`, pinned by `chk_forged_header`. Missing: remedy guidance, the fact that trigger 1 is held too, and any workflow note. **The state is permanent while #11177 is open:** `t2_base` anchors the window at the tracker's creation date and it never slides, and `git log --no-renames --name-only` lists a renamed or deleted path again, so no path edit clears it. The sibling message `the commit stream ended before the window base ...` has a different cause and no test | Extend the mismatch message only, with the corrected remedy (re-run once; rename or delete does not clear it; trigger 1 held; exits are closing #11177 or fixing the parser) and add a `RED RUN` heading to the workflow header; file ONE follow-up issue for a NUL-safe parser (CTO re-rule 2026-11-02) |

## Research Insights

**Premise Validation.** Issue #11439 is OPEN (P3, `deferred-scope-out`, `meta/machinery`, `type/chore`), closed by no PR. The collision pre-check reported one open change naming it: PR #11862, which is this branch's own draft PR (head `feat-one-shot-11439-watch-followups`, no files yet) - not a competitor. Two `test-all.sh` processes belong to an unrelated worktree (`feat-one-shot-dependabot-medium-low-batch`) and touch none of these files. Every cited path exists on this branch. No ADR in `knowledge-base/engineering/architecture/decisions/` governs the census mechanism; the proposed mechanisms are in no rejected-alternatives table. The parent epic #10331 is closed and stays closed.

**Property List.**

- P1: a git subcommand that can change refs, the index or worktrees is permitted only in `watch-brand-hex-triggers-11177.sh`, and only in the operand shapes that script uses.
- P2: no `git` invocation outside the read-only set survives the spellings `\git`, quoted, absolute-path, or held in a variable or alias.
- P3: when the numbered `GIT_CONFIG_KEY_n`/`VALUE_n` scrub list cannot be built, script 3 exits 3 before any git call or post.
- P4: the exit-3 line for a forged header names the remedy and the workflow note, and that note exists.

**Cut List.**

- New helper script or suite for the census -> P1, P2 -> the existing census already scans every file; extend it (a new suite would also trigger the fixture-relative-assert and incident-sandbox-coverage ratchets for nothing).
- A `compgen -e` rewrite of the scrub loop -> P3 -> a seen-flag buys it in a few lines (CTO fork 3).
- Posting trigger 1 despite a trigger-2 failure -> P4 -> out of scope; the issue offers documentation or wording only (CTO fork 4).
- An extra `$var <git write verb>` perl rule -> P2 -> the assignment ban catches `g=git; $g push` at the assignment (CTO fork 2).
- The hint on the `ended before the window base` message -> P4 -> different root cause; the hint would misdirect (plan-review).
- A `CENSUS_FILES` presence floor and its RETIREMENT coupling -> P1 -> a renamed or copied 11177 script already fails closed (plan-review).

**Measured baseline (prototype of the new rules in a scratch copy of the census).** `\git fetch origin`, `'git' fetch`, `"git" fetch`, `g=git; $g push`, `GIT=git; "$GIT" push`, `G=$(command -v git)`, `git_bin=git` go 0 -> 1 finding; `echo ${GIT_UNSET[@]}`, `env "${GIT_UNSET[@]}" git "$@"`, `echo "git" push`, `printf '%s\n' 'git' status`, `echo "run git fetch later"` stay 0 (quoted `git` in data position is not command position). Known and accepted: `x="git"` (an assignment whose value is `git`) and `grep -q "git push" f` (existing broad egress regex) are flagged. The census over the real lib, three scripts and workflow stays 0 findings, and a live-tree grep for the newly banned spellings returns nothing, so no real line becomes a violation.

**Institutional learnings that change the design.**

- `2026-10-28-a-read-only-census-allowlist-widened-for-one-script-was-widened-for-all.md` (this issue's source): scope an allowlist entry to the file that needs it; treat a tool name held in a variable or escaped like the bare name.
- `2026-10-30-a-read-only-verifier-refused-the-store-its-producer-writes-and-its-census-was-a-lexer-arms-race.md`: a hand-written bash census lexer is a treadmill; state the contract in writing (tripwire for accidental, plainly spelled additions; not an adversarial-author defence) and stop chasing spellings.
- `test-failures/2026-06-29-bash-accumulate-then-exit-gate-test-three-footguns.md`: an empty or failed process-substitution source yields zero iterations silently; add a minimum-cardinality check in the same edit.
- Gap for compound after merge: no learning covers `env -0` failure checks or the control-character-plus-40-hex header forgery.

## Open Code-Review Overlap

None. Queried open `code-review` issues for each file in `## Files to Edit` and the three untouched siblings: zero matches.

## Technical rulings (CTO agent, 2026-11-02)

Full text in `knowledge-base/project/specs/feat-one-shot-11439-watch-followups/decision-challenges.md`. Summary:

- **Fork 1 - option C.** Plumbing verbs file-scoped to basename `watch-brand-hex-triggers-11177.sh`; `reset` dropped everywhere; `update-ref` only as `--no-deref HEAD <x>`; `worktree` only `add`/`remove`; the `-C "$WT"` pin on the four `-C "$WT"` verbs "kept unless brittle" - resolved at plan time as **pinned** (every real call already uses the literal form, so it is not brittle; the match tolerates `"$WT"`, `"${WT}"`, `$WT`). This also closes `gitx -C "$REPO_ROOT" update-ref --no-deref HEAD x`, which would otherwise move the main checkout's HEAD.
- **Fork 2 - option (i).** Mirror the GH rules for GIT, generic `VAR=git` assignment ban, backslash and quote tolerance, `command -v|which|type -p git`; no extra call-shape rule.
- **Fork 3 - seen-flag, exit 3**, immediately after the loop and before any git call or post.
- **Fork 4 - option II, corrected.** Workflow RED RUN note + extended `::error::` text (existing text kept as the prefix), mismatch message only. The first ruling's remedy ("wait for the path to leave the window") was withdrawn after a sharp-edges finding (the window never slides); the CTO re-ruled: say plainly that rename or delete does not clear it, that trigger 1 is held on every run, and that the exits are closing #11177 or fixing the parser; file one follow-up issue for a NUL-safe parser and cite its number; no behaviour change here.

## Plan-review disposition (2026-11-02, mechanical findings applied)

DHH, Kieran and code-simplicity panels returned 24 findings, and the sharp-edges verification pass returned 12 more (the decisive one: the forged-header state never clears, which sent fork 4 back to the CTO). Applied: drop the presence floor and its self-inflicted RETIREMENT coupling; pin `-C "$WT"` and decide it now; capture `-C` operands only and require exactly one; add `mutcopy_as` (the 11177 file copy rows need it); cut the ceremony rows (neutered-census self-test, three "own dispatch" mutation rows that `mutation_row` cannot realise, duplicate mutation rows that repeat probe rows, Guard 4 harness rows); put the pass-through and `PATH`-only shims inside `chk_envfail` itself; anchor the workflow parity check on a heading, not a bare token; drop the hint from the sibling message; correct the cleanup and `set -e` wording; add quoted-data must-PASS probes; state the default probe basename. Kept despite a cut proposal: quote tolerance (CTO-ruled); the brief's repo-global check list.

Deepen-time review (security-sentinel, test-design-reviewer) added: tighter plumbing pins (`worktree add` must carry `--detach` and no `-b`/`-B`; `update-ref` takes exactly `--no-deref HEAD <one word>`; `worktree` needs `-C "$REPO_ROOT"`); isolating probes so every new regex alternation has a probe only it can flag; `chk_envfail` split into three registered scenarios; vacuity guards on the parity row; runnable fixture-scan and diff checks in the ACs. Eight further bypass classes (wrappers, case/YAML command positions, quoted env-prefix values, for-loop strip, `printf -v`/`read`/`+=` assignments, `-c` config and `--output` through read-only verbs, quoted `gh`, dashed `git-x`) are outside the stated tripwire contract and the issue's four items; they go to ONE follow-up issue instead of another lexer round (learning 2026-10-30).

## Implementation Phases

Order follows `cq-write-failing-tests-before`: in each phase, write the failing suite rows first, then the change.

### Phase 1 - Census: scope the plumbing allowlist (item 1)

File: `scripts/watch-code-quality-reeval-9730.test.sh` (`CENSUS_PERL`, `census_scan`, `probe_census`, rows G1c/G1d/G1e, X1-X6).

0. File the census follow-up issue `#<F2>` first (so the contract comment can cite it; CTO-ruled option A, 2026-11-02): "census residual bypass classes" - listing FIRST the two that are real execution or file-write rather than spelling bypasses, `-c` config injection (`core.fsmonitor`) and `--output=` through read-only verbs (not pinned now: the existing G1e must-PASS probe `git -c core.x=1 -C "$d" show :f` encodes `-c` as allowed, so a pin would rewrite an existing contract and contradict AC8), then wrappers (`timeout`, `nice`, `command -p`, `sudo`, `xargs`), `case`-arm and YAML command positions, quoted env-prefix values (`X="a b" git ...`), the `for x in git;` strip, `printf -v`/`read`/`+=`/`g=(git)` assignments, `type -P`, `-c` config injection and `--output=` through read-only verbs, the global `git "$@"` exemption, quoted `"gh"`, dashed `git-fetch`; labels `deferred-scope-out`, `priority/p3-low`, `type/chore`, `domain/engineering`; milestone `Post-MVP / Later` (the milestone of #11439); re-evaluation criterion "a watcher edit needs one of these shapes, or a review finds a census false negative".
1. `census_scan` passes the scanned file's basename to perl as argv (`perl -e "$CENSUS_PERL" "$(basename "$f")" <<<"$text"`; the script reads `<STDIN>` explicitly, so the operand lands in `@ARGV`). Perl sets `$plumb` true only for `watch-brand-hex-triggers-11177.sh`. The workflow `.yml` and every other file get `$plumb` false.
2. In `CENSUS_PERL`: remove `worktree read-tree hash-object update-index update-ref reset` from the global `%ro`; add `%plumb` (the five, no `reset`). Capture the operand of `-C` only into a list `@cdirs` (today the loop shifts the operand for both `-C` and `-c`; `-c` takes a config pair, not a directory, so it must never feed `@cdirs`). Also record whether the call carried any `-c`, `--git-dir*` or `--work-tree*` token (`$cfg`); the current `next if $x =~ /^-/` skips those silently.
3. For a `git`/`gitx` call whose sub is in `%plumb`: allowed only if `$plumb`, `$cfg` is false, and the shape matches - `read-tree`/`hash-object`/`update-index` iff `@cdirs` holds exactly one entry matching `^"?\$\{?WT\}?"?$`; `update-ref` iff that AND the remaining words are exactly `--no-deref HEAD <one non-dash word>` (so `-d`, or a ref after `HEAD`, is flagged); `worktree` iff `@cdirs` holds exactly one entry matching `^"?\$\{?REPO_ROOT\}?"?$` AND (`add` with a `--detach` word and no `-b`/`-B` word, OR `remove --force <one word>`) - `worktree add -B main ...` would otherwise move a local branch. Anything else prints `[git-subcommand] ...`.
4. `probe_census` passes the basename `probe.sh` (never the 11177 name), so `$plumb` is false (grep for other readers of `$ROOT/probe.txt` first; the probe file name changes); add `probe_census_as NAME TEXT`, which calls `assert_fixture_dir` on its absolute `$ROOT` subdirectory, then writes the probe under its real basename there. Add `mutcopy_as NAME SRC BASENAME` (a pristine and a mutated copy of `SRC` saved under `BASENAME` in a scratch dir, with `assert_fixture_dir` as `mutcopy` does) and let `mutsubst` take a file operand with its own control and `MUT_LANDED` check, because `mutcopy` copies only the 9730 script and the lib and `mutsubst` accepts only the `script` and `lib` targets.
5. Comments: write the census contract (tripwire for accidental, plainly spelled additions; the allowlist keys on the script basename, so a renamed or copied 11177 script fails closed; not an adversarial-author defence; residual bypass classes are tracked in #<F2>). Rewrite the comment block above `CENSUS_EGRESS_RE` that lists the plumbing verbs as globally read-only, and the G1d/G1e pass messages that repeat the old list.
6. Suite rows: Test Scenarios T1, T2, T5. Probe literals and mutation strings use `gitx`, never the literal `git -C "$WT"` / `git -C "$REPO_ROOT"` forms (the fixture ratchets count those as sites); where the `git` spelling must be probed, assemble it at run time from `g=git`.

### Phase 2 - Census: close the git egress shapes (item 2)

Same file.

1. `CENSUS_EGRESS_RE`: add `\$\{?GIT([^[:alnum:]_]|$)` and `(^|[^[:alnum:]_])GIT=`; extend the `command -v|which|type -p gh` alternative to `g(h|it)`.
2. Extend `CENSUS_ASSIGN_GH_RE` to `VAR=gh` and `VAR=git` (quoted, path-prefixed); `GIT_UNSET=(`, `GIT_CONFIG_*`, `x=gitlab` must stay clean.
3. `CENSUS_PERL` command-position match: optional leading backslash and optional quotes around the tool name (prototype verified: `(?:\\?["']?(?:\S*\/)?(git|...)["']?\s+(rest))`).
4. Suite rows: T3, T4, and the Guard 2 mutation row. Before changing the regexes, run the T3 RED set (the seven shapes measured 0 -> 1: `\git fetch origin`, `'git' fetch`, `"git" fetch`, `g=git; $g push`, `GIT=git; "$GIT" push`, `G=$(command -v git)`, `git_bin=git`) against the unmodified census and confirm they fail; the regression-only probes (`/usr/bin/git fetch`, `\git push origin HEAD`, already caught today) are listed apart.

### Phase 3 - `env -0` failure check (item 3)

Files: `scripts/watch-brand-hex-triggers-11177.sh`, `scripts/watch-brand-hex-triggers-11177.test.sh`.

1. Failing row first: `chk_envfail` (below).
2. Add `_envn=0` before the scrub loop and `_envn=$((_envn + 1))` for every NUL-terminated record read (before the `case`). Immediately after the loop, before `gitx()` is defined or used, add a guard of this shape (message text: `env -0` produced no output, a non-GNU env, cannot scrub the numbered GIT_CONFIG variables from git calls):

   ```bash
   [[ "$_envn" -gt 0 ]] || { echo "::error::env -0 produced no output (a non-GNU env?); cannot scrub GIT_CONFIG_KEY_n/VALUE_n from git calls" >&2; exit 3; }
   ```

   The loop precedes mode dispatch, so `--dry-run` and `--print-state` are covered. The library's own EXIT trap (`wn_cleanup`, installed when it is sourced) removes its `WN_TMPDIR`; the script's `WORK` and worktree do not exist yet.
3. Update the header comment about the scrub: a failed `env -0` is exit 3.
4. Three registered scenarios (`scenario` helper), so a failure names its arm: `chk_envfail_a` - an `env` shim that exits 2 with `env: invalid option -- '0'` when `$1` is `-0` and otherwise `exec`s the real `env` by the absolute path resolved at suite time (shim directory guarded with `assert_fixture_dir` as `chk_gitconf` does), plus the logging `git` shim -> `RC=3`, zero posts, `::error::` naming `env -0`, **zero logged git calls**, empty `$MOCKD/tmp`; `chk_envfail_b` (instrument control) - pass-through shim on a one-commit clean repo -> `RC==0`, stdout has `examined=1`, stderr lacks `env -0 produced no output`; `chk_envfail_c` - a shim whose `-0` output is a single `PATH=...` record -> the same assertions as (b) (any-record rule).

### Phase 4 - Forged-header guidance (item 4)

Files: `scripts/watch-brand-hex-triggers-11177.sh`, `.github/workflows/code-quality-followups-watch.yml` (comments only), `scripts/watch-brand-hex-triggers-11177.test.sh`.

Re-ruled by the CTO on 2026-11-02 after a sharp-edges finding: the window is anchored at the tracker's creation date (`t2_base`) and never slides, and `git log --no-renames --name-only` lists a renamed or deleted path again, so a forged-header state **does not clear** by renaming or deleting the path; it lasts while #11177 is open and holds trigger 1 on every run.

1. File ONE follow-up issue first (the deferral this finding creates): "parse the trigger-2 log stream NUL-safely so a header-shaped tracked path cannot forge a commit header"; label `deferred-scope-out`, `priority/p3-low`, `type/chore`, `domain/engineering`; milestone from `knowledge-base/product/roadmap.md`; re-evaluation criterion "the first time this exit fires in a real run". Use its number `#<F>` below.
2. Failing rows first: extend `chk_forged_header` to require the remedy clauses (`re-run`, `does not clear`, `trigger 1`) and the pointer; add the parity row.
3. In the script define one `T2_STREAM_HINT` string and append it to the `does not match the first-parent list` message only, keeping the present text as the prefix: re-run once to rule out a history change during the run; if it fails identically a commit in the window touches a path named like a commit header, renaming or deleting that path does not clear it, trigger 1 is held on every run, and the only exits are closing #11177 or fixing the parser (#<F>); see `RED RUN` in `code-quality-followups-watch.yml`.
4. Workflow header: add a `# RED RUN:` paragraph after `RESIDUAL RISK` with the same content (symptom: red run and the `::error::the commit stream ...` line; how to tell a transient history change from the permanent case: re-run once; the permanent case does not clear by rename or delete; trigger 1 is held; never edit a sentinel; follow-up #<F>). Add one RETIREMENT line: when the 11177 script is deleted, also delete the census `%plumb` allowlist, the `probe_census_as` rows and the 11177 mutation copies in `watch-code-quality-reeval-9730.test.sh`; if the replay ratchet forces an accept-row change, update the "(6 for 10515, 5 for 11177)" counts in the same edit. **Do not touch the `cron:` line or any non-comment line.**
5. Parity row: require exactly one `T2_STREAM_HINT=` definition in the SUT; extract the pointer token by `sed` and require it non-empty and matching `^[A-Z ]+$` before use (an empty token would make `grep -F` match everything); the row FAILS (never skips) when the workflow file is absent; define the paragraph as the `# RED RUN:` line through the next bare `#` line and require the clauses `trigger 1` and `does not clear` inside it, so gutting the body while keeping the heading goes RED; require stderr of `chk_forged_header` to match `#[0-9]{4,}` (an unreplaced `#<F>` placeholder fails). Add a pin that the sibling `ended before the window base` text is unchanged, and build the gutted-workflow copy with `sed` and a parity function that takes the workflow path as an argument (the 11177 suite has no `wf_mut`-style helper).

### Phase 5 - Verification and PR hygiene

0. After writing the RED rows, run `bash plugins/soleur/test/fixture-relative-assert.test.sh` and `python3 plugins/soleur/test/lib/fixture-scan.py --rule relative scripts/watch-code-quality-reeval-9730.test.sh scripts/watch-brand-hex-triggers-11177.test.sh` (and the same with `--rule operand`); both scans must print `SITES=0`. A literal `git -C "$WT"` or `git -C "$REPO_ROOT"` anywhere in either suite is a site; use `gitx` or assemble at run time. `probe_census_as` and `mutcopy_as` call `assert_fixture_dir` before `mkdir -p` and before the redirect that writes the file, as `mutcopy` does.
1. Run `bash scripts/watch-code-quality-reeval-9730.test.sh`, `bash scripts/watch-brand-hex-triggers-11177.test.sh`, `bash scripts/watch-lint-ratchet-reeval-10515.test.sh` (shares the lib; unchanged), `bash -n` on each edited script, and `python3 scripts/lint-guard-contract.py`.
2. Run the repo-global checks named in the brief before every push: `scripts/check-adr-ordinals.sh`; `plugins/soleur/test/boundary-prefix.test.sh`; `python3 -I scripts/ci-pr-affected-replay.py ratchet`; `bash .claude/hooks/grep-q-pipe-guard.test.sh`; `scripts/guard-vacuity-floor.test.sh`; `plugins/soleur/skills/verification-scaffold/test/manifest.test.sh`; and the two ratchets a file-selected battery cannot see, `bash plugins/soleur/test/fixture-relative-assert.test.sh` and `bash .claude/hooks/incident-sandbox-coverage.test.sh` (no new suite is added; the 11177 suite already sources `.claude/hooks/lib/test-incident-sandbox.sh`; new rows must use absolute `$ROOT`/`$MOCKD` paths).
3. If the replay ratchet reports a stale or missing `scripts/ci-pr-affected-audit.accept.tsv` row for an edited suite, repair it by the file's documented procedure; never bypass a gate.
4. PR body (via `--body-file`; `soleur:ship` rewrites it, so re-verify with AC10 after its last edit): `Closes #11439`, the literal line `Ref #10331` (no closing keyword), `Ref #9730`, `Ref #10515`, `Ref #11177`, the Decision Classes table, and `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. The title carries no closing keyword.

## Files to Edit

- `scripts/watch-code-quality-reeval-9730.test.sh` - census scoping, egress shapes, helpers, new rows (Phases 1-2).
- `scripts/watch-brand-hex-triggers-11177.sh` - `env -0` seen-flag, `T2_STREAM_HINT`, header comments (Phases 3-4).
- `scripts/watch-brand-hex-triggers-11177.test.sh` - `chk_envfail`, extended `chk_forged_header`, parity row, mutation rows (Phases 3-4).
- `.github/workflows/code-quality-followups-watch.yml` - comment-only: `RED RUN` note, RETIREMENT line (Phase 4). Every non-comment line, including the cron line, stays byte-identical.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-11439-watch-followups/decision-challenges.md` (written)
- `knowledge-base/project/specs/feat-one-shot-11439-watch-followups/tasks.md`

No new script, suite or workflow, so no `scripts/test-all.sh`, `suite-durations.tsv` or `suite-shard-legs.tsv` edit is expected (the repo-global checks confirm).

## Guard Contract

### Guard 1 - Census plumbing allowlist is file-scoped and operand-pinned

**Property.** A git subcommand that can change refs, the index or worktrees is permitted only in `watch-brand-hex-triggers-11177.sh`, and only in the operand shapes that script uses.

**Assembly.** One chokepoint: the `git`/`gitx` branch of `CENSUS_PERL`, reached per file from `census_scan`. The population is every file `G1c` hands it (the lib, the 9730 script, every `watch-*-reeval-*.sh` and `watch-*-triggers-*.sh` matched by glob at run time, the workflow), not a list of today's members. The verb set is "everything outside the read-only `%ro`", so a verb the issue never named (`branch -D`, `gc`, `prune`) is covered by default. The scope key is the basename, so a renamed or copied 11177 script fails closed; no presence floor is needed. Spellings reaching the branch: `git`, `gitx`, `-C` prefixes (exactly one `-C` operand is allowed on a pinned verb), `env`/`command`/`exec` prefixes, absolute path.

**Mutation matrix.** Controls first: every control scores 0 before its mutation is applied.

| # | Edit (scratch copy) | Must go RED |
|---|---|---|
| 1 | Copy of the real 11177 script (real basename): keep every compliant call and **append**, anchored at the unique `wn_preflight` line, `gitx -C "$WT" update-ref -d refs/heads/main` (second member after compliant ones; also proves the scan reaches the file under its basename) | the finding text `[git-subcommand] gitx -C "$WT" update-ref` appears in the census output |
| 2 | The unmodified 11177 text saved under another basename via `mutcopy_as` with no substitution (proves the scope key is honoured; landed = basename differs and content is `cmp`-equal; control under the real basename = 0) | census >= 1 |
| 3 | In a copy of the 11177 script, one mutation per line: `worktree add -q --no-checkout --detach` -> `worktree add -B main` (drop `--detach`); `update-ref --no-deref HEAD "$parent"` -> `update-ref --no-deref HEAD -d`; `-C "$WT" read-tree` -> `-C "$REPO_ROOT" read-tree` (all mutation text uses `gitx`, never the literal `git -C` form) | three distinct finding texts, one per mutated line |

Rows with a census-wide effect on other files (`git update-ref -d refs/heads/main` in the 9730 script, `git worktree prune` in the lib, `git reset --hard` in the 10515 script) are not file-copy rows: they are the T1 probe rows run under those basenames.

**Harness rows.** (H1) The T1/T3 probe rows are the dispatch proof: a census that returns 0 for everything reds at least 20 rows. (H2) Must-PASS non-canonical inputs under the 11177 basename that differ from the canonical text: the `git` spelling of a pinned call (assembled at run time from `g=git`), `gitx -C "${WT}" update-ref --no-deref HEAD abc123`, `gitx -C "$REPO_ROOT" worktree remove --force "$WT"`, all 0. Must-FAIL, one isolated cause each: `gitx -C "$WT" -C "$WT" read-tree HEAD` (the `-C` count only), `gitx -C "$WT" -c core.x=1 read-tree HEAD` (`$cfg` only), `gitx -C "$WT" --git-dir=/x read-tree HEAD`, `gitx -C "$WT" update-ref -d refs/heads/main` (operand shape only), `gitx -C "$WT" update-ref --no-deref HEAD refs/heads/main x` (trailing words), `gitx -C "$WT" worktree prune`, `gitx -C "$REPO_ROOT" worktree add -B main p HEAD` (`-B`), `gitx -C "$REPO_ROOT" worktree add -q p HEAD` (no `--detach`), `gitx -C "$WT" worktree add --detach p HEAD` (wrong `-C`) - one forbidden row per tightened pin.

**Anchor.** No stored hash, manifest or count is compared; nothing to weaken by a single diff.

### Guard 2 - Census flags git egress under every covered spelling

**Property.** No `git` invocation outside the read-only (and scoped plumbing) set survives in a covered file under the spellings bare, backslash-escaped, quoted, absolute-path, or reached through a variable or alias.

**Assembly.** Three scanners inside `census_scan`, each with its own blind spot: `CENSUS_EGRESS_RE` (greps the stripped text), the `VAR=tool` assignment regex, and the perl command-position scan. The property is the union, so every spelling below is probed (table-driven, T3) and a shape caught by only one scanner (as `\git push` is today) is recorded. The set is "tools the census polices x spellings", not the three shapes named in the issue.

**Mutation matrix.**

| # | Edit | Must go RED |
|---|---|---|
| 1 | Add `\git fetch origin` to a copy of the 9730 script | census >= 1 |
| 2 | Add `g=git` and `$g push` | census >= 1 |
| 3 | Add `GIT=git` then `"$GIT" push` on a line of its own after the compliant `gitx` lines of a copy of the 9730 script (second member after compliant ones) | the finding text for that line appears |
| 4 | Add `'git' fetch`, `"git" fetch`, `G=$(command -v git)`, `which git`, `type -p git` | one finding per line |

Rows 1, 2 and 4 are realised as table-driven probe rows in T3 (same text, same scorer, no file copy); row 3 is a `mutcopy` row because the file context is the point. The three regex surfaces overlap (`GIT=git; "$GIT" push` trips three of them), so T3 also carries **isolating probes**, each flagged by exactly one new clause: `GIT=$(pick_tool)` (only the `GIT=` alternation), `echo hi; "$GIT" fetch` (only the `$GIT` use alternation; `fetch` is not a gh verb) and `type -p git` (only the widened `command -v|which|type -p` alternative).

**Harness rows.** (H1) as Guard 1: the probe rows are the dispatch proof. (H2) Must-PASS non-canonical: `echo ${GIT_UNSET[@]}`, `env "${GIT_UNSET[@]}" git "$@"`, `GIT_UNSET=(-u X)`, `x=gitlab`, `legit_ok=1`, `git -C "$d" log --first-parent`, and quoted data: `echo "git" push`, `printf '%s\n' 'git' status`, `echo "run git fetch later"`. Accepted false positives, stated in the suite: `x="git"` and `grep -q "git push" f`.

**Anchor.** None stored. Residual stated in the suite: dynamic construction (`g=$(echo gi)t`, `eval`) is outside the census contract.

### Guard 3 - A failed `env -0` stops script 3 before any git call or post

**Property.** If the numbered `GIT_CONFIG_KEY_n`/`VALUE_n` scrub list cannot be built, script 3 exits 3 before the first git call and before any comment.

**Assembly.** One loop at the top of the script, ahead of mode dispatch, so `--dry-run` and `--print-state` pass through the same site; consumers of its result are `gitx` and the gate child's `GATE_PASS`, both built in that loop. The property is about ORDER (check before first use), so the matrix needs a REORDER row.

**Mutation matrix.** Realised with `mutation_row` (`sut OLD NEW` triples; the `wn_preflight` line is a unique anchor (the `wn_preflight` line)).

| # | Edit | Must go RED |
|---|---|---|
| 1 | Delete the `[[ "$_envn" -gt 0 ]]` exit | `chk_envfail_a` no longer sees `RC=3` |
| 2 | **Reorder:** delete the check and re-insert it immediately before the `wn_preflight` line (after `REPO_ROOT=$(gitx rev-parse ...)`) | `chk_envfail_a` sees a logged git call |
| 3 | Count only records matched by a `case` arm instead of every record | `chk_envfail_b` (the real env has no matching records, so the script exits 3) |
| 3b | `-gt 0` -> `-gt 1` (needs two records) | `chk_envfail_c` (a single `PATH=` record now exits 3); only (c) kills it |

**Harness rows.** `chk_envfail_b` (pass-through shim, asserts `RC==0` and `examined=1`, not merely "not 3") is the instrument control and the rejects-everything guard; `chk_envfail_c` (single `PATH=` record) is the must-PASS that differs from the canonical failing input. The existing scenarios, which all run with the real `env`, double as must-PASS controls.

**Anchor.** None stored; accepted gap per the ruling: partial output followed by failure is not detected.

### Guard 4 - The forged-header exit-3 line carries the corrected remedy and points at a note that exists

**Property.** The `does not match the first-parent list` line carries the remedy wording (re-run once; does not clear by rename or delete; trigger 1 held; follow-up number) and a pointer, and the pointed-to `# RED RUN:` paragraph exists in the workflow header with the same clauses.

**Assembly.** One error site in `t2_collect` (the sibling `ended before the window base` site has a different cause and is deliberately excluded), one `T2_STREAM_HINT`, and the workflow header comment. The parity row reads the token from the SUT, so it follows the script rather than a literal copied into the suite.

**Mutation matrix.**

| # | Edit | Must go RED |
|---|---|---|
| 1 | Remove `${T2_STREAM_HINT}` from the mismatch site (`mutation_row`) | extended `chk_forged_header` |
| 2 | Copy of the workflow with the `# RED RUN:` heading removed (or the SUT token changed to disagree with it) | the parity row |
| 3 | Copy of the workflow that keeps the `# RED RUN:` heading but guts the paragraph body (no `trigger 1`, no `does not clear`) | the parity row |
| 4 | Append the hint to the sibling `ended before the window base` message (it must stay unchanged) | the sibling-unchanged pin |

**Harness rows.** `chk_gitconf` (an existing clean run that exits 0) additionally asserts the hint is absent from stderr (`! grep`), so the hint is only on the failure arm. The parity row's vacuity guards (single definition, non-empty `^[A-Z ]+$` token, FAIL when the workflow file is absent, `#[0-9]{4,}` follow-up number) are part of the row.

**Anchor.** Documentation parity only: one diff can edit both the SUT token and the workflow note, so this proves consistency, not integrity; enough for a documentation pointer. The cron line is separately pinned by the existing workflow-facet witness in the 11177 suite.

## Test Scenarios

- T1 (G1d, new forbidden): `git update-ref -d refs/heads/main`, `git update-ref refs/heads/x HEAD`, `git worktree prune`, `git reset --hard`, `gitx -C "$REPO_ROOT" reset --hard` under the default probe basename; the five plumbing verbs under the 9730 and lib basenames; under the 11177 basename the Guard 1 H2 must-FAIL list (each with one isolated cause). The literal `git -C "$REPO_ROOT"` form is never used (the fixture ratchets count it as a site and pin the baseline by equality).
- T2 (G1e, rewritten must-PASS): the plumbing probes move to `probe_census_as watch-brand-hex-triggers-11177.sh` with the exact operand shapes (Guard 1 H2 must-PASS); `reset --mixed` leaves this row by design and is a T1 forbidden row now. No other G1e probe changes.
- T3 (G1d, new egress, table-driven): RED set `\git fetch origin`, `'git' fetch`, `"git" fetch`, `g=git; $g push`, `GIT=git; "$GIT" push`, `G=$(command -v git)`, `git_bin=git`; isolating probes `GIT=$(pick_tool)`, `echo hi; "$GIT" fetch`, `type -p git`; regression-only `\git push origin HEAD`, `/usr/bin/git fetch`, `${GIT:-git} push`, `which git`.
- T4 (G1e, new must-PASS): the Guard 2 H2 list.
- T5: `mutcopy`/`mutcopy_as` rows for Guard 1 rows 1, 2, 3 (X7, X8, X9) and Guard 2 row 3 (X10), each with a control that scores 0 first; X8 proves landing by basename inequality plus content equality (`mutcopy_as` sets `MUT_LANDED=1` for a rename-only row), the others by `cmp`.
- T6: `chk_envfail_a`, `chk_envfail_b`, `chk_envfail_c` and Guard 3 mutation rows 1, 2, 3, 3b (11177 suite, `mutation_row` with `sut` triples).
- T7: extended `chk_forged_header`, the parity row (with its vacuity guards), the sibling-unchanged pin, the `chk_gitconf` absence assertion and Guard 4 mutation rows 1-4 (11177 suite).
- Regression: the full existing 9730, 10515 and 11177 suites stay green; the only existing assertions rewritten are the G1e plumbing probes named in T2.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Census allowlist is global. ... Fix: scope those verbs to script 3's path, or require `-C \"$WT\"`." [issue #11439 item 1] | Phase 1, Guard 1, AC1-AC2 | mapped |
| 2 | "Three git egress shapes pass the census: `\git fetch origin`, `g=git; $g push`, `GIT=git; \"$GIT\" push`. ... Fix: mirror the `${GH}` / `GH=` rules for `GIT` and accept a leading backslash." [issue #11439 item 2] | Phase 2, Guard 2, AC3 | mapped |
| 3 | "`env -0` has no failure check in the `GIT_CONFIG_KEY_*` scrub loop of script 3. ... Fix: check that `env -0` produced output." [issue #11439 item 3] | Phase 3, Guard 3, AC4 | mapped |
| 4 | "A forged header keeps trigger 2 at exit 3. ... Fix: add a line to the workflow's RETIREMENT / red-run notes, or name the cause in the failure message." [issue #11439 item 4] | Phase 4, Guard 4, AC5-AC6 | mapped |
| 5 | "Do not change the workflow cron line." [brief] | AC6, Non-Goals | mapped |
| 6 | "PR body must contain the literal line `Ref #10331` ... NO closing keyword ... `Closes #11439` in the PR body, never the title." [brief] | Phase 5 step 4, AC10 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/watch-code-quality-reeval-9730.test.sh` edit (Phases 1-2) | "scope those verbs to script 3's path" / "mirror the `${GH}` / `GH=` rules for `GIT`" | asked (asks 1-2) |
| `scripts/watch-brand-hex-triggers-11177.sh` edit (Phases 3-4) | "check that `env -0` produced output" / "name the cause in the failure message" | asked (asks 3-4) |
| `scripts/watch-brand-hex-triggers-11177.test.sh` edit | - | inferred - justification: the guards the issue asks for are untested without suite rows (`cq-write-failing-tests-before`) |
| `.github/workflows/code-quality-followups-watch.yml` comment edit | "add a line to the workflow's RETIREMENT / red-run notes" | asked (ask 4) |
| `reset` dropped from every list | "lets `update-ref`, `reset`, `read-tree`, ... pass in every watcher file" | asked (ask 1; no watcher uses it) |
| `update-ref`/`worktree`/`-C "$WT"` operand pins | "or require `-C \"$WT\"`" | asked (ask 1; CTO option C: `-C "$WT"` alone does not protect shared refs, so the `update-ref` shape is pinned too) |
| Quote tolerance (`'git'`, `"git"`) and `command -v git`, `which git`, `type -p git` | "mirror the `${GH}` / `GH=` rules for `GIT`" | asked for `command -v` (the GH rule set contains it); quote tolerance is inferred - justification: same bypass family, one regex alternation, ruled in by the CTO (fork 2) |
| `mutcopy_as` helper and `probe_census_as` | - | inferred - justification: the scoped rows cannot be tested without a probe or copy that carries the 11177 basename |
| RETIREMENT line about the basename-keyed allowlist | - | inferred - justification: the scoped allowlist rots silently if the 11177 script is deleted or renamed and no note says so |
| Follow-up issue for the NUL-safe parser | - | inferred - justification: the corrected remedy for item 4 is "no operator-side exit", and a documented deferral without a tracking issue is invisible (plan Step 6 deferral check); CTO re-ruled 2026-11-02 |
| `decision-challenges.md`, `tasks.md` | "Persist every decision as a row of the `| Item | Class | Ruling |` table" [brief] | asked |

### Split Assessment

- Subsystems touched: 2 - `scripts/`, `.github/workflows/` (comment-only), plus plan/spec artifacts under `knowledge-base/`
- Planned files: 4 edits (+2 artifacts) | Estimated changed lines: ~250 (mostly suite rows)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: `git update-ref -d refs/heads/main`, `git worktree prune` and `git reset --hard` each score >= 1 census finding when scanned under the default probe name, the 9730 script's name and the lib's name; `bash scripts/watch-code-quality-reeval-9730.test.sh` is green with these rows.
- [ ] AC2: the real `scripts/watch-brand-hex-triggers-11177.sh` still scores 0 census findings; the same text under another basename scores >= 1; `gitx -C "$REPO_ROOT" update-ref --no-deref HEAD x` under the 11177 name scores >= 1 (Guard 1 matrix 1-3).
- [ ] AC3: `\git fetch origin`, `g=git; $g push`, `GIT=git; "$GIT" push`, `'git' fetch`, `"git" fetch`, `G=$(command -v git)` each score >= 1; the Guard 2 H2 list scores 0.
- [ ] AC4: with an `env` shim that rejects `-0`, script 3 exits 3, prints a `::error::` naming `env -0`, posts nothing, makes zero git calls and leaves `$MOCKD/tmp` empty; with a pass-through shim and with a `PATH`-only shim it does not exit 3 (`bash scripts/watch-brand-hex-triggers-11177.test.sh` green).
- [ ] AC5: the `does not match the first-parent list` line still begins with its present text and now carries the remedy wording and the `RED RUN` pointer; the workflow header contains a `# RED RUN:` heading; the parity row passes; the sibling `ended before the window base` line is unchanged.
- [ ] AC6: `git diff -U0 origin/main...HEAD -- .github/workflows/code-quality-followups-watch.yml | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[+-][[:space:]]*#'` prints nothing (merge-base form, stable when main moves; comments only); `grep -n "cron: '17 9 \* \* 1'" .github/workflows/code-quality-followups-watch.yml` still matches once; the existing workflow-facet witness in the 11177 suite is green.
- [ ] AC7: every Guard Contract mutation row has a passing unmutated control and a landed mutation (`MUT_LANDED` / `cmp` proof; a rename-only row proves landing by basename inequality plus content equality); count thresholds are backed by the specific finding text where the matrix names it.
- [ ] AC8: the only existing assertions rewritten are the G1e plumbing probes listed in T2 (re-expressed through `probe_census_as`, with `reset --mixed` moved to a forbidden row); every other assertion in the three suites is byte-identical; `python3 scripts/lint-guard-contract.py` passes on this plan.
- [ ] AC9: the six repo-global checks in the brief plus `bash plugins/soleur/test/fixture-relative-assert.test.sh` and `bash .claude/hooks/incident-sandbox-coverage.test.sh` pass on the final tree before the push (and `fixture-relative-assert` is run right after the RED rows are written).
- [ ] AC11: two follow-up issues exist (labels `deferred-scope-out`, `priority/p3-low`, `type/chore`, `domain/engineering`; milestone `Post-MVP / Later`; re-evaluation criterion stated): `#<F>` for the NUL-safe trigger-2 log parser, whose number appears in `T2_STREAM_HINT` and in the workflow `RED RUN` paragraph, and `#<F2>` for the census residual bypass classes, whose number appears in the suite's contract comment.
- [ ] AC12: `python3 plugins/soleur/test/lib/fixture-scan.py --rule relative` and `--rule operand` over the two edited suites print `SITES=0`.
- [ ] AC10: after `soleur:ship`'s last PR-body edit, `gh pr view <N> --json body,title,closingIssuesReferences` shows `closingIssuesReferences` equal to `[11439]`, a body line `Ref #10331` with no closing keyword, the Decision Classes table and the Claude Code attribution line, and no closing keyword in the title (ship authors the body, so the requirement is also recorded in `decision-challenges.md` where ship reads it).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing - the change is to static guards and comments on weekly notify-only watchers; the worst case is a red CI run on the suites or a missed or duplicated tracker comment on #9730, #10515 or #11177.
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure vector - no credential, token or user data is read or written; fixtures are synthesized and the watchers hold only the default `github.token` with `issues: write` on their own tracker.
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** `none` because the diff only narrows what a test census accepts and adds an exit-3 failure arm to a script that already fails closed; it adds no write capability.

`threshold: none, reason: the touched files are repo-internal watcher scripts, their suites and a workflow comment block; no user data, auth, payment or regulated-data path is involved.`

## Observability

Added at deepen time: the plan skill's Phase 2.9 trigger list omits repo-root `scripts/`, but deepen-plan Phase 4.7 gates every non-docs plan, so the section is declared rather than skipped.

```yaml
liveness_signal:
  what: the weekly scheduled run of code-quality-followups-watch.yml (three jobs) and its exit code
  cadence: weekly, Mondays 09:17 UTC (unchanged)
  alert_target: GitHub Actions failure email to the account that last edited the cron line; no dead-man alarm by design (documented RESIDUAL RISK in the workflow header)
  configured_in: .github/workflows/code-quality-followups-watch.yml
error_reporting:
  destination: Actions run annotations (::error:: lines) on the triggers-11177 job
  fail_loud: yes - exit 3 turns the run red; this change adds two named exit-3 causes (env -0 produced no output; forged commit header, now with remedy wording)
failure_modes:
  - mode: numbered GIT_CONFIG variables cannot be scrubbed because env lacks -0
    detection: "::error::env -0 produced no output" then exit 3 before any git call or post (suite chk_envfail)
    alert_route: red Actions run, the same route as every other exit 3
  - mode: a header-shaped tracked path in the trigger-2 window
    detection: "::error::the commit stream does not match the first-parent list ... re-run once ... does not clear" and the # RED RUN paragraph in the workflow header
    alert_route: red Actions run on every weekly run until #11177 closes or the parser follow-up lands
  - mode: a census regression (a write verb or egress shape slips into a watcher file)
    detection: the 9730 suite census rows (G1c/G1d/G1e and mutation rows) fail in CI
    alert_route: CI red on the PR that introduces it
logs:
  where: GitHub Actions run logs for the workflow; suite output in the CI shard logs
  retention: GitHub default (90 days)
discoverability_test:
  command: grep -n "^# RED RUN:" .github/workflows/code-quality-followups-watch.yml
  expected_output: RED RUN
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - infrastructure/tooling change confined to CI watcher scripts, their tests and a workflow comment. The UI-surface override found no matching path. Observability gate: declared in `## Observability` above (the operator-visible signal is the existing `::error::` line on a red Actions run, now with remedy wording). Architecture gate: no ADR/C4 impact. Encryption gate: no store or connection added. GDPR gate: no regulated-data surface. The named devex lens (`soleur:engineering:cto`) already ruled every fork, so it is not re-spawned as a reviewer.

## Risks and Sharp Edges

- The census is a tripwire for accidental, plainly spelled additions, not an adversarial-author defence (CTO fork 2; learning 2026-10-30). The contract sentence goes in the suite so the next reviewer does not start another lexer round.
- The scope key is a basename: a renamed or copied 11177 script fails closed. Recorded next to the allowlist and in the workflow RETIREMENT block.
- The `-C "$WT"` pin matches the real text today; a future edit that renames `WT` reds the census, which is the intended direction (fail closed, reviewer adjusts).
- Edits to the 11177 and 9730 suites can change the replay ratchet's pairs (`scripts/ci-pr-affected-audit.accept.tsv`, keyed by suite, path, anchor, ordinal). New rows must not name real repo paths; run the ratchet before pushing.
- Load-sensitive timing: the 11177 suite runs gates under `timeout`; run the suites in a quiet shell and size any new timeout for a loaded host.
- A forged-header state is permanent while #11177 is open and holds trigger 1 on every run; this PR documents it and files the parser follow-up, it does not fix it (CTO re-rule). Closing #11177 (or the parser fix) is the only exit.
- The `ended before the window base` line stays untested (pre-existing); it is not touched.
- A plan whose `## User-Brand Impact` is empty, `TBD`, or omits the threshold fails `deepen-plan` Phase 4.6 - this one is filled.

## Non-Goals

- No change to what the watchers post, to sentinel formats, or to any `gh` call set.
- No change to the cron schedule or any non-comment workflow line.
- No behaviour change to trigger ordering (CTO fork 4, option III rejected).
- No census lexer rewrite; no coverage of dynamic construction (`eval`, `$(echo gi)t`) or of `--git-dir=`/`--work-tree=` forms.
