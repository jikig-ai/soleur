# Tasks: route a technical decision in a Blocked/Paused closing to the CTO

Plan: `knowledge-base/project/plans/2026-10-26-fix-route-blocked-paused-closings-to-cto-plan.md`
Branch: `feat-one-shot-cto-routing-blocked-paused-closings` | Draft PR: 11254

CTO rulings (2026-10-26, cto_spawns=2) are in `decision-challenges.md`: A1 label sentence only, A2 one cue
`your ruling` in a new function and the tripwire declared tripped, A3 release by `Operator-only (category):`,
B3 reminder in the model-visible `reason` (B3c), C one definition in section 8.1 plus pointers, D ADR-084 addendum.

## Phase 0: failing fixtures first (cq-write-failing-tests-before)

- 0.1 Add to `.claude/hooks/pre-closing-technical-fork-gate.test.sh` the must-BLOCK rows LB1, LB2, LB3, LB4, LB6, LB7 (verbatim incident closing,
  label sentence alone, bold `**Paused**:`, NBSP, blank-line-separated `Operator-only`, `pending your ruling on which design`) and name each in `D_NAMES`
  (the name starts with the token).
- 0.2 Add the must-PASS rows LP1 (eight categories, one loop case), LP1a, LP2, LP3, LP4 (worded so only the negation veto releases it), LP5b/LP5c/LP5d
  (authorization, permission, closing-extra: one veto each), LP6 (business veto, the CTO's documented residual), LP9, LP10, LP11 (cover then a label sentence
  ending in a question mark; plus a row where the cover is 0 while a neighbour is covered), ML2 (lib without the function or with an empty phrase fails open
  with the stderr cause), R5 (reason wording substring) and H5 (neutered always-block decider reddens the new must-PASS rows). A8i is not re-added.
- 0.3 Run the suite against the UNCHANGED hook and show the new must-BLOCK rows red and the must-PASS rows green.
- 0.4 Add the ralph tests RL-B3a-c to `plugins/soleur/test/ralph-loop.test.sh` and show them red against the unchanged `stop-hook.sh`.

## Phase 1: lib and hook

- 1.1 `.claude/hooks/lib/technical-fork-cues.sh`: `TFC_LABEL_PHRASE_ERE`, `TFC_LABEL_NEG_ERE` (verb-bound negation), `tfc_is_label_handoff` defined after
  `tfc_is_handoff` with `local sentence` (phrase, then EXTRA, BUSINESS, `TFC_CL4_AUTH_RE`, `RULING_PERM_RE`, `TFC_CLOSING_PERM_RE` vetoes on their own lines,
  then the negation veto), extend `tfc_self_check`, header note (cue 4 of 6, last one, next-miss rule). Keep `_TFC_COMPLETE=1` last; no repo noun on a
  non-comment line (row C2).
- 1.2 `.claude/hooks/pre-closing-technical-fork-gate.sh`: pre-filter greps the CL4 candidate and the label phrase; the awk keeps `line_cover`, assigns
  `last_cover` after the while loop, folds `islabel()` of the label body in END and prints `F<cover><TAB><sentence>`; the reader matches `^F[01]` and strips
  `F?`; the label branch keeps the existing `if` line byte-identical and inside it exits on cover 1 or no hand-off, else sets `HIT_UNIT`/`HIT_CUE` (reset moved
  above the branch) and the two judging loops are skipped; reword the reason's last paragraph (no angle brackets, none of promise, operator-gate, done); update the header
  (and the "mirrors the plugin hook" comment, since the plugin hook still exempts the label).
- 1.3 Run the suite: Phase 0 rows green, V1/MIN_CASES not yet moved.

## Phase 2: suite accounting and mutation rows

