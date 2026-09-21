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

## Enhancement Summary

**Deepened on:** 2026-09-21. Every section was touched.

**Agents used:**
- deepen pass: security-sentinel, framework-docs-researcher, deployment-verification-agent, observability-coverage-reviewer, test-design-reviewer, verify-the-negative / self-audit (sonnet)
- plan-review panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CTO devex
- domain leaders: CTO, CLO, CPO
- advisor consult

### Key improvements

1. **The startup pin line now actually reaches Better Stack.** Vector ships only lines at level ≥ 40 (warn), so the line is logged at `warn`.
2. **The boot-proof fatal is routed.** It uses the existing `stage:sshd_config` with a `detail`, so no Sentry TF change is needed while #8453 owns that file.
3. **ssh error output is treated as hostile.** A compromised jump host controls the banner, so verdicts come from the exit code plus anchored patterns, and workflow commands in that output are stopped with `::stop-commands::`.
4. **Other ssh config cannot add trust.** The app runs `-F /dev/null`, and every path sets `GlobalKnownHostsFile=/dev/null`.
5. **Two new guards.** Guard 6 is the boot proof. Guard 7 is the redeploy tracker, tested with a `gh` stub.
6. **Guard 2 is per block.** It checks each block instead of comparing totals.
7. **The HCL pin selector matches the bash writer's "exactly one key line" rule.**
8. **Hardening elsewhere:** CODEOWNERS rows for the trust files, gate libraries that never print plan before- or after-values, and a redeploy job restricted to `main` with a sparse checkout that does not persist credentials.
9. **ADR ordinal moved from 235 to 237.** 235 and 236 are already claimed on pushed branches.

### New considerations discovered

- **Phase 0 needs an admin-IP refresh.** The planning session's egress IP is **not** in `ADMIN_IPS` (checked 2026-09-21). The direct-vantage capture therefore needs `soleur:admin-ip-refresh` first.
- **`Downtime & Cutover`:** the only offline surface is git-data during the replace. The store is empty and the flag is off, and the only live traffic, Art. 17 erasure, pages and is swept.
- **Unverified against docs** (documentation was unreachable):
  - cloud-init's rule that `ssh_keys` skips key generation;
  - Terraform's `@cert-authority` host_key form.

  The CTO confirmed both by reading source. The work phase proves them through the rung-2 rehearsal and the merge-time probe, not by assertion.

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
    - a fingerprint or count mismatch emits a fatal under the **already-routed** `stage:sshd_config`, with `detail=hostkey_mismatch` (or `hostkey_count`), via `git-data-emit`. It deliberately does not use a new `sshd_hostkey` stage, because `git_data_boot_fatal` (`issue-alerts.tf`) routes only a fixed list of stage values, and adding one would mean editing Sentry TF, which #8453 owns. The block extracts the check into a shell function that can be tested (Guard 6);
    - a missing `ssh-keygen` only warns. This follows the block's existing "`sshd -t` must abort, restart must tolerate" rule.

    The replace and birth jobs already run `git_data_boot_verify` (`scripts/lib/git-data-boot-signal-poll.sh`) after the apply, so a fatal here turns the job red **before** D6 redeploys anything. A rung-2 PASS proves the pin is live on a real boot. Keep the existing `systemctl restart ssh`: socket activation can start sshd before cc_ssh writes the keys, and the restart fixes that.
  - **Publishing.** One TF-owned secret: `doppler_secret.git_data_ssh_host_key`, in `soleur/prd`, named `GIT_DATA_SSH_HOST_KEY`. It has the same shape as `doppler_secret.git_data_ssh_host`, `visibility = "unmasked"`, no `ignore_changes`, and **`depends_on = [hcloud_server.git_data]`**, so it is written only after the host that carries the key exists. That narrows the partial-failure window in R7.
  - **Rotation.** The replace job adds `-replace='tls_private_key.git_data_host_ssh'` and `-target='doppler_secret.git_data_ssh_host_key'`. The birth job adds both as `-target`. No per-PR `-target` reaches either one.
  - **Exposure (an ADR-237 residual).** The private key sits in main-root state twice: in the `tls_private_key` and inside `hcloud_server.git_data.user_data`. A separate root would not change that (A3). The Hetzner metadata endpoint also serves user_data to local processes on git-data. Anyone who can read either copy **and** has a network position (the private net or web-1) can pretend to be git-data. This falls within #8209's scope. F5 blocks non-root metadata access.
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
  - *Bridge, bash mode:* runs `"${{ github.action_path }}/write-known-hosts.sh" web-1 "$GITHUB_WORKSPACE/apps/web-platform/infra/web-1-ssh-host-key.pub" "$RUNNER_TEMP/web-1.known_hosts"` and exports `WEB_HOST_SSH="ssh -i $KEYFILE -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$KH -o HostKeyAlias=web-1 -o HostKeyAlgorithms=ecdsa-sha2-nistp256 -o UpdateHostKeys=no -o GlobalKnownHostsFile=/dev/null -o LogLevel=ERROR -l root"`. The exported variables stay exactly `{CI_SSH_KEYFILE, WEB_HOST_SSH}`. Each of the two `workspaces-luks-cutover.yml` jobs writes its own file.
  - *Terraform:*

    ```hcl
    locals {
      web_1_ssh_host_key = regex(
        "^ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBB[A-Za-z0-9+/]{86}=$",  # twin: write-known-hosts.sh
        one([for l in split("\n", replace(file("${path.module}/web-1-ssh-host-key.pub"), "\r", "")) : l if trimspace(l) != "" && !startswith(trimspace(l), "#")]),
      )
    }
    ```

    `one()` selects **every** non-comment, non-blank line. It errors when there are two or more and returns null when there are none, and `regex()` errors on null or on anything that is not the ECDSA line. So the HCL site agrees with the bash writer's "exactly one key line" rule. So every plan that uses the pin fails closed. A `check` block would only warn, and a precondition is skipped by `-target` plans that leave its resource out. All 19 `connection {}` blocks set `host_key = local.web_1_ssh_host_key`. Changing `connection` re-runs no provisioner, so only the probe fires. Operator-local applies now also enforce `host_key` (runbook note).
  - *git-data-cutover.yml:*
    - **Pin read.** `git-data-flag-precheck.sh` already runs as its own step, before the bridge, with `DOPPLER_TOKEN_PRD`. It now also reads `GIT_DATA_SSH_HOST_KEY`, using the same measured `--no-exit-on-missing-secret` semantics. It validates the value and writes it to `$RUNNER_TEMP/git-data.pin`. It refuses (exit 5) with `verdict=git_data_host_key_unavailable reason=absent|invalid|unreadable`. It also prints an informational `TOFU_ARM present|absent` line. The line is read from the file named by `GIT_AUTH_TS_PATH`, which defaults to `apps/web-platform/server/git-auth.ts` in the checkout; tests point it at a fixture. It which the flag-flip precondition uses (D4).
    - **Known hosts.** "Write git-data ssh_config" calls the writer twice into `$RUNNER_TEMP/gd-known-hosts`: `web-1` from the committed file, and `git-data` from `$RUNNER_TEMP/git-data.pin`. It checks the result with `-s`.
    - **Host blocks.** Both blocks set `StrictHostKeyChecking yes`, `UserKnownHostsFile <gd-known-hosts>`, and `HostKeyAlias web-1|git-data`. They set `HostKeyAlgorithms` to `ecdsa-sha2-nistp256` for web-1 and `ssh-ed25519` for git-data. The inner `ProxyCommand ssh -F cfg -W 10.0.1.20:22 10.0.1.10` resolves to the `10.0.1.10` block, so the jump hop is pinned too.
    - **Teardown.** Teardown shreds both files. They hold public data, so this is hygiene only.
  - *git-data-cutover.sh `_access_reason`:* add the H4 branches, in the order given under H4, ahead of `Permission denied`. Each reason gets a test row.
  - *Error-output hygiene (every CI ssh path):* a compromised web-1 controls the jump hop's banner and error output, so treat that text as hostile.
    - The verdict is decided from the **exit code plus line-anchored patterns**. A free `verdict=` substring in ssh output is never matched.
    - Before any echo, strip control characters, including `\x7f`, U+2028 and U+2029.
    - Wrap raw ssh text in `::stop-commands::<random token>`, so an embedded `::error::` or `::add-mask::` cannot become a workflow command.
    - Pins are printed only as `SHA256:` fingerprints, computed after validation. A raw Doppler value is never printed.
    - Test row: a banner containing `::error::` and `verdict=ok` does not change the verdict.
