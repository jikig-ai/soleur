# Learning: planning a CI enforcement gate — grep existing suites first, match repo script conventions, and don't reflexively deepen

## Problem

Planning the "close-loop engineering gaps" work (#5269) risked building a gate that already
existed, prescribing a script convention the repo doesn't use, and burning a deepen-plan
fan-out with no surface to bite.

## Solution / Key Insights

1. **Before building a format/enforcement gate, grep the existing test suites for the cited
   incident class — the premise is often already closed.** The brainstorm's "Gap 1"
   (hand-authored artifact format bypass) was framed as unenforced, but research found it
   **already CI-gated by four tests** (`distribution-content-format`, `seo-aeo-drift-guard`,
   `marketing-content-drift`, `validate-seo`, run by `ci.yml` `test-bun` shard), and the
   AGENTS.md rule-budget gate the research suggested building was **already wired**
   (`scripts/test-all.sh:121`). Net: scope narrowed to the one genuinely-unbuilt gate (Gap 3
   sweep-completeness) and Gap 1 was deferred. Generalizes paraphrase-without-verification to
   "verify the GAP exists before building the gate."

2. **Match the repo's check-script convention: `set -uo pipefail` (NO `-e`).** Every
   `.github/scripts/check-*.sh` omits `-e` deliberately so the script enumerates ALL violations
   before exiting (work-list discipline). A plan prescribing `set -euo pipefail` fights that —
   `-e` aborts on the first non-zero. Verify the convention against sibling scripts; don't
   assume `-euo`. Corollary: derive the PR changeset via `gh pr diff --name-only` (repo form),
   and **fail closed** (`exit 1`) when the changeset can't be derived — never `exit 0` on an
   unobtainable diff (silent-fallback false-negative).

3. **A registry that gates other files must self-check its own paths.** The sweep gate verifies
   every `trigger`/`dependent` path exists on disk on each run (else `exit 1`). This is the
   close-loop discipline applied inward: it stops the registry from rotting silently and makes a
   legitimate dependent-deletion obligate a same-PR registry edit.

4. **For a deterministic, non-DB / non-security / non-architecture plan, a 4-agent plan-review
   (DHH + Kieran + code-simplicity + spec-flow-analyzer) already covers deepen-plan's substance
   surface.** deepen-plan's domain triad (data-integrity-guardian / security-sentinel /
   architecture-strategist) targets SQL atomicity, security primitives, and new architecture —
   none present in a bash diff-set gate. spec-flow-analyzer (run in plan-review) is the
   substance-catcher for non-DB plans. Recommend deepen-plan at single-user-incident threshold,
   but don't reflexively spawn the full triad when it has nothing to bite (hr-weigh-…, YAGNI).

## Session Errors

1. **IaC-routing PreToolUse hook blocked the first plan Write** — it substring-matched
   `doppler secrets set` even though the phrase was quoted as a NEGATIVE example (the plan's
   Phase 2.8 section listing infra patterns the plan does NOT use). Recovery: added the
   sanctioned `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out comment and reworded
   the literal to "a Doppler secret write." **Prevention:** when a plan must quote infra
   patterns (`ssh root@`, `systemctl`, `doppler secrets set`, vendor-dashboard wording) even as
   negative examples, add the `iac-routing-ack` comment up front (after reviewing Phase 2.8), or
   avoid the literal trigger string. The hook's broad substring scan is intentionally
   fail-closed; the ack is the designed opt-out, not a bug to fix.

## Tags
category: workflow-patterns
module: plugins/soleur/skills/plan; .github/scripts; .claude/hooks (iac-routing guard)
