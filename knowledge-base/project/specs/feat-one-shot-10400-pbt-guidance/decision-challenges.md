---
title: "Decision challenges — feat-one-shot-10400-pbt-guidance"
date: 2026-10-20
branch: feat-one-shot-10400-pbt-guidance
---

# Decision Challenges

Headless one-shot planning for #10400 (epic #10397 child 3). Technical items are persisted `pending - assumed` for the pipeline's technical-ruling gate (CTO); operator-class items persist for `ship` Phase 6 to render into the PR body and file as `action-required` issues.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| RED-task title form for the new token: `RED(unit\|integration\|e2e\|property)` (widened single token set) vs `RED(unit,property)` (explicit layer:oracle two-axis form) vs `RED(property)` as a separate alternative form | technical | pending - assumed: literal widening `RED(unit\|integration\|e2e\|property)` per issue AC "`work` RED-layer accepts `property` alongside unit/integration/e2e" — caveat for the ruling: `property` is an oracle class, not a pyramid layer (ADR-293 calls it a "third test class"); the two-axis form preserves the layer signal but invents a title grammar no other token uses, and the separate form invites vocabulary drift. Guidance text states the axis split either way ("`property` names the oracle class; the file still lives at a pyramid layer"). AC1's grep is form-tolerant. |
| Install `@trailofbits/skills/property-based-testing` community plugin (covers fast-check/Hypothesis/proptest conventions + shrunk-counterexample triage) alongside or instead of the authored reference | operator (scope) | pending — NOT installed; carry-forward from child 1's decision-challenges, which deferred re-evaluation explicitly to this child. Plan meets all ACs without it; adoption would duplicate the shipped reference's coverage. |
| Extend `test-pyramid-fixtures.test.sh` DRIFT pin to cover `property` (a test-file edit inside a docs-scoped issue) | technical | pending - assumed: extend — the pin exists to pin the RED vocabulary; leaving the new member unpinned is the exact silent-rot class the guard was built for. Alternative: leave the pin untouched (it stays green — `RED\(unit` still matches) and accept `property` as unpinned vocabulary. |
| `work/SKILL.md` PBT "section" shape under the byte ceiling: token + link only (~110 B of the 118 B headroom, all guidance in the reference) vs fuller in-file prose paid by delta-neutral trims elsewhere in the file | technical | pending - assumed: token + link only — ceiling `359,189` B vs current `359,071` B measured 2026-10-20 (`lint-skill-body-budget.py --base origin/main`); the issue's "PBT section" cannot physically be a section at current headroom, and the reference file (no ceiling) carries the teaching content the issue actually names. If the ruling wants in-file prose, the TDD gate's mega-bullet region is the trim candidate. |

## Not Yet Specified candidates

- Whether `plan`'s own `## Test Scenarios` outputs should later carry a per-scenario `oracle:` field (example vs property) — premature; the sentence-level guidance ships first and adoption is observable before a schema lands.
