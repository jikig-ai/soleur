---
title: "A Map That Can't Drift"
seoTitle: "A Map That Can't Drift: The Feature Map That Guards Itself"
date: 2026-11-05
description: "We gave our product's feature map a guard that fails when the map and product disagree — then review found four ways the guard itself could lie."
ogImage: "blog/og-map-that-cant-drift.png"
pillar: billion-dollar-solo-founder
tags:
  - agentic-verification
  - methodology
  - documentation
  - solo-founder
  - build-in-public
  - pillar
---

You cannot keep your own product honest by memory. Every founder learns this the embarrassing way: the onboarding tour that describes a screen you renamed three months ago, the help article that walks a customer through a flow you no longer offer, the marketing page still promising a feature you quietly removed. Nothing in a solo company is assigned to keep those documents true, so they drift — politely, invisibly, and always in the direction of promising more than the product actually does.

An AI helper makes this worse, not better. An agent navigating your product builds its own private map on every run — which page does what, how a user gets there, what they should find — and throws the map away when the session ends. Tomorrow it builds the map again, slightly differently. There is no shared memory to correct, and nothing that ever tells the map it is wrong.

We hit this wall building our own platform, and the fix we shipped sounds like paperwork until you watch it work: a written map of the product that carries its own enforcement. A map the product cannot drift away from.

## A map with thirty-two entries — and a reason for every absence

The map itself is a single document listing every distinct page a visitor can reach in our product — thirty-two of them. Twenty-seven get a full entry: how a real user reaches the page, which stable landmarks an agent can look for, and what the user should find when they arrive. The other five get no entry, and that is deliberate — each one sits on a short exemption list inside the same document, each with a written reason. An onboarding step that exists only as a funnel page. A public share link that needs a real token before it shows anything. Pages that are real but are not features, and the map says exactly why.

That last clause — "with a written reason" — is the discipline. An exemption without a reason is just a page somebody forgot, wearing a better name.

## The guard that checks both directions

A document that lists what exists drifts in two directions at once. New things appear that it never recorded. And things it recorded quietly stop existing.

So the guard that keeps the map honest checks both. Add a page and forget to update the map — the check fails. Delete a page and leave its entry behind — the check fails, because an entry for a page that no longer exists is the most dangerous line in the whole document: it sends whoever reads the map looking for something that is not there, with full confidence.

The guard also checks that entries are real. Every entry must carry its required fields — how a user reaches the page, what they should see — not just a heading and some prose. A page cannot sit in the mapped list and the exemption list at the same time; the classification has to pick a side. And nothing formatted as an example inside the document may count as a real entry.

That last rule exists because of what our review panel found. Which is the part of this story that earned the post.

## Four ways the guard itself could lie

Before the map shipped, our reviewers graded the guard the way we now grade every check that will be trusted: name an input that satisfies the check while violating the property it claims to enforce. They found four.

**The census that counted thirty-one of thirty-two.** The guard builds its list of real pages with a file-listing pattern — the kind that says "find me every page file inside every folder." Measured against an independent count, that pattern returned thirty-one files where there were thirty-two. The missing one was the homepage itself: the pattern requires at least one folder between the starting point and the file, so the single page file sitting at the front door was never counted. A census that under-counts does not look broken — it looks green forever, because the check can only see what the pattern returned.

**A completeness check satisfied by a mention.** Each entry has required fields — how a user reaches the page, what they should see there. The first version of the check searched each entry's text for those field names. A sentence inside an entry that merely mentioned a field — the equivalent of "see the field list above" — satisfied the check for an entry that had never filled the field in. Presence is not conformance: a check that searches for a word cannot tell the difference between a filled-in field and a sentence about one.

**The example that counted as real.** The map document shows its own format — a worked example of what an entry looks like, included so a human reader can follow the pattern. But the guard reads the document line by line, and a line sitting inside a formatted example block looked exactly like a real entry to it. An illustration of an entry could certify a page nobody had ever verified. The fix was blunt: the document's own convention now forbids example blocks entirely — the map never needed them, and banning the construct is far cheaper than teaching the checker to ignore it.

**Two scoreboards for the same question.** The guard tracked early errors in one tally and check failures in another, then asked "did anything fail?" against a hand-maintained list of counters. Any future check added to the guard that reported a problem but forgot to register its counter would report-and-pass — the finding would print, and the run would still come back green. Now there is one ledger: every check adds to it, and it is the only thing the final verdict reads.

Four ways for "the map is correct" to be a lie — each subtle, each caught before a single agent relied on it.

## The general lesson: any count can be quietly short

