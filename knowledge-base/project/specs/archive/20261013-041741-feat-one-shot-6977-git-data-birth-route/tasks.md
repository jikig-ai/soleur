# Tasks: feat(6977) — give `git-data` an executable birth route

Plan: `knowledge-base/project/plans/2026-07-27-feat-git-data-host-birth-route-plan.md`
Lane: `cross-domain` (spec.md absent → fail-closed default)
Open scope decisions: `knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/decision-challenges.md`

> **SCOPE FENCE — no task below dispatches the workflow or creates any resource.**

## Phase 0: Preconditions

- [x] 0.1 Re-run the trap-#3 clearance: confirm neither `git-data.tf`, `git-data-luks.tf` nor
      `cloud-init-git-data.yml` appears in any `triggers_replace` / `filesha256` in
      `apps/web-platform/infra/*.tf`
      → **CLEARED.** The only `filesha256` in the tree is `filesha256("${path.module}/${f}")` over
      `local.host_script_files` (server.tf); none of the three is a member. Same sweep confirms
      AC13's premise from the other side: `web-git-data-probe.sh` **is** a member, so it is
      double-hashed (coherence hash + the `terraform_data.git_data_probe_install` SSH provisioner)
      and stays untouched.
- [x] 0.2 Re-verify the ADR-149 ordinal is still free against `origin/main`
      → **FREE.** `ADR-148` is highest on `origin/main`.
- [x] 0.3 Read `tests/scripts/lib/web-host-birth-gate.sh` + `tests/scripts/test-web-host-birth-gate.sh`
      in full — they are the template; the new files must read as siblings, not a fork
      → Read (293 + 438 lines). Harness to mirror: `mk_plan`/`rc_entry`/`rc_noactions`/`rc_update`,
      `check <name> <want_rc> <needle> <plan>`, `mutate_and_check` (SOLE-GUARD) and
      `mutate_layered` (LAYERED, with its unmutated-gate control), both with the `cmp -s`
      non-vacuity floor.
- [x] 0.4 ADR-130-style scope probe: confirm `var.doppler_token_tf` can create a **branch config**
      (distinct API surface from `doppler_environment`) before relying on it
      → **PROVED BY MEASUREMENT, not inferred.** `var.doppler_token_tf` is the sole `provider
      "doppler"` token (main.tf) and is a **personal** token (`/v3/me` → `{"type":"personal",
      "workplace":"Soleur"}`). A live `POST /v3/configs` for a throwaway branch config under
      `soleur`/`prd` returned **http=200** (`root:false`, i.e. a branch config, the exact shape
      `prd_git_data` needs). Throwaway deleted; the `prd` config list is byte-for-byte the original
      seven and `prd_git_data` remains ABSENT so Terraform creates it.
- [x] 0.5 Determine `doppler_config`'s already-exists failure mode (errors vs adopts) and whether a
      `terraform import` would be needed if the config is ever hand-created first
      → **IT ERRORS — it does not adopt.** A repeated create returned **http=400**
      `{"messages":["Name is already in use"]}`. So a hand-created `prd_git_data` makes the first
      `terraform apply` **fail**, and recovery is `terraform import doppler_config.git_data_prd
      soleur.prd_git_data` — NOT a re-dispatch. This must appear in the runbook's partial-birth
      decision tree; it is the one failure mode the additive re-dispatch story does not cover.
- [x] 0.6 Note (no action — out of scope): `git-data-cutover.sh` drives a `soleur-web.service`
      systemd unit that does not exist, at both the flip and rollback sites. #5274/#6982 owns it;
      do NOT add a third caller of that phantom unit here
      → Confirmed and left alone; `git-data-cutover.sh` is not in Files to Edit. AC5 forbids the
      unit name in the new runbook.

## Phase 1: Gate contracts (RED first)

- [x] 1.1 Extract `tests/scripts/lib/plan-gate-preamble.sh` (~40 lines from `web-host-birth-gate.sh`)
  - [x] 1.1.1 `assert_plan_readable`, `assert_actions_classifiable`, `assert_counters_numeric`
  - [x] 1.1.2 Write `tests/scripts/test-plan-gate-preamble.sh`
