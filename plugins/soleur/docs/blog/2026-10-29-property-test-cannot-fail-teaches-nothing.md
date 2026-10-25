---
title: "A Property Test That Cannot Fail Teaches Nothing"
seoTitle: "A Property Test That Cannot Fail Teaches Nothing"
date: 2026-10-29
description: "We taught our AI to test rules instead of examples — then reviewers caught that the example we shipped to teach it could never fail."
ogImage: "blog/og-property-test-cannot-fail-teaches-nothing.png"
pillar: billion-dollar-solo-founder
tags:
  - agentic-verification
  - methodology
  - testing
  - solo-founder
  - build-in-public
  - pillar
---

Your AI produces work faster than you can check it. That is the bargain every founder makes with these tools, and most days it is a good one. The uncomfortable part is where your confidence actually comes from: checks wrapped around the work — checks you never wrote, cannot see, and mostly take on faith.

Here is the question almost nobody asks of those checks: can this one actually fail?

We learned to ask it inside a guide we wrote to teach our own AI a better way to check its work. This is the story of a teaching document that failed its own lesson, twice, before a single reader saw it. It matters even if you never write a test in your life, because the same question applies to every piece of guidance you hand an AI — and to every green light your tools show you.

## Teaching the AI to test rules, not examples

Ordinary tests check examples: feed in these inputs, expect these answers. That works until the interesting case is the one nobody thought to write down. So we taught the AI in our workflows a stronger habit — the property test. Instead of listing cases, you state a rule that must always hold: "running a cleanup twice changes nothing the second time," or "the sorted result contains the same items that went in." Then a generator throws thousands of random inputs at the rule, trying to break it — including inputs no human would pick, because the machine does not share our sense of what a reasonable input looks like.

The practice proved itself before any teaching was needed: the very first rule it ran caught a real bug on day one — which is why the guidance exists at all. Adoption first, pedagogy second. Then we wrote the guide that would hand the practice to our users' workflows.

## The example that could never fail

The guide went through our review panel — seventeen passes across the reviewers and the fix round — and three reviewers independently flagged the same finding, the release's one real defect at the highest severity grade we assign.

The guide's worked example — the one meant to show what a good property test looks like — had been written so that every possible answer, including a completely wrong one, would pass it. Read the assertion slowly and it says, in effect: "the sorted list equals the original, or it doesn't, or sorting twice works." Every branch of that sentence is a way to pass. There is no input that can fail it — not because sorting is easy, but because the sentence asks for nothing.

An example that cannot fail teaches a practice that cannot catch anything. And because a worked example in a guide is read as endorsement — "this is how we do it" — a vacuous one is worse than no example at all.

## The fix that still let nothing fail

Here is where the story earns its length. Removing the tautology was not enough.

The repaired example checked two genuine rules: the sorted output must contain the same items that went in, and running the routine twice must change nothing the second time. Both are true of a correct sort. Both are also true of a program that returns its input untouched.

A do-nothing program — take the list, hand it straight back — passes "same items out as went in." It passes "running it twice changes nothing." It sorts nothing at all. The reviewers' fix round caught that second layer: only a third rule — the output must actually be in order — closed the example to trivial implementations.

That is the deeper half of the lesson. A check is not cleansed by removing the obviously broken assertion. It is sound only when nothing lazy survives it — when "do nothing and still pass" is no longer on the table.

## The same disease, twice more

Pulled on, the thread kept coming. The same guide carried two more instances of the same shape.

The guide advised checking a round-trip — transform a value, transform it back — by comparing the result against an answer produced by the same machinery being tested. A consistently wrong program passes that check by being consistently wrong on both sides of the comparison. The expected answer has to come from somewhere independent — the plain form the input was supposed to become — or the grader and the contestant are the same entity.

And a small table of recommended tools in the guide made claims nobody had verified. Those rows now carry an explicit unverified label, and the verified rows name the date they were checked. Publishing "we believe this" as though it were "we measured this" is its own species of cannot-fail — a claim with no failure condition attached.

One subtler twin surfaced in the same review: a check elsewhere in the workflow required a phrase to appear, where the ruling demanded it appear exactly once. "Must appear" cannot see a phrase appear twice — a presence check cannot count. When the requirement is "exactly one," the check has to count, not just look.

## The honest ledger

The full count, because this post exists to practice what it preaches. Seventeen review passes across the panel and the fix round. One genuine defect at our highest grade — what the ledger calls a P1 — the example that could never fail. One grade below it, a P2: the self-grading comparison. Roughly ten smaller findings. And zero follow-up issues filed afterward — every finding was fixed before a single reader saw the guide.

