---
title: "fix(infra): git-data-cutover CI access path — jump through web-1's ssh ingress, fail closed on the unprovisioned git-data root key (ADR-220)"
type: fix
date: 2026-09-14
slug: fix-git-data-cutover-ci-access-path
branch: feat-one-shot-6680-git-data-cutover-access-path
issue: 6680
closes: []
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# Plan: a CI access path from git-data-cutover.yml to the git-data host

## Enhancement Summary

**Deepened on:** 2026-09-15
**Sections enhanced:** Research Reconciliation, ADR-220 decisions 2–5, Technical Approach (verdicts, sanitization, argument hygiene, measured probe form, precedent-diff), Observability, Guard Contract, Test Scenarios, Acceptance Criteria (AC1–AC5, AC11), Infrastructure (IaC), Alternatives, Hypotheses (network deep-dive)
**Agents used:** security-sentinel, test-design-reviewer, observability-coverage-reviewer, a verify-the-negative + dropped-symbol sweep (12/12 current-code claims confirmed, no stale prescriptions); mechanical gates 4.5–4.11 run inline; a real-OpenSSH container measurement of the probe form

### Key Improvements

1. **Custody rule (security, HIGH):** the git-data root private half must never live in the web-platform root state — PR-branch `terraform plan` runs read that state, and it already holds the web-1 root key and CF Access token. The follow-up uses a separate root; token delivery is OIDC-first.
2. **Workflow-command injection closed:** probe bytes are attacker-chosen once host keys are unverified; they now never reach the runner's command parser unsanitized (stop-commands span, printable-ASCII filter, verdicts only from script-emitted lines).
3. **Probe form measured, not assumed:** OpenSSH 9.6p1 in a container — banner on the first line 20/20 with `</dev/null`, discriminating empty-line failures for forwarding refused / target closed / key refused.
4. **Guard suite de-vacuated:** a single `$TL` timeline replaces cross-stream ordering, a structural plain-statement check (H5), argument hygiene (`invalid_host`), and a CI-required real-sshd runtime arm.
5. **Verdicts are liveness, not authenticity:** #7226 host-key pinning becomes a precondition for the credential decision's `accepted` status.

### New Considerations Discovered

