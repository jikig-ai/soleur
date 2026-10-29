# Tasks: widen the go hold-routing trigger and classify the holds on epic 9927

Plan: knowledge-base/project/plans/2026-10-29-feat-widen-hold-routing-trigger-epic-9927-plan.md
Issue: Ref #9927 (never a closing keyword). PR: 11476 (draft).

## Phase 1: Setup and RED

- 1.1 Run the existing suite green first: `bash plugins/soleur/test/go-hold-routing.test.sh` and `bash plugins/soleur/test/cto-interface-selector.test.sh` (baseline, record the counts).
- 1.2 Add the ten new pins to `go-hold-routing.test.sh` (`classification-trigger`, `classification-ignored-blocks`, `classification-open-epic-only`, `classification-author-limits`, `classification-route`, `classification-prompt-not-own-the-epic`, `classification-only`, `classification-both-forms`, `prose-amended`, `zero-scope`) and watch them go RED against the current `go.md`.
- 1.3 Add the paragraph-derived matcher (`would_route`) and the eight synthesized fixtures; watch the positive ones go RED.

## Phase 2: Core implementation

- 2.1 `plugins/soleur/commands/go.md` Step 1.5 (outside the eval-gate markers): the exception clause in the routing sentence, the separate prose sentence, the two Classification list bullets (trigger, route), the No delegable act bullet. Single-line bullets, no fence, no line starting `#`.
- 2.2 `plugins/soleur/skills/one-shot/SKILL.md` line 98: add "(a classification-only list files no issue)" and keep the two pinned substrings.
- 2.3 ADR-289: append `## Addendum 2026-10-29 (#9927)`, about five lines, 0 removed lines. Do not touch ADR-282.
- 2.4 Add the ten mutation rows and extend H4 to a second removed emit; run green once, then set `ABSOLUTE_FLOOR` to the actual count with zero slack.
- 2.5 `cto-interface-selector.test.sh`: derive the classification cue, `-n` assertion, one `rule` caller row, raise its `ABSOLUTE_FLOOR` by the added assertions.

## Phase 3: Verification

- 3.1 Run `go-hold-routing.test.sh`, `cto-interface-selector.test.sh`, `go-routing-table-parity.test.sh`, `c4-count-parity.test.sh`. A local gate that queues behind sibling runs is not waited for past its timeout; CI is the gate.
- 3.2 Eval gate no-op: `eval-gate.cjs --check plugins/soleur/commands/go.md` (gated) and the candidate run on a temp copy (`accept:true, reason:"no gated-block change"`, no API spend). Record the line for the PR body.
- 3.3 `git grep -il 'hold routing' -- plugins` still lists `commands/go.md` as the only holder of the paragraph.
- 3.4 `git diff --stat` shows only: go.md, one-shot SKILL.md, the two test files, ADR-289, the spec directory and the plan.

## Phase 4: Ship

- 4.1 PR body: `Ref #9927` only; measured vs not measured with dates (2026-10-29); CI is the gate; render decision-challenges rows; flag row O1 for the owner.
- 4.2 Merge-queue PR that is BEHIND waits for the queue: `bash plugins/soleur/scripts/ci-head-verdict.sh verdict <PR>`.

## Phase 5: Post-merge (GitHub write, named action)

- 5.1 Resolve the archived draft path on `origin/main` (exactly one match) and build the new body = original bytes + blank line + the draft's fenced section.
- 5.2 Abort unless the original is an exact prefix, `orig.txt` is non-empty, and the counts are 10 `- Hold:`, 5 `Operator-reserved:`, 4 `Class: technical`, 1 `Class: waiting`, 5 `Class: operator`.
- 5.3 Re-read `updated_at`, abort if moved, then PATCH the body in a separate call.
- 5.4 Read back: prefix intact, state open, association MEMBER, heading present. Print counts and booleans only. Change nothing else on the issue.
