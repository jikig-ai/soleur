---
lane: "procedural"
issue: "#3667"
pr_source: "#3653"
type: "compound-route-to-definition"
---

# Spec: Route-to-definition for plan + review skills (enum-gate + precondition grep)

**Issue:** #3667
**Branch:** feat-one-shot-3667-route-to-definition
**Source learning:** `knowledge-base/project/learnings/2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md`
**Source PR:** #3653

## Problem Statement

PR #3653 (cohort missing-reply marker) surfaced three plan-quality defects during its 11-agent review pass. All three were captured in a single compound learning file and routed to two skill files at compound time:

1. **Precondition false-pass via Read-not-Grep.** Plan §Phase 0.1 asserted `conversation.created_at` was accessible at the mount scope. The check was satisfied by reading the consuming code, not by grepping for the slice in the file that exposes the producing scope (`ws-client.ts`). Cost: three boundary edits during /work to plumb the field — small but avoidable.

2. **Component prop boundary vs `test.each` parameter row incompatibility.** Plan §1.1.2 listed parametrized test rows that needed `messages` + `createdAt` + `isStreamingAssistant` as inputs; plan §1.3.2 mount architecture pushed the predicate **outside** the component, exposing only `createdAt`. The two were mutually inconsistent. Cost: mid-/work pivot moving the predicate into the component to keep the brainstorm-owned test list verbatim.

3. **3-value enum gate slip.** Plan §FR2 refinement conditioned on `!isStreamingAssistant`. Codebase: `StreamState = "idle" | "streaming" | "stopping"`. The plan named one of three values; /work honored the plan verbatim; `user-impact-reviewer` caught the `"stopping"` slip at PR-review time **only because** the review-spawn prompt explicitly named the 3-value enum. The signal that prevented this from shipping was a review prompt that enumerated the enum, not the agent's pattern-matching by default.

Defects #1 and #2 are **plan-skill** gaps (plan-time guarantees insufficient). Defect #3 is a **plan + review** gap (FRs that condition on enum literals must enumerate every member; review agents must prompt for every member).

The fix is documentation-only: three Sharp Edges entries in `plugins/soleur/skills/plan/SKILL.md`, and one Defect Class catalog entry in `plugins/soleur/skills/review/SKILL.md`. Per compound skill's file-issue exception, edits spanning ≥2 skill files file as a deferred-scope-out rather than inline-edit on an unrelated feature PR — which is exactly what happened for #3653, producing this issue.

## Goals

- **G1.** Add three Sharp Edges entries to `plugins/soleur/skills/plan/SKILL.md` covering: (a) precondition grep on the producing-scope file (not just Read of the consuming file), (b) parametrized test list ↔ component prop boundary cross-check at plan time, (c) enum-gate enumeration rule (every union member classified include/exclude).
- **G2.** Add one Defect Class catalog entry to `plugins/soleur/skills/review/SKILL.md` instructing `user-impact-reviewer` and `pattern-recognition-specialist` agents: when reviewing a gate conditioned on `X === <literal>` where `X` is a TypeScript union/enum, enumerate every union member and ask "is the gate correct for each value?"
- **G3.** Each entry MUST cite PR #3653 and the source learning file, in the existing Sharp Edges / Defect Classes citation format (`**Why:** PR #N — …. See <learning-path>.`).
- **G4.** No source-code edits. Two markdown files only. No new commands, no new agents, no schema changes.

## Non-Goals

- **NG1.** Adding a programmatic enforcement hook (PreToolUse / SessionStart) for the enum-gate rule. The defect class is structurally hard to detect from the model boundary — it requires type-graph knowledge — and lives correctly in plan + review prose for now. A future hook is out of scope.
- **NG2.** Refactoring sibling Sharp Edges entries or trimming the lists. The plan SKILL.md Sharp Edges list is already long (~70 entries); pruning is a separate cleanup PR with its own criteria.
- **NG3.** Editing the source learning file. It is already the canonical record; the skill edits link back to it.
- **NG4.** Adding test fixtures or marker tests. Sharp Edges are operator-facing prose; the only build-time gate is the skill description word-budget check, which these edits do NOT affect (Sharp Edges live in the body, not the frontmatter).

