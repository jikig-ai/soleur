---
date: 2026-05-21
category: workflow-patterns
tags:
  - follow-through
  - qa
  - ship-phase-7
  - templates
  - scope-grants
issues:
  - "#4067"
  - "#4214"
prs:
  - "#4059"
  - "#4214"
---

# Follow-through template drift (host URL) + QA-spawned-feature pivot

## Problem

`/ship` Phase 7 Step 3.5 auto-generates manual-QA follow-through issues with
templated verification steps. Issue #4067 ("QA Playwright scope-grants row
status refresh") shipped with two template inaccuracies that wasted operator
attention during execution:

1. **Wrong host.** Body said `https://soleur.ai/dashboard/settings/scope-grants`
   — the dashboard actually deploys to **`app.soleur.ai`**. `soleur.ai` is the
   marketing site (`apps/marketing-site`); the dashboard is `apps/web-platform`,
   which builds at `app.soleur.ai` per `apps/web-platform/next.config.ts` and
   every `@app.soleur.ai` reference in `lib/auth/validate-origin.test.ts`,
   `app/api/checkout/route.ts:19`, `apps/web-platform/test/ws-protocol.test.ts:130`.

2. **Unrealistic latency assertion.** Body said "within ~200ms (no manual
   reload)." The implementation pattern is API roundtrip → `router.refresh()`
   → RSC re-render — not optimistic UI. Sub-second is not achievable end-to-end
   (measured 0.9–2.0s on prod). The *intent* — no manual reload required — is
   what mattered and what was verified.

Separately, the QA verification itself surfaced a brand-new product issue
(action-class titles rendered as raw dotted IDs across 4 UI surfaces) that
became PR #4214 in the same session. The brainstorm routing correctly
challenged the heavyweight `/soleur:brainstorm` default for a Y/N/refactor
decision and presented options inline; the user picked "run Playwright now."
The discovery → fix-feature pivot worked because the operator (a) kept
challenging the lane choice ("isn't this just a verification?") and (b) the
brainstorm explicit-exit branch surfaced "we already shipped, this is QA"
rather than spawning leaders.

## Solution

**For #4067 specifically:** verified inline via Playwright + DOM
MutationObserver on `app.soleur.ai/dashboard/settings/scope-grants` (operator
already authenticated as the operator — no OTP handoff needed). Both
assertions passed; issue closed with measured latencies in the comment.

**For the template:** the wrong-host class affects every future
follow-through issue that references the dashboard. Fix in `/ship` Phase 7
Step 3.5 template, not just this one issue. Search the ship skill for the
URL constant and confirm.

## Key Insight

A "manual verification" follow-through that turns out to be 100%
Playwright-automatable (operator is already authenticated; no OTP, no
CAPTCHA, no payment-card entry) does not require a heavyweight brainstorm
to re-plan it. Route directly via inline AskUserQuestion: run now / defer /
refactor approach / full brainstorm. The brainstorm skill's "is your
requirement already clear?" gate handles this when the operator pushes
back, but the better default is to challenge brainstorm routing at
`/soleur:go` time when the input is a bare `#N` reference to a
follow-through-labeled issue.

The follow-through itself spawned a real product PR (#4214 — human-readable
action-class titles) because the QA exposed a UX issue invisible from the
unit-test perspective: the unit suite asserted `router.refresh()` was
called, but did not assert the rendered strings were readable to a founder.
Manual QA is sometimes the cheapest way to discover that a unit-test gate
proves the wrong invariant.

## Session Errors

1. **Wrong host in issue body led to initial 404.** Recovery: grepped
   `apps/web-platform/next.config.ts` for `app.soleur.ai`. Prevention: fix
   the `/ship` Phase 7 Step 3.5 template URL constant.

2. **Bare-repo `find` returned false-negative on existent files.**
   `find apps/web-platform/components/scope-grants/` was empty even though
   `git ls-tree main` showed the directory had files. The session-start
   sync from HEAD is partial. Recovery: switched to `git ls-tree main` +
   `git grep -l "<symbol>" main`. Prevention: already covered by hard rule
   `hr-when-in-a-worktree-never-read-from-bare`.

3. **Initial actionClass-consumer grep missed two surfaces.** Pattern
   `{actionClass}\|run\.actionClass\|run\.action_class` missed
   `runtime-explainer-banner.tsx` (uses `{ac}` from `ACTION_CLASSES.map`)
   and `today-card.tsx` (uses `confirming?.actionClass`). The plan-deepen
   subagent caught both via its own broader greps. Recovery: read the
   plan's Files-to-Edit section. Prevention: when grepping for raw enum
   renders, include the variable-rename pattern (`{(?:ac|cls|action)}`),
   the optional-chain pattern, and any `.map(...)` callback args.

4. **Bash CWD doesn't persist between calls.** One test re-run used
   `./node_modules/.bin/vitest` from the wrong directory and got "command
   not found." Recovery: prefixed with `cd <abs-worktree-path>/apps/web-platform &&`.
   Prevention: already documented in work skill's "Common Pitfalls."

5. **`reportSilentFallback` signature mismatch on first edit.** First-pass
   call used `reportSilentFallback(s, {where, reason})` — actual signature
   is `reportSilentFallback(err, {feature, op, extra, message})`, and the
   warning-level variant `warnSilentFallback` was the better fit. Caught
   when reading `lib/client-observability.ts:80-129` before save.
   Prevention: read the signature of any new utility import before
   composing the first call site, even when the function name implies
   shape from context.

## Related

- Plan: `knowledge-base/project/plans/2026-05-21-feat-scope-grant-action-class-human-copy-plan.md`
- PR: #4214 (human-readable action-class titles)
- Verified issue: #4067 (closed in same session)
- Original fix: PR #4059 (#4048 — router.refresh on scope-grant rows)
