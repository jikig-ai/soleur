---
feature: decision-principles-engine
issue: 5984
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-04-feat-decision-principles-engine-plan.md
---

# Tasks: Decision-Principles Engine (#5984)

## Phase 0 — Ground truth (verify before edit)
- [ ] 0.1 Re-read anchors: ADR-083:22-24,51; plan:564-572; ship:296-298,1196,1242; work:142,837,857-868; brainstorm-techniques:66-69; one-shot:70,81,172; operator-digest:76,110-114; ship-operator-step-gate.sh deny regex; components.test.ts:226-236,242-277.
- [ ] 0.2 Confirm the exact `ship` Phase 6 body-construction site + the operator-step-gate regex tokens to avoid.

## Phase 1 — Author `decision-principles.md`
- [ ] 1.1 Create `plugins/soleur/skills/brainstorm-techniques/references/decision-principles.md`.
- [ ] 1.2 Write the 2 surfacing principles (blast-radius, bias-to-action) + one-line constitution pointer for code-taste.
- [ ] 1.3 Write §Classification: 3 classes; surface criterion (user-visible OR money/compliance, expanded to sub-processor/recurring-cost/data-egress/lawful-basis); classify-by-consequence; the 4 never-Mechanical classes.
- [ ] 1.4 Write the CTO precedence carve-out (arch forks → cto per work:142, not User-Challenge).
- [ ] 1.5 Write the mode-branch table keyed on **execution context** (real TTY vs any subagent/headless).
- [ ] 1.6 Write the 5-line User-Challenge frame; "both signals" gate-scope + disagreement branch; fail-safe defaults; security/feasibility terminal-halt exception.

## Phase 2 — Wire consumers (markdown links only)
- [ ] 2.1 `brainstorm-techniques/SKILL.md` technique 5: markdown-link pointer.
- [ ] 2.2 `plan/SKILL.md` Step 4.5: contradiction→User-Challenge; headless→persist to challenges artifact.
- [ ] 2.3 `work/SKILL.md`: classify emergent decisions; detect+persist to `knowledge-base/project/specs/<branch>/decision-challenges.md`; reconcile with work:142 CTO gate.
- [ ] 2.4 `ship/SKILL.md` Phase 6: read the artifact; fold `## Model Dissents (informational)` (name outside operator-step-gate regex) into the body BEFORE `gh pr edit --title --body`; open idempotent `action-required`+`decision-challenge` issue linking the PR.
- [ ] 2.5 Confirm `one-shot/SKILL.md` is NOT edited (inherits).

## Phase 3 — ADR + drift guard
- [ ] 3.1 Write `ADR-084` (standalone; consumes-not-extends 083; references 083:24/:51; 5 rejected alternatives; C4 no-impact enumeration; security exception as sole no-pause carve-out).
- [ ] 3.2 Extend `components.test.ts`: assert doc exists + 4 consumers link it (markdown-link regex) + `ship` contains the `action-required` emission. No content-presence assertions.

## Phase 4 — Verify
- [ ] 4.1 `tsc` + lint + full test suite green.
- [ ] 4.2 Fixture-check: `ship-operator-step-gate.sh` does NOT deny a body containing the rendered dissents block.
- [ ] 4.3 Drift-guard test green.