## Functional Requirements

- **FR1.** `plan/SKILL.md` MUST contain a Sharp Edges bullet whose intent is: when a plan precondition asserts "X is accessible at scope Y", the check MUST include a grep for X in the file that defines scope Y — not just a Read of the consuming code. Cite PR #3653.
- **FR2.** `plan/SKILL.md` MUST contain a Sharp Edges bullet whose intent is: when a plan specifies both (a) a component architecture and (b) a `test.each([...])` parametrized test list, cross-check at plan time that every test row's fixtures map to the component's prop boundary. If the test list's inputs span predicate state the architecture pushes outside the component, one of the two must change. Cite PR #3653.
- **FR3.** `plan/SKILL.md` MUST contain a Sharp Edges bullet whose intent is: when a plan FR conditions on a single enum value (`X === "streaming"`, `status === "completed"`), the FR text MUST classify EVERY union member of `X` as include or exclude. Single-value FRs against multi-member unions hide a class of bug under future schema widening. Cite PR #3653 with the `streamState` "stopping" example.
- **FR4.** `review/SKILL.md` Defect Classes catalog MUST contain a bullet directing `user-impact-reviewer` / `pattern-recognition-specialist` reviewers: when a gate is conditioned on `X === <literal>` where `X` is a TypeScript union/enum, enumerate every union member and verify the gate is correct for each value. Cite PR #3653.
- **FR5.** All four entries MUST follow the existing inline-paragraph format of their respective files (`plan/SKILL.md` uses single-bullet inline citations; `review/SKILL.md` Defect Classes uses inline-paragraph bullets with named pattern + `Reviewer takeaway` line + `**Why:** PR #N — … See <path>.`).

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** `grep -c "PR #3653" plugins/soleur/skills/plan/SKILL.md` returns ≥ 3 (one per FR1/FR2/FR3 entry).
- **AC2.** `grep -c "PR #3653" plugins/soleur/skills/review/SKILL.md` returns ≥ 1 (FR4 entry).
- **AC3.** `grep -c "2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md" plugins/soleur/skills/plan/SKILL.md plugins/soleur/skills/review/SKILL.md` returns ≥ 4 (one citation per added entry).
- **AC4.** `grep -nE "precondition.*grep|grep.*precondition|producing-scope|producing scope" plugins/soleur/skills/plan/SKILL.md` returns ≥ 1 match in the Sharp Edges section (line ≥ 686). (FR1 marker.)
- **AC5.** `grep -nE "test\.each|parametrized test|test list" plugins/soleur/skills/plan/SKILL.md | grep -i "prop boundary\|component"` returns ≥ 1 match in the Sharp Edges section. (FR2 marker.)
- **AC6.** `grep -nE "enum-gate|enum gate|every union member|every member of the union|classify every" plugins/soleur/skills/plan/SKILL.md` returns ≥ 1 match in the Sharp Edges section. (FR3 marker.)
- **AC7.** `grep -nE "every union member|enumerate every|classify every" plugins/soleur/skills/review/SKILL.md` returns ≥ 1 match in the Defect Classes section (line ≥ 764 and ≤ ~780, before "See `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`"). (FR4 marker.)
- **AC8.** `bun test plugins/soleur/test/components.test.ts` passes — skill description word budgets are not affected because all edits are body-text, not YAML frontmatter.
- **AC9.** `git diff origin/main...HEAD --name-only` lists exactly two files: `plugins/soleur/skills/plan/SKILL.md` and `plugins/soleur/skills/review/SKILL.md`. (Per Goals G4 — markdown-only PR, no scope creep.)
- **AC10.** PR body uses `Closes #3667` (regular PR; not ops-remediation post-merge per the sharp edge on `wg-use-closes-n-in-pr-body-not-title-to`).

### Post-merge (operator)

- **AC11.** None — closure is automatic via `Closes #3667` on merge. No cron, no terraform apply, no manual verification step.

## Risks

