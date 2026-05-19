---
title: "chore(brainstorm): tighten Phase 1.0.5 / 2.5 / Phase 2 checkpoint prose for exit-branch clarity"
date: 2026-05-15
type: chore
issue: 3836
related_prs: [3808]
related_issues: [2733]
lane: single-domain
brand_survival_threshold: none
---

# chore(brainstorm): tighten Phase 1.0.5 / 2.5 / Phase 2 checkpoint prose for exit-branch clarity

## Enhancement Summary

**Deepened on:** 2026-05-15
**Sections enhanced:** Overview, Research Reconciliation, Acceptance Criteria (AC7/AC9), Sharp Edges, Risks.

### Key Improvements

1. **Skill-description-budget claim corrected — load-bearing.** Plan v1 stated "corpus is at 2251 / 1800 words, already over cap, test failing on main." Verification against the canonical algorithm — `plugins/soleur/test/components.test.ts:147–164`, which parses YAML frontmatter and word-splits the `description:` value — returns **1840 words / 1850 cap = 10 words headroom** on main, and `bun test plugins/soleur/test/components.test.ts` exits **green**. My v1 shell `grep -h 'description:' SKILL.md | wc -w` counted the literal `description:` token, raw quotes, and prose around descriptions — apples-to-oranges with the test's frontmatter parse. The plan now cites the canonical 1840 / 1850 (10 headroom) baseline and the green test status.
2. **Two adjacent budget systems disambiguated.** PR #3808's body cites "B_ALWAYS=22,687 > 22,000 critical" — that is the **AGENTS.md byte budget** policed by `scripts/lint-agents-rule-budget.py` (lefthook gate), NOT the skill description word budget policed by `components.test.ts`. The two are independent. The plan now distinguishes them and scopes AC8 / AC9 to the correct gate.
3. **AC grep tokens verified unique on main.** All six AC grep markers (`If the feature description references named external`, `Three exit branches`, `Productize Candidate:`, `operator names a new skill`, `sibling-trim sub-plan`, `DIVERGENCE.*#3836`) currently return **zero matches** across `plugins/soleur/skills/{brainstorm,plan,work}/SKILL.md` — so AC1–AC6 cannot false-pass before the corresponding Edit lands. Grep-verified at deepen-plan time.
4. **Citations re-verified live.** `gh pr view 3808 → MERGED`, `gh issue view 2733 → CLOSED`, `gh issue view 3836 → OPEN`. All titles match the plan's narrative. `wc -l` confirms current line numbers 199 (`#### 1.0.5`), 268 (`### Phase 2: Explore Approaches`), 284 (Budget checkpoint paragraph), 286 (`### Phase 2.5: Productize Checkpoint`).
5. **Heading-level note.** Phase 1.0.5 is at `####` (h4 — sub-section of Phase 1), Phase 2 budget checkpoint is a bold-emphasized paragraph (NOT a heading), Phase 2.5 is at `###` (h3 — sibling of Phase 2). The grep ACs do not anchor on heading depth, so this asymmetry is benign — but worth noting so the /work agent does not "normalize" the headings as a drive-by.

### New Considerations Discovered

- The skill corpus has **exactly 10 words of headroom** against the 1850 cap, which is the threshold value the AGENTS.md `cq-skill-description-budget-headroom` rule monitors. This plan touches body text only — no skill description edits — so the headroom is preserved. But any future PR that adds even one word to a skill description without trimming will trip the test. This is the precise scenario `cq-skill-description-budget-headroom` exists to catch; this plan is incidental evidence that the rule's threshold is well-calibrated.
- The lefthook `lint-agents-rule-budget.py` byte budget (22,000) is a different system, on a different file (AGENTS.md + sidecars), with a different policing surface (lefthook pre-commit, not CI). PR #3808's OB1 is about THAT budget, not this one. They are sometimes conflated in operator memory; the plan now scopes each AC to its gate.
- The proposed divergence-comment marker uses `#3836` (this issue) as the anchor, not `#2733` (the parent issue). Future operators grepping for "verbatim #2733" will not find this divergence; future operators grepping for `DIVERGENCE.*#3836` or `DIVERGENCE from #2733` will. AC6's grep matches both — the marker text itself begins with `DIVERGENCE from #2733 verbatim per #3836:`.

## Overview

