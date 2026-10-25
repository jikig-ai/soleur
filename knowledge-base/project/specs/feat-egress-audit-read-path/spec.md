---
feature: egress-audit-read-path
issue: 9545
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-10-25-egress-audit-read-path-brainstorm.md
wireframe: pending (knowledge-base/product/design/settings/egress-audit-log.pen, blocked on Pencil MCP restart)
status: draft
---

# Feature: workspace egress audit log, PR2 (read path and view)

## Problem Statement

PR1 of #9545 (merged) collects per-workspace egress decisions into `workspace_egress_audit_rollup`, dark and with no reader. Workspace members cannot see what their agents' web egress contacted, and the "View egress audit log" affordance on the Scope Grants "Agent web access" card is only a stale TODO.

## Goals

- Any current workspace member can read a 30-day summary of the hosts their workspace's agents contacted and the allow/block outcome.
- The card links to the view and shows a "Last request: X ago" hint.
- Copy is honest: best-effort, lower-bound counts, visible to all current members, no per-person data.
- The legal text that PR1 wrote for a dark pipeline is made true for a live viewer (DPIA t6 re-screen).

## Non-Goals

- Sessions count, "N sessions in 24h" signal (no session id exists; t7 forbids adding one).
- Per-member attribution, timeline or 15-minute bucket view, `bytes_out` display, CSV export.
- Time-range selector and 24h request count on the card (deferred).
- Enabling collection for external workspaces (separate operator-authorized step after PR2 and a 7-day owner notice).
- A new read-side feature flag.

## Functional Requirements

- FR1: Card link "View egress audit log" (both toggle states) to the destination view; "Last request: X ago" hint when records exist.
- FR2: Destination view, member-readable: rows per (host, decision) with "at least N requests" and last seen; allowed/blocked filter; fixed 30-day window; most recent 200 with a truncated notice; `(other)` overflow row.
- FR3: Three distinct empty states (not recording; recording since a date, nothing yet; web access off, history retained until a date), a loading state, and an error state that is never rendered as empty.
- FR4: Required copy (CLO): best-effort and entries may be missing; counts are lower bounds; history visible to every current member including pre-join activity; no member or session is recorded; kept about 30 days; switching off stops new records and deletes nothing; erasure path linked. Forbidden words: complete, every connection, tamper-proof.

## Technical Requirements

- TR1: Migration `164_*` additive: `get_egress_audit_summary(p_workspace_id, p_window, p_limit)` SECURITY DEFINER, `search_path = public, pg_temp`, `statement_timeout 5s`, calls `is_workspace_member(p_workspace_id, auth.uid())` and raises `42501` for non-members; `GRANT EXECUTE` to `authenticated` only, revoked from PUBLIC/anon/service_role; `.down.sql` drops it. No table grant, no SELECT policy; direct SELECT stays a permission error.
- TR2: `GET` route over the RPC; workspace id from `resolveCurrentWorkspaceId`, never request input; `42501` maps to 403; `withUserRateLimit` (about 30/min/user); `Cache-Control: private, no-store`; faults mirrored with `reportSilentFallback` feature `egress-audit-read`, reason codes only.
- TR3: Read not gated on `web_egress` or the collection flag. Verify the PR1 toggle join does not hide history after toggle-off (ruling D).
- TR4: Tests: live-DB two-user cross-tenant test with a service-role positive control; pending invitee and removed member get `42501`; anon/service_role cannot execute; direct table SELECT denied; forged workspace id ignored; stale current workspace pinned to a non-member returns 403; aggregation sums, `truncated`, window edges.
- TR5: Amend the archived PR1 plan and ADR-288 (no member SELECT policy; read path deliberately not flag-gated; `decision` CHECK exists).

## Merge gates (PR2)

- Wireframe committed before implementation (`wg-ui-feature-requires-pen-wireframe`).
- DPIA t6 re-screen as a new section of the DPIA addendum; verify the CNIL Art. 35(4) list wording.
- Document changes with mirrors and SHA re-pin: privacy policy 4.7 and 7, AUP 5.8, DPD 2.3(ag) and the "ahead of" wording at line 239, GDPR policy 3.16 and 8.4, PA-2/PA-8/PA-37; t6 row in `compliance-posture.md`; one line in the `egress-audit-dsar` runbook.
- CPO sign-off plus spec-flow pass at plan time; `user-impact-reviewer` at review.

## Enablement gates (not merge)

Retention approval, team-workspace role decision with an Art. 28 instrument and standalone LIA, Art. 21 sufficiency, owner notice live at least 7 days, operator authorization to flip `egress-audit-collection`.
