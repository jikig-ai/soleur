---
title: A comment sweep that names every site still misses one — grep the VALUE, not the sites
date: 2026-10-28
category: workflow-patterns
tags: [review, drift, terraform, comments, one-shot]
---

# Learning: a value-change sweep keyed on sites misses the site nobody listed

## Problem

On PR #11374 (fix #11372: `query_period` 10800 → 5400 on a BetterStack alert),
the plan prescribed "update every pin, comment, and doc that records the old
window" and named four sites: the resource comment, the guard pin, and two
runbooks. All four were updated. Three independent review seats still found a
FIFTH site the sweep missed: the locals-block comment 40 lines above the same
file's SQL (`"a failing probe keeps a row inside the 3 h window and a fixed
one clears in about 3 to 4 h"`), which then contradicted the updated resource
comment. Site-enumeration sweeps fail on the site the author did not think of
— exactly the ones a reviewer must find.

## Solution

For a value change that is restated in prose (window sizes, timeouts, counts),
the sweep is a two-axis grep, not a site list: `git grep -n -E '<old-value>|<old
phrasing-shapes>'` over the repo (here: `10800|3 h|3 to 4` would have caught it
on the first try), then per hit classify as consumer-of-the-value vs unrelated
constant. The guard pins literals, not comments — so a missed comment can never
redden anything; it only misleads the next operator or a mis-briefed agent.

Adjacent datapoint worth reusing (CORRECTED 2026-10-28): BetterStack's 422
"too resource intensive" is NOT a plain check-vs-query ratio ceiling. This
paragraph first claimed ratio 36 (300/10800) rejected and 18–27 applied; that
was refuted — 300/5400 and 3600/10800 were refused for the same alert too, while
older alerts hold 3600/86400 and 3600/97200. A read-only GET of the live alerts
shows every alert with query_period above 900 was created in September and every
one created since 2026-10-01 has query_period of 900 or less (see the
2026-10-27 learning's measured table). Recorded on #11266: the ruled dead-man
tuple (query_period 2592000) will 422 on its gated probe, so it needs the
owner-authorized create-and-delete probe, not a re-planned `check_period`.

Structural-enumeration note: the alert-guard family pins literal params but
not effective-config paths (override.tf, meta-arguments, unpinned attrs,
removed/import blocks, provider version, CI-invocation pin, name-shape census
escape) — deferred to #11388.
