---
title: An issue's claim about RUNTIME state is refuted by a live off-host signal, not by reading more code — and a bare `-target` hits every for_each instance
date: 2026-07-27
category: best-practices
tags: [infra, terraform, for-each, issue-triage, drift-guard, premise-verification, cattle-hosts, ci-apply]
issues: [7000, 6459]
pr: 7001
---

## Problem

#7000 was a P1 `type/bug` with everything a good issue has: exact file paths, a named precedent to
copy (`placement-group.tf`), a load-bearing trap called out in bold (`for_each` changes the resource
address, so a missing `moved` block re-runs provisioners against live web-1), a second trap ("this
change is currently unguarded"), and six acceptance criteria. It prescribed fanning 15 web-1-pinned
`terraform_data` host provisioners in `server.tf` out over `var.web_hosts`.

Its central factual claim — *"`soleur-web-2` is a booted host, not a wired fleet member … never
receives the per-host env files, unit enablement, or config those provisioners write"*, with the
concrete instance *"`git_data_probe_install` writes `/etc/default/web-git-data-probe` and enables the
timer — on web-1 only"* — was **false**. And the prescribed fix was **unapplyable**: it would have
broken every merge-triggered infra apply.

Both were established before a single line of Terraform was written. The refutation cost one API
query.

## Root cause of the wrong premise

The issue reasoned from a `grep` over `server.tf` (15 resources hardcode
`connection.host = hcloud_server.web["web-1"].ipv4_address`) straight to a **runtime** conclusion
(web-2 lacks what they deliver). That inference skips the second delivery path. #6459 Phase 2.2 had
already given all 15 a fresh-boot route — the image bake (`local.host_script_files` →
`soleur-host-bootstrap.sh`) plus `cloud-init.yml` `write_files`/`runcmd`, including a baked
`web-probe-envwrite.sh` that writes exactly the `/etc/default/web-<probe>` files the issue named.

The web-1 pinning is *deliberate*, and `server.tf` says so at the `hcloud_server.web` comment: the
SSH provisioners stay web-1-scoped so a web-2 that is not yet SSH-reachable never hangs the
merge-triggered auto-apply. ADR-143 / #6459 **Phase 5 removes** them; it does not extend them.

## What actually settled it — a live signal, in ~4 minutes

```
BETTERSTACK_API_TOKEN_READONLY → GET /api/v2/heartbeats
  soleur-web-nic-guard-web-2      360s/120s   status=up   paused=false
  soleur-web-zot-consumer-web-2   180s/60s    status=up   paused=false
```

A 180s-period / 60s-grace heartbeat **cannot read `up`** unless the host is actively beating — it
flips `down` inside four minutes otherwise. And those probe units **cannot start without their
`/etc/default/web-<probe>` EnvironmentFile**, which is precisely the artifact the issue said only
web-1 receives. `web-probe.tf` further documents that the unpause happens only "after a real measured
beat lands", so `paused=false` is independent corroboration.

No amount of additional code reading would have been as conclusive, and code reading is what the
issue author had already done.

## Rules

1. **When an issue's claim is about RUNTIME state ("host X does not have Y", "the timer is not
   enabled", "the secret never lands"), verify it with a live off-host signal BEFORE writing code.**
   Heartbeats, monitor status, a state-reporter webhook, a metrics query. Static analysis of the
   provisioning code cannot see a second delivery path, and second delivery paths are exactly what a
   dual-delivery (pet + cattle) fleet has. This is the runtime-state sibling of "trace the ACTUAL
   producer, not the plan hypothesis", and of `hr-no-dashboard-eyeball-pull-data-yourself` — pull the
   data yourself, and pull it from the layer that would *observe* the defect.

2. **A "nothing guards this" claim must be measured per-subject, not by grepping one keyword.**
   #7000 supported its second trap with `git grep 'terraform_data' -- '*.test.sh' '*.test.ts'` →
   nothing. Literally true, materially misleading: `fresh-boot-parity.test.sh` guarded 5 of the 15
   already — keyed on the **artifacts** they deliver, not on the string `terraform_data`. The honest
   measurement is a per-resource loop (`for r in <all 15>; do grep -rlF "$r" *.test.sh; done`), which
   returned the real numbers: 10 of 15 unguarded for dual-delivery, 5 named by no suite at all. Guards
   commonly key on the artifact, the destination path, or the unit name — never assume the resource
   name is the index.

3. **Before converting a singleton to `for_each`, grep how CI `-target`s it.** A bare
   `-target=terraform_data.X` hits **every** instance, so the refactor silently widens the blast
   radius of every apply to hosts CI may have no route to. Here `apply-web-platform-infra.yml`
   `-target`s 14 of these by bare address, while CI can SSH exactly one host: `outputs.tf` exposes
   only web-1 as `server_ip`, `cf-tunnel-ssh-bridge` installs a single `iptables` NAT rule for that
   IP, the tunnel connector is web-1-only by construction (ADR-114 I1), and web-2's `:22` is
   firewalled to `var.admin_ips` which the non-static runner egress is not in. The `moved`-block trap
   the issue led with was real but **second-order** — the change could not apply at all.

4. **"Wired at birth, then frozen" is not "unwired".** On a cattle host, cloud-init runs once, so a
   later config edit reaches the pet over SSH and reaches the cattle host only on rebuild. That is
   `hr-prod-host-config-change-immutable-redeploy` working as designed, not a bug. Naming the gap
   precisely is what turns an unapplyable refactor into the guard that was actually missing.

## Resolution

No `.tf` file was changed. Delivered instead:

- `web-host-provisioner-parity.test.sh` — sweeps all 15 and every artifact each delivers across the
  four channels `server.tf` uses (`provisioner "file"` source, remote-exec heredoc, rendered
  `content=`, `printf`/`base64` env write), asserting each has a fresh-boot counterpart, with
  byte-identity where both paths carry their own copy of a unit body. Non-vacuity floor per section.
  Also pins the web-1 host-scoping, so a future fan-out fails here and forces the CI-reachability
  question to be answered first.
- `web-host-provisioner-parity-mutation.test.sh` — drives the real guard against a sandbox copy via
  `SOLEUR_INFRA_DIR`, breaks each invariant in turn, requires a RED for each (10 mutations, each
  proven landed), plus a positive control that must stay GREEN so an always-red guard cannot score a
  clean run.
- Adopted 2 orphan suites covering resources in the sweep. `run-registered-suites.sh` 72 → 76.

Related: [[2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name]],
[[2026-07-19-my-own-mutation-battery-was-the-false-confidence]],
[[2026-06-01-symptom-root-cause-trace-the-actual-redirect-not-the-plan-hypothesis]].
