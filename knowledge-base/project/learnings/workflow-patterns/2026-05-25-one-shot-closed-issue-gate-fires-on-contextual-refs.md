---
title: /soleur:one-shot Step 0a.5 closed-issue abort fires on contextual `#N` refs, not just work targets
date: 2026-05-25
category: workflow-patterns
module: one-shot
related_prs: [4418]
related_issues: [3930, 3932]
tags: [one-shot, closed-issue-gate, workflow-collision, args-hygiene]
---

# /soleur:one-shot Step 0a.5 closed-issue abort fires on contextual `#N` refs, not just work targets

## Problem

The first `/soleur:one-shot` invocation for the JTI-revoke bundle (issues
#3930 + #3932) was aborted at Step 0a.5 because the invocation args contained
predecessor citations:

> "Bundle #3930 + #3932 — both deferred from PR-E #3887 merged via #3922"

Step 0a.5's closed-issue collision gate scans `$ARGUMENTS` for ANY `#[0-9]+`
substring and runs `gh issue view <N>` against each match. The regex does not
distinguish work-target refs (the issues the operator wants resolved) from
contextual citations (predecessor PRs, parent issues, dependent specs). When
the gate found `#3887` (CLOSED) and `#3922` (MERGED via a PR that is itself
CLOSED), it fired the closed-issue ABORT path and refused to create the
worktree.

The carve-out (`FILE_PATH_TARGET=true`, downgrade abort to advisory warning
when args resolve to a file path) did not apply because the args were a
freeform prose description, not a file path.

## Root Cause

The Step 0a.5 regex `#[0-9]+` is syntactic and matches semantic roles
indiscriminately. Both the work-target ref ("close `#3930`") and the
contextual citation ("from PR `#3887`") look identical. The gate cannot
infer intent from prose.

## Solution

**Re-invoke with closed refs scrubbed from prose.** The successful second
invocation replaced `PR #3887` / `PR #3922` with date-anchored phrasing:

> "Bundle issues #3930 and #3932 ... follow-ups from the PR-E byok deny-list
> work merged 2026-05-16"

Only the OPEN work-target refs (`#3930`, `#3932`) remained in `#N` form. The
gate ran cleanly.

## Prevention (Operator Workflow Rule)

When invoking `/soleur:one-shot` to bundle multiple issues with predecessor
context:

1. **Pass ONLY the OPEN work-target issues as `#N` refs in args.** Every `#N`
   in the args MUST be an open issue the pipeline should resolve.
2. **Reference closed predecessors WITHOUT the `#` prefix.** Use
   date-anchored phrasing ("merged 2026-05-16", "shipped in the prior week's
   PR-E sweep", "follow-up to the BYOK deny-list rollout") instead of
   `PR #3922`.
3. **Alternative carve-out path:** Invoke `/soleur:one-shot
   <path-to-plan>.md` directly. The Step 0a.5 file-path pre-scan sets
   `FILE_PATH_TARGET=true`, which downgrades the closed-issue abort to an
   advisory warning. Any `#N` in the plan file body becomes contextual by
   construction.

## Skill-Level Improvement (Proposed)

A future enhancement to `/soleur:go` (the routing entry point) could include
a pre-check that flags closed `#N` refs in `$ARGUMENTS` BEFORE invoking
`/soleur:one-shot`, with a one-line suggestion: *"Did you mean to reference
`#3887` as context, not a work target? Closed-issue refs in args trigger
Step 0a.5 abort — consider scrubbing or use the plan-file path carve-out."*
Filed as a deferred improvement; not promoted to a hard rule because the
existing workflow (scrub args, re-invoke) is low-friction.

## Cross-References

- `plugins/soleur/skills/one-shot/SKILL.md` Step 0a.5 — gate definition,
  including the `FILE_PATH_TARGET=true` carve-out (added per #4363).
- `knowledge-base/project/learnings/2026-05-25-multi-agent-review-catches-stale-precedent-grep-and-unreachable-ux-toast.md`
  §Session Errors #1 — co-occurring session-error capture.
