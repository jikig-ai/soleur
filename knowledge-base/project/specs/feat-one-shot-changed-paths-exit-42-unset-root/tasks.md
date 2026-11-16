# Tasks: changed-paths.sh --match no-match exits 42 (unset-root rc 1 fails closed)

Plan: `knowledge-base/project/plans/2026-11-16-fix-changed-paths-no-match-exit-42-plan.md`. Rulings: `decision-challenges.md` in this directory. Every change is RED-first: commit the failing suite rows, then fix. CI required checks are the gate (`ci-is-the-gate`): run single suites only, never the local full battery. Separate `git add` and `git commit`; no `git stash`. Arc tracker `Ref #12246` (never `Closes`); vehicle draft PR #12809.

## Phase 1 - RED: tests (`plugins/soleur/test/changed-path-readers.test.sh`)

- [x] 1.1 Helper rc rows: the two no-match rows want 42 ("--match with no match exits 42 (not 0, not 1)", "--match on an empty diff exits 42"); relabel the "not 1" / "never 1" / "(no match, rc 1)" labels and the row-8 comment to 42.
- [x] 1.2 Executed caller rows in `section_helper`:
  - [x] 1.2.1 Extract the capture lines by handler shape from comment-stripped ship/SKILL.md and counsel-review-clo-attestation.md; assert >= 6 lines and each of the six names exactly once. The floor aborts with `[FATAL] ... exit 1`, never only through `fail`.
  - [x] 1.2.2 Preconditions: host `bash -u` unset root gives rc exactly 1; the injected-unset helper copy (`: "$SOLEUR_INJECTED_UNSET"` after `set -uo pipefail`) exits exactly 1 standalone.
  - [x] 1.2.3 Controls with the real root: A (fixture MODIFYING a non-gated file such as docs/other.md, with a precondition that its plain list is non-empty and matches none of the six patterns -> `[]`), B (fixture adding docs/legal/x.md, knowledge-base/operations/expenses.md, plugins/soleur/skills/gdpr-gate/x.md, knowledge-base/project/specs/fixture/x.txt, apps/x/y; CANONICAL_REGEX/DPF_REGEX=^apps/ -> non-empty, not unknown).
  - [x] 1.2.4 RED rows on the match fixture: R1 (`env -u CLAUDE_PLUGIN_ROOT bash -uc`), R3 (injected-unset copy), R3b (stub that is literally `exit 1`) -> `[unknown]` for every line. Control C-plain (`bash -c`, no `-u`) -> `[unknown]`.
- [x] 1.3 Static pins to `-eq 42` / new phrases: `skill_ship_handler_pin`, the REF_PINS counsel and observability rows, `skill_oneshot_pin`, `skill_fixture` (ship lines, one-shot line, new prose lines), the header comment. Add prose pins for ship's and review's "does not exit 42 (no match)", anchored on the helper line (`--match '^\.github/(workflows|actions)/'` / `--match "$CANONICAL_REGEX"`), not the whole body; move the comment and messages of `skill_oneshot_pin` too.
- [x] 1.4 DEFECTS: move the existing rows' old strings to the new forms; add RED rows (a) dpf_match back to `-eq 1`, (b) counsel back to `-eq 1` (handler fragment only, so AC3's grep stays clean), (c) one-shot back to "exit 2/127", (d) observability back to "exit 2/127", (e) ship notice back to "prints anything or exits 2/127", (f) review trigger back to "exits 0 (a match) or 2/127".
- [x] 1.5 Header PROPERTY (5).
- [x] 1.6 Run `bash plugins/soleur/test/changed-path-readers.test.sh helper` and `... sentinel` on the unfixed tree; record the RED row names for the PR body; commit the RED suite.

## Phase 2 - GREEN: helper

- [x] 2.1 `plugins/soleur/scripts/changed-paths.sh`: the `--match` empty-list arm exits 42; the `PIPESTATUS` mapping (printf failure -> 2, grep 1 -> 42, else pass through); the header CONTRACT; the two stale comments ("read as rc 1" above the pipe; "here-string" in WHY).
- [ ] 2.2 Re-run `... helper`: R2 green, control A RED and R1/R3/R3b red (expected). Do NOT commit this state: the helper edit is committed together with the six handler edits (3.1 handler + 3.2 handlers). (Not run as a separate step: the helper and the handlers were applied together; battery mutations 4 and 5 measure the helper-fixed, handler-unfixed state.)

## Phase 3 - GREEN: consumers

- [x] 3.1 counsel-review-clo-attestation.md: handler -> `-eq 42`; comment "legal_touch=unknown (diff unverifiable) counts as touched".
- [x] 3.2 ship/SKILL.md: 5 handlers -> `-eq 42`; :896 "`unknown` is NOT an edit"; :1050 "`unknown` also fires it (fail closed)"; :1307 "A non-zero exit from the helper = unknown"; :1663 drop " (exit 2/127)" (keep `unverifiable`); :2171 "does not exit 42 (no match)".
- [x] 3.3 review/SKILL.md: :371 rc-contract prose; :124 "If the helper fails (marker printed, file removed)".
- [x] 3.4 one-shot/SKILL.md:179 and observability-coverage-reviewer.md:29: "non-zero exit = ...".
- [x] 3.5 risk-tier-and-fix-rounds.md:57 and adr-ordinal-collision.md:37: trailing comments drop "(exit 2/127)".
- [x] 3.6 Re-run `... helper` and `... sentinel` green. Re-derive `MIN_HELPER_ROWS`, `MIN_TOTAL` (and its breakdown comment) and the `SELFTESTS` equality from a full single-suite run of this file.
- [x] 3.7 Test-file scope grep `grep -n -E '2/127|-eq 1 \]' plugins/soleur/test/changed-path-readers.test.sh` (only DEFECTS new-strings and generic self-tests), `bash scripts/guard-vacuity-floor.test.sh`, `(cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts)`, `python3 scripts/lint-skill-body-budget.py --base origin/main`, and the census greps (plan Phase 3.3).
- [x] 3.8 One-off mutation run of Guard Contract rows 1-12 and H1-H2 on scratch copies; record the results for the PR body.

## Phase 4 - Ride-along KB ticks

- [x] 4.1 Archived remainder plan: tick `- [x] PR body:` (AC 11) and `- [x] Required checks green` (AC 12); leave AC 1 unticked.
- [x] 4.2 Archived remainder tasks.md: `- [x] 5.4 Push`.

## Phase 5 - Ship

- [ ] 5.1 Run the repo meta-guards; push and check the exit code.
- [ ] 5.2 PR body: `Ref #12246`, `Filed: none`, `## Changelog`, `semver:patch`, the RED-first rows, the mutation results, the decision-challenges rulings.
- [ ] 5.3 Required checks green; mark ready; stop at ready-for-merge and report. Do not enqueue, never `--admin`.
