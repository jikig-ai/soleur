---
title: I asked the operator to approve a design premise I had not enumerated
date: 2026-08-03
category: workflow-patterns
issue: 7186
pr: 7189
tags: [decision-challenge, operator-gate, universal-negative, mutation-testing, react]
---

# I asked the operator to approve a design premise I had not enumerated

## Problem

Implementing the mobile Knowledge Base drill-in (#7186), the plan surfaced a design
decision (DC1: who owns "back" on the mobile browse view) and put it to the operator with a
premise labelled **"Verified finding"**:

> `inKbDocView` is computed and never used, and the mobile band is `suppressBack`
> unconditionally — **so the mobile KB landing has no reachable in-page back at all today.**

The operator approved option (a) on that premise. It was false.

An 11-agent review found a **fourth** back-renderer that neither the plan, the wireframe pass,
nor the decision-challenge counted: `drawer-back-to-menu` in `app/(dashboard)/layout.tsx`, an
`md:hidden` "Back to menu" → `/dashboard` rendered on *every* drilled route. The drawer
`<aside>` is translated off-canvas — not unmounted, not `inert` — so that link sits in the
accessibility tree in exactly the state the premise called empty.

Consequence: the populated mobile landing now ships **two links with the same accessible name
and the same href**, and the operator agreed to a change without being told that.

## Root cause

The premise is a **universal negative** — "there is no X in state S". The two facts backing it
were individually verified (`inKbDocView` really is dead; the band really is unconditionally
suppressed). But those two facts are about *two specific renderers*. The claim quantifies over
**all** renderers, and nothing enumerated that set.

This repo already documents "universal negatives are asserted, not enumerated" for PR bodies
and code comments. The new surface is that the same defect is **worse in a decision-challenge**,
because:

1. it is laundered through an operator approval, so it acquires the authority of a human
   decision while remaining an unverified engineering claim;
2. every downstream artifact inherits it — the wireframe, the plan, `decision-challenges.md`,
   the implementation comment, and the test that "guards" it;
3. the operator cannot check it. They are being asked for *taste*, and they reasonably assume
   the *facts* framing the choice were established.

The guard that looked like it covered this could not: the unit assertion rendered `KbLayout`
inside a harness without `DashboardLayout`, so the second link was never in the tree it queried.
A subtree-scoped test cannot count a composition-wide property — the repo's own
`2026-06-04-exactly-one-affordance-across-composition-boundary` learning says exactly this, and
the test still shipped scoped to a subtree.

## Solution

1. **Enumerate before asking.** A decision-challenge premise of the form "there is no X" must
   carry the enumeration that produced it, in the challenge itself:
   `git grep -n 'aria-label="Back' -- apps/web-platform` → 4 renderers, each classified by state.
   The cost is one grep. The cost of skipping it is an approval built on a false half.
2. **Correct it where the approval lives, not quietly in code.** The false premise is recorded
   in `decision-challenges.md` under an explicit `CORRECTION to DC1's premise` heading, saying
   what it does and does not change about the decision. A silent fix would leave the operator
   believing they decided something they did not.
3. **Assert the composition-wide count at the composition root.** Now pinned in the 390×844 e2e
   arm (`toHaveCount(2)`), with the unit test's comment stating explicitly that it counts the
   KB's own backs only and is *not* the composition-wide count.

## Key insight

**When a decision-challenge's premise is a universal negative, the enumeration IS the premise —
a conclusion without it is a claim wearing a finding's clothes.** Ask of every "there is no X"
you put in front of a human: *which command produced this set, and would it have found a member
in a file I did not open?*

The tell is a premise whose supporting evidence is a list of **specific** facts (`this variable
is dead`, `that flag is unconditional`) while the claim quantifies over a **category**. Specific
evidence cannot establish a universal negative, no matter how many specifics there are.

## Session Errors

**DC1's premise was an unenumerated universal negative, approved by the operator** — Recovery:
recorded a `CORRECTION` block in `decision-challenges.md`, added the composition-root e2e count,
filed the durable fix (make the closed drawer `inert`) to the follow-up tracker. Prevention: see
Key Insight — enumerate before asking; a universal negative in an operator-facing premise must
ship with the command that produced its set.

**Two P1 mutants survived a green 49-test suite** — the `fullWidth` `loading` term (mutating it
to `loading ? false : (...)` left everything green while breaking the hydration invariant a code
comment asserted) and AC3's viewport-invariance (fixtured on `empty` only, so a
`loading && !isDesktop` DOM leak survived). Recovery: added a pending-fetch case and
parameterised AC3 over all five `fullWidth` sub-states; mutation-verified 0→7 and 0→1.
Prevention: for every comment that asserts an invariant, ask which fixture instantiates it — the
recurring shape is *prose carries the guarantee, the fixture instantiates one member of the set
the prose quantifies over*.

