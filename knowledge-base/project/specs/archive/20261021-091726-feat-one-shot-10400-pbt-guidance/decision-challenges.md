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
| RED-task title form for the new token: `RED(unit\|integration\|e2e\|property)` (widened single token set) vs `RED(unit,property)` (explicit layer:oracle two-axis form) vs `RED(property)` as a separate alternative form | technical | Ruled by CTO agent, 2026-10-20: literal widening `RED(unit\|integration\|e2e\|property)` - issue AC literally names this form, AC1's `RED\([^)]*property` grep is satisfied, it costs +9 B of the 118 B headroom, and the consumer census is clean (two consumers: `work/SKILL.md:339` token site and the DRIFT pin at `test-pyramid-fixtures.test.sh:224`). Corrected evidence: the pin is a full-literal ERE including the closing `\)`, so the widened form does NOT satisfy `RED\(unit\|integration\|e2e\)` — the Item-2 pin extension is forced, not optional. Layer enforcement is path-based so a `RED(property)` title cannot evade `pyramid-justified:`. Dissent: axis purity favors `RED(unit,property)`; mitigated by the guidance clause and path-based enforcement, adequate not structural. |
| Install `@trailofbits/skills/property-based-testing` community plugin (covers fast-check/Hypothesis/proptest conventions + shrunk-counterexample triage) alongside or instead of the authored reference | operator (scope) | pending — NOT installed; carry-forward from child 1's decision-challenges, which deferred re-evaluation explicitly to this child. Plan meets all ACs without it; adoption would duplicate the shipped reference's coverage. |
| Extend `test-pyramid-fixtures.test.sh` DRIFT pin to cover `property` (a test-file edit inside a docs-scoped issue) | technical | Ruled by CTO agent, 2026-10-20: extend - under the Item-1 ruling this is forced, not discretionary: `found "$WORK_SKILL" 'RED\(unit\|integration\|e2e\)'` is a full-literal ERE match the widened spelling fails (verified by direct grep), so "leave untouched" ships a red suite; and extension is the pin's purpose — an unpinned fourth member is the silent-rot class Guard 1's mutation matrix is written against. Update the canonical pattern to cover `\|property`, bump `MIN_ASSERTIONS` (line 240) if a call site is added, keep the header accurate. Dissent: none. |
| `work/SKILL.md` PBT "section" shape under the byte ceiling: token + link only (~110 B of the 118 B headroom, all guidance in the reference) vs fuller in-file prose paid by delta-neutral trims elsewhere in the file | technical | Ruled by CTO agent, 2026-10-20: token widening + one markdown link with a ≤~100 B selection clause at one site (~110 B total), all teaching in `work/references/property-testing.md` - headroom verified (`skill-body-budget.json` pins `work: 359189`; file measures 359,071 B), the lint enforces whole-file `st_size > ceiling` and ceilings ratchet down only, so a raise is structurally barred here; the link is load-bearing per `components.test.ts:241,260–297` (no backticked `references/` path; every references/*.md must be named). Dissent: token+link may under-teach if the link is never followed — the ≤100 B clause still carries the one-line selection signal; the trim path remains available if measurement later shows it matters. |

## Not Yet Specified candidates

- Whether `plan`'s own `## Test Scenarios` outputs should later carry a per-scenario `oracle:` field (example vs property) — premature; the sentence-level guidance ships first and adoption is observable before a schema lands.
