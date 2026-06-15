---
title: "No persisted session" is a claim requiring a Playwright probe, not an answer
category: workflow-patterns
tags: [playwright-mcp, operator-steps, automation-claims, linkedin, probe-receipt]
issue: 5334
date: 2026-06-15
---

## Problem

During a LinkedIn Marketing-Developer-Platform (MDP) access task, the agent wrote
"auth-gated — no persisted session to drive headlessly" into **a user message AND two GitHub
issues (#4049, #5137)** — without ever invoking Playwright MCP. The claim was an a-priori
assertion about the LinkedIn Developer Portal's auth state, not an observation.

A later probe (`browser_navigate https://www.linkedin.com/developers/apps` + `browser_snapshot`)
showed the Playwright MCP session was **already authenticated**: "My apps" listed **Soleur
Community** (app `229658411`) and **Soleur** (app `229637496`), both Jikigai Company verified.
The portal flow was fully Playwright-drivable; no operator login was required to reach it.

The agent had to retract the claim, correct both GitHub issues, and re-derive the real state —
all avoidable. This is the **third** bypass of the `hr-never-label-any-step-as-manual-without`
class:
- PR #4227 — deferred inline-automatable post-merge steps.
- PR #5082 — deferred a browser-automatable step by asserting an MFA gate (→ the
  `playwright-attempt:` evidence line added to work Phase 4 + ship Phase 5.5; see
  `2026-06-10-playwright-attempt-evidence-before-operator-only.md`).
- **This incident** — the prior gates fire on *deferral / operator-step classification*, but
  the unprobed claim here leaked straight into a user message + GitHub issues with no deferral
  artifact at all.

## Solution

The hard rule `hr-never-label-any-step-as-manual-without` (`AGENTS.core.md`) now carries a
**probe-receipt precondition** that binds on the *act of writing the label anywhere*:

> For ANY browser/portal/UI step, do NOT write "operator-only / auth-gated / no session" in any
> message, plan, or issue/comment without prior Playwright MCP `browser_navigate` +
> `browser_snapshot` of that exact surface showing the gate; an unprobed auth state IS the
> violation.

This replaces the soft `re-verify a plan's "not feasible" claim at execution time` clause — the
exact phrasing the incident rationalized past. The precondition is checkable: the session
transcript either contains the `browser_navigate`/`browser_snapshot` of the named surface, or
the label is non-compliant.

## Key Insight

**"No persisted session" is itself a claim requiring a probe — not an answer.** Asserting an
unprobed auth state IS the violation, regardless of whether the eventual conclusion turns out
correct. The cheap probe (one navigate + one snapshot) collapses the entire question; skipping
it to save a tool call is the false economy that produced a user-facing retraction + two issue
corrections.

This specializes a recurring pattern family — *a persisted **state** is a claim requiring a
probe, not a fact* — already seen in:
- `2026-06-12-resumability-claim-must-verify-workspace-lifecycle.md` (workspace-lifecycle state)
- `2026-05-29-one-shot-collision-gate-must-probe-merged-prs.md` (merged-PR state under an open issue)

Here the state is **auth/session**, and the probe is a Playwright snapshot.

## Session Errors

1. **Wrote an unprobed auth claim into a user message + #4049 + #5137.** Said the LinkedIn
   portal was "auth-gated — no persisted session to drive headlessly" without invoking
   Playwright. A subsequent probe showed the session was already authenticated. Fix: corrected
   both issues; tightened the rule to require a probe-receipt before any such label.

## Tags

playwright-mcp, operator-steps, automation-claims, linkedin, probe-receipt, auth-state
