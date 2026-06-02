---
last_updated: 2026-06-02
last_reviewed: 2026-06-02
review_cadence: quarterly
owner: CMO
depends_on:
  - knowledge-base/marketing/brand-guide.md
  - knowledge-base/marketing/marketing-strategy.md
  - knowledge-base/product/business-validation.md
---

# Phase 4 Recruitment Messaging Templates

**Purpose:** Channel-specific copy to recruit 10 solo founders for **Phase 4 participation** — onboarding onto the Soleur platform and roughly two weeks of unassisted usage. One template per channel, each in the correct brand-guide voice register for that audience.

**This is not the problem-interview asset.** For 15-minute research calls (no pitch, no onboarding), use [`validation-outreach-template.md`](./validation-outreach-template.md). That document recruits for *research*; this one recruits for *participation*. Same audience, different ask — keep both discoverable as a pair.

> **Gate:** This file is the M4 deliverable. It produces the copy; it does **not** send anything. No recruitment outreach fires until the roadmap Marketing Gate and the Multi-User Readiness Gate complete — see `knowledge-base/product/roadmap.md` for the authoritative milestone list (the gate clause is the source of truth; don't duplicate the milestone ranges here, where they drift).

---

## The non-Claude-Code constraint (read first)

**At least 3 of 10 recruited founders must NOT be current Claude Code users.** Recruiting entirely from the Claude Code ecosystem validates the plugin-to-cloud migration path — not the platform value proposition from cold. (Roadmap, CMO review.)

This constraint is the reason the templates split into two voice registers, taken verbatim from the brand guide's **Audience Voice Profiles**:

- **Technical register** — developer-native vocabulary is on-brand. Used for Claude Code Discord and GitHub.
- **General register** — plain language, business outcomes, zero unexplained jargon. Used for X/Twitter and direct network outreach. This is where the non-Claude-Code 3-of-10 quota is reliably met.

When sourcing, fill the non-Claude-Code seats from the **General-register channels first** (see the matrix below). If you reach 10 recruits and all came from Discord/GitHub, you have missed the constraint — pause and source three more from your own network or X/Twitter.

### Channel → register → non-CC-suitability matrix

| Channel | Brand-guide register | Non-CC-suitable? | Primary framing | Primary ask |
|---|---|---|---|---|
| Claude Code Discord | Technical | No (audience is CC-native) | Builder-to-builder, what it does | Join Phase 4: onboard + 2 weeks |
| GitHub | Technical | Partial (devs, may not use CC) | What the platform does, grounded | Join Phase 4 via a grounded DM |
| IndieHackers | Both (two variants) | Yes (general variant) | Build-in-public / pain-point | Reply to join the cohort |
| X/Twitter | General | **Yes (primary non-CC channel)** | Pain-point / memory-first | Reply or DM to join |
| Direct network | General | **Yes (highest non-CC yield)** | Outcome-focused, personal | 1:1 personal ask |

**Three General-register channels feed the non-Claude-Code quota:** X/Twitter, Direct network, and the IndieHackers general variant.

---

## Channel: Claude Code Discord

**Register:** Technical. This is the one channel where Claude Code vocabulary ("plugin", "skills", "agents") is on-brand — the audience uses it daily. Tone: casual but bold, builder-to-builder. Keep it concise; sparing structural emoji (arrows, checkmarks) are fine. Link out rather than posting a wall of text.

**Post (community channel):**

> Recruiting 10 founders for a 2-week Phase 4 run of Soleur — the Company-as-a-Service platform. 60+ agents, 60+ skills, one compounding knowledge base that runs the non-engineering 70% of your company.
>
> You onboard, then use it unassisted for two weeks across whichever departments you want — marketing, legal, finance, ops. I want to see what breaks and what sticks when nobody's holding your hand.
>
> → No cost. → You keep every artifact. → Honest feedback is the only ask.
>
> Drop a 👋 or DM me if you're in.

**DM variant (warm Discord contact):**

> Hey [Name] — saw you shipping in #[channel]. Putting together a 10-founder cohort to run Soleur unassisted for two weeks and report back. Builder-to-builder, no cost, you keep everything you make. Want a seat?

---

## Channel: GitHub

**Register:** Technical, maximum precision, no marketing language (brand-guide GitHub notes). Target: developers with business-operations repos — people already automating the non-code parts of their company. Engage through their own repos/discussions first, then send a grounded DM. "Soleur" is always capitalized in prose.

**Profile / discussion DM (after genuine engagement with their work):**

> Saw [specific repo / discussion — e.g., your `ops-automation` repo]. I'm running a 2-week trial cohort for Soleur, an AI organization that handles the non-engineering side of a solo company: 60+ agents and 60+ skills over a git-tracked markdown knowledge base — no vector DB, files you read and edit directly.
>
> Looking for 10 builders to onboard and use it unassisted for two weeks. No cost; you keep all output. If that overlaps with what you're building in [repo], want a seat?

**Notes for the sender:** Lead with what the platform *does*, never with positioning adjectives. If they ask how it works, answer concretely (the knowledge base is markdown; agents read/write it like a shared filesystem). Acknowledge limitations honestly — this audience rewards it.

---

## Channel: IndieHackers

**Register:** Mixed community — provide BOTH variants below. IH norms reward transparent build-in-public framing (real numbers, honest "users: 1, revenue: zero" candor) over a pitch. Community-post format mirrors the sibling `validation-outreach-template.md` shape.

### Technical-leaning variant

> **Title:** Recruiting 10 founders to run my AI-org platform unassisted for 2 weeks
>
> I've spent months building Soleur — an AI organization that runs the non-engineering 70% of a solo company (marketing, legal, finance, ops) over a compounding knowledge base. 60+ agents, 60+ skills, 420+ merged PRs, built by one person.
>
> Before scaling, I need real founders to onboard and use it unassisted for two weeks — not a guided demo, the actual cold-start experience. No cost, you keep every artifact, and I want the brutal feedback.
>
> Comment or DM if you want a seat. Especially keen to include a few people who've never touched a developer CLI.

### General-leaning variant (for the non-Claude-Code seats)

> **Title:** You're doing 8 jobs. Want an AI team to take 7 of them for 2 weeks — free?
>
> Running a company alone means being the marketer, the lawyer, the bookkeeper, and the support desk all at once. I built a full AI team that learns your business and works those jobs with you — it remembers everything, so you stop re-explaining yourself every morning.
>
> I'm looking for 10 founders to try it for two weeks at no cost. You stay in control: every output is a starting point you approve, never something shipped behind your back. Your expertise, amplified.
>
> You do NOT need to be technical. Comment or DM if you want in.

---

## Channel: X/Twitter

**Register:** General. ≤280 characters per post (enforced at write time, not trimmed after). Hook-first — post 1 must stand alone. Links in the FINAL post only; no mid-thread links. No hashtags in the body; at most one in the final post. Lead with the pain-point framing ("You're doing 8 jobs") or the memory-first framing ("The AI that already knows your business"). Trust scaffolding required: this audience can't inspect the code, so name the human-in-the-loop guarantee.

**Public call-for-participants thread:**

> **1/** You're running a company alone. Marketing, legal, finance, ops, support — eight jobs, one person. AI solved the coding. The other seven are still on you.

> **2/** I built a full AI team that learns your business and works those seven jobs with you. Not a chatbot you re-explain yourself to every morning — it remembers your brand, your contracts, your numbers.

> **3/** Looking for 10 founders to run it for two weeks, free. You stay in control: every output is a starting point you approve, never a final answer shipped behind your back.

> **4/** A few seats are reserved for founders who have never touched a developer tool — that's the point. Want in? Reply or DM and I'll send details. #buildinpublic

**Recruitment DM variant (1:1):**

> Hi [Name] — saw [specific signal]. I built an AI team for solo founders that learns your business and helps run the parts you never have time for: marketing, legal, ops. Looking for 10 people to try it free for two weeks. You'd stay in full control. Open to a seat?

---

## Channel: Direct network outreach

**Register:** General, warm, 1:1, personalized. This is the **highest-yield channel for the non-Claude-Code quota** — your own network of non-technical builders. Outcome-focused, zero jargon.

**Personal message (email / DM to someone you know):**

> Hi [Name],
>
> I've been heads-down building something I think fits exactly what you're juggling with [their company]. It's an AI team that learns your business and takes the parts you don't have time for — the marketing copy, the contract drafts, the financial tracking, the competitor watching. It remembers everything, so it gets sharper the more you use it.
>
> I'm hand-picking 10 founders to try it for two weeks before I open it up. No cost, and you keep everything it produces. You stay in control the whole way — it hands you a starting point to approve, not a final answer it ships on its own.
>
> You came to mind because you're doing all of this solo and you'd give me the honest read I need. Want a seat?
>
> — [Your name]

**Notes for the sender:** Reference one specific thing about their company. One message per person. If they say yes, follow up with onboarding details, not a sales deck.

---

## Outreach etiquette (brand-risk guardrail)

Recruitment copy that reads as spam is a brand-damage vector and gets you banned from the communities you most want to reach. Every template here is **personalize-then-send, never mass-blast.** Respect each community's self-promotion rules: Discord and IndieHackers have explicit anti-spam norms — engage as a member first, recruit second. Personalize every DM with a specific signal about the recipient. Send **one** message per person; if there's no reply, let it go. No bulk DM campaigns, no copy-paste blasts, no recruiting in threads where it's off-topic. Hacker News is deliberately excluded as a recruitment channel — HN readers punish recruitment and marketing posts; if HN reach is wanted later, that's article submission, not outreach.

## Proof-point discipline

- **Counts are soft floors.** Use "60+ agents", "60+ skills", "420+ merged PRs" in prose — never a hardcoded exact count, which drifts as components ship (brand-guide, "Numbers: soft floors in prose").
- **No fabricated stats or unverified citations.** If a claim needs an external source, verify the live URL before embedding it and annotate `<!-- verified: YYYY-MM-DD source: <url> -->`. Recruitment DMs rarely need citations — prefer authoring directly from this guide with none.
- **No price as a call-to-action.** Pricing is still under validation. These templates lead with "free for two weeks", never a committed price. Willingness-to-pay is a research topic for the interview, not a CTA here.
- **Prohibited terms in General-register copy:** no "plugin", "Claude Code", "copilot", "assistant", "AI-powered", "just", "simply", or "terminal-first" in the X/Twitter, Direct network, or IndieHackers-general templates. Those audiences include non-Claude-Code founders; lead with outcomes, not tooling vocabulary.

## Related documents

- [`validation-outreach-template.md`](./validation-outreach-template.md) — problem-interview outreach (15-min research calls, no pitch). The research-phase sibling to this recruitment asset.
- [`brand-guide.md`](./brand-guide.md) — Audience Voice Profiles, Value Proposition Framings, channel notes, and prohibited terms. The single source of truth for everything above.
- [`marketing-strategy.md`](./marketing-strategy.md) — ICP, channel priority, and the validation imperative.
