# Learning: "Resume adding X" when X was recently retired — verify WHY it was retired before treating the retirement as an anti-goal

## Problem

A `/soleur:go` request said: "resume adding a web-2 host and create a cluster for redundancy." The IaC
carried loud, recent comments forbidding exactly that: `inngest-host.tf:10-11` — *"web-2 was retired
2026-07-17, #6538 — do NOT re-add a web-2 key"*, plus identical warnings in `variables.tf` and
`server.tf`. Taken at face value, those comments read as "the project decided against a 2nd web host,"
which would make the request contradict a settled decision — a wrong-premise reframe.

## Solution

Read the retirement issue (#6538) before treating the retirement as an anti-goal. The retirement was of a
**specific broken instance**, not the **capability**: the old web-2 was an `fsn1` orphan — unrebuildable
(`cx33` orderable only in `hel1`), shipping zero telemetry, and outside the HA placement group. Retiring
it removed a liability. The operator confirmed the actual target is *full active-active* — consistent with
ADR-068's recorded operator choice. The "do-not-re-add" comments were guarding against re-adding the
*broken shape*, not against HA.

Second half of the same session: the "add a 2nd host" ask decomposed into two very different-sized pieces.
Birthing the host is nearly free — `var.web_hosts` `for_each` is already generalized across
server/network/proxy-tls/web-probe/dns, and the deploy fan-out code (`fan_out_to_peers`) exists but is
dormant. The **real** work is the missing health-gated ingress/drain layer (no load balancer; `dns.tf` app
record is a web-1 singleton) plus the ADR-068 Phase-3 GA gate for concurrent serving (`replicas>1` never
enabled; two hosts writing one git index corrupts it). Naming that split up front reframed a "stand up a
host" ask into "build ingress + gate the flip."

## Key Insight

A "do-not-do-X" comment or a "retired X" state records what was true for a **specific instance under a
specific failure**, not a standing decision against the **capability**. When a request says "resume
adding X" and the tree says X was retired, read the retirement's own issue for the *root cause* — a broken
instance (stock, DC, telemetry, placement) argues for a *better* rebuild, whereas a capability rejection
(YAGNI, cost-with-no-consumer, superseded design) argues against. They have opposite dispositions and the
comment alone cannot distinguish them. This is the archaeology-verification rule
([[2026-07-16-issue-archaeology-is-a-claim-verify-against-the-pr-that-made-the-state]]) applied to a
*retirement* rather than a *placement*: the state's comment is a claim to verify against the issue that
created it, not a fact to route on.

Corollary: before sizing an infra ask, split it into "what the existing `for_each`/fan-out already gives
for free" vs "the primitive that's actually missing" — the missing primitive (here: health-gated
ingress/drain) is usually the real work, and the host itself is the cheap part.

## Session Errors

- **Malformed jq filter (stray `｜` character) → empty `gh issue view` output.** Recovery: re-ran with a
  clean `jq -r` filter. Prevention: one-off typo, no rule warranted.
- **`git grep -E '...|{'` → ugrep "empty (sub)expression".** Recovery: simpler pattern. Prevention:
  one-off; escape or avoid bare `{` in alternations.

## Tags
category: workflow-patterns
module: soleur-go, brainstorm, apps/web-platform/infra
