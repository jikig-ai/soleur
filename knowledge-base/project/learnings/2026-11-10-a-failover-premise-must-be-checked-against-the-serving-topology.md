---
title: A leader's failover premise must be checked against the serving topology before it bounds an operator act
date: 2026-11-10
category: workflow-patterns
tags: [brainstorm, domain-leaders, web-hosts, anti-pooling, adr-322]
issue: 12008
---

# Learning: a failover premise must be checked against the serving topology

## Problem

During the #12008 brainstorm the CTO ruling proposed a one-off owner act on the web host the replace path refuses and
framed it as low-impact: "reboot once while the other web host carries traffic". Committed config is anti-pooling: the
app record points at the refused host only and no load-balancer pool carries app weight on the other web host
(`apps/web-platform/infra/server.tf` lifecycle comment, ADR-068 §(c), ADR-143). The other host's tunnel connector is
management-plane only. So the act is a full app outage for its duration, which changes the user-notice posture.

## Solution

The orchestrator grepped `server.tf` while verifying the CTO's cited `ignore_changes` line and read the adjacent
anti-pooling comment. The brainstorm records the correction next to the ruling, and the cadence runbook's web section
now states the topology so the next reader does not inherit the premise.

## Key Insight

"X carries traffic while Y is down" is a capability claim about the serving topology, not a property of having two
hosts. Before a leader's failover framing bounds an operator act or its communication plan, grep the record that routes
user traffic (DNS record target, LB pool membership) for the standby. Host count is not pool membership.

## Session Errors

1. **CTO failover premise contradicted committed anti-pooling config.** Recovery: verified against `server.tf` and
   corrected in the brainstorm. **Prevention:** runbook web section now states the topology (fixed inline); keep using
   the brainstorm's "cross-check leader infra/substrate claims" rule for failover claims too.
2. **CPO stated proxied traffic reaches the vulnerable path.** The CTO's read showed the path is a blind spoofed
   handshake packet past a source-address-only firewall. Recovery: CTO ruling governs. **Prevention:** existing rule,
   a subagent's mechanism story is a claim to re-derive.
3. **CPO asserted an exposure check had come back negative; none was run.** Recovery: not carried into any artifact
   (ADR-322 makes exposure `unknown` by default). **Prevention:** existing rule, re-derive subagent claims; ADR-322
   decision 1.

## Tags

category: workflow-patterns
module: brainstorm
