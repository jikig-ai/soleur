---
feature: git-data-server-type-6570
issue: 6570
pr: 6974
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-27-fix-git-data-server-type-off-arm-plan.md
date: 2026-07-27
revision: 2 (post-deepen — R1–R15)
---

# Tasks — git-data server type `cax11` → `cpx22` + dual-arch derivation

**Revision 2.** Rewritten after the deepen-plan panel (12 revisions, 5 P0). Read the plan's
`## Deepen-Plan Revisions` table before starting — several v1 tasks were wrong, not merely
incomplete.

## Phase 0 — Preconditions (no edits)

- [ ] 0.1 `git fetch origin main`; confirm zero drift on `variables.tf`, `git-data.tf`,
      `cloud-init-git-data.yml`, `expenses.md` (TR7)
- [ ] 0.2 Confirm all three Doppler sites still pin `3.75.3` and the checksum pair still agrees
- [ ] 0.3 **Confirm `hcloud_server.git_data` is ABSENT from Terraform state** (R-state). It omits
      `lifecycle.ignore_changes = [user_data]`, so if it *were* in state the plan would show
      `delete → create`, not `create`, and AC5's framing would be wrong
- [ ] 0.4 *(REMOVED — v1's "verify `architecture` exists or drop FR6b" gate is pre-satisfied:
      schema-probed present on hcloud v1.63.0. v1's informational stock re-probe is also removed;
      `stock-preflight-gate.sh` re-probes for real at dispatch.)*

## Phase 1 — RED: four behavioral assertions (`cq-write-failing-tests-before`)

**No new suite (R8).** Append to `apps/web-platform/infra/git-data-luks.test.sh` — it already
defines `CLOUD_INIT="${DIR}/cloud-init-git-data.yml"`, is already registered at
`infra-validation.yml:748`, and already has `assert_holds` / `assert_mutation`. Use the mutation arm
on every new assertion (`cq-assert-anchor-not-bare-token`).

- [ ] 1.1 **A1 — escaping guard**, verbatim from `inngest-host.test.sh:177`:
      `grep -qF 'doppler_$${DOPPLER_VERSION}_linux_${doppler_arch}.tar.gz'`
- [ ] 1.2 **A2 — cross-file checksum parity**: derive canon from `inngest-host.tf:66` +
      `zot-registry.tf:86` (the `CANON_WEB_HOSTS` idiom); assert git-data's arm64 arm byte-equals
      theirs, same for amd64. Catches a **pairing swap** and pins each literal to its arm
- [ ] 1.3 **A3 — derivation orientation**: extract the ternary's own bytes and replay over
      `{cax11→arm64, cpx22→amd64, cx23→amd64, ccx13→amd64}`, with §9b's non-vacuity guard (a failed
      extraction must fail loudly, never silently pass). **This is the only assertion that catches
      an inverted ternary**
- [ ] 1.4 **A4 — default is not `cax*`**: the only static guard against #6570 regressing
- [ ] 1.5 Use `set -uo pipefail` + pass/fail counters, never `set -e` (else RED reports 1 failure
      instead of 4)
- [ ] 1.6 Confirm all four FAIL (true RED) before Phase 2

## Phase 2 — GREEN part 1: the contract

- [ ] 2.1 `variables.tf`: `git_data_server_type` default `cax11` → `cpx22` (FR1)
- [ ] 2.2 `variables.tf`: rewrite `description` (2 vCPU x86 / 4 GB; arch DERIVED; stock-forced)
- [ ] 2.3 `variables.tf`: add `validation` rejecting prefixes outside `^(cax|cpx|cx|ccx)` (FR5)
- [ ] 2.4 `git-data.tf`: extend `locals` with `git_data_arch` + `git_data_doppler_sha256` (FR2/FR3);
      reuse the checksum pair verbatim
- [ ] 2.5 `git-data.tf`: add `data "hcloud_server_type" "git_data"` (FR6)
- [ ] 2.6 **`git-data.tf`: add the FR6b `lifecycle.precondition` — MANDATORY (R1).** Without a
      referent the data source is **pruned by `-target=`** and FR6 fires on zero production paths.
      **Map the enums explicitly (R2):**
      `data.hcloud_server_type.git_data.architecture == (local.git_data_arch == "arm64" ? "arm" : "x86")`.
      A direct comparison is `"amd64" == "x86"` → reds every plan forever
- [ ] 2.7 **`git-data.tf`: add the two templatefile map keys HERE, not Phase 3 (R5)** —
      `templatefile()` accepts extra keys and errors only on missing ones, so map-first is always
      green and removes the bisect hazard
- [ ] 2.8 `git-data.tf`: rewrite the void `# cax11 = ARM64 (Ampere)` comment at `:120` (FR7)

## Phase 3 — GREEN part 2: the consumer (template only)

