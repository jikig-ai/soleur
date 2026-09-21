# Tasks: pin the web-1 and git-data SSH host keys

**Plan:** `knowledge-base/project/plans/2026-09-21-security-pin-web-1-and-git-data-ssh-host-keys-plan.md`
**Issues:** Closes #7226, Closes #8125, Ref #5914 / #5274 / #8093
**Lane:** cross-domain (defaulted)

## Phase 0: Setup (capture web-1's pin)

- [ ] 0.1 Write `scripts/capture-web-1-host-key.sh`. It does five things:
  - refuses to run in CI;
  - checks that the egress IP is in `ADMIN_IPS`;
  - runs `ssh-keyscan -T 10 -t ecdsa`;
  - cross-checks the result against the operator's known_hosts;
  - writes the file header.
- [ ] 0.2 Run `soleur:admin-ip-refresh` first; it needs its own ack. At plan time (2026-09-21) this session's egress IP was **not** in `ADMIN_IPS`.
- [ ] 0.3 Run the capture script. It writes `apps/web-platform/infra/web-1-ssh-host-key.pub` with one ECDSA-P256 line and its fingerprint header. If web-1 has no ECDSA-P256 key, stop and re-plan.

## Phase 1: Tests first (RED)

- [ ] 1.1 Guard 1: `tests/scripts/test-no-tofu-ssh.sh`. It needs an allow-list with counts, a case-insensitive match, `ssh-keyscan` detection, a scanned-file floor, and harness rows H-a and H-b.
- [ ] 1.2 Guard 2: add rows to `web-host-provisioner-parity.test.sh` and its `-mutation.test.sh`. Cover the ≥19 floor, comment skipping, and a block in another `.tf` file.
- [ ] 1.3 Guard 3: `tests/scripts/test-write-known-hosts.sh`. Use keys generated during the test. Add a must-RED row for a quoted `$RE`, a truncated key and a multi-line key.
- [ ] 1.4 Guard 4: add rows to `tests/scripts/test-git-data-host-replace-gate.sh` and `test-git-data-host-birth-gate.sh`. Cover a first-rotation create, the secret shown as `update`, a local-backend `-replace` fixture, and the per-PR exclusion.
- [ ] 1.5 Guard 5: add a vitest matrix to `apps/web-platform/test/git-auth.test.ts` and the replication/erasure tests. Cover:
  - pinned known_hosts, read inside the mocked call;
  - flag-on with no pin, which must throw before any `execFile`;
  - an invalid pin, which must return `unconfigured`;
  - `host_key_mismatch` classification;
  - `provisionGitDataRepo`.
- [ ] 1.6 Add rows to `git-data-flag-precheck.test.sh`: `git_data_host_key_unavailable reason=absent|invalid|unreadable` and `TOFU_ARM present|absent`.
- [ ] 1.6b Guard 6: rows for the boot-proof function (two hostkeys → fatal, fingerprint mismatch → fatal, no `ssh-keygen` → warn).
- [ ] 1.6c Guard 7: `tests/scripts/test-dispatch-web-redeploy.sh`, using a `gh` stub and fast intervals.
- [ ] 1.6d `apps/web-platform/infra/web-1-host-key-local.test.sh`: `terraform console` fixtures, plus a structural check that the precheck step comes before the bridge step.
- [ ] 1.6e Vitest for the startup line: both forms, warn level, and the `fp=SHA256:` format. The pinned argv must include `-F /dev/null`, `GlobalKnownHostsFile=/dev/null`, `LogLevel=ERROR` and `UpdateHostKeys=no`. Tests call `vi.resetModules()` and `vi.unstubAllEnvs()`.
- [ ] 1.7 Add rows to `git-data-cutover-access.test.sh`: `host_key_mismatch reason=changed|unknown|alg`. Update the fixtures that currently assert TOFU literals.

## Phase 2: Core implementation, infra and CI (GREEN)

- [ ] 2.1 `git-data.tf`: add `tls_private_key.git_data_host_ssh` (ED25519, `private_key_openssh`) and `doppler_secret.git_data_ssh_host_key` (prd, with `depends_on` on the server), and pass both to the module.
- [ ] 2.2 `modules/git-data-userdata`: add two MAY-DIVERGE variables, each map entry on one line.
- [ ] 2.3 `cloud-init-git-data.yml`: add the `ssh_keys` block with correct `indent()` and the `HostKey` line. Add the boot-proof function in `STAGE=sshd_config`. A mismatch is a fatal under the routed `sshd_config` stage with `detail=hostkey_mismatch|hostkey_count`; a missing `ssh-keygen` only warns.
- [ ] 2.4 Give `rung2-rehearsal/rehearsal.tf` its own tls key. Extend the `RUNG2_VAR_DIVERGENCE` allow-lists. Delete `git-data-rung2-boot-evidence.env`.
- [ ] 2.5 `server.tf`: add the `web_1_ssh_host_key` local (`regex(one(...))`), set `host_key` on 18 blocks, and add `terraform_data.web_1_host_key_probe`. In `ci-ssh-key.tf`, set `host_key`. In `variables.tf`, add `terraform_version`.
- [ ] 2.6 `apply-web-platform-infra.yml`:
  - add the probe to the per-PR target list, and add `TF_VAR_terraform_version`;
  - replace job: add `-replace` for the key and `-target` for the secret;
  - birth job: add `-target`s;
  - add two `git_data_redeploy` jobs;
  - keep the file byte budget in check.
