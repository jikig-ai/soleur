---
title: "A Flaky Test Passed on Retry and the Loop Called It Fixed"
seoTitle: "A Flaky Test Passed on Retry and the Loop Called It Fixed"
date: 2026-11-17
description: "A flaky test passed on retry and the loop called it fixed. We shipped a deterministic quarantine instead — and review caught it lying twice."
ogImage: "blog/og-flaky-test-passed-on-retry-quarantine.png"
pillar: billion-dollar-solo-founder
tags:
  - agentic-verification
  - methodology
  - testing
  - solo-founder
  - build-in-public
  - pillar
---

Your AI produces work faster than you can check it, so checks do the checking for you. That arrangement rests on one condition nobody talks about: the check has to mean something. A check that fails on Monday and passes on Tuesday over the same unchanged work is not a weaker check. It is a different object entirely — and inside an AI-driven workflow it does damage a missing check never could.

This is the story of what we shipped about that, inside the automated fix loop our users' workflows run, and the two ways review caught the machinery lying. It matters even if you never look at a check yourself, because the same question applies to every green light any tool shows you: what does a pass actually prove?

## The failure mode only an AI learns

A check that fails sometimes and passes other times, with nothing changed in between, has a name: flaky. A human engineer watches a failure vanish on re-run and gets suspicious — something underneath is unreliable, and the suspicion is the correct response.

An AI agent learns the opposite lesson. Failed? Run it again. Green this time? Move on. Every pass on retry is a data point the loop files away: red is negotiable, and persistence is a fix. The agent is not being lazy — it is being rational, responding to exactly the evidence it was given. The evidence is the problem.

That is why a flaky check left running is worse than no check at all. No check means everyone knows the work is unguarded. A flaky check means the whole system is being trained, one retry at a time, that failures clear themselves if you wait long enough. When we built the fix loop — the machinery that takes a set of failing checks, diagnoses what broke, and iterates until the work passes — this was the one behavior it could never be allowed to learn.

## One re-run, then quarantine

The rule that shipped is deliberately unglamorous: every newly failed check gets exactly one isolated re-run, on the unchanged work. Not a retry loop. One re-run, alone, with nothing fixed first.

A pass on that re-run is not a fix. It is a flake signature — proof the check fails without a cause — and it triggers three acts.

Quarantine first. The check comes off the failure list driving the fix work for that run. It is never counted as fixed — no fix was attempted — and it can never trip the loop's gone-in-circles detector, because it spends no fix budget at all. Quarantine is bookkeeping, not surgery: the check itself is never edited, skipped, or deleted. The bookkeeping is also precise about identity — the same check name in two different files counts as two separate suspects, not one flake.

File second. A tracker ticket is opened so the flake is owned, visible, and fixable later. The deduplication detail matters: rather than searching for a ticket whose title matches, the loop matches a small invisible marker written inside the ticket itself. A title search silently misses exactly the tickets it exists to find — check names carry punctuation that confuses matching-by-name — and a miss files a duplicate nobody reconciles. A found ticket gets a comment, not a clone. And a ticket that stays open forever trains everyone to ignore the label, so the convention closes it on the next green run of the same suite.

Report third. The final report must name every quarantined flake — "succeeded, with three checks quarantined and tracked" — never a bare green line. A green that could quietly cover quarantined flakes is the precise failure the screen exists to prevent.

Two honest boundaries deserve plain statement. A re-run that errors or times out does not count as a pass — the failure stays on the fix path. And quarantine must never launder a real regression the change itself caused: a flake first observed after the loop's own fix landed, or a check that exercises the files the change touched, is flagged as a possible interaction with the change, not waved through.

## What review caught

The screen went through the same review gauntlet everything here goes through — and review found two defects that matter more than the screen itself.

The first was a success row that proved nothing. The protocol's outcome table needed a line meaning "everything that failed turned out to be a flake." The case had been missing entirely at first — an all-flake run matched no outcome at all and would have been reported as a stall, throwing away real fixes. The row added to cover it then fired on any run that ended with an empty failure list — including a run that produced no readable results whatsoever. Zero quarantines read as green. The fix that shipped requires at least one real quarantine before that row can fire: nothing screened is nothing proven, and a run nobody could read falls through to the failure rows where it belongs.

The second was a flag that could never fire. The protocol carried a warning meant to catch quarantine laundering a regression — it compared the flaked check's file against the files the loop's own changes touched. Reasonable-sounding, and empty by construction: the loop never edits check files, so the comparison could never be true. A warning whose trigger cannot fire is decoration wearing the costume of coverage. The shipped version flags the two signals that can actually fire: the flake was first seen after the loop's own fix, or the flaked check exercises files the change touched.

