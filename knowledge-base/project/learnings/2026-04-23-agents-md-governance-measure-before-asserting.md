---
title: AGENTS.md governance — measure before asserting, two quantitative claims that proved wrong
date: 2026-04-23
category: process
tags: [agents-md, governance, brainstorm-hygiene, rule-metrics]
related_issues: [2686, 2754, 2762, 2865]
related_prs: [2754]
---

# Learning: AGENTS.md governance — measure before asserting

## Problem

During the 2026-04-23 revisit of the AGENTS.md rule-budget policy (issue #2865), two quantitative claims made during the prior brainstorm (2026-04-21, issue #2686, PR #2754) proved wrong when independently measured. Both would have changed the prior decision if they had been measured at the time.

The brainstorm session also exposed a third framing error in its own opening analysis — the "~93k combined always-loaded" claim — that only surfaced after a research agent verified the `@`-import chain.

## Concrete claims that proved wrong

### Claim 1 (PR #2754 spec): "migrating 3-5 skill-enforced rules to their skill files saves ~800 bytes"

**Actual measurement after merge:** +21 bytes net. Pointer-migration kept a ~200-byte pointer line in AGENTS.md for each rule. The full prose moved into the skill/hook file header, but the AGENTS.md pointer line (rule text + `[id: ...]` + `[skill-enforced: ...]`) cost approximately as much as the body it replaced. Three rules migrated → ~600 bytes of header content moved → ~600 bytes of pointer content added → essentially byte-neutral, with +21 bytes of incidental drift.

**Why this matters:** The PR #2754 decision banked on ~800 bytes of slack to stay under the threshold. The actual +21 bytes meant the 100→115 raise alone was load-bearing for the shrink. Two days after merge, the budget was re-breached at 113 rules / 40,654 bytes.

### Claim 2 (this session's opening analysis): "AGENTS.md + constitution.md combined always-loaded = 93k bytes"

**Actual chain:** `CLAUDE.md` contains a single `@AGENTS.md` import. Nothing else. AGENTS.md prose says "Detailed conventions live in `knowledge-base/project/constitution.md` — read it when needed." The "read when needed" is load-bearing — **constitution.md is on-demand, not always-loaded**. The always-loaded cost is AGENTS.md alone (~40.6k), not the combined 93k.

**Why this matters:** An "audit constitution.md too" option in the first AskUserQuestion was irrelevant. If accepted, it would have spent review cycles on a file that Claude Code is NOT warning about. A research agent caught this only after the opening analysis was sent.

## Why both claims slipped through

- **Claim 1:** Estimated savings based on rule-body character counts, without including the AGENTS.md pointer line that the migration pattern leaves behind. The estimator modeled a deletion (~zero residual cost) when the mechanic was actually a replacement (~200 byte residual per rule).
- **Claim 2:** Framing assumed `@constitution.md` was imported somewhere downstream — plausible because AGENTS.md mentions the constitution. The actual import graph is shallow and visible in CLAUDE.md directly. Verification takes 3 seconds (`grep '@' CLAUDE.md AGENTS.md`).

## Solution — measure, don't estimate

For any AGENTS.md governance brainstorm or plan:

1. **Verify the always-loaded set first.** Run `grep -E '^@[A-Z]' CLAUDE.md AGENTS.md` (and check `~/.claude/CLAUDE.md` for user-level imports). Report the exact set of always-loaded files before framing any budget.

2. **Measure claimed byte savings empirically.** For any proposed migration pattern, apply it to 1-2 rules on a scratch branch, run `wc -c AGENTS.md` before and after, and report the delta. Do not estimate. The pointer-migration case proved that estimate-based reasoning was off by two orders of magnitude (+21 vs -800).

3. **Question audit-tool output before citing it.** `scripts/rule-audit.sh` reported 4 "MISSING" hook files in this session; research found all 4 exist at different paths than the AGENTS.md tags claim. The audit script's simple-existence check is a crude heuristic, not a verified status. Before citing an audit finding, grep the repo for the named file anywhere (`find . -name "<file>"`).

4. **The discoverability litmus applies to governance claims too.** "Is this combined budget always-loaded?" is discoverable in 3 seconds. "What does pointer-migration actually save?" is discoverable in 5 minutes of scratch-branch measurement. If the answer is discoverable, do not accept an estimate.

## Key Insight

**Governance brainstorms are especially prone to estimate-based reasoning because the changes feel mechanical.** A rule migration looks like a byte-accounting problem — it should be estimable. But the mechanic includes residual pointers, immutability constraints, and cross-file references that naive estimates miss. The prior brainstorm's measurement gap shipped a threshold raise that was consumed in 2 days; the current brainstorm caught it only because a fresh audit surprised us with byte-neutral results. Make measurement a precondition for governance decisions, not a post-merge retrospective.

Two tight rules:

- Before asserting any always-loaded budget: `grep '@' CLAUDE.md AGENTS.md` and report the import chain.
- Before proposing any byte-savings migration pattern: apply it to 1-2 rules, measure `wc -c`, cite the delta.

## Session Errors

- **Claim-without-measurement propagated through two rounds of user-facing framing** — Recovery: research agent (`repo-research-analyst`) spotted both claims and reported measured values. — Prevention: add a pre-dialogue check in brainstorm Phase 1.1 when topic involves context-budget: verify always-loaded set + cite measured deltas, not estimated.
- **Session-start `cleanup-merged` skipped** per `wg-at-session-start-run-bash-plugins-soleur` — Recovery: worktree-manager script later fetched main during worktree creation, benign outcome. — Prevention: SessionStart hook that runs cleanup-merged automatically (follow-up issue; not implementing in this PR).
- **Repeated rule-audit.sh's "4 broken hook refs" finding without verification** — Recovery: research agent verified all 4 hooks exist at different paths. — Prevention: rule-audit.sh's existence check should scan the full repo, not just `.claude/hooks/`. Follow-up issue will track the heuristic fix.

## Related

- Issue #2865 — the revisit brainstorm acting on these measurements
- Issue #2762 — retired-ids allowlist (load-bearing unblock for real byte savings)
- Issue #2686 — original hybrid decision that banked on the estimate
- PR #2754 — the migration that shipped +21 bytes net
- Prior brainstorm: `knowledge-base/project/brainstorms/2026-04-21-agents-md-rule-threshold-brainstorm.md`
- Foundational learning: `knowledge-base/project/learnings/2026-02-25-lean-agents-md-gotchas-only.md` (ETH Zurich context cost data)
- Retirement pattern learning: `knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md`
- Byte-budget learning: `knowledge-base/project/learnings/2026-04-18-agents-md-byte-budget-and-why-compression.md`