<!-- lint-infra-ignore end -->
- **D4 — app consumer.**
  - **The resolver.** Add `resolveGitDataHostKeyPin(): string | null` to `git-data-replication.ts`. It trims the value first, and the regex never uses the `m` flag, so a value with a trailing newline is rejected rather than half-matched. It returns the valid pin (ED25519 regex, `# twin:` comment) and otherwise:
    - wrong shape: **throw**;
    - absent, and `isGitDataStoreEnabled()` is true: **throw**;
    - absent, and the store is disabled: return `null`, and call `reportSilentFallback({ feature: "git_data_host_key_pin", op: "pin_absent_store_disabled" })` once per process.
  - **Startup evidence.** At app startup, log one line at **`logger.warn` (pino level 40)**. It must be warn, because Vector's `app_container_warn_filter` (`infra/vector.toml`) ships only lines at level ≥ 40 to Better Stack; an `info` line never arrives. Add a code comment saying so. Read it back with `scripts/betterstack-query.sh --since 30m --grep git_data_pin=`. The line: `git_data_pin=present fp=SHA256:<fingerprint>` or `git_data_pin=absent`. This is only the public-key fingerprint. It is the **positive** evidence for post-merge steps 3 and 5. Erasures are rare, so a quiet Sentry proves nothing.
  - **Where the pin is resolved.** Each caller resolves the pin in a **dedicated guard before its ssh `try`**. The existing catch sorts errors by `e.code`, so a resolver throw inside the `try` would be misread as `unreachable`. The callers:
    - `removeGitDataRepo`:

      ```ts
      let pin: string | null;
      try { pin = resolveGitDataHostKeyPin(); } catch (e) { return { status: "unconfigured", detail: String(e) }; }
      ```

    - `provisionGitDataRepo` (its `sshWithPrivateKeyAuth` call): same guard. Its failure goes to the caller's existing report.
    - `replicateToGitData` / `fetchFromGitData`: the existing failure report. Neither ever breaks the turn.
  - **Helper signatures.** The helpers take the pin as a **required** positional parameter, placed before the defaulted `opts`: `gitWithPrivateKeyAuth(args, privateKey, hostKeyPin, opts = {})` and `sshWithPrivateKeyAuth(host, remoteCommand, privateKey, hostKeyPin, opts = {})`.
    - With a pin, the helper writes `git-data <pin>\n` into the per-call 0600 known_hosts file and passes `-F /dev/null`, `StrictHostKeyChecking=yes`, `HostKeyAlias=git-data`, `HostKeyAlgorithms=ssh-ed25519`, `UpdateHostKeys=no`, `GlobalKnownHostsFile=/dev/null` and `LogLevel=ERROR`. `-F /dev/null` and the global-file override stop any user or system ssh config in the container from adding a trusted key or rerouting the connection.
    - With `null`, the helper applies one shared module-level `const TOFU_FALLBACK_OPTS` (the single `accept-new` literal that Guard 1 counts) against the empty file.
  - **New erasure outcome `{ status: "host_key_mismatch"; detail }`.** Classify it in the H4 order, on exit 255, **before** `SSH_AUTH_FAILURE`, and remove `host key verification failed` from `SSH_AUTH_FAILURE`. `account-delete.ts` already routes every non-`erased`/`skipped` status to `erasure_outcome=<status>` under the paging Art. 17 rule. Add the new value to its comment table with the correct remedy: "the web app holds a stale or wrong pin — redeploy; or the host was re-keyed outside the replace job". Widen the union using `tsc --noEmit` as the enumerator.
  - **Why the `null` arm is allowed, and why it cannot outlive the empty store.** Strict mode is impossible until the first replace publishes the pin. Removing the arm now would fail every production erasure and show users a false "erasure pending" notice. The flag condition alone is **not** enough, because repos survive a rollback. So "pin present in prd AND #5914 closed (the arm deleted)" is a **hard precondition for ever setting `GIT_DATA_STORE_ENABLED`**:
    - the runbook states it;
    - the precheck's `TOFU_ARM` line surfaces it;
    - a note on #8211 asks for it to become a refusal when real modes are rebuilt.

    Before the flag is first set, the store holds no repository. DC-1 records the reviewers' alternative: split the app change into a second PR that is strict from its first commit.
