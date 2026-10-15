---
title: "Shared-document footer banner — change CTA label to \"Sign up for the waitlist\""
type: feat
date: 2026-06-08
branch: feat-one-shot-shared-doc-waitlist-cta
lane: single-domain
brand_survival_threshold: none
status: ready
---

# ✨ feat: Shared-document footer banner — CTA label "Create your account" → "Sign up for the waitlist"

## Enhancement Summary

**Deepened on:** 2026-06-08
**Sections enhanced:** Observability (prose → 5-field schema), Domain Review (added
wireframe `.pen` exemption rationale), verify-the-negative pass on all plan claims.

### Key Improvements

1. **Observability section** rewritten from a prose "skipped" note to the compliant
   5-field schema (`liveness_signal` / `error_reporting` / `failure_modes` / `logs` /
   `discoverability_test`) so deepen-plan Phase 4.7 passes mechanically — the
   discoverability test is the existing vitest run (no SSH).
2. **Wireframe exemption documented** — `cta-banner.tsx` matches the `components/**`
   glob superset but is exempt per the UI-surface-terms "Excluded: pure copy tweaks"
   carve-out; recorded so the Phase 4.9 determination is auditable rather than silent.
3. **Verify-the-negative pass** confirmed all factual claims against the codebase:
   signup-page H1 unchanged (1 occurrence, out-of-scope file), `href="/signup"` at
   line 31, exactly 7 test matchers, `aria-label="Dismiss signup banner"` intact.

### New Considerations Discovered

- The label "Sign up for the waitlist" semantically implies a waitlist, but the
  destination stays `/signup` (a live OTP signup page). A Plausible analytics goal
  `"Waitlist Signup"` already exists. Whether the destination should diverge from
  signup is an open product question captured under Non-Goals (deferred, not filed —
  the divergence may be intentional since signup *is* the waitlist today).
- `Create your account` lives in two files; only `cta-banner.tsx:34` changes. A blind
  repo-wide replace would clobber the signup-page H1 — flagged as a Sharp Edge.

## Overview

The public shared-document view (`/shared/[token]`) renders a fixed footer banner
(`CtaBanner`) reading:

> This document was created with **Soleur** — AI agents for every department of your startup.

with a gold CTA button currently labelled **"Create your account"**. Change that
button's visible label to **"Sign up for the waitlist"**.

This is a pure copy change to a single user-facing string plus the test assertions
that pin it. No behavioral, routing, styling, or schema change.

### Scope clarification (directional ambiguity resolved)

The arguments to this task contained two label spellings:

- Task title/instruction: change from `"Create an account"` → `"Sign up for the waitlist"`.
- Screenshot note: the **visible** button reads `"Create your account"` (verified in
  source at `apps/web-platform/components/shared/cta-banner.tsx:34`).

