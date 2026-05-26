---
title: Scope-out bundling can hide cheap inline fixes behind expensive ones — the CONCUR/DISSENT gate catches it
category: best-practices
date: 2026-05-11
issues: [3548, 3589, 3595]
tags: [code-review, scope-out, cost-of-filing, second-reviewer-gate]
---

# Scope-out bundling can hide cheap inline fixes behind expensive ones

## Problem

PR #3589 (lint-bot-synthetic glob widening, #3548) received a security-sentinel review surfacing 6 bypass classes in the lint predicate. Three were small isolated fixes (basename-exact-match, whitespace-flexible `gh pr create` grep, all-variant `[skip ci]` detection). Three were "YAML walker limitations" — bundled together because they sounded similar in framing.

My initial scope-out filing presented those three "walker limitations" as a single cross-cutting-refactor under one proposed fix: "rewrite the walker as a YAML-aware parser (~150 LOC + dependency + fixture suite)." The framing was technically correct — a real YAML parser would close all three. But it obscured the per-finding cost-of-filing analysis.

When the `code-simplifier` second-reviewer gate ran with the four scope-out criteria passed verbatim, it produced a DISSENT pinpointing one of the bundled findings: **YAML block-scalar variants (`|-`, `|+`, `>`, `>-`, `>+`) are a one-line regex extension, not a 150-LOC parser rewrite. `run: |-` is the canonical idiom in many GitHub Actions style guides.**

The DISSENT was correct. The other two findings (jobs-named-`run` collision, `actions/github-script` bridge) genuinely required YAML-aware parsing and had zero current exploitable shape. Splitting them out, fixing block-scalars inline (one regex line + 6-variant fixture loop, ~30 LOC), and re-filing the narrowed scope-out under `contested-design` produced a CONCUR.

## Solution

Apply the cost-of-filing gate **per finding**, not per bundle:

1. After review agents produce findings, list each one individually with a per-finding fix estimate (lines, files, complexity).
2. For any finding ≤30 lines AND ≤2 files: fix inline regardless of whether it "feels like" it belongs to a larger refactor.
3. Only after the per-finding pass is complete, group remaining findings by shared prerequisite and propose a bundled scope-out.
4. When the second-reviewer agent DISSENTs, read the dissent for the specific cited finding — flip just that one inline, then re-run the gate on the residual.

The four scope-out criteria define the gate; the **second-reviewer CONCUR/DISSENT gate** catches bundling pathology that the criteria alone cannot detect (because the bundle as a whole satisfies one criterion while individual items don't).

## Key Insight

> A bundled scope-out filing is suspicious by default. If three findings share a "proposed fix" sentence, ask whether each one **individually** crosses the cost-of-filing threshold before bundling them. The DISSENT-by-default posture of the second-reviewer gate exists precisely to catch this — when it fires, do not argue with the dissent; flip the named finding inline and re-evaluate.

The CONCUR/DISSENT gate is not a rubber stamp on a single filing — it is a per-finding sanity check that the bundle hasn't laundered cheap fixes into an expensive scope-out wrapper.

## Session Errors

This learning IS the prevention for session error #6. Other session errors below are fixture-design artifacts that point at the same YAML walker limitations now tracked in #3595.

1. **Test (g) fixture collision (`jobs.run:`)** — Recovery: renamed job to `audit:`. Prevention: tracked in #3595 (YAML-aware parser scope-out).
2. **Test (a)/(c) SYNTHETIC_POSTS shape** — Recovery: rewrote fixture mirroring `scheduled-content-publisher.yml`'s canonical multi-line shape. Prevention: WHY-comment in script documents the same-line `gh api ... check-runs` requirement.
3. **Test (h) initial fixture (`gh pr create` in run-block comment)** — Recovery: moved reference to YAML-level header comment outside any `run:` block. Prevention: `has_shell_pr_create` comment-agnosticism documented inline.
4. **Test (i) inline `- run: |` step shape** — Recovery: rewrote with `- name: X` / `run: |` two-line step shape. Prevention: this learning's "When writing fixture YAML" pattern below.
5. **Test 1 statuses copy drift ("All 1 scheduled" → "All 1 bot workflow(s)")** — Recovery: updated assertion. Prevention: when widening operator-facing copy in a lint script, grep the test files for old strings in the same commit.
6. **Scope-out filing dissented (block-scalars bundled with parser rewrite)** — Recovery: fixed inline, re-filed narrower scope. Prevention: this learning's main thesis.
7. **`git diff main...HEAD` returned empty in worktree (bare repo)** — Recovery: switched to `git status` + `git diff --stat`. Prevention: prefer `origin/main` over `main` in worktrees where local `main` ref may not exist.

## When writing fixture YAML for lint tests targeting the bash walker

- Use the standard two-line step shape: `- name: Foo\n        run: |\n          <commands>`. The `^([[:space:]]*)run:` regex requires `run:` at line start, not after a dash-marker.
- Avoid job names that collide with YAML keywords the walker matches (`run`, `uses`, `with`, `env`, etc.) until #3595 lands.
- Mirror real-workflow shape for canonical patterns: `gh api "repos/${{ github.repository }}/check-runs" \` is the documented multi-line continuation form. The lint requires both tokens on the same line.
- For comment-only fixtures, put the comment at YAML level (outside any `run:` block), not inside a shell `run:` block — the walker treats shell-script `#` comment lines as in-run content.

## Related

- AGENTS.md: `rf-review-finding-default-fix-inline` (the cost-of-filing rule this learning operationalizes)
- `plugins/soleur/skills/review/SKILL.md` §5 (the four scope-out criteria and CONCUR/DISSENT gate definitions)
- #3595 (the bundled scope-out that survived the gate after the inline split — covers jobs-named-`run` + `actions/github-script` bridge + audit-vs-lint enumeration drift)
- #3501-related: `knowledge-base/project/learnings/2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md` (similar bundling-vs-isolated reasoning for stale precondition budgets)
