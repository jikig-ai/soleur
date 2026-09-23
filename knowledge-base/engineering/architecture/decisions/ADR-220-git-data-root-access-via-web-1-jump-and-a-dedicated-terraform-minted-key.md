---
title: "ADR-220: git-data root access goes through a web-1 jump and uses a dedicated Terraform-minted key"
status: proposed
date: 2026-09-15
issue: 6680
supersedes: []
amends:
  - ADR-068
  - ADR-149
tags: [git-data, ssh, cloudflare-tunnel, credentials, luks, cutover, security]
---

# ADR-220: git-data root access goes through a web-1 jump and uses a dedicated Terraform-minted key

## Status

`proposed` in frontmatter, because the frontmatter holds one value and the decisions below do not
share one. Each decision's own status is in **D5**. Implements the decision half of #6680; the
credential is provisioned by **#8189**. #6680 stays open until #8189's dry-run reads
`role=git-data-auth verdict=ok`.

> **Superseded 2026-09-15 (#8189), as to which dry run closes #6680:** merging #8189 does not satisfy
> it. #6680 stays open until the post-merge dry run of #8189's delivered key (after the root-key apply,
> the fingerprint PR and the replace) reads `role=git-data-auth verdict=ok`. What #8189 changed in
> D1b–D6 is recorded in the **Amendment log** at the end; dated text above it that the log replaces
> carries a Superseded marker like this one.

## Context

`git-data-cutover.yml` is the only automated route that moves the shared git store onto LUKS and
flips `GIT_DATA_STORE_ENABLED`. ADR-068's D10 addendum also keeps it as the **rotation** route.
It **had never run** before this PR's branch dry-run (run 34906907089), so its defects show up
one at a time. A static read found three walls on the access path:

1. **The bridge had no `server-ip`.** The workflow called `./.github/actions/cf-tunnel-ssh-bridge`
   without `server-ip`, so the bridge ran `terraform output -raw server_ip` in a job that never
   installs terraform. That is the #6649 class of failure, and it dies before any SSH.
2. **`GIT_DATA_SSH` was the web-1 invocation.** In its "Decode CI SSH private key" step the bridge
   exported `GIT_DATA_SSH` byte-for-byte equal to `WEB_HOST_SSH`: the CI key, login `root`, no
   proxy. The tunnel has exactly one SSH ingress (`ssh.` → `ssh://<web-1 private IP>:22` in
   `tunnel.tf`), so `gd_ssh 10.0.1.20` dialed an address the runner cannot route to, and the
   timeout named nothing.
3. **No CI key is authorized for root on git-data.** git-data's root login accepts keys only
   (`PermitRootLogin prohibit-password` in `cloud-init-git-data.yml`), and the only key is
   `hcloud_ssh_key.default`. We measured this with public-key fingerprints only (Hetzner
   `GET /v1/ssh_keys` plus `ssh-keygen -l -E md5`). The single Hetzner key object on the server
   matches the **operator's personal** public key. The CI key (`DEPLOY_SSH_PRIVATE_KEY`) has a
   different fingerprint. The birth route passes a throwaway `ssh_key_path`, but
   `hcloud_ssh_key.default` carries `ignore_changes = [public_key]`, so that throwaway key never
   reached Hetzner.

Wall 3 means that choosing a transport is necessary but not enough. This ADR decides both the
transport and the credential.

The same static read found older defects. They stay hidden until a key exists:

- `read_flag`/`set_flag` use a `prd_terraform`-scoped token.
- The workflow is in neither the `web-1-swap` nor the `git-data-state` concurrency group.
- A default (`dry_run=true`) ROLLBACK dispatch never released a held freeze, because
  `release_freeze` returned at its `DRY_RUN` guard.
- **The freeze and both reloads are inert.** `acquire_freeze`/`release_freeze` run
  `systemctl start|stop soleur-drain.service`, and `flip_flag_and_reload`/`rollback` run
  `systemctl restart soleur-web.service`. Neither unit exists: ADR-119 records the drain unit as
  "defined nowhere", and the app is the `soleur-web-platform` docker container, whose env is fixed
  at `docker run`.
- **A later dry-run can overwrite the live store.** After a first real cutover, the mapper is
  mounted at `/mnt/git-data`. A `dry_run=true` dispatch would mount the same mapper at `FRESH_ROOT`
  and `rsync --delete` the populated store onto itself, because `read_flag` fails open.

The third is fixed in the PR that lands this ADR. The others are blocking checklist items in #8189,
which holds the detail (reconciling the freeze and reloads with ADR-119 among them).