- 2.1 Add mutation rows G1-23 to G1-33 (label judge, pre-filter parity, carried-over cover, inline `islabel` fold, negation veto, BUSINESS veto,
  authorization veto, the `tfc_self_check` clause via ML2's lib copy, G1-16 driven by LB6, the two permission vetoes, the closing-extra veto); G1-8b's
  anchor stays valid (no re-pin); keep each row's landed/parses/control/differs/no-crash guards; add census row C5.
- 2.2 Set `V1`'s literal and `MIN_CASES` to the exact new TOTAL (from a green run) in one edit, the V6 floor to the exact killed count (46 if all eleven land),
  extend `D_NAMES`, update the header MUTATION MATRIX comment, keep the floor shape for `guard-vacuity-floor`.
- 2.3 Delete the label branch in a sandbox copy and show LB1 and LB2 red (evidence for the PR body).

## Phase 3: loop reminder

- 3.1 `plugins/soleur/hooks/stop-hook.sh`: a single-quoted `REMINDER` (no backticks, apostrophes or angle brackets; names section 8.1); the final `jq` call builds
  `reason` as prompt, two newlines, `$rem`; `systemMessage` stays the banner.
- 3.2 `ralph-loop.test.sh`: RL-B3a-c green on a promise-bearing and a plain state file, iteration 1 and N; five mutations (delete, exit before emit, iteration-2-only,
  move to `systemMessage`, prepend) each red from a mutant tree that mirrors `hooks/` and `scripts/` and whose control blocks first; the full existing ralph suite green.

## Phase 4: skills

- 4.1 `technical-ruling-delegation.md`: one delta paragraph after 8.1 (heading and pinned sentences byte-identical).
- 4.2 One-shot Step 8 pointer with the exact replacement in the plan (428 bytes; file stays at or under 51996 bytes), go.md Sharp Edge 1 clause, one sentence under the
  `operator-holds.md` section 2 table, one `plan-sharp-edges.md` bullet.
- 4.3 Confirm no diff on `AGENTS.md`, `AGENTS.rules.md`, `ship/SKILL.md`, `plan/SKILL.md`; `git diff origin/main...HEAD -- plugins/soleur/skills | grep -cE '^[-+]description:'` prints 0.

## Phase 5: record

- 5.1 ADR-084 addendum dated 2026-10-26, about 15 lines, citing an artifact for each tripwire miss, the question-mark-label edge removed by LP11, the
  pre-ask coupling of `tfc_self_check`, and that the unkept-promise hook still exempts the label.
- 5.2 Learning file under `knowledge-base/project/learnings/`, slug `a-label-escape-hid-a-hand-off-the-hook-had-no-phrase-for-and-the-prefilter-never-read`, dated when written.
- 5.3 Re-run the population differential locally (base vs new hook, labels intact) and record the counts for the PR body.

## Phase 6: gates and ship

- 6.1 Suites and ratchets: hook suite, ralph suite, `components.test.ts`, `technical-ruling-gate.test.sh`, `cto-interface-selector.test.sh`,
  `boundary-prefix.test.sh`, `lint-skill-body-budget.py --base origin/main`, `guard-vacuity-floor.test.sh`, shellcheck on the touched shell files,
  `lint-guard-contract.py`, `fixture-dir-operand-assert.test.sh`, `fixture-relative-assert.test.sh`, `.claude/hooks/hook-suite-dep-unresolved.test.sh`,
  `.claude/hooks/grep-q-pipe-guard.test.sh`, `scripts/lint-trap-tempfile-ownership.test.sh`, `.claude/hooks/pre-ask-technical-fork-gate.test.sh`, `c4-count-parity.test.sh`.
- 6.2 `bash plugins/soleur/scripts/affected-tests.sh` exits 0 (rc 6 is not a pass).
- 6.3 `technical-ruling-gate.sh --branch` exits 0.
- 6.4 PR body: `## Measured` and `## Not measured` with dates, `## Changelog`, `Ruled by CTO agent` lines, no closing keyword.
- 6.5 Merge-queue behind-state: wait for the queue (`ci-head-verdict.sh verdict <PR>`); never hand-sync a queued PR.
