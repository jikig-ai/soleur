---
date: 2026-05-12
spec: knowledge-base/project/specs/feat-cc-transcript-hardening-prb-3603/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-12-cc-soleur-go-prb-cohort-marker-brainstorm.md
umbrella_brainstorm: knowledge-base/project/brainstorms/2026-05-11-cc-soleur-go-transcript-hardening-brainstorm.md
issue: "#3603"
branch: feat-cc-transcript-hardening-prb-3603
draft_pr: "#3653"
predecessors:
  - "#3602 (PR-A1, merged 2026-05-12 07:03 UTC)"
  - "#3648 (PR-A2, merged 2026-05-12 09:41 UTC)"
brand_survival_threshold: high-confidence-correctable
requires_cpo_signoff: false
gdpr_gate_required: false
user_impact_reviewer_required: true
---

# Plan — cc-soleur-go transcript hardening PR-B (cohort marker, text-only)

## Overview

A single text-only React component (`CohortMissingReplyMarker.tsx`) rendered inside chat conversations that match the row-absence cohort pattern. No CTA, no banner, no new server endpoint, no migration. Marker copy anchors to the conversation's own `created_at` (localized) and tells the user that new replies save normally. The composer already visible at the bottom of the chat surface is the action affordance; the marker is the label.

Plan-review (DHH + Kieran + code-simplicity) converged on dropping the CTA entirely — confirmed by the operator. The marker's earned position remains: a user re-opening an affected conversation weeks later needs per-thread context the umbrella brainstorm's direct comms cannot provide.

**Brand-survival threshold.** `high-confidence-correctable` (carry-forward from spec frontmatter). `user-impact-reviewer` required at PR review. GDPR-gate skipped.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| FR4-FR7 specify a "Continue conversation" CTA with onContinue, focus-and-scroll wiring, and stale-session/5xx inline error variants | The composer (`chat-input.tsx` mounted in `chat-surface.tsx`) is always visible below the message list. A CTA that scrolls 200px and focuses it duplicates the existing affordance. Failure modes (stale session, 5xx) are server-side concerns the existing chat-surface error banner (`chat-surface.tsx:541`) already covers. | **Drop CTA entirely.** Component is `<aside>` + two sentences of copy. FR4-FR7 superseded by this plan; AC6-AC9 collapsed to one a11y AC. Spec stays as historical record with a one-line "Plan-Time Amendments" note pointing here. |
| FR2: marker shows when `messages.every(role === "user")` | `messages` from chat-surface is a union of message types (text, review_gate, interactive_prompt). Non-text types carry no `role: "user"` so a naive `every` would false-negative on threads with system-side prompts mixed in. Also: streaming bubbles render from in-memory state, not from `messages`. | **Refine FR2 predicate** to `textMessages = messages.filter(m => m.type === "text"); textMessages.length > 0 && textMessages.every(m => m.role === "user") && !isStreamingAssistant`. Where `isStreamingAssistant` is the existing chat-surface state slice. |
| DEC6: CTA hidden when `session_id IS NULL` | Vestigial — no CTA. | Delete DEC6 implication. Component takes one prop only: `createdAt: string`. |
| Mount: "after `messages.map`" | Verified at `chat-surface.tsx:574-606`: plain `messages.map` inside `<div className="min-w-0 space-y-4 ...">`. Not virtualized. Canonical "end of message stream" anchor is `<div ref={messagesEndRef} />` at ~line 733. | **Mount anchor** precise: `{isCohortMissingReply && <CohortMissingReplyMarker createdAt={conversation.created_at} />}` immediately BEFORE `<div ref={messagesEndRef} />`. |

## User-Brand Impact

Carry-forward from brainstorm:

- **If this lands broken, the user experiences:** silent gaslighting — known affected cohort conversation re-opened, only user messages visible, no acknowledgement of the gap. User concludes the product is still broken.
- **If this leaks, the user's [data] is exposed via:** PR-B is read-only client-side filter on already-RLS'd hydration; no new exposure surface.
- **Brand-survival threshold:** `high-confidence-correctable`. Botched marker (wrong copy, false positive on healed thread, missing on cohort thread) is correctable within hours. No Art. 33 surface.