- **D5 — rung-2 rehearsal root.** The rehearsal root mints its own `tls_private_key` and passes it to the module. Both new variables are declared **MAY DIVERGE (identity class)**, and the `RUNG2_VAR_DIVERGENCE` allow-list is extended to match. This PR deletes `git-data-rung2-boot-evidence.env` (step 1 of the two-PR sequence).
- **D6 — pin propagation to the app (bounds R2).** Add a new follow-on job, `git_data_redeploy`, in `apply-web-platform-infra.yml`, with `needs: [<birth or replace job>]` and `if: needs.<job>.result == 'success'`. It has `permissions: { actions: write, contents: read }`, no secrets, no Terraform and no environment. It runs only under `if: github.ref == 'refs/heads/main'`, and checks out with `persist-credentials: false` and a sparse checkout of `.github/actions/dispatch-web-redeploy` only. The polling logic lives in `.github/actions/dispatch-web-redeploy/track.sh`, driven by a `gh` stub in tests. Its poll interval and timeout come from env vars, so tests can run in seconds. On timeout, its `::error::` names the baseline `databaseId` and the last one seen. The job summary prints the Terraform-side `SHA256:` fingerprint of the new pin, for the step-3 comparison. It sits outside the apply concurrency group, so it holds no infra lock. Its logic lives in the composite action `.github/actions/dispatch-web-redeploy/action.yml`, and follows the `scheduled-marketplace-drift.yml` precedent:
  1. Record `T0` and the baseline `databaseId` of the latest `web-platform-release.yml` run. Fail closed if the baseline cannot be read.
  2. Run `gh workflow run web-platform-release.yml --ref main -f bump_type=patch`, labelling the release note "pin rotation, no code change".
  3. Poll, bounded by `timeout-minutes: 75` (the release takes ~24 minutes at worst, and the deploy comes on top), for **any** `web-platform-release` run of any event type with `databaseId` > baseline whose deploy job concluded `success`. A `skipped` deploy does not count.
  4. A cancelled dispatched run is tolerated if a later qualifying run succeeds.
  5. On timeout, fail with an annotation naming the pin-lag consequence.

  Recovery is to re-run the failed job, **not** to replace again. A dispatched release is forced past `check_changed`, and `ci-deploy.sh` re-downloads prd. #8211's same-version redeploy can later replace this job; add a note on #8211. DC-2 records the reviewers' preference for a runbook step instead.

### Post-merge sequence (goes into the runbook; each prod step needs its own authorization)

1. **Merge.** Any merge-triggered `apply-web-platform-infra.yml` run from this merge onward runs `terraform_data.web_1_host_key_probe` through the strict Terraform path and must end `success`. The bash path was already proven before merge (AC15).
2. **Rung-2 re-rehearsal** (`REHEARSE-GIT-DATA`, `dry_run=false`, `--ref main`), then the **evidence-only PR**. Schedule the rehearsal right after merge. Until the evidence PR merges, birth and replace refuse, **including an emergency replace**. ADR-237 records this as an accepted gap. The break-glass path is the documented operator-local apply per ADR-096.
3. **git-data-host-replace.**
   - The replace rotates the key, `git_data_boot_verify` passes (which includes the boot proof), and the secret publishes.
   - `git_data_redeploy` succeeds, and Better Stack shows `git_data_pin=present` with the fingerprint Terraform printed.
   - **If the replace job fails after the secret published:** re-dispatch the replace. Guard 4 accepts that plan.
   - **If only `git_data_redeploy` failed:** re-run that job only.