**Resolution:** the codebase string is `"Create your account"` (not `"Create an
account"`). The explicit operator note ("the visible button reads 'Create your
account' — update that CTA label") overrides the title's paraphrase. The new label
is the single canonical target: **`Sign up for the waitlist`**. There is exactly
one such CTA button in the shared-document banner.

## Research Reconciliation — Spec vs. Codebase

| Claim (from task) | Reality (verified in repo) | Plan response |
| --- | --- | --- |
| Button reads "Create an account" | Source string is `Create your account` (`cta-banner.tsx:34`) | Target the actual string `Create your account`; new label `Sign up for the waitlist`. |
| Banner is in the shared / public view | `CtaBanner` rendered only by `app/shared/[token]/page.tsx:150` (`{data && <CtaBanner />}`) | Correct surface; no other render site. |
| "waitlist" implies a waitlist form/route | No `/waitlist` route exists. `/signup` is a live OTP signup page. A Plausible analytics goal `"Waitlist Signup"` exists (`cron-plausible-goals.ts:46`) but is unrelated to this button's destination. | **Out of scope:** the `href="/signup"` destination is NOT changed — task asks only to change the visible *label*. See Non-Goals. |

## User-Brand Impact

**If this lands broken, the user experiences:** the shared-document footer banner
shows the wrong/stale CTA label, or the banner crashes/renders nothing (the link is
the only always-present interactive element besides dismiss). Worst realistic case
of a copy typo: a slightly-off button label on a public marketing surface.

**If this leaks, the user's data is exposed via:** N/A — no data is read, written,
or transmitted by this change. The banner is a static `<Link>` + a `sessionStorage`
dismiss flag (unchanged).

**Brand-survival threshold:** none — a button-label copy edit on a public banner.
No sensitive path touched (no schema, migration, auth flow, API route, or `.sql`).

## Acceptance Criteria

### Pre-merge (PR)

- [x] The shared-document banner CTA button visible text is exactly
      `Sign up for the waitlist`.
      Verify: `grep -n "Sign up for the waitlist" apps/web-platform/components/shared/cta-banner.tsx` returns 1 line.
- [x] The string `Create your account` no longer appears in `cta-banner.tsx`.
      Verify: `grep -c "Create your account" apps/web-platform/components/shared/cta-banner.tsx` returns `0`.
- [x] The signup page H1 is unchanged (`app/(auth)/signup/page.tsx:99` still reads
      `Create your account` — a different, out-of-scope surface).
      Verify: `grep -c "Create your account" "apps/web-platform/app/(auth)/signup/page.tsx"` returns `1`.
- [x] All test assertions pinning the old label are updated to the new label.
      Verify: `grep -c "create your account" apps/web-platform/test/shared-cta-banner-close.test.tsx` (case-insensitive `-i`) returns `0`;
      `grep -ci "sign up for the waitlist" apps/web-platform/test/shared-cta-banner-close.test.tsx` returns `7`.
- [x] `aria-label="Dismiss signup banner"` and `data-testid="cta-banner-dismiss"`
      are unchanged (the dismiss-related test assertions `/dismiss signup banner/i`
      stay green).
- [x] `href="/signup"` is unchanged.
- [x] Test suite passes:
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/shared-cta-banner-close.test.tsx`.
- [x] `tsc --noEmit` (or the repo's typecheck script) passes — though no types change.

## Files to Edit

- `apps/web-platform/components/shared/cta-banner.tsx`
  - Line 34: replace the link's child text `Create your account` →
    `Sign up for the waitlist`.
  - Leave `href="/signup"`, classes, `aria-label`, dismiss button, and SVG untouched.
- `apps/web-platform/test/shared-cta-banner-close.test.tsx`
  - 7 occurrences of the accessible-name matcher `/create your account/i`
    (lines 20, 28, 35, 40, 50, 60, 72) → `/sign up for the waitlist/i`.
  - Leave the `/dismiss signup banner/i` button matcher and the
    `data-testid` queries untouched.
  - Consider updating the `it("renders the signup CTA by default", …)` description
    only if desired — optional, non-load-bearing (the test still asserts the link
    role); not required by ACs.

## Files to Create

- None.

## Open Code-Review Overlap

None — checked: no open `code-review` issues touch `cta-banner.tsx` or
`shared-cta-banner-close.test.tsx` (single-file copy change; verify with the
two-stage `gh issue list --json` + `jq --arg` pattern at /work time if desired,
but the surface is too narrow to expect overlap).

## Non-Goals / Out of Scope

- **Changing the link destination** (`href="/signup"`). The task asks only to
  change the visible label. If a true waitlist flow is intended (distinct from the
  live `/signup` OTP page), that is a separate feature: it would need a
  `/waitlist` route or form, copy on the signup page, and analytics wiring to the
  existing Plausible `"Waitlist Signup"` goal. **Deferred — file a follow-up issue
  only if product confirms the destination should diverge from signup.** No issue
  is filed now because the destination divergence is not part of this request and
  may be intentional (signup *is* the waitlist today).
- Editing the signup page H1 (`Create your account` at `signup/page.tsx:99`).
- Changing banner styling, dismiss behavior, or the marketing sentence text.

## Test Strategy

The existing `test/shared-cta-banner-close.test.tsx` (vitest, jsdom project — file
matches `include: ["test/**/*.test.tsx"]` in `apps/web-platform/vitest.config.ts`)
already asserts the CTA link by accessible name. Update those 7 matchers to the new
label; the suite then proves the new copy renders, survives dismiss, and persists
dismissal. No new test file needed.

Runner note: web-platform runs under **vitest**, not `bun test` (`bunfig.toml` sets
`[test] pathIgnorePatterns = ["**"]`). Use
`./node_modules/.bin/vitest run test/shared-cta-banner-close.test.tsx`.

## Domain Review

**Domains relevant:** Product (UI copy on a public surface)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline) — modifies one existing user-facing string
on an existing component; adds no new interactive surface, page, or flow.
**Agents invoked:** none
**Skipped specialists:** none — `ux-design-lead` N/A (no new UI surface; a one-word
copy edit to an existing button is not a new component or flow).
**Pencil available:** N/A (no UI surface created)

**Wireframe (`.pen`) exemption — `wg-ui-feature-requires-pen-wireframe`:** `cta-banner.tsx`
matches the `components/**/*.tsx` glob superset, but
`plugins/soleur/skills/brainstorm/references/ui-surface-terms.md` → **Excluded**
explicitly carves out "Pure copy or style tweaks with no structural/layout change."
This change is a single-word button label edit with zero structural or layout change,
so no `.pen` wireframe is required. The glob superset is deliberately over-broad; the
Excluded list is the authoritative refinement cited by all four enforcement layers.

#### Findings

Pure copy change. The new label "Sign up for the waitlist" sets an expectation of a
waitlist; the destination remains the live `/signup` page (see Non-Goals). If
product wants the label to imply a gated waitlist, that is the follow-up noted in
Non-Goals. No brand-guide conflict in the label itself.

## Observability

This is a static-copy change to a React component (no runtime branch, network call,
log, or persisted-state surface added), so the schema fields below describe the
existing render/test surface rather than any new instrumentation. The change adds no
new failure mode that needs an alert; the load-bearing post-merge check is the
existing component test plus visual confirmation on the public shared page.

```yaml
liveness_signal:
  what: CtaBanner renders the CTA link with accessible name "Sign up for the waitlist" on /shared/<token>
  cadence: on every public shared-document page view (client render)
  alert_target: none — copy-only change, no alertable runtime signal
  configured_in: apps/web-platform/components/shared/cta-banner.tsx (static JSX)
error_reporting:
  destination: none added — the banner has no try/catch or network call; the only
    error path (sessionStorage throwing) is already swallowed by safeSession and
    covered by existing tests
  fail_loud: false (graceful render is the desired behavior; pre-existing)
failure_modes:
  - mode: wrong/stale CTA label rendered
    detection: vitest assertion getByRole("link", { name: /sign up for the waitlist/i })
    alert_route: CI test failure on PR (vitest run, blocks merge)
  - mode: label regression on the signup-page H1 (wrong file edited)
    detection: AC grep — signup/page.tsx still reads "Create your account"
    alert_route: CI / PR review (AC verification)
logs:
  where: none added (client component, no server log emission)
  retention: n/a
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/shared-cta-banner-close.test.tsx
  expected_output: all tests pass; the suite asserts the CTA link by its new accessible name
```

## Infrastructure (IaC)

None — no server, service, cron, secret, DNS, cert, or vendor account introduced.
Pure `apps/web-platform/components/**` + `apps/web-platform/test/**` edit.

## Risks & Mitigations

- **Risk:** missing one of the 7 test matchers leaves a stale assertion that fails
  against the new label. **Mitigation:** AC greps assert `0` case-insensitive hits
  for the old label and `7` for the new in the test file.
- **Risk:** accidentally editing the signup-page H1 (same string, different file).
  **Mitigation:** AC pins `signup/page.tsx:99` to still read `Create your account`.

## Sharp Edges

- The string `Create your account` exists in **two** files. Only
  `cta-banner.tsx:34` changes; `signup/page.tsx:99` (the H1) must NOT. A blind
  repo-wide find-and-replace would clobber the signup page — edit by file, not globally.
- The test file matches the **jsdom** vitest project (`test/**/*.test.tsx`), not the
  node project. Run via `vitest run`, never `bun test` (blocked by `bunfig.toml`).
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (Section is filled above; threshold = none with sensitive-path
  reason: no sensitive path touched.)
