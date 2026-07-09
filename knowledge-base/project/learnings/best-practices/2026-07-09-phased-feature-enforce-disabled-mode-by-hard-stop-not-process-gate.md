---
date: 2026-07-09
category: best-practices
tags: [plan, scope, safety, yagni, phased-rollout]
source_issue: 6260
source_pr: 6259
---

# Phased test→live feature: enforce the not-yet-enabled mode by a hard-stop in code, not by a downstream process gate

## Context

The `/soleur:invoice` v1 plan (a payments skill, single-user-incident threshold) declared
"v1 usable in **test mode only**; the first **livemode** send is gated on a legal lockstep (#6264)."
The first draft implemented that boundary the *permissive* way: the skill *detected* livemode, showed
a scary "REAL money" warning, and **proceeded on a double-confirm** — with the actual gate living in a
compliance doc (CG5) elsewhere in the plan.

Two independent reviewers (architecture-strategist P0, code-simplicity-reviewer Finding 2) converged
on the contradiction: a plan cannot be both "test-mode only" AND ship a working live path behind two
typed words. That live path is either dead code or a direct violation of the gate the plan itself calls
load-bearing.

## The pattern

**When a feature is phased (mode B disabled until a later slice/process completes), enforce the
disabled mode with a hard-stop in the code path itself — not by a warning + proceed, and not by a gate
that lives in a separate doc/process.**

- **Permissive framing (worse):** detect disabled-mode → warn → proceed; rely on a downstream
  legal/ops/process gate to "really" stop it. The enforcement mechanism (typed tokens) does not
  implement the stated boundary; the boundary is a convention, not a property.
- **By-construction framing (better):** detect disabled-mode → **STOP**, point at the tracking issue
  for enablement, offer **no** proceed path. The scope is enforced by the code, and — the surprising
  part — this *removes* machinery (the whole warn+double-confirm+live-preview UX) rather than adding it.
  **Simpler AND strictly safer.**

The reviewers' phrase: the safety fix and the simplification *converge* — the elaborate live-mode UX
was YAGNI built for a mode the release is not permitted to use.

## Generalizes to

Any phased rollout where the later phase is gated on something outside the code (a legal lockstep, a
vendor approval, a soak, a paid-tier upgrade, a migration): dark-launch flags default-closed as a
hard refuse, feature-flag `OFF` as a 404/stop rather than a render-with-banner, "coming soon" surfaces
that STOP rather than half-work. Also a plan-review tell: if a plan says "X only in mode A" but a step
lets mode B proceed behind a confirmation, the confirmation is not the gate — grep for the hard-stop.

Related: [[2026-07-09-skill-gap-review-grep-product-for-own-version-before-greenfield]] (same session).
