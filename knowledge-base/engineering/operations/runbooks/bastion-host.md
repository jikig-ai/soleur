# Runbook — the dedicated bastion (`soleur-bastion`)

ADR-327 steps 2a (#12866) and 2b (#12879). The design and its residuals are in the ADR-327 addenda of
2026-11-18 and 2026-11-28; this page holds only the acts.

- **Birth route:** `apply-web-platform-infra.yml`, `apply_target=bastion-host-create`, `confirm=BIRTH-bastion`.
- **Replace route:** `apply-web-platform-infra.yml`, `apply_target=bastion-host-replace`, `confirm=REPLACE-bastion`, `expected_bastion_server_id=<the live id>` (or `none` to recover a lost server). See "Replacing the bastion".
- **Approval:** the `web-platform-infra-apply` environment reviewer. The `confirm` token is a typo-guard only.
- **Resource list:** `tests/scripts/lib/bastion-resources.txt`. The job `-target`s exactly this list, and the birth gate admits nothing else.
- **Cost:** EUR 5.99 per month (cx23 plus its primary IPv4). The owner's go on the real birth accepts it.
- **State in 2a:** declared, not born. The host exists only after a `bastion-host-create` run reports ready.
- **Once born:** no role. sshd is masked and nothing dials it. Egress is DNS to the Hetzner resolvers, DHCP requests for `systemd-network`, NTP for `systemd-timesync`, the metadata endpoint for root, and tcp/443 to the apt mirrors and Sentry ingest for root and `_apt`. Nothing else leaves the host, and no private address is reachable. The sshd drop-in (for step 3) refuses root login and every forwarding but TCP. It has no heartbeat until #13113.

## Birth

The agent runs both dispatches below. Each needs the owner's typed go naming the exact command.

**Pre-birth boot evidence.** `apps/web-platform/infra/bastion-runcmd-rehearsal.test.sh` boots the rendered template under real cloud-init in the pinned `ubuntu:24.04` image. CI runs it as the `bastion-boot-rehearsal` job of `infra-validation.yml`; locally, `bash apps/web-platform/infra/bastion-runcmd-rehearsal.test.sh` (needs Docker with `--privileged`, and terraform). The job is advisory on pull requests, so a red run can merge. #12942 will run the rehearsal inside the birth run and refuse the birth unless it succeeds; the suite exits 1 on a SKIP for `workflow_dispatch` (CTO Q28), so that job's `success` is enough there. Until it lands, the agent runs this check after the rehearsal (step 1 below) and before the real birth:

- Dispatch the workflow on main: `gh workflow run infra-validation.yml --ref main`. Arm a watch on the run (hr-dispatch-async-must-arm-watch).
- Pick the `workflow_dispatch` run created after the dispatch whose `headSha` equals the commit the plan_only run reports: `gh run list --workflow infra-validation.yml --event workflow_dispatch --branch main --json databaseId,headSha,createdAt`.
- Require `gh run view <id> --json jobs --jq '.jobs[]|select(.name=="bastion-boot-rehearsal")|.conclusion'` to print exactly `success`. Read this job's conclusion, never the run's or `deploy-script-tests-done`'s: other legs of the run can fail for unrelated reasons.
- Read the job id with `gh run view <id> --json jobs --jq '.jobs[]|select(.name=="bastion-boot-rehearsal")|.databaseId'`. Require `gh run view --job <job-id> --log | grep -cF 'bastion-runcmd-rehearsal: PASS ('` to print exactly `1`. A `SKIP (` or `PARTIAL (` verdict is not birth evidence: dispatch again (CTO Q7, Q28).
- On any other result, diagnose from the evidence the run already holds before dispatching again: `gh run view <id> --log-failed | grep -E 'FAIL: |SKIP \(loud\)|BRH_|bastion-runcmd-rehearsal: |HARNESS: |FATAL: |INSTRUMENT: |unbound variable'` names the failed rows, their stage and the token (or the harness fault); if it prints nothing, read the last 40 lines of `gh run view --job <job-id> --log`. `gh run download <id> -n bastion-boot-rehearsal-workdir` fetches the kept work dir (journals, cloud-init-output logs, stub captures).
- Do not substitute an existing check-run. Push runs are paths-filtered and duplicate-skipped, so the birth commit usually has none, and the suite installs from the live archive, so only a birth-day run speaks for birth day.
- If main moves before the real birth run, dispatch again.

This dispatch writes nothing, so it needs no owner go (unlike the two birth dispatches below).

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
- **The server landed.** A re-dispatch plans zero server creates, and the gate refuses it with a pointer to the replace route. Boot-verify has already powered the server off (next section). The only exit is `bastion-host-replace` with `-f expected_bastion_server_id=<that server's id>` (see "Replacing the bastion").
- **The plan changes the host key in any way** (update, delete, replace). The gate refuses. A key change is the deliberate rotation below, never a side effect of a retry.

## Not-ready birth

Boot-verify runs after a green or a failed apply. It is ready only on exactly one `verdict=ready` line with exit 0. In every other case it:

- powers the server off through the Hetzner API (the disk is kept for the post-mortem);
- prints the stage that died;
- comments the run URL on #9421 (the summary says whether the comment posted).

It never powers off a server that existed before the apply (the pre-apply id set). If the only `soleur-bastion` is such a server, the summary says it was left untouched.

The exit from a powered-off bastion is the replace route. Read the trail first. If the stage points at `bastion-cloud-init.yml`, the template fix ships in a PR before the replace. Boot-verify's own recovery line prints the exact `bastion-host-replace` dispatch with the server's id.

If boot-verify could not power the server off (its `::error::` line says so), the agent powers it off through the Hetzner API, using the same lookup by name and the same `poweroff` action as `scripts/lib/bastion-boot-verify.sh`. If no token is reachable, the owner uses the console. Either way, record it on #9421.

**DNS.** The baseline output chain admits DNS only to the Hetzner resolvers (185.12.64.1 and 185.12.64.2). If the host is handed other resolvers, the egress script's lookups fail and the boot dies at stage `egress_load`. The error trap flushes the ruleset before it reports, so `fresh_boot_not_ready_egress_load` reaches Sentry carrying the failing reason line as its `detail` tag (the `[bastion-egress] FAIL:` line or a line containing nft's `: Error:`, or `why=no_reason_line nft=<Result> egress=<Result> st=<status> last=<line>` when there is none, with `unread` for a read that timed out), and boot-verify powers the host off. A lookup that answers with a private or link-local address fails the same way. The fix is a `bastion-cloud-init.yml` edit, then the replace.

