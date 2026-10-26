---
title: "A link-graph guard whose haystack is the whole page is vacuous once the nav links the target"
date: 2026-10-26
category: workflow-patterns
tags: [testing, seo, mutation-testing, assertion-scope]
related:
  - knowledge-base/project/specs/feat-one-shot-gsc-index-link-equity/
  - plugins/soleur/test/seo-aeo-drift-guard.test.ts
---

# Link-guard haystacks must exclude site chrome

## Problem

A guard asserting "page X links URL Y" ran `hasHref` against the whole rendered
HTML. The same PR added Y to the global nav — so the nav chrome on every page
satisfied every mesh assertion and the guard's own mutation matrix went
green-not-red. Stripping every content link still passed 117/117.

## Solution

Slice the haystack to the region under test before asserting: `html.slice(indexOf("<main"), indexOf("</main>"))` for content links; `nav-links … </header>` for nav claims; `slice(0, indexOf("<footer"))` for "homepage body" claims. Never let the property's own fix supply the haystack — chrome (nav/footer) renders on every page and satisfies any whole-page presence check.

Pairs with `cq-assert-anchor-not-bare-token` (anchor on the call-form) — this is the spatial version of the same rule: **anchor on the right region, not just the right token.** Mutation-test every guard row against the *reviewer's repro*, not a proxy: the seat caught this only by stripping the fix's own markup and watching the suite stay green.

Found at `soleur:review` (structural-enumeration seat, PR #11178) — fixed as #11201.
