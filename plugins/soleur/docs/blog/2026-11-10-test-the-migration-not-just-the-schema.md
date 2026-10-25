---
title: "Test the Migration, Not Just the Schema"
seoTitle: "Test the Migration, Not Just the Schema"
date: 2026-11-10
description: "A change applied cleanly, then quietly broke everything downstream for three weeks. The fix: let the old system referee its own replacement."
ogImage: "blog/og-test-the-migration-not-just-the-schema.png"
pillar: billion-dollar-solo-founder
tags:
  - agentic-verification
  - methodology
  - migration
  - testing
  - solo-founder
  - build-in-public
  - pillar
---

Every founder who ships software eventually replaces a piece of it that already works. The rewrite is faster, cleaner, built on everything the first version taught you. Its tests pass. You flip the switch. And somewhere downstream, in a place the new system's tests never looked, something your users depended on quietly stops.

We have a measured instance of exactly that failure — one that ran undetected for about three weeks inside our own product. This is the story of what it taught us, and the practice we shipped so that an AI planning your next replacement demands better evidence than "it applied cleanly."

## The change that applied cleanly

Our product's chat feature broke for about three weeks, and nothing looked broken.

The cause was a routine database change — the kind that tightens an access rule so every saved record carries the workspace it belongs to. The change applied perfectly. Every check that watches the database said so. What it also did was make one field required, and every place where a person's typed message got saved omitted that field. Each save was refused — silently, behind a generic "an unexpected error occurred" bubble.

Here is the part that should worry anyone who runs software alone: the background jobs kept working. Automated writers ran under a different access level that bypassed the rule entirely, so data kept flowing, monitors stayed green, and the product looked healthy — while every human who typed a message hit a wall. The last successful message had been saved weeks before anyone noticed.

When a user finally reported it, the first fix repaired the wrong thing — the error the monitoring alert happened to name, not the failure the user actually hit. The real defect surfaced only when someone traced the visible symptom to its actual producer.

The lesson underneath is older than our incident. Your users never relied on the specification — the document that says what the system should do. They relied on what the old thing actually did. A change that applies cleanly proves the change landed. It says nothing about whether everything downstream of it still works.

## The old system is the referee

The discipline that answers this is called differential testing, and its premise is almost insultingly simple: the old system is the oracle. You already own a correct-by-definition reference — the thing that has been running in production, producing the behavior everyone depends on.

The recipe: feed the old system and the new system the same inputs. Normalize away the differences a human has declared meaningless — timestamps, ordering that carries no information, formatting noise. Then compare the outputs, in both directions, and account for every single difference.

Every difference is exactly one of two things: a bug in the new system, or an intended change — and an intended change must be written down in a ledger, with a reason. There is no third option. A difference with no ledger entry is a bug by definition. That ledger is what keeps "different" from quietly becoming an acceptable state — and when the migration ends, it doubles as your list of breaking changes, written for free.

The inputs matter as much as the comparison. Hand-picked cases miss the edges a rewrite actually breaks on, so the recipe draws from two sources: randomly generated inputs across the whole domain — the same practice that caught a real bug the first day we adopted it — and samples of real traffic, recorded from the running system and replayed against both sides. Real traffic carries the long tail nobody invents: strange encodings, legacy clients, inputs nobody remembered were possible. The samples must be recorded, never reconstructed — a reconstructed input is a guess about what production sends.

Two traps sit on either side of the normalization step. Under-normalize and you drown in meaningless noise; over-normalize and every category you wave away becomes a category where real divergence goes invisible. The rule: normalize only what a human explicitly declared non-semantic, and keep that list where a reviewer can audit it.

And compare the whole output set, as a one-to-one mapping. "Every new output matches some old output" leaves deletions invisible — a behavior the new system simply dropped reads as clean under that weaker check. Nothing added without a ledger entry; nothing removed without one either.

## The exit is deletion

The end of a migration is not "the comparison has been clean for a while." The exit criterion is deleting the old system — its code, its deployment, and the comparison harness along with it. The harness is what gives you the confidence to wipe the old thing away; keeping both running "just in case" is twice the work and two ways to break. A system kept around still drifts, still gets paged, and still gets hit by clients nobody rerouted.

## Where the lesson now lives

That recipe now lives inside the planning workflow our users' agents run. When a plan describes a change that rewrites, ports, or replaces a running system, the plan itself must prescribe the run-both-sides comparison and the before-and-after evidence — before a line of implementation starts. The requirement is routed, not broadcast: one conditional sentence inside the planning template's test-scenario guidance, in each place a test plan gets written, so only migration-shaped plans pick it up. A plan for a landing page never sees it.

## What this recipe does not cover

