---
feature: egress-audit-read-path
issue: 9545
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-10-25-egress-audit-read-path-brainstorm.md
wireframe: knowledge-base/product/design/settings/egress-audit-log.pen (screenshots 07-01..07-21 in knowledge-base/product/design/settings/screenshots/)
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

- FR1: Card link "View egress audit log" (both toggle states) to the destination view; "Last request: X ago" hint when records exist (wireframes 07-01, 07-03, 07-12, 07-13).
- FR2: Destination view, member-readable: rows per (host, decision) with "at least N requests" and last seen; filter All / Allowed / Blocked / Other (DB `denied` is shown as "Blocked"; `other` is a third visible state, never folded); fixed 30-day window; most recent 200 with a truncated notice; overflow rows labelled "Other hosts, not listed individually" with an info tooltip, one per decision, filtered with the rest (wireframes 07-04..07-06, 07-14..07-16).
- FR3: Three distinct empty states (not recording; recording is on, no requests recorded yet; web access off, nothing in the last 30 days), a loading state (the settings `loading.tsx` skeleton), and error states that are never rendered as empty (unavailable; no longer a member; workspace unbound). No retention sentence carries a calendar date ("deleted about 30 days after they were recorded"). A populated view with web access off shows that notice (wireframes 07-05, 07-07..07-11, 07-16..07-21, as amended in plan Phase 5).
- FR5: The enable-dialog replaces "Every outbound request is logged with workspace attribution" with the best-effort recording notice (07-02): hosts recorded as summary counts for about 30 days, visible to every current member including pre-join activity, no member or session recorded, entries may be missing, counts are minimums, turning off stops new records and deletes nothing. The notice renders only when `egress-audit-collection` is on for the workspace's org (plan must confirm how the flag value reaches the component). Needs CLO sign-off together with the privacy-policy mirrors.
- FR4: Required copy (CLO): best-effort and entries may be missing; counts are lower bounds; history visible to every current member including pre-join activity; no member or session is recorded; kept about 30 days; switching off stops new records and deletes nothing; erasure path linked. Forbidden words: complete, every connection, tamper-proof.

## Technical Requirements

- TR1: One additive migration, numbered at the last rebase (164 is claimed by open draft PRs #10901/#10905 and 165-173+ by the codex branch; the plan's Phase 0 command picks max over all `origin/*` refs plus one): `get_egress_audit_summary(p_workspace_id, p_limit, p_decision)` SECURITY DEFINER, `search_path = public, pg_temp`, fixed 30-day window (no window parameter), calls `is_workspace_member(p_workspace_id, auth.uid())` and raises `42501` for non-members; `GRANT EXECUTE` to `authenticated` only, revoked from PUBLIC/anon/authenticated-default/service_role; `.down.sql` drops it. No table grant, no SELECT policy; direct SELECT stays a permission error. **No `statement_timeout` clause** (a function-level setting does not re-arm the running statement, proved on Postgres 17); the bound is the role timeout plus `p_limit` ≤ 500, the PK-led scan, and the caller's abort signal. `p_limit = 0` returns only `last_request_at` (the card hint).
- TR2: No HTTP route (CTO ruling 2026-10-26, reversing the earlier thin-route decision). A server loader `server/egress-audit-read.ts` calls the RPC through the cookie client; the workspace id comes only from the fail-loud `readWorkspaceIdFromDb` (null → "unbound", throw → "unavailable", RPC not called in either case), never from request input; `42501` renders a "no longer have access" state and is not mirrored; other faults are mirrored with `reportSilentFallback` feature `egress-audit-read`, reason codes only. The destination page is server-rendered with the filter as a `?decision=` search param (chips are `NavLink`s).
- TR1a: RPC contract (CTO ruling 2026-10-26): returns `rows` (real hosts only, ordered and limited) plus a separate typed `overflow: [{decision, request_count, last_seen}]`; the literal `(other)` host is excluded from `rows`, the limit and any site count, and the UI owns the label. `p_decision`, when passed, filters `rows` and `overflow` alike. A real host cannot collide with `(other)` (ingest accepts only `^[a-z0-9._:\[\]-]{1,253}$`; the table CHECK admits `(other)` only as that literal). Folded overflow merges with `GREATEST`, not `SUM`, so the overflow count is a very loose lower bound and is never presented as a total.
- TR3: Read not gated on `web_egress` or the collection flag. Verify the PR1 toggle join does not hide history after toggle-off (ruling D).
- TR4: Tests: live-DB two-user cross-tenant test with a service-role positive control; pending invitee and removed member get `42501`; anon/service_role cannot execute; direct table SELECT denied; forged workspace id in the query string ignored by the loader; stale current workspace pinned to a non-member renders the "no longer have access" state (RPC raises `42501`); null/throwing workspace reader renders unbound/unavailable and never calls the RPC; aggregation sums, `truncated`, overflow, `p_limit = 0`, window edges; the CI floor of the egress rls-fuzz step is raised with the new cases.
- TR5: Amend the archived PR1 plan and ADR-288 (no member SELECT policy; read path deliberately not flag-gated; `decision` CHECK exists).

## Merge gates (PR2)

- Wireframe committed before implementation (`wg-ui-feature-requires-pen-wireframe`).
- DPIA t6 re-screen as a new section of the DPIA addendum; verify the CNIL Art. 35(4) list wording.
- Document changes with mirrors and SHA re-pin: privacy policy 4.7 and 7, AUP 5.8, DPD 2.3(ag) and the "ahead of" wording at line 239, GDPR policy 3.16 and 8.4, PA-2/PA-8/PA-37; t6 row in `compliance-posture.md`; one line in the `egress-audit-dsar` runbook.
- CPO sign-off plus spec-flow pass at plan time; `user-impact-reviewer` at review.

## Enablement gates (not merge)

Retention approval, team-workspace role decision with an Art. 28 instrument and standalone LIA, Art. 21 sufficiency, owner notice live at least 7 days, operator authorization to flip `egress-audit-collection`.
