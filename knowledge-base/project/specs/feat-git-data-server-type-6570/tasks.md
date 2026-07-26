---
feature: git-data-server-type-6570
issue: 6570
pr: 6974
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-27-fix-git-data-server-type-off-arm-plan.md
date: 2026-07-27
---

# Tasks — git-data server type `cax11` → `cpx22` + dual-arch derivation

Phase order is load-bearing: contract (Phase 2) before consumer (Phase 3).

## Phase 0 — Preconditions (no edits)

- [ ] 0.1 `git fetch origin main`; confirm zero drift on `variables.tf`, `git-data.tf`,
      `cloud-init-git-data.yml`, `expenses.md` (TR7)
- [ ] 0.2 Confirm all three Doppler sites still pin `3.75.3` and the checksum pair still agrees:
      `grep -n 'doppler_sha256\|DOPPLER_VERSION' apps/web-platform/infra/{zot-registry.tf,inngest-host.tf,cloud-init-*.yml}`
- [ ] 0.3 **Verify `architecture` exists on `data.hcloud_server_type`** (hcloud v1.63.0). If absent,
      DROP task 2.5 (FR6b) and record why — do not improvise a substitute
- [ ] 0.4 Re-probe live `cpx22` orderability (informational; the birth dispatch re-probes for real)

## Phase 1 — RED: dual-arch guard suite

- [ ] 1.1 Create `apps/web-platform/infra/git-data-host.test.sh`, mirroring `inngest-host.test.sh` §5
  - [ ] 1.1.1 Assert `local.git_data_arch` declared + derived via `startswith(..., "cax")`
  - [ ] 1.1.2 Assert `local.git_data_doppler_sha256` declares BOTH 64-hex checksums
  - [ ] 1.1.3 Assert no hardcoded `linux_arm64`/`linux_amd64` in `cloud-init-git-data.yml`
  - [ ] 1.1.4 Assert no hardcoded 64-hex `DOPPLER_SHA256` literal in `cloud-init-git-data.yml`
  - [ ] 1.1.5 Assert the templatefile map passes `doppler_arch` + `doppler_sha256`
  - [ ] 1.1.6 Assert `var.git_data_server_type` carries a `validation` block
- [ ] 1.2 Register the suite in `.github/workflows/infra-validation.yml` (alongside
      `inngest-host.test.sh:700`) — **mandatory**, else `run-registered-suites.sh` flags an orphan
- [ ] 1.3 Confirm the suite FAILS (RED) before Phase 2

## Phase 2 — GREEN part 1: the contract

- [ ] 2.1 `variables.tf`: `git_data_server_type` default `cax11` → `cpx22` (FR1)
- [ ] 2.2 `variables.tf`: rewrite `description` (2 vCPU x86 / 4 GB; arch DERIVED; stock-forced, not a resize)
- [ ] 2.3 `variables.tf`: add `validation` rejecting prefixes outside `^(cax|cpx|cx|ccx)` (FR5),
      mirroring `inngest_server_type:260`
- [ ] 2.4 `git-data.tf`: extend `locals` (`:69-77`) with `git_data_arch` + `git_data_doppler_sha256`
      (FR2/FR3), copying the `inngest-host.tf:57-66` comment shape; reuse the checksum pair verbatim
- [ ] 2.5 `git-data.tf`: add `data "hcloud_server_type" "git_data"` (FR6), mirroring `zot-registry.tf:134`
  - [ ] 2.5.1 *(optional, FR6b — only if 0.3 verified)* add `lifecycle.precondition` cross-checking
        `local.git_data_arch` against the live `architecture` attribute
- [ ] 2.6 `git-data.tf`: rewrite the void `# cax11 = ARM64 (Ampere); git/sshd are ARM-native` comment
      at `:120` (FR7)

## Phase 3 — GREEN part 2: the consumer (atomic pair — same commit)

- [ ] 3.1 `cloud-init-git-data.yml`: header comment `Doppler CLI (arm64)` → arch-derived wording
- [ ] 3.2 `cloud-init-git-data.yml`: `DOPPLER_SHA256="${doppler_sha256}"` (drop the literal)
- [ ] 3.3 `cloud-init-git-data.yml`: URL → `..._linux_${doppler_arch}.tar.gz`
- [ ] 3.4 **Keep `$${DOPPLER_VERSION}` double-`$`** — it is a shell var, not a Terraform one.
      Highest-risk edit in the PR
- [ ] 3.5 `git-data.tf` templatefile map: add `doppler_arch` + `doppler_sha256`
- [ ] 3.6 Confirm Phase 1's suite now passes (GREEN)

## Phase 4 — Ledger

- [ ] 4.1 `expenses.md` row 19: `Hetzner CAX11 (git-data)` → `CPX22`, `4.10` → `~21.05` USD
      (EUR 19.49 × ~1.08 FX) (FR8)
- [ ] 4.2 Status STAYS `approved-not-billing` (host still unborn); keep the PHANTOM-ROW note
- [ ] 4.3 Carry the identical-net-vs-gross caveat + a `verify_by` marker

## Phase 5 — ADR-143 addendum

- [ ] 5.1 Append a dated addendum recording D1–D10 (FR9). No new ADR ordinal (D8/TR8)
- [ ] 5.2 **Amend** the closing "Not changed by this addendum" paragraph, which currently asserts
      `var.git_data_server_type` keeps its unorderable default — leaving it makes the ADR contradict itself

## Phase 6 — Verification

- [ ] 6.1 `cd apps/web-platform/infra && terraform init -input=false && terraform validate`
- [ ] 6.2 `terraform plan` — assert NO diff on `hcloud_volume.git_data*`,
      `random_password.git_data_luks`, `doppler_secret.git_data_luks_key` (TR2/AC5).
      `hcloud_server.git_data` CREATE is expected and NOT applied (NG1)
- [ ] 6.3 AC6: `TF_VAR_git_data_server_type=cx99 terraform plan` aborts at PLAN
- [ ] 6.4 `bash apps/web-platform/infra/git-data-host.test.sh` — GREEN (AC7)
- [ ] 6.5 `cd apps/web-platform && ./node_modules/.bin/vitest run test/…cloud-init-user-data-size…` (AC9)
- [ ] 6.6 `bash apps/web-platform/infra/run-registered-suites.sh` — zero orphans (~25 min, AC8)
- [ ] 6.7 `bash scripts/test-all.sh`
- [ ] 6.8 AC13: every `knowledge-base/` path cited in the plan resolves

## Phase 7 — Ship prep

- [ ] 7.1 PR body carries the brainstorm's Premise Corrections table (AC12)
- [ ] 7.2 PR body uses `Closes #6570`
- [ ] 7.3 Confirm no `### Post-merge (operator)` steps exist — the birth is deliberately out of scope
