---
title: "Counsel review audit — #7226 / #5914 / PR #8511 (SSH host-key pinning on the web-1 and git-data paths, ADR-237: PA-36 (g)(14) drafted TOM, PA-36 (g)(11) and PA-1 (g)(14) / PA-2 (g)(18) superseded markers, #6588 audit addendum, encryption-posture ledger rows)"
type: counsel-review
date: 2026-09-22
issue: 7226
related_issues: [5914, 8209, 6931]
pr: 8511
plan: knowledge-base/project/plans/2026-09-21-security-pin-web-1-and-git-data-ssh-host-keys-plan.md
adr: knowledge-base/engineering/architecture/decisions/ADR-237-ssh-host-keys-are-pinned.md
brand_survival_threshold: single-user incident
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-09-22
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED. One in-PR text correction (C1) was found and APPLIED by the CLO agent in this PR before sign-off; no condition is outstanding. Reviewed against branch HEAD 50834d0fc6 plus the C1 commit."
blocking_findings: []
applied_in_pr:
  - "C1 — knowledge-base/legal/audits/2026-07-counsel-review-6588.md, Addendum (2026-09-21, #7226): the sentence 'The workflow classes an SSH transport failure as `unavailable` (reason `ssh_transport_failure`)' read as the classification of a host-key failure. The workflow gives a host-key refusal its own reason, `web_1_host_key_mismatch`, via `host_key_verdict`, checked before the generic rc-255 arm. Corrected in place: the addendum is authored inside this PR and is not yet a merged record, so no Superseded marker is owed."
optional_precision_notes:
  - "O1 — `apps/web-platform/infra/sentry/issue-alerts.tf` comment above `resource \"sentry_alert\" \"art17_erasure_incomplete\"` still says 'The four routed values are refused | unauthorized | unconfigured | unreachable'. The rule filters on `feature` + `op` only, so `host_key_mismatch` IS routed and the register's 'pages through the existing Art. 17 alert' holds. The comment is stale engineering prose, not a legal claim. Non-blocking; fold into the #5914 follow-up."
  - "O2 — 'pages' in PA-36 (g)(14) describes an email alert to issue owners with an ActiveMembers fallthrough. That matches the register's existing use of 'pages' for alert routing. Not an overclaim."
  - "O3 — Pre-existing, outside this PR: the published Data Protection Disclosure retraction (#6588) still calls the git-data host 'never provisioned'. The host was born 2026-09-14 and holds no repository (register PA-36 line-42 marker, #8171). The retraction's operative point, that no TLS host-to-host git-data traffic carries user data, still holds. This PR touches no `docs/legal/**` file and would engage the #7387 gates if it did. Recommend a compliance/ follow-up; do not fold it into this PR."
attests:
  - "knowledge-base/legal/article-30-register.md: the four additions made by PR #8511 ONLY (PA-1 (g)(14) Superseded marker; PA-2 (g)(18) Superseded marker; PA-36 (g)(11) Superseded marker; PA-36 (g)(14) DRAFTED / NOT-YET-ACTIVE TOM)"
  - "knowledge-base/legal/audits/2026-07-counsel-review-6588.md: the `addendum_2026_09_21` frontmatter key and the Addendum (2026-09-21, #7226), as corrected by C1"
  - "scripts/encryption-posture-ledger.json: the four new `connection` rows (bridge bash callers, Terraform connection blocks, git-data-cutover.yml, web-1 app container to git-data sshd with its #5914 exception)"
does_not_attest:
  - "ADR-237, the runbooks and the plan (engineering records, relied on for the activation sequence and the residuals)"
  - "The Terraform, workflows, cloud-init boot proof and tests themselves. Counsel attests the record's statements about these technical controls, not whether the controls are correct."
