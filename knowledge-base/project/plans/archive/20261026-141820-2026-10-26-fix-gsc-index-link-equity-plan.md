---
title: "fix(seo): connect pillar/cluster pages and still-unindexed URLs to the site's entry points"
type: fix
date: 2026-10-26
slug: fix-gsc-index-link-equity
branch: feat-one-shot-gsc-index-link-equity
issue: 8143
closes: [8143, 5616]
priority: p1-high
domain: marketing
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# fix(seo): connect pillar/cluster pages and still-unindexed URLs to the site's entry points

## Overview

Google Search Console rejected the "Validate Fix" submitted on 2026-09-20 for the "Crawled - currently not indexed" bucket: some pages remain affected. The established remediation for healthy pages in this bucket is internal-link equity, and the same root-cause class is already tracked by open issues #8143/#8144 (homepage and global nav pass zero links to 9 of 10 pillar/cluster pages) and #5616 (pillar/cluster interlinking). This plan implements the entry-point fix — a "Learn" dropdown in the global nav and a "Go deeper" link rail on the homepage — folds in the pillar/cluster mesh tightening, and adds scoped strengthening for the still-unindexed blog posts, while documenting what stays a non-goal and the GSC re-verification path.

> Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Research Insights

### Premise Validation (Phase 0.6)

Checked every cited reference; all held or were narrowed:

- **#8143** — OPEN, `priority/p1-high` + `type/chore` + `domain/marketing`. Prescription confirmed implementable: `base.njk:250-262` renders `item.children` (verified, and already in production use by the `Product` and `Company` dropdowns added since the audit).
- **#8144** — OPEN, same labels + `scheduled-growth-audit`. Near-verbatim duplicate of #8143 (same 2026-09-14 growth audit, same fix). Stricter AC: "Each of the ten pages is reachable from the global nav on every page" — requires all ten in the dropdown, not the five the fix sketch lists.
- **#5616** — OPEN, `priority/p1-high`. Premise partially drifted but still live: `compare-soleur-vs-cursor.njk:26` and `compare-soleur-vs-devin.njk:26` already link the pillar (`/company-as-a-service/`), but the pillar has zero `/compare/` forward-links and the compare pages have no sibling cross-links. `agentic-engineering.njk` already links its cluster set (`/skills/`, `/glossary/`, `/claude-code-plugins/`, `/ai-agents-for-solo-founders/`, `/company-as-a-service/`) — AC item is verify-only.
- **#8332** — CLOSED (the prior re-verify tracker). The 2026-09-20 "Validate Fix" it tracked is what Google rejected; this plan Refs it, does not reopen it.
- **#3328 remediation** — shipped (46 edge 301s via `apps/web-platform/infra/seo-bulk-redirects.tf`, meta-refresh machinery deleted). `scripts/followthroughs/gsc-indexing-drain-8332.sh` run 2026-10-26: 124 checks, 0 failures.
- **Audit drift found:** the 2026-09-14 audit said the homepage links exactly five internal destinations; today `index.njk:45` also links `/compare/soleur-vs-cursor/`, and the nav has grown `Product`/`Company` dropdowns. Core premise intact: 9 of 10 pillar/cluster pages still have zero inbound links from nav and homepage.
- **No ADR conflict:** the mechanism (data-only nav children + content links) has no entry in `knowledge-base/engineering/architecture/decisions/`.

### Property List (Phase 0.6b)

- P1 — every pillar/cluster page has ≥1 inbound link from the global nav (rendered site-wide) and/or the homepage.
- P2 — pillar↔cluster mesh tightened: `/company-as-a-service/` forward-links its comparison cluster; each `/compare/` page declares the pillar and links one sibling.
- P3 — the three still-unindexed blog posts (`/blog/soleur-vs-polsia/`, `/blog/why-most-agentic-tools-plateau/`, `/blog/ai-agents-for-solo-founders/`) gain inbound links from the site's highest-authority page.
- P4 — the link-equity property is regression-guarded so a future pillar page cannot ship unreachable.
- P5 — acceptance is link-graph/structure change only; index state is Google-controlled and is re-verified via a documented path, never promised.

### Cut List (Phase 0.6b)

