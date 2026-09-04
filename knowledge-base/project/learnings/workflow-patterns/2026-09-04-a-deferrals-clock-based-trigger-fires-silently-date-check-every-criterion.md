---
title: "A deferral's clock-based trigger fires silently — date-check every criterion, not just the one that woke you"
date: 2026-09-04
category: workflow-patterns
module: brainstorm, issue-triage, deferrals
tags: [deferral-triggers, premise-validation, issue-hygiene]
issues: [3210, 3209]
pr: 7828
---

# A deferral's clock-based trigger fires silently — date-check every criterion

## Problem

Issue #3210 (deferred Corporate CLA mechanism) recorded three re-evaluation criteria under "whichever fires first". An inbound email arrived that plainly satisfied the first one — *"Next contributor self-discloses corporate affiliation."* The whole session, and the framing handed to every domain leader, was built on that trigger.

The **second** criterion was:

> "30 days from #3209 merge — schedule the joint CPO+CLO sync regardless."

Issue #3209 closed **2026-05-16**. That criterion fired **2026-06-15**. By the session date it was **81 days overdue**, and nothing had ever surfaced it.

The work was justified regardless. But the *reason* the team believed it was justified was wrong-in-emphasis: this was not "a new trigger just fired, let's reconsider," it was "a commitment has been in breach for three months and an unrelated event happened to make us look."

## Root cause

Event-based and clock-based triggers fail differently:

- An **event-based** trigger arrives with its own notification. Someone emails, a PR opens, an alert fires. It cannot be missed, because the event *is* the interrupt.
- A **clock-based** trigger has no interrupt. Nothing fires at T+30 days. It is discharged only if a human happens to re-read the issue and do the arithmetic — and the issue is, by construction, one nobody is looking at, because it was deferred.

So the trigger most likely to be silently overdue is the one that will never announce itself, and the trigger you *do* notice is the one that made you open the issue in the first place. The noticing is anti-correlated with the overdue-ness.

## Solution

When certifying that a deferral's trigger has fired, **enumerate every criterion and date-check the clock-based ones**, rather than confirming the one that prompted the session.

```bash
# The deferral's own criteria
gh issue view <deferred-issue> --json body --jq .body

# For each "N days from #M" criterion, resolve the anchor date
gh issue view <M> --json closedAt,state --jq '"\(.state) closedAt=\(.closedAt)"'
gh pr view  <M> --json mergedAt,state --jq '"\(.state) mergedAt=\(.mergedAt)"'
```

One command per anchor. In this case `gh issue view 3209 --json closedAt` returned `2026-05-16T18:55:21Z` and settled it in seconds.

Then say so in the artifact. The brainstorm doc records all three triggers with dates, so the next reader does not re-derive them and so the overdue one is on the record rather than quietly absorbed.

## Key Insight

**The trigger that woke you is the one least likely to be the overdue one.** A deferral's criteria are a set, not an alternative — enumerate and date-check all of them, because the clock-based ones fail silently by construction and the deferred issue is precisely the issue nobody re-reads.

## Prevention

- Treat "whichever fires first" lists as a checklist to evaluate in full, never as a menu where matching one entry ends the inquiry.
- Resolve every `#N` anchor in a time-based criterion with `gh issue view <N> --json closedAt` / `gh pr view <N> --json mergedAt` — the anchor's date is rarely the date anyone remembers.
- Record every fired trigger with its date in the brainstorm or plan, so a silently-overdue commitment becomes visible rather than being absorbed into the narrative of the event that happened to surface it.
- When a deferral bundles two capabilities with different urgency, split it. #3210 was deferred twice because one issue carried both a blocking mechanism and an unrelated PII question; the low-urgency half set the priority for both.

## Related

- `knowledge-base/project/brainstorms/2026-09-04-ccla-signing-mechanism-brainstorm.md` — "Three pre-committed triggers have fired"
- `knowledge-base/project/learnings/2026-09-04-an-agent-will-confidently-restate-the-position-your-corpus-already-corrected.md` — the same session's verification learning
