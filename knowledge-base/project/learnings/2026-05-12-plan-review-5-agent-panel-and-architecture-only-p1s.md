---
title: Plan-review 5-agent panel surfaces architecture-only P1s the simplification panel misses; both-panels-fire heuristic naturally produces multi-PR splits
date: 2026-05-12
category: best-practices
module: plan-review
component: soleur-plan-review-skill
problem_type: process_issue
severity: high
tags: [plan-review, both-panels-fire, architecture-strategist, brand-survival-threshold, single-user-incident, multi-pr-split, sentry-scope, formatters-log]
related_issues: ["#3698", "#3701", "#3710", "#3711", "#3638", "#3685", "#3696", "#3708"]
related_pr: "#3701"
related_learning: ["2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md", "2026-05-12-brainstorm-issue-body-option-and-inventory-staleness-pino-userid.md"]
source_session: brainstorm + plan + plan-review of #3698 (pino userId pseudonymisation) on 2026-05-12
---

# Plan-review 5-agent panel surfaces architecture-only P1s; both-panels-fire heuristic produces multi-PR splits

## Problem

#3698 was a follow-up to PR #3685's deferred-scope-out. The brainstorm bundled 6 deliverables at the user's explicit scope-choice ("Bundle operator hash-user-id CLI ✓ Bundle Sentry.setUser middleware ✓ Add recursive walker ✓ Also migrate 10 sites ✓ Block on retention pin ✓"). The plan was written to match: 8 phases, ~25 file-edits, 11+4 ACs.

The 6-agent plan-review panel (DHH + Kieran + code-simplicity + architecture-strategist + canonical spec-flow + GDPR auditor — invoked per `brand_survival_threshold: single-user incident`) produced:

