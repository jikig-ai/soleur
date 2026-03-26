# Tasks: SEO Meta Descriptions, Vision H1, Open-Source Copy

## Phase 1: Setup

- [ ] 1.1 Run `npm install` in worktree (docs build dependency)
- [ ] 1.2 Verify current site builds: `npx @11ty/eleventy` from docs directory

## Phase 2: Core Implementation

### Homepage (`plugins/soleur/docs/index.njk`)

- [ ] 2.1 Update frontmatter `description` to include "open-source" and remove redundant phrasing
- [ ] 2.2 Update hero sub-paragraph (line 11) to include "open-source" before "company-as-a-service platform"
- [ ] 2.3 Add "solopreneur" to "Who is Soleur for?" FAQ answer (line 164)
- [ ] 2.4 Update corresponding JSON-LD FAQ entry for "Who is Soleur for?" (around line 214)

### Getting Started (`plugins/soleur/docs/pages/getting-started.njk`)

- [ ] 2.5 Update frontmatter `description` to "Get started with Soleur in one command. Deploy AI agents across engineering, marketing, legal, finance, and every business department. Free and open source."

### Vision (`plugins/soleur/docs/pages/vision.njk`)

- [ ] 2.6 Update H1 from "Vision" to "The Soleur Vision: Company-as-a-Service for the Solo Founder"

## Phase 3: Verification

- [ ] 3.1 Build site with `npx @11ty/eleventy` -- verify exit code 0
- [ ] 3.2 Grep for "plugin" in updated meta descriptions -- verify zero matches
- [ ] 3.3 Grep for "open-source" in index.njk meta description -- verify match
- [ ] 3.4 Grep for "solopreneur" in index.njk -- verify match
- [ ] 3.5 Grep for "Company-as-a-Service" in vision.njk H1 -- verify match
- [ ] 3.6 Grep for "free and open source" in getting-started.njk description -- verify match
