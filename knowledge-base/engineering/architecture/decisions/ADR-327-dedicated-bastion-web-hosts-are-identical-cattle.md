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

Step 2 ships as two PRs. This one (2a) declares `soleur-bastion` and its gated birth route; the birth
itself is an owner-authorized dispatch after merge. #12879 (2b) adds the replace route and heartbeat,
and blocks step 3. The plan is
`knowledge-base/project/plans/archive/20261119-111207-2026-11-17-feat-dedicated-bastion-host-gated-routes-plan.md`; the operator
acts are in `knowledge-base/engineering/operations/runbooks/bastion-host.md`.

- **Routes are `apply_target` choices of `apply-web-platform-infra.yml`.** `bastion-host-create` is a
  thin job there that calls the reusable `bastion-host-create.yml` (`confirm=BIRTH-bastion`, environment
  `web-platform-infra-apply`), so it runs inside the caller's run and holds the workflow's concurrency
  group. The body lives in its own file because the caller sits at its byte gate
  (`workflow-file-size.test.ts`); 2b's replace job joins it there. Its gate admits only the addresses in
  `tests/scripts/lib/bastion-resources.txt`; `plan_only` runs first and prints the commit and the
  planned addresses for the owner's go.
- **Until 2b merges, the Consequences line "its own replace route bounds that risk" is not yet true.**
  A birth that does not report `fresh_boot_ready` is powered off (disk kept) and commented on #12879;
  there is no in-repo exit until 2b.
- **git-data admits by private-network membership plus forced commands.** Residual: any member of the
  private network reaches git-data:22. The nftables source allowlist is #12880.
- **Hetzner firewalls filter only the public interface.** The bastion's own nftables `input` chain
  drops private-network inbound; git-data does not yet (#12880). The host has no filter of its own
  until the post-settle pass enables `nftables.service` (on the kernel-update path: the first boot, the
  settle reboot and the second apt run); sshd is masked and the zero-rule Hetzner firewall cover that window.
- **Egress rows land with the consumer they serve.** 2a allows DNS to the Hetzner resolvers, NTP for
  `systemd-timesync`, the metadata endpoint for root, and tcp/443 to the apt mirrors and Sentry ingest for
  root and `_apt`, each row cited to its on-host consumer. The lint refuses an output accept row with no
  destination or owner qualifier and any private-range destination. Later steps add rows with their dialers.
- **The bastion host key does not rotate on replace.** Residual: a leaked copy (Terraform state, or
  `user_data` as the metadata endpoint serves it to root on the host) stays valid until a deliberate rotation, which the runbook defines.
- **Cost.** The bastion is EUR 5.99 per month (cx23 plus its primary IPv4), not the EUR 4–5 above.
  The owner's go on the real birth accepts it; the ledger rows land in this PR.

## Addendum — 2026-11-20 (#12941, first-boot rehearsal)

The byte pins in `apps/web-platform/infra/bastion.test.sh` passed a template whose boot depends on the image
shipping `systemd-timesyncd`. The public noble cloud image ships it; Hetzner's image is unverified. Step 2a
therefore also needs a runtime rehearsal of the first boot. `apps/web-platform/infra/bastion-runcmd-rehearsal.test.sh`
boots the rendered `bastion-cloud-init.yml` under real cloud-init, with systemd as PID 1, in privileged
containers on the pinned `ubuntu:24.04` image. It runs in the `bastion-boot-rehearsal` job of
`infra-validation.yml`. The plan is `knowledge-base/project/plans/2026-11-20-feat-bastion-runcmd-rehearsal-plan.md`.

- **The template installs every user its nftables rules name.** The `skuid` rows name `systemd-timesync`.
  The template did not install `systemd-timesyncd`, which owns that user, so its boot depended on the image
  shipping it. This is latent image-dependency hardening, not a live fault. The apt line now names it, and
  the suite checks every named user exists.
- **`IMAGE_ASSUMED` in the suite is the declared contract with the image.** A container is not Hetzner's
  image. The suite therefore boots a minimal baseline for every row and adds one boot on a package set
  copied from the noble cloud-image manifest. The minimal boot proves the template installs what it needs;
  the cloud-faithful boot proves the template survives the cloud image's copies of the 10 packages it
  touches (`CLOUD_IMAGE_PKGS`), not the rest of the manifest. The suite header lists where the
  container differs from the real host.
- **A failed egress load reports its real reason.** This was a reporting defect, not a boot failure. The
  fatal's `detail` tag now carries the failing lines from both units' journals, or
  `why=no_reason_line` with both units' `Result` values, and no longer systemd boilerplate.
- **The job is advisory on pull requests.** It is not a required check, so a red run can merge. #12942 will
  gate the birth by running the rehearsal inside the birth run and requiring success. Until it lands, the
  runbook's dispatched check is the only gate (`bastion-host.md`, "Pre-birth boot evidence"). Neither reads
  an existing check-run: push runs are paths-filtered and duplicate-skipped, so the birth SHA usually has none.
- **The local runner never executes the suite.** `run-registered-suites.sh` lists it in `DEDICATED_JOB_WHY`
  and treats it like a privileged suite: derived, never executed, sharded or unsharded. Locally, run it
  directly with `bash apps/web-platform/infra/bastion-runcmd-rehearsal.test.sh`.
- **Alternative rejected for now: boot the real Ubuntu cloud image under QEMU/KVM with a NoCloud seed.**
  It would still not be Hetzner's image, costs about 600 MB per run, and `/dev/kvm` is unverified on the
  runner class. It reopens on a fault the container provably cannot reproduce, or once `/dev/kvm` is
  confirmed on `ubuntu-24.04` runners with a cached image.
