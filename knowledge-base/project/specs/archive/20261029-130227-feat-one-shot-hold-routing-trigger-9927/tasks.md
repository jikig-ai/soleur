# Tasks: widen the go hold-routing trigger and classify the holds on epic 9927

Plan: knowledge-base/project/plans/2026-10-29-feat-widen-hold-routing-trigger-epic-9927-plan.md
Issue: Ref #9927 (never a closing keyword). PR: 11476 (draft).

## Phase 1: Setup and RED

- 1.1 Run the existing suites green first (`go-hold-routing.test.sh` about 40 s, `cto-interface-selector.test.sh`); record the counts (212 and 167 floors).
- 1.2 Add the new pins to `go-hold-routing.test.sh` (22 tokens listed in the plan, Phase 2 item 1) and watch them go RED against the current `go.md`.
- 1.3 Add the paragraph-derived matcher (one awk process, fixture table in `$SANDBOX`, extraction must match exactly once, fixed-string comparison, fixtures via files/ENVIRON, JSON via `jq -n --arg`) and the eleven synthesized fixtures; watch the positive ones go RED.

## Phase 2: Core implementation

- 2.1 `plugins/soleur/commands/go.md` Step 1.5 (outside the eval-gate markers): the exception clause in the routing sentence, the separate prose sentence, the appended ask-once exception, the two Classification list bullets (trigger, route), the No delegable act bullet. Single-line bullets, no fence, no heading line.
- 2.2 `plugins/soleur/skills/one-shot/SKILL.md` line 98: rewrite at a net -1 byte (budget headroom is 6 bytes); keep the two pinned substrings; run `lint-skill-body-budget.py --base origin/main`.
- 2.3 ADR-289: append `## Addendum 2026-10-29 (#9927)`, about six lines, 0 removed lines, including the creator-versus-editor note. Do not touch ADR-282.
- 2.4 Add the ten hand-written mutation rows, the table-driven pin sweep and the extended H4 (second emit, grep `nested.err`, `nrows++`/`ck` in both branches); run green once, then set `ABSOLUTE_FLOOR` to the actual count with zero slack.
- 2.5 `cto-interface-selector.test.sh`: derive the classification cue, `-n` assertion, one `rule` caller row, one `misroute_row`; raise the literal `+ 8` to `+ 9` and the `ABSOLUTE_FLOOR` to the new count.

## Phase 3: Verification

- 3.1 Run `go-hold-routing.test.sh`, `cto-interface-selector.test.sh`, `go-routing-table-parity.test.sh`, `c4-count-parity.test.sh`, `technical-ruling-gate.sh --branch`, `lint-skill-body-budget.py --base origin/main`. A local gate that queues behind sibling runs is not waited for past its timeout; CI is the gate.
- 3.2 Eval gate no-op: `eval-gate.cjs --check plugins/soleur/commands/go.md` (gated) and the candidate run on a temp copy (`accept:true, reason:"no gated-block change"`, no API spend). Record the line for the PR body.
- 3.3 `git grep -il 'hold routing' -- plugins ':!plugins/soleur/test'` prints exactly go.md; `git grep -il -e 'OWNER-GATED' -e 'HOLDS:' -- plugins ':!plugins/soleur/test'` prints exactly go.md and skills/one-shot/SKILL.md.
- 3.4 `git diff --name-only origin/main...HEAD` shows only: go.md, one-shot SKILL.md, the two test files, ADR-289, the archived spec directory and the archived plan (and optionally one learning file). ADR-282 has 0 changed lines.

## Phase 4: Ship

- 4.1 PR body: `Ref #9927` only; measured vs not measured with dates (2026-10-29); CI is the gate; render decision-challenges rows; flag row O1 for the owner.
- 4.2 Merge-queue PR that is BEHIND waits for the queue: `bash plugins/soleur/scripts/ci-head-verdict.sh verdict <PR>`.

## Phase 5: Post-merge (GitHub write, named action; automation via gh)

- 5.1 Resolve the archived draft path on `origin/main` (exactly one match); `SCRATCH` is a mode-700 temp directory.
- 5.2 Read the body (`jq -j`), note its sha256, build `new.txt` = original bytes + blank line + the draft's fenced section.
- 5.3 Abort unless the original is an exact prefix, `orig.txt` is non-empty, and the counts are 10 `^- Hold:`, 5 `Operator-reserved:`, 4 `^  Class: technical`, 1 `^  Class: waiting`, 5 `^  Class: operator`.
- 5.4 In a separate call, re-fetch and abort unless the body sha256 is unchanged, then PATCH. On any abort re-read from the start; never retry the same file.
- 5.5 Read back: response equals `new.txt` (hash), prefix intact, state open, association MEMBER, heading present. Print counts and booleans only. Change nothing else on the issue.
