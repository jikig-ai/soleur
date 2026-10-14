# Tasks: S7c derivation recall (tracker #9217, Ref only)

Plan: knowledge-base/project/plans/2026-10-12-chore-grep-q-wave-b-s7c-derivation-recall-plan.md

## Phase 0 J0 (read-only; the first commit that touches evidence.md precedes every edit of the guard or a suite)

- [x] 0.1 Merge current main into the branch. Re-run `ulimit -v 6000000; python3 -I knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-s7c-derivation-recall/j0-derive.py` in a clean checkout; its BASE line must equal the guard's own pair and triple figures on the same tree; compare with `j0-plan-time-output.txt` and explain differences.
- [x] 0.2 Classify each new pair (stdin-reading command or not); give every `exempt` row a closed-vocabulary reason; a new vocabulary word is a decision-challenges entry.
- [x] 0.3 Copy the reach tooling from commit `6e320b391e` (`j0-stubs.py`, `j0-sites.py`, `j0-instrument.py`) into the spec dir; run the reach probe in sandboxes from `scripts/soleur-sandbox.sh new` (markers at every stub a suite owns, one run per suite under `timeout 300` and `ulimit -v 6000000`, `run-isolated`, three at a time) in two tranches: U1's 51 suites first, then the 18 extra suites only the any-producer arm adds (decision-challenges item 24: 69 test files for U2 against 51 for U1) (that arm ships only if tranche 2 completes); a suite that needs tags or history runs in a real local clone. Classes: EXEC, TEXT, UNVERIFIED, BLOCKED, NOTCMD, VARNAMED.
- [x] 0.4 Read each EXEC stub by hand: drain state and consuming flag.
- [x] 0.5 Record the count of suites needing an edit and the infra share; `cloud-init-inngest-bootstrap.test.sh` is never edited.
- [x] 0.6 Re-measure the late #10074 findings on the merged tree (window, verdict controls, spellings, annotation, `pj_sourced`, 1|141, mawk) and record the table with commands.
- [x] 0.7 Write `evidence.md` with 0.1 to 0.6 and commit it first.

## Phase 1 Red first

- [x] 1.1 In the guard: the derivation fixture suite (one case table, one loop, one probe check, through a derive function shared with the real run), the window and spelling fixtures, the verdict controls and the pin on the `pj_j` assignment; run once from a clean checkout under `ulimit -v 6000000`; record each new check's first result in evidence.md.

## Phase 2 Derivation arms and detector fixes (commit order; the last is cuttable)

- [x] 2.1 R7 stub-name strip.
- [x] 2.2 R1 logical-line join over a trailing backslash or pipe (not a block scalar, not inside quotes); R2 wrapper set (`command -v` excluded); R8 annotation strip bounded at its string. Before each arm's rows: one guard run with the arm in and its rows absent, diffed against the arm's increment in `j0-derive.py`.
- [x] 2.3 R4 reverse source map resolved in `END`.
- [x] 2.4 R5a helper arguments; R5b loops; R6 extension list and owner-token pattern.
- [x] 2.5 Guard 2: window bound at any verb's function, helper-call or heredoc opener (not at a data-file write), heredoc terminator and closing brace (one-line stubs included); `test -t 0`, `if ...; then` and input-redirect non-drains; `cat 2>` and `cat -` accepted.
- [x] 2.6 Guard 3: verdict functions with fixture controls; new column-0 pin on the `pj_j` merge assignment.
- [x] 2.7 R3 any-producer scan (quote parity, case-pattern exclusion), last; ships only with every new pair reach-classified (tranche 2).

## Phase 3 Stub edits (hand edits only)

- [x] 3.1 Commit A: owner suites outside `apps/web-platform/infra/`.
- [x] 3.2 Commit B: infra owner suites (plain `cat` where the suite's PATH farm lacks `timeout`).
- [x] 3.3 Each edited stub: flag-keyed drain as the first statement; one wire assert per drained pair with the `${KNOB:-default}` form; `git diff --stat` shows only those edits and no reach marker.

## Phase 4 Rows

- [x] 4.1 One `PRODUCER_JOIN` row per new pair, rows sorted by (suite, verb); the `unlisted pair` message names the producer file(s); recompute `PJ_TRIPLES` and `SWEEP_PROBE_CHECKS` from a green run with the header recipe; reword the two `blocked-#9956` rows to a true reason.

## Phase 5 Wording

- [x] 5.1 Rewrite the guard header's STATED LIMITS to the S7c state; list the follow-on slices; do not write that the series is finished.

## Phase 6 Evidence and ship

- [x] 6.1 Mutation rows M1 to M46 and harness rows H1 to H7, one at a time under `ulimit -v 6000000` on a scratch clone, each asserting the mutation landed and the control is green; owner-suite rows through `run-isolated`.
- [ ] 6.2 Pair run of each edited suite at base and head from real checkouts; lints (plan AC-9); `bash scripts/test-affected-kb-consumers.test.sh` once before the push; pre-push ratchet lane on the merged tree.
- [x] 6.3 decision-challenges.md update; learning if a non-obvious finding occurs.
- [ ] 6.4 PR body per AC-11; `soleur:ship`; post-merge per AC-12 (tracker comment with J0 numbers and command, NOT-fixed list, next slice named).
