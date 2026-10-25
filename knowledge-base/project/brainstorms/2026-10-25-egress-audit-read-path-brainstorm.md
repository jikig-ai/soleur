# Brainstorm: workspace egress audit log, PR2 (read path and "View egress audit log" view)

Date: 2026-10-25. Issue #9545 (stays open until PR2 merges). Branch `feat-egress-audit-read-path`, draft PR #11115.

## What We're Building

The read side of the workspace egress audit log. PR1 (merged 2026-10-15) shipped the dark ingest pipeline: migration 162 `workspace_egress_audit_rollup` (15-minute per-workspace buckets, 30-day retention, RLS on, no member read), flag `egress-audit-collection` default off for external workspaces, ADR-288 (adopting).

PR2 delivers:

- A read RPC `get_egress_audit_summary` that any current workspace member can call, and a thin `GET` route over it.
- A "View egress audit log" link on the Scope Grants "Agent web access" card, wired to a destination view (the link is currently only a stale TODO in `scope-grants/page.tsx` and `web-egress-toggle.tsx`).
- The destination view: a host list per (host, decision) with an allowed/blocked filter, "at least N requests", last seen, a fixed 30-day window, a truncated notice, three distinct empty states, an error state that is never rendered as empty, and a "Last request: X ago" hint on the card.
- The DPIA t6 re-screen, and the public-document changes the viewer makes true (privacy policy, AUP, DPD, GDPR policy, Art. 30 rows).

## Why This Approach

Product scope was minimal by operator choice (2026-10-25): host list and decision filter only, fixed 30-day window. The "N sessions used web access in 24h" signal named in the issue is dropped: the data has no session id (DPIA trigger t7 forbids adding one), so it cannot be claimed honestly. `bytes_out` is not displayed (best-effort, reads as exfiltration). No per-member attribution, timeline, or export.

## Key Decisions

| Decision | Ruling | Source |
|---|---|---|
| Who can read | Every current workspace member (`is_workspace_member`, which excludes pending and removed). Not gated on `web_egress` or the collection flag, so history stays readable after a toggle-off | CLO, CPO, CTO agree; ruling D |
| Read path | SECURITY DEFINER RPC through the tenant client; **no member SELECT policy and no table grant**; RPC raises `42501` for non-members (route maps to 403). Direct `.from(table).select()` stays a permission error | Ruled by CTO agent |
| Shape | Group by (requested_host, decision) over a window; RPC takes a window enum, v1 UI fixes 30 days; limit 200 (clamp 500), `truncated` flag, `(other)` overflow row, `statement_timeout 5s` | Ruled by CTO agent; window scope by operator |
| Honest claims | "at least N requests", "N sites contacted plus unlisted overflow", "N blocked", last activity; never "complete", "every connection", "tamper-proof", never sessions | CTO, CPO, CLO |
| Copy | Hosts and outcome are best-effort and entries may be missing (flood cap, `drop_newest`); history visible to all current members including pre-join activity; no member/session recorded; about 30 days then deleted, separate operator copy exists; toggle-off stops new records but deletes nothing; erasure path linked | CLO, CPO |
| DSAR | The view does not satisfy an Art. 15 request; `egress-audit-dsar` runbook stays the path (add a line). No CSV export | CLO |
| Flag | No new read-side flag; data is already gated by per-org collection (off for externals until after PR2 plus a 7-day owner notice) | Ruled by CTO agent |
| Migration | `164_*` additive (function plus REVOKE/GRANT), `.down.sql` drops the function (163 is taken) | Ruled by CTO agent |
| Rate limit and observability | `withUserRateLimit` (about 30/min/user), `Cache-Control: private, no-store`, `reportSilentFallback` feature `egress-audit-read` with reason codes only | Ruled by CTO agent |
| Visual design | New wireframe for the destination view and the card in both toggle states, committed before implementation | `wg-ui-feature-requires-pen-wireframe`; ux-design-lead running |

Inherited rulings kept: A (collection off for externals until PR2 plus owner notice at least 7 days), B (notice, not re-confirmation), D (toggle off is not a purge).

## Corrections to the archived PR1 plan and ADR-288

- Plan lines for "member SELECT policy" (PR2 checklist, and the "zero rows once the member policy exists" test) are superseded: direct SELECT stays denied and the RPC is the only read path. ADR-288 lines saying a policy lands in PR2 need the same amendment; ADR-288 should also say the read path is deliberately not flag-gated.
- The plan says there is no CHECK on `decision`; migration 162 has `CHECK IN ('allowed','denied','other')`.
- Migration 162 `REVOKE ALL` stays as is (no grant needed under the RPC design).
- Verify the PR1 toggle join (drops rows when web access is off) against ruling D: history must stay visible after toggle-off.

## User-Brand Impact

- **Artifact:** the member-facing egress audit view and `get_egress_audit_summary` RPC.
- **Vector:** a leak across workspaces, or to a pending or removed member, would reveal which external hosts one workspace's agents contacted, which can disclose what a founder asked an agent to research; a surveillance-style framing would harm trust.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

Ship a small read-only, workspace-level "what agents reached" view; defer anything that counts or watches people. Three distinct empty states. Members whose agents are logged are not notified by the owner-only notice, so disclose in the view. Needs spec-flow plus wireframe before work.

### Engineering (CTO)

RPC-only read path (rulings above). Verify `resolveCurrentWorkspaceId` re-validates membership, and add a stale-current-workspace test expecting 403. Two-user cross-tenant live-DB test with a service-role positive control.

### Legal (CLO)

Members may read; t6 re-screen concludes "no full DPIA, conditional" (nine fields, no per-person field, 30 days, t7 tripwire). Verifying the CNIL Art. 35(4) list wording is a merge gate for the re-screen. Merge gates: re-screen as a new DPIA addendum section, document changes with mirrors and SHA re-pin, view and toggle copy. Enablement gates (not merge): retention approval, team-workspace role decision with an Art. 28 instrument and standalone LIA, Art. 21 sufficiency, owner notice live 7 days, operator authorization to flip the flag.

## Open Questions

- Does any member have a per-user private agent session? If so, one member's hosts become visible to another and the t6 re-screen must weigh it (CLO, confirm with CPO).
- The owner notice (ruling B) goes to owners only; whether non-owner members need a notice or the in-view disclosure suffices (CLO).
- Real customer volume is still unmeasured (zero real-workspace rows); it cannot be measured before collection is enabled, so PR2 does not wait on it. Sizing stays on the CTO's assumption (about 80k rows/day at 1,000 workspaces) and the RPC is bounded by limit and `statement_timeout`.
- Time-range selector and 24h request count on the card: deferred (out of scope for v1).
- Per-member attribution and CSV export: excluded by design (out of scope).

## Capability Gaps

None. Evidence: repo research found no existing "View egress audit log" link (only two stale TODO comments), no read-side flag, and migration 162 with no member policy.
