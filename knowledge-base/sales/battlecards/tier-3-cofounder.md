---
last_updated: 2026-11-01
last_reviewed: 2026-11-01
review_cadence: monthly
owner: CRO
depends_on:
  - knowledge-base/product/competitive-intelligence.md
  - knowledge-base/product/competitive-intelligence/tier-3-cofounder.md
  - knowledge-base/product/pricing-strategy.md
competitor: Cofounder (cofounder.co)
tier: 3
convergence_risk: Critical
---

# Battlecard: Cofounder (cofounder.co)

> **[2026-11-01 Created via downstream-sync cascade]** This is a new battlecard. The CI index rates Cofounder **"Critical — closest product match"**, the highest overlap in Tier 3, and until now it had no card. **No new web facts went into it.** The 2026-11-01 scheduled scan could not do web research (the cron hook blocked the tools), so every competitor fact here comes from the 2026-06-14 targeted intake and the **2026-07-22 source-verification pass** recorded in the [Cofounder detail shard](../../product/competitive-intelligence/tier-3-cofounder.md). Facts are about 3.5 months old. **The shard's graded claims are authoritative.** Where the index row or `business-validation.md` state a claim flatly (for example "no revenue share" or "8 departments"), this card uses the shard's hedged grading instead.
>
> **Rep rules for this card:**
> 1. **"No revenue share" is INFERRED.** It is not quoted vendor policy. Say "their published pricing shows no revenue share", not "Cofounder has a no-rev-share policy."
> 2. **Do not cite a department number.** The index and `business-validation.md` say "8 departments" and count legal. The cofounder.co landing page lists 11 functional areas and does not list legal. The two counts are not reconciled. Say "the full spread of company functions."
> 3. **Team $50/mo was "coming soon" at intake.** Check before you say it is or is not available.
> 4. **Do not lead with founder-in-the-loop, breadth, or no lock-in.** Cofounder matches Soleur on all three. Lead with the three moats below.

## Quick Facts

