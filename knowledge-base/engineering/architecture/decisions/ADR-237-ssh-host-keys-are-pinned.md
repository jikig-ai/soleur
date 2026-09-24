---
title: "ADR-237: SSH host keys are pinned"
status: adopting
date: 2026-09-21
issue: 7226
supersedes: []
amends:
  - ADR-220
  - ADR-068
tags: [ssh, host-keys, git-data, web-1, cloudflare-tunnel, terraform, security]
---

# ADR-237: SSH host keys are pinned

## Status

`adopting`. Implemented by PR #8511 (closes #7226 and #8125, references #5914). It flips to
`accepted` at post-merge step 4 of the runbook's host-key sequence
(`knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`, "Host-key pinning
post-merge sequence"): a strict `git-data-cutover.yml` dry run from `main` reads
`role=git-data-auth verdict=ok` with both hops pinned. That flip happens in a docs PR.

## Context

Every SSH session the system opened to web-1 or to the git-data host accepted whatever host key the
peer presented, in three places:

1. **The CI tunnel bridge** (`.github/actions/cf-tunnel-ssh-bridge/action.yml`) remembered nothing
   between connections, so web-1's key was re-accepted unchecked on every run (#7226). Its five
   callers include the daily `workspaces-luks-verify.yml` run behind a published Article 32 claim. The
   Terraform `connection {}` blocks that reach web-1 through the same bridge set no `host_key` (#8125):
   17 in `server.tf` and 1 in `ci-ssh-key.tf`.
2. **The git-data cutover workflow** did the same on both hops. Per ADR-220 D4, every store-probe
   answer was therefore unauthenticated, and a compromised web-1 could pretend to be git-data.
3. **The app's private-network git transport** (`apps/web-platform/server/git-auth.ts`) trusted on
   first use against an empty known_hosts file created per call (#5914). It carries the live Art. 17
   erasure call today, and every replication push and fetch once the store is enabled.

No sshd host key was minted anywhere: git-data generated its own at first boot, so its key was not
Terraform-known. web-1 cannot be replaced (the replace gate refuses it until #6931), ignores cloud-init
changes (`ignore_changes = [user_data]`), and may not have sshd changed in place
(`hr-prod-host-config-change-immutable-redeploy`).

Terraform 1.10.5's vendored `golang.org/x/crypto` (v0.27.0) lists ED25519 last among host-key
algorithms and treats a key of another type as a mismatch, so against Ubuntu's default host keys the
Terraform SSH client negotiates ECDSA-P256.

## Decision

1. **Hosts that Terraform births get a Terraform-minted ED25519 host key.** For git-data,
   `tls_private_key.git_data_host_ssh` is installed through the cloud-config `ssh_keys` block. A boot
   proof in the `sshd_config` stage checks that sshd serves exactly one host key and that its
   fingerprint equals the Terraform key's; a mismatch is a routed boot fatal, and
   `git_data_boot_verify` turns the replace or birth job red before anything is redeployed.
2. **The host's replace job rotates the key, and a follow-on workflow loads it into the app.** The gated
   replace re-mints the key with the host; the birth job mints it. The public half is published as a
   Terraform-owned Doppler `prd` secret, `GIT_DATA_SSH_HOST_KEY` (`doppler_secret.git_data_ssh_host_key`,
   written only after the server exists). When the apply run completes, `git-data-pin-redeploy.yml`
   (`workflow_run`, job `redeploy`) forces a `web-platform-release` if a birth or replace job **and
   its `Terraform apply` step (`id: apply`)** both succeeded, and waits for a newer run's deploy
   to succeed, so the app loads the new pin within about one release cycle. The job conclusion alone
   is not evidence of an apply: a `plan_only` rehearsal ends `success` with the apply step skipped,
   so it never redeploys (#8710, amended 2026-09-24). The apply run prints the
   new fingerprint to its job summary and log; a failed redeploy emails ops. Nothing outside Terraform copies the pin, and no per-PR `-target`
   reaches the key or the secret.
3. **Hosts that cannot be re-provisioned get a committed, reviewed pin.** web-1's ECDSA-P256 key is
   captured once from a vantage outside Cloudflare (`scripts/capture-web-1-host-key.sh`, from an
   `ADMIN_IPS` egress to web-1's public port 22) and committed as
   `apps/web-platform/infra/web-1-ssh-host-key.pub`: header lines with the capture method, date and
   fingerprint, then exactly one key line. ECDSA-P256 is a constraint of x/crypto's preference order
   for the pinned Terraform version, not a preference. OpenSSH callers pin the same key with
   `HostKeyAlgorithms=ecdsa-sha2-nistp256`. A read-only probe, `terraform_data.web_1_host_key_probe`,
   re-runs whenever the pin or `terraform_version` changes, so a wrong pin or a Terraform bump that
   changes negotiation fails the merge-time apply loudly.
4. **Every consumer is strict.** The bridge, both cutover hops and the app verify against a known_hosts
   file holding only the pin, under a fixed `HostKeyAlias` (`web-1`, `git-data`), with other trust
   sources removed. Pins are shape-validated at every site that turns one into trust (the bash writer,
   the app resolver, the HCL local). A mismatch fails closed with a named verdict
   (`host_key_mismatch reason=changed|unknown|alg`; `git_data_host_key_unavailable
   reason=absent|invalid`, or the flag read's own reason words plus `rc=` when the pin read fails).
5. **Trust-on-first-use options are banned** outside the allow-list of the no-TOFU guard
   (`tests/scripts/test-no-tofu-ssh.sh`), which counts each allowed site exactly.

## Consequences

- **A CI-to-CI dispatch edge.** A birth or replace run whose job and apply step both succeeded now
  triggers `web-platform-release` through `git-data-pin-redeploy.yml`: `workflow_run` on the apply
  workflow's completion (any branch, dispatched runs only; birth and replace are dispatch-only
  targets), gated by `.github/actions/dispatch-web-redeploy/source-run-gate.sh`, which reads the
  apply step's conclusion rather than the job's, so a `plan_only` rehearsal never redeploys; plus `workflow_dispatch` with an optional `source_run_id` for recovery. It runs
  `.github/actions/dispatch-web-redeploy/track.sh` with `actions: write` and no Terraform secrets
  (only the two ops emails' Resend key), outside the apply lock. C4 does not model CI-to-CI edges, so
  this ADR is where it is recorded. #8211's same-version redeploy is the intended replacement (DC-2 in
  the feature's `decision-challenges.md`).
- **Coupled to a display name.** `workflow_run` matches the apply workflow by its `name:` string
  (`Apply web-platform infra (Doppler/Cloudflare/BetterStack/GitHub-App/Inngest/firewall)`), not its
  path. Renaming that workflow silently stops every automatic redeploy: the replace still succeeds and
  the app keeps the old pin. A rename must update both files in the same PR.
- **Also coupled to the two apply-step display names.** The jobs API carries no step `id`, so the
  gate matches each job's apply step by its exact `name:` (`Terraform apply (git-data birth)` and
  `Terraform apply (git-data-host -replace) — both-volumes-preserved assert`). A rename is caught in
  CI by parity test PT1 (`plugins/soleur/test/terraform-target-parity.test.ts`); at runtime a green
  job whose apply step cannot be found exits 1 (`verdict=unidentified`, failure email) and a red one
  prints `apply=not_found` in its warning and emails ops — never a silent skip. PT1 binds main's
  gate to main's workflow only: a dispatch from a branch that renamed the step is caught at runtime
  as above, not in CI. Parity test PT4 holds every other job of every workflow off the pin
  addresses, so the two `id: apply` steps are the only CI writers of the pin. The break-glass
  operator-local apply (`OPERATOR_APPLIED_EXCLUSIONS`, ADR-096) can also re-mint the key and fires
  no gate; its redeploy is the no-`source_run_id` dispatch of `git-data-pin-redeploy.yml`.
- **The redeploy dispatches and judges (accepted AP-024 deviation).** The same job dispatches the
  release and decides whether a newer release's deploy succeeded. AP-024 separates the write from the
  verdict; here the write is one release dispatch with no Terraform credentials, and the
  authoritative proof is independent of the job anyway: the app's startup line `git_data_pin=present
  fp=` must match the apply run's fingerprint (runbook go/no-go). The deviation is accepted for that
  reason.
- **The rung-2 emergency-replace gap.** PR #8511 changes the hash-bound git-data payload, so the rung-2
  interlock refuses every git-data birth and replace, an emergency replace included, from its merge
  until the rehearsal's evidence-only PR lands. This gap is accepted. The break-glass path is the
  operator-local apply under the `OPERATOR_APPLIED_EXCLUSIONS` contract (ADR-096). Keep the window
  short by rehearsing right after merge.
- **Pin lag is bounded, not zero.** The first rotation cannot mismatch, because the app has no pin
  until then. From the second rotation on, the app holds the previous pin until the redeploy
  succeeds: erasures in that window page as `erasure_outcome=host_key_mismatch`, and once the store
  flag is on, replication pushes and fetches stall too. Recovery is `gh run rerun <run-id> --failed` on
  the pin-redeploy run, or `gh workflow run git-data-pin-redeploy.yml --ref main -f
  source_run_id=<apply run id>`; never another replace. The bound holds when the source job is
  green. A red job with a green apply step (the boot poll failed after the pin was published)
  publishes the pin **without** a redeploy: the gate prints `verdict=pin_published` and emails ops
  (gate output `pin_published`; an unsent email fails the run, so the failure email retries it). A
  red job whose apply step failed or was cancelled may have written the pin first: it prints
  `verdict=pin_maybe_published` and takes the same email. Its recovery is the dispatch with no `source_run_id`,
  `gh workflow run git-data-pin-redeploy.yml --ref main`, because the same id re-reads the same red
  job and skips again.
- **Expected drift until the first replace.** Scheduled drift shows a pending replace of
  `hcloud_server.git_data` and creates of the key and the secret until post-merge step 3.
- **Operator-local applies enforce `host_key` too.** A laptop apply now verifies web-1 the same way CI
  does.
- **A web-1 rebuild is a re-capture.** When #6931 makes web-1 replaceable, every strict consumer fails
  closed with `reason=changed` until a re-capture PR lands. Terraform-minted keys for web hosts are
  a deferred follow-up.
- **A full revert is never the rollback.** It would restore trust-on-first-use on every path; fixes go
  forward.

### Code-owner review is not an enforced anchor

The PR adds explicit `.github/CODEOWNERS` rows for the trust files: the web-1 pin,
`.github/workflows/git-data-pin-redeploy.yml`, the `.github/actions/dispatch-web-redeploy/` directory,
`git-auth.ts`, `git-data-replication.ts`, `git-data-flag-precheck.sh`, both gate libraries and the
no-TOFU guard (the bridge directory already had one). On
2026-09-21, `gh api repos/jikig-ai/soleur/branches/main/protection` returned **404 "Branch not
protected"**, and the active rulesets on `main` contain only `required_status_checks` (CI Required,
CLA Required), `deletion` and `non_fast_forward` (Force Push Prevention). Nothing requires a code-owner
review. The CODEOWNERS rows are therefore **advisory**: they request a review, and they are not a
review anchor for the pins. The enforced controls are the guards and the probe; a reviewer of a pin
change compares the fingerprint independently.

## Residuals

- **Key exposure through main-root state and user_data (#8209).** git-data's private host key sits in
  main-root Terraform state twice: in the `tls_private_key` and inside the server's rendered
  `user_data`. The Hetzner metadata endpoint also serves user_data on git-data, but only to root:
  since #7772 a host-local nftables rule (`git-data-nftables.sh` in `cloud-init-git-data.yml`) drops
  metadata traffic from non-root UIDs, and root on git-data already holds the key on disk. So the plan's
  deferral F5 (block non-root metadata access) is already in place and needs no new issue. Anyone who
  can read the state copy **and** holds a network position (the private network or web-1) can pretend
  to be git-data. This is within #8209's scope.
- **web-1's pin rests on a single capture event.** It was cross-checked before merge by a second,
  independent observation (AC15): `workspaces-luks-verify.yml` run 35636913078, dispatched on the
  branch at `d916e62f1`, concluded `success` through Cloudflare over the pinned strict path (log:
  `pinned web-1 ecdsa-sha2-nistp256 SHA256:ARBTzhY4hCGXKwWZ2j9aOc4zZefBYgAxJncoVglvuok`,
  `workspaces-luks re-assert PASSED`). An independent in-band vantage on git-data is a deferred option
  (F2).
- **The transitional app arm (#5914).** Until the first replace publishes the pin and the redeploy
  loads it, the app keeps one unpinned fallback arm. It is reachable only with no pin in the
  environment **and** the store flag off; with the flag on, a missing pin throws. The store holds no
  repository until the flag is first set, and deleting the arm (the #5914 follow-up PR) is a hard
  precondition for that flag flip. The cutover precheck's `TOFU_ARM` line is a reminder read from the
  dispatched source tree on every dry run; the enforcing control is the resolver's throw on an absent
  pin while the store flag is on.
- **A pinned key authenticates the host, not its answers.** A rooted git-data can still answer the
  store probes falsely, so the probes stay bounded and fail-closed.

## Alternatives considered

| # | Alternative | Why not |
|---|---|---|
| A1 | Persist known_hosts across runs (actions/cache) | Any workflow on the repo can write the cache, and first contact is still unchecked. |
| A2 | `ssh-keyscan` git-data from web-1 after birth and publish the result | Trust on first use at birth, from the vantage (web-1) that ADR-220 D4 already names as a possible impersonator. |
| A3 | Mint the host key in its own additive-only root (the ADR-220 root-key pattern) | That root cannot rotate by design, and the main root renders `user_data`, which puts the private key in main-root state anyway. A separate root adds nothing unless the host fetches its own key (A4). |
| A4 | The host generates its own key and publishes it with a write-scoped Doppler token | The token sits in user_data. Whoever roots the old host can overwrite the pin after a replace unless the token rotates too. |
| A5 | Rotate web-1's key in place to a Terraform-minted key via a provisioner | Violates `hr-prod-host-config-change-immutable-redeploy`, and the swap connection would itself be unverified. |
| A6 | The app fails closed on an absent pin immediately | Every production erasure would fail, with a false "erasure pending" notice shown to users, until the first replace. |
| A7 | Keep git-data's key stable across replaces and rotate only on request | Removes the lockstep, but a fresh replace would keep a key a rooted host could have exfiltrated during the read-only period, defeating ADR-220 D6's fresh replace. Rotation on replace was the stated direction; the redeploy job bounds the lag instead. |
| A8 | Two-slot pins (current and next pre-published) so rotation never lags | Adds a slot variable, a second key in state and a two-step rotation, when the lag is already bounded. |

Also rejected during planning: SSH host certificates or a host CA (the `tls` provider cannot sign
OpenSSH certificates, and a CA adds a signing key to guard for no property the plain pin misses), and a
staged fail-open rollout for the bridge (with the pin file always written, the interim phase checks
nothing new).

## References

- Plan: `knowledge-base/project/plans/2026-09-21-security-pin-web-1-and-git-data-ssh-host-keys-plan.md`
- Decision challenges: `knowledge-base/project/specs/feat-one-shot-7226-5914-host-key-pinning/decision-challenges.md`
- Runbook: `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`
- ADR-220 (git-data root access; D4's first residual is closed by this ADR at post-merge step 4),
  ADR-068 (cutover design), ADR-096 (operator-applied exclusions, the break-glass path)
- Issues: #7226, #8125, #5914, #8209, #8211, #6931
