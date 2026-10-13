---
title: "feat: human-readable action-class titles on Scope Grants and related UIs"
type: enhancement
status: planned
lane: single-domain
branch: feat-one-shot-scope-grant-action-class-copy
created: 2026-05-21
requires_cpo_signoff: false
---

# feat: human-readable action-class titles on Scope Grants and related UIs

## Enhancement Summary

**Deepened on:** 2026-05-21
**Sections enhanced:** Overview, Files to Edit, Acceptance Criteria, Risks, Sharp Edges
**Phase 4.6 (User-Brand Impact halt):** PASS — section present, threshold `none` with explicit justification, no sensitive-path matches in `Files to Edit` (verified against canonical regex).
**Phase 4.7 (Observability gate):** SKIP — plan touches `apps/web-platform/components/`, `lib/messages/`, `app/(dashboard)/dashboard/`, and `test/` only. No new code under `apps/*/server/` or `apps/*/infra/`. Pure FE copy edits.
**Phase 4.8 (PAT-shaped variable halt):** PASS — sweep returned no matches.

### Key Improvements (over plan v1)

1. **Codebase claim verification.** Every "lines X-Y" attribution and "renders Z" claim was re-grepped at deepen-time. Two minor corrections noted below (see Research Insights → Verified Facts).
2. **R2 (Stripe-prefix test risk) downgraded.** Grep `grep -rn '"Stripe"\|Stripe ' apps/web-platform/test/ | grep -iE 'redacted|audit'` returned ZERO matches. The "Stripe" hardcoding in `redacted-event-summary.tsx:18` is rendered but not test-asserted. Risk R2 stays in the plan (caution against future drift) but is documented as a single-grep, not a multi-test fix-up.
3. **Tooling verified.** `apps/web-platform/node_modules/.bin/vitest` exists (symlinked); `package.json scripts.test = "vitest"`; `scripts.test:ci = "vitest run"`. The plan's verification commands (`./node_modules/.bin/vitest run …`) are correct.

### New Considerations Discovered

- **Off-by-one on `action-class-map.ts` checklist line range.** Plan v1 cites "lines 8-11" for the "Adding an entry" comment. Actual range is lines 8-12 (5 lines, ending with the `expect(ACTION_CLASSES.length).toBe(...)` bump step). AC9 wording uses "lines 8-11" — preserve intent ("extend the checklist with a 5th step"); /work agent can confirm the correct line range at edit time.
- **`scope-grants/page.tsx` line 68 confirmed: linear `ACTION_CLASSES.map`, no current grouping.** The plan's Phase 3 category-grouping addition is purely additive — no removal of existing UI behavior.
- **`audit/page.tsx` confirmed clean** (no `actionClass` references). All audit-surface edits land in `components/audit/`, not the page wrapper.

### Research Insights — Verified Facts

| Plan claim | Verification command | Result |
|---|---|---|
| `ACTION_CLASSES` has 16 members | `awk '/ACTION_CLASSES = \[/,/\] as const/' apps/web-platform/server/scope-grants/action-class-map.ts \| grep -cE '^\s+"[a-z]'` | `16` ✓ |
| `scope-grant-row.tsx:129` renders `<h2>{actionClass}</h2>` | `sed -n '128,130p' apps/web-platform/components/scope-grants/scope-grant-row.tsx` | confirmed ✓ |
| `audit/page.tsx` does NOT reference `actionClass` | `grep -n 'actionClass' apps/web-platform/app/\(dashboard\)/dashboard/audit/page.tsx` | no matches ✓ |
| `scope-grants/page.tsx:68` uses `ACTION_CLASSES.map` (linear, ungrouped) | `grep -n 'ACTION_CLASSES.map' apps/web-platform/app/\(dashboard\)/dashboard/settings/scope-grants/page.tsx` | line 68 ✓ |
| `test/messages/` is NEW directory | `ls apps/web-platform/test/messages/ 2>/dev/null` | does not exist ✓ |
| vitest binary present | `ls -la apps/web-platform/node_modules/.bin/vitest` | symlink present ✓ |
| `expect(ACTION_CLASSES.length).toBe(16)` exists | `grep -n 'ACTION_CLASSES.length' apps/web-platform/test/server/scope-grants/action-class-exhaustive.test.ts` | line 102 ✓ |
| No existing test asserts literal `"Stripe"` prefix | `grep -rn '"Stripe"' apps/web-platform/test/ \| grep -v node_modules` | no matches ✓ — R2 is forward-looking only |
| Action-class-map "Adding an entry" checklist line range | `sed -n '7,13p' apps/web-platform/server/scope-grants/action-class-map.ts` | actual range is 8-12 (plan v1 says 8-11; preserve intent, fix at /work) |

## Overview