- **R1.** Word-budget regression on plan/SKILL.md or review/SKILL.md skill frontmatter. **Mitigation:** edits are body-only; AC8 enforces. Sharp Edges live below the frontmatter and don't enter the skill description tokenizer.
- **R2.** Sharp Edges list pollution. The plan SKILL.md Sharp Edges list is already long (~70 entries); adding three more is +4% growth. **Mitigation:** each entry is one paragraph with a citation; the list's value comes from grepable specificity, not brevity.
- **R3.** Defect Class catalog drift. The review SKILL.md Defect Classes section is a curated catalog; a new entry should mirror the existing format (named pattern + agent that reliably catches it + Reviewer takeaway + Why+citation). **Mitigation:** FR5 enforces format mirroring; the entry will mirror the "Cross-stream format-contract drift" / "Replicated literals" entries which use the same shape.
- **R4.** Plan-skill self-reference: the new FR3 entry could be misread as applying only to TypeScript code (where unions are explicit). **Mitigation:** the wording will say "enum / union" and give a TypeScript example, but the FR is general (any predicate over a finite value set with ≥ 3 members benefits from explicit enumeration). The PR #3653 example happens to be TypeScript, but the principle applies to Postgres CHECK constraints, Zod schemas, Rust enums, etc. — out of scope to expand here.

## User-Brand Impact

- **If this lands broken, the user experiences:** the `plan/SKILL.md` Sharp Edges section becomes harder to grep (broken formatting), or the new entries cite a wrong learning path producing a 404 link in operator-facing review output. The lower-bound failure mode is "operator wastes one cycle reading a malformed entry"; the upper-bound is the entries failing to fire as guidance and the same #3653-class defect recurring on a future plan.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A. Documentation-only PR touching two skill files. No regulated-data surfaces, no API routes, no schemas, no auth flows. Per `hr-gdpr-gate-on-regulated-data-surfaces` and the broadened triggers (a)/(b)/(c)/(d), none apply.
- **Brand-survival threshold:** `none`. **Reason:** plan- and review-skill prose edits are operator-facing guidance, not user-facing artifacts. Failure mode is "guidance entry doesn't fire" — the worst case is identical to the pre-PR state. No `single-user incident` exposure surface, no aggregate-pattern surface.

## Test Strategy

This is a markdown-only PR with no production code paths. Test strategy is grep-based AC verification per the Pre-merge ACs above plus the existing skill word-budget test:

1. **Grep-marker verification** — AC1 through AC7 collectively enforce that the four entries exist at the right line ranges in the right files with the right citations. Run them as a single bash block at the end of /work.
2. **Skill components test** — AC8: `bun test plugins/soleur/test/components.test.ts` (covers description word budgets and required frontmatter). Expected to pass; edits are body-text.
3. **No new test framework, no new fixtures, no new dependencies.** Per `Before a plan's Test Strategy names a specific framework`-style sharp edge, the existing `bun test` infrastructure covers this PR's test surface.

## Files to Edit

