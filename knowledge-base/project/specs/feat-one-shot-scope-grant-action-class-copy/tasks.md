---
title: "Tasks: human-readable action-class titles on Scope Grants and related UIs"
plan: knowledge-base/project/plans/2026-05-21-feat-scope-grant-action-class-human-copy-plan.md
branch: feat-one-shot-scope-grant-action-class-copy
created: 2026-05-21
lane: single-domain
---

# Tasks — Scope Grants action-class human copy

## Phase 0 — Verification

- [ ] 0.1 — Re-grep for unknown consumers of raw `actionClass` text.
  - Command: `grep -rn '\{actionClass\}\|run\.actionClass' apps/web-platform/components/ apps/web-platform/app/`
  - Expected: 8 known source files (`scope-grant-row.tsx`, `audit-sections.tsx`, `redacted-event-summary.tsx`, `runtime-explainer-banner.tsx`, `today-card.tsx`, `typed-confirm-modal.tsx` consumer-side, plus the page wrappers). Any new match is a scope expansion — record in plan body before continuing.
- [ ] 0.2 — Run baseline green: `cd apps/web-platform && ./node_modules/.bin/vitest run`. Capture exit code 0 before any edits.
- [ ] 0.3 — Open Code-Review Overlap query across all 8 files (see plan §Open Code-Review Overlap).

## Phase 1 — Copy map (TDD: RED → GREEN)

- [ ] 1.1 — Write `apps/web-platform/test/messages/action-class-copy.test.ts` with the 6 AC1 assertions (every-class-covered, non-empty title, non-empty description, title ≤ 60 chars, description ≤ 200 chars, category ∈ 8-value editorial set, no dotted-ID leakage in titles).
- [ ] 1.2 — Run the test: should fail (import missing).
- [ ] 1.3 — Write `apps/web-platform/lib/messages/action-class-copy.ts`:
  - `ACTION_CLASS_COPY: Record<ActionClass, { title: string; description: string; category: string }>` typed `as const`.
  - 16 entries — one per `ACTION_CLASSES` member.
  - `satisfies Record<ActionClass, …>` for compile-time exhaustiveness.
  - Draft titles conservatively (active voice, no jargon, ≤ 60 chars).
  - Draft descriptions: one sentence each, ≤ 200 chars.
  - Category labels from the 8-value set: "Money", "Engineering", "Triage", "Security", "Knowledge", "Customer replies", "Brand-critical sends", "Infrastructure".
- [ ] 1.4 — Re-run test: should pass.
- [ ] 1.5 — Run `cd apps/web-platform && npx tsc --noEmit`: exit code 0.

## Phase 2 — Row component swap

- [ ] 2.1 — Edit `apps/web-platform/components/scope-grants/scope-grant-row.tsx`:
  - Import `ACTION_CLASS_COPY` from `@/lib/messages/action-class-copy`.
  - Compute `const copy = ACTION_CLASS_COPY[actionClass]`.
  - Replace `<h2>{actionClass}</h2>` (line ~128-130) with `<h3>{copy.title}</h3>`.
  - Add `<p className="mt-1 text-sm text-soleur-text-secondary">{copy.description}</p>` between title and the "Active at … since …" line.
  - Add `<code className="mt-1 block text-xs text-soleur-text-muted">{actionClass}</code>` caption (always visible).
  - Change `<legend>` (line ~159) from `Trust tier for {actionClass}` to `Trust tier for {copy.title}`.
  - Leave `aria-describedby`, `id`, `name`, `aria-describedby`-error-id attributes USING `actionClass` (DOM identifiers, not user-visible text — see Sharp Edge 3).

## Phase 3 — Category grouping on Scope Grants page

- [ ] 3.1 — Edit `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/page.tsx`:
  - Add `const CATEGORY_ORDER = ["Money", "Engineering", "Triage", "Security", "Knowledge", "Customer replies", "Brand-critical sends", "Infrastructure"] as const;`.
  - Build `categoryToClasses: Record<string, ActionClass[]>` by walking `ACTION_CLASSES` and reading `ACTION_CLASS_COPY[ac].category`.
  - Replace the flat `<ul>` rendering with one `<section aria-labelledby={…}>` per non-empty category, each containing an `<h2>` category heading and a nested `<ul>` of `<ScopeGrantRow>`.
- [ ] 3.2 — Visual smoke: run dev server locally; open `/dashboard/settings/scope-grants`; confirm 8 sections with row groupings.