Honesty about scope is part of the artifact, so here it is plainly. The recipe governs replacing a runnable system — a rewrite in a new language, a pipeline moved to a new engine, a component swapped for an equivalent one. It deliberately does not govern the schema-change scripts that reshape a live database; those keep their own runbooks and their own defect histories.

The title's "schema" is the cheap test everyone already runs — did the change apply — not the document's scope. And yes, our own three-week incident was a schema-shaped change. That is the point rather than a contradiction: whatever layer a change lives in, "it applied cleanly" is evidence the change landed, never evidence that anything downstream still works. The compare-before-you-trust instinct applies everywhere; the full oracle apparatus is for when you replace the machine itself.

## The harness had to prove it could see red

The review story behind the document carries this arc's usual twist — the verification machinery needed verifying.

The recipe reaches a user's plans through a pointer sentence inside template text that gets copied verbatim into every generated plan. The first version of the link inside that sentence was written for where the file lives in our repository — which resolves to nothing inside a plan generated on a user's machine. The fix anchored the link to the user's own installation instead.

But the part worth stealing came next. The plan claimed that existing checks already guaranteed the new document stayed reachable — a coverage claim. That claim was believed only after a negative control ran: on a scratch copy, delete the pointer and confirm the census check went red, naming the missing file. A suite you say covers a thing is evidence only after removing the thing makes it fail.

The same plan escalated a placement question — full reference document or slimmed-down summary page — to an explicit ruling instead of a guess, and the ruling kept the full version. A decision the agent could not settle locally got decided in the plan, in writing.

This post expands one thread of [the four days we spent shipping a trust checklist]({{ site.url }}/blog/agentic-verification-checklist-shipped/) — the day-by-day account this story is a spoke of.

## What to demand before you retire the old thing

You do not have to build the harness to ask the questions it answers. The next time your AI, a contractor, or a vendor proposes replacing a piece of your product that already works, ask three things.

First: what evidence will you show me that the new system does what the old one did — not "it passed its tests," but the same inputs through both, with every difference accounted for? Second: where is the written list of the differences you meant to make — because anything not on that list is a bug, not a surprise to negotiate later? Third: when does the old system actually get deleted — because "we will keep both running" is not a migration, it is a mortgage.

And ask the question this whole arc hangs on: can the check go red? "It applied cleanly" could not. A side-by-side comparison can.

For the full technical recipe — the normalization contract, the replayed-traffic corpus, the approved-changes ledger, and the delete-the-old exit criterion — see [the reference document on GitHub](https://github.com/jikig-ai/soleur/blob/main/plugins/soleur/skills/plan/references/differential-migration-testing.md). And if this is the discipline you want wrapped around the AI work in your own company, [join the waitlist](https://soleur.ai/pricing/#waitlist).

## Frequently Asked Questions

### What is differential testing?

A testing approach where you run an old system and its replacement side by side on the same inputs and compare their outputs. The old system acts as the oracle — the definition of correct — and every difference between the two is either a bug to fix or a deliberate change that must be written down with a reason. There is no third option.

### How is this different from a migration test?

A typical migration test asks whether the change applied cleanly — did the script run, did the data land in the new shape. Differential testing asks whether everything downstream still behaves the way the old system behaved. Our own incident applied cleanly and still broke the feature users touched for about three weeks; "it applied" and "it still works" are different claims that need different evidence.

### What counts as evidence a replacement is safe?

Three things: the same inputs run through the old system and the new one, with outputs compared in both directions; a written ledger where every accepted difference has a stated reason — anything not in the ledger is a bug; and an exit that deletes the old system once the comparison is clean modulo that ledger. A check that can only ever report success is decoration, not coverage.

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "What is differential testing?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "A testing approach where you run an old system and its replacement side by side on the same inputs and compare their outputs. The old system acts as the oracle — the definition of correct — and every difference between the two is either a bug to fix or a deliberate change that must be written down with a reason. There is no third option."
      }
    },
    {
      "@type": "Question",
      "name": "How is this different from a migration test?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "A typical migration test asks whether the change applied cleanly — did the script run, did the data land in the new shape. Differential testing asks whether everything downstream still behaves the way the old system behaved. Our own incident applied cleanly and still broke the feature users touched for about three weeks; \"it applied\" and \"it still works\" are different claims that need different evidence."
      }
    },
    {
      "@type": "Question",
      "name": "What counts as evidence a replacement is safe?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Three things: the same inputs run through the old system and the new one, with outputs compared in both directions; a written ledger where every accepted difference has a stated reason — anything not in the ledger is a bug; and an exit that deletes the old system once the comparison is clean modulo that ledger. A check that can only ever report success is decoration, not coverage."
      }
    }
  ]
}
</script>