One of those four is worth pulling out on its own, because it reaches far past our document: any check built on a listing can under-count and stay green. A pattern that returns thirty-one results where there are thirty-two looks identical to a pattern that is working — the missing item is invisible precisely because the pattern never produced it. And a check that reports its findings on one channel and its verdict on another can always drift into reporting without failing.

That yields two habits, both cheap. First, when a check counts things, count them a second way and compare — not because the second count is more trustworthy, but because the disagreement is the signal. Second, before you trust a check, prove it can go red: hand it a tree you know is wrong and watch it fail. A check that has never failed is a hypothesis, not a guard. Ours now ships with a companion battery that does exactly that — it deliberately breaks the tree underneath the check and demands the check notice.

## What the guard does today — stated plainly

Here is the honest scope, because a post about honest verification should not oversell its own machinery. The guard runs as part of our full local test suite, where a disagreement between the map and the product fails the run. In continuous integration — the pipeline that re-runs our checks on every proposed change — it currently reports rather than blocks. That is a deliberate staging choice while the guard earns trust, not an oversight, and the document itself says so in writing.

Enforcement that reports is still enforcement: the finding prints, names the page, and says which direction it drifted. What the guard does not yet do is stop a merge — and this post will not pretend otherwise. The day it gets promoted, the only thing that changes is the volume. The check itself stays the same.

The same idea also exists for a founder's own codebase — a companion post tells that story: [the map that only records what the agent saw]({{ site.url }}/blog/map-that-only-records-what-the-agent-saw/).

This story is one spoke of [the four days we spent shipping a trust checklist]({{ site.url }}/blog/agentic-verification-checklist-shipped/), the day-by-day account of the whole arc.

## What a founder takes from this

You do not need our machinery to use the lesson. Whatever keeps your company's documents honest — a wiki, a help center, an internal handbook, a feature list on your pricing page — ask it the question our reviewers asked: what makes this true? If the honest answer is "somebody remembers to update it," the document is already drifting; the only question is how far. The fix is rarely a better document. It is a check that can fail — one that counts in both directions, and one you have watched go red on purpose.

And if you hand your product to an AI to test, audit, or drive, give it the same thing we gave ours: a map it can read, and a guard that keeps the map honest. An agent working from a maintained map navigates. An agent rebuilding its own private map from scratch on every run is guessing — confidently, fluently, and without ever telling you it guessed.

For the full technical post-mortem — the exact file-listing trap, the three parser defects, and the test battery that now mutates the tree underneath the guard to prove it still sees red — see [the write-up on GitHub](https://github.com/jikig-ai/soleur/blob/main/knowledge-base/project/learnings/2026-10-20-a-census-guard-under-counts-on-both-enumerators.md). And if this is the kind of verification machinery you want wrapped around the AI work in your own company, [join the waitlist](https://soleur.ai/pricing/#waitlist).

## Frequently Asked Questions

### What is a feature map?

A feature map is a written inventory of everything your product does from the user's point of view — each page or screen, how a real person reaches it, and what they should find there. Unlike documentation that is written once and left to rot, a feature map lives next to a check that keeps it honest, so it stays true instead of becoming a confident lie.

### How can documentation check itself?

By comparing the document against the thing it describes, in both directions. Anything real that is missing from the document is a failure, and anything in the document that no longer exists is a failure too. The document becomes something software can verify rather than something a person has to remember to update.

### Why did the checker need checking?

Because a check that under-counts, or that can report a problem and still pass, is worse than no check at all — it shows green while certifying nothing. Reviewers found four distinct ways ours could have lied, from a file listing that skipped the homepage to two separate tallies for "did it fail." Each was fixed before anyone relied on the map.

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "What is a feature map?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "A feature map is a written inventory of everything your product does from the user's point of view — each page or screen, how a real person reaches it, and what they should find there. Unlike documentation that is written once and left to rot, a feature map lives next to a check that keeps it honest, so it stays true instead of becoming a confident lie."
      }
    },
    {
      "@type": "Question",
      "name": "How can documentation check itself?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "By comparing the document against the thing it describes, in both directions. Anything real that is missing from the document is a failure, and anything in the document that no longer exists is a failure too. The document becomes something software can verify rather than something a person has to remember to update."
      }
    },
    {
      "@type": "Question",
      "name": "Why did the checker need checking?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Because a check that under-counts, or that can report a problem and still pass, is worse than no check at all — it shows green while certifying nothing. Reviewers found four distinct ways ours could have lied, from a file listing that skipped the homepage to two separate tallies for \"did it fail.\" Each was fixed before anyone relied on the map."
      }
    }
  ]
}
</script>
