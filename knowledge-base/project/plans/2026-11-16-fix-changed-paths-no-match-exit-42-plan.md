---
title: "fix: changed-paths.sh --match reports no-match as exit 42 so an rc 1 from an unset root fails closed"
type: fix
date: 2026-11-16
slug: fix-changed-paths-no-match-exit-42
branch: feat-one-shot-changed-paths-exit-42-unset-root
issue: none
closes: none
priority: p2
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
lane: cross-domain
---

## Overview

The `--match` mode of `plugins/soleur/scripts/changed-paths.sh` reports "none of the changed paths match" as exit 1. Bash returns the same code when the caller's own line dies on an unbound variable under `set -u` (for example an unsubstituted `${CLAUDE_PLUGIN_ROOT}`), and when the helper itself trips an unbound variable. Every `--match` caller reads rc 1 as "no match", so those failures silently skip the gate they guard. The counsel-review `legal_touch` check is the sharpest instance: a failed diff skips CLO counsel review instead of firing it.

This plan moves the no-match outcome to a dedicated exit code, 42, following the ship `battery-owed.sh` exit-42 precedent. Every consumer of the exit code moves with it, so rc 1 lands in the fail-closed `unknown` arm. Vehicle: draft PR #12809. Arc tracker: `Ref #12246` (a merged PR used as the changed-path-readers arc tracker; there is no open issue to close, so there is no `Closes`).

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (verified 2026-11-16) | Plan response |
|---|---|---|
| Unset root under `set -u` makes the invocation die with rc 1 | Measured on GNU bash 5.3.20: `env -u FOO bash -uc 'x=$(bash "${FOO}/a.sh") \|\| echo rc=$?'` prints `rc=1` and the parent shell survives. A script with an unbound variable also exits 1. An empty (set but empty) root gives `bash "/scripts/x.sh"` = rc 127. | Holds. Precondition rows pin rc 1 on the host bash, so the RED-first rows cannot pass vacuously on a bash that answers 127. |
| Six callers: counsel `legal_touch` plus five sites in ship/SKILL.md | Exactly six `[ $? -eq 1 ]` capture lines: ship/SKILL.md `ledger_touched`, `gdpr_gate_touch`, `diff_match`, `dpf_match`, `plan_refs`, plus counsel `legal_touch`. | Holds. |
| "grep the whole repo for every other consumer" | The only consumers are Markdown prose under `plugins/soleur/` and `plugins/soleur/test/changed-path-readers.test.sh`. `scripts/lib/test-affected-paths.sh:1308` only maps the path for affected-test selection. No hook, workflow, TS or Python reads the exit code: workflows and hooks use the inline form by design (helper header). Prose consumers found beyond the six: two direct `--match` prose consumers (ship Phase 7 UNTRUSTED-CI notice; review gdpr-gate trigger), three plain-mode prose consumers that name only `2/127` (one-shot scope check, observability-coverage-reviewer inventory, ship PIR meta-case), and seven code-backed annotations that name `2/127` (ship 896/1050/1663, counsel comment, review:124, risk-tier:57, adr-ordinal:37). | All in scope per CTO rulings Q1-Q3 and Q6 (see `decision-challenges.md`). |
| "about 35 lines / 5 files" | 10 source files plus 2 KB ride-along files; about 95 changed lines, about 60 of them in the test file. The extra files are the prose consumers the brief's own sweep instruction requires. | Accepted. Still well inside the split thresholds (see Scope Check). |
| ship/SKILL.md has ~73 bytes of headroom | 273955 ceiling minus 273882 bytes = 73 (`plugins/soleur/test/skill-body-budget.json`; `scripts/lint-skill-body-budget.py` compares `st_size`, whole file). one-shot has 32 bytes (52000 - 51968); review has 1531 (475921 - 474390). | Holds. The ship diff is net negative, about -30 bytes (see Byte Budget). |
| Ride-along KB lines exist | Archived plan line 384 `- [ ] PR body:` (AC 11), line 385 `- [ ] Required checks green` (AC 12), line 374 `- [ ] Every site ...` (AC 1, stays unticked). Archived tasks.md line 51 `- 5.4 Push (real exit code), ...`. | Holds. |

## Problem Statement

The current caller idiom is:

```bash
legal_touch=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh" --match '<ERE>' origin/main...HEAD) || { [ $? -eq 1 ] || legal_touch=unknown; }
```

It sorts outcomes into match (rc 0), no match (rc 1), and unknown (anything else). Three distinct failures collapse into the rc 1 bucket:

1. The caller's `${CLAUDE_PLUGIN_ROOT}` is unbound under `set -u`. The command substitution's subshell exits 1 before the helper runs. This is the live case for Read-not-loaded reference files such as `counsel-review-clo-attestation.md`, whose root the skill loader does not substitute.
2. The helper itself trips an unbound variable (it runs `set -uo pipefail`) and exits 1.
3. Any other shell-level failure that bash reports as 1.

In every case `legal_touch` stays empty and the counsel gate reads "no legal doc touched", so it does not fire. Plain-mode prose consumers have the same hole in another form: rc 1 with an empty stdout reads as an empty list, which is "vacuously in scope" for the one-shot scope check and "vacuously contained" for the ship PIR meta-case.

