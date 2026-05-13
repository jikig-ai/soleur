---
title: Brainstorm — grep the cited flag/symbol against main before spawning leaders
date: 2026-05-13
category: best-practices
module: brainstorm
issue: 2939
related_prs: [3270]
tags: [brainstorm, leader-spawn, issue-body-staleness, verification, retired-symbol]
---

# Learning: Grep the issue body's cited flag/symbol against `main` before spawning leaders

## Problem

Brainstorm of #2939 (cc-soleur-go Stage 6 smoke + visual QA) ran Phase 0.5 leader assessment with the issue's framing — "flag-on smoke tests gated behind `FLAG_CC_SOLEUR_GO`" — as ground truth. CTO and repo-research-analyst both surfaced **independently** that the flag had been **retired ~6 weeks earlier by PR #3270**:

- `apps/web-platform/server/cc-dispatcher.ts:8` — "Originally gated behind FLAG_CC_SOLEUR_GO=1; the [flag now retired]"
- `apps/web-platform/server/ws-handler.ts:100,1021` — "Always `{ kind: 'soleur_go_pending' }` since #3270 retired FLAG_CC_SOLEUR_GO"
- `apps/web-platform/test/router-stickiness-invariant.test.ts:25` — same retirement comment

cc-soleur-go had been the unconditional production routing path since the retirement. The Stage 6 scope, as originally written, no longer mapped to reality — there was no flag to flip; the cutover had already happened. The leaders that ran on the stale framing then had to mid-assessment pivot from "pre-flip gate" to "post-cutover regression net," which reshapes risk model, golden paths, and PR layering.

## Solution

Add a Phase 1.1 check that runs BEFORE leader spawn:

```bash
# For each capitalized symbol cited in the issue body (FLAG_*, ENABLE_*, USE_*, *_ENABLED,
# uppercase camel-case feature names), grep main and read the first 10 lines of each match
# for a retirement comment.
ISSUE_SYMBOLS=$(echo "$ISSUE_BODY" | grep -oE '\b(FLAG|ENABLE|USE|FEATURE)_[A-Z][A-Z0-9_]+\b' | sort -u)
for sym in $ISSUE_SYMBOLS; do
  matches=$(git grep -l "$sym" main -- 'apps/web-platform/server/' 2>/dev/null)
  for f in $matches; do
    head -20 "$f" | grep -iE "retire|removed|deprecated|sunset" && \
      echo "WARNING: $sym referenced in $f with retirement signal — issue body may be stale"
  done
done
```

A 30-second check at Phase 1.1 saves a multi-leader spawn premised on the wrong scope. The brainstorm skill already has a similar hook for "Verifying referenced PR/issue state" (adjacent PR claims) and "Verifying 'approach 1 vs approach 2' claims" (named architectural approaches), but neither covers the failure mode here: the issue cites a symbol still referenced by name in its own body, and the retirement evidence is a code-comment in the symbol's owning module — not an adjacent PR or named approach.

## Key Insight

**The retirement-comment-in-owning-module is a high-signal failure mode for follow-through and Stage-N issues.** Multi-stage plans (Stage 1 → ... → Stage N) commonly create child issues at one point in time that describe the gating mechanism the parent plan assumed. Subsequent stages or out-of-band PRs may retire the mechanism while leaving the child issue's body untouched. The downstream issue is the **last fingerprint** of the old framing.

The check's leverage is asymmetric:
- **30-second cost** to grep + head a handful of files.
- **Multi-leader spawn + downstream pivot cost** if missed: in #2939's case, CPO's "kill-switch vs graded rollout" framing, CTO's "what flag-on means at the test boundary" advice, and the visual-QA's "one-time pre-flip gate" decision all had to reframe mid-assessment. Caught at Phase 1.1, they would have started from "post-cutover regression net" directly.

The check should target capitalized symbols (`FLAG_*`, `ENABLE_*`, `USE_*`, `FEATURE_*`, `*_ENABLED`) plus any explicitly-cited code module path in the issue body. The retirement signal vocabulary (`retire|removed|deprecated|sunset`) lives in the comment header of the symbol's owning file 90%+ of the time when a deliberate retirement happens. It does not catch silent removals (where the symbol just stops existing); a follow-up `git grep -c "$sym"` returning zero is a different signal that deserves a separate warning ("symbol cited in issue body but absent from main — issue may be stale or symbol was never named that").

This pairs with existing brainstorm Phase 1.1 Sharp Edges:
- "Verifying referenced PR/issue state" — adjacent PR claims
- "Verifying 'approach 1 vs approach 2' claims" — named architectural approaches
- This learning — cited symbols in the issue's own body

The three together cover the staleness shapes: PR-state, approach-state, and symbol-state.

## Session Errors

None detected this session — the brainstorm caught the staleness via leader convergence at Phase 0.5/1.1, not via a missed gate, so the cost was "leader compute on stale framing for ~3 min" not "shipped wrong scope." This learning is preventive: a Phase 1.1 grep moves the catch from "leader convergence" (which costs 3-5 min of parallel agent compute) to "30-second grep" (which costs nothing).

## Cross-references

- Issue: #2939
- Retirement PR: #3270
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-13-cc-soleur-go-stage-6-smoke-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-cc-soleur-go-smoke-2939/spec.md`
- Existing brainstorm staleness hooks (sibling checks):
  - "Verifying referenced PR/issue state" — `plugins/soleur/skills/brainstorm/SKILL.md` Phase 1.1
  - "Verifying 'approach 1 vs approach 2' claims" — same
  - "Verifying issue-body architectural constraints against plugin-wide rule corpus" — same
- Related learning: `2026-05-11-brainstorm-grep-approach-hook-before-spawning-leaders.md` (the named-approach variant of this same class)
