---
title: "feat: destroy the retired plaintext git-data volume through Terraform (Option B)"
date: 2026-10-26
slug: git-data-plaintext-volume-terraform-destroy
branch: feat-one-shot-option-b-plaintext-volume-destroy
issue: 8211
type: feat
lane: cross-domain
requires_cpo_signoff: true
---

# feat: destroy the retired plaintext git-data volume through Terraform (Option B)

## Overview

The plaintext Hetzner volume `soleur-git-data-store` (id 106867358, attached to server 170370833) is the
retired pre-LUKS git-data store. The workflow wipe that was meant to end its retention cannot conclude
(two independent barriers, CTO ruling 2026-10-25). The CLO ruled 2026-10-26 that deleting the device at
the provider API through Terraform ends the retention just as well, and the CTO ruled 2026-10-26 that
this is feasible by 2026-11-05 if the HCL edit keeps the git-data host's rendered `user_data`
byte-identical.

This PR delivers code and records, not the destruction. It merges the HCL removal, a dedicated
`workflow_dispatch` destroy workflow, a pinned jq plan gate, tests, a runbook section and a DRAFT ADR-239
amendment. Nothing is destroyed until the owner merges and dispatches the workflow in their own session.

**Deliberate consequence (stated, not hidden).** Merging disables the git-data host rotate, replace and
create routes: their gates demand the retired plaintext addresses, which can no longer appear in any plan.
That is a disabled capability tracked by a filed issue, not "fails closed, fine". A rotate is required
before every flip dispatch, so **the merge must follow the flip retry and any rotate it needs**.

## Enhancement Summary