4. **Strict dry run.** Dispatch `git-data-cutover.yml`. It must read `role=git-data-auth verdict=ok` with both hops pinned. Then tick the #7226 line and flip ADR-237 to `accepted` in a docs PR.
5. **The #5914 follow-up PR.** It deletes the `null` arm and `TOFU_FALLBACK_OPTS`, removes `git-auth.ts` from Guard 1's allow-list, and closes #5914. It is gated on the step-3 startup line (`git_data_pin=present` on the current deploy), not on silence. It must merge before any `GIT_DATA_STORE_ENABLED` flip.

Step 3 is not ADR-220 D6's "fresh replace immediately before the real cutover". That replace is still required, and it rotates the pin and redeploys again automatically.

### Research Insights (deepen)

**Network-outage deep-dive** (`hr-ssh-diagnosis-verify-firewall`, L3 → L7):

| Layer | Path | Status |
|---|---|---|
| L3 firewall | CI → web-1: goes through the CF tunnel. The runner's IP needs no allowlist; admission is decided by CF Access (bridge verdict `ci_ssh_access_denied`). | not a dependency |
| L3 firewall | Phase 0 direct capture → web-1 public :22 | **Verified 2026-09-21:** the session's egress IP (`curl -s https://ifconfig.me/ip`) is **not** in Doppler `prd_terraform` `ADMIN_IPS`. Run `soleur:admin-ip-refresh` before Phase 0, then retry. |
| L3 private net | runner → git-data (`-W 10.0.1.20:22`) and app → git-data | Use the existing Private-NIC readiness read. A timeout is H2, never H4. |
| L3 DNS | none | All targets are IP literals or tunnel hostnames already proven by the bridge liveness step |
| L7 TLS | CF edge | cloudflared verifies it (unchanged) |
| L7 SSH identity | all hops | The subject of this plan: named verdicts, per H4 |

**Framework and source verification:**

| Claim | Status |
|---|---|
| TF 1.10.5 vendors `golang.org/x/crypto` v0.27.0 | verified (go.mod at the v1.10.5 tag) |
| x/crypto v0.27.0 lists ED25519 last in `supportedHostKeyAlgos` | verified (common.go) |
| OpenSSH `REMOTE HOST IDENTIFICATION HAS CHANGED`, `No %s host key is known for …` | verified (sshconnect.c) |
| `no matching host key type found` | This comes from key-exchange negotiation (`Unable to negotiate with … : no matching host key type found`), not from sshconnect.c. The classifier matches `no matching host key type found` anywhere in the line. |
| `gh run list --json databaseId,createdAt,event,conclusion`; `gh run view --json jobs` | verified; job-level `conclusion` confirmed from existing repo usage in the work phase |
| cloud-init: `ssh_keys` skips key generation; TF `host_key` written as `@cert-authority`; `private_key_openssh` format | Docs unreachable. The CTO read the source. Proven at rung 2 (boot proof) and at the merge-time probe. |

**Deploy-day go/no-go** (goes into the runbook with the Post-merge sequence):

- **Step 3 GO** requires two things:
  - Better Stack `git_data_pin=present fp=SHA256:X` (`scripts/betterstack-query.sh --since 30m --grep git_data_pin=`), where X equals the fingerprint printed in the `git_data_redeploy` job summary.
  - Zero Sentry events tagged `erasure_outcome=*` between the dispatch and that line. If there are any, follow the sweep runbook using `gitDataRepoId`.
- **The first rotation cannot produce `host_key_mismatch`.** The app had no pin, so it stays on the fallback against the new host until the redeploy. Pin lag matters only from the second rotation on.
- **A full revert of this PR is never the rollback.** It would restore `accept-new`. Every fix goes forward.

**Verify-the-negative:** seven load-bearing negatives were confirmed with file:line (per-PR target set, `ci-deploy.sh` prd download, helper chokepoint, bridge export assertion, no `environment:` on verify, `git_data_boot_verify` in both jobs, catch mapping to `unreachable`). The self-audit found no stale references after the v3 revisions.

## Downtime & Cutover

- **Operation that takes something offline:** post-merge step 3, `git-data-host-replace`. It destroys `hcloud_server.git_data` before creating the new one. The affected surface is the git-data SSH endpoint `10.0.1.20:22`. **No user-serving web surface goes offline.** web-1 is not replaced and not rebooted, and the only new web-1 change is a no-op remote-exec probe. The app's `GIT_DATA_STORE_ENABLED` is off, so no read or write path depends on git-data.
- **What still reaches git-data during the window:**
  - Art. 17 erasure (`removeGitDataRepo`). It is not gated on the flag, so an account deletion during the window gets `unreachable`, which marks `erasure=pending`.
  - `web-git-data-probe.sh`, a TCP heartbeat. It misses during the window.
