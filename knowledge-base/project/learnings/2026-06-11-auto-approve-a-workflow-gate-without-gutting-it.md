# Learning: Auto-approving a workflow gate without gutting it

## Problem

An operator asked, mid-brainstorm, to stop being prompted by the brainstorm skill's
Phase 0.1 user-impact framing question — they always answered "all of them," so the
`AskUserQuestion` was pure friction that never changed the posture (#5175, captured
from the #5085 brainstorm). The naive implementation — "just delete the prompt" — risks
two regressions: (a) silently *weakening* the gate if the deletion also drops the
flag-set, and (b) turning an always-on default into a rubber stamp that suppresses real
per-feature reasoning.

## Solution

Encode the operator's standing answer as an **unconditional default**, not a deleted gate:

1. **Set the flag unconditionally** (`USER_BRAND_CRITICAL=true`), no prompt, no keyword
   parse. Direction matters: the change must make the gate fire *more* (fail-safe /
   over-protect), never less. The old "no keyword → set false" branch is removed entirely.
2. **Keep the telemetry emit.** The `emit_incident … applied` block stays — the rule still
   records every application. Correct the now-false comment that described a "fired vs
   asked" ratio (there is no "asked" path anymore); state the accepted constant-ratio
   tradeoff explicitly rather than leaving a comment that lies.
3. **Add an anti-rubber-stamp guard.** The synthesized `## User-Brand Impact` block's
   *artifact* must be derived dynamically from the feature description (the real surface
   being built), never a static literal. Vector and threshold may be generic/fixed, but a
   concrete artifact keeps plan-time carry-forward and the review-time `user-impact-reviewer`
   honest.
4. **Ship it as its own PR.** The request surfaced inside an unrelated feature brainstorm
   (#5085); the workflow change went on a separate branch/PR (#5177 / #5175), never bundled.

## Key Insight

**A default-flip on a conditional gate can orphan a downstream block that branched on the
old condition.** Phase 0.1 setting the flag unconditionally made Phase 0.4's `Skip if
USER_BRAND_CRITICAL=true` *always* fire, rendering its `**Otherwise:**` lane-inference block
unreachable. The block can't simply be deleted (it's the escape hatch for a future
per-feature override), so the fix is a one-line clarifying note marking it vestigial. When
you make a flag unconditional, grep every downstream `if <flag>` / `Skip if <flag>` / `when
<flag> is set` site and either rewire it or annotate the now-dead branch — a reviewer
(pattern-recognition) reliably catches this, but it's cheaper to sweep at write time.

A secondary tell: prose that still says "when X sets the flag" or "the framing question was
answered" after X now sets it *always*. Sweep for conditional phrasing that implies a branch
that no longer exists.

## Session Errors

- **`gh issue create` denied for missing `--milestone`** (filing #5175) — Recovery: re-ran
  with `--milestone "Post-MVP / Later"`. Prevention: already hook-enforced by the
  `guardrails:require-milestone` PreToolUse gate; the hook fired as designed. One-off
  recovery, no workflow gap. (Also: never heredoc the issue body in the *same* Bash call as
  a hook-gated `gh issue create` — a denial takes the heredoc down with it; here the body
  was inline so no loss, but the Write-body-first pattern is the safe default.)

## Tags
category: workflow-patterns
module: brainstorm