That last number is the one that matters. The point of the gauntlet is not that the guide was perfect — it visibly was not — but that its defects were caught where only reviewers could see them.

## Guidance is graded like code

The lesson underneath all of it: instructions you hand to an AI are graded like code. A worked example is not prose — it executes in the reader's head, and whatever it permits becomes the practice it teaches. A vacuous example is not a typo to shrug at; it is a defect in the teaching, with the same blast radius as a bug in the thing being taught.

So the discipline we demand of tests now applies to the documents that teach them. Can this example fail? Does a do-nothing answer still pass it? Is the expected answer produced by the machinery being graded? Three questions, cheap to ask, expensive to skip — and they apply to any guidance you hand an AI, a contractor, or yourself.

This post expands one thread of [the four days we spent shipping a trust checklist]({{ site.url }}/blog/agentic-verification-checklist-shipped/) — the day-by-day account this story is a spoke of.

## What to ask of your own tools

You never have to write a test to use this lesson. The next time an AI tool hands you a check, a score, a green "verified" — ask the one question this whole story hangs on: what would make this fail? If the honest answer is "nothing could," you are looking at decoration wearing the costume of protection. If the honest answer is "we never checked," you know what the check is worth.

And when you write instructions for your own AI tools — a style guide, a checklist, an example of what good looks like — grade the instructions the way you would grade the work. An example that cannot be wrong teaches a standard that cannot be met.

For the full technical post-mortem — every finding, every fix, the three checks we now run on any shipped example — see [the write-up on GitHub](https://github.com/jikig-ai/soleur/blob/main/knowledge-base/project/learnings/best-practices/2026-10-21-shipped-guidance-examples-must-survive-trivial-implementations-and-self-oracles.md). And if this is the discipline you want wrapped around the AI work in your own company, [join the waitlist](https://soleur.ai/pricing/#waitlist).

## Frequently Asked Questions

### What does it mean for a test to be unable to fail?

It means the test was written so that every outcome counts as a pass — including a completely wrong answer. It looks like protection and behaves like decoration: it runs, it reports green, and it can never catch anything. The only test worth keeping is one that can show you a red light.

### How can instructions to an AI be wrong if they read correctly?

Because an example in a guide is not prose — it executes in the reader's head. If the worked example permits a do-nothing answer, the reader learns to permit do-nothing work. A wrong-looking instruction is easy to catch; a plausible-sounding one that demands nothing is the dangerous kind.

### What should I ask about the checks my AI tools rely on?

Ask what would make each check fail, and when it last did. A check with no failure condition is decoration; a claim nobody verified should be labelled as such; and the expected answer should come from somewhere independent of the machinery being graded. Whoever or whatever reviews the checks is the layer that makes "verified" mean something.

### Does this apply to work that is not software?

Yes. Any instruction you hand off — to an AI, a freelancer, a template — is only as good as its failure condition. "The report should cover our metrics" cannot fail if any metrics count. "These three numbers must reconcile" can. The discipline is the same wherever the example lives.

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "What does it mean for a test to be unable to fail?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "It means the test was written so that every outcome counts as a pass — including a completely wrong answer. It looks like protection and behaves like decoration: it runs, it reports green, and it can never catch anything. The only test worth keeping is one that can show you a red light."
      }
    },
    {
      "@type": "Question",
      "name": "How can instructions to an AI be wrong if they read correctly?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Because an example in a guide is not prose — it executes in the reader's head. If the worked example permits a do-nothing answer, the reader learns to permit do-nothing work. A wrong-looking instruction is easy to catch; a plausible-sounding one that demands nothing is the dangerous kind."
      }
    },
    {
      "@type": "Question",
      "name": "What should I ask about the checks my AI tools rely on?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Ask what would make each check fail, and when it last did. A check with no failure condition is decoration; a claim nobody verified should be labelled as such; and the expected answer should come from somewhere independent of the machinery being graded. Whoever or whatever reviews the checks is the layer that makes \"verified\" mean something."
      }
    },
    {
      "@type": "Question",
      "name": "Does this apply to work that is not software?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes. Any instruction you hand off — to an AI, a freelancer, a template — is only as good as its failure condition. \"The report should cover our metrics\" cannot fail if any metrics count. \"These three numbers must reconcile\" can. The discipline is the same wherever the example lives."
      }
    }
  ]
}
</script>
