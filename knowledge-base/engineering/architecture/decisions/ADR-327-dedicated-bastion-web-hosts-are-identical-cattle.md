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

## Addendum — 2026-11-18 (#12866, step 2a)

Step 2 ships as two PRs. This one (2a) births `soleur-bastion`; #12879 (2b) adds its replace route and
heartbeat, and blocks step 3. The plan is
`knowledge-base/project/plans/2026-11-17-feat-dedicated-bastion-host-gated-routes-plan.md`; the operator
acts are in `knowledge-base/engineering/operations/runbooks/bastion-host.md`.

- **Routes are `apply_target` jobs, not workflow files.** `bastion-host-create` is a job in
  `apply-web-platform-infra.yml` (`confirm=BIRTH-bastion`, environment `web-platform-infra-apply`, the
  workflow's own concurrency group). Its gate admits only the addresses in
  `tests/scripts/lib/bastion-resources.txt`; `plan_only` runs first and prints the commit and the
  planned addresses for the owner's go.
- **Until 2b merges, the Consequences line "its own replace route bounds that risk" is not yet true.**
  A birth that does not report `fresh_boot_ready` is powered off (disk kept) and commented on #12879;
  there is no in-repo exit until 2b.
- **git-data admits by private-network membership plus forced commands.** Residual: any member of the
  private network reaches git-data:22. The nftables source allowlist is #12880.
- **Hetzner firewalls filter only the public interface.** The bastion's own nftables `input` chain
  drops private-network inbound; git-data does not yet (#12880). On first boot the baseline loads only
  after apt installs `nftables`; sshd is masked and the zero-rule Hetzner firewall covers that window.
- **Egress rows land with the consumer they serve.** 2a allows only the apt mirrors and Sentry ingest,
  each cited to its on-host consumer; later steps add rows with their dialers.
- **The bastion host key does not rotate on replace.** Residual: a leaked copy (Terraform state or
  `user_data`) stays valid until a deliberate rotation, which the runbook defines.
- **Cost.** The bastion is EUR 5.99 per month (cx23 plus its primary IPv4), not the EUR 4–5 above.
  The owner's go on the real birth accepts it; the ledger rows land in this PR.
