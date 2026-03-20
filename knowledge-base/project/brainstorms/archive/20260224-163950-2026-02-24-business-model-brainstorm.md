# Business Model Brainstorm

**Date:** 2026-02-24
**Issue:** #287
**Participants:** CPO, CFO, CRO, CMO

## What We're Building

A hosted web platform with a Lovable-like UX that lets non-technical and semi-technical founders run an entire AI-powered organization from a dashboard. The existing CLI plugin (60 agents, 50 skills, 8 domains) becomes the open-source engine; the web platform is the paid product surface that makes it accessible to founders who would never use a terminal.

**Two-track parallel strategy:**

- **Track 1 (Now):** Push CLI adoption among technical founders. Validate the multi-domain value thesis with real external users.
- **Track 2 (Now):** Design and architect the web platform. UX research, prototyping, technical architecture.
- **Convergence:** CLI learnings inform web UX. Ship web platform when multi-domain value is proven.

## Why This Approach

The CaaS thesis -- "Build a Billion-Dollar Company. Alone." -- requires an audience larger than CLI-native developers. Non-technical founders are a vastly larger market with higher willingness to pay (they can't self-host, they need managed experiences). The web platform is the real product; the CLI was the prototype.

The parallel approach de-risks by validating with technical users (free, fast) while building for the broader market. CLI adoption provides demand signal, user feedback, and content marketing fuel without requiring the platform to be built first.

## Key Decisions

### 1. Business Model: Hosted Web Platform (Approach 1)

All-in on a web platform with Lovable-like UX. Rejected alternatives:

- **Expertise marketplace** (pre-built knowledge packs): Lower ambition, doesn't deliver the managed platform vision. Easier to replicate/pirate.
- **Concierge-to-platform bridge** (consulting first): Generates near-term revenue but trades founder time 1:1, contradicts the autonomous thesis, and risks becoming a consulting trap.
- **Hybrid (platform + consulting bridge)**: Recommended by analysis but declined in favor of full platform focus.

### 2. MVP: Agent Dashboard

The minimum viable product is a dashboard where founders can trigger and monitor agents across all 8 domains: "Draft a contract," "Write a blog post," "Review my expenses" -- all from one screen, no terminal needed.

Onboarding wizard (guided setup, zero-to-operational in 10 minutes) is v2, not MVP. Dashboard first, onboarding later.

### 3. Target Customer: Non-Technical Founders

Primary paying audience is non-technical or semi-technical founders who would never use a CLI. This is a deliberate expansion beyond the current CLI-native technical founder audience.

Implication: competing with Lovable, Bolt, Notion AI on UX quality, not just Claude Code plugins on agent depth. The competitive set changes.

### 4. Licensing: BSL 1.1 (Option A)

Switch from Apache-2.0 to BSL 1.1 for the entire project (CLI plugin + future web platform).

**Additional Use Grant (Option A):** Allows individual self-hosting for personal/internal use. Blocks competing hosted services that commercialize the code.

**Rationale:** The CLI plugin's agent orchestration architecture, 60+ agent definitions, and skill system represent significant IP worth protecting. The CLI is the product, not just a distribution vehicle.

**Transition mechanics:**
- Prior versions released under Apache-2.0 are grandfathered -- existing forks keep their rights.
- Future versions are BSL 1.1.
- Converts to Apache-2.0 after a set period (3-4 years, exact timeline TBD).
- Claude Code plugin registry has no license restrictions -- BSL is compatible.

### 5. Pricing: Deferred Until Validation

The $49-99/month range is a hypothesis based on competitor pricing (Lindy $49-499/month, Cursor $20-40/month), not validated willingness to pay. Price point will be set after CLI validation produces real demand data.

The CFO flagged that Claude API costs per active user could be $5-20/month, so margins must be modeled before committing to a price.

### 6. Distribution: Multi-Channel Combination

- **CLI-to-platform funnel:** Existing CLI users see upgrade prompts to sync knowledge base to the cloud.
- **Content and community:** Blog posts, X/Twitter, IndieHackers, Claude Code Discord. Build audience around the CaaS thesis.
- **Launch event:** Product Hunt launch when web MVP is ready.

### 7. Runway: 2-3 Months Self-Funded

No near-term revenue pressure. Accepted risk that the web platform likely won't generate revenue within this window. The parallel CLI validation track provides early signal without requiring revenue.

## Open Questions

1. **Unit economics:** What are the per-user Claude API + infrastructure costs? Is $49/month viable after API costs, payment processing (Stripe ~2.9%), and hosting? This must be modeled before pricing.

2. **BSL conversion timeline:** 3 years or 4 years before auto-conversion to Apache-2.0? Shorter builds more trust with developers; longer protects the business longer.

3. **Web platform architecture:** Separate repository or monorepo with the CLI plugin? Separate codebase allows independent licensing and deployment but adds coordination overhead.

4. **CLI community reaction to BSL:** Technical developers may resist the license switch on principle (BSL is "source available," not "open source" by OSI definition). The HashiCorp precedent (OpenTofu fork) is worth studying.

5. **Beachhead within non-technical founders:** "Non-technical solo founders" is still broad. Which sub-segment -- e-commerce founders? Agency owners? SaaS bootstrappers? -- is the most receptive to a CaaS pitch?

6. **Platform dependency risk:** What survives if Anthropic ships native multi-domain capabilities in Claude Code? The brainstorm assumes the platform layer (UX + managed knowledge base) is the defensible moat, not the agent logic itself.

7. **CLI agent adaptation:** Current agents are CLI-native (Bash commands, git workflows, terminal output). How much rearchitecting is needed to run them in a web context? Is it a wrapper or a rewrite?

## Domain Leader Assessments Summary

### CPO Assessment
- The knowledge base is the moat, not the agents. Business model should center on who owns/hosts the knowledge base.
- No distribution strategy exists. A business model without a path to users is a pricing exercise.
- The "aha moment" that converts free-to-paid must be identified -- it doesn't exist in the current product.
- 5 sharpest questions: What does hosted do that self-hosted can't? Is the monetization unit a seat, domain, or outcome? Does the model work if only engineers adopt? What converts free to paid? How does open-source coexist with paid tiers?

### CFO Assessment
- Current burn: ~$15.83/month (GitHub Copilot, Hetzner, Plausible trial).
- Hosted platform introduces a cost cliff: per-customer storage, compute, and Claude API tokens.
- At $0.003/token, a single active user could cost $5-20/month in API costs before margin.
- No capital position or runway documented. The brainstorm cannot model viability without this.
- Sequence matters: locking pricing before unit economics are understood risks underpricing or overpricing.

### CRO Assessment
- Pre-pipeline state: no ICP, no outbound sequences, no conversion mechanism, no pricing framework.
- Zero demand signal for paid conversion. This is a pipeline generation problem, not a pricing problem.
- Concierge onboarding ($500-2,000 one-time) is fastest path to first revenue and WTP validation.
- The freemium funnel has no defined conversion steps. Free user installs plugin, then what?
- 6 key questions: Who is the specific first customer? What's the one paid-tier gate? What happens to Apache-2.0 license with paid tiers? Is sales motion product-led or founder-led? Is the 50-user gate from validation agreed? Is there a professional services wedge?

### CMO Assessment
- Monetization timing vs brand credibility: zero paying customers while promising "billion-dollar company" energy creates misalignment.
- Open-source signals collide with premium pricing. Users anchor on "free."
- The freemium tier split (engineering free, business paid) may undersell the integration thesis.
- No acquisition channel exists. Before committing to revenue, need a path to first users.
- 5 key questions: Is open source distribution or values? What triggers upgrade? Who pays -- solo founder or 2-person team? Minimum users before charging? Is managed onboarding a bridge or a business?
