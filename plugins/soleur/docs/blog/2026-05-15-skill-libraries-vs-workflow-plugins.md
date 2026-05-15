---
title: "Skill Libraries vs. Workflow Plugins: Two Shapes of Claude Code Extension"
seoTitle: "Skill Libraries vs Workflow Plugins: When to Use Each"
date: 2026-05-15
description: "Portable skill libraries and workflow plugins both extend Claude Code. They answer different questions. Here's how to know which fits your workflow."
ogImage: "blog/og-skill-libraries-vs-workflow-plugins.png"
tags:
  - comparison
  - category-creation
  - claude-code
  - solo-founder
---

Search "Claude Code skills" on GitHub and two very different shapes come back. One repository is a catalog: a long list of self-contained skills you can drop into any Claude Code install, picked individually, used independently. Another shape is the opposite — a single bundle of agents, skills, and a shared knowledge base, opinionated end-to-end, with cross-references between every component.

The instinct is to rank them on shelf size. The catalog looks bigger, the bundle looks narrower, and the comparison ends before the actual question gets asked: which shape fits the work you're doing?

These are two different categories. Each answers a different question. Choosing between them — or running both — depends on what you need Claude Code to do this week.

## What a Skill Library Is

A skill library is a portable catalog of self-contained Claude Code skills. The defining traits: breadth-first coverage, intentional unopinionatedness about how the skills get used, pick-and-mix consumption, MIT-friendly portability across teams and projects.

The canonical exemplar is the [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills) repository — the reference implementation for the portable-library shape. It catalogs a broad collection of skills covering common developer needs (research workflows, data wrangling, documentation generation, project scaffolding) and ships them as independent units. Each skill is its own folder, its own README, its own contract. You can copy one skill into your project, ignore everything else in the catalog, and never touch the rest.

A skill library answers one question: "what's the next useful capability I can add to Claude Code without changing how I work?" The library is a shelf. You walk down it, you take what you need, you go. There is no expectation that skill A is aware of skill B. There is no shared memory between them. Orchestration is your job; the library hands you the pieces.

That shape has real strengths. The library is portable: a skill written for one team's Claude Code install runs on another team's install with no migration. The catalog scales horizontally — adding capabilities widens coverage without changing the core promise. And the unopinionated design respects the user's existing workflow, imposing no convention.

## What a Workflow Plugin Is

A workflow plugin is opinionated orchestration across a lifecycle. Where a library hands you pieces, this shape runs an organization.

Soleur is the canonical exemplar. Soleur ships {{ stats.agents }}+ agents, {{ stats.skills }}+ skills, and a compounding knowledge base, organized across {{ stats.departments }} business departments — engineering, marketing, legal, finance, operations, product, sales, support, community. The agents are not interchangeable parts. The marketing agent reads what the legal agent decided. The competitive-intelligence agent feeds the brand-architect agent. The compound skill captures learnings from every session and replays them into the next one.

The agents and skills are wired through a brainstorm → plan → work → review → compound lifecycle. Each stage is a gate. Brainstorm surfaces ambiguity before plans get written. Plans get deepened, then executed by work. Review catches what work missed. Compound writes the lesson into a knowledge base that every future session reads from. Decisions in session 1 shape what session 50 produces.

The compounding knowledge base is the structural component that separates a workflow plugin from a pile of skills. It is a git-tracked directory of markdown files that every agent reads from and writes to. The brand guide informs the copywriter agent's tone. The competitive-intelligence audit informs the growth-strategist agent's positioning. The institutional learnings from a debugged migration inform the data-integrity-guardian agent the next time someone touches the schema. None of this requires the founder to wire it manually. The cross-domain coherence is the default.

This shape answers a different question: "how do I execute every department of my company without hiring a team?" That is the [Company-as-a-Service]({{ site.url }}/company-as-a-service/) shape — a full AI organization, opinionated end-to-end, designed for the founder running every job alone.

## Why Two Shapes (Not One Hierarchy)

The temptation is to put these on a leaderboard and pick a winner. Resist it. Skill libraries and workflow plugins optimize for different things. Comparing them on the same axis is like comparing a hardware store to a general contractor — same building materials, completely different unit of value.

| Optimizes for | Skill libraries | Workflow plugins |
|----|----|----|
| Distribution model | Pick-and-mix, individual skills | End-to-end lifecycle, all-or-nothing |
| Unit of value | A single capability | A coordinated organization |
| Knowledge flow | Per-skill, ephemeral | Cross-session, compounding |
| Adoption pattern | Copy what you need | Install once, use everything |
| Best fit | Augmenting an existing workflow | Replacing the workflow itself |

