---
last_updated: 2026-03-26
last_reviewed: 2026-03-26
review_cadence: quarterly
owner: CMO
depends_on:
  - knowledge-base/product/business-validation.md
---

# Soleur Brand Guide

## Identity

### Mission

Soleur exists to solve one engineering problem: enabling a single founder to build, ship, and scale a billion-dollar company. We are building the Company-as-a-Service platform -- a full-stack AI organization that reviews, plans, builds, remembers, and self-improves. Every decision the founder makes teaches the system. Every feature or project gets better and faster than the last.

The name Soleur is a portmanteau of Solo and Solar -- entrepreneur energy and light to better the world.

### Target Audience

Solo founders who think in billions. Technical builders who refuse to accept that scale requires headcount. People who see the billion-dollar solo company not as science fiction, but as an engineering problem waiting to be solved.

### Who Is Soleur For?

| Segment | Description | Default channels |
|---------|-------------|-----------------|
| Technical builders | Founders who code, use Claude Code, think in systems. The beachhead audience. | HN, GitHub, Discord, technical blog posts |
| Non-technical founders | Founders who use AI tools (ChatGPT, Notion) but don't code. Want business leverage, not technical leverage. | Website, LinkedIn, X/Twitter, onboarding content |

### Positioning

Soleur is not a copilot. Not an assistant. It is a full AI organization -- 60+ agents, 60+ skills, and compounding knowledge -- that operates as every department from strategy to shipping. The brand energy mirrors Tesla and SpaceX: audacious, mission-driven, future-focused. We lead with the ambitious platform vision, never the plugin description.

**Tagline:** The Company-as-a-Service Platform

**Thesis:** "The first billion-dollar company run by one person isn't science fiction. It's an engineering problem. We're solving it."

**General thesis (non-technical channels):** "Running a company alone shouldn't mean doing everything alone. Soleur gives you a full team of AI specialists -- marketing, legal, operations, finance -- that learn your business and work together."

> **[2026-03-22 Business Validation Review]** The positioning statement, tagline, and thesis remain valid -- user research confirmed the CaaS vision resonates strongly with founders. However, "terminal-first workflow" is no longer a positioning asset. The positioning must be delivery-agnostic: accessible from any device, not tied to a specific development environment. The phrase "operates as every department from strategy to shipping" holds. What changes is the access surface, not the mission. When the web platform ships, positioning language should emphasize "accessible anywhere" alongside the existing "full AI organization" framing. No changes to mission or thesis required.

## Founder

- **Name:** Jean Deruelle
- **Role:** Founder & CEO
- **Company:** Jikigai (legal entity), operating Soleur (product)

Use this section as the authoritative source when any skill or agent needs to attribute content, generate About pages, produce author schema, or write LinkedIn Personal posts in the founder's voice. Never infer the founder's name from org names, GitHub handles, or domain slugs.

## Voice

### Brand Voice

Ambitious-inspiring. Bold, forward-looking, energizing. The voice of Soleur is the voice of someone who has already seen the future and is building it right now. We speak like Vercel markets -- with conviction, precision, and an undercurrent of inevitability.

**Core adjectives:** Bold. Forward-looking. Energizing. Mission-driven. Precise.

### Tone Spectrum

| Context | Tone | Example |
|---------|------|---------|
| Marketing / Hero | Maximum ambition, declarative | "Build a Billion-Dollar Company. Alone." |
| Product announcements | Confident, concrete | "60+ agents. Every department. From idea to shipped." |
| Technical docs | Clear, precise, no fluff | "The compound skill chains two agents sequentially." |
| Community / Discord | Direct, collaborative, still bold | "Shipped. Try it and tell us what breaks." |
| Error messages | Honest, actionable | "Agent failed. Here's the log. Here's the fix." |
| Non-technical founders | Clear, outcome-focused, no jargon | "Your AI marketing team writes copy, plans campaigns, and tracks competitors -- without you hiring anyone." |

### Do's and Don'ts

**Do:**

- Lead with what becomes possible, not what the tool does
- Use declarative statements ("Build at scale" not "Try building at scale")
- Frame the founder as the decision-maker, the system as the executor
- Use concrete numbers when available (60+ agents, 60+ skills)

