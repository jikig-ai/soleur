# Tasks — feat-one-shot-gsc-index-link-equity

Plan: `knowledge-base/project/plans/2026-10-26-fix-gsc-index-link-equity-plan.md`
Issues: Closes #8143, Closes #5616; #8144 duplicate-of #8144→#8143 comment; Ref #8332, Ref #7181.
Wireframe: `knowledge-base/product/design/marketing/learn-nav-go-deeper-rail.pen` (committed by planning phase).

## Phase 1 — Failing guard assertions first (RED)

- [x] 1.1 Extend `plugins/soleur/test/seo-aeo-drift-guard.test.ts` with a new describe block implementing Guard Contract Guards 1+2:
  - [x] 1.1.1 `PILLAR_CLUSTER` registry constant (the ten pillar/cluster URLs) + `CHROME` allowlist; anti-vacuity assertion `PILLAR_CLUSTER.length >= 10` and every registry URL resolves to a built page.
  - [x] 1.1.2 Entry-point assertions on built output: each registry URL appears in the `nav-links` subtree of a non-homepage built page (e.g. `_site/pricing/index.html`) OR in `_site/index.html` body links (footer excluded); both `href="/x/"` and `href="https://soleur.ai/x/"` forms accepted.
  - [x] 1.1.3 Census: glob `plugins/soleur/docs/pages/**/*.{njk,md}` — every file classified (registry / CHROME / individually exempted with reason) else RED.
  - [x] 1.1.4 Mesh assertions: built `_site/company-as-a-service/index.html` links both `/compare/` pages; each built `/compare/` page links the pillar + sibling; `_site/agentic-engineering/index.html` links its cluster set.
- [x] 1.2 Run `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts` — confirm the new assertions are RED (per `cq-write-failing-tests-before`).

## Phase 2 — Entry-point links

- [x] 2.1 `plugins/soleur/docs/_data/site.json`: insert `{ "label": "Learn", "children": [...] }` into `nav` after the `Product` item — all ten children in the order given in the plan.
- [x] 2.2 `plugins/soleur/docs/index.njk`: add `<section class="landing-section" id="go-deeper">` after `#soleur-vs-copilots` (`</section>` ~`:191`), mirroring sibling section structure (`.landing-section-inner` wrapper): Pillars / Guides / Comparisons columns + `From the blog` group — all ten pillar/cluster URLs + `/goal-primitive/` + the three unindexed blog URLs, descriptive anchors only.
- [x] 2.3 If any NEW above-the-fold selector is introduced, add it to the critical-CSS block in `base.njk` (existing `.nav-has-children`/`.nav-submenu*` already covered at `:119`); otherwise record the AC as vacuously satisfied.

## Phase 3 — Pillar/cluster mesh (#5616)

- [x] 3.1 `plugins/soleur/docs/pages/company-as-a-service.njk`: add "pillar page" declaration linking `/compare/soleur-vs-cursor/`, `/compare/soleur-vs-devin/`, `/ai-agents-for-solo-founders/`, `/solo-founder-ai-stack/` (placement: existing related-links block ~`:186`).
- [x] 3.2 `plugins/soleur/docs/pages/compare-soleur-vs-cursor.njk`: pillar-series declaration + sibling link to `/compare/soleur-vs-devin/` (existing pillar link at `:26` retained).
- [x] 3.3 `plugins/soleur/docs/pages/compare-soleur-vs-devin.njk`: mirror — declaration + sibling link to `/compare/soleur-vs-cursor/`.
- [x] 3.4 `plugins/soleur/docs/pages/agentic-engineering.njk`: verify cluster links (`/skills/`, `/glossary/`, `/claude-code-plugins/`, `/ai-agents-for-solo-founders/`, `/company-as-a-service/`); edit only on a real gap; record outcome for the PR body.

## Phase 4 — Verification

- [x] 4.1 `npx @11ty/eleventy` from repo root — green.
- [x] 4.2 `node plugins/soleur/docs/scripts/check-critical-css-coverage.mjs` — green.
- [x] 4.3 `node plugins/soleur/docs/scripts/screenshot-gate.mjs` — green on audited routes incl. `/` (CI; local run optional, needs Playwright).
- [x] 4.4 `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts` — green.
- [x] 4.5 Exercise Guard Contract mutation rows 1-3 (nav children removal / rail deletion / empty registry) — confirm RED each time, then restore.
- [x] 4.6 Grep built `_site/` for the new hrefs; grep the diff for "click here|read more|learn more" — zero hits.

## Phase 5 — Tracking + PR wiring

- [x] 5.1 File tracking issue: `chore(gsc): post-deploy re-pull of "Crawled - currently not indexed" bucket after link-equity PR` — refs this PR + the two learnings; assignee operator (GSC coverage has no API, dashboard behind Google sign-in).
- [x] 5.2 Post duplicate-of comment on #8144 naming #8143 (`gh issue comment 8144`).
- [x] 5.3 Confirm `decision-challenges.md` carries the PR-body intent (`Closes #8143`, `Closes #5616`, `Ref #8144`, `Ref #8332`, `Ref #7181`) for `soleur:ship` to fold in.

## Post-merge (operator, non-blocking)

- [x] 5.4 Re-run `bash scripts/followthroughs/gsc-indexing-drain-8332.sh` post-deploy (exit 0).
- [x] 5.5 Operator re-requests "Validate Fix" in GSC (sign-in gated); record outcome — Google-controlled, not promised.
