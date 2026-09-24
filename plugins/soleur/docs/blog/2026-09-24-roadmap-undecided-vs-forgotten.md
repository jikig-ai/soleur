---
title: "Your Roadmap Can't Tell Undecided from Forgotten"
seoTitle: "Your Roadmap Can't Tell Undecided from Forgotten (Product Roadmap Audit Retrospective)"
date: 2026-09-24
description: "Our own roadmap tool saw 30 of 118 open issues and picked the wrong phase, silently. Here's the four-place fix and what a five-bundle audit of mattpocock/skills taught us about it."
ogImage: "blog/og-knowledge-compounding-ai-development.png"
tags:
  - product
  - roadmap
  - github-issues
  - solo-founder
  - agentic-engineering
---

We run a skill called `product-roadmap next`. Point it at the repo and it reads the live roadmap, picks the current phase, and tells you the next unblocked, unassigned issue to work on. It is the tool we built so that neither of us -- founder or agent -- has to hold the whole roadmap in our head before starting work.

While shipping the fix for one of the gaps a skills audit had flagged, we measured `next` against our own live repo -- and found it was quietly wrong. `next` was reading 30 of Phase 4's 118 open issues. It recommended work from Phase 5, a phase ahead of the one we were actually in. And it never said a word about any of it -- the missing 88 issues just weren't there, and a `gh` failure would have read the same as "nothing left to do."

