# Learning: measure the data-production rate before scoping a "make-X-visible" surface

## Problem

Issue #6039 asked to build a founder-facing weekly changelog surfacing Soleur's
self-improvement activity ("your workspace got smarter this week"). The framing
implied the raw material existed and just needed a display surface. A live
premise check during brainstorm found the opposite:

- `promotion-log.md` had **0 data rows**; `gh pr list --search "head:self-healing/auto-" --state all`
  returned **0 PRs** — the compound-promote loop has promoted nothing to date.
- **0 beta users** (roadmap Phase 4) — no audience for a founder surface.
- Improvement is **global** (shared harness: `AGENTS.core.md`, plugin `SKILL.md`),
  not per-tenant — so "**your** workspace got smarter" is a misleading claim.

Building the surface as-specced would have shipped an empty, mis-framed,
write-mostly artifact.

## Solution

Re-scoped to a dogfood: a platform-framed "What got smarter this week" section
in the existing `operator-digest` skill (operator audience, completed
improvements only, honest empty state). Deferred the founder surface (#6102)
behind a hard trigger: ≥1 beta user AND ≥N accumulated real promotions.

## Key Insight

Two cheap probes belong in every **"make X legible / visible / surfaced"**
brainstorm, run BEFORE spawning leaders or scoping a surface:

1. **Measure the data-production rate, not just data existence.** The
   write-mostly-artifact diagnosis (2026-05-12) checks for *closures*; extend it:
   count the rows/merged-PRs the source has *actually produced* over its lifetime
   (`wc -l` the ledger past its header marker; `gh pr list --search "head:<branch-shape>" --state all`).
   A source that exists but has produced ~0 entries means the display surface
   renders empty — the real prerequisite is making the *producer* work, not the
   viewer. An existence check (`ls`, "the table exists") passes while the
   production rate is zero.

2. **Check per-tenant vs global attribution before accepting possessive framing.**
   When copy says "*your* workspace/account/data got X", grep the producer for
   a tenant/workspace scope (`insert ... workspace_id`, `WHERE tenant =`). If the
   producer writes only global/shared artifacts, possessive per-tenant framing is
   a deceptive-implication risk (FTC net-impression / EU UCPD Art. 6) — reframe to
   product-level ("Soleur got sharper") before it reaches user-facing copy.

Both were confirmed by CPO/CLO/CTO/CMO convergence, but the 30-second grep/count
surfaced them faster than the leaders and made every leader prompt single-track.

## Tags
category: workflow-patterns
module: brainstorm
related: 2026-05-12-brainstorm-write-mostly-artifact-diagnosis-and-lifecycle-prereq.md
issue: "#6039"
