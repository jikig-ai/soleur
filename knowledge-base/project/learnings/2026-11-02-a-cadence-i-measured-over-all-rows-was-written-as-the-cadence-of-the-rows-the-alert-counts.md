# Learning: a cadence measured over every row under a tag was written as the cadence of the one row type an alert counts

## Problem

PR #11887 added a comment and two runbook notes saying a Better Stack `lower_than` silence incident can stay open after its data returns. The evidence lines in the `.tf` comment said object-typed flip rows were "arriving about every 40 s (11 in the last hour)". Eleven rows an hour is one per five minutes. The 40 s figure came from reading every row under the `inngest-cutover-flip` tag, and most of those rows are string-typed Doppler lines that the alert's predicate (`JSONType(raw,'message')='Object'`) does not count. Three fix-round seats found the contradiction, and the same file's own header, the emitter's 300 s throttle and `tasks.md` all said five minutes.

Two siblings in the same edit: "no `lower_than` incident has auto-resolved in the mirror history" had no scope (the mirror had run for about a week), and a plan AC ticked `[x]` named `git diff --name-only origin/main`, which lists 40 files main gained since the branch base.

## Solution

State each measurement over the population the claim is about. The object-typed rows, not the tag, and not "rows". Scope a universal negative to the window that was observed. Run an AC's command exactly as written before ticking it, and fix the AC text when the three-dot form is the one that was meant.

## Key Insight

A figure read from one query is a fact about that query's filter. Before it goes into a sentence, name the predicate the sentence is about and check the figure was measured under it. Two numbers from the same tag (a high one and a low one) are the signal to ask which one the alert counts.

## Session Errors

1. **Wrote "about every 40 s" for object rows** — Recovery: replaced with "about one per 5 min (11 in the last hour)" — **Prevention:** when a comment cites a cadence, quote the filter it was measured under and compare it with the emitter's own throttle constant before writing it.
2. **Universal negative with no scope ("no lower_than incident has auto-resolved")** — Recovery: scoped to the mirror window (first mirror issue 2026-10-25) — **Prevention:** a "no X has ever Y" sentence names the observation window in its own clause, never in a later one.
3. **Ticked a plan AC whose literal command was false** — Recovery: changed the AC to the three-dot form — **Prevention:** run every AC command as written; if the output contradicts the AC, amend the AC text explicitly.
4. **Ended a turn on a first-person promise; the Stop hook blocked it** — Recovery: did the action in the same turn — **Prevention:** already hook-enforced.
5. **Offered a technical fork (pause vs investigate an alert) to the operator** — Recovery: sent it to the CTO agent, which ruled — **Prevention:** `hr-technical-fork-is-not-an-operator-question`.

## Tags

category: workflow-issues
module: betterstack-alerts