- [x] 1.2 Write `tests/scripts/test-git-data-host-birth-gate.sh` **before** the gate
  - [x] 1.2.1 Harness: `set -uo pipefail`, `mktemp -d` + `trap`, `mk_plan`/`rc_entry` synthesizers
        using `jq -R .`, `check <name> <want_rc> <needle> <plan>` pinning rc **and** message
  - [x] 1.2.2 Fixtures synthesized only (`cq-test-fixtures-synthesized-only`)
  - [x] 1.2.3 Reject arms: missing file · unparseable plan · unclassifiable actions · counter parse
        failure · cardinality (0 and >1, distinct messages) · identity · destroys (delete+forget) ·
        named volume-destroy (issue AC2) · reboot-forcing update · out-of-scope via `IN(...)`
  - [x] 1.2.4 **Firewall-content arm**: `update` adding rules to `hcloud_firewall.git_data` REFUSED
  - [x] 1.2.5 **LUKS-passphrase arm**: delete/forget/update on the pair REFUSED
  - [x] 1.2.6 **Requirement arm split by entailment**: `creates == 1` for the four id-referencing
        addresses only; **presence** (`create`∨`no-op`) for the rest
  - [x] 1.2.7 **Partial-birth resume fixture** (mixed `create`/`no-op`) must **PASS**
  - [x] 1.2.8 Backstop arms: heartbeat pair and `terraform_data.git_data_probe_install` REFUSED
- [x] 1.3 Implement `tests/scripts/lib/git-data-host-birth-gate.sh`; source the preamble;
      `def allow:` (singleton, no key arg); per-arm messages; telemetry line before the verdict
- [x] 1.4 Mutation battery
  - [x] 1.4.1 SOLE-GUARD: destroy · out-of-scope · requirement · firewall-content · LUKS-passphrase
  - [x] 1.4.2 LAYERED + control: identity · cardinality · reboot
  - [x] 1.4.3 `cmp -s` non-vacuity floor on **every** mutation
- [x] 1.5 Write `tests/scripts/lib/git-data-birth-readiness-gate.sh` + its suite
  - [x] 1.5.1 Sentinel = interpolated `${sentry_dsn}` in the `templatefile` vars block
  - [x] 1.5.2 Assert **behavior against synthesized fixtures**, never the live count
  - [x] 1.5.3 Failure message names #6982, the sentinel, the runbook banner and ADR-149
  - [x] 1.5.4 Arm proving a comment mentioning the word does NOT satisfy the sentinel
- [x] 1.6 Register both suites in `scripts/test-all.sh` (**not** `run-registered-suites.sh`)

## Phase 2: Workflow job + IaC

- [x] 2.1 `apply_target` enum + input descriptions
  - [x] 2.1.1 Add `- git-data-host-create` with its `#6977` comment block
  - [x] 2.1.2 Extend `confirm` with `BIRTH-GIT-DATA`; replace the accreting `confirm.description`
        with a runbook pointer, moving token literals into job headers
  - [x] 2.1.3 Fix `registry-ruleset-entrypoint-audit` → `entrypoint-audit` in the field label
  - [x] 2.1.4 Fix the stale `# NOTE on the input budget` comment (7 inputs used, not 5)
  - [x] 2.1.5 Do NOT restate an option count
- [x] 2.2 Add the `git_data_host_create:` job
  - [x] 2.2.1 `if:` guard mutually exclusive with every other dispatch job
  - [x] 2.2.2 `environment: web-platform-infra-apply`
  - [x] 2.2.3 `concurrency:` group **shared with `git_data_host_replace`**
  - [x] 2.2.4 `permissions: { contents: read }`
- [x] 2.3 Step order: checkout → setup-terraform → Doppler CLI → validate confirm → ephemeral SSH
      pubkey → verify `DOPPLER_TOKEN` → backend creds + `SENTRY_DSN` non-empty → `terraform init` →
      birth-readiness gate → plan + birth gate + stock preflight → apply → summary (`if: always()`)
  - [x] 2.3.1 `SENTRY_DSN` read uses `|| rc=$?`, never `; rc=$?`; distinct unreadable-vs-empty
        messages; never print the value
  - [x] 2.3.2 `export HCLOUD_TOKEN` from Doppler **before** sourcing the stock gate
  - [x] 2.3.3 Birth gate **before** stock preflight
  - [x] 2.3.4 No `-var="image_name=…"`
- [x] 2.4 Plan step: `set +e; set -uo pipefail`, capture `rc=$?` on the very next line, `set -e`
      before `terraform show`
- [x] 2.5 Apply-failure message per plan §Phase 2.5 (re-dispatch safe; the one replace-not-complete
      exception; do not assert both halves at once)
