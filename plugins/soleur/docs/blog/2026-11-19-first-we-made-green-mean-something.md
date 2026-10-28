---
title: "First We Made 'Green' Mean Something. Then We Made It Fast."
seoTitle: "We Made Green Mean Something, Then Made It Fast"
date: 2026-11-19
description: "Our automated checks said 'green' while four different lies hid inside the scoreboard. We fixed what green means first — then made it faster."
ogImage: "blog/og-first-we-made-green-mean-something.png"
pillar: billion-dollar-solo-founder
tags:
  - methodology
  - ai-trust
  - solo-founder
  - build-in-public
  - pillar
---

If you use AI tools to run parts of your business, a green check mark is the bargain you made. You stopped reading every line of what your tools produce because something promised to check it for you. Whatever that something is — a test suite, a review agent, a health monitor — its verdict is the thing your week quietly rests on.

So here is a question worth five minutes: what does that green actually prove?

We had to answer it ourselves. Our company runs on nearly 700 automated checks that judge every change before it ships — and when we looked closely at our own scoreboard, we found it had been lying to us. Not once. At least four different ways. This is the story of what it took to make green honest — and why the flagship speed change was sequenced last of all.

## Green was lying, at least four ways

Every founder has learned the hard way that "the check passed" and "the thing works" are two different sentences. Ours had drifted apart in four specific, countable places.

**A skipped check counted as a pass.** Some checks can't run everywhere — they need a tool that isn't installed, or a fixture the environment doesn't have. Reporting "skipped" was honest. The scoreboard read it as "passed." A check that never ran was padding the same column as a check that proved something. Green meant "nothing admitted to failing," which is a much weaker claim than "everything verified."

**A whole directory of checks was invisible to the finder.** We built a tool whose entire job is finding checks that nothing runs anymore — orphaned work, quietly rotting. It had a blind spot the size of a directory. Dozens of checks existed — and the tool that was supposed to know about them had never counted them. You can't trust a census that doesn't know what it missed.

**The map forgot a guard the moment its file was deleted.** Our runner keeps a map of which checks a change actually needs — the thing that decides a copy edit doesn't deserve a database audit. The map dropped an entry the moment its file disappeared — so a change that *removed* a guarded file never ran the check that watched it. Delete the thing a check protected and the check simply didn't happen: the safest-looking green a diff can produce.

**Nobody knew what green was worth.** Worst of all: we kept a list of checks that were already failing, treated as known-bad, so the scoreboard could stay green anyway. A "pass" had come to mean "nothing *new* is broken — we think." The baseline of excuses had become invisible. When your standard for success is "no worse than the mess we stopped counting," green is a shrug.

## The rest of the dishonesty ledger

Those four were the flagship lies. There were three more ways the verdict was weaker than it looked — and six of the seven repairs landed before the first speed change shipped.

A check that fails one run in five teaches everyone to press "re-run" until it agrees — and a check cut short could file an ordinary-looking verdict, even a false alarm, instead of admitting it never finished. Flaky checks don't just waste time; they train the whole team to treat red as weather instead of information.

A throwaway environment we build to run a check safely could, in one path, survive into the real one — a rehearsal space bleeding into the actual stage. The check wasn't just lying about the verdict; it was contaminating what it measured.

And an error handler could pass every rehearsal and never fire in production. When work crosses a boundary — one system handing off to another — an error arrives rebuilt, stripped of everything the handler was watching for. So we built a census that counts every place an error can be swallowed crossing that line. A handler that only works in practice is not a handler.

Seven repairs to what a verdict *means*. Six landed before any speed change shipped — and the flagship speed change was gated to land last of all.

## Only then, speed

We could have led with the fast part. Speed is the change everyone can feel, and "we made the checks faster" is an easy thing to say. The flagship change — running checks side by side — was gated to land last on purpose, and only after the rebuilt scoreboard had vouched for every repair before it: speed on top of a dishonest verdict is a faster lie.

With the scoreboard rebuilt, five changes earned their place. The runner now declines checks the change couldn't have affected — a copy fix no longer triggers the full hardware audit. Runs split across more workers. A cap keeps a small change from dragging the whole nearly-700-check battery in behind it. And when you ask for it, checks can run side by side instead of one after another: in a controlled experiment on a small fixed set, the opt-in path measured **1.88 times faster**. The default stays exactly what it was — every founder and every release sees the same serial, boring, trustworthy order unless they choose otherwise.

## The part that lives in no single fix

Here is the detail that makes this story more than a list of repairs: the scoreboard we were fixing was also the thing judging every fix.

