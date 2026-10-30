---
title: "The Map That Only Records What the Agent Saw"
seoTitle: "The Map That Only Records What the Agent Saw"
date: 2026-11-12
description: "An AI checking your product needs a map it cannot fabricate: record only the pages the agent visited, correct only what a run contradicted."
ogImage: "blog/og-map-that-only-records-what-the-agent-saw.png"
pillar: billion-dollar-solo-founder
tags:
  - agentic-verification
  - methodology
  - testing
  - solo-founder
  - build-in-public
  - pillar
---

Ask your AI to check whether your product still works, and it will happily start clicking. Ask it again next week and it starts from zero — re-deriving how your pages fit together, guessing which menu leads where, discarding everything it worked out the moment the session ends. That is not testing. It is tourism.

The fix is a map: a written inventory of what your product does from the user's side of the screen, so the agent navigates instead of wandering. But a map an agent writes carries a failure no paper map ever had — it can describe, in confident detail, places the author never visited. This is the story of the convention we wrote to make that impossible, and of the review that caught the check that was supposed to protect it.

## An agent without a map pays for discovery on every run

Without a map, every verification run burns its effort twice over: first discovering that a billing page exists, then discovering how a real user reaches it. Worse, the discovery is ephemeral. Whatever the agent worked out about your navigation evaporates at session end, so the next run guesses again — and a lucky guess is indistinguishable from a verified route.

The flailing has a signature. The agent mistakes a wrong turn for a missing feature. It takes a shortcut no customer could take and reports a page healthy that a signed-out visitor never sees. It spends its budget re-deriving the shape of your product instead of checking the product itself — and on a solo founder's budget, that re-derivation is the difference between a check that finished and one that ran out of room. Keeping the map — the thing every run was rebuilding and then throwing away — is the fix, and it is what turns wandering into navigation.

## One file, one home, one entry per reachable page

The convention we shipped is a contract in three parts. The first is the artifact itself: a single map file that lives with the project at one pinned location inside its documentation, so every agent that needs it looks in exactly one place — and a missing map is unambiguous, not merely somewhere else.

The second is the entry shape. Each reachable page gets one entry written in a fixed grammar: how a real user gets there, whether a menu path or a direct link; the stable on-screen landmarks an agent can check for; what the user should find on arrival; whether a sign-in is needed; and the traps that make a naive check wrong — a table that fills in a beat late, a banner that only appears some days. Every field is written from the user's side of the screen — what a person reaches and what they see — never from the machinery underneath, because the map exists to steer a check that pretends to be a user. A short section at the end lists the pages deliberately left unmapped, each with a written reason, so "not in the map" never silently means "forgotten."

The third part is the pair of rules that decides what the map may claim — and it is the reason the document exists at all.

## A map may only record what the agent actually saw

Here is the failure the convention exists to prevent. An agent asked for a map can produce one — every page, every landmark, every expectation — for routes it has never once visited. The invented entries read exactly like earned ones. Only they are fiction: landmarks that may not exist, outcomes nobody verified, confidence with no walk behind it. A fabricated entry is worse than a missing one, because the next agent navigates straight toward anchors that were never there.

So the contract draws its line where trust lives: the map may only seed the routes a run actually exercised. No visit, no entry. The agent may still enumerate what exists — a skeleton of pages derived from the product itself — but the fields that make an entry worth believing come only from observed navigation. And if a run exercised nothing at all, no map is written. An empty walk produces no record. A vacuous map certifies nothing.

That is a harder discipline than "document everything," and deliberately so. It accepts a partial map — the map is authoritative per page, never a reason to skip a page it does not cover — because a smaller truth beats a larger fiction. What grows the map is use: each real run appends the pages it genuinely walked.

## Only the fields a run contradicted get corrected

A map you cannot annotate is a map you will stop trusting. You will add your own notes — this banner is a deliberate experiment, that landmark is scheduled to change — and a wholesale rewrite would erase them on the next run. So updates are field-scoped: a run corrects only the fields it directly contradicted, and appends entries for newly visited pages. Everything else — including every note you wrote — stays exactly as it was.

