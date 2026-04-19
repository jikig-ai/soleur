---
date: 2026-04-19
category: bug-fixes
module: ops-ssh-firewall
tags: [ssh, firewall, hetzner, fail2ban, misdiagnosis, layer-ordering, admin-ip, workflow-gate]
related:
  - knowledge-base/project/learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md
  - knowledge-base/engineering/ops/runbooks/admin-ip-drift.md
  - knowledge-base/engineering/ops/runbooks/ssh-fail2ban-unban.md
  - AGENTS.md#hr-ssh-diagnosis-verify-firewall
  - PR #2655
  - issue #2654
  - issue #2681
---

# Learning: admin-IP drift misdiagnosed as fail2ban lockout (layer-ordering failure in hypothesis generation)

## Problem

On 2026-04-19, operator SSH to `soleur-web-platform` failed with
`kex_exchange_identification: read: Connection reset by peer`. Issue #2654
opened to diagnose; the plan proposed three hypotheses, all sshd-layer:

1. fail2ban permanent ban
2. sshd config drift
3. sshguard conflict

PR #2655 shipped a correct fail2ban `bantime.maxtime` cap -- preventive,
well-scoped, reviewed. But it was not causal. The actual outage was
L3 firewall-layer: `Doppler prd_terraform/ADMIN_IPS` held a single CIDR
(`82.67.29.121/32`) and the operator's ISP-assigned egress IP had
rotated to `66.234.146.82`. The Hetzner Cloud Firewall dropped port-22
ingress at L3; sshd never saw the packet.

The signal was visible but not sought: `journalctl -u ssh` had NO entry
for the operator IP during the incident window. A packet that reaches
sshd produces a log line (banner exchange, kex, auth attempt). Silence
in the sshd journal means the packet was dropped before sshd -- which
is a direct "firewall first" indicator the plan never checked.

The misdiagnosis happened because the plan skill did not force an
L3->L7 ordering on hypothesis generation. The planning subagent
defaulted to the most proximate symptom (kex reset) and produced
layer-proximate hypotheses (sshd, fail2ban) without verifying that
lower layers were clear.

## Why it recurred

Institutional learning
`2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md` documents the
same class, from a CI-runner angle: GitHub Actions deploy failed
because Hetzner's port-22 rule was scoped to `admin_ips` and runners
have ~5000 rotating IPs. That incident's key insight:

> Always verify network connectivity independently from authentication
> -- they are separate failure modes that produce different errors at
> different stages of the SSH handshake.

The insight was captured but not enforced at the plan layer. A new
incident produced a new plan that made the same inversion.

## Solution

Three-layer defense:

1. **Operator runbook** (`knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`)
   -- the diagnostic decision tree enforces L3 checks (firewall, egress
   IP diff, routing) before L7 checks (sshd, fail2ban).

2. **Operator skill** (`/soleur:admin-ip-refresh`) -- detects drift,
   proposes the corrective Doppler mutation with explicit operator ack,
   and emits the exact `terraform apply` invocation. No auto-apply, no
   vendor-API side door -- per AGENTS.md `hr-all-infrastructure-provisioning-servers`
   and `hr-menu-option-ack-not-prod-write-auth`.

3. **Workflow gate** -- new AGENTS.md hard rule
   `hr-ssh-diagnosis-verify-firewall`, new reusable checklist at
   `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md`,
   integrated into `plan/SKILL.md` Phase 1.4 and `deepen-plan/SKILL.md`
   Phase 4.5. Any plan addressing an SSH/network-connectivity symptom
   triggers the checklist, which requires the `## Hypotheses` section
   to list unverified layers in L3->L7 order BEFORE any service-layer
   hypothesis.

The fix prioritizes the workflow-gate layer per AGENTS.md
`wg-when-a-workflow-gap-causes-a-mistake-fix`: a rule + skill
instruction edit, not just a learning file. The learning file captures
the class for future investigators; the rule + instruction edits
prevent the class from recurring.

## How to prevent

When drafting hypotheses for a network-connectivity symptom, the
ordering discipline is:

- L3 first (firewall allow-list, DNS resolution, routing reachability)
- L4 next (TCP state, MTU)
- L7 last (TLS cert chain, service config, jail state)

A layer that drops packets is invisible to layers above it. Starting
at L7 and working up produces phantom hypotheses: fail2ban cannot be
the cause of a reset if fail2ban never saw the packet.

For SSH specifically, the load-bearing diagnostic is:

```bash
# Client side:
curl -s https://ifconfig.me/ip     # Current egress IP

# Server side (or from Hetzner CLI):
hcloud firewall describe soleur-web-platform  # Realized allow-list

# Doppler (source of truth):
doppler secrets get ADMIN_IPS -p soleur -c prd_terraform --plain
```

If the egress IP is not in the Doppler list, drift exists. If the
Doppler list does not match the firewall's `source_ips`, drift exists
in the other direction. Either invariant failing is a hard-stop on
further L7 hypothesis generation until resolved.

## Why the workflow-gate layer is the real fix

PR #2655's fail2ban cap was preventive and correct -- it shipped a fix
to a genuine (but orthogonal) failure mode. The recurring class is not
"missing fail2ban cap" but "layer-order inversion in hypothesis
generation." A learning file alone documents the class for future
investigators but does not prevent the next plan from making the same
inversion. The AGENTS.md rule + plan-skill Phase 1.4 + deepen-plan
Phase 4.5 integration turns the discipline into a trigger that fires
automatically on any future SSH/network symptom.

Per AGENTS.md `wg-every-session-error-must-produce-either`: every
session error must produce either an AGENTS.md rule, skill instruction
edit, or hook -- not just a learning file entry. This learning covers
all three.