Failure modes ranked:

1. Marker fails to render on affected threads → silent-gaslighting persists → hours-correctable.
2. Marker renders on non-affected thread (false positive) → confusing note → hours-correctable.
3. Marker flashes during streaming → ~1-3s UX glitch per turn → hours-correctable; addressed by FR2 refinement.

## Domain Review

**Domains relevant:** Product, Engineering, Legal (carry-forward from umbrella + PR-B focused refresh)

### Engineering (CTO — carry-forward)

**Status:** reviewed (carry-forward)
**Assessment:** No new persistence, no new server surface. CTO carry-forward applies.

### Legal (CLO — carry-forward)

**Status:** reviewed (carry-forward)
**Assessment:** Marker IS the Art. 5(1)(a) per-thread transparency remediation. No new compliance surface.

### Product/UX Gate

**Tier:** blocking (mechanical escalation — new `components/**/*.tsx` file)
**Decision:** reviewed (carry-forward — all three pipeline agents ran during brainstorm)
**Agents invoked:** spec-flow-analyzer (brainstorm Phase 0.5), cpo (brainstorm focused refresh), ux-design-lead (brainstorm wireframes). Marker wireframe State B (no CTA variant) is now the only state — already designed.
**Skipped specialists:** copywriter (English-only minimal copy per spec NG5)
**Pencil available:** N/A

#### Findings (plan-review pass)