This exact collision was recorded in `knowledge-base/project/learnings/2026-11-08-converting-changed-path-readers-moved-the-failure-to-newline-names-and-to-the-prose-that-calls-the-helper.md`. The fix adopted there was `${CLAUDE_PLUGIN_ROOT:-}`, which turned an unset root into rc 127. The remainder PR (#12494, 53efc49758) then removed the `:-` arm, which `plugin-root-anchoring.test.ts` and the `skill_ref_pin` `:-`-absent check now forbid. That reopened case 1, and case 2 was never covered.

## Proposed Solution

Give "no match" an exit code that bash never produces by itself, and make every consumer test for that code alone.

1. **Helper** (`plugins/soleur/scripts/changed-paths.sh`):
   - The `--match`-only empty-list arm `[ -n "$out" ] || exit 1` becomes `exit 42`. It sits after the plain-mode `exit 0`, so plain mode can never exit 42; the existing helper row "an empty diff exits 0" pins that.
   - The final `grep` maps only grep's own exit 1 to 42. It reads `PIPESTATUS` on the statement right after the pipeline: a `printf` failure becomes 2 (unknown), grep's 1 becomes 42, and every other grep status passes through unchanged (2 = bad ERE, 128+n = signal).

     ```bash
     printf '%s\n' "$out" | LC_ALL=C grep -E -e "$match"
     st=("${PIPESTATUS[@]}")
     [ "${st[0]}" -eq 0 ] || exit 2
     [ "${st[1]}" -ne 1 ] || exit 42
     exit "${st[1]}"
     ```

   - Header CONTRACT: `--match ERE  0 = at least one path matches (printed), 42 = none match, 2 = git or usage failure.` Add one sentence on why it is 42 and not grep's 1 (bash exits 1 on an unbound variable, in the caller or here), and that callers test `[ $? -eq 42 ]` and treat every other non-zero rc as unknown. In the same edit, fix two stale helper comments (named by text, not line): the comment above the final pipe, "an unwritable TMPDIR would skip grep entirely and read as rc 1", becomes "... read as 42"; and the WHY paragraph's "then grep reads a here-string" becomes "then grep reads it through a pipe from printf", which is what the code does. (The "row 8" comment is in the test file and is covered by Phase 1.1.)
   - Plain mode is unchanged: 0 = list, any non-zero = not a list.
2. **Six capture lines**: `[ $? -eq 1 ]` becomes `[ $? -eq 42 ]` (counsel `legal_touch`; ship `ledger_touched`, `gdpr_gate_touch`, `diff_match`, `dpf_match`, `plan_refs`).
3. **Direct `--match` prose consumers**:
   - ship/SKILL.md Phase 7 UNTRUSTED-CI notice: "prints anything or exits 2/127" becomes "does not exit 42 (no match)" (Q1).
   - review/SKILL.md:371 gdpr-gate trigger: "exits 0 (a match) or 2/127 (unknown: treat as a match)" becomes "does not exit 42 (no match): 0 is a match and any other exit is unknown, so treat both as a match".
4. **Plain-mode prose consumers** (Q3): `exit 2/127` becomes `non-zero exit` in one-shot/SKILL.md:179, observability-coverage-reviewer.md:29 and ship/SKILL.md:1307.
5. **Code-backed annotations** (Q2, Q6): delete the exit-code list and keep the value or marker.
   - ship:896 becomes "`unknown` is NOT an edit".
   - ship:1050 becomes "`unknown` also fires it (fail closed)".
   - ship:1663 becomes "Any hit or `unverifiable` ⇒ ..." (only " (exit 2/127)" is deleted; `unverifiable` is the marker the line above prints, CTO Q2b).
   - The counsel comment becomes "legal_touch=unknown (diff unverifiable) counts as touched".
   - review:124 becomes "If the helper fails (marker printed, file removed)".
   - risk-tier:57 becomes "# unknown: skip the script, spawn the full class panel".
   - adr-ordinal:37 becomes "# list unknown: sweep every tracked file, never an empty list".
   - review/SKILL.md:114 "rc 2 on failure" stays: it describes the helper and is still true.
6. **Tests** (`plugins/soleur/test/changed-path-readers.test.sh`), written RED-first. See Implementation Phase 1.
7. **Ride-along KB ticks** (no code). See Implementation Phase 4.

### Byte Budget (ship/SKILL.md, ceiling 273955, now 273882)

| Edit | Delta (bytes, approx.) |
|---|---|
| 5 x `-eq 1` -> `-eq 42` | +5 |
| :2171 "prints anything or exits 2/127" -> "does not exit 42 (no match)" | -3 |
| :896 drop " (exit 2/127)" | -13 |
| :1050 drop " (rc 2/127)" | -11 |
| :1663 drop " (exit 2/127)" (keep `unverifiable`, Q2b) | -13 |
| :1307 "Exit 2/127" -> "A non-zero exit" | +5 |
| **Net** | **about -30 -> about 273852** |

one-shot/SKILL.md: +3 bytes, about 51971 against 52000. review/SKILL.md: about +33 bytes (the :371 rewrite adds ~41, dropping "rc 2/127; " at :124 saves ~10), against 1531 of headroom. Measure the real figures with `wc -c` at work time. The lint is the authority: `python3 scripts/lint-skill-body-budget.py --base origin/main`.

## Research Insights

**Premise Validation.**

- #12246: MERGED PR ("feat(ship): a brief's ci-is-the-gate constraint reaches ship Phase 4"), used as the arc tracker by the remainder plan. `Ref` is correct and there is nothing to close.
- #12332: CLOSED.
- 53efc4975872 (#12494) is an ancestor of HEAD.
- Draft PR #12809 is OPEN on this branch.
- Collision pre-check (`collision-precheck.sh 12246`): `prs=none`. The only foreign rows are three `test-all.sh` processes owned by the unrelated `feat-one-shot-11556-epic-ac-chain` worktree, so this is not duplicate work.
- No mechanism in the ask sits in an ADR's rejected-alternatives table. The exit-42 precedent is live code in ship/SKILL.md Phase 4 (`battery-owed.sh`, `if [[ "$rc" -eq 42 ]]`).

**Property List.**

- P1: a `--match` capture line yields `unknown` for every helper outcome except a real match or a real no-match.
- P2: the helper's no-match exit is a code that no shell-level failure (unbound variable, missing file, signal) can produce.
- P3: every prose consumer of the helper's exit code, in both modes, treats exactly the defined success codes as success and everything else as unknown.
- P4: the suite proves P1 by executing the real capture lines from the files that ship, not a regex over their spelling.

**Cut List.**

- `${CLAUDE_PLUGIN_ROOT:-}` (unset root -> rc 127). Buys P1 for case 1 only. Already removed by #12494 and forbidden by `plugin-root-anchoring.test.ts` and the `skill_ref_pin` `:-`-absent check, and it leaves case 2 (unbound variable inside the helper, rc 1) open. Cut.
- A resolve-root preamble in each reference file. The counsel reference already carries the plugin-root notice; adding more prose buys nothing P1-P4 need. Cut.

**Value-proposition measurement.** Not applicable: the plan's case is correctness (fail closed), not a cost saving.

**Learnings applied.**

- `knowledge-base/project/learnings/2026-11-08-converting-changed-path-readers-moved-the-failure-to-newline-names-and-to-the-prose-that-calls-the-helper.md`: names the rc-1 collision; the earlier `:-` fix was later removed.
- `knowledge-base/project/learnings/2026-11-10-converting-the-remaining-changed-path-readers-each-fix-needed-a-locale-registry-or-premise-proof.md`: execute the extracted line rather than pin its spelling. This is why the Q4 rows execute.
- `knowledge-base/project/learnings/best-practices/2026-07-03-enforcement-probe-must-discriminate-exit-codes-not-any-failure-as-safe.md`: only the specific verdict code counts.
- `knowledge-base/project/learnings/2026-11-06-a-nine-seat-review-and-a-16-mutant-battery-both-missed-what-a-fresh-verifier-found.md`: the origin of the exit-42 precedent; git's rc 1 overloading "absent" and "corrupt" is the same class.
- `knowledge-base/project/learnings/2026-09-23-compressing-prose-to-fit-a-byte-ceiling-dropped-the-conditions-that-made-it-correct.md`: the ship edits are net negative by deleting exit-code lists, not by compressing conditions. Q1 keeps the "(no match)" gloss for that reason.

**Sharp Edges catalogue entries applied.** Every negative row gets a positive control on the same input, because an `expect rc 1` row passes on an unreadable file. A fail-closed change must also refuse its most natural repair: an agent seeing `legal_touch=unknown` may "repair" it by exporting the checkout's own `plugins/soleur` as the root. The counsel reference's plugin-root notice already forbids that, and this plan adds no new refusal that needs its own repair check.

**CLAUDE.md conventions.** The helper is called from skill prose with the exact call form `bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh"` (pinned by `skill_spelling_pin`). Workflows and hooks stay inline. Rule ids are immutable. CI's required checks are the gate (`ci-is-the-gate`). Separate `git add` and `git commit`. No `git stash`.

**Relevant file:line anchors.**

- Helper exits: `changed-paths.sh` `[ -n "$out" ] || exit 1` and the final `printf | grep; exit $?`.
- Caller pins in the test file: `skill_ship_handler_pin` (`-eq 1` regex), the `REF_PINS` counsel and observability rows, `skill_oneshot_pin`, `skill_fixture`, and the DEFECTS rows. Helper rc rows: "--match with no match exits 1 (not 0)" and "--match on an empty diff exits 1".

## Files to Edit

| File | Change |
|---|---|
| `plugins/soleur/scripts/changed-paths.sh` | No-match -> 42 (both arms), `PIPESTATUS` mapping, header CONTRACT, two stale comments |
| `plugins/soleur/skills/ship/references/counsel-review-clo-attestation.md` | `legal_touch` handler -> `-eq 42`; comment drops "exit 2/127" |
| `plugins/soleur/skills/ship/SKILL.md` | 5 handlers -> `-eq 42`; :896, :1050, :1663 (drop "(exit 2/127)") annotations; :1307 "non-zero exit"; :2171 "does not exit 42 (no match)" |
| `plugins/soleur/skills/review/SKILL.md` | :371 rc-contract prose; :124 marker wording |
| `plugins/soleur/skills/one-shot/SKILL.md` | :179 "non-zero exit = scope unverified: treat as a breach" |
| `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md` | :29 "non-zero exit = inventory unknown" |
| `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md` | :57 trailing comment |
| `plugins/soleur/skills/ship/references/adr-ordinal-collision.md` | :37 trailing comment |
| `plugins/soleur/test/changed-path-readers.test.sh` | rc-1 pins -> 42; new executed caller rows; new prose pins; new DEFECTS rows; header PROPERTY (5) |
| `knowledge-base/project/plans/archive/20261110-140832-2026-11-09-fix-convert-remaining-changed-path-readers-plan.md` | Tick AC 11 and AC 12 only |
| `knowledge-base/project/specs/archive/20261110-140832-feat-one-shot-changed-path-readers-remainder/tasks.md` | `- 5.4 Push` -> `- [x] 5.4 Push` |

No files to create, apart from this feature's own `knowledge-base/project/specs/feat-one-shot-changed-paths-exit-42-unset-root/` artifacts (`tasks.md`, `decision-challenges.md`). No `description:` frontmatter is edited, so the skill-description word budget does not apply.

## Implementation Phases

### Phase 1 — RED: tests first (`plugins/soleur/test/changed-path-readers.test.sh`)

1.1 **Helper rc rows (R2).**

- "--match with no match exits 1 (not 0)" becomes `... exits 42 (not 0, not 1)` with want 42.
- "--match on an empty diff exits 1" becomes 42.
- Relabel "an injected git failure exits 2, not 1" to "not 42", "never 1 (none match)" to "never 42", and "(no match, rc 1)" to "(no match, rc 42)". Update the row-8 comment.
- The generic `h_expect_rc` / `h_expect_refused` self-tests that use 1 and 2 as arbitrary values stay.

1.2 **Executed caller rows (R1, R3; CTO Q4).** These go in `section_helper`, so the `helper` selector runs them.

- **Extract.** Take every line of the comment-stripped `ship/SKILL.md` and `counsel-review-clo-attestation.md` that matches the handler shape `^[a-z_]+=\$\($RX_CALL --match .+\) \|\| \{`. Assert the line count is >= 6 and that each of `legal_touch ledger_touched gdpr_gate_touch diff_match dpf_match plan_refs` is found exactly once. The floor is not an exact ceiling: a seventh capture line gets executed too.
- **Fixtures.** Reuse `new_row` / `commit_row` (the template's `origin/main` already exists in each row clone). Use one row for control A, and one for control B plus the RED rows.
  - Control A must MODIFY a non-gated template file (for example `docs/other.md`). `commit_row` uses `--allow-empty`, so an empty commit would send the helper through its empty-list branch and grep would never run; mutation row 2 could then not reach control A.
  - Add a precondition that control A's plain-mode list is non-empty and matches none of the six patterns.
- **Runner.** For each line with variable `v`, in a scratch fixture, run `env <ENV> CANONICAL_REGEX=<ere> DPF_REGEX=<ere> bash -uc "$line"'; printf "[%s]" "${'"$v"'}"'`. Capture stdout and assert the exact bracketed value.
  - Read the two source files from `$REPO_ROOT` directly. Do not go through `skill_body` / `SKILL_ROOT`, which the sentinel self-tests repoint at synthetic trees. Define the extraction ERE locally rather than relying on the top-level `RX_CALL` defined further down the file, so the rows stay correct if the section order changes.
  - On a control failure, name the extracted line and say "extend fixture B / the runner env". A legitimate seventh capture line with a new ERE or a new `$*_REGEX` will fail controls A/B until the fixture grows, and that must not read as a handler regression.
- **Preconditions (load-bearing, otherwise the RED-first rows can pass vacuously):**
  - On the host bash, `env -u CLAUDE_PLUGIN_ROOT bash -uc 'x=$(bash "${CLAUDE_PLUGIN_ROOT}/x") || exit $?'` exits exactly 1, not 127.
  - The injected-unset helper copy, run standalone, exits exactly 1. Build it as a copy of the real helper under `$WORK_ROOT/stubroot/scripts/changed-paths.sh` with `: "$SOLEUR_INJECTED_UNSET"` inserted on the line after `set -uo pipefail`, run with `env -u SOLEUR_INJECTED_UNSET`.
- **Must-PASS controls** (real root `CLAUDE_PLUGIN_ROOT=$REPO_ROOT/plugins/soleur`):
  - (A) No-match fixture (nothing under any of the six surfaces; `CANONICAL_REGEX`/`DPF_REGEX` = `^zzz-never/`): every line yields `[]`.
  - (B) Match fixture: one diff touching `docs/legal/x.md`, `knowledge-base/operations/expenses.md` (ADDED in the fixture PR: `build_template` does not seed it, and `--diff-filter=AMT` includes `A`), `plugins/soleur/skills/gdpr-gate/x.md`, `knowledge-base/project/specs/fixture/x.txt` and `apps/x/y`, with `CANONICAL_REGEX`/`DPF_REGEX` = `^apps/`. Every line yields a non-empty value that is not `unknown`.
- **RED rows:**
  - (R1) `env -u CLAUDE_PLUGIN_ROOT` on the match fixture: every line yields `[unknown]`.
  - (R3) `CLAUDE_PLUGIN_ROOT=$WORK_ROOT/stubroot` (the injected-unset helper copy): every line yields `[unknown]`.
  - (R3b, hermetic) `CLAUDE_PLUGIN_ROOT=$WORK_ROOT/stub1root`, whose `scripts/changed-paths.sh` is literally `exit 1`: every line yields `[unknown]`. This row states the contract ("rc 1 is unknown") without depending on how the host bash reports an unbound variable, so it stays RED-first even if a future bash answers 127 there.
  - (C-plain, control) `env -u CLAUDE_PLUGIN_ROOT bash -c` (no `-u`): every line yields `[unknown]`, since the root expands empty and the helper path is missing (rc 127). Measured on today's tree for the counsel line: `[unknown]`. It passes before and after the fix and guards the case where the shell running skill prose has no `set -u`.
- R1, R3 and R3b run on the MATCH fixture, so an `unknown` cannot be confused with an empty no-match. Today they print `[]`, because rc 1 is read as no match.
- **Measured on today's tree.** Scratch repo with a `docs/legal/x.md` change, counsel line: R1 under `bash -uc` yields `[]` (RED-first confirmed), C-plain yields `[unknown]`, and control B yields `[docs/legal/x.md]`. Plan review independently ran all six lines and got R1 = R3 = `[]` today, and `[unknown]` for R1/R3/R3b/C-plain against a patched helper with `-eq 42` callers.

1.3 **Static pins (lockstep).**

- `skill_ship_handler_pin`: both regexes and the pass message go to `-eq 42`.
- `REF_PINS`: in the counsel row, shape, arm and fixture go to `-eq 42`. In the observability row, arm and fixture become `non-zero exit = inventory unknown`.
- `skill_oneshot_pin`: becomes `non-zero exit = scope unverified: treat as a breach`.
- `skill_fixture`: the five ship lines go to `-eq 42`, and the one-shot fixture line moves to the new phrase.
- Header comment line "ship ... keeps `|| { [ $? -eq 1 ] || VAR=unknown; }` (rc 1 = no match ...)" becomes 42.
- New prose pins, anchored on the helper line (the `skill_oneshot_pin` shape, per `cq-assert-anchor-not-bare-token`), never on the whole file body. Each needs a matching `skill_fixture` line.
  - In `skill_ship_semantics_pin`: select the comment-stripped line holding `--match '^\.github/(workflows|actions)/'` (it occurs only at the Phase 7 notice), then require `does not exit 42 (no match)` on that line.
  - In `skill_review_pin`: select the line holding `--match "$CANONICAL_REGEX"` (it occurs once in review/SKILL.md), then require `does not exit 42 (no match)` on that line.
- The comment above `skill_oneshot_pin` ("the failure arm is prose: exit 2/127 is a breach") and that pin's pass/fail messages move to the new phrase too.

1.4 **DEFECTS rows (CTO Q5).**

- Move the four existing rows' old strings to the `-eq 42` forms.
- Move the one-shot breach-arm row and the observability row to the new phrases.
- Add RED rows:
  - (a) `{ [ $? -eq 42 ] || dpf_match=unknown; }` -> `{ [ $? -eq 1 ] || dpf_match=unknown; }`
  - (b) the counsel handler back to `-eq 1`. Write the old and new strings as the handler FRAGMENT only (`|| { [ $? -eq 42 ] || legal_touch=unknown; }` -> `... -eq 1 ...`), like the existing counsel rows. A full `changed-paths.sh" --match ... -eq 1` line in the test file would make AC3's grep fail on a correct tree.
  - (c) one-shot back to `exit 2/127 = scope unverified: treat as a breach`
  - (d) observability back to `exit 2/127 = inventory unknown`
  - (e) the ship notice back to `prints anything or exits 2/127`
  - (f) the review trigger back to `exits 0 (a match) or 2/127`

1.4b **Floors (exact counts, same diff).** The suite's bottom-of-file floors are exact full counts, not margins: `MIN_HELPER_ROWS=109`, `MIN_TOTAL=415` (its comment reads "helper 109 + steps 187 + sentinel 119"), and the equality `[ "$SELFTESTS" -ne 68 ]`. Every new executed row counted through `h_ok` / `h_bad`, every new `pass` / `fail`, and every new DEFECTS row (each calls `selftest_skill_tree`, which increments `SELFTESTS`) moves them. Re-derive all three from a full-suite run of THIS file (`bash plugins/soleur/test/changed-path-readers.test.sh`, a single suite, not the battery), and update the numbers and the `MIN_TOTAL` breakdown comment in the same commit. The new `>= 6` extraction floor must abort on its own path (`printf '[FATAL] ...' >&2; exit 1`, the shape of the existing floors and self-tests), never only through `fail`, with any subtrahend written as a literal directly above the `if`. Then run `bash scripts/guard-vacuity-floor.test.sh`, the meta-guard that builds a neutered mutant of every counter floor; see work SKILL.md 6.7.

1.5 **Header PROPERTY.** Add (5): "a `--match` no-match is exit 42, so a shell-level rc 1 (an unbound variable under `set -u`, in the caller or the helper) is unknown, never no match".

1.6 Run `bash plugins/soleur/test/changed-path-readers.test.sh helper`. This is one suite section, not the battery. Record the RED rows (the names failing on the unfixed tree) for the PR body. The prose pins live in the sentinel section, so run `... sentinel` too and record its RED pin and DEFECTS rows.

### Phase 2 — GREEN: helper

2.1 Edit `changed-paths.sh` per Proposed Solution 1. Re-run `... helper`.

- Expected intermediate state: R2 goes green. Control A goes RED, because the helper now returns 42 while the callers still test `-eq 1`, so every line yields `[unknown]`. R1, R3 and R3b stay red.
- That intermediate tree is the reverse regression (every `--match` gate fires on every PR), so it must never be committed. **The helper edit and the six handler edits (counsel plus the five ship handlers, Phase 3.1-3.2) land in ONE commit.** Only the Phase 1 RED suite is committed before them.

### Phase 3 — GREEN: consumers

3.1 Counsel reference, then ship/SKILL.md (5 handlers + 5 prose edits), review/SKILL.md (2), one-shot/SKILL.md, observability-coverage-reviewer.md, risk-tier-and-fix-rounds.md, adr-ordinal-collision.md.

3.2 Re-run `... helper` and `... sentinel`: all green. Then run the two neighbouring guards that read the same prose:

- `bun test plugins/soleur/test/plugin-root-anchoring.test.ts` (the `:-` ban)
- `python3 scripts/lint-skill-body-budget.py --base origin/main`

3.3 Census check (residual zero):

- `git grep -n -E '\[ \$\? -eq 1 \]' -- plugins/soleur/skills plugins/soleur/agents` returns no changed-paths line.
- `git grep -n '2/127' -- plugins/soleur ':!plugins/soleur/test' ':!plugins/soleur/agents/engineering/review/test-design-reviewer.md'` returns nothing. (`test-design-reviewer.md:146` talks about mutation-harness exit codes, not this helper, and is out of scope.)
- Test-file scope (AC4 excludes the test file): `grep -n -E '2/127|-eq 1 \]' plugins/soleur/test/changed-path-readers.test.sh` hits only the new-string column of the restore DEFECTS rows (a)-(f) and the generic `h_expect_rc` / `h_expect_refused` self-tests. No pin, fixture line, comment or message keeps the old contract.

### Phase 4 — Ride-along KB ticks

4.1 In the archived remainder plan, change `- [ ] PR body:` to `- [x] PR body:` (AC 11) and `- [ ] Required checks green` to `- [x] Required checks green` (AC 12). AC 1 (`- [ ] Every site in the final convert set ...`) stays unticked. These are CTO-verified as satisfied by the merge and deploy evidence.

4.2 In the archived remainder tasks.md, change `- 5.4 Push` to `- [x] 5.4 Push`.

### Phase 5 — Ship constraints (carried to work/ship)

- Run the repo meta-guards before pushing.
- Separate `git add` and `git commit`. Check the push exit code. No `git stash`.
- CI's required checks are the gate (`ci-is-the-gate`): do not run the local full battery.
- PR body: `Ref #12246` (never `Closes`), a `## Changelog` section, label `semver:patch`, the RED-first row names from 1.6, and the `decision-challenges.md` rulings.
- Merge: `allow_auto_merge=false`, and enqueue authorisation does not carry over. Stop at ready-for-merge and report. Do not enqueue, never `--admin`.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| `${CLAUDE_PLUGIN_ROOT:-}` at every call site (unset -> 127) | Removed by #12494 and banned by `plugin-root-anchoring.test.ts` and the `:-`-absent pin. Covers only the caller-side unset root, not an unbound variable inside the helper (rc 1). |
| Callers test `[ $? -eq 1 ] && [ -z "$out" ]` | An unset root also leaves stdout empty, so it does not discriminate. |
| A new exit code other than 42 | 42 is the established "deliberate non-failure verdict" code in ship (battery-owed.sh). Reusing it costs no new vocabulary. Ruled by the CTO. |
| Counsel-only executed row | Ruled out by CTO Q4: the defect is per call site, and five ship handlers would stay unexecuted. |
| Leave plain-mode prose for a follow-up | Ruled out by CTO Q3: it knowingly ships a skipped-PIR / vacuous-scope fail-open on a gate path. |

No deferrals, so no tracking issue is filed (`Filed: none`).

## Open Code-Review Overlap

None. 96 open `code-review` issues were checked against every planned path (and the bare token `changed-paths`); no body names any of them.

## User-Brand Impact

- **If this lands broken, the user experiences:** a ship run on their repository that silently skips a gate it should have fired: CLO counsel review on a legal-document change, gdpr-gate, the data-processing-flow gate, the vendor-expense ledger check, or the `Closes` -> `Ref` downgrade. A regression in the other direction (exit 42 misread) would fire those gates on every PR and spend extra review cost.
- **If this leaks, the user's workflow is exposed via:** a legal document or regulated-data change merged without the attestation step that `soleur:ship` promises. No data leaves the user's machine: the helper is local, layer 7.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the failure needs a specific shell condition (`set -u` with an unsubstituted root, or a helper defect) to coincide with a gated change, and it yields a skipped review rather than a data exposure. That is a pattern-level trust erosion, not a single-user breach. It matches the threshold the rest of the changed-path-readers arc used.

## Observability

Layer citation: every failure mode below is **layer 7 (`cli-stdout-artifact`)**. The helper and its prose callers run on the customer's own CLI, and the signal is the tool-result stdout or stderr read in-session, plus the CI `test` check for regressions. There is no Soleur-side sink, and by design there must not be one.

```yaml
liveness_signal:
  what: plugins/soleur/test/changed-path-readers.test.sh helper and sentinel sections (executed caller rows plus static pins) in the required CI test check
  cadence: per-PR (every PR whose diff selects the suite via scripts/lib/test-affected-paths.sh, and every full-battery run)
  alert_target: the required CI check `test` goes red on the PR (layer 7 for runtime; CI for regression)
  configured_in: plugins/soleur/test/changed-path-readers.test.sh, scripts/lib/test-affected-paths.sh

error_reporting:
  destination: in-session tool-result stdout/stderr on the customer CLI (layer 7 cli-stdout-artifact); no Soleur-side sink by design
  fail_loud: "the capture variable reads the literal value unknown, which fires the gate; the helper writes changed-paths: <reason> to stderr on rc 2"

failure_modes:
  - mode: caller-side ${CLAUDE_PLUGIN_ROOT} unbound under set -u (rc 1)
    detection: "layer 7: VAR=unknown in the gate's own output, so the gate runs and its run is visible in-session; CI: executed row R1"
    alert_route: in-session (agent and operator read the gate firing); CI test check on regression
  - mode: helper trips an unbound variable (rc 1)
    detection: "layer 7: bash prints '<file>: line N: <var>: unbound variable' on stderr and VAR=unknown; CI: executed row R3"
    alert_route: in-session; CI test check on regression
  - mode: a caller regresses to [ $? -eq 1 ]
    detection: "CI: skill_ship_handler_pin / REF_PINS counsel row RED, plus DEFECTS rows (a)/(b) prove the pins reject it"
    alert_route: CI test check on the PR
  - mode: helper returns 42 for a non-no-match outcome (e.g. bad ERE)
    detection: "CI: helper row '--match with an invalid ERE exits 2'"
    alert_route: CI test check on the PR

logs:
  where: the customer's own session transcript (tool-result stdout/stderr); CI job log for the test check
  retention: customer-controlled for sessions; GitHub Actions log retention for CI

discoverability_test:
  command: grep -o -m1 -e '42 = none match' plugins/soleur/scripts/changed-paths.sh
  expected_output: "42 = none match"
```

## Guard Contract

### Guard 1 — exit-42 no-match contract of changed-paths.sh and its readers

**Property.** Every consumer of `changed-paths.sh`'s exit code treats only that mode's defined verdict codes as verdicts (`--match`: 0 = match, 42 = no match; plain: 0 = list), so any other exit, including a shell-level rc 1 from an unbound variable in the caller line or inside the helper, is read as unknown, and the helper returns 42 for no-match and for nothing else.

**Assembly.** There are three chokepoints, and the guard covers each separately.

- (1) **The helper's exits.** Two no-match arms (empty list; grep's 1 through `PIPESTATUS`) and the pass-through of every other status.
- (2) **The `--match` capture lines.** Selected by handler shape (`^[a-z_]+=\$\(bash "\$\{CLAUDE_PLUGIN_ROOT\}/scripts/changed-paths\.sh" --match .+\) \|\| \{`) over comment-stripped `plugins/soleur/skills/ship/SKILL.md` and `plugins/soleur/skills/ship/references/counsel-review-clo-attestation.md`. These are executed, with a floor of 6 and set identity on the six names.
- (3) **The prose consumers with no code arm.** These are pinned statically only, because prose cannot be executed: ship Phase 7 UNTRUSTED-CI notice, review gdpr-gate trigger, one-shot scope check, observability-coverage-reviewer inventory, and ship PIR meta-case.

Closure of chokepoint (2) does not rest on the extractor alone. The existing pins already turn a capture line the extractor would miss into a RED:

- In ship/SKILL.md, `skill_ship_handler_pin` compares an unanchored count of `=$(<call> --match` captures with the anchored good-shape count. An indented, `if`-form or otherwise reshaped capture lands in the first count and not the second.
- In the counsel reference, `REF_PINS` requires every helper mention to match the exact capture shape.
- In the other closed-list prose files, the spelling and range pins fire.

No consumer propagates the helper's exit code into `battery-owed.sh` or any other reader of 42 (census in Research Reconciliation), so the two meanings of 42 never meet. The executed rows stop at the captured value. That `unknown` then runs each gate is held by the existing semantics pins: the explicit `[[ $plan_refs == unknown ]]` branch, and the ledger rule "`unknown` fires the gate".

Out of the guard's window, by construction:

- a `--match` capture written in a file other than those two (the census in `section_sentinel` already limits helper call forms to the closed prose list);
- preflight's `$rc -eq 1` arms, which read grep's status on the cached list file, not the helper's.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Helper empty-list arm back to `exit 1` | RED (row "--match on an empty diff exits 42") |
| 2 | Helper final arm back to `exit $?` (grep's 1 leaks through) | RED (row "--match with no match exits 42"; executed control A then yields `[unknown]`) |
| 3 | Helper maps every non-zero grep status to 42 (`[ "${st[1]}" -eq 0 ] \|\| exit 42`) | RED (row "--match with an invalid ERE exits 2") |
| 4 | `dpf_match` handler back to `-eq 1` while the other four stay compliant (second member after a compliant first) | RED (executed R1/R3 rows for `dpf_match`; `skill_ship_handler_pin`) |
| 5 | Counsel `legal_touch` handler back to `-eq 1` | RED (executed R1/R3 for `legal_touch`; REF_PINS counsel row) |
| 6 | A seventh `--match` capture line added to ship/SKILL.md with `-eq 1` | RED (it is extracted by shape and executed; floor is >= 6, not == 6) |
| 7 | Guard's own dispatch: the extraction regex is broken so it selects zero lines | RED (floor >= 6 and the six-name set identity) |
| 8 | Injected-unset helper copy fails to inject (insert line lands after `exit`, so the copy exits 0/42) | RED (precondition "the stub exits exactly 1") |
| 9 | Host bash answers 127, not 1, for the unbound root | RED (precondition row), so R1 cannot pass vacuously |
| 10 | ship Phase 7 notice back to "prints anything or exits 2/127" | RED (new ship semantics pin; DEFECTS row (e)) |
| 11 | one-shot back to "exit 2/127 = scope unverified" | RED (`skill_oneshot_pin`; DEFECTS row (c)) |
| 12 | Must-PASS control B fixture loses one gated surface (say the expenses edit) | RED (control B for `ledger_touched` yields `[]`, not a path) |

**Harness rows.**

- **H1 (suite edit -> RED).** Replace the caller runner's `bash -uc "$line"` with a constant `printf '[unknown]'`. Controls A and B go RED, which proves the RED rows cannot be satisfied by a runner that never executes the line.
- **H2 (suite edit -> RED).** Drop `env -u CLAUDE_PLUGIN_ROOT` from R1 while the test environment exports a valid root. R1 yields a path, not `unknown`, and goes RED, which proves R1 depends on the unset condition.
- **H3 (must-PASS, non-canonical).** The synthetic `skill_fixture` tree, whose capture lines use different EREs (`'^plugins/x/'`) and the same `-eq 42` handler, passes every static pin cleanly (the existing "compliant tree" self-test). Control B, a match diff rather than the canonical no-match, passes the executed rows.

**Anchor.** The stored values are the pin regexes, the fixture lines and the DEFECTS strings in this test file. A diff that edits a caller and its pin together proves consistency, not integrity. The outside movers are:

- the executed rows, which read the real lines from the shipped files and run them under real bash against the real helper, so a pin-and-prose co-edit cannot make an `-eq 1` handler pass R1/R3;
- the required `test` CI check;
- the reviewer reading the DEFECTS block.

The `>= 6` floor is paired with six-name set identity.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "In plugins/soleur/scripts/changed-paths.sh the \"none match\" outcome exits 42 (map grep's exit 1 to 42; update the header comment)" [brief] | Proposed Solution 1 / Phase 2 | mapped |
| 2 | "The six callers change `[ $? -eq 1 ]` to `[ $? -eq 42 ]`" [brief] | Proposed Solution 2 / Phase 3 | mapped |
| 3 | "update the prose in plugins/soleur/skills/review/SKILL.md that describes the rc contract" [brief] | Proposed Solution 3 (review:371) / Phase 3 | mapped |
| 4 | "grep the whole repo for every other consumer of changed-paths.sh's exit code (skills, scripts, hooks, workflows, tests) — every caller that treats rc 1 as no-match must move to 42, or the change opens a new silent class" [brief] | Research Reconciliation row 3; Proposed Solution 3-5; Phase 3.3 census | mapped |
| 5 | "update the existing rc-1 pins" [brief] | Phase 1.1, 1.3, 1.4 | mapped |
| 6 | "(1) the counsel line under `env -u CLAUDE_PLUGIN_ROOT bash -uc` yields `unknown` (fails today)" [brief] | Phase 1.2 R1 (counsel plus the five ship lines) | mapped |
| 7 | "(2) a no-match exits 42" [brief] | Phase 1.1 R2 | mapped |
| 8 | "(3) a helper with an injected unset variable yields `unknown`" [brief] | Phase 1.2 R3 | mapped |
| 9 | "ship SKILL.md has ~73 bytes of size-ceiling headroom, keep growth minimal" [brief] | Byte Budget (net about -30) | mapped |
| 10 | "tick AC 11 (`- [ ] PR body:` -> `- [x] PR body:`) and AC 12 (`- [ ] Required checks green` -> `- [x] Required checks green`); leave AC 1 unticked" [brief] | Phase 4.1 | mapped |
| 11 | "change `- 5.4 Push` to `- [x] 5.4 Push`" [brief] | Phase 4.2 | mapped |
| 12 | "Use `Ref #12246`, never `Closes`" [brief] | Phase 5 PR body | mapped |
| 13 | "stop at ready-for-merge and report; do not enqueue, never --admin" [brief] | Phase 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| changed-paths.sh edit | asks 1 | asked |
| counsel-review-clo-attestation.md edit | asks 2 | asked |
| ship/SKILL.md handlers | asks 2 | asked |
| ship/SKILL.md :2171, :1307, :896, :1050, :1663 prose | "every caller that treats rc 1 as no-match must move to 42, or the change opens a new silent class" (ask 4) | asked |
| review/SKILL.md :371 | asks 3 | asked |
| review/SKILL.md :124, risk-tier :57, adr-ordinal :37 | — | inferred — justification: CTO Q6 ruling; after the 42 change the "2/127" annotation states a false contract next to a fail-closed arm, and review:124 is agent-acted prose that could shrink the review panel on rc 1 |
| one-shot/SKILL.md :179, observability-coverage-reviewer.md :29 | ask 4 ("every other consumer of changed-paths.sh's exit code") | asked |
| test file: rc-1 pins | asks 5 | asked |
| test file: executed caller rows R1/R3, controls, preconditions | asks 6, 8 | asked |
| test file: execution of the five ship lines (beyond counsel) | — | inferred — justification: CTO Q4 ruling; the defect is per call site, and the ship handlers are the same write sites (`hr-write-boundary-sentinel-sweep-all-write-sites`) |
| test file: DEFECTS rows and the two new prose pins | — | inferred — justification: CTO Q5 ruling; the pins must reject the regression this PR removes, or they rot |
| archived plan ticks | asks 10 | asked |
| archived tasks.md tick | asks 11 | asked |
| `PIPESTATUS` mapping: grep's 1 -> 42 | "map grep's exit 1 to 42" (ask 1) | asked |
| `PIPESTATUS` arm: printf failure -> 2 | — | inferred — justification: fail-closed precision; a printf failure alongside a grep 1 means grep judged incomplete input, and without this arm that would map to 42, a false "no match". The arm reports it as 2 (unknown) instead. |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur/` (script, skills, agent, test) and `knowledge-base/project/` (archived ticks)
- Planned files: 11 | Estimated changed lines: about 95
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

### Pre-merge (PR)

- [ ] AC1: In a fixture repo, `bash plugins/soleur/scripts/changed-paths.sh --match '^zzz-never/' origin/main...HEAD` exits 42, a matching ERE exits 0 and prints the paths, an invalid ERE (`'['`) exits 2, and an unresolvable range exits 2 (suite rows in `section_helper`).
- [ ] AC2: `grep -o -m1 -e '42 = none match' plugins/soleur/scripts/changed-paths.sh` prints `42 = none match`, and the header no longer says `1 = none match`.
- [ ] AC3: Exactly six `--match` capture lines carry `|| { [ $? -eq 42 ] || VAR=unknown; }`: 5 in `plugins/soleur/skills/ship/SKILL.md`, 1 in `counsel-review-clo-attestation.md`. `git grep -n -E 'changed-paths\.sh" --match .*\[ \$\? -eq 1 \]' -- plugins/soleur` returns nothing.
- [ ] AC4: `git grep -n '2/127' -- plugins/soleur ':!plugins/soleur/test' ':!plugins/soleur/agents/engineering/review/test-design-reviewer.md'` returns nothing. Today it finds 12 lines, all changed-path consumers; the excluded file's one hit is unrelated mutation-harness text.
- [ ] AC5: RED-first evidence. On the unfixed tree, these rows fail: R2 (2 rows), R1, R3 and R3b (6 lines each), the moved static pins and the new DEFECTS rows. After the fix, `bash plugins/soleur/test/changed-path-readers.test.sh helper` and `... sentinel` are fully green. Both row lists go in the PR body. The Guard Contract mutation matrix (rows 1-12) and harness rows H1-H2 are a one-off mutation run at work time, each applied to a scratch copy and reverted. Their RED/GREEN results are recorded in the PR body; they are not new permanent suite code, apart from the rows Phase 1 already names.
- [ ] AC6: The executed caller rows extract >= 6 lines with all six names exactly once; both preconditions (host bash rc 1; stub rc 1) pass; controls A and B pass.
- [ ] AC6b: The full single-suite run `bash plugins/soleur/test/changed-path-readers.test.sh` exits 0 with `MIN_HELPER_ROWS`, `MIN_TOTAL` and the `SELFTESTS` equality re-derived to the new exact counts, and `bash scripts/guard-vacuity-floor.test.sh` passes with the new extraction floor covered, not UNCLASSIFIED.
- [ ] AC7: `python3 scripts/lint-skill-body-budget.py --base origin/main` prints OK. `wc -c` reports ship/SKILL.md <= 273955 and one-shot/SKILL.md <= 52000.
- [ ] AC8: `bun test plugins/soleur/test/plugin-root-anchoring.test.ts` is green (no `${CLAUDE_PLUGIN_ROOT:-}` introduced).
- [ ] AC9: In the archived remainder plan, the `PR body:` and `Required checks green` lines are `- [x]`, and the `Every site in the final convert set` line is still `- [ ]`. In the archived remainder tasks.md, line `- [x] 5.4 Push (real exit code), ...` is present. No other line in either file changes (`git diff --stat` shows 2 insertions and 2 deletions in the plan, 1 and 1 in tasks.md).
- [ ] AC10: The diff is a subset of the 11 files in Files to Edit plus this feature's pipeline-written artifacts: `knowledge-base/project/plans/2026-11-16-fix-changed-paths-no-match-exit-42-plan.md`, `knowledge-base/project/specs/feat-one-shot-changed-paths-exit-42-unset-root/{tasks.md,decision-challenges.md,session-state.md}`, and any generated `knowledge-base/INDEX.md`.
- [ ] AC11: Repo meta-guards pass before push; push exit code checked.
- [ ] AC12: PR body carries `Ref #12246` with no `Closes`, `Filed: none`, a `## Changelog` section, the `decision-challenges.md` rulings, and the label `semver:patch`.
- [ ] AC13: Required CI checks are green (`ci-is-the-gate`; the local full battery is not run). The PR is marked ready, and the run stops at ready-for-merge: not enqueued, no `--admin`.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO agent ruled the design (exit 42, binding) and the residual forks Q1-Q6 on 2026-11-16 (see `knowledge-base/project/specs/feat-one-shot-changed-paths-exit-42-unset-root/decision-challenges.md`). The change is confined to a local CLI helper and the prose that consumes it, follows an existing in-repo exit-42 precedent, and only moves outcomes from the silent arm to the fail-closed arm.

Not relevant:

- **Legal.** The change restores the counsel-review gate's firing on a failed diff; it changes no legal document, claim or processing activity, so no CLO review is needed for the change itself.
- **Product/UX.** No UI surface: none of the planned paths match the UI-surface term list. Tier NONE.
- **Marketing, Operations, Finance, Sales, Support.** No implications.

No ADR or C4 change: this is a bug fix on an existing helper contract, and no ownership, substrate or trust boundary moves. No GDPR, IaC, encryption-posture or task-design trigger fires: no regulated-data surface, no infrastructure, no store or connection, and no new autonomous task.

## Test Scenarios

All rows are `unit`: shell, against scratch git repos.

- Given a fixture diff with no path matching the ERE, when the helper runs in `--match` mode, then it exits 42 and prints nothing.
- Given an empty diff, when the helper runs in `--match` mode, then it exits 42.
- Given an invalid ERE, when the helper runs in `--match` mode, then it exits 2, never 42.
- Given the counsel line and each ship capture line, a match fixture and `CLAUDE_PLUGIN_ROOT` unset, when the line runs under `bash -u`, then the variable reads `unknown`. (Regression for this bug; RED today.)
- Given each capture line and a helper copy that trips an unbound variable, when the line runs, then the variable reads `unknown`. (RED today.)
- Given each capture line, the real plugin root and a no-match fixture, when the line runs, then the variable is empty: the must-PASS control.
- Given each capture line, the real plugin root and a fixture touching every gated surface, when the line runs, then the variable holds a path, not `unknown`: the must-PASS control.
- Given the synthetic skills tree with one handler reverted to `-eq 1`, or one prose consumer reverted to `2/127`, when the prose pins run, then FAIL moves (DEFECTS).

## Risks and Sharp Edges

- `PIPESTATUS` is overwritten by the next command. It must be captured in the statement immediately after the pipeline, with nothing (not even `rc=$?`) in between.
- The R1 precondition is a host-bash fact. If a future bash answers 127 for an unbound variable in a command substitution, R1 stops being RED-first, but the precondition row reports it rather than letting R1 pass vacuously.
- ship/SKILL.md is a hot file. A concurrent PR can eat the 73-byte headroom before merge. The edits are net negative, but re-run the budget lint after any Phase 7 sync.
- Moving a static pin and its prose in the same commit proves consistency only. The executed rows are what prove behaviour, so do not drop them as redundant with the pins.
- Do not compress ship prose beyond the planned deletions. The ruled Q1 wording keeps "(no match)" deliberately.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6. This plan fills it (`aggregate pattern`).

## References

- Helper: `plugins/soleur/scripts/changed-paths.sh`
- Precedent: `plugins/soleur/skills/ship/SKILL.md` Phase 4 battery block (`battery-owed.sh`, `if [[ "$rc" -eq 42 ]]`)
- Suite: `plugins/soleur/test/changed-path-readers.test.sh`
- Rulings: `knowledge-base/project/specs/feat-one-shot-changed-paths-exit-42-unset-root/decision-challenges.md`
- Arc: #12246 (tracker), #12332, #12494 / 53efc4975872, draft PR #12809