That bug, and the fix, are one thread in a longer story: five audit bundles pulled from [mattpocock/skills](https://github.com/mattpocock/skills), an MIT-licensed skill library for Claude Code by Matt Pocock of Total TypeScript, plus a sixth bundle that landed the day this post was drafted. This is the retrospective -- what we found, what we shipped, and the one idea worth taking if you plan your own product in GitHub Issues: a roadmap has to be able to say "we haven't decided yet," or it can't be trusted to say "there's nothing here."

## The bug: a silent default limit

`gh issue list` returns 30 issues per page unless you pass `--limit`. Our roadmap script didn't pass one. Phase 4 had 118 open issues. The script fetched the first 30, computed "next" from that set, and stopped -- no warning, no truncation notice, nothing to tell you the other 88 existed.

Compounding it: the phase-selection logic picked whichever milestone looked active by its Current State row, and Phase 4's row had no frozen count to check against. So `next` skipped past it and recommended work from **Phase 5** -- the desktop app, issue #1423 -- while Phase 4 was the phase actually in flight. And because a failed `gh` call and an empty result set were indistinguishable, a rate limit or an auth hiccup would have silently reported "no open issues" instead of an error.

None of this showed up in normal use. The tool always returned *something* -- a plausible-looking next action, a real issue number, a real title. It just wasn't looking at the roadmap; it was looking at the first page of it.

The fix, shipped in [PR #8536](https://github.com/jikig-ai/soleur/pull/8536): `next` now reads the live open milestones directly to pick the phase (`pick_phase`), instead of trusting a hand-maintained status row that can drift. The issue fetch now passes `--limit 1000` and exits with code 2 on any untrusted read, rather than treating a fetch failure as an empty result. After the fix, `next` correctly names Phase 4 issue #673, and `next --frontier` lists the full set: all 118.

Thirty of a hundred and eighteen is 25%. A roadmap tool that silently reasons from a quarter of the backlog is worse than no tool -- it produces a confident, specific, wrong answer, and confident wrong answers get trusted.

## The real fix: four places, not two

The limit bug was a bug. The deeper problem it exposed was structural: our roadmap only had two states for a piece of work -- scheduled in a phase, or not there. That binary can't distinguish "we know we need this but haven't figured out what it is yet" from "nobody ever wrote it down." Both look like silence.

The fix we shipped alongside the limit bug borrows a mechanic from `mattpocock/skills`' `wayfinder` skill (MIT, credited in `plugins/soleur/NOTICE`): **every known piece of work lives in exactly one of four places.**

| Place | What it means | How it's recorded |
|---|---|---|
| Phase row | We are building this in the current phase. | Open issue in a `Phase N` milestone. |
| Post-MVP / Later | Filed, but chosen for later. | Open issue in the `Post-MVP / Later` milestone. |
| Not Yet Specified | We know we'll need something here; we can't yet say what question it answers. | A bullet under `## Not Yet Specified` -- no issue. |
| Out of Scope | We decided no. | Issue closed as `not planned`, plus a one-line reason. |

Anything outside those four, with no issue anywhere, was forgotten -- not deferred, not declined, just never written down. That's the distinction the two-state version couldn't make: "undecided" and "forgotten" rendered identically, as absence.

**Not Yet Specified** is the section that does the real work here, and its admission test is narrow on purpose: can you state the question this work will answer, precisely, right now? Not whether you can *answer* it -- whether you can *phrase* it. "Improve onboarding" fails; it names no deliverable. A bullet that fails the test doesn't get filed as fog dressed up as a plan. It waits, honestly labeled as not-yet-sharp, until someone can write a real issue title and a done-when line. Fog never gets pre-sliced into row-sized pieces just to look organized.

**Out of Scope** is the mirror case: not silence, a recorded no. Ruling something out closes the issue with `not planned` and a one-line reason, and anything that depended on it gets re-checked before the door shuts -- closing a blocker releases whatever it was blocking onto the frontier, so each dependent needs its own look before you walk away. Out-of-scope work never quietly graduates back in; if the founder changes their mind, that's a new issue, not a reopened one.

An issue that's open but carries no milestone at all isn't forgotten either -- it's **unsorted**: known, but not yet placed. The roadmap workshop's fog-and-scope walk treats that as its own bucket, so "unsorted" and "forgotten" don't collapse into each other either.

## Blocking edges and the frontier

The other half of the fix answers a different question: given everything that *is* scheduled, what can you actually start right now? Work in a phase can still be blocked by something else, and a roadmap that doesn't track that will recommend work nobody can start yet.

We wired this to GitHub's native issue dependencies rather than inventing our own: `gh issue edit <N> --add-blocked-by <M>` records a real blocking edge, visible in GitHub's own UI, not just prose in a comment. `next --frontier` reads those edges and reports the take-able set: issues that are open, unblocked, and unassigned. Every other issue in the phase gets classified too -- `WAITING` on a named blocker, `UNVERIFIED` if the blocker data couldn't be trusted, `CLAIMED` if someone's already on it. Nothing gets silently dropped from the report the way the missing 88 issues did.

Put together with the four-places rule, the frontier query answers the question a founder actually has at the start of a session: not "what's on the roadmap," but "what, specifically, can I start right now that nothing else is blocking." Try it yourself:

```
product-roadmap next --frontier
```

## The audit, and what it did and didn't change

The four-places mechanic was the last of five bundles filed from a single audit of `mattpocock/skills` on 2026-09-18. All 38 of its `SKILL.md` files were read, no sampling -- a deliberately different-ICP library (senior TypeScript engineers, not the founders we build for), with zero business-domain agents and no knowledge base. It isn't a competitor. It's mechanic density in exactly the places our own tooling was thinnest, and the audit's recommendations shipped in order:

1. **Bundle 1** -- a wizard-generated operator bootstrap script and a Merge Danger block for PRs, implementing two hard rules we'd written but never built a template for.
2. **Bundle 2** -- a red-capable debugging loop for `reproduce-bug`: a completion gate that won't let hypothesizing start before reproduction is confirmed.
3. **Bundle 3** -- a rejected-request knowledge base, a domain glossary, and `questionnaire-generate`, for routing questions to whoever actually holds the answer.
4. **Bundle 4** -- budget relief across the invocation axis, plus two real defects the audit caught in our own skill-creator documentation along the way.
5. **Bundle 5** -- the roadmap fix above: four places, native blocking edges, `next --frontier`.

A sixth data point landed the same week this post was written: [PR #8647](https://github.com/jikig-ai/soleur/pull/8647), merged 2026-09-24, folding in three items the audit record had left unfiled -- a dialogue-discipline rule for how we run planning conversations, a null-guardrail check that reads a repo's own test scripts before proposing a new one, and a skill-composition map. Not every recommendation made the cut, either: one bundle proposed a rewrite based on an A/B test that came back inconclusive against our own pre-registered bar, and we didn't ship it. The audit's job wasn't to import someone else's library. It was to find the places our own rules existed on paper but not in code, and fix those -- five confirmed, one still landing, one deliberately declined.

## The one thing to take

If you plan work in GitHub Issues, the fix worth stealing isn't the code -- it's the test. Every piece of work you know about should sit in exactly one of four places: scheduled, deferred, not-yet-specified, or ruled out with a reason. If it isn't in any of them, and there's no issue for it, it's not undecided. It's forgotten. And a roadmap tool that can't tell the difference will eventually hand you a confident answer built on 25% of the truth.

Try `product-roadmap next --frontier` and see what it surfaces first.

<details>
<summary>What's the difference between "Not Yet Specified" and "Post-MVP / Later"?</summary>

Post-MVP / Later is a filed issue -- the work is sharp enough to state as a deliverable, it's just been chosen for a later phase. Not Yet Specified has no issue at all, because the question it would answer can't yet be stated precisely. The test is whether you can write a real issue title and a done-when line today, not whether you've decided to build it.

</details>

<details>
<summary>Why not just always pass a high --limit to gh issue list?</summary>

That's exactly the fix -- `next` now passes `--limit 1000` on every fetch. The deeper problem the bug exposed was that a silent default (30 issues) combined with a failure mode that couldn't tell "empty" from "broken," so the fix also makes any untrusted or failed fetch exit with an error instead of reporting zero results.

</details>

<details>
<summary>What does GitHub's native issue-blocking feature actually track?</summary>

A real dependency edge between two issues (`gh issue edit <N> --add-blocked-by <M>`), visible in GitHub's own UI and readable over the REST and GraphQL APIs, not just prose like "blocked by #12" in a comment. `next --frontier` reads those edges to compute which open, unassigned issues have no open blocker -- the actual take-able set.

</details>

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "What's the difference between \"Not Yet Specified\" and \"Post-MVP / Later\"?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Post-MVP / Later is a filed issue -- the work is sharp enough to state as a deliverable, it's just been chosen for a later phase. Not Yet Specified has no issue at all, because the question it would answer can't yet be stated precisely. The test is whether you can write a real issue title and a done-when line today, not whether you've decided to build it."
      }
    },
    {
      "@type": "Question",
      "name": "Why not just always pass a high --limit to gh issue list?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "That's exactly the fix -- next now passes --limit 1000 on every fetch. The deeper problem the bug exposed was that a silent default (30 issues) combined with a failure mode that couldn't tell \"empty\" from \"broken,\" so the fix also makes any untrusted or failed fetch exit with an error instead of reporting zero results."
      }
    },
    {
      "@type": "Question",
      "name": "What does GitHub's native issue-blocking feature actually track?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "A real dependency edge between two issues (gh issue edit <N> --add-blocked-by <M>), visible in GitHub's own UI and readable over the REST and GraphQL APIs, not just prose like \"blocked by #12\" in a comment. next --frontier reads those edges to compute which open, unassigned issues have no open blocker -- the actual take-able set."
      }
    }
  ]
}
</script>
