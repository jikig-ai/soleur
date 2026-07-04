// ---------------------------------------------------------------------------
// Named CEO/design/devex panel composition (ADR-084 / #5985).
//
// PURE decision function: maps the detect step's INDEPENDENT relevance signals
// to the set of named-panel lenses to spawn. Kept in an importable module so it
// is testable WITHOUT spawning live agents (AC11/AC12) — the Workflow runtime
// cannot import (no filesystem/import access), so `plan-review.workflow.js`
// carries a byte-identical duplicate of `computeNamedPanel` per the
// self-contained-workflow convention (keep the two copies in sync, like
// safeTitle/safeId). The drift guard in
// `plugins/soleur/test/plan-review-named-panel.test.ts` asserts the workflow
// copy stays wired.
//
// CPO Condition 1 (correlated-failure fix): activation is driven by an
// INDEPENDENT content scan, never by trusting the plan's own `## Domain Review`
// verdict — a UI plan mis-judged `Product: NONE` still activates ux+cpo via the
// mechanical UI-surface hit.
// ---------------------------------------------------------------------------

// The four named lenses, in stable output order.
export const NAMED_LENSES = ['cpo', 'cmo', 'cto', 'ux-design-lead']

/**
 * Compute the named panel from INDEPENDENT relevance signals.
 *
 * @param {object} signals
 * @param {boolean} signals.uiSurfaceHit  - mechanical: `## Files to Create/Edit`
 *   contains a UI-surface glob (components/**\/*.tsx, app/**\/page.tsx,
 *   app/**\/layout.tsx, or a shared UI-term path). Overrides the Domain Review
 *   verdict — this is the correlated-failure fix.
 * @param {boolean} signals.productSignal - fresh read: product/scope language.
 * @param {boolean} signals.marketingSignal - fresh read: market/GTM/brand/user-copy language.
 * @param {boolean} signals.uxSignal - fresh read: user-facing/flow/visual language.
 * @param {boolean} signals.devexSignal - fresh read: code/infra/tooling Files-to-Edit.
 * @returns {string[]} activated lens keys, subset of NAMED_LENSES, stable order.
 */
export function computeNamedPanel(signals) {
  const s = signals || {}
  const active = new Set()

  // Step 1 — mechanical UI-surface scan (independent). A UI-surface hit forces
  // ux-design-lead + cpo regardless of the Domain Review verdict.
  if (s.uiSurfaceHit) {
    active.add('ux-design-lead')
    active.add('cpo')
  }

  // Step 2 — fresh independent relevance read (NOT the verdict line).
  if (s.productSignal) active.add('cpo')
  if (s.marketingSignal) active.add('cmo')
  if (s.uxSignal) active.add('ux-design-lead')
  if (s.devexSignal) active.add('cto')

  // Step 4 — if none activate, the named panel is empty (eng panel still runs).
  return NAMED_LENSES.filter((k) => active.has(k))
}