- `plugins/soleur/skills/plan/SKILL.md` — append three Sharp Edges bullets at end of `## Sharp Edges` section (current last bullet is the hyphenated-Python-module entry on line 758, citing PR #2723).
- `plugins/soleur/skills/review/SKILL.md` — append one Defect Class bullet at end of `### Defect Classes This Review Reliably Catches` list, before the `See <full-pattern-catalogue>` line (current line 779).

## Files to Create

None.

## Open Code-Review Overlap

No matches (queried `gh issue list --label code-review --state open --json number,title,body --limit 200` and grep'd for `plan/SKILL.md` and `review/SKILL.md` paths in the bodies of any open code-review issues — none currently touch these files). The deferred-scope-out for THIS work is #3667 itself, which is the parent — not an overlap.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)

**Status:** reviewed (inline assessment — single-domain markdown documentation change).
**Assessment:** This is a workflow-rule edit affecting the plan + review skill prose only. No code, no schema, no auth, no infrastructure. Per the lane assessment, this is a `procedural` lane PR. No specialist required beyond the standard plan-review trio (DHH, Kieran, code-simplicity) at plan-review time, which is the default for any plan.

No Product/UX gate fires (NONE tier — no user-facing surface).

## Research Reconciliation — Spec vs Codebase

| Issue body claim | Codebase reality (2026-05-12) | Plan response |
|------------------|-------------------------------|---------------|
| Add Sharp Edges entries to `plugins/soleur/skills/plan/SKILL.md` | `## Sharp Edges` section exists at line 686, current last bullet at line 758 cites PR #2723 (hyphenated Python modules). Format is single-paragraph bullets with optional `**Why:** PR #N — … See <learning-path>.` citation. | Append three new bullets after line 758 mirroring this format. |
| Add catalog entry to `plugins/soleur/skills/review/SKILL.md` "Defect Classes This Review Reliably Catches" | `### Defect Classes This Review Reliably Catches` exists at line 764. List ends at line 777 (last bullet cites PR #3521 vendor-pipeline). Closing line at 779: `See knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md ...`. Format is inline-paragraph bullets with named pattern + agents-that-catch + Reviewer takeaway + Why+citation. | Append one new bullet after line 777 (before the closing See line) mirroring this format. |
| Source learning exists at `knowledge-base/project/learnings/2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md` | Confirmed — file exists, 198 lines, frontmatter `pr: "#3653"`, three Drift sections + Slip section that map 1:1 to the three plan-skill bullets + one review-skill bullet. | Cite this learning in all four entries. |
| `streamState` 3-value enum is `"idle" \| "streaming" \| "stopping"` | Confirmed in the source learning (line 107: `StreamState = "idle" | "streaming" | "stopping"` from `ws-client.ts:47`). | Use this verbatim in FR3 / AC6 example. |
| PR #3653 is not yet cited in either SKILL.md | Confirmed — `grep "PR #3653"` returns zero hits in both files. | First-citation PR for #3653; AC1 / AC2 verify the introduction. |

No spec-vs-codebase divergence detected. The issue body's proposed edits align with the file structure and citation conventions in place at HEAD.

## GDPR / Compliance Gate

[skill-enforced: gdpr-gate at plan Phase 2.7]

Skipped silently per Phase 2.7 trigger predicate. Documentation-only PR; no schemas / migrations / auth flows / API routes / `.sql` files touched. None of triggers (a) LLM/external-API on operator-derived data, (b) `single-user incident` brand-survival threshold, (c) cron/workflow reading from `knowledge-base/project/learnings/` or `specs/`, (d) artifact distribution surface change apply.

## Implementation Phases

### Phase 1 — `plan/SKILL.md` Sharp Edges additions

Append three bullets to the end of `## Sharp Edges` (after line 758):

1. **Precondition-grep bullet (FR1)** — text shape:
   > When a plan precondition asserts "X is accessible at scope Y", the check MUST include `grep -nE '\bX\b' <file-that-defines-scope-Y>` — not just a Read of the consuming code. The consuming code can name a variable optimistically (`conversation.created_at` reads as if it's a property of an in-scope object) when the producing scope only exposes `conversationId: string` and a flat hook return; the read passes while the field doesn't exist at the proposed mount scope. **Why:** PR #3653 — plan §Phase 0.1 asserted `conversation.created_at` accessibility via Read; /work surfaced that `useWebSocket(conversationId)` returns slices without `conversationCreatedAt` and `/api/conversations/:id/messages` did not select the field. Three boundary edits required at /work to plumb the slice. See `knowledge-base/project/learnings/2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md`.

2. **Parametrized-test-list ↔ component-boundary bullet (FR2)** — text shape:
   > When a plan specifies both (a) a component architecture and (b) a parametrized test list (`test.each([healed, postFix, preWindow, streaming, postSunset])(...)`), cross-check at plan time that every test row's fixture inputs map to the component's prop boundary. If the test list's inputs span predicate state that the architecture pushes outside the component (e.g., the predicate lives at the mount site in an IIFE while the component takes only one prop), one of the two must change. Architecture > tests if tests can be rewritten to drive through a higher-level mount; tests > architecture if the test inputs are the load-bearing brainstorm-owned failure enumeration. **Why:** PR #3653 — plan §1.1.2 listed 5 test rows needing `messages` + `createdAt` + `isStreamingAssistant` while plan §1.3.2 mount IIFE exposed only `createdAt` to the component; /work pivoted to move the predicate into the component to keep the brainstorm-owned test list verbatim. See same learning file.

3. **Enum-gate enumeration bullet (FR3)** — text shape:
   > When a plan FR conditions on a single enum / union value (`X === "streaming"`, `!isStreamingAssistant`, `status === "completed"`), the FR text MUST classify EVERY union member of `X` as include or exclude. If `X` has N values, the FR must explicitly enumerate all N. Single-value FRs hide a class of bug under any future schema widening, and the work phase reliably honors the FR verbatim — the gap is structural in the FR, not in execution. **Why:** PR #3653 — plan §FR2 conditioned on `!isStreamingAssistant`; implementation bound it to `streamState === "streaming"`. Codebase: `StreamState = "idle" | "streaming" | "stopping"` (`ws-client.ts:47`); `"stopping"` is a distinct in-flight state during mid-aborts that the FR never named. `user-impact-reviewer` caught the slip at PR review only because the review-spawn prompt explicitly enumerated the 3-value enum — without that prompt, the agent would have echoed the same false-pass. Recovery renamed prop to `isTurnInFlight`, bound to `streamState !== "idle"`. See same learning file.

### Phase 2 — `review/SKILL.md` Defect Classes addition

Append one bullet to the end of `### Defect Classes This Review Reliably Catches` (after line 777, before the `See ...` closing line at 779). Text shape:

> **Single-literal gate over a multi-member union/enum** — when a TypeScript predicate gates behavior on `X === <literal>` (or `!isFoo`, `status === "completed"`) and `X` is a union/enum with ≥ 3 members, the gate is correct only by coincidence unless every member has been classified include/exclude in the originating FR. `user-impact-reviewer` and `pattern-recognition-specialist` reliably catch this **only when the review-spawn prompt explicitly enumerates the union members** — without the prompt, agents echo the plan's single-value framing as a false-pass. Reviewer takeaway: when reviewing a gate conditioned on `X === <literal>` where `X` is a TypeScript union/enum, enumerate every union member by grepping the type's declaration (`rg "type X =" <module>` or `grep -nE "X = .*\|"`), then ask "is the gate correct for each value?" Single-literal gates against multi-member unions are a known defect class. **Why:** PR #3653 — plan §FR2 conditioned on `!isStreamingAssistant`; work bound `streamState === "streaming"` while `StreamState = "idle" | "streaming" | "stopping"` (`ws-client.ts:47`). `"stopping"` is a distinct in-flight substate that mid-aborts traverse; a Stop click could have flashed the marker during that window. Caught only because the spawn prompt explicitly named the 3-value enum. See `knowledge-base/project/learnings/2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md`.

### Phase 3 — AC verification + commit

Run AC1-AC9 as a single grep block. Commit both files in one commit with message body referencing #3667 + #3653 + source learning path. Push.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`. (This plan satisfies the section above with threshold `none, reason: …`.)
- The plan/SKILL.md Sharp Edges list is grep-indexed by operators. Each new bullet should start with a distinct opening clause ("When a plan precondition asserts …", "When a plan specifies both …", "When a plan FR conditions on a single enum …") so a 2026-future operator can find the rule by the symptom they're hitting. Avoid burying the operative verb after a long preamble.
- The review/SKILL.md Defect Classes list uses **bold lead clause** + em-dash + body. Mirror this for the new entry so the catalog stays scan-readable.
- Sibling Sharp Edges bullets that cite a PR # but no learning file path are stylistically tolerated, but every new bullet added by this PR MUST cite the learning file path — the path is the durable artifact; PR numbers redirect to closed issues.
- When citing PR #3653 from the new bullets, link to the **source learning** for the explanatory body and let the bullet itself be the operator-facing rule. Don't re-narrate the cohort-marker context in any of the four bullets — the body belongs in the learning file.

## Resume prompt (copy-paste after `/clear`)

```text
/soleur:work knowledge-base/project/plans/2026-05-12-feat-route-to-definition-plan-review-skills-plan.md. Branch: feat-one-shot-3667-route-to-definition. Worktree: .worktrees/feat-one-shot-3667-route-to-definition/. Issue: #3667. Plan reviewed, implementation next.
```