> **Numbers: soft floors in prose.** Use "60+ agents" and "60+ skills" in static documentation and marketing prose. The live site renders exact counts from the filesystem via `{{ stats.agents }}` / `{{ stats.skills }}` -- never duplicate the exact count in prose, where it will drift as new agents and skills ship. Soft floors stay accurate across releases.

- Write like the future is already here
- Use "we" when speaking as Soleur, "you" when addressing the founder
- Keep sentences short and punchy in marketing copy
- When writing for non-technical founders: define technical terms on first use, lead with business outcomes, use "your AI team" instead of "60+ agents," and explain concepts in business terms (e.g., "knowledge base" = "your company's institutional memory")

**Don't:**

- Say "AI-powered" or "leverage AI" -- the entire platform is AI; saying it is redundant
- Use "just" or "simply" -- these minimize the ambition
- Say "assistant" or "copilot" -- Soleur is an organization, not a helper
- Say "terminal-first" or "CLI-native" as a positioning advantage -- the delivery pivot requires device-agnostic language [added 2026-03-22, per business validation]
- Hedge with "might," "could," or "potentially"
- Use startup jargon ("disrupt," "synergy," "move the needle")
- Over-explain -- trust the reader's intelligence
- Use emojis in formal marketing copy (acceptable in Discord)
- Call it a "plugin" or "tool" in public-facing content -- it is a platform. **Exception:** "plugin" is permitted in literal CLI commands (`claude plugin install`), in legal documents where "Plugin" is a defined term, and in technical documentation describing the installation mechanism

### Audience Voice Profiles

Two registers share the same brand identity (bold, mission-driven, precise). They differ in vocabulary, explanation depth, and proof points.

**Technical register** (default for HN, GitHub, Discord, technical blog posts):

- Use engineering metaphors and developer-native terms freely
- Proof points: "420+ merged PRs," "60+ agents, 60+ skills," "brainstorm-plan-implement-review-compound lifecycle"
- Assume the reader understands agents, CLI, workflows, and software development concepts
- "Trust the reader's intelligence" applies -- don't over-explain

**General register** (default for website, LinkedIn, X/Twitter, onboarding content):

- Plain language -- no jargon without immediate definition in the same sentence
- Proof points: "saves 15+ hours/week on marketing, legal, and ops," "handles 7 of the 8 jobs you're doing alone," "remembers everything about your business"
- Use business analogies: "your AI team" not "60+ agents," "your company's memory" not "compounding knowledge base," "AI specialists" not "domain leader agents"
- Key term glossary for inline definitions:
  - **Agents** = "AI specialists that handle specific business functions"
  - **Skills** = "workflows the AI team follows to get things done"
  - **Knowledge base** = "your company's institutional memory -- everything your AI team learns stays and compounds"
  - **Compounding** = "gets smarter the more you use it"
  - **Cross-domain coherence** = "your marketing agent knows what your legal agent decided"
- "Explain, don't dumb down" -- maintain confidence and precision, just use accessible vocabulary

### Value Proposition Framings

> **[2026-03-26 Synthetic Research Review]** Tested three framings against 10 synthetic founder personas. Pain-point framing won 7/10. CaaS framing requires market education a bootstrapped company can't afford. Tool-replacement failed for pre-revenue founders (6/10 of the cohort) who don't have tool spend to replace. These findings are hypotheses to validate in real interviews.

**Primary framing (pain-point):** "Stop hiring, start delegating"

- Use: Landing page hero, outbound messaging, first-contact copy
- Pitch: "You're doing 8 jobs. Soleur helps you tackle 7 of them — marketing campaigns, legal contracts, competitive analysis, financial planning — delegated to AI agents that remember everything about your business."
- Why: Near-universal problem recognition. "You're doing 8 jobs" describes every solo founder's lived experience. Softened claim ("helps you tackle" not "handles") for pragmatist credibility.
- Segment: Best for $10K-50K MRR founders at the hire/don't-hire fork

**Memory-first variant (recommended for A/B test):** "The AI that already knows your business"

