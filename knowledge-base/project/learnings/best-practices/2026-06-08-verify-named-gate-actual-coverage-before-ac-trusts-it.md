---
title: Verify what a named gate actually validates before an AC trusts it (2026-06-08)
date: 2026-06-08
category: best-practices
tags: [plan, acceptance-criteria, lint, validation-gate, lifecycle, fail-closed]
module: plan
pr_reference: '#5021'
problem_type: plan_quality
severity: P0
---

# Verify what a named gate actually validates before an AC trusts it (2026-06-08)

## Problem

In the `feat-shortform-feature-tweets` (#5021) plan, an Acceptance Criterion read
"…writes a draft with `status: draft`, `channels: x`, `pr_reference`, and a `## X/Twitter
Thread` section; `lint-distribution-content.sh` exits 0 on it." The AC's structure implied the
linter enforced those frontmatter fields + section heading. It does not: reading the script's
full source shows it checks **exactly one thing** — unrendered Liquid/Jinja markers (`{{ }} {% %}`)
in the body. A draft with garbage frontmatter and no `## X/Twitter Thread` heading passes lint
with exit 0, then dies silently at publish time (`content-publisher.sh` skips it to stderr).

A sibling instance in the same plan: the AC + Observability section claimed the existing publisher
"owns stale handling" for drafts. But `content-publisher.sh:800` gates `status != scheduled` →
`continue` *before* the stale-sweep at L804-808 — so a `status: draft` file **never ages out, never
alerts**. The detect-and-act lifecycle covered the `scheduled` state but not the `draft` state the
operator is most likely to leave un-acted.

Both were caught at plan-review (Kieran P0, spec-flow-analyzer SEV-1) — not by the plan author.

## Solution

When a plan AC names a gate (linter, validator, hook, cron sweep, test) as the thing that enforces
a correctness property, **read the gate's source and confirm it actually covers that property**
before the AC relies on it. Two concrete fixes applied:

1. Frontmatter/section well-formedness is now enforced by a **skill-owned structural assertion**
   (grep the assembled file for required fields + the `## X/Twitter Thread` heading, abort before
   write) — the Liquid linter stays scoped to Liquid markers only.
2. The stale-draft gap is closed by a campaign-calendar "Stale Draft" group (flags `draft` files
   older than N days) + in-session surfacing of the draft path in the postmerge report — i.e., the
   lifecycle now covers the un-acted `draft` state, not just `scheduled`.

## Key Insight

**A single-purpose gate passing ≠ the artifact is well-formed.** "X passes lint" and "X has the
required structure" are different claims unless you've read the linter and confirmed it checks the
structure. The same applies to detect-and-act lifecycles: a sweep that only transitions the
`scheduled` state silently strands every artifact stuck in the prior (`draft`) state — a
detect-and-act path must cover the state the human is most likely to leave un-acted, not only the
state immediately before the action. This is the plan-side instance of
`hr-verify-repo-capability-claim-before-assert` (verify a tool's real behavior before asserting it)
and the register-citation Sharp Edge in `plan/SKILL.md` (verify against canonical source).

## Session Errors

Session error inventory: none detected (planning session was clean). The two findings above are
plan-quality gaps caught and folded at plan-review, not execution errors.

## Cross-references

- `knowledge-base/project/plans/2026-06-08-feat-shortform-feature-tweets-plan.md` — the plan (findings folded into Research Reconciliation + Sharp Edges).
- `scripts/lint-distribution-content.sh` — the Liquid-only linter the AC over-trusted.
- `scripts/content-publisher.sh:800-808` — the stale-sweep that only touches `scheduled`.
- AGENTS.md `hr-verify-repo-capability-claim-before-assert` — the cross-cutting parent rule.
