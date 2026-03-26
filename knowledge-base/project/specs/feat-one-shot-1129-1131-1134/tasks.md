# Tasks: SEO Meta Descriptions, Vision H1, Open-Source Copy

## Phase 1: Setup

- [ ] 1.1 Run `npm install` in worktree (docs build dependency)
- [ ] 1.2 Verify current site builds: `npx @11ty/eleventy` from docs directory

## Phase 2: Core Implementation

### Homepage (`plugins/soleur/docs/index.njk`)

- [ ] 2.1 Update frontmatter `description` (line 3) to include "open-source" and "free" -- target 150-160 chars total. Do NOT hardcode agent counts (constitution line 79).
- [ ] 2.2 Update hero sub-paragraph (line 11) to include "open-source" before "company-as-a-service platform". Preserve `{{ stats.agents }}` and `{{ stats.departments }}` Nunjucks variables intact.
- [ ] 2.3 Add "solopreneur" to "Who is Soleur for?" FAQ answer (around line 164) -- natural context: "Solo founders and solopreneurs who refuse to accept..."
- [ ] 2.4 Update corresponding JSON-LD FAQ entry for "Who is Soleur for?" (around line 214) to match the visible FAQ answer text

### Getting Started (`plugins/soleur/docs/pages/getting-started.njk`)

- [ ] 2.5 Update frontmatter `description` (line 3) to "Get started with Soleur in one command. Deploy AI agents across engineering, marketing, legal, finance, and every business department. Free and open source." (156 chars)

### Vision (`plugins/soleur/docs/pages/vision.njk`)

- [ ] 2.6 Update H1 (line 10) from "Vision" to "The Soleur Vision: Company-as-a-Service for the Solo Founder" (60 chars)

## Phase 3: Verification

- [ ] 3.1 Build site with `npx @11ty/eleventy` -- verify exit code 0
- [ ] 3.2 Grep for "plugin" in updated meta descriptions (index.njk line 3, getting-started.njk line 3) -- verify zero matches
- [ ] 3.3 Grep for "open-source" in index.njk frontmatter description -- verify match
- [ ] 3.4 Grep for "solopreneur" in index.njk FAQ section -- verify match
- [ ] 3.5 Grep for "Company-as-a-Service" in vision.njk H1 -- verify match
- [ ] 3.6 Grep for "free and open source" in getting-started.njk frontmatter description -- verify match
- [ ] 3.7 Verify meta description character counts: index.njk between 150-160 chars, getting-started.njk between 150-160 chars
- [ ] 3.8 Verify Nunjucks variables in index.njk hero-sub paragraph still render (check `{{ stats.agents }}` present in source)
- [ ] 3.9 Verify index.njk JSON-LD "Who is Soleur for?" answer text matches the visible FAQ answer
- [ ] 3.10 Inspect `_site/index.html` built output to confirm `<meta name="description">` renders correctly
- [ ] 3.11 Inspect `_site/pages/vision.html` built output to confirm `<h1>` contains full keyword-rich heading