Twelve consecutive changes rebuilt the accounting, the map, the boundaries, and the scheduler. Each one was judged by the very suite it was repairing. The arbiter adjudicated its own rebuild — twelve merges, zero broken mains. A bootstrap problem with a working answer: fix the measuring stick while the measuring stick is checking you.

This is also why the work compounds instead of repeating. Every repaired lie is now a permanent, automatic check — a ratchet that can only tighten. The next "skipped counts as passed" doesn't get a second chance, because the scoreboard itself now guards the counting. We've written before about turning hard-won lessons into standing rules; extending that habit to the suite that judges everything else was the obvious next turn of the same ratchet. The pattern set out in [our last post on the theme]({{ site.url }}/blog/agentic-verification-checklist-shipped/) — catch the lesson, write it into the machinery — now covers the machinery's own verdicts.

## The honest limits

The caveat is part of the story, so we are telling it plainly.

One repair is still earning its verdict. The change that makes the runner decline irrelevant checks has a soak test running in the background — a probe that watches real runs accumulate and asks whether the savings are real and nothing broke through. It has not answered yet, and we are deliberately not closing the question early. If it comes back negative, that is the machinery working exactly as intended: an honest "not yet" instead of a convenient "sure."

The speed claim is bounded the same way. 1.88× is what we measured on a small, controlled set of checks, on the opt-in path. It is not a promise about your workload, and we would rather tell you the shape of the evidence than round it into marketing.

## The lesson for the founder

You do not need to know how any of this works to use the lesson. The order is the whole thing:

**Ask what green means before you ask how fast it runs.** Whatever checks your business leans on — a test suite, a review agent, a report that says "all good" — its verdict is only worth what its accounting is worth. A fast answer you can't trust is just a quicker way to be wrong.

We made ours mean something first. Then we made it fast.

For the technical write-up — the full ledger of what was lying and how each repair was verified — see the [public engineering record on GitHub](https://github.com/jikig-ai/soleur/issues/10971).

And if the reason this resonates is that you are running the whole company yourself: that is the problem Soleur exists for. Your AI team checks its own work, writes down what it learns, and gets measurably better — so the green you see means what you think it means. [Join the waitlist](https://soleur.ai/pricing/#waitlist).

## Frequently Asked Questions

### What does a green check mark actually prove?

Only what its accounting is worth. A green verdict means the checks that ran reported no failures — but that can hide checks that never ran, checks that were counted wrong, or known failures quietly excused. Before trusting a green, it is worth asking what "passed" and "skipped" actually counted for.

### Can an automated check itself be wrong?

Yes — in specific, enumerable ways. Ours had at least four: a skipped check counted as a pass, a finder that could not see a whole directory of checks, a map that forgot a guard the moment its file was deleted, and a baseline that made green mean "no worse than the mess we stopped counting." Every kind of check machinery has an equivalent list worth auditing.

### Should speed come before accuracy in automated checks?

No — and the order matters more than either alone. Speed on top of a dishonest verdict is a faster lie: the same wrong answer, delivered sooner. Fix what the verdict means first, make it fast second, and keep the honest path the default even after a faster one exists.

### How do I know whether to trust my AI tool's results?

Ask what the tool does when it is uncertain, and whether its record is auditable. Trust signals to look for: it says "not yet" when evidence is thin rather than guessing, its past claims can be checked against what actually happened, and the rules it learned from its own mistakes are written down where you can see them.

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "What does a green check mark actually prove?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Only what its accounting is worth. A green verdict means the checks that ran reported no failures — but that can hide checks that never ran, checks that were counted wrong, or known failures quietly excused. Before trusting a green, it is worth asking what \"passed\" and \"skipped\" actually counted for."
      }
    },
    {
      "@type": "Question",
      "name": "Can an automated check itself be wrong?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes — in specific, enumerable ways. Ours had at least four: a skipped check counted as a pass, a finder that could not see a whole directory of checks, a map that forgot a guard the moment its file was deleted, and a baseline that made green mean \"no worse than the mess we stopped counting.\" Every kind of check machinery has an equivalent list worth auditing."
      }
    },
    {
      "@type": "Question",
      "name": "Should speed come before accuracy in automated checks?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "No — and the order matters more than either alone. Speed on top of a dishonest verdict is a faster lie: the same wrong answer, delivered sooner. Fix what the verdict means first, make it fast second, and keep the honest path the default even after a faster one exists."
      }
    },
    {
      "@type": "Question",
      "name": "How do I know whether to trust my AI tool's results?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Ask what the tool does when it is uncertain, and whether its record is auditable. Trust signals to look for: it says \"not yet\" when evidence is thin rather than guessing, its past claims can be checked against what actually happened, and the rules it learned from its own mistakes are written down where you can see them."
      }
    }
  ]
}
</script>