- **Zero-downtime evaluation.**
  - A blue-green git-data (born fresh at a second address, then cut over) does not fit. `GIT_DATA_SSH_HOST` is fixed at `10.0.1.20` by `network.tf`. The ADR-220 access design, the gates and the runbook all assume a single git-data host. A replace also rotates the key (P4).
  - The store holds no repository (#6976), so there is nothing to drain or copy.
  - The path is therefore a **bounded replace**, the same operation ADR-220 D6 already requires. This plan adds no new replace; it adds key rotation to the existing one.
- **Bounding and mitigation:**
  - Dispatch in a low-traffic window.
  - The boot-verify poll bounds the window (`git_data_boot_verify`, the existing timeout).
  - An erasure that fails in the window pages through `art17_erasure_incomplete`. It is then retried by the sweep runbook, which locates the repo by `gitDataRepoId`. Before cutover the store is empty, so no data is owed and the retry is a no-op success.
  - The heartbeat gap is expected; the runbook already covers it under git-data replaces.
- **Rollback per stage:**
  - Replace failed before the server exists: nothing was published (the secret `depends_on` the server). Re-dispatch the replace.
  - Replace failed after the secret was published: re-dispatch the replace.
  - Only `git_data_redeploy` failed: re-run that job.
  - Never re-enable `accept-new`.
- **Sign-off:** each step needs its own operator authorization (`hr-menu-option-ack-not-prod-write-auth`). The residual unavailability (git-data only, store empty) is accepted as the same window ADR-220 D6 already accepted.

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
- `apps/web-platform/infra/git-data-cutover.sh`: the H4 branches and the error-output hygiene (D3).
- `.github/CODEOWNERS`: explicit rows for `apps/web-platform/infra/web-1-ssh-host-key.pub`, `.github/actions/cf-tunnel-ssh-bridge/`, `.github/actions/dispatch-web-redeploy/`, `apps/web-platform/server/git-auth.ts`, and `tests/scripts/lib/git-data-host-{replace,birth}-gate.sh`. Keep these paths off any auto-merge label path. Check whether branch protection enforces code-owner review (`gh api repos/jikig-ai/soleur/branches/main/protection`). If it does not, record the gap in ADR-237 rather than claiming a review anchor that nothing enforces.
- `tests/scripts/lib/git-data-host-{replace,birth}-gate.sh`: failure output prints only `.address` and `.change.actions`, never `.change.before` or `.change.after`, because the replace plan's before-values carry the old user_data and host key. Add a test row that fails if a gate prints those fields. `tfplan.json` is not uploaded as an artifact today (the only `upload-artifact` in the workflow uploads a manifest); keep it that way.
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
- `knowledge-base/engineering/architecture/decisions/ADR-220-*.md`: an amendment-log entry. D4's first residual is closed by ADR-237 (effective at step 4). **D6's pre-cutover fresh replace now also rotates the host key and redeploys the app**; record that as a design change.
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
- `.github/actions/dispatch-web-redeploy/action.yml` + `track.sh`: D6 logic (Guard 7).
- `tests/scripts/test-dispatch-web-redeploy.sh`: Guard 7, with a `gh` stub.
- `apps/web-platform/infra/web-1-host-key-local.test.sh`: runs `terraform console` in a scratch copy with no providers, against fixture pin files: 0 lines, 2 lines, CRLF, a trailing comment, a leading space, and a truncated key. Each must error; the valid file must return the key. It also checks structurally that the precheck step comes before the bridge step in `git-data-cutover.yml`.
- `scripts/capture-web-1-host-key.sh`: the Phase 0 capture as one command. It runs keyscan, prints the fingerprint, cross-checks against the operator's known_hosts, and writes the header. It refuses to run when `CI`/`GITHUB_ACTIONS` is set (Guard 1 row 7). It also serves future re-captures.
- `tests/scripts/test-no-tofu-ssh.sh`: Guard 1. Confirm that the CI runner's `tests/scripts/test-*.sh` glob picks it up.
- `tests/scripts/test-write-known-hosts.sh`: Guard 3 fixtures for the bash writer.
- `knowledge-base/engineering/architecture/decisions/ADR-237-ssh-host-keys-are-pinned.md`. The ordinal is **provisional**: re-probe across all `origin/*` refs right before merge. On a renumber, sweep this plan, tasks.md and the ADR-220/068 amendments.

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
    detection: "merge-time web_1_host_key_probe apply fails with ::error:: on the apply job (layer 6: workflow run log); cutover annotates host_key_mismatch role=web; workspaces-luks-verify scheduled-failure issue"
    alert_route: "workspaces-luks-verify scheduled-failure issue; apply workflow failure notification"
  - mode: "git-data re-keyed but the app did not reload the pin (redeploy job failed)"
    detection: "git_data_redeploy job fails with a pin-lag annotation; erasures emit erasure_outcome=host_key_mismatch; startup line fingerprint differs from the Terraform-printed one"
    alert_route: "art17_erasure_incomplete Sentry alert; workflow failure"
  - mode: "app pin absent while the store is disabled (transitional)"
    detection: "startup line git_data_pin=absent; Sentry op=pin_absent_store_disabled once per process"
    alert_route: "Sentry issue stream (warning); expected to stop after post-merge step 3"
  - mode: "app pin absent or malformed while the store is enabled"
    detection: "resolveGitDataHostKeyPin throws in the caller's guard; erasure reports erasure_outcome=unconfigured (pages); replicateToGitData reports feature=worktree_lease op=git_data_replication_push and fetchFromGitData/provisionGitDataRepo report through their existing reportSilentFallback ops (layer 2, Sentry; non-paging today because both paths are gated off while the store flag is off, and #8211 owns their alerting at cutover)"
    alert_route: "art17_erasure_incomplete Sentry alert"
  - mode: "git-data boots with a host key other than the Terraform one"
    detection: "cloud-init boot proof emits a fatal under the routed stage:sshd_config with detail=hostkey_mismatch via git-data-emit (layer 3: Sentry + Better Stack); git_data_boot_verify turns the replace job red before any redeploy (layer 6: workflow ::error::)"
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

- **Create ADR-237 (provisional ordinal): "SSH host keys are pinned".** The decisions:
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
  - D4's first residual is closed by ADR-237, effective at step 4.
  - D2's `accepted` precondition points to ADR-237.
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
  - `claude -> gitDataStore`: add "host key pinned via GIT_DATA_SSH_HOST_KEY (ADR-237)";
  - `doppler -> claude`: edit only if the edge lists secret names.
  - `github -> doppler`: the cutover job's new pin read uses the `prd` read token it already
    holds (the flag precheck), so the access set does not change. Confirm the edge text does
    not claim that `prd` is read only for the flag. The replace job dispatching
    `web-platform-release` is a CI-to-CI edge, which C4 does not model; ADR-237 records it
    under its consequences.
- **Cardinalities:** the `github -> tunnel` edge says "17 terraform_data SSH provisioners".
  Leave counts alone unless `plugins/soleur/test/c4-count-parity.test.sh` requires a change. Run
  it together with `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.

### Sequencing

ADR-237 is written now with status `adopting`, and the step-4 docs PR flips it.

## Guard Contract

### Guard 1 — No unpinned host-key option in any SSH consumer

**Property.** No tracked file outside a named allow-list configures an SSH client with
`StrictHostKeyChecking` set to `accept-new`, `no` or `off`, points `UserKnownHostsFile` at
`/dev/null`, or pipes `ssh-keyscan` output into a known_hosts file. The match is
case-insensitive and covers every spelling: `-o K=V`, `-oK=V`, `-o "K V"`, ssh_config `K V`, TS literals and `GIT_SSH_COMMAND` strings. `GlobalKnownHostsFile=/dev/null` is **allowed**: it is a hardening option that removes a trust source, whereas `UserKnownHostsFile=/dev/null` removes the pin.

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
| 8 | `-o "StrictHostKeyChecking accept-new"` (quoted space form) | RED |
| 9 | `GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no"` in a script | RED |
| 10 | `-o GlobalKnownHostsFile=/dev/null` alone | PASS (must not be flagged) |

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
comment contains `connection { host }`). It asserts that **every** `connection` block contains exactly one `host_key`. That is a per-block check, not a comparison of totals, so moving a `host_key` from one block to another cannot pass. It also asserts at least 19 blocks.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete `host_key` from the first block | RED |
| 2 | Delete it from the **last** block only | RED |
| 3 | Walker finds 0 blocks | RED (floor) |
| 4 | Add a new `terraform_data` + `connection` without `host_key` in a different `.tf` | RED |
| 5 | Move one block's `host_key` into another block (totals unchanged) | RED |
| 6 | A web-1 block with `host_key` set to anything other than `local.web_1_ssh_host_key` | RED |

