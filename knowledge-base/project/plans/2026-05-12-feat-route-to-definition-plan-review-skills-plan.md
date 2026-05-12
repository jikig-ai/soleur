---
lane: "procedural"
issue: "#3667"
pr_source: "#3653"
type: "compound-route-to-definition"
plan_review: true
detail_level: "MORE"
---

# Plan: Route-to-definition for plan + review skills (enum-gate + precondition grep)

**Issue:** [#3667](https://github.com/jikig-ai/soleur/issues/3667)
**Branch:** `feat-one-shot-3667-route-to-definition`
**Spec:** [`knowledge-base/project/specs/feat-one-shot-3667-route-to-definition/spec.md`](../specs/feat-one-shot-3667-route-to-definition/spec.md)
**Source learning:** [`2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md`](../learnings/2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md)
**Source PR:** #3653

## Overview

PR #3653 (cohort missing-reply marker) shipped clean, but its 11-agent review surfaced three plan-quality defects that compound into one canonical learning. The compound skill routed those defects to **two** skill files (`plan/SKILL.md` Sharp Edges + `review/SKILL.md` Defect Classes), which crosses compound's file-issue threshold for `cross-cutting-refactor` — so the work was deferred via issue #3667 instead of inline-edited on the #3653 PR.

This plan is the deferred work: append three Sharp Edges bullets to `plan/SKILL.md` and one Defect Class bullet to `review/SKILL.md`. All four entries cite PR #3653 and the source learning. No source code edits, no schema, no infrastructure. This is `procedural` lane, `MORE` detail level.

The three defects routed to `plan/SKILL.md` are:

1. **Precondition false-pass via Read-not-Grep.** Plan said "X is accessible at scope Y", check was satisfied by reading the consuming code instead of grepping for X in the producing-scope file. Field didn't exist; /work had to plumb three boundaries.
2. **Component prop boundary vs `test.each` parameter row mismatch.** Plan's architecture pushed predicate outside the component while the test list needed predicate inputs at the component boundary — mutually inconsistent at plan time, surfaced as a mid-/work pivot.
3. **3-value enum gate slip.** FR named one of three union members; /work implemented the FR verbatim; review caught the missing third value (`"stopping"`) **only because** the review-spawn prompt explicitly enumerated the enum. The signal was prompt-driven, not pattern-recognition.

The fourth defect (the same enum-gate class, viewed from the review side) routes to `review/SKILL.md` to make the prompt-driven catch a documented default.

## Research Reconciliation — Spec vs Codebase

See spec.md "Research Reconciliation" table. Summary: zero divergences; the issue body's proposed edits map 1:1 to current file structure and citation conventions.

## User-Brand Impact

- **If this lands broken, the user experiences:** the `plan/SKILL.md` Sharp Edges section becomes harder to grep (broken formatting) or the new entries cite a wrong learning path producing a 404 link in operator-facing review output. The lower-bound failure is "operator wastes one cycle reading a malformed entry"; the upper-bound is the entries failing to fire as guidance and the same #3653-class defect recurring on a future plan.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A. Documentation-only PR touching two skill files. No regulated-data surfaces, no API routes, no schemas, no auth flows.
- **Brand-survival threshold:** `none, reason: documentation-only edits to operator-facing plan and review skill prose; no user-facing surface, no data path, no execution path. Failure mode is "guidance entry doesn't fire" — identical to pre-PR state.`

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** `grep -c "PR #3653" plugins/soleur/skills/plan/SKILL.md` returns ≥ 3 (one per FR1/FR2/FR3 entry).
- **AC2.** `grep -c "PR #3653" plugins/soleur/skills/review/SKILL.md` returns ≥ 1 (FR4 entry).
- **AC3.** `grep -c "2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md" plugins/soleur/skills/plan/SKILL.md plugins/soleur/skills/review/SKILL.md` returns ≥ 4 (one citation per added entry).
- **AC4.** `grep -nE "precondition.*grep|grep.*precondition|producing-scope|producing scope" plugins/soleur/skills/plan/SKILL.md` returns ≥ 1 match at a line ≥ 686 (inside `## Sharp Edges`). (FR1 marker.)
- **AC5.** `grep -nE "test\.each|parametrized test|test list" plugins/soleur/skills/plan/SKILL.md | grep -iE "prop boundary|component"` returns ≥ 1 match in the Sharp Edges section. (FR2 marker.)
- **AC6.** `grep -nE "enum-gate|enum gate|every union member|every member of the union|classify every" plugins/soleur/skills/plan/SKILL.md` returns ≥ 1 match in the Sharp Edges section. (FR3 marker.)
- **AC7.** `grep -nE "every union member|enumerate every|classify every|multi-member union" plugins/soleur/skills/review/SKILL.md` returns ≥ 1 match in the Defect Classes section (between line 764 and the `See knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` closing line at ~779). (FR4 marker.)
- **AC8.** `bun test plugins/soleur/test/components.test.ts` passes. (Body-text edits do not affect description word budgets.)
- **AC9.** `git diff origin/main...HEAD --name-only` lists exactly two files: `plugins/soleur/skills/plan/SKILL.md` and `plugins/soleur/skills/review/SKILL.md`. (No scope creep.)
- **AC10.** PR body uses `Closes #3667`.

### Post-merge (operator)

- **AC11.** None — closure is automatic on merge.

## Files to Edit

- `plugins/soleur/skills/plan/SKILL.md` — append three Sharp Edges bullets at the end of `## Sharp Edges` (current last bullet at line 758 cites PR #2723).
- `plugins/soleur/skills/review/SKILL.md` — append one Defect Class bullet at the end of `### Defect Classes This Review Reliably Catches` (current last bullet at line 777; new bullet inserts before the closing `See ...` line at 779).

## Files to Create

None.

## Open Code-Review Overlap

None. Queried open code-review-labeled issues; none reference `plugins/soleur/skills/plan/SKILL.md` or `plugins/soleur/skills/review/SKILL.md` in their bodies. The parent issue #3667 is itself the deferred-scope-out for this work — not an overlap.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)

**Status:** reviewed (inline assessment).
**Assessment:** Single-domain markdown documentation change. No code, schema, auth, or infrastructure paths touched. Lane resolves to `procedural`. No specialist required beyond the standard plan-review trio (DHH-rails, Kieran-rails, code-simplicity) at plan-review time.

No Product/UX gate (NONE tier — no user-facing surface).

## Implementation Phases

### Phase 1 — `plan/SKILL.md` Sharp Edges additions

Append three single-paragraph bullets to the end of `## Sharp Edges` (after current line 758). Each bullet follows the file's established format: opening "When a plan …" clause, operative rule, optional Why+citation paragraph.

**Bullet 1 (FR1) — Precondition grep:**

> When a plan precondition asserts "X is accessible at scope Y", the check MUST include `grep -nE '\bX\b' <file-that-defines-scope-Y>` — not just a Read of the consuming code. The consuming code can name a variable optimistically (`conversation.created_at` reads as if it's a property of an in-scope object) when the producing scope only exposes `conversationId: string` and a flat hook return; the Read passes while the field doesn't exist at the proposed mount scope. **Why:** PR #3653 — plan §Phase 0.1 asserted `conversation.created_at` accessibility via Read; /work surfaced that `useWebSocket(conversationId)` returns slices without `conversationCreatedAt` and `/api/conversations/:id/messages` did not select the field. Three boundary edits required at /work to plumb the slice. See `knowledge-base/project/learnings/2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md`.

**Bullet 2 (FR2) — Parametrized test list ↔ component prop boundary:**

> When a plan specifies both (a) a component architecture and (b) a parametrized test list (`test.each([healed, postFix, preWindow, streaming, postSunset])(...)`), cross-check at plan time that every test row's fixture inputs map to the component's prop boundary. If the test list's inputs span predicate state that the architecture pushes outside the component (e.g., predicate lives at the mount site in an IIFE while the component takes only one prop), one of the two must change. Architecture > tests if tests can be rewritten to drive through a higher-level mount; tests > architecture if the test inputs are the load-bearing brainstorm-owned failure enumeration. **Why:** PR #3653 — plan §1.1.2 listed 5 test rows needing `messages` + `createdAt` + `isStreamingAssistant` while plan §1.3.2 mount IIFE exposed only `createdAt` to the component; /work pivoted to move the predicate into the component to keep the brainstorm-owned test list verbatim. See same learning file.

**Bullet 3 (FR3) — Enum-gate enumeration:**

> When a plan FR conditions on a single enum / union value (`X === "streaming"`, `!isStreamingAssistant`, `status === "completed"`), the FR text MUST classify EVERY union member of `X` as include or exclude. If `X` has N values, the FR must explicitly enumerate all N. Single-value FRs hide a class of bug under any future schema widening, and the work phase reliably honors the FR verbatim — the gap is structural in the FR, not in execution. **Why:** PR #3653 — plan §FR2 conditioned on `!isStreamingAssistant`; implementation bound it to `streamState === "streaming"`. Codebase: `StreamState = "idle" | "streaming" | "stopping"` (`ws-client.ts:47`); `"stopping"` is a distinct in-flight state during mid-aborts that the FR never named. `user-impact-reviewer` caught the slip at PR review only because the review-spawn prompt explicitly enumerated the 3-value enum. Recovery: renamed prop to `isTurnInFlight`, bound to `streamState !== "idle"`. See same learning file.

### Phase 2 — `review/SKILL.md` Defect Classes addition

Append one bullet to the end of `### Defect Classes This Review Reliably Catches` (after current line 777, BEFORE the closing `See knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` line at 779). Format mirrors sibling entries: **bold lead clause** + em-dash + body + `Reviewer takeaway:` + `**Why:** PR #N — … See <path>.`.

**Bullet 4 (FR4) — Single-literal gate over multi-member union/enum:**

> **Single-literal gate over a multi-member union/enum** — when a TypeScript predicate gates behavior on `X === <literal>` (or `!isFoo`, `status === "completed"`) and `X` is a union/enum with ≥ 3 members, the gate is correct only by coincidence unless every member has been classified include/exclude in the originating FR. `user-impact-reviewer` and `pattern-recognition-specialist` reliably catch this **only when the review-spawn prompt explicitly enumerates the union members** — without the prompt, agents echo the plan's single-value framing as a false-pass. Reviewer takeaway: when reviewing a gate conditioned on `X === <literal>` where `X` is a TypeScript union/enum, enumerate every union member by grepping the type's declaration (`rg "type X =" <module>` or `grep -nE "X = .*\|"`), then ask "is the gate correct for each value?" Single-literal gates against multi-member unions are a known defect class. **Why:** PR #3653 — plan §FR2 conditioned on `!isStreamingAssistant`; work bound `streamState === "streaming"` while `StreamState = "idle" | "streaming" | "stopping"` (`ws-client.ts:47`). `"stopping"` is a distinct in-flight substate that mid-aborts traverse; a Stop click could have flashed the marker during that window. Caught only because the spawn prompt explicitly named the 3-value enum. See `knowledge-base/project/learnings/2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md`.

### Phase 3 — AC verification + commit

Run AC1-AC9 as a single bash verification block. On green, commit both files in one commit; push. PR body uses `Closes #3667` and references both #3653 and the source learning path.

## Risks

- **R1.** Word-budget regression on plan/SKILL.md or review/SKILL.md skill frontmatter. **Mitigation:** edits are body-only; AC8 enforces. Sharp Edges sit below frontmatter and don't enter the description tokenizer.
- **R2.** Sharp Edges list pollution. The plan SKILL.md Sharp Edges list is already long (~70 entries); +3 is +4% growth. **Mitigation:** each entry is one paragraph with a citation. Operator value comes from grepable specificity, not list-brevity; pruning is a separate cleanup PR.
- **R3.** Defect Class catalog format drift. **Mitigation:** the new bullet mirrors the existing "Cross-stream format-contract drift" / "Replicated literals across ≥2 source files" entries — same `**Bold lead** — body + Reviewer takeaway + **Why:** PR #N — … See <path>.` shape.
- **R4.** Reviewer agents over-fire the new defect-class rule on 2-member unions (e.g., `boolean`). **Mitigation:** rule scope is "≥ 3 members"; the wording will say `≥ 3 members` explicitly. Boolean gates are not the target — the target is `streamState`-class 3+-value unions.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`. (This plan satisfies the section above with threshold `none, reason: …`.)
- The plan/SKILL.md Sharp Edges list is grep-indexed by operators. Each new bullet should start with a distinct opening clause ("When a plan precondition asserts …", "When a plan specifies both …", "When a plan FR conditions on a single enum …") so a 2026-future operator can find the rule by the symptom they're hitting. Avoid burying the operative verb after a long preamble.
- The review/SKILL.md Defect Classes list uses **bold lead clause** + em-dash + body. Mirror this for the new entry so the catalog stays scan-readable.
- Sibling Sharp Edges bullets that cite a PR # without a learning file path are stylistically tolerated, but every new bullet added by this PR MUST cite the learning file path — the path is the durable artifact; PR numbers redirect to closed issues.
- Cross-skill prose edits (`plan/SKILL.md` + `review/SKILL.md` in one PR) are exactly the `cross-cutting-refactor` scope-out criterion that triggered #3667's filing. This plan is the deferred remediation, not a new violation — the work is in-scope here because the issue is the explicit authorization.
- When `/work` implements Phase 1 and Phase 2, do them as **separate commits** if at all possible (one commit per skill file) so `git log -- plugins/soleur/skills/plan/SKILL.md` and `git log -- plugins/soleur/skills/review/SKILL.md` both show clean single-purpose entries. If a single combined commit is shipped, the PR body MUST enumerate both file changes explicitly.

## Test Strategy

Grep-based AC verification (AC1-AC7), skill-budget test (AC8: `bun test plugins/soleur/test/components.test.ts`), and scope check (AC9: `git diff origin/main...HEAD --name-only` returns exactly 2 paths). No new fixtures, no new framework, no new dependencies.

## Resume prompt (copy-paste after `/clear`)

```text
/soleur:work knowledge-base/project/plans/2026-05-12-feat-route-to-definition-plan-review-skills-plan.md. Branch: feat-one-shot-3667-route-to-definition. Worktree: .worktrees/feat-one-shot-3667-route-to-definition/. Issue: #3667. Plan reviewed, implementation next.
```
