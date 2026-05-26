---
date: 2026-05-12
status: complete
parent_brainstorm: knowledge-base/project/brainstorms/2026-05-11-cc-soleur-go-transcript-hardening-brainstorm.md
issues:
  - "#3603 (hardening umbrella, OPEN — PR-B of 3-PR sequence)"
pull_requests:
  - "#3602 (PR-A1, merged 2026-05-12 07:03 UTC)"
  - "#3648 (PR-A2, merged 2026-05-12 09:41 UTC)"
  - "#3653 (PR-B, this brainstorm's draft PR)"
brand_survival_threshold: high-confidence-correctable
gdpr_gate_required: false
predecessors_landed: true
---

# Brainstorm — PR-B migration cohort marker (W5 only, no rollout banner)

## What We're Building

A **single client-side UX affordance** for the pre-#3286 lopsided-state cohort:

1. **Inline `CohortMissingReplyMarker`** rendered as a sibling component (not a `message-bubble` variant) at the tail of any conversation that matches the row-absence pattern on the client: `messages.length > 0 && messages.every(m => m.role === "user")` after hydration via `api-messages.ts`. Copy: "Some assistant replies from this conversation (started [conversation.created_at | localized]) weren't captured. New replies are saved normally."
2. **"Continue conversation" CTA** embedded in the marker. Renders only when `conversations.session_id IS NOT NULL`. Click resumes the SDK session via the existing send-message pipeline. CTA hidden when `session_id` is null (no resume path).

**Out of scope (this PR):**

- Rollout banner. **Dropped** during brainstorm — Soleur has no external users, direct comms covers the rollout-disclosure role more honestly than a chat-surface banner, and the existing `pwa-install-banner.tsx` has zero consumers so banner mount-point precedent is also missing.
- Server-side cohort detection endpoint. Not needed when the row-absence pattern is computable from the already-hydrated message list.
- Rail-level affordance on `conversations-rail.tsx`. Deferred to PR-D when external-user count > 0 makes rail-level surfacing worth the additional surface.

**Sunset:** Marker code remains until **2026-08-11** (90 days post-PR-B merge), enforced by a hardcoded TypeScript constant co-located with the component. After sunset, the marker render path is dead code on the trunk; removal is a follow-up `chore:` PR.

## Why This Approach

The verification-gated 3-PR sequence framed PR-B as "migration cohort UX." Two assumptions in the original framing were challenged during this brainstorm and updated:

1. **USER_BRAND_CRITICAL → HIGH.** PR-B is read-only SELECT on already-RLS'd rows, no new attack surface, no Art. 33 notifiable surface, no cross-tenant blast radius. CPO refresh: "a botched banner is recoverable in hours; a botched persistence layer is not." Plan inherits `brand_survival_threshold: high-confidence-correctable`. `user-impact-reviewer` remains required at PR review (the load-bearing gate), GDPR-gate skipped per user brief.
2. **Banner dropped entirely.** The umbrella's W5 carried a rollout banner alongside the inline marker. With zero external users at the time of this brainstorm (today, 2026-05-12, hours after PR-A1+A2 merged), the banner's audience is internal/reachable-by-direct-comms — direct outreach is more honest than a chat-surface banner. The inline marker still earns its keep because it provides per-thread context that direct comms cannot (a known user re-opening an affected conversation weeks later needs the visual cue then, not the email they archived in May).