**Deepened on:** 2026-10-26 (proportionate pass; the full 40-agent deepen fan-out was NOT run, by the invocation's own constraint — the plan had already been through the CTO, CLO and CPO rulings, a six-seat plan-review panel and an architecture seat that measured `-target` behaviour on terraform 1.9.8).

**Gates run and passed:** 4.6 User-Brand Impact (threshold `single-user incident`), 4.7 Observability (five fields; probe verb `bash`; literal `expected_output`; `credentials_required` declared), 4.8 no PAT-shaped variable, 4.10 Encryption Posture, 4.11 Guard Contract (`lint-guard-contract.py`: 1 plan, 1 guard entry, rc 0), 4.12 Scope Check (one unfenced section, zero `unmapped`), 4.13 Task Design (one unfenced section). 4.9 and 4.45 do not apply (no UI surface; no negative security claim without a grep — the "no workflow runs an untargeted apply" claim was verified by the repo-research and architecture seats).

**Live citation checks:** SHA pins `34e114876b0b…` (checkout, 40 chars, 79 workflows) and `5e8dbf3c6d9d…` (setup-terraform, 40 chars, 12 workflows) resolve; rule ids `hr-all-infrastructure-provisioning-servers` and `wg-when-deferring-a-capability-create-a` exist; #8211, #6897 and #10112 are OPEN; `git-data.tf:386/538/552`, `git-data-cutover.yml:112-114` and the `git-data-state` job groups at `apply-web-platform-infra.yml:3743-3745` and `:5677` match the plan text.

**Not verified here (carried into Phase 0 / the ACs):** `-target` on 1.10.5; `action_reason` of the orphan delete; whether the PR-time `infra-validation.yml` plan comment is available for the byte-identical `user_data` evidence.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| "Precedent `workspaces-plaintext-forget.yml`" | Not in this tree: added `403487494d`, deleted `3ed3e4e6da`. A `terraform state rm`, not a plan grader; no `plan-gate-preamble`. | Use `git show 403487494d:.github/workflows/workspaces-plaintext-forget.yml` for conventions only (input validation, credential and backend extraction, Hetzner helpers, presence proof, cleanup). The gate is new. |
| "Concurrency group `git-data-state`" | A workflow may hold one group at workflow level and another at job level (`apply-web-platform-infra.yml:3743-3745`, `:5677`; `git-data-cutover.yml:112` and `:134-137`). The R2 backend has no state lock (`main.tf:19` `use_lockfile = false`); `terraform-apply-web-platform-host` is its serializer (`:237-251`). | **Ruled by CTO agent 2026-10-26:** workflow-level `terraform-apply-web-platform-host` + job-level `git-data-state`. The runtime cutover-polling assertion is dropped (a real mutex has no check-then-act race). |
| "Environment probably `web-platform-infra-apply`" | Verified read-only: 1 required reviewer, `prevent_self_review=false`, no wait timer; `infra-privileged` has 0 reviewers. | `environment: web-platform-infra-apply`. The ADR states honestly that the owner can approve their own run; the typed pins and the gate are the controls outside that approval. |
| "git-data.tf is outside the rung-2 hash set" | True: the hash covers `modules/git-data-userdata/*.tf`, the template and `file()` payloads (`git-data-birth-readiness-gate.sh:364-368`, `:238-240`). `git_data_volume_id` is already in the divergence allowlist. | All edits stay in root `git-data.tf`; the module directory is byte-unchanged. |
| "Byte-identical user_data" | Rendering old vs new expression proves nothing (both are `"106867358"`). Real risks: state id differs from the literal, or the server already has diff. Consumers of the id: `modules/git-data-userdata/main.tf:131`, `cloud-init-git-data.yml:1139` (LUKS != plaintext guard) and `:1340`, the budget stub seam, rehearsal root (own volume). | Evidence = Hetzner id equals the literal (read 2026-10-26) + the PR-time `infra-validation.yml` plan (`-refresh=false`, config vs state) shows `hcloud_server.git_data` with no change. |
| "No state surgery" | True for the destroy. Until dispatch, state holds both addresses: untargeted plans (`scheduled-terraform-drift.yml:162/170`, PR-time validation) show the two destroys and the drift workflow files an `infra-drift` issue and email. No workflow runs an untargeted apply. | Runbook/ADR/PR body record the expected drift issue; the dispatch closes it. A local untargeted apply in that window would delete the volume without pins or gate — said in the runbook. |
| "`-target` on an absent address" | Measured by the architecture seat on 1.9.8: an absent address exits 0 ("no differences"); `-target` on an orphan pulls in its dependencies, not its dependents. Workflows pin 1.10.5. | Phase 0 repeats it and records `action_reason`; if 1.10.5 is unobtainable the AC says "unverified on 1.10.5". The replace/birth `-target` lines stay (parity test pins them equal to the gates). |
| "Wedge-test classification" | After removal the new workflow's `-target` addresses are not in the root HCL graph; the deriver skips them (`if base not in G: continue`), so it is an unreachable apply-capable non-reader, not "delete-only". | Update `WEDGE_ADDRS`, the F1/F2 live-check expectations and the stale suite header; run the suite and fix only what it asserts. |

## Review Reconciliation — 2026-10-26 (PR #11179 review round 1)

The text below this section is the plan as written before implementation and the 12-seat review. Where it disagrees with this section, THIS section and the code win. Rulings recorded in `decision-challenges.md` (CTO and CLO, 2026-10-26).

- The `hcloud_volume.git_data` ledger row is **kept** (not removed): it keeps the lint-enforced `expires_on: 2026-11-12`, and the record PR (#11195) retires it. `OPERATOR_APPLIED_EXCLUSIONS` entries for the two addresses are **kept** (the replace and birth parity tests still require them).
- The structural test is folded into the parity suite and the gate test; there is no standalone structural test file.
- The census gets `DISPATCH_GATED_DESTROYS` (CTO fork, option B of its fork): a narrow allowance, now also requiring an exact `-target` set, an apply of the planned file, a gate call before the apply, no continue-on-error or status-function override, and a tier-B environment (rows g4-15..g4-29).
- Only the **volume** id 106867358 and name are hard pins. The git-data server and its LUKS volume are resolved by name from the live read, and the live server id is passed to the gate as a third argument (CTO, Fork A). A rotate therefore needs no re-pin.
- The gate runs after the plan and again inside the step that applies the saved plan; the workflow refuses to run off `main` (`verdict=not_main`); the read-back requires `shape=gone` and an unchanged server and LUKS id (CTO, Fork D).
- The 2026-10-15 wipe preconditions are superseded for this end event (CTO, Fork B; ADR-239 Amendment 2026-10-26 item 8).
- The owner order is: flip retry; a rotate only if the flip refuses `d6_replace_stale` and no run has executed the flag-write step (the statement that a rotate is required before every flip is stale); then merge; then dispatch within about 24 hours of the merge (CTO, Fork C).
- "Extension to 2026-12-11" is a candidate input to a CLO re-ruling, not an authorized date; a recorded re-ruling is a precondition of any change to `expires_on`. The DPD §10.3(b) edit waits for the verified read-back (record PR by the earlier of 7 days after the read-back and 2026-11-11), with a 2026-11-09 checkpoint on #6897 (CLO, forks L1-L4).
- The acceptance command for "no forbidden files touched" is the three-dot form, `git diff --name-only origin/main...HEAD`.
- The failure-mode list in `## Observability` is replaced by the layer-cited one below; there is no standing notifier for this workflow.

## Research Insights

**Premise Validation (Phase 0.6).** #8211 and #6897 are OPEN umbrella issues. No open PR touches `git-data.tf`, the ledger or the new workflow (`pr-overlap-preflight.sh --mode start`: `prs=none`). Cited paths exist (verified by the repo-research and Kieran seats). ADR-239 Amendments 2026-10-09 and 2026-10-15 define the wipe as the end event; this plan appends an amendment declaring a Terraform destroy an accepted equivalent, which the CLO (2026-10-26) said is required and attestable.

**Property List.**
1. Exactly the plaintext volume (and its attachment) can be destroyed; the LUKS volume 107140231, the server and the passphrase pair never.
2. Merging the PR changes no production resource.
3. The destroy needs a reviewer-approved dispatch with two matching typed pins, and a typo must not burn an approval.
4. The destroy never runs concurrently with another `terraform` run on this state or with any `git-data-state` holder (cutover, rung-2, root key).
5. The end event is proven (404 by id, empty list by name) and claimed no wider than "device deleted at the provider API".
6. A partial apply is re-dispatchable and its state is observable even when the apply fails.

**Cut List.** (mechanism → property → covered by)
- `terraform state rm` forget path → 1 → plain HCL removal plans the destroy (CTO).
- PR-C empty-id host-replace design → n/a → changes `user_data` and replaces the live host (CTO: do NOT use).
- A job in `apply-web-platform-infra.yml` → 3 → file is 489,696/490,000 bytes; dedicated file.
- Editing `git-data-host-replace-gate.sh` / `git-data-host-birth-gate.sh` / their constants / the replace-birth `-target` lines → none → brief rule 4; tracked follow-up issue.
- Cutover `gh run list` polling assertion → 4 → job-level `git-data-state` group (real mutex).
- Standalone structural workflow test file and its three registry rows → 3,4 → pins asserted in `terraform-target-parity.test.ts` (already edited) and the gate test (CTO, DHH and simplicity seats).
- `[ack-destroy]` bypass mutation row → none → no gate reads it; replaced by a "never referenced" grep.
- "Both gone → no-op success through the gate" path → 6 → workflow short-circuit before plan.
- Pre-plan LUKS presence check → 1 → gate requires zero LUKS actions; post-apply check kept.
- Reading the plaintext volume's contents → 5 → CLO: unnecessary processing.
- Post-destroy records (Art. 30 marker, `expenses.md`, DPD §10.3(b) refresh, deleting the one-shot workflow) → none here → follow-up record PR (issue filed).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "delete hcloud_volume.git_data (~line 538) and hcloud_volume_attachment.git_data (~line 552); change `git_data_volume_id = hcloud_volume.git_data.id` (~line 386) to the string literal \"106867358\"" [brief] | Phase 2, `git-data.tf` | mapped |
| 2 | "New dedicated workflow file ... workflow_dispatch only, inputs `expected_volume_id` and a `confirm` token, `-target` on exactly the two orphaned addresses" [brief] | Phase 2, new workflow | mapped |
| 3 | "New jq plan gate ... Pass ONLY if: exactly two resource_changes with non-no-op action, both exactly [\"delete\"]" [brief] | Phase 1, gate lib + test | mapped |
| 4 | "Do NOT weaken git-data-host-replace-gate.sh or git-data-host-birth-gate.sh" [brief] | Phase 3 | mapped |
| 5 | "Keep suites green: terraform-target-parity.test.ts, test-git-data-wipe-wedge.sh ..." [brief] | Phase 3 | mapped |
| 6 | "Docs: runbook note ... and a DRAFT ADR-239 amendment" [brief] | Phase 4 | mapped |
| 7 | "Tests for the new gate (positive, and negative cases ...)" [brief] | Phase 1 | mapped |
| 8 | "End the PR body with an 'Owner actions' section" [brief] | Phase 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|---|---|---|
| `git-data.tf` edit | asks 1 | asked |
| `.github/workflows/git-data-plaintext-volume-destroy.yml` | asks 2 | asked |
| `tests/scripts/lib/git-data-plaintext-destroy-gate.sh` + `tests/scripts/test-git-data-plaintext-destroy-gate.sh` | asks 3, 7 | asked |
| `apps/web-platform/infra/git-data-plaintext-volume-state.sh` (read-only probe) | — | inferred — justification: the pre-plan read, the post-apply read-back and the `## Observability` discoverability command are the same three-line read; one script avoids three copies |
| `terraform-target-parity.test.ts` edits (exclusions, `MAIN_ROOT_TF_WORKFLOWS`, pins describe block) | asks 5 | asked |
| `test-git-data-wipe-wedge.sh` edit | asks 5 | asked |
| `scripts/encryption-posture-ledger.json` row removal + rehearsal-row prose | asks 5 | asked |
| runbook section + ADR-239 DRAFT amendment | asks 6 | asked |
| `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv` rows for the one new test | — | inferred — justification: `lint-orphan-test-suites` fails on an unregistered new test |
| follow-up GitHub issues (gate retirement + `id=""` rebirth sequencing; post-destroy record PR + workflow deletion) | — | inferred — justification: `wg-when-deferring-a-capability-create-a`; the disabled host-replace path and the dangling literal need an owner and a date |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform/infra`, `.github/workflows`, `tests/scripts`, `knowledge-base` (+ `plugins/soleur/test`, `scripts` registries)
- Planned files: ~16 | Estimated changed lines: ~650 (gate + tests dominate)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the HCL removal, the workflow and the gate are not independently safe (HCL alone leaves drift plans red; the workflow alone has nothing to destroy; the gate/workflow pair needs the addresses absent from config to grade as pure deletes). Four subsystem roots is justified by one coherent change.

## Open Code-Review Overlap

- #10112 (`scripts/encryption-posture-ledger.json`): **Acknowledge.** Its residuals are different concerns; this PR edits only the `hcloud_volume.git_data` row and the rehearsal row's prose that refers to it. The scope-out stays open.

## Implementation Phases

### Phase 0 — Offline experiment and read-only confirmations (no repo change)

- Scratch dir under the session scratchpad: a `terraform_data` config, resource B removed from config but kept in state. Record for `-target=B` (orphan) and `-target=GONE` (absent from config and state): exit code, warning text, `resource_changes` shape, `action_reason` of the orphan delete, whether `resource_changes` is omitted on an empty plan. Terraform 1.9.8 is installed; try the pinned 1.10.5 if the network allows and state which version proved what.
- Re-read the live volume read-only (`GET /v1/volumes/106867358`): id, name, server 170370833, LUKS volume 107140231 on the same server. Stop and re-plan if anything differs.
- Run the baseline suites named in Phase 3 on the unmodified tree.
- Verify by grep that `git-data-cutover.yml` and the `rollback` mode never reference the plaintext volume (AC).

### Phase 1 — Guard first: the gate and its test (TDD)

Write `tests/scripts/test-git-data-plaintext-destroy-gate.sh` and `tests/scripts/lib/git-data-plaintext-destroy-gate.sh` before the workflow. `git_data_plaintext_destroy_gate <plan.json> <expected_volume_id>`: parameter named `local plan_json`; sources `plan-gate-preamble.sh` and CALLS `plan_gate_assert_readable`/`_classifiable`/`_numeric` (anchored call); one `jq -n` computes every counter, wrapped in `if ! counts=$(jq ...)`, then `plan_gate_assert_numeric` on each. Rules:
- Compare `.change.actions == ["delete"]` exactly (never `index`/`any`); ignore only entries whose actions are exactly `["no-op"]` or exactly `["read"]` (the targeted closure pulls the server, module and data sources in as `no-op`/`read`); anything else non-ignorable is out of scope.
- Exactly one entry per pinned address, `.mode == "managed"`, exact `.address` (no prefix match); no `deposed` entries.
- Types: `hcloud_volume.before.id` is a string, attachment `volume_id`/`server_id` are numbers — `tostring` both sides, constants are strings; pin the attachment `server_id` to 170370833 as well as `volume_id`.
- Required: the volume delete. An attachment-only delete with the volume present is RED; the attachment alone being absent (already gone) is GREEN.
- Optional hardening after Phase 0: assert `action_reason == "delete_because_no_resource_config"`.

### Phase 2 — HCL removal and the destroy workflow

- `apps/web-platform/infra/git-data.tf`: delete the two resources; `git_data_volume_id = "106867358"` with a comment and a `SOLEUR-DEBT:` marker — literal is the dangling id after destroy; remove it only with a deliberate host replace that sets `""`, sequenced behind the gate-retirement issue; refresh the stale comment at `:23` and mentions in `git-data-luks.tf`. Check that `var.git_data_volume_size` (`variables.tf:223`) is now unused and that validation/lint steps tolerate it. `modules/git-data-userdata/*` untouched.
- `.github/workflows/git-data-plaintext-volume-destroy.yml` (new, `workflow_dispatch` only; precedents: the deleted forget workflow, the replace job's plan step at `apply-web-platform-infra.yml:~356-363` and its `set +e` rc-capture bracket):
  - Top-level `env.TF_VAR_terraform_version` equal to `TERRAFORM_VERSION` (1.10.5); `permissions: contents: read`; SHA-pinned actions (`actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5`, `hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85`); workflow-level `concurrency: terraform-apply-web-platform-host, cancel-in-progress: false`.
  - Job `validate` (no environment, no job-level group): inputs passed through `env:` and compared as literals before any secret is read — `expected_volume_id == 106867358`, `confirm == DESTROY-PLAINTEXT-GIT-DATA-VOLUME`; refuses under `set -x`. A typo fails here and never consumes a reviewer approval.
  - Job `destroy` (`needs: validate`, `environment: web-platform-infra-apply`, job-level `concurrency: git-data-state, cancel-in-progress: false`, `timeout-minutes`): tiered credential loader; R2 creds with `::add-mask::`; `terraform init -lockfile=readonly`; ephemeral SSH public key step and `doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- terraform …` with `-var=ssh_key_path=…` (the root has 17 required variables; `file()` is evaluated at plan time). Hetzner helpers send the token on stdin, treat 404 as an answer (never `curl -f`), retry 429/5xx in the read-back, and fail closed on any `gh`/API error.
  - Steps: pre-plan read via `git-data-plaintext-volume-state.sh` (volume id/name/server; name list; server 170370833 returns 200 and holds LUKS volume 107140231 — a presence proof, since a 404 from another project proves nothing) → **already-gone short-circuit**: volume 404 and name list empty → skip plan/gate/apply, run the read proof, summarise "already destroyed (original run id if known)" → refuse with named verdicts on unexpected shapes (name exists under a different id; attachment exists at Hetzner but not in state; volume attached to another server) → `terraform plan -target=hcloud_volume_attachment.git_data -target=hcloud_volume.git_data -out=tfplan` → `terraform show -json tfplan` to a runner file read only by the gate → gate (`if ! …` at the call site) → `terraform apply tfplan` → read-back as a `success() || failure()` step reporting actual state (`attachment_gone`, `volume_present|absent`, 404 by id, empty name list, LUKS volume still present on the server) → cleanup step (`if: always()`) removing `tfplan` and `tfplan.json`; no upload of plan files, no human-readable `terraform show` to the log.
  - Step summary fields: run id, verdict, pre and post state, plan counts, LUKS present and attached, UTC timestamp — counts and identifiers only. The record PR pastes the summary (default run retention is shorter than an attestation needs).
  - Reviewer rejection leaves no change; re-dispatch is the recovery.

### Phase 3 — Keep the existing guards green (change only what turns red)

- `plugins/soleur/test/terraform-target-parity.test.ts`: remove the two `OPERATOR_APPLIED_EXCLUSIONS` entries (`:1284-85`) because the exclusion set is checked against declared resources; add the new workflow to `MAIN_ROOT_TF_WORKFLOWS` (`:2320`) and bump `expect(found.length).toBe(3)` to 4 (`:2430-2452`); add a pins describe block asserting: `workflow_dispatch` only, `environment: web-platform-infra-apply`, both concurrency groups, the two inputs and literals, exactly the two `-target`s, `env.TF_VAR_terraform_version`, the gate call site `if !` form, and that neither the workflow nor the gate references `ack-destroy`. **Leave** `GIT_DATA_REPLACE_TARGETS`, `GIT_DATA_BIRTH_TARGET_BASES` and `GIT_DATA_PRESERVED_VOLUMES` unchanged — the parity test pins the replace/birth jobs' `-target` lines, the gates' allow-sets and those constants equal, and the gates stay untouched.
- `tests/scripts/test-git-data-wipe-wedge.sh`: update `WEDGE_ADDRS` (`:66`), fixture F1/F2 live-check expectations and the stale header; run and fix only what it asserts.
- `scripts/encryption-posture-ledger.json`: remove the `hcloud_volume.git_data` row (the lint resolves HCL; a row for a removed resource fails) and fix the rehearsal row prose (`reevaluate_when: hcloud_volume.git_data becomes the LUKS volume`). The exception and the 2026-11-12 bound move to the ADR amendment and #6897 with dated entries and a milestone.
- Run and fix only what the removal turns red: `git-data-rung2-rehearsal.test.sh`, `test-infra-privileged-tier-census.sh` Guard 1 (and the G1i extract form), `workflow-file-size.test.ts`, `c4-count-parity.test.sh`, `lint-encryption-posture.test.sh`, `test-plan-gate-preamble.sh`, `test-git-data-host-replace-gate.sh`, `test-git-data-host-birth-gate.sh` (their fixtures keep the retired addresses and stay green — they give no signal that the live route is disabled; that is what the filed issue is for).
- Register the one new test in `scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv` using the `tests/scripts/<name minus test- prefix>` label form.

### Phase 4 — Records (draft; nothing attested)

- Runbook `git-data-luks-cutover-5274.md`: new section "Plaintext-volume destroy (Option B)" next to "The wipe": dispatch command and inputs; **order: flip retry (and any rotate) → merge → dispatch**, a flip started during the destroy is unsupported; dispatch only when the reviewer can approve immediately (the workflow-level group is held through approval and GitHub keeps one pending run per group); cancel a stale `waiting` cutover run; expected plan counts; the drift-issue window and the "never run an untargeted apply" warning; recovery by re-dispatch; reviewer rejection and who notes #6897; rollback after the destroy cannot use the plaintext volume. Short; the claim limits live in the ADR and the section links there.
- ADR-239: append `## Amendment 2026-10-26 — Terraform destroy is an accepted equivalent end event (#8211)`, marked `PENDING CLO ATTESTATION`; the claim-limits paragraph once ("device deleted at the provider API" only; no claim about emptiness, "no personal data", provider snapshots or copies, lock residue, `.gc-cursor`, or copies held by anyone with prior access); fires on the owner's successful dispatch; states that the git-data host rotate/replace/create routes are disabled until the gates are retired and that `id = ""` can only be reached by a deliberate host replace; states `prevent_self_review=false`. The emptiness claim the CLO barred appears nowhere.
- File two issues (milestone + re-evaluation date): (1) retire the plaintext arms of the replace/birth gates, `git_data_host_post_apply_assert` and the three jobs' `-target` lines, then replace the host with `id = ""`; (2) post-destroy record PR — Art. 30 marker, `expenses.md` flip, DPD §10.3(b) refresh, deleting the one-shot workflow + gate + tests + parity/registry entries. #6897 carries the 2026-11-02 and 2026-11-12 dates.
- No edit to `docs/legal/**`, its mirror, `legal-doc-shas.ts`, `article-30-register.md` or `expenses.md`.

### Phase 5 — Review, PR body, stop

Full relevant suites, `soleur:review`, `soleur:qa` (no UI scenarios; skips), compound, then `soleur:ship` configured to STOP at a READY PR with green CI (no auto-merge armed, no merge). PR body: `Ref #8211`, `Ref #6897`, the disabled-capability statement, the expected drift issue, and an `## Owner actions` section naming — not running — flip retry first (and any rotate), then merge, then the dispatch (`gh workflow run git-data-plaintext-volume-destroy.yml -f expected_volume_id=106867358 -f confirm=DESTROY-PLAINTEXT-GIT-DATA-VOLUME`), the environment approval, CLO attestation of the ADR amendment, and the recorded bound on #6897 (re-ruling by 2026-11-02 if not merged).

## Files to Create

- `.github/workflows/git-data-plaintext-volume-destroy.yml`
- `tests/scripts/lib/git-data-plaintext-destroy-gate.sh`
- `tests/scripts/test-git-data-plaintext-destroy-gate.sh`
- `apps/web-platform/infra/git-data-plaintext-volume-state.sh`

## Files to Edit

- `apps/web-platform/infra/git-data.tf`
- `apps/web-platform/infra/git-data-luks.tf` (comments that now assert a false fact)
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `tests/scripts/test-git-data-wipe-wedge.sh`
- `scripts/encryption-posture-ledger.json`
- `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`
- `knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` (only if `c4-count-parity` or a description now false requires it)

`.github/workflows/apply-web-platform-infra.yml` and the replace/birth gate libraries are NOT edited.

## User-Brand Impact

**If this lands broken, the user experiences:** a git-data host replaced or rebooted by a changed `user_data`, or the LUKS store detached — workspaces that cannot read or push repository state; or, after the merge, a host-recovery path that is disabled when an incident needs it. Merging alone changes no resource; the exposure is the dispatched destroy with a wrong target, and the disabled replace route.

**If this leaks, the user's data is exposed via:** nothing new; the PR reads and logs only counts and identifiers and never uploads plan JSON. The volume is a retained plaintext device that may hold id-bearing lock residue (CLO ruling); deleting it removes that exposure.

**Brand-survival threshold:** single-user incident

The threshold is `single-user incident` because a mis-scoped destroy of the LUKS volume, an unplanned host replace, or a disabled recovery route is an availability-and-data-loss class risk on the git-data store. The CTO and CLO rulings of 2026-10-26 are the recorded technical and legal sign-offs; CPO sign-off is requested at plan time (Phase 2.6) before `soleur:work`; `soleur:engineering:review:user-impact-reviewer` runs at review; the owner's merge and dispatch are the authorization.

## Domain Review

**Domains relevant:** Engineering (CTO ruled), Legal (CLO ruled), Operations

### Engineering
**Status:** reviewed
**Assessment:** CTO 2026-10-26: Option B feasible by 2026-11-05 with a literal id (byte-identical `user_data`), a dedicated workflow with its own gate, id pinned twice, replace/birth gates untouched. Plan review (CTO devex lens) added: workflow-level `terraform-apply-web-platform-host` + job-level `git-data-state`; merge only after the flip retry; follow-up issues for gate retirement and the dangling literal; fold the structural test into the parity suite.

### Legal
**Status:** reviewed
**Assessment:** CLO 2026-10-26 (v1 internal attestation, not external counsel): Option B recommended; the device limb is satisfied by a provider-API delete; requires a dated ADR-239 amendment; the emptiness claim ("the volume held nothing") is not attestable and must not appear; no `docs/legal/**` edit required; post-destroy DPD §10.3(b) refresh recommended, not required.

### Product (CPO plan-time sign-off, `requires_cpo_signoff`)
**Status:** reviewed — SIGN-OFF WITH CONDITIONS (2026-10-26)
**Assessment:** No user-visible promise is created; merge alone changes nothing; the only product-side exposure is the disabled host-recovery window between merge and gate retirement. Conditions, all carried into Phase 4/5 and the ACs: (1) both follow-up issues filed before READY, each with milestone, calendar date and owner — the gate-retirement issue names a target date (about one week after the destroy); (2) Owner actions state the order flip retry → any rotate → merge → dispatch, and that no host rotate/replace/create may start after the merge until gate retirement lands (an emergency rebirth in that window stops and escalates to the owner); (3) if not merged by 2026-11-02, the CLO re-ruling and the DPD edit are dated items on #6897; (4) no public copy beyond the ADR claim limits; (5) keep merge-to-dispatch within about 24 hours or hold the merge. Owner decisions (not technical): tolerance of the recovery window; whether the post-destroy DPD refresh needs a user-facing notice (recommend no proactive announcement); avoid dispatching during a cohort onboarding call or demo; accept self-approval (`prevent_self_review=false`) consciously; the `expenses.md` flip has an owner.

### Operations
**Status:** reviewed
**Assessment:** A provider-resident device deletion through Terraform satisfies `hr-all-infrastructure-provisioning-servers`; the `expenses.md` flip is a post-destroy record edit.

No Product/UX surface (no UI file in the Files lists).

## Infrastructure (IaC)

### Terraform changes
Root `apps/web-platform/infra`: remove `hcloud_volume.git_data` and `hcloud_volume_attachment.git_data`; module input `git_data_volume_id` becomes the literal `"106867358"`. No provider/version change. No new sensitive variable; the workflow reuses the sibling `doppler run … tf-var` plumbing and the tiered credential loader.

### Apply path
Not cloud-init-only and not `-replace`. A dedicated reviewer-gated dispatch destroys the attachment (live detach, no reboot — first in-repo hot-detach, unmeasured, low risk) then the volume. Expected downtime: none; the volume is never mounted writable (ADR-239 D2). `user_data` unchanged, so `hcloud_server.git_data` plans no change.

### Host fan-out
No `terraform_data` SSH provisioner is added or changed; not applicable.

### Distinctness / drift safeguards
The gate pins volume id/name and the attachment's volume and server ids as constants; LUKS volume 107140231, the server and the passphrase pair may show only `no-op`/`read`. Drift plans show the two destroys between merge and dispatch (documented; the dispatch resolves them). State lives in R2; plan JSON is never uploaded.

### Vendor-tier reality check
No Hetzner tier gate affects delete. Protection is off on both volumes (`protection.delete=false`, read 2026-10-26), so the id pins and the live read are the only guards.

## Architecture Decision (ADR/C4)

### ADR
Amend ADR-239: `Amendment 2026-10-26 — Terraform destroy is an accepted equivalent end event`. DRAFT, PENDING CLO ATTESTATION, fires on the owner's successful dispatch. It also records the disabled host rotate/replace/create routes and the sequencing to `id = ""`. Not a deferred follow-up; the gate-retirement work is a separate PR with its own issue.

### C4 views
Read all three model files before concluding (`model.c4`, `views.c4`, `spec.c4`). Enumerated for this change: external human actors — none added; external systems — Hetzner API (already modeled), GitHub Actions (already modeled); data stores — the plaintext volume appears in descriptions only (update any description that says it still exists); actor↔surface access — unchanged. Run `plugins/soleur/test/c4-count-parity.test.sh`: a new workflow may move a stated workflow count; fix only if it fails.

### Sequencing
The ADR describes the target state now. The destroy happens at the owner's dispatch.

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.git_data (removed)
    mechanism: plaintext-exception (retired; being destroyed)
    evidence: scripts/encryption-posture-ledger.json row removed in this PR; the device is deleted by the dispatched workflow (404 read-back by id and name)
    defends_against: nothing at the volume layer (unchanged); the destroy removes the device
    does_not_defend: provider snapshots/copies, lock-file residue and .gc-cursor are unmeasured and unclaimed; copies held by anyone with prior access
    disclosed_as: not-publicly-claimed (DPD section 10.3(b) stays date-anchored and true)
    live_verification: Hetzner API read 2026-10-26 (id 106867358, server 170370833); the workflow re-reads before and after
in_transit:
  - connection: runner to Hetzner API and R2 backend
    tls: https
    cert_verification: on
    does_not_defend: a compromised runner token; the environment reviewer and branch policy bound it
    disclosed_as: not-publicly-claimed
exception:
  justification: the retained volume stays until the owner dispatches the destroy; the exception continues from the removed ledger row into the ADR-239 amendment and #6897
  tracking_issue: "#6897"
  reevaluate_when: dispatch done, or 2026-11-02 if the PR is not merged (CLO single bounded extension to 2026-12-11)
  expires_on: 2026-11-12
```

## Observability

Every signal of this one-shot, dispatcher-attended workflow is **layer 6 analogue: the workflow run log** (`::error::` annotations, the step summary, exit codes). There is no Inngest function, pino logger or Vector sink in this change, and none is needed. There is also no standing notifier: `git-data-cutover.yml`'s `notify-failure` job does not cover this workflow, so a failed or cancelled run reaches the dispatcher through GitHub's default failed-run email only (the record PR, #11195, is where the outcome is written down).

```yaml
liveness_signal:
  what: the plaintext volume's presence or absence at the provider API
  cadence: on demand (single-use destroy; no recurring signal needed)
  alert_target: workflow run log annotations (::error::) and GitHub's default failed-run email to the dispatcher; no standing notifier, no new alert
  configured_in: apps/web-platform/infra/git-data-plaintext-volume-state.sh
error_reporting:
  destination: GitHub Actions run summary and workflow run log annotations (::error:: with verdict=<name>)
  fail_loud: every refusal exits non-zero with a named verdict; the read-back step runs on success and failure and fails the job unless the shape is gone (404 by id AND an empty name list), the LUKS volume is present on the same git-data server, and the server and LUKS ids are unchanged since the pre-plan read
failure_modes:
  - mode: dispatched from a ref other than main
    detection: workflow run log, ::error:: verdict=not_main in validate
    alert_route: failed run annotation (the destroy job is skipped)
  - mode: input mismatch or wrong typed token
    detection: workflow run log, ::error:: verdict=input_mismatch in validate (before any approval)
    alert_route: failed run annotation
  - mode: pre-plan probe cannot complete (exit 3 no credential, 4 API or parse error, 5 presence proof failed)
    detection: workflow run log, ::error:: verdict=pre_plan_read_failed (exit N) plus the probe's error= line
    alert_route: failed run annotation, nothing planned
  - mode: unexpected Hetzner shape (name under another id, attached elsewhere, identity mismatch) or LUKS volume missing from the git-data server
    detection: workflow run log, ::error:: verdict=<shape> or verdict=luks_volume_missing in the pre-plan read
    alert_route: failed run annotation, nothing planned
  - mode: terraform plan fails
    detection: workflow run log, ::error:: terraform plan failed (exit N)
    alert_route: failed run annotation, nothing applied
  - mode: plan contains anything beyond the pinned deletes (including a host replace after a user_data change)
    detection: workflow run log, git_data_plaintext_destroy_gate REFUSE verdict=<counter name> with the list of non-no-op addresses; the apply step re-runs the gate
    alert_route: failed run annotation, no apply executed
  - mode: apply fails, or fails after the attachment was destroyed
    detection: workflow run log, ::error:: terraform apply failed, then the read-back step (runs on failure) reports verdict=volume_still_present_after_failed_apply or apply_failed_volume_gone
    alert_route: failed run annotation; re-dispatch is the recovery unless the verdict says the device is gone
  - mode: read-back finds the volume still present, a non-empty name lookup, a missing LUKS volume or a changed server id
    detection: workflow run log, ::error:: verdict=volume_still_present | luks_volume_missing | server_id_drift
    alert_route: failed run annotation; stop and escalate to the owner
  - mode: already gone (re-dispatch after success)
    detection: workflow run log, pre-plan read prints the already-gone line and the read-back re-proves the end event
    alert_route: green run, step summary records the proof
  - mode: approval rejected or timed out, or the run is cancelled
    detection: GitHub run status only (no workflow verdict; nothing has changed at that point)
    alert_route: none beyond the run page; re-dispatch when the reviewer can approve
logs:
  where: GitHub Actions run logs and step summary (counts and identifiers only; plan files removed)
  retention: GitHub default run retention (the record PR pastes the summary)
discoverability_test:
  command: bash apps/web-platform/infra/git-data-plaintext-volume-state.sh
  expected_output: plaintext_volume=present or plaintext_volume=absent (plaintext_volume=unknown with exit 3, 4 or 5 when it cannot determine)
  credentials_required: HCLOUD_TOKEN_READONLY from Doppler prd_terraform - the provider API has no unauthenticated read of volume state
```


## Guard Contract

### Guard 1 — git_data_plaintext_destroy_gate

**Property.** A saved plan may be applied only if it deletes the plaintext git-data volume 106867358 named `soleur-git-data-store` (and optionally its attachment, which must bind that volume and server 170370833) and changes nothing else.

**Assembly.** Every path that can authorize a destroy for these addresses: the gate function, its single call site in the workflow (return code checked), the workflow's `-target` set, the validate job's literals, the job-level and workflow-level concurrency groups, and the read-back. The chokepoint is the one `terraform apply tfplan` step: it consumes only a plan this gate graded in the same job. No other workflow can delete these addresses: the replace/birth jobs are graded by their own gates, which refuse any plan that deletes the plaintext attachment.

**Mutation matrix.**

| # | Mutation (drives the gate RED) | Expected refusal |
|---|---|---|
| M1 | add `hcloud_volume.git_data_luks` (107140231) as `["delete"]` | out_of_scope_change |
| M2 | add a third non-ignorable change (`hcloud_server.git_data` `["update"]`) after the two compliant deletes | out_of_scope_change |
| M3 | volume `before.id` = "106867359" or `before.name` = "soleur-git-data-store-luks" | wrong_volume_identity |
| M4 | volume actions `["delete","create"]`, `["create","delete"]` or `["forget"]` | not_pure_delete |
| M5 | attachment `before.volume_id` = 107140231, or `server_id` = another server | wrong_attachment_binding |
| M6 | `resource_changes` null or absent | preamble refusal |
| M7 | an entry missing `.change.actions` | preamble refusal, never dropped |
| M8 | duplicate entry for one pinned address, `deposed` entry, or `.mode` = "data" | wrong_volume_identity / out_of_scope_change |
| M9 | attachment-only delete with the volume present | volume_delete_missing |
| M10 | the gate is sourced but never called, or the call site drops the `if !` check | parity-suite pins describe block RED |

**Harness rows.** H1: replace the gate body with `return 0` → the must-RED rows turn the suite RED. H2: type-faithful fixtures (volume id string, attachment ids numbers) — a fixture using the wrong type would pass or fail for the wrong reason. Must-PASS rows that are NOT the canonical: P1 volume delete only (attachment already gone); P2 reordered `resource_changes`; P3 extra `["no-op"]` and `["read"]` entries (server, module, data sources, passphrase pair).

**Anchor.** The pin lives in three places one edit cannot move together without a reviewer seeing it: the constant in the gate, the `expected_volume_id` input literal in the validate job, and the live Hetzner read in the same job. A weakening that edits the constant still fails the live read. The environment reviewer authorizes each dispatch, but `prevent_self_review=false`: the owner can approve their own run, so the typed pins and the gate are the controls that do not depend on that approval.

## Task Design

```yaml
tasks:
  - task: git-data-plaintext-volume-destroy (workflow jobs validate + destroy)
    trigger: workflow_dispatch by the owner, then environment-reviewer approval for the destroy job
    services: reads Hetzner API (volumes, server) and the R2 Terraform state; writes the R2 state (serial +1) and deletes the Hetzner attachment and volume
    next: nothing
    human_reentry: the reviewer can reject before the destroy job starts (no change made); the owner can cancel a queued or waiting run; a failed or partial run is re-dispatched through the same workflow
    dedupe: precheck by observed state - the Hetzner read decides the shape (both present, attachment gone, both gone) and the already-gone short-circuit skips plan and apply; the gate accepts only the pinned delete shapes; the single Terraform state serial records the removal; both concurrency groups serialize overlapping runs
    source_dedupe: not a ticket source
```

## Acceptance Criteria

- [ ] Phase 0 recorded: `-target` behaviour on an orphaned address and on an absent address, empty-plan `resource_changes` shape, `action_reason`, with the terraform version(s) used ("unverified on 1.10.5" stated if not run).
- [ ] `git-data.tf` declares neither resource; the module call passes `"106867358"` with the `SOLEUR-DEBT:` marker; `terraform validate` passes.
- [ ] `user_data` evidence: the live Hetzner volume id equals the literal, and the PR-time `infra-validation.yml` plan shows `hcloud_server.git_data` with no change (if that plan is unavailable, say so rather than downgrade silently).
- [ ] `modules/git-data-userdata/*` is byte-unchanged and the rung-2 template hash function gives the same value before and after.
- [ ] `test-git-data-plaintext-destroy-gate.sh` passes with M1–M9 RED, P1–P3 green, type-faithful fixtures, and goes RED when the gate body is `return 0`; `test-plan-gate-preamble.sh` passes.
- [ ] The workflow: `workflow_dispatch` only; `validate` job with no environment; `destroy` job `environment: web-platform-infra-apply` with job-level `git-data-state` and workflow-level `terraform-apply-web-platform-host`; `TF_VAR_terraform_version` set; `-target` on exactly the two addresses; read-back runs `success() || failure()`; plan files removed `always()` and never uploaded; the parity pins describe block asserts each.
- [ ] `terraform-target-parity.test.ts` (with `MAIN_ROOT_TF_WORKFLOWS` registration and the count bump), `test-git-data-wipe-wedge.sh`, `git-data-rung2-rehearsal.test.sh`, `test-infra-privileged-tier-census.sh`, `workflow-file-size.test.ts`, `c4-count-parity.test.sh`, `lint-encryption-posture.test.sh`, and the existing replace/birth gate suites pass.
- [ ] `apply-web-platform-infra.yml`, `git-data-host-replace-gate.sh` and `git-data-host-birth-gate.sh` are byte-unchanged; `ci-deploy.sh`, the webhook secret, `git-data-cutover.yml` and the wipe code are untouched (`git diff --name-only origin/main`).
- [ ] Grep shows `git-data-cutover.yml` and its `rollback` mode never reference the plaintext volume.
- [ ] No `docs/legal/**`, mirror, `legal-doc-shas.ts` or `AGENTS.rules.md` edit; no emptiness claim occurs anywhere in the diff.
- [ ] Runbook section, ADR-239 DRAFT amendment (PENDING CLO ATTESTATION, claim limits once, disabled-routes statement, `prevent_self_review` statement) are present.
- [ ] The two follow-up issues are filed before READY, each with milestone, calendar date and owner (gate retirement: target about one week after the destroy), and linked from the ADR amendment and the PR body.
- [ ] Owner actions state: flip retry → any rotate → merge → dispatch within about 24 hours; no host rotate/replace/create after the merge until gate retirement lands (emergency rebirth escalates to the owner); avoid dispatching during a cohort call or demo; if not merged by 2026-11-02 the CLO re-ruling and DPD edit are dated items on #6897.
- [ ] The PR is READY with green CI, auto-merge not armed, ends with `## Owner actions` including the order flip retry → merge → dispatch; no workflow dispatched, no `terraform apply` run, no plan file or secret printed.
- [ ] Commits authored `Jean Deruelle` (verified before push), `git commit -F`, with the Co-Authored-By line.

## Test Scenarios

- Given a synthesized plan with exactly the volume and attachment deleting (plus `no-op`/`read` closure entries), the gate passes.
- Given a plan that also touches the LUKS volume, a server update, a replace shape, a wrong id/name/binding, a duplicate entry, an attachment-only delete or a degraded document, the gate refuses with a named verdict and apply is never reached.
- Given the attachment already gone, a volume-only delete plan passes.
- Given the volume 404 and the name list empty before planning, the workflow skips plan/gate/apply and ends "already destroyed".
- Given an apply that fails after the attachment is destroyed, the read-back step still runs and reports the actual state.
- Given a wrong typed input, the validate job fails before any approval is requested.

## Sharp Edges

- Merging disables the git-data host rotate/replace/create routes and strands the `"106867358"` literal as a dangling id: any host rebirth before `id = ""` boots into a bootstrap FATAL. The merge must follow the flip retry; the follow-up issue sequences gate retirement → `id = ""` via a deliberate host replace.
- Between merge and dispatch the drift workflow files an `infra-drift` issue and email showing the two destroys, and a local untargeted `terraform apply` would delete the volume without pins or gate. Keep the window short.
- The workflow-level group is held while the run waits for approval and GitHub keeps one pending run per group; dispatch only when the reviewer can approve at once.
- Protection is off on both volumes; the id pins and the live read are the only guards. The gate must not accept `["read"]` or `["no-op"]` loosely: only those exact action lists.
- The plan JSON embeds secret values (passphrase, service token): read only inside the gate, never upload, remove it in an `always()` step.
- Local terraform is 1.9.8, workflows pin 1.10.5; state which version proved what.
- A plan whose `## User-Brand Impact` is empty or lacks the threshold fails deepen-plan Phase 4.6; it is filled.
- Deadline: PR ready by 2026-10-30; flip retry first; dispatch 2026-11-02..11-05; if the PR is not merged by 2026-11-02, the CLO single bounded extension applies (DPD edit before 2026-11-12, re-ruling on #6897).