- [x] 2.6 IaC edits
  - [x] 2.6.1 New `resource "doppler_config" "git_data_prd"`; re-point
        `doppler_secret.git_data_luks_key` + `doppler_service_token.git_data` at it
  - [x] 2.6.2 Retire the obsolete OPERATOR NOTE in `git-data-luks.tf`
  - [x] 2.6.3 `depends_on = [hcloud_server.git_data]` on the three SSH `doppler_secret`s
  - [x] 2.6.4 `depends_on = [doppler_secret.git_data_luks_key]` on `hcloud_server.git_data` (P13)
  - [x] 2.6.5 `terraform validate` — confirm no cycle

## Phase 3: Registries + parity

- [x] 3.1 `plugins/soleur/test/terraform-target-parity.test.ts`
  - [x] 3.1.1 Add `"git_data_host_create"` to `stripDispatchJobs`
  - [x] 3.1.2 Add `GIT_DATA_BIRTH_TARGET_BASES` (18 addresses)
  - [x] 3.1.3 Add `"doppler_config.git_data_prd"` to `OPERATOR_APPLIED_EXCLUSIONS` — and **never** a
        per-PR `-target` line
  - [x] 3.1.4 New `describe` block: `source` via `^\s*source\s+` command anchor; borrows no sibling
        gate; environment asserted; `def allow:` == `-target` == const
  - [x] 3.1.5 Omit the keyed-interpolation and pinned-digest tests (no analogue — drop, don't fake)
  - [x] 3.1.6 **Trap:** the `stripDispatchJobs` self-pinning guard extracts EVERY `"[a-z0-9_]+"`
        string literal in that function body and asserts each names a real `^  <id>:` job. Add
        `"git_data_host_create"` and a justification comment — but no other string literal
  - [x] 3.1.7 Use the unparameterized extractor `/def allow:\s*\[([^\]]+)\]/` (this gate is a
        singleton, so the web gate's `def allow\(\$k\):` form does not apply)
- [x] 3.6 Refresh the stale `MIN_APPLY_TARGET_OPTIONS` sentinel comment in
      `stock-preflight-coverage.test.ts` — it enumerates 10 options and predates
      `web-host-create`/`web-host-replace`. Floors are `>=` so nothing breaks; update the inventory
      while adding the new option rather than letting it rot a third time
- [x] 3.7 Do NOT add a `stock-preflight` `EXCLUSION_ALLOWLIST` entry — this target stays **gated**
      → VERIFIED: `stock-preflight-coverage.test.ts` is 9/0 with the new option present, and its
      "every apply_target option resolves to exactly one job" arm would have failed had
      `git-data-host-create` not resolved. No allowlist entry added.
- [x] 3.2 Add the enum ⇄ `description` parity assertion
- [x] 3.3 `export TMPDIR="${TMPDIR:-/var/tmp}"` at the top of `scripts/test-all.sh`
- [x] 3.4 Add the replace-gate regression arm for P13's new upstream `no-op`
- [x] 3.5 Run `stock-preflight-coverage.test.ts` — confirm auto-enrolment as *gated*, not allowlisted

## Phase 4: Runbook, ADR, C4

- [x] 4.1 Create `knowledge-base/engineering/operations/runbooks/git-data-birth.md`
  - [x] 4.1.1 DO-NOT-DISPATCH banner naming #6982 + the interlock
  - [x] 4.1.2 Dispatch invocation + confirm token
  - [x] 4.1.3 Post-birth `ci-deploy` remediation; **zero** occurrences of `soleur-web.service`
  - [x] 4.1.4 "What you now have, and what it is not": empty store · `GIT_DATA_STORE_ENABLED` still
        absent · no monitor · plaintext-backed until the cutover → pointer to
        `git-data-luks-cutover-5274.md`
  - [x] 4.1.5 Partial-birth decision tree
  - [x] 4.1.6 Non-SSH verification only; note that the environment approver approves *before* any
        step runs
- [x] 4.2 Write ADR-149 (provisional ordinal) + amend ADR-145 `## Consequences`
  - [x] 4.2.1 Three ADR-145 deltas; the interlock + its release checklist
  - [x] 4.2.2 Residuals: ADR-115 guest-convergence gap; empty-store Art. 17 window
- [x] 4.3 C4
  - [x] 4.3.1 Correct `gitDataStore` description (never-born + birth route)
  - [x] 4.3.2 Correct `betterstack -> founder` ("unfed" is falsified by P8)
  - [x] 4.3.3 Re-read `hetzner -> gitDataStore` and `claude -> gitDataStore` for the same class
  - [x] 4.3.4 Run both C4 tests; regenerate `model.likec4.json`
- [x] 4.4 File the follow-on issue: retrofit the fail-closed preamble into the 5 gates lacking it

## Phase 5: Verification + ship

- [ ] 5.1 Full gate run (see plan §Test Strategy) — record baselines in the PR body, not the plan
- [ ] 5.2 Verify every AC1–AC16
- [ ] 5.3 `/review` — **route the vacuity question to an INDEPENDENT reviewer**: *"find the vacuity
      this mutation battery missed — do not re-run its mutations."* Do not self-certify
- [ ] 5.4 `/ship` — re-verify the ADR-149 ordinal; if it renumbers, sweep plan + tasks + ACs
- [ ] 5.5 Confirm `decision-challenges.md` (DC-1/DC-2/DC-3) is rendered into the PR body and filed
      as an `action-required` issue
- [ ] 5.6 `Ref #6977` — do **not** auto-close; the route ships, the birth does not

---

## Measured results (Phase 5.1)

| Gate | Result | Baseline |
|---|---|---|
| `git-data-luks.test.sh` | 39 / 0 | 39 / 0 — held |
| `test-stock-preflight-gate.sh` | 53 / 0 | 53 / 0 — held |
| `validate-infra-templates.sh` | 7 / 7 | 7 / 7 — held |
| `terraform test` | 3 / 0 | 3 / 0 — held |
| `terraform validate` | Success | no cycle from either `depends_on` |
| `test-git-data-host-birth-gate.sh` | **62 / 0** | new |
| `test-git-data-birth-readiness-gate.sh` | **19 / 0** | new |
| `test-plan-gate-preamble.sh` | **27 / 0** | new |
| `test-git-data-host-replace-gate.sh` | **18 / 0** | was 16 — +2 P13 regression arms |
| `terraform-target-parity.test.ts` | **93 / 0** | was 80 — +13 |
| `stock-preflight-coverage.test.ts` | 9 / 0 | held, new option auto-enrolled as GATED |
| `c4-code-syntax` + `c4-render` | 23 / 0 | held |
| `scripts/test-all.sh` | **222 / 222 suites** | all three new suites execute (AC12) |
| `run-registered-suites.sh` | **72 / 72** | the CI-registered infra runner — `test-all.sh` does NOT cover `apps/web-platform/infra/` and says so in its own epilogue, so this is the infra evidence |
| `shellcheck -x` (7 files) | 18 findings, ALL SC2016 (info) | single-quoted jq/sed expressions where shell expansion must NOT happen; `web-host-birth-gate.sh` carries the same. Used instead of semgrep: OSS semgrep's tree-sitter bash parser matches ~0 rules, so a clean semgrep on a bash-dominant diff is vacuous |
| `actionlint` | rc 0 | — |

## Corrections made during /work, each caught by a gate rather than by reading

1. **Three mutation contracts were misclassified** in the birth-gate battery. The destroy arm
   is sole-guard only on a REPLACE fixture (on a volume-destroy fixture the named arm shadows
   it); the firewall arm is layered behind presence for the UPDATE shape; the actions-shape
   check is layered behind the numeric floor — and only by accident of which jq builtin raises
   on null. All three were corrected by measurement, not by re-reading the code.
2. **A fourth was backwards.** An assertion that the generic destroy arm is layered behind the
   named volume arm was written with `own`/`fallback` inverted; the layered control's
   unmutated-gate precondition caught it. Deleted rather than "fixed" — the relationship is
   already asserted from the correct direction.
3. **Two parity ordering assertions anchored on bare tokens and FAILED correctly.**
   `indexOf("terraform plan")` matched the job's own header comment ("...not after a
   two-minute terraform plan") and reported the interlock as running AFTER the plan when it
   runs before it. Re-anchored on syntactic constructs.
4. **A workflow-injection sink**: the Dispatch summary interpolated `${{ inputs.reason }}`
   directly into a `run:` body. Routed through `env:` per the convention recorded at the top
   of that workflow.
5. **The shared concurrency group had to be added to BOTH jobs.** `git_data_host_replace`
   carried no job-level group, so declaring one only on the new job would have been a mutex of
   one — the exact "divergent group strings silently fail to serialize" trap that workflow's
   own header warns about.