art_33_triggered: false
art_34_triggered: false
re_evaluation_triggers: "(1) Post-merge step 3 completes (first key-rotating `git-data-host-replace` publishes GIT_DATA_SSH_HOST_KEY to Doppler prd and the redeploy logs `git_data_pin=present`). PA-36 (g)(14) then becomes an active measure. Re-attest that the cell's status marker is updated IN-CELL at that commit and not before. (2) #5914 merges and deletes TOFU_FALLBACK_OPTS. Residual (b) of (g)(14) and the ledger exception then close, and both must be rewritten in place with Superseded markers. (3) Any proposal to set GIT_DATA_STORE_ENABLED before (1) AND (2) are both true is a hard block. The record makes it a precondition, and the resolver's throw enforces it. (4) Any web-1 host-key mismatch that neither a wrong capture nor a legitimate re-key (#6931) explains goes to breach-notice triage (recommended-tools.md#breach-notice-triage); the Art. 33 72-hour clock runs from awareness. (5) The #8209 residual (host private key in main-root state and user_data) is either cured, or widened by any new reader of that state. (6) Inherited triggers: first arms-length data subject, EEA-out transfer, regulated-industry data subject."
---

# Counsel review audit: #7226 / #5914 / PR #8511 (SSH host keys are pinned)

This file is the load-bearing evidence for the ship Phase 5.5 Counsel-Review CLO-Attestation Gate on
PR #8511. The gate fired on `knowledge-base/legal/**` under a `single-user incident` brand-survival
threshold. The CLO agent is the v1 attestation authority, and the operator holds an optional veto.
Everything here is draft material that requires professional legal review. External counsel
re-review is reserved for the re-evaluation triggers above.

## Why a new audit file, not only the #6588 addendum

The #6588 addendum covers one surface: whether a `workspaces-luks-verify` verdict can be trusted
after the Cloudflare-bridge channel is pinned. It says nothing about the Article 30 register changes
(PA-36, PA-1, PA-2) or the ledger rows. Those need an attestation of their own, and this file
provides it. The addendum stays where it is and is attested below as one artifact.

## Scope and limit check

- **Append-only in the register.** `git diff --word-diff=porcelain origin/main...HEAD` over the
  register shows additions only, with no deleted token. The additions are three `[Superseded
  2026-09-21 (#7226) …]` markers and one new numbered item, PA-36 (g)(14). No Status or lawful-basis
  cell was touched.
- **Merge-conditioning is stated, not implied.** Each marker and (g)(14) say the item "is written
  into this register by PR #8511, is conditioned on that PR's merge, and is not activated by the
  merge itself". The addendum opens with "Conditioned on the merge of PR #8511 … If PR #8511
  closes unmerged, this addendum is void", and its frontmatter key says the same. Nothing in either
  file uses the past tense for this PR's merge.
- **No published surface engaged.** `git diff --name-only origin/main...HEAD` lists no
  `docs/legal/**` or `plugins/soleur/docs/pages/legal/**` path. The five #7387 gates are not engaged.
- **No `[DRAFT — pending CLO/counsel review` marker** was added (`grep -c` over the diff returns 0).
- **Production untouched.** The only production reads were name-only and status reads: the Doppler
  `prd` secret names, the absence of `GIT_DATA_STORE_ENABLED`, and `gh run list`. No write was run.

## Drift table