The remaining marker scope is small enough to fit a single client-only component + one regression test on the chat surface. Cohort detection happens in the existing render path; no new endpoint, no new query, no migration.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| DEC1 | Drop rollout banner from PR-B scope | No external users today; direct comms is more honest than a banner; existing PWA banner is orphaned (no precedent for chat-surface banner mount). YAGNI per CLAUDE.md. |
| DEC2 | `brand_survival_threshold = high-confidence-correctable` (not single-user incident) | Read-only SELECT, no Art. 33 surface, no cross-tenant blast radius. Botched copy is hours-correctable. (User confirmed at Phase 1.2.) |
| DEC3 | Marker = new sibling component `CohortMissingReplyMarker.tsx`, NOT a `message-bubble` variant | Keeps cohort logic out of the already-load-bearing `renderAbortedAssistant` render path in `message-bubble.tsx`. Marker is a notice ABOUT a missing message, not a message — different semantic, different component. |
| DEC4 | Cohort detection = client-side filter on hydrated messages | `messages.every(m => m.role === "user")` AND `conversations.created_at BETWEEN '2026-05-05' AND '2026-05-11'`. No new server endpoint. Hydration payload already includes role + created_at. Matches GDPR R1 carryover (row-absence is the signal, not a server-side flag). |
| DEC5 | Marker date token = `conversation.created_at` (localized) | CPO refresh: anchors to a date the user already knows; avoids over-disclosing internal AC11 fix chronology. ux-design-lead's tentative "May 11, 2026" was overruled. |
| DEC6 | "Continue conversation" CTA hidden when `session_id IS NULL` | No resume path is possible without a session. Marker stands alone with copy: "New replies are saved normally" — user can manually start a new turn via the composer (existing behavior). |
| DEC7 | CTA failure mode (SDK 404/410, 5xx, network) = inline error variant + retry button | Toast/modal would tear the user out of conversation context. Inline error preserves position. Retry button re-attempts the same resume; on second failure, fall back to "Start new conversation" affordance. |
| DEC8 | Sunset = hardcoded `COHORT_MARKER_SUNSET = "2026-08-11"` constant, co-located with component | 90 days post-PR-B merge. Bypassable by clock-skew but no security boundary. Cleanup is a follow-up `chore:` PR after the sunset date. |
| DEC9 | NO rail-level affordance on `conversations-rail.tsx` | Deferred-scope-out → file as PR-D when external-user count > 0 warrants the additional surface. Marker-only is sufficient when affected conversations are visited via direct user action. |
| DEC10 | A11y: marker uses semantic `<aside role="note" aria-label="Conversation history note">` | Communicates "system note about this thread" to screen readers; keyboard-reachable CTA inherits standard `<button>` semantics. |
| DEC11 | i18n: English-only | Matches existing chat surface scope. No new i18n infrastructure introduced for a 90-day affordance. |
| DEC12 | Logged-out users: chat-surface short-circuits, no cohort filter run | Existing auth-gated mount path already covers this; no PR-B-specific code needed. |

## Open Questions

1. **PR-A2 W4 `usage` column population in cohort conversations.** PR-A2 wired `usage: { cost_usd }` on complete assistant turns under `CC_PERSIST_USAGE=true`. Cohort conversations have NO assistant rows so `usage` is moot for them. Confirm during plan Phase 1: client filter must NOT use `usage` field presence as a signal — `role === "user"` is the only valid filter axis.
2. **Continue-conversation CTA → SDK 404 detection.** Cleared-stale-session-id logic lives in `cc-dispatcher.ts:963-981` (`clearStaleSessionId`). When the client clicks CTA, the resume flow may hit a 404 from the SDK. The client-visible error needs to be distinguishable from generic network failure so the inline error copy can say "Session expired — start a new conversation" instead of "Network error, try again." Resolve at plan Phase 2.
3. **Marker placement when the cohort conversation has subsequent (post-fix) user+assistant turns.** Per detection rule, if even one assistant row exists, the conversation doesn't match. But a user could re-open a cohort thread, type a new message that DOES persist (post-fix), and now the thread has 1 assistant row → no marker. That's intentional (the thread is healed) but should be confirmed during plan Phase 2 against the spec-flow-analyzer's F1 scenario.
4. **Sunset cleanup PR scheduling.** 2026-08-11 is ~3 months out. `/soleur:schedule` a follow-up automated PR that removes the marker component, or rely on the hardcoded const to render no-op and clean up manually later? Default: rely on the constant; schedule cleanup via `/soleur:schedule` post-PR-B merge.

## User-Brand Impact