- Use: A/B test against primary framing on landing page
- Pitch: "Every time you use Soleur, it learns more about your company. Your marketing agent knows your brand guide. Your legal agent knows your compliance requirements. Your product agent knows your competitive landscape. One compounding knowledge base across 8 departments."
- Why: "Memory" / persistent context generated the strongest unprompted positive reactions across 4 personas. This is the feature that separates Soleur from "just use ChatGPT." Not one of the three tested framings — emerged from cross-cutting analysis.
- Segment: Best for pre-revenue enthusiasts who already use ChatGPT and are frustrated by context loss

**CaaS framing (secondary, education-heavy):** "Your AI company" — retain for deep content (blog posts, case studies) where there's space to explain the concept. Not suitable for headlines or first-contact messaging.

**Tool-replacement framing (retire as primary):** "One platform, 8 departments" — demote to secondary proof point on the pricing page for later-stage founders. Not suitable for headlines. The $765-3,190/month comparison only resonates with $15K+ MRR founders with established tool stacks.

**Trust scaffolding (add to all framings):** All three framings lacked trust signals. Add phrases like "human-in-the-loop," "starting point, not final answer," or "your expertise, amplified" to address the #1 objection across 8/10 personas: "What if the output is wrong?"

### Example Phrases

**Announcements:**

- "Every department. From idea to shipped."
- "Your AI organization just got smarter."
- "One founder. Full-stack AI. No compromises."

**Product descriptions:**

- "You decide. Agents execute. Knowledge compounds."
- "Not a copilot. Not an assistant. A full AI organization that reviews, plans, builds, remembers, and self-improves."
- "Designed, built, and shipped by Soleur -- using Soleur."
- "Stop hiring. Start delegating." _[Added 2026-03-26: lead pain-point framing]_
- "The AI that already knows your business." _[Added 2026-03-26: memory-first variant for A/B testing]_

**Community replies:**

- "Shipped. Let us know what you build with it."
- "Good catch. Fix is in, deploying now."
- "That's the right instinct. Here's how to wire it up."

**Error / system messages:**

- "Agent failed on step 3. Logs attached. Retrying with fallback."
- "Knowledge base updated. 4 new learnings captured."

## Visual Direction

### Color Palette

The visual identity follows the **Solar Forge** direction: raw power being shaped by one person's judgment. Energy against darkness.

| Role | Hex | Usage |
|------|-----|-------|
| Background | `#0A0A0A` | Page and canvas background |
| Surface | `#141414` | Cards, panels, elevated surfaces |
| Border | `#2A2A2A` | Dividers, card borders, subtle structure |
| Gold Accent | `#C9A962` | Section labels, icons, highlights |
| Gold Gradient Start | `#D4B36A` | CTAs, buttons (left/top) |
| Gold Gradient End | `#B8923E` | CTAs, buttons (right/bottom) |
| Text Primary | `#FFFFFF` | Headlines, body text |
| Text Secondary | `#848484` | Subheadlines, descriptions |
| Text Tertiary | `#6A6A6A` | Captions, metadata, timestamps |

**Light mode (Solar Radiance):** A warm cream and amber/gold counterpart palette is under exploration but not yet confirmed. Do not use in production until formally defined.

### Typography

| Role | Font | Weight | Notes |
|------|------|--------|-------|
| Headlines | Cormorant Garamond | 500 | Serif -- deliberately distinguishes from every dev tool |
| UI / Body | Inter | 400-600 | Clean, legible, industry standard |
| Data / Code | JetBrains Mono | 400 | Monospace for technical content |
| Section Labels | Inter | 600 | 12px, letterSpacing 3, gold color, ALL CAPS |
| Logo Wordmark | Inter | 500 | letterSpacing 4, spaced-out "SOLEUR" |

### Style

- **Metaphor:** A forge. Raw power being shaped by one person's judgment. Energy against darkness.
- **Corners:** Sharp (0px border-radius). Architectural precision. No rounded corners.
- **Logo:** Gold Circle -- a circular gold stroke containing a serif "S", paired with the spaced-out "SOLEUR" wordmark.
- **Imagery:** Dark backgrounds with gold accents. Minimal, structural. No stock photos of people shaking hands.
- **Motion:** Subtle, purposeful. No bouncing or playful animations. Think: light emerging from darkness.
- **Density:** Generous whitespace. Let the content breathe. The emptiness is part of the power.

