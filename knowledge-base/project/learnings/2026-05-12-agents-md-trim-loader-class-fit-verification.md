---
date: 2026-05-12
category: best-practices
module: agents-md
issue: 3679
pr: 3681
tags: [agents-md, rule-budget, session-rules-loader, work-skill, demotion]
---

# Learning: AGENTS.md wg-* demotion must verify loader-class fit, not just rule semantics

## Problem

When trimming the always-loaded AGENTS payload (AGENTS.md index + AGENTS.core.md sidecar) under the 22 k critical threshold, the deepen-plan classified `wg-plan-prescribed-skills-must-run-inline` as "fires at `/work` Phase 4 entry; `/work` runs on code/infra sessions exclusively. Safe." This was wrong: `/work` can run on docs-only PRs (plan-only edits, knowledge-base content). The `.claude/hooks/session-rules-loader.sh` loads `AGENTS.rest.md` only when `HAS_CODE=1` or `HAS_INFRA=1`; a docs-only `/work` session would silently lose the gate that prevents deferring named-skill checkpoints to "operator at PR time" — defeating `hr-gdpr-gate-on-regulated-data-surfaces`'s skill-invocation requirement on regulated-data surfaces.

Pattern-recognition reviewer (F1 HIGH) caught this pre-merge. The plan's mitigation reasoning ("rule fires on code/infra only") was a category error: the rule governs `/work`'s skill-invocation behavior independent of changeset class.

## Solution

Reverted demotion: moved `wg-plan-prescribed-skills-must-run-inline` back to `AGENTS.core.md` but body-trimmed from 1,004 B → 433 B (>50% reduction while preserving the load-bearing constraint + `hr-gdpr-gate-on-regulated-data-surfaces` cross-reference). Trimmed body:

```text
When a plan checkpoint names a Soleur skill (e.g., `/soleur:gdpr-gate`,
`/soleur:qa`, `/soleur:preflight`), `/soleur:work` MUST invoke it at the
checkpoint — never defer to operator at PR time
[id: wg-plan-prescribed-skills-must-run-inline]. If unavailable, mark
`pending-operator` and surface the gap.
**Why:** PR-A2 #3603 — closes work-skill deferral-loophole on
`hr-gdpr-gate-on-regulated-data-surfaces`.
```

Post-fix always-loaded: 21,985 B (15 B under 22 k critical). The trim respected `cq-agents-md-tier-gate`'s "already-enforced" branch (the rule is reinforced by the work skill's own enforcement tags) while keeping the constraint visible on every session class.

Kept-as-is decisions documented in PR #3681 review summary:
- `wg-every-session-error-must-produce-either` (F2): plan §Risks authored the tradeoff with named mitigations (`cq-agents-md-tier-gate` in AGENTS.docs.md + `wg-when-a-workflow-gap-causes-a-mistake-fix` in core). Per `rf-when-a-reviewer-or-user-says-to-keep-a`.

## Key Insight

When demoting `wg-*` rules core → rest, **verify the rule's trigger surface against the loader's class table, not against the rule's authored intent.** Two distinct properties:

1. **Changeset class** (what the loader sees: docs / code / infra / mixed) — a function of the diff.
2. **Skill-invocation context** (where the rule semantically fires) — a function of which skill runs.

A rule like "`/soleur:work` MUST invoke X" applies whenever `/work` runs, regardless of changeset class. If demoted to rest, it disappears on docs-class `/work` sessions. The plan author's reasoning that "`/work` runs on code/infra sessions exclusively" is a frequent category error: skill invocation is orthogonal to changeset classification.

**Verification gate for future demotions:** for each proposed wg-* demotion, grep `.claude/hooks/session-rules-loader.sh` for the load conditions and answer: "Can the situation that triggers this rule occur during a session that the loader classifies as `docs-only`?" If yes → rule belongs in core (body-trim if budget requires).

## Session Errors

1. **Phase 4 handoff fired with uncommitted work.** /work emitted `## Work Phase Complete` and continued to review; review agents got an empty `git diff origin/main...HEAD` because Phase 1-4 edits were never committed (only the initial wip stub was on origin). — **Recovery:** committed work then re-ran diff capture. — **Prevention:** add a Phase 4 entry-guard to `plugins/soleur/skills/work/SKILL.md`: before invoking review/qa/compound/ship, assert `git log origin/<branch>..HEAD --oneline | wc -l > 0` so the chain doesn't fire against a stale remote.

2. **Plan's loader-class-fit reasoning was wrong** (the F1 finding above). — **Recovery:** pattern-recognition reviewer caught at PR time; reverted demotion. — **Prevention:** add a check to `plugins/soleur/skills/plan/SKILL.md` (and `deepen-plan/SKILL.md`) so any proposed `wg-*` core→rest demotion grep-verifies the rule's trigger surface against the loader's class table.

3. **Why-line over-trim dropped semantic per-issue labels** (F4). Trimming `#2618 per-command-ack; #2880 operationalized for non-interactive exec.` to `#2618; #2880.` stripped the load-bearing mechanism distinction. — **Recovery:** restored to `#2618 per-command-ack; #2880 non-interactive exec.` (+28 B). — **Prevention:** Why-line trim guidance (in compound and `cq-agents-md-why-single-line`) should explicitly preserve per-issue semantic mechanism labels (the words after `#N`), trimming redundant prose only.

## Tags

category: best-practices
module: agents-md