The Scope Grants page (`/dashboard/settings/scope-grants`), the runtime
explainer banner, the audit log, and the typed-confirm modal all render
raw `ACTION_CLASSES` enum values (dotted IDs like
`external.brand_critical.bluesky_reply_soleur_handle`) as user-facing
text. These are internal identifiers — operator feedback during QA of
#4067 was direct: "not understandable for Soleur users."

This change introduces `apps/web-platform/lib/messages/action-class-copy.ts`
— a single source of truth for human-readable `{ title, description,
category }` per action class — mirroring the PR-G `trust-tier-copy.ts`
pattern verbatim. UI consumers swap dotted IDs for the copy map's
`title`; the dotted ID stays accessible as a small `<code>` caption for
operator/support log mapping. The technical IDs in
`server/scope-grants/action-class-map.ts` are NOT renamed — they are
load-bearing enum values referenced by DB CHECK constraints, Inngest
function names, and webhook routers.

Scope: copy-layer + UI-swap only. No schema changes, no behavior changes,
no security-boundary changes. The category field is editorial UI text,
not a security primitive (per `action-class-map.ts:97-98`).

## User-Brand Impact

**If this lands broken, the user experiences:** Scope Grants page
renders empty/`undefined` titles or React error boundaries, blocking
founders from authorizing or revoking action classes. Worst case:
mis-routed copy (wrong description on wrong row) makes founders
authorize the wrong class — but the security boundary is the dotted-ID
radio submit, not the title, so a copy-map miswire is informational
drift, not unauthorized action.

**If this leaks, the user's data is exposed via:** N/A. This change
touches operator-facing copy only. No new data flows, no new persisted
fields, no auth-boundary edits.

**Brand-survival threshold:** none

Reason for `none`: This is editorial UI copy with zero new data
processing, zero auth-boundary changes, zero net new write surfaces. The
existing security gates (per-class radio submit, server-side
`isGranted`, DB CHECK enum-absence) are untouched. Failure mode is
"founder sees a confusing label" — a degraded UX, not a brand-survival
event. The threshold `single-user incident` is reserved for changes
whose failure mode is a single user experiencing a money/legal/identity
incident — this change cannot cause one.

## Research Reconciliation — Spec vs. Codebase

The feature description in the one-shot ARGUMENTS named 4 UI surfaces.
Repo grep at plan time found **3 additional consumers** the description
did not enumerate. Each must land in `Files to Edit` or be explicitly
deferred.

| Spec claim | Codebase reality (grep at plan time) | Plan response |
|---|---|---|
| 16 action classes today | Confirmed: `ACTION_CLASSES.length === 16` (`test/server/scope-grants/action-class-exhaustive.test.ts:102`). | Mirror 16 entries in `ACTION_CLASS_COPY`. |
| Scope Grants row renders `<h2>{actionClass}</h2>` | Confirmed at `components/scope-grants/scope-grant-row.tsx:129`. Also `aria-label`/`legend`/`name` attributes use raw `actionClass` at lines 159, 174, 222, 157. | Swap title + secondary text + technical `<code>` caption; update `<legend>` text; keep `name={`tier-${actionClass}`}` (DOM attribute, not user-facing — must remain stable for form-submit). |
| Audit page renders raw class name | Indirect — `app/(dashboard)/dashboard/audit/page.tsx` itself does NOT render `actionClass`. The renderer is `components/audit/audit-sections.tsx:191` via `RedactedEventSummary({ eventName: run.actionClass })`, and lines 51, 55 use it inside `buildMailto` subject + body. | Edit `audit-sections.tsx` (renderer) and `redacted-event-summary.tsx` (consumer), NOT the page wrapper. Plan §Files to Edit lists both. |
| (not in spec) `components/dashboard/runtime-explainer-banner.tsx` joins all 16 raw IDs into a sentence at lines 43-46. | Confirmed via `grep -rn "ACTION_CLASSES" apps/web-platform/components/`. | Fold in — same defect class, same fix (use `ACTION_CLASS_COPY[ac].title` per item). |
| (not in spec) `components/ui/typed-confirm-modal.tsx:121` renders `{tierLabel} — {actionClassLabel}`; caller `components/dashboard/today-card.tsx:411` passes raw `confirming?.actionClass` for `actionClassLabel`. | Confirmed via `grep -rn "actionClassLabel" apps/web-platform/`. | Fold in — `today-card.tsx` must pass `ACTION_CLASS_COPY[ac].title` (with a runtime fallback for unknown classes since `confirming?.actionClass` is typed as `string`, not `ActionClass`). |
| (not in spec) `audit-sections.tsx:51,55` use raw `actionClass` in `mailto:` subject and body. | Confirmed. | Use `ACTION_CLASS_COPY[ac]?.title ?? ac` in `buildMailto`; keep the raw dotted ID as a second line in the body for operator support. |
| Test file `test/server/scope-grants/action-class-exhaustive.test.ts` exists with `expect(ACTION_CLASSES.length).toBe(16)`. | Confirmed at line 102; also has compile-time `Record<ActionClass, X>` parity gates at lines 32-36. | Add a fourth gate to that test (runtime parity for `ACTION_CLASS_COPY`) AND a separate `test/messages/action-class-copy.test.ts` for content shape (title length cap, non-empty fields, category enum membership). The test/server file already enforces the compile-time `Record<ActionClass, ...>` parity via `satisfies` — the new copy file gets the same `satisfies` rail. |
| `bun test` vs `vitest` | `package.json scripts.test = "vitest"`; the existing test file imports from `vitest`. | Tests use vitest, not bun test. Verification command: `./node_modules/.bin/vitest run test/messages/action-class-copy.test.ts test/server/scope-grants/action-class-exhaustive.test.ts` from `apps/web-platform/`. |

