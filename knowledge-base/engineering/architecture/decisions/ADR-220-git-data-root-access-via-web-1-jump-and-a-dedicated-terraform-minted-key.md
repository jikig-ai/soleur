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

### D3 — Lifetime

- **Consumer side:** the read credential exists only for a cutover window (a rehearsal, the
  cutover, or a rotation) and expires on its own.
- **Host side:** the key is revoked at the next replace.
- **Rotation:** rotation cutovers therefore **need no host replace**.
- **While a token exists:** #8009's authorization accounting and PA-36 record the root authority.

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
- PR-branch `plan` runs can already read the web-platform root state. This is a pre-existing
  exposure: this ADR bounds it with the custody goal but does not remove it (D2 known gaps).

## Cost Impacts

None. #8189 adds one Doppler config, a service token or OIDC identity, and one Hetzner SSH key
object, all on existing plans.

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
