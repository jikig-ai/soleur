# Tasks: fix: a brief's "ask the operator" wording on a technical fork triggers the CTO

Plan: `knowledge-base/project/plans/2026-10-14-fix-technical-ruling-brief-override-plan.md`
Branch: `feat-one-shot-technical-ruling-brief-override`. Issue: `Ref #9217` only (never `Closes`).

## Phase 1: RED first

- 1.1 Add the must-DENY rows AK1 to AK5 to `.claude/hooks/pre-ask-technical-fork-gate.test.sh` (ruling-arm block, `run_ruling ... deny ruling`).
- 1.2 Add the must-ALLOW rows AL1 to AL11 (AL9 to AL11 are the pinned residual).
- 1.3 Add `NR3` (lib probe: `shared` and `shared+closing` exit 1, `shared+ask` exits 0 with `TFC_HIT=ask`) and the AK1 reason assertion (the ask lead is present).
- 1.4 Extend V5's row list with AK1 to AK5 and raise its floor by 5; move the V1 literal (three sites) and `MIN_CASES` together to `145 + N` (count N by running).
- 1.5 In `.claude/hooks/pre-closing-technical-fork-gate.test.sh`: retarget G2-2 to the `shared+ask` case line with a comment, add the three committed mutants (group ignored, dispatch dead, Stop carrier widened) through a pre-ask variant of the mutant row helper, add the closing allow row (AK3 text), raise the V6 floor by 3, move the V1 literal and `MIN_CASES` (130, three sites), correct the header table at line 32.
- 1.6 Run both suites: they must be RED.

## Phase 2: lib and hook

- 2.1 `.claude/hooks/lib/technical-fork-cues.sh`: `shared+ask) ask=1 ;;` (leave `shared) ;;` untouched), `ask=0` in the `local` line, the two `TFC_ASK_*` regexes verbatim from the plan, the one-line ask check in the weak block after the `ab` cue; update the header.
- 2.2 `.claude/hooks/pre-ask-technical-fork-gate.sh`: call `tfc_is_fork "$__rq" shared+ask`; replace the reason lead when `TFC_HIT` is `ask` and keep every later paragraph; update the header comments and state the residual.
- 2.3 Run both suites: GREEN.

## Phase 3: skill text

- 3.1 Reference section 1: add the H2 classification rule verbatim after the `scope` bullet.
- 3.2 Reference section 5: extend the Override clause (brief wording is the trigger) and add the 2026-10-14 Why.
- 3.3 Reference section 7: add the T4 worked row; run `bash plugins/soleur/test/technical-ruling-gate.test.sh`.
- 3.4 `plugins/soleur/commands/go.md`: one sentence in the first Sharp Edge bullet only (outside the go-routing block).
- 3.5 `plugins/soleur/skills/go/SKILL.md`: one sentence with a markdown link to the reference.
- 3.6 `plugins/soleur/skills/one-shot/SKILL.md`: one clause in the inline copy; `wc -c` below 52000.
- 3.7 `plugins/soleur/test/components.test.ts`: the `OPEN DECISION` token and one test with three content anchors.

## Phase 4: records

- 4.1 ADR-084: correct the pre-ask group sentence and add the short 2026-10-14 addendum via `soleur:architecture` (include the `TFC_ASK_*` budget).
- 4.2 Learning under `knowledge-base/project/learnings/workflow-patterns/` (the brief wording is the third carrier).
- 4.3 Confirm `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` exits 0.

## Phase 5: verify and ship

- 5.1 Run every command in the plan's Phase 5 once, including the three cue-internal mutation rows by hand; markdownlint every new or edited `.md`.
- 5.2 Confirm the forbidden paths are absent from `git diff origin/main --name-only` (AC9) and that the go-routing block hash equals `origin/main`'s.
- 5.3 PR: labels `semver:patch` and `app:web-platform`; body `Ref #9217`, ends with the Claude Code generated-with line; commits end with the Co-Authored-By line.
- 5.4 Merge: `emit-review-trailer.sh --findings <n>` as its own command, then push, then `gh pr merge`.