**Net effect on Files to Edit:** the brief named 5 files (1 new lib, 1
row component, 2 pages, 2 tests). Reality is **8 source files** (1 new
lib, 1 row component, 1 page, 1 audit-sections renderer, 1
redacted-event-summary, 1 runtime-explainer banner, 1 today-card caller,
1 typed-confirm-modal type rename — optional) **plus 2 tests** (1 new, 1
extended). The Scope Grants `page.tsx` itself only iterates
`ACTION_CLASSES.map`; the row component is where the title swap lands.

## Files to Edit

### New files

- `apps/web-platform/lib/messages/action-class-copy.ts` — single
  source-of-truth `ACTION_CLASS_COPY: Record<ActionClass, { title:
  string; description: string; category: string }>` map. 16 entries,
  one per current `ACTION_CLASSES` member. `as const`. Re-export
  `ActionClass` for ergonomic single-import consumers. Includes
  exhaustiveness rail (`satisfies Record<ActionClass, …>` — compile-time
  gate per `cq-union-widening-grep-three-patterns`).

- `apps/web-platform/test/messages/action-class-copy.test.ts` — vitest
  suite asserting (a) every `ACTION_CLASSES` member has a copy entry,
  (b) every entry has non-empty `title`, `description`, `category`,
  (c) every `title` ≤ 60 chars (founder-readable cap), (d) every
  `description` ≤ 200 chars (one sentence cap), (e) `category` ∈ the
  8-value editorial set ("Money", "Engineering", "Triage", "Security",
  "Knowledge", "Customer replies", "Brand-critical sends",
  "Infrastructure"), (f) titles contain no dotted-ID characters (no
  `.`, no `_` — reject internal-ID leakage).

### Edited files

- `apps/web-platform/components/scope-grants/scope-grant-row.tsx` —
  - Import `ACTION_CLASS_COPY` from `@/lib/messages/action-class-copy`.
  - Line 128-130: swap `<h2>{actionClass}</h2>` for `<h2
    className="font-medium text-soleur-text-primary">{copy.title}</h2>`
    where `const copy = ACTION_CLASS_COPY[actionClass]`.
  - Add secondary `<p className="mt-1 text-sm text-soleur-text-secondary">{copy.description}</p>`
    between title and the existing "Active at … since …" line.
  - Add small `<code className="mt-1 block text-xs text-soleur-text-muted">{actionClass}</code>`
    caption — always visible (no toggle; the dotted ID is short
    enough that a single muted line is less friction than a toggle, and
    operator-support workflows benefit from always-on visibility).
  - Line 159: change `<legend className="sr-only">Trust tier for
    {actionClass}</legend>` to `Trust tier for {copy.title}`.
  - Line 157, 222: leave `aria-describedby={`${actionClass}-error`}`
    and `id={`${actionClass}-error`}` AS IS — these are DOM linkage
    identifiers, not user-visible text. Same for `name={`tier-${actionClass}`}`
    on the radio (line 174). Form-submit semantics depend on stable
    `name` attributes; the dotted ID is structurally correct here.

