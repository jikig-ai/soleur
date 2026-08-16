# Runbook — `vector-redeliver`

Deliver a committed `vector.toml` or `journald-soleur.conf` change to the running web-1 without waiting for a clean whole-plan apply.

- **Dispatch target:** `apply-web-platform-infra.yml`, `apply_target=vector-redeliver`
- **Confirm token:** `REDELIVER-VECTOR`
- **Irreversible:** no — the delivered file is the committed one, and re-dispatching redelivers it
- **What it replaces:** `terraform_data.journald_persistent` only. Its `triggers_replace` hashes **two** files — `vector.toml` **and** `journald-soleur.conf` (`server.tf:987-990`) — so a merged change to *either* makes this arm plan a delivery, and replacing the resource is what re-runs the delivery provisioners
- **First real use:** not yet fired. Record the run id here on the first dispatch.
- **ADR:** none. The decision content lives in the gate's own header (`tests/scripts/lib/vector-redeliver-gate.sh`) — see "Architecture Decision" in the plan for why no ADR was written.

## When to fire this

Fire it when a change to `vector.toml` **or** `journald-soleur.conf` has **merged** and needs to reach the running host, and the merge-triggered push apply cannot carry it.

The push apply grades the **whole** plan at once, so a delivery that is by itself routine cannot land while unrelated pending drift sits in the same plan. That is the condition this arm exists for: it gives the delivery its own dispatch, scoped to the one address, with its own gate.

Fire it when:

