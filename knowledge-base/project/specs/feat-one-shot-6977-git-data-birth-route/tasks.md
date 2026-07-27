# Tasks: feat(6977) — give `git-data` an executable birth route

Plan: `knowledge-base/project/plans/2026-07-27-feat-git-data-host-birth-route-plan.md`
Lane: `cross-domain` (spec.md absent → fail-closed default)
Open scope decisions: `knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/decision-challenges.md`

> **SCOPE FENCE — no task below dispatches the workflow or creates any resource.**

## Phase 0: Preconditions

- [ ] 0.1 Re-run the trap-#3 clearance: confirm neither `git-data.tf`, `git-data-luks.tf` nor
      `cloud-init-git-data.yml` appears in any `triggers_replace` / `filesha256` in
      `apps/web-platform/infra/*.tf`
- [ ] 0.2 Re-verify the ADR-149 ordinal is still free against `origin/main`
- [ ] 0.3 Read `tests/scripts/lib/web-host-birth-gate.sh` + `tests/scripts/test-web-host-birth-gate.sh`
      in full — they are the template; the new files must read as siblings, not a fork
- [ ] 0.4 ADR-130-style scope probe: confirm `var.doppler_token_tf` can create a **branch config**
      (distinct API surface from `doppler_environment`) before relying on it
- [ ] 0.5 Determine `doppler_config`'s already-exists failure mode (errors vs adopts) and whether a
      `terraform import` would be needed if the config is ever hand-created first
- [ ] 0.6 Note (no action — out of scope): `git-data-cutover.sh` drives a `soleur-web.service`
      systemd unit that does not exist, at both the flip and rollback sites. #5274/#6982 owns it;
      do NOT add a third caller of that phantom unit here

## Phase 1: Gate contracts (RED first)

- [ ] 1.1 Extract `tests/scripts/lib/plan-gate-preamble.sh` (~40 lines from `web-host-birth-gate.sh`)
  - [ ] 1.1.1 `assert_plan_readable`, `assert_actions_classifiable`, `assert_counters_numeric`
  - [ ] 1.1.2 Write `tests/scripts/test-plan-gate-preamble.sh`
- [ ] 1.2 Write `tests/scripts/test-git-data-host-birth-gate.sh` **before** the gate
  - [ ] 1.2.1 Harness: `set -uo pipefail`, `mktemp -d` + `trap`, `mk_plan`/`rc_entry` synthesizers
        using `jq -R .`, `check <name> <want_rc> <needle> <plan>` pinning rc **and** message
  - [ ] 1.2.2 Fixtures synthesized only (`cq-test-fixtures-synthesized-only`)
  - [ ] 1.2.3 Reject arms: missing file · unparseable plan · unclassifiable actions · counter parse
        failure · cardinality (0 and >1, distinct messages) · identity · destroys (delete+forget) ·
        named volume-destroy (issue AC2) · reboot-forcing update · out-of-scope via `IN(...)`
  - [ ] 1.2.4 **Firewall-content arm**: `update` adding rules to `hcloud_firewall.git_data` REFUSED
  - [ ] 1.2.5 **LUKS-passphrase arm**: delete/forget/update on the pair REFUSED
  - [ ] 1.2.6 **Requirement arm split by entailment**: `creates == 1` for the four id-referencing
        addresses only; **presence** (`create`∨`no-op`) for the rest
  - [ ] 1.2.7 **Partial-birth resume fixture** (mixed `create`/`no-op`) must **PASS**
  - [ ] 1.2.8 Backstop arms: heartbeat pair and `terraform_data.git_data_probe_install` REFUSED
- [ ] 1.3 Implement `tests/scripts/lib/git-data-host-birth-gate.sh`; source the preamble;
      `def allow:` (singleton, no key arg); per-arm messages; telemetry line before the verdict
- [ ] 1.4 Mutation battery
  - [ ] 1.4.1 SOLE-GUARD: destroy · out-of-scope · requirement · firewall-content · LUKS-passphrase
  - [ ] 1.4.2 LAYERED + control: identity · cardinality · reboot
  - [ ] 1.4.3 `cmp -s` non-vacuity floor on **every** mutation
