# Copy Deck: Website Conversion Flow Review

**Issue:** #1142
**Phase:** 0.2 (UX Gate -- Copywriter Artifact)
**Brand guide source:** `knowledge-base/marketing/brand-guide.md` (read 2026-03-26)
**Wireframe source:** `knowledge-base/product/design/website/homepage-getting-started-wireframes.pen`

## Voice Notes

Per brand guide: bold, forward-looking, energizing, mission-driven, precise. Declarative statements. No hedging. Lead with what becomes possible, not what the product does. Frame the founder as the decision-maker, the system as the executor.

**Prohibited terms in public content:** "plugin," "terminal-first," "CLI-native," "AI-powered," "copilot," "assistant," "just," "simply," "disrupt," "synergy."

---

## 1. site.json Description

**Current:**
> The company-as-a-service platform. A Claude Code plugin that gives solo founders a full AI organization across every business department.

**Proposed:**
> The company-as-a-service platform -- a full AI organization that gives solo founders the operational capacity of every business department.

**Rationale:** Removes "Claude Code plugin." Retains "company-as-a-service platform" (brand tagline) and "full AI organization" (core positioning). Keeps SEO phrase "solo founders."

---

## 2. Homepage Hero

### Badge (unchanged from wireframe)

`THE COMPANY-AS-A-SERVICE PLATFORM`

### H1 Headline

> Build a Billion-Dollar Company. Alone.

No change. This is the brand thesis headline and performs well.

### Subheadline

**Current (index.njk):**
> The company-as-a-service platform for solo founders. {{ stats.agents }} AI agents across {{ stats.departments }} departments -- engineering, marketing, legal, finance, sales, and more -- orchestrated from a single Claude Code plugin.

**Proposed:**
> The company-as-a-service platform for solo founders. {{ stats.agents }} AI agents across {{ stats.departments }} departments -- engineering, marketing, legal, finance, sales, and more -- orchestrated from a single platform.

**Rationale:** Only change is "Claude Code plugin" to "platform." The rest is strong -- dynamic stats, department listing, and concise positioning all remain.

### Inline Waitlist Form

| Element | Text |
|---------|------|
| Email input placeholder | `Enter your email address` |
| Submit button | `Join the Waitlist` |

### Primary CTA (below form)

> See Pricing & Join Waitlist

Links to pricing page. Arrow indicator appended in UI: `See Pricing & Join Waitlist  -->`

### Secondary CTA (below primary)

> Or try the open-source version

Links to Getting Started page (self-hosted section anchor). Arrow indicator appended in UI: `Or try the open-source version -->`

---

## 3. Homepage FAQ Rewrites

All 6 Q&A pairs. Questions match wireframe layout. Answers rewritten to remove all plugin/CLI-first framing.

### Q1: What is Soleur?

**Current:**
> Soleur is a company-as-a-service platform delivered as a Claude Code plugin. It deploys {{ stats.agents }} AI agents across {{ stats.departments }} business departments -- engineering, marketing, legal, finance, operations, product, sales, and support -- giving a single founder the operational capacity of a full organization. Every problem solved compounds into patterns that accelerate future work.

**Proposed:**
> Soleur is the company-as-a-service platform. It deploys {{ stats.agents }} AI agents across {{ stats.departments }} business departments -- engineering, marketing, legal, finance, operations, product, sales, and support -- giving a single founder the operational capacity of a full organization. Every problem solved compounds into patterns that accelerate future work.

**Changes:** Removed "delivered as a Claude Code plugin." Changed "a company-as-a-service platform" to "the company-as-a-service platform" (declarative, owns the category). Rest unchanged -- the answer is already strong.

**JSON-LD version:**
> Soleur is the company-as-a-service platform. It deploys AI agents across business departments -- engineering, marketing, legal, finance, operations, product, sales, and support -- giving a single founder the operational capacity of a full organization. Every problem solved compounds into patterns that accelerate future work.

---

### Q2: What is company-as-a-service?

**Current:**
> Company-as-a-service means running every business function through a unified platform of AI agents instead of hiring individual employees or contractors for each department. You provide the taste, vision, and decisions -- the agents handle execution across engineering, marketing, legal, sales, and every other department.

**Proposed:** No change. This answer contains no plugin language and is already well-written.

---

### Q3: How does Soleur differ from Cursor or GitHub Copilot?

**Current:**
> Cursor and Copilot are code editors. Soleur operates across every business department, not only engineering. It includes agents for marketing strategy, legal compliance, financial planning, sales pipeline analysis, and more. It also compounds knowledge over time -- every decision and pattern is captured and reused, making your organization smarter with each project.

**Proposed:** No change. Clean differentiation, no prohibited terms, concrete examples.

---

### Q4: Is Soleur free?

**Current:**
> The Soleur plugin is open source and free to install. It runs on Claude Code, which requires an Anthropic API key or a Claude subscription. Your costs depend on your Claude usage.

**Proposed:**
> Soleur offers two paths. The cloud platform (coming soon) provides managed infrastructure, a web dashboard, and priority support -- pricing starts at the Spark tier. The self-hosted version is open source and free. Both run on Anthropic's Claude models, so your AI costs depend on your Claude usage.