| Field | Value | Grading (shard, 2026-07-22) |
|-------|-------|-----------------------------|
| **Product** | Cofounder: "first full-stack agent company platform." It coordinates agent departments with managers and shared context. Its stated goal is to show a software company run entirely by agents in 2026. | Index/shard description |
| **Company** | The General Intelligence Company of New York. CEO Andrew Pignanelli. | VERIFIED (third-party) |
| **Funding** | **$8.7M seed led by Union Square Ventures (Dec 8 2025).** Acrew Capital and Compound participated, with angels Scott Belsky and Yohei Nakajima. | VERIFIED (Built In NYC / Forbes / TradedVC) |
| **Pricing** | 7-day trial ($10 of usage included) / **Pro $20/mo** (usage included; domain purchase + hosting, agent inboxes, preview environments, project "graduation") / **Team $50/mo "coming soon"** (multiplayer, SOC 2). Usage-based overage. | VERIFIED ([cofounder.co/pricing](https://cofounder.co/pricing)); Team availability not re-checked since intake |
| **Revenue share** | None stated on the pricing page. | **INFERRED.** The absence is real, but "no rev-share" is not verbatim vendor copy. |
| **Department breadth** | Broad. The index and `business-validation.md` list 8 departments: engineering, sales/GTM, marketing, design, finance, legal (LLC incorporation + bank account), ops, customer support. The landing page lists 11 functional areas: engineering, sales, marketing, design, finance, operations, customer support, infrastructure, security, product analytics, payments. Legal is not among them, though "Incorporate LLC" appears as an agent action. | VERIFIED that the breadth exists. **The count is UNRECONCILED (8 vs 11).** |
| **Human-in-the-loop** | "Nothing ships without your approval." Dangerous actions such as Incorporate LLC and Open Bank Account are labeled "Agent requires approval." | VERIFIED (landing page) |
| **Memory** | Three tiers: Working / Core / Long-Term. **"Sleep-time compute"** runs background inference that reorganizes stored information between interactions. Core Memory is described as "compact knowledge representations," so it compresses and distills rather than storing verbatim. Ingests Gmail, Notion, Linear, Slack. Runs in proprietary cloud. | VERIFIED ([GIC memory post](https://www.generalintelligencecompany.com/writing/introducing-cofounder-our-state-of-the-art-memory-system-in-an-agent)) |
| **Ownership** | "Cofounder Pro and Team users can graduate at any point and claim ownership of the GitHub, Supabase, Vercel, and related projects Cofounder manages for them." | VERIFIED verbatim (cofounder.co/pricing) |
| **Workflow model** | Reusable **"Flows"** (one-time setups + ongoing operations) along a guided idea-to-$1B milestone roadmap that triggers agents automatically. | Index/shard description |
| **Extensibility** | MCP, custom APIs, custom skills, or an entire custom codebase. | Index/shard description |

## When You Will Encounter This

- A founder says: "Cofounder does everything Soleur does. It has approval gates, every department, and no revenue cut."
- A founder has already turned down Polsia or NanoCorp because they are too autonomous or take a revenue cut. Cofounder is the obvious next option, and the Polsia/NanoCorp talk tracks **do not work here**.
- A founder compares memory systems ("Cofounder has state-of-the-art memory").
- A founder prices Pro at $20/mo against Soleur Solo at $49/mo.
- A founder wants incorporation and a bank account handled for them.
- An investor-minded prospect cites the USV seed.

## What Cofounder Neutralizes (Be Honest)

Against Polsia and NanoCorp, Soleur's usual contrast is founder-in-the-loop vs. full autonomy, 8 domains vs. a narrow engine, and no revenue cut vs. 20%. **Cofounder matches all three:**

| Usual Soleur differentiator | Status vs. Cofounder |
|---|---|
| Founder-in-the-loop | **Neutralized.** Cofounder has verified approval gates on binding actions. Soleur's structured HITL approval queue for write/send actions is still an open issue ([#4672](https://github.com/jikig-ai/soleur/issues/4672)). On productized approval gates, Cofounder is arguably ahead. |
| Whole-company breadth | **Neutralized.** Both cover the full spread of company functions. Do not argue counts. |
| No revenue share / no lock-in | **Largely neutralized.** Cofounder's published pricing shows no revenue share (INFERRED) and offers ownership graduation (VERIFIED). Soleur's self-serve Solo/Startup/Scale tiers are flat-priced. Note that Soleur's own **Enterprise** tier includes a negotiated sliding revenue share (10% falling to 5%) per `pricing-strategy.md`, so do not say "Soleur never takes a revenue share." |

The index states the conclusion: **the durable contrast narrows to three moats.** Talk tracks lean only on these.

## The Three Moats That Hold vs. Cofounder

1. **Verbatim, git-tracked knowledge base in the founder's own repo, vs. lossy cloud memory.** Soleur's KB is plain files that the founder can read, diff, edit and revert, with full history, in a repo they own. Cofounder's memory is compressed and reorganized in the background into "compact knowledge representations" in proprietary cloud.
2. **A named-artifact lifecycle with explicit review and compound stages.** Soleur runs brainstorm → plan → work → review → compound, and each stage leaves a named, inspectable artifact. Cofounder models work as "Flows" along a milestone roadmap. The index records no explicit review or compound/learning stage in Flows. Treat that as "not documented on our record", not as "Cofounder has no review."
3. **Owned from day one, no "graduation."** Soleur's `provision-github` creates repos in the founder's own GitHub org with the founder's own credentials, so there is never a handover step. Cofounder manages the projects and the founder can claim them "at any point."

A **fourth, weaker** point is local-first: Soleur runs in the founder's existing Claude Code environment. Use it carefully. `business-validation.md` finds that target founders want a visual UI, which the index calls "a liability as much as a moat." Soleur's hosted Command Center (workstream, inbox, routines, domain router) is the better answer to UI questions.

## Differentiator Table

| Dimension | Cofounder | Soleur | Advantage |
|-----------|-----------|--------|-----------|
| **Operating model** | HITL approval gates on dangerous/binding actions (VERIFIED). | Founder-in-the-loop by design. Structured approval queue still open (#4672). | **Parity.** Arguably Cofounder on productized gates. |
| **Breadth** | Full company spread (8 vs 11 count UNRECONCILED). | 8 departments, 67 agents (index, HumanLayer row, 2026-10-24). | **Parity.** Do not argue counts. |
| **Memory form** | Compressed/distilled: "compact knowledge representations," reorganized by sleep-time compute. | Verbatim markdown files, git history, every change diffable. | **Soleur** (fidelity, auditability). |
| **Memory location** | Proprietary cloud. | Founder's own repo. | **Soleur** (ownership, portability). |
| **Memory upkeep** | Automatic background consolidation between sessions. | `/compound` is manual. Background KB consolidation is filed as [#5292](https://github.com/jikig-ai/soleur/issues/5292) (Post-MVP, p3). | **Cofounder.** Concede it. |
| **Memory ingestion** | Gmail, Notion, Linear, Slack. | KB built from lifecycle artifacts. Inbox/SaaS breadth is [#4673](https://github.com/jikig-ai/soleur/issues/4673) (open). | **Cofounder** on ingestion breadth. |
| **Workflow** | "Flows" + guided idea-to-$1B milestone roadmap that triggers agents automatically. | Named-artifact lifecycle: brainstorm → plan → work → review → compound. `product-roadmap` skill creates GitHub milestones. | **Soleur** on explicit review + compound stages. Parity on roadmapping. |
| **Recurring operations** | Ongoing-operation Flows. | Routines exist in the hosted Command Center. Cross-system scheduled automations are [#4674](https://github.com/jikig-ai/soleur/issues/4674) (open). | **Cofounder** for now. |
| **Ownership** | Graduation "at any point" for GitHub, Supabase, Vercel and related projects (VERIFIED). | Founder-owned repos from creation via `provision-github`. | **Soleur, structurally**, but the gap is smaller than it sounds. |
| **Company formation** | Performs LLC incorporation and bank-account setup (with approval). | Drafts legal documents via `legal-generate`. Does not execute formation; that needs a CPO go/no-go. | **Cofounder.** |
| **Extensibility** | MCP, custom APIs, custom skills, custom codebase. | MCP, plugin skills/agents, runs on the founder's codebase. | **Parity** on the record. |
| **Entry price** | Pro $20/mo + usage overage. Trial $10 of usage. | Solo $49/mo. Startup $149, Scale $499 (`pricing-strategy.md`). | **Cofounder** on list price. |
| **Revenue share** | None stated (INFERRED). | None on self-serve tiers. Enterprise has a negotiated sliding share. | **Parity** for the solo-founder ICP. |
| **Backing** | $8.7M USV-led seed (VERIFIED). | Early stage, dogfooded on soleur.ai. | **Cofounder.** |

## Talk Tracks

### "Cofounder does everything Soleur does, with approval gates too."

**Response:** "You're right that Cofounder is the closest thing to Soleur out there. It keeps you in the approval seat, covers the whole company, and doesn't take a cut of revenue. So the question isn't who has more departments. It's **where your company's memory lives and what form it's in.** With Soleur, every decision, plan, review and lesson is a plain file in your own git repo. You can read it, diff it, roll it back, or take it anywhere. Cofounder's memory is a compressed summary in their cloud. They describe it as 'compact knowledge representations' that get reorganized in the background. That's clever engineering. But six months in, when you need to know exactly what was decided and why, you want the record, not a summary of it."

### "Cofounder's memory is state-of-the-art. It consolidates itself while I sleep."

**Response:** "It does, and that's a real convenience. Our consolidation is a deliberate step today, and background consolidation is on our roadmap. The trade-off is fidelity and ownership. Sleep-time compute rewrites what's stored. Soleur keeps the verbatim artifact, and git keeps every prior version. You can see exactly what changed in your company's knowledge and when, and undo it. If an agent ever acts on a wrong memory, you can find the line and fix it. You can't diff a compressed representation in someone else's cloud. Ask Cofounder how you'd audit or correct a specific memory, and whether you can export it in readable form."

### "Cofounder's Flows and milestone roadmap take me from idea to $1B."

**Response:** "A guided roadmap is useful, and Soleur's roadmap skill turns yours into GitHub milestones too. The difference is what happens **inside** each piece of work. Soleur runs every task through brainstorm, plan, build, review, and compound, and each stage leaves a named artifact you can inspect. The review stage catches problems before they ship. The compound stage turns what you learned into a rule the next task follows automatically. That's how the system gets better at *your* company over time. Ask how Cofounder's Flows handle review, and how a mistake in one Flow changes what the next one does."

### "Cofounder lets me own everything. I can graduate whenever I want."

**Response:** "Good. Neither of us wants to lock you in. The difference is the starting point. With Soleur, your repos are created in your own GitHub org from day one, so there is nothing to graduate from and no handover to plan. Your knowledge base lives in that same repo. One question worth asking Cofounder: their graduation language names your GitHub, Supabase and Vercel projects. Does the memory come with you too, and in what format?"

*(Note for reps: the verbatim graduation quote does not mention the memory store. Ask it as a question. Do not assert that memory is excluded.)*

## Objection Handling

| Objection | Response |
|-----------|----------|
| "Cofounder is $20/month. Soleur is $49." | "On list price, Cofounder is cheaper to start. Pro is $20 plus usage overage, so check what your actual usage costs. Soleur Solo is a flat $49 and includes every department. The real comparison is what you're buying: a knowledge base you own verbatim in your repo, and a lifecycle with built-in review. If those don't matter to you, Cofounder's price is hard to beat." |
| "Cofounder incorporates my LLC and opens my bank account." | "That's a real capability we don't match. Soleur drafts your formation and legal documents but doesn't execute incorporation or banking. If you need that done for you this week, use Cofounder or a formation service like Stripe Atlas or Firstbase, and keep running your company in Soleur. Formation is a one-time event. Where your company's memory lives is a permanent one." |
| "Cofounder has agent inboxes and pulls in my Gmail, Slack, Notion and Linear." | "That's ahead of us today. Inbox and SaaS-integration breadth is on our open roadmap. What Soleur gives you now is a knowledge base built from the work itself: decisions, plans, reviews and lessons, kept verbatim. Ingesting more sources is useful. Owning a faithful record of what you decided is the harder thing to retrofit." |
| "Cofounder has approval gates. Your founder-in-the-loop pitch isn't special." | "Agreed, it isn't special against Cofounder. Both of us keep you in charge of binding actions, and that's the right design. The difference is what the gates sit on top of: Soleur's named, reviewable artifacts in your own repo, and a compound stage that learns from every decision you approve or reject." |
| "No revenue share at Cofounder either. So what's the cost difference?" | "For a solo founder there isn't one on revenue. Neither takes a cut on self-serve plans, and Cofounder's pricing page shows none. Compare on memory ownership and workflow instead." *(Do not claim Soleur never takes a revenue share. Enterprise pricing is negotiated and includes a sliding share.)* |
| "Cofounder covers 11 departments." | "Both of us cover the whole company. Counts depend on how you group functions. Pick the three that matter most to you this quarter and let's compare the output side by side." |
| "USV backed them. That's safer." | "USV's bet confirms that running a business with agents is a real category, which is good for us too. Funding tells you about runway, not about where your data lives. If Cofounder pivots, gets acquired, or reprices, your Soleur knowledge base is still sitting in your own repo." |
| "I don't want a terminal. Cofounder feels like a product." | "Fair. Most founders tell us the same. Soleur has a hosted web platform (the Command Center, with workstream, inbox and routines), and the plugin is there if you want to work in Claude Code. Let me show you the web experience." *(Do not over-sell local-first to non-technical founders. The index flags it as a liability as well as a moat.)* |

## Discovery Questions (Use in Head-to-Head Deals)

1. "If an agent acts on something it remembered wrong, how would you find and fix that memory?" (Tests memory auditability.)
2. "When you graduate a project, does the memory come with it, and in what format?" (The verbatim graduation quote does not say.)
3. "How does a mistake caught in one Flow change how the next Flow runs?" (Tests whether there is a compound/learning stage.)
4. "What did your usage overage come to in the last month?" (Tests the $20 vs $49 comparison.)
5. "Do you need incorporation and banking done for you, or is your entity already formed?" (Finds the one capability we concede.)

## Claims Reps Must NOT Make

- "Cofounder has no memory" or "Cofounder forgets." It has a verified three-tier memory system. The contrast is **verbatim and owned vs. compressed and cloud-hosted**.
- "Cofounder is fully autonomous." Its approval gates are verified.
- "Cofounder has no review stage." Our record doesn't document one. That is not proof it doesn't exist.
- "Cofounder's graduation excludes memory." It is unstated. Ask, don't assert.
- Any bare department count for Cofounder (8 vs 11 is unreconciled).
- "No revenue share" phrased as a quoted Cofounder policy. It is INFERRED.
- "Team plan isn't available." It was "coming soon" at intake and has not been re-checked since.
- "Soleur never takes a revenue share." Enterprise pricing includes one.

## Convergence Watch

Review monthly. Cofounder is the highest-overlap Tier 3 competitor. Any Tier 3 positioning rewrite ([#6827](https://github.com/jikig-ai/soleur/issues/6827)) must start from the shard's source-verified grading.

| Trigger | Current Status (as of intake 2026-06-14 / verified 2026-07-22; not re-checked 2026-11-01) | Action if Triggered |
|---------|---------------------------|-------------------|
| Cofounder ships verbatim, exportable, or git-backed memory | Memory is compressed and reorganized in proprietary cloud. | **Critical escalation.** Moat 1 is neutralized. Fall back to the named-artifact lifecycle and day-one ownership, and escalate to CPO for a positioning rewrite. |
| Cofounder adds an explicit review or learning stage to Flows | Not documented on our record. | Moat 2 narrows. Re-test with discovery question 3. Shift weight to memory fidelity and ownership. |
| Graduation explicitly includes memory export | Verbatim quote names GitHub, Supabase, Vercel and related projects only. | Retire the "does memory come with you?" question. Moat 3 narrows to "no handover needed." |
| Team $50/mo tier launches (multiplayer, SOC 2) | "Coming soon" at intake. | Update pricing comparison vs. Soleur Startup ($149). Expect overlap with founding-team prospects. |
| Cofounder publishes a revenue-share or usage repricing | No revenue share stated (INFERRED). Pro $20 + usage. | Update pricing objections. |
| Cofounder raises again or ships a major version | $8.7M USV seed (Dec 2025). | Update traction framing. Track funding and version cadence monthly, per the index. |
| Cofounder ships a Claude Code plugin or a local-first runtime | Not on record. | Local-first point is lost. Lean entirely on moats 1–3. |
| Soleur ships #4672 / #4673 / #4674 / #5292 | All open. | Update the Differentiator Table rows that concede the approval queue, ingestion, recurring operations and background consolidation. |
| CPO decides on company-formation execution | Decision pending; drafting only today. | Update the formation objection. |

## Sources

All facts are via the CI index and the [Cofounder detail shard](../../product/competitive-intelligence/tier-3-cofounder.md). None were re-fetched on 2026-11-01.

- [cofounder.co](https://cofounder.co/) (landing page: approval gates, functional-area list)
- [cofounder.co/pricing](https://cofounder.co/pricing) (tiers, verbatim graduation language)
- [GIC memory post](https://www.generalintelligencecompany.com/writing/introducing-cofounder-our-state-of-the-art-memory-system-in-an-agent) (three-tier memory, sleep-time compute)
- [GIC seed post](https://www.generalintelligencecompany.com/writing/cofounder-1.5-and-8.7-million-seed), [Built In NYC](https://www.builtinnyc.com/articles/general-intelligence-company-raises-8m-seed-20251212), [USV](https://blog.usv.com/the-race-to-run-businesses-autonomously-cofounder-by-the-general-intelligence-company-of-new-york) (funding)
- Soleur pricing: `knowledge-base/product/pricing-strategy.md` (Solo $49 / Startup $149 / Scale $499; Enterprise negotiated)

---

_Created: 2026-11-01 (downstream-sync cascade; no new web facts). Source: competitive-intelligence.md (2026-11-01 index; Cofounder data as of 2026-06-14 intake, convergence claims source-verified 2026-07-22)._
