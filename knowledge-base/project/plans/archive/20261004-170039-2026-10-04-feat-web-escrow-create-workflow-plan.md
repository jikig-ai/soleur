---
title: "feat: dispatch-only create-only workflow for the web-class LUKS escrow resources"
date: 2026-10-04
slug: web-escrow-create-workflow
branch: feat-one-shot-web-escrow-create-workflow
issue: 9377
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: dispatch-only create-only workflow for the web-class LUKS escrow resources

## Enhancement Summary

**Deepened on:** 2026-10-04 (after the plan-review panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CTO devex lens; plus the CLO and CPO consults).
**Scope of this pass:** the mandatory halts were run mechanically (user-brand impact, observability, PAT sweep, encryption posture, guard contract via `scripts/lint-guard-contract.py`, scope check with exactly one unfenced section) and every cited rule id, issue and PR number was re-verified live. A blanket fan-out of every agent and skill was not repeated: the six-seat review panel had just read this exact plan, and the corrections they and the verification pass produced are already merged into the sections below.

### Key improvements

1. **The create set is now evidence-backed, not assumed.** The drift comment on #9382 shows exactly the bucket and three `doppler_secret` creates (the password arrived with #9448), with `doppler_config.workspaces_luks_web` and the fresh-boot token already in state.
2. **A second, CI-forced parity-test edit was found** (`MAIN_ROOT_TF_WORKFLOWS` and its `found.length` census) that the brief did not name; `web-1-swap` was identified as a group the new workflow must NOT take.
3. **Every abort now names the next action** (recovery decision rule for a names-present abort, the `doppler_config` message, the re-dispatch note for a failed apply), and Property 3 no longer claims plan identity across dispatches.
4. **The reader script wiring is now correct** (`doppler secrets` reads `DOPPLER_TOKEN`, so the provider token is passed explicitly for that one call), and its AC3 justification was corrected.
5. **Scope trimmed at review:** the `previous_address` notice, a zero-creates branch and a separate cleanup step were cut; duplicate mutants merged (24 to 20).

### New considerations discovered

- `apply-deploy-pipeline-fix.yml` is `active` (measured read-only 2026-10-04) and shares the serializer group, so a per-merge run can be running or pending when this workflow is dispatched; only `apply-web-platform-infra.yml` is `disabled_manually`.
- `model.c4` carries a clause ("the push-apply creates the key") that this change falsifies; the fix is unconditional and requires regenerating `model.likec4.json`.
- `scripts/guard-vacuity-floor.test.sh` assigns `PROMOTED_FILES` four times; only the last is live.
- #7992 is exactly the "pre-apply state snapshot" capability the architecture review asked to build inline; it stays deferred there.

## Overview