| # | Claim in the record | Checked against | Verdict |
|---|---|---|---|
| D1 | (g)(14): every leg into the store (push/fetch, provision, Art. 17 erasure) is SSH over the private network under the three forced-command keys, not TLS | Every call site of `gitWithPrivateKeyAuth` and `sshWithPrivateKeyAuth`: `replicateToGitData` (push), `fetchFromGitData` (git-data-client.ts), `provisionGitDataRepo`, `removeGitDataRepo`. Each passes a `hostKeyPin`. No TLS path reaches git-data. | **Holds** |
| D2 | PA-1 (g)(14), PA-2 (g)(18), PA-36 (g)(11) markers: the one-way TLS proxy is the web↔web session relay, and its certificate does not name git-data | `infra/proxy-tls.tf`: `ip_addresses` = web hosts' private IPs, `dns_names` = web host keys + `localhost`. `session-proxy.ts` references git-data only as a host to *reject* before the handshake. | **Holds** |
| D3 | (g)(14), pinned arm: on activation the app checks the pin on every dial, and a mismatch fails closed | `gitDataHostKeyTrust` in git-auth.ts: a non-null pin gives a per-call known_hosts `git-data <pin>` with `PINNED_HOST_KEY_OPTS` (`-F /dev/null`, `StrictHostKeyChecking=yes`, `HostKeyAlias=git-data`, `HostKeyAlgorithms=ssh-ed25519`, `UpdateHostKeys=no`, `GlobalKnownHostsFile=/dev/null`) | **Holds** |
| D4 | (g)(14) residual (b) and the markers: the transitional unpinned arm "is reachable only while the running app holds no pin **and** `GIT_DATA_STORE_ENABLED` is off; a malformed pin, or an absent pin with the flag on, refuses the dial" | `resolveGitDataHostKeyPin`: `present` returns the pin. `invalid` throws. Absent with `isGitDataStoreEnabled()` (`=== "true"`) throws. Absent with the flag off returns `null`, which `gitDataHostKeyTrust` maps to `TOFU_FALLBACK_OPTS` (`accept-new`, empty known_hosts). `gitDataHostKeyTrust` also throws on a pin containing a newline or only whitespace. | **Holds exactly** |
| D5 | Not overstated: (g)(14) is "DRAFTED / NOT-YET-ACTIVE" and "asserts NO present-tense measure before that line is observed" | Doppler `prd` (names only): `GIT_DATA_SSH_HOST_KEY` absent. `doppler_secret.git_data_ssh_host_key` is written only by the birth/replace targets (`depends_on = [hcloud_server.git_data]`). The only workflow references to `hcloud_server.git_data` are the replace job (which also `-replace`s `tls_private_key.git_data_host_ssh`) and the birth job. So no per-PR apply publishes the pin, and it does not exist today. The record states exactly that. | **Holds**: no overclaim |
| D6 | (g)(14): "Until activation, the erasure path … which is live and deliberately not flag-gated, runs over that arm against a store that holds no repository" | `removeGitDataRepo` gates on `GIT_REMOVE_SSH_PRIVATE_KEY`, not on the flag (documented rationale: dual-existence after rollback). Doppler `prd` holds `GIT_REMOVE_SSH_PRIVATE_KEY` and no `GIT_DATA_STORE_ENABLED`, so erasure is live and currently takes the unpinned arm. `provisionGitDataRepo` and `ensureGitDataRemote` return early with the flag off. The register's PA-36 #8171 marker records "the store holds no repository". | **Holds**: the residual is disclosed in the record, not hidden |
| D7 | (g)(14): ED25519 host key minted by Terraform, installed by cloud-init, checked by a boot proof, rotated on every replace | `tls_private_key.git_data_host_ssh` (ED25519). `cloud-init-git-data.yml` `ssh_deletekeys: true` + `ssh_keys.ed25519_*`. The `git_data_hostkey_proof` function fails the boot on `hostkey_count`/`hostkey_mismatch` and only warns if `ssh-keygen` is missing, which is the documented could-not-measure rule. Rotation: the replace job `-replace`s the key alongside the server, and no other workflow path replaces the server. | **Holds** |
| D8 | (g)(14): a mismatch on the erasure path yields `host_key_mismatch`, which pages through the existing Art. 17 alert | `removeGitDataRepo`: on rc 255, `SSH_HOST_KEY_MISMATCH` is tested before `SSH_AUTH_FAILURE`, which returns `{status:"host_key_mismatch"}`. `deleteAccount` treats any status other than `erased`/`skipped` as `gitDataErasurePending = true` and calls `reportSilentFallback` with `feature=account-delete`, `op=git-data-bare-repo-erasure`, tag `erasure_outcome`. `sentry_alert.art17_erasure_incomplete` filters on feature+op, so it routes every outcome value. The pin guard sits outside the ssh `try`, so an invalid pin, or an absent pin with the flag on, reads as `unconfigured` (`pin_invalid` / `pin_absent_store_enabled`) and not as `unreachable`. | **Holds** (see O1, O2) |
| D9 | (g)(14) residual (a): host private key in main-root state and in `user_data`; the metadata endpoint serves it to root only since #7772; state reader + network position can impersonate (#8209) | git-data.tf `tls_private_key.git_data_host_ssh` comment (EXPOSURE, #8209). `cloud-init-git-data.yml` #7772 nftables metadata drop for non-root UIDs. ADR-237 lines on metadata/root. | **Holds** |
| D10 | (g)(14): precondition "Pin present in `prd` AND that arm deleted (#5914)" for any store enablement | ADR-237 "transitional app arm" bullet; the git-auth.ts header comment; the enforcing control is the resolver's throw with the flag on and no pin | **Holds** as a recorded precondition. The throw enforces the pin half. The arm-deletion half is a process precondition (cutover runbook), and the record calls it a precondition, not a technical control. |
| D11 | Addendum: before AC15 / merge, luks-verify ran over a bridge that did not verify web-1's host key | `origin/main` `cf-tunnel-ssh-bridge/action.yml`: `StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null` | **Holds** |
| D12 | Addendum: from AC15 on, the runner checks web-1 against the committed ECDSA-P256 pin under strict checking | Branch `action.yml`: `write-known-hosts.sh` writes `web-1 <pin>`, and `SSH_INVOCATION` has `-F /dev/null … StrictHostKeyChecking=yes … HostKeyAlias=web-1 -o HostKeyAlgorithms=ecdsa-sha2-nistp256 …`. Pin file `web-1-ssh-host-key.pub` (captured 2026-09-21T18:12:21Z). AC15 run 35636913078 on d916e62f17 ended `success`. | **Holds** |
| D13 | Addendum: a host-key failure is `unavailable`, not `drift`, and does not fire trigger (3) | `workspaces-luks-verify.yml` `host_key_verdict` → `emit_class unavailable web_1_host_key_mismatch`. The `drift` class is reached only through `is_at_rest_drift`. | **Holds as to class. The reason name was wrong, fixed by C1.** |
| D14 | Ledger: web-1 app to git-data row `cert_verification: "off"` with a #5914 exception; "the only live call" is erasure | Consistent with D4 and D6. The three web-1 rows are `on`, which matches D12 and the Terraform `host_key` wiring. All rows are `disclosed_as: not-publicly-claimed`. | **Holds** |