## Phase 4 — Audit log swap

- [ ] 4.1 — Edit `apps/web-platform/components/audit/audit-sections.tsx`:
  - Add `humanTitle(s: string): string` helper using `isKnownActionClass` + `ACTION_CLASS_COPY`.
  - Update `buildMailto` subject (line ~51): `${REQUEST_REVIEW_SUBJECT_PREFIX}: ${humanTitle(run.actionClass)} (${run.id})`.
  - Update `buildMailto` body (line ~55): split into `Action: ${humanTitle(run.actionClass)}\n` + `Technical ID: ${run.actionClass}\n`.
  - Update `<RedactedEventSummary eventName={run.actionClass} />` → `<RedactedEventSummary eventLabel={humanTitle(run.actionClass)} masked={…} />`.
- [ ] 4.2 — Edit `apps/web-platform/components/audit/redacted-event-summary.tsx`:
  - Rename prop `eventName` → `eventLabel`.
  - Drop the literal `"Stripe"` prefix (line ~18). New shape: `<span>{eventLabel} for <code>{masked}</code></span>`.
- [ ] 4.3 — Re-grep for any test asserting `"Stripe"` literal on the audit surface:
  - Command: `grep -rn '"Stripe"\|Stripe ' apps/web-platform/test/ | grep -v node_modules | grep -iE 'redacted|audit'`
  - Plan-time result: ZERO matches. Re-confirm at /work time; if matches appear, update or remove obsolete assertions.

## Phase 5 — Runtime explainer banner + typed-confirm modal

- [ ] 5.1 — Edit `apps/web-platform/components/dashboard/runtime-explainer-banner.tsx`:
  - Replace the lines-43-48 `ACTION_CLASSES.map((ac, i) => <code>{ac}</code>)` rendering with a `<ul>` of category-grouped bullets.
  - Each bullet: `{categoryLabel} — {titles.join(", ")}` where titles are derived from `ACTION_CLASS_COPY` filtered to the category.
- [ ] 5.2 — Edit `apps/web-platform/components/dashboard/today-card.tsx`:
  - Line ~411: change `actionClassLabel={confirming?.actionClass ?? ""}` to `actionClassLabel={confirming ? humanTitle(confirming.actionClass) : ""}`.
  - Import or locally define `humanTitle` with the same fallback as audit-sections.

## Phase 6 — Exhaustiveness test + checklist comment

- [ ] 6.1 — Edit `apps/web-platform/test/server/scope-grants/action-class-exhaustive.test.ts`:
  - Add a runtime parity assertion: `for (const c of ACTION_CLASSES) { expect(ACTION_CLASS_COPY).toHaveProperty(c); }`.
  - Keep content-shape assertions (title cap, non-empty fields, category enum) in the dedicated `test/messages/action-class-copy.test.ts` — this file enforces registry parity.
- [ ] 6.2 — Edit `apps/web-platform/server/scope-grants/action-class-map.ts` doc comment:
  - Locate the "Adding an entry" checklist (lines 8-12 approximately).
  - Add a 5th item: `extend lib/messages/action-class-copy.ts with {title, description, category} per test/messages/action-class-copy.test.ts content rules.`

## Phase 7 — Full verification

- [ ] 7.1 — `cd apps/web-platform && ./node_modules/.bin/vitest run` exits 0.
- [ ] 7.2 — `cd apps/web-platform && npx tsc --noEmit` exits 0.
- [ ] 7.3 — `cd apps/web-platform && npm run lint` exits 0 (next lint).
- [ ] 7.4 — Local dev smoke: open `/dashboard/settings/scope-grants`, `/dashboard/audit`, and the today-banner runtime explainer; screenshot each.
- [ ] 7.5 — Playwright verification against deployed `https://app.soleur.ai/dashboard/settings/scope-grants` per AC12. Attach screenshot to PR body.

## Phase 8 — Acceptance criteria check-off

- [ ] AC1 through AC12 (see plan): verify each with the prescribed command before marking PR ready.

## Phase 9 — PR-body wiring

- [ ] 9.1 — PR title: `feat: human-readable action-class titles on Scope Grants`.
- [ ] 9.2 — PR body references `Ref #4067 (operator QA follow-through)`, NOT `Closes #4067` (issue is already closed).
- [ ] 9.3 — Include before/after screenshots from Phase 7.4 and 7.5.
- [ ] 9.4 — Note Phase 4.6 threshold = `none` with justification; no CPO sign-off required.
