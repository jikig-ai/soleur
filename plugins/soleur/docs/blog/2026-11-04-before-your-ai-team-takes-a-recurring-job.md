---
title: "Before Your AI Team Takes a Recurring Job, It Answers Six Questions"
date: 2026-11-04
description: "Scheduled automations pile up quietly. Before our AI team may create a new recurring job, it has to write down six answers about it — or the job doesn't exist."
ogImage: "blog/og-audited-102-guardrails-four-portable.png"
pillar: agentic-solo-founder
tags:
  - agentic-engineering
  - solo-founder
  - automation
  - trust
---

Somewhere in your business, a machine does something on a schedule every night. An invoice reminder. A weekly report. A newsletter draft queued for morning. You set most of them up yourself — probably in a hurry, on a Tuesday, because you needed the thing done more than you needed to think about how it would happen.

A few months later, could you name every one of them? What each one touches? Whether any two are doing the same job?

Most founders can't. The automation pile grows by accretion — each piece added in a moment of need, none ever removed, and the inventory lives in somebody's head or nowhere at all. That pile works fine right up until it doesn't, and the failure is always the same shape: something ran twice, something ran and nobody noticed, or something kept running long after it should have stopped.

We decided that answer can't live in anyone's head — including ours. Before our AI team is allowed to give itself a new recurring job, it has to write down six things about the job. Until the answers exist, the job doesn't exist.

## The six questions

Every new recurring job — a scheduled check, a background process, a monitor that watches other monitors — now declares, before it is allowed to exist:

**What wakes it up.** A clock, an event, a person, or another job finishing. If you can't say what fires it, you can't say when it runs.

**What it reads and what it changes.** A job that writes to your billing system deserves a different level of attention than one that writes a draft you'll review. Naming the surfaces makes the risk legible before it's live.

**What it hands off next.** Jobs rarely end. They produce something — a ticket, a report, an alert — and something downstream has to own it. "Nothing" is a valid answer, but it has to be a decision, not an omission.

**How a person steps back in.** When a job goes wrong at 3 a.m., how do you pause it, redirect it, or stop it? If the answer is "dig through the code," the job isn't ready to run unattended.

**Why it can't do the same work twice.** This is the question everyone gets wrong, and it is worth its own section — see below.

**How the thing that assigns work avoids assigning it twice.** When a system can file work for itself — an alert that becomes a task — something has to prevent the same alert from becoming two tasks.

## A line at a bakery is not a deduplicator

The subtle one is the fifth question. Most systems that run recurring work offer a way to make jobs wait their turn — one run at a time, in order. That sounds like protection against duplicate work. It isn't. Making jobs wait their turn is not the same as making sure the work doesn't happen twice.

A line at a bakery is orderly. It does not stop two customers from ordering the same birthday cake.

Our rule makes that distinction a hard requirement: an answer of "the jobs wait their turn" is rejected outright. The job has to name a real mechanism — checking whether the work was already done before starting, leaving a marker so the next run sees it, or keying the work to something that can't be created twice. Order is a courtesy. Idempotence is a property.

## Three doors, or seven

When we built this rule, the first version watched the three doors we already knew about — the place we schedule automations, the place our background functions live, and our registered checks. It would have caught every new job that entered through any of the three.

Then we did the boring thing, which turned out to be the important thing: we enumerated every way a recurring job can be born in our system. Not the ways we remembered — the ways that exist.

Seven. Jobs created inside the database itself. Jobs created by infrastructure files that generate other jobs — a job born one step removed, invisible to anyone watching the final file. Jobs armed by an API call that leaves no file behind at all, so there is nothing for a file-watching rule to see.

A rule that watches the doors you know is a rule that watches the doors you know. The enumeration is what turned a good intention into a gate.

## Why this is a creation rule, not a cleanup rule

The check only applies to new jobs. You can't retrofit trust onto jobs that are already running — the honest answer for those is an inventory, and ours runs as an ongoing audit. But every job that enters the system from now on arrives with its answers already written down.

That asymmetry matters. If the answers are required at creation, the design answers are never a to-do item for a future you. They are written when the job is cheap to change — before it has a reason to exist unchanged.

## What a recurring job must declare

If you run your own automations — in any system, not just ours — the same six questions are worth answering for each one, on paper, before it goes on:

- What wakes it up?
- What does it read, and what does it change?
- What does it hand off when it finishes?
- How do you pause it, redirect it, or stop it at 3 a.m.?
- Why can't it do the same work twice — a real mechanism, not "it waits its turn"?
- If it can file work for itself, what stops it filing the same work twice?

If your automations have quietly become a system nobody fully remembers, that is the moment to get the answers out of your head and into a place they can be checked. [Try Soleur](https://soleur.ai) — we made the answers a condition of the job existing at all.

For the technical write-up — the map that names every one of the seven doors a background job can enter through — see [our factory-map architecture note](https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/architecture/factory-map.md).

## Frequently asked questions

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "How do I find out what automations are running in my business?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Start with an inventory, not an audit. List every scheduled job you can find across every system that runs one — schedulers, databases, background processes, integrations that fire on events. Most founders find several they forgot and at least one doing work nobody owns. The inventory, not the fix, is the first deliverable."
      }
    },
    {
      "@type": "Question",
      "name": "What is the difference between scheduling work and duplicating it?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Scheduling decides when work runs. Duplication is whether the same work can happen twice. A queue that runs jobs one at a time is orderly, but it does not check whether the work was already done. Preventing duplication takes a dedicated mechanism — checking first, marking the work done, or keying it to something unique."
      }
    }
  ]
}
</script>