The web-host escrow readiness preflight fails because the Doppler config `prd_workspaces_luks_web` holds none of
`WORKSPACES_LUKS_KEY`, `WORKSPACES_HEADER_BUCKET`, `WORKSPACES_HEADER_R2_ENDPOINT`,
`WORKSPACES_HEADER_R2_ACCESS_KEY_ID`, `WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY`, so a web-host replace of web-2 cannot start
(the web-2 replace is the step that delivers the soleur-github-app read token to web-2, per the #8609 runbook). The Terraform
that defines the first three names (`workspaces-luks-header-web.tf`, merged in #9397 and #9448, ADR-263) was never applied,
because the only workflow that applies this root, `apply-web-platform-infra.yml`, has been `disabled_manually` since 2026-10-01.

This plan adds one new workflow, `.github/workflows/apply-web-escrow-create.yml`: dispatch-only, create-only, five `-target`
addresses, no `-replace`, an inverted plan gate (only an exact `["create"]` on those five addresses may appear), the shared
destroy-guard counters at zero, a names-only live precondition, then apply of the saved plan and a names re-read. It contacts
no host, runs no Terraform state verb and arms no heartbeat. The two remaining names (the R2 access-key pair) are a separate
credential mint tracked on #9377 and are not Terraform; the workflow prints that as the next step.

The pipeline that produces this change dispatches nothing, enables nothing and writes nothing to production. Each live step
(the plan-only dispatch, the applying dispatch, the R2 mint) needs the owner's separate, explicit authorization
(`hr-menu-option-ack-not-prod-write-auth`); a menu answer is not authorization. This PR edits `.github/workflows`, so there is
no agent `--admin` merge. The PR body uses `Refs #9377` and `Refs #8609`, never `Closes`.

## Premise Validation

Checked before research (Phase 0.6), against `origin/main` at 447da66a52:

- **#9377 OPEN, #8609 OPEN, #9397 and #9448 MERGED** (2026-10-03 and 2026-10-04), **#9372 OPEN** (the web-2 rebirth), **#9382 OPEN**
  (drift issue), **#9348 OPEN** (touches the parity test and `workspaces-luks.tf`), **#9474 / #9466 / #9481 OPEN drafts**. None is
  already resolved by a merged PR; the premise holds.
- **`#8609 R-step 5`**: the issue title is about the runtime App key's reachability, and no in-repo text contains the phrase
  "R-step 5". It is used here only as context for why web-2 must be replaced; nothing in this plan depends on it.
- **The five resources exist on `origin/main`** in `apps/web-platform/infra/workspaces-luks-header-web.tf`, and
  `doppler_config.workspaces_luks_web` plus `doppler_service_token.workspaces_luks_fresh_boot_web` exist in
  `workspaces-luks-fresh-boot.tf`.
- **The mechanism against the ADR corpus** (ADR-263 and its 2026-10-02/2026-10-03 addenda): the create path is not a rejected
  alternative. ADR-263 "Known limits" says the first-create premise must be checked live before the reviewed apply (C8) and that
  the HALT's create exemption ends when the rebirth formats a volume; this workflow is the named mechanism for the first.
- **Own capability claims** (`hr-verify-repo-capability-claim-before-assert`): the claim "the apply job cannot take another
  `apply_target`" was read from the owner's brief and is not relied on; the file is not edited at all (owner constraint).

## Research Reconciliation: the headless CTO consult against `origin/main`

The consult's claims were not trusted; each was re-verified.

| Claim | Reality (command or file read) | Plan response |
|---|---|---|
| New file `.github/workflows/apply-web-escrow-create.yml`, dispatch only | `workspaces-plaintext-forget.yml` is the precedent for a separate dispatch-only workflow that takes the same group and an `infra-privileged` job | Adopted |
| Concurrency group exactly `terraform-apply-web-platform-host`, `cancel-in-progress: false`, the only serializer of the lockless R2 state | True: `apply-web-platform-infra.yml` workflow-level `concurrency:` block says so (anchor `group: terraform-apply-web-platform-host`); `main.tf` carries no state lock; three workflow files declare the literal (the apply workflow, `apply-deploy-pipeline-fix.yml`, `workspaces-plaintext-forget.yml`). The parity test's `EXPECTED_GROUP` row covers only the first two, so suite row T4 is the sole pin for the new file | Adopted. Note: a run queued behind a running one displaces an older *pending* run in the same group (GitHub semantics, same for every sharer); recorded under Risks |
| Environment `infra-privileged`, skeleton from `ci_ssh_token_replace` | True for the skeleton (loader, typo-guard, dummy ssh public key for `var.ssh_key_path`, backend credentials, `init -lockfile=readonly`). **Not** the job-level `web-1-swap` group: that arm destroys a credential the SSH bridges use; ours touches no bridge, and `web-1-swap-concurrency-parity.test.sh` counts exactly eight `group: web-1-swap` occurrences across three workflows, so enrolling would redden it | Skeleton adopted; `web-1-swap` deliberately NOT taken (pinned by a suite row) |
| Exactly five `-target`s, no `-replace` | The five resources are the whole of `workspaces-luks-header-web.tf` (bucket, password, three secrets) | Adopted |
| The create set is unproven (drift log truncated) | **Mostly proven.** The 2026-10-04 07:49 UTC drift comment on #9382 (state of #9397, before #9448) lists `will be created` for exactly the bucket and the three `doppler_secret`s, `Plan: 14 to add, 1 to change, 10 to destroy` (the other 10 adds are replaces of unrelated hosts), and shows `doppler_config.workspaces_luks_web` and `doppler_service_token.workspaces_luks_fresh_boot_web` as `Refreshing state` (in state). `random_password.workspaces_luks_web` arrived with #9448 and is the fifth create. The plan output there shows `(sensitive value)` for every secret value | The five-address set is consistent with measured evidence. The plan-only dispatch remains the real review; the table "If the real plan differs" below states the gate's behaviour |
| `doppler_config` create must abort | True and necessary: the config is in state, so a create would mean state/live divergence, and the workflow has no state verbs, so it can neither import nor create it | Gate aborts; recovery is a separate reviewed change |
| Shared filter `destroy-guard-filter-web-platform.jq`, a first create of the password and key copy is legal | True: `luks_passphrase_rotations` counts `update`, `delete`, `forget` and unreadable verb lists at six addresses, and explicitly not `create`. `host_creates` counts `hcloud_server.*` creates only | All eight outputs required (`plan_ok` true, seven counters zero) |
| Names-only live precondition enforces C8 and the create-exemption-expiry trap | Counsel review C8: "the checker's live mode must report the key as missing and the reviewed plan must show creates only for the web-class pair". ADR-263 Known limits: a state loss after the first format plans as a `create` that overwrites the live secret | Adopted as a step that reads names through a committed reader script (see Cut List for why a script) |
| Tests/registrations: `suite-shard-legs.tsv`, `suite-durations.tsv`, `scripts/guard-vacuity-floor.test.sh` | All three hold the forget suite. The vacuity script's `apps/web-platform/infra/` directory is DEFERRED with a shrink-only ledger, so a new floor-bearing suite there must be added to `PROMOTED_FILES` (the `workspaces-plaintext-forget-workflow` entry is the precedent) | Adopted, with the PROMOTED_FILES edit named |
| "The one deliberate gate change" in `terraform-target-parity.test.ts` | **Not one: two.** (1) The "NO other workflow FILE" row only (the "NO other job" row iterates the apply workflow's own jobs and stays as it is). (2) `MAIN_ROOT_TF_WORKFLOWS` (a closed list of main-root Terraform planners) and its census row `expect(found.length).toBe(3)`: any new workflow with `terraform plan`/`apply` and `INFRA_DIR` is `found`, so the exact-equality assertion reddens, and the listed workflows must also feed `TF_VAR_terraform_version` equal to `TERRAFORM_VERSION` | Both edits planned and flagged for explicit review; the apply-job rows are not touched |
| `test-infra-privileged-tier-census.sh` update only if it flags the new file | The census assembles its file set from `git ls-files` and keys on what a job references; a job that declares an `infra-privileged` environment, carries `--preserve-env` on every `doppler run` and takes backend credentials in the loader-compatible form is clean. AC3 flags a `doppler secrets get <Tier-B name> ... -c prd_terraform` read (`DOPPLER_TOKEN_TF` is one) in any workflow step outside the loader; a `doppler run -c prd_terraform --name-transformer tf-var` is not flagged (plan-review correction: the first draft overstated this) | No census edit planned. The names reader stays a committed script for testability and log hygiene, not to dodge AC3 |
| Workflow-file-size and the other workflow census gates | `workflow-file-size.test.ts` caps each file at 490,000 bytes (the new file is a few KB). `c4-count-parity.test.sh` counts only workflows that use `actions/sentry-heartbeat`; this one arms none. `web-1-swap-concurrency-parity.test.sh` is unaffected (above). `web-host-escrow-preflight-census.test.ts` keys on a job that applies an indexed `-target` of `hcloud_server.web`; this job has none | Run all four as targeted checks; expect no edit |

### If the real plan differs: how the gate behaves

The gate is an allow-set over the whole plan, so every unexpected shape stops the run before any mutation. Nothing here is
decided by the workflow itself; a person decides the next change.

| Shape of the real plan | Gate and run | Why / next |
|---|---|---|
| A subset of the five addresses as `["create"]` (for example the password already in state) | Pass; the creates file lists only those; apply creates only those | A re-dispatch after a partial apply lands here |
| Zero non-no-op entries | Pass with `creates=0`; no apply, summary says nothing to create | Idempotent re-dispatch |
| `doppler_config.workspaces_luks_web` as `["create"]` | Abort (not in the allow-set, named in the message) | The config is in state per the drift evidence; a create means state and live disagree. This workflow has no import verb; the fix is a separate reviewed change |
| `doppler_service_token.workspaces_luks_fresh_boot_web` in the plan | Abort | Not a dependency of the five targets, so it can appear only if the dependency graph changed; investigate |
| `["update"]` on any of the five | Abort | A value changed under an existing resource is a rotation, the class the HALT counters exist for; also trips `luks_passphrase_rotations` |
| `["update"]` on any address outside the five (for example drift on `doppler_config.workspaces_luks_web`, an inheritance or metadata change) | Abort, naming the address | No remedy inside this workflow; a reviewed change reconciles it |
| `["delete","create"]` or `["create","delete"]` or `["delete"]` or `["forget"]` on any address | Abort | Replace/destroy/forget is never legal here |
| Any other address (any `hcloud_*`, `terraform_data.*`, module-prefixed or indexed spelling of an allowed address) | Abort | `-target` is transitive on dependencies; the flags are a request, the plan is the proof |
| An entry whose `actions` is missing, not an array, or empty | Abort | Both the allow-set (treated as not no-op/read) and the shared filter's `undecidable_entries` read it |
| A plan JSON with no `resource_changes` array | Abort (`plan_ok` not true) | A zero count from nothing parsed is not a clean plan |
| `["no-op"]` or `["read"]` entries at any address (including `data.*` reads, and no-op `doppler_config` refresh) | Ignored | Not changes |
| A plan creating a key copy whose name already exists in the live config | Abort in the next step (live precondition) | C8 premise; state-loss-after-format trap |

## Research Insights

**Property List (Phase 0.6b).**

1. The five escrow addresses can be created exactly once by an automated, reviewable path while push-apply stays disabled.
2. That path can never replace, rotate, destroy, forget, import or touch any other resource, host or credential.
3. A person sees the exact create set in the plan-only run before any applying run exists. The applying dispatch re-plans (the plan-only run's saved plan does not carry over) and re-grades with the same gates, so it can differ from what was reviewed only inside the allow-set (at most the five known creates); both runs print the creates list so the two can be compared.
4. A passphrase copy that already exists live is never overwritten.
5. State writes are serialized with every other applier of this root.
6. No secret value reaches a log, summary or artifact.

**Cut List.** (mechanism, property it would buy, what already covers it)

- Re-enable `apply-web-platform-infra.yml` or add an `apply_target` there: buys property 1, but the whole-root plan on #9382 carries ten unrelated destroy/replace entries, the file sits near its byte cap, and the owner forbids editing it. Cut.
- A local, ungated `terraform apply` from a workstation: buys property 1, but bypasses every gate and the serializer. Cut (`hr-all-infrastructure-provisioning-servers`).
- A cross-gate census listing this workflow beside the apply job: property 2 is already pinned by the parity-test rows this plan rewrites. Cut.
- A new `plan_only` entry in the tier census `PLAN_ONLY_JOBS`: the owner said update that census only if it flags the new file; it will not. Cut; the guard form (`if: inputs.plan_only != true`) is mirrored anyway, so adding the job later is one set member.
- A Sentry heartbeat or alert for this workflow: owner excluded heartbeat arming; a one-shot manual run has no cadence to watch. Cut.
- A step that proves "push-apply is paused" (as the forget workflow does): not needed, the shared concurrency group already serializes, and a pause proof would need a `gh` call and `actions: read`. Cut.
- Cut at plan review: a `previous_address` notice (answers no ask, noisy on existing `moved` blocks); a `creates=<n>` output and in-step zero branch (an empty plan applies as a no-op); a separate cleanup step (merged into the summary step); a pre-apply copy of the state object to a dated key and a second names check inside the apply step (adds a raw state read to a workflow the owner scoped to no state verbs; #7992 is the tracked "automatic pre-apply Terraform state snapshot" capability, which is exactly this, built once for every applier; the gap between the names step and the apply is minutes inside a serialized group). The last two are recorded as taste calls in decision-challenges.md.
- **Kept, with its justification:** a committed names-reader script (`scripts/web-escrow-create-names.sh`). Inline, the check would be a `bash -c` one-liner under `doppler run` that no suite can drive with a stub, and the names listing (about 116 inherited `prd` names) must not reach the public log. See Scope Check, provenance table.

**Relevant files** (all verified present on `origin/main`): `apps/web-platform/infra/workspaces-luks-header-web.tf`,
`workspaces-luks-fresh-boot.tf`, `.github/workflows/apply-web-platform-infra.yml` (concurrency block, `ci_ssh_token_replace` job,
the `apply` job's destroy-guard block), `.github/workflows/workspaces-plaintext-forget.yml` and its suite,
`tests/scripts/lib/destroy-guard-filter-web-platform.jq`, `scripts/web-host-escrow-preflight.sh`,
`scripts/check-web-host-escrow-config.sh`, `.github/actions/infra-credentials/action.yml`,
`plugins/soleur/test/terraform-target-parity.test.ts`, `tests/scripts/test-infra-privileged-tier-census.sh`,
`plugins/soleur/test/workflow-file-size.test.ts`, `scripts/guard-vacuity-floor.test.sh`, ADR-263,
`knowledge-base/legal/audits/2026-10-counsel-review-9377.md` (C1-C8), the two runbooks.

**Institutional learnings that apply** (a researcher's list was spot-checked; entries that did not match their cited file were dropped):
the 2026-09-24 learning on a rotation resource reachable by more than one workflow (the rationale of the parity rows),
`2026-10-04-an-allow-list-of-line-shapes-is-not-a-closed-sequence...` (state a gate span as a closed sequence and pin order with a
reorder mutant), `2026-07-27-the-safety-rationale-i-wrote-was-false-and-the-gate-it-justified-failed-open-three-ways` (optional
`.change.actions?`, real plan shapes, an error from jq must not read as "condition false"), `2026-08-14-my-gate-reserved-its-reassuring-message...`
(fixtures must be real plan shapes: `["no-op"]` rows, not an empty array), `2026-05-16-...destroy-guard-empty-string-bypass`
(test non-empty before arithmetic). The work phase re-reads each before relying on it.

**Parallel work left alone:** draft PR #9474 (read-only escrow diagnostic workflow; it also edits both runbooks and ADR-241, so
expect textual conflicts in the two runbooks and keep this plan's edits additive in new subsections), #9466, #9382 (the
`hcloud_server.git_data` replace drift is intentional until the cutover and is not touched), #9348 (touches the parity test: plan
for a conflict, see Risks).

## Hypotheses

The network-outage trigger matched only on the words "no SSH leg" in the brief. This plan diagnoses no connectivity symptom and
adds no SSH or bridge path; the layer checklist is therefore recorded as not applicable, with its one live consequence kept: the
workflow's only egress is to the Doppler API, the Cloudflare API (R2 bucket) and the R2 state endpoint, all over TLS from a
GitHub-hosted runner, none of which depends on a firewall allow-list or on a host. The L3/L7 host hypotheses (firewall
allow-list, DNS, sshd, fail2ban) are not tested because no host is contacted (`hr-ssh-diagnosis-verify-firewall` applied).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add a dedicated, dispatch-only, create-only GitHub Actions workflow that creates the web-class LUKS escrow resources" | Phase 2; Files to Create: the workflow | mapped |
| 2 | "workflow_dispatch only (inputs confirm=CREATE-WEB-ESCROW, reason, plan_only)" | Phase 2 inputs block; suite structural rows T1-T3 | mapped |
| 3 | "concurrency group exactly `terraform-apply-web-platform-host` with cancel-in-progress false" | Phase 2; suite row T4 and its mutant | mapped |
| 4 | "environment infra-privileged, no SSH leg, no host contact, no terraform state verbs, no heartbeat arming" | Phase 2; suite rows T5-T9 | mapped |
| 5 | "skeleton from the ci_ssh_token_replace job (infra-credentials, typo-guard with reason echoed to the step summary, dummy ssh key, backend credentials, init -lockfile=readonly)" | Phase 2 step list | mapped |
| 6 | "Plan with EXACTLY five -target addresses and no -replace" | Phase 2 plan step; suite row T10 and mutants | mapped |
| 7 | "the plan must say how the gate behaves if the real plan differs" | Research Reconciliation, "If the real plan differs" table | mapped |
| 8 | "INVERTED plan gate: every non-no-op non-read change must be exactly [\"create\"] on one of those five; any other address or verb, or a doppler_config create, aborts" | Phase 2 gate step; Guard 1 | mapped |
| 9 | "also run the shared tests/scripts/lib/destroy-guard-filter-web-platform.jq and require plan_ok true and zero for resource_deletes, nested_deletes, reboot_updates, host_creates, luks_passphrase_rotations, undecidable_entries and apex_move_orphans" | Phase 2 gate step (counters block); Guard 1 | mapped |
| 10 | "a names-only live precondition that aborts if the plan creates a key copy whose name already exists live" | Phase 1 reader, Phase 2 precondition step; Guard 2 | mapped |
| 11 | "plan_only stops after the gate; otherwise apply the saved plan, re-read the names and print the next step" | Phase 2 apply, re-read and summary steps; suite rows | mapped |
| 12 | "State in the workflow header that first-create legality ends once a web-class volume is formatted (#9372 rebirth)" | Phase 2 header; suite row T15 pins the sentence | mapped |
| 13 | "new apps/web-platform/infra/web-escrow-create-workflow.test.sh modelled on workspaces-plaintext-forget-workflow.test.sh with mutant rows" | Phase 0, Phase 3; Files to Create | mapped |
| 14 | "registered in suite-shard-legs.tsv, suite-durations.tsv and scripts/guard-vacuity-floor.test.sh" | Phase 3 registrations | mapped |
| 15 | "replace the blanket ban with 'exactly this one file may target the pair, only with the structural pins', flag it for explicit review, do not weaken the apply-job rows" | Phase 4 edit A; Guard 3 | mapped |
| 16 | "note open PR #9348 also touches that test file: plan for a conflict" | Risks R6; Phase 4 note | mapped |
| 17 | "run tests/scripts/test-infra-privileged-tier-census.sh and update only if it flags the new file" | Phase 6 verification list; no edit planned | mapped |
| 18 | "an ADR-263 addendum via soleur:architecture and runbook order updates in web-host-birth.md and web-host-replace.md" | Phase 5 | mapped |
| 19 | "check workflow-file-size and the other workflow census gates" | Phase 6 verification list | mapped |
| 20 | "Do NOT edit apply-web-platform-infra.yml, server.tf or any git-data*.tf; do NOT touch hcloud_server.git_data" | Acceptance criterion AC9 (diff check) | mapped |
| 21 | "No production write, host replace, key rotation, ruleset change or workflow dispatch without my explicit, per-step authorization" | Overview; Phase 6; AC10; Risks R9 | mapped |
| 22 | "Never dispatch any workflow or enable apply-web-platform-infra.yml to validate this change; this PR edits .github/workflows so there is NO agent --admin merge. Use `Refs #9377` and `Refs #8609` in the PR body, never Closes." | AC10, AC11 | mapped |
| 23 | "Run targeted suites only (no full local battery; CI owns it)." | Phase 6 | mapped |
| 24 | "Parallel work to leave alone: draft PR #9474 ..., PR #9466 ..., and #9382." | Research Insights; AC9 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/workflows/apply-web-escrow-create.yml` | "new file .github/workflows/apply-web-escrow-create.yml" | asked |
| `apps/web-platform/infra/web-escrow-create-workflow.test.sh` | "new apps/web-platform/infra/web-escrow-create-workflow.test.sh" | asked |
| Edits to `suite-shard-legs.tsv`, `suite-durations.tsv`, `scripts/guard-vacuity-floor.test.sh` | "registered in suite-shard-legs.tsv, suite-durations.tsv and scripts/guard-vacuity-floor.test.sh" | asked |
| Edit A in `terraform-target-parity.test.ts` (ban rows) | "the one deliberate gate change in plugins/soleur/test/terraform-target-parity.test.ts" | asked |
| Edit B in `terraform-target-parity.test.ts` (`MAIN_ROOT_TF_WORKFLOWS`, count 3 to 4, version-feed row) | — | inferred — justification: without it the existing main-root census row reddens on the new workflow (`found` would hold a fifth entry and `length` would be 4), and that row also enforces `TF_VAR_terraform_version` parity for every main-root planner |
| ADR-263 addendum | "an ADR-263 addendum via soleur:architecture" | asked |
| `web-host-birth.md` and `web-host-replace.md` edits | "runbook order updates in web-host-birth.md and web-host-replace.md" | asked |
| `scripts/web-escrow-create-names.sh` | — | inferred — justification: the live precondition needs a Doppler provider token and a names listing that must not reach the public log; a committed script can be driven by a stub in the suite (a `bash -c` one-liner under `doppler run` cannot), and it is the single chokepoint Guard 2 quantifies over |
| Model/diagram edits in `model.c4` (only if the enumeration finds a gap) | — | inferred — justification: the ADR/C4 gate requires the architecture record to match what ships; conditional on the three-file read |
| `plan_only` defaults to `true` | "plan_only stops after the gate" | asked (default is a safety choice; see decision-challenges.md) |
| Gate prints a table of non-no-op entries (addresses and verbs) | "the plan_only dispatch is the real review" | asked (the review needs something to read); a `previous_address` notice was considered and cut at plan review (answers no ask, fires on pre-existing `moved` blocks) |

### Split Assessment

- Subsystems touched: 5 — `.github`, `apps/web-platform`, `plugins/soleur`, `scripts`, `knowledge-base`
- Planned files: 13 | Estimated changed lines: about 1,500 (workflow 420, suite 700, reader 70, parity test 150, docs 150, tables 10)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — the one natural seam is the documentation (ADR addendum and the two runbooks) trailing the code. Declined, with the reason: the CI-required parity-test edits cannot be separated from the workflow (the new file reddens two existing rows on its own), the suite registrations ride with the suite, and the runbook and ADR text describe the shipped mechanism in the wording the counsel review constrains (no past tense for anything not yet run), so they are reviewed best against the code. If review wants a smaller PR, the docs are the part to move.

## Open Code-Review Overlap

None. Queried the open `code-review` issues (200 fetched) against every planned path; no body names any of them.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing today. No user data exists on a web-class volume (web-2 is plaintext,
empty and at serving weight 0). The harm lands later and is irreversible: a data-bearing web-class volume formatted against key
material that was regenerated, lost or overwritten, so one user's workspace is unopenable. A gate that is wrong in the other
direction (fails closed forever) blocks the web-2 replace only, with no user impact.

**If this leaks, the user's workflow data is exposed via:** the web-class LUKS passphrase, whose durable copies are Doppler
(three names in `prd_workspaces_luks_web`, plus Doppler history) and Terraform state, and which exists on the runner for the life
of the job. Vectors: (A) a regenerated or replaced passphrase after a format (primary; guarded by create-only gate, the shared
rotation counters and the live-names precondition); (B) state loss or rewind, which plans as a `create` and would overwrite the
live secret (guarded by the live-names precondition; the state bucket has no object versioning, tracked #7992, accepted only
while no web-class volume holds data); (C) a log, summary or artifact carrying a value (guarded: plan output shows `(sensitive
value)`, names-only reads, no artifact upload, no `tee`, plan files deleted in an `always()` step); (D) a partial apply (a
re-dispatch plans only the remainder; a secret created but not recorded in state is caught by the names precondition and needs a
person); (E) a gate that fails closed (blocks web-2 replace only); (F) premature trust: creation proves names exist, not that the
header can be restored or that the R2 pair is bucket-scoped (both stay open: #9372 criterion 2 for recovery, the signed isolation
proof on #9377 for scope).

**Brand-survival threshold:** `single-user incident`

CPO plan-time sign-off: yes-with-conditions (consulted headlessly 2026-10-04). Conditions carried: vectors A-F and the artifact are
named here and go into the PR body; create-only immutability is stated (no replace or update path exists in the workflow, and
`random_password.workspaces_luks_web` already carries `prevent_destroy`); state-loss recovery and log masking are stated;
partial-apply recovery is stated; the restore-verification follow-up already exists (#9372 criterion 2, #7992), so no new issue is
filed; `soleur:engineering:review:user-impact-reviewer` runs at review time; the GDPR gate must run when the first data-bearing
web-class host is born (recorded in the ADR addendum).

## Domain Review

**Domains relevant:** Engineering (the CTO consult was headless and is re-verified above), Legal, Product (single-user threshold only)

### Engineering

**Status:** reviewed
**Assessment:** The consult's design is sound; four of its claims needed correction or completion (see the reconciliation table:
the drift evidence, the second parity-test edit, `web-1-swap` must not be taken, the names reader must be a script).

### Legal

**Status:** reviewed (CLO headless consult, 2026-10-04)
**Assessment:** No register cell, Article 30 row or attestation changes, because the workflow is the "push-apply" the cells already
condition on; no addendum is needed before merge. Re-review is needed only if this PR edits a register cell, the ledger row or
the ADR text beyond an additive addendum. The first live apply fires re-evaluation trigger 1 and needs a measured supersession
(C4: after reading state and re-reading the Doppler names, append a dated `Superseded` marker under every conditional sentence
without deleting it, keep the Article 30 and compliance-posture R4 cells byte-equal after bold removal, re-run
`python3 scripts/lint-encryption-posture.py`), owned by the CLO agent as v1 attestation authority with the owner holding a veto,
not by the owner alone. C8 is satisfied BEFORE the apply by the live precondition (record its output in the run summary). C1
(bucket scope of the R2 pair) and C2 (retiring the pre-split token) are untouched by this apply. Wording constraints for the
workflow header, summary, runbooks and ADR addendum: no sentence says web-2 is or will be encrypted or "LUKS-backed"; say
"intended to be scoped, unverified" for the R2 pair; "best-effort Sentry email" not "paged"; durable copies are Doppler, Doppler
history and state, plus a runner-local copy for the life of a job; the first-create premise is read from workflow state and
history, not from Doppler (C8), and this workflow is the check; cite code by name, never by line number; nothing the run has not
done is written in the past tense.

### Product/UX Gate

**Tier:** none (no user-facing surface: workflow, tests, scripts and docs only; no path in Files matches the UI-surface list)
**Decision:** not applicable, infrastructure change
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** not applicable (no UI surface)

CPO threshold sign-off is recorded in User-Brand Impact.

## Architecture Decision (ADR/C4)

Detection fires (a new automated path for first creation of key material, a new trust-boundary writer to `prd_workspaces_luks_web`,
and an extension of ADR-263's decisions D7/D8). Both are deliverables of this plan, not follow-ups.

### ADR

Amend ADR-263 with a hand-written appended section `## Addendum — 2026-10-04 (#9377)` (the `soleur:architecture` skill has no
amend sub-command; the 2026-10-03 addendum was written the same way, and ADR-263 is an addendum-carrying record: dated text is
kept, status stays `adopting`). Content: the decision (D9: a dedicated create-only workflow is the only automated creation path
for the web-class escrow resources, while push-apply is disabled); alternatives considered and rejected (re-enable push-apply,
an `apply_target` on the apply workflow, a local ungated apply, a Terraform root of its own); the gate shape (inverted allow-set
over five addresses, shared counters, live names precondition); the sentence that first-create legality ends once a web-class
volume is formatted (the #9372 rebirth) and that the live precondition, not the plan gate, is what keeps a state-loss `create`
from overwriting a live secret after that point; the retire-with-#9372 note (with the link to the retirement checklist comment); the shared-group displacement note; that the seven counters are defense in depth and the allow-set is the guard; the CLO follow-through (C4/C8) and the GDPR gate
reminder for the first data-bearing web-class host. Written in the future or conditional tense for everything not yet run.

### C4 views

Work-phase task, before writing any "no C4 impact" line: READ `knowledge-base/engineering/architecture/diagrams/model.c4`,
`views.c4` and `spec.c4` (not a keyword grep) and enumerate against the feature: (a) external human actor: the dispatching owner
(the `founder -> github` and `founder -> doppler` approval edges exist); (b) external systems: GitHub Actions, Doppler, Cloudflare
(R2 state bucket and the web-class header bucket; the `hetzner -> cloudflare` edge describes web-1's bucket and the `doppler ->
hetzner` edge describes the web-class config); (c) containers or stores touched: the web-class header bucket (already in the
ledger and ADR), `prd_workspaces_luks_web`; (d) actor-surface access relationships: the Tier-B `github -> doppler` edge covers a
Tier-B job writing Doppler through Terraform. If an element or relationship is not modelled, the `.c4` edit (element, `#external`
tag, edges, and the `view include` line so it renders) is an in-scope task. Edge descriptions that the change falsifies are
corrected. **One correction is already known and unconditional (architecture review):** the `doppler -> hetzner` edge in
`model.c4` says "Once PR #9448 (Ref #9377) merges and the push-apply creates the key (nothing has been applied)". The push-apply
is disabled and this workflow becomes the creator, so that clause is reworded to name both (the disabled push-apply, or
`apply-web-escrow-create.yml`), still in the conditional tense (nothing is applied by this change). After any `.c4` edit,
regenerate the derived JSON with `scripts/regenerate-c4-model.sh` (pinned `likec4@1.50.0`) and run
`plugins/soleur/test/c4-model-freshness.test.sh`, because `model.likec4.json` must stay byte-identical to a fresh render. Validate with `apps/web-platform/test/c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` (the latter
counts only heartbeat-using workflows, so it must stay green unchanged).

### Sequencing

The ADR describes the target state with an `adopting` status; no later slice is needed for the addendum itself.

## Encryption Posture

No file in this change declares a store or a connection. The workflow instantiates stores that `workspaces-luks-header-web.tf`
already declares and `scripts/encryption-posture-ledger.json` already ledgers (`cloudflare_r2_bucket.workspaces_luks_header_web`).

```yaml
at_rest:
  - store: cloudflare_r2_bucket.workspaces_luks_header_web (created by this workflow's apply, declared in #9397)
    mechanism: provider-managed object storage encryption (Cloudflare R2), no customer-held key; the header object is a LUKS header, which cannot open a volume without the passphrase
    evidence: scripts/encryption-posture-ledger.json row for this store (already merged); not re-asserted here
    defends_against: offline disk theft at the provider
    does_not_defend: a Cloudflare or token-holder with API access reading or overwriting objects; the bucket has no object versioning and no lock rule; the R2 pair's bucket scope is intended and unverified (C1)
    disclosed_as: Article 30 and compliance-posture cells already carry this (counsel review 2026-10)
    live_verification: none yet; the signed HEAD isolation proof on #9377 is the later step
  - store: doppler_secret.workspaces_luks_web_key and two sibling secrets in prd_workspaces_luks_web
    mechanism: Doppler-managed secret storage, visibility masked
    evidence: workspaces-luks-header-web.tf (visibility = "masked")
    defends_against: casual disclosure in dashboards and logs
    does_not_defend: any holder of a token that resolves the config, which inherits the roughly 116 `prd` secrets; the passphrase also sits in Terraform state with no object versioning (#7992)
    disclosed_as: ADR-263 Known limits and the 2026-10-03 addendum
    live_verification: the post-apply names re-read proves the names exist, never the values
in_transit:
  - connection: runner to the Doppler API, the Cloudflare API and the R2 state endpoint
    tls: https, certificate verification on (no `-k`, no skip flag in any step)
    cert_verification: on
    does_not_defend: a compromised runner or a leaked job token
    disclosed_as: the workflow header, which states the runner-local copy
```

## Infrastructure (IaC)

No new infrastructure is introduced: the resources the workflow creates are Terraform-declared, and the workflow is the apply path
for them (`hr-all-infrastructure-provisioning-servers` satisfied). The one step that stays outside Terraform is the R2 credential
mint, which is the deferred, tracked item on #9377 and is printed as the next step, not performed here.

### Terraform changes

None. `workspaces-luks-header-web.tf` and `workspaces-luks-fresh-boot.tf` are not edited (and `server.tf`, every `git-data*.tf`,
`apply-web-platform-infra.yml` are explicitly off limits). No new `TF_VAR_*`: every provider token already comes from
`prd_terraform` through `doppler run --name-transformer tf-var`, as in `ci_ssh_token_replace`.

### Apply path

Dispatch of a new workflow (neither cloud-init nor a taint): plan-only first, then an applying dispatch that applies the saved plan.
Expected downtime: none; blast radius: one R2 bucket, one random value and three Doppler secrets in a branch config that no live host
reads yet.

### Distinctness / drift safeguards

The existing `workspaces-luks-header-web.test.sh` and the checker's `--static` census keep the web-class passphrase independent of
web-1's. This workflow adds the runtime half: the live precondition refuses to create over an existing name. `prevent_destroy`
stays on the bucket and the password; the key copy has no lifecycle block and is stopped by the rotation counters.

### Vendor-tier reality check

The R2 bucket create needs the narrow `cloudflare.r2` provider token (`cf_api_token_r2`, Workers R2 Storage:Edit), the same one
that created web-1's header bucket. No free-tier gate applies. A 403 from that API would fail the apply step after the random
value may already exist in state; the recovery is the same re-dispatch (it plans the remainder).

## Observability

Files in scope include `apps/web-platform/infra/*.test.sh` and a new workflow, so the block is required. The surface is a
one-shot, manually dispatched GitHub Actions run; the signal is the run itself (layer 6: workflow-run log and step summary),
with no Sentry layer (heartbeat arming is excluded by the owner).

```yaml
liveness_signal:
  what: the workflow run conclusion and its job step summary (stage table, the reason text, the five creates or "nothing to create", the names re-read, the next step)
  cadence: on each owner-authorized dispatch only; there is no schedule and none is wanted
  alert_target: GitHub notifies the dispatching user of a failed run; every abort is an ::error:: annotation naming the cause (layer 6)
  configured_in: .github/workflows/apply-web-escrow-create.yml (steps gate, names, apply, reread, summary)
error_reporting:
  destination: workflow-run annotations and the job step summary (layer 6); no Sentry event is emitted by design
  fail_loud: every guard step exits non-zero with an ::error:: line; no step carries continue-on-error; a missing outcome in the summary step fails closed
failure_modes:
  - mode: the real plan differs from the five creates
    detection: the gate step aborts and prints the offending addresses and verbs (names and verbs only)
    alert_route: layer 6 annotation on the failed run
  - mode: a key copy name already exists live (hand-set value, partial apply whose state write was lost, state loss after a format)
    detection: the names step aborts naming the address and the secret name, never a value
    alert_route: layer 6 annotation on the failed run
  - mode: the names listing cannot be read (token invalid, config absent, output shape changed)
    detection: the reader exits 3 and the step aborts; an unreadable listing is never read as absent
    alert_route: layer 6 annotation on the failed run
  - mode: apply fails part-way (R2 API 403, Doppler API error)
    detection: the apply step is red; the summary step records outcomes
    alert_route: layer 6; recovery is a re-dispatch, which plans and creates only the remainder
  - mode: a value reaches a log
    detection: pinned absent by the suite (names-only reads, no tee, no artifact upload, no echo of plan JSON) and by a behavioral row that greps the step output for a sentinel
    alert_route: the suite fails in CI before merge
logs:
  where: GitHub Actions run log and job summary; the repo is public, so the log carries addresses, verbs, counts and the five secret names only
  retention: GitHub's default run-log retention
discoverability_test:
  command: grep -n "group: terraform-apply-web-platform-host" .github/workflows/apply-web-escrow-create.yml
  expected_output: terraform-apply-web-platform-host
```

## Guard Contract

The deliverable includes three guards. Matrices are derived from the design, written before the code (Phase 0 writes the suite
rows first). Each mutation is an edit to a copy of the workflow (or the parity test) that must turn a named row RED.

### Guard 1 — the inverted create-only plan gate

**Property.** The plan that is applied contains, apart from no-op and read entries, only entries whose address is one of the five
escrow addresses and whose action list is exactly `["create"]`, and the shared destroy-guard output reads `plan_ok` true with all
seven counters zero.

**Assembly.** The chokepoint is the single saved plan file `tfplan`: exactly one `terraform plan -out=tfplan` step, exactly one
`terraform show -json tfplan` (the gate), exactly one `terraform apply ... tfplan` (the apply, with no `-target` or `-replace` of
its own). The members that must agree are the plan step's five `-target` flags, the gate's allow-set literal, the creates-file
consumer (the names step) and the address-to-secret-name map; the suite pins the first two equal to each other and to the five
addresses of `workspaces-luks-header-web.tf`, so the two encodings of one fact cannot drift apart silently. Order (gate before
names before apply) is pinned by step index, and the apply and re-read steps carry the `plan_only` guard.

**Mutation matrix.**

| # | Edit (to a copy of the workflow) | Row that must go RED |
|---|---|---|
| 1 | add a sixth address (`doppler_config.workspaces_luks_web`) to the allow-set | T11 allow-set equals the five; B-gate-config (a config create must abort) |
| 2 | loosen the verb test from exact `["create"]` to "contains create" | B-gate-replace (a password `["delete","create"]` must abort) |
| 3 | make the violation branch print and continue (remove its `exit 1`), the gate's own dispatch | every B-gate abort row, plus T12 (the gate step must end the job on a violation) |
| 4 | after a compliant first entry, stop scanning (grade only the first N entries) | B-gate-second (five legal creates plus one extra `hcloud_server` create must abort) |
| 5 | drop the `plan_ok` check | B-gate-noarray (a plan JSON with no `resource_changes` must abort) |
| 6 | drop one counter read or its zero requirement (`luks_passphrase_rotations`) | T13 counter set equals the seven plus `plan_ok` |
| 7 | move the apply step above the gate (a REORDER, not a delete) | T14 step order; plus a row that observes inside the window: the gate step must precede every step that can write (apply) |
| 8 | remove `if: inputs.plan_only != true` from the apply step | T16 apply and re-read carry the guard; T17 no step is enabled by `plan_only` |
| 9 | add `-replace=random_password.workspaces_luks_web`, a sixth `-target`, or a `-target=hcloud_...` to the plan step (one row: all die on the same pin) | T10 exactly five `-target` and no `-replace`; T18 no `hcloud_` token in any step |

**Harness rows.** (a) The suite's own instrument self-test (`ok()`/`no()` drive both verdicts once and exit 2 unless both counters
moved) turns RED under a neutered `no()`; (b) a pass floor `-lt` bound, printed with `printf` and `exit 1`, never through `no()`,
and `PASS + FAIL == CASES`. Must-pass inputs that are not the canonical: a legal plan carrying three of the five creates plus
no-op and read entries in a different order; a plan with zero non-no-op entries (must pass, empty creates file).

**Anchor.** The stored value is the allow-set. One diff could edit the workflow, the suite and the parity-test pin together, so
the suite proves consistency, not integrity. What sits outside the commit: the parity-test rows (a different file, flagged in the
PR body for explicit review, whose pin of the five addresses is derived from `workspaces-luks-header-web.tf`, not from the
workflow) and the plan-only dispatch, where the owner reads the real plan before any applying dispatch.

### Guard 2 — the names-only live precondition (C8)

**Property.** No `doppler_secret` create in the plan is applied while its secret name already exists in
`prd_workspaces_luks_web` (own or inherited), and an unreadable listing is never read as "absent".

**Assembly.** The chokepoint is the single reader script `scripts/web-escrow-create-names.sh` (token from
`TF_VAR_doppler_token_tf` under `doppler run --preserve-env ... --name-transformer tf-var`; `doppler secrets --only-names` only;
the listing goes to a file, never stdout). The consumers are the precondition step (all three create-able names, driven by the
gate's creates file and the address-to-name map) and the post-apply re-read step. No other step reads Doppler names. The reader is
the only place a Doppler value-reading verb (`get`, `download`, `run` into the listing) could appear; the suite pins its absence.

**Mutation matrix.**

| # | Edit | Row that must go RED |
|---|------|----------------------|
| 1 | remove the abort when a name is present | B-names-present (key present must abort) |
| 2 | treat a failing reader (exit 3) as "no names", or read a header-only listing as "absent" (one row: both are "unreadable is not absent") | B-names-unreadable and B-names-empty (must abort) |
| 3 | check only the key address and skip the bucket and endpoint addresses, or swap two entries of the address-to-name map (a second member after a compliant first; one row, one map) | B-names-second (bucket present, key absent must abort) and B-names-map (each address aborts on its own name only) |
| 4 | print the listing to stdout instead of the file | B-names-log (the step output must hold none of the inherited-name sentinels) |
| 5 | add a `doppler secrets get` to the reader | T19 names-only (no value-reading verb) |

**Harness rows.** A `doppler` stub implements `run ... -- cmd` (exec) and `secrets --only-names`, and answers only to the provider token (a row proves the reader fails closed when it would otherwise use the ambient Tier-A `DOPPLER_TOKEN`); a must-pass non-canonical input is
a listing with a different order, extra inherited names and none of the three. The stub's own self-check proves it can emit both
a present and an absent verdict.

**Anchor.** Consistency only: the reader and the suite can be edited together, and nothing outside the commit holds the
precondition's stored value. The checker `scripts/check-web-host-escrow-config.sh --live` reads the same names by a different code
path, but it runs only later (the birth and replace jobs), so it is a later witness of the result, not an anchor of this check at
apply time.

### Guard 3 — the parity-test exemption: exactly one file may target the pair

**Property.** Apart from the `apply` job of `apply-web-platform-infra.yml`, the only workflow file that may `-target` a member of
the web-class passphrase pair is `apply-web-escrow-create.yml`, and only in the create-only shape: dispatch-only, five targets, no
`-replace`, the allow-set and the seven counters present, gate before apply.

**Assembly.** The parity-test rows that quantify over workflow files: the "NO other job" row (unchanged), the "NO other workflow
FILE" row (rewritten: every file except the apply workflow and the one exempt constant), the new structural row over the exempt
file, the instrument rows that prove the scan sees split-line flags, the main-root planner census (`MAIN_ROOT_TF_WORKFLOWS`, its
`found.length` assertion and the version-feed row). The exempt file is a single constant, `EXEMPT_PAIR_WORKFLOW`, so the exemption
cannot spread by editing a list.

**Mutation matrix.**

| # | Edit | Row that must go RED |
|---|------|----------------------|
| 1 | copy the escrow workflow to a second file name | the rewritten ban row (the copy is not exempt) |
| 2 | add `-replace=random_password.workspaces_luks_web` or a sixth `-target` to the exempt file (one row, one pin) | the exempt-file pin (targets) |
| 3 | add a `push:` trigger to the exempt file | the exempt-file pin (dispatch-only) |
| 4 | move the apply step above the gate in the exempt file | the exempt-file pin (order) |
| 5 | change `EXEMPT_PAIR_WORKFLOW` to another existing workflow name | the ban row (the real file is now banned) and the pin (the named file lacks the shape) |
| 6 | drop `apply-web-escrow-create.yml` from `MAIN_ROOT_TF_WORKFLOWS` | the census equality row |

**Harness rows.** The existing split-line instrument rows are kept; a must-pass non-canonical input: the exempt file with
different step names and extra comments still satisfies the structural pin, because the pin reads parsed structure, not text.

**Anchor.** The apply-job rows stay byte-identical (checked by diff at review), and the PR body flags the two edited rows. A
weakening PR must edit this file in a hunk reviewers can see; there is no WORM acknowledgement, so this guard proves
consistency, and says so.

## Implementation Phases

Order follows `cq-write-failing-tests-before`: the suite's rows come first and are red until the workflow exists.

### Phase 0 — failing suite skeleton (RED)

Create `apps/web-platform/infra/web-escrow-create-workflow.test.sh` modelled on `workspaces-plaintext-forget-workflow.test.sh`:
the `ok()`/`no()` instrument self-test, `set -uo pipefail`, a scratch dir with an `EXIT` trap, a python YAML pass for the
structural rows, then stub-driven behavioral rows, then the mutation battery, then the floor. Initially it fails because the
workflow is absent. Structural rows (T-numbers are referenced above):

- T1 the only trigger is `workflow_dispatch`; T2 inputs are exactly `confirm`, `reason`, `plan_only`; T3 `plan_only` is boolean with default `true`.
- T4 workflow-level `concurrency.group` equals the apply workflow's literal and `terraform-apply-web-platform-host`, `cancel-in-progress` is `false`; no job-level `web-1-swap`.
- T5 exactly one job, environment `infra-privileged`; T6 permissions are exactly `contents: read`; T7 `TERRAFORM_VERSION` equals the apply workflow's and `TF_VAR_terraform_version` equals it.
- T8 no `cf-tunnel-ssh-bridge`, no `TF_VAR_ci_ssh_private_key`, no `ssh`/`scp` at command position other than the dummy-key `ssh-keygen`; T9 the only Terraform verbs are `init`, `plan`, `show`, `apply` (no `state`, `import`, `taint`, `destroy`, `force-unlock`), no `sentry-heartbeat`, no `gh`.
- T10 exactly five `-target=` flags equal to the five addresses, no `-replace`, `-out=tfplan`; T11 the allow-set literal equals the same five; T12 the gate step ends the job on a violation; T13 the gate reads `plan_ok` and exactly the seven counters and requires each zero; T14 step order: validate < loader < extract < init < plan < gate < names < apply < reread < summary; T15 the header states first-create legality ends once a web-class volume is formatted (#9372 rebirth); T16 apply and re-read carry `if: inputs.plan_only != true` and nothing else carries a `plan_only` condition; T17 no step is enabled by `plan_only`; T18 no `hcloud_` token in any run body or target; T19 the reader holds no value-reading Doppler verb.
- T20 one hygiene row, a single loop over the parsed steps, replacing separate rows (plan review: collapse text-shape pins): every `run:` refuses xtrace (`case $- in *x*)`), no `${{ inputs.` inside a `run:` body (inputs reach the shell only through `env:`), every `doppler run` carries `--preserve-env`, no `upload-artifact`, no `tee`, no `continue-on-error`, `if:` only on apply, re-read and summary. T8, T9, T18 and T24 stay as the owner-listed pins ("absence of any hcloud_*", "no bridge/SSH", "apply of the saved plan") but are computed in the same parsed pass.
- T21 `Extract backend credentials` equals the `apply` job's step except for the deliberate heredoc-delimiter write (compared to the apply job, not to the forget workflow, which PR B deletes); T22 `terraform init -input=false -lockfile=readonly` in `apps/web-platform/infra`; T23 the reason is echoed to `GITHUB_STEP_SUMMARY`; T24 the apply step applies the saved plan `tfplan` with `-auto-approve` and no flag naming a resource.

Behavioral rows extract the `validate`, `gate`, `names` and `reread` step bodies and run them under stubs (`terraform` prints a fixture plan JSON for `show -json`; `doppler` per Guard 2): typo-guard accept and refuse (wrong token, blank reason, reason lands in the summary); gate happy path (five creates, subset, zero), and refusals (each row of the "If the real plan differs" table, including indexed and module-prefixed spellings, actions `[]`, missing array, `["no-op"]`/`["read"]` pass-through); names present, absent, unreadable, header-only, and the log-leak sentinel row; re-read success and the printed next step (the R2 credential mint, tracked on #9377, not Terraform); no output line carries a fixture secret.

### Phase 1 — the names reader

`scripts/web-escrow-create-names.sh <out-file>`: refuses xtrace; requires a non-empty `TF_VAR_doppler_token_tf` (fails closed, exit 2) and passes it as `DOPPLER_TOKEN` to that one `doppler` call (the ambient `DOPPLER_TOKEN` is the Tier-A token and cannot read the web-class config); lists `prd_workspaces_luks_web` with `doppler secrets --only-names -p soleur -c prd_workspaces_luks_web --no-check-version`, tokenises as `scripts/check-web-host-escrow-config.sh` does (requires the `NAME` header; empty or unrecognised output is exit 3, never "absent"); redacts any `dp.<kind>.<body>` shape in a failure line and keeps at most 300 bytes of it; writes names to the out-file only, never to stdout. Before writing it, the work phase checks whether adding a names-only mode to `scripts/check-web-host-escrow-config.sh` is smaller than a reader (plan review asked); the default is NOT to edit that checker or the preflight wrapper, because both are tested production-path scripts run by two birth jobs and this is a one-shot. The tokenise block is copied from the checker's `read_names` function (cited by name), not re-derived.

### Phase 2 — the workflow

`.github/workflows/apply-web-escrow-create.yml`, one job `create` (`timeout-minutes: 15`), steps in this order, every `run:` opening with the xtrace refusal:

1. Header comment: why a separate file (the apply workflow is `disabled_manually`, its whole-root plan carries unrelated replace drift, and the file is not edited); the sequence (plan-only dispatch, review the summary, applying dispatch, the R2 credential mint, then the web-host preflight); the first-create sentence ("first-create legality ends once a web-class volume is formatted (#9372 rebirth); after that a `create` of the key copy would overwrite a live secret and the live names precondition, not the plan gate, is what refuses it"); what the workflow does not do; this pipeline never dispatches it.
2. `Validate inputs (typo-guard)`: `confirm` must equal `CREATE-WEB-ESCROW`, `reason` non-blank, reason (printable-ASCII, 300 bytes) and `plan_only` echoed to the step summary; inputs enter through `env:` only.
3. `checkout`, `setup-terraform` (1.10.5, no wrapper), `Load infra credentials (tiered)` (no `github-app-runtime-token`), `Verify required secrets present`.
4. `Generate ephemeral SSH public key for var.ssh_key_path` (dummy, as the sibling arm: HCL evaluates `file()` at plan time regardless of `-target`).
5. `Extract backend credentials` (the apply job's step, heredoc-delimiter GITHUB_ENV form), `Terraform init` (`-lockfile=readonly`).
6. `Terraform plan` (step `env: DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}`, as in `ci_ssh_token_replace`; steps 8, 9 and 10 carry the same `env:`): `doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -no-color -input=false -out=tfplan -var="ssh_key_path=${CI_SSH_PUB}"` plus the five `-target=` flags, in the order of the allow-set.
7. `Plan gate` (id `gate`): `terraform show -json tfplan` to a runner-temp file; run the shared filter; require `plan_ok` true, every counter numeric (non-empty test before arithmetic) and zero; the allow-set check in jq with optional `.change.actions?` (anything not exactly no-op or read, and not an allowed address with exactly `["create"]`, is a violation, printed as address and verbs); print the table of non-no-op entries (addresses and verbs only); write the creates (addresses only) to a runner-temp file. A `doppler_config` entry gets its own message: "the web-class config is in state per the drift evidence; this workflow cannot import or create it; file an issue and decide a reviewed import" (review finding: an abort must name the next action). The error text for every other abort names the address, the verbs and the runbook subsection.
8. `Live names precondition` (id `names`, runs in plan-only too): `doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- bash scripts/web-escrow-create-names.sh <file>`; map each created `doppler_secret` address to its name (key to `WORKSPACES_LUKS_KEY`, bucket to `WORKSPACES_HEADER_BUCKET`, endpoint to `WORKSPACES_HEADER_R2_ENDPOINT`); abort if any such name is present, with the recovery decision rule in the message (see Phase 5); print per-name present/absent for the five names only.
9. `Apply the saved plan` (`if: inputs.plan_only != true`): `doppler run ... -- terraform apply -no-color -input=false -auto-approve tfplan`. An empty plan applies as a no-op, so there is no separate zero-creates branch (review finding: it falls out of "a subset passes"). The step's failure text says a re-dispatch plans and creates only the remainder, so a 403 after the random value reached state is not read as a dead end.
10. `Re-read the names and print the next step` (`if: inputs.plan_only != true`): the reader again; the three Terraform-managed names (not "the created names", since a re-dispatch may create nothing) must now be present, and the R2 pair's two names are reported present or absent; print the R2 credential mint as the next step, labelled as tracked on #9377 and not Terraform, and say the run being green does not mean the preflight will pass: the pair is unminted and unverified; no claim about encryption or scope.
11. `Summary` (`if: always()`, one step): `rm -f` of the saved plan and the plan JSON (one line; kept at the CLO's request although the runner is ephemeral and a create plan holds no password value, see decision-challenges.md), then a stage table of step outcomes (an empty outcome fails closed), the creates list, the plan-only/applying mode, and the next step.

### Phase 3 — mutation battery, floor, registrations

Mutation rows apply the Guard 1 and Guard 2 matrices to copies of the workflow (and of the reader), assert each edit landed (md5 change plus an exact changed-line count), and require the named row RED while the pristine control is all green. Pass floor: `WEB_ESCROW_MIN_PASS` set to the measured count, a literal on the line above its `-lt` test, reported by `printf` and `exit 1`. Register the suite: append to `suite-shard-legs.tsv` and `suite-durations.tsv` with `python3 scripts/regenerate-shard-manifest.py --group infra --incremental --write` (no timings fetched; the new row takes the floor weight); add the suite path to the LAST `PROMOTED_FILES=` assignment in `scripts/guard-vacuity-floor.test.sh` (the file assigns it four times; only the final one is live) with a comment block above it in the sibling entries' form, and keep the floor literal on the line directly above its `-lt` test so the per-file pin scores FIRES under the script's own neutering (a new floor-bearing suite in the deferred `apps/web-platform/infra/` directory would otherwise grow the shrink-only ledger).

### Phase 4 — the parity-test edits (flag both for explicit review)

In `plugins/soleur/test/terraform-target-parity.test.ts`:

- **Edit A.** Replace the body of "NO other workflow FILE -targets or -replaces either member of the pair" with: every workflow file except `apply-web-platform-infra.yml` and the single constant `EXEMPT_PAIR_WORKFLOW = "apply-web-escrow-create.yml"` must not target or replace either member (unchanged scan); and a new row asserts the exempt file's shape from parsed YAML (dispatch-only trigger, exactly the five targets with no `-replace`, the allow-set and counter names present, gate step index below the apply step index). The "NO other job in the workflow" row and every apply-job row stay byte-identical.
- **Edit B.** Add `apply-web-escrow-create.yml` to `MAIN_ROOT_TF_WORKFLOWS` and change `expect(found.length).toBe(3)` to `4`; the version-feed row then enforces `TF_VAR_terraform_version` parity for the new file.
- Conflict plan: #9348 also edits this file. Keep both edits as small localized hunks away from the helpers, rebase on `origin/main` before the review phase and again before marking ready, resolve by taking both sides, and re-run the file.

### Phase 5 — documents

- ADR-263 addendum (section in Architecture Decision above); no other ADR is edited.
- `web-host-birth.md` and `web-host-replace.md`: in each, a new additive subsection under Step 0 (so a textual conflict with #9474 stays contained) giving the order: (1) dispatch `apply-web-escrow-create` with `plan_only` left true and confirm the run actually started (a queued run can displace an older pending one); read the step summary: a green plan-only run means the five creates were graded and the names are absent, and nothing was written; (2) the applying dispatch (re-plans and re-grades with the same gates; compare its creates list with the plan-only one); (3) the R2 credential mint tracked on #9377 (not Terraform); until it is done the preflight fails with the checker's missing-R2-pair CAUSE line, which is expected and is not a fault of the apply; (4) the preflight must print `escrow-split-contract:live-ok`; (5) then the web-host dispatch; (6) after the first live apply, the CLO's measured supersession of the conditional wording (C4) and the re-read of the names, tracked on #9377. Correct the Step 0 sentence that attributes a missing name to "the push-apply has not created it" to name this workflow (the push-apply is disabled), without editing the checker's own CAUSE text. Each dispatch is stated as needing the owner's authorization. Wording per the CLO constraints above.
- The same subsections carry the **recovery decision rule for a names-present abort** (spec-flow review: an abort must not strand the owner). The reader proves a name exists, never its value, so the rule keys on whether a web-class volume could have been formatted. While no web-class volume is formatted (until #9372 runs; the readiness rows in Better Stack show it), the stray secret holds nothing keyed by it: remove it under the owner's authorization and re-dispatch. Once a web-class volume may be formatted, never remove or overwrite it: import it into state under a separate reviewed change and escalate on #9372 criterion 2 (passphrase-loss recovery). The same subsection names the two other aborts: a `doppler_config` create or update in the plan (file an issue; the config is imported or reconciled by a separate reviewed change; this workflow cannot) and a failing apply (re-dispatch; it plans only the remainder).
- C4 read and, if a gap is found, the edit (Architecture Decision, C4 views).

### Phase 6 — targeted verification (no full battery; CI owns it)

`bash apps/web-platform/infra/web-escrow-create-workflow.test.sh`; `bun test plugins/soleur/test/terraform-target-parity.test.ts`; `bash tests/scripts/test-infra-privileged-tier-census.sh` (edit only if it flags the new file); `bun test plugins/soleur/test/workflow-file-size.test.ts`; `bash scripts/guard-vacuity-floor.test.sh`; `bash .github/scripts/test/test-infra-suite-registration.sh`; `bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh`; `bash plugins/soleur/test/c4-count-parity.test.sh`; `bun test plugins/soleur/test/web-host-escrow-preflight-census.test.ts`; `bash scripts/lint-workflows.sh .github/workflows/apply-web-escrow-create.yml` (no new finding); `python3 scripts/lint-workflow-step-env-refs.py` and `scripts/lint-workflow-issue-write-scope.py` if they take a path; `python3 scripts/lint-guard-contract.py` over this plan. Nothing is dispatched, no workflow is enabled.

## Files to Create

- `.github/workflows/apply-web-escrow-create.yml`
- `apps/web-platform/infra/web-escrow-create-workflow.test.sh`
- `scripts/web-escrow-create-names.sh`

## Files to Edit

- `plugins/soleur/test/terraform-target-parity.test.ts` (Edit A and Edit B)
- `apps/web-platform/infra/suite-shard-legs.tsv`
- `apps/web-platform/infra/suite-durations.tsv`
- `scripts/guard-vacuity-floor.test.sh` (`PROMOTED_FILES` plus comment)
- `knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md` (appended addendum)
- `knowledge-base/engineering/operations/runbooks/web-host-birth.md`
- `knowledge-base/engineering/operations/runbooks/web-host-replace.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` (the `doppler -> hetzner` edge clause, unconditional) and its derived `model.likec4.json` (regenerated, never hand-edited); `views.c4` only if the three-file read finds an unmodelled element
- `tests/scripts/test-infra-privileged-tier-census.sh` (only if it flags the new file; none expected)

Not edited, by instruction: `.github/workflows/apply-web-platform-infra.yml`, `apps/web-platform/infra/server.tf`, any `git-data*.tf`, `hcloud_server.git_data`, the Terraform that defines the five resources.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1. `.github/workflows/apply-web-escrow-create.yml` parses; `on:` is exactly `workflow_dispatch` with inputs `confirm`, `reason`, `plan_only` (boolean, default true); one job `create`, environment `infra-privileged`.
- [x] AC2. The workflow-level concurrency group is the literal `terraform-apply-web-platform-host` with `cancel-in-progress: false`; no `web-1-swap` group.
- [x] AC3. The plan step has exactly five `-target` flags equal to the five addresses, no `-replace`; the gate allow-set is the same five; no `hcloud_` token appears in any step.
- [x] AC4. The gate requires `plan_ok` true and zero for the seven counters, applies the inverted allow-set, and runs before the apply, which applies the saved `tfplan` and carries `if: inputs.plan_only != true`.
- [x] AC5. The live names precondition aborts on a present name and on an unreadable listing, in plan-only and applying runs alike.
- [x] AC6. `bash apps/web-platform/infra/web-escrow-create-workflow.test.sh` exits 0 with every mutation row killed and the floor met; the suite is present in `suite-shard-legs.tsv`, `suite-durations.tsv` and `PROMOTED_FILES`, and `bash scripts/guard-vacuity-floor.test.sh` and `.github/scripts/test/test-infra-suite-registration.sh` pass.
- [x] AC7. `bun test plugins/soleur/test/terraform-target-parity.test.ts` passes; `git diff origin/main -- plugins/soleur/test/terraform-target-parity.test.ts` shows only Edit A (the "NO other workflow FILE" row) and Edit B (no hunk inside the apply-job rows or the "NO other job" row), and the PR body flags both for explicit review.
- [x] AC8. `test-infra-privileged-tier-census.sh`, `workflow-file-size.test.ts`, `c4-count-parity.test.sh`, `web-1-swap-concurrency-parity.test.sh` and `web-host-escrow-preflight-census.test.ts` pass; the census file is edited only if it flagged the new file (a flag is reported, not silently patched).
- [x] AC9. `git diff --name-only origin/main` contains none of `apply-web-platform-infra.yml`, `server.tf`, any `git-data*.tf`, `workspaces-luks-header-web.tf`.
- [ ] AC10. The pipeline dispatches nothing and enables nothing; the PR body states that each live step needs the owner's per-step authorization.
- [ ] AC11. The PR body uses `Refs #9377` and `Refs #8609`, never `Closes`; no agent `--admin` merge.
- [x] AC12. The ADR-263 addendum and both runbook subsections exist and obey the wording constraints: `grep -n -i -E "web-2 (is|will be) (LUKS|encrypted)|bucket-scoped"` over the added text returns no unqualified claim, and nothing not yet run is in the past tense.
- [x] AC13. `python3 scripts/lint-guard-contract.py` passes on this plan; `python3 scripts/lint-encryption-posture.py` still passes.
- [x] AC13b. The `doppler -> hetzner` edge no longer says only "the push-apply creates the key"; `plugins/soleur/test/c4-model-freshness.test.sh` and `apps/web-platform/test/c4-render.test.ts` pass.
- [x] AC13c. The retirement checklist (all coupled artifacts, see Risks R2) is posted as a comment on #9372 and linked from the ADR addendum.

### Post-merge (read-only; nothing is dispatched)

- [ ] AC14. `gh workflow view apply-web-escrow-create.yml` (or the unauthenticated API read of its `state`) reports `active`. Any dispatch, the R2 credential mint and the C4 supersession follow-through (CLO) are separate steps, each authorized by the owner and none performed by the pipeline.

## Test Scenarios

1. Valid dispatch, plan-only, real plan equals five creates: summary lists the five, names step reports all three names absent, run ends green without applying.
2. Same with `plan_only` false: apply creates five, re-read shows the three Terraform-managed names present and reports the R2 pair's two names, the next step is printed, plan files removed.
3. Re-dispatch after a green apply: zero non-no-op entries, the empty plan applies as a no-op, the re-read still reports the five names, still green.
4. Partial apply followed by re-dispatch: plan holds only the remainder, passes.
5. A key copy exists live with state not holding it: names step aborts naming the secret name.
6. Wrong `confirm` token, blank `reason`: the first step stops the run before credentials load.
7. Plan with a `doppler_config` create, a password `update`, a host create, an indexed address, empty actions, no `resource_changes`: each aborts at the gate with no apply.
8. A concurrent run of any applier of this root: queued behind the group; an older pending run is displaced (documented).

## Risks

- **R1. The real plan differs from the five creates.** Covered by the allow-set; the plan-only dispatch is the review. The failure mode of this gate is an abort, not data loss.
- **R2. A create after a web-class volume is formatted.** Legality of first-create ends at the #9372 rebirth. The control that survives that point is mechanical and already in the design: once the first apply lands the three names exist live, so every later `create` is refused by the live names precondition (it also refuses a hand-set value, and it cannot tell an inherited `prd` name from an own one, so an inherited name aborts too: a false positive that is safe). The workflow header and the ADR addendum say so. Retirement: the workflow is single-use and is deleted when #9372 completes; the work phase posts ONE checklist comment on #9372 naming every coupled artifact so none is forgotten: the workflow, its suite, the reader script, the suite's rows in both `.tsv` tables, its `PROMOTED_FILES` entry, the parity-test `EXEMPT_PAIR_WORKFLOW` constant and its `MAIN_ROOT_TF_WORKFLOWS` entry with the count back to 3. A self-expiring abort inside the workflow (checking whether #9372 is closed) was considered and declined: it needs a `gh` call and `issues: read`, which the suite pins absent, and it would block an owner-authorized dispatch if #9372 closed first.
- **R3. State-write loss in a cancelled apply.** The backend is lockless; the group serializes only GitHub runs. A cancelled apply can leave a Doppler secret that state does not hold, which the names precondition then refuses; recovery needs a person (state import or secret removal under review), outside this workflow.
- **R4. Concurrency displacement.** A run queued behind a running one displaces an older pending run in the group. The group is declared by exactly three workflow files today (`apply-web-platform-infra.yml`, `apply-deploy-pipeline-fix.yml`, `workspaces-plaintext-forget.yml`; `registry-host-replace-dispatch.yml` only mentions it in a comment and reaches it by dispatching the apply workflow), so a dispatch here can silently drop a queued run of any of those three. Measured read-only on 2026-10-04 (`gh api .../actions/workflows/<file> -q .state`): `apply-web-platform-infra.yml` is `disabled_manually`, but `apply-deploy-pipeline-fix.yml` and `workspaces-plaintext-forget.yml` are `active`, so a per-merge pipeline-fix run can be running or pending when this workflow is dispatched (it queues behind it, and a second queued run would displace the first pending one). Same exposure every sharer already has; accepted, stated in the workflow header and the ADR addendum, and the runbook step says to confirm the run actually started. A cancelled RUNNING apply (SIGINT then kill) is the real partial-state path and is R3. The work phase confirms that `git-data-rung2-rehearsal` (a different group) never writes the main-root state.
- **R4b. The seven shared counters are largely redundant under `-target`.** `host_creates` and `resource_deletes` cannot see untargeted resources; the allow-set is the real guard and the counters are defense in depth the owner asked for. A drift `update` on `doppler_config.workspaces_luks_web` aborts with no in-workflow remedy (a reviewed change decides).
- **R5. Passphrase on the runner.** The password exists in state and in the apply process for the life of the job; plan JSON for a create carries no password value (it is unknown at plan time) and is deleted anyway; no artifact upload; documented as a runner-local copy.
- **R6. Parity-test conflict with #9348.** Small localized hunks; rebase twice; both sides kept.
- **R7. Runbook conflict with #9474.** Additive subsections only.
- **R8. The R2 pair stays unminted.** The preflight keeps failing until the credential mint; the workflow says so and does not claim readiness.
- **R9. Accidental dispatch.** Typed confirm, `plan_only` default true, `infra-privileged` main-only policy (a dispatch from this branch cannot pass the environment gate), and the pipeline never dispatches.
- **R10. Provider token scope.** The apply uses the existing write-capable provider token; a read-only token for the names check is tracked at #9461 and is not part of this change.

## Non-Goals and deferrals

- The R2 access-key pair mint, its signed isolation proof, retiring the pre-split token, and passphrase-loss recovery stay on #9377 and #9372 (existing tracking; no new issue needed: criterion 2 of the #9372 comment and #7992 carry restore verification and state versioning).
- A `plan_only` entry in the tier census, a read-only Doppler token (#9461) and re-enabling push-apply are out of scope.

## Sharp Edges

- A `## User-Brand Impact` section that is empty or lacks the threshold fails `deepen-plan`; this one is filled and carries the threshold.
- The exempt-file pin in the parity test must read parsed structure, not text, or a harmless step rename reddens CI and a re-ordered text passes it.
- Every `doppler run` in the new workflow needs `--preserve-env` (tier census Guard 2) and no step may `doppler secrets get` a Tier-B name from `prd_terraform` (AC3); the reader script consumes the provider token only through the transformed environment (`TF_VAR_doppler_token_tf`).
- `doppler secrets` reads `DOPPLER_TOKEN`, not `TF_VAR_doppler_token_tf`, and the ambient `DOPPLER_TOKEN` (`secrets.DOPPLER_TOKEN`, the Tier-A `prd_terraform` token) cannot read `prd_workspaces_luks_web`: the reader sets `DOPPLER_TOKEN="$TF_VAR_doppler_token_tf"` for that one call only, and the workflow steps that wrap it in `doppler run` carry `env: DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}` exactly as the `ci_ssh_token_replace` plan step does. A suite row drives the reader with a stub that rejects any other token.
- `plan_only` must only ever subtract (census Guard 5 convention): the guard form is `inputs.plan_only != true` on mutating steps, and no step is enabled by it.
- A fixture plan must use real shapes (`["no-op"]` entries, `["read"]` data entries, `["create"]` with `change.after` omitting unknown values), not an empty array.
- The reason input is free text from the dispatcher: it reaches only the step summary, through `env:`, sanitized to printable ASCII.