**`rerender(tree)` with the same element object is a no-op** — React bails out of re-rendering a
subtree whose element is referentially identical, so a breakpoint-flip test built on one shared
`tree` const never re-rendered. Recovery: `makeTree()` returning a fresh element per call.
Prevention: any `rerender` driving a *transition* must construct a new element; reusing the
object makes the case vacuous in the direction that looks green.

**An import guard checked for the symbol, not the import** — `if "KbMobilePageHeader" not in s:
add_import()` skipped, because the symbol was already present at the usage site added moments
earlier in the same script. Two files then failed `tsc` with TS2304. Recovery: guard on the
literal import LINE. Prevention: an idempotency guard must test for the exact artifact it
writes, not for a substring that the change itself introduces elsewhere.

**`git checkout HEAD -- <file>` did not revert my own change** — used to undo an
in-progress edit, but HEAD *contained* the code being reverted (it had been committed one step
earlier), so the file came back unchanged and the grep that "verified" the revert reported 6
surviving references. Recovery: `git checkout origin/main -- <file>`. Prevention: when reverting
work from THIS branch, the baseline is `origin/main` (or the branch base SHA), never `HEAD`.

**A concurrent review agent mutated the shared worktree** — an agent created and deleted
`apps/web-platform/test/zz-perf-probe.test.tsx` mid-review, contaminating another agent's full-suite
run (7 phantom failures in 2 files) and briefly breaking `tsc`. Recovery: the affected agent
rebuilt a pristine sandbox (`git archive HEAD | tar -x`, symlinked `node_modules`), re-verified
the baseline green there, and re-ran every finding. Prevention: review agents that need to mutate
must work on a sandbox copy; the review skill already says this and the instruction needs to be
in the *spawn prompt*, not only in the skill body.

**`taste-profile-update.sh` rejected context `kb`** — one-off. The allowlist is
`landing-page marketing-site dashboard app-ui docs email component`; re-ran with `app-ui`. The
script named the valid set in its own error message, so recovery was immediate.

**CWD drift after `cd apps/web-platform`** — one-off, twice. Relative paths resolved against the
app dir instead of the worktree root. Recovery: absolute paths. Documented class
(`cm-delegate-verbose-exploration` neighbours); hit anyway because the drift happened in an
earlier tool call than the failure.

**A `//` comment inside a JSX opening tag** — one-off, caught by the next `tsc` run. JSX attribute
position needs `/* */`.

**A self-derived test count in a commit message was off by one** (12842 vs 12843) — one-off, but
the same class the repo documents as "publish the COMMAND next to the number". Caught by a review
agent re-running the suite, not by me.

## Related

- `knowledge-base/project/learnings/ui-bugs/2026-06-04-exactly-one-affordance-across-composition-boundary-needs-integration-count-assertion.md` — the composition-boundary counting rule this session re-proved
- `knowledge-base/project/learnings/2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md` — universal negatives asserted rather than enumerated, in PR bodies
- `knowledge-base/project/learnings/2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md` — the mutant-survival half
- `knowledge-base/engineering/architecture/decisions/ADR-158-kb-file-tree-host-is-a-derived-value.md`