- [ ] 2.7 Create `.github/actions/dispatch-web-redeploy/action.yml` and `track.sh`. The job runs only on `main`, uses a sparse checkout, and sets `persist-credentials: false`. Its summary prints the Terraform fingerprint. It records a baseline `databaseId`, dispatches a patch release with a "pin rotation" note, waits for any later run whose deploy job succeeded (not skipped), and times out after 75 minutes.
- [ ] 2.8 Update the gate allow-sets in `git-data-host-replace-gate.sh`, `git-data-host-birth-gate.sh` and `plugins/soleur/test/terraform-target-parity.test.ts`. Run the orphan-suite sweep grep.
- [ ] 2.9 Create `.github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh` (validated writer, mode 0444).
- [ ] 2.10 Bridge `action.yml`: build `WEB_HOST_SSH` with the pinned options and `UpdateHostKeys=no`, keep the export set unchanged, and add a header contract.
- [ ] 2.11 `git-data-flag-precheck.sh`: read the pin, add the unavailable verdict and the `TOFU_ARM` line.
- [ ] 2.12 `git-data-cutover.yml`: use the writer to build `gd-known-hosts`, pin both Host blocks, add teardown. `git-data-cutover.sh`: order the H4 classifier branches.
- [ ] 2.12b Error-output hygiene on every CI ssh path. Decide verdicts from the exit code plus anchored patterns, strip control characters, wrap output in `::stop-commands::`, and print fingerprints only. Add a test row where a banner injects `::error::` and `verdict=ok`.
- [ ] 2.12c `.github/CODEOWNERS`: add rows for the pin file, the bridge, `dispatch-web-redeploy`, `git-auth.ts` and the gate libraries. Check branch protection, and record any gap in ADR-237. Gate libraries must never print `.change.before` or `.change.after`.
- [ ] 2.13 Run `terraform fmt -check` and `validate` on both roots, plus the render, budget and strip suites and all gate suites.

## Phase 3: Core implementation, app (GREEN)

- [ ] 3.1 `git-auth.ts`: take `hostKeyPin` as a positional parameter before `opts`, add `TOFU_FALLBACK_OPTS`, add the pinned arm, and rewrite the doc-comments.
- [ ] 3.2 `git-data-replication.ts`:
  - add `resolveGitDataHostKeyPin`;
  - add guarded pin resolution in remove, provision and replicate;
  - add the `host_key_mismatch` outcome, classified before `SSH_AUTH_FAILURE`.
- [ ] 3.3 `git-data-client.ts`: guarded pin resolution in `fetchFromGitData`.
- [ ] 3.4 Log a startup line at `logger.warn` (Vector ships only lines at level 40 and above): `git_data_pin=present fp=…|absent`.
- [ ] 3.5 Update the comment table in `account-delete.ts`.
- [ ] 3.6 Run `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` and `./node_modules/.bin/vitest run <touched tests>`.

## Phase 4: Docs and legal

- [ ] 4.1 Runbook `git-data-luks-cutover-5274.md`:
  - rewrite the precondition checklist, including "pin present AND #5914 closed" before any flag flip;
  - add the post-merge sequence and the verdict rows;
  - add the notes on rotation, expected drift, operator-local `host_key`, the emergency-replace gap, H4 escalation and re-capture.
- [ ] 4.2 ADR-237 (provisional ordinal, status adopting). Amend ADR-220 (close the D4 residual, record the D6 design change) and ADR-068 (one line).
- [ ] 4.3 `model.c4`: update the edge text. Run c4-count-parity, c4-code-syntax and c4-render.
- [ ] 4.4 Rewrite the header comment in `workspaces-luks-verify.yml` without the literal option strings.
- [ ] 4.5 Article 30 register, PA-36 §(g): add the new DRAFTED item and correct (g)(11). Do not touch the sentences #8218 covers.
- [ ] 4.6 Add the conditioned addendum to the counsel audit `2026-07-counsel-review-6588.md`.
- [ ] 4.7 `scripts/encryption-posture-ledger.json`: add 4 connections and the exception (#5914). Run `lint-encryption-posture.py --repo-sweep`.
- [ ] 4.8 File F1, F2, F4 and F5, checking that the labels exist. Leave notes on #8211 and #5914.

## Phase 5: Pre-merge verification

- [ ] 5.1 Push, then dispatch `workspaces-luks-verify.yml --ref <branch>` and wait for `success` (AC15).
- [ ] 5.2 Re-check that the ADR-237 ordinal is free across all `origin/*` refs.
- [ ] 5.3 Walk through AC1–AC16.