And the guard that keeps the map honest is not a separate checker. It is the update contract itself: a change that adds, renames, or removes a page carries its map edit in the same change, and the map states that rule in its own header, so whoever reads the artifact sees the deal that protects it. Presence, not conformance — an agent that relies on the map looks for it at the one pinned place and reads what is there; the contract, not a gate, is what keeps it true. Teams that want the contract enforced mechanically can add an automated check, and the document sketches what one verifies — the harder version of that story, where we built such a check for our own product's map and found four ways it could lie, is the companion post's to tell: [a map that cannot drift]({{ site.url }}/blog/map-that-cant-drift/).

## The review that caught the checker

The convention shipped through the same review gauntlet as everything else in this arc — which means its own verification was audited too, and the audit caught a lie.

To prove the map document was properly linked where the system could find it, the plan prescribed a control: on a scratch copy, remove the link, and watch the reachability check turn red. It could not. The check did not look for the link at all — it counted the document's name appearing anywhere in the surrounding text, and after both links were deleted, the name survived in five other mentions. The control reported green either way. A test that could never fail had certified the link.

The person running the control and the reviewer re-verifying it hit the same wall independently, and each had to derive the faithful version alone: remove every occurrence of the name — the thing the check actually reads — and only then watch it go red. The rule that came out of it generalizes well past this map: a negative control must remove what the check reads, not what the change happened to add.

## What this is really about

The map is one thread of [the four days we spent shipping a trust checklist]({{ site.url }}/blog/agentic-verification-checklist-shipped/) — the day-by-day account this story is a spoke of. But the rule underneath it applies to any document an AI writes for a later reader, human or machine.

A record is trustworthy in proportion to how hard it is to fabricate. Your AI can draft anything; the question is what it is permitted to assert. Ask it for a map of the whole product and it will oblige — plausibility is its job. The convention's answer is to narrow what "obliging" is allowed to mean: a map that records only what the agent saw, and corrects only what a run contradicted, cannot claim a visit that never happened. That constraint, not the document's format, is what makes the next run's navigation worth trusting — and the same constraint is worth demanding of any report, summary, or inventory your AI hands you: show me the walk, not the confidence.

For the convention itself — the entry grammar, the seed contract, the field-scoped refresh — see [the shipped document on GitHub](https://github.com/jikig-ai/soleur/blob/main/plugins/soleur/skills/test-browser/references/feature-map.md). And if you want this kind of discipline wrapped around the AI work in your own company, [join the waitlist](https://soleur.ai/pricing/#waitlist).

## Frequently Asked Questions

### Why can't the agent write the whole map at once?

It can draft the skeleton — the list of pages that exist. What it cannot do honestly is fill in the details for a page it never visited: the landmarks to check, what the user should find, the traps that break a naive check. Those fields are the map's value, and invented ones send the next agent hunting for things that were never there.

### What happens to notes I add to the map?

They survive. Updates are field-scoped: a run rewrites only the fields it directly contradicted and appends entries for newly visited pages. Untouched entries — and every annotation you added — stay exactly as you left them.

### Where does the map live in my project?

In a single file at one pinned location inside the project's documentation folder — one place, so every tool that needs the map knows where to look. It is working material for your AI, not a page you publish for customers.

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Why can't the agent write the whole map at once?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "It can draft the skeleton — the list of pages that exist. What it cannot do honestly is fill in the details for a page it never visited: the landmarks to check, what the user should find, the traps that break a naive check. Those fields are the map's value, and invented ones send the next agent hunting for things that were never there."
      }
    },
    {
      "@type": "Question",
      "name": "What happens to notes I add to the map?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "They survive. Updates are field-scoped: a run rewrites only the fields it directly contradicted and appends entries for newly visited pages. Untouched entries — and every annotation you added — stay exactly as you left them."
      }
    },
    {
      "@type": "Question",
      "name": "Where does the map live in my project?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "In a single file at one pinned location inside the project's documentation folder — one place, so every tool that needs the map knows where to look. It is working material for your AI, not a page you publish for customers."
      }
    }
  ]
}
</script>
