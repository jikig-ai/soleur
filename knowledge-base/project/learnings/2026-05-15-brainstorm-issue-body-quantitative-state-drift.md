---
title: Brainstorm — re-measure quantitative state cited in issue bodies before treating it as a constraint
date: 2026-05-15
category: best-practices
tags: [brainstorm, issue-body-drift, premise-validation, agents-md-sidecars]
pr: 3808
issue: 2741
---

# Brainstorm — re-measure quantitative state cited in issue bodies before treating it as a constraint

## Problem

Issue #2741 (filed 2026-04-21) included a precise quantitative premise in its body:

> **Budget:** ~520 bytes. Current AGENTS.md at 106/100 rules and 36566/40000 bytes. Adding this rule requires retiring another rule OR compressing narrative first.

By 2026-05-15 (when the brainstorm for the bundle PR ran), the world had moved on: `AGENTS.md` had been sharded into sidecars via a separate refactor. Current state:

| File | Bytes | Rules |
|---|---|---|
| `AGENTS.md` (pointer index) | 4,662 | 75 pointers |
| `AGENTS.core.md` | 18,534 | 52 |
| `AGENTS.docs.md` | 2,154 | 4 |
| `AGENTS.rest.md` | 7,120 | 19 |
| **Total** | **32,470** | **75** |

The single-file 40,000-byte / 100-rule cap that the issue body assumed no longer exists. There is now an always-loaded budget (`AGENTS.md` + `AGENTS.core.md`) and a registry total — neither matches the cited numbers, and the "retire a rule or compress" prescription is a non-sequitur against the current architecture.

If the brainstorm had treated the cited state as ground truth, it would have spent its energy designing a rule-retirement procedure (which alternative to retire? which sidecar to compress?) against a constraint that was no longer load-bearing.

## Solution

Treat any quantitative state cited in an issue body — rule counts, byte sizes, file counts, headroom percentages, inventory counts, "currently at N/M" claims — as **point-in-time** the moment the issue was filed, never as a constraint at brainstorm time. Re-measure with a one-liner BEFORE letting the cited number bound the option space.

For AGENTS.md specifically:

```bash
echo "=== rule counts ==="
for f in AGENTS.core.md AGENTS.docs.md AGENTS.rest.md; do
  printf "%-20s " "$f"; grep -cE "\[id: " "$f"
done
echo
echo "=== total bytes ==="
cat AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md | wc -c
```

Generalized: when an issue body contains the pattern `\d+/\d+` adjacent to words like `bytes`, `rules`, `headroom`, `slots`, `cap`, `quota`, `tasks`, `lines` — pause Phase 1.1 research and re-measure the same quantity against current `main` before any approach proposal.

## Key Insight

The Soleur brainstorm SKILL.md already encodes **eight** distinct "verifying X claims" patterns at Phase 1.1 (mounted/wired, regression-of-#N, referenced PR/issue state, approach hooks, leader infra/substrate, issue-body rules, option enumerations, flag/symbol presence). This case adds a ninth flavor: **quantitative-state drift on tracked artifacts that have been subject to recent refactor PRs**. The signature is: an issue more than ~2 weeks old, an explicit `N/M` claim against a file the project has been actively refactoring, and a prescription chain ("therefore X is required") downstream of that claim.

The brainstorm SKILL.md's existing "verify referenced PR/issue state" rule is the closest match but doesn't cover this case — it covers *adjacent* PR claims ("PR #N adds X"), not *self-citation of artifact metrics* ("AGENTS.md is at 106/100"). Worth adding as a Phase 1.1 sub-pattern, but the cost of formalization may not be load-bearing yet: this is N=1, and the existing eight patterns are already a heavy reading load. **Recommendation:** capture the pattern here, link from the brainstorm SKILL.md's Phase 1.1 only if a second instance shows up within 60 days.

## Meta-loop

This brainstorm session was itself a real-time demonstration of #2733's proposed Phase 1.0.5 (Premise Validation): the AGENTS.md re-measure happened at exactly the point in the brainstorm flow where Phase 1.0.5 would fire (between Phase 1.0 external-platform verification and Phase 1.1 research fan-out). The "first instance of the new pattern's value is the brainstorm that proposes the pattern" makes the case for #2733 itself.

## Session Errors

- **Used `gh pr view` for issue numbers** — first lookup returned GraphQL "no such PullRequest" for #2731-#2741 because they're issues, not PRs. **Recovery:** re-queried with `gh issue view`. **Prevention:** when an issue/PR reference lacks an explicit prefix in the user's message, query both endpoints in parallel, or run `gh search issues+prs --json number,state,type` once and dispatch on `type`.
- **Wrong `grep` pattern for sidecar rule counting** — used `^### \[` (the legacy AGENTS.md heading format) and got 0 matches across all three sidecars. **Recovery:** switched to `\[id: ` which matches the actual format. **Prevention:** `head -20` a refactored file once before scripting any counter against it; assume nothing about heading conventions post-refactor.

Neither error warrants a hook — both are recovery-within-the-turn and tied to one-off introspection. Documented for the closed-loop pattern only.

## Related

- [[2026-04-21-agents-md-rule-retirement-deprecation-pattern]] — the precedent retirement mechanism (still applies to in-file rules; only the "100/40000 single-file cap" assumption is obsolete).
- [[2026-05-12-brainstorm-defer-decision-issue-body-rule-drift-and-oauth-only-bundling-scope-bound]] — Pattern 1 covers issue-body *constraint* drift (rule claims); this learning covers issue-body *quantitative* drift (count/byte claims).

## Tags

category: brainstorm-process
module: plugins/soleur/skills/brainstorm
