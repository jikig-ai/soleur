---
date: 2026-05-12
issue: "#3603"
parent_brainstorm: knowledge-base/project/brainstorms/2026-05-12-cc-soleur-go-prb-cohort-marker-brainstorm.md
umbrella_brainstorm: knowledge-base/project/brainstorms/2026-05-11-cc-soleur-go-transcript-hardening-brainstorm.md
pull_requests:
  - "#3602 (PR-A1, merged 2026-05-12 07:03 UTC)"
  - "#3648 (PR-A2, merged 2026-05-12 09:41 UTC)"
  - "#3653 (PR-B, draft)"
branch: feat-cc-transcript-hardening-prb-3603
brand_survival_threshold: high-confidence-correctable
requires_cpo_signoff: false
gdpr_gate_required: false
user_impact_reviewer_required: true
---

# Spec — cc-soleur-go transcript hardening PR-B (cohort marker)

## Problem Statement

Between PR #3286's merge (2026-05-05) and the AC11 verification date (2026-05-11), the cc-soleur-go path persisted user messages but did NOT reliably persist assistant turns. The fix in #3286 (verified on 2026-05-11) closed the asymmetry going forward, but conversations created during the ~6-day window now render lopsidedly when the affected user re-opens them: user bubbles present, assistant bubbles absent. Without an explicit in-thread acknowledgement, an affected user concludes the product is still broken — a silent gaslighting failure mode that erodes trust even though the underlying bug is fixed.

PR-B is the per-thread transparency remediation. Its job is to make the missing-reply state legible to the user inside the affected conversation, and to offer a one-click resume path when the SDK session is still recoverable.

## Goals

- **G1.** Render an inline `CohortMissingReplyMarker` at the tail of any chat conversation that matches the row-absence cohort pattern, with copy that anchors to the conversation's own `created_at`.
- **G2.** Offer a "Continue conversation" CTA inside the marker that resumes the SDK session via the existing send-message pipeline when `conversations.session_id IS NOT NULL`.
- **G3.** Handle CTA failure modes (`session_id IS NULL`, stale session 404, network 5xx) inline without tearing the user out of conversation context.
- **G4.** Sunset the affordance automatically after 2026-08-11 (90 days post-PR-B merge) via a hardcoded TypeScript constant, with no scheduled migration or DB cleanup.
- **G5.** Pass the `user-impact-reviewer` agent at PR review (load-bearing gate per `brand_survival_threshold: high-confidence-correctable`).

## Non-Goals

- **NG1.** Rollout banner on the chat surface. Dropped in brainstorm DEC1. Direct comms covers the rollout-disclosure role for the pre-public cohort; banner is YAGNI.
- **NG2.** Server-side cohort detection endpoint. Cohort signal is computable from the already-hydrated message list — no new endpoint or query.
- **NG3.** Rail-level affordance on `conversations-rail.tsx`. Deferred-scope-out to PR-D when external-user growth justifies the surface.
- **NG4.** New database migration. PR-B is render-path only.
- **NG5.** i18n. English-only matches the existing chat surface.
- **NG6.** Cross-tab dismissal sync. Reload re-evaluates the cohort condition; cross-tab broadcast not needed.
- **NG7.** GDPR-gate invocation. Read-only client-side filter on already-RLS'd rows; no new compliance surface.

## Functional Requirements

- **FR1.** Add `apps/web-platform/components/chat/cohort-missing-reply-marker.tsx` exporting `CohortMissingReplyMarker` with props `{ conversationCreatedAt: string; sessionId: string | null; onContinue?: () => void; }`. Render conditions and copy match brainstorm DEC3 / DEC5 / DEC6.
- **FR2.** Mount `<CohortMissingReplyMarker/>` from the message-list render path in `chat-surface.tsx` (or its message-list child) when ALL of the following hold:
  - `messages.length > 0`
  - `messages.every(m => m.role === "user")`
  - `conversation.created_at >= "2026-05-05T00:00:00Z"` AND `conversation.created_at < "2026-05-12T00:00:00Z"` (cohort window, inclusive of 2026-05-11 in UTC)
  - `Date.now() < COHORT_MARKER_SUNSET` where `COHORT_MARKER_SUNSET = Date.parse("2026-08-11T00:00:00Z")`
- **FR3.** Marker copy: `Some assistant replies from this conversation (started {formattedDate}) weren't captured. New replies are saved normally.` where `formattedDate` uses the user's browser locale (`new Intl.DateTimeFormat(undefined, { year: "numeric", month: "long", day: "numeric" }).format(...)`).
- **FR4.** When `sessionId !== null`, render a `<button>` labelled `Continue conversation` that invokes `onContinue`. When `sessionId === null`, do NOT render the button (marker stands alone).
- **FR5.** `onContinue` triggers the existing resume-send path in `chat-surface.tsx` (i.e., posts a no-op resume turn through the same WebSocket / send-message pipeline that a normal user-typed turn uses). On success, the marker's render condition flips false on the next hydration (one new assistant row → cohort filter no longer matches) and the marker unmounts naturally.
- **FR6.** CTA failure handling:
  - Stale session_id (cc-dispatcher returns 404/410 OR `clearStaleSessionId` fires): replace marker body with inline error "This session can't be resumed. Start a new conversation in the composer below." No button retry on this error.
  - 5xx / network failure: replace marker body with inline error "Couldn't resume — try again." + a retry button that re-invokes `onContinue`. After a second failure, fall back to the stale-session copy.
