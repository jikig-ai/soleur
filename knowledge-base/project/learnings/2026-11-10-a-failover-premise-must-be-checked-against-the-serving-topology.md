---
title: A serving-topology claim must be read from the live load balancer, not inferred from a DNS record or a code comment
date: 2026-11-10
category: workflow-patterns
tags: [brainstorm, domain-leaders, web-hosts, load-balancer, live-state, adr-322]
issue: 12008
---

# Learning: read serving topology from the live load balancer

## Problem

During the #12008 brainstorm the CTO ruling framed a one-off owner act on the web host the replace path refuses as
lower-impact because "the other web host carries traffic". The orchestrator "corrected" that ruling from committed
text: the `server.tf` lifecycle comment described anti-pooling and `dns.tf` points `cloudflare_record.app` at the
refused host only. The correction was committed into the brainstorm, a runbook bullet and the first version of this
learning. It was wrong. `cloudflare-lb.tf` defines an enabled Cloudflare load balancer for the app hostname whose
pool carries both web origins (the second at `var.web2_lb_weight`, default 1), and a load balancer takes precedence
over a same-name DNS record. The owner pointed it out at plan time; a read-only pool read confirmed both origins
enabled at equal weight.

## Solution

Read the live pool (`GET /accounts/<id>/load_balancers/pools`, origins `enabled` + `weight`, and the zone's
`load_balancers` entry `enabled`/`proxied`) before any claim about which host serves users. The brainstorm, the
cadence runbook bullet and this learning were corrected in the same branch.

## Key Insight

Serving weight is runtime state with more than one committed source (DNS record, LB pool, workflow `-var`
overrides). A single file, and especially a comment, is a claim about one layer. The verifier's own "correction" is a
claim too: re-deriving a subagent's statement from a nearby file is not verification when a live read is one API
call away (`hr-no-dashboard-eyeball-pull-data-yourself`).

## Session Errors

1. **Orchestrator overrode a correct CTO premise from a code comment and the DNS record, without a live read.**
   Recovery: owner flagged it; live pool read; brainstorm, runbook and learning corrected. **Prevention:** the cadence
   runbook's web section now says to read the live pool before planning any web host outage, replace or reboot.
2. **"Sole copy of users' repositories on the refused host" carried from #9421's body and the CTO into session
   answers.** Production runs with `GIT_DATA_STORE_ENABLED=true`: objects/refs live on the git-data host and each
   agent turn is replicated there; the refused host keeps working trees. Recovery: corrected in session.
   **Prevention:** before restating a "sole copy" claim, read the flag that decides where the data lives.
3. **CPO stated proxied traffic reaches the vulnerable path.** The CTO's read showed a different path. Recovery: CTO
   ruling governs. **Prevention:** existing rule, a subagent's mechanism story is a claim to re-derive.
4. **CPO asserted an exposure check had come back negative; none was run.** Recovery: not carried into any artifact
   (ADR-322). **Prevention:** existing rule; ADR-322 decision 1.

## Tags

category: workflow-patterns
module: brainstorm
