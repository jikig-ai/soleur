---
title: Durable, action-bound approval requests (HITL approval queue, slice 1)
date: 2026-10-27
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-hitl-approval-queue
issue: 4672
folds_in: [10443]
epic: 9601
---

# Durable, action-bound approval requests (HITL approval queue, slice 1)

## What We're Building

An in-product approval primitive for the hosted web app. When an agent wants to do an outward write or use a credential (send an email, push a branch, open a PR, share a KB doc), the workspace Owner sees a card that shows the exact action and its consequence and presses Approve or Deny. The request is stored in the database, so it survives a restart and an absent user: today the gate is an in-memory promise that dies after 5 minutes or on any restart, and leaves no audit trace.

This is epic #9601's next link (CTO ruling 2026-10-27: #4672 follows #4671's delivered slices; #9543 is blocked by it). #4672 is narrowed to this slice and #10443 is folded in as the same deliverable (close one as a duplicate once the plan lands). It is the issue for slice 1: one issue, one PR.

## Existing-Primitive Audit (verified on origin/main 2026-10-27)

| Concept | Primitive | State | Gap |
|---|---|---|---|
| Gate | `server/review-gate.ts` `abortableReviewGate`, `REVIEW_GATE_TIMEOUT_MS` 5 min | In-memory `Map` on the session; lost on restart/abort/disconnect | No durable object; user away >5 min finds nothing |
| Gated tier | `server/tool-tiers.ts`, gated branch of `permission-callback.ts` (~L1342-1365) | Unlisted tools default to gated | No try/catch around the await (Bash lane has one); only trace is `log.info` |
| Card | `components/chat/review-gate-card.tsx`, WS `review_gate` / `review_gate_response` | Question + option buttons | No bound-action block, expiry, resolved/expired states |
| Send record | `action_sends` (mig 051) | WORM, NOT NULL `message_id`/`grant_id`, post-hoc "user clicked Send" | Cannot be extended for a pre-approval request |
| Inbox | `inbox_item` (mig 122/154), `notifyInboxItem`, `notifications.ts` web push | Content-minimised, mutable; mig comment reserves `approval_required` for #4672 | Gate never creates an `action_required` item; `notifyOfflineUser` fires only when the socket send fails |
| Bash must-ask | ADR-284 lane | Approve/Reject card, no cache entry, "adopting" (0 natural asks) | Not measured; out of slice |
| Operator writes | ADR-249 TTY ack, ADR-264 / #9388 | Terminal-only for operators | Different principal; keep both |
| Email body-hash | `email-triage-tools.ts` `approvedBodySha256` | Computed from the same args at handler time | Tautological: binds nothing independent of the gate |

## Key Decisions

Ruled by CTO agent (2026-10-27) unless noted; product answers by CPO agent; legal posture by CLO agent.