There is a third lesson in the same review, smaller and worth keeping. The first draft of the ticket-deduplication step invented a name-based search — while the codebase already had the marker-inside-the-ticket convention, proven against exactly the inputs that break a name search. When the machinery you need already exists nearby, mirror it; an invented mechanism tends to be weaker on precisely the cases it exists for.

## Six questions to ask of any suite

When a filed flake needs a root cause, the protocol points at a checklist — six axes, and most flakes resolve to exactly one. A founder can audit any suite against them without touching the machinery:

- **Seeds** — is randomness reproducible? A check that rolls dice fails on inputs nobody can replay. Every random source needs a fixed seed so a red run can be repeated exactly.
- **Clocks** — does anything read wall-clock time? That check is unpredictable by construction. Freeze time, and never demand exact equality on a measured quantity — a real clock can tick between two readings.
- **Network** — does a check reach the real network? Latency and vendor hiccups make it a flake farm. Stand-ins must fail loudly on an unexpected call, never quietly return a default that passes.
- **State isolation** — does every check leave the world as it found it? Shared leftovers between checks are order-dependence waiting for a scheduler to expose it.
- **Output terseness** — quiet on green, loud on red. A chatty suite buries the failure line in noise, and anything reading the summary needs the last line to be the verdict.
- **Contention** — the one axis an isolated re-run cannot see: a check that fails only under load, when siblings race for the same resource. For that class the honest fix is determinism work on the check itself, not another retry.

This post expands one thread of [the four days we spent shipping a trust checklist]({{ site.url }}/blog/agentic-verification-checklist-shipped/) — the day-by-day account this story is a spoke of.

## What a pass is worth

You never have to run a check to use this. The next time a tool hands you a green light — a verified badge, a fixed ticket, an all-clear — ask the question this whole story hangs on: did it pass, or did it pass eventually? A pass on retry is not a pass. It is a flake asking to be quarantined, tracked, and fixed properly — and a system that reports it as fixed is teaching itself that red was negotiable all along.

For the full technical checklist — the six axes, the quarantine protocol, and what each signature means — see [the determinism reference on GitHub](https://github.com/jikig-ai/soleur/blob/main/plugins/soleur/skills/test-fix-loop/references/determinism-checklist.md). And if this is the discipline you want wrapped around the AI work in your own company, [join the waitlist](https://soleur.ai/pricing/#waitlist).

## Frequently Asked Questions

### Isn't retrying a flaky test harmless?

No — a pass on retry teaches the system that red is negotiable. An AI agent does not get suspicious when a failure vanishes on re-run; it learns that persistence is a fix. A flaky check left running is worse than no check, because it quietly trains the whole workflow to retry until green instead of fixing until green.

### What does quarantine actually do to the test?

Nothing to the test itself — it is never edited, skipped, or deleted. Quarantine removes it from the failure list driving the fix work for that run, opens a tracker ticket so the flake is owned and visible, and makes the final report name it. The check is never counted as fixed, and the tracker closes on the next green run so the label never becomes noise.

### How do I make my suite less flaky in the first place?

Audit it against six axes: seeds (is randomness reproducible), clocks (is time frozen), network (are real calls blocked), state isolation (does every check clean up after itself), output terseness (quiet on green, loud on red), and contention (does it fail only under load). Most flakes resolve to exactly one of the six.

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Isn't retrying a flaky test harmless?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "No — a pass on retry teaches the system that red is negotiable. An AI agent does not get suspicious when a failure vanishes on re-run; it learns that persistence is a fix. A flaky check left running is worse than no check, because it quietly trains the whole workflow to retry until green instead of fixing until green."
      }
    },
    {
      "@type": "Question",
      "name": "What does quarantine actually do to the test?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Nothing to the test itself — it is never edited, skipped, or deleted. Quarantine removes it from the failure list driving the fix work for that run, opens a tracker ticket so the flake is owned and visible, and makes the final report name it. The check is never counted as fixed, and the tracker closes on the next green run so the label never becomes noise."
      }
    },
    {
      "@type": "Question",
      "name": "How do I make my suite less flaky in the first place?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Audit it against six axes: seeds (is randomness reproducible), clocks (is time frozen), network (are real calls blocked), state isolation (does every check clean up after itself), output terseness (quiet on green, loud on red), and contention (does it fail only under load). Most flakes resolve to exactly one of the six."
      }
    }
  ]
}
</script>
