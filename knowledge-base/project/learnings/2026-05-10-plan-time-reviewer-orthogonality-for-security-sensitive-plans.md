---
title: Plan-time reviewer orthogonality for security-sensitive plans
date: 2026-05-10
category: best-practices
tags: [plan-review, security, brand-survival, single-user-incident, reviewer-consensus]
related_pr: 3522
related_issue: 3518
related_brainstorm: 2026-05-09-gdpr-gate-skill-brainstorm.md
status: active
---

# Plan-time reviewer orthogonality for security-sensitive plans

## Problem

For plans whose `brand_survival_threshold: single-user incident` is carried forward from brainstorm — typically credential-leak, auth, payment, or PII surfaces — auto-accepting any single reviewer's verdict mis-aligns the plan in a predictable direction. v2 gdpr-gate (#3518, brand-survival = single-user incident) made the orthogonality concrete:

- **DHH-style review** finds simplicity wins (cut 14 patterns to 7; cut 4 anchor fixtures; cut a 6-step Sign-off ceremony list). Bias: cut anything that isn't load-bearing right now.
- **Code-Simplicity review** converges 80% with DHH (similar cut list) plus surfaces YAGNI-shaped padding (e.g., 8-row Risks table → 4). Bias: defer everything not load-bearing today.
- **Kieran-style review** finds rigor holes (silent-typo bypass in `GDPR_GATE_REPO_SCAN_ALLOW_PATHS` where a typo'd path coincidentally matches a deny pattern; canonical-regex semantic drift between `--diff` and `--repo-scan`; archive-vs-rewrite for shape changes). Bias: every load-bearing security invariant has an explicit test that fails on regression.

The simplicity reviewers wanted to cut what Kieran wanted to harden (e.g., Code-Simplicity's "delete all 4 anchor fixtures" was correct AND Kieran's "if you keep them, harden them against gitleaks JWT detection" was correct — they're the same advice from opposite poles). Neither is wrong individually; auto-accepting either alone produces a bad plan.

## Solution

For security-sensitive plans (any plan with `brand_survival_threshold: single-user incident` in frontmatter, or any plan whose Files-to-Edit touches `auth/`, `secrets/`, `migrations/`, payment, or credential surfaces), apply the **union+intersection** rule:

- **Apply the union of cuts** from DHH + Code-Simplicity (anything both flag as cargo-cult is gone; anything one flags is presumed gone unless Kieran defends it on rigor grounds).
- **Apply the intersection of P1 hardening** from Kieran (every Kieran P1 is load-bearing; P2 is high-value; P3 is nice-to-have).
- **Re-spawn the relevant domain leader** at plan time — not just brainstorm carry-forward — for any architectural surface the brainstorm leader didn't bless. v2 gdpr-gate added `--repo-scan` (new architectural surface); CTO's targeted re-review found 5 ship-blocking design issues (path-allowlist shape, sole-arg sentinel, deny-list completeness, batching size, AGENTS.md-vs-SKILL.md placement). Brainstorm CTO assessment from 24h prior was insufficient.

The resulting plan is shorter than the simplicity reviewers' cut would produce (because Kieran's hardening adds tests + clauses) AND shorter than Kieran's rigor would produce alone (because simplicity cuts kill the cargo-cult that Kieran would have left in place). The 3-way consensus is the signal; any single reviewer's verdict in isolation is not.

## Key Insight

**Three plan-reviewers + one targeted domain-leader re-review is the minimum viable rigor floor for `single-user incident` plans.** The reviewers have intentionally different biases — that orthogonality IS the value. Treating the 3-reviewer skill output as "pick the winner" loses the orthogonality and produces a plan that's either over-cut (simplicity wins, hardening lost) or over-padded (rigor wins, padding kept). Treating it as "apply the union of cuts AND the intersection of hardening" is the correct synthesis.

For lower-threshold plans (`aggregate pattern` or `none`), the simplicity bias wins by default and Kieran's P2/P3 nits can be deferred. For `single-user incident` plans, every Kieran P1 is load-bearing — defer none.

## Session Errors

None detected. The plan flowed cleanly through brainstorm carry-forward → CTO targeted review → draft → 3-reviewer plan-review → revisions. The interesting outcome wasn't an error but the recognition that the three reviewer biases are orthogonal — captured here for future security-sensitive plan sessions.

**Prevention:** Future plan-review consumers on `single-user incident` plans should default to the union+intersection rule rather than picking a winning reviewer. Plan skill could surface this convention in its "After review completes" instructions; deferred to a follow-up issue rather than rule churn.

## Tags

category: best-practices
module: plan-skill, plan-review-skill
applicability: security-sensitive plans (single-user incident threshold)
