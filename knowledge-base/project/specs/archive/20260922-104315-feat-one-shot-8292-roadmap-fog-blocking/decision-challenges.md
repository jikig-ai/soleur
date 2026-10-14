# Decision challenges — feat-one-shot-8292-roadmap-fog-blocking

Plan-review findings classified Taste (named-panel product findings) or User-Challenge, recorded
per ADR-084 because the planning run was headless. None was applied to the plan. `ship` renders this
file into the PR body and files the `action-required` issue.

Plan: `knowledge-base/project/plans/2026-09-22-feat-product-roadmap-fog-and-native-blocking-plan.md`

---

## DC-1 — Walk the unsorted (no-milestone) issues in workshop step 1.6

**Date:** 2026-09-22 · **Classification:** Taste · **Source:** `soleur:product:cpo`
The four-places table names open issues with no milestone (about 209 today) as "unsorted", but no step
makes anyone look at them, so "forgot" only shows up if someone searches. Proposal: step 1.6 shows the
unsorted count and the oldest few and asks the founder to place or rule out each.
**Counter-view:** `soleur:engineering:review:dhh-rails-reviewer` called the unsorted set an
unrequested chore. **Plan default:** the table names the set in one line; no walk step.

## DC-2 — Empty-state wording in roadmap.md

**Date:** 2026-09-22 · **Classification:** Taste · **Source:** `soleur:product:cpo`
`_None recorded._` can read as "nothing is undecided". Proposal:
`_Nothing recorded yet. The roadmap workshop adds entries._`
**Plan default:** `_None recorded._`

## DC-3 — State the four-places rule inside roadmap.md

**Date:** 2026-09-22 · **Classification:** Taste · **Source:** `soleur:product:cpo`
The founder reads roadmap.md, not the skill. Proposal: one sentence above the two new sections saying
that work in none of the four places was forgotten. **Plan default:** the rule lives in the skill.

## DC-4 — Post-MVP wording in the four-places table

**Date:** 2026-09-22 · **Classification:** Taste · **Source:** `soleur:product:cpo`
"We know exactly what to build" is false for most of the Post-MVP milestone's issues. Proposal:
"filed as an issue; chosen for later". **Plan default:** the CPO's first-round wording.

## DC-5 — Soften "these entries never move back"

**Date:** 2026-09-22 · **Classification:** Taste · **Source:** `soleur:product:cpo`
Proposal: add "changed your mind? open a new issue" to the Out of Scope intro so founders are not
deterred from ruling work out. **Plan default:** unchanged.

## DC-6 — Plain words in founder-facing output

**Date:** 2026-09-22 · **Classification:** Taste · **Source:** `soleur:product:cpo`
Proposal: keep "frontier", "blocked", "claimed" in the rules, but use "ready to start", "waiting on
#M", "someone is on it" in `next` output and headings. **Plan default:** `ready` / `blocked` /
`claimed` counts and the existing CODEABLE / OPERATOR tokens.

## DC-7 — Rank roadmap-row issues ahead of internal tooling in the frontier

**Date:** 2026-09-22 · **Classification:** Taste · **Source:** `soleur:product:cpo` (first round)
Phase 4 mixes the validation core (#1439-#1443) with internal-tooling issues; lowest-number-first
may point `next` at old tooling. **Plan default:** keep `next`'s existing lowest-number pick, as the
issue asks the frontier to compose with it.

## DC-8 — Ship the phase-selection fix as its own PR

**Date:** 2026-09-22 · **Classification:** User-Challenge (scope) · **Source:**
`soleur:engineering:review:code-simplicity-reviewer`
`pick_phase` fixes a pre-existing defect that no #8292 property requires. **Plan default:** keep it
in this PR as its own commit (CPO, CTO and DHH concurred: without it the new frontier renders the
wrong phase on day one).

---

## Operator resolution — 2026-09-22

Resolved by the operator in-session (AskUserQuestion), so no `action-required` issue is owed for
this file:

- **DC-1 accepted:** workshop step 1.6 walks the unsorted (no-milestone) issues — count plus the
  oldest few — and asks the founder to place or rule out each.
- **DC-2 accepted:** empty state is `_Nothing recorded yet. The roadmap workshop adds entries._`
- **DC-3 accepted:** one sentence in roadmap.md above the two new sections states the four-places rule.
- **DC-4 accepted:** Post-MVP row reads "filed as an issue; chosen for later".
- **DC-5 accepted:** Out of Scope intro adds "changed your mind? open a new issue".
- **DC-6 accepted:** `next` output and headings use "ready to start" / "waiting on #M" /
  "someone is on it"; the rules keep frontier / blocked / claimed.
- **DC-7:** not raised with the operator; plan default stands (lowest-number pick).
- **DC-8:** operator chose to keep the phase-selection + truncation fix in this PR as its own commit.
