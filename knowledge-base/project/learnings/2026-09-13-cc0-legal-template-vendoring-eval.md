---
title: "Evaluating a CC0 legal-template library for vendoring: precedent-first convergence and the footnote-as-ad-unit"
date: 2026-09-13
category: workflow-patterns
related-brainstorm: knowledge-base/project/brainstorms/2026-09-13-legal-templates-cc0-eval-brainstorm.md
related-issues: ["#8122", "#3786"]
---

# Learning: CC0 legal-template vendoring evaluation (General-Legal/legal-templates)

## Problem

Operator asked (via an X post + repo link) whether to copy or reference `General-Legal/legal-templates` — 12 attorney-drafted CC0-1.0 startup legal templates — inside Soleur's legal skills.

## Solution

Six-way parallel assessment (CPO+CLO+CTO triad + CMO + repo-research + learnings-research) converged on the same controlling precedent before any design work: `2026-05-15-claude-for-legal-evaluation-brainstorm.md`'s no-integration verdict and the `content-vendoring.md` machinery. Operator then chose **vendor all 12** into `legal-generate/references/templates/` with template-fill generation.

## Key Insights

- **The footnote is an ad unit, not attribution.** Upstream embeds a "General Legal credit footnote" in every template — CC0 makes it optional, so shipping it in emitted docs is *choosing* to run a third-party firm's ad inside user deliverables. Disposition: retain in corpus (provenance), strip in output, grep the diff for `general.legal`/`General Legal` pre-merge per `hr-third-party-content-grep-on-undertaking`.
- **A published disclaimer can veto a feature.** `disclaimer.md` §2.3 affirmatively says generated docs are "not prepared by licensed attorneys" — vendoring attorney-drafted templates makes that literally false. ToS §7.2 + Disclaimer §2.3 amendments (TC_VERSION bump + CLO attestation) are a *blocking* cost of the copy path, not paperwork.
- **License-easier ≠ liability-easier.** CC0 removes Apache-2.0's NOTICE burden but the claude-for-legal objection (founder-grade audience relying on attorney-grade content, `single-user incident` threshold) survives intact — the DRAFT banner + "still requires counsel" framing carries the weight.
- **Check deferral criteria before re-deriving.** #3786's ALL-must-hold re-eval criteria for the sibling legal-content lift were still unfired — the correct move was to record that this feature partially serves that demand rather than pretend the question was new.
- **The real gap was doc-type coverage, not template quality.** Their 12 skew to bilateral contracts; our 8 are published-compliance docs. "Copy templates" reframed to "contract-type coverage with attorney-drafted baselines."

## Session Errors

1. **Issue-filing format miss (2 blocks).** `gh issue create` rejected twice by `guardrails:require-filing-justification`: missing `User-Impact:`/`Fix-Size:` lines, then `~30 files / 12 dirs` not matching `Fix-Size: <N> lines / <M> files`. **Prevention:** the hook's regex wants literal `N lines / M files`; write it exactly, first try.
2. **Commit guard false-positive on workdir param.** `git commit` with the exec `workdir` set to the worktree was blocked as "committing to main"; explicit `cd <worktree> && git commit` in the same command passed. **Prevention:** for git mutations in worktrees, `cd` inside the command rather than relying on the workdir parameter alone.
3. **Pre-existing orphan worktree.** `cleanup-merged` reported `feat-one-shot-supabase-bind-loopback` unremovable (EACCES) — unrelated to this session. **Prevention:** none; remediation pointer lives in git-worktree SKILL.md §Sharp Edges.

## Tags

category: workflow-patterns
module: brainstorm/legal-vendoring
