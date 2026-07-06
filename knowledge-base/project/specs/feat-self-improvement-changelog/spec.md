---
title: "Self-improvement changelog — operator-digest dogfood section"
feature: feat-self-improvement-changelog
issue: "#6039"
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec
date: 2026-07-06
brainstorm: knowledge-base/project/brainstorms/2026-07-06-self-improvement-changelog-brainstorm.md
---

# Spec: Self-Improvement Changelog (Dogfood Section)

## Problem Statement

Soleur's brand commits "self-improves" as core identity, and the compounding-
knowledge moat (roadmap theme T3, "Make the Moat Visible") is only a moat if
it is visible. Today the operator has no plain-language view of what the
self-improvement loop actually completed. #6039 originally asked for a
founder-facing changelog, but a live premise check found: **0 promotion PRs
ever opened, 0 beta users, and all improvement is global (not per-tenant)** —
so a founder surface would be an empty, mis-framed, write-mostly artifact.
This spec re-scopes to a dogfood: an honest, platform-framed section in the
operator's existing weekly digest.

## Goals

- G1 — Add a "What got smarter this week" section to the `operator-digest` skill.
- G2 — Surface only *completed* improvements: merged `self-healing/auto-*`
  promotion PRs (resolved via `promotion-log.md` cluster-hash) + retired rules.
- G3 — Render an honest, deterministic empty state when zero improvements
  merged in the window (the current common case).
- G4 — Keep every claim platform-truthful ("Soleur / your agents got sharper"),
  never per-tenant ("your workspace").
- G5 — Validate framing + real signal volume on the operator before any
  founder-facing surface is considered.

## Non-Goals

- NG1 — No founder-facing surface (in-product card, email). Deferred behind
  trigger: ≥1 beta user AND ≥N accumulated real promotions.
- NG2 — No new Inngest cron / web page / component (deferred with NG1).
- NG3 — No changes to the promotion loop itself (this surfaces existing
  activity; improving the loop is #6037's closed scope).
- NG4 — Do NOT count rule-metrics `prevented_errors` or weakness-digest
  patterns as "smarter" (found ≠ fixed — overclaim).

## Functional Requirements

- FR1 — New digest section reads merged `self-healing/auto-*` PRs in the 7-day
  window and the retired-rule diff; summarizes each as a plain-language "fix".
- FR2 — Each summarized fix carries a substantiation link to its merged PR
  (cluster-hash → PR lookup).
- FR3 — Empty-window renders a deterministic honest line: "Nothing was promoted
  to the shared harness this week." (never blank).
- FR4 — A FAILED read (non-zero `gh` exit) renders the ⚠️ read-failure line,
  NOT the quiet-week fallback (reuse operator-digest §"Read-failure handling").
- FR5 — Section copy is platform-framed; the string "your workspace" is
  prohibited in this section's output.

## Technical Requirements

- TR1 — Source only from sanitized artifacts (promotion-log, PR titles/labels,
  retired-rule-ids), never raw operational logs (data-minimization).
- TR2 — Follow operator-digest scope guardrails L1 (path scope) and L2
  (summaries only); no other-tenant identifiers or incident bodies.
- TR3 — Fallback/degraded-mode rendering is verified against a **real**
  promotion-log/PR shape fixture, not synthetic convenience fixtures
  (2026-06-11 digest-launch-quality learning).
- TR4 — No new secrets; reuse `_cron-shared` / claude-code-action auth already
  available to operator-digest.

## Deferred (follow-up issue)

Founder-facing changelog (weekly in-product card + monthly email), platform-
framed, forking `cron-weekly-release-digest.ts`. Requires Pencil wireframes +
an ADR for delivery-surface & tenant attribution. Trigger: ≥1 beta user AND
≥N accumulated real promotions.
