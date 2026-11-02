# Tasks: route a technical decision in a Blocked/Paused closing to the CTO

Plan: `knowledge-base/project/plans/2026-10-26-fix-route-blocked-paused-closings-to-cto-plan.md`
Branch: `feat-one-shot-cto-routing-blocked-paused-closings` | Draft PR: 11254

CTO rulings (2026-10-26, cto_spawns=2 of 2) are in `decision-challenges.md`: A1 label sentence only, A2 one cue `your ruling` in a new function and the tripwire declared
tripped, A3 release by `Operator-only (category):`, B3 and B3c reminder in the model-visible `reason`, C one definition in section 8.1 plus pointers, D ADR-084 addendum.
The plan carries the exact fixtures, anchors, regexes and the REMINDER text; this file is the checklist.

## Phase 0: failing fixtures first (cq-write-failing-tests-before)

- 0.1 `.claude/hooks/pre-closing-technical-fork-gate.test.sh` must-BLOCK rows LB1, LB2, LB3, LB4, LB6, LB7, LB8 (names start with the token; add to `D_NAMES`).
- 0.2 Must-PASS and documenting rows: LP1 (eight categories) and LP1a (two-line shape, label body identical to LB2), LP2 (inline, category money/scope/irreversible/legal-risk, no veto word) and LP2b,
  LP3 and LP3q, LP4-LP4d, LP5b/LP5c/LP5e/LP5d (one veto each), LP6, LP9, LP10, LP10b, LP11 and LP11u, LP12, LP13; ML2 (three lib copies: function missing, phrase emptied, negation emptied,
  each `cmp`-differs, control blocks, copies fail open with the stderr cause); R5; LG2 (ledger cue `label`, hash form, no unit tokens). A8i is not re-added; there is no H5.
- 0.3 Run the suite against the UNCHANGED hook: the must-BLOCK rows red, the must-PASS rows green.
- 0.4 `plugins/soleur/test/ralph-loop.test.sh` RL-B3a and RL-B3b on four fresh state files (iteration 1 and 7, with and without a promise), literal oracle, `print_results <N>`; red against the unchanged hook.
- 0.5 `.claude/hooks/pre-ask-technical-fork-gate.test.sh`: add the two label variables to ML3's loop (one existing row; TOTAL does not move).

## Phase 1: lib and hook

- 1.1 `.claude/hooks/lib/technical-fork-cues.sh`: `TFC_LABEL_PHRASE_ERE`, `TFC_LABEL_NEG_ERE` (one physical line each, column 0), `tfc_is_label_handoff` after `tfc_is_handoff` with `local sentence`
  (phrase gate, EXTRA, BUSINESS, `TFC_CL4_AUTH_RE`, `RULING_PERM_RE`, `TFC_CLOSING_PERM_RE` vetoes each on its own line, negation veto), `tfc_self_check` lines, header note (cue 4 of 6, last,
  next-miss rule, label ledger hash). `_TFC_COMPLETE=1` last; no repo noun on a non-comment line (C2); no comment repeats a mutation anchor.
- 1.2 `.claude/hooks/pre-closing-technical-fork-gate.sh`: pre-filter greps the CL4 candidate and the label phrase; awk `fin_cover` per sentence, END folds `islabel()` of the label body, prints
  `F<cover><TAB><sentence>`; reader `^F[01]` and `F?` strip; `HIT_UNIT`/`HIT_CUE` reset above the label branch; the existing exclusion condition opens a multi-line block (G1-8b re-pinned); cover 1 or no hand-off
  exits 0, else the hit goes to the block output and the judging loops are skipped; reason wording per the plan; header and the "mirrors the plugin hook" comment.
- 1.3 Run the suite: Phase 0 rows green, V1/MIN_CASES not yet moved.

## Phase 2: suite accounting and mutation rows

- 2.1 Mutation rows G1-23 to G1-37 and G1-32b (sixteen) with the anchors in the plan, each asserting its anchor occurs once; G1-8b re-pinned; census row C5.
- 2.2 `V1`'s literal and `MIN_CASES` to the exact new TOTAL (green run) in one edit, the V6 floor to the exact killed count (51 if all sixteen land), `D_NAMES`, the header MUTATION MATRIX comment, the floor shape.
- 2.3 Delete the label branch in a sandbox copy and show LB1 and LB2 red (evidence for the PR body).

## Phase 3: loop reminder

- 3.1 `plugins/soleur/hooks/stop-hook.sh`: single-quoted `REMINDER` (text in the plan), final `jq` builds `reason` as prompt, two newlines, `$rem`; `systemMessage` stays the banner.
- 3.2 `ralph-loop.test.sh`: RL-B3a and RL-B3b green; five mutations red from a mutant tree that mirrors `hooks/` and `scripts/` with a blocking control; the full existing ralph suite green.

## Phase 4: skills

- 4.1 `technical-ruling-delegation.md`: one delta paragraph after 8.1 (heading and pinned sentences byte-identical).
- 4.2 One-shot Step 8 pointer (exact text in the plan; at or under 51996 bytes), go.md Sharp Edge 1 clause, one sentence under the `operator-holds.md` section 2 table, one `plan-sharp-edges.md` bullet.
- 4.3 No diff on `AGENTS.md`, `AGENTS.rules.md`, `ship/SKILL.md`, `plan/SKILL.md`; `git diff origin/main...HEAD -- plugins/soleur/skills | grep -cE '^[-+]description:'` prints 0.

## Phase 5: record

- 5.1 ADR-084 addendum dated 2026-10-26 (about 15 lines): the rulings, an artifact cited for each tripwire miss, the residuals (final sentence only, forged category, veto words and synonyms, first Stop only, the
  unkept-promise hook still exempts and teaches the label), the pre-ask `tfc_self_check` coupling, B3 and the B1 flip condition (founder-reported only), ADR-178 unchanged.
- 5.2 Learning file under `knowledge-base/project/learnings/`, slug `a-label-escape-hid-a-hand-off-the-hook-had-no-phrase-for-and-the-prefilter-never-read`, dated when written.
- 5.3 Re-run the local population differential (base against new hook, labels intact) and record the counts for the PR body.

## Phase 6: gates and ship

- 6.1 Suites and ratchets: hook suite, pre-ask suite, ralph suite, `components.test.ts`, `technical-ruling-gate.test.sh`, `cto-interface-selector.test.sh`, `boundary-prefix.test.sh`,
  `lint-skill-body-budget.py --base origin/main`, `guard-vacuity-floor.test.sh`, shellcheck on the touched shell files, `lint-guard-contract.py`, `fixture-dir-operand-assert.test.sh`,
  `fixture-relative-assert.test.sh`, `.claude/hooks/hook-suite-dep-unresolved.test.sh`, `.claude/hooks/grep-q-pipe-guard.test.sh`, `scripts/lint-trap-tempfile-ownership.test.sh`, `c4-count-parity.test.sh`.
- 6.2 `bash plugins/soleur/scripts/affected-tests.sh` exits 0 (rc 6 is not a pass); it does not select the pre-ask or ralph suites, so their pass lines go in the PR body.
- 6.3 `technical-ruling-gate.sh --branch` exits 0.
- 6.4 PR body: `## Measured` and `## Not measured` with dates, `## Changelog`, `Ruled by CTO agent` lines, no closing keyword.
- 6.5 Merge-queue behind-state: wait for the queue (`ci-head-verdict.sh verdict <PR>`); never hand-sync a queued PR.
