---
title: Dedicated bastion; web hosts are identical cattle
status: active
date: 2026-11-10
---

# ADR-327: Dedicated bastion; web hosts are identical cattle

## Context

web-1 is a pet. It is the `ssh.` jump to git-data (ADR-220), the `deploy.` webhook target, the Inngest
SDK URL (ADR-100 Decision 1), the CI SSH key target and the luks-monitor primary. It carries 26
`terraform_data` provisioners, and `web-host-replace` refuses it. web-2 holds the tunnel connector
(ADR-114 I1) and is otherwise cattle. A role pinned to a host key cannot move when that host is
replaced. The owner asked for web-1 to be retired (#9421).

## Decision

Management-plane roles move to a dedicated bastion host, and web hosts become identical and
replaceable. The CTO ruled on this on 2026-11-10, and the ruling is binding:

- **Bastion.** `hcloud_server.bastion` in the web-platform root. It has no public inbound and an
  egress allowlist with a cited consumer per row. Its host key is generated in Terraform. It is born
  and replaced through gated routes, and it runs the same bounded apt and kernel-settle steps (ADR-326).
- **Roles are fields, not key literals.** Each role a web host holds is a field of `var.web_hosts`
  (`lb_weight`, `luks_monitor_profile`, `jump`, `tunnel_connector`), validated so that each
  single-holder role has exactly one host. Derived lists (the GA LB pool origins and the web private
  IP list) are computed from the map, and hand-kept copies are pinned to the derived value by test.
- **No SSH-delivered config to web hosts.** Config arrives only via the baked image and cloud-init.
- **Deploys and Inngest.** One `deploy-<key>.` hostname per web host through the bastion's connector.
  Inngest reaches the web hosts through a private Hetzner load balancer (ADR-100 Decision 1's "private
  VIP when active-active-N").
- **Retirement.** New hosts take new keys (`web-3`), never a reused `web-1`. Before web-1 is destroyed,
  every dirty worktree is flushed to git-data, and a read-only count of unflushed worktrees must read zero.

The work lands as a seven-PR sequence tracked on #9421. The first PR makes `var.web_hosts` keyed and
adds the kernel-settle birth step (ADR-326); it changes no running host. The host-bound-state census
(`knowledge-base/engineering/operations/web-host-bound-state-census.md`) records what a birth must
recreate.

## Consequences

- A new web host is one map entry plus the per-key items the census names (Doppler probe URLs and a
  kernel heartbeat), and it is born drained. Serving it is not yet one entry: the drain gate's input
  (`local.web_lb_gate`), the overlay's `SOLEUR_GATED_HOST` and the unkeyed workspaces LUKS marker each name
  web-2 alone. The plan refuses a second host serving outside the gate, and `lb-weight-gate.sh` refuses
  web-2's marker for any other key, so that wiring is a later PR's edit, not a silent gap.
- The bastion is a single point for the management plane (not for user traffic). Its own replace
  route bounds that risk.
- Until PR 7, web-1 literals remain. `web-hosts-generic.test.sh` ratchets their count down from the
  2026-11-10 measurement to zero.
- The bastion (about €4–5 per month) and the private load balancer (about €5–6 per month) are new
  recurring costs. The owner approved both on 2026-11-10. They are recorded in the ledger in the PRs
  that create them.
