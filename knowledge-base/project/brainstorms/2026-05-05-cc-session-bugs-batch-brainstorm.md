---
title: Command Center session bug batch (4 bugs from a single screenshot)
date: 2026-05-05
status: triaged
issues:
  - 3250
  - 3251
  - 3252
  - 3253
draft_pr: 3249
branch: feat-cc-session-bugs-batch
---

# Command Center session bug batch — 2026-05-05

A single Command Center session surfaced four distinct bugs. This brainstorm triages them into separate GitHub issues, names the user-brand impact threshold, and recommends a fix order.

## What we're shipping

Four discrete fixes, filed as separate issues, bundled under draft PR #3249 only as a coordination point. The issues are scoped to be resolvable independently.

| # | Issue | Priority | Surface |
|---|---|---|---|
| 1 | #3250 — Concierge 400 "model does not support assistant message prefill" | **P1** | `apps/web-platform/server/{cc-dispatcher,soleur-go-runner,agent-runner-query-options}.ts` |
| 2 | #3251 — "Routing to the right Experts" hides Concierge once leaders picked | P2 | Chat surface (component to be located) |
| 3 | #3252 — Read-only OS commands (`ls`, `pwd`, `cwd`) prompt for approval | P2 | `apps/web-platform/server/agent-runner.ts` (canUseTool, autoAllowBashIfSandboxed) |
| 4 | #3253 — Inconsistent "PDF Reader doesn't seem installed" message | P3 | Likely model-emitted, not a real availability check |

## Why this approach

- **Separate issues, not an umbrella.** The four bugs span different layers (API thread construction, React routing UI, server-side permission policy, system-prompt hygiene). Bundling them into one PR would lengthen the cycle for the P1 blocker and conflate review concerns.
- **#3250 first as one-shot.** It is a hard blocker on Concierge — every first-touch user can hit a raw API error. It is also the most narrowly scoped (one suspected root cause: assistant-terminated thread on session resume).
- **#3251, #3252, #3253 batch separately.** They are polish / trust-tier bugs. Once labeled consistently they can drain together via `/soleur:drain-labeled-backlog` after #3250 ships, or be one-shot individually depending on operator capacity.

## User-Brand Impact

**Artifact named:** Soleur Concierge response surface in the Command Center web app (first-touch interactive surface for new users).

**Vector named:** Trust breach on first impression. The most damaging path is #3250 — a raw Anthropic 400 error rendered in the Concierge bubble — which users read as "Soleur is broken." #3251 (hidden Concierge in routing panel) compounds this by obscuring which agent answered. #3252 introduces a sandbox-over-reach risk if the auto-approve allowlist drifts beyond exact-match read-only commands.

**Threshold:** `single-user incident`.

A single user encountering #3250 on first use is a brand-survival event for the Command Center surface. Any plan derived from this brainstorm (especially the #3250 one-shot) inherits this threshold and MUST go through the `user-impact-reviewer` agent at review time per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`.

## Key decisions

| Decision | Rationale |
|---|---|
| File 4 separate issues, no umbrella issue | Each bug is independently scoped and resolvable; bundling would slow the P1 blocker. |
| #3250 → `/soleur:one-shot` first | P1 hard blocker; narrow root-cause hypothesis (session-resume reconstructs assistant-terminated thread). |
| #3252 fix MUST use exact-match command allowlist, not prefix matching | Prefix would allowlist `lsof`, `cdrecord`, `pwdx`. Reject shell metacharacters explicitly. |
| #3253 first action is **investigation**, not a fix | The user-facing string is not in the codebase — likely model-emitted. Confirm before patching. |
| Concierge model swap is NOT in scope for #3250 | Unless a code path intentionally prefills, the right fix is to prevent assistant-terminated threads, not to change models. |
| Brand-survival threshold = `single-user incident` for the #3250 plan | Concierge is the first-touch surface. Any failure mode is brand-visible. |

## Open questions

- **#3250 root cause confirmation:** Is the trailing-assistant message actually coming from the resume path, or from `respondToToolUse` racing with a runaway-timer terminal `workflow_ended`? The fix should ship with a regression test that asserts the failing thread shape, then proves the guard prevents the 400 — so the test design will pin down the trigger.
- **#3251 component location:** First subagent sweep did not find a literal "Routing to the right Experts" component. Either the string is templated (assembled from parts) or lives in a chat-surface component not yet read. The one-shot plan for this issue must locate it before designing the fix.
- **#3252 sandbox status:** Is the CC session actually flagged sandboxed (so `autoAllowBashIfSandboxed: true` should fire)? If yes, why isn't the SDK auto-approving `ls`/`pwd`? If no, the fix lives in how sessions get the sandbox flag, not in the allowlist.
- **#3253 root cause:** Is this a tool-availability detection layer we haven't found, or pure model self-misreport?

## Domain Assessments

**Assessed:** Engineering, Product. (Other domains not relevant to this bug-fix scope: no marketing/sales/legal/finance/operations implications. Skipping their leaders per pragmatism — these are bug fixes, not new capabilities.)

### Engineering (CTO lens, captured implicitly via repo research)

**Summary:** All four bugs are in the Command Center web app server/UI layer. #3250 is the architectural risk — the resume path reconstructs message history without enforcing user-terminated invariants. The right shape is a thread-shape guard at the boundary that emits a Sentry warn when it fires (per `cq-silent-fallback-must-mirror-to-sentry`).

### Product (CPO lens, captured implicitly via user-impact framing)

**Summary:** First-touch Concierge surface is brand-load-bearing. #3250 + #3251 together are a trust-collapse pattern. #3252 has both UX (interruption) and security (sandbox over-reach) framings — the security framing dominates if the fix is wrong.

## Capability Gaps

None identified — all fixes route through existing surfaces and patterns.
