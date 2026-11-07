---
title: Decision challenges — feat-one-shot-9601-adr309-item3-expiry-monitor-alert
date: 2026-11-07
---

# Decision Challenges

Headless pipeline run. Technical forks were put to the CTO agent (no operator question asked); each ruling is a row below.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| ADR-309 / handover checklist item 3 wording: keep the number and rewrite as status plus re-check, vs delete and renumber, vs mark done | technical | Ruled by CTO agent, 2026-11-07: keep item 3 in place and rewrite it from an instruction to "routing declared, unconfirmed until apply and re-read at flip", never "discharged", "done" or struck - items 8 and 12 of the copied checklist cite each other by number, renumbering would break those citations, and this PR must not discharge any flip item. |
| Which other passages move: the ADR "Accepted deviation: cron monitor routing" section, the post-deploy verification paragraph, the handover "Other preconditions" bullet | technical | Ruled by CTO agent, 2026-11-07: no edits to the post-deploy paragraph or the "Other preconditions" bullet (dated, time-bound, not contradicted by item 3); append exactly one dated sentence to the accepted-deviation section so it does not contradict item 3 - the item-3 rewrite stays the single live status location. |
| Whether editing `apps/web-platform/infra/sentry/alert-reference.json` (adding detector id 2557403) is in scope though the brief does not name it | technical | Ruled by CTO agent, 2026-11-07: in scope, a mandatory companion of the `monitor_ids` edit - the plan_pr reference gate requires the committed reference to equal the plan projection (precedents #11999 and #12235); insert by hand in string-sorted position between 2409332 and 2586358. |