## Late ready

A host can report `fresh_boot_ready` after boot-verify's window closed. That changes nothing: the power-off stands, the create gate refuses a second birth, and the host leaves through the replace route (`bastion-host-replace`). The run log's trail is the record. A fresh strict re-read needs `SENTRY_ACTIONS_RO_TOKEN`, which is a repository secret by design and is not mirrored to Doppler (ADR-031, #7946), so it runs only inside a workflow; the replace job reads the trail by construction, since its verify step runs the same strict reader. The reader queries `statsPeriod=1h`, so an hour after the boot even a workflow re-read finds nothing.

## Lost state while Hetzner shows `soleur-bastion`

Never re-birth. A create against an empty state with a live `soleur-bastion` would make a second host with the same name, and boot-verify refuses to guess between two.

The replace route **refuses** this case too. Its gate aborts with `LOST STATE: pin none but the Hetzner project still holds <n> soleur-bastion server(s) (ids <ids>). This route refuses lost state while a server is live: that is #13117, which depends on #13116 (losing state loses the host key). Do not use the birth route either.` Lost state loses the host key, so a recovery would also be a key rotation. Stop and take it to the owner; the in-repo route is #13117.

The recovery arm (`expected_bastion_server_id=none`) is for the opposite case: state and Hetzner both hold no bastion.

## Replacing the bastion

The replace destroys `soleur-bastion` and creates it again from the same template. The host key and the private IP (10.0.1.70) are kept. The agent runs both dispatches. Each needs the owner's typed go naming the exact command. The same "dispatch only when the owner can approve at once" rule as the birth applies.

1. **Rehearsal.**
   `gh workflow run apply-web-platform-infra.yml -f apply_target=bastion-host-replace -f confirm=REPLACE-bastion -f expected_bastion_server_id=<id> -f plan_only=true -f reason="bastion replace rehearsal (#12879)"`.
   - It runs the readiness interlock, the Hetzner read, the plan, the replace gate and the stock gate, then stops.
   - Its summary lists every `soleur-bastion` id the API reports, the commit SHA and every planned address with its action.
   - If the id is not known yet, dispatch the rehearsal with any well-formed id: the gate aborts with `IDENTITY MISMATCH: pin=... api_ids=<the live id> ...`, and the summary lists the live id. Nothing is destroyed.
   - Where reading `HCLOUD_TOKEN` is permitted, the read-only Hetzner `servers?name=` recipe in `git-data-luks-cutover-5274.md` (with `name=soleur-bastion`) gives the same id.
   - A born bastion's own birth summary also prints its server id.
2. **Find and watch the run.**
   `gh run list --workflow apply-web-platform-infra.yml --event workflow_dispatch -L1 --json databaseId,url`, then `gh run watch <id>`. Arm the watch (hr-dispatch-async-must-arm-watch). A status of "waiting" means the run is waiting for the `web-platform-infra-apply` environment reviewer, not that it is stuck.
3. **Real replace.**
   After the owner has read the rehearsal's list, run the same command with `-f plan_only=false`, quoting the rehearsal run ID in `reason`.
   - The TOCTOU step re-reads the API just before the apply. If the server's id, role label or status changed since the plan, it aborts and nothing is applied.
   - A green run means the gated plan applied and the new server reported `fresh_boot_ready` after the run's anchor. The summary prints the new server id, the host key fingerprint and the private IP.

Every refusal before the apply ends `NOTHING HAS BEEN DESTROYED — this gate runs before the apply.` followed by the next action.

## Recovering a failed replace

After a failure, the run summary prints a `next dispatch` line. It is computed from a fresh API read and `terraform state list`, never guessed. Copy it when it carries a command; it is always a `plan_only=true` rehearsal first.

- **The apply failed before the destroy.** The pre-apply server is still the live one. The next dispatch is the same pin. Boot-verify leaves that server untouched (`old_untouched`).
- **The destroy landed, the create did not.** The API shows no `soleur-bastion`. The next dispatch is the recovery arm, `expected_bastion_server_id=none`. Its gate admits a bare create only when the API lists zero servers and the state no longer holds the server.
- **The new server landed but was not ready.** Boot-verify powered it off (disk kept) and commented on #9421. Read the trail. If the stage points at `bastion-cloud-init.yml`, ship the template fix in a PR first. Then the next dispatch pins the new server's id. That replace destroys the kept disk.
- **State holds the server but the API shows none.** The summary says `none applies` and prints no command. Stop and take it to the owner.
- **Two or more `soleur-bastion` servers exist.** Every route refuses to guess. Stop and inspect the Hetzner project with the owner.
- **Cancelled mid-run.** If the apply was reached and verify did not pass, the cancel step powers off the replacement, never a pre-apply server. Read the summary's power-off line before any re-dispatch.
- **Lost state with a live server, or a key rotation.** Both are refused: #13117 and #13116 (see the sections above).

## First-boot window

The host has no packet filter of its own until the post-settle pass enables `nftables.service`. On the kernel-update path that window covers the first boot, the settle reboot and the second boot's apt run. Two things cover it: sshd is masked from `bootcmd`, before `ssh.socket` can listen, and the zero-rule Hetzner firewall drops public inbound. From the boot after the post-settle pass, the ruleset loads before `network-pre.target`.

## Deliberate host-key rotation

The host key does not rotate on a replace (ADR-327 addendum). Rotate it only for one of these triggers:

- a suspected leak of Terraform state or of `user_data`;
- the offboarding of an operator who could read either.

Both routes refuse any change to the key: the birth gate, and the replace gate, which requires `tls_private_key.bastion_host_ssh` to be exactly `no-op`. Rotation cannot ride either route. It lives at #13116; until that lands, a rotation trigger is an owner escalation. From step 3 on, every dialer's pin moves in the same change as the key. Record the trigger on #13116.

## Per-merge `host_creates` HALT

If the per-merge apply ever HALTs on `hcloud_server.bastion`, the remediation is this page's birth route (`apply_target=bastion-host-create`, `confirm=BIRTH-bastion`, `plan_only=true` first), never a full apply. Its gate admits only the `bastion-resources.txt` addresses. If the bastion already exists and is not ready, the recovery is `bastion-host-replace`, never a second create.

## Break-glass full apply

If the operator-local full apply is ever used, abort it if the plan creates, replaces or deletes any address in `bastion-resources.txt`, `tls_private_key.bastion_host_ssh` included. The per-merge `host_creates` HALT message carries the same clause.
