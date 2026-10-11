---
title: "docs(adr): record ADR-276 Decision 4 (draft-PR light checks) as adopting in the Stage status list"
type: docs
date: 2026-10-11
slug: adr-276-decision-4-adopting-line
branch: feat-one-shot-adr276-decision4-adopting-line
issue: 9728
lane: single-domain
---

# docs(adr): record ADR-276 Decision 4 (draft-PR light checks) as adopting in the Stage status list

## Overview

ADR-276 carries `status: adopting` in its front-matter since 2026-10-09, but its Status section says Decisions 4 and 5
"stay the proposed shape of stages 3 and 4". Stage 3 (draft PRs run the light set, `CI_DRAFT_LIGHT`, Decision 4) has
since shipped (#9885) and been switched on (`S3-ACTIVATED: 2026-10-11T09:43:31Z` on #9728). The CTO's review comment on
the merged status-flip PR #9876 (CONFIRM WITH CONDITIONS, 2026-10-11T09:46:49Z) makes the first condition: append a
dated line recording Decision 4 as adopting, because it shipped and is active with no line saying so.

This PR does exactly that and nothing else: one appended dated line under `### Stage status` in the ADR. The block is
append-only, so no earlier row or line is edited. Docs only, no code, no CI behaviour change.

Draft PR #10040 already exists on this branch. The PR body says `Ref #9728` and carries no close keyword (#9728 stays
open: S3 is soaking, not exited).

## Enhancement Summary

**Deepened on:** 2026-10-11 (proportionate pass; no agent fan-out, per the one-line docs scope of the brief)
**Sections enhanced:** 3 (Scope Check restructured to the gate schema, AC 3 and the Test Scenarios made unambiguous)
**Checks run:** 4.6 User-Brand Impact present, threshold `none` with scope-out (ADR path is not a sensitive path);
4.7 skipped (pure docs); 4.8 PAT sweep clean; 4.9 to 4.11 not triggered (no UI, store or connection, guard);
4.12 exactly one unfenced `## Scope Check` with the three subsections, no `unmapped` row, a `Recommendation:` line.
Cited state verified live: #9728 OPEN, #9876 MERGED, #9885 MERGED (commit 3ef5aa6e12 is an ancestor of
`origin/main`), #9454 OPEN, #10040 OPEN draft; the CTO comment URL and the `S3-ACTIVATED` comment URL resolve via
`gh api`. No AGENTS.md rule ids are cited. The markdown lint config (`.markdownlint.json`) has MD013 off, so the long
single-line bullet matches its neighbours.

### Key Improvements

1. The Scope Check now follows the schema the 4.12 gate parses (it was prose bullets and would have halted).
2. AC 3 no longer contradicts itself: the added line necessarily contains the words `S3 live` inside its negation; the
   AC now asserts exactly that and the test scenario gives the expected counts (1 added, 3 total).
3. The ADR corpus check confirmed the mechanism (a dated Stage-status line) is the one the ADR prescribes; no rejected
   alternative applies.

## Research Insights