- **FR7.** Marker uses semantic `<aside role="note" aria-label="Conversation history note">` wrapping copy + CTA. CTA inherits standard `<button>` keyboard semantics.

## Technical Requirements

- **TR1.** No new server endpoint, no migration, no new RLS rule. Cohort detection uses only the hydration payload returned by `api-messages.ts` (lines 80-95: `select "id, role, content, leader_id, created_at, status, usage, ..."`).
- **TR2.** Detection runs in the chat-surface render path (memoized on `messages` and `conversation.created_at`). No effect / network call introduced. O(messages.length) for the `.every()` check; cohort is bounded so worst-case is dozens of messages.
- **TR3.** `COHORT_MARKER_SUNSET` is a module-level `const` in `cohort-missing-reply-marker.tsx`. After 2026-08-11, the component returns `null` regardless of cohort match. Cleanup PR removes the file entirely; until then the file is dead-render on the trunk.
- **TR4.** "Continue conversation" CTA reuses the existing send-message pipeline — does NOT bypass authentication, RLS, or rate-limiting that already gate normal turns. Resume is functionally identical to a user-typed turn (with empty content or a system-generated prompt; resolve in plan Phase 2).
- **TR5.** Regression test in `apps/web-platform/test/cohort-missing-reply-marker.test.tsx` covering:
  - Renders marker when cohort filter matches AND sunset not reached
  - Hides marker when `messages` contains any `role === "assistant"` row
  - Hides marker when `conversation.created_at` is outside the cohort window
  - Hides marker when `Date.now() >= COHORT_MARKER_SUNSET`
  - CTA hidden when `sessionId === null`
  - CTA visible + invokable when `sessionId !== null`
  - Inline error copy on stale-session and 5xx failure paths
- **TR6.** No new test fixture data persisted to the database. Test fixtures synthesized per `cq-test-fixtures-synthesized-only`.
- **TR7.** Typecheck + lint clean. No new ESLint suppressions.
- **TR8.** A11y assertion in the new test: `aside` has `role="note"` and `aria-label`; CTA button reachable via Tab.

## Acceptance Criteria

- **AC1.** Marker renders on a synthesized cohort conversation (user-message-only, `created_at` 2026-05-08, `session_id` set) and includes a clickable "Continue conversation" button.
- **AC2.** Marker hides on a healed conversation (same row, plus one synthesized assistant turn appended).
- **AC3.** Marker hides on a post-fix conversation (`created_at` 2026-05-13, user-message-only — outside cohort window).
- **AC4.** Marker hides when test clock advances past `COHORT_MARKER_SUNSET` (2026-08-11 UTC).
- **AC5.** CTA hidden when `session_id` is null; marker copy still rendered.
- **AC6.** Clicking CTA invokes `onContinue` exactly once; subsequent clicks while in-flight no-op (debounce).
- **AC7.** Inline error path: stale-session response → marker body replaced with "Start a new conversation" copy; no retry button.
- **AC8.** Inline error path: 5xx → marker body replaced with "try again" copy + retry button; second failure transitions to stale-session copy.
- **AC9.** A11y: `aside` exposes `role="note"` and the CTA receives focus on Tab from the prior interactive element.
- **AC10.** `user-impact-reviewer` agent passes at PR review (the load-bearing gate per `brand_survival_threshold: high-confidence-correctable`).
- **AC11.** Manual verification on prod after merge: open a known affected cohort conversation in the operator's account (if one exists; otherwise synthesize via dev) and confirm marker + CTA render correctly. If no affected conversation exists in any operator account, mark AC11 N/A and document the cohort population.

## Files in Scope

**New:**

- `apps/web-platform/components/chat/cohort-missing-reply-marker.tsx`
- `apps/web-platform/test/cohort-missing-reply-marker.test.tsx`

**Modified:**

- `apps/web-platform/components/chat/chat-surface.tsx` — mount the marker in the message-list render path (filter + memo wiring)

**Read-only context (no expected change):**

- `apps/web-platform/server/api-messages.ts` — hydration payload already supplies `role` + `created_at`
- `apps/web-platform/server/cc-dispatcher.ts` — session_id resume + stale-clear primitives already exist
- `apps/web-platform/components/chat/message-bubble.tsx` — aborted-assistant render path untouched

## Deferred / Scope-out

- **D-PR-B-banner** — Rollout banner on chat surface. Dropped in brainstorm DEC1; revisit when external-user count > 0 makes a banner audience plausible. Label: `deferred-scope-out`.
- **D-PR-B-rail** — Rail-level affordance on `conversations-rail.tsx` (badge or dot on affected rows). Deferred to PR-D. Label: `deferred-scope-out`.
- **D-PR-B-i18n** — Marker copy localization. English-only matches existing chat surface. Revisit when i18n is introduced globally.
- **D-PR-B-cleanup** — Component removal PR after 2026-08-11 sunset. Schedule via `/soleur:schedule` post-PR-B merge.

## Open Questions for Plan Phase 2

See brainstorm `## Open Questions` 1-4. Two are load-bearing for FR4-FR6:

1. **Resume-send payload shape.** Does the "Continue conversation" CTA post an empty user turn, a system-generated prompt, or invoke a dedicated resume RPC? Existing send-message pipeline assumes user-typed content. Plan must resolve.
2. **Distinguishable stale-session error.** `cc-dispatcher.ts:963-981` `clearStaleSessionId` runs server-side; the client-visible error needs a distinguishable code so FR6's two branches (stale-session vs network) can route correctly. Plan must specify the error contract.