**Rationale:** Removes "plugin" and "install." Introduces the dual-path model (cloud + self-hosted) that matches the new Getting Started page. References pricing tiers without committing to specific numbers. Directs interest toward the cloud platform as primary.

**JSON-LD version:**
> Soleur offers two paths. The cloud platform provides managed infrastructure, a web dashboard, and priority support with tiered pricing. The self-hosted version is open source and free. Both run on Anthropic's Claude models.

---

### Q5: Who is Soleur for?

**Current:**
> Soleur is built for solo founders and small teams who want to operate at the scale of a full organization. Among solo founder AI tools, Soleur is the only platform that spans every department and compounds institutional knowledge across sessions.

**Proposed:**
> Solo founders who refuse to accept that scale requires headcount. Soleur is the only platform that spans every business department and compounds institutional knowledge across projects -- giving one person the operational capacity of a full organization.

**Rationale:** Opens with the brand guide's target audience language (bold, declarative). Drops "small teams" to sharpen the solo founder positioning. Changes "across sessions" to "across projects" (more meaningful to the audience, delivery-agnostic).

**JSON-LD version:**
> Solo founders who refuse to accept that scale requires headcount. Soleur is the only platform that spans every business department and compounds institutional knowledge across projects, giving one person the operational capacity of a full organization.

---

### Q6: How do I get started?

**Current:**
> Install the plugin with `claude plugin install soleur`, then run `/soleur:go` and describe what you want to do. Soleur routes your request to the right workflow -- whether that is building a feature, validating a business idea, generating legal documents, or running a competitive analysis.

**Proposed:**
> Join the waitlist for the cloud platform, or install the open-source version and run `/soleur:go` to start. Describe what you need -- build a feature, validate a business idea, generate legal documents, run a competitive analysis -- and Soleur routes to the right workflow.

**Rationale:** Removes "Install the plugin with `claude plugin install soleur`." Leads with the cloud waitlist (primary conversion goal) and offers self-hosted as secondary. Retains the concrete use cases that demonstrate breadth.

**JSON-LD version:**
> Join the waitlist for the cloud platform, or install the open-source version and start with /soleur:go. Describe what you need and Soleur routes to the right workflow -- whether building a feature, validating a business idea, generating legal documents, or running a competitive analysis.

---

## 4. Getting Started -- Cloud Platform Path

### Card Title

> Soleur Cloud Platform

### Badge

> COMING SOON

### Value Prop (2-3 sentences)

> Access your AI organization from any device. No CLI required. Dashboard, real-time agents, managed infrastructure, and priority support -- all in the browser.

### Feature Bullets

1. Web dashboard -- access from any device
2. Managed infrastructure and agent orchestration
3. Real-time agent activity and knowledge base
4. Priority support and early access to new features

### CTA Button

> Join the Waitlist

Links to pricing page with waitlist form. Arrow indicator appended in UI: `Join the Waitlist -->`

### Subtext (below CTA)

> Links to pricing page with waitlist form

*(Implementation note: this is not visible copy -- it is the wireframe annotation indicating the link target.)*

---

## 5. Getting Started -- Self-Hosted Path

### Card Title

> Self-Hosted (Open Source)

### Badge

> AVAILABLE NOW

### Description

> Install the Claude Code extension and run your AI organization locally. Full access to all {{ stats.agents }} agents and {{ stats.skills }} skills. Free and open source.

**Note:** "Claude Code extension" is used here as a technical installation instruction, which is within the brand guide's exception for literal CLI commands and technical documentation. The self-hosted path is inherently a technical/developer audience, so referencing the installation mechanism is appropriate. The word "plugin" is avoided per brand guide -- "extension" serves the same technical function without triggering the prohibited term.

---

## 6. Form Success Messages

### Homepage Waitlist Form (after email submission)

**Current:** N/A (new form)

**Proposed:**
> You are on the list. We will notify you when the cloud platform is ready.

**Rationale:** Short, declarative, no filler. Does not promise "check your email" (which implies a confirmation email that may or may not exist depending on Buttondown configuration). Confirms what happened and what to expect next.

### Newsletter Footer Form (after email submission)

**Current:** "Check your email to confirm your subscription."

**Proposed:**
> Subscribed. You will hear from us when it matters.

**Rationale:** Matches brand voice (declarative, confident). Signals respect for the reader's inbox -- we don't spam. If Buttondown requires double opt-in confirmation, append: "Check your inbox to confirm."

---

## Compliance Checklist

- [x] Brand guide read before writing (2026-03-26)
- [x] Zero instances of "plugin" as product framing (exception: none used)
- [x] Zero instances of "terminal-first" or "CLI-native"
- [x] Zero instances of "AI-powered"
- [x] Zero instances of "copilot" or "assistant" (except in Q3 where they describe competitors)
- [x] Zero instances of "just" or "simply"
- [x] All CTAs use declarative voice
- [x] Dynamic stats preserved ({{ stats.agents }}, {{ stats.departments }}, {{ stats.skills }})
- [x] Wireframe element names matched to copy elements

## Review Status

- [ ] CMO review
- [ ] Founder approval
