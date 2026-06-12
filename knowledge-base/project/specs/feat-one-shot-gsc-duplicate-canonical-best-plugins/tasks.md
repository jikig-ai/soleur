---
title: 'Tasks — GSC Duplicate-canonical (www variant) — best-claude-code-plugins-2026'
plan: knowledge-base/project/plans/2026-06-12-fix-gsc-duplicate-canonical-best-plugins-plan.md
branch: feat-one-shot-gsc-duplicate-canonical-best-plugins
lane: single-domain
---

# Tasks

Outcome: **no required repo code change.** The reported GSC class is the benign
`www→apex` 301 consolidation; on-site signals are correct. Resolution is operator
VALIDATE-FIX + wait. One **optional** CI hardening (Phase 2) may be folded in or
deferred.

## Phase 0 — Preconditions (verify only)

- [x] 0.1 Re-run live checks (re-verified at /work time 2026-06-12 — drift-clean):
  - `curl -sI https://www.soleur.ai/blog/best-claude-code-plugins-2026/` → **301**, `location: https://soleur.ai/blog/best-claude-code-plugins-2026/` ✓
  - `curl -sI https://soleur.ai/blog/best-claude-code-plugins-2026/` → **200** ✓
  - apex canonical → `https://soleur.ai/blog/best-claude-code-plugins-2026/` (apex) ✓
- [x] 0.2 Confirmed `site.url == "https://soleur.ai"` (apex) in `_data/site.json`. ✓
- [x] 0.3 Confirmed PR #4729 hardening intact: `validate-seo.sh` retains the
  redirect-stub gate + sitemap canonical-host gate; AC5 (`_site/sitemap.xml`
  redirecting-loc count) = 0. ✓

## Phase 1 — Outcome decision (no code)

- [x] 1.1 Conclusion recorded (benign `www→apex` consolidation; no site code fix —
  resolution is operator VALIDATE-FIX + wait). Captured in session-state.md + the
  tracking issue (filed at ship).

## Phase 2 — OPTIONAL CI regression-hardening (FOLDED IN)

- [x] 2.1 **Decided: FOLD IN.** ~16 added lines; directly extends the existing
  sitemap host-consistency invariant to the per-page canonical axis; precedent =
  2026-06-01 benign-finding→defense-in-depth hardening. Produces a testable,
  shippable gate vs. a docs-only PR.
- [x] 2.2 Edited `validate-seo.sh`: after the per-page `rel="canonical"` presence
  check, added a host assertion. **Design refinement over the plan snippet:** the
  expected host is **DERIVED from the sitemap's single `<loc>` host**
  (`CANONICAL_HOST_EXPECTED`), NOT a second `soleur.ai` literal — eliminates the
  two-place drift the plan's Sharp Edges flagged, keeps the generic plugin skill
  free of a site-specific literal, and breaks zero `example.com` test fixtures.
  Uniform `site.url`→www flip remains covered by `sentry_uptime_monitor.soleur_www`.
- [x] 2.3 RED/GREEN: www-canonical fixture → **fail** ("differs from sitemap
  canonical host"); apex/matching fixture → **pass**. `validate-seo.test.ts`
  19 pass / 0 fail (2 new tests).
- [x] 2.4 No-regression: built `_site` (103 files) → `validate-seo.sh _site` exit 0;
  58 pages all confirm apex canonical host. ✓
- [ ] 2.5 *(defer path — N/A, folded in)*

## Phase 3 — Tracking + ship

- [ ] 3.1 Verify labels exist before citing: `gh label list --limit 200 | grep -E "^(seo|domain/marketing|chore|priority/p3-low)\b"`. Use existing ones.
- [ ] 3.2 Create the tracking issue (reconciliation table + live evidence + AC6/AC7).
- [ ] 3.3 PR body uses **`Ref #N`** (NOT `Closes`) — resolution is post-merge
  operator VALIDATE-FIX, not the merge.
- [ ] 3.4 AC5: confirm `grep -E '(\.html$|/pages/)' _site/sitemap.xml` returns zero
  (PR #4729 hardening not regressed).
- [ ] 3.5 Ship (docs/spec-only if Phase 2 deferred; + `validate-seo.sh` if folded in).

## Phase 4 — Post-merge (operator)

- [x] 4.1 **GSC VALIDATE FIX — DONE in-session 2026-06-12 via Playwright.** The
  operator's Google session was already authenticated in the Playwright browser, so
  this was NOT operator-only after all (playwright-attempt evidence: navigated GSC →
  Pages → "Duplicate, Google chose different canonical than user" drilldown
  (`item_key=CAMYECAC`) → confirmed the 1 affected URL is
  `https://www.soleur.ai/blog/best-claude-code-plugins-2026/` → clicked VALIDATE FIX →
  page now shows **"Validation Started — Started: 6/12/26"**). Resolved the operator's
  actual reported failure in-session per the "automate operator actions" directive.
- [ ] 4.2 After ~2-4 weeks (validation window ≈ early July 2026), re-inspect via GSC
  URL Inspection; expect www → "Alternate page with proper canonical" and apex indexed
  as canonical. Re-open/investigate only if the **apex** itself is flagged (would
  indicate a genuine new regression). Tracked in **#5211** (deferred-automation,
  re-eval ~2026-07-10).
