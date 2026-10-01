---
feature: feat-one-shot-8189-git-data-root-key
plan: knowledge-base/project/plans/2026-09-15-feat-git-data-root-key-separate-root-plan.md
issue: 8189
lane: cross-domain
revision: v4 (deepened 2026-09-15)
---

# Tasks — git-data root key (#8189)

## Phase 0 — Probes, baselines, follow-ups

- [x] 0.1 Re-measure baselines: parity 197/0, replace gate 23/0, birth gate 114/0, access suite 69/0/0, rung-2 gate RELEASED `5c50797be839…`.
- [x] 0.2 Doppler read-only probe: project limit and identity availability.
- [ ] 0.3 Record the measured Doppler CLI semantics (absent + `--no-exit-on-missing-secret` → rc 0, empty; bad config → rc 1) in the flag-precheck header.
- [x] 0.4 Fingerprint form: normalize the arm and the apply's print step to one `SHA256:` form (`ssh-keygen -l -E sha256` on the public key).
- [ ] 0.5 Scratch `terraform validate` of the planned root (`-backend=false`); generate the lock with `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`.
- [x] 0.6 Consumer sweep of `git-data-cutover.sh` and the functions to delete; list every edit.
- [x] 0.7 Resolve 40-char SHA pins for `actions/checkout`, `hashicorp/setup-terraform`, `DopplerHQ/cli-action`; pin the Doppler CLI version.
- [x] 0.8 Identify the `web-git-data-probe` heartbeat monitor and its read-only state API call.
- [x] 0.9 File F1, F2, F4 (dedupe first; milestone Post-MVP / Later) with the bodies the plan specifies; comment on #8093 (hook prose, root-login detection, `removeGitDataRepo` connect timeout).

## Phase 1 — RED (harness conventions: `mutate()` helper, `MUTANT_FLOOR`, `True`-key YAML lookup, `is False`, census lower bounds, per-name Doppler shim, `diff` timelines, stub-based RED ledger)

- [ ] 1.1 New `apps/web-platform/infra/git-data-flag-precheck.test.sh` (Guard 1).
- [ ] 1.2 Access suite: Guards 2, 3, 5, 6 (cutover half), 7; D-6 step order; key-fetch and `ssh_config` steps; fix `mutating()` for `findmnt` and WF9's `DOPPLER_TOKEN_WRITE` allowance.
- [ ] 1.3 New `tests/scripts/test-git-data-root-key-arm.sh` (Guard 4 incl. fingerprint rows and call-site census); extend replace and birth gate fixtures with `prior_state` and a fingerprint file.
- [ ] 1.4 New `apps/web-platform/infra/git-data-root-key.test.sh` (Guard 6 root half, Guard 8 allowlist/parse/census/notify job, backend key, `prevent_destroy`, root census, no `terraform_remote_state`, path exclusion).
- [ ] 1.5 `plugins/soleur/test/infra-validation-detect.test.sh`: nested root collapses to the parent.
- [ ] 1.6 Record each behavioral row RED against `origin/main` bytes in the per-row ledger.

## Phase 2 — New root

- [ ] 2.1 `apps/web-platform/infra/git-data-root-key/{main,variables,key,access}.tf` + lock file per D-1 (copied `app_auth`; no output/nonsensitive/local_file/local-exec/provisioner; `prevent_destroy` on key, Hetzner key, Doppler project/environment/secret).
- [ ] 2.2 `.github/workflows/apply-git-data-root-key.yml`: dispatch-only, typed `confirm` + `rotate_read_token`, environment, job-level `git-data-state`, SHA pins, `terraform_wrapper: false`, readonly lock, allowlist refusal with parse check, fingerprint print, plan-file shred, `notify-root-key-apply` job.
- [ ] 2.3 `infra-validation.yml` validate step for the root; `apply-web-platform-infra.yml` path exclusion.

## Phase 3 — Web-platform root and create gates

- [ ] 3.1 `git-data.tf` data source + `tostring` concat.
- [ ] 3.2 `tests/scripts/lib/git-data-root-key-arm.sh` (prior_state, exactly-one, name, fingerprint file, set comparison); source it from the replace and birth gates; pass the fingerprint file path from `apply-web-platform-infra.yml`.
- [ ] 3.3 Parity suite reads 197/0 with no edit to it (stop and re-plan otherwise).

## Phase 4 — Script and flag precheck

