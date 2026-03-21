# Tasks: Phase 0 Marketing Foundation + Phase 1 Article

## Phase 1: Keyword Vacuum Fixes (Deliverable 1)

### 1.1 Homepage H2 Keyword Injection

- [x] Read `plugins/soleur/docs/index.njk`
- [x] Rewrite Problem Section H2 to include "company-as-a-service" or target keyword
- [x] Rewrite Features Section H2 to include relevant keywords
- [x] Verify section labels remain decorative (no keyword changes needed)
- [x] Verify no brand guide violations in new H2 text

### 1.2 Agents Page Introductory Prose

- [x] Read `plugins/soleur/docs/pages/agents.njk`
- [x] Add 2-3 paragraph introduction after hero close and before category nav
- [x] Include keywords: "agentic engineering", "AI agents", "company-as-a-service", "cross-domain coherence"
- [x] Wrap in consistent styling section
- [x] Verify prose explains what the agents do, why 8 domains matter, and how they share context

### 1.3 Skills Page Introductory Prose

- [x] Read `plugins/soleur/docs/pages/skills.njk`
- [x] Add 2-3 paragraph introduction after hero close and before category nav
- [x] Include keywords: "agentic engineering", "compound engineering", "AI workflow skills"
- [x] Describe the brainstorm-plan-implement-review-compound lifecycle
- [x] Wrap in consistent styling section

## Phase 2: Pillar Article (Deliverable 2)

### 2.1 Article Structure and Outline

- [x] Define article outline following content strategy brief
- [x] Gather all external sources and statistics for GEO compliance
- [x] Verify source URLs are accessible

### 2.2 Write Article

- [x] Create `plugins/soleur/docs/blog/what-is-company-as-a-service.md`
- [x] Write YAML frontmatter (title, description, date, tags)
- [x] Write introduction with machine-readable definition in first 150 words
- [x] Write "The Problem CaaS Solves" section with statistics
- [x] Write "How CaaS Works" section with Soleur product specifics
- [x] Write "CaaS vs SaaS" comparison section
- [x] Write "The Technology Behind CaaS" section
- [x] Write "Who Needs CaaS" section
- [x] Write "The CaaS Future" section with quotations from industry leaders
- [x] Write FAQ section (3-5 questions)
- [x] Add FAQPage JSON-LD schema block
- [x] Add CTA section with internal links
- [x] Verify word count is 2,500-3,000

### 2.3 GEO/AEO Compliance Review

- [x] Count external source citations (target: 5-8)
- [x] Count quotations (target: 2-3)
- [x] Count statistics with attribution (target: 5-10)
- [x] Verify no keyword stuffing (primary keyword used naturally, not forced)
- [x] Verify internal links to 2+ Soleur pages with keyword-rich anchor text

### 2.4 Brand Voice Compliance Review

- [x] Scan for prohibited terms: "AI-powered", "leverage AI", "just/simply", "assistant/copilot", "plugin/tool" (in marketing context)
- [x] Verify declarative voice (no hedging: "might", "could", "potentially")
- [x] Verify founder-as-decision-maker framing
- [x] Verify concrete numbers used (agent counts, department counts)

## Phase 3: Build, Validate, and Ship

### 3.1 Build Verification

- [x] Run `npm install` in worktree
- [x] Run `npm run docs:build`
- [x] Verify build succeeds with zero errors (24 files, 0.87s)

### 3.2 SEO Validation

- [x] Run `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site`
- [x] Verify all checks pass (canonical, JSON-LD, OG, Twitter card on blog post)
- [x] Verify blog post renders at `/blog/what-is-company-as-a-service/`
- [x] Verify blog index shows the post

### 3.3 Compound and Commit

- [ ] Run compound skill
- [ ] Commit all changes
- [ ] Push and create PR via /ship