**Premise Validation.** Checked: #9728 is OPEN; PR #9876 is merged and carries the CTO comment
(<https://github.com/jikig-ai/soleur/pull/9876#issuecomment-6107725381>) with condition 1 as quoted above;
`S3-ACTIVATED: 2026-10-11T09:43:31Z` is on #9728
(<https://github.com/jikig-ai/soleur/issues/9728#issuecomment-6107700815>); #9454 (the ADR-270 canary) is OPEN; the
ADR on `origin/main` (47c38a19da) ends the Stage status list at the `2026-10-09 S3 amended (#9728; ...)` line, and
`git log` for the file shows #9885 (S3 dark) as the latest change. Held: all of it. Stale: nothing. No ADR-corpus
conflict: the mechanism is a plain dated-line append, which the ADR's own Stage status preamble prescribes
(`- 2026-MM-DD S3 amended`, `- ... S3 live`).

**Status-section reading (how Decision 4 transitions).** The Status section (lines 15-20) says the `status:` flip makes
the guardrail decisions (1, 2, 3, 6, 7, 8) `adopting` while "Decisions 4 and 5 stay the proposed shape of stages 3 and
4". It states no explicit trigger for 4 and 5. The `## Amendment 2026-10-09 (status flip to adopting)` repeats the
same sentence. The trigger therefore comes from the CTO condition, and the line must say so. Also relevant: the Stage
status preamble defines `live` as "the stage's dark-launch exit criterion passed". `adopting` is deliberately a
weaker word than `live`, which is the correct reading here: the criterion (at least 20 light draft pushes over at least
7 days since activation, an exit census) has not been met.

**Property List.**

1. A reader of the Stage status list can see that Decision 4 is no longer the proposed shape (it is adopting) and why.
2. The line does not claim S3 is `live` or exited, and does not touch Decision 5 (stage 4) or any S2 line.
3. The line does not present ADR-270's `accepted` status as canary evidence.
4. The change is append-only (no earlier row edited) and merges without closing #9728.

**Cut List.** (none needed) The ask names one mechanism, a dated Stage-status line, which the ADR already prescribes. A
separate `## Amendment` section was considered (CTO condition 1 allows "the `S3 live` line or a one-line amendment")
and cut: the S3 amendment already carries the design, a second section would restate it, and a single Stage-status
line buys the one property (visibility of the transition) at the lowest cost. Putting it in an `S3 live` line is
excluded because S3 is not live.

**Open Code-Review Overlap.** None (queried open `code-review` issues for the ADR path: no match).

## Files to Edit

- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`
  (append one bullet after the `- 2026-10-09 S3 amended (#9728; ...)` line, before `## Context`; no other change)

## Files to Create

- `knowledge-base/project/plans/2026-10-11-docs-adr-276-decision-4-adopting-line-plan.md` (this plan)
- `knowledge-base/project/specs/feat-one-shot-adr276-decision4-adopting-line/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-adr276-decision4-adopting-line/session-state.md`

## Implementation

Single Edit: insert immediately after the line beginning `- 2026-10-09 S3 amended (#9728;` (the anchor is that
content, not a line number) the following bullet, kept as one source line like its neighbours:

```markdown
- 2026-10-11 S3 activated, Decision 4 adopting (#9728; condition 1 of the agent-run CTO review comment on the status-flip PR, <https://github.com/jikig-ai/soleur/pull/9876#issuecomment-6107725381>, posted 2026-10-11T09:46:49Z): draft-PR light checks shipped in #9885 and `CI_DRAFT_LIGHT` has been `on` since 2026-10-11T09:43:31Z (`S3-ACTIVATED`, <https://github.com/jikig-ai/soleur/issues/9728#issuecomment-6107700815>), so Decision 4 is now the adopting shape of stage 3, no longer the proposed one; Decision 5 stays the proposed shape of stage 4. Order of events: activation rested on the operator's go (`S3-CONFIRMED`, which recorded the CTO confirmation as still owed) and preceded that review comment by about three minutes; this line records the comment as received, and whether an agent-run review stands in for the human CTO confirmation owed on the 2026-10-09 status-flip line is the operator's call. `S3 live` is NOT recorded and still waits for the exit census: the soak runs until at least 2026-10-18. CTO conditions 2 to 4 are tracked on #9454, #9729 and #9728 and are not claimed here. ADR-270 `accepted` is not canary evidence (that evidence is open on #9454, items 4, 5 and 6).
```

Wording rules, each tied to the brief:

- "adopting" and "soak", never "live", "exited" or "closed".
- ADR-270 is cited only as a non-evidence disclaimer, matching CTO condition 2.
- No S2 / `CI_PUSH_DEDUPE` text added or changed; no change to the table, the preamble, the Status section, the
  `## Amendment` sections, the front-matter, or the earlier "S3 amended" line (which still says `S3 live` waits for
  activation; the new line does not contradict it because activation is not exit).
- The date is the PR's authoring date (2026-10-11, today), consistent with the dated-line convention.

## Acceptance Criteria

- [x] `git diff origin/main --stat` shows exactly one ADR file changed with one added line and zero removed lines, plus
  the plan, tasks and session-state files; no other path.
- [x] `git diff origin/main -- <ADR>` has no `-` content lines (append-only), and the added line sits after the
  `2026-10-09 S3 amended` line and before `## Context`.
- [x] The added line contains `Decision 4 adopting`, `#9728`, `2026-10-11T09:43:31Z` and `2026-10-18`, and it states
  that `S3 live` is NOT recorded (the only occurrence of `S3 live` in the line is that negation).
- [x] The added line does not contain `accepted` outside the ADR-270 disclaimer, does not contain `exited`, `CI_PUSH_DEDUPE`
  or `S2`.
- [x] The existing `status: adopting` front-matter line is unchanged.
- [x] `npx markdownlint-cli2` (or the repo's markdown lint used in CI for `knowledge-base/**`) passes on the ADR; the
  bullet must not break the list.
- [ ] PR #10040 body says `Ref #9728` and contains none of `Closes`, `Fixes`, `Resolves` (any case/tense) as a close
  keyword; #9728 remains open after merge.
- [ ] PR #10040 is marked ready only after the above verify, and carries no operator checklist.

## Test Scenarios

Docs-only; verification is by diff inspection:

- `git diff origin/main -- <ADR> | grep -c '^-[^-]'` returns 0.
- `grep -n 'Decision 4 adopting' <ADR>` returns exactly one hit, on the line after the S3 amended line.
- `git diff origin/main -- <ADR> | grep '^+' | grep -c 'S3 live'` returns 1, and that hit is the "NOT recorded" negation;
  `grep -c 'S3 live' <ADR>` is 3 after the edit (2 on `origin/main` plus the negation).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing; the ADR is an internal engineering record, and the
only failure is a reader of the Stage status list misreading stage 3 as live or Decision 4 as still proposed.

**If this leaks, the user's data / workflow / money is exposed via:** no exposure vector; the line cites only public
issue and PR URLs and a UTC timestamp already on #9728.

**Brand-survival threshold:** none

threshold: none, reason: a one-line append to an internal architecture decision record; it touches no sensitive path,
data, auth, or CI behaviour.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: internal ADR bookkeeping, no UI, no data, no vendor, no infrastructure.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "append a dated line (2026-10-11) to the \"### Stage status\" list ... recording Decision 4 (draft-PR light checks, CI_DRAFT_LIGHT) as \"adopting\"" | Implementation (single Edit) | mapped |
| 2 | "The Stage status block is append-only (dated lines under the table, never edit earlier rows)" | AC 1, AC 2 (zero removed lines) | mapped |
| 3 | "PR body must say \"Ref #9728\" with NO close keywords" | AC 7 | mapped |
| 4 | "do not claim the stage is exited/live, do not cite ADR-270 as accepted canary evidence, do not touch the S2 (CI_PUSH_DEDUPE) lines" | Wording rules, AC 3, AC 4 | mapped |
| 5 | "Check the Status section (around lines 15-20) of the ADR for how Decision 4 transitions to adopting and phrase the line consistently" | Research Insights (Status-section reading), Wording rules | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| One appended Stage-status line | "append a dated line (2026-10-11)" | asked |
| Soak-not-live wording, ADR-270 disclaimer | "do not claim the stage is exited/live, do not cite ADR-270 as accepted canary evidence" | asked |
| Diff and PR-body acceptance checks | "Docs only, no code" and "NO close keywords" | asked |
| Markdown lint check (AC 6) | none | inferred: an ADR bullet that breaks the list fails the docs lint in CI, so one run covers it |
| Plan and tasks files | "Plan only: write only under knowledge-base/project/{plans,specs}/" | asked |

### Split Assessment

- Subsystems touched: 1 - knowledge-base/engineering/architecture/decisions
- Planned files: 1 edited, 2 created (plan, tasks) | Estimated changed lines: 1
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. CTO conditions 2, 3 and 4 on #9876 are not part of this ask; they are actions on #9454, #9729 and #9728, and this PR neither defers nor claims them.

## Observability

Skipped: pure docs, no Files to Edit under code or infrastructure paths.

## Risks and Sharp Edges

- Do not write `S3 live`, `exited`, or `activated and proven`: the soak is open until at least 2026-10-18 and the probe
  `scripts/followthroughs/ci-draft-light-soak-9728.sh` needs an `S3-EXIT-CENSUS` marker before the stage can close.
- The ADR has a front-matter `status: adopting` and a historic Status paragraph that still reads "Proposed,
  2026-10-07". Do not edit either; the current state is the front-matter plus amendments plus the dated lines.
- A close keyword in the PR body would auto-close #9728 on merge while the soak is running. Use `Ref #9728` only. The
  PR title must not carry one either.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6; this one declares `none` with a reason.