- **Artifact:** the in-thread visual context that a cohort conversation is incomplete. Surfaces: chat-surface (`/dashboard/chat/[id]`), specifically inside the message list rendered by `message-bubble.tsx` siblings.
- **Vector:** silent gaslighting — a known user re-opens an affected conversation, sees only their own messages with no assistant replies, and concludes the product is still broken. The marker prevents that misread.
- **Threshold:** `high-confidence-correctable`. Botched marker (wrong copy, wrong date format, wrong placement) is correctable within hours via a copy/style change PR. No data integrity stakes. No Art. 33 notifiable surface (the underlying fix shipped in #3286; this is transparency about it).
- **Failure modes ranked.**
  1. Marker fails to render on affected threads → user concludes product broken → low severity, hours-correctable.
  2. Marker renders on a non-affected thread (false positive) → user sees a confusing note that doesn't apply → low severity, hours-correctable.
  3. Continue-CTA fires resume on a stale session_id → user sees inline error → already handled by DEC7 fallback.
- **Mitigations baked into PR-B.** Single sibling component with one filter condition; regression test asserting marker presence on cohort fixtures and absence on healed/post-fix fixtures; CTA failure path explicitly designed (DEC7) not implicit.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

**Carry-forward from umbrella (`2026-05-11-cc-soleur-go-transcript-hardening-brainstorm.md`):** CTO + CLO assessments persist verbatim. PR-B is read-only UX with no new persistence and no new compliance surface — the umbrella's CTO/CLO framing for W5 still applies and was not contested during this focused refresh.

### Product (CPO — focused refresh)

**Summary:** Recommended threshold drop from CRITICAL → HIGH given PR-B's read-only nature. Overruled the marker `[date]` token choice (rejected AC11 verification date as over-disclosure, chose `conversation.created_at`). Recommended dropping banner suppression heuristic in favor of universal-within-window — and during dialogue this evolved into dropping the banner entirely given Soleur's pre-public state. spec-flow-analyzer's 14 gaps were resolved as fixed decisions DEC1-DEC12 above; G5 rail badge deferred as scope-out for PR-D.

### Engineering (CTO — carry-forward from umbrella, no new findings)

**Summary:** From umbrella: "Migration cohort is narrow (hours-wide window between #3254 and #3286 merges) — no backfill job warranted." PR-B is purely render-path, no new persistence. CTO carry-forward applies without modification.

### Legal (CLO — carry-forward from umbrella, no new findings)

**Summary:** From umbrella: "transparency defect (docs don't acknowledge cc path) remains" for PR-C scope; for PR-B specifically, the inline marker IS the Art. 5(1)(a) transparency remediation at the per-thread level. CLO did not gate PR-B during the umbrella assessment. No new Art. 33 surface introduced by a read-only client-side filter.

## Capability Gaps

None. Verified during Phase 0.5 + Phase 1.1 research:

- **Hydration payload already includes `role` and `created_at`.** `apps/web-platform/server/api-messages.ts:80-95` selects `"id, role, content, leader_id, created_at, status, usage, message_attachments(...)"` and orders by `created_at ascending`. Filter axes for cohort detection are already present.
- **Session-id resume primitive exists.** `cc-dispatcher.ts:929-981` defines `persistSdkSessionId` + `clearStaleSessionId` (#3266) — the resume hook the CTA invokes already exists with stale-session-handling baked in.
- **Aborted-status precedent for similar markers.** `message-bubble.tsx:196-197, 324+` already renders `renderAbortedAssistant` for `status === "aborted"` rows with `usage` snapshot. PR-B's marker is a distinct case (row-absence, not aborted-status) but the visual precedent of "in-thread system note" exists.
- **Dismissible-banner pattern exists but unused.** `apps/web-platform/components/chat/pwa-install-banner.tsx` exposes `dismissed` + `onDismiss` props. Discovered during brainstorm: ZERO consumers (`grep -rln "PwaInstallBanner" apps/web-platform/` returns only the file itself and its test). This is not a capability gap for PR-B (we dropped the banner) but it IS a noted artifact: any future banner PR will land the FIRST chat-surface banner mount and should resolve the PWA-banner-orphan ambiguity at that time.

Evidence (worktree-relative paths):

- `apps/web-platform/server/api-messages.ts:80-95` — hydration payload shape
- `apps/web-platform/components/chat/message-bubble.tsx:114-117, 196-197, 324-349` — assistant-bubble render with status/usage branching
- `apps/web-platform/server/cc-dispatcher.ts:929-981` — session_id persist + clear-stale primitives
- `apps/web-platform/components/chat/pwa-install-banner.tsx` — dismissible-banner pattern (orphaned, zero consumers per `grep -rln`)
- `apps/web-platform/supabase/migrations/001_initial_schema.sql:64-98` — conversations/messages schema + `(conversation_id, created_at)` index
- `apps/web-platform/supabase/migrations/028_conversations_user_id_session_id_unique.sql` — `session_id` is `text NOT NULL` after migration 035; nullable historically (the cohort's `session_id IS NULL` case is real)