## Processors, recipients, data categories

No new processor, recipient, or category of personal data is introduced.

- The pin is a **host public key** and the startup line carries only its SHA256 fingerprint. Neither
  relates to a natural person, so neither is personal data under Art. 4(1). Doppler holding a
  public host key is not processing of personal data, so the question of whether Doppler is a
  register processor does not arise for this PR.
- The new Sentry event `pin_absent_store_disabled` carries no identifier.
- The `host_key_mismatch` erasure event reuses the existing carrier: `extra.gitDataRepoId`, already
  documented with its Art. 17 completion basis, and `detail`, scrubbed by `scrubErasureDetail`.
  Its remote stderr can name the private IP `10.0.1.20`, which is infrastructure and not personal
  data. It adds no field.
- Better Stack receives the one warn-level startup line (`git_data_pin=…`), which holds no
  personal data.

## Findings

- **C1 (applied).** See the frontmatter. The addendum named `ssh_transport_failure` as the reason a
  host-key failure carries. The code gives it `web_1_host_key_mismatch`, checked first on every ssh
  call in the probe step. The conclusion (class `unavailable`, not `drift`, trigger (3) not fired)
  was right. The implementation detail was not, and that is the #4353/#4558 drift class. The
  correction was made in place in the same PR.
- **O1–O3.** See the frontmatter. None blocks the merge.

## Per-artifact verdict

| Artifact | Verdict |
|---|---|
| `article-30-register.md`: PA-36 (g)(14) | **APPROVED.** Accurate, correctly tensed as DRAFTED / NOT-YET-ACTIVE, residuals (a) and (b) stated. The transitional-arm condition matches `resolveGitDataHostKeyPin` exactly. |
| `article-30-register.md`: PA-36 (g)(11) marker | **APPROVED.** The correction is true, and it states which items it does not amend. |
| `article-30-register.md`: PA-1 (g)(14) / PA-2 (g)(18) markers | **APPROVED.** The correction is true, the two markers are twins, and the relay description is left unamended. |
| `audits/2026-07-counsel-review-6588.md`: `addendum_2026_09_21` + Addendum | **APPROVED as corrected by C1.** #6588's disposition is correctly left unchanged. The E-1 discharge is not invalidated retroactively, and the residual is recorded honestly. The H4 escalation routes to breach-notice triage with the 72-hour clock. |
| `scripts/encryption-posture-ledger.json`: four new rows | **APPROVED.** |

## Disposition

**DISCHARGED.** The ship Phase 5.5 Counsel-Review CLO-Attestation gate for PR #8511 is satisfied.
The one correction (C1) is applied in this PR, and no pre-merge condition is outstanding. The
operator retains an optional veto.
