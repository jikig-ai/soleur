# Learning: Stale content publisher sends duplicate Discord warnings daily

## Problem

The `content-publisher.sh` cron (runs daily at 14:00 UTC) detects files in `knowledge-base/marketing/distribution-content/` with `status: scheduled` and a past `publish_date`. When found, it posts a "Stale scheduled content detected" warning to Discord. However, it never updates the file status after warning, so every subsequent daily run re-sends the same warning for every stale file indefinitely.

Symptom: 4 duplicate Discord notifications per day for the same 4 stale content files.

## Solution

Added `sed -i 's/^status: scheduled/status: stale/' "$file"` after the stale warning is posted (line 515 of `content-publisher.sh`). This transitions the file to `status: stale`, which causes the `[[ "$status" == "scheduled" ]] || continue` guard on line 509 to skip it on subsequent runs.

The workflow's commit step already stages all files in `distribution-content/`, so the `stale` status change gets committed back to main automatically.

## Key Insight

Every detection-and-alert path must also transition the entity out of the detected state, so the alert is idempotent. Firing the handler once and firing it N times should produce the same observable side effects. The signature of this anti-pattern is a read-only query paired with a write-only side effect and no state mutation in between (grep-then-curl without sed).

## Prevention

- **Test case:** A Bats test that runs the stale detection function twice against the same fixture. Assert the webhook is called exactly once and the file reads `status: stale` after the first run.
- **Pattern to audit:** Any cron/loop that scans for a condition and fires a notification without updating the source data. Check reminder crons, retry loops, and webhook dispatchers for the same read-then-notify-without-mutate pattern.

## Related

- GitHub issues #796, #797: LinkedIn API failures for content publisher (same script)
- GitHub issue #553: IndieHackers posting for content publisher

## Tags

category: logic-errors
module: content-publisher
problem_type: missing-state-transition
severity: medium
tags: [content-publisher, discord, cron, stale-detection, duplicate-notifications, idempotency]
