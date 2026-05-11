---
module: review
date: 2026-05-11
problem_type: integration_issue
component: review_skill
symptoms:
  - "CSS file's self-documented contract with another file silently breaks when one side changes"
  - "Plan + pattern + architecture + code-quality reviewers approve a diff in isolation"
  - "Only git-history-analyzer reading the other-side artifact catches the drift"
root_cause: cross_artifact_contract_drift
severity: medium
tags: [multi-agent-review, contract-drift, cross-artifact, brand-guide, review-coverage]
synced_to: [review]
related_pr: 3556
related_issue: 3564
---

# Learning: Multi-agent review catches cross-artifact contract drift the rest of the agents miss

## Problem

In PR #3556 (font normalization), `apps/web-platform/app/globals.css:37` carried this comment:

```
Token names mirror knowledge-base/marketing/brand-guide.md exactly.
```

That comment is a **self-documented contract** — the CSS file promises to track the brand guide. The PR changed the typography (drop Cormorant Garamond, normalize to Inter) but did NOT update the brand guide, silently breaking the contract.

Eight of the ten review agents — pattern-recognition-specialist, architecture-strategist, code-quality-analyst, security-sentinel, performance-oracle, data-integrity-guardian, agent-native-reviewer, test-design-reviewer — approved the diff. None read the brand guide. Their scope was the diff and the file under it.

Only `git-history-analyzer` caught it. The agent:
1. Read `knowledge-base/marketing/brand-guide.md` for context on the typography spec
2. Read the CSS file's self-claiming comment at line 37
3. Cross-checked the two and flagged the contradiction as P1

## Solution

Fixed inline in two commits on the PR branch:
- Updated `knowledge-base/marketing/brand-guide.md` to scope Cormorant Garamond headlines to the marketing surface (Eleventy site, banners, landing) and add an explicit "Web-platform dashboard = Inter" row.
- The CSS comment at `globals.css:37` continues to claim fidelity to the brand guide; the brand guide now reflects the new dashboard state, so the contract is restored.

## Key Insight

**When a code/config file self-claims fidelity to another artifact (via comment, README, docstring), the multi-agent review pipeline can miss a divergence unless an agent is explicitly tasked with reading the claimed artifact.** This is the same defect class as the "telemetry-join format-contract drift" pattern in the review skill — internally each side passes tests, but the cross-stream contract silently breaks.

Three review agents covered the LOCAL code (pattern, architecture, code-quality) and all approved. The contract break was only visible by reading BOTH files. The git-history-analyzer's archaeology habit (read past commits + adjacent canonical docs) is what surfaced it.

## Prevention

**For future review prompts:** when the diff touches a file containing a "mirrors X" / "kept in sync with X" / "matches X" self-claim comment, include in the review prompt: *"Read the named artifact X and verify the claim still holds post-diff."*

**Scanner pattern (cheapest gate):** at plan time or review time, grep changed files for self-claiming comments:

```bash
git diff origin/main...HEAD --name-only | xargs rg -l "(mirror|matches|kept in sync|tracks|reflects) (the )?(knowledge-base/|docs/|spec/)" 2>/dev/null
```

Any hit produces a list of files whose changes must be cross-checked against the named artifact. This is the same shape as the existing `cq-eleventy-critical-css-screenshot-gate` (renders against an external truth, gates the diff).

## Session Errors

- **Bash CWD reset across calls** — Chained `cd apps/web-platform && cmd` worked, but a follow-up bare command lost CWD and got "no such file or directory". Recovery: use `cd <worktree-abs-path> && cmd` chains consistently. Prevention: discoverable via clear error; already documented in AGENTS.md (`hr-when-a-command-exits-non-zero-or-prints`). No new rule.
- **`next lint` triggered interactive ESLint setup prompt** — Project has no ESLint config; `next lint` blocks waiting for menu input. Recovery: skipped lint, relied on `tsc --noEmit` + `vitest run` as quality gates. Prevention: discoverable; this project uses TSC + Vitest, not ESLint. No new rule.

## Related

- Defect class entry in `plugins/soleur/skills/review/SKILL.md` § "Defect Classes This Review Reliably Catches" — "Cross-stream format-contract drift in telemetry joins" (PR #3124) is the closest precedent. This learning generalizes that pattern from telemetry joins to **any** self-claimed cross-artifact contract.
- PR #3556 — the originating PR.
- Issue #3564 — the deferred-scope-out filed in the same review session (CWV infrastructure, architectural-pivot).
