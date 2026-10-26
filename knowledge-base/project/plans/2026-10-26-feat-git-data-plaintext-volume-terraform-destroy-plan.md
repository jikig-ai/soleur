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
| `apps/web-platform/infra/git-data-plaintext-volume-state.sh` (read-only probe) | — | inferred — justification: the pre-plan read, the post-apply read-back and the `## Observability

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