- [ ] 1.5 Write `tests/scripts/lib/git-data-birth-readiness-gate.sh` + its suite
  - [ ] 1.5.1 Sentinel = interpolated `${sentry_dsn}` in the `templatefile` vars block
  - [ ] 1.5.2 Assert **behavior against synthesized fixtures**, never the live count
  - [ ] 1.5.3 Failure message names #6982, the sentinel, the runbook banner and ADR-149
  - [ ] 1.5.4 Arm proving a comment mentioning the word does NOT satisfy the sentinel
- [ ] 1.6 Register both suites in `scripts/test-all.sh` (**not** `run-registered-suites.sh`)

## Phase 2: Workflow job + IaC

- [ ] 2.1 `apply_target` enum + input descriptions
  - [ ] 2.1.1 Add `- git-data-host-create` with its `#6977` comment block
  - [ ] 2.1.2 Extend `confirm` with `BIRTH-GIT-DATA`; replace the accreting `confirm.description`
        with a runbook pointer, moving token literals into job headers
  - [ ] 2.1.3 Fix `registry-ruleset-entrypoint-audit` → `entrypoint-audit` in the field label
  - [ ] 2.1.4 Fix the stale `# NOTE on the input budget` comment (7 inputs used, not 5)
  - [ ] 2.1.5 Do NOT restate an option count
- [ ] 2.2 Add the `git_data_host_create:` job
  - [ ] 2.2.1 `if:` guard mutually exclusive with every other dispatch job
  - [ ] 2.2.2 `environment: web-platform-infra-apply`
  - [ ] 2.2.3 `concurrency:` group **shared with `git_data_host_replace`**
  - [ ] 2.2.4 `permissions: { contents: read }`
- [ ] 2.3 Step order: checkout → setup-terraform → Doppler CLI → validate confirm → ephemeral SSH
      pubkey → verify `DOPPLER_TOKEN` → backend creds + `SENTRY_DSN` non-empty → `terraform init` →
      birth-readiness gate → plan + birth gate + stock preflight → apply → summary (`if: always()`)
  - [ ] 2.3.1 `SENTRY_DSN` read uses `|| rc=$?`, never `; rc=$?`; distinct unreadable-vs-empty
        messages; never print the value
  - [ ] 2.3.2 `export HCLOUD_TOKEN` from Doppler **before** sourcing the stock gate
  - [ ] 2.3.3 Birth gate **before** stock preflight
  - [ ] 2.3.4 No `-var="image_name=…"`
- [ ] 2.4 Plan step: `set +e; set -uo pipefail`, capture `rc=$?` on the very next line, `set -e`
      before `terraform show`
- [ ] 2.5 Apply-failure message per plan §Phase 2.5 (re-dispatch safe; the one replace-not-complete
      exception; do not assert both halves at once)
- [ ] 2.6 IaC edits
  - [ ] 2.6.1 New `resource "doppler_config" "git_data_prd"`; re-point
        `doppler_secret.git_data_luks_key` + `doppler_service_token.git_data` at it
  - [ ] 2.6.2 Retire the obsolete OPERATOR NOTE in `git-data-luks.tf`
  - [ ] 2.6.3 `depends_on = [hcloud_server.git_data]` on the three SSH `doppler_secret`s
  - [ ] 2.6.4 `depends_on = [doppler_secret.git_data_luks_key]` on `hcloud_server.git_data` (P13)
  - [ ] 2.6.5 `terraform validate` — confirm no cycle

## Phase 3: Registries + parity

