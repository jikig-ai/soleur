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

- [ ] 0.1 Re-run live checks (re-verify at /work time; values captured 2026-06-12):
  - `curl -sI https://www.soleur.ai/blog/best-claude-code-plugins-2026/` → expect `301`, `location: https://soleur.ai/blog/best-claude-code-plugins-2026/`
  - `curl -sI https://soleur.ai/blog/best-claude-code-plugins-2026/` → expect `200`
  - `curl -s https://soleur.ai/blog/best-claude-code-plugins-2026/ | grep -oiE '<link rel="canonical"[^>]*>'` → expect apex href
- [ ] 0.2 Confirm `site.url == "https://soleur.ai"` (apex) in `plugins/soleur/docs/_data/site.json`.
- [ ] 0.3 Confirm PR #4729 hardening intact: `validate-seo.sh` retains the
  redirect-stub gate (~line 76) and canonical-host gate (~line 81+).

## Phase 1 — Outcome decision (no code)

- [ ] 1.1 Record the conclusion (benign `www→apex` consolidation; no code fix) in
  the tracking issue + this spec. This is the load-bearing deliverable.

## Phase 2 — OPTIONAL CI regression-hardening (fold-in OR defer)

- [ ] 2.1 **Decide:** fold-in (cheap, prevents future host-flip regression) vs.
  defer (scope discipline; file a tracking issue, ship zero code).
- [ ] 2.2 *(if fold-in)* Edit `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh`:
  after the per-page `rel="canonical"` presence check (~line 141), add a host-value
  assertion — fail if the canonical href host ≠ apex `soleur.ai`. Comment it as
  `mirror of _data/site.json site.url host`.
- [ ] 2.3 *(if fold-in)* RED/GREEN: run the gate on a www-canonical fixture (expect
  **fail**) and an apex fixture (expect **pass**).
- [ ] 2.4 *(if fold-in)* No-regression: `cd plugins/soleur/docs && npx @11ty/eleventy && bash ../skills/seo-aeo/scripts/validate-seo.sh _site` → all pass.
- [ ] 2.5 *(if defer)* File a `validate-seo` canonical-host-gate tracking issue with
  re-eval criteria ("after this GSC report validates green"); PR carries zero code.

## Phase 3 — Tracking + ship

- [ ] 3.1 Verify labels exist before citing: `gh label list --limit 200 | grep -E "^(seo|domain/marketing|chore|priority/p3-low)\b"`. Use existing ones.
- [ ] 3.2 Create the tracking issue (reconciliation table + live evidence + AC6/AC7).
- [ ] 3.3 PR body uses **`Ref #N`** (NOT `Closes`) — resolution is post-merge
  operator VALIDATE-FIX, not the merge.
- [ ] 3.4 AC5: confirm `grep -E '(\.html$|/pages/)' _site/sitemap.xml` returns zero
  (PR #4729 hardening not regressed).
- [ ] 3.5 Ship (docs/spec-only if Phase 2 deferred; + `validate-seo.sh` if folded in).

## Phase 4 — Post-merge (operator)

- [ ] 4.1 **GSC VALIDATE FIX** for `https://www.soleur.ai/blog/best-claude-code-plugins-2026/`
  (operator-only — no API, SSO/CAPTCHA-gated).
- [ ] 4.2 After ~2-4 weeks, re-inspect via GSC URL Inspection; expect www →
  "Alternate page with proper canonical" and apex indexed as canonical. Close the
  tracking issue when green; re-open with evidence only if the **apex** is flagged.
