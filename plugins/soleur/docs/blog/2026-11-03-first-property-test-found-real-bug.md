---
title: "The First Property Test We Wrote Found a Real Bug"
seoTitle: "The First Property Test We Wrote Found a Real Bug"
date: 2026-11-03
description: "The first property test we ever ran caught a real bug on day one — an invisible trailing space, a twin defect in the database, and a harness lying green."
ogImage: "blog/og-first-property-test-found-real-bug.png"
pillar: billion-dollar-solo-founder
tags:
  - agentic-verification
  - methodology
  - testing
  - solo-founder
  - build-in-public
  - pillar
---

Every check guarding your company's work is a list of cases somebody remembered to write down. That is true of the checklist your assistant follows, the spot-checks you run before shipping, and the tests your AI writes for its own output. The list is only as good as the imagination behind it — and the imagination doing the listing has the same blind spots the rest of you does.

We found out how much that costs the day we stopped writing lists and started writing rules. The very first run caught a real bug — one that had already survived two earlier fixes to the same drift, behind a documented promise and a dedicated check that had never once seen it.

## Your test list is your imagination

The ordinary way to check anything — in code, in a spreadsheet, in a process — is the example: pick a case, decide what the right answer looks like, compare. It works until the interesting case is the one nobody thought of. The cases that make the list are the ones the author could picture, and the author can only picture inputs that look reasonable to a human.

That is the quiet hole in every hand-picked suite. It is not that the wrong answers pass. It is that the question that would produce them is never asked, because "a repository address with a stray space hiding just before its file suffix" is not a shape a person reaches for. No one writes the example they cannot imagine.

## A rule instead of a list

There is a stronger habit, and we adopted it formally: the property test. Instead of listing cases, you state a rule that must always hold — "running a cleanup twice changes nothing the second time" — and a generator throws thousands of random inputs at the rule, trying to break it. The machine does not share our sense of what a reasonable input looks like, so it explores corners no one would think to try: empty inputs, padded inputs, inputs with marks hiding exactly where the cleanup operates.

When the generator wins, it does something a human tester rarely does: it shrinks the failing input down to the smallest form that still breaks the rule, and that minimized case joins the test list permanently, as a named example the bug can never slip past again. And because a rule that can only ever pass is decoration, each generated check proves itself once at write time against deliberately broken code — it has to show red before it is trusted to show green.

## Day one

The first generated test we aimed was at a small utility that tidies repository addresses — trims stray spaces, strips a trailing suffix, the kind of boring function every product accumulates. Its own documentation promised that running it twice was safe: clean up the cleaned-up value and nothing changes.

The generator's first run disagreed. It produced an address with a space sitting just in front of the suffix — an input no human picks, because no human thinks an address looks like that. The cleanup trimmed the ends first, then stripped the suffix — and the space the suffix had been hiding stepped out into the open, left behind at the end of the result, invisible to the eye. Run the tidy-up once, get one answer. Feed that answer back in, and the leading trim moves it again: a third answer. The documented contract said that was impossible. The code did it anyway.

And the dedicated check we already had — a separate comparison built specifically to keep that cleanup honest — had never seen it either, because its own hand-picked list of cases contained nothing shaped like the offending input. It was the third time the same cleanup had drifted. Every example we had ever written had walked around it.

## The twin

Once we knew the shape to look for, we found the same defect in a second place: the database kept its own copy of the same cleanup, written in the database's own language, with the same sequence of steps and the same missing final trim. It was the third time the two implementations of one idea had drifted apart — each time in a different way, each time unnoticed until something looked sideways at it.

Both are fixed now. The application side gained a final tidy-up pass after the stripping, closing the hole the suffix had opened. The database side could not be edited in place — a database change that has already run is history, not a draft — so the fix shipped as a new change that re-cleaned the rows already stored in the broken shape, behind a strict check that only rewrites values both sides agree on. That follow-up has since shipped and closed. The lesson outlived the bug: when the same logic lives in two places, a fix on one side means the other side now disagrees with it.

## The harness needed fixing too

Here is the part of the story we tell carefully, because this post exists to practice what it preaches. The machinery we built to run these generated tests arrived with defects of its own — and every one of them failed in the same direction: it covered less than it claimed while still reporting green.

One job of the machinery was to read the program under test and collect the rules it was supposed to watch. It understood one of the two ways a rule could be written — so it was watching 31 of the 39 rules while the check stayed green. A rule written in the other style would never join the check at all, and nothing would ever notice.