- [ ] 3.1 `plugins/soleur/test/terraform-target-parity.test.ts`
  - [ ] 3.1.1 Add `"git_data_host_create"` to `stripDispatchJobs`
  - [ ] 3.1.2 Add `GIT_DATA_BIRTH_TARGET_BASES` (18 addresses)
  - [ ] 3.1.3 Add `"doppler_config.git_data_prd"` to `OPERATOR_APPLIED_EXCLUSIONS` — and **never** a
        per-PR `-target` line
  - [ ] 3.1.4 New `describe` block: `source` via `^\s*source\s+` command anchor; borrows no sibling
        gate; environment asserted; `def allow:` == `-target` == const
  - [ ] 3.1.5 Omit the keyed-interpolation and pinned-digest tests (no analogue — drop, don't fake)
  - [ ] 3.1.6 **Trap:** the `stripDispatchJobs` self-pinning guard extracts EVERY `"[a-z0-9_]+"`
        string literal in that function body and asserts each names a real `^  <id>:` job. Add
        `"git_data_host_create"` and a justification comment — but no other string literal
  - [ ] 3.1.7 Use the unparameterized extractor `/def allow:\s*\[([^\]]+)\]/` (this gate is a
        singleton, so the web gate's `def allow\(\$k\):` form does not apply)
- [ ] 3.6 Refresh the stale `MIN_APPLY_TARGET_OPTIONS` sentinel comment in
      `stock-preflight-coverage.test.ts` — it enumerates 10 options and predates
      `web-host-create`/`web-host-replace`. Floors are `>=` so nothing breaks; update the inventory
      while adding the new option rather than letting it rot a third time
- [ ] 3.7 Do NOT add a `stock-preflight` `EXCLUSION_ALLOWLIST` entry — this target stays **gated**
- [ ] 3.2 Add the enum ⇄ `description` parity assertion
- [ ] 3.3 `export TMPDIR="${TMPDIR:-/var/tmp}"` at the top of `scripts/test-all.sh`
- [ ] 3.4 Add the replace-gate regression arm for P13's new upstream `no-op`
- [ ] 3.5 Run `stock-preflight-coverage.test.ts` — confirm auto-enrolment as *gated*, not allowlisted

## Phase 4: Runbook, ADR, C4

- [ ] 4.1 Create `knowledge-base/engineering/operations/runbooks/git-data-birth.md`
  - [ ] 4.1.1 DO-NOT-DISPATCH banner naming #6982 + the interlock
  - [ ] 4.1.2 Dispatch invocation + confirm token
  - [ ] 4.1.3 Post-birth `ci-deploy` remediation; **zero** occurrences of `soleur-web.service`
  - [ ] 4.1.4 "What you now have, and what it is not": empty store · `GIT_DATA_STORE_ENABLED` still
        absent · no monitor · plaintext-backed until the cutover → pointer to
        `git-data-luks-cutover-5274.md`
  - [ ] 4.1.5 Partial-birth decision tree
  - [ ] 4.1.6 Non-SSH verification only; note that the environment approver approves *before* any
        step runs
- [ ] 4.2 Write ADR-149 (provisional ordinal) + amend ADR-145 `## Consequences`
  - [ ] 4.2.1 Three ADR-145 deltas; the interlock + its release checklist
  - [ ] 4.2.2 Residuals: ADR-115 guest-convergence gap; empty-store Art. 17 window
- [ ] 4.3 C4
  - [ ] 4.3.1 Correct `gitDataStore` description (never-born + birth route)
  - [ ] 4.3.2 Correct `betterstack -> founder` ("unfed" is falsified by P8)
  - [ ] 4.3.3 Re-read `hetzner -> gitDataStore` and `claude -> gitDataStore` for the same class
  - [ ] 4.3.4 Run both C4 tests; regenerate `model.likec4.json`
- [ ] 4.4 File the follow-on issue: retrofit the fail-closed preamble into the 5 gates lacking it

## Phase 5: Verification + ship

- [ ] 5.1 Full gate run (see plan §Test Strategy) — record baselines in the PR body, not the plan
- [ ] 5.2 Verify every AC1–AC16
- [ ] 5.3 `/review` — **route the vacuity question to an INDEPENDENT reviewer**: *"find the vacuity
      this mutation battery missed — do not re-run its mutations."* Do not self-certify
- [ ] 5.4 `/ship` — re-verify the ADR-149 ordinal; if it renumbers, sweep plan + tasks + ACs
- [ ] 5.5 Confirm `decision-challenges.md` (DC-1/DC-2/DC-3) is rendered into the PR body and filed
      as an `action-required` issue
- [ ] 5.6 `Ref #6977` — do **not** auto-close; the route ships, the birth does not
