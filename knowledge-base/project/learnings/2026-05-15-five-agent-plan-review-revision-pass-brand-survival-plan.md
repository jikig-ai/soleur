---
date: 2026-05-15
category: best-practices
module: plan, plan-review, brand-survival
tags: [plan-revision, plan-review-panel, brand-survival-threshold, paraphrase-without-verification, vendor-misclassification, gdpr-gate-signature, defer-vs-ship, anchor-resolution-over-architecture, compound-from-revision-pass]
related-plan: knowledge-base/project/plans/2026-05-15-feat-clo-founder-threshold-detection-plan.md
related-brainstorm: knowledge-base/project/brainstorms/2026-05-15-claude-for-legal-evaluation-brainstorm.md
related-spec: knowledge-base/project/specs/feat-cc-legal-skill-bridge/spec.md
related-issues: ["#3785", "#3786"]
related-learnings:
  - knowledge-base/project/learnings/2026-05-15-evaluating-anthropic-first-party-plugin-marketplaces.md
  - knowledge-base/project/learnings/2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md
  - knowledge-base/project/learnings/best-practices/2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md
---

# Learning: 5-agent plan-review revision pass on a brand-survival single-user-incident plan

## Problem

The first draft of a `brand_survival_threshold: single-user incident` plan (CLO founder-threshold detection bridging to a vendor-neutral `recommended-tools.md` docs page) was structurally complete and internally coherent. The 5-agent plan-review panel (DHH + Kieran + code-simplicity + architecture-strategist + spec-flow-analyzer — the brand-survival-extended panel from `plan-review/SKILL.md`) caught 13+ issues spanning 6 distinct error classes that would each have surfaced at /work-time as either pivot-required failures or brand-survival regressions. The challenge was applying the panel's "BOTH-fire delete rule" cleanly without losing brainstorm-blessed deliverables.

## Solution

Apply the panel's findings via a single revision pass with explicit triage by panel-axis convergence. The plan-review skill's BOTH-fire rule ("when simplification AND correctness panels both fire on the same scope, prefer delete over fix") drove cuts that simultaneously dissolved 6+ "fix this specifically" findings.

### The 6 error classes the panel caught

#### 1. Phase-number paraphrase against source files (P0; plan-skill `paraphrase-without-verification` rule)