- A PR touching `apps/web-platform/infra/vector.toml` or `apps/web-platform/infra/journald-soleur.conf` has merged with `[skip-web-platform-apply]`, or the push apply halted on its destroy-guard, and the new Source-4 tag / sink / transform is not yet live on web-1.
- The `vector_config_identity` sha in the deploy-status webhook (see [After it succeeds](#after-it-succeeds)) still reports the pre-merge file.

**Do NOT fire on these**, which look similar and have different remedies:

| Symptom | Meaning | What to do instead |
|---|---|---|
| Better Stack shows no rows for a NEW identifier, and the tag is not in the committed `vector.toml` | The Source-4 allow-list never gained the entry. Delivery cannot fix an entry that does not exist. | Add the `SyslogIdentifier` to `vector.toml` and merge first — Source 4 is exact-value `sd_journal_add_match`, so a missing entry is a permanently-dead no-op. |
| Better Stack shows no rows for an identifier the **inngest** host emits | `vector.toml` reaches the inngest host **only** via the OCI bootstrap image, which bakes it in and `docker cp`s it at boot. This arm's resource connects to `hcloud_server.web["web-1"]` and nothing else. | Rebuild the image (`build-inngest-bootstrap-image.yml`) and replace the inngest host (`apply_target=inngest-host-replace`, #7462). This arm cannot help. |
| `vector.service` is down / the agent is failing | A delivery restarts the agent, but the arm asserts the restart succeeded — it is a delivery path, not a repair path. | Read `services.vector` and `services.vector_journal_tail` from the deploy-status webhook first; fix the cause. |
| A **whole**-infra change is pending, not just `vector.toml` | This arm's gate refuses every address except `terraform_data.journald_persistent`. | Use the push apply, or `apply_target=manual-rerun`. |

## Preconditions

1. **The change must be merged to `main`.** `environment: web-platform-infra-apply` binds this job to a `main`-only deployment branch policy, and `workflow_dispatch` runs the **selected ref's** workflow *and its scripts* — including the gate. Dispatching from a branch is refused by the environment, which is the point: the reviewer prompt shows a branch name, not a diff.

   > **The pin is live — measured, not assumed.** As of 2026-08-16 the environment carries both protection rules and exactly one deployment branch policy, `main`:
   >
   > ```bash
   > gh api repos/jikig-ai/soleur/environments/web-platform-infra-apply --jq '[.protection_rules[].type]'
   > # ["required_reviewers","branch_policy"]
   > gh api repos/jikig-ai/soleur/environments/web-platform-infra-apply/deployment-branch-policies --jq '[.branch_policies[].name]'
   > # ["main"]
   > ```
   >
   > `github_repository_environment_deployment_policy.web_platform_infra_apply_main` does still appear as a pending CREATE in the push plan, but that is a **state** fact, not a **liveness** one: the policy exists at GitHub and Terraform has not yet adopted it. The two are easy to conflate and the difference is the whole F7 protection — read the API, never the plan, when the question is "is the pin protecting me right now".

2. **No other web-1 mutation in flight.** This job takes the `web-1-swap` mutex, so GitHub will queue it — but a queued job holds the mutex for its whole run, and this one also holds an SSH bridge. Check:

   ```bash
   for wf in workspaces-luks-cutover.yml workspaces-luks-verify.yml git-data-cutover.yml \
             apply-deploy-pipeline-fix.yml apply-web-platform-infra.yml web-platform-release.yml; do
     echo "$wf: $(gh run list --workflow=$wf --status in_progress -L 5 --json databaseId --jq 'length')"
   done
   ```

3. **Approve or cancel — never leave a dispatch pending.** This job needs a deployment approval (`environment: web-platform-infra-apply`), and a run held in `waiting` **already holds the `web-1-swap` mutex**. `timeout-minutes` does not bound that: it starts when the job begins executing, and a pending approval survives for up to 30 days. An abandoned dispatch therefore blocks `ci-ssh-token-replace` — the arm deliberately built with no approval gate so credential recovery is never behind a click — as well as the LUKS cutover arms. If you are not going to complete a dispatch, cancel the run.

4. **The CF Access `ci_ssh` credential must be live.** The bridge asserts this itself and fails with a named reason (`ci_ssh_access_denied`) before anything is planned, so you do not need to pre-check it — but if it is dead, the remedy is `apply_target=ci-ssh-token-replace` first (see [ci-ssh-token-replace.md](ci-ssh-token-replace.md)).

## Fire it

```bash
gh workflow run apply-web-platform-infra.yml \
  -f apply_target=vector-redeliver \
  -f confirm=REDELIVER-VECTOR \
  -f reason="deliver <what changed> from <PR #> — push apply wedged/skipped"
```

All three inputs are required. `reason` is the audit trail and is echoed to the step summary.

## What it does, and what protects each step

| Step | Protection |
|---|---|
| Typo-guard | `confirm` must be exactly `REDELIVER-VECTOR` — deliberately distinct from every other target's token, so a string typed for a host birth or a credential destroy cannot fire a delivery. It is **not** the authorization: the menu-ack dispatch is (`hr-menu-option-ack-not-prod-write-auth`) |
| `environment: web-platform-infra-apply` | A **main-branch pin**, not merely a reviewer click. Without it, anyone who can dispatch could point the run at a branch carrying a neutered gate — and this job runs root `remote-exec` on web-1 |
| CF Tunnel SSH bridge | Runs **before** the plan, deliberately: it exports `TF_VAR_ci_ssh_private_key`, and a plan built before it bakes `agent = true` on an agent-less runner. It also asserts CF Access still admits the `ci_ssh` token, so a dead credential stops the run before anything is planned |
| `terraform plan -out=tfplan` | One `-target`, no `-replace`. The `vector.toml` hash in `triggers_replace` is what makes this a replace; a `-replace` flag would force a needless production restart even when the config had not changed |
| **Plan gate** | Reads the **saved plan**, not the `-target` flags — `-target` is transitive and is a request, not a bound (the real closure is ~9 addresses). Four counters; refuses anything that is not exactly one delivery. See [If the gate refuses](#if-the-gate-refuses) |
| `terraform apply tfplan` | Consumes the **saved plan the gate graded**, so no resource can enter the apply that was absent from the graded document. Runs only on the gate's `pass` outcome |
| Post-restart assertions | The provisioner itself greps the delivered `/etc/vector/vector.toml` for the expected Source-4 tags and asserts `vector.service` is active — so "the apply went green" cannot be true while the file did not land or the agent did not come back |
| `if: always()` teardown | Deletes the NAT rule, kills `cloudflared`, and prints the last 200 lines of `/tmp/cloudflared.log` — the evidence the L3 triage below runs on |

## If the gate refuses

On every branch that reaches the counters, the gate prints one counter line before its verdict:

```
vector_out_of_scope_changes=<n> host_destroyed=<n> journald_entries=<n> journald_noop=<n> journald_family=<n> journald_delivered=<n>
```

Nothing has been applied when it refuses. Find your row — the two SUCCESS shapes are listed first, because neither is a failure and both are green runs:

| Verdict / counter | What it means | What to do |
|---|---|---|
| **`PASS`** — `journald_entries = 1`, `journald_delivered = 1` | Exactly one delivery, nothing else changed. The apply runs. | Nothing. Verify off-host afterwards. |
| **`NO-OP`** — `journald_entries = 1`, `journald_noop = 1` | **Success, not a refusal.** The address is in the plan as a `no-op`, so the committed files are **already on the host**. This is what a re-dispatch looks like after a delivery has landed, and it is the *ordinary* second-dispatch outcome — terraform emits `["no-op"]` rows for targeted-but-unchanged resources. No apply runs. | Nothing. If you expected a delivery, the change you are chasing is not in the committed `vector.toml` / `journald-soleur.conf` — check the merge landed. |
| **`NO-OP`** — `journald_entries = 0`, `journald_family = 0` | The address is **absent from the plan entirely**. Benign only if you expected it. | If a delivery was expected, this is the alarming one: the resource is neither at the allow-set address nor at an indexed form of it. Check it still exists in `server.tf` and in state. |
| `ABORT` — `journald_entries = 0`, `journald_family ≥ 1` | **The allow-set is STALE.** The resource is in the plan but has moved off the exact address — almost certainly under `for_each`/`count`, so its address is now `terraform_data.journald_persistent["…"]`. | The arm delivers **nothing** until the allow-set in `tests/scripts/lib/vector-redeliver-gate.sh` is updated to the indexed address. This is a code fix, not a dispatch you can retry. |
| `ABORT` — `host_destroyed ≥ 1` | The plan would DELETE an `hcloud_server` or an `hcloud_volume`. web-1 and the sole-copy workspaces volumes are in this closure. | **Stop.** Do not retry, do not ack anything. A delivery must never remove them — this is a state or provider anomaly, not a dispatch you can force through. Open an incident and read the plan output in the step log. |
| `ABORT` — `vector_out_of_scope_changes ≥ 1` | Something else in the ~9-address target closure carries a pending change (both `hcloud_server.web` entries, `hcloud_ssh_key.default`, `hcloud_placement_group.web_spread`, the CF tunnel + `random_id.tunnel_secret`, `doppler_service_token.web_probes`, `hcloud_volume.workspaces[*]`, `tls_private_key.ci_ssh`). This arm may only deliver one address. | **This is the terminal one — read the break-glass below.** Clearing the drift normally needs the push apply. |
| `ABORT` — address present, neither a delivery nor a no-op | Covers every remaining shape at the allowed address: a lone `delete`/`forget`, an update-in-place, **or** duplicate entries (`journald_entries ≥ 2` in any combination with `journald_delivered`). | **Stop.** Do not re-dispatch. Read the plan in the step log: a lone delete means something wants the resource *gone*, and duplicates mean state corruption. Neither is fixed by firing again. |

**If no counter line was printed at all**, the fail-closed preamble refused before the counters ran. That is a **tooling** fault that reads like an infra fault. The message is one of:

- `ABORT — no plan JSON path supplied`
- `ABORT — plan JSON not found: <path>`
- `ABORT — jq filter failed on <path>`
- `ABORT — unclassifiable plan entry: <addr>`
- `ABORT — counter parse failed (<name=value>)`
- `vector_redeliver_gate: jq evaluation failed on <path>`

Re-dispatch **once**. If it repeats, the gate or `terraform show -json` is broken — fix that, do not work around it. Nothing was applied either time.

### Break-glass for the terminal case

`vector_out_of_scope_changes ≥ 1` from pending closure drift is **circular**: clearing that drift needs the push apply, and the push apply is exactly what was unavailable when you reached for this arm. Left alone, `vector.toml` becomes undeliverable by any route — the condition this arm exists to end.

Do **not** widen the allow-set and do **not** add an ack trailer to a merge commit. The named break-glass is the operator-local untargeted apply under the `OPERATOR_APPLIED_EXCLUSIONS` contract (ADR-096), which does **not** go through the wedged CI path.

> Do not go looking for that pointer in this arm's own step log — it is not there. The `OPERATOR_APPLIED_EXCLUSIONS` / ADR-096 remediation text lives in the **push-apply** preflight halt (`apply-web-platform-infra.yml:660`, `:667`), a different job. This arm's refusal prints only the gate's own message and a pointer back to this runbook, which is why the route is written out here:

```bash
cd apps/web-platform/infra && \
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan
```

Read that plan first and identify the out-of-scope address. Clear it through the route that owns it (a dedicated dispatch arm if one exists for that resource, otherwise the operator-local apply), then re-dispatch this arm — the plan is a single delivery again.

## If it fails

Triage in **L3 → L7 order** (`hr-ssh-diagnosis-verify-firewall`). The inverted order — opening with an sshd or fail2ban hypothesis — is the #2654→#2681 mistake this ordering exists to prevent.

1. **L3 — credential.** Did the bridge fail with `ci_ssh_access_denied`? Then CF Access is rejecting the `ci_ssh` service token and the remedy is `apply_target=ci-ssh-token-replace` ([runbook](ci-ssh-token-replace.md)) — not anything on this host. `ci_ssh_liveness_unverifiable` / `ci_ssh_liveness_unavailable` mean **nothing was measured**; re-run the drift detector, do not re-mint.
2. **L3 — firewall.** Applies to the operator-local apply path only, **not** to this CI arm — CI reaches web-1 through the tunnel, not through `var.admin_ips`. If you are seeing `connection reset by peer` from a **local** terraform run, that is admin-IP drift (`/soleur:admin-ip-refresh`, [admin-ip-drift.md](admin-ip-drift.md)), not an sshd fault.
3. **L3 — tunnel / routing.** Read the teardown step's `=== /tmp/cloudflared.log (last 200 lines) ===` block. An unhealthy tunnel or a mismatched pinned binary shows here. The version and SHA-256 are pinned in the workflow env (`CLOUDFLARED_VERSION` / `CLOUDFLARED_SHA256`).
4. **L7 — service.** Only after all three L3 checks are verified green. sshd config drift or a fail2ban ban on the runner's tunnel-side address. The no-SSH read that actually tests *this* hypothesis is a Better Stack query on the `sshd` identifier — it is in Source 4's allow-list precisely so `Accepted publickey` / `Failed publickey` are answerable off-box:

   ```bash
   doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep sshd
   ```

   Do **not** reach for `services.vector_journal_tail` here: that field is the *vector* unit's own journal tail (`cat-deploy-state.sh:669`) and reports nothing about sshd or fail2ban.

**Failure at the plan step** — nothing was applied. Read the `::error::terraform plan (vector-redeliver) failed` annotation.

**Failure at the apply step** — the delivery is partial. The provisioner's own assertions are ordered so the render is validated *before* the live agent is touched (`test -s`, no unsubstituted `@@HOST_NAME@@`, sink present) — so a failure at those lines means the running agent was never disturbed. A failure at or after `systemctl restart vector.service` means the agent may be down: read `services.vector` from the deploy-status webhook immediately, and re-dispatch once the cause is fixed. Re-dispatching is safe — the arm is idempotent and delivers the committed file.

## After it succeeds

Verify **off-host**. No SSH (`hr-no-ssh-fallback-in-runbooks`).

1. **The apply asserted it already.** The provisioner greps the delivered `/etc/vector/vector.toml` for its expected Source-4 tags and asserts `vector.service` is active, so a green run is already evidence the file landed and the agent came back. The checks below are the independent confirmation.

2. **Deploy-status webhook** — single authenticated GET, no SSH. This is one tunnel with **multiple connector replicas** and Cloudflare load-balances across them (`tunnel.tf:32`, `:79`), so the connector that answers is not pinned — but the `deploy.` ingress rule's *service* is origin-relative and pinned to `var.web_hosts["web-1"].private_ip:9000` (`tunnel.tf:53-54`, #6594). Whichever replica answers therefore proxies to web-1:

   ```bash
   WS=$(doppler secrets get WEBHOOK_DEPLOY_SECRET -p soleur -c prd_terraform --plain)
   CID=$(doppler secrets get CF_ACCESS_CLIENT_ID -p soleur -c prd_terraform --plain)
   CSEC=$(doppler secrets get CF_ACCESS_CLIENT_SECRET -p soleur -c prd_terraform --plain)
   HMAC=$(printf '' | openssl dgst -sha256 -hmac "$WS" | sed 's/.*= //')
   curl -fsS -H "X-Signature-256: sha256=${HMAC}" \
     -H "CF-Access-Client-Id: ${CID}" -H "CF-Access-Client-Secret: ${CSEC}" \
     "https://deploy.soleur.ai/hooks/deploy-status" \
     | jq '{journald_storage, vector: .services.vector, vector_config_identity: .services.vector_config_identity, vector_journal_tail: .services.vector_journal_tail}'
   ```

   Expect:
   - `journald_storage.persistent == true` — the journald half of the resource is still in effect;
   - `services.vector` active, and `services.vector_journal_tail` **non-empty** — the agent restarted and is talking;
   - `services.vector_config_identity` — the identity of the **live** `/etc/vector/vector.toml`, in the form `redis_allowlisted=<yes|no> sha256=<hash> mtime=<epoch>` (`cat-deploy-state.sh:618`).

     **Compare it against the sha the committed file renders to, not against its own previous value.** Render the same substitution the delivery performs and hash it:

     ```bash
     sed 's|@@HOST_NAME@@|soleur-web-platform|g' apps/web-platform/infra/vector.toml | sha256sum
     ```

     `live == rendered` is the success condition, and it is the *only* form that works on every dispatch. A before-vs-after diff proves something changed; it does not prove the *right* content is there, and it **inverts on a NO-OP** — when the host already has the committed file the gate returns NO-OP (a success) and the sha correctly does **not** move, which a "changed sha proves delivery" rule reads as failure. Capturing the before value is still worth doing, but as a supporting datum, not the verdict.
     The literal string **`absent`** (`:620`) means the file is not there at all — that is not a stale delivery, it is a broken agent config, and it is the one value that should stop you rather than prompt a re-dispatch.

   > The live sha will **not** equal a bare `sha256sum apps/web-platform/infra/vector.toml` — the delivery substitutes `@@HOST_NAME@@` for the host's Better Stack name, so the repo file as-committed is never what lands. That is why the check above pipes the file through the same `sed` first. Hashing the raw repo file and finding a mismatch proves nothing.

3. **Positive control on the sink.** A new identifier producing no rows is ambiguous — the agent may be dark. Assert first that the channel carries *anything*, then ask about your identifier.

   **Use an unfiltered short window as the liveness probe**, not a `--grep` on a named identifier:

   ```bash
   doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 15m --limit 3
   ```

   `app_container` rows flow continuously from web-1, so a live sink answers this in seconds with `"host_name":"soleur-web-platform"`. No `--table` is needed: web-1's sink posts to `https://s2457081.eu-fsn-3.betterstackdata.com/` (`vector.toml`, `[sinks.betterstack]`) and source **2457081** is the same source that backs the script's default table — the mapping is recorded at [betterstack-log-query.md](betterstack-log-query.md) under *Connection details* (`t<TEAM_ID>_<table_name>_logs` → `t520508_soleur_inngest_vector_prd_3_logs`). Every host multiplexes into that one source.

   > **Do NOT use `--grep ci-deploy --since 1h` as the liveness probe.** `ci-deploy` and `sshd` are **event-driven**, not continuous: measured 2026-08-16, `ci-deploy` returned 0 rows over 24h and rows over 72h. A quiet hour produces zero rows on a perfectly healthy sink — the exact ambiguity this step exists to remove. Reach for `--grep ci-deploy` only with `--since 72h`, and note the source's retention is **3 days**, so a longer window buys nothing.

   Once the unfiltered probe returns rows, "no rows for the new identifier" is evidence about the identifier.

   **A zero-row unfiltered result IS meaningful — it means the channel is dark.** Do not explain it away. Measured 2026-08-16: rows were absent across hot *and* archive for the whole preceding day, then began abruptly at 20:43:26Z; the same host reported `vector: active` with a non-empty journal tail throughout, so the unit being up proves nothing about the sink. A dark channel is a real finding — see #7569 for a concurrent instance on a different channel.

   The delivery itself does not depend on any of this: the rendered-sha comparison in step 2 reads the webhook's own response body and needs no log channel at all. A dark sink is worth an incident; it is not a reason to doubt a sha that matches.

## Known residual

- **A successful dispatch un-wedges the push apply.** The journald replace is currently the only destroy in the pending plan, so once this arm applies it the push guard's `destroy_count` drops to 0 and **the next merge touching a `paths:`-matching file applies the four pending creates plus the `cloudflare_bot_management` update unattended**, by whoever merges it. Those resources belong to #7462 / PR #7516 / #7539. Check what is pending before dispatching, and know that this is the release path for them unless one of those PRs lands first.

- **A dated future brick.** This arm is clean today only because `hcloud_server.web` carries `lifecycle { ignore_changes = [user_data, ssh_keys, image, placement_group_id] }`, which `server.tf` documents as a temporary GA deferral ("REMOVE this entry in the GA maintenance-window PR as its FIRST diff"). When `placement_group_id` leaves that list, web-1 plans a pending in-place update on every dispatch, `vector_out_of_scope_changes` reads ≥ 1 forever, and this arm refuses permanently — a gate that always fails is an outage, not a tripwire. Revisit the allow-set in the same PR that removes the lifecycle entry.

- **`hcloud_ssh_key.default` is inside the closure.** It stays a no-op only via its own `lifecycle { ignore_changes = [public_key] }`. The job generates a throwaway keypair to satisfy HCL's `file()` parsing; if that lifecycle block is ever removed, the throwaway key becomes a real diff and the gate refuses every dispatch.

- **This arm does not reach the inngest host.** `terraform_data.journald_persistent` connects to `hcloud_server.web["web-1"]` only. The inngest host receives `vector.toml` exclusively through the OCI bootstrap image. Verifying `inngest-boot-phone-home` / `inngest-bs-token-restage` belongs to `apply_target=inngest-host-replace` under #7462, not here.
