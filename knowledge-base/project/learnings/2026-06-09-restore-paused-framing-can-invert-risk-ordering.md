# Learning: a "restore the paused X" issue framing can invert the real risk ordering — verify live-vs-paused state before accepting it

## Problem

Brainstorm of #5046 ("Tier-2: … → restore the paused crons"). The issue body's mental
model was: the 11 broad-bash claude crons are **paused and need a durable boundary to be
restored safely**, while a separate group of 4 `spawn("bash")` crons are "uncontained by
the hook" and "need the egress firewall before they can safely run unsandboxed." The
framing reads as "everything dangerous is currently held back; this issue unblocks it."

That framing is **inverted on the urgent axis**. A one-minute check found the 4
`spawn("bash")` crons (`content-publisher`, `content-vendor-drift`, `rule-prune`,
`weekly-analytics`) were registered in `cron-manifest.ts` with **no `deferIfTier2Cron`
guard and no pause** — running **live and uncontained right now**, holding `GH_TOKEN` +
12 social-API secrets with `*_ALLOW_POST: "true"` and unrestricted egress. The 11 "paused"
crons were the *safe-because-paused* population. The real urgent exposure was the group the
issue framed as "future work," not the group it framed as "blocked and waiting."

## Solution

Before accepting any "restore the paused X / unblock the held-back Y" framing in a
brainstorm, **verify the live-vs-paused state of every named actor against the runtime
registry**, not against the issue's prose:

```
# the pause/defer set is the source of truth, not the issue body
git grep -n "TIER2_DEFERRED_CRONS\|deferIfTier2Cron" -- '*_cron-shared.ts'
# every actor the issue calls "uncontained / future work" — is it actually gated?
for c in <named-actors>; do
  git grep -nE "deferIfTier2Cron|paused|DISABLED|enabled\s*[:=]\s*false" -- "<path>/$c.ts"
done
# and is it registered/live?
git grep -n "$c" -- '<registry/manifest file>'
```

If an actor named as "needs a boundary before it can run" is **already running**, the
boundary is a *containment of a live exposure*, not an *unblock of paused work* — which
flips the brand-survival threshold and the sequencing options you present to the operator.

## Key Insight

"Paused" and "needs containment" are independent axes. An issue author writing from the
in-flight-PR mental model often conflates them: the thing they just paused feels like "the
dangerous thing," so an adjacent uncontained-but-live actor gets described as future work.
The pause-state registry (the defer set / manifest) is ground truth; the issue body is a
point-in-time narrative. Checking the registry costs a minute and can invert which
population is urgent — which in turn changes the User-Brand Impact framing and the
sequencing question put to the operator (here: "contain-the-live-4 first" vs the chosen
"restore-the-11 first, accept the bounded live gap, expedite the firewall PR after").

## Session Errors

1. **CTO subagent reported the host was not Terraform-managed** — it read
   `apps/web-platform/infra/main.tf` (no `hcloud_server`) and missed `hcloud_server.web`
   in `server.tf`. **Recovery:** the parallel repo-research agent located it in `server.tf`
   + `firewall.tf`. **Prevention:** already covered — brainstorm SKILL.md "Cross-checking
   leader infra/substrate claims against repo-research" fired and caught it; no new rule.
   Reinforces running the repo-research agent in the same parallel batch as domain leaders
   so infra claims are cross-checked before they reach the brainstorm doc.
2. **Foreground `sleep 45` blocked** by the harness ("use Monitor with an until-loop").
   **Recovery:** relied on background-agent completion notifications instead. **Prevention:**
   one-off; never foreground-sleep to wait on background agents — they re-invoke on
   completion. Already harness-enforced.

## Tags
category: workflow-patterns
module: plugins/soleur/skills/brainstorm
