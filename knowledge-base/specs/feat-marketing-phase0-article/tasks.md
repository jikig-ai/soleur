# Tasks: Phase 0 Marketing Foundation + Phase 1 Article

## Phase 1: Keyword Vacuum Fixes (Deliverable 1)

### 1.1 Homepage H2 Keyword Injection
- [ ] Read `plugins/soleur/docs/index.njk`
- [ ] Rewrite Problem Section H2 to include "company-as-a-service" or target keyword (currently: "One founder powered by a full AI organization across every department.")
- [ ] Rewrite Features Section H2 to include relevant keywords (currently: "Your AI organization -- every department, from idea to shipped.")
- [ ] Verify section labels remain decorative (no keyword changes needed)
- [ ] Verify no brand guide violations in new H2 text

### 1.2 Agents Page Introductory Prose
- [ ] Read `plugins/soleur/docs/pages/agents.njk`
- [ ] Add 2-3 paragraph introduction after `</section>` (hero close) and before `<div class="container">` (category nav)
- [ ] Include keywords: "agentic engineering", "AI agents", "company-as-a-service", "cross-domain coherence"
- [ ] Wrap in `<section class="content"><div class="container"><div class="prose">` for consistent styling
- [ ] Verify prose explains what the agents do, why 8 domains matter, and how they share context

### 1.3 Skills Page Introductory Prose
- [ ] Read `plugins/soleur/docs/pages/skills.njk`
- [ ] Add 2-3 paragraph introduction after `</section>` (hero close) and before `<div class="container">` (category nav)
- [ ] Include keywords: "agentic engineering", "compound engineering", "AI workflow skills"
- [ ] Describe the brainstorm-plan-implement-review-compound lifecycle
- [ ] Wrap in `<section class="content"><div class="container"><div class="prose">` for consistent styling

## Phase 2: Pillar Article (Deliverable 2)

### 2.1 Article Structure and Outline
- [ ] Define article outline following content strategy brief
- [ ] Gather all external sources and statistics for GEO compliance
- [ ] Verify source URLs are accessible (use WebFetch if needed)

### 2.2 Write Article
- [ ] Create `plugins/soleur/docs/blog/what-is-company-as-a-service.md`
- [ ] Write YAML frontmatter (title, description, date, tags -- all literal strings, no template vars)
- [ ] Write introduction with machine-readable definition in first 150 words
- [ ] Write "The Problem CaaS Solves" section with statistics
- [ ] Write "How CaaS Works" section with Soleur product specifics
- [ ] Write "CaaS vs SaaS" comparison section
- [ ] Write "The Technology Behind CaaS" section
- [ ] Write "Who Needs CaaS" section
- [ ] Write "The CaaS Future" section with quotations from industry leaders
- [ ] Write FAQ section (3-5 questions)
- [ ] Add FAQPage JSON-LD schema block
- [ ] Add CTA section with internal links
- [ ] Verify word count is 2,500-3,000

### 2.3 GEO/AEO Compliance Review
- [ ] Count external source citations (target: 5-8)
- [ ] Count quotations (target: 2-3)
- [ ] Count statistics with attribution (target: 5-10)
- [ ] Verify no keyword stuffing (primary keyword used naturally, not forced)
- [ ] Verify internal links to 2+ Soleur pages with keyword-rich anchor text

### 2.4 Brand Voice Compliance Review
- [ ] Scan for prohibited terms: "AI-powered", "leverage AI", "just/simply", "assistant/copilot", "plugin/tool" (in marketing context)
- [ ] Verify declarative voice (no hedging: "might", "could", "potentially")
- [ ] Verify founder-as-decision-maker framing
- [ ] Verify concrete numbers used (agent counts, department counts)

## Phase 3: Build, Validate, and Ship

### 3.1 Build Verification
- [ ] Run `npm install` in worktree
- [ ] Run `npm run docs:build`
- [ ] Verify build succeeds with zero errors

### 3.2 SEO Validation
- [ ] Run `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site`
- [ ] Verify all checks pass (canonical, JSON-LD, OG, Twitter card on blog post)
- [ ] Verify blog post renders at `/blog/what-is-company-as-a-service/`
- [ ] Verify blog index shows the post (no "coming soon" message)

### 3.3 Compound and Commit
- [ ] Run compound skill
- [ ] Commit all changes
- [ ] Push and create PR via /ship
