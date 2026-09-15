---
feature: feat-one-shot-8189-git-data-root-key
plan: knowledge-base/project/plans/2026-09-15-feat-git-data-root-key-separate-root-plan.md
issue: 8189
lane: cross-domain
---

# Tasks — git-data root key (#8189)

## Phase 0 — Probes, baselines, follow-ups

- [ ] 0.1 Re-measure baselines: parity 197/0, replace gate 23/0, birth gate 114/0, access suite 69/0/0, rung-2 gate RELEASED `5c50797be839…`.
- [ ] 0.2 Doppler read-only probe: project limit and identity availability.
- [ ] 0.3 `doppler secrets get <absent> --plain --no-exit-on-missing-secret -p soleur -c dev`: record rc/output; pick D-3's form.
- [ ] 0.4 Scratch plan-JSON shape for `data "hcloud_ssh_keys"` (structure only; scratch dir deleted).
- [ ] 0.5 Scratch `terraform validate` of the planned root (`-backend=false`).
- [ ] 0.6 Consumer sweep of `git-data-cutover.sh` and the functions to delete; list every edit.
- [ ] 0.7 File F1, F2, F4 (dedupe first; milestone Post-MVP / Later) with the bodies the plan specifies; comment on #8093.

## Phase 1 — RED

- [ ] 1.1 Access suite: Guards 1, 2, 3, 5, 6 (cutover half), 7; D-6 YAML; key-fetch and `ssh_config` steps.
- [ ] 1.2 New `tests/scripts/test-git-data-root-key-arm.sh` (Guard 4 + call-site census); extend replace and birth gate fixtures with `prior_state`.
- [ ] 1.3 New `apps/web-platform/infra/git-data-root-key.test.sh` (Guard 6 root half, Guard 8, backend key, `prevent_destroy`, no `terraform_remote_state`, path exclusion).
- [ ] 1.4 `plugins/soleur/test/infra-validation-detect.test.sh`: nested root collapses to the parent.
- [ ] 1.5 Record each behavioral row RED against `origin/main` bytes.

## Phase 2 — New root

- [ ] 2.1 `apps/web-platform/infra/git-data-root-key/{main,variables,key,access}.tf` + lock file per D-1.
- [ ] 2.2 `.github/workflows/apply-git-data-root-key.yml` (environment, `git-data-state`, additive-only refusal, no plan exposure).
- [ ] 2.3 `infra-validation.yml` validate step for the root; `apply-web-platform-infra.yml` path exclusion.

## Phase 3 — Web-platform root and create gates

- [ ] 3.1 `git-data.tf` data source + `tostring` concat.
- [ ] 3.2 `tests/scripts/lib/git-data-root-key-arm.sh`; source it from the replace and birth gates.
- [ ] 3.3 Parity suite reads 197/0 with no edit to it (stop and re-plan otherwise).

## Phase 4 — Script

- [ ] 4.1 Delete the cutover body, `web_ssh`, recovery trap branches, mode branches.
- [ ] 4.2 Real-mode refusal, fail-closed `read_flag`, `gd_capture`, three store probes.
- [ ] 4.3 Header rewrite (read-only proof until F2; exit codes 3 and 5).

## Phase 5 — Workflow

- [ ] 5.1 `git-data-cutover.yml` per D-6 (one input, workflow-level `git-data-state`, one gated job, key fetch, `ssh_config`, teardown).
- [ ] 5.2 Register new suites in `infra-validation.yml`; `actionlint`.

## Phase 6 — Docs and records

- [ ] 6.1 ADR-220 dated amendment log.
- [ ] 6.2 C4 `github -> gitDataStore` edge; C4 tests + count parity.
- [ ] 6.3 Runbook rewrite (read-only proof, verdict map, pending-approval hold, no-downtime replace, breach trigger, web-2 removal).
- [ ] 6.4 Article 30 TOM within CLO limits + cross-references + Superseded markers + secrets bullet.
- [ ] 6.5 Authorization accounting (#8009 C1) and roadmap row (F1, F2).
- [ ] 6.6 Sweep "until #8189" / "not yet"; encryption-posture ledger reconcile.

## Phase 7 — Validation and learning

- [ ] 7.1 Full battery via `setsid nohup` from Bash, watched by a separate Monitor.
- [ ] 7.2 `fixture-scan.py --rule relative` on new shell write sites; infra human-steps lint; guard-contract lint.
- [ ] 7.3 Compound learning under `knowledge-base/project/learnings/security-issues/` with the four PR #8187 session errors.
- [ ] 7.4 PR body: `Ref #8189`, `Ref #6680`, `Ref #8093`; the two applies the merge fires; no prod dispatch claimed.

## Post-merge (explicit authorization at each prod step)

- [ ] 8.1 Approve and verify the `apply-git-data-root-key.yml` push apply (AC16).
- [ ] 8.2 Record the web-platform push apply's Plan line (AC17).
- [ ] 8.3 Authorized `git_data_host_replace` from `main` (AC18).
- [ ] 8.4 Authorized, approved dry-run dispatch from `main`; close #6680 and #8189 with the run URL (AC19).
