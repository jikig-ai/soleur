# Tasks — GSC internal-link equity for 3 unindexed blog pages

Plan: `knowledge-base/project/plans/2026-07-06-feat-gsc-internal-linking-equity-plan.md`
Lane: cross-domain (no spec.md `lane:` present — TR2 fail-closed default)

## Phase 1 — Add contextual internal links (edit prose only, use `{{ site.url }}/blog/<slug>/`)

For each: `grep -n '<exact phrase>' <file>` first; confirm present and NOT already linked.

- [ ] 1.1 `2026-03-31-soleur-vs-paperclip.md` — link **"fully autonomous by design"** → `/blog/soleur-vs-polsia/` (PROSE ~L134 only; do NOT touch JSON-LD ~L178)
- [ ] 1.2 `2026-05-12-company-as-a-service-platform.md` — link **"fully autonomous AI companies"** (~L62) → `/blog/soleur-vs-polsia/`
- [ ] 1.3 `2026-04-21-one-person-billion-dollar-company.md` — link **"Human-in-the-loop decision gates"** (~L86) → `/blog/soleur-vs-polsia/`
- [ ] 1.4 `2026-03-24-vibe-coding-vs-agentic-engineering.md` — link **"the same blank slate"** (~L49) → `/blog/your-ai-team-works-from-your-actual-codebase/`
- [ ] 1.5 `2026-03-24-ai-agents-for-solo-founders.md` — link **"start from a blank slate on each session"** (~L80) → `/blog/your-ai-team-works-from-your-actual-codebase/`
- [ ] 1.6 `2026-05-12-company-as-a-service-platform.md` — link **"a structural outcome of AI agents extending beyond engineering into every function a company needs"** (~L107, unlinked clause) → `/blog/billion-dollar-solo-founder-stack/`

## Phase 2 — Build + verify (blocking)

- [ ] 2.1 Fresh build: `npx @11ty/eleventy`
- [ ] 2.2 Locate build dir dynamically: `for d in _site plugins/soleur/docs/_site; do [ -d "$d/blog" ] && SITE="$d" && break; done`
- [ ] 2.3 Host-mangle grep MUST be empty: `grep -rEoh 'https://soleur\.ai[a-zA-Z]' "$SITE"/blog/`
- [ ] 2.4 If pre-existing host-mangle surfaces in untouched posts → fix inline (leading-slash), add file to plan §Files to Edit
- [ ] 2.5 Confirm 3 target absolute URLs present with new inbound counts ≥ (3, 2, 1)

## Phase 3 — Ship

- [ ] 3.1 PR body: `Ref` (not `Closes`) for any tracking issue + GSC diagnosis summary
- [ ] 3.2 Confirm no `noindex`/canonical/sitemap/frontmatter changes to target pages