> **Superseded 2026-09-15 (#8189):** the flag token, the concurrency serialization and the dry-run
> self-overwrite are fixed; the inert freeze and reloads were deleted with the whole cutover body, whose
> rebuild is #8211. See the Amendment log, "Blocker dispositions".

## Considered Options

| Option | What it buys | Why it was not chosen |
|---|---|---|
| (a) A second ingress `ssh-git-data.` → `ssh://10.0.1.20:22`, with a second Access app and a second bridge redirect | An sshd for the store that the edge can address directly | Today web-1 is the only connector (#6425), so this path also goes through web-1 and gains no host independence. It also gives the store host a public SSH hostname and brings in #6441's per-hostname multiplexing. It satisfies ADR-114 I2, but the blast radius is too large. |
| `ssh -J` with the jump host on the command line | A shorter invocation | The jump hop ignores a command-line `-i` (`man ssh`), so web-1 would be dialed without the CI key |
| Jump via `127.0.0.1:2222` | Skips the NAT rule | One host would have two SSH identities for #7226 to pin. The NAT rule already matches for `server-ip` callers. |
| A git-data key on web-1, or agent forwarding | No proxy needed on the runner | Anyone with root on web-1 could reach root on the store |
| Reuse `ci_ssh` as the git-data root key | No new secret | `ci_ssh` is already used by four workflows, including a `TF_VAR` in every infra apply |
| Root key in `cloud-init-git-data.yml`, a 4th `git` forced-command key, or an SSH CA | No Hetzner key object | The template is hash-bound (it would re-hold rung-2), still needs the replace, and breaks the #8009 three-key authorization-map gate |
| Deliver the key in place (remote-exec, rescue, `reset_password` + console, `hcloud rebuild`) | No replace | Violates `hr-prod-host-config-change-immutable-redeploy`. Rescue also needs the reboot that ADR-115 bars. |
| Copy the personal Hetzner key into Doppler | Works today | It is a human mint, and that key is root on every host |
| A GitHub repo secret that holds the key | Fewer moving parts | Violates AP-008, and any workflow on any branch can name a repo secret |
| Keep the keypair in the web-platform root state | One root and the simplest Terraform | That state already holds the web-1 root key and the CF Access token, and PR-branch `terraform plan` runs can read it. Adding the key would make that state root access on the store. |
| Destroy the key after each window | The tightest possible bound | Every rotation would need a host replace first. The authorized public key and the old state versions persist anyway. |
| Born-on-LUKS (no cutover SSH at all) | Removes the need for access | Rejected by ADR-068 D10. Rotation still needs the cutover. Not reopened here. |

## Decision

### D1a — Transport: a jump through web-1's existing `ssh.` ingress

The runner reaches web-1 over the existing tunnel and NAT rule (`server-ip` = 10.0.1.10). All uses
share this one route. The runner then opens a `direct-tcpip` channel through web-1's sshd to
`10.0.1.20:22`.

- **Proof in this PR:** `$WEB_HOST_SSH -W 10.0.1.20:22 10.0.1.10 </dev/null` passes only if the
  first output line begins `SSH-2.0-`, whatever the exit code. It needs no git-data credential. It
  proves that web-1 permits `direct-tcpip` and that something answered with an `SSH-2.0-` line:
  liveness, not authenticity (#7226).
- **If web-1's sshd refuses forwarding** (`reason=forward_refused`): the fallback (a ProxyCommand
  that runs a TCP relay on web-1) needs its own amendment to this ADR.

### D1b — Authenticated hop: `ssh_config` ProxyCommand, end-to-end

The runner authenticates **end-to-end** to git-data through the D1a channel, using an `ssh_config`
`ProxyCommand ssh -F <cfg> -W %h:%p 10.0.1.10` with `IdentitiesOnly yes` and `BatchMode yes` on both
host blocks (#8189). No key and no agent socket ever lands on web-1, so a compromised web-1 cannot
replay the root login.

> **Superseded 2026-09-15 (#8189), as to `%h:%p` only:** the ProxyCommand names a literal
> `-W 10.0.1.20:22` target, never `%h`. See the Amendment log, "D1b".

### D2 — Credential: a dedicated Terraform-minted root key for git-data

- **Key resources.** `tls_private_key` (ED25519) and `hcloud_ssh_key` are appended to
  `hcloud_server.git_data`'s `ssh_keys`. The key is set at create time, outside the rung-2 hash, so
  it is not a hash-bound edit. It reaches the host only at a git-data replace, and
  `ignore_changes = [ssh_keys]` stays. The private half lives in Doppler config `prd_git_data_root`
  (AP-008). It is never stored in `prd_git_data`, which is the host's own boot config and must not
  hold a credential that logs in **to** that host. It is never stored in `prd_terraform` either.
- **Custody goal.** No silent, replayable root credential for the store may be readable from
  PR-reachable surfaces. The web-platform root state is one: PR-branch `terraform plan` runs
  (`infra-validation.yml`'s `plan` job) read it, and it already holds the web-1 root key and the CF
  Access token. So the keypair is minted in a **separate Terraform root**
  (`hr-every-new-terraform-root-must-include-an`). #8189 must deliver that root with:
  1. a dedicated R2 bucket and its own token. Both roots use `soleur-terraform-state` today, and R2
     tokens are scoped per bucket, so a separate key prefix isolates nothing;
  2. exclusion from `infra-validation.yml`'s `detect-changes`/`plan` job (or planning only in an
     environment-gated job), with a test that pins the exclusion;
  3. no `terraform_remote_state` read of it from the web-platform root.
- **Known gaps: existing root-equivalent paths this rule does not close.**
  - `hcloud_token` in `prd_terraform` allows rescue, rebuild and volume moves.
  - `doppler_service_token.git_data` sits in web-platform state and reads `prd_git_data`, which holds
    `GIT_DATA_LUKS_KEY`.
  - Root on web-1 reads the `GIT_PROVISION`/`GIT_TRANSPORT`/`GIT_REMOVE` ssh keys, which carry full
    data access.
- **Public-key hand-off.** A singular `data "hcloud_ssh_key"` fails every web-platform plan while the
  key is absent: before the new root's first apply, and mid-rotation, because key names are unique.
  #8189 uses a plural `data "hcloud_ssh_keys"` with a label selector (an absent key is an empty list,
  not an error) plus a precondition only on the git-data replace path, or a gate-enforced apply
  order.
- **Token delivery, OIDC first.**
  - **Preferred:** a Doppler OIDC identity bound to the `git-data-cutover` environment's `sub`, so no
    secret is stored.
  - **Only if the pinned provider cannot express that:** a repo-secret token with three guards:
    1. a CI lint that allows only `git-data-cutover.yml` to reference it;
    2. a `main`-only deployment policy on the environment;
    3. an expiry set at mint time.

    These guards are needed because an `environment:` gate only binds the jobs that declare it,
    while any workflow file on any branch can name a repo secret.
- **Scope.** The reviewer-gated environment covers every mode that needs the git-data credential:
  dry-run and real cutover. Otherwise a dry-run could never authenticate, and the dry-run is the
  proof. Rollback is urgent, so it is split: the flag-off write and the web reload run in an
  ungated job that holds no git-data secret, and only the freeze-sentinel removal (which needs the
  credential) runs gated. This split is the decision #8189 implements.

> **Superseded 2026-09-15 (#8189):** the config `prd_git_data_root`, the dedicated R2 bucket, the
> OIDC-first delivery, the mint-time expiry and the rollback split are each replaced or deferred. See the
> Amendment log, "D2".

### D3 — Lifetime

- **Consumer side:** the read credential exists only for a cutover window (a rehearsal, the
  cutover, or a rotation) and expires on its own.
- **Host side:** the key is revoked at the next replace.
- **Rotation:** rotation cutovers therefore **need no host replace**.
- **While a token exists:** #8009's authorization accounting and PA-36 record the root authority.

> **Superseded 2026-09-15 (#8189):** there is no window, the token does not expire, and the host-side
> key is not revoked at the next replace. See the Amendment log, "D3".

### D4 — Residuals, with their bounds

- **Unverified host keys (#7226).** Both hops accept host keys without verifying them. A compromised
  web-1 cannot log in to git-data, but it could impersonate git-data and receive cutover commands.
  We accept this only while #6976 holds, because the store is empty by construction at the initial
  cutover. Any rotation against a populated store is gated on #7226.
- **Verdicts show liveness, not authenticity.** A compromised web-1 can answer `-W` with a forged
  `SSH-2.0-` line. Once a key exists, it could also run a fake sshd that accepts any login. So
  pinning git-data's host key is a precondition for D2's `accepted` status, not only for rotating
  a populated store.
- **The path to the store.** Since #6594 the `ssh.` ingress is origin-relative, so reaching git-data
  depends on a connector with a private NIC plus web-1's sshd (ADR-114 I1), not on exactly one
  connector. Any #6441 rework must keep the jump working.
- **web-1 forwarding is unguarded.** `AllowTcpForwarding` on web-1 is a stock default that nothing
  pins. Hardening web-1's sshd could silently break the jump; it would surface at the next dispatch
  as `role=git-data-jump verdict=failed reason=forward_refused`.
- **Probe penalties on git-data.** OpenSSH ≥ 9.8 `PerSourcePenalties noauth` could penalize
  10.0.1.10 after each unauthenticated banner probe. That is the same source as production
  `GIT_TRANSPORT`/`GIT_PROVISION`. When git-data's OpenSSH is upgraded, set
  `PerSourcePenaltyExemptList 10.0.1.10`.

### D5 — Statuses

| Decision | Status | Flips to `accepted` when |
|---|---|---|
| D1a transport | `accepted` (2026-09-15) | Measured: branch dry-run [34906907089](https://github.com/jikig-ai/soleur/actions/runs/34906907089), re-measured on the post-review code in [34948776755](https://github.com/jikig-ai/soleur/actions/runs/34948776755) (same three verdicts, exit 3), logged `role=web verdict=ok`, `role=git-data-jump verdict=ok`, `role=git-data-auth verdict=git_data_root_key_absent` and exited 3 before `prepare_luks_target`. web-1's sshd permits the `direct-tcpip` channel and an `SSH-2.0-` line came back through it. |
| D1b authenticated hop | `proposed` | #8189's dry-run reads `role=git-data-auth verdict=ok`. |
| D2–D3 credential and lifetime | `proposed` | #7226 pins git-data's host key, #8189's dry-run reads `role=git-data-auth verdict=ok`, **and** the freeze and reloads are reconciled with ADR-119 (Context). That dry-run exercises neither the freeze nor the flip, so it cannot stand in for the reconciliation. With a `main`-only deployment policy, it can only run after #8189 merges. |
| D4 residuals | Standing constraints | They are not accepted. Each one is discharged by the issue named with it. |

`architecture list` shows the frontmatter's single status, which is the least-advanced one
(`proposed`).

> **Superseded 2026-09-15 (#8189), as to the D1b and D2–D3 rows:** their flip conditions are restated
> in the Amendment log, "D5".

### D6 — Sequencing

**This PR** ships D1a's wiring and a fail-closed access gate; the change list is in the plan
(`plans/archive/20260915-105155-2026-09-14-fix-git-data-cutover-ci-access-path-plan.md`). It has **no key input and no secret
reference**: a secret wired into an ungated job would arm itself the moment #8189 creates it.

**Exit codes.** `3` = the access gate stopped the run (one `ACCESS` verdict per role: `web`,
`git-data-jump`, `git-data-auth`). `4` = a ROLLBACK-only run could not complete a recovery step
(`::warning title=git-data-cutover recovery::step=<name> rc=<n>`). Until #8189 lands, the expected
dry-run result is a **red** run whose annotation reads
`role=git-data-auth verdict=git_data_root_key_absent`, stopped before `prepare_luks_target`.

**#8189** delivers the rest:

- the key resources (separate root), `prd_git_data_root`, the read credential, and the environment;
- admission to the birth/replace gate allow-sets and the target lockstep;
- #8009 C1 re-approval (CPO + CTO) and the PA-36 update;
- the `ssh_config` auth wiring;
- the git-data replace;
- its blocking checklist: the `prd_terraform`-scoped flag token, the missing concurrency
  serialization, the ADR-119 reconciliation of the freeze and reloads, and the post-cutover
  dry-run self-overwrite (Context).

Landing the key resources in this PR would put their addresses outside every exact-scope gate
allow-set.

> **Superseded 2026-09-15 (#8189):** exit code `4` and the ROLLBACK mode are gone; `5` is a refusal.
> The red result is bound to key delivery, not to #8189's merge: after the merge and before the root-key
> apply a dry run refuses `verdict=git_data_root_token_absent`, and before the replace it reads
> `role=git-data-auth verdict=failed reason=auth_refused` (runbook verdict map). There is no
> `prepare_luks_target` step any more. The "#8189 delivers the rest" list is dispositioned in the
> Amendment log, "D6".

## Consequences

**Easier:**

- Root on the store is never reachable from web-1 root.
- No internet-edge hostname or Access app is added for the store host.
- Rotation cutovers need no replace.
- The never-run workflow now fails at a named verdict instead of `terraform: command not found` or
  an ssh timeout that names nothing.

**Harder or newly true:**

- Delivering the key requires a git-data replace (#8189).
- Reaching the store depends on web-1's sshd allowing `direct-tcpip` and on a connector with a
  private NIC.
- There is now a second unverified host key for #7226.
- Once #8189 lands, a dry-run is **no longer non-mutating**: it runs `luksOpen`, mounts, and runs
  `rsync --delete` into FRESH.

  > **Superseded 2026-09-15 (#8189):** the dry run stays read-only. See the Amendment log,
  > "Consequences".
- PR-branch `plan` runs can already read the web-platform root state. This is a pre-existing
  exposure: this ADR bounds it with the custody goal but does not remove it (D2 known gaps).

## Cost Impacts

None. #8189 adds one Doppler config, a service token or OIDC identity, and one Hetzner SSH key
object, all on existing plans.

> **Superseded 2026-09-15 (#8189), as to the object list:** one Doppler project with one environment,
> one service token and one Hetzner SSH key object, all on existing plans. Still no cost.

## NFR Impacts

- **NFR-026 (Encryption In-Transit):** no tier change. The jump is SSH-2 inside the CF-Access-gated
  tunnel, and host-key verification stays off on both hops (#7226).
- **NFR-014 (Externalized Environment Configuration):** the key lives in Doppler, never in the repo
  or on web-1.

## Principle Alignment

- **AP-001 (Terraform-only):** Aligned. The key is minted by Terraform and delivered by replace, with
  no human mint.
- **AP-008 (Doppler secrets):** Aligned. The key is in `prd_git_data_root`, and the repo-secret
  fallback carries only a read token.
- **AP-003 (R2 remote backend):** Aligned. The separate root gets its own backend.
- **AP-002 (No SSH state mutation):** No new deviation. The cutover already mutates hosts over SSH
  under ADR-068. This ADR only decides how that SSH session reaches git-data, and no runbook gains an
  SSH step.

> **Superseded 2026-09-15 (#8189), as to AP-008 and AP-003:** the key is in the Doppler project
> `soleur-git-data-root`, not `prd_git_data_root`, and the root has its own state key in the shared R2
> bucket, not its own bucket. See the Amendment log, "Principle Alignment".

## Amendment log

### 2026-09-15 (#8189): a separate root, a reviewer-gated read token, and a read-only dry run

Implementation measured several D2 and D3 requirements as unmet or undeliverable. The decisions below
replace them. The plan
(`knowledge-base/project/plans/archive/20260915-181714-2026-09-15-feat-git-data-root-key-separate-root-plan.md`, "Measured facts
that change the issue's design") holds the evidence. The issues named here are #8209 (evict the
repo-secret-reachable credentials from `prd_terraform`), #8211 (rebuild the cutover's real modes) and
#8210 (`/dev/mapper/git-data` is not reopened at boot).

#### Blocker dispositions (Context)

1. **`read_flag` failed open.** `git-data-flag-precheck.sh` now reads `GIT_DATA_STORE_ENABLED` from `prd`
   in its own workflow step, before the bridge and the key fetch exist. It is the only step holding
   `DOPPLER_TOKEN_PRD`. A read error refuses `flag_read_failed`, and `true` refuses `flag_already_true`.
   `DOPPLER_TOKEN_WRITE` is no longer referenced.
2. **Inert freeze and reloads.** Deleted, together with the rest of the cutover body (copy, repoint,
   canary, wipe, flip, rollback, the web-host SSH helper). A real mode refuses
   `real_cutover_unreconciled` before any remote call. The rebuild is #8211.
3. **Dry-run self-overwrite.** The script no longer contains a copy, mount or LUKS call. After the access
   gate, three fail-closed probes refuse `old_store_unmounted`, `already_cut_over` and `store_not_empty`.
4. **No serialization.** The run holds workflow-level `git-data-state`. `web-1-swap` membership moves to
   #8211, with the first job that mutates web-1. A read-only job waiting on that group could cancel a
   pending release deploy (#8167) and would protect nothing.

#### D1b

The authenticated hop is written by a workflow step into a fixed-path `ssh_config`. It has exact
`Host 10.0.1.10` and `Host 10.0.1.20` blocks, each with its own `IdentityFile`, and
`ProxyCommand ssh -F <cfg> -W 10.0.1.20:22 10.0.1.10` with a literal target. Both blocks set
`IdentitiesOnly`, `BatchMode` and no forwarding. The decision is otherwise unchanged.

#### D2 — the credential as delivered

- **The custody goal is nominal today.** Any branch workflow can name the `DOPPLER_TOKEN` repo secret,
  which reads `prd_terraform`. That config holds `DOPPLER_TOKEN_TF`, `CF_API_TOKEN_R2`, `HCLOUD_TOKEN` and
  `GITHUB_APP_PRIVATE_KEY`. The separate root is still worth having: the key never enters the web-platform
  root, which many plan and apply jobs read and print from in a public repository's logs. It does not
  protect against a repo-secret holder. That is #8209, which needs its own ADR.
- **The root.** `apps/web-platform/infra/git-data-root-key/`, applied only by the dispatch-only
  `apply-git-data-root-key.yml`. That job runs behind the `web-platform-infra-apply` environment and
  holds job-level `git-data-state`. It is **additive-only, with no exception and no rotation input**:
  it refuses any plan other than a create of exactly the root's seven addresses or a no-op (so
  `forget`, `delete`, `update` and a replace are refused too), and it refuses an import or a moved
  address. Once
  `apps/web-platform/infra/git-data-root-key.fingerprint` exists in the checkout, it refuses a create
  of `tls_private_key.git_data_root` (`git_data_root_key_remint_refused`): a create then means state
  loss or a deleted key, never a first mint. It prints the key's `SHA256:` fingerprint **read from
  Terraform state**, and only after that value equals the fingerprint derived from the Hetzner key
  object's public key (`git_data_root_key_fingerprint_mismatch` otherwise), so the printed anchor is
  never read from the object it protects. It emails ops on any non-success except a run-level cancel.
  - Resources: an ED25519 `tls_private_key`; `hcloud_ssh_key` `soleur-git-data-root`, labelled
    `soleur-role=git-data-root`; the Doppler project `soleur-git-data-root`, whose environment and config
    `prd` holds `GIT_DATA_ROOT_SSH_PRIVATE_KEY`; and a read service token published as the repo secret
    `DOPPLER_TOKEN_GIT_DATA_ROOT`.
  - `prevent_destroy` covers the key, the Hetzner key object, the project, the environment and the secret.
- **A Doppler project, not `prd_git_data_root`.** A branch config under `prd` resolves `prd`'s secrets
  (learning `security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md`).
- **D2.1 reversed: a shared bucket with its own state key.** State lives at
  `web-platform/git-data-root-key/terraform.tfstate` in `soleur-terraform-state`. No credential can mint a
  bucket-scoped R2 token (ADR-130), and `CF_API_TOKEN_R2` is account-wide, so a dedicated bucket would be
  readable by the same holders.
- **D2.2 holds by placement.** The nested root collapses to its parent in `detect-changes`, so the PR
  `plan` job never initializes it (`infra-validation-detect.test.sh`, TS2b). **D2.3 holds:** the
  web-platform root has no `terraform_remote_state`.
- **Public-key hand-off.**
  - `git-data.tf` reads a label-selected plural `data "hcloud_ssh_keys" "git_data_root"` and concatenates
    it into `hcloud_server.git_data`'s `ssh_keys`. `ignore_changes = [ssh_keys]` stays.
  - There is no resource precondition, because it would fail every web-platform plan. Instead, both
    host-creating gates call `git_data_root_key_arm`. It refuses a create unless:
    - the committed `apps/web-platform/infra/git-data-root-key.fingerprint` matches the single resolved
      key;
    - every created server carries exactly the default key and that key.
  - The refusal is an `::error title=git-data-root-key-arm::` annotation reading
    `verdict=git_data_root_key_not_in_create reason=<word>` (the word only), with a per-reason remedy:
    `fingerprint_file_missing` or `data_source_absent` means the anchor or the key is not in place yet
    (dispatch the root-key apply, commit the fingerprint, re-dispatch); `fingerprint`, `key_count` or
    `name` means a key object changed outside Terraform (do **not** re-anchor; open an incident under
    the runbook's breach-triage trigger); `server_keys` is a plan-shape defect.
  - The committed fingerprint is the one value an `HCLOUD_TOKEN` holder cannot move. It stops a swapped
    Hetzner key object from becoming root on every future replace. **That holds for dispatches from
    `main` only.** The arm reads the fingerprint file from the dispatched ref's checkout. The birth job
    is environment-gated to `main`; the replace job has no `environment:`, so a replace dispatched from
    a branch supplies that branch's own anchor. Against a repository-write actor the replace path's
    anchor is not outside reach (#8093).

    > **Superseded 2026-09-22 (#8209, ADR-241 D2):** `git_data_host_replace` now carries
    > `environment: infra-privileged`, whose deployment-branch policy admits `main` only, so a
    > replace dispatched from a branch is refused before the job starts and can no longer supply
    > its own anchor. The reachable set narrows from "anyone with repository write" to "anyone who
    > can land a commit on `main`". The residual named above is not closed by that -- it is
    > narrowed -- and the remaining reach is tracked as ADR-241's residual R1.
- **Token delivery: the fallback is taken.** Doppler service-account identities need the Team or
  Enterprise plan, and the workplace is on the Developer plan. The fallback's three guards, as delivered:
  1. A reference census allows `DOPPLER_TOKEN_GIT_DATA_ROOT` under `.github/` only in the `cutover` job of
     `git-data-cutover.yml`, matching the secret name case-insensitively, and runs on every PR. It stops
     accidental use on `main` bytes. It does not stop a branch workflow from naming a repo secret.
  2. The `main`-only policy comes from reusing `web-platform-infra-apply` (reviewer, custom branch policy
     `main`) instead of creating a `git-data-cutover` environment.
  3. **Expiry is not expressible.** `doppler_service_token` has no expiry attribute. The token persists
     until a reviewed PR that adds a typed rotation arm for exactly its addresses replaces it, or a PR
     removes it.
- **What the environment is and is not.** It is a single-human acknowledgement, not two-party review: it
  records `can_admins_bypass: true` and `prevent_self_review: false`. It is a human gate, not a secret
  boundary. The Terraform App cannot write environment secrets, so the token is a repo secret, and
  `secrets: inherit` in `web-platform-release.yml` and `version-bump-and-release.yml` passes every repo
  secret to `reusable-release.yml`. The real boundary is repository write access.
- **Scope.** The gated job serves the read-only dry run only. The rollback split moves to #8211.
- **The Doppler hop is kept** (AP-008) over a repo secret holding the key itself.

#### D3 — lifetime as delivered

- **No window.** The read token does not expire (D2). The private key stays in state and in Doppler.
- **Host side.** The key is not revoked at the next replace. `prevent_destroy` and the create gate make
  every replace carry the same key. Host authorization ends only at a replace that follows a rotation.
- **Rotation.** The root-key apply is additive-only with no exception, so **any rotation, of the read
  token or of the key, is a reviewed PR** that adds a typed allowlist arm naming exactly the addresses
  it replaces. A key rotation's PR also lifts `prevent_destroy` on those addresses and accounts for the
  re-mint refusal. Then a dispatch runs; for the key, a new fingerprint PR merges and the next replace
  delivers the new key. Until that replace, dry runs fail `auth_refused`. An earlier draft of this
  amendment carried a `rotate_read_token` dispatch input; it was removed because it admitted
  delete-only and no-op "rotations" and could not express a key rotation.
- **Accounting.** #8009's authorization accounting records the root key as a distinct root authority,
  beside `hcloud_ssh_key.default`, which every create also delivers as a root login key
  (ADR-149, "Addendum — #8189 (2026-09-15)"), and the Article 30 git-data entry carries it as a TOM.

#### D4 — new residuals

- **Repo-secret reach (#8209).** A repo-secret holder reaches the R2 state object and the Doppler project
  that hold the key. #8209 decides the eviction in its own ADR.
- **`HCLOUD_TOKEN` already reaches root on the host** through rescue, rebuild or a volume re-attach. The
  separate root does not protect against that holder.
- **The key's reach is the whole private network, not only web-1.** D1b keeps the key and any agent
  socket off web-1, but the key itself authenticates from any foothold on `10.0.1.0/24`: the git-data
  firewall has no rules, and a Hetzner firewall does not filter the private network in any case. A key
  holder with a shell on any private-network host reaches root on the store.
- **A leaked root key exposes `prd` before any repository exists.** Root on the host reads the host's own
  `prd_git_data` token. That token is a `prd` branch config, likely resolving all of `prd` (#6167).
- **Store-probe evidence is unauthenticated until #7226.** A compromised web-1 could answer "mounted, not
  cut over, empty". `store_not_empty` stays as a refusal at least until #7226 pins git-data's host key.
- **Root logins on git-data are not detected.** Tracked on #8093.
- **Breach triage.** Once repositories exist, a root-key leak is likely an Art. 33 event. The runbook
  (`git-data-luks-cutover-5274.md`, "Breach-triage trigger") names what opens an incident. The trigger
  covers **any workflow run that received `DOPPLER_TOKEN_GIT_DATA_ROOT`** outside the `cutover` job,
  including a callee that received it through `secrets: inherit` (D2, "What the environment is and is
  not"), not only a reference in `git-data-cutover.yml`.
- **No drift leg for the new root.** A scheduled leg would need state that holds the private key. A
  deleted or swapped Hetzner key object surfaces at the create gate. A deleted secret or a revoked token
  surfaces as `git_data_root_key_fetch_failed` on the next dispatch.
- **A rotation breaks dry runs until the next replace** (`auth_refused`).

#### D5 — statuses (2026-09-15)

| Decision | Status | Flips to `accepted` when |
|---|---|---|
| D1a transport | `accepted` (2026-09-15) | Unchanged. |
| D1b authenticated hop | `proposed` | A dispatch from `main`, after the root-key apply, the fingerprint PR and the replace, reads `role=git-data-auth verdict=ok` with all three store probes clear. The flip is recorded with the caveat that the store evidence is unauthenticated until #7226. |
| D2–D3 credential and lifetime | `proposed` | #7226, #8209 and #8211 land. |
| D4 residuals | Standing constraints | Each is discharged by the issue named with it. |

#### D6 — sequencing and hand-off

- **#8189 ships** the new root and its apply, the data source and the create-gate arm, the flag precheck,
  the read-only script with its probes, and the workflow's shape and serialization. Exit codes: `3` means
  the access gate stopped the run, and `5` means a refusal.
- **Post-merge order.** Each step needs explicit authorization:
  1. the root-key apply;
  2. the fingerprint PR;
  3. `git-data-host-replace`;
  4. the private-NIC heartbeat read;
  5. the dry run.

  The runbook holds the verdict map.
- **Hand-off to #8211:** the cutover body; the rollback split (an ungated flag-off and reload, and a gated
  credential step); `web-1-swap` membership on the job that drains web-1; and a `prd` flag-write
  credential.
- **#8211's preconditions:**
  - #7226;
  - #8209;
  - a fresh replace plus a `GIT_DATA_LUKS_KEY` rotation immediately before the real cutover, so nothing
    planted during the read-only period survives into it.

  #8210 must close before a post-cutover reboot is safe.

#### Consequences

- **The dry run stays read-only.** It authenticates to root and runs three read probes. It cannot copy,
  mount, flip or wipe.
- Delivering the key requires a replace, and so does ending a rotated key's authorization.
- **The create gates now depend on the root-key apply and the fingerprint file.** A recovery replace
  refuses until both exist. Until it runs, each account deletion waits up to the 30 s `execFile`
  timeout and logs an Art. 17 erasure-failure event; no repository exists, so nothing is left behind.
  The runbook names this blocked-recovery window and its escape hatch (a reviewed PR that reverts the
  arm call in both gates).
- **A pending approval on a cutover or root-key run holds `git-data-state`.** Answer or cancel it before
  dispatching a replace.
- **"Rotation cutovers need no replace for access" survives only in a narrow sense.** It means a later
  cutover run authenticates with the already-delivered root key, because that key persists across
  replaces. It does not mean either rotation is replace-free: a `GIT_DATA_LUKS_KEY` passphrase rotation
  is a full volume cutover that needs a host replace (`git-data-luks.tf`, "Rotation"), and a rotation of
  the SSH root key needs a replace to deliver the new key. The first real cutover needs a replace too
  (D6).

#### Considered options: zero-downtime key delivery

Delivering the key needs a git-data replace, which takes the store host down for the replace job's
duration. Two zero-downtime alternatives were evaluated and rejected (moved here from the plan's
"Downtime & Cutover" section, so the rejection lives with the decision):

| Option | What it buys | Why it was not chosen |
|---|---|---|
| Blue-green: a second host, then switch | No store outage | Both store volumes attach to one server, and the private address `10.0.1.20` is fixed in every consumer. A second host needs a new address, volume moves and a consumer repoint: more risk than a minutes-long outage of a surface no user request depends on while the flag is off. |
| In-place key delivery | No replace | Violates `hr-prod-host-config-change-immutable-redeploy` (see also the Considered Options row "Deliver the key in place"). |

Accepted: the existing replace, whose gate already asserts both volumes are retained, run with explicit
authorization.

#### Principle Alignment

- **AP-001:** unchanged. The key is minted by Terraform and delivered by a replace, with no human mint.
- **AP-008:** the key is in the Doppler project `soleur-git-data-root`, and the repo secret carries only a
  read token.
- **AP-003:** the root has its own state key in the R2 backend's shared bucket.

### 2026-09-21 (#8101, PR #8454): a fourth read probe, the pre-receive fence

The dry run now runs a fourth read-only probe after the three store probes: `probe=fence-shape`
(`git-data-cutover.sh` › `refuse_if_fence_not_intact`). It checks that a push would run a root-owned
`pre-receive` of the planted shape. That means the hooks directory and hook are owned and permissioned
as the bootstrap sets them, the `git` user can run the hook, the installed transport wrapper and the
system `core.hooksPath` both name the directory, and it sits on the accepted store device. The 2026-09-15
D5 row for D1b is unchanged: D1b is judged on the access gate and the three store probes. Exit 0 of the
dry run now also requires the fence probe. Like every store probe, its answer is unauthenticated while
#7226 is open. The copy half of #8101, and the wrappers' mapper-device assertion, are carried by #8211.

### 2026-09-21 (#7226, PR #8511): host keys are pinned (ADR-237)

[ADR-237](./ADR-237-ssh-host-keys-are-pinned.md) pins web-1's host key on every CI path and git-data's
on both cutover hops and in the app's git transport. Earlier entries are not rewritten; this entry
records what changes in them.

- **D4, first residual ("Unverified host keys (#7226)") — closed by ADR-237, effective at post-merge
  step 4** of the runbook's host-key sequence: the strict dry run from `main` reads
  `role=git-data-auth verdict=ok` with both hops pinned. Until then the residual stands as written.
  The 2026-09-15 residual "Store-probe evidence is unauthenticated until #7226" closes at the same
  step, as to web-1 standing in for git-data. A pinned key authenticates the host, not its answers:
  a rooted git-data can still answer falsely, so `store_not_empty` and the bounded probes stay.
- **D4, second residual ("Verdicts show liveness, not authenticity").** The host-key half of D2's
  `accepted` precondition now points to ADR-237 reaching `accepted`. The other conditions in the
  2026-09-15 D5 table (#8209, #8211) are unchanged.
- **D6 — design change.** The fresh replace immediately before the real cutover (a #8211
  precondition) now also **rotates git-data's SSH host key** and **redeploys the app**: the replace
  job re-mints `tls_private_key.git_data_host_ssh`, republishes `GIT_DATA_SSH_HOST_KEY` to `prd`, and
  the `git-data-pin-redeploy.yml` workflow, triggered when that apply run completes, forces a web
  release so the app loads the new pin. Nothing planted during the read-only period survives into
  the cutover, now including the host key. The replace is still required; ADR-237's post-merge
  step 3 is a separate, earlier replace, not this one.
- **New constraint from ADR-237.** Setting `GIT_DATA_STORE_ENABLED` requires the pin present in `prd`
  **and** #5914 closed (the app's unpinned fallback arm deleted). The runbook's precondition list
  carries it.

### 2026-09-22 (#8209): the custody goal gets a boundary — ADR-241's credential tiers

[ADR-241](./ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md) decides the
eviction this ADR deferred. Earlier entries are not rewritten; this entry records what changes in
them.

- **D2, "The custody goal is nominal today" — now carried by ADR-241's Tier-B boundary, not yet
  discharged.** That clause said the separate root "does not protect against a repo-secret holder"
  and named #8209 as the decision that would. ADR-241 D1–D2 is that decision: credentials are split
  into a branch-reachable Tier A and a main-only Tier B, and a Tier-B credential is delivered only as
  a GitHub environment secret on an environment whose deployment-branch policy admits `main` only.
  `web-platform-infra-apply`, the environment this ADR's D2 already reuses, is one of the four Tier-B
  environments, and ADR-241's census asserts its `main` policy from the Terraform sources on every
  PR. What does **not** change: an environment is still a human gate, not the boundary — the
  *branch policy* is the boundary, and ADR-241 D2 is explicit that it holds whether or not reviewers
  are configured.
- **D4, "Repo-secret reach (#8209)" — addressed, not closed.** That residual named two paths to the
  root key: the repo secret and the R2 state object. ADR-241 D7 moves both. The repo secret
  `DOPPLER_TOKEN_GIT_DATA_ROOT` becomes an **environment secret on `web-platform-infra-apply` under
  the same name** at operator step O7 of the #8209 runbook, so `git-data-cutover.yml` needs no edit
  (its `cutover` job already declares that environment, and an environment secret overrides a
  repo secret of the same name); the Terraform-minted token and the repo secret are forgotten by
  Terraform with `removed { … lifecycle { destroy = false } }` and then revoked out of band. The
  state object moves to a second R2 bucket, `soleur-terraform-state-privileged`, read only by a
  bucket-scoped Tier-B token — which **reverses D2.1 as amended on 2026-09-15**: that reversal put
  the root-key state in the shared bucket because `CF_API_TOKEN_R2` is account-wide and no credential
  can mint a bucket-scoped token (ADR-130). The token is still operator-minted; what changed is the
  measurement that the `prd_terraform` `AWS_*` keys are **bucket-scoped**, so a bucket they are not
  scoped to is genuinely out of reach. **This residual is not closed until ADR-241's residual R1
  closes.** R1 is the soleur-ai *runtime* key in Doppler `prd`, readable by `DOPPLER_TOKEN_PRD` and
  by every `prd_*` branch-config repo-secret token; the App holds `administration:write` on
  `jikig-ai/soleur`, so a holder can rewrite the very deployment-branch policy the new boundary rests
  on. Until R1 closes, the move stops a branch workflow from *naming* the secret; it does not stop a
  `prd` repo-secret holder. R1 is filed at `priority/p1-high`, `type/security` and blocks #8211's
  real cutover.
- **D5 — the "D2–D3 credential and lifetime" row.** Its 2026-09-15 flip condition reads "#7226, #8209
  and #8211 land". Restated with the #8209 limb made precise, the other two unchanged:

  | Decision | Status | Flips to `accepted` when |
  |---|---|---|
  | D2–D3 credential and lifetime | `proposed` | #7226 (ADR-237 reaching `accepted`, per the 2026-09-21 entry) and #8211 land, **and** the #8209 limb is satisfied — which is not the merge of #8209's PR but ADR-241's own D2 reaching `accepted`, i.e. ADR-241 residual **R1** closed and **R7** closed at the runbook's state-key step. Merging #8209 alone leaves the boundary nominal against a `prd` repo-secret holder, which is the same gap this row was opened for. |

  The D1a, D1b and D4 rows are unchanged.
- **No change to the root's additive-only contract.** #8209 adds exactly one typed allowlist arm,
  `8209_custody_forget`, admitting a forget of exactly the two custody addresses
  (`github_actions_secret.doppler_token_git_data_root`, `doppler_service_token.git_data_root_read`)
  and nothing else. It is one-shot: ADR-241's residual R6 deletes it once that forget has landed.
  That is the D3 rule as written — any change is a reviewed PR with a typed arm — not an exception to
  it.
- **The backend becomes partial.** `git-data-root-key/main.tf` drops its literal `bucket`, so
  `terraform init` takes `-backend-config=bucket=$BUCKET`: the privileged bucket when the credential
  loader exported the `GIT_DATA_ROOT_STATE_*` pair (all-or-none; a half-set pair is refused), the
  legacy bucket otherwise, and the legacy bucket **refused** once the repo variable
  `GIT_DATA_ROOT_STATE_MIGRATED=1` is set. D2.2 still holds by placement: the nested root collapses
  into its parent in `detect-changes`, so the PR `plan` job never initializes it and needs no backend
  config. If the legacy fallback were ever taken after the old object is gone, `init` would yield an
  empty state — and the existing `git_data_root_key_remint_refused` gate, keyed on the committed
  fingerprint file, refuses that plan. A re-mint stays structurally unreachable.
