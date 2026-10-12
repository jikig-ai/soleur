---
title: "chore: grep -q pipe-guard series, slice S7c (derivation recall)"
date: 2026-10-12
slug: grep-q-wave-b-s7c-derivation-recall
branch: feat-one-shot-grep-q-pipe-guard-s7c-derivation-recall
issue: 9217
type: chore
lane: single-domain
---

## Enhancement Summary

**Deepened on:** 2026-10-12. **Method:** the plan-time J0 (a committed port of the guard's derivation that reproduces its 66 pairs and 120 triples before measuring any arm), a learnings sweep, a scoped advisor consult, a four-seat plan-review panel (DHH, correctness, simplicity, devex), the deepen-plan mechanical halts (user-brand, observability, PAT, UI, encryption, Guard Contract lint, Scope Check) and live verification of every cited issue, PR, commit, rule id, learning path and plan-quoted number; the all-agent fan-out was not run because every mechanism had already been read against the real guard and its fixtures by the review seats and by the plan-time measurements below.

- Measured, not asserted: U1 (the brief's list without the any-producer arm) is +57 pairs in 48 test files; with the any-producer arm (quote parity and a case-pattern exclusion included) +90 pairs in 66.
- J0 found a defect the brief did not list: a stub written `> "$d/jq"; chmod` is recorded as `jq";` and never matches (7 pairs).
- The late #10074 findings were re-measured at the merged head: the window crossing (verb, heredoc, brace) and every unneutered verdict are open; one fail-open spelling is already fixed; the annotation finding is real for a pipe after the annotation string (a first grep read 0, a wider scan found 29 lines, 1 new triple).
- Review changes applied: R1 is a logical-line join (the any-bar scan belongs to R3), the drain-window bound is restricted to function, helper and heredoc openers (a logging write must not bound it), the exact-status row for the dynamic control is dropped (unkillable where CI inherits an ignored SIGPIPE), the fixture suite is one case table with one probe check, and the Guard Contract matrix grew must-not rows (quoted bar, case alternation, block scalar, `command -v`, unsourced library).
- Open taste and user-challenge items are recorded in `decision-challenges.md` (items 1 to 18); the any-producer arm is kept last and cuttable against four signals to drop it.

## Overview

Slice S7c of the grep -q pipe-guard series (tracker #9217; also #7376, #6601, #7797, #9482). S1 to S6, S7a and S7b are merged and verified (S7b merge `0aae3f8680`, evidence comment `issuecomment-6117916154` on #9217, dissents ledger #10074). S7b put the producer side of the pipe under a join: every (test file, verb) pair where a test names a non-test file that pipes `printf|echo|cat` into a verb the test stubs has a `PRODUCER_JOIN` row, and the rows that matter pin a stdin drain in the stub. Its own evidence records what the derivation cannot see, as a NOT-fixed list. This slice is that list.

The lane note: this branch has no `spec.md` (the one-shot path creates none), so the lane is the plan's own call after the domain sweep found no domain relevant; it follows the S7b plan.

This PR (S7c) delivers five things, each owned by one Guard Contract entry or one phase:

1. J0, the measurement, as the first phase and the first commit: a committed, re-runnable derivation (`j0-derive.py` in the spec dir, already written and run at plan time) that reproduces the guard's own 66 pairs and 120 triples and then relaxes ONE rule per arm, so each arm's increment is attributable. No stub is edited and no row is added before the numbers and a reach classification of every new pair are recorded in `evidence.md`.
2. Derivation arms in the guard's one awk program, in commit order: the stub-name defect J0 found (R7), split lines (R1), wrapped verbs (R2), the annotation strip bounded at its string (R8), libraries sourced by a `pipefail` file (R4), helper-with-argument and loop-built stubs (R5), `.tf`-family producers (R6), and any producer before a bar (R3, last and cuttable at ship time). A derivation fixture suite inside the guard drives every arm with a must-derive and a must-not-derive case (Guard 1); it is one case table (name, expected, producer text, suite text) run through the real derive function by one loop that appends to `sweep_probe_fail` once, so a new case is one table line and `SWEEP_PROBE_CHECKS` moves by one.
3. The detector findings of the late #10074 report, each re-measured at the merged head first: the drain window bounded at the next stub of ANY verb, a heredoc terminator or a closing brace; the fail-open spellings; three cheap false rejects (Guard 2).
4. A negative control for every verdict the join block prints and a pin on the merge assignment, so a neutered verdict turns the guard red (Guard 3).
5. The new rows, the stub edits J0 shows are needed, the recomputed pins, the guard header rewritten to the S7c state, and the evidence.

## Research Insights

**Sources read.** The S7b plan, its `evidence.md`, `decision-challenges.md`, `tasks.md`, `session-state.md` and `j0-derive.py` (archived under `knowledge-base/project/specs/archive/20261012-033826-feat-one-shot-grep-q-pipe-guard-s7b-producer-join/`), the S7b learning (`2026-10-12-a-text-pipe-derivation-read-an-annotation-echo-as-a-pipe-and-a-stub-drain-called-a-binary-its-sandbox-lacked.md`), the tracker comments for S6, S7a and S7b, the #10074 ledger with its late report, and the whole join block of the guard (`.claude/hooks/grep-q-pipe-guard.test.sh`, 1627 lines at `0aae3f8680`: the header, `PJ_AWK`, `pj_defs`, `pj_judge`, the row loop, the controls and the dynamic control). A learnings sweep (12 files; see the Learnings list below) and the repo itself supplied the rest.

**Premise validation (Phase 0.6).** Checked against `origin/main` at `0aae3f8680` (this branch's base) on 2026-10-12:

- #9217, #7376, #6601, #7797, #9482, #10074, #9971, #9950, #9638 and #9639 are open; PR #9745 (cursor harness, the line-102 pipe) is open; draft PR #10085 is this branch's. Nothing cited is stale except the next item.
- **#9956 is CLOSED** (closed 2026-10-11T22:00:50Z by PR #10053; the guard's two rows `cloud-init-inngest-bootstrap.test.sh | docker` and `| timeout` still read `blocked-#9956 suite red at origin/main`). The brief says the suite is red at base and must be left alone. A look at `Infra Validation` runs on main finds `deploy-script-tests` shards 1 to 4 green on every run since `47c38a19da` (2026-10-11 15:33 UTC) in which the job ran (the runs for `ba4cbd3911` and `0aae3f8680` skipped it as tests-only). Run in the local isolated sandbox the suite is red for an environmental reason (no git tags in the copy: `GuardA2: vector_sha256 identical at vinngest-v1.1.50 ... tag=''`). So the premise "red at origin/main" is not supported by CI; the instruction "leave it alone" still binds. Phase 0 reclassifies the two pairs in a real clone with tags, the rows keep a truthful reason, and the file is not edited whatever the classification says (recorded as decision-challenges item 6).
- The brief's "about 24 pairs" for split lines measures 29 under this plan's rule; "16 pairs when forced on" for a library pipe with no pipefail token measures 18 under the forced-on reading and 10 under the reading this plan adopts (below).
- No ADR in `knowledge-base/engineering/architecture/decisions/` decides a stub-drain or pipe-derivation mechanism (S7b grepped the same terms; unchanged). The guard's only recorded architecture is its own header.
- Open `code-review` issues touching any candidate file: one hit, #7098, which names `git-data-rung2-rehearsal.test.sh` as a precedent for an unrelated lint (see Open Code-Review Overlap).
- The host has `gawk` only (no `mawk`), while CI's default awk may be `mawk`: the guard's awk is written mawk-safe and is verified for mawk only by CI. Recorded, not claimed.

**J0 at plan time** (the command is `ulimit -v 6000000; python3 -I knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-s7c-derivation-recall/j0-derive.py`; full output in `j0-plan-time-output.txt` beside it, deterministic across two runs; about 20 s wall). The port reproduces the guard before it relaxes anything: BASE reads 66 pairs and 120 producer triples, the numbers the guard prints at `0aae3f8680`.

| Arm | Rule relaxed | New pairs | New triples | Test files |
| --- | --- | --- | --- | --- |
| R1 | a logical line joined over a trailing backslash or a trailing single pipe (not a YAML block-scalar indicator, not a bar inside quotes) | 29 | 42 | 27 |
| R2 | the verb behind `timeout`, `env`, `command`, `nice`, `stdbuf`, `exec`, `builtin` or `VAR=x` | 1 | 3 | 1 |
| R3 | any stage before a single bar outside quotes, not only `printf`, `echo` or `cat` (quote parity and the case-pattern exclusion are in the measurement; the first draft without them read 63 pairs) | 47 | 70 | 42 |
| R4b | pipefail taken from a file that sources the library | 10 | 12 | 10 |
| R4a, R4c | forced on; or the owning test file has pipefail (over-inclusive: a subprocess does not inherit the option) | 18, 18 | 30, 30 | 16, 16 |
| R5a | a stub helper called with the verb as any argument, not only the first | 2 | 2 | 1 |
| R5b | a loop over verb names whose body writes `.../$VAR` | 6 | 10 | 4 |
| R6 | producers in `.tf .tftpl .template .service .tmpl` files and in extensionless files with a shebang | 0 | 0 | 0 |
| R7 | the stub-file arm records `jq";` (quote and semicolon kept) for a stub written `> "$d/jq"; chmod`, so it never matches `jq` | 7 | 8 | 7 |
| R8 | an annotation echo is stripped from its token to the closing unescaped quote of its string, not to the end of the line | 0 | 1 | 0 |
| U1 | R1 + R2 + R4b + R5a + R5b + R6 + R7 + R8 | 57 | 81 | 48 |
| U2 | U1 + R3 | 90 | 142 | 66 |

U1 is the brief's list without the any-producer arm: its new pairs span 48 test files (51 counting three whose listed pair gains a producer), 29 of which S7b did not probe. U2 adds the any-producer arm: 90 pairs in 66 test files (69 counting the same three-style cases), 43 of them not probed in S7b and 14 of them reached by no arm but this one. S7b's population was 60 pairs in 48 test files. Without the quote-parity and case-pattern rules the any-producer arm read 63 pairs, about a fifth of them prose or function-name noise; with them it reads 47, of which about 7 are still noise (`ready`, `lexer`, `fatal`, `constitution.md`, `bunfig.local.toml`, `AGENTS.md`, a shell function name).

R6 population, measured separately (`r6diag` read of the tracked tree): 88 `.tf`, 23 `.service`, 8 `.template` and 3 `.tmpl` files, of which 3 `.tf`, 1 `.service` and 2 `.template` files hold a text pipe (one `.tf` with a `pipefail` token, `object_lock.tf`, piping into `jq`), and 4 extensionless files carry a shell shebang, with no text pipe in any of them. No suite derives a pair from any of them.

**A defect J0 found that the brief did not list (R7).** `PJ_AWK` strips a stub path with `sub(/"?[ \t]?$/, "", m)`, which leaves the `;` when a stub is written `printf ... > "$d/jq"; chmod +x "$d/jq"` (the most common one-line spelling in the tree). The recorded name is `jq";`, so that stub is invisible: seven pairs (jq 4, awk 2, perl 1) in seven suites. Reproduced with a one-line fixture (`stub-semicolon`: derives nothing at the merged head; `stub-semicolon-nospace`, a spelling with a space after the quote, derives). It is the same class as the brief's list (an identifier set narrower than the property) hiding behind a different cause.

**Late findings on #10074, each re-measured at the merged head** (a scratch clone of this branch's tree, one mutant at a time under `ulimit -v 6000000`, the unmutated control run first; fixtures in `$SCRATCH/fx`):

| Finding (measured at `e949471417`) | At the merged head `0aae3f8680` | Disposition |
| --- | --- | --- |
| The drain window is bounded at the next opener of the SAME verb only, so another verb's stub can be credited | Open. Fixtures `crossverb` (`curl() { : }` then `gh() { cat >/dev/null }`), `crossheredoc` and `crossbrace` (a function ends and a top-level `cat >/dev/null` follows it) read `ok` where `no` is wanted | Fix (Guard 2) |
| Verdicts outside `pj_judge` and the `pj_j` assignment have no negative control | Open. Six one-fault-one-neuter mutants (count mismatch, no drain, malformed row, triple pin, a deleted row with the `pj_j=` assignment blanked, the `no`-line loop made a no-op) all exit 0; each fault with its verdict intact exits 1 | Fix (Guard 3) |
| Fail-open drain spellings: `[[ -t 0 ]] && cat`, `test -t 0 && cat`, `if [ -t 0 ]; then cat; fi`, `cat >/dev/null </dev/null` | `[[ -t 0 ]] && cat` is already rejected (S7b round 1). The other three are still read as drains | Fix (Guard 2) |
| Fail-closed false rejects: `x=$(cat 2>/dev/null)`, `cat -`, `[ -t 0 ] && true \|\| cat`, `cat >/dev/null; sleep 0 &`, a here-string in a command substitution, `#` inside a string | All reproduce (the `#` case: `echo "a #b"; cat >/dev/null` loses the drain) | Fix the first and second (`cat 2>` and `cat -`: cheap, in the same regexes); record the rest, including the `#` in a string, as NOT fixed (rare spellings, fail closed with the hint naming the accepted form; a quote-aware comment strip would be a second quote parser in awk for one spelling) |
| The annotation skip drops a real pipe sharing a line with an `::error::` echo | A pipe BEFORE the annotation text on its line is derived (fixture `annot-pipe-before`; S7b fixed it, its battery row N22 has no permanent fixture). A pipe AFTER the annotation string is dropped with it, because the strip runs to the end of the line. A first grep over the non-test tree found none; a scan that locates the string's closing quote finds 29 of the 2,754 annotation lines with a single bar after it (a real `echo "$BODY" \| head`, and pipes inside `$( )` in the annotation text), which `j0-derive.py` arm R8 turns into 0 new pairs and 1 new triple (an already-listed pair gains a producer) | Fix (arm R8: strip from the token to the closing unescaped quote, not to the end of the line); permanent fixtures for both shapes (Guard 1) |
| No fixture for the `pj_sourced` rules | Open | Fixture (Guard 1) |
| The dynamic grader's `1\|141` branch was not shown reachable | Measured: SIGPIPE ignored gives rc 1 and the default disposition rc 141 (dash and bash). The control accepts either status for either disposition | No row: an exact-status assertion cannot be killed by a mutation where CI inherits an ignored SIGPIPE (both dispositions then read 1); recorded as measured-reachable (Guard 3 Assembly) |
| mawk unmeasured | No `mawk` on this host | CI is the reading; new awk code avoids `\b`, `gensub`, intervals and a bare `split` |

**Learnings applied** (from the sweep): `test-failures/2026-09-30-stub-drain-fidelity-and-endpoint-keyed-sweeps.md` (key the drain on the flag, keep `[ ! -t 0 ]`); `test-failures/2026-10-05-a-reader-that-exits-early-flipped-three-suites-and-the-stub-had-to-read-too.md` (pin the mechanism, never a timing); the S7b learning above (a text-derived population changes verdict with no edit on the branch: run the derivation on the tree merged with main; a `timeout` drain fails when the sandbox PATH farm lacks it); `2026-09-14-every-guard-i-shipped-had-a-narrower-window-than-its-name-and-my-first-mutant-caught-my-own-guard.md` and `2026-09-23-the-prose-stated-the-property-and-the-predicate-checked-a-subset.md` (write the property, then compare it with the recognised set); `2026-10-10-my-must-pass-arm-passed-wherever-its-mutation-landed-and-nothing-noticed-the-arms-could-be-deleted.md` and `test-failures/2026-10-10-a-negative-row-passed-for-the-wrong-reason-four-times-in-the-guard-built-to-contain-mutants.md` (a must-PASS row must pass only where the property lives; a negative row must fail for its asserted reason); `2026-10-11-a-control-that-fails-early-proves-nothing-about-the-checks-after-it.md` (one control per check, attributed by its own diagnostic, and a landing assertion that the mutation changed the file); `2026-09-17-awk-word-boundary-backslash-b-is-backspace.md` and `2026-03-31-awk-split-defaults-to-fs-not-whitespace.md` (no `\b`, pass the separator to `split`); `test-failures/2026-10-08-a-pair-run-needs-a-real-base-checkout-and-the-mandated-ulimit-aborts-vitest-on-both-sides.md` (pair-run bases are real checkouts; `ulimit -v` only on shell-only mutants). Only the S7b learning above names the join's symbols (`git grep -l` over `knowledge-base/project/learnings` for `PJ_AWK`, `PJ_TRIPLES`, `SWEEP_PROBE_CHECKS` and `PRODUCER_JOIN` returns that one file), and it records the annotation and drain-spelling defects, not recall; no learning covers the derivation's recall, so it has no direct prior art.

**Property List (Phase 0.6b).**

- P1. A new non-test pipe into a verb a test suite stubs cannot appear without a recorded decision (a table row), in any of the spellings the arms name, whatever the verb is called.
- P2. In every suite that RUNS such a pipe with the verb stubbed, the stub reads stdin before it can exit when argv carries the consuming flag, and the pin cannot be satisfied by another verb's stub, by a spelling that reads only on a terminal, or by text that is not code.
- P3. Every verdict the join block prints is driven by a fixture that must make it print, so a neutered verdict (a `pj_fail` replaced by `:`, a blanked merge, a no-op loop) turns the guard red.
- P4. Each derivation arm is exercised by a case that must derive and a case that must not, inside the guard's own run, so an arm cannot be narrowed or deleted unseen.

**Cut List (Phase 0.6b),** each cut names the property it would have bought and what covers it:

- R4a and R4c (pipefail forced on, or taken from the owning test file): cut. A subprocess does not inherit the option, so a pipe in a script the suite RUNS without pipefail cannot report the hazard; R4b (a library sourced by a file that has the token, test or not) is the reading that matches the runtime. Measured: 10 pairs against 18.
- Extensionless producers (the second half of R6): cut. 4 tracked extensionless files carry a shell shebang and none holds a text pipe; reading each file's first line would add a per-file read to a derivation already near the preflight cap for no pair. The `.tf` family stays (one extension list and one token pattern, 0 pairs today).
- Replacing the `printf|echo|cat` site scan wholesale with the any-bar scan: cut. The 66 rows and the 120-triple pin are defined by the old scan; the new scan is added as a second site source and the two are unioned, so a regression of the new arm cannot move the old rows. Recorded as decision-challenges item 2.
- An identity pin for the producer triples (a list or a hash instead of a count): cut. A count pin lets one producer be deleted while another is added for the same pair; naming each triple would double the table for that one swap. Stated in the Anchor of Guard 1.
- A proper shell lexer for bar detection: cut in favour of a quote-parity test on the text before each bar. A bar inside `"$( ... )"` is missed (an under-derivation, stated); a bar inside a plain string is not read as a pipe.
- A shell lexer is the alternative to the quote-parity test, and the repo has a recorded lesson for guards over a structured language (learning `2026-09-24-a-line-scanner-is-not-a-lexer-and-my-guard-fixture-hid-the-suite.md`, #8667: scan the language, never lines keyed on a column). It is cut here on cost, and the cost is stated: the existing guard is a line scanner by construction (S7b), a lexer in awk for strings, comments, heredocs and `$( )` depth is its own slice, and the under-derivation it would close is bounded and listed in NOT fixed (decision-challenges item 3).
- The fail-closed false rejects that need a shell parser (`[ -t 0 ] && true || cat`, a drain followed by a backgrounded `sleep`, a here-string in a command substitution): cut, listed as NOT fixed.
- An ADR for the guard architecture (S7b dissent, taste): cut here. Nothing in the diff changes a substrate or a trust boundary; the semantics are still moving (the any-producer arm may be cut at ship time, and Items D to I remain), so the header and `evidence.md` carry the record. Recorded as decision-challenges item 5.
- Running the owner suites from inside the guard, a shared stub-drain helper, a sibling suite for the join, and converting the non-test pipes: cut for the reasons the S7b plan recorded (CI already runs the suites; the helper edits the same stubs; a new registered suite needs a declared edge in a fenced file; the sites are correct, the stubs are not).
- A pre-registered cut gate on the number of new pairs: cut (S7b cut its own; the commit order below makes a split at ship time free).

**Value-proposition measurement (Phase 0.6c).** The claim is flake prevention and recall, not a saving, so there is no saving to quantify. The measured base rate is S7b's: three producer-side stub flakes in eleven days before the join, each found only after a red run. What this slice adds is measured, not asserted: 57 pairs (U1) or 113 (U2) the guard cannot see today, and seven that are invisible only because of a one-character defect.

## Research Reconciliation: Spec vs. Codebase

| Claim | Reality | Plan response |
| --- | --- | --- |
| Brief: "a pipe split over lines by a trailing backslash or pipe (about 24 pairs)" | 29 pairs in 27 test files from a logical-line join (trailing backslash, trailing pipe; a YAML block-scalar indicator and a bar inside quotes do not join) | One join rule; J0 reconciles the count with the awk derivation (AC-4). A physical line that begins with a bar is read by the any-producer arm, not by this one |
| Brief: "a library pipe with no pipefail token" (S7b evidence: 16 pairs when forced on) | Forced on reads 18; the reading that matches the runtime (the library is sourced by a file that has the token) reads 10 | R4b only; R4a and R4c cut with the measure |
| Brief: "helper-with-argument and loop-built stubs", "five suites seen by no pair" | 2 pairs from helper arguments (one suite) and 6 from loops (four suites) | R5a and R5b as stub arms; fixtures name both |
| Brief: "producers in .tf or extensionless files" | 0 pairs; 6 files with a text pipe in the `.tf` family, 0 extensionless | Extension list only; extensionless cut with the measure |
| S7b: `cloud-init-inngest-bootstrap.test.sh` is BLOCKED by #9956 | #9956 closed 2026-10-11; `Infra Validation` green on main in every run where the job ran; the brief still says red at base | Do not edit the file; reclassify the two pairs in a real clone; rows keep a truthful reason (decision-challenges item 6) |
| S7b evidence: "annotation echoes were read as pipes; the filter strips the text after the annotation" | True at the merged head for a pipe before the annotation; the strip runs to the end of the line, so a pipe after the annotation string is dropped (29 lines, 1 new triple, 0 pairs; the plan's first draft read a narrow grep as "0 instances", a universal negative the wider scan refuted) | Arm R8; permanent fixtures for both shapes |
| S7b: "derivation is authoritative; `j0-derive.py` is a point-in-time measurement" | The S7c script is a port of the guard that reproduces 66 and 120 before it measures anything | The port's BASE line is the drift check (AC-1); the guard stays authoritative |
| Brief: "nothing added to `plugins/soleur/skills/work/SKILL.md`"; fenced files | The guard's declared affected-edge list lives in a fenced file | Not edited; the limit stays stated (`--affected` does not select the guard when only an owner suite changes) |

## Implementation Phases

Phase 0 (J0, read-only, before any edit). Everything here is recorded in `evidence.md` and committed first.

- 0.1 Re-run the derivation in a clean checkout (`git status --porcelain` empty): `ulimit -v 6000000; python3 -I knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-s7c-derivation-recall/j0-derive.py`, on the branch merged with current main. The BASE line must read the guard's own figures (read from the guard run on the same tree); if it does not, the port has drifted and nothing below is read until it is repaired. Compare with `j0-plan-time-output.txt` and explain any difference (main moves, and a new producer on main is a new unlisted pair by design).
- 0.2 Classify each new pair, as in S7b: a stdin-reading command, or not a command in that sense (`died`, `no`, `out`, `set`, `the`, a shell function, a word of prose). The derivation still reports the pair; it becomes an `exempt` row with a word from the closed vocabulary (`not-a-command`, `text-only`, `unverified`, `blocked-#N`, `helper-built-stub`, `variable-named-verb`, `pass-through`, `deliberate-fault`, `arm-drain`). A new vocabulary word is a decision-challenges entry.
- 0.3 Reach probe, the S7b tooling (`j0-stubs.py`, `j0-sites.py`, `j0-instrument.py`, recoverable from commit `6e320b391e`, copied into this spec dir). In a scratch checkout from `bash scripts/soleur-sandbox.sh new s7c-reach`, never committed, insert one marker at the top of EVERY stub definition a suite owns (a suite is run once for all its verbs), run each suite once under `timeout 300` and `ulimit -v 6000000` through `bash scripts/soleur-sandbox.sh run-isolated "$SBX" -- ...`, and read the hit log. EXEC = a piped call reached the stub with argv recorded (a process substitution looks the same to the marker, so each EXEC row is read by hand against its producer line); TEXT = the suite ran green and no piped call arrived; UNVERIFIED = a timeout, a suite red in the sandbox, or a helper-built stub; BLOCKED = red at base for a reason that is not the sandbox. A suite that needs git tags or history (`cloud-init-inngest-bootstrap.test.sh`) runs in a real local clone with tags, never in the copy. Two tranches: tranche 1 is the suites behind U1 (51 test files, 29 not probed in S7b); tranche 2 is the 14 further suites only the any-producer arm adds. Up to 300 s each: run three at a time, one sandbox each, and record the host load beside the wall time. The any-producer arm ships only with every one of its new pairs classified: if tranche 2 cannot be completed, that arm is cut and recorded as NOT fixed (an unprobed population), never shipped with rows nobody classified; `unverified` is a class for a suite that timed out or was red in the probe, not for a suite nobody ran.
- 0.4 Read each EXEC stub by hand and record its drain state (drains in every arm before its first exit or return, only in some arms, never, delegates to the real binary) and the consuming flag per verb from the producer line.
- 0.5 Record the count of suites that need an edit and how many are under `apps/web-platform/infra/`. There is no gate on the number; Phase 2 orders its commits non-infra first and infra second. Also record, per arm, how many of its new pairs classify EXEC: an arm whose pairs are all TEXT, UNVERIFIED or not-a-command still buys the recall property for FUTURE pipes (and costs rows), so it ships by default; the per-arm EXEC count is what the ship-time cut of the last arm is argued from. `cloud-init-inngest-bootstrap.test.sh` is never edited: if its pairs classify EXEC and non-draining they are recorded as NOT fixed (fenced by the brief) with the classification.
- 0.6 Re-measure the late findings against the tree merged with main and record the table above with the commands. If `busybox awk` or `original-awk` is installed, also run the derivation fixtures under it as a second engine (mawk stands in for CI's default awk); otherwise CI is the only reading and the evidence says so.

Phase 1 (red first, `cq-write-failing-tests-before`). In the guard, before any derivation change: add the derivation fixture suite (Guard 1), the window and spelling fixtures (Guard 2) and the verdict controls (Guard 3). Run once in a clean checkout under `ulimit -v 6000000` and record every new check's first result: each arm's must-derive fixture reads FAIL naming its case, each must-not-derive fixture reads PASS, the cross-verb and fail-open spellings read as drains, and each neutered-verdict control reads RED. The fixtures are the tests; the edits turn them green.

Phase 2 (derivation arms and detector fixes, in this commit order so the last arm is cuttable). Each commit leaves the guard green with the rows it needs:

1. R7 (the stub name), because it is a defect and its pairs are U1's.
2. R1 (logical lines joined over a trailing backslash or pipe), then R2 (wrapped verbs), then R8 (the annotation strip).
3. R4 (the library rule: a reverse source map built in the one awk, resolved in `END`).
4. R5a and R5b (helper arguments; loops), then R6 (the extension list and the owner-token pattern).
5. Guard 2 and Guard 3 changes (window bound, spellings, verdict functions).
6. R3 (any producer), last.

Before an arm's rows are added, run the guard once with the arm in and its rows absent and diff the `unlisted pair` lines against that arm's increment in `j0-derive.py`; record the difference (expected: none, except the any-bar arm's quote parity, which drops pairs the measurement counts), then add the rows. This is the per-arm parity check between the Python port and the awk derivation. The design of each, and the fixtures that pin it, are in the Guard Contract. All new awk avoids `\b`, `gensub`, interval expressions and `split` without a separator; every regex that travels through `awk -v` uses bracket expressions and no backslashes (as `PJ_DETECT` does).

Phase 3 (stub edits, by hand; the three kinds of edit only). For each suite Phase 0.4 marks for edit, in two commits ordered by blast radius (outside `apps/web-platform/infra/` first): (a) a drain as the stub's FIRST statement, exactly when argv carries the consuming flag, keeping the not-a-terminal test, bounding the read with `timeout 2 cat` where the suite's PATH carries `timeout` (a stub that runs under `env -i` with a PATH farm uses plain `cat`: S7b's `cron-egress-nftables` stub failed on exactly that), and capturing to a side file only when the suite names one; (b) one wire assert per drained pair, with the `${KNOB:-default}` form; (c) no new knob unless a race row already needs one. No non-test file, workflow or `.tf` file is edited, and none of the fenced files below.

Phase 4 (rows). The `unlisted pair` message gains the producer file(s) that derive the pair (the third column the derivation already prints), so a contributor sees which pipe caused it; a pin failure (`PJ_TRIPLES`, `SWEEP_PROBE_CHECKS`) keeps printing the recomputed value. Rows stay sorted by (suite, verb). The table gains one row per new pair: `drains` with a definition count and the flag token for each EXEC pair that now drains, `exempt` with a vocabulary reason (and the reach evidence in the reason) for the rest. `PJ_TRIPLES` and `SWEEP_PROBE_CHECKS` are recomputed from a green run with the header recipe, never by hand.

Phase 5 (wording). Rewrite the STATED LIMITS paragraph of the guard header to the S7c state (what each arm now sees, what is still not seen: extensionless producers, a bar inside `"$( )"`, a verb behind a group beyond its first word, a stub two or more hops away, a variable-named verb, a pipe written after an annotation's text, and the rare drain spellings that fail closed), keep the series open (Items D, E, F, G, I and H, the Wave A3 carriers, the #9639 and #9638 triage are listed, not planned), and do not write that the series is finished.

Phase 6 (evidence, battery, ship). Run the mutation rows and the harness rows below one at a time under `ulimit -v 6000000` on a scratch clone, each asserting first that the mutation landed (the file changed) and that the unmutated control exits 0; a row whose mutation executes an owner suite goes through `run-isolated`. Pair run: each edited suite at its base commit and at head from real checkouts, same machine, results compared. Then the lints in AC-9, `bash scripts/test-affected-kb-consumers.test.sh` once (about 95 s), the pre-push ratchet lane on the branch merged with main, `decision-challenges.md`, a learning only if a non-obvious finding occurs, the PR body per AC-11, `soleur:ship`, then AC-12.

## Files to Edit

- `.claude/hooks/grep-q-pipe-guard.test.sh` (the derivation program, the derive function and its fixtures, `pj_defs`, `PJ_NODRAIN`, the verdict functions and their controls, the rows, `PJ_TRIPLES`, `SWEEP_PROBE_CHECKS`, the header)
- Owner suites, only those Phase 0.4 marks for edit. The candidates are the test files in `j0-plan-time-output.txt` under U1 (51 test files) and U2 (69); the edit list is a Phase 0 output recorded in `evidence.md`. A stub that lives in a sourced helper is edited in the helper. Not edited whatever its class: `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`.
- `scripts/test-affected-kb-consumers.baseline.txt` only by the gate's own regeneration (`--write-baseline`) if the gate names a reference one hop away that the guard does not read (S7b added six rows this way).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-s7c-derivation-recall/{tasks.md,evidence.md,decision-challenges.md,session-state.md,j0-stubs.py,j0-sites.py,j0-instrument.py}` (`j0-derive.py` and `j0-plan-time-output.txt` already exist there; the three reach scripts are copied from `6e320b391e` at Phase 0.3)
- `knowledge-base/project/learnings/test-failures/2026-10-12-<slug>.md` only if a non-obvious finding occurs (the stub-name defect is the first candidate)

## Files to Delete

None.

Not touched, on purpose: `plugins/soleur/skills/work/SKILL.md`, `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/lib/scratch-root.sh`, `plugins/soleur/test/skill-body-budget.json`, `plugins/soleur/skills/plan/SKILL.md`, `AGENTS*.md`, every file under `.github/workflows/`, every non-test script, cloud-init file and `.tf` file that carries a pipe (the sites are correct; the stubs are not), `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`, `cursor-matcher-parity.test.sh` (PR #9745), and the main checkout's `.mcp.json` and untracked `apps/web-platform/1000:` and `500` files.

## Open Code-Review Overlap

One match among 88 open `code-review` issues, over the guard path, the S7b owner suites and every U2 test file: #7098 (`ci: audit the 56 run: bodies whose set omits -e ...`) names `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` as a precedent for its own lint. Acknowledge: a different concern, nothing in this slice rewrites that suite's arm 13d; the issue stays open. The Phase 0.5 edit list is re-queried before the first suite edit.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing; a regression is a CI false-red (a suite whose stub now needs a drain it should not need, or a guard that reads a pair the table lacks) or a false-green on a test-hygiene gate, seen by contributors as a red `test` or `infra-validation` check.
**If this leaks, the user's data is exposed via:** no vector; the diff edits test stubs and one drift guard, handles no credential or user data, and the drained bytes are written to a per-run scratch file the suite already owns.
**Brand-survival threshold:** none
threshold: none, reason: the diff edits repo-internal test stubs and one drift guard; no runtime, data or credential surface is touched, and no non-test script is edited.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.

## Guard Contract

The deliverable is a guard (the widened join and its controls). One entry per property; the matrix is written from the design before the guard. Each entry carries a row against its own dispatch, a second-member row and, where the property is about order or a window, a REORDER or window row; each also carries must-PASS rows that are not the canonical, and a row on the remediation's own text (the new rows and fixtures must themselves satisfy the guard that reads them). Every row is run one at a time on a scratch clone under `ulimit -v 6000000`, asserting that the mutation landed and that the unmutated control exits 0. A row is graded RED only when the guard exits non-zero AND prints the named FAIL substring (or the fixture's case name); a different failure is a wrong-reason RED and is re-aimed, never counted.

### Guard 1 — the derivation closes over every arm

**Property.** Every (test file, verb) pair where the test file names a non-test file that pipes into that verb under `pipefail` (its own, or a file that sources it) with its status observed, and the test file (or one file it sources) stubs that verb, derives and has exactly one row, in each spelling an arm names; narrowing, disabling or deleting an arm turns the guard red through that arm's own fixture, and a spelling the arm must not read (a quoted bar, a case-pattern alternation, a comment, a status-dropped site, `command -v`, a block scalar) does not derive.

**Assembly.** One awk program (`PJ_AWK`) and its inputs, structural and not a list of today's members. The chokepoint is a single derive function over a listing and a set of files, called by the real run and by every fixture (so a fixture exercises the same program the tree does); the rest quantifies over: (1) the file kinds: ONE shared extension list feeds the listing pathspec, the non-test test and the owner-token pattern, so no arm can widen one of the three and not the others; (2) the site sources, TWO and unioned: the old `printf|echo|cat` pattern run over LOGICAL lines (a code line ending in a backslash, or in a single bar outside quotes that is not a YAML block-scalar indicator such as `run: |`, absorbs the next code line, capped at a fixed number of lines), and, for the any-producer arm only, a scan of every single bar outside quotes on a physical line; (3) the verb extraction after a bar: group openers, assignments, `sudo` flags, and a wrapper table with per-wrapper flag arity (`timeout`: `-k DUR`, `-s SIG`, `--foreground` and the duration; `nice`: `-n N`; `env`: `-i`, `-u NAME`, `VAR=x`; `stdbuf`: `-i`, `-o`, `-e` with a mode; `command`: `-p` only, while `-v` and `-V` are queries and not wrappers; `exec`: `-a NAME`, `-c`, `-l`; `builtin`), a bare wrapper with no verb excluded, and a bar followed by a word and a `)` read as a case-pattern alternation and not a pipe; (4) the annotation rule (from an `::error::`, `::warning::` or `::notice::` token to the first unescaped double quote after it, or to the end of the line when no quote follows, is dropped; the rest of the line is scanned; a string that spans lines is stripped to the end of its first physical line, a stated limit) and the observed rule (a `|| true` or `|| :` on the logical line); (5) the pipefail scope (the file's own token, `shell: bash` in a workflow, or a file that sources the library and has the token, resolved in `END`); (6) the stub arms, FIVE: a function definition, a file written to `.../WORD` (name cleaned of trailing quote, semicolon and blanks), a stub-helper call naming WORD as any argument, a loop over verb names whose body writes `.../$VAR`, and each of these in one sourced file (one hop); (7) the owner rule (the producer's basename as a whole token on a non-comment line). There is more than one injection path into the pair set (two site sources, five stub arms, one extension list read three ways), so each arm has its own fixture and its own mutation row. The pins read the one derivation: the unlisted-pair and stale-row checks, the recall rows (`luks-monitor.test.sh` with `cryptsetup` derives through the sourced harness; the variable-named `ssh` stand-in is an `exempt variable-named-verb` row), the producer-triple pin and the fixtures.

**Mutation matrix.**

| # | Mutation | Expected RED |
| --- | --- | --- |
| M1 | Own dispatch: the derive function is handed an empty file set, or the fixture runner derives nothing | `UNRESOLVED` (exit 3) for the real run; `derivation-fixtures ... derived nothing` for the fixture run, never a pass |
| M2 | Drop the logical-line join over a trailing pipe | `derivation-fixtures`: `pipe-split` must derive |
| M3 | Drop the logical-line join over a trailing backslash | `derivation-fixtures`: `backslash-split` must derive (a fixture whose continuation line holds the bar mid-line, after a quoted argument: `printf '%s\n' \` then `"$a" \| curl -K -`) |
| M4 | Second member: a fixture file whose first line is a compliant `printf \| curl` and whose later line pipes into a second stubbed verb; make the scan stop after the first site | `derivation-fixtures`: the second verb must derive |
| M5 | Drop the wrapper table (a verb behind `timeout 5` no longer derives) | `derivation-fixtures`: `wrapper-timeout` must derive |
| M6 | Per-wrapper arity: read `timeout -k 2 5 curl` with the arity of a bare `timeout` | `derivation-fixtures`: `wrapper-timeout-k` must derive |
| M7 | Treat `command -v curl` as a wrapper of `curl` | `derivation-fixtures`: `command-v` (`printf x \| command -v curl`) must NOT derive |
| M8 | Drop the any-bar scan | `derivation-fixtures`: `other-producer` (`jq -r .x f \| curl -K -`) must derive |
| M9 | Treat a bar inside double quotes or single quotes as a pipe (quote parity removed) | `derivation-fixtures`: `quoted-bar` (`foo "a \| curl"`) and `quoted-bar-single` (`foo 'a \| curl'`) must NOT derive |
| M10 | Join a trailing bar that sits inside a quote (parity dropped from the join) | `derivation-fixtures`: `quoted-trailing-bar` (a `jq '.a \|` line followed by `select(.b)'`) must NOT derive |
| M11 | Join over a YAML block-scalar indicator (`run: \|`) | `derivation-fixtures`: `yaml-block-scalar` must NOT derive a pair of its own |
| M12 | Drop the case-alternation exclusion | `derivation-fixtures`: `case-alternation` (`case $x in a\|curl) :;; esac`) must NOT derive |
| M13 | Drop the sourcer rule (the reverse source map) | `derivation-fixtures`: `library-sourced` must derive; `library-unsourced-no-pipefail` stays green |
| M14 | Take the pipefail scope from the owning test file (the over-inclusive reading) | `derivation-fixtures`: `library-unsourced-no-pipefail` must NOT derive |
| M15 | Helper stub: read only the first argument | `derivation-fixtures`: `helper-arg2` must derive |
| M16 | Drop the loop arm | `derivation-fixtures`: `loop-built` must derive; `loop-nonverb` (a loop that writes a file that is not a verb) stays green |
| M17 | Drop `.tf` from the shared extension list | `derivation-fixtures`: `tf-producer` must derive (the fixture runs through the listing pathspec, the non-test test and the token pattern); `tf-no-pipefail` must NOT derive |
| M18 | Restore the stub-name strip (`"?[ \t]?$` only) | `derivation-fixtures`: `stub-semicolon`, `stub-unquoted-semicolon` (`> $d/jq;`) and `stub-space-semicolon` (`> "$d/jq" ;`) must derive |
| M19 | Drop the one-hop sourced-stub arm | `derivation-fixtures`: `stub-in-sourced`; the `luks-monitor.test.sh` recall row |
| M20 | The annotation strip reverts to end-of-line (a pipe after the annotation string is dropped with it) | `derivation-fixtures`: `annot-pipe-after` must derive; `annot-pipe-before` stays green |
| M21 | The annotation strip stops at the first quote and ignores the backslash | `derivation-fixtures`: `annot-escaped-quote` must NOT derive |
| M22 | A pipe inside the annotation text is derived (no strip) | `derivation-fixtures`: `annot-pipe-inside` must NOT derive |
| M23 | The observed rule reads only the first physical line of a logical line | `derivation-fixtures`: `continuation-or-true` (`printf x \` then `\| curl \|\| true`) must NOT derive |
| M24 | Add one new producer for an already-listed pair | `PJ_TRIPLES` verdict (count off by one) |
| M25 | Delete one row and keep its pair; keep a row whose pair no longer derives | `unlisted pair`; `stale join row` |

**Harness rows.** H1 (suite edit that MUST read RED): delete the fixture runner's `|| sweep_probe_fail+=` tail (the one tail the whole case table shares); `probe-count` reads RED. H2 (must-PASS, not the canonical): a continuation line indented with a tab; `env -i VAR=1 curl` (assignment and wrapper together); a comment line between two joined lines is skipped; a fixture whose suite names `fprod.sh` is not an owner of `prod.sh`; a producer written with CRLF line endings still derives. H3 (the remediation's own text): the fixtures are built with `printf` or indented, so no column-0 `FAIL=0`, `exit "$FAIL"`, `sweep_fold` or `|| sweep_probe_fail+=(` text appears inside a fixture or a message, and the recipe in the header is re-run after drafting.

**Anchor.** The table, the fixtures and the derivation sit in one file and each row's stub sits in another, so one diff can edit a row and its stub together: that proves consistency, not integrity. What stands outside the commit: `evidence.md` (the J0 table, the reach table per pair, the arm increments reproduced by `j0-derive.py`, an independent port of the same rules, compared as an empty diff on pairs AND triples at the final configuration), the dynamic control (Guard 3 reads no row), the closed vocabulary that makes `exempt` reasons greppable, and the reviewer reading the two-place edit. A count pin (`PJ_TRIPLES`) survives an add-one-delete-one swap for one pair; the swap is a stated limit, not a claimed integrity.

### Guard 2 — a stub's drain is its own, reads on a non-terminal, and is code

**Property.** For every `drains` row, each of the row's N stub definitions has, inside ITS OWN extent (from its opener to the earliest of: the opener of a function, helper-call or heredoc stub of ANY verb, its heredoc terminator, its closing brace, or the window limit), a drain keyed on the row's flag token that reads when stdin is not a terminal; a drain belonging to another verb's stub, one that reads only on a terminal, one in a comment, or one reached after a bare exit does not count, while a data-file write (a logging line) before the drain does not end the extent.

**Assembly.** The opener finder (function opener, file written to `.../VERB`, helper call; over the row's verb for the check, and for the BOUND over function openers, helper calls and heredoc writers of any verb only, since a one-line `printf ... >> "$d/args"` logging write is not a stub of anything), the extent limits (next bounding opener, heredoc terminator found on the opener line, closing brace at the opener's indent or on the opener line itself for a one-line stub, the four-line window), the exit disarm, the comment strip (unchanged: a `#` inside a string still reads as a comment and fails closed), the detector pair (`PJ_DETECT` and `PJ_NODRAIN`, shared by the pin and the dynamic control) and the two spelling arrays. The chokepoint is `pj_defs`: the count check, the flag check and the first-statement check all read its output, and `pj_detects` is the one detector.

**Mutation matrix.**

| # | Mutation | Expected RED |
| --- | --- | --- |
| M26 | REORDER (window): remove the bound at another verb's opener, so a following verb's stub is inside this stub's window | the `crossverb` finder fixture reads `ok` instead of `no` |
| M27 | Remove the heredoc-terminator bound | the `crossheredoc` finder fixture |
| M28 | Remove the closing-brace bound | the `crossbrace` finder fixture (measured open at the merged head; a function body ends, the next statement is a top-level `cat >/dev/null`) |
| M29 | Widen the bound to every file write (the any-write reading of the stub-file pattern) | the must-PASS fixture `logging-write-before-drain` reads `no` instead of `ok` |
| M30 | The closing-brace bound ignores a one-line stub | the must-PASS fixture `one-line-stub` (`curl() { cat >/dev/null; }`) reads `no` instead of `ok` |
| M31 | Second member: a second definition of the verb with no drain after a compliant first | `definitions 2, pinned 1` (kept) |
| M32 | Drop the `test -t 0` alternative from the non-drain pattern | the non-reading array row `test -t 0 && cat` is detected: `detector disagreements` |
| M33 | Drop the `if ...; then` alternative | the row `if [ -t 0 ]; then cat; fi` |
| M34 | Drop the input-redirect alternative | the row `cat >/dev/null </dev/null` |
| M35 | Own dispatch: rename the stub opener so the finder sees zero | `stale join row` / `UNRESOLVED` (kept) |
| M36 | Remove the `cat 2>` and `cat -` alternatives | the accepted rows `x=$(cat 2>/dev/null)` and `cat -` read `no` |

**Harness rows.** H4 (suite edit): make the extent logic accept only a function opener; the rows whose stubs are heredocs read RED (kept). H5 (must-PASS, not the canonical): each accepted spelling runs through the dynamic control under both dispositions and both interpreters, including the two new accepted spellings (`x=$(cat 2>/dev/null)` and `cat -`); `[ ! -t 0 ] && cat` and `[ -t 0 ] || cat` stay accepted; the three new non-reading spellings fail the dynamic run under both dispositions.

**Anchor.** The flag token in a row and the flag in the stub are edited by one diff. The dynamic control (Guard 3) is the reading that trusts neither, and the reach table in `evidence.md` records which pairs actually ran. Stated.

### Guard 3 — every verdict is driven

**Property.** Every FAIL the join block can print (malformed row, definition count, no drain, producer-triple pin, the judge's five, the merge) is produced by a function the probe drives with a fixture that must make it print, and the merge assignment, the `PJ_FAIL` setter and the fold into the suite verdict are pinned, so a verdict neutered to `:` or a merge blanked cannot leave the guard green.

**Assembly.** The verdict sites (the three row checks, the triple pin, `pj_judge`, the `UNRESOLVED` exits), the merge assignment (`pj_j="$(printf ... | pj_judge "$pj_pairs")"`, pinned by a NEW column-0 pin `wire_pjj` counted into the existing `producer-join-wiring` check: the existing `wire_pjn` pins only the line that tests `pj_j`, not the assignment above it), `pj_fail`, the column-0 fold, the fixture drivers (`pj_jc` and its new siblings for the row checks and for the triple pin), and the wire pins (`producer-join-wiring`). The chokepoint is the set of verdict functions plus one merge statement; the wire pins read the whole file's non-comment lines at column 0, so an indented copy in a dead branch does not count. The dynamic control's 1-versus-141 grading is NOT a row here: the control accepts either status for either disposition, rc 1 under an ignored SIGPIPE and 141 under the default were both measured reachable at plan time, and an exact assertion is not killable by mutation where CI inherits an ignored SIGPIPE (the status then reads 1 for both).

**Mutation matrix.** Each row neuters a verdict; the fault is carried by the control's own fixture (the same fault with the verdict intact exits 1, measured at plan time as the `a0 b0 c0 d0 f0` runs).

| # | Mutation | Expected RED |
| --- | --- | --- |
| M37 | The definition-count verdict is neutered | the row-check control: `definition count verdict did not print` |
| M38 | The no-drain verdict is neutered | the row-check control: `no-drain verdict did not print` |
| M39 | The malformed-row verdict is neutered | the row-check control: `malformed-row verdict did not print` |
| M40 | The triple-pin verdict is neutered | the triple-check control |
| M41 | The `pj_j` merge assignment is blanked, with a real row deleted | `producer-join-wiring`: `the pj_j assignment` |
| M42 | The `no`-line loop of the row check is made a no-op | the row-check control |
| M43 | Second member: two faulty fixture rows, only the first one's verdict neutered | the row-check control still sees the second (a check that stopped at the first row would stay green) |
| M44 | Own dispatch: the row-check driver is handed zero rows | `row checks derived nothing`, never a pass |
| M45 | `pj_unread` widened to accept rc 3 (kept from S7b) | the hazard control |

**Harness rows.** H6 (suite edit that MUST read RED): delete one new control's `|| sweep_probe_fail+=` tail; `probe-count` reads RED. H7 (must-PASS, not the canonical): a clean table and clean fixtures print nothing from each verdict function; the verdict functions accept a row with extra whitespace around the separators and a `drains` row with a tab; the fold still turns a non-zero `PJ_FAIL` into a red suite when a fixture row is deliberately wrong.

**Anchor.** The controls store no value, so nothing outside the commit needs to move for a weakening to pass: weakening a verdict means editing it, which M37 to M43 drive RED. The wire pins are text and cannot defend code placed ahead of themselves (the limit S7a recorded: a diff that edits the guard's control flow is read by a reviewer). Stated.

## Observability

```yaml
liveness_signal:
  what: the grep-q-pipe-guard suite runs in the CI test group on every PR and merge_group run and prints PASS lines, one DEFERRED line per sweep row, one JOINED line per join row and a PASS line for the producer join
  cadence: per PR and per merge_group run; run directly before each push
  alert_target: the required test check turns red on the PR, which blocks merge and ejects a queue entry
  configured_in: scripts/test-all.sh SUITE_GLOBS entry '.claude/hooks/*.test.sh' (registration), .claude/hooks/grep-q-pipe-guard.test.sh (the passes)
error_reporting:
  destination: CI job log of the test check (repo-hygiene guard, no Sentry surface)
  fail_loud: a FAIL line naming the unlisted pair, the stale row, the stub and the reason, a failed derivation fixture by case name, or a verdict control by verdict name, exit 1; an empty derivation, a drains row that finds no definition, a failed listing or a fixture run that derived nothing prints UNRESOLVED or FAIL and exits non-zero
failure_modes:
  - mode: a new non-test pipe (in any spelling an arm names) plus a suite that stubs its verb lands without a row
    detection: the derived pair set differs from PRODUCER_JOIN, so the guard prints "unlisted pair" naming the suite and the verb
    alert_route: required test check red on the PR
  - mode: a running stub loses its drain, or its drain is another verb's, reads only on a terminal, or sits below an exit
    detection: the per-row stub check prints the definition and the reason; the dynamic control fails a non-reading spelling
    alert_route: required test check red on the PR
  - mode: a derivation arm or a verdict is narrowed, disabled or neutered
    detection: the arm's must-derive fixture, or the verdict's control, prints its case name; probe-count catches a deleted check
    alert_route: required test check red on the PR
  - mode: an edited owner suite changes behaviour
    detection: the suite's own result in infra-validation deploy-script-tests or the test check on the PR head, and the recorded pair run; infra-validation is not a required check, so AC-6 reads it
    alert_route: the check on the PR (visible, not always blocking) and the review
logs:
  where: CI job logs of the test and infra-validation checks; locally the stdout of the guard
  retention: GitHub Actions log retention
discoverability_test:
  command: bash .claude/hooks/grep-q-pipe-guard.test.sh
  expected_output: grep-q-sweep-probe-pass
```

Detection note for preflight Check 10 (argued against the suite-shaped detection of deepen-plan Phase 4.7: the guard has no partial mode, so it is the smallest command that prints the signal `liveness_signal.what` names, and its measured cost is inside the cap): one deterministic file set, no build or network. At plan time the guard runs in 8.2 s wall (10.7 s user) on this host at load average 5.5. S7b measured the join adding about 6 s on a quiet host and more under load, and Check 10 caps a probe at 15 s, so this slice carries a budget: the new site scan is one pass over the lines that hold a bar (21,010 lines in the non-test tree), the reverse source map is built in the same pass, and the fixture suite runs the awk over a few hundred bytes. AC-10 records wall time plain and in a Check 10-shaped read-only `bwrap` with `uptime` beside each figure; if the plain figure on a quiet host exceeds 12 s, the declared command above is replaced by a committed repo-relative script that prints the signal from the guard's last-run summary line (decision recorded in `decision-challenges.md`).

## Alternative Approaches Considered

| Alternative | Why not |
| --- | --- |
| Treat the six items as NOT fixed again and add only the detector fixes | The brief's order puts derivation recall first, and J0 shows 57 pairs (113 with any producer) the guard cannot see, seven of them behind a one-character defect |
| Replace the `printf\|echo\|cat` scan with the any-bar scan | Cut List: moves the meaning of the 66 rows and the 120-triple pin; a union keeps them stable |
| Read pipefail from the owning test file (R4c) or force it on (R4a) | Cut List: over-includes subprocesses that do not inherit the option |
| A shell lexer for bar detection | Cut List: a parity test on the text before the bar is enough for the measured population and costs one `gsub` per candidate bar |
| Split R3 into its own slice | Recorded as decision-challenges item 1; the commit order makes a split at ship time free, and the brief names the slice as one |
| Extensionless producers | Cut List: 4 files, 0 pipes |
| A shared stub-drain helper, a sibling suite, a dynamic whole-suite run per pair | Cut List: as in S7b |

## Follow-on slices (listed, not planned here)

Items D, E, F, G, I and H of the series brief, the Wave A3 carriers where unblocked (the six carrier rows and the 23 later-wave sites are gated on a host replace), and the #9639 and #9638 triage are later slices tracked on #9217, each its own PR or recorded as not fixed with a reason. Two are visible from this slice's data: Item F (a per-subtree count pin for the `# sigpipe-demo: intentional` marker; the baseline was 34 marked lines repo-wide at S7a) and the declared affected-edge list for the guard (`scripts/lib/test-affected-paths.sh`), which needs the join's owner suites added by a PR that may edit that file.

## Scope Check

Required on every plan (plan Phase 2.4; halted at deepen-plan 4.12). Asks are quoted from the run's brief (`[brief]`).

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Continue the grep -q pipe-guard series (tracker #9217; also #7376, #6601, #7797, #9482)." [brief] | Overview, Phases 0 to 6 | mapped |
| 2 | "Next: S7c (derivation recall), as its own plan and Guard Contract. Run J0 first." [brief] | Phase 0, `j0-derive.py`, Guard Contract, AC-1 | mapped |
| 3 | "a pipe split over lines by a trailing backslash or pipe (about 24 pairs)" [brief] | R1, Guard 1 (M2, M3, M10, M11) | mapped |
| 4 | "a verb behind timeout/env/command" [brief] | R2, Guard 1 (M5 to M7) | mapped |
| 5 | "a producer other than printf/echo/cat" [brief] | R3, Guard 1 (M8, M9, M12) | mapped |
| 6 | "a library pipe with no pipefail token" [brief] | R4b, Guard 1 (M13, M14); R4a and R4c cut | mapped |
| 7 | "helper-with-argument and loop-built stubs" [brief] | R5a and R5b, Guard 1 (M15, M16) | mapped |
| 8 | "producers in .tf or extensionless files" [brief] | R6 (extension list), Guard 1 (M17); extensionless cut with the measure | mapped |
| 9 | "Each new pair needs a reach classification first." [brief] | Phase 0.2 to 0.5, AC-1, AC-5 | mapped |
| 10 | "the drain window can run into another verb's stub" [brief] | Guard 2 (M26 to M30) | mapped |
| 11 | "the verdicts outside pj_judge and the pj_j merge assignment lack negative controls" [brief] | Guard 3 (M37 to M44) | mapped |
| 12 | "fail-open and fail-closed drain spellings" [brief] | Guard 2 (M32 to M34, M36) | mapped |
| 13 | "the annotation skip drops a real pipe sharing a line with an ::error:: echo" [brief] | Research table; arm R8; Guard 1 (M20 to M22) | mapped |
| 14 | "Then, each as its own PR or recorded as not fixed with a reason: Items D, E, F, G, I, H, the Wave A3 carriers where unblocked, and the #9639/#9638 triage. (Those are LATER PRs; this plan covers S7c only.)" [brief] | Follow-on slices | descoped — justification: the brief itself makes them later slices, listed here and not planned |
| 15 | "Open: #9971 (S7a dissents), #9950 (S6 dissents), and PR #9745's cursor-matcher-parity test line 102, which still has a pipe." [brief] | Premise validation, Not touched, NOT fixed here | mapped |
| 16 | "apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh is red at base — leave it alone." [brief] | Phase 0.3 and 0.5, Files to Edit (never edited), decision-challenges item 6 | mapped |
| 17 | "per PR: an evidence comment on #9217, Ref not Closes, a plain NOT-fixed list, no [skip-deploy-fix-apply], nothing added to plugins/soleur/skills/work/SKILL.md" [brief] | AC-11, AC-12, NOT fixed here | mapped |
| 18 | "keep the PR body free of soak, outage, production and Pro vocabulary and of bullets starting with operator verbs; cite the spec dir's evidence.md, never a plan path containing soak" [brief] | AC-11 | mapped |
| 19 | "mutation batteries run under ulimit -v 6000000, one mutant at a time. Never run a mutant of a signal-sending or file-removing helper outside scripts/soleur-sandbox.sh run-isolated. Never put ulimit -v on the gate" [brief] | Phase 6, AC-7 | mapped |
| 20 | "do not edit: work/SKILL.md, scripts/test-all.sh, scripts/lib/test-affected-paths.sh, scripts/lib/scratch-root.sh, skill-body-budget.json, plan/SKILL.md, any .github workflow, AGENTS*.md" and "leave the main checkout's .mcp.json and the untracked apps/web-platform/1000: and 500 files alone" [brief] | Not touched list | mapped |
| 21 | "before pushing a change that names test or script paths literally inside a suite, run bash scripts/test-affected-kb-consumers.test.sh once (about 95 s)", "the pre-push ratchet lane tests the branch merged with current main", "never write to the repo while a full-gate run is in flight" [brief] | Phase 6, AC-9 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
| --- | --- | --- |
| `j0-derive.py` and `j0-plan-time-output.txt` in the spec dir | "Run J0 first" (ask 2) | asked |
| The base-reproduction check in `j0-derive.py` (BASE must read 66 and 120) | "Run J0 first" (ask 2) | inferred — justification: a measurement script that does not reproduce the guard's own figures cannot attribute an arm's increment; the S7b plan made the same point about its two implementations |
| Arms R1 to R6 | asks 3 to 8 | asked |
| R7, the stub-name defect | "a producer other than printf/echo/cat" and the rest of the list (asks 3 to 8) | inferred — justification: J0 found seven pairs invisible to the guard through one character of a regex; it is the same class (an identifier narrower than the property) and its fixture is the smallest possible, so it ships with the arms rather than as a follow-up |
| Reach probe and the reclassification of the two `blocked-#9956` pairs | "Each new pair needs a reach classification first." (ask 9) and "leave it alone" (ask 16) | asked |
| Guard 2 (window, spellings, `#` in strings) | asks 10 and 12 | asked |
| Guard 3 verdict controls and the `pj_j` pin | ask 11 | asked |
| Permanent annotation fixtures and the `pj_sourced` fixture | ask 13 | asked |
| Derivation fixture suite (Guard 1) | "Guard Contract" (ask 2) | inferred — justification: the derivation's rules were exercised only by the real tree and the battery, so an arm could be narrowed with every row still matching; a must-derive and a must-not-derive case per arm is the contract's own rule for a guard over a derivation |
| `evidence.md`, `decision-challenges.md`, `tasks.md`, `session-state.md` | "a plain NOT-fixed list" and "an evidence comment on #9217" (ask 17) | inferred — justification: the tracker comment cites the spec dir's `evidence.md`, and the pipeline's decision-record contract needs `decision-challenges.md` |
| Follow-on list | ask 14 | asked |

### Split Assessment

- Subsystems touched: up to 6 — `.claude/hooks`, `apps/web-platform`, `plugins/soleur`, `scripts`, `tests`, `.github` (the test script under `.github/scripts/test`), plus the knowledge-base spec dir
- Planned files: 1 guard, up to 69 candidate owner suites (U2; the edit subset is a Phase 0 output, S7b edited 9 of 48), 7 spec artifacts | Estimated changed lines: about 350 added to the guard (arms, fixtures, controls), about 150 table rows, about 5 to 12 per edited suite | about 700 in total
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the root count and the candidate count exceed the thresholds, but the edits are test-side and mechanical and the number that decides (suites needing an edit) is not known until the reach probe runs; Phase 2 orders R3 last and Phase 3 orders non-infra before infra, so a cut at either boundary is free at ship time, and the call is recorded in `decision-challenges.md` if it is made

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC-1 `evidence.md` records, before any owner suite or the guard is edited (the first commit that touches `evidence.md` precedes every other commit's edit of the guard or a suite, `git log --reverse` order): the re-run of `j0-derive.py` with its command and output on the tree merged with main, its BASE line equal to the guard's own pair and triple figures, the reconciliation to the plan-time numbers, the Phase 0.2 classification, the reach table (EXEC, TEXT, UNVERIFIED, BLOCKED, NOTCMD or VARNAMED per pair, with the argv seen), the drain-state table, the Phase 0.5 count of suites needing an edit, and the late-findings table with its commands.
- [ ] AC-2 The red-first run (Phase 1) is recorded: each arm's must-derive fixture reads FAIL by case name, each must-not-derive fixture reads PASS, the cross-verb and fail-open spellings read as drains, and each neutered-verdict control reads RED; the first result of every new check is in `evidence.md`.
- [ ] AC-3 `bash .claude/hooks/grep-q-pipe-guard.test.sh`, run from inside the repo in a checkout with an empty `git status --porcelain` under `ulimit -v 6000000`, exits 0, still prints its twelve `DEFERRED:` lines, prints one `JOINED:` line per `PRODUCER_JOIN` row (`... | grep -c '^JOINED:'` equals the row count: 67 at S7b, the 66 derived pairs plus the variable-named `ssh` row) and its `PASS: grep-q-producer-join` line, on the branch merged with current main.
- [ ] AC-4 The guard's derived pairs AND producer triples at the final configuration equal those `j0-derive.py` prints for the same arms on the same tree: an empty `diff` of the two sorted lists, run once and recorded. The port carries the same exclusions as the awk before the awk is written (YAML block scalars, quote parity on the join and on the any-bar scan, case-pattern alternation, the annotation rule); the only permitted deltas are enumerated in `evidence.md` with the line that explains each, and an unexplained delta fails the criterion. Where they differ the awk is authoritative.
- [ ] AC-5 Every pair classified EXEC is a `drains` row (its stubs verified by Guard 2) or an `exempt` row whose reason cites the evidence; the count of EXEC pairs whose stub lacks a first-statement drain is zero except pairs fenced by the brief (`cloud-init-inngest-bootstrap.test.sh`), which are listed as NOT fixed; every TEXT, UNVERIFIED and BLOCKED pair is an `exempt` row whose reason is a word from the closed vocabulary; the two `blocked-#9956` rows are reworded to a reason that is true at merge.
- [ ] AC-6 Pair run: each edited suite is run at its base commit and at head from real checkouts on the same machine, results compared: pass, fail and assertion counts equal (a difference is a failure of this PR); wall time and `uptime` are context only; a suite red at base for an environmental reason is listed and not edited; the `deploy-script-tests` shards on the PR head are read and any red that main also shows is recorded as pre-existing.
- [ ] AC-7 Mutation rows M1 to M45 and harness rows H1 to H7 (none of them executes an owner suite; each is a read-only edit of the guard, about 15 s a row, run by one scripted harness over a scratch clone) are each graded against the committed guard, one at a time under `ulimit -v 6000000`, each asserting that the mutation landed and that the unmutated control exits 0, a row that executes an owner suite through `scripts/soleur-sandbox.sh run-isolated`, results in `evidence.md`; a row that cannot be run is listed UNVERIFIED with the reason, never counted as passed. M4, M26, M41 and M43 are the four rows that MUST read RED where a stop-at-the-first-member, a same-verb-only window, an unpinned merge, or a first-row-only control would read green; a row counts as graded only when the guard exits non-zero and prints the row's named FAIL substring or fixture case name.
- [ ] AC-8 The dynamic control is recorded: the non-reading stub fails the pipeline under SIGPIPE ignored and under the default (rc 1 or 141 each: an already-ignored signal cannot be reset, so CI reads 1 for both), as a `#!/bin/sh` stub and as a bash stub; each accepted spelling, including the new ones, passes under the interpreter it is tagged for; each non-reading spelling, including `test -t 0 && cat`, `if [ -t 0 ]; then cat; fi` and `cat >/dev/null </dev/null`, fails; the detector and the control agree on every spelling.
- [ ] AC-9 Repo-global lints pass against the branch's base: `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`, `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, `shellcheck -S warning` findings on the guard and every edited suite unchanged from base, `python3 scripts/lint-guard-contract.py` on this plan, `knowledge-base/project/` is excluded from markdownlint by `.markdownlintignore` (the plan, tasks and evidence need no run), `python3 scripts/lint-infra-no-human-steps.py` on the plan, `bash scripts/pre-push-ratchet-lane.sh` on the merged tree, and `bash scripts/test-affected-kb-consumers.test.sh` once before the push (a baseline row only by the gate's own regeneration, for a reference the guard does not read).
- [ ] AC-10 `SWEEP_PROBE_CHECKS` equals `grep -vE '^[[:space:]]*#' .claude/hooks/grep-q-pipe-guard.test.sh | grep -cE '(\|\||&&)[[:space:]]+sweep_probe_fail\+=\('`, the arithmetic (47 at S7b, checks added here) is recorded; `PJ_TRIPLES` is recomputed from a green run; the guard's wall time before and after is recorded plain and under a Check 10-shaped read-only `bwrap` with `uptime` beside each figure; the real run invokes `PJ_AWK` exactly once (`grep -c 'awk "\$PJ_AWK"'` over the non-comment lines outside the fixture driver returns 1), and no per-pair scan of the corpus or per-file process is added.
- [ ] AC-11 PR body: `Ref #9217` (never a closing keyword), a plain NOT-fixed list, a `Filed:` line and a gate-override justification if an issue is filed, Merge Danger (`Undo:` and `Blast Radius:`), Pipeline Tally, Changelog, Model Dissents; cites the spec dir's `evidence.md`, not this plan's path; says the non-test sites are unchanged and only test stubs moved; avoids the barred vocabulary (write "non-test" for the series' older word) and bullets that start with an operator verb; labels per the S5, S6 and S7b convention (`semver:patch`, and `app:web-platform` when an infra suite changed); no `[skip-deploy-fix-apply]`.

### Post-merge

- [ ] AC-12 `soleur:postmerge`: `deploy-arm.sh find --wait <full sha>`, then `served` reads CONTAINS (a tests-only diff may have no deploy for the merge SHA; record what the arm says); when an infra suite changed, read the `Apply web-platform infra` and `Infra Validation` runs for the merge SHA against the known reds (the apply workflow has been red on every main push since 2026-10-11 22:20 UTC from a remote-exec on the egress-gateway host, which has no tracking issue, and `test-all-orphan-log-retention` Part C is timing-flaky; neither is this slice's); then a tracker comment on #9217 with the J0 figures and their command, the before and after `JOINED:` table, the matrix results, the NOT-fixed list, and the next slice named (the tracker is the re-evaluation record; no new issue unless a deferral needs one).

## NOT fixed here (carried into the PR body and the tracker comment)

- Extensionless producers (4 tracked files with a shell shebang, 0 text pipes: measured, cut).
- A bar inside `"$( ... )"` or after an apostrophe inside double quotes (the quote-parity test under-derives); a verb behind a group opener beyond the first word (`printf x | ( umask 077; curl ... )`); a stub two or more hops away; a verb named through a variable (`WEB_HOST_SSH`); a stub built through a helper the definition finder cannot read.
- The fail-closed drain spellings that need a parser: `[ -t 0 ] && true || cat`, a drain followed by a backgrounded `sleep`, a here-string in a command substitution, and a bare `exit` line inside an earlier case arm (use an `arm-drain` row), a `#` inside a string ahead of the drain, and a multi-line `if [ -t 0 ]` / `then` / `cat` spelling that the line-based detector cannot see.
- A count pin for the producer triples survives an add-one-delete-one swap for one pair; `arm-drain`, `pass-through`, `text-only` and `blocked-#N` reasons remain attestations checked for their first word.
- The two `cloud-init-inngest-bootstrap.test.sh` pairs: the file is not edited whatever their class.
- Whatever the reach probe leaves UNVERIFIED (a suite that timed out or needs a host the sandbox does not have), listed as `exempt` rows with their class.
- No ADR for the guard architecture (decision-challenges item 5); the declared affected-edge list for the guard cannot be extended here, so `--affected` runs do not select the guard when only an owner suite changes; CI's full battery does.
- Items D, E, F, G, I and H; the Wave A3 carriers (six carrier rows, 23 hits, gated on a host replace); the #9639 and #9638 triage; the dissent records #9971, #9950 and #10074.
- PR #9745's `cursor-matcher-parity.test.sh` line 102 pipe (another PR's file).

## Test Scenarios

- Given the guard after Phase 2, when a suite stubs `curl` and a non-test script splits `printf ... \` and `| curl -K -` over two lines, then the guard fails naming the suite and `curl` as an unlisted pair, and the derivation fixture `backslash-split` passes.
- Given a stub `curl() { : }` followed by `gh() { cat >/dev/null }`, then the finder reads the `curl` stub as having no drain.
- Given `test -t 0 && cat >/dev/null` as a stub's only drain, then the guard reads it as a non-drain and the dynamic control fails it under both dispositions.
- Given a verdict neutered to `:` with its fault present, then the guard exits 1 through the verdict's control.
- Given a stub written `printf ... > "$d/jq"; chmod +x "$d/jq"` in a suite that names a non-test file piping into `jq`, then the pair derives.
- Given a suite that names a listed non-test file only in a comment, or a pipe inside a quoted string, then no pair derives and the guard stays green.
- Given the repository after Phase 3, when the edited owner suites run, then each suite's result equals its result at its base commit.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan`; this one carries `threshold: none` with a reason.
- The derivation and the fixtures must themselves be pipe-guard clean: read files with `git grep`, a here-string or a process substitution, never `... | grep -q`. A pipe-fed early-exit reader in the guard's own new code would flake the guard it extends.
- The wire pins read the whole file's non-comment lines at column 0: every fixture and message in the new code is indented or built with `printf`, and `SWEEP_PROBE_CHECKS` is recomputed with the header recipe after drafting, never by hand (S7b had to relearn this at each edit).
- `j0-derive.py` is a PORT with a drift check, not the authority: its BASE line must read the guard's figures on the tree being measured; the arm increments are attributable only while it does. Its R3 uses a quote-parity count and a case-pattern exclusion; the awk must match it (AC-4) or the allowlisted delta is explained.
- Naming is not running: a pair the textual join lists is edited only if the reach probe shows the pair EXEC; a TEXT pair is an `exempt` row whose reason cites the probe, not a skipped pair. The reach markers live in scratch copies only; `git diff --stat` on each edited suite is read for added lines that are not the three kinds of edit.
- The sandbox copy has no git tags or history: a suite that needs them is red there for an environmental reason (the `cloud-init-inngest-bootstrap.test.sh` run at plan time failed `GuardA2 ... tag=''`), so it is run in a real local clone, and a red in the copy alone is never read as BLOCKED.
- A drain written as a bare `cat` blocks when a harness leaves stdin open; the canonical form bounds the read with `timeout 2`, but a stub that runs under `env -i` with a PATH farm may not carry `timeout` (S7b's first head run of `cron-egress-nftables` failed 16 assertions on exactly that): use plain `cat` there. `#!/bin/sh` stubs run under dash: `case`, `[ ]` and `cat` only.
- The sweep elsewhere in the guard reads the working tree (`--no-index`); the join reads tracked files only (`git ls-files`), so a mutation that adds a file must `git add` it, and a scratch file left untracked cannot change the join. Run the guard, J0 and the matrix from a clean checkout either way.
- The pre-push ratchet lane runs the guard on the branch merged with current main: a producer main added since the last merge is a new unlisted pair by design (S7b met three), so merge main before reading any run as green, and re-read the derived count after each merge.
- Never put `ulimit -v` on the full gate (it crashes bun and vitest); batteries of shell-only mutants run under it, one at a time, in a scratch clone, and a mutant of a signal-sending or file-removing helper runs only through `run-isolated`. A hook blocks Bash text containing the secrets-CLI verb or the infrastructure-apply verb: write such a command to a file with the Write tool and run it by path.
- A red merge_group run dequeues the PR: read the failing job, re-arm once if it is a flake (`test-all-orphan-log-retention` Part C is timing-flaky), and stop and report if it dequeues twice. A verifier seat whose output file has not moved in 15 minutes is stalled.
