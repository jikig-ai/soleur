---
title: "Grok dogfood host: no private-net join, YOLO off by default, no passwordless sudo"
date: 2026-07-16
category: workflow-patterns
module: apps/web-platform/infra
issue: 6545
pr: 6544
refs: ["#6545", "#6546", "#6547", "#6416"]
tags: [infra, grok-build, dogfood, terraform, security, review]
---

# Grok dogfood host: isolate from the private trust plane

## Problem

Phase 1 of the headless Grok Build Hetzner trial (#6545) stood up a gated
`hcloud_server.grok_dogfood` with cloud-init that installs the Grok CLI and a
measurement script. First-pass design joined the private network (fixed IP
`.50`), granted passwordless sudo to `dogfood`, and ran measure with `--yolo`
by default — convenient for an agent that needs tools, catastrophic if the
agent misbehaves on a host that shares L2 with zot/git-data/web.

Review P1s named the blast radius:

1. **Private net = trust plane.** YOLO-capable shell on the same L2 as
   registry/git-data is an unnecessary lateral-move surface for an
   operator-only dogfood host that only needs public egress to xAI + GitHub.
2. **YOLO on by default** turns every measure run into full tool autonomy.
3. **Passwordless sudo** lets a prompt-injection path escalate to root.
4. **CLI "pin" claims** overstated install.sh behavior (tracks latest stable,
   not a checksum-pinned artifact).

## Solution

Hardened in `c442dc6cb` before ship:

| Control | Before | After |
|---------|--------|--------|
| Network | `hcloud_server_network` on private subnet | Public IPv4 only; no private-net join |
| Measure flags | `--yolo` default | YOLO off; opt-in via env/flag documented in runbook |
| Sudo | `NOPASSWD:ALL` for `dogfood` | No passwordless sudo; no sudo group |
| CLI pin | Implied fixed pin | Honest: install.sh + version log; checksum pin is runbook/operator |

Provision remains **flag-gated** (`enable_grok_dogfood` default `false`) so
per-PR apply never births the host (#6416 tripwire). Live create is a
post-merge free-slot check + `TF_VAR_enable_grok_dogfood=true` targeted apply.

## Key Insight

**An agent dogfood host is not "another app server."** Anything with
autonomous shell + model API access must be scored as a high-privilege
workstation: keep it **off** private trust planes, deny root by default, and
require explicit opt-in for YOLO. Reusable substrate (#6546 open-model swap,
#6547 product ACP) still holds — network isolation is orthogonal to model
endpoint swap.

## Prevention

- Review checklist for agent hosts: private-net join? passwordless sudo?
  YOLO default? secrets on disk mode?
- Default-deny flags for any new dogfood/agent TF resource (same pattern as
  `enable_grok_dogfood`).
- Prefer public-egress-only until a concrete fleet-tooling need requires
  private L2 — then document the threat model first.

## Session Errors

**Ship-session inventory (this compound run):** none detected in the ship
turn itself. Implementation + review P1 fix landed in prior turns on the same
branch; this compound archives plan/brainstorm/spec and records the review
hardening lesson.

**Prevention:** Keep review P1 hardening on the same PR as the substrate so
ship does not land a private-net YOLO host "and fix later."

## Related

- Runbook: `knowledge-base/engineering/operations/runbooks/grok-build-hetzner-dogfood.md`
- TF: `apps/web-platform/infra/grok-dogfood.tf`, `cloud-init-grok-dogfood.yml`
- Measure: `scripts/dogfood/grok-measure.sh`
- Deferred: #6546 (open-model), #6547 (product ACP)
