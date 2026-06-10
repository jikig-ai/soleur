# Learning: A "move X from A to B" request can conceal a scope fork — verify the *actual* complaint and the *actual* mechanism

## Problem

The operator asked to "move release notifications from Discord to Slack." Taken literally, that's a
slot-for-slot CI swap: delete the Discord step, add a Slack step. But the framing question surfaced
the real driver: a community member had **muted** the Discord `#releases` channel because there were
**too many** per-release posts (the project ships multiple times/day).

Two traps lurked:

1. **The "move" would have silently created a gap.** Removing the Discord per-release post entirely
   leaves the *community* with zero release visibility — but the underlying complaint was "too many,"
   not "none." A literal move solves the operator's stated request while regressing the community's
   experience in the opposite direction from the actual pain.

2. **The assumed fatigue mechanism was wrong.** It's tempting to "fix fatigue" by converting `#releases`
   to a quiet/no-`@mention` channel. But reading the *actual* Discord payload showed it already used
   `allowed_mentions:{parse:[]}` — i.e., it never pinged anyone. The fatigue was pure **message volume**,
   not mention-pings. A "quiet channel" change would have been a no-op against the real problem; the
   real fix is a **batched lower-frequency digest**.

## Solution

- Split the work along the fork the complaint revealed: per-release firehose → **internal Slack** (team
  tolerates high frequency); community → **weekly batched digest** (the actual fatigue fix), deferred to
  a fast-follow issue (#5080) rather than scope-creeping the Slack move (#5079).
- Before designing the community fix, **read the real payload** to confirm the fatigue mechanism
  (volume, not pings) instead of assuming it.

## Key Insight

A directive phrased as "move/replace/migrate X" encodes an *implementation*, not a *goal*. When the
request is anchored on a complaint, ask **what the complaint actually was** ("too many" ≠ "none") and
**verify the mechanism against the real artifact** (the actual webhook payload, the actual config) before
accepting the implied fix. The honest decomposition is often "do the literal move for one audience, and
build the *opposite-direction* fix (less, not none) for the audience that complained" — as two separately
-scoped pieces of work, not one.

## Tags
category: workflow-patterns
module: brainstorm