**Harness rows.** The mutation test runs rows 1–4 on a temp copy. Must-PASS: different
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
| 8 | The pinned argv drops `-F /dev/null`, `GlobalKnownHostsFile=/dev/null`, `HostKeyAlgorithms=ssh-ed25519` or `UpdateHostKeys=no` | RED |
| 9 | stderr `Unable to negotiate … no matching host key type found` classified as anything other than `host_key_mismatch` | RED |

**Harness rows.** Each test resets module state with `vi.resetModules()` and `vi.unstubAllEnvs()`, because the once-per-process Sentry report is module-level state. known_hosts content is read **inside** the mocked `execFile` call. The file is
unlinked in `finally`, so reading it afterwards proves nothing. Must-PASS: a pin with surrounding
whitespace is trimmed and accepted.

**Anchor.** None.

### Guard 6 — git-data boot proof

**Property.** A git-data boot succeeds only if sshd serves exactly one host key, and that key's
fingerprint equals the Terraform public key's fingerprint.

**Assembly.** A single shell function (`git_data_hostkey_proof`) inside the
`STAGE=sshd_config` block of `cloud-init-git-data.yml`. It reads `sshd -T` output and the
expected fingerprint. It is extracted verbatim for rung-1 tests by the existing
render/extraction harness (`git-data-runcmd-rehearsal.test.sh`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fake `sshd -T` lists two `hostkey` lines | fatal (`detail=hostkey_count`) |
| 2 | Fingerprint differs from the expected one | fatal (`detail=hostkey_mismatch`) |
| 3 | `ssh-keygen` absent | warn only (`sshd_config_warn`), boot continues |
| 4 | Function body replaced by `return 0` | RED (rows 1–2 no longer fatal) |

**Harness rows.** Must-PASS: one `hostkey` whose fingerprint matches, with `sshd -T` output in a
different line order.

**Anchor.** The payload is hash-bound to the rung-2 evidence, and rung 2 proves the proof on a
real boot.

### Guard 7 — redeploy tracker

**Property.** `git_data_redeploy` succeeds only if some `web-platform-release` run newer than
the pre-dispatch baseline has a deploy job that concluded `success`.

**Assembly.** `.github/actions/dispatch-web-redeploy/track.sh` is the only decision point. It is
tested by `tests/scripts/test-dispatch-web-redeploy.sh`, which uses a `gh` stub and 1–2 s
intervals.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Baseline read fails (stub exits 1 or returns non-numeric) | RED (fail closed before dispatch) |
| 2 | Newer run `success`, but its deploy job is `skipped` | RED at timeout |
| 3 | Deploy job renamed or missing from `jobs` | RED (not treated as success) |
| 4 | Only a run at or below the baseline succeeds | RED |
| 5 | Dispatched run `cancelled`, then a later push-triggered run deploys `success` | PASS |

**Harness rows.** A run that qualifies before `gh workflow run` returns still counts, because it
is newer than the baseline: PASS. Stubbing the decision to `exit 0` must fail rows 1–4.

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

- The runbook, ADR-237, the ADR-220/068 amendments, the C4 edge text and C4 tests, and the workspaces-luks-verify comment.
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
- **R3: rung-2 interlock.** This PR voids the evidence. Birth and replace, including an emergency replace, refuse until the evidence PR lands. Break-glass is the operator-local apply (ADR-096), and ADR-237 records the gap.
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

- [x] **AC1:** `bash tests/scripts/test-no-tofu-ssh.sh` exits 0, prints a scanned-file count > 0, and every allow-list entry hits its expected count (Guard 1).
- [x] **AC2:** the bridge's `WEB_HOST_SSH` contains:
  - `StrictHostKeyChecking=yes`
  - `HostKeyAlias=web-1`
  - `HostKeyAlgorithms=ecdsa-sha2-nistp256`
  - `UpdateHostKeys=no`
  - a `UserKnownHostsFile=` that is not `/dev/null`

  The bridge exports exactly `{CI_SSH_KEYFILE, WEB_HOST_SSH}`, and the `infra-validation.yml` assertion is green.
- [x] **AC3:** `git-data-cutover.yml`'s ssh_config contains no `accept-new` and no `/dev/null` except the hardening `GlobalKnownHostsFile /dev/null` (amended in the work phase: that option removes a trust source, it adds none), and both Host blocks carry `HostKeyAlias` and `StrictHostKeyChecking yes`. `git-data-cutover-access.test.sh` passes with rows for `host_key_mismatch reason=changed|unknown|alg`. `git-data-flag-precheck.test.sh` passes with rows for `git_data_host_key_unavailable reason=absent|invalid|unreadable` and `TOFU_ARM present|absent`.
- [x] **AC4:** Guard 2 passes: `host_key` count == `connection` count, and the count is ≥ 19, across `apps/web-platform/infra/**/*.tf`. The mutation test also passes.
- [x] **AC5:** `terraform validate` passes in `apps/web-platform/infra` and in `rung2-rehearsal`. The rendered git-data cloud-config parses as YAML and contains `ssh_keys.ed25519_private` / `ed25519_public` and `ssh_deletekeys: true`. `01-hardening.conf` has the `HostKey` line and the boot-proof block. Check this with the render test, not grep.
- [x] **AC6:** the replace and birth gate suites pass with the Guard 4 rows, including both first-rotation must-PASS variants and the local-backend `-replace` fixture. `terraform-target-parity.test.ts` passes. The per-PR list contains the probe and neither pin address.
- [x] **AC7:** `git-data-rung2-boot-evidence.env` is absent from the tree. The rung-2 suites pass with the new MAY-DIVERGE variables.
- [x] **AC8:** the Guard 5 vitest matrix passes. It covers `host_key_mismatch` classification, an invalid pin returning `unconfigured` (not `unreachable`), and `provisionGitDataRepo` passing the pin. `tsc --noEmit` is clean.
- [x] **AC9:** `web-1-ssh-host-key.pub` has exactly one ECDSA-P256 line that passes Guard 3, and its header fingerprint equals `ssh-keygen -lf` of that line. The PR body names the capture vantage point and the cross-check result.
- [x] **AC10:** the runbook's "#7226 — pin git-data's SSH host key…" bullet is replaced by a staged list: mechanism merged ✔, post-merge steps 1–5 as open items, and the flag-flip precondition "pin present in prd AND #5914 closed". The runbook also has the verdict rows, the expected-drift note, the emergency-replace gap and the re-capture section.
- [x] **AC11:** ADR-237 exists with status `adopting`, and its ordinal is free across all `origin/*` refs at merge time. The ADR-220 amendment (including the D6 design change) and the ADR-068 amendment exist. The C4 edge text is updated, and `c4-count-parity`, `c4-code-syntax` and `c4-render` pass.
- [x] **AC12:** the PA-36 §(g) item and the (g)(11) correction exist. The counsel-audit addendum exists. `python3 scripts/lint-encryption-posture.py --repo-sweep` passes with the four new connections.
- [x] **AC13:** `workflow-file-size.test.ts` passes, and so does the git-data user_data budget suite.
- [x] **AC14:** `bash tests/scripts/test-write-known-hosts.sh` passes. The `dispatch-web-redeploy` action's embedded shell passes `bash -c` syntax checks. The redeploy job (moved to `git-data-pin-redeploy.yml`, see the work-phase addendum) carries `permissions: {actions: write, contents: read}` and no `secrets.` reference. F1, F2 and F4 are filed as #8518 (F5 already shipped in #7772).
- [x] **AC16:** `tests/scripts/test-dispatch-web-redeploy.sh`, `web-1-host-key-local.test.sh`, the boot-proof rows (Guard 6), and a vitest for the startup line (both forms, `fp=SHA256:` format, warn level) all pass. `.github/CODEOWNERS` has the listed rows. The gate libraries print no `.change.before`/`.after`.
- [x] **AC15:** after pushing, `workspaces-luks-verify.yml` dispatched with `--ref <branch>` ends `success`. This is the strict bash path through Cloudflare, and it is the second observation of web-1's pin.

### Post-merge (operator; each separately authorized; runbook Post-merge sequence)

- [ ] Step 1: every merge-triggered apply that follows is `success` (the probe ran).
- [ ] Steps 2–5 as described in the runbook. Step 4 flips ADR-237 to `accepted` and ticks the precondition. Step 5 closes #5914.

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


## Addendum — 2026-09-21: work-phase deviations (measured)

- **No `LogLevel=ERROR` on any pinned ssh path** (bridge `WEB_HOST_SSH`, cutover ssh_config, app helpers). Measured in an ubuntu:24.04 container: OpenSSH 9.6 under `LogLevel=ERROR` suppresses "Unable to negotiate … no matching host key type found" and "channel N: open failed", which made `host_key_mismatch reason=alg` unobservable and broke the existing `forward_refused`/`connect_refused` rows. D3/D4 prescribed it; it is removed and a test asserts its absence in the app argv.
- **D6 redeploy is a separate workflow, not two jobs in `apply-web-platform-infra.yml`.** Jobs inside that workflow sit in its workflow-level concurrency group and would hold the fleet apply lock for up to ~80 min. `.github/workflows/git-data-pin-redeploy.yml` triggers on the apply workflow's completion, gates on the birth/replace job conclusion (`source-run-gate.sh`) and has its own concurrency group. The Terraform-side fingerprint is printed by the birth/replace apply steps from a new non-sensitive output `git_data_ssh_host_key_fingerprint`; the redeploy summary links to that run.
- **`track.sh` polls only the deploying arms** (`workflow_dispatch`, `workflow_run`) of `web-platform-release` — the `push` arm never deploys (ADR-217); required by `workflow-run-deploy-invariants.test.sh` G8.
- **`TF_VAR_terraform_version` is workflow-level env** in all four workflows that plan the main root, pinned equal to `TERRAFORM_VERSION` by a parity test (job-level env cannot read `env.*`).
- **`ssh_genkeytypes: []` dropped** — `cloud-init schema` rejects an empty list; `cc_ssh` generates nothing when `ssh_keys` is present (read in cloud-init 26.1 source).
- **CRLF pin files are accepted** (D3's `replace(…, "\r", "")` wins over the Files-to-Create "CRLF must error" row). Both the HCL local and the bash writer strip EVERY CR, including one inside a line; the fixed-length regex still bounds what survives, so nothing can be smuggled (corrected at review: an earlier wording said a mid-line CR is rejected).
- **F5 already shipped** in #7772 (`git-data-nftables.sh`); not filed. F1/F2/F4 consolidated into #8518. PA-1 (g)(14) and PA-2 (g)(18) corrected inline rather than via a follow-up issue.
- **Code-owner review is not enforced** on `main` (no branch protection; rulesets are status checks + force-push only) — recorded in ADR-237; the CODEOWNERS rows are advisory.
- **Phase 0 capture:** 2026-09-21T18:12:21Z from an `ADMIN_IPS` egress (82.67.29.121, added with operator ack; firewall applied as a targeted plan whose only change was that port-22 rule) directly against web-1's public :22. Fingerprint `SHA256:ARBTzhY4hCGXKwWZ2j9aOc4zZefBYgAxJncoVglvuok`; no prior operator known_hosts entry to cross-check.

- **AC15 evidence:** `workspaces-luks-verify.yml` run 35636913078 on d916e62f1 concluded `success` over the pinned strict bridge path (log: `pinned web-1 ecdsa-sha2-nistp256 SHA256:ARBTzhY4hCGXKwWZ2j9aOc4zZefBYgAxJncoVglvuok`, `workspaces-luks re-assert PASSED`) — the second, Cloudflare-side observation of the captured pin.
- **Review round (2026-09-21):** the composite `dispatch-web-redeploy/action.yml` was deleted — the workflow runs `track.sh` directly (its `fingerprint` input was dead); the redeploy concurrency group moved onto the job; the redeploy emails ops on failure; the `head_branch == main` source filter was dropped (a replace can be dispatched from any branch); a failed pin read reports `reason=<word> rc=<n>` rather than a fixed `unreadable`; TOFU_ARM detects the option literal, not the constant name; the birth gate accepts a pin `update` when the server is a `create` (post-rotation retry).
