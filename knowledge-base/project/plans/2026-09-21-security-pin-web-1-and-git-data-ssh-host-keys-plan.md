---
title: "security: pin web-1 and git-data SSH host keys (replace accept-new TOFU on the CI bridge, the cutover jump and the app's git-data transport)"
type: fix
date: 2026-09-21
slug: security-pin-web-1-and-git-data-ssh-host-keys
branch: feat-one-shot-7226-5914-host-key-pinning
issue: 7226
closes: [7226, 8125]
refs: [5914, 5274, 8093, 8211]
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# security: pin web-1 and git-data SSH host keys

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

**PR body lines (ship):** `Closes #7226`, `Closes #8125` (#8125 duplicates #7226's Terraform
half), `Ref #5914`, `Ref #5274`, `Ref #8093`.
**Why `Ref` and not `Closes` for #5914:** this PR ships the pinned path for the app, but it
keeps one unpinned fallback arm that is reachable only until the first replace publishes the
pin (D4). #5914 stays open as that arm's tracking issue. It closes with the follow-up PR that
deletes the arm, which is a hard cutover precondition (see the runbook update). This follows
the plan-sharp-edges rule for fixes that complete after merge.

## Overview

Every SSH session the system opens to web-1 or to the git-data host accepts whatever host key
the peer presents. Three places do this:

