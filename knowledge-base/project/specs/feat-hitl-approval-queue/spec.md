---
title: Durable, action-bound approval requests (slice 1)
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-hitl-approval-queue
issue: 4672
folds_in: [10443]
epic: 9601
pr: 11289
brainstorm: knowledge-base/project/brainstorms/2026-10-27-hitl-approval-queue-brainstorm.md
---

# Spec: Durable, action-bound approval requests (slice 1)

## Problem Statement

Gated agent actions wait on an in-memory promise (5 minute timeout, lost on restart) with no audit row, no binding between what the user saw and what runs, and no way to reach an absent user. The email body-hash binding is computed from the same arguments at handler time, so it binds nothing.

## Goals

- G1: A persisted approval request the Owner can answer later, in the product, with a button.
- G2: Approval bound to the exact action, single use, expiring, with an audit trail.
- G3: An unanswered request is observable and reaches the away Owner.
- G4: Unblock #10196 and the credential broker (#9543) with a gate that is a boundary.

## Non-Goals

- "Approve all", remember-this, batch digest, file-backed queue, member-role matrix, policy editor.
- Bash must-ask lane migration (ADR-284), operator-script writes (#9388), outbound email queue UI (#5331), autopilot gating (#4674), flag flips.
- Server-side execution of an approved payload after the session died.
- LLM-written consequence text.

## Functional Requirements

- FR1: Slice 1 tools (`email_send`, `email_reply`, `email_suppress`, `github_push_branch`, `create_pull_request`, `github_trigger_workflow`, `kb_share_create`, `workspace_set_autonomous`) create an `approval_request` row before the agent waits.
- FR2: The Owner sees a card with the exact bound action, a server-built consequence line, an expiry countdown, and Approve and Deny only. Wireframes (9 screens, operator-approved 2026-10-27): `knowledge-base/product/design/approvals/approval-request.pen`, exports in `knowledge-base/product/design/approvals/screenshots/`. The 1-hour reminder push shown in the copy deck is outside slice 1.
- FR3: A non-owner member who triggers a request sees a read-only "waiting for the workspace owner" state.
- FR4: Approval is single use and bound to `action_sha256`; a changed input needs a new request and the card says so.
- FR5: Expiry (default 24 h) denies with a static "did not run, do not retry" message, notifies the Owner, and records `expired`.
- FR6: Every request creates an `inbox_item` (`approval_required`, `action_required`) and a web push with generic text; no action content in push or email.
- FR7: A deny returns a static "do not retry or respell" message; repeated re-proposal of the same hash is counted and surfaced.

## Technical Requirements

- TR1: Migration adds `approval_request` and RPCs (`create`, `decide`, `consume`, `expire`), SECURITY DEFINER with `search_path = public, pg_temp`, owner-only RLS select, status transitions RPC-only; widen the `inbox_item.source` CHECK; ship a verify script.
- TR2: `consume_approval(id, hash)` is one atomic conditional UPDATE run in `canUseTool` immediately before `allow()`; the gated await gets a try/catch that denies on timeout or abort.
- TR3: Five Sentry ops, each with its own static message: `approval-requested`, `gate_unanswered`, `approval-expired`, `approval-decided`, `approval-consume-rejected`.
- TR4: Flagsmith flag `approval-queue`, default off; flag off keeps the old path byte-identical.
- TR5: Legal in the same PR: Art. 30 entry or PA-14/PA-16 amendment, DPD §2.3, GDPR Policy, Privacy Policy; erasable action-text column with TTL, anonymise RPC in `account-delete.ts`, `dsar-export-allowlist.ts` entry.
- TR6: Tests: a real-SDK probe that `canUseTool` runs for each slice-1 tool, plus a mutation battery killing: hash omitted from consume predicate, missing expiry check, non-single-use consume, missing owner check, "Approve all" accepted, timeout returning allow or throwing, preview built from different data than the hash, a tool dropped from the map.
- TR7: ADR via `soleur:architecture` ("Durable, action-bound approval requests"). Plan carries the single-user-incident section; `user-impact-reviewer` and `gdpr-gate` run.
- TR8: No public security claim ahead of the measured control (G5/FR6 of the epic spec).
