# Learning: When a plan builds a detection/classification control — verify the named threat entity is IN the protected set, and prefer a human-gate-on-all-changes over a reward-hackable classifier for a not-yet-existent threat actor

## Problem

Plan #6103 (a semantic-weakening detector for AGENTS.md hard-rule bodies, prereq for the deferred
#6038 auto-proposer) went into a 4-agent review panel (spec-flow, architecture-strategist,
security-sentinel, code-simplicity). The panel converged on findings the plan author (me) had
missed, all of the same family:

1. **The headline threat rule was not in the control's protected set.** The plan's `## User-Brand
   Impact` named `hr-gdpr-gate-on-regulated-data-surfaces` reworded mandatory→advisory as the
   nightmare. But the plan's strong control (an ack + mandatory human review) was scoped to
   `[compliance-tier]`-tagged rules — and `hr-gdpr-gate` is tagged `[hook-enforced]`, NOT
   `[compliance-tier]` (AGENTS.core.md:43). So the exact rule the threat model named fell into the
   *weak* (reward-hackable lexer) bucket. The control did not cover its own stated nightmare.
2. **The classifier was the weak half, guarding a threat actor that doesn't exist yet.** The
   deontic-strength lexer (the plan's centerpiece) auto-classifies a body change as weakening vs
   strengthening. But its only distinct value is catching a *machine* weakening without a human in
   the loop — and no machine writes these rule bodies until #6038 (the auto-proposer) ships ~1 month
   out. Meanwhile it (a) misses no-hedge scope-narrowing (its own documented false-negative), and
   (b) needs false-positive calibration + threshold tuning that only real digest evidence can
   provide. A per-change human ACK required on EVERY hard-rule body change is both STRONGER (covers
   all rules, all weakening shapes) and SIMPLER (~half the build surface).
3. **"A job in ci.yml" ≠ "a required check."** The plan said "register it as a required status
   check" but merge-blocking in this repo is enforced by
   `scripts/ci-required-ruleset-canonical-required-status-checks.json` +
   `infra/github/ruleset-ci-required.tf` (CODEOWNERS-pinned) — a job merely existing in ci.yml runs
   *advisory* (PR mergeable while RED). The security gate would have shipped bypassable.
4. **Self-ack + stale-ack + vacuous recursion test**: the ack file was writable by the same PR
   (one key, vs the sibling `lint-rule-ids.py`'s two keys), the ack was per-id not per-change (a
   stale ack lingered forever), and the recursion-invariant test asserted files ∉ `TARGET_ALLOW_RE`
   — always true, since the regex only matches `AGENTS.core.md` + `SKILL.md` (it tested a tautology,
   not the real catch property).

## Solution

Operator chose the panel's **minimal v1**: manifest + per-change hash-bound CODEOWNERS-gated ACK
required on ANY `hr-*`/`wg-*` body change/deletion (NOT the lexer) + required CI check wired into
the canonical ruleset + drift-guard + a recursion test that imports the live `TARGET_ALLOW_RE` and
asserts the real catch property. Lexer, LLM-judge, C4 component, lefthook mirror, and the soak
follow-through deferred to the #6038 proposer PR (where a machine writes bodies + digest evidence
tunes thresholds). This is stronger AND simpler than the original plan.

## Key Insight

Three reusable checks when a plan builds ANY detection / classification / guard control:

1. **Verify the specific entity your threat model names is actually IN the control's protected set.**
   A control scoped by a tag/label/allowlist must be cross-checked against the exact rule, route,
   table, or field your `## User-Brand Impact` (or threat model) names as the nightmare — grep for
   that entity's membership. It is startlingly common to build a control that excludes its own
   headline case (here: the strong gate covered `[compliance-tier]` but the named rule was
   `[hook-enforced]`).
2. **A classifier that distinguishes "bad change" from "ok change" only earns its keep if a
   NON-HUMAN actor makes the changes.** If every change already passes through a human, a
   reward-hackable classifier adds false-positive cost + a bypass surface while a
   block-everything-pending-human-ack is both stronger (no classification gap) and simpler. Defer
   the classifier until the machine writer it guards actually exists — and until you have evidence
   to tune its thresholds. (Matches the brainstorm's own NG4 / CPO "provisional, don't tune blind.")
3. **"Required check" is a ruleset fact, not a workflow fact.** In this repo, a job in `ci.yml` is
   advisory until its context is in `ci-required-ruleset-canonical-required-status-checks.json` +
   `ruleset-ci-required.tf` (+ enrolled in the required-check drift-guard cron). Any plan adding a
   merge-blocking check MUST edit those, not just add the job. Same class as the existing
   branch-protection sharp edge in plan/SKILL.md.

Meta: a 4-agent panel (spec-flow for flow/edge-cases, architecture for invariants/ADR/C4, security
for gate-integrity/bypass, simplicity for YAGNI) on a `single-user incident` plan caught a scope
error the author's own plan-review pass did not — the classifier-guards-nobody insight required the
simplicity lens, the tag-coverage gap required the flow lens, and the ruleset-wiring gap required
the security lens reading the actual ruleset files. At single-user threshold, run the panel.

## Session Errors
- **Plan v1 built a control that excluded its own headline threat rule** (strong gate scoped to
  `[compliance-tier]`; `hr-gdpr-gate` is `[hook-enforced]`). Recovery: ack required on ALL hr-/wg-
  bodies. Prevention: check #1 above (grep the named threat entity's membership in the control set).
- **Plan v1 centerpiece (lexer) guarded a machine writer that doesn't exist yet.** Recovery:
  deferred to the proposer PR; human-ack-on-all-changes is the v1 control. Prevention: check #2.
- **Plan v1 treated "job in ci.yml" as a required check.** Recovery: wire the context into the
  canonical ruleset JSON + .tf + drift-guard. Prevention: check #3 (route-to-definition candidate —
  the plan/SKILL.md branch-protection sharp edge covers the audit but not the "job≠required" fact).

## Tags
category: best-practices
module: plan, review-panel, ci-required-ruleset, harness-safety
