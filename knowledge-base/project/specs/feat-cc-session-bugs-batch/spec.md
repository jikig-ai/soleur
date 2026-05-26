---
title: Command Center session bug batch
date: 2026-05-05
status: triaged
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md
draft_pr: 3249
issues:
  - 3250
  - 3251
  - 3252
  - 3253
---

# Spec — Command Center session bug batch

This is a **bundle spec** — four independent fixes coordinated under one branch and draft PR. Each issue carries its own acceptance criteria; this spec records the cross-cutting framing the four bugs share.

## Problem statement

A single Command Center session surfaced four distinct bugs that together degrade the first-touch experience of Soleur. The most severe (#3250) renders a raw Anthropic 400 error in the Concierge response bubble, which users read as "Soleur is broken."

## Goals

1. Stop the Concierge 400 prefill error on session resume (#3250).
2. Restore Concierge visibility in the routing panel after leaders are picked (#3251).
3. Stop interrupting users for read-only OS commands without widening the sandbox surface (#3252).
4. Resolve the inconsistent "PDF Reader doesn't seem installed" message (#3253).

## Non-goals

- Changing the Concierge default model (out of scope unless investigation in #3250 proves no code path intentionally prefills).
- Reworking the broader CC permission model (#3252 is scoped to a tight read-only allowlist).
- Building a generic capability-discovery layer (#3253 is scoped to PDF specifically; broader work is a separate effort).

## Functional requirements

- **FR1 (#3250):** Concierge replies do not 400 on resume after a tool-use turn. Regression test reproduces the failing thread shape.
- **FR2 (#3251):** Soleur Concierge appears in the "Routing to the right Experts" panel in both the no-leaders-yet AND leaders-resolved states. Visual regression covers both.
- **FR3 (#3252):** `ls`, `pwd`, `cd` (and similar exact-match read-only commands) do not prompt in CC sessions. Anything with shell metacharacters or non-listed commands still prompts.
- **FR4 (#3253):** Root cause confirmed (model-emitted vs. real availability check). PDF reading succeeds consistently across sessions when the file is reachable.

## Technical requirements

- **TR1 (silent-fallback rule):** Any thread-shape guard added in #3250 or allowlist rejection in #3252 MUST emit a Sentry warn via `reportSilentFallback` per `cq-silent-fallback-must-mirror-to-sentry`. Pino-only logging is insufficient.
- **TR2 (user-impact gate):** Plans derived from this brainstorm inherit `Brand-survival threshold: single-user incident`. The `user-impact-reviewer` agent MUST sign off at review time.
- **TR3 (no umbrella issue):** Per AGENTS.md `wg-when-deferring-a-capability-create-a` bundle pattern, each bug stays a separate issue; this spec and the brainstorm doc are the bundle's single source of truth.
- **TR4 (exact-match allowlist for #3252):** No prefix-only matching (`lsof`/`cdrecord`/`pwdx` would slip through). Reject shell metacharacters (`>`, `>>`, `|`, `&&`, `;`, `&`, backticks, `$()`, `..` path traversal).

## Recommended fix order

1. **#3250 first** — `/soleur:one-shot` immediately. P1 blocker.
2. **#3251 + #3252 + #3253** — independent one-shots or a drain pass after #3250 ships. Order within this batch can be optimized for surface co-location (#3251 and #3252 both touch the chat surface server config).

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md`
- Draft PR: #3249
- Issues: #3250 (P1), #3251 (P2), #3252 (P2), #3253 (P3)
