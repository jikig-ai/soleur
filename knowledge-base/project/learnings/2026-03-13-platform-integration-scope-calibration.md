---
title: "Platform Integration Scope Calibration: LinkedIn Case Study"
date: 2026-03-13
category: integration-issues
tags: [scope-calibration, platform-integration, plan-review, linkedin, social-distribute, community-agent]
module: plugins/soleur/skills/social-distribute
---

# Learning: Platform Integration Scope Calibration

## Problem

When planning LinkedIn as the 4th community platform (#138), the initial plan proposed a full-stack integration (12 acceptance criteria, 11+ files, 2 new scripts) including API scripts with stubs, docs site cards with placeholder URLs, scheduled workflow updates, dual content variants (company page + personal profile), and content-publisher automation. This mirrored the X/Twitter integration scope.

Three independent reviewers (DHH, Kieran, Code Simplicity) and SpecFlow analysis unanimously flagged this as overscoped. The core issue: building infrastructure for an API that doesn't exist yet, a company page that hasn't been created, and a content distinction (company vs personal) that is speculative.

## Solution

Cut scope to content generation only (manual-only, like IndieHackers/Reddit/HN):

1. **One LinkedIn variant** in social-distribute (not two) — thought-leadership tone usable from personal profile on day one
2. **Brand guide Channel Notes** — LinkedIn-specific voice guidance
3. **Platform detection table** — register LinkedIn as a known platform
4. **Agent description update** — mention LinkedIn in community-manager

Deferred items filed as 5 separate GitHub issues (#589-#593), each gated on a real prerequisite (API approval, company page URL, data on content differentiation).

Result: 5 files changed, 7 acceptance criteria (down from 12), zero dead code.

## Key Insight

The scope heuristic from the X integration learning (flag if >3 new files) predicted this correctly. But the deeper lesson is: **match scope to what can be validated on day one.** If you can't test it with real data (no API, no company page, no followers), it's speculative infrastructure. Ship the part that produces immediate value (content generation for manual posting) and file tracking issues for the rest.

The dual-variant decision was particularly instructive: SpecFlow identified that two LinkedIn variants (company page + personal profile) created an unresolvable ambiguity in the content-publisher's one-channel-to-one-section model. The architectural friction was a signal that the feature was premature, not that the architecture needed extending.

## Session Errors

1. `worktree-manager.sh cleanup-merged` failed when invoked from bare repo root — needs a worktree checkout context
2. CMO assessment agent reported brand guide as missing (it exists at `knowledge-base/marketing/brand-guide.md`) — agent searched wrong paths after knowledge-base restructure
3. `replace_all` on tasks.md accidentally marked incomplete items as done — always scope replacements to specific text blocks, not global patterns

## Tags

category: integration-issues
module: plugins/soleur/skills/social-distribute
