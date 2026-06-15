---
title: "Tasks — SEO internal-linking for 3 GSC crawled-not-indexed pages"
plan: knowledge-base/project/plans/2026-06-15-feat-gsc-seo-internal-linking-plan.md
lane: single-domain
date: 2026-06-15
---

# Tasks — SEO internal-linking for 3 GSC crawled-not-indexed pages

Derived from `2026-06-15-feat-gsc-seo-internal-linking-plan.md`. Read each file before
editing (`hr-always-read-a-file-before-editing-it`); locate anchors by quoted prose, not
by frozen line numbers.

## Phase 1 — Target 1: brand-guide case study (0 → 2 inbound)

- [ ] 1.1 Read `plugins/soleur/docs/blog/2026-05-14-how-to-run-every-department-with-ai-agents.md`; in the "## Marketing" section, link the existing phrase "reads your brand guide" to `{{ site.url }}/blog/case-study-brand-guide-creation/`.
- [ ] 1.2 Read `plugins/soleur/docs/blog/case-study-business-validation.md`; link the existing "brand guide('s positioning)" phrase (~line 39) to the brand-guide case study, matching the file's locally-dominant link style. If the bullet reads forced once linked, fall back per Phase 1 note (Link A only + one natural alternative).
- [ ] 1.3 Confirm neither edit double-links the slug and both anchors read naturally.

## Phase 2 — Target 2: agents-that-use-apis-not-browsers (1 → 2 inbound)

- [ ] 2.1 Read `plugins/soleur/docs/blog/2026-04-22-billion-dollar-solo-founder-stack.md`; in the "## Model Context Protocol (MCP)" paragraph, add a natural clause linking descriptive anchor text to `{{ site.url }}/blog/agents-that-use-apis-not-browsers/`.
- [ ] 2.2 Confirm the anchor is descriptive (not bare URL / "click here") and the file did not already link the slug.

## Phase 3 — Target 3: footer parity for Acceptable Use Policy

- [ ] 3.1 Read `plugins/soleur/docs/_data/site.json`; append `{ "label": "Acceptable Use", "url": "/legal/acceptable-use-policy/" }` to the `footerLegal` array (now 4 entries), matching sibling object shape and trailing-slash convention.
- [ ] 3.2 Confirm `_includes/base.njk` already iterates `site.footerLegal` (no template edit needed) and `pages/legal.njk` already links AUP (no index edit needed).

## Phase 4 — Verify build + validator + rendered output

- [ ] 4.1 Run `npx @11ty/eleventy` from the worktree repo root (handle the worktree `agents.js` gotcha per Sharp Edges — fall back to grep verification if the build hits a pre-existing path issue).
- [ ] 4.2 Run `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh plugins/soleur/docs/_site`; expect exit 0.
- [ ] 4.3 Rendered-output grep: `grep -rEoh 'https://soleur\.ai[a-zA-Z]' plugins/soleur/docs/_site/blog/` returns nothing (no host-mangled URLs); confirm the 3 expected built hrefs resolve.
- [ ] 4.4 Inbound-count delta: `grep -rl` shows Target 1 = 2 sources, Target 2 = 2 sources (+ self); footer has 4 legal entries.

## Phase 5 — Ship hygiene

- [ ] 5.1 `git diff --name-only` shows only the 4 edited files (+ plan + tasks); no infra/redirect/canonical/sitemap/CSS/template/version file touched.
- [ ] 5.2 PR body includes `## Changelog`; label `semver:patch`; use `Ref` (not `Closes`) for any GSC tracking issue.
