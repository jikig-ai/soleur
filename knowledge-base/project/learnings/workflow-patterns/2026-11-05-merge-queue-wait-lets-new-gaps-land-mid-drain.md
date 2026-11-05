---
title: "A merge-queue dependency wait lets NEW gaps land on main mid-drain — re-audit after the rebase"
date: 2026-11-05
category: workflow-patterns
related: [10861, 12110, 12070, 12127, 12128]
---

Resuming a `s4-drain` strict-zero slice after its dependency (#12128) merged: the rebase surfaced a
gap pair that did not exist at measurement time — a suite (`codeql-to-issues-sweep-wiring`) had landed
via #12070's queue merge DURING the ~70 min wait and read `.github/workflows/codeql-to-issues.yml`
with no declared edge. Suite census moved 731 → 732.

Rule: when a drain plan's measurement predates a dependency merge, the post-rebase audit is a NEW
measurement, not a confirmation — absorb residual per the epic contract (real read → declare an
`AFFECTED_<LABEL>_PATHS` edge in `scripts/lib/test-affected-paths.sh`; mention → anchor-keyed accept
row). The `CODEQL_TO_ISSUES_SWEEP_WIRING` block is the worked example (sibling convention: workflow +
self + `THIS FILE`).

Also measured: GitHub merge-queue PRs show `mergeStateStatus: UNKNOWN` indefinitely while queued —
poll the `merge_group` Actions run (event=merge_group, branch `gh-readonly-queue/main/pr-<N>-*`) for
the actionable signal, not the PR mergeable field. Exit-coded background poll subagents work well
(75-min deadline, exit 0 on MERGED).