- [ ] 3.1 `cloud-init-git-data.yml`: header comment → arch-derived wording (also `:123-124`)
- [ ] 3.2 `DOPPLER_SHA256="${doppler_sha256}"` (drop the literal)
- [ ] 3.3 URL → `..._linux_${doppler_arch}.tar.gz`
- [ ] 3.4 **Keep `$${DOPPLER_VERSION}` double-`$`.** Note the *silent* direction (R4): a double-`$`
      on a **Terraform** var renders a literal bash expands to empty, and
      `validate-infra-templates.sh` skips `$${key}` **by design** — nothing catches it but A1
- [ ] 3.5 Confirm Phase 1's four assertions now pass (GREEN)

## Phase 4 — Ledger

- [ ] 4.1 `expenses.md` row 19: `CAX11` → `CPX22`, `4.10` → `~21.05` USD, `2 vCPU AMD x86 / 4 GB`
- [ ] 4.2 Drop the **"cannot be born at ANY account cap"** clause (conflates type-unorderability
      with the cap, and the cap premise is the stale `5`)
- [ ] 4.3 Re-anchor the stale `variables.tf:113` citation (now `:172`), preferring a content anchor
- [ ] 4.4 Drop the **`#6416`** blocker reference — it is CLOSED. Re-verify the ADR-115 `luksOpen`
      half before restating it
- [ ] 4.5 Status STAYS `approved-not-billing`; keep the PHANTOM-ROW note; carry the
      identical-net-vs-gross caveat + `verify_by`

## Phase 4b — G5 sweep: stale `cax11` outside the three obvious files (R13)

- [ ] 4b.1 `.github/workflows/apply-web-platform-infra.yml:2393` — the CI error string
      *"cax11 has had no EU stock, so it cannot be born at any account cap"* is wrong on **both**
      clauses after this PR, and fires on the exact path an operator debugs a failed birth (FR12)
- [ ] 4b.2 Same file `:2373` — matching comment
- [ ] 4b.3 `knowledge-base/legal/article-30-register.md:69` — correct the `cax11` clause (FR13).
      **Flag** (do not necessarily fix) the same row's stale `cx23` for web-2 — pre-existing drift
      from #6966/#6967. Regulated surface, but a factual correction to a row marked
      DRAFTED / NOT-YET-ACTIVE; note in the PR body

## Phase 5 — ADR record (split, R12)

- [ ] 5.1 **ADR-068** gets the D1–D10 decision record — git-data is ADR-068's element, not ADR-143's
- [ ] 5.2 **ADR-143** gets the correction only: amend the closing "Not changed by this addendum"
      paragraph asserting `var.git_data_server_type` keeps its unorderable default, + a forward
      pointer. Leaving it ships a self-contradictory ADR
- [ ] 5.3 No new ordinal — both are addenda (D8/TR8)

## Phase 6 — Verification

> **AC5/AC6 are credentialed live-prod reads.** 26 no-default vars + an R2 backend mean a bare
> `terraform plan` fails immediately. Use
> `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan …` with
> `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` exported. This holds `HCLOUD_TOKEN` (destroy authority
> over the whole prod fleet) and contends for R2 state. Read-only, but an operator step.

- [ ] 6.1 `terraform init -input=false && terraform validate` (via the wrapper above)
- [ ] 6.2 **AC5 differential**: `terraform show -json` before vs after; assert **identical** on
      `hcloud_volume.git_data`, `git_data_luks`, `random_password.git_data_luks`,
      `doppler_secret.git_data_luks_key`. Do **not** assert no-change on the two
      `hcloud_volume_attachment.*` — they legitimately recreate
- [ ] 6.3 **AC6a/b/c**: `cpx99` → stderr `/cpx99/` + `/not found/`; `zz11` → FR5's `error_message`;
      `cpx22` → succeeds past the data-source read (**the positive control is load-bearing**)
- [ ] 6.4 `bash apps/web-platform/infra/git-data-luks.test.sh` — GREEN
- [ ] 6.5 **TR3 restored (R14)**: `curl -sL …/doppler_3.75.3_linux_amd64.tar.gz | sha256sum` equals
      `9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db`
- [ ] 6.6 **TR5 restored (R14)**: confirm `stock-preflight-gate.sh` reads the new type and no test
      encodes today's availability. **Now the sole orderability guard** — FR6 catches only phantom
      types, not unorderable ones
- [ ] 6.7 `bash apps/web-platform/infra/run-registered-suites.sh` — exits 0 and adds **no new**
      orphan vs the `origin/main` baseline (9 pre-existing; the check is advisory)
- [ ] 6.8 `cloud-init-user-data-size.test.ts` passes
- [ ] 6.9 `bash scripts/test-all.sh` — note it does **not** cover `apps/web-platform/infra/`
- [ ] 6.10 AC13 in its fixed form (must be able to `exit 1`)

## Phase 7 — Ship prep

- [ ] 7.1 PR body carries the Premise Corrections table (AC12)
- [ ] 7.2 PR body notes the Art. 30 register touch (Phase 4b.3)
- [ ] 7.3 `Closes #6570` in the body
- [ ] 7.4 Confirm no `### Post-merge (operator)` steps — the birth is out of scope and now tracked
      by **#6977**
