---
title: "We Audited 102 Guardrails. Only Four Belong in Every Repository."
seoTitle: "102 Guardrails Audited: Only Four Belong in Every Repo"
date: 2026-10-27
description: "We audited all 102 automated safety checks on our own codebase. Only four belonged in every repository — and each had to prove it works first."
ogImage: "blog/og-audited-102-guardrails-four-portable.png"
pillar: billion-dollar-solo-founder
tags:
  - agentic-verification
  - methodology
  - guardrails
  - solo-founder
  - build-in-public
  - pillar
---

Your AI writes code faster than you can read it. That is the deal you made, and most days it is a good one — until the question arrives that every founder eventually asks: what is actually checking this work?

If you are running a company alone, the honest answer is usually "some automated checks I did not write and cannot see." Maybe your AI tool set them up. Maybe a template did. Either way, you are trusting them the same way you trust the AI itself — on faith, and on the fact that nothing has gone visibly wrong yet.

That faith deserves a receipt. So before we shipped any safety checks into the repositories our users work in, we audited our own. All of them. This post is what the audit found — and it is a useful story even if you never install a single check, because the question underneath it applies to every automated safeguard you rely on: can it prove it catches anything?

## The audit: count your own first

Our own codebase has been accumulating automated checks for months — every mistake that ever got through left a check behind to stop it from happening twice. Before we told founders which of these belong in their repositories, we had to answer an uncomfortable question ourselves: how many of ours actually would?

On October 21 we counted the whole corpus: 102 automated checks, in two families. Fifty-six of them are tripwires — they fire in the moment work is about to be saved, the last instant a mistake can still be stopped cheaply. The other forty-six are sweeps — they read the whole repository and flag anything that has drifted out of line.

Then we graded every single one against a blunt question: would this mean anything in someone else's repository? Each check got one of three verdicts:

- **Portable as it stands** — the check would work in any repository with at most a path changed.
- **Portable after repackaging** — the idea is universal, but our copy is wired into machinery that does not exist anywhere else, so it would have to be rebuilt as a clean, self-contained version.
- **Welded to our machinery** — the check's whole purpose is ours: it enforces one of our own rules, reads one of our own file layouts, or watches a vendor in our own stack. In another repository it would check nothing that means anything.

## The honest count

Here is what the verdicts came back as:

| Where the check runs | Portable as it stands | Portable after repackaging | Welded to our machinery |
|---|---|---|---|
| Tripwires that fire before work is saved (56 checks) | 0 | 10 | 46 |
| Repo-wide sweeps (46 checks) | 9 | 8 | 29 |

Read that first column again. Of the fifty-six checks guarding the exact moment work gets saved — the highest-value position in the whole system — not one could be carried into another repository as it stood. Zero. Every one of them had grown roots into our machinery: our internal rules, our file layout, our own bookkeeping, our vendors.

This is the part of the story most teams never publish, because the honest version is unflattering. The reusable fraction of a mature safety practice turns out to be startlingly small — not because the checks are bad, but because a check earns its place by knowing the codebase it guards. Knowledge of your repository is precisely what does not transfer.

From the portable candidates we shipped four — the four with the highest value for any codebase, each rebuilt as a clean, self-contained template. Most teams in our position would have promised a hundred and shipped four quietly. We would rather show the count.

## The four that belong in every repository

What survived the audit, translated into what each one does for you:

- **A scan for secrets left in work about to be saved.** Passwords, keys, access credentials — the class of mistake that is free to catch and catastrophic to miss. A widely used secrets scanner reads what is about to be saved and flags anything that looks like a credential.
- **A check that work never lands straight on the main line.** Every change arrives through a side branch where it can be reviewed — yours, your tools', anyone's. Direct saves to the project's backbone get refused.
- **A check that unfinished work is never quietly shelved and forgotten.** "Tuck this away for later" is how work-in-progress silently dies. The check catches the shelving move at the moment it happens and asks whether you meant it.
- **A check that a test suite with nothing left to run cannot pass silently.** The guard that guards the guards: it watches whether your other checks are still wired into the machinery that runs them, because a check that exists but never runs is worse than no check — it looks like coverage.

Notice what the four share: none of them knows anything about our company, our rules, or our stack. Each encodes a mistake every software project can make. That is what earned them a place on the list — and it is why the list is so short.

## They arrive as warnings, not walls

Every check that ships installs in advisory mode first: it runs the identical tests it always would, but it warns instead of blocks. Same evidence, different verb.

That is deliberate, and it is the part most safety tooling skips. A check you did not write, dropping into your repository and refusing to let work save, is a frustration waiting to happen — and worse, it teaches you to distrust the whole idea of checks. So each one arrives watching and reporting. Promoting a check from warning to blocking is a one-line change, and it requires at least one clean observed run first: proof that the check behaves correctly in your repository before it is allowed to refuse anything there.

## Proven before it is allowed to guard anything

Here is the contract underneath all of it — the part we think matters most.

When one of these checks installs, it does not get trusted. It gets rehearsed. The installer makes a throwaway copy of the repository, plants a violation the check is supposed to catch, and watches: the check must go off. Then the violation is removed, and the check must go quiet. Only after it has proven both — that it fires when it should and stays silent when it should — is it written into your repository for real.