Neither column is a deficiency. The library shape exists because some users have a workflow they like and want more capabilities to drop into it. The workflow-plugin shape exists because some users — solo founders especially — don't have a workflow yet and need one that already works.

The wrong question is "which is better?" The right question is "which one does what I need this week?" Sometimes the answer is one. Sometimes both. Sometimes the answer changes as the work changes.

## When a Skill Library Wins

Three founder moments make the portable-library shape unambiguously the right call.

**You need one capability, not a system.** You're working on something that's mostly working. You need a single skill — clean up an Excel export, normalize a JSON schema, generate boilerplate for a new package. You don't want a new lifecycle. You want a tool you can install in two minutes and forget you have until you need it again. The skill library is the shelf you walk to.

**You're evaluating Claude Code itself.** If you haven't decided whether Claude Code is the right substrate for your team, you don't want to commit to an opinionated bundle yet. Pulling individual skills from a portable library is a low-risk way to feel out the platform — the cost of removal is one folder. Library skills are evaluation-friendly by design.

**You already have an orchestration layer.** Some teams have invested years in their own internal workflow — their own brainstorming process, their own QA gates, their own knowledge management. Layering an opinionated lifecycle on top would conflict. A portable library slots in without claiming the orchestration territory.

In each of those cases, the opinionated shape would be the wrong fit. The user already has what it would replace.

## When a Workflow Plugin Wins

The other three moments belong to this shape.

**You're a solo founder running every department.** Marketing campaigns, legal contracts, financial planning, competitive analysis, customer support — every job that a venture-backed company spreads across eight hires. You don't have a workflow that absorbs context across departments because you don't have departments. An opinionated organization is the substitute for the team you didn't hire.

**You need decisions to compound.** A skill-library session 100 starts where session 1 started — fresh, no memory, no accumulated context. For prototyping that's fine. For running a business it's a structural problem: every session re-litigates what was already decided. A compounding knowledge base means the brand decisions from January shape the marketing copy in May without the founder pasting them back into the prompt.

**You want the lifecycle, not only the tools.** Brainstorm before plan, plan before work, review before commit, compound before move-on. The lifecycle is opinionated on purpose: it enforces the discipline a solo founder can't enforce on themselves at 11pm before a release. The skills inside are the executors; the lifecycle is the structure that makes the executors useful.

These are the moments where the [Company-as-a-Service]({{ site.url }}/company-as-a-service/) shape — not a tool, an organization — wins.

## They Stack

The two shapes are not mutually exclusive. A founder running Soleur for cross-domain orchestration can install individual skills from a portable library for one-off capabilities the workflow-plugin shape doesn't cover. Different layers of the stack: the organization runs the lifecycle, the library skills fill specific gaps.

The category-creation point holds: choose the shape based on what you need it to do. Run both when both answer different questions.

## FAQ

**How does alirezarezvani/claude-skills relate to Soleur?**

It is the canonical exemplar of the portable-library category — a different shape, answering a different question. Soleur is the workflow-plugin shape. They sit in different categories, not on the same leaderboard.

**Can I use both?**

Yes. The shapes stack at different layers. The organization runs the lifecycle; library skills fill capability gaps the lifecycle doesn't cover.

**Why isn't there a head-count comparison?**

Counting catalog entries against a coordinated organization's component list is comparing inventory against architecture. The number of library entries says nothing about whether a lifecycle exists, whether knowledge compounds across sessions, or whether agents share context. The right comparison is shape-against-shape, not count-against-count.

**Which shape is right for a solo founder running a company alone?**

The workflow-plugin shape. The defining trait of solo-founder work — running every department without a team to absorb context — requires the compounding knowledge base and cross-domain orchestration that a portable library, by design, does not provide. Use a library to augment specific capabilities; use an organization to replace the team you don't have.

**What about installing both?**

Common and reasonable. The organization should be the substrate; the library can extend specific capabilities the substrate doesn't cover. Order matters: install the workflow plugin first, then layer library skills on top where the gaps appear.

---

If you're a solo founder building toward the company that takes every job off your plate, the workflow-plugin shape is what you want as the substrate. [See how Company-as-a-Service runs every department]({{ site.url }}/company-as-a-service/) — and decide where the library skills slot in around it.
