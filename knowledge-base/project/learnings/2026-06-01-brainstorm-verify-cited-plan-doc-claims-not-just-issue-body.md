---
title: "Brainstorm: a cited plan doc is not more authoritative than the code it describes — verify its component/route/HTTP-status claims against main too"
date: 2026-06-01
category: workflow-patterns
module: brainstorm
issue: 4712
tags: [brainstorm, premise-validation, plan-doc-staleness, repo-research]
---

# Learning: verify cited-plan-doc claims against main, not just issue bodies

## Problem

Brainstorming #4712 (KB-sync #4706 follow-ups), the GitHub issue body **and** the cited parent plan
(`knowledge-base/project/plans/2026-05-31-fix-kb-sync-stale-design-folder-frozen-timestamps-plan.md`)
both stated two concrete, load-bearing technical claims that were **false against `main`**:

1. The reconnect UI lives in a component named **`RepoConnectionCard`** — which exists **nowhere in code**
   (`git grep RepoConnectionCard` hits only the plan doc). The real surfaces are `ProjectSetupCard`
   (`components/settings/project-setup-card.tsx`) + `DisconnectRepoDialog`.
2. **`/api/kb/tree` returns 409 on `repo_status='error'`** — it does not. It 404s on `not_connected`,
   503s on `workspace_status!='ready'`; the 409s are in `/api/kb/sync`. The "don't flip to `error`"
   constraint still holds in spirit (degrading the tree is worse), but the stated *mechanism* was stale.

Both claims, if accepted, would have bound the spec to a phantom component and a wrong control-flow
premise. A repo-research agent grepping for the specific symbols caught both before Phase 2.

A third research finding *flipped a framing*: the issue treated the reconnect button as possibly a
dead-end, but `/api/repo/detect-installation` **already exists** as the NULL-install auto-heal path —
making "Reconnect" a genuine one-click fix. The plan doc never mentioned this existing endpoint.

## Solution

In brainstorm Phase 1.1, treat a **cited plan/spec/brainstorm doc the same as an issue body**: a
point-in-time artifact that drifts from code. The brainstorm skill already mandates verifying
*issue-body* component/symbol/PR-state claims against `main`; extend the same grep discipline to
**every concrete code claim in a cited plan doc** — component names, route paths, and HTTP-status
behavior. Grep the specific symbol (component name, route file + the literal status code) before
letting the claim bound the option space. A plan doc authored against live prod data is still not a
more authoritative source than the code it describes — especially for component *names* (easy to
paraphrase/invent) and *exact* HTTP-status behavior (easy to misremember).

## Key Insight

**Authoritativeness of a source is about freshness vs. the code, not about how official the document
looks.** A detailed, recently-written plan doc ("rewritten v3 against live prod data") earns trust on
its *data* claims (DB row values it actually queried) but NOT automatically on its *code-shape* claims
(component names, route status codes) — those are prose the author wrote from memory and can be stale
or invented. Verify code-shape claims by grepping the symbol; reserve trust for the claims the doc
actually measured.

## Session Errors

Session error inventory: none detected (operationally clean — no failed commands, wrong paths, or
permission denials). The two premise corrections above were research findings that *prevented* spec
errors, not session execution errors.

## Tags
category: workflow-patterns
module: brainstorm