Two more refusals sit underneath that. The installer will not overwrite anything already sitting where a check would go — there is no force flag, no "clobber and continue." And it refuses to rehearse inside the real repository it is meant to protect: the rehearsal happens in the throwaway copy, or it does not happen, and the installer says so out loud rather than skipping the proof quietly.

A guard that cannot be proven to fire is a document, not a guard.

## What the review found in the machinery itself

Because the checks are machinery, the checks had defects too. This is the part of the build log nobody else publishes, so we will:

- A branch name containing a certain punctuation mark could slip past the main-line check's pattern. Under blocking mode the hole ran the worst possible way: instead of stopping nothing, it would have waved everything through.
- Each rehearsal overwrote the previous run's error log, so a check that failed could erase the evidence of why it failed.
- The remover reported tidying up machinery that was never there — a small lie in the cleanup report, but a lie in a report is a lie in a report.
- Several of the refusal cases had no automated test pinned on them — the rules existed, but nothing verified they still worked.

Every one of those was filed and fixed before release. And the sharpest finding was not any single defect: three different surfaces that record derived facts about the codebase — an architecture diagram, a test scorecard, and a headline number in the project's public description — all went red for the same reason. One regeneration step had run on a subset of what it was meant to update. Three red lights, one root cause, one fix. It is the audit's lesson again, viewed from inside: the machinery that verifies things needs verifying itself.

## The lesson worth taking

If you take one idea from the count, take this one: the portable fraction of a real safety corpus is far smaller than anyone assumes, and you only learn it by measuring. We would have guessed half our checks were generic. The audit said fewer than a third were even candidates — and only four were ready to stand alone in somebody else's repository.

The same question transfers to whatever automated checks protect your own work today — in your AI tools, your automations, your bookkeeping integrations. Not "does a check exist?" but "when did it last prove it catches anything?" A safeguard that cannot show you a real catch is a decoration with a green light.

This post expands one section of [the build log we published last week]({{ site.url }}/blog/agentic-verification-checklist-shipped/) — the day-by-day account of shipping the trust machinery this audit was part of.

For the full technical write-up — every check named, every verdict explained — see [the audit itself, on GitHub](https://github.com/jikig-ai/soleur/blob/main/plugins/soleur/skills/verification-scaffold/references/guardrail-audit.md). And if this is the kind of safety you want wrapped around your own AI work, [join the waitlist](https://soleur.ai/pricing/#waitlist).

## Frequently Asked Questions

### What is a guardrail for AI-written code?

An automated check that watches the work instead of trusting it — a scan that fires before a mistake is saved, or a sweep that notices when something has drifted out of line. The point is not to slow the AI down; it is to give you evidence you can review instead of work you have to re-do.

### Why did only four of the 102 checks qualify?

Because a check earns its keep by knowing the codebase it guards — our rules, our file layouts, our vendors — and that knowledge is exactly what does not transfer. Fewer than a third of our checks were even candidates for portability, and the four that shipped were the highest-value ones that could be rebuilt as clean, self-contained templates and proven on a throwaway copy before activation.

### Can an automated check itself be wrong?

Yes — ours were, and that is the point. The review found a check that could wave bad work through, a log that erased its own evidence, and a report that claimed cleanup it never did. Verification machinery needs verification, which is why every check we ship has to prove it catches a planted violation before it is allowed to guard anything.

### Do these checks replace a human reviewing the work?

No — they change what reviewing costs. The checks absorb the mechanical watching (credentials left in code, changes landing on the main line, forgotten work, test suites that quietly stopped running) so your judgment lands on the decisions that need it. You stay the reviewer; you stop being the tripwire.

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "What is a guardrail for AI-written code?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "An automated check that watches the work instead of trusting it — a scan that fires before a mistake is saved, or a sweep that notices when something has drifted out of line. The point is not to slow the AI down; it is to give you evidence you can review instead of work you have to re-do."
      }
    },
    {
      "@type": "Question",
      "name": "Why did only four of the 102 checks qualify?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Because a check earns its keep by knowing the codebase it guards — our rules, our file layouts, our vendors — and that knowledge is exactly what does not transfer. Fewer than a third of our checks were even candidates for portability, and the four that shipped were the highest-value ones that could be rebuilt as clean, self-contained templates and proven on a throwaway copy before activation."
      }
    },
    {
      "@type": "Question",
      "name": "Can an automated check itself be wrong?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes — ours were, and that is the point. The review found a check that could wave bad work through, a log that erased its own evidence, and a report that claimed cleanup it never did. Verification machinery needs verification, which is why every check we ship has to prove it catches a planted violation before it is allowed to guard anything."
      }
    },
    {
      "@type": "Question",
      "name": "Do these checks replace a human reviewing the work?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "No — they change what reviewing costs. The checks absorb the mechanical watching (credentials left in code, changes landing on the main line, forgotten work, test suites that quietly stopped running) so your judgment lands on the decisions that need it. You stay the reviewer; you stop being the tripwire."
      }
    }
  ]
}
</script>