- `infra-validation.yml`'s PR-only `plan` job exposes the web-platform root state to anyone with write access (pre-existing; bounded here by the custody rule, not changed).
- The workflow header's "Inngest dispatches this workflow" claim is false; corrected in this PR.
- Once the follow-up adds a `main`-only deployment policy, the proving dry-run can only run after that PR merges.
- Downtime gate (4.55): not triggered — no forward run gets past the access gate, and the AC11 dry-run runs only `true` on web-1 and reads git-data's banner. A rollback dispatch can now reach web-1's reload and un-drain calls (review 2026-09-15), but those are inert: the systemd units they name do not exist (#8189).

## Overview

The git-data LUKS cutover workflow needs an SSH session to two private hosts: web-1 (10.0.1.10) and
the git-data store (10.0.1.20). The Cloudflare Tunnel carries one SSH ingress, pinned to web-1, so the
workflow can reach web-1 but has no route and no authorized credential for the git-data host. This plan
decides the access path in an ADR and wires the workflow, the shared bridge action and the cutover
script to it, failing closed where the path is not yet provisionable.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Check | Result |
|---|---|---|
| #6680 open, targets this gap | `gh issue view 6680` | OPEN, body matches |
| #6441 (ADR-114 I2 residual) | `gh issue view 6441` | OPEN; §1 states a second SSH **hostname** forces per-hostname bridge/port/NAT multiplexing, a service repoint does not |
| PR #6681 terraform-free `server-ip` input | `gh pr view 6681` | MERGED 2026-07-18 |
| #5274 / #8101 / #8094 / #8178 / #6604 | `gh issue view` | all OPEN (out of scope, cited only) |
| `git-data-cutover.sh` dials `10.0.1.20` via `gd_ssh` | read file | holds: `GIT_DATA_HOST="${GIT_DATA_HOST:-10.0.1.20}"`, `gd_ssh() { ${GIT_DATA_SSH:-ssh} "$1" "$2"; }` |
| workflow gets both invocations from the bridge | read `git-data-cutover.yml` + `action.yml` | **stale in two ways.** (1) the workflow does NOT pass `server-ip`, so the bridge takes the terraform path (`terraform output -raw server_ip`) in a job that never installs terraform — wall 1, exactly the #6649 wall. (2) Even with `server-ip`, the bridge exports `GIT_DATA_SSH` byte-identical to `WEB_HOST_SSH` (`ssh -i <ci key> … -l root`, no proxy), so it can never reach 10.0.1.20. The workflow also has no `if: always()` teardown step. |
| one SSH ingress, to web-1 | read `tunnel.tf` | holds: `ssh.${app_domain_base}` → `ssh://${var.web_hosts["web-1"].private_ip}:22`; web-1 is the only connector (#6425) |
| root on git-data is key-only, key = `hcloud_ssh_key.default` | read `cloud-init-git-data.yml` `01-hardening.conf`, `git-data.tf` `hcloud_server.git_data` | holds (`PermitRootLogin prohibit-password`, `ssh_keys = [hcloud_ssh_key.default.id]`, `ignore_changes = [ssh_keys]`) |
| **no CI credential is authorized for root on git-data** | Hetzner API `GET /v1/ssh_keys` (read-only) + `ssh-keygen -l -E md5` of the Doppler `DEPLOY_SSH_PRIVATE_KEY` pubkey and of the local operator pubkey (public fingerprints only) | **holds, measured.** `soleur-web-platform` (the only key on `hcloud_server.git_data`) = `MD5:95:97:8c:9a:…` = the operator's personal `~/.ssh/id_ed25519.pub`; the CI key is `MD5:42:4b:85:dd:…`. The birth route passes `-var ssh_key_path=/tmp/ci_ssh_key.pub` (a throwaway) but `hcloud_ssh_key.default` carries `ignore_changes = [public_key]`, so the throwaway never reaches Hetzner. |
| `git` user has three forced-command keys only | read template | holds; `git_data_authorization_map_gate` (#8009, CPO C1) asserts exactly three |
| store holds no repos | #6976 + ADR-068 D10 | holds **by construction**: every write path is gated on `isGitDataStoreEnabled()` and the cutover refuses to run once the flag is on |
| Proposed mechanism vs ADR corpus | grep `decisions/` for `born-on-LUKS`, `ssh-git-data`, `ProxyJump` | **born-on-LUKS is an explicitly rejected alternative** (ADR-068 addendum D10, operator decision 2026-07-27): "#6680 must be fixed regardless, since rotation remains a full volume cutover." Not re-litigated here. ADR-114 anti-pattern: per-hostname ingress does not pin a connector; I2 requires origin-relative service addresses. |
| Workflow run history | `gh run list --workflow git-data-cutover.yml` | **zero runs ever** — a never-run workflow; budget for a chain of walls, not one (learning 2026-07-18 shared-action false export contract) |

### Property List (Phase 0.6b)

- **P1** A `dry_run=true` dispatch of `git-data-cutover.yml` establishes an authenticated root SSH session to web-1 over the existing tunnel.
- **P2** The same dispatch establishes (or, where not provisionable, proves the route to) an SSH session to the git-data host without adding an internet-edge ingress for it.
- **P3** When root on git-data is not authorized, the run stops BEFORE any host-mutating step with a machine-readable reason naming the missing credential — never a silent fallback, never a timeout that names nothing.
- **P4** The root credential for git-data is minted by Terraform (no operator mint), is not a credential already held by other workflows or readable from the web-platform root state, and never lands on web-1.
- **P5** Existing bridge callers (`apply-web-platform-infra.yml`, `apply-deploy-pipeline-fix.yml`, `workspaces-luks-cutover.yml`, `workspaces-luks-verify.yml`) observe no change to any export they consume (the only removed export, the bogus `GIT_DATA_SSH`, has exactly one consumer: `git-data-cutover.sh › gd_ssh`).
- **P6** No hash-bound birth input, no rung-2 evidence, no terraform target lockstep, no Doppler `prd_git_data` hand-creation changes in this PR.
- **P7** The access-path decision is recorded in an ADR and in the C4 model in the same PR.

### Cut List (Phase 0.6b)

- **Second tunnel ingress + second CF Access app + second bridge redirect** (issue option (a)) → buys P2 → already bought by the existing `ssh.` ingress plus an OpenSSH `ProxyCommand … -W` hop through web-1's sshd. Cut.
- **A new SSH key for web-1** → buys P1 → `DEPLOY_SSH_PRIVATE_KEY` (ci_ssh) is already authorized on web-1 root (`ci-ssh-key.tf`, `cloud-init.yml ssh_authorized_keys`). Cut.
- **A new reachability probe mechanism** → buys P3's transport half → OpenSSH's own `-W` stdio forward already returns the target sshd's `SSH-2.0-` banner with no git-data credential. No new probe binary. Cut.
- **Terraform in the cutover job** (to satisfy the bridge's `terraform output`) → buys P1 → the terraform-free `server-ip` input (#6681) already covers it. Cut.
- **Plan-review cuts (2026-09-15, DHH + code-simplicity + advisor, all Mechanical):** the bridge `ssh_config` writer and its two new inputs (the jump probe is `$WEB_HOST_SSH -W`, which needs no config); all key handling — key input, malformed check, git-data `Host` block, `ssh -G` guard (dead until the follow-up creates the secret, and untestable here); the stderr classifier + fixture capture (stage + stdout banner decide the verdict; raw stderr is logged); the IP literal parity guard (a wrong IP fails loud in the live probe); the post-merge re-run dry-run (duplicates the pre-merge branch run).

### Relevant files (measured anchors)

- `.github/workflows/git-data-cutover.yml` — bridge step `uses: ./.github/actions/cf-tunnel-ssh-bridge` with no `server-ip`; no teardown; `concurrency.group: git-data-cutover`.
- `.github/actions/cf-tunnel-ssh-bridge/action.yml` — step "Decode CI SSH private key": `SSH_INVOCATION` = the ssh binary with identity `$KEYFILE`, `StrictHostKeyChecking=accept-new`, `UserKnownHostsFile=/dev/null`, login `root` — then `WEB_HOST_SSH=` and `GIT_DATA_SSH=` both set to it. Final step "Gate — CF Access must still admit the ci_ssh credential" MUST remain last (asserted by `scripts/check-cloudflare-token-drift.test.sh` W6; call-site distribution W7 counts one `uses:` in `git-data-cutover.yml`).
- `apps/web-platform/infra/git-data-cutover.sh` — `main()` runs `prepare_luks_target` (luksOpen + mount, NOT `DRY_RUN`-gated) before `preconditions`; `read_flag()` swallows Doppler errors to `""`.
- `apps/web-platform/infra/git-data-luks.test.sh` — predicates `p_repoint`, `p_canary_gate`, `p_prepare_luks`, `p_trap_rollback`, `p_postdrain_gate` grep the cutover script (function names, the luksOpen line, and the ORDER of the `acquire_freeze`/`delta_rsync`/`verify_set_identity`/`flip_flag_and_reload` call sites). A new call at the head of `main()` and new `gd_ssh`/`web_ssh` bodies do not match any of them.
- `.github/workflows/workspaces-luks-cutover.yml` — the precedent: workflow-level `WEB_HOST_PRIVATE_IP: "10.0.1.10"` single-sourced into `server-ip` and the Run step, plus the `Tear down cloudflared SSH bridge` step (`if: always()`, `-n`-guarded NAT delete, cloudflared kill, keyfile shred, log tail).
- `apps/web-platform/infra/workspaces-luks-cutover-workflow.test.sh`, `workspaces-luks-verify-workflow.test.sh` — the precedent test shape: parse the workflow as YAML, extract and EXECUTE `run:` bodies over stubbed `ssh`/`doppler`.
- `scripts/lint-workflow-step-env-refs.test.sh` — every uppercase var in a `run:` body must be step-`env:`-declared, `$GITHUB_ENV`-exported earlier in the job, guarded, or local.
- `apps/web-platform/infra/cloud-init.yml` `01-hardening.conf` — web-1 sshd sets no `AllowTcpForwarding` / `DisableForwarding` / `PermitOpen` / `Match` (repo-wide grep, no hit), so OpenSSH's default permits a root `direct-tcpip` channel. Unmeasured on the live host; the new transport probe measures it.
- `apps/web-platform/infra/rung2-rehearsal/rehearsal.tf` — precedent for `tls_private_key` + `hcloud_ssh_key` minted in Terraform.
- `apply-web-platform-infra.yml` `registry_host_replace` — precedent for a new credential (`doppler_secret.registry_betterstack_logs_token`, #6244) riding a replace dispatch's gate allow-set.

### External / tool verification

- OpenSSH `ssh(1)` on `-J`: "configuration directives supplied on the command-line generally apply to the destination host and not any specified jump hosts. Use ~/.ssh/config to specify configuration for jump hosts." → a `-J` with a command-line `-i` would dial web-1 without the CI key. Use an `ssh_config` file with an explicit `ProxyCommand`. <!-- verified: 2026-09-14 source: man ssh (OpenSSH_10.2p1) -->
- `ssh -G -F <cfg> 10.0.1.20` resolves `user root`, `identityfile <gd key>`, `identitiesonly yes`, `proxycommand ssh -F <cfg> -W %h:%p 10.0.1.10` with no network I/O — a deterministic, real-binary assertion for tests. <!-- verified: 2026-09-14 locally, OpenSSH_10.2p1; ubuntu-24.04 runners ship OpenSSH 9.6, -G exists since 6.8 -->
- Doppler CLI v3.75.3: absent key → rc=1, stderr `Could not find requested secret`; invalid token → rc=1, stderr `Invalid Auth token`. Exit code alone cannot discriminate; stderr substring can. <!-- verified: 2026-09-14 against prd_terraform with a nonexistent key name -->
- L3 firewall (Hetzner API, read-only): `soleur-git-data` = 0 inbound rules, attached to server 165880387 (public deny-all; the private net is not filtered by Hetzner firewalls). `soleur-web-platform` allows :22 only from admin IPs — irrelevant here because the tunnel connector dials web-1's private address locally. DNS: `ssh.soleur.ai` resolves to Cloudflare anycast (`104.26.10.163`, …).

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-07-18-shared-action-false-export-contract-and-never-run-workflow-sequential-walls.md` — a `${X:-ssh}` fallback is where a never-satisfied export contract hides; a never-run workflow reveals walls one at a time. Drives: drop the fallbacks; enumerate every wall statically (below).
- `knowledge-base/project/learnings/2026-07-18-cutover-bridge-dryrun-guard-and-workflow-step-vs-in-script-ssh.md` — the git-data dry-run is host-touching before its first `DRY_RUN` gate; the bridge must run unconditionally. Drives: keep the unguarded bridge; put the access gate before `prepare_luks_target`.
- `knowledge-base/project/learnings/2026-05-20-l3-network-fix-vs-l7-credential-fix-on-ssh-provisioner-chain.md` — close L3 and L7 separately; a timeout and `no supported methods remain` are different failures. Drives: the transport probe (banner, no credential) is separate from the auth probe.
- ADR-214 — never an env-declared test seam for a destination/credential path. Drives: tests shim `ssh`/`doppler` on `PATH`, never a `*_TEST_*` env switch in the script.

### Walls in the never-run chain (static enumeration)

1. Bridge without `server-ip` → `terraform output` with no terraform → exit 127. **Fixed here.**
2. `GIT_DATA_SSH` = web invocation, no proxy → `gd_ssh 10.0.1.20` times out naming nothing. **Fixed here.**
3. git-data root refuses the CI key (no authorized credential). **Fail-closed here with a named reason; provisioned in the follow-up.**
4. `read_flag()` AND `set_flag()` run `doppler … -c prd` under `DOPPLER_TOKEN_WRITE`, a `prd_terraform`-scoped service token (`doppler-write-token.tf` › `doppler_service_token.write`). `read_flag` swallows the error to `""`, so the "flag already true → refuse" precondition fails OPEN; `set_flag` would fail the flip and the rollback's flag-off write alike. Unreachable while wall 3 holds. **Pre-existing; filed as its own issue, blocking the follow-up (not folded — it needs a token-scope decision).**
5. `git-data-cutover.yml` drains and restarts web-1 but is in neither `web-1-swap` nor `git-data-state` concurrency groups, and holds a `ci_ssh`-authenticated session that `ci_ssh_token_replace` can invalidate mid-run. **Pre-existing; filed as its own issue, blocking the follow-up.**
6. ROLLBACK mode's `release_freeze` returns at its `DRY_RUN` guard, and the dispatch input `dry_run` defaults to `true`, so a default rollback dispatch never releases a held freeze even though the header says rollback ignores `DRY_RUN`. **Pre-existing; filed as its own issue, blocking the follow-up.**

### Related issues

#6441 (per-hostname NAT rework), #7226 (bridge host keys unverified — the jump adds a second unverified host key; tracked there), #8101 (edits `bulk_rsync`/`delta_rsync`/`canary` in the same script — disjoint functions), #6976 (empty-by-construction store), #8009 (authorization-map C1), #6604 (sibling cutover), #8179 (drift issue; incidentally shows `hcloud_firewall_attachment.inngest` drifting — the live `soleur-inngest` firewall has an empty `applied_to`; not this plan's scope, surfaced to the lead).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief / earlier draft) | Reality (measured) | Plan response |
|---|---|---|
| "Add a second tunnel ingress, OR ProxyJump through web-1" — a transport choice closes the gap | Transport is necessary, not sufficient: no CI credential is authorized for root on git-data (fingerprints above) | ADR-220 decides transport AND credential; this PR ships the transport measurement and a gate that stops at the credential boundary with a named reason |
| The bridge already exports a usable `GIT_DATA_SSH` | It exports the web-1 invocation under that name; `git-data-cutover.yml` never passes `server-ip` | Pass `server-ip`; delete the bogus export (its one consumer is `gd_ssh`) |
| `ssh -J` through web-1 | `ssh -J` does not carry a command-line `-i` to the jump hop (man ssh) | The follow-up's auth path uses an `ssh_config` `ProxyCommand ssh -F <cfg> -W %h:%p 10.0.1.10`; this PR's transport probe is `$WEB_HOST_SSH -W 10.0.1.20:22 10.0.1.10`, where web-1 IS the destination, so the existing `-i` applies |
| Address the jump as `HostName 127.0.0.1` / `Port 2222` (CTO) | For `server-ip` callers `SERVER_IP` is the input (10.0.1.10), so the NAT rule DOES match (`workspaces-luks-cutover.yml` run 29995797567 reached web-1 this way); a second route would give one host two SSH identities for #7226 to pin (architecture review) | Keep one route: 10.0.1.10 through the existing NAT rule, for both the probe and the follow-up's jump |
| Key custody separates git-data root from ci_ssh (earlier draft) | Any `tls_private_key` private half lives in `web-platform/terraform.tfstate` (architecture review). That state is readable without any reviewer: `infra-validation.yml`'s `plan` job runs `terraform plan` on PR-branch code with `prd_terraform` backend credentials (security review, verified). It already holds `tls_private_key.ci_ssh` (web-1 root) and the CF Access token, so adding a git-data root key would turn "read state" into "remote root on the store" — the LUKS passphrase comparison does not hold, because the passphrase is useless without the disk | ADR-220: the git-data root private half must NEVER be readable by a credential that reads the web-platform root state. The follow-up keeps the keypair in a separate Terraform root with its own isolated state location and credentials (held only in `prd_git_data_root`) and hands the main root only the public half (`data "hcloud_ssh_key"`) |
| A GitHub repo secret for the key (earlier draft) | AP-008 "Doppler for all secrets"; the TF GitHub App gets 403 writing environment secrets (`inngest-arm-write-token.tf`) | ADR-220: key in a dedicated Doppler config `prd_git_data_root`; read via a Doppler OIDC identity bound to the `git-data-cutover` environment where the provider supports it, else a repo-secret token with a single-reference CI lint, a `main`-only deployment policy and a mint-time expiry (security review: an `environment:` gate binds only the jobs that declare it) |
| Key destroyed after each window (CPO condition, earlier draft) | The authorized public key persists until a replace; destroying the private half would make every rotation cutover require a host replace first, which ADR-068 D10 never weighed (architecture review) | Consumer-side bound instead: the read token exists only for a cutover window; host-side revocation is the next replace. Rotation cutovers need no replace |
| Wire the key input into the bridge now (earlier draft) | Nothing can supply or exercise it until the follow-up; passing `secrets.X` from an ungated job would hand store root to any dispatch the moment the follow-up creates the secret (spec-flow P1-b) | No key input, no secret reference in this PR; the follow-up adds the secret, the `environment:` gate and the auth wiring together |
| A dry-run proves `git-data-auth ok` after the follow-up (earlier draft) | If the key reached only the reviewer-gated real-cutover mode, dry-runs could never authenticate (spec-flow P1-a) | ADR-220: the reviewer-gated environment covers every dispatch mode, so a dry-run carries the key and is the proof |
| A new `hetzner -> gitDataStore` C4 edge (earlier draft) | That edge is the web-host consumer probe; web-1 only relays TCP for CI, so a `hetzner` source would draw the "authority on web-1" design ADR-220 rejects (architecture review) | New edge `github -> gitDataStore` (transport live, credential TARGET) |

## Problem Statement

`git-data-cutover.yml` is the only automated route that moves the shared git store onto LUKS and flips
`GIT_DATA_STORE_ENABLED`; ADR-068 D10 also keeps it as the rotation route. It has never run. Statically,
its first dispatch dies at the bridge (`terraform: command not found`); past that, `gd_ssh 10.0.1.20`
dials an unroutable address and times out naming nothing; past that, git-data's sshd refuses every
credential CI holds.

## Proposed Solution

### ADR-220 decisions (provisional ordinal; re-derive at ship)

1. **Transport — jump through web-1's existing `ssh.` ingress** (issue option (b)). The runner opens a
   `direct-tcpip` channel through web-1's sshd and authenticates end-to-end to git-data; no key and no
   agent socket lands on web-1, and a compromised web-1 cannot replay the root login. One route to
   web-1 (10.0.1.10 via the existing NAT rule) for every use. **Rejected (a)** — second ingress
   `ssh-git-data.` → `ssh://10.0.1.20:22`: web-1 is the sole connector (#6425), so (a) traverses web-1
   too and buys no host independence, while adding an internet-edge SSH hostname and CF Access app for
   the store host and #6441's per-hostname bridge/port/NAT multiplexing. It satisfies ADR-114 I2; it is
   rejected on blast radius. **Rejected:** a git-data key on web-1, and agent forwarding (both make
   store root reachable from web-1 root). **Known unknown:** `-W` needs web-1's sshd to permit TCP
   forwarding — no directive in the repo (default permits it), vendor drop-in unmeasured; AC11 measures
   it before merge. If refused, the fallback (a ProxyCommand that execs a TCP relay on web-1) is a
   separate ADR amendment.
2. **Credential — a dedicated Terraform-minted root key for git-data**: `tls_private_key` →
   `hcloud_ssh_key` appended to `hcloud_server.git_data.ssh_keys` (create-time, outside the rung-2
   hash, so NOT a hash-bound edit; reaches the host only at a git-data replace) → private half in
   Doppler `prd_git_data_root` (AP-008), read by a dedicated service token published as a repo secret
   and injected only into the reviewer-gated `git-data-cutover` environment, which covers every
   dispatch mode. **Custody rule:** the private half must never be readable by any credential that reads
   the web-platform root state (that state is readable from PR-branch `terraform plan` runs and already holds
   the web-1 root key and the CF Access token). The follow-up therefore mints the keypair in a separate
   Terraform root with its own isolated state location and credentials held only in `prd_git_data_root`,
   and the main root references only the public half via `data "hcloud_ssh_key"`. **Token delivery:**
   prefer a Doppler OIDC identity bound to the `git-data-cutover` environment's `sub` (no stored secret);
   if the pinned Doppler provider cannot express it, a repo secret with (i) a CI lint that only
   `git-data-cutover.yml` references it, (ii) a `main`-only deployment policy on the environment, and
   (iii) an expiry set at mint time rather than a revoke after the soak — an `environment:` gate only
   binds jobs that declare it, while any workflow file on any branch can name a repo secret.
   **Rejected:** reusing ci_ssh (held by `apply-web-platform-infra.yml`'s TF_VAR,
   `apply-deploy-pipeline-fix.yml` and both workspaces-luks workflows); a root `ssh_authorized_keys:`,
   a 4th `git` forced-command key, or an SSH CA in the template (hash-bound, still needs a replace,
   breaks the three-key authorization-map gate); any in-place delivery to a running host — remote-exec
   from a local apply holding the personal key, Hetzner rescue, `reset_password` + console,
   `hcloud rebuild` (`hr-prod-host-config-change-immutable-redeploy`; rescue also needs the reboot
   ADR-115 bars); the personal Hetzner key copied into Doppler (a human mint, and it is root on every
   host). Born-on-LUKS is ADR-068 D10's rejected alternative, not re-litigated.
3. **Lifetime** — consumer-side: the read credential exists only for a cutover window (rehearsal, cutover
   or rotation) and expires on its own; host-side: revocation is the next replace. The #8009
   authorization accounting and PA-36 record the root authority while a token exists.
4. **Residuals, bounded** — host keys are accepted unverified on both hops (#7226): a compromised
   web-1 cannot log in to git-data but could impersonate it and receive cutover commands. Accepted only
   while #6976 holds (store empty by construction at the initial cutover); any rotation against a
   populated store is gated on #7226. git-data reach now depends on web-1's sshd and the single
   connector (ADR-114 I1); any #6441 rework must keep the jump working. **Verdicts are liveness checks,
   not authenticity checks:** a compromised web-1 can answer `-W` with a forged `SSH-2.0-` line (a false
   `git-data-jump ok`, harmless in this PR because nothing supplies `GIT_DATA_SSH`) and, once a key exists,
   could run a fake sshd that accepts any login. Pinning git-data's host key (#7226) is therefore a
   precondition for the credential decision becoming `accepted`, not just for populated-store rotation.
5. **Statuses** — the transport decision is `accepted` once AC11 measures `git-data-jump ok`; the
   credential decision is `proposed` until #7226 pins git-data's host key AND the follow-up's dry-run reads
   `git-data-auth ok`. With a `main`-only deployment policy, that proving dry-run can only run after the
   follow-up merges.
6. **Sequencing** — this PR: ADR-220, the ADR-068 D10 amendment note, the workflow/bridge/script
   wiring, the fail-closed access gate, tests, C4, runbook line. **Follow-up** (issue filed in /work
   Phase 0, milestone `Post-MVP / Later`, scheduled with the cutover rehearsal, **blocked by walls 4,
   5 and 6**): the key resources + Doppler config + token + environment, admitting them in the
   birth/replace gate allow-sets and target lockstep, #8009 C1 re-approval (CPO + CTO), PA-36 update,
   the `ssh_config` auth wiring (`IdentitiesOnly yes` + `BatchMode yes` on both blocks — both sshds
   allow 3 auth tries), and the git-data replace. Landing the key resources here would put addresses
   outside every exact-scope gate allow-set.

### What a `dry_run=true` dispatch does after this PR

```text
bridge (server-ip=10.0.1.10) → exports WEB_HOST_SSH + CI_SSH_KEYFILE (unchanged); no GIT_DATA_SSH
git-data-cutover.sh main()
  access_gate (first statement of the forward path):
    ACCESS role=web           host=10.0.1.10 verdict=ok
    ACCESS role=git-data-jump host=10.0.1.20 verdict=ok       (stdout begins SSH-2.0-; no git-data credential)
    ACCESS role=git-data-auth host=10.0.1.20 verdict=git_data_root_key_absent → exit 3, before prepare_luks_target
```

Every `ACCESS` line is mirrored as an annotation carrying only role, host and verdict. Raw ssh stderr is
logged separately with CR/LF stripped; it holds no credential.

## Technical Approach

### Verdicts (stage decides; stdout/rc decide within a stage)

| role | verdict | rule |
|---|---|---|
| `web` | `ok` / `failed` (with `rc=<n>`) / `web_roster_empty` / `web_host_ssh_unset` / `invalid_host` | `WEB_HOST_SSH` empty → `web_host_ssh_unset` (checked with `${WEB_HOST_SSH:-}` first, because a bare expansion under `set -u` kills the script with no verdict); then per `WEB_HOSTS` member: `timeout 30 $WEB_HOST_SSH -o BatchMode=yes -o ConnectTimeout=20 "$h" true`; rc 0 → ok |
| `git-data-jump` | `ok` / `failed` (with `rc=<n>`) | `timeout 25 $WEB_HOST_SSH -o BatchMode=yes -o ConnectTimeout=20 -W "$GIT_DATA_HOST:22" "$jump" </dev/null 2>"$errf" \| head -n 1`, jump = the FIRST `WEB_HOSTS` member; **ok iff the first captured line (CR stripped) begins `SSH-2.0-`, whatever the rc** (a banner followed by more output can yield 141) |
| `git-data-auth` | `ok` / `failed` (with `rc=<n>`) / `git_data_root_key_absent` | only after `web` and `git-data-jump` are both ok; `GIT_DATA_SSH` unset → key absent (nothing in the repo sets it after this PR); set → `timeout 30 $GIT_DATA_SSH -o BatchMode=yes "$GIT_DATA_HOST" true` |

Options are appended before the destination, so `WEB_HOST_SSH`'s bytes stay untouched. `timeout` is the
external binary applied to the expanded invocation, never to the `web_ssh`/`gd_ssh` shell functions.
A non-ok verdict exits 3 from `access_gate` itself (not `die`, which exits 1). `access_gate` is called as
a plain statement — never inside `$(…)` or an `||` list, where `set -e` would be suspended.
`ok` verdicts emit `::notice title=git-data-cutover access::role=<r> verdict=ok`; every other verdict emits
`::error title=git-data-cutover access::role=<r> verdict=<v>`. Only role, host and verdict reach an annotation.

**Untrusted bytes never reach the runner's command parser (security review).** The runner interprets
workflow commands on stdout AND stderr, and every byte a probe returns (the `-W` first line, a pre-login
`Banner`, ssh's stderr) is chosen by the edge or web-1 once host keys are unverified. So: every probe's
stdout and stderr go to files, never the terminal; the `-W` first line is only compared, never printed; a
failed probe's stderr is printed only between `::stop-commands::<per-run random token>` and `::<token>::`,
after `LC_ALL=C tr -cd '\40-\176'` and behind a fixed `[git-data-cutover] probe-stderr:` prefix. The
script also appends the three verdict lines to `$GITHUB_STEP_SUMMARY` when that variable is set.

**Argument hygiene.** `WEB_HOST_SSH` / `GIT_DATA_SSH` are split once with `read -ra` into arrays (no glob
expansion); every `WEB_HOSTS` member and `GIT_DATA_HOST` must match `^[0-9.]+$` before use, so a value
beginning with `-` can never become an ssh option (`-oProxyCommand=…` would execute on the runner);
violations are verdict `invalid_host`. ssh keeps the FIRST value of a repeated `-o`, so the appended
`BatchMode`/`ConnectTimeout` can add but never override an option the bridge already set. Each probe's
capture uses `out=$(…) || rc=$?`, so a non-zero pipeline rc can never trip `set -e` on a success path.

#### Research Insights (deepen-plan 2026-09-15)

- **The probe form is measured, not assumed.** In a throwaway `ubuntu:24.04` container (OpenSSH 9.6p1, the
  GitHub `ubuntu-24.04` runner's version) with three local sshds: allowing-jump → `SSH-2.0-OpenSSH_9.6p1…`
  as the first line in ~0 s with `</dev/null` stdin, **20/20 runs** (no stdin-EOF race), rc 0 even under
  `pipefail`; `AllowTcpForwarding no` → empty line + stderr `channel 0: open failed: administratively
  prohibited: open failed`; closed target → empty line + `channel 0: open failed: connect failed: Connection
  refused`; jump key refused → empty line + `root@127.0.0.1: Permission denied (publickey).` All non-ok
  shapes yield an empty first line, so the banner rule discriminates without parsing stderr.
- **Precedent-diff (Phase 4.4).** No `ssh -W` banner probe exists in the repo — the pattern is novel. Nearest
  precedents: `workspaces-luks-verify.yml` bounds every call by appending
  `-o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=4` to `WEB_HOST_SSH` (same
  append-options shape adopted here); `web-git-data-probe.sh` proves web-1 → 10.0.1.20:22 with a TCP
  connect-and-close from ON the host (it cannot prove web-1's sshd permits forwarding, which is the new
  fact this probe measures); `git-data-ownership.test.sh` runs a real sshd in a pinned `ubuntu:24.04`
  image with a CI-required runtime arm — the precedent for Guard 1's runtime rows R1–R4.

### Files to Edit

- `.github/actions/cf-tunnel-ssh-bridge/action.yml` — in the "Decode CI SSH private key" step's
  `server-ip` branch, delete the `GIT_DATA_SSH=` export line; update the `server-ip` input description
  and the OUTPUTS header so neither names `GIT_DATA_SSH`. No other change; the liveness gate stays the
  last step.
- `.github/workflows/git-data-cutover.yml`
  - workflow `env:` gains `WEB_HOST_PRIVATE_IP: "10.0.1.10"` (single source, as in
    `workspaces-luks-cutover.yml`);
  - bridge `with:` gains `server-ip: ${{ env.WEB_HOST_PRIVATE_IP }}`; Run step `env:` gains
    `WEB_HOSTS: ${{ env.WEB_HOST_PRIVATE_IP }}`;
  - new `Tear down cloudflared SSH bridge` step (`if: always()`) placed after the Run step and before
    `Cutover summary`, copied from `workspaces-luks-cutover.yml`;
  - header "Reach model" rewritten: the jump, the credential boundary, ADR-220, and that no secret for
    git-data is referenced until the follow-up adds the reviewer-gated environment; the "Inngest-dispatches-GHA"
    paragraph is corrected — no such Inngest function exists (`git grep` over `apps/web-platform/server` finds
    none), and a scheduled dispatcher would need a Sentry-mirrored alarm like `workspaces-luks-verify.yml`'s.
- `apps/web-platform/infra/git-data-cutover.sh`
  - `gd_ssh`/`web_ssh`: drop the `:-ssh` fallbacks; when the invocation is unset, print `…_SSH unset`
    to stderr and return 97;
  - new `access_gate` per the verdict table, called as the FIRST statement of the forward path in
    `main()`; the remedy line for `git_data_root_key_absent` names ADR-220 and the follow-up issue
    number (not the ADR ordinal alone, so a renumber touches docs only);
  - ROLLBACK branch unchanged in order (`set_flag false` needs no SSH and must never wait on a probe);
    its SSH calls now fail closed through the existing `|| log "WARNING…"` arms, each of which also emits
    `::warning title=git-data-cutover recovery::step=<name> rc=<n>` so a partial rollback is visible in the
    annotations API;
  - "INVOCATION BOUNDARY" header comment updated.
- `.github/workflows/infra-validation.yml` — register the new suite beside the workspaces-luks workflow suites.
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` — dated amendment note under D10: the access path and root credential are decided in ADR-220, and rotation cutovers inherit its lifetime rule (no replace per rotation).
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` — one line in the dry-run step: until the ADR-220 follow-up lands, the dry-run stops at `git-data-auth verdict=git_data_root_key_absent` by design.
- `knowledge-base/engineering/architecture/diagrams/model.c4` (+ `views.c4` include only if the new edge does not render) — see ADR/C4.

### Files to Create

- `apps/web-platform/infra/git-data-cutover-access.test.sh` — Guard 1 + Guard 2 suite.
- `knowledge-base/engineering/architecture/decisions/ADR-220-git-data-root-access-via-web-1-jump-and-a-dedicated-terraform-minted-key.md` — via `/soleur:architecture` (ordinal provisional).

### Implementation Phases

#### Phase 0 — Preconditions (no code)

1. Re-derive the ADR ordinal across every pushed ref (`for r in $(git for-each-ref --format='%(refname)' refs/remotes/origin); do git ls-tree -r --name-only "$r" -- knowledge-base/engineering/architecture/decisions; done | grep -oE 'ADR-[0-9]+' | sort -t- -k2 -n -u | tail -1`); 219 was the max on 2026-09-14.
2. File four issues (labels verified: `domain/engineering`, `type/security`, `priority/p2-medium`; milestone `Post-MVP / Later`):
   - **Follow-up**: "git-data root access (ADR-220): Terraform-minted root key in a separate root, Doppler `prd_git_data_root` + environment-bound read credential, reviewer-gated environment, gate allow-sets, #8009 C1 re-approval, replace git-data" — body: the decision list above incl. the custody rule (private half never readable by web-platform-state readers; the separate root needs its own R2 backend per `hr-every-new-terraform-root-must-include-an`) and OIDC-first token delivery, "blocked by walls 4–6", "#7226 host-key pinning is a precondition for the credential decision becoming accepted", PA-36 update (gdpr-gate Art. 32 suggestion), the note that once the key lands a dry-run is no longer non-mutating (it runs `luksOpen`, mount, `rsync --delete` into FRESH), and the CPO ask to assert store emptiness at run time before a first cutover.
   - **Wall 4**: "git-data-cutover.sh reads and writes Doppler prd under a prd_terraform-scoped token — read_flag() fails open and set_flag() cannot flip or roll back".
   - **Wall 5**: "git-data-cutover.yml drains and restarts web-1 but serializes against neither web-1-swap nor git-data-state".
   - **Wall 6**: "git-data-cutover.sh ROLLBACK never releases a held freeze on a default (dry_run=true) dispatch".

#### Phase 1 — Tests first (RED)

Write `git-data-cutover-access.test.sh` from the Guard Contract (unit rows over the `$TL` timeline, the H5 structural check, and the docker runtime arm R1–R4 with the pinned `UBUNTU_BASE` from `git-data-ownership.test.sh`); confirm the behavioral cases fail against `origin/main`'s bytes. Save the runtime arm's real stderr as the shim fixtures.

#### Phase 2 — Script

`gd_ssh`/`web_ssh`, `access_gate`, `main()`. Run the new suite + `git-data-luks.test.sh`.

#### Phase 3 — Bridge + workflow

The one-line export delete + header; workflow env, `with:`, Run `env:`, teardown, header. Run the new suite, `scripts/check-cloudflare-token-drift.test.sh`, `scripts/cf-tunnel-liveness-gate-mutations.test.sh`, `workspaces-luks-cutover-workflow.test.sh`, `workspaces-luks-verify-workflow.test.sh`, `workspaces-luks-header.test.sh`, `web-1-swap-concurrency-parity.test.sh`, `bash scripts/lint-workflow-step-env-refs.test.sh`, `actionlint .github/workflows/git-data-cutover.yml`, `bun test plugins/soleur/test/terraform-target-parity.test.ts`.

#### Phase 4 — Live transport measurement (read-only, before review)

Push, then dispatch the BRANCH's workflow (AC11) and arm a watch in the same turn (`hr-dispatch-async-must-arm-watch`). `git-data-jump failed` halts the PR for the fallback-transport amendment.

#### Phase 5 — ADR, ADR-068 note, runbook, C4

`/soleur:architecture` for ADR-220; C4 edit; `apps/web-platform/test/c4-code-syntax.test.ts`, `apps/web-platform/test/c4-render.test.ts`, `bash plugins/soleur/test/c4-count-parity.test.sh`; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.

#### Phase 6 — Invariance proofs

AC9; `git merge-tree --write-tree origin/main HEAD` clean before review and before `gh pr ready`.

## Alternative Approaches Considered

| Option | Buys | Decisive reason not chosen |
|---|---|---|
| (a) second ingress `ssh-git-data.` + second Access app + second bridge redirect | an edge-addressable store sshd | traverses web-1 anyway (sole connector); a public SSH hostname for the store host; #6441 multiplexing |
| `ssh -J` with the jump on the command line | shorter invocation | the jump hop ignores the command-line `-i` |
| jump via `127.0.0.1:2222` | skips the NAT rule | two SSH identities for one host under #7226; the NAT rule already matches for `server-ip` callers |
| git-data key on web-1 / agent forwarding | no runner-side proxy | store root reachable from web-1 root |
| reuse ci_ssh as the git-data root key | no new secret | ci_ssh reaches four workflows incl. a TF_VAR in every infra apply |
| root key in `cloud-init-git-data.yml` / 4th forced-command key / SSH CA | no Hetzner key object | hash-bound (re-holds rung-2), still needs the replace, breaks the three-key map gate |
| in-place key delivery (remote-exec, rescue, reset_password console, rebuild) | no replace | `hr-prod-host-config-change-immutable-redeploy`; ADR-115 |
| personal Hetzner key in Doppler | works today | a human mint; root on every host |
| GitHub repo secret holding the key | fewer moving parts | AP-008; any workflow on any branch can name a repo secret |
| keypair in the web-platform root state | one root, simplest Terraform | that state is readable by PR-branch `terraform plan` runs and already holds the web-1 root key + CF Access token, so it would become remote root on the store |
| destroy the key after each window | strongest bound | every rotation would need a host replace first; state versions and the authorized public key persist anyway |
| born-on-LUKS (no cutover SSH) | removes the need | ADR-068 D10 decision; rotation still needs the cutover |
| key input + `ssh_config` writer in this PR | follow-up is Terraform only | dead and untestable until the secret exists; an ungated secret reference would arm itself when the follow-up creates it |

## User-Brand Impact

- **If this lands broken, the user experiences:** (1) nothing directly while `GIT_DATA_STORE_ENABLED` stays off — the cutover stays blocked; (2) if the shared bridge edit regresses, `apply-web-platform-infra.yml` SSH applies, `apply-deploy-pipeline-fix.yml`, `workspaces-luks-cutover.yml` and the daily `workspaces-luks-verify.yml` (the evidence behind the published Article 32 LUKS claim for every user's workspace) stop — deploys and infra fixes for all users stall and the at-rest claim loses its daily verification.
- **If this leaks, the user's data is exposed via:** (1) the future git-data root key — root on the store holding every connected user's source code; (2) one compromise of CI secrets or Terraform state yielding both the web-1 route and the store key — closed by the custody rule (the private half lives outside the web-platform root state, which PR-branch plan runs can read) plus a window-scoped, environment-bound read credential; (3) an unverified git-data host key letting a compromised web-1 receive cutover traffic (accepted only while #6976 holds; #7226 gates any populated-store rotation).
- **Brand-survival threshold:** `single-user incident`

CPO sign-off (plan time, 2026-09-14): **yes**, with conditions — unchanged consumed exports for all four bridge callers (P5), key custody outside `prd_terraform`, a bounded key lifetime, C1 re-approval in the follow-up. The lifetime condition is met as a window-scoped read token plus revocation at replace (the architecture review showed per-window key destruction would force a replace before every rotation). `user-impact-reviewer` runs at review.

## Observability

```yaml
liveness_signal:
  what: "Conclusion of the dispatch-only git-data-cutover.yml run plus one ACCESS annotation per role (web, git-data-jump, git-data-auth)"
  cadence: "per dispatch (workflow_dispatch only, no schedule)"
  alert_target: "the dispatching session's armed watch on the run; a stopped run carries a named ::error:: annotation"
  configured_in: "apps/web-platform/infra/git-data-cutover.sh access_gate + .github/workflows/git-data-cutover.yml"
error_reporting:
  destination: "GitHub Actions annotations and run log (the job runs off-host on a runner with no Sentry client)"
  fail_loud: "::error title=git-data-cutover access::role=<role> verdict=<verdict> and exit 3 before any host-mutating step"
failure_modes:
  - mode: "cloudflared forward down or CF Access rejects ci_ssh"
    detection: "the bridge's existing liveness gate (ci_ssh_access_denied / ci_ssh_liveness_unverifiable), or role=web verdict=failed with its rc and logged stderr"
    alert_route: "layer 6: workflow run log + ::error:: annotation (the bridge's own ::error:: lines for forward/NAT/liveness failures)"
  - mode: "web-1 refuses the CI key"
    detection: "role=web verdict=failed rc=255, stderr line logged"
    alert_route: "layer 6: workflow run log + ::error:: annotation"
  - mode: "web-1 sshd refuses direct-tcpip, or git-data sshd unreachable from web-1"
    detection: "role=git-data-jump verdict=failed (no SSH-2.0- banner), stderr line logged"
    alert_route: "layer 6: workflow run log + ::error:: annotation; halts the PR at AC11"
  - mode: "root key not provisioned (expected until the follow-up)"
    detection: "role=git-data-auth verdict=git_data_root_key_absent"
    alert_route: "layer 6: workflow run log + ::error:: annotation naming ADR-220 and the follow-up issue"
  - mode: "a key is supplied but not authorized on the host"
    detection: "role=git-data-auth verdict=failed rc=255, reachable only after git-data-jump=ok"
    alert_route: "layer 6: workflow run log + ::error:: annotation"
  - mode: "WEB_HOST_SSH not exported (bridge regression)"
    detection: "role=web verdict=web_host_ssh_unset"
    alert_route: "layer 6: workflow run log + ::error:: annotation"
  - mode: "malformed roster or invocation input"
    detection: "role=web verdict=invalid_host / invalid_multiline_input / web_roster_empty, or role=git-data-jump verdict=invalid_host; exit 3 before any probe dials"
    alert_route: "layer 6: workflow run log + ::error:: annotation"
  - mode: "jump probe hangs (edge, web-1 or git-data sshd stalls)"
    detection: "role=git-data-jump verdict=failed rc=124 reason=timeout; other failed verdicts carry reason=forward_refused / connect_refused / no_route / auth_refused / unknown"
    alert_route: "layer 6: workflow run log + ::error:: annotation"
  - mode: "rollback incomplete (a recovery step could not run)"
    detection: "::warning title=git-data-cutover recovery::step=<set_flag|web_restart|web_roster|freeze_sentinel_rm|web_undrain> rc=<n> per failed step, and the ROLLBACK-only run exits 4 (red)"
    alert_route: "layer 6: workflow run log + ::warning:: annotations + failed job conclusion"
logs:
  where: "GitHub Actions run log for git-data-cutover.yml"
  retention: "the repository's Actions log retention setting (GitHub default 90 days)"
discoverability_test:
  command: 'curl -sf --max-time 15 "https://api.github.com/repos/jikig-ai/soleur/actions/workflows/git-data-cutover.yml/runs?per_page=1"'
  expected_output: "git-data-cutover.yml"
  verdict_read: "Fail-closed by construction: curl -f exits non-zero on any HTTP error, and a workflow with zero runs returns no git-data-cutover.yml path, so the match fails. Preflight Check 10 bars pipes, $ and gh, so the verdict read is a second step: take .workflow_runs[0].id from that response, the job id from gh run view <run-id> --json jobs --jq '.jobs[0].databaseId', then gh api repos/jikig-ai/soleur/check-runs/<job-id>/annotations --jq '.[].message'. Until #8189 it lists role=web verdict=ok, role=git-data-jump verdict=ok, role=git-data-auth verdict=git_data_root_key_absent. host= values are not read, because the bridge add-masks 10.0.1.10."
```

## Encryption Posture

```yaml
at_rest:
  - store: "none introduced by this PR — no secret, key or config file is added; the pre-existing chmod-600 CI keyfile on the ephemeral runner is shredded by the new if:always() teardown. The follow-up that creates Doppler prd_git_data_root carries its own at_rest row."
    mechanism: "not-applicable: no persistent store"
    evidence: ".github/actions/cf-tunnel-ssh-bridge/action.yml:CALLER-SIDE TEARDOWN CONTRACT"
    defends_against: "key material outliving the job on a persistent runner"
    does_not_defend: "a malicious step in the same job reading the keyfile while the job runs; a compromised runner image"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable: ephemeral runner filesystem"
in_transit:
  - connection: "runner cloudflared -> Cloudflare edge (ssh. hostname)"
    enforced_at: ".github/actions/cf-tunnel-ssh-bridge/action.yml:cloudflared access tcp"
    tls: "TLS 1.2+ (cloudflared default) with CF Access service-token auth"
    cert_verification: "on"
    does_not_defend: "Cloudflare itself, or a holder of the ci_ssh Access token, observing or redirecting the stream at the edge"
    disclosed_as: "not-publicly-claimed"
  - connection: "runner -> web-1 sshd 10.0.1.10:22 (NAT-redirected into the tunnel); the git-data jump rides this session as a direct-tcpip channel carrying only git-data's SSH banner in this PR"
    enforced_at: ".github/actions/cf-tunnel-ssh-bridge/action.yml:WEB_HOST_SSH"
    tls: "SSH-2 (OpenSSH defaults), public-key user auth"
    cert_verification: "off"
    does_not_defend: "an actor at the edge or on web-1 presenting a different host key (accept-new with /dev/null known_hosts)"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "Host keys are unverifiable today (TOFU with no persistence, pre-existing in the bridge); the new jump carries no credential and no user data in this PR, and the follow-up's root session is bounded by #6976 (store empty by construction at the initial cutover)"
  tracking_issue: "#7226"
  reevaluate_when: "before the follow-up authenticates to git-data, before any rotation cutover against a populated store, or when #7226 pins host keys"
  expires_on: "2026-12-13"
```

## Guard Contract

### Guard 1 — the access gate precedes every host mutation on the forward path

**Property.** In a forward (non-ROLLBACK) run of `git-data-cutover.sh`, no remote command other than the access probes reaches any host unless `web` (every roster member), `git-data-jump` and `git-data-auth` returned `ok` in that order; in a ROLLBACK run the probes never delay or prevent the flag-off write; and no byte a probe returns can reach the runner's workflow-command parser unsanitized.

**Assembly.** Every remote dial flows through three chokepoints: `web_ssh()`, `gd_ssh()`, and the probe invocations inside `access_gate()` (arrays split from `$WEB_HOST_SSH` / `$GIT_DATA_SSH`). Their callers: `main()`'s forward path (`prepare_luks_target` … `old_volume_wipe`), `main()`'s ROLLBACK branch (`rollback`, `release_freeze`), and the EXIT trap `cleanup()`. Roster: `WEB_HOSTS` (a list) + `GIT_DATA_HOST`. The suite observes through ONE timeline file `$TL`: `PATH` shims for `ssh`, `doppler` and a pass-through `timeout` each append their argv to `$TL`, so probe calls (recognizable by `true` / `-W` argv) and mutating calls (`cryptsetup`, `mountpoint`, `rsync`, `systemctl`, `secrets set`) are ordered within a single stream. Forward-path cases run with `GIT_DATA_SSH` SET unless the case is about its absence, so a mis-ordered gate visibly sends `prepare_luks_target`'s remote through the shim. The shim refuses an empty destination. A second, structural assembly member is `main()`'s text: the gate's call site and its `exit 3`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `access_gate` call from `main()` (`GIT_DATA_SSH` set, auth scripted to refuse) | RED — `$TL` gains a `cryptsetup`/`mountpoint` remote and the run does not exit 3 |
| 2 | REORDER: move `access_gate` after `prepare_luks_target` | RED — in `$TL` a `cryptsetup` remote precedes the web probe line |
| 3 | Own dispatch: delete the empty-roster branch (`WEB_HOSTS=""`) | RED — the run must exit 3 with `role=web verdict=web_roster_empty`, not reach the jump through an empty destination |
| 4 | Second member: iterate only the first roster member (`WEB_HOSTS="10.0.1.10 10.0.1.11"`, second refuses) | RED unless the run exits 3 with `host=10.0.1.11 verdict=failed` |
| 5 | Re-introduce `${WEB_HOST_SSH:-ssh}` or `${GIT_DATA_SSH:-ssh}` (ROLLBACK=1, DRY_RUN=0, both unset) | RED — `$TL` gains an `ssh` line without the fixture's `-i` marker |
| 6 | Run the auth probe before the jump probe (key set, jump scripted to fail) | RED — the verdict must be `role=git-data-jump verdict=failed`; no auth-probe line in `$TL` |
| 7 | Key the jump verdict on rc instead of the first-line banner (scenario: banner then extra output, rc 141) | RED — must read `verdict=ok` |
| 8 | Call `access_gate` from the ROLLBACK branch before `rollback` (web scripted to refuse) | RED — `$TL` must contain the `secrets set GIT_DATA_STORE_ENABLED false` line, and it must precede every `ssh` line |
| 9 | Print the `-W` first line or raw probe stderr to stdout (shim stderr contains `::error title=git-data-cutover access::role=git-data-jump verdict=ok`) | RED — no line of script output may start with `::error`/`::notice`/`::add-mask`/`::stop-commands` except the script's own verdict annotations, and the forged text must appear only inside the stop-commands span with `::` intact-but-inert |
| 10 | Jump dials the LAST roster member | RED — the `-W` line in `$TL` must target the first member |

**Harness rows:**

| # | Suite edit / input | Expected |
|---|---|---|
| H1 | Suite edit: the `ssh` shim ignores its scenario and always exits 0 with a banner | rows 1, 4, 6 go RED |
| H2 | Suite edit: the shims stop appending to `$TL` | rows 1, 2, 5, 8, 10 go RED (each case asserts ≥1 `$TL` line) |
| H3 | must-PASS, non-canonical: two-host roster, all probes ok, key set, `DRY_RUN=1`, banner ending `\r\n` | passes the gate; in `$TL` the `prepare_luks_target` remote follows the two web probes, the jump and the auth probe |
| H4 | Suite floor: fail on `0 passed` or fewer cases than declared; under `CI=true` a skipped runtime arm is a failure | an emptied case list or a missing docker goes RED |
| H5 | Structural: extract `main()` (comments stripped); after the ROLLBACK `fi`, the first statement other than `log` must match `^[[:space:]]*access_gate[[:space:]]*$`; exactly one `access_gate` call outside its definition; the definition contains `exit 3` and no `return 3` | adding `\|\| true`, `$(…)`, `if !` or a second call site goes RED |

**Runtime arm (real OpenSSH, `git-data-ownership.test.sh` precedent: same pinned `UBUNTU_BASE`, CI-required).** One container, three sshds with a synthesized key: a "web" sshd allowing forwarding on `127.0.0.1:2201`, a "web" sshd with `AllowTcpForwarding no` on `127.0.0.1:2202`, and a "git-data" sshd on `127.0.0.2:22` (the script dials port 22); `WEB_HOST_SSH` carries `-p`. R1: allowing sshd, `GIT_DATA_SSH` unset → exit 3, `jump ok`, `auth git_data_root_key_absent`, elapsed under 20 s (bounded, not pinned). R2: `AllowTcpForwarding no` → `jump failed`; the captured stderr is saved as the shim fixture text for the unit rows. R3: git-data sshd stopped → `jump failed`. R4 (negative control): a non-SSH listener on `127.0.0.2:22` → `jump failed`.

### Guard 2 — the bridge's `server-ip` export set

**Property.** The bridge's "Decode CI SSH private key" step exports exactly `{CI_SSH_KEYFILE, WEB_HOST_SSH}` on the `server-ip` branch (with `WEB_HOST_SSH` byte-equal to its pre-change value) and exactly `{TF_VAR_ci_ssh_private_key}` on the terraform branch.

**Assembly.** One writer: that step's `run:` body in `.github/actions/cf-tunnel-ssh-bridge/action.yml`. The suite extracts it by YAML parse, executes it once per branch with a `PATH`-shimmed `doppler` returning a synthesized ed25519 key (`ssh-keygen` in scratch, `cq-test-fixtures-synthesized-only`), captures `$GITHUB_ENV` to a temp file, parses NAMES from both `NAME=value` and `NAME<<DELIM` heredoc forms, and compares the name set and the `WEB_HOST_SSH` value.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore the `GIT_DATA_SSH=` export | RED — name set differs |
| 2 | Own dispatch: rename the step so extraction finds zero bodies | RED — "extracted 0 run bodies", never a pass |
| 3 | Second member: add any other export after `WEB_HOST_SSH` | RED — name set differs |
| 4 | Change one option inside `SSH_INVOCATION` | RED — `WEB_HOST_SSH` value differs |
| 5 | Swap `CI_SSH_KEYFILE` for `GIT_DATA_SSH` (same count) | RED — name set differs |

**Harness rows:**

| # | Suite edit / input | Expected |
|---|---|---|
| H1 | Suite edit: the name parser ignores heredoc-form exports | the terraform-branch case goes RED (its only export is heredoc-form) |
| H2 | must-PASS, non-canonical: a different synthesized key and a `RUNNER_TEMP`-style temp root | PASS |

## Architecture Decision (ADR/C4)

### ADR

- **Create ADR-220** (provisional ordinal; `/ship`'s ordinal-collision gate re-verifies; a renumber sweeps this plan, `tasks.md` and the runbook line): decisions 1–6 above with separate statuses (transport `accepted` after AC11; credential `proposed`), the rejected table, the residuals, the AP-008-compliant custody, and the web-1/connector dependency.
- **Amend ADR-068** with a dated note under addendum D10: the access path and credential are ADR-220's; rotation cutovers inherit its window-scoped token rule and need no replace.

### C4 views

All three model files were checked (`model.c4`, `views.c4`, `spec.c4`) for the actors, systems and relationships this decision touches:
- **External systems/actors:** GitHub Actions (`github`), Cloudflare Tunnel (`tunnel`), the web cluster (`hetzner`), the git-data store (`gitDataStore`) — all modeled; no new element.
- **Relationships:** `github -> tunnel` describes CI reaching web-1's shell; `hetzner -> gitDataStore` is the web-host consumer probe; nothing models CI → git-data. Add `github -> gitDataStore` "cutover SSH via the ssh. tunnel and a web-1 direct-tcpip channel — transport LIVE (banner probe), root credential TARGET until the ADR-220 follow-up" (technology "SSH"). Add the edge to whichever view already includes both `github` and `gitDataStore`; if none renders it, add the include line in `views.c4`. No count embedded in edge prose changes.
- Validation: `apps/web-platform/test/c4-code-syntax.test.ts`, `apps/web-platform/test/c4-render.test.ts`, `plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

ADR-220 lands now; the follow-up flips the credential decision to `accepted` when a dry-run reports `git-data-auth verdict=ok`.

## Infrastructure (IaC)

### Terraform changes

None in this PR (AC9). The follow-up's set, recorded so it is not re-derived: in a SEPARATE Terraform root with its own isolated state location and credentials (custody rule) — `tls_private_key.git_data_root_ssh` (ED25519) and `hcloud_ssh_key.git_data_root`; in the web-platform root — a `data "hcloud_ssh_key"` lookup appended to `hcloud_server.git_data.ssh_keys`, `doppler_config.git_data_root` (`prd_git_data_root`), `doppler_secret.git_data_root_ssh_private_key`, a window-scoped `doppler_service_token` published by `github_actions_secret`, `github_repository_environment.git_data_cutover` (+ deployment policy on `main`). No sensitive variable, no human mint.

### Apply path

This PR: none. The new suite lives under `apps/web-platform/infra/`, so `apply-web-platform-infra.yml`'s push trigger fires on merge; its target-scoped plan must report no changes for this diff (read from the post-merge run). Follow-up: the `git-data-host-replace` dispatch with the new resources admitted in its gate allow-set and created in that dispatch (the #6244 registry precedent).

### Distinctness / drift safeguards

`ignore_changes = [ssh_keys]` stays — the key reaches only a replaced host. The key lives in neither `prd_git_data` (the host's own boot config, which must never hold a credential that authenticates TO the host) nor `prd_terraform`.

### Vendor-tier reality check

The Terraform GitHub App cannot write GitHub environment secrets (403, `inngest-arm-write-token.tf`); the follow-up publishes the token as a repo secret behind a reviewer-gated `environment:`.

## Hypotheses

(Network-outage checklist applies: an SSH reachability change.)

| Layer | Status | Artifact |
|---|---|---|
| L3 firewall | verified | Hetzner API: `soleur-git-data` 0 inbound rules (public deny-all), attached; the private 10.0.1.0/24 net is not filtered by Hetzner firewalls; git-data nftables drops only non-root egress to 169.254.169.254; web-1's `cron-egress-nftables.sh` hooks `DOCKER-USER` only |
| L3 DNS / routing | verified | `dig +short ssh.soleur.ai` → Cloudflare anycast; the runner never routes to 10.0.1.0/24 — the NAT rule sends 10.0.1.10:22 into the cloudflared forward |
| L7 TLS/proxy | verified by existing gate | the bridge's last step asserts CF Access admits the ci_ssh token before any SSH |
| L7 application (sshd) | measured by the new probes (no SSH-based diagnosis) | web auth, git-data banner via `-W`, git-data auth |

H1 (expected): web ok, jump ok, auth `git_data_root_key_absent`. H2: jump failed with "administratively prohibited" — a vendor drop-in forbids forwarding on web-1; the fallback transport amendment. H3: jump failed with a channel-open timeout — git-data's private NIC down (#6416 class).

### Network-Outage Deep-Dive (deepen-plan 4.5)

| Layer | Verified? | Artifact / gap |
|---|---|---|
| L3 firewall | yes | Hetzner API read 2026-09-14 (`soleur-git-data` 0 inbound, attached); the runner's egress IP is irrelevant — both hops ride the CF tunnel, and web-1 → 10.0.1.20 is private-net traffic Hetzner firewalls do not filter |
| L3 DNS/routing | yes | `ssh.soleur.ai` → Cloudflare anycast; iptables OUTPUT redirect scoped to 10.0.1.10:22 (bridge `server-ip`) |
| L7 TLS/proxy | yes (existing gate) | the bridge's final step proves CF Access admits `ci_ssh` before any SSH |
| L7 application | measured in-container; live measurement = AC11 | OpenSSH 9.6p1 stderr shapes recorded under Technical Approach; no SSH-based diagnosis is prescribed |

## Open Code-Review Overlap

None (`gh issue list --label code-review --state open` bodies checked for the bridge, workflow, script, ADR-068 and runbook paths). Acknowledged non-code-review overlap: #8101 edits `bulk_rsync`/`delta_rsync`/`canary_luks_device` in the same script (disjoint functions); #7226 owns host-key pinning.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `bash apps/web-platform/infra/git-data-cutover-access.test.sh` exits 0, prints its declared case count with `0 failed`, its cases cover every Guard 1 and Guard 2 row and Test Scenarios 1–17, and under `CI=true` the runtime arm ran (not skipped); Phase 1 recorded each behavioral case RED against `origin/main`'s bytes.
- [ ] **AC2** Canonical dry-run case (web ok, banner printed, `GIT_DATA_SSH` unset): exit 3; the last `ACCESS` line is `role=git-data-auth host=10.0.1.20 verdict=git_data_root_key_absent`; `$TL` holds exactly the web probe and the jump probe (`apps/web-platform/infra/git-data-cutover.sh › access_gate`).
- [ ] **AC3** Key-present refusal case (`GIT_DATA_SSH` set, auth scripted rc=255): exit 3 with `role=git-data-auth verdict=failed rc=255`, and no `cryptsetup`/`mountpoint`/`rsync` remote in `$TL`.
- [ ] **AC4** The bridge export sets and `WEB_HOST_SSH` value match Guard 2's property for both branches (`.github/actions/cf-tunnel-ssh-bridge/action.yml › Decode CI SSH private key`).
- [ ] **AC5** `grep -nE '_SSH:?[-=]ssh\}' apps/web-platform/infra/git-data-cutover.sh` returns no line (covers `:-`, `-`, `:=`, `=` fallback forms; the behavioral half is Guard 1 row 5).
- [ ] **AC6** Parsed as YAML, `git-data-cutover.yml`'s bridge step has `with.server-ip == '${{ env.WEB_HOST_PRIVATE_IP }}'` and no `if:`; the Run step's `env.WEB_HOSTS == '${{ env.WEB_HOST_PRIVATE_IP }}'`; a `Tear down cloudflared SSH bridge` step with `if: always()` comes after the Run step; no step references a `secrets.*` name other than `DOPPLER_TOKEN` and `DOPPLER_TOKEN_WRITE`.
- [ ] **AC7** `bash scripts/check-cloudflare-token-drift.test.sh` and `bash scripts/cf-tunnel-liveness-gate-mutations.test.sh` exit 0 (the liveness gate is still the bridge's last step; call-site count unchanged).
- [ ] **AC8** These unchanged suites stay green: `git-data-luks.test.sh`, `workspaces-luks-cutover-workflow.test.sh`, `workspaces-luks-verify-workflow.test.sh`, `workspaces-luks-header.test.sh`, `web-1-swap-concurrency-parity.test.sh`, `scripts/lint-workflow-step-env-refs.test.sh`, `bun test plugins/soleur/test/terraform-target-parity.test.ts`; `actionlint .github/workflows/git-data-cutover.yml` exits 0.
- [ ] **AC9** `git diff --stat origin/main -- apps/web-platform/infra/cloud-init-git-data.yml apps/web-platform/infra/modules/git-data-userdata apps/web-platform/infra/git-data-rung2-boot-evidence.env 'apps/web-platform/infra/*.tf'` is empty, and `bash apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` still reports RELEASED `5c50797be8392fe551a940ae04555c52a3f4409cf249ed11bb1280fec783d5b1`.
- [ ] **AC10** The suite is registered: parsed `infra-validation.yml` has a step whose `run` equals `bash apps/web-platform/infra/git-data-cutover-access.test.sh`.
- [ ] **AC11** Live transport measurement: after AC1–AC3 pass on the pushed branch, `gh workflow run git-data-cutover.yml --ref feat-one-shot-6680-git-data-cutover-access-path -f confirm=CUTOVER-GIT-DATA -f dry_run=true -f rollback=false -f confirm_wipe=false` (the branch's workflow and action bytes; non-mutating because the gate precedes every mutating step and nothing supplies `GIT_DATA_SSH`) is watched to completion, and its log shows `role=web … verdict=ok`, `role=git-data-jump … verdict=ok`, `role=git-data-auth … verdict=git_data_root_key_absent` as script-emitted `[git-data-cutover] ACCESS` lines (the only place those tokens can appear, because probe output never reaches the parser unsanitized), matched on `role=`/`verdict=` only (the bridge add-masks 10.0.1.10, so `host=` may render as `***`). Any other result halts the PR. If the workflow, bridge or script bytes change after this run, it is repeated.
- [ ] **AC12** ADR-220 exists with decisions 1–6, the rejected table and the #7226/#6976 residual; ADR-068 carries the dated D10 note; the four Phase 0 issues exist and the script's remedy line cites the follow-up number.
- [ ] **AC13** The C4 tests pass with the new `github -> gitDataStore` edge; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0.
- [ ] **AC14** The PR body uses `Ref #6680` (not `Closes`), states that merging applies no infrastructure, and names the follow-up issue.

### Post-merge (automated)

- [ ] **AC15** The merge-triggered `apply-web-platform-infra.yml` run reports no resource changes for this diff (read from its log); `#6680` stays open until the follow-up's dry-run reads `git-data-auth verdict=ok`.

## Test Scenarios

### Acceptance tests (RED phase targets)

1. Canonical dry-run, `GIT_DATA_SSH` unset, banner printed → exit 3, `git_data_root_key_absent`, `$TL` holds exactly the web probe and the jump probe.
2. Key set, jump ok, auth rc=255 → exit 3, `git-data-auth verdict=failed rc=255`, no mutating remote.
3. Key set, jump returns no banner (fixture stderr captured by runtime R2) → `git-data-jump verdict=failed`; no auth probe in `$TL`.
4. Banner printed, then more output, rc 141 → `git-data-jump verdict=ok`.
5. Banner arrives on line 2 → `git-data-jump verdict=failed`.
6. Second of two roster members refuses → exit 3 on that member; the jump dials the first member.
7. `WEB_HOSTS=""` → `web_roster_empty`.
8. `WEB_HOST_SSH` unset on the forward path → `web_host_ssh_unset`, exit 3 (not a `set -u` death).
9. A roster member `-oProxyCommand=touch /tmp/pwn` → `invalid_host`, and `/tmp/pwn` does not exist.
10. `GIT_DATA_SSH` set while the web probe fails → no jump or auth line in `$TL`.
11. All probes ok, key set, `DRY_RUN=1` → the gate passes and `prepare_luks_target`'s remote follows the probes in `$TL`.
12. After `access_gate` exits 3, the EXIT trap re-exits 3 and adds no `$TL` line.
13. ROLLBACK=1 with both invocations unset, run under `DRY_RUN=0` and `DRY_RUN=1` → `$TL` contains the `false` flag write before any `ssh`; each failed step emits `::warning title=git-data-cutover recovery::step=<name> rc=<n>`.
14. Forged workflow commands: probe stderr containing `::error title=git-data-cutover access::role=git-data-jump verdict=ok`, `::add-mask::x` and a CR/LF → no annotation-shaped line escapes the stop-commands span; the logged text is printable-ASCII only.
15. `ok` verdicts emit `::notice`, non-ok emit `::error` (both asserted).
16. Bridge decode body, both branches → Guard 2 name sets.
17. Runtime arm R1–R4 (real sshd).

## Domain Review

**Domains relevant:** Engineering, Product (sign-off only)

### Engineering

**Status:** reviewed
**Assessment:** CTO binding ruling (2026-09-14): transport (b) ACCEPT — the only option where a compromised web-1 cannot log in to git-data, with no Cloudflare change; key K1 ACCEPT — every disqualifier verified (the default user keeps create-time keys on root; the ci_ssh fan-out is real; template edits are hash-bound); sequencing ACCEPT — key resources outside the per-PR allow-set would break the exact-scope gates, so the follow-up is a tracked issue tied to the rehearsal. Required and adopted: the auth verdict can never stand in for a transport failure (jump before auth, Guard 1 row 6); both future `ssh_config` blocks need `IdentitiesOnly yes` + `BatchMode yes`; the host-key residual is tied to #6976 and rotation is gated on #7226. Superseded after plan review: the `127.0.0.1:2222` jump address (the NAT rule matches for `server-ip` callers, and one route keeps one host identity); `GIT_DATA_SSH_HOST` as the address source (it lives in `prd`); the names-only Doppler probe (no key handling ships in this PR).

### Product/UX Gate

**Tier:** none (no UI surface; CPO consulted solely for the `single-user incident` sign-off)
**Decision:** reviewed
**Agents invoked:** cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO signed off with conditions: unchanged consumed exports for all four bridge callers; key custody outside `prd_terraform`; a bounded key lifetime; C1 re-approval in the follow-up. All are carried into ADR-220 and the follow-up; the lifetime condition is satisfied as a window-scoped read token plus revocation at replace. The ask to assert store emptiness at run time goes to the follow-up, since this PR never reaches the store.

## Plan Review Record (2026-09-15)

Panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, plus the Phase 4.5 strong-model consult. All consolidated findings were technical (Mechanical) and are applied above; none changed the brief's stated direction, so nothing was persisted to `decision-challenges.md`. The main changes: the bridge edit shrank to a one-line export delete; all key handling moved to the follow-up; stage+banner verdicts replaced the stderr classifier; Guard 3 and the post-merge dry-run were cut; the live transport measurement moved before merge; the ungated secret reference was removed; key custody became AP-008-compliant with a window-scoped token; the C4 edge source was corrected; ROLLBACK keeps its flag-off write ahead of any probe; walls 4–6 block the follow-up.

## Review Record (2026-09-15)

A 10-agent review panel found no P1. Its fixes were applied inline: one roster and invocation parse
shared by the gate and every later call; `reason=` on failed probes; a ROLLBACK-only run that exits
4 when a recovery step could not run; a rollback reachable after a bridge failure; and ADR-220,
ADR-068, ADR-149, runbook and C4 corrections. The one follow-up, #8189, was extended with the
review's blockers: the ADR-119 reconciliation of the inert freeze and reloads, the post-cutover
dry-run self-overwrite, and the custody requirements (dedicated R2 bucket and token, plan-job
exclusion, plural `hcloud_ssh_keys` lookup, rollback split).

## Dependencies & Risks

| Risk | Mitigation |
|---|---|
| web-1's sshd forbids `-W` | AC11 measures it before merge; halt + fallback-transport amendment |
| The banner probe behaves differently on the runner (early EOF, timing) | stdin held for 5 s, `timeout 25`; the verdict keys on the banner, not the rc; AC11 measures the real form |
| The bridge edit regresses a live caller | Guard 2 export sets; AC7/AC8 existing suites |
| Walls 4–6 bite once the key lands | filed in Phase 0 as blocking the follow-up |
| After the follow-up, a dry-run is no longer non-mutating | recorded in the follow-up issue body |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- `ssh -J` drops a command-line `-i` for the jump hop; the follow-up must use an `ssh_config` `ProxyCommand`.
- The jump verdict keys on the `SSH-2.0-` banner, never on the pipeline's exit code, which is non-zero on success paths.
- `access_gate` must stay a plain statement; inside `$(…)` or `||`, `set -e` is suspended and a failing probe could fall through.
- The ADR ordinal is provisional; renumbering sweeps the plan, `tasks.md` and the runbook line in one edit.
- The AC11 dry-run is non-mutating only while nothing supplies `GIT_DATA_SSH`; once the follow-up lands it runs `luksOpen`, mount and `rsync --delete` into FRESH.