- **Simplification panel (DHH + code-simplicity):** aggressive cut-list — delete Phases 3/4/5, helper extraction, recursive walker, operator CLI, PA8 §(f). Propose 3-PR split.
- **Correctness panel (Kieran + canonical spec-flow + focused spec-flow):** ~15 P1/P2 fixes if the bundle stayed (AC regex, line-range citations, phase ordering, spec/codebase contradictions, missing CI gate persistence).
- **Architecture-strategist alone:** TWO P1s nobody else raised — **F2 formatters.log throw drops log line** (pino propagates formatter throws — original PR's `logger.error({err, userId}, "msg")` calls would have their original error context dropped if `renameUserIdToHash` ever threw); **F3 Sentry scope cross-request bleed under custom-server boot path** (Next.js AsyncLocalStorage isolation unverified for `apps/web-platform/server/index.ts` Node http server; `setUser` could persist across requests in the same Node worker).
- **GDPR auditor:** 2 critical findings (add persistent CI gate, not one-time AC; refresh `compliance-posture.md` line 88 post-merge).

The both-panels-fire heuristic (per `2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md`) triggered on six scope items where simplification AND correctness panels both fired. The trim produced a clean 3-PR split:

- **PR-A (this PR / #3701):** formatters.log + try/catch + PA8 §(c) + ADR-029 + persistent CI gate.
- **PR-B (#3710):** Sentry.setUser + helper migration + sentry-scrub coverage. Architecture F3 gate (2-request scope-isolation test) is load-bearing prereq.
- **PR-C (#3711):** operator CLI + PA8 §(f) retention pin + compliance-posture refresh.

## Investigation

Six review agents fanned out across distinct axes:

- **DHH (37signals lens):** "this is a 20-line problem wearing a 7-phase suit." Brutal cut-list.
- **Kieran (strict convention/correctness):** 12 P1/P2 findings on cited line numbers, AC verifiability, type correctness, phase ordering.
- **Code-simplicity (YAGNI):** convergent with DHH on cut-list, plus the explicit 3-PR split proposal that became the trim shape.
- **Architecture-strategist:** **the ONLY agent to surface F2 and F3.** Both P1; both load-bearing; neither caught by the other 5 reviewers.
- **Canonical spec-flow:** FR-to-AC traceability + spec/codebase contradictions + retention-window driver-disambiguation gap.
- **Focused spec-flow (parallel earlier pass):** operator runbook flow gaps + PA8 §(c) over-claim risks + migration-window false-negative.

**The architecture-only P1s would have shipped silently in a 3-panel review.** F2's blast radius: any future formatter-throw drops the original error context — the exact scenario `reportSilentFallback` was designed to make observable. F3's blast radius: one user's `userIdHash` attached to another user's Sentry event during an incident; cross-tenant identity confusion at the worst possible time.

**Kieran-style "your inventory is wrong" findings need ground-truth verification.** Kieran's P1.6 claimed `services/route.ts` already used `reportSilentFallback`. Inline `grep` against the worktree returned `logger.error({...userId...})` at lines 103, 133, 198. The finding was WRONG. Accepting it would have removed real migration targets from the plan; rejecting it without verification would have left a 50% chance of error. Verification took 5 seconds.

**Both-panels-fire produces a natural shape.** When DHH and code-simplicity both said "cut Phase X" AND specflow/architecture pointed out concrete bugs in Phase X's verification commands or implementation contract, the cut dissolved the bug. The 3-PR split wasn't the user's brainstorm preference, but it was the natural consequence of the consolidated panel: each PR is reviewable in one sitting; PR-A unblocks compliance immediately; PR-B isolates the F3 verification gate; PR-C is operator-bookkeeping that can ship on its own cadence.

## Solution

Applied the trim at plan-review-finalisation time. Specific actions:

1. **Rewrote the plan** to PR-A scope (`knowledge-base/project/plans/2026-05-12-feat-pino-userid-formatters-log-plan.md`). 5 phases, ~8 file-edits, ~6 ACs. Plan frontmatter records `plan_review_outcome: trim-per-both-panels-fire`.
2. **Narrowed the spec** to match. FR1 (formatters.log) + new FR2 (PA8 §(c)) + new FR3 (ADR-029) + new FR4 (CI gate) + new FR5 (shared helper) stay. Original FR2-FR6 deferred to #3710/#3711. TR3 null-handling row corrected (`pepper_unset_null` sentinel matches `observability.ts:53`).
3. **Created ADR-029** documenting the rename-at-boundary pattern (per Architecture AP-011 advisory). Names follow-up issues by number.
4. **Filed PR-B (#3710) and PR-C (#3711)** with concrete acceptance criteria. PR-B's body cites Architecture F3 scope-isolation gate as a load-bearing prereq.
5. **Folded F2 fix into PR-A** — `formatters.log` wraps the rename in `try/catch` returning `obj` on throw + one-time `console.warn` (NOT `logger` — re-entrancy).
6. **Folded GDPR critical findings into PR-A** — replaced the one-time AC2(ii) bypass-grep with a persistent CI gate (`.github/workflows/lint.yml` step); deferred compliance-posture.md line 88 refresh to PR-C.
7. **Updated #3698 body** with the plan-time scope decision so any future reader sees the trim rationale.

## Key Insight

**The architecture-strategist's P1s in a single-user-incident plan are the canonical reason the 5-agent panel exists.** F2 and F3 are not the kind of finding a simplification reviewer produces (they don't reduce LOC); they're not the kind a convention reviewer produces (they don't violate a project rule); they're not the kind a spec-flow reviewer produces (they don't introduce a flow gap). They're architectural: about what happens when a primitive throws under load, about whether a per-request scope is actually per-request. Only an agent prompted to think "where does this break under adversarial conditions / at the layer below the one being designed" surfaces them.

The 3-agent panel (DHH + Kieran + code-simplicity) is enough for routine plans. The 5-agent panel (+ architecture-strategist + spec-flow-analyzer) is load-bearing for **any plan whose User-Brand Impact section declares `single-user incident` or `aggregate pattern`**, because those plans by definition fail in ways the simplification panel does not measure.

**The both-panels-fire heuristic is more aggressive than either panel alone, and the aggression is a feature.** When DHH says "cut this" and architecture says "this has a hidden P1" the convergence means *both* the YAGNI floor and the correctness floor reject the scope. Cutting dissolves the bug AND the bloat. Adding to the bug fix would have grown the plan by ~40 lines (verify steps for F3, runbook for F2 fallback, additional fixtures). Cutting Phase 4 entirely deleted the F3 risk surface and saved the 40 lines.

**Brand-survival threshold framing should NOT be conflated with bundle preference.** The brainstorm-stage user choice to "bundle everything" was a maximalist scope preference, but the threshold (`single-user incident`) actually argues for **shipping the disclosure-truth deliverable fast**, not for bundling. The plan review caught the conflation; the user accepted the trim.

## Prevention

1. **Plan-review skill behaviour: always invoke 5-agent panel when `brand_survival_threshold: single-user incident` is declared.** The plan-review skill at `plugins/soleur/skills/plan-review/SKILL.md` already encodes this — confirm it remains in place; do NOT add an "exceptions" clause.

2. **Plan-author behaviour: ground-truth-verify every "your inventory is wrong" review finding.** A 5-second `grep` against the worktree settles whether a finding is real. Accepting blindly cascades fixes; rejecting blindly leaves bugs. Run the grep before deciding.

3. **Brainstorm-stage placement recommendations are tentative.** Domain leaders (CPO/CTO/CLO) can suggest "place this here" but those suggestions need plan-time API verification. The brainstorm's CPO/CTO Sentry.setUser recommendations were sound for a Next-default setup; they were wrong for the custom-server setup, but neither leader had access to the custom-server constraint. Plan-author owns the verification.

4. **Spec-skill: spec fixture rows must match existing codebase behaviour, not the spec-author's mental model.** The TR3 null-handling row said "no key added"; `observability.ts:53` says `userIdHash: "pepper_unset_null"`. Spec-skill should prompt: "Read the target module's existing behaviour before writing the fixture row."

5. **Plan-skill: AC verification commands must be tested against the actual target file before freezing.** AC6's `awk` pattern wouldn't match because PA8 §(c) is a Markdown table cell, not line-anchored prose. The plan-author should `bash` the verification command locally before writing it into the AC.

6. **CI gates beat one-time ACs for persistent regression risk.** The GDPR auditor's "add persistent CI gate, not one-time AC" finding generalises: any AC that depends on a code surface that future PRs could regress should be enforced by CI, not by reviewer judgment at one merge. Plan-review skill should surface this distinction explicitly.

## Session Errors

1. **Brainstorm Sentry.setUser placement recommendation was incomplete** — CPO/CTO proposed `instrumentation.ts`; plan-time grep showed it's a no-op for the custom-server. **Recovery:** plan-time pivot moved Sentry.setUser to follow-up PR-B. **Prevention:** brainstorm-stage placement recommendations should be flagged as tentative pending plan-time API verification.

2. **Spec.md TR3 null-handling contradicted codebase** — spec said "no key added", `observability.ts:53` emits `"pepper_unset_null"` sentinel. **Recovery:** corrected spec inline during plan-time. **Prevention:** spec fixture rows must be verified against existing codebase behaviour at spec-write time.

3. **AC6 awk grep pattern wouldn't match the Markdown table cell** — Kieran caught at review. **Recovery:** rewrote as `grep -n "formatters.log()"`. **Prevention:** plan-author should test verification commands against the actual target file before freezing the AC.

4. **AC2(ii) bypass-grep regex missed nested objects and multi-line emits** — specflow caught. **Recovery:** the trim path made this AC moot (CI gate replaces one-time AC). **Prevention:** AST-based or multi-line-aware patterns for AC enforcement; or replace one-time AC with persistent CI gate.

5. **Initial Kieran P1.6 was wrong** — claimed `services/route.ts` already uses `reportSilentFallback`; inline `grep` verified false. **Recovery:** rejected the finding with verified evidence. **Prevention:** always ground-truth-verify "your inventory is wrong" review findings before accepting OR rejecting.

6. **Architecture F2 + F3 NOT raised by brainstorm or simplification panel** — only architecture-strategist surfaced both P1s. **Recovery:** F2 folded into PR-A try/catch; F3 deferred to PR-B with scope-isolation gate. **Prevention:** the plan-review skill's "5-agent panel for single-user-incident threshold" rule is load-bearing; never downgrade to 3-panel for brand-survival plans.

## Cross-References

- `2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md` — origin of the both-panels-fire heuristic; this learning provides a second-instance confirmation of the pattern at a different scope.
- `2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md` — names #3698 as the deferred-scope-out; two-clause AC pattern.
- `security-issues/2026-05-12-multi-agent-review-catches-load-bearing-redaction-primitive-bypasses.md` — the multi-agent review pattern this learning extends from PR review-time to plan review-time.
- `2026-05-12-brainstorm-issue-body-option-and-inventory-staleness-pino-userid.md` — the brainstorm-side pivot from this same session.
- `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md` — phase ordering principle the plan-author honoured.
- `plugins/soleur/skills/plan-review/SKILL.md` — codifies the 5-agent panel + both-panels-fire heuristic.
- AGENTS.md `hr-weigh-every-decision-against-target-user-impact` — the rule that triggered the threshold framing.
- Issue #3698 (closing) — PR #3701 — PR-A.
- Issue #3710 — PR-B follow-up (Sentry-side + helper migration).
- Issue #3711 — PR-C follow-up (operator CLI + retention + compliance-posture).
- Issue #3708 — DPD §(l) follow-up (separate track).
- ADR-029 — rename-at-boundary pattern (created by this PR).