PR #3808 implemented #2733's Phase 1.0.5 (Premise Validation), Phase 2.5 (Productize Checkpoint), and Phase 2 inline budget checkpoint **verbatim with #2733's issue body**. The verbatim choice was deliberate (Kieran's plan-review and git-history-analyzer dual-verified character-for-character match) but spec-flow-analyzer's review of the same prose flagged five distinct prose-level ambiguities — trigger predicates undefined, exit branches missing, artifact contracts unspecified, detection mechanisms unstated, and outcome semantics for budget-headroom failures left implicit.

The verbatim text was load-bearing for #3808's plan-review acceptance criteria. Changing it inside #3808 would have diverged from the issue body's prescribed text and triggered re-verification of the AC's character-match invariant. Five spec-flow gaps were deliberately deferred as **out-of-bundle follow-up OB4** (PR #3808 body, "Out-of-bundle follow-ups").

This issue (#3836) is that follow-up: a **prose-tightening pass** on the three brainstorm SKILL.md sections that mirror #2733's body — no new functionality, no new phases, no new behavior beyond making the existing exit branches explicit.

**What is in scope.** Five `Edit` operations in `plugins/soleur/skills/brainstorm/SKILL.md` on lines 199–288 (Phase 1.0.5, Phase 2 Budget checkpoint, Phase 2.5). Each Edit replaces an ambiguous sentence with a tighter form that names triggers, exits, and artifacts explicitly.

**What is NOT in scope.**

- Editing #2733's issue body (option 1 from the issue's "Proposed approach"). The issue is closed, and historiographically the verbatim record should remain. This plan adopts **option 2** (just update brainstorm SKILL.md and note divergence here).
- Changing skill descriptions, AGENTS.md rules, or AGENTS sidecars. The skill description corpus is at **1840 / 1850 words = 10 words headroom** on main (canonical `components.test.ts` measure, verified at deepen-plan time). The corpus is currently UNDER the cap — `bun test plugins/soleur/test/components.test.ts` is green — but a single description-line edit could trip `cq-skill-description-budget-headroom` (the rule fires at < 10 words headroom). This plan touches body text only, preserving the headroom intact.
- New behavior in `/work`, `/plan`, `/review`. The tightened prose still describes the same operations.
- Re-running spec-flow-analyzer against the tightened prose at PR time. spec-flow's flagged gaps from PR #3808's plan-review window are the canonical list; closing them is the AC.

## Research Reconciliation — Spec vs. Codebase

| Claim from #3836 body | Codebase reality | Plan response |
|---|---|---|
| "PR #3808 implemented Phase 1.0.5 / 2.5 / Phase 2 inline budget verbatim with #2733's issue body" | Confirmed: `plugins/soleur/skills/brainstorm/SKILL.md` lines 199–201 (Phase 1.0.5), 284 (Phase 2 budget checkpoint), 286–288 (Phase 2.5) match #2733 prose char-for-char (validated against PR #3808's `Verbatim quote integrity` checkbox + the corresponding git-history-analyzer pass). | Direct Edit targets are these three locations. |
| "Phase 1.0.5 trigger predicate undefined — three readings are valid" | Confirmed: current text begins "Before launching research agents, grep existing truth sources..." — reads as always-run on first pass; the inline list ("CI report, roadmap, prior brainstorms ... named external entities or claims in the feature description") implies conditional on named entities; reads as exhaustive sweep otherwise. | Edit 1 makes the trigger explicit ("If the feature description references...") and lists the trigger classes. |
| "Phase 1.0.5 no exit branches for contradiction" | Confirmed: current text says "surface the contradiction and re-scope with the user" — no enumerated operator response options. | Edit 2 adds the three-branch exit enumeration (a/b/c) from #3836's proposed clarifications. |
| "Phase 2.5 no artifact contract for 'yes recurring'" | Confirmed: current text is a question without a downstream artifact. | Edit 3 adds the `Productize Candidate: <skill-name>` Key Decisions entry contract — "do not pivot the current brainstorm" is explicit. |
| "Phase 2 budget checkpoint detection mechanism undefined" | Confirmed: current text ("if the brainstorm proposes adding or restructuring skills") fires at a point where approaches are being authored — proposal doesn't exist at the trigger point. | Edit 4 reframes the trigger as operator-self-detected on naming a new skill OR proposing a `description:` edit. |
| "Phase 2 budget checkpoint `< 10 words` outcome undefined" | Confirmed: current text ("Surface headroom as a first-class constraint") doesn't define abort / force-trim / annotate semantics. | Edit 5 (same Edit block as Edit 4) makes the outcome explicit: approach options without sibling-trim sub-plans are invalid. |
| "Touching the skill description fires `cq-skill-description-budget-headroom`" | Confirmed via the canonical algorithm in `plugins/soleur/test/components.test.ts:147–164`: 1840 words / 1850 cap = **10 words headroom**. `bun test plugins/soleur/test/components.test.ts` is green on `origin/main`. The plan's v1 baseline (2251 / 1800) was derived from a naive `wc -w` and is non-canonical; corrected here. | Plan scope explicitly excludes `description:` edits. Only body text changes — preserves the 10-word headroom intact. |
| "spec-flow gaps from PR #3808 plan-review (Flows 1–5) are the AC" | #3836 re-evaluation criteria: "Spec-flow-analyzer's flagged gaps (Flows 1-5 from PR #3808's plan-review) resolve" | AC checklist enumerates the five gaps and the prose change that closes each. |

## User-Brand Impact

**If this lands broken, the user experiences:** No user-facing artifact. Brainstorm is an internal authoring skill; the worst case is operator confusion at the next brainstorm run on a skill-editing topic.

**If this leaks, the user's [data / workflow / money] is exposed via:** Not applicable — body-text-only edits to an authoring skill; no regulated data, no external surface, no monetary path.

**Brand-survival threshold:** none, reason: prose-tightening of an internal authoring-skill body has no user-facing artifact and no exposure vector. Operator confusion at brainstorm time degrades agent compute efficiency, not brand.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Phase 1.0.5 trigger explicit.** `plugins/soleur/skills/brainstorm/SKILL.md` line 199 body starts with a conditional clause naming the trigger classes: named external systems, prior issues, prior brainstorms, OR numerical claims (caps, counts, byte budgets). Verify: `grep -n "If the feature description references named external" plugins/soleur/skills/brainstorm/SKILL.md` returns one match in the Phase 1.0.5 block.
- [ ] **AC2 — Phase 1.0.5 three-branch exits enumerated.** Same section names exits (a) confirmed → proceed to 1.1, (b) contradiction → re-scope with operator and restart 1.0.5 on revised framing, (c) operator override → annotate in brainstorm body and proceed. Verify: `grep -cE "\(a\) confirmed|\(b\) contradiction|\(c\) operator override" plugins/soleur/skills/brainstorm/SKILL.md` returns 3.
- [ ] **AC3 — Phase 2.5 artifact contract explicit.** Phase 2.5 body names the `Productize Candidate: <skill-name>` Key Decisions entry and the "do not pivot the current brainstorm" guarantee. Verify: `grep -n "Productize Candidate:" plugins/soleur/skills/brainstorm/SKILL.md` returns one match in the Phase 2.5 block.
- [ ] **AC4 — Phase 2 budget checkpoint trigger explicit.** Phase 2 "Budget checkpoint" paragraph reframes the trigger as operator-self-detected: fires when the operator names a new skill OR proposes editing a `description:` in any approach option. Verify: `grep -nE "operator names a new skill|proposes editing a .description:." plugins/soleur/skills/brainstorm/SKILL.md` returns matches in the Phase 2 budget block.
- [ ] **AC5 — Phase 2 budget checkpoint outcome explicit.** Same paragraph defines the `< 10 words headroom` outcome: each approach option MUST include a sibling-trim sub-plan; approaches without one are invalid and must be rewritten or dropped. Verify: `grep -n "sibling-trim sub-plan" plugins/soleur/skills/brainstorm/SKILL.md` returns one match in the Phase 2 budget block.
- [ ] **AC6 — Verbatim-divergence note exists.** A new comment line near the Phase 1.0.5 / Phase 2 budget / Phase 2.5 sections (or a single consolidated `<!-- DIVERGENCE: tightened per #3836 ... -->` marker) records that the prose intentionally diverges from #2733's issue body for the reasons documented in #3836. Verify: `grep -n "DIVERGENCE.*#3836" plugins/soleur/skills/brainstorm/SKILL.md` returns at least 1 match.
- [ ] **AC7 — No skill description corpus change.** The canonical word count via `plugins/soleur/test/components.test.ts`'s frontmatter-parse algorithm is **1840 words / 1850 cap = 10 words headroom** on `origin/main` (verified at deepen-plan time). The plan does NOT alter any `description:` line. A quick post-edit canonical re-measure must still return 1840 / 1850. The naive operator command `grep -h 'description:' plugins/soleur/skills/*/SKILL.md \| wc -w` is NOT canonical (counts the literal `description:` token and quoting) and returns ~2251 — do NOT use it as the gate.
- [ ] **AC8 — No AGENTS.md / AGENTS.{core,docs,rest}.md change.** `git diff origin/main -- AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` is empty. (This is a separate budget system from AC7 — the AGENTS.md byte budget is policed by `scripts/lint-agents-rule-budget.py` via lefthook, not by `components.test.ts`.)
- [ ] **AC9 — Skill-description test stays green.** `bun test plugins/soleur/test/components.test.ts` exits 0 — currently green on `origin/main` with 1840 / 1850 words. This plan does not touch any `description:` line, so the test status MUST not regress. If this AC fails, scope drift has occurred and Edit 1–6 must be re-inspected for an accidental `description:` field change.
- [ ] **AC10 — PR body references the verbatim divergence.** PR body's "Why this matters" section explicitly notes the option-1 vs option-2 trade-off from the #3836 issue body (the divergence is option 2 — SKILL.md updated, #2733 issue body left as historiographic record).

### Post-merge (operator)

- [ ] **AC11 — Re-evaluation at next skill-editing brainstorm.** When the next `/soleur:brainstorm` invocation touches a skill-editing topic, no operator confusion about "what fires when" in Phase 1.0.5 / Phase 2.5 / Phase 2 budget checkpoint. This is operator-side validation — not automatable, but the rest of the AC checklist is the structural proof that the prose change landed correctly. Closes #3836 on merge (`Closes #3836` in PR body).

## Files to Edit

- `plugins/soleur/skills/brainstorm/SKILL.md` — five `Edit` operations on lines 199–288.

  1. **Phase 1.0.5 trigger** (line 201, the body sentence "Before launching research agents, grep existing truth sources..."). Replace with:

     ```text
     If the feature description references named external systems, prior issues, prior brainstorms, or numerical claims (caps, counts, byte budgets), grep existing truth sources (CI report, roadmap, prior brainstorms) for those named entities or claims before launching research agents. ...
     ```

     The trailing "If the framing contradicts what the ground truth documents say, surface the contradiction..." prefix is replaced by the three-branch exits in Edit 2.

  2. **Phase 1.0.5 exits** (same paragraph, continuing). Append after the trigger-explicit sentence:

     ```text
     Three exit branches: (a) confirmed → proceed to 1.1; (b) contradiction → re-scope with the operator and restart 1.0.5 on the revised framing; (c) operator override → annotate the disagreement in the brainstorm body and proceed. A framing defect caught here is worth more than a full research sprint built on it.
     ```

  3. **Phase 2.5 artifact contract** (line 288, body "When proposing an action plan, ask: is the inciting work pattern likely to recur..."). Replace the closing sentence ("If yes, propose a skill or sub-mode of an existing skill that captures the workflow.") with:

     ```text
     If yes, record a `Productize Candidate: <skill-name suggestion>` entry in the brainstorm's Key Decisions block; do NOT pivot the current brainstorm. The candidate becomes a follow-up issue (filed at brainstorm-end via the existing deferred-item issue-creation step), not a brainstorm scope change.
     ```

  4. **Phase 2 budget checkpoint trigger** (line 284, body sentence "If the brainstorm proposes adding or restructuring skills, run the SKILL.md description word-budget measurement one-liner..."). Reframe the leading clause:

     ```text
     The Budget checkpoint fires when the operator names a new skill or proposes editing a `description:` line in any approach option (operator self-detects on naming, not pre-emptively). When fired, run the SKILL.md description word-budget measurement one-liner ...
     ```

  5. **Phase 2 budget checkpoint outcome** (same paragraph, replace the closing sentence "Surface headroom as a first-class constraint if < 10 words remain..."). Replace with:

     ```text
     If headroom is < 10 words against the 1800-word cumulative cap, each approach option MUST include a sibling-trim sub-plan that frees at least the required number of words. Approach options without a sibling-trim sub-plan are invalid and must be rewritten or dropped before Phase 2 closes. Surface the headroom number as a first-class constraint in the approach comparison table.
     ```

  6. **Divergence comment** (single HTML comment placed once near the Phase 1.0.5 heading at line 199, or duplicated across the three sections — the AC requires only one match):

     ```html
     <!-- DIVERGENCE from #2733 verbatim per #3836: trigger predicates and exit branches made explicit for Phases 1.0.5 / 2.5 / Phase 2 inline budget. Spec-flow-analyzer Flows 1-5 from PR #3808 plan-review. -->
     ```

## Files to Create

- None.

## Files NOT to Edit

- `plugins/soleur/skills/brainstorm/references/*.md` — spec-flow gaps are confined to the SKILL.md prose (those three phase blocks). Reference files were not flagged.
- `AGENTS.md`, `AGENTS.core.md`, `AGENTS.docs.md`, `AGENTS.rest.md` — no rule changes.
- Any `description:` line anywhere — corpus already over cap.

## Implementation Phases

### Phase 0 — Preconditions

- [ ] `git branch --show-current` returns `feat-one-shot-3836`.
- [ ] Canonical skill-description corpus is **1840 / 1850 words = 10 headroom**, measured via `bun test plugins/soleur/test/components.test.ts` (green on main) or the inline Node measurement one-liner from `knowledge-base/project/learnings/2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`. Any change to that count after the edits means scope drift into a `description:` field.
- [ ] `grep -n "Phase 1\.0\.5 Premise Validation\|Phase 2\.5: Productize Checkpoint\|Budget checkpoint" plugins/soleur/skills/brainstorm/SKILL.md` returns three lines: 199, 284, 286.

### Phase 1 — Edit Phase 1.0.5 (trigger + exits)

- [ ] Apply Edit 1 (trigger predicate).
- [ ] Apply Edit 2 (three-branch exits).
- [ ] Grep verification for AC1 and AC2 passes.

### Phase 2 — Edit Phase 2 budget checkpoint (trigger + outcome)

- [ ] Apply Edit 4 (operator-self-detected trigger).
- [ ] Apply Edit 5 (sibling-trim-sub-plan outcome).
- [ ] Grep verification for AC4 and AC5 passes.

### Phase 3 — Edit Phase 2.5 (artifact contract)

- [ ] Apply Edit 3 (`Productize Candidate:` Key Decisions entry).
- [ ] Grep verification for AC3 passes.

### Phase 4 — Divergence comment

- [ ] Insert the `<!-- DIVERGENCE from #2733 ... -->` comment near the Phase 1.0.5 heading.
- [ ] Grep verification for AC6 passes.

### Phase 5 — Verify no scope drift

- [ ] Canonical skill-description count still 1840 / 1850 (AC7) via the test or the Node measurement one-liner.
- [ ] `git diff origin/main -- AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` empty (AC8).
- [ ] `bun test plugins/soleur/test/components.test.ts` exits 0 — green on main, must remain green (AC9).

### Phase 6 — Commit + push + open PR

- [ ] One commit: `docs(brainstorm): tighten Phase 1.0.5 / 2.5 / Phase 2 inline budget prose (#3836)`.
- [ ] `Closes #3836` in PR body, NOT title (`wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] PR body's "Why this matters" notes the option-1 / option-2 trade-off (AC10).

## Test Strategy

**No new tests.** This is a body-text-only documentation change in an authoring skill.

**Existing test coverage exercised:**

- `bun test plugins/soleur/test/components.test.ts` runs the cumulative skill description word-count gate. The gate's threshold (1800 words) is already exceeded on `origin/main` (2251 words per PR #3808 OB1 pre-existing-state acknowledgement). This plan's AC9 explicitly accepts that pre-existing state and asserts only no further regression.
- `python3 scripts/lint-rule-ids.py` is unaffected (no AGENTS.md changes).
- `python3 scripts/lint-agents-rule-budget.py` is unaffected.

**Manual verification:**

- The six grep ACs (AC1–AC6) replace the role test coverage would play. They are deterministic, regex-precise, and demonstrably resolvable.
- AC11 (operator-side re-evaluation at next brainstorm) is the only manual gate — it lives in Post-merge (operator) and closes naturally on next session.

## Risks

- **R1 — Prose drift if operator hand-edits during apply.** The five Edits are sequential and small; an inattentive operator could partially apply Edits 4 and 5 (same paragraph) and produce malformed text. Mitigation: AC4 and AC5 are independently grep-verifiable; failure of either is visible immediately. Risk severity: low (single-file, single-paragraph).
- **R2 — Future spec-flow re-analysis finds additional gaps in the tightened prose.** spec-flow-analyzer is non-deterministic; new prose can introduce its own ambiguities. Mitigation: the proposed text from #3836's body is the canonical specification — operator chose this exact wording at issue-filing time, so spec-flow's later re-analysis is expected to converge. If new gaps surface post-merge, file a separate follow-up; do not block this PR. Risk severity: low.
- **R3 — Divergence-comment churn at later edits.** The `<!-- DIVERGENCE -->` marker creates a maintenance obligation: future edits to Phases 1.0.5 / 2.5 / Phase 2 budget should either preserve the marker or update its content. Mitigation: the marker is self-documenting (cites #3836 and PR #3808); a future operator can re-derive its intent. Risk severity: low.
- **R4 — Operator carry-over of stale brainstorm-of-brainstorms muscle memory.** Operators who internalized the verbatim prose from #2733 may default to the looser semantics in real brainstorm runs. Mitigation: the divergence comment is in-line; AC11 makes the operator-side re-evaluation explicit. Risk severity: low.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --json number,title,body --limit 200` then `jq` over the planned file path (`plugins/soleur/skills/brainstorm/SKILL.md`) returned no open code-review issues touching this file.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a body-text prose-tightening change to an internal authoring skill, with no user-facing surface, no regulated-data path, no UI, no copy-strategy concern, no infrastructure change, no monetary path. Routed as a **single-domain (engineering / docs)** change per `lane: single-domain` in frontmatter.

The Product/UX Gate is NONE: the brainstorm skill is operator-facing-engineer tooling, not user-facing UI. The mechanical escalation regex (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`) does not match any planned edit.

GDPR / Compliance Gate (plan §2.7): not invoked — no regulated-data surface touched; no LLM-on-operator-data processing change; no public PR-body distribution change; no plugin update artifact change.

Brainstorm-recommended specialists: none (no brainstorm document exists for this issue; this plan is filed directly from the #3836 issue body, which already contains the canonical clarifications).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. The threshold is set to `none` with a one-sentence rationale; this satisfies the preflight Check 6 sensitive-path regex if it fires, but for this plan no sensitive-path regex matches (no schema, no migration, no auth flow, no API route, no `.sql` file in scope).
- The skill description corpus is at **1840 / 1850 = 10 words headroom** (canonical `components.test.ts` measure). The corpus is UNDER cap and the test is green; this plan preserves both. A naive `wc -w` over `grep -h 'description:'` returns ~2251 and is misleading — the canonical algorithm parses YAML frontmatter and counts only the value-side word-split. This plan's AC7 explicitly excludes any `description:` edit. If a future amendment is tempted to "while we're here" trim a sibling description, that becomes a different PR — bundling it here would smuggle in a corpus change masquerading as a prose-clarity PR.
- The verbatim-quote integrity invariant from PR #3808 is **intentionally broken** by this PR. The DIVERGENCE comment is the load-bearing artifact that records the break, with #3836 and PR #3808 as the audit trail. Future operators who grep for "verbatim #2733" will find the comment AND the issue body; the divergence is not silent.
- The plan does NOT touch `plugins/soleur/skills/brainstorm/references/*.md`. spec-flow-analyzer's flagged gaps are confined to the SKILL.md prose. If a future operator widens the scope to references, that is a new issue.
- `wg-use-closes-n-in-pr-body-not-title-to`: `Closes #3836` goes in the PR body, not the title.
- The B_ALWAYS = 22,687 critical state from PR #3808 OB1 is a **distinct budget system** (AGENTS.md byte budget, policed by lefthook via `scripts/lint-agents-rule-budget.py`) — not the skill-description word budget that AC7/AC9 cover. This plan does not regress the B_ALWAYS byte count (no AGENTS.md edits), but it also does not reduce it; OB1 remains the immediate-next priority on its own.

## Research Insights

### Best Practices Applied (deepen-pass)

- **Paraphrase-without-verification caught on own plan.** Per `knowledge-base/project/learnings/2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md` and PR #3625's plan-time parsing learning, plan-author claims about codebase numeric state must be grepped/measured before freezing. The v1 baseline (2251 / 1800 / "test failing on main") was a textbook instance of this defect — caught at deepen-plan via direct test run + reading the test source. The plan now cites canonical 1840 / 1850 with the test status.
- **Adjacent-system conflation hazard.** AGENTS.md byte budget (22000) and skill-description word budget (1850) are independent systems on independent files policed by independent gates. The plan body explicitly separates them (AC7/AC9 → word budget; AC8 → byte budget reference only).
- **AC grep tokens verified unique on main.** All six AC markers return zero matches in the brainstorm/plan/work SKILLs, so each AC's pass-condition is genuinely load-bearing and not pre-satisfied by accident.
- **Citations resolved live.** `gh pr view 3808 → MERGED`, `gh issue view 2733 → CLOSED`, `gh issue view 3836 → OPEN`. Titles match plan narrative. PR-number-paraphrase-without-verification (per `2026-05-05-cc-stuck-active-conversation-leaks-slot.md` Session Error #1) avoided.

### Edge Cases Discovered (deepen-pass)

- **Phase 2 budget checkpoint operator-detection wording.** Edit 4's "operator self-detects on naming, not pre-emptively" is the load-bearing clause — it prevents Phase 2 from being interpreted as "scan every approach for hidden description edits." The operator declares the trigger by naming a new skill OR by proposing a `description:` edit in an approach option's prose. Both shapes count; neither requires Phase 2 to introspect.
- **Heading-level asymmetry.** Phase 1.0.5 = `####` (h4), Phase 2.5 = `###` (h3), Phase 2 budget = bold paragraph (not heading). The /work agent must preserve these levels — a drive-by "normalize heading depth" would change the rendered ToC and is out of scope. AC grep tokens do not anchor on heading depth, so this risk is detectable only at human-review.
- **DIVERGENCE marker placement.** AC6 requires `≥ 1` match for `DIVERGENCE.*#3836`. Placing the marker once near Phase 1.0.5 satisfies it. Placing it three times (one per section) is also valid. Single-placement is preferred for brevity; the marker text itself names all three sections in its body.

### Implementation Notes

- The five Edits are sequential and independent. Order: Phase 1.0.5 (Edits 1 + 2), Phase 2 budget (Edits 4 + 5), Phase 2.5 (Edit 3), then divergence comment (Edit 6). Phase ordering in `## Implementation Phases` reflects this.
- No tests need to be added or changed. The 73 existing components.test.ts subtests and the skill-description corpus test all stay green.
- Commit message: `docs(brainstorm): tighten Phase 1.0.5 / 2.5 / Phase 2 inline budget prose (#3836)`. NOT a `chore:` prefix despite the issue title — the actual edit is documentation prose, not maintenance scaffolding.

### References (research)

- Issue body for #3836 — contains the canonical clarifications, used verbatim in Edits 1–5.
- `plugins/soleur/test/components.test.ts:140–171` — canonical skill description word budget definition (1850 cap).
- `knowledge-base/project/learnings/2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md` — the Measurement one-liner; Phase 2 Edit 4's text now references this learning for the canonical measurement form.
- `knowledge-base/project/learnings/2026-05-15-multi-stage-premise-validation-compounds-and-agents-sidecar-loader-class-fit.md` — direct evidence (N=3) that the proposed Phase 1.0.5 clarifications close real defect classes.

## References

- Issue #3836 — this plan's source.
- Issue #2733 — original "premise validation + productize checkpoint" issue whose body was implemented verbatim in PR #3808; this plan tightens that verbatim prose.
- PR #3808 — `feat-bundle-workflow-fixes` bundle that implemented #2733 + #2741. PR body lists OB4 (this issue) as out-of-bundle follow-up.
- `knowledge-base/project/learnings/2026-05-15-multi-stage-premise-validation-compounds-and-agents-sidecar-loader-class-fit.md` — direct evidence (Pattern 1, three independent stages) that the proposed clarifications are load-bearing.
- `knowledge-base/project/learnings/2026-05-15-brainstorm-issue-body-quantitative-state-drift.md` — single-instance capture of premise-validation value in a real brainstorm run.
- `knowledge-base/project/learnings/2026-04-21-peer-plugin-audit-brainstorm-patterns.md` — origin learning that motivated #2733.
- `plugins/soleur/skills/brainstorm/SKILL.md:199–288` — current Phase 1.0.5 / Phase 2 budget checkpoint / Phase 2.5 prose, the edit target.