- `llms.txt` coverage of the same ten pages → cut; separate tracked surface (#7181), different mechanism (crawler directive vs link equity). Ref only.
- Additional link equity for `/legal/gdpr-policy/` and `/legal/data-protection-disclosure/` → cut; both already carry a site-wide footer link (`site.json` `footerLegal`), so the marginal lever is spent — their continued non-indexing is a thin-content/quality call no link edit fixes. Documented non-goal.
- New template logic for nav → cut; `base.njk:250-262` already renders `children` (the property the mechanism needs is already bought).

### Relevant paths

- `plugins/soleur/docs/_data/site.json` — `nav` array (`:16-30`), `footerColumns` (`:59-82`), `footerLegal`
- `plugins/soleur/docs/_includes/base.njk` — nav `children` render block `:250-262`; critical-CSS block already lists `.nav-has-children, .nav-dropdown*, .nav-submenu*` (`:119`)
- `plugins/soleur/docs/index.njk` — `#soleur-vs-copilots` section ends `:191`; FAQ section follows; existing internal links: `/compare/soleur-vs-cursor/` (`:45`), `/agents/` + `/skills/` (`:57,:61`), `/getting-started/`, `/legal/privacy-policy/`, `/pricing/`
- `plugins/soleur/docs/pages/{company-as-a-service,agentic-engineering,glossary,claude-code-plugins,ai-agents-for-solo-founders,solo-founder-ai-stack,ai-cto,ai-cmo,compare-soleur-vs-cursor,compare-soleur-vs-devin}.njk` — the ten pillar/cluster pages
- `plugins/soleur/docs/_data/pillars.js` + `plugins/soleur/docs/_includes/pillar-series.njk` — blog pillar-series data + renderer
- `plugins/soleur/docs/scripts/{screenshot-gate.mjs,screenshot-gate-routes.json,check-critical-css-coverage.mjs}` — the `cq-eleventy-critical-css-screenshot-gate` machinery (`/` already an audited route)
- `plugins/soleur/test/seo-aeo-drift-guard.test.ts` — existing bun:test drift-guard that already builds the site (`npx @11ty/eleventy`) and reads `site.json` + `index.njk`; natural home for the link-graph assertions
- `plugins/soleur/docs/package.json` — `docs:build` = `cd ../../../ && npx @11ty/eleventy` (eleventy.config.js at repo root)
- `scripts/followthroughs/gsc-indexing-drain-8332.sh` — post-deploy URL-health probe (edge 301s + the five pages 200/self-canonical/no-meta-refresh)

### Institutional learnings applied

- `2026-06-15-gsc-crawled-not-indexed-remediation-is-internal-linking.md` — on healthy pages the bucket is Google's discretionary quality call; internal-link equity is the only in-repo lever.
- `2026-07-06-gsc-coverage-report-is-playwright-pullable-after-operator-signin.md` — coverage data has no API; re-verification is an operator-sign-in dashboard step (Playwright-pullable after sign-in).
- `knowledge-base/project/specs/archive/20260919-113408-feat-one-shot-3328-gsc-indexing-cleanup/gsc-evidence.md` — the 11-URL bucket inventory (5 healthy pages + 6 stale variants).

### Community / external research

- Community Discovery (1.5): no uncovered stacks (Eleventy/Nunjucks docs site; no signature-file matches). Skipped.
- Functional Overlap (1.5b): no spawn capability in this planning subagent; the feature is a data+content edit to our own docs site — no plausible community-artifact overlap. Noted, not spawned.
- External research (1.6): skipped — strong local context, prescribed fix already written in #8143/#8144, established remediation documented.

## Open Code-Review Overlap

None — queried open `code-review`-labeled issues for all seven planned file paths; zero body matches (checked 2026-10-26).

## Deepen Pass

**Deepened on:** 2026-10-26 | **Mode:** in-process, `Reviewed-Coverage: sequential-fallback` — the planning subagent has no Task-spawn capability; every halt gate was executed mechanically in-shell and the agent fan-out (skills/learnings/review/research agents) was replaced by a planner self-review plus the standing checks below. The residual is recorded in `knowledge-base/project/specs/feat-one-shot-gsc-index-link-equity/decision-challenges.md`.

### Halt-gate verdicts (all executed against the file)

- **4.6 User-Brand Impact:** PASS — section present, threshold `aggregate pattern` (valid enum), decision line present.
- **4.7 Observability:** PASS — all 5 fields populated, no placeholders; `discoverability_test.command` = `grep -o …` (allowlisted verb, no `ssh`, sub-second, non-suite); `expected_output` = literal `company-as-a-service/`.
- **4.8 PAT-shaped variables:** PASS — zero matches on the four-pattern regex.
- **4.9 UI-wireframe artifact:** PASS — `knowledge-base/product/design/marketing/learn-nav-go-deeper-rail.pen` referenced and committed (`git ls-files --error-unmatch` verified).
- **4.10 Encryption Posture:** N/A — no `.tf`/SQL/cloud-init/compose file, no new store or connection.
- **4.11 Guard Contract:** PASS — `python3 scripts/lint-guard-contract.py` green (2 guard entries); Assembly is structural (two emitting surfaces + a `pages/**` census), matrices are design-derived with dispatch, second-member, and must-PASS rows.
- **4.12 Scope Check:** PASS — exactly one unfenced `## Scope Check`, all three subsections present, zero `unmapped`/`status: BLOCKED` rows, every `inferred` item justified, `Recommendation: single PR` present.
- **4.13 Task Design:** N/A — no new autonomous-task surface (the tracking issue is a GitHub issue, not a registered task).
- **4.4 Precedent-diff:** precedents exist and are used — `Product`/`Company` `children` blocks in `site.json` (same mechanism), `seo-aeo-drift-guard.test.ts`'s built-site assertions (same harness the guard extends), and `pillar-series.njk`/related-links blocks for the mesh notes. Not novel.
- **4.45 Verify-the-negative:** negative claims re-verified — nav contains zero links to the ten pillar/cluster URLs (site.json `nav` enumerated); `/goal-primitive/` has zero inbound references site-wide; `/glossary/` is footer-only (footerColumns). No contradiction found.
- **4.5 Network-outage / 4.55 Downtime-cutover:** no trigger — static docs site, Cloudflare Pages deploy, no host/DB/router operation.
- **Citations:** rule IDs cited (`cq-eleventy-critical-css-screenshot-gate`, `cq-write-failing-tests-before`, `wg-ui-feature-requires-pen-wireframe`) verified ACTIVE; issues #8143/#8144/#5616/#7181 verified OPEN, #8332 CLOSED, #3328 merged — all via `gh` this session.

### Additional learning folded

- `2026-10-21-a-remove-the-link-control-cannot-red-a-basename-substring-census.md` (`cq-assert-anchor-not-bare-token`): a census keyed on bare-basename substring cannot be driven RED. Guards 1+2 therefore assert **anchored `href="/x/"` / `href="https://soleur.ai/x/"` forms on built HTML**, never bare URL tokens — the discipline is load-bearing for the mutation matrix to mean anything.
- `2026-05-05-gsc-indexing-triage-patterns.md`: GSC exports are aggregate-only — consistent with the premise that the validation email does not enumerate URLs; the bucket is re-read only via the operator-sign-in dashboard path.

### Key improvements from the pass

1. `/goal-primitive/` found unreachable (zero inbound links) by the census reasoning — added to the rail and to the guard's classification contract.
2. Guard Contract hardened: census-over-`pages/**` (unclassified bucket goes RED) + anchored-href assertions per the basename-substring learning.
3. AC split into `Pre-merge (PR)` / `Post-merge (operator)` (sharp-edge #2226); PR-body intent routed through `decision-challenges.md` since `soleur:ship` authors the body (sharp-edge #5984).

## Problem Statement / Motivation

On 2026-10-26 Google Search Console replied to the 2026-09-20 "Validate Fix" request for the "Crawled - currently not indexed" bucket: some pages are still affected. The bucket's five healthy live URLs (`/blog/soleur-vs-polsia/`, `/blog/why-most-agentic-tools-plateau/`, `/blog/ai-agents-for-solo-founders/`, `/legal/gdpr-policy/`, `/legal/data-protection-disclosure/`) serve 200, are self-canonical, carry no meta-refresh — verified 2026-10-26 by `scripts/followthroughs/gsc-indexing-drain-8332.sh` (124 checks, 0 failures). Per `knowledge-base/project/learnings/2026-06-15-gsc-crawled-not-indexed-remediation-is-internal-linking.md`, on healthy pages this bucket is Google's discretionary quality call and the only in-repo lever is internal-link equity.

The same root-cause class is already open work: nine of the site's ten pillar/cluster pages have zero inbound links from the homepage and zero from the global nav (#8143/#8144, both `priority/p1-high`), and the pillar↔cluster mesh has gaps (#5616). The pages Google declines to index sit inside exactly this weak-equity region of the link graph. Index state itself is Google-controlled and lags — this plan changes the link graph and documents the re-verification path; it does not promise index-state outcomes.

## Proposed Solution

Three coordinated edits, all inside `plugins/soleur/docs/` plus one test extension:

1. **Entry-point links (P1).** (a) Add a `Learn` dropdown to `site.nav` in `plugins/soleur/docs/_data/site.json` with all ten pillar/cluster pages as `children` — data-only, `base.njk:250-262` already renders `children` (in production use by `Product`/`Company`). (b) Add a `Go deeper` link rail section to `plugins/soleur/docs/index.njk` after `#soleur-vs-copilots` (`:183-191`), before the FAQ section — grouped descriptive links covering all ten pages.
2. **Pillar↔cluster mesh (P2, #5616).** Add the "pillar page" declaration with forward-links on `company-as-a-service.njk`; add pillar-declaration + sibling cross-links on `compare-soleur-vs-cursor.njk` and `compare-soleur-vs-devin.njk`; verify `agentic-engineering.njk` cluster links (already present — record outcome).
3. **Scoped strengthening for the still-unindexed posts (P3).** A `From the blog` group in the same homepage rail links `/blog/soleur-vs-polsia/`, `/blog/why-most-agentic-tools-plateau/`, and `/blog/ai-agents-for-solo-founders/` — the three unindexed blog URLs — giving them a direct inbound link from the site's highest-authority page. The rail's `Guides` group also links `/goal-primitive/` — a docs page the census found with **zero** inbound links anywhere on the site (same failure class, found while planning).
4. **Regression guard (P4).** Extend `plugins/soleur/test/seo-aeo-drift-guard.test.ts` with link-graph assertions over the built `_site/` output — including a census over `plugins/soleur/docs/pages/` so a future unreachable page cannot slip past a pinned name list — and so the mesh cannot silently regress.

Wireframe (generated during planning via authenticated Pencil CLI): `knowledge-base/product/design/marketing/learn-nav-go-deeper-rail.pen` — two frames: the `Learn` nav dropdown and the `Go deeper` rail layout.

## Implementation Phases

### Phase 1 — Failing guard assertions first

Extend `plugins/soleur/test/seo-aeo-drift-guard.test.ts` with a new `describe` block (see Guard Contract): entry-point coverage over the `PILLAR_CLUSTER` registry (10 URLs) and the pillar↔cluster mesh assertions. Run `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts` — expected RED on the new assertions (per `cq-write-failing-tests-before`).

### Phase 2 — Entry-point links

1. `site.json`: insert `{ "label": "Learn", "children": [...] }` into `nav` after the `Product` item, with all ten children:

```json
{ "label": "Learn", "children": [
  { "label": "Company-as-a-Service", "url": "/company-as-a-service/" },
  { "label": "Agentic Engineering", "url": "/agentic-engineering/" },
  { "label": "Glossary", "url": "/glossary/" },
  { "label": "Claude Code Plugins", "url": "/claude-code-plugins/" },
  { "label": "AI Agents for Solo Founders", "url": "/ai-agents-for-solo-founders/" },
  { "label": "Solo Founder AI Stack", "url": "/solo-founder-ai-stack/" },
  { "label": "AI CTO", "url": "/ai-cto/" },
  { "label": "AI CMO", "url": "/ai-cmo/" },
  { "label": "Soleur vs Cursor", "url": "/compare/soleur-vs-cursor/" },
  { "label": "Soleur vs Devin", "url": "/compare/soleur-vs-devin/" }
] }
```

(Ten children, not the five sketched in the issues — #8144's AC requires each of the ten reachable from the global nav. Deviation noted in decision-challenges.md.)

2. `index.njk`: add `<section class="landing-section" id="go-deeper">` after the `#soleur-vs-copilots` `</section>` (`:191`), mirroring the sibling section structure (`<div class="landing-section-inner">` wrapper, `section-label` + `section-title` + `section-desc`). Structure per the wireframe: three grouped columns — **Pillars** (`/company-as-a-service/`, `/agentic-engineering/`), **Guides** (`/ai-agents-for-solo-founders/`, `/solo-founder-ai-stack/`, `/ai-cto/`, `/ai-cmo/`, `/claude-code-plugins/`, `/glossary/`, `/goal-primitive/`), **Comparisons** (`/compare/soleur-vs-cursor/`, `/compare/soleur-vs-devin/`) — plus a `From the blog` group linking the three unindexed posts. Reuse existing classes (`landing-section`, `section-label`, `section-title`, `feature-grid`-style card markup already on the page); every anchor uses descriptive text with a one-line description — no generic link text. Any new class must be below-the-fold-safe or added to the critical-CSS block (see AC).

### Phase 3 — Pillar/cluster mesh (#5616)

1. `pages/company-as-a-service.njk`: add a "pillar page" note (natural placement: end of the intro or the existing related-links block ~`:186`) — "This is the pillar page for our Company-as-a-Service series" — forward-linking `/compare/soleur-vs-cursor/`, `/compare/soleur-vs-devin/`, and the use-case cluster `/ai-agents-for-solo-founders/`, `/solo-founder-ai-stack/`.
2. `pages/compare-soleur-vs-cursor.njk`: add a declaration line — "Part of the [Company-as-a-Service](/company-as-a-service/) series" — plus a sibling link to `/compare/soleur-vs-devin/` (pillar back-link already present at `:26`; keep and add the explicit declaration).
3. `pages/compare-soleur-vs-devin.njk`: mirror — declaration + sibling link to `/compare/soleur-vs-cursor/`.
4. `pages/agentic-engineering.njk`: verify it links `/skills/`, `/agents/` or `/glossary/` cluster members — it already links `/skills/`, `/glossary/`, `/claude-code-plugins/`, `/ai-agents-for-solo-founders/`, `/company-as-a-service/` (`:27,:122,:132,:170-173`); record the verification outcome in the PR body. Edit only if a gap is found.

### Phase 4 — Verify

`npx @11ty/eleventy` build green; `node plugins/soleur/docs/scripts/check-critical-css-coverage.mjs` green; `node plugins/soleur/docs/scripts/screenshot-gate.mjs` green (CI; local run needs Playwright); `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts` green; grep the built `_site/` for the new hrefs.

### Phase 5 — Tracking + PR wiring

File the post-deploy re-verification tracking issue (see GSC Re-Verification Path). The durable intent for the PR body lives in `knowledge-base/project/specs/feat-one-shot-gsc-index-link-equity/decision-challenges.md` (which `soleur:ship` folds into the body it authors): `Closes #8143`, `Closes #5616`, `Ref #8144` + a duplicate-of comment posted on #8144 naming #8143, `Ref #8332`, `Ref #7181`. No index-state issue is closed — Ref only.

## Files to Edit

- `plugins/soleur/docs/_data/site.json` — `nav` gains the `Learn` children block (data-only).
- `plugins/soleur/docs/index.njk` — new `#go-deeper` rail section after `:191`.
- `plugins/soleur/docs/pages/company-as-a-service.njk` — pillar-series declaration + forward links.
- `plugins/soleur/docs/pages/compare-soleur-vs-cursor.njk` — pillar declaration + sibling link.
- `plugins/soleur/docs/pages/compare-soleur-vs-devin.njk` — pillar declaration + sibling link.
- `plugins/soleur/docs/pages/agentic-engineering.njk` — verify-only; edit only if the cluster audit finds a gap.
- `plugins/soleur/test/seo-aeo-drift-guard.test.ts` — new describe block (link-graph guard).

## Files to Create

- `knowledge-base/product/design/marketing/learn-nav-go-deeper-rail.pen` — wireframe (already produced in this planning session).

## Non-Goals

- **Index-state outcomes.** Google's discretionary index decision is not a deliverable; acceptance is link-graph structure + a documented re-verify path (Ref, not Closes, on index-state issues).
- **`llms.txt` coverage of the ten pages** — tracked separately as #7181 (crawler-directive surface, different mechanism).
- **`/legal/gdpr-policy/` + `/legal/data-protection-disclosure/` extra equity** — both already carry a site-wide `footerLegal` link; the marginal link lever is spent and their non-indexing is a thin-content call no nav edit fixes.
- **Stale-variant URLs** (www., legacy `.html`, `feed.xml` shapes) — already remediated by #3328 edge 301s; drain script green.
- **New template logic** — no `base.njk` changes; `children` rendering exists.
- **Content changes to the pages themselves** — links and a declaration note only; no copy rewrites.

## Technical Considerations

- **Nav weight:** a sixth top-level item with a 10-row dropdown. `base.njk:157-158` CSS handles the submenu on desktop (absolute, hover/focus-within) and mobile (stacked, `:158`); no new selectors needed for the dropdown itself — `.nav-has-children`/`.nav-submenu*` are already in the critical-CSS block (`:119`).
- **Anchor-href forms:** docs templates mix root-relative `href="/x/"` and `{{ site.url }}/x/` forms. The guard asserts on **built `_site/` HTML** (where `{{ site.url }}` resolves), accepting both `href="/x/"` and `href="https://soleur.ai/x/"` — never on raw `.njk` source.
- **No architectural decision** — a data + content edit on an existing surface; no ADR/C4 deliverable (Phase 2.10 skip: no ownership/substrate/trust-boundary change; a competent engineer reading the ADR corpus is not misled after this ships).
- **NFR:** none of the `nfr-register.md` axes are moved (static-site content; no latency/auth/data-safety impact).

## User-Brand Impact

- **If this lands broken, the user experiences:** a broken or mis-linked global nav dropdown, or a malformed homepage section — visible on every page of soleur.ai (the site's front door), e.g. dead links or a layout regression.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — the diff is public marketing-site markup only; worst case is a public-facing cosmetic defect, not a data/workflow breach.
- **Brand-survival threshold:** `aggregate pattern` — a broken nav harms many visitors' first impression cumulatively; no single user's data/workflow/money is at stake.
- **Threshold decision (challengeable):** `aggregate pattern`, not `single-user incident` — there is no per-user breach surface; not `none` because the diff touches the public site's chrome on every page.

## Observability

```yaml
liveness_signal:
  what: "Eleventy build + critical-CSS coverage check + screenshot-gate job on the docs site; Cloudflare Pages deploy status for soleur.ai"
  cadence: "per-PR (ci.yml) and per-deploy (deploy-docs.yml)"
  alert_target: "GitHub required-check failure on the PR / failed deploy-docs run"
  configured_in: ".github/workflows/ci.yml (npx @11ty/eleventy, check-critical-css-coverage.mjs, screenshot-gate.mjs jobs ~:2441-2482) and .github/workflows/deploy-docs.yml"

error_reporting:
  destination: "GitHub Actions check failure (annotated on the PR); screenshot-gate failures uploaded as the screenshot-gate-failures-pr artifact"
  fail_loud: "non-zero exit from check-critical-css-coverage.mjs / screenshot-gate.mjs / seo-aeo-drift-guard.test.ts; a malformed site.json fails the eleventy build"

failure_modes:
  - mode: "site.json nav edit is invalid JSON or wrong shape"
    detection: "npx @11ty/eleventy build fails in CI"
    alert_route: "PR required-check red"
  - mode: "new above-the-fold selector without critical-CSS coverage (nav/rail regression)"
    detection: "check-critical-css-coverage.mjs + screenshot-gate.mjs FOUC diff on audited routes (incl. /)"
    alert_route: "PR required-check red + failure screenshots artifact"
  - mode: "pillar/cluster page loses its entry-point link (future regression)"
    detection: "seo-aeo-drift-guard.test.ts link-graph assertions (built-site href census)"
    alert_route: "bun test failure in CI"
  - mode: "typo'd or dead internal href in nav/rail"
    detection: "the same drift-guard assertions match exact built hrefs — a typo'd link fails presence; registry URLs are asserted to have a built page"
    alert_route: "bun test failure in CI"
  - mode: "deployed soleur.ai loses the new links post-deploy"
    detection: "discoverability_test below + scheduled growth-audit sweeps"
    alert_route: "preflight Check 10 / audit issue filing"

logs:
  where: "GitHub Actions run logs (ci.yml, deploy-docs.yml); Cloudflare Pages deploy log"
  retention: "GitHub default (~90 days)"

discoverability_test:
  command: "grep -o 'company-as-a-service/' plugins/soleur/docs/_data/site.json plugins/soleur/docs/index.njk"
  expected_output: "company-as-a-service/"
```

No soak-gated AC and no new autonomous task — the GSC bucket drains on Google's schedule and coverage has no API (see GSC Re-Verification Path); Phase 2.9.1/2.9.3 do not fire.

## Guard Contract

### Guard 1 — pillar/cluster entry-point coverage (in `seo-aeo-drift-guard.test.ts`)

**Property.** Every URL in the pillar/cluster registry is reachable from the rendered global nav (the `<ul class="nav-links">` subtree, present on every built page) or the rendered homepage body — footer links do not count.

**Assembly.** Two emitting surfaces, asserted on built `_site/` output: `_data/site.json`'s `nav` subtree rendered into every page's `nav-links` block by `base.njk` (sample a non-homepage page, e.g. `_site/pricing/index.html`, to prove site-wide rendering), and `index.njk`'s body links (`_site/index.html` minus the footer region). The registry is a `PILLAR_CLUSTER` constant in the test quantifying over the ten `plugins/soleur/docs/pages/` pillar/cluster URLs; an anti-vacuity assertion requires `PILLAR_CLUSTER.length >= 10` and that every registry URL resolves to a built page. **Census, not just a floor (sharp-edge #8097):** the test also globs `plugins/soleur/docs/pages/**/*.{njk,md}` (recursing into `pages/legal/`); every file must be classified — a member of `PILLAR_CLUSTER`, a member of the named `CHROME` allowlist (nav/footer destinations: `about`, `agents`, `skills`, `pricing`, `getting-started`, `blog`, `changelog`, `community`, `vision`, `legal`, `legal/*`, `known-external-tools`; `index.njk`/`404.njk`/root templates live outside the census glob), or individually exempted with a reason in the test — else RED. `/goal-primitive/` is already unreachable today; this plan links it from the rail and classifies it `PILLAR_CLUSTER`-adjacent (linked, not chrome).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Remove the `Learn` `children` array from `site.json` nav (rail kept) → nav-only pages lose entry coverage | RED |
| 2 | Delete the `#go-deeper` rail from `index.njk` (nav kept) → homepage-only members fail | RED |
| 3 | Empty `PILLAR_CLUSTER` to zero members (guard's own dispatch) | RED |
| 4 | Add a new `pages/foo.njk` page in neither `PILLAR_CLUSTER` nor `CHROME` (a second member after a compliant first — an unclassified page the census must flag) | RED |
| 5 | Typo one registry URL (`/compnay-as-a-service/`) — built pages never contain it | RED |
| 6 | Harness must-PASS: a member linked only from the homepage body (not nav) — satisfies the property's nav-OR-homepage arm | PASS |

### Guard 2 — pillar/cluster mesh (same file)

**Property.** `/company-as-a-service/` forward-links both `/compare/` pages; each `/compare/` page links the pillar and its sibling; `/agentic-engineering/` links its cluster set.

**Assembly.** Built output of `_site/company-as-a-service/index.html`, `_site/compare/soleur-vs-cursor/index.html`, `_site/compare/soleur-vs-devin/index.html`, `_site/agentic-engineering/index.html` — per-page href presence, asserted per member (an aggregate count cannot express the per-member property).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Remove the forward-link block from `company-as-a-service.njk` | RED |
| 2 | Remove the sibling link from exactly one compare page, leave the other intact — per-member check must isolate it | RED |
| 3 | Point a compare page's pillar link at a different URL (`/about/`) | RED |
| 4 | Harness must-PASS: sibling link written as `{{ site.url }}/compare/...` (absolute form) — built-output assertion accepts both href forms | PASS |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "I got this from GSC, can you please review and fix — 'Some fixes failed for Page indexing issues ... "Crawled - currently not indexed". Some of your pages are still affected by this issue.'" [brief] | Phases 1-4 (the full link-equity fix) | mapped |
| 2 | "primarily implementing #8143/#8144 (nav "Learn" menu + homepage link rail connecting the 9-10 pillar/cluster pages to the site's highest-authority page)" [brief] | Phase 2 (site.json Learn dropdown + index.njk rail) | mapped |
| 3 | "decide whether any additional scoped strengthening for the 5 known unindexed pages or #5616 belongs in this PR vs documented non-goals" [brief] | Phase 3 (#5616 fold-in), Phase 2 `From the blog` group (3 unindexed posts), Non-Goals (legal pages, llms.txt) | mapped |
| 4 | "a plan that MUST declare an Observability block per repo convention and a Test Scenarios section" [brief] | `## Observability`, `## Test Scenarios` | mapped |
| 5 | "Do NOT promise index state changes ... frame acceptance as link-graph/structure changes + a documented GSC re-verify path (Ref, not Closes, on index-state issues)" [brief] | P5, `## GSC Re-Verification Path`, Phase 5 PR-body wiring | mapped |
| 6 | "Every pillar/cluster page is reachable from / in one click, or from the global nav on any page." [#8143 AC] | Phase 2 both edits | mapped |
| 7 | "Each of the ten pages is reachable from the global nav on every page." [#8144 AC] | Learn dropdown with all ten children | mapped |
| 8 | "/glossary/ has at least one non-footer inbound link." [#8143 AC] | Learn dropdown + rail `Guides` group | mapped |
| 9 | "Anchor text is descriptive; no generic link text introduced." [#8143/#8144 AC] | Phase 2 copy spec + AC | mapped |
| 10 | "Any new above-the-fold selector is added to the critical-CSS block in base.njk and covered by screenshot-gate.mjs" [#8143/#8144 AC] | AC + Test Scenarios | mapped |
| 11 | "Add a 'This is the pillar page for our Company-as-a-Service series' note ... linking the comparison + use-case clusters." [#5616 AC] | Phase 3 item 1 | mapped |
| 12 | "Each /compare/soleur-vs-* page links back to the pillar plus one sibling comparison." [#5616 AC] | Phase 3 items 2-3 | mapped |
| 13 | "Verify the /agentic-engineering/ pillar links to its /skills/, /agents/, /glossary/ clusters." [#5616 AC] | Phase 3 item 4 | mapped |
| 14 | "Build passes; no broken internal links." [#8143/#8144/#5616 AC] | Phase 4 + AC | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Learn dropdown in `site.json` | "nav \"Learn\" menu" [brief]; "add a Learn dropdown to nav" [#8143] | asked |
| `Go deeper` rail in `index.njk` | "homepage link rail" [brief]; "add a \"Go deeper\" rail" [#8143] | asked |
| Pillar note + compare back-links | "pillar forward links + /compare/ back-links" [#5616 title] | asked |
| `From the blog` rail group (3 unindexed posts) | "any additional scoped strengthening for the 5 known unindexed pages" [brief] | asked |
| `seo-aeo-drift-guard.test.ts` extension | "a documented GSC re-verify path" + "link-graph/structure changes" [brief] | inferred — justification: without the drift-guard the link-graph property the fix ships has no regression protection (P4), and the precedent failure mode (a new pillar page shipping unlinked) is exactly what produced #8143 |
| Tracking issue for post-deploy GSC re-pull | "a documented GSC re-verify path" [brief] | asked |
| `.pen` wireframe | — | inferred — justification: `wg-ui-feature-requires-pen-wireframe` — the plan edits `*.njk` UI surfaces (nav chrome + homepage section) so a committed wireframe is mandatory on the pipeline path |
| Ten (not five) dropdown children | "Each of the ten pages is reachable from the global nav on every page." [#8144 AC] | asked |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur` (plus `knowledge-base/` artifacts)
- Planned files: 7 source files | Estimated changed lines: ~250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `site.nav` in `plugins/soleur/docs/_data/site.json` contains a `Learn` item whose `children` list all ten pillar/cluster URLs; the rendered nav on a non-homepage page (built `_site/pricing/index.html` or equivalent) contains `href="/company-as-a-service/"`.
- [ ] `index.njk` renders a `#go-deeper` section whose anchors cover all ten pillar/cluster URLs, `/goal-primitive/`, and the three unindexed blog URLs.
- [ ] `/glossary/` has at least one non-footer inbound link.
- [ ] Built `_site/company-as-a-service/index.html` links `/compare/soleur-vs-cursor/` and `/compare/soleur-vs-devin/`; each built `/compare/` page links `/company-as-a-service/` and its sibling comparison.
- [ ] `/agentic-engineering/` cluster links verified (outcome recorded in PR body).
- [ ] Anchor text is descriptive: zero new occurrences of "click here", "read more", "learn more" in the diff (verified by grep on the built site).
- [ ] Any new above-the-fold selector is added to the critical-CSS block in `base.njk` and the route is covered by `screenshot-gate-routes.json` (`/` already audited); if no new above-fold selector is introduced, this is satisfied vacuously and recorded as such.
- [ ] `npx @11ty/eleventy` build passes; `node plugins/soleur/docs/scripts/check-critical-css-coverage.mjs` passes; `node plugins/soleur/docs/scripts/screenshot-gate.mjs` passes on the audited routes.
- [ ] `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts` is green with the new link-graph assertions, and the Guard Contract mutation rows were exercised (at least rows 1-3 driven RED during implementation).
- [ ] Post-deploy re-verification tracking issue filed; PR body carries `Closes #8143`, `Closes #5616`, `Ref #8144` (+ duplicate-of comment on #8144), `Ref #8332`, `Ref #7181`.
- [ ] Wireframe committed at `knowledge-base/product/design/marketing/learn-nav-go-deeper-rail.pen`.

### Post-merge (operator)

- [ ] After deploy, `bash scripts/followthroughs/gsc-indexing-drain-8332.sh` exits 0 (URL-health re-probe; automatable, no sign-in).
- [ ] Operator re-requests "Validate Fix" in GSC for the "Crawled - currently not indexed" bucket — dashboard step behind the operator's Google sign-in; no API exists (see GSC Re-Verification Path). Outcome is Google-controlled — recorded, not promised.

## Domain Review

**Domains relevant:** Marketing, Product

### Marketing

**Status:** deferred — no Task-spawn capability in this planning subagent; planner assessment inlined (a headless run cannot leave this unrecorded).
**Assessment:** The change is the marketing domain's own growth-audit prescription (#8143/#8144, `domain/marketing`). Nav labels match existing site voice; `Learn` is consistent with the `Product`/`Company` dropdown pattern already shipped. SEO direction is the established remediation for the bucket. No brand-voice or positioning concerns; CMO consult is recommended if the work phase can spawn it.

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface override — `## Files to Edit` matches `**/*.njk` + nav chrome on the shared term list)
**Decision:** reviewed (partial) — headless pipeline; wireframe produced in-process, specialist agents not spawnable from this subagent
**Agents invoked:** none — no Task capability in this run; the planner generated the `.pen` directly via the authenticated Pencil CLI (plan Phase 2.5's sole-producer requirement satisfied in-process)
**Skipped specialists:** soleur:product:spec-flow-analyzer, soleur:product:cpo — not spawnable in this run; recorded here rather than silently omitted. `soleur:product:design:ux-design-lead` is NOT skipped: its deliverable exists on disk.
**Pencil available:** yes (`pen` CLI authenticated as jean.deruelle@jikigai.com, Node v26.12.1)

#### Findings

- Wireframe: `knowledge-base/product/design/marketing/learn-nav-go-deeper-rail.pen` — Frame 1: global nav with the `Learn` dropdown (10 items, prescribed order); Frame 2: `Go deeper` rail (Pillars / Guides / Comparisons columns). Headless run — wireframes ready for async review, no pause.
- Self spec-flow check (in lieu of soleur:product:spec-flow-analyzer): the dropdown renders site-wide via `base.njk` `nav-links`; the rail is static descriptive links; no interactive flow, no error states, no dead ends — every link resolves to an existing built page.

## Test Scenarios

- **unit** — `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts`: Given the built `_site/` output, when the new describe block runs, then every `PILLAR_CLUSTER` URL is found in the nav subtree of a non-homepage page or the homepage body, and every mesh assertion (pillar forward-links, compare back/sibling links, agentic-engineering cluster) holds.
- **unit** — mutation exercise: Given the guard, when (a) the `Learn` children are removed, (b) the rail is deleted, (c) `PILLAR_CLUSTER` is emptied, then the suite goes RED (Guard Contract rows 1-3 executed during implementation, not just written).
- **integration** — `npx @11ty/eleventy` from repo root exits 0; `grep -o 'company-as-a-service/' _site/index.html _site/pricing/index.html` finds the nav/rail hrefs.
- **integration** — `node plugins/soleur/docs/scripts/check-critical-css-coverage.mjs` exits 0.
- **e2e** (`pyramid-justified: mandated by cq-eleventy-critical-css-screenshot-gate — the FOUC contract can only be observed in a rendered browser`) — `node plugins/soleur/docs/scripts/screenshot-gate.mjs` green on all audited routes including `/` (runs in CI Playwright container; local run optional).
- **e2e (post-deploy, non-blocking on index state)** — after merge+deploy: `bash scripts/followthroughs/gsc-indexing-drain-8332.sh` exits 0 (edge/page health), then the operator path in `## GSC Re-Verification Path`.

## GSC Re-Verification Path

Index state is Google-controlled and lags — this is a documented path, not an AC.

1. After merge, `deploy-docs.yml` deploys to soleur.ai (Cloudflare Pages).
2. Re-run `bash scripts/followthroughs/gsc-indexing-drain-8332.sh` — verifies the five bucket pages still serve 200 + self-canonical and all declared edge 301s hold.
3. Operator step (justified — GSC coverage has no API and sits behind the operator's Google sign-in; `knowledge-base/project/learnings/2026-07-06-gsc-coverage-report-is-playwright-pullable-after-operator-signin.md`): in GSC → Page indexing → "Crawled - currently not indexed", re-request "Validate Fix". Optionally re-pull the bucket via the documented Playwright-after-signin path to see which URLs remain.
4. During implementation, file the tracking issue `chore(gsc): post-deploy re-pull of "Crawled - currently not indexed" bucket after link-equity PR` (assignee: operator; refs this PR + the two learnings above) so the re-pull does not rot.

## Success Metrics

- Link-graph (this PR's contract): every pillar/cluster URL has ≥1 entry-point inbound link (nav and/or homepage); the three unindexed blog posts gain a homepage inbound link; the guard census is green.
- Directional (Google-controlled, not promised): the "Crawled - currently not indexed" bucket count declines on the next GSC re-pull after the validation request.

## Dependencies & Risks

- **Nav crowding** — a sixth top-level item + 10-row dropdown; desktop CSS handles it (`min-width:170px` submenu); mobile stacks it (`base.njk:158`). Watch the screenshot-gate diff.
- **Anchor-href form drift** — guard asserts on built output to neutralize `{{ site.url }}` vs root-relative forms.
- **#8144 duplicate handling** — closing it requires a duplicate-of comment naming #8143 (Phase 5).
- **Risk: none to production systems** — static marketing site; worst case is a reverted PR.

## References & Research

- Issues: #8143 (implemented), #8144 (duplicate of #8143 — close with comment), #5616 (folded in), #8332 (prior tracker, closed — Ref), #3328 (shipped remediation), #7181 (llms.txt — non-goal, Ref)
- Evidence: `knowledge-base/project/specs/archive/20260919-113408-feat-one-shot-3328-gsc-indexing-cleanup/gsc-evidence.md`
- Learnings: `knowledge-base/project/learnings/2026-06-15-gsc-crawled-not-indexed-remediation-is-internal-linking.md`, `knowledge-base/project/learnings/2026-07-06-gsc-coverage-report-is-playwright-pullable-after-operator-signin.md`
- Wireframe: `knowledge-base/product/design/marketing/learn-nav-go-deeper-rail.pen`
- Probe: `scripts/followthroughs/gsc-indexing-drain-8332.sh` (124 checks green, 2026-10-26)