1. **New table `approval_request`, linked from `inbox_item`.** Do not widen `action_sends` (WORM, send-shaped) and do not put the payload in `inbox_item` (content-minimised). Columns: workspace, requester, conversation, tool name, canonical action (jsonb), `action_sha256`, status (`pending|approved|rejected|expired|consumed`), `expires_at`, decider, timestamps. Writes only via SECURITY DEFINER RPCs pinned to `search_path = public, pg_temp`; owner-only select under RLS. The `inbox_item.source` CHECK widens to add `approval_required` (the migration comment reserves it for this issue).
2. **Binding and single use.** `action_sha256 = sha256(canonicalJSON({tool_name, workspace_id, conversation_id, normalized input}))` over the full input, never the truncated display preview. `consume_approval(id, hash)` is one atomic conditional UPDATE (`status='approved' AND expires_at>now() AND action_sha256=$hash`) executed in `canUseTool` immediately before `allow()`. A changed input hashes differently and needs a new request.
3. **No server-side execution in slice 1.** If the session died before approval, the approval resolves the row and the agent re-proposes on resume. Executing from a stored payload is a different principal and a larger change.
4. **Approver: workspace Owner only** (CPO; ADR-066 grain, `is_workspace_owner` mig 098). Members can trigger a request and see "waiting for the workspace owner". ADR-284's member-approves precedent is for destroy-class Bash only and is not generalised. Decided by the CPO agent, not the operator.
5. **Expiry.** Short in-session wait (5 min) for a live prompt; durable `expires_at` default 24 h for the away case (CPO suggested, CTO to confirm at plan). At expiry: row to `expired`, deny with a static "did not run, do not retry, ask the user", owner notified.
6. **Slice 1 tools:** `email_send`, `email_reply`, `email_suppress`, `github_push_branch`, `create_pull_request`, `github_trigger_workflow`, `kb_share_create`, `workspace_set_autonomous` (it changes the Bash approval posture). Other gated tools stay on the old path behind the flag; the Bash lane is unchanged. `payment|legal|auth` stay DB-blocked.
7. **#5351 folded in as a precondition.** Always write the `inbox_item` (`action_required`, email fallback already wired as `notify-inbox-action-required`) instead of relying on `notifyOfflineUser`, which misses a stale open tab. Each new Sentry op gets its own static message: `approval-requested`, `gate_unanswered`, `approval-expired`, `approval-decided`, `approval-consume-rejected`.
8. **Never offered:** "Approve all", "remember this", batch digest, file-backed queue, member-role matrix, autopilot gating (#4674), policy editor, Bash or operator-script scope, flag flips. `Approve` is an exact-string match; the new tier never writes to the 60-minute Bash cache.
9. **Consequence text is built server-side from the bound payload, never from model prose** (CPO: highest single-user risk). Push and email bodies are generic and carry no action text (matches the existing content-free offline-gate rule, #8532).
10. **Dark launch.** Flag `approval-queue` (Flagsmith, default off, per cohort). With the flag off the old in-memory path is byte-identical. The migration is additive.
11. **Legal (CLO):** a new Art. 30 entry (or explicit PA-14/PA-16 amendment) is required if the record holds action text; DPD §2.3, GDPR Policy and Privacy Policy move in the same PR. Retention: keep hash + decision in an append-only row, raw action text in an erasable column with a short TTL, an anonymise RPC in `account-delete.ts`, and a `dsar-export-allowlist.ts` entry. No default-on and no bulk approve for brand-critical classes. No public claim of the form "every outward action requires your approval" until measured (G5/FR6). No LLM-generated consequence summary in slice 1 (it would need a new processing entry and could contradict the bound action).
12. **Not claimed as measured:** the ask path stays "adopting" until #9776 and #10111 close; this slice does not depend on them.
13. **Visual design:** 9-screen wireframe `knowledge-base/product/design/approvals/approval-request.pen` (operator-approved 2026-10-27): request card (email, GitHub push), bound-action catalog, card states incl. approved-but-failed and action-changed, non-owner read-only, inbox rows + nav badge, mobile away-user landing, expiry notice, copy deck. The 1-hour reminder push is outside slice 1.
14. **Productize Candidate:** none.

## User-Brand Impact

- **Artifact:** the Command Center approval card and `approval_request` records that gate a founder's outward writes and credential use.
- **Vector:** an agent acts outward on one founder's behalf under a stale, changed, replayed or wrong-principal approval, or the founder's pending approval stalls silently, or the consequence text disagrees with the action.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** New `approval_request` table plus RPCs, hash-bound single-use consume in `canUseTool`, try/catch deny on timeout, inbox `action_required` and web push for the away user, five static-message ops, flagged dark. A real-SDK probe is required: a mocked SDK cannot see permission-chain order.

### Product (CPO)

**Summary:** Owner-only approval; email and GitHub writes first; extend `ReviewGateCard`; 24 h durable expiry; no approve-all; expiry tells owner and agent; wireframe needed for the card, its states, the inbox row, nav badge and non-owner state.

### Legal (CLO)

**Summary:** Verbatim action text breaks the `action_sends`/`inbox_item` minimisation precedent, so add a PA entry and move DPD, GDPR Policy and Privacy Policy together; split erasable text from the append-only decision row; no public claim ahead of a measured control.

## Capability Gaps

- **Durable approval object** — evidence: `review-gate.ts` keeps resolvers in `session.reviewGateResolvers` (a `Map`); `git grep -l approval_request -- apps/web-platform/supabase/migrations` returns nothing.
- **Gate-originated inbox item** — evidence: `inbox_item` producers today are the merge-queue stall cron and the notification path; none are gates.

## Open Questions

- Exact durable TTL (24 h proposed) — CTO to confirm at plan time.
- Whether `action_sends` can carry the consumed-outcome row or a separate audit table is needed (CTO: unverified).
- Whether the SDK treats a throwing `canUseTool` as deny (unverified; the plan adds the try/catch regardless).
- Whether a reconnect replays an unresolved `review_gate` card (unverified).
- (out of scope) Bash lane migration to the new table; #9388 operator-script adapter; #5331 outbound email queue UI; confidence-gated auto-send; #10196 taint downgrade (blocked by this slice).

## Session Errors

- The operator's resume brief treated #4671 as unstarted; it had two merged PRs (#10192, #11075). Corrected by `gh` before routing.