A second surface was subtler. A test input that arrived in a form the checker could not read was silently treated as "nothing wrong found" — folding into the machinery as a permanent do-nothing, a check that looks alive and can never fire.

The third was older and stranger. The built-in random-number source in the language our small helper programs are written in carries a trap on older versions: called one perfectly ordinary way, it keeps handing back the same draw instead of advancing. A run that claimed a hundred draws had really drawn one — and the pass counter printed a hundred beside it.

All three are fixed: the watcher now counts the rules independently and demands the two counts agree; every collected input must prove it can be read before it is trusted; the generator draws without hitting the trap; and a floor rule insists a run must actually happen at least once before it is allowed to print green.

## What the first day bought

Example tests sample the cases you remembered. Rules plus generation find the one you didn't. That is the whole trade, and the first run already paid for the practice: the defect it caught had already lived through two fixes, sitting in code that carried a written promise and a purpose-built comparison check, and neither had ever seen the input that broke it.

That is also the honest way to read any green light your tools show you. The value of a check is measured by what it can still find, not by how long it has stayed green — a check that never goes red might mean the work is good, or it might mean the check cannot see. This post expands one thread of [the four days we spent shipping a trust checklist]({{ site.url }}/blog/agentic-verification-checklist-shipped/) — and when we later wrote the guide that teaches this practice, reviewers caught that its own worked example could never fail, which is [a post-mortem of its own]({{ site.url }}/blog/property-test-cannot-fail-teaches-nothing/).

## What to take into your own week

You do not need to write a test to use this. Wherever a list of remembered cases is what stands between you and a mistake — an audit checklist, a review routine, the prompts you hand your AI — ask whether a rule could stand there instead, and let a machine attack it. Ask of any green light two questions: what input would make this fail, and how much of what it claims to watch is it actually watching? And when the same logic lives in two places — the app and the database, the spreadsheet and the invoicing tool — treat a fix on one side as a promise you now owe the other.

For the technical write-up — the defect, the twin, the three harness fixes, and the minimized inputs we pinned as permanent examples — see [the learning record on GitHub](https://github.com/jikig-ai/soleur/blob/main/knowledge-base/project/learnings/logic-errors/2026-10-20-repo-url-retrim-shielded-whitespace-sql-twin.md). And if this is the discipline you want wrapped around the AI work in your own company, [join the waitlist](https://soleur.ai/pricing/#waitlist).

## Frequently Asked Questions

### What is a property test in plain terms?

It is a check built from a rule instead of a list. Instead of writing "this input should give that answer" for a handful of remembered cases, you state something that must always be true — "running this cleanup twice changes nothing" — and a generator throws thousands of random inputs at the rule trying to break it. When one does, the tool shrinks the failing input to its smallest form, and that case joins the test list permanently.

### How is a rule better than a list of examples?

A list only covers the cases someone imagined. Our own result is the cleanest proof: a documented cleanup utility passed every hand-picked test we had ever written, then a generator's first run produced an input nobody would have chosen — an address with a space hiding before its suffix — and exposed a real defect. A rule covers the whole space, including the corners your imagination skips.

### Do I need this if my AI writes my tests?

You need it especially then. An AI writes the same kind of list a person does — the cases it can imagine — only faster, so the blind spot arrives sooner. Asking your AI to state rules that must always hold, and to let a generator attack them, is what turns its speed into coverage instead of a longer list with the same holes.

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "What is a property test in plain terms?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "It is a check built from a rule instead of a list. Instead of writing \"this input should give that answer\" for a handful of remembered cases, you state something that must always be true — \"running this cleanup twice changes nothing\" — and a generator throws thousands of random inputs at the rule trying to break it. When one does, the tool shrinks the failing input to its smallest form, and that case joins the test list permanently."
      }
    },
    {
      "@type": "Question",
      "name": "How is a rule better than a list of examples?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "A list only covers the cases someone imagined. Our own result is the cleanest proof: a documented cleanup utility passed every hand-picked test we had ever written, then a generator's first run produced an input nobody would have chosen — an address with a space hiding before its suffix — and exposed a real defect. A rule covers the whole space, including the corners your imagination skips."
      }
    },
    {
      "@type": "Question",
      "name": "Do I need this if my AI writes my tests?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "You need it especially then. An AI writes the same kind of list a person does — the cases it can imagine — only faster, so the blind spot arrives sooner. Asking your AI to state rules that must always hold, and to let a generator attack them, is what turns its speed into coverage instead of a longer list with the same holes."
      }
    }
  ]
}
</script>