## Channel Notes

### Discord

- Tone shifts slightly casual but retains the boldness. Direct, collaborative, builder-to-builder.
- Emojis are acceptable sparingly -- prefer structural ones (arrows, checkmarks) over decorative ones.
- Keep messages concise. If it needs a wall of text, link to docs instead.
- Announcements should still carry the brand energy: declarative, concrete, forward-looking.
- Engage with the community as equals who are building the future together.
- Example announcement: "New: SEO + AEO for your docs site. One skill, three sub-commands. Ship it."
- Example reply: "Good question. The compound skill handles that -- docs here: [link]"

### GitHub

- Maximum technical precision. No marketing language in issues or PRs.
- Commit messages and PR descriptions should be clear and factual.
- Issue responses: acknowledge, explain, resolve. No hedging.
- README and public-facing repo content can carry brand voice but stays grounded in what the software does.
- Use "Soleur" (capitalized) consistently, never "soleur" in prose.
- Example issue response: "Confirmed. The agent resolver doesn't recurse into nested skill directories. Fix in #74."
- Example PR description: "Add brand-architect agent and discord-content skill. Enables interactive brand workshops and Discord content generation from brand guide."

### X/Twitter

**Handle:** [@soleur_ai](https://x.com/soleur_ai)

- Full brand voice. Declarative, concrete, no hedging. Every tweet should read like a statement, not a question.
- **Thread format:** Hook tweet (standalone value, no "thread" announcement) > Numbered body tweets (2/ 3/ 4/) > Final tweet with article link and one-line CTA.
- **280-character limit** is enforced per tweet during generation, not as a post-hoc trim.
- Hook-first: the first tweet must deliver a complete, compelling idea that works even if nobody clicks "Show more." No "I just wrote about..." openers.
- Links go in the final tweet only. Mid-thread links break reading flow and reduce impressions.
- No hashtags in body tweets. One relevant hashtag in the final tweet is acceptable if it adds discoverability (e.g., #solofounder, #buildinpublic). Never more than two.
- No emojis in hook tweets. Body tweets may use one structural emoji (arrow, checkmark) per tweet if it aids scanning.
- Metrics and numbers land hardest. Lead with concrete data when available: "420+ merged PRs. 40+ agents. 8 departments. One founder."
- Never use "excited to announce" or "we're thrilled." State what shipped and why it matters.
- Example hook: "The other 70% of running a company is still manual. AI solved coding. Nothing solved the rest."
- Example thread body: "2/ Company-as-a-Service runs every department with AI agents that share a compounding knowledge base. Marketing knows what engineering decided. Legal references the privacy policy. Context flows everywhere."
- Example final tweet: "Full breakdown of what CaaS means and why it matters for solo founders:\n\nhttps://soleur.ai/blog/what-is-company-as-a-service/\n\n#solofounder"

#### Engagement Guardrails

These guardrails apply in both automatic mode (fetch-mentions) and manual mode (Free tier 403 fallback). The human reviewer is the enforcement mechanism.

**Topics to avoid:**

- Political, partisan, or religiously divisive topics
- Competitor criticism or comparisons -- state what Soleur does, never what others lack
- Unverified claims or speculation about roadmap dates
- Anything requiring legal review (pricing commitments, data handling details beyond the privacy policy)
- Trending hashtags or memes with unclear associations -- meanings shift fast

**Exception:** Engaging with #solofounder, #buildinpublic, and AI/developer tooling communities is encouraged even when conversations touch on industry trends. The prohibition targets partisan, religious, and inflammatory topics, not the broader tech ecosystem.

### LinkedIn Personal

- Thought leadership is the primary format. Case studies, reflections on building with AI agents, lessons learned, and honest assessments of what worked and what didn't.
- First-person founder voice. Write as the person behind the company, not as a faceless brand. "I built..." not "We launched..."
- Professional but not corporate. The tone sits between X's punchy brevity and a conference keynote -- substantive, measured, and direct. No buzzwords, no jargon for jargon's sake.
- Aim for ~1,300 characters for optimal organic visibility. Maximum 3,000 characters. Longer posts get truncated behind "see more" -- front-load the hook.
- Hook-first: the opening line must deliver a complete, compelling idea that works in the feed preview. No "Excited to share..." openers.
- Include the article URL naturally in context, not as a standalone CTA at the end.
- One or two relevant hashtags maximum. Prefer #solofounder, #buildinpublic, #AIagents. Never more than two. No hashtag walls.
- Tuesday-Thursday mornings perform best for B2B developer tools content.
- No promotional framing. "Here's what I learned building X" outperforms "Check out our new feature Y" by an order of magnitude on LinkedIn.
- Example post: "Most AI coding tools solve 30% of running a company. The other 70% -- marketing, legal, finance, ops -- is still manual.\n\nI spent the last 6 months building an AI organization that handles all of it. 40+ agents across 8 departments, sharing a compounding knowledge base.\n\nThe surprising part: the hardest problem wasn't the AI. It was getting agents to share context across departments.\n\n[link to article]\n\n#solofounder #buildinpublic"

**When to skip a mention:**

- Abusive, harassing, or spam content
- Off-topic mentions with no connection to Soleur or solo-founder topics
- Mentions that are themselves rage-bait or provocative in tone (thread-level context review is a human reviewer responsibility during the approval step)
- Likely bot accounts (alphanumeric handle pattern, generic or empty display name)
- Threads where replying would amplify negative sentiment
- Mentions that are retweets or quote-tweets of Soleur content -- the RT is sufficient engagement
- Accounts whose mention content creates brand association risk (full account history review is a human reviewer responsibility during the approval step)

**Reply cadence:**

- Maximum 10 replies per engagement session
- Minimum 2-minute gap between posting replies. X's algorithm penalizes rapid-fire bursts that look automated.
- One reply per thread -- do not enter extended back-and-forth. Escalate complex questions to Discord or docs.
- Default to skipping when unsure -- silence is safer than a misaligned reply

**Tone in replies:**

- Match the register of the original tweet (technical question gets a technical answer, casual mention gets a concise acknowledgment)
- Never argue or debate -- state the position once, then disengage
- Credit insight in feature suggestions ("Solid idea. Filed as #N." not "Thanks for the feedback!")
- Maintain a human voice -- avoid phrases that sound templated or auto-generated

#### Profile Banner

| Property | Value |
|----------|-------|
| Dimensions | 1500x500px (3:1 aspect ratio) |
| File | `plugins/soleur/docs/images/x-banner-1500x500.png` |
| Background | `#0A0A0A` with gold gradient edge accents (`#D4B36A` left, `#B8923E` right) |
| Wordmark | "S O L E U R" -- Inter 500, 52px, gold `#C9A962`, centered horizontally, upper third |
| Thesis | "Build a Billion-Dollar Company. Alone." -- Cormorant Garamond 500, 82px, white `#FFFFFF`, centered |
| Metrics | "60+ Agents · 8 Departments · 1 Founder" -- Inter 400, 26px, secondary `#848484`, below thesis |
| Gold accent line | 1px horizontal, 600px wide centered, 40% opacity, at y=325 |
| Mobile safe zone | Center 900px (60%) contains all text -- verified |
| Avatar overlap | Bottom-left clear of critical content |
| Source file | `knowledge-base/product/design/brand/brand-x-banner.pen` |
| Generated with | Pencil MCP (design) + Pillow (PNG export) |

### LinkedIn Company Page

- Official announcement tone, third-person company voice
- Product updates, feature announcements, milestone celebrations
- Professional framing: "Soleur now supports...", "Today we're releasing..."
- ~1,300 chars optimal, 3,000 max
- Link to blog post or docs for details
- Minimal hashtags (1-2 max, same as personal)
- Cross-reference ### LinkedIn Personal for cadence, skip rules, and reply guidelines

### Bluesky

**Handle:** @soleur.bsky.social

- Developer-first audience, technical and builder-oriented tone. Bluesky's early adopter base skews heavily toward developers and open-source contributors.
- Full brand voice applies. Declarative, concrete, no hedging -- same energy as X/Twitter but adapted to Bluesky's thread culture.
- **Thread format:** Reply chains for multi-part content. Each post in a thread must stand alone as a complete thought.
- **300-character limit** (graphemes) per post -- enforced during generation, not as a post-hoc trim. More generous than X's 280 but still demands concision.
- AT Protocol / open-source credibility angle. Bluesky's community values decentralization and protocol-level thinking. Reference open-source, composability, and protocol design when relevant.
- No hashtags. Bluesky does not support hashtags as a native discovery feature. Do not use them.
- No emojis in standalone posts. Thread body posts may use one structural emoji (arrow, checkmark) if it aids scanning.
- Engagement guardrails: Bluesky's community is small and tightly knit with strong anti-bot sentiment. Start with organic, high-quality engagement. Avoid aggressive automated posting patterns that could trigger community backlash.
- Example post: "Company-as-a-Service: 60+ agents running every department from strategy to shipping. One founder makes decisions. The system executes."
- Example reply: "AT Protocol makes this possible -- open, composable, no API gatekeeping. Exactly the kind of infrastructure solo founders need."
- Example thread start: "The first billion-dollar solo company isn't science fiction. It's an engineering problem. Here's how we're solving it."

#### Engagement Guardrails

Same guardrails as X/Twitter apply (see above), with these Bluesky-specific additions:

**Bluesky-specific:**

- Maximum 5 replies per engagement session (smaller community, higher visibility per reply)
- No rapid-fire posting. Space posts at least 3 minutes apart. The small community notices automated patterns quickly.
- Engage authentically in AT Protocol and decentralization discussions -- this is native territory for Soleur's builder audience.
- Do not cross-post identical content from X/Twitter. Adapt the message for Bluesky's audience and tone.

### Hacker News

- Understated, technical tone. HN readers detect and punish marketing language instantly. Write like an engineer explaining to peers, not a brand talking to prospects.
- Show, don't tell. Lead with what the thing does and how it works. Never lead with why it's great.
- No superlatives ("revolutionary", "game-changing", "best-in-class"). No exclamation marks. No emojis.
- No marketing speak ("excited to share", "we're thrilled", "check it out"). State facts.
- Comments should add technical substance to the conversation. If the comment doesn't teach something or clarify a misconception, don't post it.
- Respect HN culture: be direct, cite sources, admit limitations, engage with criticism honestly.
- When discussing Soleur, focus on the technical architecture and specific capabilities, not positioning or branding.
- Example story title: "Soleur -- AI agents that run the non-engineering 70% of a solo founder's company"
- Example comment reply: "The knowledge base is a git-tracked directory of markdown files. Agents read and write to it like a shared filesystem. No vector DB, no embeddings -- just files the founder can read and edit directly."

### Website / Landing Page

- Full brand energy. This is where the ambition lives at maximum volume.
- Hero pattern: Badge (ALL CAPS, gold) > Headline (Cormorant Garamond, white) > Subheadline (Inter, secondary text) > CTA (gold gradient button).
- Section pattern: Label (ALL CAPS, gold, Inter 12px 600) > Title (Cormorant Garamond) > Description (Inter, secondary).
- Stats should feel monumental: large numbers, minimal labels.
- The footer tagline is always: "Designed, built, and shipped by Soleur -- using Soleur."
- Final CTA: "Ready to build at scale?" / "Your AI organization is ready. Are you?" / Start Building.

> **[2026-03-22 Business Validation Review]** When the web platform launches, the website CTA must shift from plugin installation to platform signup/login. The hero pattern, visual identity, and brand energy transfer directly -- the Solar Forge aesthetic is delivery-agnostic. The stats line ("60+ agents, 8 departments, 1 founder") remains valid. CTA copy candidates: "Start Building" (current, still works), "Open Your Dashboard", "Meet Your Organization." Do not reference CLI installation as the primary CTA in any new landing page content.
