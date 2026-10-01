---
date: 2026-09-17
category: machinery
module: soleur/followthroughs
related:
  - scripts/sweep-followthroughs.sh
  - knowledge-base/engineering/operations/runbooks/followthrough-convention.md
  - "#8160"
---

# Learning: enrolling a followthrough directive on an EXISTING issue has three silent-failure traps

## Problem

A plan prescribed `<!-- soleur:followthrough ... -->` on an already-open
issue (#8160). Review caught that the directive would have been either
completely inert or daily-spamming — and nothing would have reported either
state:

1. **Missing `follow-through` label** — the sweeper enumerates
   `gh issue list --label follow-through`; it never parses issue bodies. A
   directive on an unlabeled issue is invisible. The gate that normally adds
   the label only fires on issue *create*, so nothing enrolls it for you.
2. **Bare `script=` filename** — the convention requires the canonical
   `script=scripts/followthroughs/<name>.sh`. The bare name fails the
   sweeper's path canonicalization — a `fail()` line in the run log,
   **stderr-only, zero comments** — silently, every run, forever.
3. **Notify-only probes still comment daily** — the sweeper comments on
   EVERY non-0/1 verdict with no dedup. A months-long wait state (exit 2
   NOT YET) produces ~30 comments/month on the tracking issue. The sweeper
   is therefore wrong for indefinite-horizon watches regardless of probe
   contract — a dedicated scheduled workflow that files one deduplicated
   issue on detection is the right shape.

## Solution

- For long-horizon "detect upstream change" watches: dedicated
  `scheduled-*-drift.yml` workflow + `Ref #N` in the filed issue's body.
  The watcher filing the issue IS the signal; the heartbeat is the
  dead-watcher signal. No sweeper binding needed.
- If a directive on an existing issue IS the right mechanism, the
  enrollment checklist is: verify `follow-through` label → verify no prior
  directive → directive at column 0 → canonical
  `script=scripts/followthroughs/<name>.sh` → `secrets=GH_TOKEN` if the
  probe calls `gh` → ISO-8601 `earliest=` → post-merge verify the sweeper
  log shows the script actually ran.

## Key Insight

The sweeper's failure modes are all silent: a missing script produces a
stderr line, an unlabeled issue produces nothing at all. "It didn't
comment" is indistinguishable from "it worked and found nothing" — so a
directive that is never *verified armed* may as well not exist. Also: the
reasoning that rejects the sweeper as a primary watcher (comments every
run) applies equally to a sweeper binding on the tracker — check your own
cut list for ideas you've reintroduced under a different name.

## Session Errors

1. **Proposed a followthrough binding that reintroduced the rejected spam
   cost.** Recovery: 7-agent plan-review panel caught it (5 independent
   findings); probe+directive cut, replaced by `Ref #8160` in the
   drift-issue body. **Prevention:** when a plan's Cut List rejects
   mechanism X for cost C, grep the rest of the plan for X-shaped
   mechanisms carrying the same C before drafting.
2. **CTO subagent report truncated to `<stop>` marker.** Recovery:
   resumed the agent with a re-emit request. **Prevention:** none needed
   — `resume` is the supported recovery.
3. **Can't find lefthook in PATH** on commit. **Prevention:** known
   environmental warning, non-blocking.

## Tags

category: machinery
module: soleur/followthroughs
