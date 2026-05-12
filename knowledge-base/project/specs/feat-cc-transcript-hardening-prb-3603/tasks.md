---
date: 2026-05-12
plan: knowledge-base/project/plans/2026-05-12-feat-cc-transcript-hardening-prb-cohort-marker-plan.md
spec: knowledge-base/project/specs/feat-cc-transcript-hardening-prb-3603/spec.md
issue: "#3603"
branch: feat-cc-transcript-hardening-prb-3603
draft_pr: "#3653"
brand_survival_threshold: high-confidence-correctable
requires_cpo_signoff: false
gdpr_gate_required: false
user_impact_reviewer_required: true
---

# Tasks — cc-soleur-go transcript hardening PR-B (cohort marker, text-only)

Derived from the post-review plan. Single-component, three-tests scope: marker is text-only after CTA-drop decision.

## Phase 0 — Setup

- [ ] 0.1 Read `apps/web-platform/components/chat/chat-surface.tsx:570-740`. Verify: (a) `messages.map` mount block at ~574; (b) `<div ref={messagesEndRef} />` at ~733; (c) no virtualization wrapper; (d) `conversation.created_at` accessible at mount scope; (e) identify the actual `isStreamingAssistant`-equivalent state slice name.

## Phase 1 — Component implementation (single commit)

### 1.1 Tests T-marker (RED — write first)

File: `apps/web-platform/test/cohort-missing-reply-marker.test.tsx`. Synthesized fixtures only. Sibling pattern: `apps/web-platform/test/abort-marker.test.tsx`.

- [ ] 1.1.1 `test("AC1 — renders marker on cohort fixture with locale-formatted created_at", ...)`. Fixture: `createdAt: "2026-05-08T10:00:00Z"`, two user-only text messages. Assert marker visible; rendered text contains "started" + locale-formatted date.
- [ ] 1.1.2 `test.each([healed, postFix, preWindow, streaming, postSunset])("AC2-AC6 — hides marker when {label}", ({ fixture, expectHidden }) => { ... })`. Parametrized table:
  - healed: cohort fixture + 1 assistant text message appended
  - postFix: `createdAt: "2026-05-12T00:00:00Z"` (exclusive upper bound)
  - preWindow: `createdAt: "2026-05-04T23:59:00Z"`
  - streaming: cohort fixture + `isStreamingAssistant: true`
  - postSunset: `vi.useFakeTimers()` + `vi.setSystemTime("2026-08-11T00:00:01Z")` + cohort fixture
- [ ] 1.1.3 `test("AC7 — hides marker when createdAt is malformed", ...)`. `createdAt: "not-a-date"` → marker absent.
- [ ] 1.1.4 `test("AC8 — semantic role and aria-label", ...)`. `screen.getByRole("note", { name: /conversation history note/i })` returns the marker root.

Assert all FAIL with "component not found" before 1.2.

### 1.2 Component (GREEN)

File: `apps/web-platform/components/chat/cohort-missing-reply-marker.tsx`.

- [ ] 1.2.1 Module-level constants via `new Date(...).getTime()` (NaN surfaces at test-run, not prod):
  - `COHORT_WINDOW_START = new Date("2026-05-05T00:00:00Z").getTime()`
  - `COHORT_WINDOW_END = new Date("2026-05-12T00:00:00Z").getTime()`
  - `COHORT_MARKER_SUNSET = new Date("2026-08-11T00:00:00Z").getTime()`
  - One-line comment: `// Sunset 90 days after PR-B merge — component returns null after this date; lazy-delete on next file touch.`
- [ ] 1.2.2 Export `CohortMissingReplyMarker({ createdAt }: { createdAt: string })`. Single prop.
- [ ] 1.2.3 Early return `null` when `Date.now() >= COHORT_MARKER_SUNSET` OR `Number.isNaN(Date.parse(createdAt))`.
- [ ] 1.2.4 Inline date formatting: `const formattedDate = new Intl.DateTimeFormat(undefined, { year: "numeric", month: "long", day: "numeric" }).format(new Date(createdAt));`. No `useMemo`.
- [ ] 1.2.5 JSX (text-only, no button):
  ```tsx
  <aside
    role="note"
    aria-label="Conversation history note"
    className="my-6 flex flex-col items-center gap-2 px-4 text-center text-sm text-soleur-text-secondary"
  >
    <p>Some assistant replies from this conversation (started {formattedDate}) weren't captured.</p>
    <p>New replies are saved normally.</p>
  </aside>
  ```