Plan said "Phase 1 Discovery short-circuit" 7+ times. Actual file: `legal-audit/SKILL.md` is `## Phase 0: Discovery / ## Phase 1: Context / ## Phase 2: Audit / ## Phase 3: Report`. The "Phase N Discovery" memory shape (most skills' first phase IS discovery, so it would be Phase 1 if 1-indexed) bled through into the plan body without grep verification.

**Detection:** Kieran AND arch-strategist independently grep-verified `^## Phase` against the actual file. Both surfaced as P0.

**Cost difference:** ~10 seconds at plan-write time (single grep) vs. /work-time pivot when the grep-search for "Phase 1" lands in `## Phase 1: Context` (which has no short-circuit message at all) and either no-ops or inserts the pointer in the wrong place.

#### 2. Vendor misclassification by package-name intuition

Plan v1 named `gosprinto/compliance-skills` as Tool B for DSAR / breach / vendor-AI / commercial-contract review. The package name reads "compliance" + the gdpr-gate `NOTICE` is the most prominent vendoring precedent in the codebase, so naming it as a legal-tooling alternative felt natural.

**Reality (verified by reading the NOTICE upstream-paths):** lifted scope is `pii-detector/patterns/`, `pii-detector/rules/`, `pii-detector/layers/`. It is a PII-detector code-scanner, NOT legal-tooling. Lifted files: `fields.md`, `leakage-vectors.md`, `legal-consent.md`, `non-negotiables.md`, `layers/api-layer.md`, `layers/data-in-transit.md`, `layers/data-lifecycle.md`. None are DSAR responders, breach-notice generators, vendor-AI reviewers, or commercial-contract analyzers.

**Detection:** Kieran's reviewer-question #1 ("Does `gosprinto/compliance-skills` actually have sections labeled DSAR / breach / vendor-AI / commercial-contract?") + planner pre-/work verification (`ls plugins/soleur/skills/gdpr-gate/references/`, read NOTICE).

**Generalizable rule:** Before naming any vendored package as a category-X alternative, verify scope against the lifted upstream-paths in its NOTICE — package names lie.

#### 3. Wrong-signature script invocation cited in a plan AC

Plan v1 prescribed `bash plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh --target <plan-file>`. Reading the actual script revealed:
- It's a lefthook pre-commit hook with signature `{staged_files}` (NOT `--target`)
- Always exits 0 (advisory; comment header line 4: "Always exits 0 — the hook is advisory, never blocking. Blocking enforcement lives in /soleur:ship Phase 5.5.")
- Plan-time invocation per `plan/SKILL.md` Phase 2.7 goes through the SKILL (`Skill: soleur:gdpr-gate`), not the script.

**Detection:** Kieran P1-5 — paraphrase-without-verification antipattern again, this time on a script signature.

#### 4. Spec mutation hidden in implementation phase (cross-PR contract drift)

Plan v1 Phase 9 included a step: "Re-evaluate the deferred-issue #3786 re-evaluation criteria. Edit #3786 to replace [unobservable criteria] with observable criteria." This silently mutated a separate GitHub issue's contract from inside an unrelated PR's implementation phase.

**Detection:** DHH ("polishing the deferral; close it instead"), Kieran (P1-4: "split into a separate `gh issue comment` with its own approval"), architecture-strategist (P1: "cross-PR contract mutation; the right shape is this PR ships the changes; a separate one-line PR/operation revises the criteria").

**Fix:** Replaced inline mutation with one-line context comment posted to #3786 (NOT changing the issue body's recorded criteria; future re-openers can propose new observable criteria when real demand emerges).

**Generalizable rule:** Plans correcting upstream technical facts (spec TR4 was wrong → plan corrects) is OK and was applied in the same revision. Plans correcting strategy facts (re-evaluation criteria, deferral conditions, brainstorm decisions) belong upstream — in a brainstorm revision, spec addendum, or its own PR — never inside implementation phases of an unrelated PR.

#### 5. Anchor-resolution scaffolding over-architecture for ≤3-file invariant

Plan v1 Phase 7 proposed lefthook OR test (with "decide at /work time" deferral) to validate that 5 anchors in `clo.md` + `legal-audit/SKILL.md` resolve to H2 anchors in `recommended-tools.md`. DHH: "pyramid for a paperclip"; code-simplicity: "drop or pick one." Architecture-strategist wanted BOTH lefthook + test (correctness panel disagreement).

**Resolution:** Per plan-review skill BOTH-fire rule (simplification + correctness both fired on the scope of "anchor-resolution machinery"), prefer delete. Cut Phase 7 entirely. Replace with a single vendor-neutrality grep test in `components.test.ts` that asserts both vendor-neutrality (per-row Tool B ≠ claude-for-legal-only) AND anchor resolution (as a side-effect — the test reads the anchors to verify the row count). One mechanism, not two.

**Generalizable rule:** For static-doc cross-file invariants where N (file count) is ≤ 3 and the existing test surface can absorb the check, do not build atomicity-enforcement infrastructure. A single cross-file test asserting the invariant as a side-effect of an existing assertion is cheaper than a new lefthook hook + a new CI step + the matrix of bypass-path mitigations.

#### 6. Defer-vs-ship inversion at brand-survival single-user-incident threshold

Plan v1 deferred `/soleur:go` keyword routing for legal-threshold mentions (MSA, DSAR, breach, AI vendor, OSS license) to a follow-up issue. Rationale: "in-scope changes cover the modal entry points; this is the next-most-likely entry but not blocking."

**Spec-flow-analyzer counter:** at `brand_survival_threshold: single-user incident`, "next-most-likely entry not covered" creates a single-user-incident window — which is exactly what the threshold guards against. A founder pasting an MSA into `/soleur:go` (modal Soleur entry point) and not being routed to `clo` means catalog-miss, statutory deadline missed, brand-fatal incident.

**Fix:** Un-deferred. Added 1-row table entry to `commands/go.md` Classify table — small inline patch.

**Generalizable rule:** At brand-survival single-user-incident threshold, a scope-out justified by "next-most-likely entry; modal entry covered" is the wrong shape. Either the second-most-likely entry covers the brand-survival surface (in which case ship it inline — the cost is small relative to the brand-survival blast radius), OR the threshold is wrong (and brainstorm should re-frame).

### The "BOTH-fire delete" rule held in practice

Per `plan-review/SKILL.md`'s consolidation guidance: "When BOTH panels fire on the same scope, prefer delete over fix." The simplification panel (DHH + code-simplicity) and correctness panel (Kieran + arch-strategist + spec-flow) converged on:

- **Phase 7 anchor-resolution machinery** → DELETE (replaced by side-effect of vendor-neutrality test)
- **Phase 9 #3786 criteria mutation** → DELETE (replaced by context comment)
- **Risks table 11 → 5 rows** → CUT 6 documentation-theater rows (mitigations of "PR review will catch it" or "N/A")
- **Phase 1 + Phase 2 parallel tables** → COLLAPSE to one
- **Two `clo` Assess subsections** → COLLAPSE to one (Assess only; routing rule moves to Sharp Edge)

Cutting the scopes dissolved 6+ "fix this specifically" findings simultaneously. Net plan reduction ~30%; all correctness P1s also resolved by the cuts.

## Key Insight

A 5-agent panel on a brand-survival plan is not just "more reviewers" — it's two orthogonal axes (simplification + correctness) whose convergence on a scope is a high-signal delete-this signal. **Most plan revisions are easier as deletions than as fixes.** When a plan section earns separate findings from "this is too complex" (DHH/code-simp) AND "this has 4 specific bugs" (Kieran/arch/spec-flow), cutting the section dissolves both classes of finding — including bugs the cut author wasn't tracking.

A second meta-insight: **paraphrase-without-verification fires more times in a single plan than the planner notices.** This plan revision caught 3 distinct paraphrase classes in one pass (phase numbers, vendor scope, script signatures). Each is a 10-second grep at plan-write time vs. minutes-to-hours of pivot at plan-review or /work time. The plan-skill Sharp Edges already encode this rule for issue-body paths and named architectural approaches; the same discipline applies to *every* fact the planner cites without re-reading.

## Session Errors

1. **Plan v1 wrong phase numbering (P0).** "Phase 1 Discovery" cited 7+ times; actual is Phase 0. **Recovery:** rewrote all references to Phase 0. **Prevention:** before citing a phase number from another skill, `grep -nE "^## Phase [0-9]+" <skill-file>` to enumerate. Already covered by plan-skill `paraphrase-without-verification` Sharp Edges, but the existing rule names "issue-body paths" and "named architectural approaches" — adding "phase numbers from sibling skills" to the prose would tighten the rule.

2. **Plan v1 vendor misclassification.** Named gosprinto as Tool B for legal thresholds. **Recovery:** removed; named real alternatives (counsel marketplaces, OneTrust/Securiti/Osano, ContractGen/LegalSifter, FOSSA/Snyk for OSS license). **Prevention:** before citing any vendored package as a category-X alternative, read the NOTICE upstream-paths to verify scope. Cost: ~30 seconds.

3. **Plan v1 wrong-signature script citation.** `bash gdpr-gate.sh --target` is wrong (signature is `{staged_files}`; always exits 0). **Recovery:** changed to `Skill: soleur:gdpr-gate`. **Prevention:** before prescribing a bash invocation in a plan AC, `head -20 <script>` to verify the signature comment header.

4. **Plan v1 spec mutation hidden in Phase 9.** Inline rewrite of #3786 criteria from inside an unrelated PR. **Recovery:** replaced with one-line context comment. **Prevention:** plan-review-skill rule already exists ("don't mutate spec inside implementation phases"); adding a placement check at plan-skill Phase 2.7 ("if a Phase N step modifies a separate-issue contract, file separately") would catch it pre-review.

5. **Plan v1 over-architected anchor-resolution.** Phase 7 lefthook OR test for 5 anchors. **Recovery:** cut entirely; single vendor-neutrality grep test in components.test.ts asserts anchor resolution as side-effect. **Prevention:** when a cross-file invariant spans ≤ 3 files, prefer a single existing-test-surface check over new infrastructure. (This is the YAGNI principle in the plan-skill Phase 4 detail-level guidance, applied at the per-section level.)

6. **Plan v1 defer-vs-ship inversion at brand-survival.** Deferred `/soleur:go` keyword routing. **Recovery:** un-deferred. **Prevention:** at `brand_survival_threshold: single-user incident`, scope-outs justified by "next-most-likely entry not covered" are anti-pattern. Plan-skill Phase 2.6 should add a check: "If the plan defers an entry point that COULD be the surface a brand-survival incident reaches the user through, ship it inline or downgrade the threshold."

7. **Plan v1 missed zero-findings + threshold-in-flight gap.** Mid-DSAR founder with clean privacy policy gets clean audit, never sees catalog. **Recovery:** added zero-findings catch rule. **Prevention:** spec-flow-analyzer's "where does the flow drop the user?" question is load-bearing on brand-survival plans; planner should self-ask "what's the audit-output state when nothing in the audit triggers but a threshold IS in flight?"

8. **Bash CWD persistence across `cd` in tool calls (continued from earlier session).** First-pass `ls .worktrees/feat-cc-legal-skill-bridge/...` returned nothing because the prior `cd` to the worktree persisted. **Recovery:** re-queried with paths relative to current CWD. **Prevention:** already documented in `2026-05-15-evaluating-anthropic-first-party-plugin-marketplaces.md` Session Errors #1; reinforced by recurrence here.

## Workflow Feedback Proposals (for Constitution / Skill routing)

The compound skill's Phase 1.5 step 4 enforcement hierarchy applied. Per the AGENTS.md placement gate (already-enforced / domain-scoped / cross-cutting):

- **Plan-skill Sharp Edge addition (DOMAIN-SCOPED — plan/SKILL.md):** "When citing a phase number from a sibling skill, `grep -nE '^## Phase [0-9]+' <sibling-skill>` BEFORE writing the plan. Phase numbers are 0-indexed in some skills (legal-audit is 0/1/2/3) and 1-indexed in others; memory shape lies." Single bullet append to plan/SKILL.md Sharp Edges — within bounded surface.

- **Plan-skill Phase 2.7 Sharp Edge (DOMAIN-SCOPED — plan/SKILL.md):** "When citing a vendored package as a category-X alternative in a Tool table, read the NOTICE upstream-paths to verify scope. Package names ('compliance-skills') describe the AUTHOR's intent, not the LIFTED CONTENT's domain." Single bullet append.

- **Plan-skill Phase 2.7 Sharp Edge (DOMAIN-SCOPED — plan/SKILL.md):** "When prescribing a bash invocation in a plan AC, `head -20 <script>` to verify the signature comment header. Plans citing scripts from memory propagate `--target` / `--file` / `--input` flags that don't exist." Single bullet append.

- **Plan-skill Phase 2.6 placement check (DOMAIN-SCOPED — plan/SKILL.md):** "At `brand_survival_threshold: single-user incident`, scope-outs justified by 'next-most-likely entry not covered' are anti-pattern. Either ship the entry inline or downgrade the threshold." This crosses Phase 2.6 (User-Brand Impact) territory — applies inline as a sub-rule.

- **AGENTS.md addition (NOT proposed — domain-scoped to plan-skill).** None of the above qualify as cross-cutting session invariants per the placement gate; all are plan-skill-scoped.

These would route to compound's "Route Learning to Definition" phase as direct edits to `plan/SKILL.md` Sharp Edges (single-bullet append per item — within bounded surface). Operator decides whether to apply now or batch.
