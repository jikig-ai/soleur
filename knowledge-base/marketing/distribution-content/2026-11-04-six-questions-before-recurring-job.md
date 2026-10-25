---
title: "Before Your AI Team Takes a Recurring Job, It Answers Six Questions"
type: spoke
publish_date: 2026-11-04
channels: x, bluesky, discord, linkedin-personal
status: draft
issue_reference: "#11074"
---

## X/Twitter Thread

**Tweet 1 (Hook):**
Before our AI team is allowed to create a new recurring job, it has to write down six things about it.

Until the answers exist, the job doesn't exist.

Here's why that turned out to matter more than it sounds.

**Tweet 2:**
2/ The six questions every new recurring job must declare — trigger, what it reads and writes, what it hands off next, how a person steps back in, why it can't do the same work twice, and how the thing that assigns work avoids assigning it twice.

**Tweet 3:**
3/ The subtle one: jobs waiting their turn is not the same as work not happening twice. A line at a bakery is orderly — it doesn't stop two customers ordering the same cake. Order is a courtesy. Idempotence is a property.

**Tweet 4:**
4/ The honest part: our first version watched three doors we knew about. Enumerating every way a background job is born found seven — including API calls that leave no file at all. A gate watches the doors it knows.

**Tweet 5:**
5/ Full post — the six questions written for a founder's automation pile, not just ours:

https://soleur.ai/blog/before-your-ai-team-takes-a-recurring-job/

## Bluesky

Before our AI team may create a new recurring job, it must answer six questions first — trigger, reads/writes, handoff, human re-entry, dedupe, source dedupe. A "jobs wait their turn" answer is a hard reject. And the honest part: our first gate watched 3 doors; enumeration found 7.

https://soleur.ai/blog/before-your-ai-team-takes-a-recurring-job/

## Discord

New spoke in the agentic-verification arc: **Before Your AI Team Takes a Recurring Job, It Answers Six Questions**

Every NEW autonomous task now declares six answers at creation time — trigger, services, next, human re-entry, semantic dedupe, source dedupe. `concurrency: group:` alone is a hard reject (it serializes runs; it doesn't dedupe work). The structural-enumeration story: the gate's first detection watched three doors; a review seat found seven substrate families a background job can enter through — including API-armed reminders that leave no file behind.

Post (founder register): https://soleur.ai/blog/before-your-ai-team-takes-a-recurring-job/
Technical write-up (the map of all seven doors): https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/architecture/factory-map.md

## LinkedIn Personal

Every business I talk to has the same quiet problem: scheduled automations accumulate — an invoice reminder here, a weekly report there — and six months later nobody can name what runs, what it touches, or whether two of them are doing the same job twice.

We decided that answer can't live in anyone's head. Before our AI team is allowed to give itself a new recurring job, it writes down six things about that job — and until the answers exist, the job doesn't exist.

Two of the six are subtler than they look:

1. "Jobs wait their turn" is not "the work can't happen twice." A line at a bakery is orderly; it doesn't stop two customers ordering the same cake. An answer of "the jobs queue" is now a hard reject — the job has to name a real deduplication mechanism.

2. Our first version of the gate watched the three doors we already knew. Enumerating the structure found seven ways a background job gets born — including API calls that leave no file behind at all. A rule that watches the doors you know is a rule that watches the doors you know.

The post is written for the founder whose automation pile grew by accretion — the questions work for any system, not just ours:

https://soleur.ai/blog/before-your-ai-team-takes-a-recurring-job/
