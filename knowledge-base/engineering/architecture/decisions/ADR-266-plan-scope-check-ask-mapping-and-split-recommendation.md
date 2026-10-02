---
title: "Every plan carries a Scope Check: ask mapping, item provenance, split recommendation"
status: accepted
date: 2026-10-01
amends: none
supersedes: none
issue: 9398
related: [9339, 4133]
related_adrs: [ADR-176, ADR-180, ADR-131]
tags: [plan, deepen-plan, scope-check, gate, machinery]
brand_survival_threshold: none
---

# ADR-266: Every plan carries a Scope Check — ask mapping, item provenance, split recommendation

## Status

**Accepted — 2026-10-01 (#9398).**

## Context

The plan pipeline had gates checking mechanisms against properties (plan Phase
0.6b) and file lists against open scope-outs (Phase 1.7.5), but no gate checked
the plan against the *user's own words*. On PR #9339 (merged 2026-10-01) a
brief listing tasks a–f produced a plan that added a destructive `--attest`
rung nobody asked for, and a diff that grew to 101 files / +6175/−195. Three of
seven plan reviewers cut the rung — but only after the plan was written,
deepened, and fanned out. The catch cost an 11-seat review, several fix rounds,
and about eight CI cycles. The defect class is "plan invents scope" + "plan
outgrows the brief"; both are computable at plan time for near-zero cost.

## Decision

Every plan emitted by `soleur:plan` carries a `## Scope Check` section with
three parts:

1. **`### Ask Mapping`** — one row per user ask (verbatim quote), mapped to the
   plan item that serves it. An ask with no item is `unmapped` unless marked
   `descoped` with a justification.
2. **`### Plan-Item Provenance`** — every plan item, default, rung, or added
   step cites the verbatim user words it answers ("per operator direction" must
   carry the quote), or is marked `inferred` with a justification naming the
   dependency or safety reason.
3. **`### Split Assessment`** — subsystem count, planned-file count, estimated
   changed lines, and a `single PR` / `split — <boundary>` recommendation. The
   thresholds (`>= 4` subsystem roots, `> 25` files, `> 800` estimated lines)
   are declared tunables, first values chosen so #9339 (101 files) is clearly
   over and a typical machinery PR is clearly under.

**Placement:** `soleur:plan` Phase 2.4 — after `## Files to Edit` /
`## Files to Create` are stable, before the Phase 2.5 domain fan-out, so a
BLOCKED verdict or split recommendation fires before expensive machinery.

**Enforcement:** `soleur:deepen-plan` §4.12 halts a plan missing the section,
carrying an `unmapped` ask (unconditional — the remedy is mapping it or
`descoped — justification`), or carrying a `descoped`/`inferred` row with an
empty justification, and emits a
`SOLEUR_RULE_APPLIED rule=plan-scope-check-blocks-unmapped-asks` telemetry line
on fire only. The canonical spec lives in
`plugins/soleur/skills/plan/references/plan-scope-check.md`; the schema is
replicated into all three tiers of `plan-issue-templates.md`;
`plan-scope-check.test.ts` pins the contract across all five surfaces
(canonical spec, plan pointer, three template tiers, deepen halt, plan-review
feed). `plan-review` feeds the section to code-simplicity-reviewer so "which
requirement does this mechanism satisfy?" has the verbatim ask list.

## Alternatives considered

- **`scripts/lint-plan-scope-check.py` + CI wiring** — rejected per ADR-131's
  (proposed) gate-moratorium tail-cost argument: a perpetual lint surface for a
  check that a prose halt + contract test already enforces.
- **Review-time-only check** — rejected: #9339 is the measurement that review
  catches this class too late, after deepen and fan-out spend.
- **Blocking PreToolUse hook on plan-file writes** — rejected: the check is a
  read-the-brief judgment a hook cannot make mechanically.
- **Do nothing** — rejected: the scope-reduction learnings show the class is
  systemic, not a one-off.

## Consequences

Plans grow one always-on section (~30 lines of template); deepen-plan grows one
halt. No new lint script, CI job, or hook — deliberately. The ADR-131 tension
(moratorium vs. this halt) is recorded in
`knowledge-base/project/specs/feat-one-shot-9398-plan-scope-check/decision-challenges.md`.
Split-threshold values are tunables to be adjusted on observed false positives.

**Enforcement boundary, stated plainly:** the block is plan-emit-time (Phase 2.4)
plus the deepen-plan §4.12 halt. A `soleur:plan` → `soleur:work` path that never
runs deepen-plan carries the section but meets no gate — matching the boundary
every sibling halt (§§4.6–4.11) already has. The deepen-plan *workflow port*
(`workflows/deepen-plan.workflow.js`) does not implement §4.12 — a documented
divergence on an opt-in path. Plans authored before this decision halt once on
their next deepen run until the section is hand-added; that one-time cost is
accepted.