- [ ] 1.2.6 Re-run T-marker tests: assert GREEN.

### 1.3 Mount in chat-surface

- [ ] 1.3.1 Import `COHORT_WINDOW_START`, `COHORT_WINDOW_END`, `CohortMissingReplyMarker` from the new module into `chat-surface.tsx`. No separate constants module.
- [ ] 1.3.2 Inline the predicate at the JSX mount site (no `useMemo`):
  ```tsx
  {(() => {
    const textMessages = messages.filter((m) => m.type === "text");
    const startMs = Date.parse(conversation.created_at);
    const show =
      textMessages.length > 0 &&
      textMessages.every((m) => m.role === "user") &&
      startMs >= COHORT_WINDOW_START &&
      startMs < COHORT_WINDOW_END &&
      !isStreamingAssistant;
    return show ? <CohortMissingReplyMarker createdAt={conversation.created_at} /> : null;
  })()}
  ```
- [ ] 1.3.3 Mount **immediately before** `<div ref={messagesEndRef} />` at ~line 733. Verify the visual placement in dev.
- [ ] 1.3.4 Replace `isStreamingAssistant` placeholder with the actual slice name identified in 0.1. If the actual slice is `status === "streaming"` or `workflowEnded === false`, use that.
- [ ] 1.3.5 Confirm `conversation.created_at` (or whatever the hydrated field is) is accessible. Adapt prop name if hydration spelling is `createdAt`.

### 1.4 Spec amendment + commit

- [ ] 1.4.1 Add a "Plan-Time Amendments (2026-05-12)" note at the top of `knowledge-base/project/specs/feat-cc-transcript-hardening-prb-3603/spec.md`. NO strike-through, NO FR rewrite. One line pointing to the plan.
- [ ] 1.4.2 Run full suite: `bunx vitest run apps/web-platform/test/`. Green.
- [ ] 1.4.3 `bun tsc --noEmit` clean.
- [ ] 1.4.4 `bun lint` clean on edited files.
- [ ] 1.4.5 Commit: `feat(chat): add CohortMissingReplyMarker (text-only) for cohort transparency — #3603`.

## Phase 2 — Pre-merge gates

- [ ] 2.1 Push branch; `gh pr ready 3653`.
- [ ] 2.2 `/soleur:review` 5-agent parallel pass (`user-impact-reviewer` mandatory per brand_survival_threshold).
- [ ] 2.3 Fix-inline P1 findings.
- [ ] 2.4 `/soleur:qa` skipped (UX-only, no DB writes).
- [ ] 2.5 `/soleur:preflight` ship Phase 5.5: confirm plan's `## User-Brand Impact` section present; no sensitive-path regex matches.
- [ ] 2.6 `gh pr checks` green.
- [ ] 2.7 `gh pr merge --squash --auto`.

## Phase 3 — Post-merge

- [ ] 3.1 `/soleur:postmerge` deployment + Sentry health for chat-surface render path.
- [ ] 3.2 AC11 manual verification: open one cohort-matching conversation on prod (if any exists). Confirm marker renders with the operator's browser locale. If no affected conversation exists in any operator account, mark N/A and document.
- [ ] 3.3 `/soleur:compound` — capture the Q1 resolution + CTA-drop pattern.
- [ ] 3.4 Verify deferred-scope-out issues #3659 (banner) and #3660 (rail) remain OPEN with appropriate context.

## Deferred (carry-forward — track separately)

- **#3659** — Rollout banner. Dropped in brainstorm DEC1; revisit when external user count > 0.
- **#3660** — Rail-level cohort indicator on `conversations-rail.tsx`. Deferred to PR-D.
- **D-spec-cleanup** — Future cleanup PR (post-2026-08-11) deletes `cohort-missing-reply-marker.tsx` and its mount + tests + spec. Lazy-delete: no scheduled PR; handle next time someone touches `chat-surface.tsx`.

## Acceptance Criteria

See plan §Acceptance Criteria. AC1-AC10 pre-merge; AC11 post-merge manual.
