# Runbook — the dedicated bastion (`soleur-bastion`)

ADR-327 step 2a (#12866). The design and its residuals are in the ADR-327 addendum of 2026-11-18;
this page holds only the acts.

- **Birth route:** `apply-web-platform-infra.yml`, `apply_target=bastion-host-create`, `confirm=BIRTH-bastion`.
- **Replace route:** `bastion-host-replace`, which is #12879 (step 2b) and does not exist yet.
- **Approval:** the `web-platform-infra-apply` environment reviewer. The `confirm` token is a typo-guard only.
- **Resource list:** `tests/scripts/lib/bastion-resources.txt`. The job `-target`s exactly this list, and the birth gate admits nothing else.
- **Cost:** EUR 5.99 per month (cx23 plus its primary IPv4). The owner's go on the real birth accepts it.
- **State in 2a:** born, no role. sshd is masked and nothing dials it. Egress is limited to the apt mirrors and Sentry ingest, and it has no heartbeat until #12879.

## Birth

The agent runs both dispatches below. Each needs the owner's typed go naming the exact command.

1. **Rehearsal.**
   `gh workflow run apply-web-platform-infra.yml -f apply_target=bastion-host-create -f confirm=BIRTH-bastion -f plan_only=true -f reason="bastion birth rehearsal (#12866)"`.
   It runs the readiness interlock, the DSN assert, the plan, the birth gate and the stock gate, then stops.
   Its run summary lists the commit SHA and every planned address with its action. The agent posts the run ID, the SHA and the list on #12866.
2. **Real birth.**
   After the owner has read that list, run the same command with `-f plan_only=false`, quoting the rehearsal run ID in `reason`.
   - A green run means two things: the gated plan applied, and `soleur-bastion` reported `fresh_boot_ready` after the run's anchor.
   - The summary prints the host key fingerprint and the private IP (10.0.1.70). #12880 pins them.

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

**DNS.** The baseline output chain admits DNS only to the Hetzner resolvers (185.12.64.1 and 185.12.64.2). If the host is handed other resolvers, the egress script's lookups fail, the boot dies at `fresh_boot_not_ready_egress_load`, and boot-verify powers the host off. The fix is a `bastion-cloud-init.yml` edit, then the replace.

## Late ready

A host can report `fresh_boot_ready` after boot-verify's window closed. Do not dispatch the create again: the gate refuses it. The agent re-reads the trail locally, read-only, without SSH:

```bash
SENTRY_ACTIONS_RO_TOKEN="$(doppler secrets get SENTRY_API_TOKEN -p soleur -c prd --plain)" \
BOOT_TRAIL_STRICT=1 BOOT_TRAIL_HOST_NAME=soleur-bastion BOOT_TRAIL_SINCE=<the run's boot-trail anchor epoch> \
JOB_STATUS=success DISPATCH_LABEL=bastion-host-create \
  bash apps/web-platform/infra/scripts/fresh-host-boot-trail.sh
```

The anchor epoch is printed in the run's "Stamp boot-trail run anchor" step. A late `verdict=ready` does not undo the power-off: the host still leaves through the replace route.

## Lost state while Hetzner shows `soleur-bastion`

Never re-birth. A create against an empty state with a live `soleur-bastion` would make a second host with the same name, and boot-verify refuses to guess between two. Recovery is #12879's recovery arm. Until 2b merges, stop and take it to the owner.

## First-boot window

The baseline nftables ruleset loads only after apt installs `nftables`. Until then the host has no packet filter of its own. Two things cover that window: sshd is masked from `bootcmd`, so nothing listens, and the zero-rule Hetzner firewall drops public inbound. After the settle reboot, the ruleset loads on every boot before `network-pre.target`.

## Deliberate host-key rotation

The host key does not rotate on a replace (ADR-327 addendum). Rotate it only for one of these triggers:

- a suspected leak of Terraform state or of `user_data`;
- the offboarding of an operator who could read either.

The birth gate refuses any change to the key, so rotation cannot ride this route. The rotation act belongs to the replace route (#12879), which defines it; until 2b merges, a rotation trigger is an owner escalation. From step 3 on, every dialer's pin moves in the same change as the key. Record the trigger on #12879.

## Break-glass full apply

If the operator-local full apply is ever used, abort it if the plan creates, replaces or deletes any address in `bastion-resources.txt`, `tls_private_key.bastion_host_ssh` included. The per-merge `host_creates` HALT message carries the same clause.