- [ ] 4.1 `apps/web-platform/infra/git-data-flag-precheck.sh` (D-3).
- [ ] 4.2 Delete the cutover body, `web_ssh`, recovery trap branches, mode branches, the in-script flag read.
- [ ] 4.3 Real-mode refusal, `gd_capture` (timeout 30, `head -c 4096`, PIPESTATUS rc, never prints), three store probes.
- [ ] 4.4 Header rewrite (read-only proof until F2; exit codes 3 and 5).

## Phase 5 — Workflow

- [ ] 5.1 `git-data-cutover.yml` per D-6 (one input, workflow-level `git-data-state`, one gated job, flag precheck step before the bridge, key fetch with masks and `ssh-keygen -y` check, hardened `ssh_config` with literal ProxyCommand target, teardown).
- [ ] 5.2 Register new suites in `infra-validation.yml`; `actionlint`.

## Phase 6 — Docs and records

- [ ] 6.1 ADR-220 dated amendment log (D2, D3, D4 residuals incl. HCLOUD_TOKEN, host `prd_git_data` token exposure, unauthenticated evidence, `secrets: inherit`; D5; D6 F2 preconditions incl. fresh replace + LUKS key rotation).
- [ ] 6.2 C4 `github -> gitDataStore` edge; C4 tests + count parity.
- [ ] 6.3 Runbook rewrite (read-only proof, post-merge order AC16–AC19, verdict map incl. L3/L7 split, pending-approval hold, Delete Account events during replace, breach trigger, web-2 removal).
- [ ] 6.4 Article 30 TOM within CLO limits (fingerprint-checked create delivery) + cross-references + Superseded markers + secrets bullet.
- [ ] 6.5 Authorization accounting (#8009 C1) and roadmap row (F1, F2).
- [ ] 6.6 Sweep "until #8189" / "not yet"; encryption-posture ledger reconcile.

## Phase 7 — Validation and learning

- [ ] 7.1 Full battery via `setsid nohup` from Bash, watched by a separate Monitor.
- [ ] 7.2 `fixture-scan.py --rule relative` on new shell write sites; infra human-steps lint; guard-contract lint; rung-2 gate.
- [ ] 7.3 Compound learning under `knowledge-base/project/learnings/security-issues/` with the four PR #8187 session errors.
- [ ] 7.4 PR body: `Ref #8189`, `Ref #6680`, `Ref #8093`; merging fires only the web-platform push apply; the root-key apply is dispatch-only; no prod dispatch claimed.

## Post-merge (explicit authorization at each prod step)

- [ ] 8.1 Authorized, approved `apply-git-data-root-key.yml` dispatch; record the printed fingerprint; record the push apply's Plan line (AC16).
- [ ] 8.2 PR committing `apps/web-platform/infra/git-data-root-key.fingerprint` (AC17).
- [ ] 8.3 Authorized `git_data_host_replace` from `main`; `web-git-data-probe` heartbeat green via its API (AC18).
- [ ] 8.4 Authorized, approved dry-run dispatch from `main`; flip D1b with the caveat; close #6680 and #8189 with the run URL (AC19).

## Phase 0 results (measured 2026-09-15, /work)

- 0.1 parity 197/0; replace gate 23/0; birth gate 114/0; access suite 69/0/0; rung-2 gate `RELEASED … 5c50797be8392fe551a940ae04555c52a3f4409cf249ed11bb1280fec783d5b1`.
- 0.2 Doppler workplace currently lists 4 projects (`doppler projects --json | length`); identities not probed further (plan tier already recorded in DC-3).
- 0.4 Hetzner `GET /v1/ssh_keys` returns `fingerprint` in MD5 colon-hex form, so the arm and the apply's print step derive `SHA256:` with `ssh-keygen -l -E sha256` from `public_key`.
- 0.6 Extra consumer the plan did not list: `apps/web-platform/infra/git-data-luks.test.sh` asserts the cutover body (GAP-1/GAP-2/A8/A10, `verify_set_identity`); its rows are retired with the body.
- 0.7 Pins: `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`, `hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85 # v4.0.0`, `DopplerHQ/cli-action@5351693ec144fc7f7a2d30025061acfc3c53c47c # v4`.
- 0.8 `web-git-data-probe.sh` pings `GIT_DATA_HEARTBEAT_URL` on success (Better Stack heartbeat).
- 0.9 Filed F1 #8209, F4 #8210, F2 #8211 (milestone Post-MVP / Later); #8093 comment posted.
