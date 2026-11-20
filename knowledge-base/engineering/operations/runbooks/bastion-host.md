# Runbook — the dedicated bastion (`soleur-bastion`)

ADR-327 step 2a (#12866). The design and its residuals are in the ADR-327 addendum of 2026-11-18;
this page holds only the acts.

- **Birth route:** `apply-web-platform-infra.yml`, `apply_target=bastion-host-create`, `confirm=BIRTH-bastion`.
- **Replace route:** `bastion-host-replace`, which is #12879 (step 2b) and does not exist yet.
- **Approval:** the `web-platform-infra-apply` environment reviewer. The `confirm` token is a typo-guard only.
- **Resource list:** `tests/scripts/lib/bastion-resources.txt`. The job `-target`s exactly this list, and the birth gate admits nothing else.
- **Cost:** EUR 5.99 per month (cx23 plus its primary IPv4). The owner's go on the real birth accepts it.
- **State in 2a:** declared, not born. The host exists only after a `bastion-host-create` run reports ready.
- **Once born:** no role. sshd is masked and nothing dials it. Egress is DNS to the Hetzner resolvers, DHCP requests for `systemd-network`, NTP for `systemd-timesync`, the metadata endpoint for root, and tcp/443 to the apt mirrors and Sentry ingest for root and `_apt`. Nothing else leaves the host, and no private address is reachable. The sshd drop-in (for step 3) refuses root login and every forwarding but TCP. It has no heartbeat until #12879.

## Birth

The agent runs both dispatches below. Each needs the owner's typed go naming the exact command.

**Pre-birth boot evidence.** `apps/web-platform/infra/bastion-runcmd-rehearsal.test.sh` boots the rendered template under real cloud-init in the pinned `ubuntu:24.04` image. CI runs it as the `bastion-boot-rehearsal` job of `infra-validation.yml`; locally, `bash apps/web-platform/infra/bastion-runcmd-rehearsal.test.sh` (needs Docker with `--privileged`). The job is advisory on pull requests, so a red run can merge. Until #12942 lands, the agent checks that run is green on the birth commit before the real birth; #12942 makes the birth refuse it otherwise.

**Dispatch only when the owner can approve at once.** The run holds the shared `terraform-apply-web-platform-host` group while it waits for the environment reviewer, and GitHub keeps one pending run per group: a later queued run (a merge's apply, an `cf-lb-overlay` drain, a key rotation) cancels the one waiting behind it. Approve it promptly or cancel it.

1. **Rehearsal.**
   `gh workflow run apply-web-platform-infra.yml -f apply_target=bastion-host-create -f confirm=BIRTH-bastion -f plan_only=true -f reason="bastion birth rehearsal (#12866)"`.
   It runs the readiness interlock, the DSN assert, the plan, the birth gate and the stock gate, then stops.
   Its run summary lists the commit SHA and every planned address with its action. The agent posts the run ID, the SHA and the list on #12866.
2. **Real birth.**
   After the owner has read that list, run the same command with `-f plan_only=false`, quoting the rehearsal run ID in `reason`.
   - A green run means two things: the gated plan applied, and `soleur-bastion` reported `fresh_boot_ready` after the run's anchor.
   - The summary prints the host key fingerprint and the private IP (10.0.1.70, read from `hcloud_server_network.bastion`). #12880 pins them.

**Stock failure.** If the stock gate aborts with `class=stock`, nothing was created. Do not change the server type to get past it. Wait and re-dispatch, or take the type question to the owner (ADR-143 precedent). Any other class names its own cause in the `::error::` lines.

## Partial birth

Terraform creates the key and the firewall before the server. If the apply fails part-way, the retry is legal only in these shapes:

- **The key or the firewall landed, but the server did not.** Re-dispatch. The gate accepts `no-op` on any listed address, and an `update` on the firewall attachment. It still requires exactly one create, of `hcloud_server.bastion`.
- **The server landed.** A re-dispatch plans zero server creates, and the gate refuses it with a pointer to #12879. Boot-verify has already powered the server off (next section). The only exit is `bastion-host-replace` (#12879).
- **The plan changes the host key in any way** (update, delete, replace). The gate refuses. A key change is the deliberate rotation below, never a side effect of a retry.

## Not-ready birth

Boot-verify runs after a green or a failed apply. It is ready only on exactly one `verdict=ready` line with exit 0. In every other case it:

- powers the server off through the Hetzner API (the disk is kept for the post-mortem);
- prints the stage that died;
- comments the run URL on #12879.

In 2a there is no in-repo exit from a powered-off bastion: the recovery is #12879's replace route. Read the trail first. If the stage points at `bastion-cloud-init.yml`, the template fix ships in a PR before the replace.

If boot-verify could not power the server off (its `::error::` line says so), the agent powers it off through the Hetzner API, using the same lookup by name and the same `poweroff` action as `scripts/lib/bastion-boot-verify.sh`. If no token is reachable, the owner uses the console. Either way, record it on #12879.

**DNS.** The baseline output chain admits DNS only to the Hetzner resolvers (185.12.64.1 and 185.12.64.2). If the host is handed other resolvers, the egress script's lookups fail and the boot dies at stage `egress_load`. The error trap flushes the ruleset before it reports, so `fresh_boot_not_ready_egress_load` reaches Sentry carrying the egress unit's last journal lines as its detail, and boot-verify powers the host off. A lookup that answers with a private or link-local address fails the same way. The fix is a `bastion-cloud-init.yml` edit, then the replace.

## Late ready

A host can report `fresh_boot_ready` after boot-verify's window closed. That changes nothing: the power-off stands, the create gate refuses a second birth, and the host leaves through the replace route (#12879). The run log's trail is the record. A fresh strict re-read needs `SENTRY_ACTIONS_RO_TOKEN`, which is a repository secret by design and is not mirrored to Doppler (ADR-031, #7946), so it runs only inside a workflow; #12879's replace job reads the trail by construction. The reader queries `statsPeriod=1h`, so an hour after the boot even a workflow re-read finds nothing.

## Lost state while Hetzner shows `soleur-bastion`

Never re-birth. A create against an empty state with a live `soleur-bastion` would make a second host with the same name, and boot-verify refuses to guess between two. Recovery is #12879's recovery arm. Until 2b merges, stop and take it to the owner.

## First-boot window

The host has no packet filter of its own until the post-settle pass enables `nftables.service`. On the kernel-update path that window covers the first boot, the settle reboot and the second boot's apt run. Two things cover it: sshd is masked from `bootcmd`, before `ssh.socket` can listen, and the zero-rule Hetzner firewall drops public inbound. From the boot after the post-settle pass, the ruleset loads before `network-pre.target`.

## Deliberate host-key rotation

The host key does not rotate on a replace (ADR-327 addendum). Rotate it only for one of these triggers:

- a suspected leak of Terraform state or of `user_data`;
- the offboarding of an operator who could read either.

The birth gate refuses any change to the key, so rotation cannot ride this route. The rotation act belongs to the replace route (#12879), which defines it; until 2b merges, a rotation trigger is an owner escalation. From step 3 on, every dialer's pin moves in the same change as the key. Record the trigger on #12879.

## Per-merge `host_creates` HALT

If the per-merge apply ever HALTs on `hcloud_server.bastion`, the remediation is this page's birth route (`apply_target=bastion-host-create`, `confirm=BIRTH-bastion`, `plan_only=true` first), never a full apply. Its gate admits only the `bastion-resources.txt` addresses. If the bastion already exists and is not ready, the recovery is `bastion-host-replace` (#12879), never a second create.

## Break-glass full apply

If the operator-local full apply is ever used, abort it if the plan creates, replaces or deletes any address in `bastion-resources.txt`, `tls_private_key.bastion_host_ssh` included. The per-merge `host_creates` HALT message carries the same clause.
