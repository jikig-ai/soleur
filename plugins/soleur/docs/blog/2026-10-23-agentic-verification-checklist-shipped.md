---
title: "A Checklist for Trusting AI Work Was Just Published. We Shipped All of It."
seoTitle: "The Checklist for Trusting AI Work, Shipped in 4 Days"
date: 2026-10-23
description: "An expert published a checklist for trusting what AI produces. We shipped every row in four days — and the reviews found real bugs in the verifiers."
ogImage: "blog/og-agentic-verification-checklist.png"
pillar: billion-dollar-solo-founder
tags:
  - agentic-verification
  - ai-trust
  - methodology
  - solo-founder
  - build-in-public
  - pillar
---

If you use AI tools to run parts of your business, you have already made a quiet bargain: you stopped checking every line, because checking every line is the job you were trying to stop doing. The leverage is real. So is the question underneath it — what if it's wrong?

That question is the number-one hesitation founders have about delegating to AI, and it deserves a better answer than "trust me." It just got a much better answer. Addy Osmani — an engineering leader whose writing on AI-assisted development is among the most followed in the industry — published [a checklist for agentic verification](https://addyo.substack.com/p/agentic-verification): the practice of giving an AI system ways to check its own work, so a human reviews evidence instead of re-doing the work.

We read it the day it came out, measured ourselves against every row, and shipped what was missing. Seven changes in four days — some in our own codebase, most in the workflows we hand to the founders who use Soleur. But the speed is not the story worth telling. The story is that almost every piece of verification machinery we shipped arrived with a real defect in the machinery itself — caught by reviewers before a single user saw it. A checklist for trusting AI work turns out to be the easy half. The hard half is trusting the verifiers.

## What the checklist actually asks for

Osmani's argument in one sentence: the bottleneck has moved from producing work to knowing the work is correct, so the durable investment is giving the agent ways to verify its own output. The checklist is concrete:

- **Test what a real user sees.** End-to-end checks that sign up, click through, and confirm the outcome — the ground truth a unit check can share a misunderstanding with and still pass.
- **Test the rules, not the examples.** Property-based testing: instead of checking a handful of hand-picked inputs, you state a rule that must always hold — "running this twice changes nothing the second time" — and a generator throws thousands of random inputs at it trying to break it.
- **Keep a feature map.** A written inventory of what your product does from the user's point of view — what exists, how a real person reaches it, what they should see — so an agent driving the product works from a map, not a guess.
- **When you replace something, compare old and new.** Differential testing: run the old system and the new system side by side over the same inputs, and treat every difference as either a bug or a deliberate, documented change.
- **Make the loop fast and predictable.** Checks that are slow or flaky teach the agent the wrong lesson — it learns to retry instead of fix. A flaky check gets isolated and removed, not tolerated.
- **Write the check before the work.** Define what "correct" means first; the agent iterates toward a target instead of a vibe.
- **Make taste compound.** When the agent gets something wrong, write the lesson down as a permanent, automatic check so it never happens twice.

Measured honestly, we already had three rows solid — the user-perspective test suite, the check-before-work gate, and a written-down-lessons practice that has grown into more than a hundred automatic checks on our own repository. Four rows were missing or only lived inside our walls, invisible to the people we build for. So we shipped all four — and packaged each one so a founder's own codebase gets the same benefit, not just ours.

## The map that guards itself — and the four ways the guard was wrong

The feature map row sounds like paperwork. It is actually the difference between an AI helper that navigates your product and one that bluffs. Our platform has 32 distinct pages and screens a visitor can reach; the map records each one — how a real user gets there and what they should find — and an automatic guard fails the build the moment the map and the product disagree, in either direction.

Our review panel found four defects in that guard before it shipped:

- The counter that enumerates the screens **silently missed the homepage** — it counted 31 of 32, because the pattern it used to list pages skipped the one sitting at the front door. A check that under-counts looks green forever.
- A stray line of descriptive text could **satisfy the completeness check** without the required information actually being present — presence is not conformance.
- An example shown inside the map document — included to teach the format — could be **counted as a real entry**, certifying a page nobody had verified.
- The guard kept **two separate scoreboards** for "did everything pass," and a future check could report a problem and still come back green.

Four ways for "the map is correct" to be a lie, each subtle, each caught before anyone relied on it. This became the theme of the whole four days.

We wrote up [the guard that keeps the map honest]({{ site.url }}/blog/map-that-cant-drift/) — the four defects it caught in itself, and what a coverage check has to prove — as a companion to this post. And for your own agent, [the convention that lets it keep an honest map]({{ site.url }}/blog/map-that-only-records-what-the-agent-saw/) is written up as a companion too — what the map records, where it lives, and how it stays true.

## The test that found a bug on day one — and the example that could never fail

Property-based testing is the row most teams skip, because "generate thousands of random inputs" sounds exotic. It is not. You write one sentence — "cleaning up a value twice must give the same answer as cleaning it once" — and a machine spends its afternoon trying to prove you wrong.

The very first generated test we ran caught a real bug on day one. A small utility that tidies repository addresses — trimming spaces, stripping a trailing suffix — could leave an invisible trailing space behind. Run it on certain inputs, get a subtly different answer, run it again, get a third. The documentation said running it twice was safe; the code disagreed. And once we looked, the same defect lived in a second place where the same cleanup logic ran. No human would have hand-picked that input. A generator finds it immediately because it does not share our imagination about what "reasonable input" looks like.

Then the row taught its own second lesson. When we wrote the guide that teaches our users' workflows to do the same thing, three reviewers independently flagged the guide's own worked example: it was written so that every possible answer — including a completely wrong one — would pass it. An example that cannot fail teaches a practice that cannot catch anything. And after we fixed that, the fix-round found a second layer: a do-nothing program still passed the improved example. Teaching material gets graded like code now, because to a reader it is code.

We wrote up [the full post-mortem]({{ site.url }}/blog/property-test-cannot-fail-teaches-nothing/) — how the example shipped, what the reviewers caught, and what it changed — as a companion to this post. We also wrote up [the day-one bug itself]({{ site.url }}/blog/first-property-test-found-real-bug/) — the input nobody would have hand-picked — as a companion to this post.

## Old versus new, side by side

The differential-testing row exists because of a failure mode anyone who has replaced a system knows: the new version passes its own tests while quietly diverging from the old one in ways nobody documented. Users never relied on the specification; they relied on what the old thing actually did.

The answer is to treat the old system as the referee: feed both versions the same inputs and account for every difference. We shipped that practice into the workflow our users get — any change that moves data through a new path now has to show before-and-after evidence, born from an incident class we had measured where a change applied cleanly and broke everything downstream of it. The companion rule the reviews surfaced: a check that cannot go red is not coverage. If your comparison can only ever report success, it is a formality wearing a seatbelt costume. We wrote up [the differential-testing practice]({{ site.url }}/blog/test-the-migration-not-just-the-schema/) — the old system as referee, before-and-after evidence for every change — as a companion to this post.

## A pass on retry is not a pass

Here is a failure mode unique to AI-driven work. When a check fails sometimes and passes other times with nothing changed, a human knows to be suspicious. An agent learns something worse: retrying is a strategy that works. Osmani's checklist is blunt about it — a flaky check left in the main suite is worse than no check, because it quietly teaches the whole system that "red" is negotiable.

So we shipped a quarantine rule into the fix-loop workflow users get: every newly failed check gets exactly one isolated re-run, and a pass-on-retry on unchanged work is filed as a flake to be quarantined and tracked — never reported as fixed.

And here the reviews caught the sharpest defect of the four days. The rule's own "all clear" row — the line meant to mean "everything that failed turned out to be a flake" — could fire on a run that produced no readable results at all. Zero quarantines, read as green. The success row proved nothing, which is exactly the failure mode the row existed to prevent. A second reviewer found a warning flag whose trigger was empty by construction — it compared the failing check against a list of things the workflow never touches, so it could never be true. Decoration that reads as coverage. We wrote up [the quarantine protocol]({{ site.url }}/blog/flaky-test-passed-on-retry-quarantine/) — one isolated re-run, then the file — as a companion to this post.

## Safety rails you can install

The last row is the one closest to the founder's version of the problem. We run more than a hundred automated checks on our own codebase — the accumulated taste of every mistake that ever got through. Those checks are why our platform's AI work is trustworthy. But a founder's codebase is not our codebase, so we asked the honest question: how much of this is actually portable?

We audited all 102 of our automated checks one by one. The answer: four. Four were generic enough to belong in any repository — a scan for accidentally committed secrets, a check that work never lands straight on the main line, a check against stashing away unfinished work, and a check that catches tests abandoned with nothing left to run. Nearly everything a mature verification system accumulates turns out to be welded to the machinery around it. The audit is the honest part of the story — most teams would have promised a hundred and shipped four quietly.

The four that shipped each have to prove themselves before they are allowed to guard anything. Installing one triggers a rehearsal on a throwaway copy of the repository: the check must catch a real planted violation, then go quiet when the violation is removed. A guard that cannot be proven to fire is a document, not a guard — and it installs nothing if something already sits where it would go, rather than quietly overwriting what you have. We wrote up [the audit's full story]({{ site.url }}/blog/audited-102-guardrails-four-portable/) — every check classified, every verdict explained — as a companion to this post.

## The real lesson: verify the verifiers

Step back and count. The feature map's guard shipped with four defects. The testing guide's own example could never fail — and its first fix still let a do-nothing program pass. The quarantine rule's "all clear" could fire on an unreadable run. The very first property test found a bug humans had been shipping for months. Every row of the checklist arrived with at least one way the verifier itself could lie.

That is not an indictment of the checklist — it is the checklist's deepest row, the one underneath the others. Verification machinery is machinery. It has defects like anything else we build, and a defect in a verifier is worse than a defect in the product, because it converts "unverified" into "verified-looking." A check that cannot fail is worse than no check at all.

The reason our four days produced something trustworthy is not that we built fast. It is that everything we built got reviewed by people and panels whose only job was to ask "how could this be wrong?" — and the build log, defects and all, is public. Trust does not come from the checklist existing. It comes from the machinery being honest about where it almost failed.

## What this means when the company is yours

You cannot personally check everything your AI tools produce. Nobody running a company alone can — that is the whole reason for the tools. So the question was never whether to trust; it is what trustworthy looks like.

It looks like this: checks that behave like a real user, rules tested against thousands of cases you would never think to try, a map of the product that cannot quietly drift, proof when new replaces old, and flakes quarantined instead of retried into silence. And then — the part those four days taught us — reviewers who grade the checks themselves, so a green light means something was actually tested, not merely run.

You stay the decision-maker. What changes is what deciding costs: evidence arrives already examined, and the examiners were examined too. If "what if it's wrong?" is the question keeping you from delegating real work to AI, [join the waitlist](https://soleur.ai/pricing/#waitlist) — this is the system we built to answer it.

For the technical write-up — every defect named, every fix shown — see [the public tracking record on GitHub](https://github.com/jikig-ai/soleur/issues/10397).

## Frequently Asked Questions

### What does "agentic verification" mean in plain terms?

It means giving an AI system ways to check its own work before a human sees it — tests that behave like real users, generated inputs that try to break the rules, comparisons against what worked before. Your job shifts from inspecting every line of output to reviewing evidence that the work already passed.

### How can I tell whether the AI tools I use verify their work?

Ask four questions. Does it check outcomes the way a user would experience them, not just internal steps? Does it test rules against cases nobody hand-picked? Does a check that passes on retry count as fixed — or get quarantined as a flake? And who checks the checks — does anything review the verification machinery itself?

### Isn't verifying the AI's work the same as doing the work twice?

No — verification is where machines are strongest and humans are weakest. Defining what "correct" means takes your judgment once; proving it against thousands of cases takes the machine seconds. You keep the deciding; the system absorbs the checking, which is the part that never scaled.

### Do I need to be a programmer for this to matter to me?

No. The checklist is about software, but the principle is about delegation: anything you hand off — code, contracts, campaigns — is only as trustworthy as the way its output gets checked. When you evaluate an AI tool for your business, "how does it prove its work?" is the question that separates a system you can rely on from one you have to babysit.

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "What does \"agentic verification\" mean in plain terms?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "It means giving an AI system ways to check its own work before a human sees it — tests that behave like real users, generated inputs that try to break the rules, comparisons against what worked before. Your job shifts from inspecting every line of output to reviewing evidence that the work already passed."
      }
    },
    {
      "@type": "Question",
      "name": "How can I tell whether the AI tools I use verify their work?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Ask four questions. Does it check outcomes the way a user would experience them, not just internal steps? Does it test rules against cases nobody hand-picked? Does a check that passes on retry count as fixed — or get quarantined as a flake? And who checks the checks — does anything review the verification machinery itself?"
      }
    },
    {
      "@type": "Question",
      "name": "Isn't verifying the AI's work the same as doing the work twice?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "No — verification is where machines are strongest and humans are weakest. Defining what \"correct\" means takes your judgment once; proving it against thousands of cases takes the machine seconds. You keep the deciding; the system absorbs the checking, which is the part that never scaled."
      }
    },
    {
      "@type": "Question",
      "name": "Do I need to be a programmer for this to matter to me?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "No. The checklist is about software, but the principle is about delegation: anything you hand off — code, contracts, campaigns — is only as trustworthy as the way its output gets checked. When you evaluate an AI tool for your business, \"how does it prove its work?\" is the question that separates a system you can rely on from one you have to babysit."
      }
    }
  ]
}
</script>