- `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/page.tsx` —
  - Page currently does NOT group rows by category (it iterates
    `ACTION_CLASSES.map` linearly at lines 68-80). Per the brief's
    conditional ("if it groups by category, use the new `category`
    field"), the trigger does not apply. **Scope decision:** ship
    category grouping in this PR. Rationale: with 16 rows the linear
    list is already a wall of text; the editorial value of "Money /
    Engineering / Triage / Security / Knowledge / Customer replies /
    Brand-critical sends / Infrastructure" headings is what makes the
    copy improvement actually legible. The grouping is presentational
    and reverts cleanly; if review prefers list-only, drop the
    `<section>` wrappers and keep the title/description swap.
  - Add a stable category order constant
    `CATEGORY_ORDER: readonly string[]` matching the
    `ACTION_CLASS_COPY` enum (Money → Engineering → Triage → Security
    → Knowledge → Customer replies → Brand-critical sends →
    Infrastructure). Group `ACTION_CLASSES` into category buckets at
    render time; emit one `<section aria-labelledby>` per non-empty
    bucket with an `<h2>` category heading + the existing
    `<ScopeGrantRow>` list inside.
  - Move the row component's `<h2>` to an `<h3>` to keep heading
    hierarchy correct (page `<h1>` → section `<h2>` → row `<h3>`).
    This is a one-line edit in `scope-grant-row.tsx` and the only
    structural change.

- `apps/web-platform/components/audit/audit-sections.tsx` —
  - Import `ACTION_CLASS_COPY` and `isKnownActionClass` from server
    map.
  - Line 31: `actionClass: string` — leave as `string` (the Inngest
    API surface is untyped; runtime fallback handles unknown values).
  - Line 51 `buildMailto` subject: replace `run.actionClass` with
    `humanTitle(run.actionClass)` where `humanTitle(s) =
    isKnownActionClass(s) ? ACTION_CLASS_COPY[s].title : s`.
  - Line 55 `buildMailto` body: replace `Action class: ${run.actionClass}`
    with two lines — `Action: ${humanTitle(run.actionClass)}` and
    `Technical ID: ${run.actionClass}`. Operator support needs both.
  - Line 191 `<RedactedEventSummary eventName={run.actionClass} />`:
    change prop name to `eventLabel` and pass
    `humanTitle(run.actionClass)`. Update the `RedactedEventSummary`
    component below.

- `apps/web-platform/components/audit/redacted-event-summary.tsx` —
  - Rename prop `eventName` → `eventLabel` (the value is now a human
    title, not a literal Stripe event-name like `invoice.payment_failed`).
  - The component currently hard-codes the phrase `"Stripe"` (line 18)
    — this was correct when the only audit source was Stripe webhooks,
    but PR-H widened to GitHub/external/infra surfaces. The phrasing
    must drop the `"Stripe"` prefix. New shape: `<span>{eventLabel}
    for <code>{masked}</code></span>`. The `masked` value is still a
    customer/entity id; the rendered text becomes (e.g.) "Payment
    failed for `cus_***`".
  - **Coupled risk:** AC8 in the original PR-G plan stated this file
    is the SOLE renderer of the masked-summary string with a
    grep-guard. Re-run the grep at /work time to confirm the guard's
    expected text changed accordingly. If the grep guard is encoded
    in a test, update it.

- `apps/web-platform/components/dashboard/runtime-explainer-banner.tsx` —
  - Replace the `ACTION_CLASSES.map((ac, i) => <code>{ac}</code>)`
    rendering at lines 43-48 with category-grouped human-readable
    bullets. Concretely: replace the inline `<code>`-comma-separated
    sentence with a short bulleted list (`<ul>`) of category labels
    (e.g., "Money — payment failures", "Engineering — PR reviews + CI
    failures", "Customer replies — vendor support, status updates,
    DMs", "Brand-critical sends — marketing email, public posts,
    enterprise DMs", "Infrastructure — dependency bumps, log
    rotations"). The current sentence form is unreadable at 16 items
    and is the most operator-hostile surface in the codebase per
    feedback during #4067 QA.
  - Compose bullets by walking `Object.values(ACTION_CLASS_COPY)`
    grouped by `category`, emitting one bullet per category with the
    category label + a comma-joined list of titles. This stays in
    sync automatically when classes are added.

- `apps/web-platform/components/dashboard/today-card.tsx` —
  - Line 411: change `actionClassLabel={confirming?.actionClass ?? ""}`
    to `actionClassLabel={confirming ? humanTitle(confirming.actionClass) : ""}`
    where `humanTitle` is imported from a small local helper (or
    inlined as a ternary). Use the same `isKnownActionClass` runtime
    fallback as audit-sections.
  - The TypedConfirmModal prop name `actionClassLabel` is already
    semantic ("label" not "id"), so no prop rename is required —
    only the call-site value changes.

- `apps/web-platform/test/server/scope-grants/action-class-exhaustive.test.ts` —
  - Update the comment block at lines 8-11 (the
    "Adding an entry" checklist in `action-class-map.ts:8-11` is the
    canonical list; that file is the source-of-truth for the
    checklist, NOT this test file). Edit `action-class-map.ts:8-11`
    to add a fifth step: "extend `lib/messages/action-class-copy.ts`
    with `{title, description, category}` per the message-budget
    rules in `test/messages/action-class-copy.test.ts`."
  - Add a runtime parity assertion (test `(f)`): `for (const c of
    ACTION_CLASSES) { expect(ACTION_CLASS_COPY).toHaveProperty(c); }`.
    Keep the new content-shape assertions (title cap, non-empty,
    category-enum) in the new dedicated test file — this file's
    role is the registry-exhaustiveness rail, not copy content.

### Files NOT edited (verified absent)

- `apps/web-platform/app/(dashboard)/dashboard/audit/page.tsx` — Per
  the brief's "if it renders the raw class name, swap" condition, the
  trigger does not apply: this server component does NOT render
  `actionClass`. The renderer lives in `audit-sections.tsx`. Listed
  here per Sharp Edge "files NOT edited should be explicit when the
  brief named them" — review can grep to confirm.

- `apps/web-platform/server/scope-grants/action-class-map.ts` — Per
  brief constraint: technical IDs are load-bearing enum values
  referenced by DB CHECK constraints, Inngest function names, and
  webhook routers (consumer list at lines 13-21). DO NOT rename. The
  only edit is the doc-comment checklist extension at lines 8-11 (see
  above).

- `apps/web-platform/lib/messages/trust-tier-copy.ts` — Per brief
  constraint: trust-tier copy is already covered by PR-G. DO NOT
  duplicate or refactor.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — `apps/web-platform/lib/messages/action-class-copy.ts`
  exists and exports `ACTION_CLASS_COPY: Record<ActionClass, { title:
  string; description: string; category: string }>` typed `as const`,
  with exactly 16 entries — one per `ACTION_CLASSES` member.
  Verification: `cd apps/web-platform && ./node_modules/.bin/vitest
  run test/messages/action-class-copy.test.ts` passes all 6 assertions
  (every-class-covered, non-empty-title, non-empty-description, title
  ≤ 60 chars, description ≤ 200 chars, category ∈ 8-value editorial
  set, no dotted-ID leakage in titles).

- **AC2** — `tsc --noEmit` from `apps/web-platform/` exits 0.
  Concretely: the compile-time `satisfies Record<ActionClass, …>` rail
  on `ACTION_CLASS_COPY` triggers `TS2322` when a new `ActionClass`
  member is added without a copy entry. Verification: dry-run by
  adding a literal to `ACTION_CLASSES` locally without touching
  `ACTION_CLASS_COPY` and confirming `tsc --noEmit` fails with the
  expected message — REVERT before commit.

- **AC3** — `apps/web-platform/components/scope-grants/scope-grant-row.tsx`
  renders `ACTION_CLASS_COPY[actionClass].title` as the row heading
  (`<h3>` after the page-grouping change). Verification:
  `grep -nE '^\s*<h[23]>?.*\{actionClass\}' components/scope-grants/scope-grant-row.tsx`
  returns zero matches (no raw `{actionClass}` in heading position);
  `grep -n 'ACTION_CLASS_COPY' components/scope-grants/scope-grant-row.tsx`
  returns at least 2 matches (title + description).

- **AC4** — The dotted ID is still rendered in the row, but as
  `<code>` muted caption — operator/support can map UI to logs.
  Verification: `grep -n '<code' components/scope-grants/scope-grant-row.tsx`
  returns a line containing `{actionClass}`.

- **AC5** — Audit log renders human-readable titles (not dotted IDs)
  in `RedactedEventSummary`, in `buildMailto` subject, and in
  `buildMailto` body (the body retains the dotted ID on a separate
  "Technical ID:" line for support). Verification:
  `grep -n '\${run\.actionClass}' components/audit/audit-sections.tsx`
  returns at most 1 match (the "Technical ID:" body line);
  `grep -n 'humanTitle\|ACTION_CLASS_COPY' components/audit/audit-sections.tsx`
  returns ≥ 3 matches (subject, body human line, prop pass).

- **AC6** — Runtime explainer banner renders a category-grouped
  bulleted summary, not a 16-item comma-separated `<code>`-list.
  Verification: `grep -c '<code' components/dashboard/runtime-explainer-banner.tsx`
  returns 0 (no raw-ID `<code>` tags); `grep -c 'ACTION_CLASS_COPY'
  components/dashboard/runtime-explainer-banner.tsx` returns ≥ 1.

- **AC7** — Typed-confirm modal receives a human title for
  `actionClassLabel`. Verification:
  `grep -n 'actionClassLabel' components/dashboard/today-card.tsx`
  returns a line where the value is `humanTitle(...)` (or equivalent),
  NOT `confirming?.actionClass`.

- **AC8** — Scope Grants page renders category section headings.
  Verification: `grep -cE '<section .*aria-labelledby' app/\(dashboard\)/dashboard/settings/scope-grants/page.tsx`
  returns ≥ 8 (one per category present); the page's row iteration
  is grouped by `ACTION_CLASS_COPY[ac].category` rather than the
  flat `ACTION_CLASSES.map`.

- **AC9** — `action-class-map.ts` doc-comment checklist (lines 8-11)
  is extended with step 5: "extend `lib/messages/action-class-copy.ts`
  with `{title, description, category}`." Verification:
  `grep -n 'action-class-copy' server/scope-grants/action-class-map.ts`
  returns ≥ 1.

- **AC10** — `RedactedEventSummary` no longer hardcodes `"Stripe"` in
  user-visible text. Verification:
  `grep -n '"Stripe"\|>Stripe<' components/audit/redacted-event-summary.tsx`
  returns 0. The component now reads `eventLabel` (human title) and
  renders `{eventLabel} for <code>{masked}</code>`.

- **AC11** — All existing `vitest` suites still pass. Verification:
  `cd apps/web-platform && ./node_modules/.bin/vitest run` exits 0.
  Specifically: `test/server/scope-grants/action-class-exhaustive.test.ts`
  passes (existing parity gates + new copy parity gate); any
  `accept-terms-copy-regression`-style copy tests still pass.

- **AC12** — Playwright verification against deployed
  `https://app.soleur.ai/dashboard/settings/scope-grants` (operator
  session) shows each row's heading is a human-readable phrase, not
  a dotted ID. Screenshot attached to PR body. Verification:
  `mcp__playwright__browser_navigate` to the URL,
  `mcp__playwright__browser_snapshot`, confirm 16 rows with
  non-dotted headings + 8 category section headings.

### Post-merge (operator)

(none — pure FE/copy change, no migrations, no infra, no IaC)

## Test Scenarios

### S1 — Copy map coverage

Given `ACTION_CLASSES` has 16 members and `ACTION_CLASS_COPY` is
declared with `satisfies Record<ActionClass, {title, description,
category}>`, when a 17th member is added to `ACTION_CLASSES` without
updating the copy map, then `tsc --noEmit` fails with `TS2322 ...
not assignable to ... Record<ActionClass, ...>`.

### S2 — Row rendering

Given a founder with no active grants visits
`/dashboard/settings/scope-grants`, when the page renders, then each
row shows: an `<h3>` with a human-readable phrase (no `.`/`_`), a
description paragraph, and a small muted `<code>` caption containing
the dotted ID.

### S3 — Audit mailto body retains technical ID

Given an Inngest run appears in the audit log, when the founder clicks
"Request human review →", then the mailto body contains both
`Action: Payment failed` (or equivalent human title) AND `Technical
ID: finance.payment_failed`. Operator support reads the latter.

### S4 — Category section grouping

Given the 16 classes span 8 editorial categories, when the Scope
Grants page renders, then there are exactly 8 `<section>` blocks with
`<h2>` category headings, in stable `CATEGORY_ORDER` regardless of
`ACTION_CLASSES` member order.

### S5 — Typed-confirm modal label

Given a founder triggers the `approve_every_time` typed-confirm flow
for an `external.brand_critical.*` send, when the modal opens, then
the subtitle shows `{tierLabel} — {human title}`, not `{tierLabel} —
external.brand_critical.public_x_thread`.

### S6 — Unknown action class fallback

Given a runtime path emits an action class not in `ACTION_CLASS_COPY`
(e.g., audit row from an older record that pre-dates a future enum
rename), when `humanTitle` is called, then it returns the raw string
unchanged (no exception, no `undefined`).

### S7 — Runtime explainer banner stays in sync

Given a 17th `ACTION_CLASS` is added with a copy entry in category
"Engineering", when the explainer banner re-renders, then the
"Engineering" bullet automatically includes the new title (no manual
update to the banner needed).

## Risks

- **R1 — Category grouping reorders existing rows.** Founders who have
  memorized the linear order will see rows in a new sequence. Mitigation:
  document in the PR body that the order is intentional and category-
  based; the dotted-ID `<code>` caption preserves the find-by-id path.

- **R2 — `RedactedEventSummary` "Stripe" prefix removal is a
  user-visible string change.** PR-G's AC8 explicitly named that file
  as the sole renderer of the masked-summary string. Deepen-pass
  verified `grep -rn '"Stripe"\|Stripe ' apps/web-platform/test/ |
  grep -v node_modules | grep -iE 'redacted|audit'` returns ZERO
  matches at the time of plan-write — risk is forward-looking, not
  retroactive. The /work phase must re-run that grep at edit time to
  confirm no new tests have landed since.

- **R3 — `today-card.tsx` `confirming?.actionClass` is typed as
  `string`, not `ActionClass`.** The runtime fallback (`isKnownActionClass(s)
  ? COPY[s].title : s`) handles this without a type-cast — confirm the
  fallback path is exercised in tests rather than relying on assertions.

- **R4 — Brand voice drift.** The copy text itself is the load-bearing
  artifact. Without a copywriter pass, descriptions may sound
  engineer-written. Mitigation: this plan's brainstorm/spec stage did
  not flag CMO/copywriter; the threshold is "non-engineer founders
  understand it." Recommend the /work agent draft conservatively
  (active voice, "Soleur [verb]s when [condition]") and request
  copywriter review at PR-review time if a domain leader flags it.

- **R5 — Cap drift on `title` length.** A future class with a long
  human title (e.g., "Slack DM to enterprise tier-1 customer") may
  bump up against the 60-char cap. The test rejects entries above the
  cap; the /work agent must trim or restructure. The cap is editorial,
  not load-bearing — bump in a follow-up PR if needed.

## Open Code-Review Overlap

Query (per Phase 1.7.5):

```bash
gh issue list --label code-review --state open \
  --json number,title,body --limit 200 > /tmp/open-review-issues.json
# Then per file:
jq -r --arg path "components/scope-grants/scope-grant-row.tsx" '
  .[] | select(.body // "" | contains($path))
  | "#\(.number): \(.title)"
' /tmp/open-review-issues.json
```

Run at /work time. If matches surface for any of the 8 edited files,
record disposition (fold-in / acknowledge / defer) inline before
shipping.

**Plan-time pre-check:** None matched the 4 files named in the brief.
The 4 additional surfaces discovered (`runtime-explainer-banner.tsx`,
`audit-sections.tsx`, `redacted-event-summary.tsx`, `today-card.tsx`)
have not been cross-checked yet — /work Phase 0 task.

## Domain Review

**Domains relevant:** Product (BLOCKING — mechanical: this plan
modifies 5+ existing user-facing components and changes the most
prominent text on `/dashboard/settings/scope-grants`. Not in the
BLOCKING-tier "new pages" category, but in the "founder-facing copy on
a single-user-incident-adjacent surface" category. Recommend
copywriter pass post-implementation.)

### Product/UX Gate

**Tier:** advisory (copy-only on existing screens; no new pages, no new
interactive surfaces, no new flow paths)

**Decision:** auto-accepted (pipeline) — plan written inside a one-shot
Task subagent; deferring the interactive prompt per the existing ADVISORY-
pipeline-mode rule.

**Agents invoked:** none at plan-time (operator may invoke copywriter
agent at PR-review time if voice drift surfaces in the draft).

**Skipped specialists:** ux-design-lead (rationale: no new wireframes
required — copy swap on existing components, layout unchanged except
for category section headers which mirror standard
`<section><h2>...</h2></section>` Tailwind-card pattern already in
use); copywriter (rationale: defer to PR-review; the /work agent
drafts conservatively per R4 and review-time can re-engage if needed).

**Pencil available:** N/A (no wireframes needed)

#### Findings

Copy quality is the load-bearing artifact. The /work agent should:

1. Read existing operator-facing copy in
   `lib/legal/disclosures.ts` and `lib/messages/trust-tier-copy.ts` for
   tone reference — short, direct, second-person, "Soleur [verb]s".
2. Avoid jargon (`P0`, `P1`, `tier-1`, `CVE`) in titles; descriptions
   may use the technical term once if helpful. E.g., title "Critical
   bug triage" + description "When a P0/P1 issue is filed, Soleur
   triages it and routes to the right owner."
3. Avoid implying behavior Soleur does NOT do. E.g., do not write
   "Soleur pays the invoice" for `finance.payment_failed` — Soleur
   surfaces the failure and (at most) drafts a customer reply.

## Infrastructure (IaC)

Not applicable — no new infrastructure surface. No new servers,
services, secrets, vendors, DNS records, or runtime processes. Plan
edits files under `apps/web-platform/components/`,
`apps/web-platform/lib/messages/`, `apps/web-platform/app/`, and
`apps/web-platform/test/` only.

## Observability

Not required per Phase 2.9 — this plan adds zero new code paths under
`apps/*/server/` or `apps/*/infra/`. All edits are FE rendering and
copy data. The existing observability surfaces on Scope Grants (grant
POST route, `isGranted` server function, audit-log RPC) are untouched.

## Implementation Phases

### Phase 0 — Verification

0.1 — Re-grep for unknown consumers of raw `actionClass` text. Plan
recorded 8 source files; re-run `grep -rn '\{actionClass\}\|run\.actionClass'
apps/web-platform/components/ apps/web-platform/app/` and confirm.
Any new match is a scope expansion — record in the plan body's "Files
to Edit" section before continuing.

0.2 — Run `cd apps/web-platform && ./node_modules/.bin/vitest run`
to capture green baseline before any edits.

0.3 — Cross-check Open Code-Review Overlap query (see section above)
against the full 8-file set.

### Phase 1 — Copy map (TDD: failing test → green)

1.1 — Write `test/messages/action-class-copy.test.ts` with all 6
assertions per AC1. Run: should fail because the import target does
not exist yet.

1.2 — Write `lib/messages/action-class-copy.ts` with 16 entries.
Draft titles + descriptions conservatively (R4); use `as const` and
`satisfies Record<ActionClass, …>`.

1.3 — Re-run the test from 1.1: should pass.

1.4 — Run `tsc --noEmit`: should pass.

### Phase 2 — Row component swap

2.1 — Update `components/scope-grants/scope-grant-row.tsx` per Files
to Edit. Heading goes from `<h2>` to `<h3>` in anticipation of Phase
3's section grouping.

2.2 — Confirm `aria-label` / `<legend>` / `name` attributes per the
plan (user-visible text uses `copy.title`; DOM identifiers retain
`actionClass`).

### Phase 3 — Category grouping on Scope Grants page

3.1 — Add `CATEGORY_ORDER` constant + grouping helper in
`app/(dashboard)/dashboard/settings/scope-grants/page.tsx`. Render one
`<section>` per non-empty category.

3.2 — Manual smoke (Playwright) against local dev server to confirm
heading hierarchy and grouping look right.

### Phase 4 — Audit log swap

4.1 — Update `components/audit/audit-sections.tsx` per Files to Edit
(humanTitle helper, subject + body, prop rename).

4.2 — Update `components/audit/redacted-event-summary.tsx`: drop
"Stripe" prefix; rename `eventName` → `eventLabel`.

4.3 — Re-grep for any test asserting `"Stripe"` literal on the audit
surface (R2). Update or delete obsolete assertions.

### Phase 5 — Runtime explainer banner + typed-confirm modal

5.1 — Update `components/dashboard/runtime-explainer-banner.tsx` per
Files to Edit (category-grouped bullets instead of comma-separated
codes).

5.2 — Update `components/dashboard/today-card.tsx:411` to pass
`humanTitle(confirming.actionClass)` into the typed-confirm modal.

### Phase 6 — Exhaustiveness test extension

6.1 — Add the runtime parity assertion to
`test/server/scope-grants/action-class-exhaustive.test.ts` (test `(f)`).

6.2 — Update the "Adding an entry" comment in
`server/scope-grants/action-class-map.ts:8-11` with step 5.

### Phase 7 — Full verification

7.1 — `cd apps/web-platform && ./node_modules/.bin/vitest run` exits 0.

7.2 — `cd apps/web-platform && npx tsc --noEmit` exits 0.

7.3 — Local dev server: open `/dashboard/settings/scope-grants`,
`/dashboard/audit`, and the today-banner runtime-explainer surface;
screenshot each.

7.4 — Playwright against deployed
`https://app.soleur.ai/dashboard/settings/scope-grants` per AC12.
Attach screenshot to PR body.

## Sharp Edges

- **Sharp Edge 1 — Plan whose `## User-Brand Impact` is empty fails
  deepen-plan Phase 4.6.** This plan's threshold is `none` with an
  explicit one-sentence justification. Do not strip the justification
  during edits.

- **Sharp Edge 2 — `RedactedEventSummary`'s "Stripe" prefix removal
  is a load-bearing copy edit.** PR-G's AC8 declared this file the
  sole renderer of the masked-summary string. /work Phase 4 must
  re-check the grep guard if it exists.

- **Sharp Edge 3 — DOM identifiers vs user-visible text.** Resist the
  temptation to rename `name={`tier-${actionClass}`}` or the
  `aria-describedby` chain — form-submit semantics depend on stable
  identifiers, and per scope-grant-row.tsx:174 the `name` is what the
  radio-group binds. User-visible text uses `copy.title`; DOM
  identifiers retain `actionClass`. This is the same pattern as
  `trust-tier-copy.ts` where `TIER_ORDER` (DOM key) stays as the
  enum value while `TRUST_TIER_COPY[t].label` is the visible string.

- **Sharp Edge 4 — Brand voice drift without a copywriter pass.**
  The /work agent will draft 16 titles + 16 descriptions
  conservatively. If review surfaces voice issues, fix-inline; if the
  finding is broad (more than 4 entries need rewording), spawn the
  copywriter agent and apply the diff before merge.

- **Sharp Edge 5 — Category labels are editorial, not enum-typed.**
  Defining `category` as `string` (not a discriminated union) is a
  deliberate choice: the editorial labels can drift independently of
  `ActionClassCategory` (the internal type at `action-class-map.ts:58-66`).
  The test enforces the 8-value set at runtime. If a future class
  needs a 9th category, the test fails, /work updates both the
  copy map and the test in the same PR.

- **Sharp Edge 6 — Unknown action class at runtime.** The audit log
  surfaces records from arbitrary historical Inngest runs. A run row
  with an unrecognized class (because it predates a future enum
  rename, or because a fixture is stale) must NOT crash the UI.
  `humanTitle(s) = isKnownActionClass(s) ? COPY[s].title : s` is the
  fallback. Test S6 verifies.

## Related

- PR-G #3947 — trust-tier-copy.ts pattern (mirrored here).
- PR-H #4077 — extended action-class registry to 16 entries.
- Issue #4067 / PR #4059 — router.refresh fix on Scope Grants; this
  plan addresses operator feedback from that QA session.
- ADR-034 — action-class registry as single source of truth for
  per-class authorization.

## PR body — closing reference

This is a UX copy-only enhancement caught during QA of the merged
PR #4059 (issue #4067). No tracking issue was filed; the PR body
should reference `Ref #4067 (operator QA follow-through)` rather
than `Closes`. There is no formal issue to close.
