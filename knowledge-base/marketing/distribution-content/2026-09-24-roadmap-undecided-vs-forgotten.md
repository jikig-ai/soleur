---
title: "Your Roadmap Can't Tell Undecided from Forgotten"
type: pillar
publish_date: ""
channels: x
status: draft
---

## X/Twitter Thread

Our own roadmap tool saw 30 of 118 open issues. It picked the wrong phase. It never said a word about the other 88 -- they just weren't there.

2/ The bug: `gh issue list` returns 30 results unless you pass `--limit`. Ours didn't. A failed fetch and an empty result set looked identical too, so a rate limit would have silently read as "nothing left to do."

3/ The real fix wasn't the limit flag. It was structural: every known piece of work now lives in exactly one of four places -- a phase row, Post-MVP, Not Yet Specified, or Out of Scope (closed, with a reason). Anything outside those four, with no issue, was forgotten.

4/ "Not Yet Specified" has one test: can you state the question this work answers, precisely, right now? Not whether you can answer it -- whether you can phrase it. If not, it waits there honestly instead of getting filed as a fake plan.

5/ Paired with native GitHub blocking edges, `next --frontier` reports the real take-able set: open, unblocked, unassigned issues only. Try it: `product-roadmap next --frontier`

Full retrospective -- the bug, the fix, and five audit bundles from mattpocock/skills (MIT) that led here:

https://soleur.ai/blog/roadmap-undecided-vs-forgotten/?utm_source=x&utm_medium=social&utm_campaign=roadmap-undecided-vs-forgotten

#solofounder
