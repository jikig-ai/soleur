---
title: "Docker inter-bridge traffic: the reply path is a separate rule — DOCKER-ISOLATION-STAGE-2 beats conntrack"
date: 2026-10-05
category: best-practices
tags: [docker, nftables, networking, egress, security]
symptoms:
  - "forward-accept rule added but CONNECTs through a second-bridge gateway hang/timeout"
  - "SNAT/forwarding works one way but TCP handshake never completes"
module: apps/web-platform/infra/cron-egress-nftables.sh
---

# Learning: docker inter-bridge reply path needs its own established/related accept — and any drop must be `ct state new`-scoped

## Problem

Design for the open-web egress gateway (`feat-open-web-egress`, #9534): an
app container on `docker0` must reach a Squid gateway on a custom bridge
(`soleur-egress0`). The forward leg looks trivial — `iifname "docker0"` jumps
into the repo's `SOLEUR-EGRESS` chain, where one `daddr <gw-ip> dport <port>
accept` fires before the default-drop and terminates evaluation.

Two review findings showed the connection still cannot establish:

1. **Reply path**: gw→docker0 SYN-ACKs arrive `iifname soleur-egress0,
   oifname docker0` — they skip the docker0-scoped jump entirely, then hit
   `DOCKER-ISOLATION-STAGE-2 -o docker0 DROP`, which Docker inserts BEFORE
   the `established,related` accepts. Conntrack does not rescue them;
   inter-bridge isolation rejects *established* replies too.
2. **Self-inflicted drop**: a defense-in-depth `iifname soleur-egress0 →
   RFC1918` drop would eat the same replies — docker0's `172.17.0.0/16` IS
   RFC1918. And the drop cannot live inside `SOLEUR-EGRESS` anyway (egress0
   packets never enter that iifname-scoped chain — dead code).

## Solution

Three rules, three placements:

- Forward leg: `iifname "docker0" daddr <gw-ip> tcp dport <port> accept`
  inside the existing docker0-scoped chain (before its default-drop).
- Reply leg: `iifname "<custom-bridge>" oifname "docker0" ct state
  established,related accept` at DOCKER-USER level, ordered BEFORE
  DOCKER-ISOLATION-STAGE-2.
- Deny leg: a separate chain jumped from DOCKER-USER on `iifname
  <custom-bridge>`, every deny scoped `ct state new` so replies pass.
  Invariant worth a fixture: NEW gw→docker0 connections must still drop —
  the accept is reply-traffic-only (one-way).

Related: resolver/self-heal needle sets that verify chain/ruleset presence
must be extended for every new chain, or deleting the chain goes unnoticed
by the drift guard.

## Key Insight

On docker's FORWARD path, "the connection works" is a claim about TWO
directions with different rule placement — and RFC1918-based deny lists
always contain the docker bridge ranges themselves, so any drop rule on a
bridge that serves other bridges must be `ct state new`-scoped or it eats
its own replies.