1. **The CI tunnel bridge** (`.github/actions/cf-tunnel-ssh-bridge/action.yml`, the
   `SSH_INVOCATION=` line in the step "Decode CI SSH private key…") uses
   `StrictHostKeyChecking=accept-new` together with `UserKnownHostsFile=/dev/null`. Nothing is
   remembered between connections, so web-1's key is re-accepted without a check every time
   (#7226). The Terraform `connection {}` blocks that reach web-1 through the same bridge set no
   `host_key` (#8125). There are 18 such blocks in `server.tf` and 1 in `ci-ssh-key.tf`.
2. **The git-data cutover workflow** (`.github/workflows/git-data-cutover.yml`, step "Write
   git-data ssh_config") sets `accept-new` and `/dev/null` on both hops. Per ADR-220 D4, this
   means every store-probe answer is unauthenticated, and a compromised web-1 could pretend to
   be git-data.
3. **The app's private-network git transport** (`apps/web-platform/server/git-auth.ts`,
   `gitWithPrivateKeyAuth` and `sshWithPrivateKeyAuth`) uses `accept-new` against an empty
   known_hosts file created fresh for each call (#5914). These helpers carry the live Art. 17
   erasure call (`removeGitDataRepo`) and the provisioning call. Once the store is enabled,
   they also carry every replication push and fetch.

How each host gets pinned:

- **git-data.** Terraform mints the host key (`tls_private_key`, ED25519). Cloud-init installs
  it, and a boot-time check confirms that sshd serves exactly that key. Terraform publishes the
  public half to Doppler `prd` in the same apply that creates the host. The birth and replace
  jobs rotate the key together with the host. A separate follow-on job then forces a web
  release, so the app loads the new pin within about one release cycle. The pin comes from the
  replace flow itself, and nothing outside Terraform ever copies it.
- **web-1.** web-1 cannot be replaced: the replace gate refuses it by name until #6931. It also
  ignores cloud-init changes (`ignore_changes = [user_data]`), and
  `hr-prod-host-config-change-immutable-redeploy` forbids changing sshd in place. So its current
  **ECDSA-P256** key is captured once, from a vantage point outside Cloudflare, and committed to
  the repo as a reviewed pin. ECDSA is used rather than ED25519 because Terraform's Go client
  negotiates ECDSA (see R4). OpenSSH callers pin the same key with
  `HostKeyAlgorithms=ecdsa-sha2-nistp256`. A no-op probe provisioner runs whenever the pin or
  the Terraform version changes. That way a wrong Terraform pin fails the apply at merge time,
  instead of weeks later in someone else's PR.

This is the #7226 precondition in the git-data LUKS cutover runbook
(`knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` §"Preconditions
for the real cutover"). This PR updates that checklist. Plan review raised two decisions that
challenge the operator's stated direction. They are recorded in
`knowledge-base/project/specs/feat-one-shot-7226-5914-host-key-pinning/decision-challenges.md`
(DC-1: split the app change into a second PR; DC-2: the forced-release redeploy).

## Research Reconciliation — Spec vs. Codebase

| Claim (dispatch / issue bodies) | Reality on `origin/main` (55761389b) | Plan response |
|---|---|---|
| Bridge TOFU at `action.yml:197` | Confirmed (`SSH_INVOCATION="ssh -i $KEYFILE -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -l root"`) | Replaced. Anchor on content, not the line number |
| cutover.yml `:211,227` accept-new | Confirmed, **plus** `UserKnownHostsFile /dev/null` at `:212,228` (both hops) | Both hops pinned |
| git-auth.ts `:367,455` | Confirmed. The doc-comments at `:330-335` and `:419-420` say pinning was "deliberately NOT used" because the host may be replaced | That reason no longer holds (the replace flow publishes the pin), so the comments are rewritten |
| #7226: "the composite is used by 4 workflows" | **5 callers:** `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` (terraform mode); `git-data-cutover.yml`, `workspaces-luks-cutover.yml` (2 jobs) and `workspaces-luks-verify.yml` (bash mode, all `server-ip: WEB_HOST_PRIVATE_IP`) | All covered by the bridge plus the connection blocks |
| #8125: "17 SSH-provisioned terraform_data" | **19** `connection {` blocks: 18 in `server.tf` and 1 in `ci-ssh-key.tf` (`terraform_data.root_authorized_keys`, `agent = true`, operator-local). All dial `hcloud_server.web["web-1"].ipv4_address` | Guard 2 counts at run time over every `.tf` |
| #5914: "provision the host's public key at TF/cloud-init time (it is TF-known)" | **Not** TF-known today. No sshd host key is minted anywhere (`git grep -nE 'ssh_keys:\|ssh_genkeytypes\|ssh_deletekeys\|ssh_host_' apps/` finds only unrelated hits). `hcloud_server.git_data.ssh_keys` is the Hetzner *authorized-key* list | Mint the key (`tls_private_key.git_data_host_ssh`) and inject it with the cloud-config `ssh_keys:` block |
| #7226 suggests a two-phase rollout for the bridge (fail-open first, then fail-closed) | `accept-new` over a known_hosts file that already **contains** the pinned key rejects a changed key. It differs from `yes` only when no entry exists, and the pin file is always written | The staged phase is cut (Cut List) |
| The app can take its pin from Doppler like its other git-data config | `GIT_DATA_SSH_HOST` is already a TF-owned `doppler_secret` in `soleur/prd` (`git-data.tf`). `ci-deploy.sh` loads prd into the container env at deploy time (`doppler secrets download --no-file --format docker --project soleur --config prd`) | Same pattern for `GIT_DATA_SSH_HOST_KEY`. A forced web release after every birth or replace bounds the lag (D6) |
| "Go's SSH client prefers ED25519" (plan v1 assumption) | **False (CTO source read):** Terraform 1.10.5 (`TERRAFORM_VERSION` in `apply-web-platform-infra.yml`) writes `host_key` as `@cert-authority <host> <key>` and falls back to a direct match. It never sets `HostKeyAlgorithms`. Its vendored `golang.org/x/crypto` v0.27.0 lists ED25519 **last**, after ECDSA and RSA. `knownhosts` treats a different key type as a mismatch. Ubuntu 24.04 ships RSA, ECDSA and ED25519 host keys | web-1 is pinned to its **ECDSA-P256** key on every path. OpenSSH callers use `HostKeyAlgorithms=ecdsa-sha2-nistp256` |
| The erasure path only runs while the store is enabled | **False.** `removeGitDataRepo` is deliberately *not* gated on the flag, because repos persist after a rollback (comment inside the function). Doppler `prd` holds `GIT_REMOVE_SSH_PRIVATE_KEY`, `GIT_PROVISION_SSH_PRIVATE_KEY`, `GIT_TRANSPORT_SSH_PRIVATE_KEY` and `GIT_DATA_SSH_HOST` (checked by name only). So erasure SSH to git-data is **live in production today** | This shapes the D4 fallback and the cutover precondition (#5914 closes before any flag flip) |
| A host-key failure on erasure reads as some existing outcome | `SSH_AUTH_FAILURE` (in `git-data-replication.ts`) already matches `host key verification failed`, so a mismatch comes back as `unauthorized`. The account-delete comment and the Art. 17 alert describe that as a "REMOVE key rejected, fleet-wide until a host replace", which is the wrong remedy | New outcome `host_key_mismatch`, classified before `SSH_AUTH_FAILURE` (D4) |
| A cloud-init edit is an ordinary change | `cloud-init-git-data.yml` is **hash-bound** to the rung-2 evidence (`git-data-rung2-rehearsal.md` §"Changing the payload: the two-PR sequence") | This PR is the **payload PR** and deletes the evidence file |
| `apply-web-platform-infra.yml` can take edits freely | 478,861 bytes against the 490,000-byte gate (ADR-231, `plugins/soleur/test/workflow-file-size.test.ts`) | Workflow edits stay small. The redeploy logic goes in a new composite action, which the gate does not measure |
| `hcloud_server.git_data` drift after merge would only show new resources | `user_data` changes and the resource has no `ignore_changes` on it, so `scheduled-terraform-drift` will show a **server replace** pending until post-merge step 3 | Documented as expected in R1 and in the runbook |

## Research Insights

### Premise Validation (Phase 0.6)

- #7226, #5914, #8125 and #8093 are **OPEN**, with no closing PR. #8211, #8209 and #8218 (out
  of scope) are OPEN. #6931 (the web fresh-boot LUKS path, which blocks any web-1 replace) is
  OPEN. #8385 (the workflow split) is OPEN.
- #8451/#8453 (Sentry alert-rule 410 migration, owned by another session) is on a different
  surface. This plan edits **no** file under `apps/web-platform/infra/sentry/`. The existing
  `sentry_alert.art17_erasure_incomplete` filters on `feature=account-delete` +
  `op=git-data-bare-repo-erasure` (not on outcome values), so the new `host_key_mismatch`
  erasure outcome is routed and pages with no Sentry change. The rule's comment lists four
  outcome values and goes stale by one. Refresh it in a follow-up after #8453 merges (F4).
- The read-only cutover dry run exists; its last success was 2026-09-16. The git-data host is
  born.
- ADR corpus: ADR-220 D4 names "Unverified host keys (#7226)" as a residual and makes the
  git-data pin a precondition for D2 reaching `accepted`. ADR-068 says rotations against a
  populated store are gated on #7226. No ADR rejects Terraform-minted host keys.
- CLI claims verified at plan time: the `TERRAFORM_VERSION` pin (1.10.5); the `workflow_dispatch`
  arm of `web-platform-release.yml` (with `bump_type`), and `reusable-release.yml`'s
  `check_changed`, which prints "Release forced (workflow_dispatch or force_run)". A dispatched
  release therefore deploys even when no app file changed.

### Property List (Phase 0.6b)

- **P1** A CI session to web-1, from bash callers and the Terraform Go client alike, succeeds
  only if web-1 presents a pinned host key.
- **P2** The cutover workflow's session to git-data succeeds only if git-data presents its
  pinned key. The check is end-to-end from the runner, so neither the Cloudflare edge nor
  web-1 (the jump host) can stand in for git-data.
- **P3** The app's git-data transport, provision and remove calls verify git-data's key
  whenever a pin is published. With the store enabled, they refuse to connect if no pin is
  published.
- **P4** The git-data pin is created and published by the same Terraform apply that births or
  replaces the host carrying it, and it changes on every replace. No copy step exists outside
  Terraform. After each such apply the app loads the new pin with no separate step.
- **P5** A mismatch fails closed with a named verdict that is visible off-host (a workflow
  annotation, a Sentry event, or the existing Art. 17 alert).
- **P6** The cutover runbook's precondition checklist, ADR-220 D4, PA-36 and the counsel audit
  describe the new state.

### Cut List (Phase 0.6b)

| Proposed mechanism | Property | Why cut |
|---|---|---|
| #7226 step 3: fail-open (`accept-new` + known_hosts) then flip to `yes` in a later PR | P1 | With the known_hosts file always written, the interim phase checks nothing new. The merge-time probe provisioner and the pre-merge verify dispatch (AC15) give the confidence the staged rollout was meant to buy |
| #8125 option: capture web-1's key via cloud-init into a TF output | P1 | web-1 has `ignore_changes = [user_data]` and no replace path |
| Publish web-1's pin to Doppler | P1 | No rotation flow exists for web-1. A committed file is reviewed and versioned in git, and it removes a Doppler read from 5 callers |
| SSH host certificates / a host CA | P1–P4 | The `tls` provider cannot sign OpenSSH certificates. A CA adds a signing key to guard and a boot-time signing step for no property the plain pin misses |
| A new bridge export (`WEB_1_KNOWN_HOSTS`) | P2 | `infra-validation.yml` asserts that the bridge exports exactly `{CI_SSH_KEYFILE, WEB_HOST_SSH}`. The cutover workflow uses the same writer script against the same committed file |
| A new Sentry alert rule for `host_key_mismatch` | P5 | The existing Art. 17 rule routes every erasure outcome by `op`. Replication is not live until cutover (#8211 owns its alerting). Editing Sentry TF would collide with #8453 |
| (plan review) A second algorithm (ED25519) in web-1's pin | P1 | Terraform must use ECDSA-P256, and OpenSSH can pin ECDSA as well. That leaves one line, one regex and one algorithm for web-1 |
| (plan review) A second Doppler copy of the git-data pin in `prd_terraform` | P2 | The cutover workflow already holds a `prd` read token, scoped to its own step before the bridge. The pin read moves into that step (`git-data-flag-precheck.sh`), so `prd` is still never read in a process that handles host bytes |
| (plan review) Six distinct H4 / pin-read verdicts | P5 | They collapse to two: `git_data_host_key_unavailable reason=<absent\|invalid\|unreadable>` and `host_key_mismatch reason=<changed\|unknown\|alg>`. The remedy is the same within each group, and the reason word keeps the diagnosis |
| (plan review) A cross-language regex byte-parity check | Guard 3 | Each site has its own must-reject and must-pass fixtures. A `# twin:` comment next to each regex names where the others live |

### Relevant files (content anchors)

- `.github/actions/cf-tunnel-ssh-bridge/action.yml`: step "Decode CI SSH private key (TF_VAR + optional keyfile/WEB_HOST_SSH export)", `SSH_INVOCATION=` line.
- `.github/workflows/git-data-cutover.yml`: step "Write git-data ssh_config" (the heredoc blocks `Host 10.0.1.10` / `Host 10.0.1.20`), step "Run git-data cutover read-only proof", and the bridge teardown.
- `apps/web-platform/infra/git-data-cutover.sh`: the access gate (roles `web`, `git-data-jump`, `git-data-auth`) and its `_access_reason` stderr classifier.
- `apps/web-platform/server/git-auth.ts`: `gitWithPrivateKeyAuth`, `sshWithPrivateKeyAuth`.
- `apps/web-platform/server/git-data-replication.ts`: `resolveGitDataSshHost` (the pattern for `resolveGitDataHostKeyPin`), `SSH_AUTH_FAILURE`, `GitDataErasureOutcome`, `removeGitDataRepo`, `provisionGitDataRepo`, `replicateToGitData`. `git-data-client.ts` `fetchFromGitData`. `workspace-resolver.ts` `isGitDataStoreEnabled` (synchronous). `account-delete.ts` (consumes the erasure outcome; tag `erasure_outcome`).
- `apps/web-platform/infra/git-data.tf`: `resource "doppler_secret" "git_data_ssh_host"` (the publishing pattern), `resource "hcloud_server" "git_data"`, `module "git_data_userdata"`.
- `apps/web-platform/infra/modules/git-data-userdata/{main,variables,outputs}.tf`. The rendered output is already `sensitive = true`. `variables.tf` carries the MAY-DIVERGE / MUST-MATCH taxonomy. `main.tf` notes the one-line map-entry parser constraint.
- `apps/web-platform/infra/cloud-init-git-data.yml`: `/etc/ssh/sshd_config.d/01-hardening.conf` (first-match-wins; the `01-` prefix is load-bearing) and the `STAGE=sshd_config` `sshd -t` block, which already emits through `git-data-emit`.
- `apps/web-platform/infra/rung2-rehearsal/rehearsal.tf`: `module "git_data_userdata"`.
- `.github/workflows/apply-web-platform-infra.yml`: the per-PR SSH apply `-target` list (16 `terraform_data` entries ending `send_failed_alert_probe`), the git-data-host-replace plan step (`-replace='hcloud_server.git_data'` + 4 `-target`s), and the git-data-host-create target list.
- `tests/scripts/lib/git-data-host-replace-gate.sh`, `tests/scripts/lib/git-data-host-birth-gate.sh` (allow-set lists `doppler_secret.git_data_ssh_host`), and their `tests/scripts/test-*.sh`.
- `apps/web-platform/infra/server.tf` (18 connection blocks), `apps/web-platform/infra/ci-ssh-key.tf` (1 block), `apps/web-platform/infra/tunnel.tf` (a *comment* containing `connection { host }`, which Guard 2's walker must not count), `web-host-provisioner-parity.test.sh` (+ `-mutation.test.sh`).
- Tests that assert the TOFU literals: `apps/web-platform/infra/git-data-cutover-access.test.sh` (`WEB_INV=`, `WEB_PROBE=`, the `ssh -i FIXTURE_WEB_KEY … 10.0.1.10 true` fixture pair, `_want_inv=`, the ssh_config key allow-list containing `"StrictHostKeyChecking accept-new", "UserKnownHostsFile /dev/null"`, and two `WEB_HOST_SSH=` harness fixtures); `apps/web-platform/test/git-auth.test.ts` (`toContain("StrictHostKeyChecking=accept-new")` ×2).
- Local-only TOFU that stays (on Guard 1's allow-list): `apps/web-platform/infra/git-data-ownership.test.sh` (`StrictHostKeyChecking=no` to `127.0.0.1:2222` in a throwaway container) and `apps/web-platform/infra/infra-config-gate.test.sh` (a fixture string inside a detector test).

### Institutional learnings applied

- `2026-07-18-cutover-bridge-dryrun-guard-and-workflow-step-vs-in-script-ssh.md`: the pin goes in the ssh_config, the one path shared by the dry run and the real run.
- `2026-05-20-l3-network-fix-vs-l7-credential-fix-on-ssh-provisioner-chain.md`: Access admission, auth and host identity fail independently, so each verdict names which one failed (Hypotheses).
- `2026-07-27-the-safety-rationale-i-wrote-was-false-and-the-gate-it-justified-failed-open-three-ways.md`: the new jq arms in the gate need both positive and negative rows (Guard 4).
- `best-practices/2026-07-09-terraform-source-guard-must-key-on-arming-class-not-ignore-changes-value.md`: Guard 2 keys on the block type, not on a host value.
- `2026-03-21-cloudflare-tunnel-server-provisioning.md`: create-time attributes behind `ignore_changes` do nothing on the live host, which is why web-1 uses a captured pin.
- `2026-06-03-path-rename-sweep-exclude-own-migration-artifacts.md`: Guard 1 excludes `knowledge-base/**`, where docs quote the old literals on purpose.

### CLAUDE.md / AGENTS.md conventions in force

`hr-prod-host-config-change-immutable-redeploy`, `hr-all-infrastructure-provisioning-servers`,
`hr-no-ssh-fallback-in-runbooks`, `cq-silent-fallback-must-mirror-to-sentry`,
`cq-cite-content-anchor-not-line-number`, `hr-menu-option-ack-not-prod-write-auth`,
`hr-dispatch-async-must-arm-watch` (the redeploy dispatch waits on its run),
`cq-union-widening-grep-three-patterns` (the new erasure outcome), `cq-test-fixtures-synthesized-only`.

## Hypotheses (L3 → L7 triage for post-merge failures)

Phase 1.4's network gate fired on "SSH". The rollout adds a new failure class, so triage must rule
out the lower layers first:

- **H1 L3 admission:** the bridge reports `ci_ssh_access_denied` / `ci_ssh_liveness_*`. This is Cloudflare Access or the tunnel, not the pin.
- **H2 L3 firewall / private NIC:** the git-data hop times out. Check with the runbook's Private-NIC readiness read. A key mismatch never produces a timeout.
- **H3 L7 auth:** `Permission denied (publickey)` means the wrong CI or root key. This plan does not change that path.
- **H4 L7 host identity (new).** One verdict, `host_key_mismatch`, with a reason word. Classifier order in `git-data-cutover.sh` `_access_reason`, ahead of its `Permission denied` branch, and the same order in the app classifier:
  1. `no matching host key type found` gives `reason=alg`.
  2. `No .* host key is known for` gives `reason=unknown` (a typo'd alias or an empty known_hosts, which is a config bug).
  3. `REMOTE HOST IDENTIFICATION HAS CHANGED` or `Host key verification failed` gives `reason=changed`.

  Consider H4 only after H1–H3. Likely causes, in order:
  - (a) web-1's pin was captured wrong.
  - (b) git-data was replaced outside the gated job, so the pin was never republished.
  - (c) a real impersonation.

  **Role attribution caveat:** the jump hop's `ProxyCommand` ssh shares stderr, so a bad web-1 line can surface as `role=git-data-auth`. The `role=web` probe runs first, and both known_hosts lines come from one writer. Outside the cutover workflow, the `workspaces-luks-*` callers do not name a verdict. Their log shows ssh's raw stderr, and the run fails.

  Remediation: a re-capture PR for (a), a replace dispatch for (b). Never re-enable `accept-new`. If neither (a) nor (b) explains the failure, go to breach-notice triage (`knowledge-base/legal/recommended-tools.md#breach-notice-triage`, the 72-hour clock). If (a) is still unfixed after 21 days, escalate to the CLO (claim-decay window).

## Proposed Solution

### Design decisions

- **D1 — git-data pin: Terraform-minted, rotated on replace.**
  - **The key.** Add `resource "tls_private_key" "git_data_host_ssh" { algorithm = "ED25519" }` in `git-data.tf`.
  - **Into cloud-init.** Pass it through two new module variables:
    - `host_ssh_ed25519_private_key` (sensitive) = `tls_private_key.git_data_host_ssh.private_key_openssh`. It must be `private_key_openssh`, because `private_key_pem` is PKCS#8 for ED25519, and OpenSSH and cc_ssh do not load that reliably.
    - `host_ssh_ed25519_public_key` = `trimspace(….public_key_openssh)`.

    Render them into the cloud-config:

    ```yaml
    ssh_deletekeys: true
    ssh_genkeytypes: []     # documentation only: cc_ssh skips generation when ssh_keys is present
    ssh_keys:
      ed25519_private: |
        ${indent(4, host_ssh_ed25519_private_key)}
      ed25519_public: ${host_ssh_ed25519_public_key}
    ```

    The `indent(N, …)` argument must equal the column of the `${` in the real template. AC5 parses the rendered YAML to catch a mismatch.
  - **sshd config.** Add `HostKey /etc/ssh/ssh_host_ed25519_key` to `01-hardening.conf`. `HostKey` lines accumulate across drop-ins rather than first-match-wins, so the boot proof below is what guarantees there is only one.
  - **Boot proof.** Inside the `STAGE=sshd_config` block, after `sshd -t`:
    - `sshd -T` must list exactly one `hostkey` (the ED25519 path);
    - `ssh-keygen -lf` of that key must equal the fingerprint of the Terraform public key;
    - a fingerprint or count mismatch emits `stage:sshd_hostkey` fatal via `git-data-emit`;
    - a missing `ssh-keygen` only warns. This follows the block's existing "`sshd -t` must abort, restart must tolerate" rule.

    The replace and birth jobs already run `git_data_boot_verify` (`scripts/lib/git-data-boot-signal-poll.sh`) after the apply, so a fatal here turns the job red **before** D6 redeploys anything. A rung-2 PASS proves the pin is live on a real boot. Keep the existing `systemctl restart ssh`: socket activation can start sshd before cc_ssh writes the keys, and the restart fixes that.
  - **Publishing.** One TF-owned secret: `doppler_secret.git_data_ssh_host_key`, in `soleur/prd`, named `GIT_DATA_SSH_HOST_KEY`. It has the same shape as `doppler_secret.git_data_ssh_host`, `visibility = "unmasked"`, no `ignore_changes`, and **`depends_on = [hcloud_server.git_data]`**, so it is written only after the host that carries the key exists. That narrows the partial-failure window in R7.
  - **Rotation.** The replace job adds `-replace='tls_private_key.git_data_host_ssh'` and `-target='doppler_secret.git_data_ssh_host_key'`. The birth job adds both as `-target`. No per-PR `-target` reaches either one.
  - **Exposure (an ADR-235 residual).** The private key sits in main-root state twice: in the `tls_private_key` and inside `hcloud_server.git_data.user_data`. A separate root would not change that (A3). The Hetzner metadata endpoint also serves user_data to local processes on git-data. Anyone who can read either copy **and** has a network position (the private net or web-1) can pretend to be git-data. This falls within #8209's scope. F5 blocks non-root metadata access.
- **D2 — web-1 pin: captured once, committed, ECDSA-P256.**
  - **The file.** New file `apps/web-platform/infra/web-1-ssh-host-key.pub`: `#` header lines (capture method, UTC date, SHA256 fingerprint), then exactly one key line, `ecdsa-sha2-nistp256 …`.
  - **Capture (Phase 0).** Run `ssh-keyscan -T 10 -t ecdsa <web-1 public IPv4>` from an egress IP listed in `var.admin_ips`. That reaches web-1's public port 22 directly, without passing through Cloudflare, which is the threat position #7226 names. If the session's egress is not on the allowlist, run `soleur:admin-ip-refresh` first (that step needs its own ack). Cross-check against the operator's existing known_hosts entry (`ssh-keygen -F <ip>`) if one exists, and record the fingerprint in the PR body.
  - **Pre-merge second observation (AC15).** Dispatch `workspaces-luks-verify.yml --ref <branch>`. It is read-only and has no `environment:` gate, so this is a strict bash-mode run through Cloudflare, before merge.
  - **Merge-time Terraform proof.** Add `terraform_data.web_1_host_key_probe` with `triggers_replace = sha256("${local.web_1_ssh_host_key}|${var.terraform_version}")` and a `remote-exec` of `true` (read-only). Add it to the per-PR `-target` list. `var.terraform_version` defaults to `""` and is fed from the workflow's `TERRAFORM_VERSION` as `TF_VAR_terraform_version`. A Terraform bump can change x/crypto's host-key algorithm order (R4), and that change also re-runs the probe.
  - **If web-1 is ever replaced (#6931).** Every strict consumer fails closed with `host_key_mismatch reason=changed`. The fix is a re-capture PR using `scripts/capture-web-1-host-key.sh` (Files to Create). F1 tracks Terraform-minted web-host keys.
<!-- lint-infra-ignore start: D3 describes CI-executed SSH configuration, not an operator step -->
- **D3 — CI consumers.**
  - *Shared writer:* `.github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh <alias> <pin-file> <out>`.
    - Reads the single key line of `<pin-file>`. It selects non-comment lines with `awk`, not `grep -v`, because `grep -v` exits 1 under `pipefail` when nothing survives. It requires exactly one line and strips `\r`.
    - Validates the line against the regex for its algorithm (Guard 3), using `[[ $pin =~ $RE ]]` with `$RE` **unquoted**.
    - Writes `<alias> <key>` and sets mode 0444.
    - Rejects an `<out>` path that does not match `^/[A-Za-z0-9/_.-]+$`, because callers expand `${WEB_HOST_SSH}` unquoted.
  - *Bridge, bash mode:* runs `"${{ github.action_path }}/write-known-hosts.sh" web-1 "$GITHUB_WORKSPACE/apps/web-platform/infra/web-1-ssh-host-key.pub" "$RUNNER_TEMP/web-1.known_hosts"` and exports `WEB_HOST_SSH="ssh -i $KEYFILE -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$KH -o HostKeyAlias=web-1 -o HostKeyAlgorithms=ecdsa-sha2-nistp256 -o UpdateHostKeys=no -l root"`. The exported variables stay exactly `{CI_SSH_KEYFILE, WEB_HOST_SSH}`. Each of the two `workspaces-luks-cutover.yml` jobs writes its own file.
  - *Terraform:*

    ```hcl
    locals {
      web_1_ssh_host_key = regex(
        "^ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBB[A-Za-z0-9+/]{86}=$",  # twin: write-known-hosts.sh
        one([for l in split("\n", replace(file("${path.module}/web-1-ssh-host-key.pub"), "\r", "")) : l if startswith(l, "ecdsa-sha2-nistp256 ")]),
      )
    }
    ```

    `one()` errors on two or more lines and returns null on zero, and `regex()` errors on null or on no match. So every plan that uses the pin fails closed. A `check` block would only warn, and a precondition is skipped by `-target` plans that leave its resource out. All 19 `connection {}` blocks set `host_key = local.web_1_ssh_host_key`. Changing `connection` re-runs no provisioner, so only the probe fires. Operator-local applies now also enforce `host_key` (runbook note).
  - *git-data-cutover.yml:*
    - **Pin read.** `git-data-flag-precheck.sh` already runs as its own step, before the bridge, with `DOPPLER_TOKEN_PRD`. It now also reads `GIT_DATA_SSH_HOST_KEY`, using the same measured `--no-exit-on-missing-secret` semantics. It validates the value and writes it to `$RUNNER_TEMP/git-data.pin`. It refuses (exit 5) with `verdict=git_data_host_key_unavailable reason=absent|invalid|unreadable`. It also prints an informational `TOFU_ARM present|absent` line, read from `apps/web-platform/server/git-auth.ts` in the checkout, which the flag-flip precondition uses (D4).
    - **Known hosts.** "Write git-data ssh_config" calls the writer twice into `$RUNNER_TEMP/gd-known-hosts`: `web-1` from the committed file, and `git-data` from `$RUNNER_TEMP/git-data.pin`. It checks the result with `-s`.
    - **Host blocks.** Both blocks set `StrictHostKeyChecking yes`, `UserKnownHostsFile <gd-known-hosts>`, and `HostKeyAlias web-1|git-data`. They set `HostKeyAlgorithms` to `ecdsa-sha2-nistp256` for web-1 and `ssh-ed25519` for git-data. The inner `ProxyCommand ssh -F cfg -W 10.0.1.20:22 10.0.1.10` resolves to the `10.0.1.10` block, so the jump hop is pinned too.
    - **Teardown.** Teardown shreds both files. They hold public data, so this is hygiene only.
  - *git-data-cutover.sh `_access_reason`:* add the H4 branches, in the order given under H4, ahead of `Permission denied`. Each reason gets a test row.
<!-- lint-infra-ignore end -->
- **D4 — app consumer.**
  - **The resolver.** Add `resolveGitDataHostKeyPin(): string | null` to `git-data-replication.ts`. It returns the valid pin (ED25519 regex, `# twin:` comment) and otherwise:
    - wrong shape: **throw**;
    - absent, and `isGitDataStoreEnabled()` is true: **throw**;
    - absent, and the store is disabled: return `null`, and call `reportSilentFallback({ feature: "git_data_host_key_pin", op: "pin_absent_store_disabled" })` once per process.
  - **Startup evidence.** At app startup, log one line to Better Stack: `git_data_pin=present fp=SHA256:<fingerprint>` or `git_data_pin=absent`. This is only the public-key fingerprint. It is the **positive** evidence for post-merge steps 3 and 5. Erasures are rare, so a quiet Sentry proves nothing.
  - **Where the pin is resolved.** Each caller resolves the pin in a **dedicated guard before its ssh `try`**. The existing catch sorts errors by `e.code`, so a resolver throw inside the `try` would be misread as `unreachable`. The callers:
    - `removeGitDataRepo`:

      ```ts
      let pin: string | null;
      try { pin = resolveGitDataHostKeyPin(); } catch (e) { return { status: "unconfigured", detail: String(e) }; }
      ```

    - `provisionGitDataRepo` (its `sshWithPrivateKeyAuth` call): same guard. Its failure goes to the caller's existing report.
    - `replicateToGitData` / `fetchFromGitData`: the existing failure report. Neither ever breaks the turn.
  - **Helper signatures.** The helpers take the pin as a **required** positional parameter, placed before the defaulted `opts`: `gitWithPrivateKeyAuth(args, privateKey, hostKeyPin, opts = {})` and `sshWithPrivateKeyAuth(host, remoteCommand, privateKey, hostKeyPin, opts = {})`.
    - With a pin, the helper writes `git-data <pin>\n` into the per-call 0600 known_hosts file and passes `StrictHostKeyChecking=yes`, `HostKeyAlias=git-data`, `HostKeyAlgorithms=ssh-ed25519` and `UpdateHostKeys=no`.
    - With `null`, the helper applies one shared module-level `const TOFU_FALLBACK_OPTS` (the single `accept-new` literal that Guard 1 counts) against the empty file.
  - **New erasure outcome `{ status: "host_key_mismatch"; detail }`.** Classify it in the H4 order, on exit 255, **before** `SSH_AUTH_FAILURE`, and remove `host key verification failed` from `SSH_AUTH_FAILURE`. `account-delete.ts` already routes every non-`erased`/`skipped` status to `erasure_outcome=<status>` under the paging Art. 17 rule. Add the new value to its comment table with the correct remedy: "the web app holds a stale or wrong pin — redeploy; or the host was re-keyed outside the replace job". Widen the union using `tsc --noEmit` as the enumerator.
  - **Why the `null` arm is allowed, and why it cannot outlive the empty store.** Strict mode is impossible until the first replace publishes the pin. Removing the arm now would fail every production erasure and show users a false "erasure pending" notice. The flag condition alone is **not** enough, because repos survive a rollback. So "pin present in prd AND #5914 closed (the arm deleted)" is a **hard precondition for ever setting `GIT_DATA_STORE_ENABLED`**:
    - the runbook states it;
    - the precheck's `TOFU_ARM` line surfaces it;
    - a note on #8211 asks for it to become a refusal when real modes are rebuilt.

    Before the flag is first set, the store holds no repository. DC-1 records the reviewers' alternative: split the app change into a second PR that is strict from its first commit.
- **D5 — rung-2 rehearsal root.** The rehearsal root mints its own `tls_private_key` and passes it to the module. Both new variables are declared **MAY DIVERGE (identity class)**, and the `RUNG2_VAR_DIVERGENCE` allow-list is extended to match. This PR deletes `git-data-rung2-boot-evidence.env` (step 1 of the two-PR sequence).
- **D6 — pin propagation to the app (bounds R2).** Add a new follow-on job, `git_data_redeploy`, in `apply-web-platform-infra.yml`, with `needs: [<birth or replace job>]` and `if: needs.<job>.result == 'success'`. It has `permissions: { actions: write, contents: read }`, no secrets, no Terraform, and no environment. It sits outside the apply concurrency group, so it holds no infra lock. Its logic lives in the composite action `.github/actions/dispatch-web-redeploy/action.yml`, and follows the `scheduled-marketplace-drift.yml` precedent:
  1. Record `T0` and the baseline `databaseId` of the latest `web-platform-release.yml` run. Fail closed if the baseline cannot be read.
  2. Run `gh workflow run web-platform-release.yml --ref main -f bump_type=patch`, labelling the release note "pin rotation, no code change".
  3. Poll, bounded by `timeout-minutes: 75` (the release takes ~24 minutes at worst, and the deploy comes on top), for **any** `web-platform-release` run of any event type with `databaseId` > baseline whose deploy job concluded `success`. A `skipped` deploy does not count.
  4. A cancelled dispatched run is tolerated if a later qualifying run succeeds.
  5. On timeout, fail with an annotation naming the pin-lag consequence.

  Recovery is to re-run the failed job, **not** to replace again. A dispatched release is forced past `check_changed`, and `ci-deploy.sh` re-downloads prd. #8211's same-version redeploy can later replace this job; add a note on #8211. DC-2 records the reviewers' preference for a runbook step instead.

### Post-merge sequence (goes into the runbook; each prod step needs its own authorization)

1. **Merge.** Any merge-triggered `apply-web-platform-infra.yml` run from this merge onward runs `terraform_data.web_1_host_key_probe` through the strict Terraform path and must end `success`. The bash path was already proven before merge (AC15).
2. **Rung-2 re-rehearsal** (`REHEARSE-GIT-DATA`, `dry_run=false`, `--ref main`), then the **evidence-only PR**. Schedule the rehearsal right after merge. Until the evidence PR merges, birth and replace refuse, **including an emergency replace**. ADR-235 records this as an accepted gap. The break-glass path is the documented operator-local apply per ADR-096.
3. **git-data-host-replace.**
   - The replace rotates the key, `git_data_boot_verify` passes (which includes the boot proof), and the secret publishes.
   - `git_data_redeploy` succeeds, and Better Stack shows `git_data_pin=present` with the fingerprint Terraform printed.
   - **If the replace job fails after the secret published:** re-dispatch the replace. Guard 4 accepts that plan.
   - **If only `git_data_redeploy` failed:** re-run that job only.
4. **Strict dry run.** Dispatch `git-data-cutover.yml`. It must read `role=git-data-auth verdict=ok` with both hops pinned. Then tick the #7226 line and flip ADR-235 to `accepted` in a docs PR.
5. **The #5914 follow-up PR.** It deletes the `null` arm and `TOFU_FALLBACK_OPTS`, removes `git-auth.ts` from Guard 1's allow-list, and closes #5914. It is gated on the step-3 startup line (`git_data_pin=present` on the current deploy), not on silence. It must merge before any `GIT_DATA_STORE_ENABLED` flip.

Step 3 is not ADR-220 D6's "fresh replace immediately before the real cutover". That replace is still required, and it rotates the pin and redeploys again automatically.

## Files to Edit

- `.github/actions/cf-tunnel-ssh-bridge/action.yml`: D3 bash mode, plus a "HOST-KEY PIN" contract paragraph in the header. Check the embedded shell with `bash -c`. Do **not** run `actionlint` on a composite action.
- `.github/workflows/git-data-cutover.yml`: the writer calls, the ssh_config Host blocks, teardown.
- `.github/workflows/apply-web-platform-infra.yml`:
  - the per-PR `-target` list gains `terraform_data.web_1_host_key_probe`, and the job env gains `TF_VAR_terraform_version`;
  - the replace job gains `-replace` + `-target` for the key and secret;
  - the birth job gains 2 `-target`s;
  - add two `git_data_redeploy` jobs (after birth, after replace).

  Net bytes must stay under ~2 KB, and `workflow-file-size.test.ts` must stay green.
- `.github/workflows/workspaces-luks-verify.yml`: rewrite the header's "KNOWN RESIDUAL … (#7226)" paragraph. **Do not quote the old option literals**, or Guard 1 counts them.
- `.github/workflows/infra-validation.yml`: edit only if its bridge-export assertion checks the value of `WEB_HOST_SSH`.
- `apps/web-platform/infra/git-data-flag-precheck.sh` + its test (`git-data-flag-precheck.test.sh`): pin read, `git_data_host_key_unavailable`, the `TOFU_ARM` line.
- `apps/web-platform/server/git-auth.ts`: the `hostKeyPin` parameter (placed before `opts`), `TOFU_FALLBACK_OPTS`, the pinned arm, the rewritten doc-comments.
- `apps/web-platform/server/git-data-replication.ts`: `resolveGitDataHostKeyPin`; guarded pin resolution in `removeGitDataRepo`, `provisionGitDataRepo`, `replicateToGitData`; the `host_key_mismatch` outcome; the `SSH_AUTH_FAILURE` edit.
- `apps/web-platform/server/git-data-client.ts`: guarded pin resolution in `fetchFromGitData`.
- The app startup module that logs boot facts (locate the server entry with `git grep -n "createChildLogger(\"server\")\|app.prepare()" apps/web-platform/server`): the `git_data_pin=` line.
- `apps/web-platform/server/account-delete.ts`: the comment table only.
- `apps/web-platform/test/git-auth.test.ts` and the replication/erasure tests (`git grep -l "removeGitDataRepo\|replicateToGitData\|provisionGitDataRepo" apps/web-platform/test`): the Guard 5 matrix. Build the `accept-new` literal by concatenation so Guard 1 does not count it. Run with `cd apps/web-platform && ./node_modules/.bin/vitest run <paths>` and `./node_modules/.bin/tsc --noEmit`.
- `apps/web-platform/infra/git-data.tf`: the tls key, the `doppler_secret` (with `depends_on`), the module inputs.
- `apps/web-platform/infra/modules/git-data-userdata/{main,variables}.tf`: two variables (MAY-DIVERGE identity class), each map entry on one line.
- `apps/web-platform/infra/cloud-init-git-data.yml`: the `ssh_keys` block, the `HostKey` line, the boot proof.
- `apps/web-platform/infra/git-data-rung2-boot-evidence.env`: **delete**.
- `apps/web-platform/infra/rung2-rehearsal/rehearsal.tf` (+ `variables.tf` if needed): its own tls key.
- `apps/web-platform/infra/server.tf`: the `web_1_ssh_host_key` local, `host_key` on 18 blocks, the new probe.
- `apps/web-platform/infra/ci-ssh-key.tf`: `host_key` on `terraform_data.root_authorized_keys`.
- `apps/web-platform/infra/variables.tf`: `variable "terraform_version" { type = string, default = "" }`.
- `apps/web-platform/infra/git-data-cutover.sh`: the H4 branches.
- `apps/web-platform/infra/git-data-cutover-access.test.sh`: update the fixtures that assert TOFU; add rows for `git_data_host_key_unavailable` and for `host_key_mismatch` reasons `changed|unknown|alg`.
- `apps/web-platform/infra/web-host-provisioner-parity.test.sh` (+ `-mutation.test.sh`): Guard 2, plus the probe in the per-PR list parity.
- `plugins/soleur/test/terraform-target-parity.test.ts`: the authority on `-target` lists. Add the probe (per-PR) and the key + secret (birth/replace).
- The rung-2 divergence allow-list: `git grep -n RUNG2_VAR_DIVERGENCE -- tests scripts apps` finds `tests/scripts/lib/git-data-birth-readiness-gate.sh`, `scripts/followthroughs/git-data-rung2-evidence-capture.sh`, `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` and their tests. Update each one that enumerates variables.
- `tests/scripts/lib/git-data-host-replace-gate.sh` + `tests/scripts/test-git-data-host-replace-gate.sh`: Guard 4 (replace arm).
- `tests/scripts/lib/git-data-host-birth-gate.sh` + `tests/scripts/test-git-data-host-birth-gate.sh`: Guard 4 (birth arm).
- The orphan-suite sweep: `git grep -ln "send_failed_alert_probe\|git_data_ssh_host\b" -- tests scripts plugins/soleur/test apps/web-platform/infra .github`. Update every hit that enumerates these lists.
- The git-data user_data budget and strip suites (`git-data-userdata-budget.sh`, `git-data-template-strip.test.sh`, `git-data-render-strip-parity.test.sh`): re-run them. The added material is about 0.6 KB before gzip, against about 10 KB of headroom.
- `scripts/encryption-posture-ledger.json`: add the four in-transit `connections` and the exception. Run `python3 scripts/lint-encryption-posture.py --repo-sweep`.
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`:
  - the precondition checklist and the Post-merge sequence;
  - verdict-map rows;
  - Rotation: "the host key rotates on every replace; `git_data_redeploy` loads it into the app";
  - expected drift: a pending server replace plus the key and secret creates until step 3;
  - a dispatch between merge and step 3 ends `git_data_host_key_unavailable reason=absent`;
  - operator-local applies enforce `host_key`;
  - the rung-2 emergency-replace gap and its break-glass path;
  - the H4 escalation;
  - a web-1 re-capture section (script + PR).
- `knowledge-base/engineering/architecture/decisions/ADR-220-*.md`: an amendment-log entry. D4's first residual is closed by ADR-235 (effective at step 4). **D6's pre-cutover fresh replace now also rotates the host key and redeploys the app**; record that as a design change.
- `knowledge-base/engineering/architecture/decisions/ADR-068-*.md`: one amendment line at "Rotations against a populated store stay gated on #7226".
- `knowledge-base/engineering/architecture/diagrams/model.c4`: edge descriptions only (see C4 views).
- `knowledge-base/legal/article-30-register.md` PA-36 §(g) (CLO):
  - add a new item: "Host-key authentication of the git-data SSH transport, provision and remove authorities — DRAFTED / NOT-YET-ACTIVE; activates at post-merge step 3; Terraform-minted ED25519 key rotated on every replace; residual: a reader of main-root state with a network position (#8209); a transitional unpinned arm reachable only before the first pin publication, deleted before any store-enable (#5914)";
  - correct (g)(11);
  - use conditional wording and cite by function name;
  - do **not** touch the sentences #8218 owns.
- `knowledge-base/legal/audits/2026-07-counsel-review-6588.md`: a conditioned addendum:
  - before AC15/step 1, verify verdicts came over an unverified channel (the #7226 residual);
  - after that, they are host-authenticated;
  - a host-key failure counts as **unavailable** within the 30-day claim-decay window, not as trigger (3).

## Files to Create

- `apps/web-platform/infra/web-1-ssh-host-key.pub`: the D2 pin (one ECDSA-P256 line).
- `.github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh`: the shared, validated writer (D3).
- `.github/actions/dispatch-web-redeploy/action.yml`: D6 logic.
- `scripts/capture-web-1-host-key.sh`: the Phase 0 capture as one command. It runs keyscan, prints the fingerprint, cross-checks against the operator's known_hosts, and writes the header. It refuses to run when `CI`/`GITHUB_ACTIONS` is set (Guard 1 row 7). It also serves future re-captures.
- `tests/scripts/test-no-tofu-ssh.sh`: Guard 1. Confirm that the CI runner's `tests/scripts/test-*.sh` glob picks it up.
- `tests/scripts/test-write-known-hosts.sh`: Guard 3 fixtures for the bash writer.
- `knowledge-base/engineering/architecture/decisions/ADR-235-ssh-host-keys-are-pinned.md`. The ordinal is **provisional**: re-probe across all `origin/*` refs right before merge. On a renumber, sweep this plan, tasks.md and the ADR-220/068 amendments.

## Open Code-Review Overlap

1 open scope-out mentions a planned file: #2197 (billing `SubscriptionStatus` refactor) names
`apps/web-platform/infra/server.tf`. **Acknowledge:** a different concern (billing types/docs).
This plan touches only the `connection` blocks, one local and one new `terraform_data`.

## Alternative Approaches Considered

| # | Alternative | Why not |
|---|---|---|
| A1 | Persist known_hosts across runs (actions/cache) | Any workflow on the repo can write the cache, and there is still no check on first contact |
| A2 | `ssh-keyscan` git-data from web-1 after birth and publish the result | TOFU at birth, from a vantage point (web-1) that ADR-220 D4 already names as a possible impersonator |
| A3 | Mint the host key in its own additive-only root (the ADR-220 root-key pattern) | That root cannot rotate by design, and the main root renders `user_data`, which puts the private key in main-root state anyway (CTO). A separate root adds nothing unless the host fetches its own key (A4) |
| A4 | The host generates its own key and publishes it with a write-scoped Doppler token | The token sits in user_data. Anyone who roots the old host can overwrite the pin after a replace unless the token rotates too |
| A5 | Rotate web-1's key in place to a TF-minted key via a provisioner | Violates `hr-prod-host-config-change-immutable-redeploy`, and the swap connection would itself be TOFU |
| A6 | App fails closed on an absent pin immediately | Every production erasure would fail, with a false "erasure pending" shown to users, until step 3 |
| A7 | Keep the git-data key stable across replaces and rotate only on explicit request (advisor) | Removes the lockstep, but a fresh replace would then keep a key a rooted host could have exfiltrated during the read-only period. That defeats the purpose of ADR-220 D6's fresh replace, and the operator stated rotation on replace. D6's redeploy dispatch bounds the lag instead. Recorded, not adopted |
| A8 | Two-slot pins (current + next pre-published) so rotation never lags | Adds a slot variable, a second key in state and a two-step rotation. Lag is already bounded by D6 |

## User-Brand Impact

- **If this lands broken, the user experiences:**
  - **Account deletion.** Art. 17 erasure of the user's git-data bare repo reports
    `host_key_mismatch` or `unconfigured`. `account-delete.ts` then marks
    `gitDataErasurePending` and sends the user to `/login?deleted=true&erasure=pending`, which
    tells them the erasure "will be completed". Before cutover the store is empty, so that
    notice would be **false**. After cutover it is **true**, and nothing retries automatically.
    The route to a human is the paging Art. 17 alert plus the sweep runbook, which locates the
    repo by the deliberately retained `gitDataRepoId`.
  - **Workspace code (after cutover).** A failed replication push or workspace fetch leaves
    stale or missing code in the user's workspace.
  - **Operator side.** All 5 bridge callers fail closed. That includes the daily at-rest
    encryption verdict behind a published Article 32 claim; the CLO's claim-decay handling
    applies.
- **If this leaks, the user's source code is exposed via:** anyone who impersonates git-data,
  from the Cloudflare-edge position, a compromised web-1 or the private net, receives the user's
  pushed objects. That is possible today because nothing verifies the host. After this change
  an attacker also needs git-data's host private key, which lives in main-root TF state, in
  git-data's user_data and on the host. A mis-shaped pin could inject known_hosts wildcards;
  Guard 3 closes that.
- **Brand-survival threshold:** `single-user incident`. `requires_cpo_signoff: true` (CPO
  approved with changes, all folded in: see Domain Review).
  `soleur:engineering:review:user-impact-reviewer` runs at review.

## Observability

```yaml
liveness_signal:
  what: "Conclusion of the daily workspaces-luks-verify.yml run (it connects to web-1 only through the pinned key); the merge-triggered apply's web_1_host_key_probe; the app startup line git_data_pin=present|absent in Better Stack"
  cadence: "daily for the verify run; per infra merge or Terraform bump for the probe; per deploy for the startup line"
  alert_target: "workspaces-luks-verify scheduled-failure issue (#6808); sentry_alert.art17_erasure_incomplete email (issue owners, fallthrough ActiveMembers) for erasure outcomes"
  configured_in: ".github/workflows/workspaces-luks-verify.yml; apps/web-platform/infra/sentry/issue-alerts.tf (existing art17_erasure_incomplete, unchanged); apps/web-platform/server/git-data-replication.ts"
error_reporting:
  destination: "Sentry web-platform project (SENTRY_DSN) for the app; GitHub workflow annotations for CI"
  fail_loud: "::error title=git-data-cutover …::verdict=host_key_mismatch reason=changed|unknown|alg; ::error title=git-data-flag-precheck::verdict=git_data_host_key_unavailable reason=absent|invalid|unreadable; Sentry tag erasure_outcome=host_key_mismatch; Sentry op=pin_absent_store_disabled"
failure_modes:
  - mode: "web-1 committed pin wrong, or web-1 re-keyed"
    detection: "merge-time web_1_host_key_probe apply fails; cutover fails host_key_mismatch role=web; workspaces-luks-* runs fail with ssh's raw stderr in the log (no named verdict)"
    alert_route: "workspaces-luks-verify scheduled-failure issue; apply workflow failure notification"
  - mode: "git-data re-keyed but the app did not reload the pin (redeploy job failed)"
    detection: "git_data_redeploy job fails with a pin-lag annotation; erasures emit erasure_outcome=host_key_mismatch; startup line fingerprint differs from the Terraform-printed one"
    alert_route: "art17_erasure_incomplete Sentry alert; workflow failure"
  - mode: "app pin absent while the store is disabled (transitional)"
    detection: "startup line git_data_pin=absent; Sentry op=pin_absent_store_disabled once per process"
    alert_route: "Sentry issue stream (warning); expected to stop after post-merge step 3"
  - mode: "app pin absent or malformed while the store is enabled"
    detection: "resolveGitDataHostKeyPin throws in the caller's guard; erasure reports erasure_outcome=unconfigured"
    alert_route: "art17_erasure_incomplete Sentry alert"
  - mode: "git-data boots with a host key other than the Terraform one"
    detection: "cloud-init boot proof emits stage:sshd_hostkey fatal via git-data-emit; git_data_boot_verify turns the replace job red before any redeploy"
    alert_route: "existing git_data_boot_fatal route (Sentry + Better Stack); workflow failure"
logs:
  where: "GitHub Actions run logs; Sentry; Better Stack (git-data boot emits, container stdout incl. the startup pin line)"
  retention: "Actions logs 90 days; Sentry and Better Stack per plan retention"
discoverability_test:
  command: "curl -s --max-time 10 https://api.github.com/repos/jikig-ai/soleur/actions/workflows/workspaces-luks-verify.yml/runs?per_page=1 | jq -r '.workflow_runs[0].conclusion'"
  expected_output: "success"
```

## Encryption Posture

```yaml
at_rest: []   # no new persistent store. The new tls_private_key and the user_data embedding it live in the existing main-root TF state (R2 soleur-terraform-state), like tls_private_key.ci_ssh.
in_transit:
  - connection: "GitHub runner -> web-1 sshd (bash callers, via cloudflared access tcp)"
    enforced_at: ".github/actions/cf-tunnel-ssh-bridge/action.yml step 'Decode CI SSH private key…' (WEB_HOST_SSH: StrictHostKeyChecking=yes, HostKeyAlias=web-1) + write-known-hosts.sh"
    tls: "SSH-2 inside a Cloudflare-verified TLS tunnel (ECDSA-P256 host key)"
    cert_verification: on
    does_not_defend: "a compromised web-1 (holds the real key); a stolen CI SSH key plus CF Access token (authenticates as CI, not as the host)"
    disclosed_as: "not-publicly-claimed"
  - connection: "GitHub runner / operator -> web-1 sshd (Terraform connection blocks)"
    enforced_at: "apps/web-platform/infra/server.tf local.web_1_ssh_host_key + host_key in every connection block (server.tf, ci-ssh-key.tf)"
    tls: "SSH-2 (Go crypto/ssh, ECDSA-P256 host key)"
    cert_verification: on
    does_not_defend: "same as above"
    disclosed_as: "not-publicly-claimed"
  - connection: "GitHub runner -> git-data sshd (direct-tcpip via web-1, git-data-cutover.yml)"
    enforced_at: ".github/workflows/git-data-cutover.yml step 'Write git-data ssh_config' (Host 10.0.1.20: StrictHostKeyChecking yes, HostKeyAlias git-data) + git-data-flag-precheck.sh pin read"
    tls: "SSH-2 end-to-end runner<->git-data, nested in the web-1 session (ED25519 host key)"
    cert_verification: on
    does_not_defend: "a reader of main-root TF state or git-data metadata who also has a network position; a rooted git-data host"
    disclosed_as: "not-publicly-claimed"
  - connection: "web-1 app container -> git-data sshd (private net, git-auth.ts)"
    enforced_at: "apps/web-platform/server/git-auth.ts gitWithPrivateKeyAuth/sshWithPrivateKeyAuth (hostKeyPin); apps/web-platform/server/git-data-replication.ts resolveGitDataHostKeyPin"
    tls: "SSH-2 over the Hetzner private network (ED25519 host key)"
    cert_verification: on
    does_not_defend: "the transitional null-pin arm (see exception); a rooted web-1 (holds the transport keys)"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "Until the first git-data replace publishes GIT_DATA_SSH_HOST_KEY and git_data_redeploy loads it, the app keeps the accept-new arm, reachable only with no pin in env AND the store flag off; the store holds no repository until the flag is first set, and deleting the arm is a precondition for that. Failing closed now would fail every production Art. 17 erasure."
  tracking_issue: "#5914"
  reevaluate_when: "post-merge step 3 completes (startup line git_data_pin=present) — the #5914 follow-up PR then deletes the arm"
  expires_on: 2026-12-20
```

## Architecture Decision (ADR/C4)

### ADR

- **Create ADR-235 (provisional ordinal): "SSH host keys are pinned".** The decisions:
  - Hosts born by Terraform get Terraform-minted ED25519 host keys, installed through cloud-config `ssh_keys` and checked by a boot proof.
  - The host's replace job rotates the key. The public key is published as a TF-owned Doppler `prd` secret, and a follow-on job reloads it into the app.
  - Hosts that cannot be re-provisioned (web-1) get a committed, reviewed ECDSA-P256 pin, captured from a vantage outside Cloudflare. ECDSA is a constraint of x/crypto's host-key preference order for the pinned Terraform version. The probe re-runs on Terraform bumps, so a change there breaks applies loudly.
  - `accept-new` and `UserKnownHostsFile=/dev/null` are banned outside Guard 1's allow-list.

  Consequences:
  - a CI-to-CI dispatch edge (the replace job triggers `web-platform-release`), which C4 does not model;
  - the rung-2 interlock leaves no gated emergency replace between merge and the evidence PR, so the break-glass path is the operator-local apply.

  Residuals: key exposure through main-root state and user_data (#8209, F5); web-1's single capture event, cross-checked before merge by AC15; the transitional app arm (#5914).

  Alternatives A1–A8. Status `adopting` until post-merge step 4, then `accepted`.
- **Amend ADR-220.** Add an amendment-log entry:
  - D4's first residual is closed by ADR-235, effective at step 4.
  - D2's `accepted` precondition points to ADR-235.
  - D6's fresh replace now rotates the host key and redeploys the app. Record this as a design change.
- **Amend ADR-068.** Add one line at "Rotations against a populated store stay gated on #7226".

### C4 views

All three files were read (`model.c4` 820 lines, `views.c4` 104, `spec.c4` 54). Checked:

- **External actors:** none new. The Cloudflare-edge adversary is a threat position, not a
  modeled actor.
- **External systems:** `github`, `tunnel`, `doppler`, all already modeled.
- **Containers/stores:** `hetzner` (web-1), `gitDataStore`, both already modeled.
- **Changed relationships** (description text only, no new element or edge):
  - `github -> tunnel`: state that web-1's host key is pinned (committed ECDSA-P256 pin, used by the bridge and by the
    Terraform provisioners);
  - `github -> gitDataStore`: replace "Host keys unverified on both hops (#7226), so the store
    answers are unauthenticated" with the pinned state, effective at step 4;
  - `claude -> gitDataStore`: add "host key pinned via GIT_DATA_SSH_HOST_KEY (ADR-235)";
  - `doppler -> claude`: edit only if the edge lists secret names.
  - `github -> doppler`: the cutover job's new pin read uses the `prd` read token it already
    holds (the flag precheck), so the access set does not change. Confirm the edge text does
    not claim that `prd` is read only for the flag. The replace job dispatching
    `web-platform-release` is a CI-to-CI edge, which C4 does not model; ADR-235 records it
    under its consequences.
- **Cardinalities:** the `github -> tunnel` edge says "17 terraform_data SSH provisioners".
  Leave counts alone unless `plugins/soleur/test/c4-count-parity.test.sh` requires a change. Run
  it together with `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.

### Sequencing

ADR-235 is written now with status `adopting`, and the step-4 docs PR flips it.

## Guard Contract

### Guard 1 — No unpinned host-key option in any SSH consumer

**Property.** No tracked file outside a named allow-list configures an SSH client with
`StrictHostKeyChecking` set to `accept-new`, `no` or `off`, points `UserKnownHostsFile` at
`/dev/null`, or pipes `ssh-keyscan` output into a known_hosts file. The match is
case-insensitive and covers every spelling: `-o K=V`, `-oK=V`, ssh_config `K V`, and TS literals.

**Assembly.** There is no single chokepoint: SSH options appear in workflow YAML, composite
actions, bash, cloud-init templates, TS and HCL. The guard's universe is `git ls-files`, minus
`knowledge-base/**`, minus an allow-list of `path → reason → expected count`. Each entry must hit
exactly its count, so an entry with zero hits is RED. The allow-list:

- `apps/web-platform/infra/git-data-ownership.test.sh`: a local container.
- `apps/web-platform/infra/infra-config-gate.test.sh`: a detector fixture.
- `apps/web-platform/server/git-auth.ts`: exactly 1, the shared `TOFU_FALLBACK_OPTS`.
- the guard script itself.

Test files that need the literal build it by concatenation. The failure message names the
allow-list file and the line to edit. The #5914 follow-up PR removes the `git-auth.ts` entry.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `-o StrictHostKeyChecking=accept-new` to the bridge's `WEB_HOST_SSH` | RED |
| 2 | Enumeration over an empty pathspec ("0 files scanned") | RED (scanned-file floor, and every allow-list entry must be hit) |
| 3 | Bridge compliant; add `stricthostkeychecking no` (lower-case) in a **second**, new file | RED |
| 4 | `UserKnownHostsFile /dev/null` in ssh_config form in cutover.yml | RED |
| 5 | A second TOFU literal in `git-auth.ts` (count 2 ≠ 1) | RED |
| 6 | An allow-list entry for a path with zero hits | RED |
| 7 | `ssh-keyscan 10.0.1.10 >> "$KH"` in a workflow | RED |

**Harness rows.**

- **H-a:** stub the assertion to `exit 0`. The harness's must-RED run (mutation 1 on a temp copy) must still fail.
- **H-b (must-PASS, not canonical):** a file with `StrictHostKeyChecking=yes` and `UserKnownHostsFile=/tmp/kh`.

**Anchor.** The allow-list lives in the reviewed script. There is no stored hash.

### Guard 2 — Every Terraform SSH connection block pins the host key

**Property.** Every `connection {}` block with `type = "ssh"` in any `.tf` under
`apps/web-platform/infra/` sets `host_key`. A block whose `host` references
`hcloud_server.web["web-1"]` must set it to `local.web_1_ssh_host_key`.

**Assembly.** All `connection` blocks in every `*.tf` of the root and its modules. Today that is
18 in `server.tf` and 1 in `ci-ssh-key.tf`. The walker skips comment lines (the `tunnel.tf`
comment contains `connection { host }`). It asserts that the count of `host_key` equals the count
of `connection`, and that the count is at least 19.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete `host_key` from the first block | RED |
| 2 | Delete it from the **last** block only | RED |
| 3 | Walker finds 0 blocks | RED (floor) |
| 4 | Add a new `terraform_data` + `connection` without `host_key` in a different `.tf` | RED |

**Harness rows.** The mutation test runs rows 1 and 3 on a temp copy. Must-PASS: different
whitespace or attribute order, and the `tunnel.tf` comment is not counted.

**Anchor.** None. The structural parse runs every time.

### Guard 3 — Pin shape validation

**Property.** A pin is accepted only if it is exactly one key of the expected algorithm, with no
newline, host pattern, marker or comment:

- ED25519 (git-data): `^ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+/]{43}$` (68 base64 characters, no padding).
- ECDSA-P256 (web-1): `^ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBB[A-Za-z0-9+/]{86}=$`. That is 140 characters: the fixed 0x04 point prefix encodes as `B`, and one `=` of padding.

**Assembly.** Three code sites turn a pin into trust:

- `write-known-hosts.sh`: every bash path, both algorithms.
- `resolveGitDataHostKeyPin`: TS, ED25519.
- `local.web_1_ssh_host_key`: the HCL `regex()`, ECDSA.

Each regex carries a `# twin:` comment naming the others.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Pin `<valid>\n* ssh-rsa AAAA…` fed to each site | RED (reject) at all 3 |
| 2 | Trailing comment `… host@x` | RED |
| 3 | An `ssh-rsa` key, and a truncated ECDSA key (139 characters) | RED |
| 4 | The pin file carries two key lines | RED (exactly one: the writer and HCL `one()`) |

**Harness rows.** Must-PASS: the committed pin file, plus keys generated at test time with
`ssh-keygen -t ed25519` and `-t ecdsa -b 256`. Never real keys. A writer variant with `$RE`
quoted must go RED on the must-PASS input, which proves the unquoted form matters.

**Anchor.** web-1's fingerprint is in the file header and in the PR body. The file is reviewed.

### Guard 4 — git-data birth/replace plans publish and rotate exactly the pin set

**Property.** A replace plan that replaces `hcloud_server.git_data` is accepted only if two
things hold:

- `tls_private_key.git_data_host_ssh` is created in it. That is either `["delete","create"]`, or `["create"]` on the first rotation, while the key is not yet in state.
- `doppler_secret.git_data_ssh_host_key` is `create`, `update` or replaced.

No other action on either address is allowed. A birth plan must create both. Neither address
may appear in a per-PR apply plan.

**Assembly.**

- the two gate libraries sourced by the jobs;
- the birth and replace `-target`/`-replace` lists;
- the per-PR `-target` list;
- `plugins/soleur/test/terraform-target-parity.test.ts`, the authority on `-target` lists, which runs the lockstep check in both directions.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Server replaced, key `no-op` | RED |
| 2 | Server replaced, key absent from the plan | RED |
| 3 | Key rotated, secret absent | RED |
| 4 | A second tls address created | RED (out of scope) |
| 5 | Drop the `-replace='tls_private_key.git_data_host_ssh'` line | RED (lockstep) |
| 6 | Add `doppler_secret.git_data_ssh_host_key` to the per-PR list | RED |

**Harness rows.**

- **Must-PASS, not canonical:** (i) a first rotation where the key and the secret are create-only; (ii) the secret as `update`.
- **A local-backend fixture:** `terraform plan -replace=tls_private_key.x` on an address absent from state plans a create and exits 0. This proves the first-rotation assumption.
- **Must-RED rows** edit a **copy** of the fixture.

**Anchor.** The allow-sets are reviewed code. The root-key fingerprint anchor is unaffected.

### Guard 5 — App transport is pinned whenever a pin exists

**Property.** Whenever a pin resolves, every git-data SSH invocation from the app passes
`StrictHostKeyChecking=yes` and `HostKeyAlias=git-data`, and its known_hosts file is exactly
`git-data <pin>`. With the store enabled and no valid pin, no invocation happens. A mismatch
surfaces as `host_key_mismatch`, never as `unauthorized` or `unreachable`. An invalid pin in
the erasure path surfaces as `unconfigured`.

**Assembly.** The two helpers in `git-auth.ts` are the chokepoint for ssh and git-over-ssh to
git-data. Callers: `fetchFromGitData`, `provisionGitDataRepo`, `removeGitDataRepo`,
`replicateToGitData`. Two work-phase checks confirm there is no other path:

- run `git grep -nE "execFile(Async)?\(\s*\"(ssh|git)\""` under `apps/web-platform/server`;
- confirm that nothing (`inflight-checkpoint.ts`, the agent sandbox) runs `git push/fetch git-data` through the persistent `git-data` remote outside the helpers.

Any such site is a second chokepoint and must be listed. The required positional `hostKeyPin`
makes TypeScript enforce the parameter at every caller.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | The helper ignores `hostKeyPin` | RED |
| 2 | Flag on + absent pin returns `null` | RED |
| 3 | The pinned arm is correct in `gitWithPrivateKeyAuth` only | RED |
| 4 | known_hosts keyed by address while `HostKeyAlias` is set | RED |
| 5 | Mismatch stderr classified as `unauthorized` | RED |
| 6 | Pin resolved inside `removeGitDataRepo`'s ssh `try` (an invalid pin becomes `unreachable`) | RED |
| 7 | `provisionGitDataRepo` passes `null` although a pin is set | RED |

**Harness rows.** known_hosts content is read **inside** the mocked `execFile` call. The file is
unlinked in `finally`, so reading it afterwards proves nothing. Must-PASS: a pin with surrounding
whitespace is trimmed and accepted.

**Anchor.** None.

## Implementation Phases

### Phase 0: Capture web-1's pin (before any code)

- Write `scripts/capture-web-1-host-key.sh`, then run it. It:
  - checks that the egress IP is in `ADMIN_IPS` (a read-only Doppler get; if it is not, run `soleur:admin-ip-refresh` first, with its own ack);
  - runs `ssh-keyscan -T 10 -t ecdsa <web-1 public IPv4>` and `ssh-keygen -lf`;
  - cross-checks with `ssh-keygen -F <ip>`;
  - writes the header.
- There is no login.
- If web-1 has no ECDSA-P256 key, **stop and re-plan** (A5 is forbidden).

### Phase 1: Tests first (RED)

- Fixtures and harness rows for Guards 1–5.
- Precheck test rows.
- Update the assertions that currently expect TOFU literals to the pinned forms.
- Replication and erasure tests: `host_key_mismatch`, guarded pin resolution, `provisionGitDataRepo`.

### Phase 2: Infra + CI (GREEN)

- **git-data.** `git-data.tf` (key, secret with `depends_on`), the module, cloud-init (key block, `HostKey`, boot proof), the rehearsal root, and the evidence-file delete.
- **Workflows.** The `-target`/`-replace` lists, the gate allow-sets, the target-parity test, the probe + `terraform_version` variable, the `dispatch-web-redeploy` action, and the two redeploy jobs.
- **Consumers.** `server.tf` + `ci-ssh-key.tf`; the writer; the bridge; the flag precheck; cutover.yml; the cutover.sh verdicts.
- **Checks.** `terraform fmt -check` and `terraform validate` on both roots, then the render/budget suites and the gate suites.

### Phase 3: App (GREEN)

- The resolver, the helper parameter and `TOFU_FALLBACK_OPTS`, the callers, the new outcome, the startup line and the Sentry reports.
- `tsc --noEmit`, then vitest on the touched tests.

### Phase 4: Docs + legal

- The runbook, ADR-235, the ADR-220/068 amendments, the C4 edge text and C4 tests, and the workspaces-luks-verify comment.
- PA-36, the counsel-audit addendum, and the encryption ledger.
- File F1, F2, F4, F5, and add the notes on #8211 and #5914.

### Phase 5: Pre-merge verification

- Push the branch and dispatch `workspaces-luks-verify.yml --ref <branch>` (AC15).

## Deferrals (file as GitHub issues in the work phase; milestone per `knowledge-base/product/roadmap.md`; verify labels with `gh label list` first)

- **F1:** Terraform-minted host keys for web hosts in `cloud-init.yml`, which would retire the committed web-1 pin at the next web-1 birth or replace. Re-evaluate when #6931 closes.
- **F2:** An independent vantage on git-data: the dry run runs `ssh-keyscan 10.0.1.10` on git-data over the authenticated session and compares the result against the committed pin. Optional hardening.
- **F3:** None. Removing the `null` arm is tracked by **#5914** itself (Ref, not Closes).
- **F4:** After #8453 merges, refresh the outcome list in the `art17_erasure_incomplete` comment (`issue-alerts.tf`) to include `host_key_mismatch`. This is a comment-only change; routing is already correct.
- **F5:** Block non-root access to the Hetzner metadata endpoint on git-data (nftables `meta skuid != 0 ip daddr 169.254.169.254 drop`). This is a hash-bound payload change, so it rides on the next payload PR.
- **Notes (comments, not issues):**
  - on #8211: make `TOFU_ARM present` and a missing pin refusals in the rebuilt real modes, and let the same-version redeploy supersede `git_data_redeploy`;
  - on #5914: its closing PR is post-merge step 5.

## Risks

- **R1: a routine apply publishes a pin the live host does not carry.**
  - **Mitigation.** Neither address is on any per-PR `-target` list, and Guard 4 row 6 enforces that. The secret also `depends_on` the server.
  - **Expected drift.** `scheduled-terraform-drift` will show a pending **server replace** and the key and secret creates until step 3. The runbook says this is expected.
- **R2: pin lag after a rotation.** D6 bounds it to one release cycle. If the redeploy job fails, erasures page through the Art. 17 alert, and the fix is to re-run that job. #8211 inherits this.
- **R3: rung-2 interlock.** This PR voids the evidence. Birth and replace, including an emergency replace, refuse until the evidence PR lands. Break-glass is the operator-local apply (ADR-096), and ADR-235 records the gap.
- **R4: Terraform algorithm negotiation.** Terraform 1.10.5 uses x/crypto v0.27.0, which negotiates ECDSA-P256 against Ubuntu's default host keys (CTO source read). The web-1 pin is therefore ECDSA. If a later Terraform bump changes that preference, the probe re-runs (its trigger includes `terraform_version`) and fails loudly.
- **R5: web-1 lacks ECDSA-P256.** Phase 0 stops.
- **R6: byte budget.** About 2 KB of the ~11 KB headroom. The redeploy logic lives in a composite action, and `workflow-file-size.test.ts` checks the budget.
- **R7: partial replace.** The secret is written only after the server exists (`depends_on`). If the boot proof or `git_data_boot_verify` fails, the job goes red before any redeploy. Re-dispatch the replace.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (CPO sign-off because of the single-user-incident threshold)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Approve with changes. All changes are folded in:

- R4 is resolved: Terraform negotiates ECDSA, so the Terraform pin uses ECDSA.
- The A3 rationale changed: user_data already puts the key into main-root state. Metadata-endpoint access is deferred to F5.
- The R2 lag is bounded mechanically (D6).
- A boot proof was added.
- The expected drift is documented.
- There is a runbook note for operator-local applies.
- Guard 1 now covers `ssh-keyscan`.
- Guard 5 now includes a census of the persistent remote.

On the devex panel: D6 now uses the baseline-`databaseId` pattern and a 75-minute timeout; the release note marks it as a pin rotation; Phase 0 has a capture script; Guard 1's error names the allow-list line.

### Legal (CLO)

**Status:** reviewed
**Assessment:** No published document changes and DC-1 is unaffected, so this does not block. Folded in:

- a new PA-36 §(g) item and a (g)(11) correction;
- an addendum to the counsel audit: a host-key failure counts as "unavailable", not as trigger (3);
- H4 escalation: a wrong capture unresolved after 21 days goes to the CLO, and an unexplained mismatch goes to breach-notice triage;
- the flag-flip precondition;
- ledger connections.

### Product/UX Gate

**Tier:** none. No UI-surface path appears in Files to Edit or Files to Create.
**Decision:** CPO signed off with changes, all folded in:

1. User-Brand Impact names the `erasure=pending` notice, including the case where it is false.
2. The lag is bounded mechanically (D6).
3. Deleting the `null` arm (#5914) is a hard precondition for the flag flip.
4. A `host_key_mismatch` on erasure pages through the existing Art. 17 alert, which routes by `op`.

**Agents invoked:** soleur:product:cpo, soleur:product:spec-flow-analyzer
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

### SpecFlow (Phase 3 + plan-review re-validation)

**First pass:** C1–C5 and I1–I4 are folded in.

**Re-validation.** The fixes:
- **I1:** the HCL `one()` selection is now written out.
- **C4:** the precheck emits a `TOFU_ARM` line and refuses on an absent pin.
- **I2:** verdicts are collapsed, and the observability text is corrected for the workspaces-luks callers.
- **D6:** the redeploy job is its own job. It tracks the run by baseline `databaseId`, accepts any later successful release, requires a non-skipped deploy, has a 75-minute timeout and sits outside the apply lock.
- **Step 5:** now gated on the positive startup line.
- **Ordering:** `depends_on` the server; the boot proof runs before the redeploy.
- **Step 1:** the "any merge-triggered apply" clause is added.
- **Guard 1:** the #5914 follow-up removes the allow-list entry.

### Plan review (eng panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow; named panel: CTO devex)

- **Mechanical, applied:**
  - web-1 pin is ECDSA only;
  - one `prd` secret (the pin read moved into the `prd`-scoped precheck step);
  - verdicts collapsed from six to two;
  - the Guard 3 parity check replaced by `# twin:` comments;
  - pin resolution guarded **before** the ssh `try` (Kieran P0);
  - `provisionGitDataRepo` added;
  - one `TOFU_FALLBACK_OPTS` literal, matched case-insensitively;
  - H4 classifier order fixed;
  - `private_key_openssh` specified;
  - exact regex lengths;
  - `hostKeyPin` placed before `opts`;
  - `github.action_path` and `UpdateHostKeys=no`;
  - D6 as a separate job with robust run tracking;
  - the probe re-triggered on Terraform version;
  - `terraform-target-parity.test.ts` and a local-backend `-replace` fixture;
  - the pre-merge verify dispatch (AC15);
  - the ADR-220 design-change note;
  - the rung-2 emergency-replace gap recorded.
- **User-Challenge, persisted to `decision-challenges.md`, not applied:**
  - DC-1: split the app change into a strict-only second PR, which would remove the `null` arm. DHH P0 and code-simplicity agree.
  - DC-2: replace D6 with a runbook step (DHH), which conflicts with the CPO's requirement for a mechanical bound.
- **Taste, kept as planned:**
  - Keep the boot proof. Code-simplicity suggested cutting it, but the CTO and architecture reviewer need it so the redeploy does not ship a pin the host does not serve.
  - Keep the PA-36 and ADR docs in this PR. DHH suggested deferring them to step 4, but the CLO asked for the DRAFTED items now.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1:** `bash tests/scripts/test-no-tofu-ssh.sh` exits 0, prints a scanned-file count > 0, and every allow-list entry hits its expected count (Guard 1).
- [ ] **AC2:** the bridge's `WEB_HOST_SSH` contains:
  - `StrictHostKeyChecking=yes`
  - `HostKeyAlias=web-1`
  - `HostKeyAlgorithms=ecdsa-sha2-nistp256`
  - `UpdateHostKeys=no`
  - a `UserKnownHostsFile=` that is not `/dev/null`

  The bridge exports exactly `{CI_SSH_KEYFILE, WEB_HOST_SSH}`, and the `infra-validation.yml` assertion is green.
- [ ] **AC3:** `git-data-cutover.yml`'s ssh_config contains no `accept-new` and no `/dev/null`, and both Host blocks carry `HostKeyAlias` and `StrictHostKeyChecking yes`. `git-data-cutover-access.test.sh` passes with rows for `host_key_mismatch reason=changed|unknown|alg`. `git-data-flag-precheck.test.sh` passes with rows for `git_data_host_key_unavailable reason=absent|invalid|unreadable` and `TOFU_ARM present|absent`.
- [ ] **AC4:** Guard 2 passes: `host_key` count == `connection` count, and the count is ≥ 19, across `apps/web-platform/infra/**/*.tf`. The mutation test also passes.
- [ ] **AC5:** `terraform validate` passes in `apps/web-platform/infra` and in `rung2-rehearsal`. The rendered git-data cloud-config parses as YAML and contains `ssh_keys.ed25519_private` / `ed25519_public` and `ssh_deletekeys: true`. `01-hardening.conf` has the `HostKey` line and the boot-proof block. Check this with the render test, not grep.
- [ ] **AC6:** the replace and birth gate suites pass with the Guard 4 rows, including both first-rotation must-PASS variants and the local-backend `-replace` fixture. `terraform-target-parity.test.ts` passes. The per-PR list contains the probe and neither pin address.
- [ ] **AC7:** `git-data-rung2-boot-evidence.env` is absent from the tree. The rung-2 suites pass with the new MAY-DIVERGE variables.
- [ ] **AC8:** the Guard 5 vitest matrix passes. It covers `host_key_mismatch` classification, an invalid pin returning `unconfigured` (not `unreachable`), and `provisionGitDataRepo` passing the pin. `tsc --noEmit` is clean.
- [ ] **AC9:** `web-1-ssh-host-key.pub` has exactly one ECDSA-P256 line that passes Guard 3, and its header fingerprint equals `ssh-keygen -lf` of that line. The PR body names the capture vantage point and the cross-check result.
- [ ] **AC10:** the runbook's "#7226 — pin git-data's SSH host key…" bullet is replaced by a staged list: mechanism merged ✔, post-merge steps 1–5 as open items, and the flag-flip precondition "pin present in prd AND #5914 closed". The runbook also has the verdict rows, the expected-drift note, the emergency-replace gap and the re-capture section.
- [ ] **AC11:** ADR-235 exists with status `adopting`, and its ordinal is free across all `origin/*` refs at merge time. The ADR-220 amendment (including the D6 design change) and the ADR-068 amendment exist. The C4 edge text is updated, and `c4-count-parity`, `c4-code-syntax` and `c4-render` pass.
- [ ] **AC12:** the PA-36 §(g) item and the (g)(11) correction exist. The counsel-audit addendum exists. `python3 scripts/lint-encryption-posture.py --repo-sweep` passes with the four new connections.
- [ ] **AC13:** `workflow-file-size.test.ts` passes, and so does the git-data user_data budget suite.
- [ ] **AC14:** `bash tests/scripts/test-write-known-hosts.sh` passes. The `dispatch-web-redeploy` action's embedded shell passes `bash -c` syntax checks. Both `git_data_redeploy` jobs carry `permissions: {actions: write, contents: read}` and no `secrets.` reference. F1, F2, F4 and F5 are filed with labels that exist.
- [ ] **AC15:** after pushing, `workspaces-luks-verify.yml` dispatched with `--ref <branch>` ends `success`. This is the strict bash path through Cloudflare, and it is the second observation of web-1's pin.

### Post-merge (operator; each separately authorized; runbook Post-merge sequence)

- [ ] Step 1: every merge-triggered apply that follows is `success` (the probe ran).
- [ ] Steps 2–5 as described in the runbook. Step 4 flips ADR-235 to `accepted` and ticks the precondition. Step 5 closes #5914.

## Test Scenarios

- Given the committed pin, when `write-known-hosts.sh` receives a pin with an embedded newline and a second `* ssh-rsa` line, it rejects the pin and writes no file.
- Given `GIT_DATA_SSH_HOST_KEY` is absent in prd, when the precheck runs, it prints `verdict=git_data_host_key_unavailable reason=absent`, exits 5, and no bridge or ssh step runs.
- Given `GIT_DATA_STORE_ENABLED=true` and no pin, when `replicateToGitData` runs, no `execFile` happens and the turn is not broken.
- Given the store is disabled and there is no pin, when `removeGitDataRepo` runs twice, ssh uses the fallback options and Sentry receives exactly one `pin_absent_store_disabled`.
- Given an invalid pin, when `removeGitDataRepo` runs, it returns `{status:"unconfigured"}` and does not throw.
- Given a valid pin, when `sshWithPrivateKeyAuth` runs, the known_hosts file read inside the mocked call is exactly `git-data <pin>\n`, and argv contains `StrictHostKeyChecking=yes` and `HostKeyAlias=git-data`.
- Given ssh stderr `REMOTE HOST IDENTIFICATION HAS CHANGED` with exit 255, `removeGitDataRepo` returns `host_key_mismatch`. Given `No ED25519 host key is known for git-data`, it also returns `host_key_mismatch`. Given `Permission denied (publickey)`, it returns `unauthorized`.
- Given a first-rotation replace plan (the key and the secret are create-only), `git_data_host_replace_gate` returns PASS. With the key as `no-op`, it returns ABORT.
- Given a `web-platform-release` run history where the dispatched run is cancelled and a later push-triggered run deploys successfully, the redeploy action succeeds. If the only newer run's deploy job is `skipped`, the action fails when it times out.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- Three different things share the `ssh_keys` name:
  - cloud-config `ssh_keys:` (host keys, a dict);
  - `hcloud_server.ssh_keys` (Hetzner authorized-key ids);
  - `ssh_authorized_keys:`.
- Use `private_key_openssh`, never `private_key_pem`, for the ED25519 host key. The `indent()` width must match the template column.
- The rendered user_data stays `sensitive = true`. Never `nonsensitive()` it for a budget printout.
- `HostKeyAlias` changes the name ssh looks up in known_hosts. The file must hold `web-1 …` / `git-data …`, not IPs.
- Algorithms: web-1 is pinned **ECDSA-P256** everywhere, because Terraform forces it. git-data is **ED25519**, because Terraform mints it and the TF provisioners never connect to git-data. Do not change either without re-reading x/crypto's preference order for the pinned Terraform version.
- Never add `ssh-keyscan` to a CI path as a pin source (Guard 1 row 7). `scripts/capture-web-1-host-key.sh` refuses to run in CI.
- `HostKey` lines accumulate across sshd drop-ins; the `01-` first-match rule does not apply to them. The boot proof's "exactly one hostkey" is the real guarantee.
- The rewritten `workspaces-luks-verify.yml` comment must not quote the old option literals (Guard 1).
- `accept-new` stays in exactly one place (`TOFU_FALLBACK_OPTS`, counted by Guard 1). #5914 removes it before any store-enable.
- Do not edit `apps/web-platform/infra/sentry/**` in this PR. #8453 owns that surface.