- DHH: validated Q1 resolution and CTA-drop direction (P1 simplifications applied).
- Kieran: wiring + mount-anchor + Date.parse-NaN + test-naming findings applied; CTA-related findings (#3) moot after drop.
- code-simplicity: CTA-drop position adopted; test cuts applied (11 → 5); useMemo + debounce + Phase 2 ceremony dropped.

## Files to Create

- `apps/web-platform/components/chat/cohort-missing-reply-marker.tsx`
- `apps/web-platform/test/cohort-missing-reply-marker.test.tsx`

## Files to Edit

- `apps/web-platform/components/chat/chat-surface.tsx` — mount the marker conditionally before `messagesEndRef`
- `knowledge-base/project/specs/feat-cc-transcript-hardening-prb-3603/spec.md` — add a single-line "Plan-Time Amendments" note pointing here (NO strike-through, NO FR rewrite — spec stays as historical record)

## Open Code-Review Overlap

**None.** Open code-review issues #3638-3642 touch `cc-dispatcher.ts` (PR-A2 follow-ups); PR-B's file scope doesn't overlap. Verified:

```bash
gh issue list --label code-review --state open --json number,body --limit 200 \
  | jq -r '.[] | select(.body | contains("cohort-missing-reply") or contains("chat-surface.tsx")) | "#\(.number)"'
# returns: (empty)
```

## Implementation Phases

### Phase 0 — Setup

- [x] 0.1 Read `apps/web-platform/components/chat/chat-surface.tsx` lines 570-740 to confirm: (a) `messages.map` mount block exists at ~574, (b) `<div ref={messagesEndRef} />` exists at ~733, (c) no virtualization wrapper has been introduced since this plan was drafted, (d) `conversation.created_at` (or equivalent) is accessible from the surrounding scope of the mount point.

### Phase 1 — Component implementation (RED → GREEN, single commit)

#### 1.1 Tests T-marker (write first, RED)

File: `apps/web-platform/test/cohort-missing-reply-marker.test.tsx`. Synthesized fixtures only (`cq-test-fixtures-synthesized-only`). Test names use AC trace inline per sibling `abort-marker.test.tsx` convention.

- [x] 1.1.1 `test("AC1 — renders marker on cohort fixture with locale-formatted created_at", ...)`. Cohort fixture (`createdAt: "2026-05-08T10:00:00Z"`, two user-only text messages). Assert marker visible; assert rendered text contains "started" + locale-formatted "May 8, 2026" (or equivalent for `en-US` if test locale is forced).
- [x] 1.1.2 `test.each([healed, postFix, preWindow, streaming, postSunset])("AC2-AC5 — hides marker when …", ({ fixture, label, expectHidden }) => { … })`. Parametrized table with 5 cases sharing one render+assert body: (a) healed (cohort fixture + one appended assistant message), (b) post-fix (`createdAt: "2026-05-12T00:00:00Z"` — exclusive upper bound), (c) pre-window (`createdAt: "2026-05-04T23:59:00Z"`), (d) streaming (`isStreamingAssistant: true`), (e) post-sunset (`vi.useFakeTimers()` + `vi.setSystemTime("2026-08-11T00:00:01Z")`).
- [x] 1.1.3 `test("AC9 — semantic role and aria-label", ...)`. Assert `screen.getByRole("note", { name: /conversation history note/i })` returns the marker root.

All three tests FAIL with "component not found" before Phase 1.2.

#### 1.2 Component implementation (GREEN)

File: `apps/web-platform/components/chat/cohort-missing-reply-marker.tsx`:

- [x] 1.2.1 Module-level constants. Use `new Date(...).getTime()` (validates at module load — `NaN` would surface at any test run, not at production runtime):
  ```ts
  const COHORT_WINDOW_START = new Date("2026-05-05T00:00:00Z").getTime();
  const COHORT_WINDOW_END = new Date("2026-05-12T00:00:00Z").getTime();
  const COHORT_MARKER_SUNSET = new Date("2026-08-11T00:00:00Z").getTime();
  ```
  Single-line comment: `// Sunset 90 days after PR-B merge — component returns null after this date; lazy-delete on next file touch.`
- [x] 1.2.2 Exported function `CohortMissingReplyMarker({ createdAt }: { createdAt: string })`. Single prop matching the hydration-payload spelling (Kieran finding #1).
- [x] 1.2.3 Early return when `Date.now() >= COHORT_MARKER_SUNSET` returns `null`. NaN-guard `Number.isNaN(Date.parse(createdAt))` also returns `null` to suppress malformed-date false positives.
- [x] 1.2.4 Format date inline (no `useMemo` — single call per render, render is gated by the parent's filter): `const formattedDate = new Intl.DateTimeFormat(undefined, { year: "numeric", month: "long", day: "numeric" }).format(new Date(createdAt));`.
- [x] 1.2.5 JSX:
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
  Use the existing `text-soleur-text-secondary` token (verified live in `pwa-install-banner.tsx`). No new color or spacing classes invented.
- [x] 1.2.6 No `onContinue`, no button, no event handlers. Component is pure presentational.
- [x] 1.2.7 Re-run test suite: assert all three tests GREEN.

#### 1.3 Mount in chat-surface

- [x] 1.3.1 Import the constants from the marker module (not duplicated). The cohort filter lives at the mount site, not inside the component, so the predicate can read sibling chat-surface state (`isStreamingAssistant`) without prop-drilling.
- [x] 1.3.2 Inline the predicate at the JSX site (no `useMemo` — five boolean checks per render is fine):
  ```tsx
  {(() => {
    const textMessages = messages.filter((m) => m.type === "text");
    const startMs = Date.parse(conversation.created_at);
    const isCohortMissingReply =
      textMessages.length > 0 &&
      textMessages.every((m) => m.role === "user") &&
      startMs >= COHORT_WINDOW_START &&
      startMs < COHORT_WINDOW_END &&
      !isStreamingAssistant;
    return isCohortMissingReply ? <CohortMissingReplyMarker createdAt={conversation.created_at} /> : null;
  })()}
  ```
  Mount **immediately before** `<div ref={messagesEndRef} />` at ~line 733.
- [x] 1.3.3 Identify the actual `isStreamingAssistant`-equivalent state slice name in chat-surface (likely derived from `status` or a workflow-lifecycle hook). Use the exact name in the predicate.
- [x] 1.3.4 Confirm `conversation.created_at` is available in the mount scope; if the hydration payload exposes it as `createdAt` instead of `created_at`, adapt.

#### 1.4 Phase 1 commit

- [x] 1.4.1 Run full suite: `bunx vitest run apps/web-platform/test/`. Assert green.
- [x] 1.4.2 `bun tsc --noEmit` clean.
- [x] 1.4.3 `bun lint` clean on edited files.
- [x] 1.4.4 Add a one-line "Plan-Time Amendments" note at the top of `knowledge-base/project/project/specs/feat-cc-transcript-hardening-prb-3603/spec.md`:
  > **Plan-Time Amendments (2026-05-12):** CTA dropped during plan-review (DHH + code-simplicity convergence). Spec FR4-FR7 and AC6-AC9 are superseded by `knowledge-base/project/plans/2026-05-12-feat-cc-transcript-hardening-prb-cohort-marker-plan.md` §Research Reconciliation. Spec body retained as historical record.
- [x] 1.4.5 Commit `feat(chat): add CohortMissingReplyMarker (text-only) for cohort transparency — #3603`. Single commit covers component + test + chat-surface mount + spec amendment note.

### Phase 2 — Pre-merge gates

- [ ] 2.1 Push branch; mark PR #3653 ready for review (`gh pr ready 3653`).
- [ ] 2.2 Run `/soleur:review` 5-agent parallel pass. `user-impact-reviewer` invocation is mandatory per `brand_survival_threshold: high-confidence-correctable` (the review skill's conditional-agent block).
- [ ] 2.3 Fix-inline any P1 findings per `rf-review-finding-default-fix-inline`.
- [ ] 2.4 `/soleur:qa` skipped — UX-only, no DB writes, no integration test surface beyond unit.
- [ ] 2.5 `/soleur:preflight` ship Phase 5.5: confirm plan's `## User-Brand Impact` section present (it is); no sensitive-path regex matches (chat component is not regulated-data surface).
- [ ] 2.6 `gh pr checks` green.
- [ ] 2.7 `gh pr merge --squash --auto`.

### Phase 3 — Post-merge

- [ ] 3.1 `/soleur:postmerge` deployment + Sentry health for chat-surface render path.
- [ ] 3.2 AC10: open one cohort-matching conversation on prod (if any exists in the operator's account); confirm marker renders with the conversation's actual `created_at` formatted in the operator's browser locale. If no affected conversation exists, mark N/A and document.
- [ ] 3.3 `/soleur:compound` — capture the Q1 resolution + CTA-drop pattern (transparency surfaces should resist adding affordances when the existing UI already provides the action surface).

**Out of scope (deliberate omissions vs original plan draft):**

- ~~Phase 2 spec amendment as standalone phase~~ — inlined into Phase 1.4.4 (one-line note, no FR rewrite). DHH P2.
- ~~Phase 4.4 `/soleur:schedule` cleanup PR~~ — dead code costs nothing; lazy-delete on next file touch. DHH P3.
- ~~Phase 0.1/0.3/0.4 baseline run + role-typing read + symbol-grep~~ — typescript + write-time will catch. code-simplicity P2.
- ~~useMemo on predicate and Intl.DateTimeFormat~~ — premature optimization. DHH + code-simplicity P1.
- ~~Debounce-on-render via useRef + useEffect~~ — testing the framework, not the component. DHH + Kieran. (Moot anyway after CTA drop.)
- ~~`cohort-window-constants.ts` extracted module~~ — three consts at the top of a 30-LoC file, no circular-import problem. DHH + code-simplicity.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** Marker renders on a synthesized cohort fixture (`createdAt: 2026-05-08T10:00:00Z`, two user-only text messages) with the conversation's `created_at` formatted in the test locale.
- **AC2.** Marker hides on a healed fixture (same row + one synthesized assistant text message).
- **AC3.** Marker hides on a post-fix fixture (`createdAt: 2026-05-12T00:00:00Z` — exclusive upper bound).
- **AC4.** Marker hides on a pre-window fixture (`createdAt: 2026-05-04T23:59:00Z`).
- **AC5.** Marker hides during active streaming (`isStreamingAssistant: true`) regardless of message-list match.
- **AC6.** Marker hides when test clock advances past `COHORT_MARKER_SUNSET` (2026-08-11 UTC).
- **AC7.** Marker hides when `createdAt` is malformed or empty (`Number.isNaN(Date.parse(createdAt))` guard).
- **AC8.** A11y: `aside` exposes `role="note"` with `aria-label="Conversation history note"`. Marker carries no interactive elements.
- **AC9.** `bun tsc --noEmit` clean. `bun lint` clean on edited files. Full Vitest suite passes.
- **AC10.** `user-impact-reviewer` agent passes at PR review.

### Post-merge (operator)

- **AC11.** Manual verification on prod (if cohort conversation exists in any operator account).

## Risks

- **R1 — Cohort filter false positive during streaming.** Addressed by FR2 refinement (`!isStreamingAssistant` clause). Phase 0.1 reads chat-surface to confirm the exact state name; Phase 1.3.3 names it.
- **R2 — Non-text message types in cohort conversations (review_gate, interactive_prompt).** Filter pre-restricts to `type === "text"`. If a cohort conversation has ONLY non-text user messages (very rare; user has to have invoked an interactive prompt without typing), the marker won't render. Acceptable — those conversations have a different surface for "incomplete" already (the prompt's own UI).
- **R3 — `conversation.created_at` malformed or null.** AC7 guard returns `null`. No exception, no marker rendered.
- **R4 — Sunset bypassable via clock skew.** No security boundary; acceptable.
- **R5 — Mount-point regression in chat-surface.** Plain `messages.map` (not virtualized — verified at `chat-surface.tsx:574-606`); appending a sibling is safe. `/soleur:review` at Phase 2.2 catches any layout regression.
- **R6 — `isStreamingAssistant` slice rename in future PR-A follow-ups.** If a follow-up renames the chat-surface state, the cohort filter silently breaks (marker flashes again). Mitigation: TypeScript ensures the named slice is referenced correctly at compile time; future grep for `isStreamingAssistant` (or whatever the actual slice name is) will surface the marker's dependency.

## Test Strategy

- **Framework:** Vitest 3.1 + `@testing-library/react` 16.3 + `@testing-library/user-event` 14.6 (verified Phase 0).
- **File:** `apps/web-platform/test/cohort-missing-reply-marker.test.tsx`.
- **Sibling precedent:** `apps/web-platform/test/abort-marker.test.tsx`.
- **Coverage:** AC1-AC9 in 3 `test()` cases (one parametrized table). No CTA tests (CTA dropped).
- **Fixtures:** Synthesized only. No DB seed, no Supabase access.
- **Time:** `vi.useFakeTimers()` + `vi.setSystemTime` for sunset case.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Carry-forward done.)
- The cohort window constants live in the marker component file. chat-surface imports them — no separate constants module. Sunset PR (eventual) deletes one file.
- The `isStreamingAssistant`-equivalent state slice name is verified at Phase 0.1 and again at Phase 1.3.3. Do not guess.
- The spec stays as a historical record. Do NOT strike-through FR4-FR7 in the spec body during Phase 1.4.4 — just add the one-line "Plan-Time Amendments" note pointing to this plan. Future readers will understand the spec captured the original intent, the plan captures the shipped form.

## Plan Review Output

Three reviewers ran (DHH + Kieran + code-simplicity) in parallel before this plan was finalized. Convergent findings applied to this revision:

- **DHH (P1):** collapse 11 tests → 4-5, drop useMemo, drop debounce, drop Phase 2 ceremony, drop `cohort-window-constants.ts`, lazy-delete sunset (no scheduled PR). All applied.
- **Kieran (must-fix):** prop renamed `createdAt`; test names use AC trace inline; mount anchor explicit before `messagesEndRef`; Date.parse → `new Date().getTime()` with module-load validation. All applied.
- **code-simplicity (strongest position):** drop the CTA entirely. **Adopted per operator decision** — collapses the largest residual scope. The marker is now text-only.
- **code-simplicity (next-cheapest alternative):** "zero code — email the affected users." Considered and rejected by operator: the marker earns its position for per-thread context that direct comms cannot provide weeks later when a user re-opens an affected conversation.
