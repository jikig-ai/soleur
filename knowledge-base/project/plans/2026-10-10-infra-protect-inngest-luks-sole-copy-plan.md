---
title: "infra: protect hcloud_volume.inngest_redis_luks as the sole copy of the Inngest store (delete protection, edge pins, key-loss posture)"
date: 2026-10-10
slug: infra-protect-inngest-luks-sole-copy
branch: feat-one-shot-9879-luks-sole-copy-protection
issue: 9879
closes: 9879
type: infra
priority: p1
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

The Inngest Redis AOF now lives only on the LUKS volume `hcloud_volume.inngest_redis_luks`, opened by
one Doppler secret. Nothing at Hetzner or in Terraform refuses its deletion today. This plan adds
Hetzner-side delete protection, Terraform-side destroy refusal on the sole-copy edges, a mechanical
guard that scans effective Terraform text, and a recorded key-loss posture, while keeping the
sanctioned host-replace dispatch working.

## Research Insights

**Premise validation (Phase 0.6).** Held: #9879 is OPEN with no closing PR; the draft PR #9925 is this branch.
`hcloud_volume.inngest_redis_luks` exists on main with no `delete_protection` and no `lifecycle` block; the
live Hetzner object was read back with the read-only token (volume 106903269, attached to server 169426216,
`protection.delete=false`, size 10, hel1; the retired plaintext volume 106261946 answers `not_found`). The G4_PROTECTED
census entries exist (tests/scripts/test-infra-privileged-tier-census.sh, content anchor `G4_PROTECTED = {`).
Stale or corrected: (1) the brief says the `cloud-init-inngest.yml` pin is v1.1.47 with v1.1.48 unbumped; PR #9899 already
merged the bump (main pins v1.1.48 at both `IREF=` and `ZIREF=`), so the only remaining gap is that the live host still
runs the v1.1.47 user_data, which is the planned replace window (#9786) — not a bump PR. (2) The brief says the per-merge
apply delivers the in-place update. The volume is NOT in the per-merge `-target=` list (it is an
OPERATOR_APPLIED_EXCLUSION in plugins/soleur/test/terraform-target-parity.test.ts). It rides the per-merge plan only as a
dependency: `locals.inngest_luks_wrong_volume_alias` in apps/web-platform/infra/betterstack-logs-alerts.tf interpolates
`hcloud_volume.inngest_redis_luks.id`, and `logtail_exploration.inngest_luks_wrong_volume` is per-merge targeted. That is
an inference from Terraform targeting semantics and must be proven by a read-only targeted plan before merge (AC4).
(3) ADR corpus: the mechanism (delete protection + prevent_destroy on a sole-copy volume) is the accepted web-1 precedent
(ADR-119, ADR-263, #9348); ADR-142's "No key escrow" stance was already sharpened by the 2026-10-08 addendum (O4). Nothing
here is a rejected alternative.

**Property List (Phase 0.6b).**

- P1. Hetzner refuses a DELETE of volume 106903269 from every client until protection is lifted in a reviewed apply.
- P2. No Terraform plan on any path can destroy or replace the volume or the passphrase pair.
- P3. The attachment can be replaced ONLY as part of a gated server replace (the sanctioned `inngest-host-replace`), never alone.
- P4. No dispatch, workflow step, `removed {}` or `moved {}` block can reach the sole-copy addresses by a spelling the guards do not normalize.
- P5. The loss modes of the opener (INNGEST_REDIS_LUKS_KEY) are enumerated with a recovery stance each, and the claims are mechanically checked where a check exists without a host change (pins, single-writer row, drift plan, post-merge read-back).

**Cut List (Phase 0.6b).**

- `prevent_destroy` on the attachment (the web-1 B4-9 row) -> buys P3 -> CUT: it makes `-replace` a plan error and breaks
  `inngest-host-replace`; the existing gates already bind the attachment replace to a server replace.
- Widening `inngest-host-replace-gate.sh` / `inngest-host-shape-gate.sh` to tolerate a pending `delete_protection` update
  -> buys "first replace right after merge" -> CUT: the per-merge apply lands the update first; a fail-closed abort with a
  named reason is the safe behaviour; documented in the runbook instead.
- A new header off-host backup or an on-host `luksOpen --test-passphrase` continuity probe -> buys P5 -> DEFERRED, not cut:
  both edit cloud-init user_data, which force-replaces the sole scheduler (no `ignore_changes=[user_data]`).
- A new reviewer-gated dispatch for lifting protection -> buys "deliberate unprotect path" -> CUT: lifting is a reviewed PR
  (delete_protection first, prevent_destroy second); a dispatch would be a new path to the very edge being closed.
- A repo-wide single-writer scan of workflows/scripts for Doppler write verbs (was Guard 4) -> buys P4 for the key -> CUT after
  plan review: the 12h drift plan already shows any live second writer, and a `.tf`-only single-writer row inside Guard 1 keeps
  the part that is deterministic.
- A new read-back probe script with its own suite, `test-all.sh` line and `BASELINE_DECLARED_PROBES` bump -> buys the live
  read-back -> CUT after plan review: four files for one boolean; the runbook carries the one-line wrapped command and
  `soleur:postmerge` runs it; the discoverability command reads the declared pin instead.
- A draft CLO audit file for this PR, the two sibling Article 30 cross-references, and a Doppler version-history measurement in
  the PR -> CUT after plan review (inferred, nothing consumes them); the measurement moves to the deferral issue; the CLO's
  audit-file suggestion is recorded as a decision for the user.
- A new passphrase escrow copy (R2/other) -> CUT: ADR-142 and the destruction record rejected it on confidentiality grounds;
  two independent copies already exist (Doppler secret, Terraform state value).

**Existing mechanisms reused (grepped, not assumed).**

- apps/web-platform/infra/workspaces-luks.tf + workspaces-luks.test.sh Guard B4: effective-text lexer (`strip_comments`,
  brace-depth block extraction, `*override.tf` / `*.tf.json` refusal, mutation battery, floor 61). Inline in the suite today.
- tests/scripts/lib/inngest-host-replace-gate.sh and inngest-host-shape-gate.sh: per-address permitted-action tables.
- plugins/soleur/test/terraform-target-parity.test.ts: B5/B6 pin the pair and the attachment/volume targeting; G1 is the
  retired-address reachability census template.
- tests/scripts/test-infra-privileged-tier-census.sh: G4_PROTECTED (4 inngest + 2 workspaces + App identity), G4f, G4a-G4g.
- scripts/encryption-posture-ledger.json row `hcloud_volume.inngest_redis_luks` (does_not_defend names #9879);
  knowledge-base/engineering/architecture/diagrams/model.c4 inngest container description ("protection ... tracked in #9879").
- scheduled-terraform-drift.yml: full-root `terraform plan -detailed-exitcode` every 12h (detects lifted protection and a
  deleted or diverged Doppler key copy as drift).

**Institutional learnings applied.**

- 2026-10-01 the-guards-i-wrote-to-protect-the-sole-copy-scanned-a-shape-the-attack-did-not-take: enumerate every
  operation that makes the data unreachable; guard effective text, not a serialization; pin the edge, not only the node.
- 2026-10-09 a-probe-loop-left-its-last-value-in-the-committed-floor-and-a-rebase-orphaned-the-attested-sha: probe mutations on
  a scratch copy of the suite, read every floor back before commit, never rebase after an attestation names commit ids.
- 2026-09-27 an-import-block-breaks-terraform-test... and ADR-006 caveat: import of `random_password` is unverified for this
  class; do not state re-import as a recovery procedure.
- 2026-09-19 apply-workflow byte limit (512000, gate 490000): this plan edits NO workflow file, by design.
- 2026-07-24 guest-luks-store-must-gate-consumer-on-mount: pin the halt, not token presence (applies to the guard rows).

**Domain findings carried into the plan** (full text under `## Domain Review`): CTO — protect the Doppler cascade parents,
`moved{}` joins the census rule, record the Hetzner project-deletion and ciphertext-has-no-backup residuals, and the
host token's `read/write` access is a delete vector whose fix is a ForceNew host replace (deferred); CLO — recite the sole
copy and the accepted residual in the Article 30 register and compliance posture now, do not edit the attested destruction
records, write every merge-dependent sentence conditionally; CPO — agree `single-user incident`, require an
untested-path proof that protection does not block host replace, a read-back after apply, and a written unprotect path.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "applied by the merge's per-merge apply" | The volume is an OPERATOR_APPLIED_EXCLUSION, not in the per-merge `-target=` list; it rides the per-merge plan as a dependency of the targeted `logtail_exploration.inngest_luks_wrong_volume` (alias local). Inference, not measurement. | Phase 0 proves it with a read-only plan built from the real per-merge `-target` list and NO volume target; if the closure does not contain the volume the plan STOPS and is re-planned (a per-merge volume target is a design change, not an inline branch). |
| "the inngest pin ... is v1.1.47 while tag vinngest-v1.1.48 is merged (check for an existing bump PR)" | PR #9899 merged the bump 2026-10-10T00:27:42Z; main pins v1.1.48. | No bump work. Note only: the live host still runs v1.1.47 user_data, so a full-root plan shows a pending server replace; every plan in this PR is TARGETED and the runbook says never to run an untargeted apply. |
| "pins ... on the volume or its attachment/passphrase pair" (web-1 precedent pinned the attachment) | Copying `prevent_destroy` onto the attachment would plan-fail `inngest-host-replace` (ForceNew server_id). | Attachment is deliberately unpinned in HCL; its protection is the existing gate rows plus the extended reachability pins; the guard suite pins the ABSENCE and carries a must-PASS row. |
| "G4_PROTECTED ... extend, do not duplicate" | G4_PROTECTED guards only INTENDED_DESTROYS / RETIRED_STATE_ABSENT entries (G4f); nothing stops a `removed{}` or `moved{}` block naming a protected address. | Extend G4_PROTECTED with the two Doppler parents and add one census row (G4h) over `removed`/`moved` blocks; no second list. |
| "key-loss posture ... mechanically checked" | ADR-142's "No key escrow" rationale (transient AOF) is contradicted by its own 2026-10-08 addendum; R2 state has no versioning or PITR (ADR-006 correction); an on-host key-continuity probe (precedent registry-luks-escrow, #8408) needs cloud-init, i.e. a host replace. | Record the stance and the loss-mode table; mechanically check what exists without a host change (prevent_destroy, drift plan, a `.tf` single-writer row, the post-merge read-back); defer the on-host probe and header backup with a dated trigger. |

## Problem Statement / Motivation

With the plaintext backstop gone (destroyed 2026-10-09), losing `hcloud_volume.inngest_redis_luks` or its sole opener is
unrecoverable data loss for every armed reminder and in-flight job payload. Today a single mistaken plan, `removed {}`
block, console click or API call deletes the volume, and no layer refuses. Web-1's equivalent store got four guards after
the fact (#9348); this store gets them before anything goes wrong, with one structural difference: its attachment must stay
replaceable.

## Proposed Solution

Five layers, each pinning a different edge (the 2026-10-01 learning: enumerate every operation that makes the data
unreachable, pin each, guard the effective text).

1. **Hetzner-side:** `delete_protection = true` on the volume.
2. **Terraform-side:** `lifecycle { prevent_destroy = true }` on the volume, the passphrase pair, and the two Doppler
   cascade parents (`doppler_project.inngest`, `doppler_environment.inngest_prd`). NOT on the attachment.
3. **Guards over effective text:** a new suite scanning the HCL (lexer shared with web-1's Guard B4 via an extracted
   library, not copied); the existing B5/B6 reachability pins extended in `terraform-target-parity.test.ts`; census row G4h
   plus the extended `G4_PROTECTED`.
4. **Key-loss posture:** new ADR (canonical loss-mode table) + ADR-142 pointer addendum + runbook section + Article 30 /
   compliance-posture recitation; the post-apply read-back is a wrapped one-line read in the runbook run by `soleur:postmerge`.
5. **Records that would otherwise lie:** the encryption-posture ledger row and the C4 container description both say
   "protection ... tracked in #9879".

### Edge enumeration (every operation that makes the store unreachable)

| # | Operation | Reaches the store via | Pin after this PR | Layer |
|---|---|---|---|---|
| 1 | Delete the volume at Hetzner | API, CLI, console, any token | `delete_protection = true` | Hetzner |
| 2 | Destroy / replace the volume in a plan | per-merge apply, `inngest-host`, any local run, `-replace=`, taint, ForceNew edit (size shrink is refused by Hetzner; `location` edit) | `prevent_destroy` on the volume | plan time |
| 3 | Forget the volume from state | `removed {}` block, `terraform state rm` | census G4h; `forget` counted by both dispatch gates; parity test pins zero state-writing workflows | CI + gates |
| 4 | Rename the address (state-only) so the pins stop applying | `moved {}` block | census G4h (`from` or `to`) | CI |
| 5 | Detach the volume (attachment destroyed alone) | `-target`/`-replace` of the attachment, a `removed {}` | gates: replace only with `inngest_server_replaced==1`, shape gate no-op or create only; extended reachability pins: exactly two jobs name it | gates + CI |
| 6 | Detach via host replace | `inngest-host-replace` | SANCTIONED; unchanged; proven by a gate-library replay that still PASSes | gate |
| 7 | Regenerate the passphrase | taint, `-replace=`, state loss, destroy | `prevent_destroy` on the pair; existing `luks_passphrase_rotations` HALT (per-merge) and `luks_passphrase_in_graph` (dispatches) | plan time + gates |
| 8 | Delete the Doppler secret outside Terraform | Doppler API/CLI/console, any write-capable token (host token `inngest-boot` is `read/write`) | cannot be prevented; DETECTED by the 12h drift plan; recoverable (value lives in state) | residual |
| 9 | Cascade-delete the secret by replacing its parent | replace/destroy of `doppler_environment.inngest_prd` or `doppler_project.inngest` | `prevent_destroy` on both parents | plan time |
| 10 | A second Terraform writer for `INNGEST_REDIS_LUKS_KEY` on prd | a new `doppler_secret` in the root | single-writer row in Guard 1; a live non-Terraform write shows in the drift plan | CI + drift |
| 11 | A retired dispatch still reaching the addresses | stale `apply_target` option or job | reachability census names the only legal (job, verb, address) triples | CI |
| 12 | Hetzner project deletion / account loss | provider side | NOT covered; stated as residual (CTO: whether protection blocks project deletion is unverified) | residual |
| 13 | Detach through an untargeted full apply | a local or dispatched full-root apply replaces the server and its attachment (the live host's user_data is stale, so a full plan shows a server replace) with no gate running | runbook: never untargeted; residual (the volume itself stays pinned by `prevent_destroy` and delete protection) | residual |
| 14 | Revoke the opener's access path | revoking or replacing `doppler_service_token.inngest` (the host's read/write boot token) strands a reboot until the replace flow re-delivers it | not pinned here (replacing it is part of the sanctioned replace flow); recited as residual | residual |

### Key-loss posture (decision, with recovery stance per mode)

No new escrow artifact is created by this PR. Independent copies of the opener today: the Doppler secret
(`soleur-inngest/prd`) and the Terraform state value `random_password.inngest_redis_luks.result` (R2 backend, no
versioning, no point-in-time recovery — ADR-006 correction). The LUKS header has no off-host copy
(`cloud-init-inngest.yml` says so). Escrow of the header or passphrase to a third store was rejected on confidentiality
grounds (ADR-142; destruction record) and stays rejected here; reopening it is a legal decision, not an engineering default.

| Loss mode | Detection | Recovery stance |
|---|---|---|
| Doppler secret deleted | 12h drift plan (create planned) | A create of the Doppler copy alone is legal on the per-merge path and restores the state value; the next merge apply or a `manual-rerun` dispatch re-creates it. |
| Doppler secret overwritten with another value | 12h drift plan (update planned) | The per-merge guard HALTs on any update of the pair (correctly: it cannot tell repair from rotation), so there is no automated repair route. Recovery is Doppler version history (retained per secret on paid tiers; the plan tier and the rollback scope are NOT measured here and are carried by the deferral issue; never print diffs, they carry plaintext). The owner of this repair is the repository owner; the procedure is written in the runbook section. Automated repair dispatch is DEFERRED (tracking issue). |
| Terraform state entry lost | next plan shows create of the passphrase | Re-import is unverified for this resource class (ADR-006 caveat, `special=false` import plans a replacement). Doppler copy is the only live opener; the per-merge HALT blocks the create. Owner: repository owner, who decides the repair; do not apply; the import rehearsal in the rehearsal root is DEFERRED to the tracking issue and re-import is not claimed as a recovery until it passes. |
| Both copies lost | none possible | Total loss of the store; accepted residual, recited in the register (CLO). |
| LUKS header corrupted | the hourly probe row proves device binding, not the cipher, so detection lags to the first Redis failure (existing wrong-volume alert; dead-man's switch #9703, not yet armed) | No recovery; header backup DEFERRED to the planned host-replace window with a dated trigger (CTO: "next replace" alone is not a date). |
| Hetzner volume deleted despite protection / project loss | none | No recovery; residual. |

## Technical Considerations

- **Delivery of the in-place update.** `delete_protection` is an optional boolean on `hcloud_volume` (provider 1.63.0,
  lock-pinned); treated as an in-place update, confirmed by the Phase 0 plan. `prevent_destroy` changes no plan by itself.
- **Interaction with the dispatch gates (fail-closed, intended).** `inngest-host-replace-gate.sh` and
  `inngest-host-shape-gate.sh` abort `luks_volume_touched` on any update of the volume, and the volume is a dependency of
  the attachment target. Until the merge's apply lands the update, a host-replace dispatch aborts with a named reason. Not
  widened (Cut List); the runbook orders merge-apply before any replace, and the Phase 3 replay proves a post-apply plan
  (volume no-op) still PASSes.
- **Ordering trap (copied from web-1, adapted).** To lift protection deliberately: lift `delete_protection` first in its
  own reviewed change, then remove `prevent_destroy`. Removing `prevent_destroy` alone lets a destroy apply detach the
  mounted volume before Hetzner refuses the delete (provider `resourceVolumeDelete` detaches then deletes).
- **A future key rotation** (header `luksChangeKey`) needs `prevent_destroy` lifted on the pair in the same reviewed change;
  the comment on the pair says so.
- **No workflow file is edited** (byte-limit gate 490000 on apply-web-platform-infra.yml; learning 2026-09-19). The
  reachability pins read workflows, they do not change them.
- **Refusal text points somewhere.** Each new refusal's comment (the `.tf` lifecycle comments, the guard failure messages)
  names the runbook section; a deliberate change goes through that section's reviewed two-step route.
- **Drift caveat.** The full-root drift plan is already non-empty (pending server replace until #9786), so the drift signal
  for this PR's pins is a read of the named addresses in the plan text.
- **Infrastructure (IaC) apply path:** per-merge apply (CI) of one in-place update on a live volume; no downtime, no detach,
  no reboot, no host replace. Not a cloud-init change (`user_data` untouched, so `hcloud_server.inngest` is not replaced).
  Provider pin and lock unchanged. No new secret, token or variable.
- **NFR impact:** durability / recoverability of the Inngest store (nfr-register); no performance impact.

<!-- lint-infra-ignore start: describes the production-write gate and the authorization the plan must obtain; prescribes no human-run infra step (the apply is CI; the human supplies only the go-ahead) -->
## Production Write Gate

**Does merging this alone mutate production? Yes — and the PR body's first line must say so.** `apply-web-platform-infra.yml`
fires on any push touching `apps/web-platform/infra/**` (its `paths:` filter; the rehearsal and git-data-root-key sub-roots are
negated out), the per-merge job needs no further dispatch, and the merge is the authorization act. Workflow census for the
two edited `.tf` files: `apply-deploy-pipeline-fix.yml` lists explicit script paths (no `inngest-*.tf`) and its `-target` graph
is web-1 `terraform_data` only; `apply-sentry-infra.yml`, `apply-github-infra.yml`, `apply-inngest-rls.yml` watch other trees;
`scheduled-terraform-drift.yml` is plan-only. So one workflow applies this change, and the only plan delta it can carry is the
volume's in-place update.

The only production write is one in-place update (`delete_protection` false -> true on volume 106903269), applied by the
merge's per-merge apply. The PR is NOT merged, and is not put through the merge queue, until all of the following exist:

1. **Evidence plan built from the REAL per-merge target set.** A read-only plan (`-lock=false`, state read only, read-only
   Hetzner token as `TF_VAR_hcloud_token`, throwaway ssh public key for `var.ssh_key_path`) whose `-target` list is extracted
   mechanically from the per-merge `plan` step of `apply-web-platform-infra.yml` (the same list CI will use, ~70 targets) and
   carries NO `-target` on the volume, so the volume update appears only if the dependency closure really delivers it. Saved as
   `knowledge-base/project/specs/feat-one-shot-9879-luks-sole-copy-protection/apply-plan-output.md` (human plan + JSON) and
   showing exactly: one `hcloud_volume.inngest_redis_luks` in-place update (`delete_protection: false -> true`), zero other
   in-place updates, zero adds, zero destroys, nothing at web-1's volume 106443278, and `hcloud_server.inngest` ABSENT from the
   plan (its pending user_data replace is not in the per-merge closure; assert that explicitly).
2. The per-merge guard logic is replayed over the saved JSON: `destroy-guard-filter-web-platform.jq` prints every counter 0 and
   the workflow's own halt conditions (rotation HALT, host-creates HALT, destroy count) evaluate to pass.
3. The exact command and output are quoted to the user, who gives an explicit per-command go-ahead for the merge. A menu
   answer is not an authorization (`hr-menu-option-ack-not-prod-write-auth`). Because state and main can move through the merge
   queue, the go-ahead is bound to "one update, nothing else"; a delta at apply time is an abort, not a proceed.
4. The squash message and PR body carry no `[skip-web-platform-apply]` marker (it would skip the apply and leave the dispatch
   gates aborting `luks_volume_touched`).
5. Read-back after the apply (executor: the `soleur:postmerge` verification step; a failed read-back is a red post-merge
   status, not a note): a read-only Hetzner GET of volume 106903269 returns `protection.delete=true`, run as
   `doppler run -p soleur -c prd_terraform -- sh -c '<curl with the read-only token>'` (the quoted wrapper form: a bare
   `"$VAR"` argument expands in the caller's shell before Doppler sets it). That read is a proxy for "Hetzner refuses a
   delete"; the refusal itself is not exercised here.

**If the apply is skipped or fails mid-merge:** the sanctioned delivery route is a `manual-rerun` dispatch of
`apply-web-platform-infra.yml` (the same per-merge job). The `inngest-host` dispatch is NOT a delivery route (its shape gate
refuses an update on the volume). Until the update lands, a host-replace dispatch aborts `reason=luks_volume_touched`; that is
the intended fail-closed behaviour, and an emergency replace in that window needs the apply to land first.

**Contingency if the evidence plan does NOT show the volume update (closure inference wrong): STOP and re-plan.** Adding a
per-merge `-target` on the volume would make the per-merge job a third writer of the sole copy and gives it a create path,
edits a workflow (byte-limit gate 490000), removes the volume from OPERATOR_APPLIED_EXCLUSIONS, changes the Guard 2 expected
set (seven lines become eight) and the B5/B6 pins, and leaves a delete covered only by the ack-able destroy counter (the
un-ackable rotation HALT covers the passphrase pair only; `prevent_destroy` would be the sole remaining brake). That is a
design change that needs its own review, not an inline branch.

**R2 caveat (first live proof is the first replace).** Detach of a delete-protected volume during the sanctioned
`inngest-host-replace` is documented only indirectly (client docs list no protection precondition on detach; the repo's web-1
note cites provider source). This PR does not perform a replace and must not. The first replace after merge is the live proof,
so a failure there is not to be misread as this PR's regression. Whether to spend a scratch volume to prove it earlier is a
user decision (it is a billable production write), recorded in `decision-challenges.md`.
<!-- lint-infra-ignore end -->

## User-Brand Impact

- **If this lands broken, the user experiences:** a stalled or late host replacement (the sanctioned dispatch plan-fails or
  aborts), so scheduled reminders and agent runs fire late; worst case, protection is stripped in a hurry and the original
  exposure returns. Nothing is lost by this change itself.
- **If this leaks, the user's workflow data is exposed via:** nothing new. The volume stays LUKS-encrypted; no secret is
  printed, copied or escrowed by this change; the read-back probe prints a boolean only.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one lost queue silently drops one user's armed reminders and in-flight work with
  no notice, which is a per-user trust failure; CPO assessed and agreed, and did not go higher because this is a durability
  gap, not a data exposure.

## Observability

```yaml
liveness_signal:
  what:            "declared pins: delete_protection and prevent_destroy on the volume, prevent_destroy on the pair and the two Doppler parents, checked in effective HCL by the guard suite on every PR; live state: scheduled-terraform-drift.yml full-root plan (a lifted protection or a changed key copy is a pending update at a named address)"
  cadence:         "per PR (guard suite) and every 12h (drift plan)"
  alert_target:    "red PR check; the drift workflow's tracking issue"
  configured_in:   "apps/web-platform/infra/inngest-luks-sole-copy.test.sh; .github/workflows/scheduled-terraform-drift.yml"

error_reporting:
  destination:     "GitHub Actions run logs, drift tracking issue (layer 6); guard suites fail the PR check run"
  fail_loud:       "plan-time error 'Instance cannot be destroyed' on any destroy/replace plan of a pinned address; named reason= tokens from the two dispatch gates; census row G4h RED"

failure_modes:
  - mode:          "protection lifted at Hetzner outside Terraform"
    detection:     "drift plan shows delete_protection true -> false pending at hcloud_volume.inngest_redis_luks. CAVEAT: the live host still runs stale user_data, so the full-root drift plan is already non-empty (pending server replace) until the next planned replace (#9786); the detector for THIS mode is therefore a diff of the named addresses in the drift plan output, and a new reason is not distinguishable from the existing issue by exit code alone"
    alert_route:   "drift tracking issue (read the plan text for the address)"
  - mode:          "Doppler key copy deleted or overwritten"
    detection:     "drift plan shows create/update at doppler_secret.inngest_redis_luks_key (same caveat)"
    alert_route:   "drift tracking issue"
  - mode:          "a plan, removed/moved block or workflow flag targets a pinned address"
    detection:     "plan-time prevent_destroy error; census G4h; reachability census in terraform-target-parity.test.ts"
    alert_route:   "red PR check / red apply job"
  - mode:          "host-replace dispatch aborts luks_volume_touched because the update is not yet applied"
    detection:     "reason=luks_volume_touched in the dispatch gate output"
    alert_route:   "dispatch run summary; the runbook section names the ordering and the manual-rerun delivery route"
  - mode:          "LUKS header corrupted or key divergent"
    detection:     "the hourly probe row proves device binding, not the cipher, so detection lags to the first Redis failure; the real detectors are the existing wrong-volume alert and the dead-man's switch (#9703, not yet armed)"
    alert_route:   "existing Better Stack alerts"

logs:
  where:           "GitHub Actions run logs for the per-merge apply, the dispatches and the drift workflow"
  retention:       "GitHub Actions default retention"

discoverability_test:
  command:         grep -c -e 'delete_protection = true' apps/web-platform/infra/inngest-redis-luks.tf
  expected_output: 1
```

The discoverability command reads the DECLARED pin (the single code line; comments in the file must not spell the literal
`delete_protection = true`, which the guard suite also asserts). The LIVE property is read by the post-merge read-back in the
Production Write Gate and by the runbook's one-line recipe.

## Encryption Posture

```yaml
at_rest:
  - store:            hcloud_volume.inngest_redis_luks
    mechanism:        luks
    evidence:         "scripts/encryption-posture-ledger.json row hcloud_volume.inngest_redis_luks (device_binding volume+attachment+mapper inngest-redis); apparatus apps/web-platform/infra/cloud-init-inngest.yml luksFormat/luksOpen; key pair co-located in apps/web-platform/infra/inngest-redis-luks.tf"
    defends_against:  "a seized, RMA'd or snapshot-imaged Hetzner volume: the AOF is unreadable without the Doppler-held passphrase"
    does_not_defend:  "a leaked credential; an app-layer read on the unlocked host; loss of the key or header (no second copy of either off-host); deletion, which this change addresses with delete_protection and prevent_destroy but not with a backup"
    disclosed_as:     "not-publicly-claimed"
    live_verification: "unavailable:the hourly probe row proves which device backs /mnt/data, not the cipher; unchanged by this PR"
in_transit: []
```

No new store and no new connection; the ledger row's `does_not_defend` text is updated (Phase 4) so it stops saying protection is tracked in #9879.

## Architecture Decision (ADR/C4)

### ADR

Create a SHORT NEW ADR (standing policy, not a migration addendum): "sole-copy LUKS volume protection set" — the decision that
a sole-copy store gets `delete_protection` plus `prevent_destroy` on the volume, the passphrase pair and the Doppler cascade
parents, and that the attachment stays deliberately unpinned where a sanctioned dispatch replaces it (inngest), in
contrast to web-1 (ADR-263, ADR-119), where the attachment is pinned because its replace dispatch refuses web-1 by name. It
cross-references ADR-263, ADR-119 and ADR-142, and carries the key-loss loss-mode table as its single canonical copy (the
runbook links to it, the plan does not restate it). The ordinal is PROVISIONAL: probe `origin/*` refs for the next free
number at write time and again immediately before merge (current highest on main: ADR-281). Add a divergence note to ADR-263.
Amend ADR-142 with a short dated pointer addendum only: supersession marks for the "No key escrow ... transient and
self-healing" rationale and for the "NOT built here ... #9879 (open)" bullet, with every merge-dependent sentence
conditional ("fires on the merge of PR #N"). The "reminders re-armable from Postgres" claim is verified before it is restated.

### C4 views

Container view: `platform.infra.inngestRedis` description in `diagrams/model.c4` says "protection for the sole copy is
tracked in #9879" — falsified by this change; rewrite to state the protections and the residuals. Elements/edges checked
against all three files (`model.c4`, `views.c4`, `spec.c4`) at work time: external system Hetzner (`hetzner` container,
`github -> hetzner` control-plane edge), external system Doppler (`doppler -> inngest` boot-credential edge for the isolated
`soleur-inngest` project), Cloudflare R2 (terraform state), GitHub (apply and drift), human actor `founder` (per-command
go-ahead). No new element or edge; the `inngestRedis` view include is unchanged. Re-run
`plugins/soleur/test/c4-count-parity.test.sh` and the C4 syntax/render tests, and regenerate `model.likec4.json`
(`scripts/regenerate-c4-model.sh`, lefthook re-stages it).

### Sequencing

The ADR describes the target state ("status: adopting") until the merge's apply lands and the read-back passes.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (advisory sign-off only)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Leaving `prevent_destroy` off the attachment is correct (the web-1 attachment is pinned only because its
host-replace refuses web-1 by name). Findings applied: protect the Doppler cascade parents (a `-target`ed replace of the
environment cascade-deletes the secret without planning its destroy, so `prevent_destroy` on the secret alone would not
fire); add `moved {}` to the census rule; `prevent_destroy` on the pair is safe for the per-merge apply (destroy already
trips the rotation HALT; create of the Doppler copy alone stays legal; the rehearsal root is a separate state with its own
key); record residuals (Hetzner project deletion unverified, ciphertext has no backup, host token `inngest-boot` is
`read/write`). Findings NOT applied here: downgrading the token to read-only is ForceNew (token `.key` feeds `user_data`),
i.e. a host replace, so it rides the deferral issue; a header backup without `user_data` change was checked and no
host-side delivery path exists for the inngest host (the SSH-installed probes target web-1).

### Legal (CLO)

**Status:** reviewed
**Assessment:** Adequate for the O4 caveat only if recited and framed as an accepted residual, not as mitigated. Edit in THIS
PR: Article 30 register (the Inngest processing activity: add a numbered TOM for sole copy and sole opener, and a dated pointer
in its (e) row; the CLO's one-line cross-references in the two sibling entries were cut at plan review), compliance-posture row
for the destroyed backstop (append a dated bracket), ADR-142 addendum with supersession marks. Do NOT edit
`inngest-aof-backstop-destruction-record.md` (attested, status complete), `inngest-aof-destruction-record.md` or
`2026-09-counsel-review-8248.md`. Art. 17: protection does not complicate per-subject erasure; whole-volume erasure now needs
a deliberate unprotect and no sanctioned erase path exists since PR B — say so; do not claim crypto-erasure (key copies sit
in Doppler and state). Check `docs/legal/` and its mirror for an availability claim; if none changes, the #7387 gates stay
out of play. The CLO's separate draft audit file for this change was cut at plan review and is recorded as a decision for the user.

### Product (CPO)

**Status:** reviewed
**Assessment:** Agrees with `single-user incident`. Conditions: explicit per-command go-ahead for the production write; a
read-back after the apply; no SSH in the runbook; the key-loss posture states plainly that losing the opener means losing the
queue; the runbook carries a deliberate reviewed unprotect path; the guard suite proves the replace dispatch still works with
protection on. No UI surface: Product/UX tier is none and no wireframe applies.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "(a) delete_protection = true on the volume" [brief] | Phase 1 volume block; AC1 | mapped |
| 2 | "(b) pins/guards so no dispatch (workflow_dispatch, destroy/taint/replace paths) can target the volume or its attachment/passphrase pair" [brief] | Phases 1-3; edge table rows 2-7, 9-11; Guards 1-3 | mapped |
| 3 | "the pin MUST NOT break the legitimate inngest_host_replace flow, which replaces the attachment" [brief] | attachment left unpinned; Guard 1 must-PASS row; Phase 3 gate replay; AC3 | mapped |
| 4 | "(c) a key-loss posture for INNGEST_REDIS_LUKS_KEY (escrow/recovery stance, documented and, where possible, mechanically checked)" [brief] | key-loss table (ADR); Phase 4 ADR/runbook/register; Guard 1 single-writer row; runbook read-back recipe | mapped |
| 5 | "extend, do not duplicate" [brief] | Phase 2 extends G4_PROTECTED and adds G4h; extracts the lexer to one library | mapped |
| 6 | "surface the exact apply/plan output and get the operator's per-command go-ahead" [brief] | Production Write Gate; AC4-AC6 | mapped |
| 7 | "NEVER touch web-1's LUKS volume 106443278 (sole copy)" [brief] | Files list excludes workspaces-luks.tf; AC8 asserts the plan touches no web-1 address | mapped |
| 8 | "Explicitly out of scope: web-2 workspaces volume, git_data volume, rehearsal volume, ADR-198 baked credentials." [brief] | none of the four is edited; AC8 | mapped |
| 9 | "Follow-up queue after this PR (separate runs, in order, do not start here)" [brief] | not planned here; the bump drift item is reconciled as already merged | descoped — justification: the brief itself defers #9703, #9786, #8316 to separate runs |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| inngest-redis-luks.tf: delete_protection + prevent_destroy (volume, pair) | "delete_protection = true on the volume" | asked (ask 1, 2) |
| inngest-host.tf: prevent_destroy on the two Doppler parents | — | inferred — justification: a parent replace cascade-deletes the key without planning the secret's destroy (CTO finding), re-opening the key-loss edge asks 2 and 4 name; `inngest_host` targets both parents so the edge is reachable |
| new suite inngest-luks-sole-copy.test.sh | "pins/guards so no dispatch ... can target the volume" | asked (ask 2) |
| tests/scripts/lib/hcl-effective-text.sh (extracted lexer) and the one-line source edit in workspaces-luks.test.sh | "extend, do not duplicate" | inferred — justification: the only alternative to reusing web-1's effective-text lexer is copying ~60 lines of it; the extraction is the lower-duplication reading of ask 5 and carries the accepted risk R4 (surfaced as a decision) |
| extending the existing B5/B6 reachability pins in terraform-target-parity.test.ts | "no dispatch (workflow_dispatch, destroy/taint/replace paths) can target" | asked (ask 2) |
| census G4h + G4_PROTECTED extension | "extend, do not duplicate" | asked (ask 5) |
| new ADR, ADR-142 pointer addendum, runbook section, ledger row, C4 description | "documented" | asked (ask 4); the ledger row and C4 text become false otherwise |
| Article 30 TOM + (e) pointer, compliance-posture bracket | "documented" | inferred — justification: counsel review O4 said the register recites the sole copy once the backstop is gone; the CLO assessment names these two rows |
| suite-shard-legs.tsv / suite-durations.tsv entries | — | inferred — justification: shard assignment for a new suite is an enforcement contract of the runner |
| deferral issue for header backup / key-continuity probe / repair dispatch / token downgrade / state-loss import rehearsal / Doppler version-history measurement | "(c) ... escrow/recovery stance" | inferred — justification: the stance defers these, and a deferral without a tracking issue is invisible (wg-when-deferring-a-capability-create-a) |

### Split Assessment

- Subsystems touched: 5 — apps/web-platform/infra, tests/scripts, plugins/soleur/test, scripts, knowledge-base
- Planned files: ~16 | Estimated changed lines: ~500
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the pin and its guard must land together (a pin without its guard, or the reverse, is the exact class this plan exists to avoid); the legal and ADR records are derivative of the same facts and the CLO requires them in the same PR.

## Implementation Phases

### Phase 0 — Prove the delivery path (read-only; no merge, no apply)

1. With the Phase 1 edit applied in the worktree, run the evidence plan described in Production Write Gate item 1: the
   per-merge `-target` list extracted from the workflow, NO volume target, `-lock=false`, read-only Hetzner token. Save the
   human and JSON plan, assert the server is absent and exactly one volume update is present, replay the per-merge guard logic
   (item 2), write `apply-plan-output.md`. Never print secret values (`doppler run` injection only).
2. Outcome A (expected): one in-place update, nothing else. Continue. Outcome B: STOP and re-plan (see contingency).
3. Build the Phase 3 gate-replay fixture from this real plan JSON (volume, attachment and server entries), not from a
   hand-made document.

### Phase 1 — Terraform pins (apps/web-platform/infra)

- `inngest-redis-luks.tf`: volume gets `delete_protection = true` (the only code line carrying that literal; comments say
   "delete protection") and `lifecycle { prevent_destroy = true }` with a sole-copy comment (ordering trap, the two guards,
   why `format` stays absent, a pointer to the runbook section and the new ADR); pair gets `lifecycle { prevent_destroy = true }`
   with a comment on the rotation caveat; the attachment keeps no lifecycle block and gets a comment stating why and naming the
   compensating pins; fix the header comment that still says protection is future work.
- `inngest-host.tf`: `prevent_destroy` on `doppler_project.inngest` and `doppler_environment.inngest_prd`, with a comment that
  a deliberate recreate of the whole project needs a reviewed lift first.
- `terraform fmt -check` and `terraform validate` (backend-less init) green.

### Phase 2 — Guards (write the mutation matrices first; they are in `## Guard Contract`)

- Extract `strip_comments`, `block_of`, `_b4_block_range` and the attribute predicates from `workspaces-luks.test.sh` into
  `tests/scripts/lib/hcl-effective-text.sh`, resolved from the repo root (not the suite's own directory); both suites source
  it. First check that no existing B4 row mutates `strip_comments` by editing the suite's own text. Record the web-1 suite's
  pass count and floor BEFORE the edit; the count must be identical after, and neutering the library must redden both suites.
- Create `apps/web-platform/infra/inngest-luks-sole-copy.test.sh` (Guard 1), anchoring every predicate (`prevent_destroy`
  and `delete_protection` are matched as a whole code line, inside the right block, trailing comment allowed) and register it
  in `apps/web-platform/infra/suite-shard-legs.tsv` / `suite-durations.tsv`. Its consumer is the infra runner glob
  (`apps/web-platform/infra/run-registered-suites.sh`), verified with `scripts/lint-orphan-test-suites.sh`; check
  `scripts/guard-vacuity-floor.test.sh` derivation picks up its floor (literal floor on an `if` line; counters incremented at
  the call site).
- `plugins/soleur/test/terraform-target-parity.test.ts`: extend the existing B5/B6 pins and helpers (`extractJobBlock`,
  `extractAllTargets`, `stripDispatchJobs`, the continuation-folding and comment-stripping helpers) with the expected-set
  literal for Guard 2 and the `-replace`/`-destroy`/taint/state spellings; no new standalone block.
- `tests/scripts/test-infra-privileged-tier-census.sh`: extend `G4_PROTECTED` with the two Doppler parents; derive
  `G4H_SOLE_COPY` = `G4_PROTECTED` minus the two App-identity entries (`doppler_secret.github_app_id`,
  `doppler_secret.github_app_private_key`, whose `removed` blocks in `github-app.tf` are legitimate forget-only); add a
  SEPARATE `moved_blocks` collector (the existing `removed_blocks` collector also feeds G4a, which demands a `from` and
  `lifecycle { destroy = false }`); add G4h (Guard 3) after G4g with a must-PASS row for the existing App-identity forget; update
  the row-presence list and the exact row-count floor and ceiling the file keeps. Live-tree count of `removed`/`moved` blocks
  naming `G4H_SOLE_COPY` today: 0 (measured 2026-10-10 for the inngest addresses; re-measure for all).

### Phase 3 — Prove the sanctioned path still works

- Replay a host replace built from the real Phase 0 JSON through `inngest_host_replace_gate` with the volume at `no-op` and
  the attachment replaced (add a row to `test-inngest-host-replace-gate.sh`, floor raised) — PASS. Add the pre-apply
  counterpart (volume `update`) asserting the named abort `luks_volume_touched`, so the ordering in the runbook is a tested fact.
- Run the existing gate suites unchanged and green.

### Phase 4 — Records and posture

- New ADR + ADR-142 pointer addendum + ADR-263 divergence note; runbook `inngest-luks-cutover-6894.md` section "Sole-copy
  protection and key loss": it LINKS to the ADR's loss-mode table, states the read-back recipe as a one-line wrapped command,
  the deliberate unprotect path (below), replace-after-apply ordering, `manual-rerun` as the delivery route, the owner and
  procedure for each loss mode, no SSH, no untargeted apply (a full untargeted apply today would replace the server and its
  attachment with no gate running), and the scratch-worktree revert recipe.
- **Unprotect path, stated honestly.** Lifting is two reviewed PRs (delete protection first, apply, then `prevent_destroy`),
  and each must edit the guards it trips (Guard 1 rows, G4h/G4_PROTECTED, the Guard 2 expected set). No workflow can
  destroy the volume today and PR B deleted the wipe/destroy dispatch, so NO sanctioned erase path exists for this volume;
  designing one is a separate issue (also relevant to Art. 17 whole-volume erasure — say so in the register TOM).
- `scripts/encryption-posture-ledger.json` row text; `diagrams/model.c4` (+ regenerate `model.likec4.json`).
- Article 30 register (the Inngest activity's TOM list and its (e) row pointer) and compliance-posture bracket. Not touched:
  `inngest-aof-backstop-destruction-record.md`, `inngest-aof-destruction-record.md`, `2026-09-counsel-review-8248.md`.
- Deferral issue FILED during planning as #9927 (keep its body in sync with this list): header off-host backup decision, on-host `luksOpen --test-passphrase` continuity probe (precedent
  registry-luks-escrow, #8408), Doppler repair dispatch for an overwritten key, host token read-only downgrade (ForceNew),
  state-loss `random_password` import rehearsal, Doppler version-history measurement (plan tier and rollback scope; never print
  diffs), Hetzner project-deletion coverage, optional scratch-volume proof that detach works under protection. Dated
  re-evaluation trigger `2027-01-08` (within 90 days) or the next planned host replace, whichever comes first;
  `Mandated-By: wg-when-deferring-a-capability-create-a`.

### Phase 5 — Gate, merge, read back

Production Write Gate items 1-5. PR body: first line says merging applies one in-place production update; `Closes #9879`,
`Ref #8285`, `Ref #9786`, `Ref #9703`, `Ref #8316`; ends with the Generated-with line. Commits carry the Co-Authored-By
trailer. No rebase after any record names a commit id.

## Files to Edit

- `apps/web-platform/infra/inngest-redis-luks.tf`
- `apps/web-platform/infra/inngest-host.tf`
- `apps/web-platform/infra/workspaces-luks.test.sh` (source the library; zero row changes)
- `apps/web-platform/infra/suite-shard-legs.tsv`, `apps/web-platform/infra/suite-durations.tsv`
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `tests/scripts/test-infra-privileged-tier-census.sh`
- `tests/scripts/test-inngest-host-replace-gate.sh`
- `scripts/encryption-posture-ledger.json`
- `knowledge-base/engineering/architecture/decisions/ADR-142-inngest-redis-aof-zero-data-loss-luks-migration.md` (pointer addendum)
- `knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md` (divergence note)
- `knowledge-base/engineering/architecture/diagrams/model.c4` and `model.likec4.json` (regenerated)
- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md`
- `knowledge-base/legal/article-30-register.md`, `knowledge-base/legal/compliance-posture.md`

## Files to Create

- `apps/web-platform/infra/inngest-luks-sole-copy.test.sh`
- `tests/scripts/lib/hcl-effective-text.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-<next free ordinal>-sole-copy-luks-volume-protection-set.md` (ordinal provisional)
- `knowledge-base/project/specs/feat-one-shot-9879-luks-sole-copy-protection/apply-plan-output.md` (Phase 0 evidence)

## Open Code-Review Overlap

None. (Queried open `code-review` issues for every path above; no body names any of them.)

## Guard Contract

### Guard 1 — inngest sole-copy HCL pins (new suite over effective Terraform text)

**Property.** The effective (comment-stripped) Terraform text declares `delete_protection = true` plus `prevent_destroy = true` inside a `lifecycle` block on the volume, `prevent_destroy = true` on the passphrase pair and on the two Doppler parents, NO `prevent_destroy` on the attachment, no `ignore_changes` on the volume or the pair, and exactly one writer of `INNGEST_REDIS_LUKS_KEY` on `soleur-inngest`/`prd`.

**Assembly.** Every `*.tf` in the main root (the sub-roots, including the rehearsal root with its own scratch secret of the same NAME, are separate directories and are not scanned) read through ONE chokepoint, the shared lexer (`hcl-effective-text.sh`) that strips `#`, `//` and multi-line `/* */` comments while keeping line numbers and respecting strings and heredocs; blocks extracted by brace depth for six addresses (volume, attachment, `random_password`, `doppler_secret`, `doppler_project.inngest`, `doppler_environment.inngest_prd`); predicates anchored to a whole code line (`^\s*prevent_destroy\s*=\s*true\s*(#.*)?$`) evaluated only inside a `lifecycle` block (the shared lexer keeps trailing comments, so an unanchored match would pass a comment-only mention); plus the root directory itself (no `*override.tf`, no `*.tf.json`: Terraform merges them and either could set `prevent_destroy = false`); plus every `.tf` in the root for a second `doppler_secret` named `INNGEST_REDIS_LUKS_KEY` resolving to project `doppler_project.inngest.name` and config `doppler_environment.inngest_prd.slug`. Three scans on purpose: block text, directory listing, cross-file census.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | volume `delete_protection = true` flipped to `false` | RED |
| 2 | volume `prevent_destroy` line deleted from its lifecycle block | RED |
| 3 | the volume's whole lifecycle block wrapped in a multi-line block comment | RED |
| 4 | volume `prevent_destroy = false` | RED |
| 5 | `ignore_changes = [delete_protection]` (and `= all`) added on the volume | RED |
| 6 | `prevent_destroy = true` moved into a nested non-lifecycle block of the volume | RED |
| 7 | `prevent_destroy` removed from the pair member that comes SECOND in the file after the first stays compliant (second-member row) | RED |
| 8 | `prevent_destroy` removed from `doppler_environment.inngest_prd` | RED |
| 9 | `prevent_destroy = true` ADDED to the attachment (the host-replace breaker) | RED |
| 10 | a planted `zz_override.tf` in the root | RED |
| 11 | a second `doppler_secret` named `INNGEST_REDIS_LUKS_KEY` on the prd config in a sibling `.tf` | RED |
| 12 | the suite's own dispatch: the block extractor returns empty for an address (renamed resource) so zero attributes are checked | RED (extractor non-vacuity row, not "0 checked, exit 0") |

**Harness rows.** SUITE edit: neuter `strip_comments` in the library to the identity function — row 3 must then pass the guard, so the library-neutering row and the reporter self-test go RED on BOTH suites that source it. Must-PASS variants that differ from the canonical in a permitted way: a cosmetic rewrite (extra spacing, trailing `# comment` after `delete_protection = true`), the attachment with a trailing comment mentioning `prevent_destroy`, and the rehearsal sub-root's scratch secret of the same name (different directory, must stay green). Instrument self-test drives pass and fail once before any verdict.

**Anchor.** The pins live in the same commit as the guard, so one diff can weaken both. Independent anchors: the census rows (G4h, `G4_PROTECTED`) are in a different file; the merge-base diff the census already computes for G4c catches a deleted resource block; and the post-merge read-back plus the drift plan read live Hetzner, which a weakening of text alone cannot change. A deleted whole resource block (taking its lifecycle with it) is caught by G4c and by row 12, both only as strong as their being required checks; the runbook states that lifting protection is a reviewed two-step change.

### Guard 2 — reachability of the sole-copy addresses across all workflows (extends B5/B6 in the parity test)

**Property.** The only (workflow, job, verb) triples that name `hcloud_volume.inngest_redis_luks`, `hcloud_volume_attachment.inngest_redis_luks`, `random_password.inngest_redis_luks`, `doppler_secret.inngest_redis_luks_key`, `doppler_project.inngest` or `doppler_environment.inngest_prd` in a Terraform flag are the exact expected set.

**Assembly.** Every `.github/workflows/*.y(a)ml`, comments stripped and line continuations folded, over every spelling: `-target=X`, `-target X`, quoted forms, `-replace=X`, `-replace X`, `-destroy`, `terraform destroy`, `taint`, `state rm|mv|push`, `import`; per-job extraction through the existing `extractJobBlock` / `extractAllTargets` chokepoints; plus the per-merge job after `stripDispatchJobs`. Three call-site classes exist: per-merge apply, `inngest_host`, `inngest_host_replace`; a flag spelled in any other job, or any `-replace`/`-destroy` of these addresses anywhere, is the defect. **Measured on the live tree 2026-10-10** with `grep -nE "^[^#]*-(target|replace)[= ]+['\"]?(<the six addresses>)\b" .github/workflows/*.yml`: seven lines, all in `apply-web-platform-infra.yml` — per-merge job `-target` the passphrase pair (2), `inngest_host` `-target` volume, attachment, `doppler_project.inngest`, `doppler_environment.inngest_prd` (4), `inngest_host_replace` `-target` attachment (1), and zero `-replace`/`-destroy` of any of them. That is the expected set.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `-replace='hcloud_volume.inngest_redis_luks'` added to `inngest_host_replace` | RED |
| 2 | `-target='hcloud_volume.inngest_redis_luks'` added to `inngest_host_replace` (breaks preserve-by-omission) | RED |
| 3 | the attachment target added to a third job after the two legal ones are intact (second-member row) | RED |
| 4 | `terraform destroy` step added to a main-root workflow | RED |
| 5 | `-target X` written with a space and a line continuation instead of `=` | RED |
| 6 | the census's own dispatch: `extractAllTargets` returns an empty set for a job (renamed job) | RED (non-vacuity: expected jobs must be found) |
| 7 | a new workflow file naming the pair in `-target` | RED |

**Harness rows.** SUITE edit: replace the expected-set constant with a superset and assert the mutation battery turns RED. Must-PASS: the live workflow tree; a copy with comments and line continuations rewritten (re-quoted, `=` to space) that must still equal the expected set; and the two Doppler parents appearing only in `inngest_host` (they are targeted, never replaced or destroyed).

**Anchor.** The expected set is a literal in the test file, edited only with a reviewer reading it; the workflow file is the other side of the comparison and is not edited by this PR, so one diff changing both is visible in review as a workflow edit.

### Guard 3 — census G4h, no `removed {}` or `moved {}` over a sole-copy address

**Property.** No `removed` block and no `moved` block in any census root names an address in `G4H_SOLE_COPY` as `from` or `to`.

**Assembly.** Every `.tf` under every `GUARD4_ROOTS` entry (the existing block scanner `block_bodies`), both block kinds, both attributes. `G4H_SOLE_COPY` is DERIVED from the single `G4_PROTECTED` list (extended with the two Doppler parents) minus the two App-identity entries that legitimately have forget-only `removed` blocks; it is never a second hand-written list. `removed` blocks come from the existing `removed_blocks` collector; `moved` blocks from a new collector (the existing one also feeds G4a, which would false-RED on a `moved` block).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `removed { from = hcloud_volume.inngest_redis_luks }` added | RED (G4h) |
| 2 | `moved { from = hcloud_volume.inngest_redis_luks to = hcloud_volume.x }` added | RED |
| 3 | a compliant `removed` block for an unprotected address, then a second `removed` for `doppler_environment.inngest_prd` (second-member row) | RED |
| 4 | `doppler_environment.inngest_prd` deleted from `G4_PROTECTED` while the removed block stays | the presence pin and the exact-set row RED |
| 5 | the `moved` collector reads zero blocks on a fixture that contains one (dispatch non-vacuity) | RED |

**Harness rows.** SUITE edit: remove the new row from the presence list — the presence pin must RED. Must-PASS: the existing App-identity forget-only `removed` blocks (`github-app.tf`) stay green, and a `removed` block for an UNPROTECTED address with `lifecycle { destroy = false }` stays green (the G4a shape).

**Anchor.** `G4_PROTECTED` and the presence list sit in the same file as the new row; the independent anchor is the merge-base diff the census already computes for G4c (base-ref declared addresses), so a deleted protected resource block still reds G4c even if G4h is weakened.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. `inngest-redis-luks.tf`: volume has `delete_protection = true` (one code line; no comment spells the literal) and `prevent_destroy = true`; both pair members and both Doppler parents have `prevent_destroy = true`; the attachment has no `lifecycle` block; `grep -c -e 'delete_protection = true' apps/web-platform/infra/inngest-redis-luks.tf` prints `1` (the observability discoverability command, run once before finalizing).
- [ ] AC2. `bash apps/web-platform/infra/inngest-luks-sole-copy.test.sh` green with every Guard 1 mutation row RED and every must-PASS row green; `bash apps/web-platform/infra/workspaces-luks.test.sh` green with the SAME pass count and floor as before the library extraction.
- [ ] AC3. A gate-library replay of a host replace built from the real Phase 0 JSON (attachment `delete`+`create`, volume `no-op`, server replaced) PASSes `inngest_host_replace_gate`; the same plan with the volume `update` aborts `reason=luks_volume_touched`.
- [ ] AC4. `apply-plan-output.md` exists, was produced with the real per-merge `-target` list and no volume target, and shows one in-place update of the volume (`delete_protection`), zero other updates, zero adds, zero destroys, nothing at 106443278, and no `hcloud_server.inngest` entry; the destroy-guard counters and the per-merge halt logic evaluate to pass over its JSON.
- [ ] AC5. The user's explicit per-command go-ahead for the merge is recorded in the PR before it is marked ready; the squash message and PR body carry no `[skip-web-platform-apply]` marker; the PR body's first line says merging applies one in-place production update.
- [ ] AC6. `bun test plugins/soleur/test/terraform-target-parity.test.ts`, `bash tests/scripts/test-infra-privileged-tier-census.sh`, `bash tests/scripts/test-inngest-host-replace-gate.sh`, `bash tests/scripts/test-inngest-host-shape-gate.sh`, `bash apps/web-platform/infra/inngest-host.test.sh`, `bash apps/web-platform/infra/inngest-redis-luks.test.sh`, `bash scripts/guard-vacuity-floor.test.sh`, the C4 count-parity and syntax/render tests, `python3 scripts/lint-encryption-posture.py`, `python3 scripts/lint-guard-contract.py`, `bash scripts/lint-orphan-test-suites.sh` and `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (the gate's own invocation, not a hand-listed path set) are all green (`TEST_GROUP=affected` locally; CI is the authority). G4h's live-tree count of `removed`/`moved` blocks over `G4H_SOLE_COPY` is 0.
- [ ] AC7. New ADR, ADR-142 pointer addendum, ADR-263 divergence note, runbook section, ledger row, C4 description, Article 30 TOM and compliance-posture bracket are written with merge-dependent sentences conditional; `git diff --quiet origin/main...HEAD -- knowledge-base/legal/audits` exits 0 (the attested destruction and counsel files are untouched).
- [ ] AC8. `git diff --quiet origin/main...HEAD -- 'apps/web-platform/infra/workspaces-luks*.tf' apps/web-platform/infra/server.tf 'apps/web-platform/infra/git-data*.tf' apps/web-platform/infra/inngest-provision-rehearsal` exits 0 (merge-base form, so a sibling merge cannot redden it); no ADR-198 credential file is edited; the Phase 0 plan names no web-1, web-2, git_data or rehearsal address. The diff-scope allowance for files the pipeline itself writes: `knowledge-base/INDEX.md`, `specs/feat-one-shot-9879-luks-sole-copy-protection/session-state.md` and `tasks.md`.
- [ ] AC9. Deferral issue #9927 (header backup, continuity probe, repair dispatch, token downgrade, import rehearsal, version-history measurement, scratch-volume proof) exists with the dated trigger and `Mandated-By` line and matches the plan; PR body carries `Closes #9879` and only `Ref` for others.
- [ ] AC10. The revert recipe was executed once in a scratch detached worktree (`git revert --no-commit`, then the registered suite and baseline checks) and its output is recorded in the runbook section.

### Post-merge (automated read-back; no human step)

- [ ] AC11. Executor `soleur:postmerge`: after the per-merge apply, the wrapped read-only Hetzner GET of volume 106903269 returns `protection.delete=true`, and the drift plan output shows no pending change at `hcloud_volume.inngest_redis_luks` or the two key addresses (the drift run as a whole may stay red for the unrelated pending server replace until #9786). A failed read-back is a red post-merge status and routes to the `manual-rerun` delivery route.

## Test Scenarios

- Given the HCL with all pins, when the new suite runs, then every must-PASS row is green (unit).
- Given any Guard 1-3 mutation, when the suite runs, then the named row goes RED (unit).
- Given a host-replace plan built from the real Phase 0 JSON with the volume at no-op, when the gate library is replayed, then PASS (unit).
- Given the same plan with the volume `update`, when replayed, then ABORT luks_volume_touched (unit).
- API verify (read-only, post-apply): the wrapped GET of `/v1/volumes/106903269` with the read-only token expects `protection.delete` true (it reads false today, verified 2026-10-10).

## Success Metrics

Zero plans on any path can destroy, replace or forget the four addresses or the two parents; the sanctioned replace still plans; the live volume reads `protection.delete=true`; the register and ADR no longer say protection is future work.

## Rollback

Two recipes, both to be EXECUTED once in a scratch detached worktree before the PR leaves draft (the recipe is not
trustworthy until a revert has been run through the same gates):

- **Partial (preferred):** keep the protections, revert only a misbehaving guard row or record edit. Never rebase after a
  record names a commit id.
- **Full revert:** `git revert --no-commit` the feature commits, then run the suites the revert PR must pass. The revert
  plans the inverse in-place update (`delete_protection` true -> false) through the same per-merge path, and removes the new
  suite with its registrations (`suite-shard-legs.tsv`, `suite-durations.tsv`, the `test-all.sh` line, the
  `BASELINE_DECLARED_PROBES` bump) in the same commit or the orphan census and the baseline test go red. Record the
  scratch-run output in the runbook section. Lifting protection deliberately is never a revert of only `prevent_destroy`.

## Dependencies & Risks

- **R1 closure inference wrong** — mitigated by Phase 0 (no volume target in the evidence plan); the branch is stop and re-plan.
- **R2 Detach under delete protection** is documented only indirectly; the first sanctioned host replace is the live proof; this PR does not perform one and must not.
- **R3 Pending-update abort** of the two dispatch gates between merge and apply, or after a skipped/failed apply — fail-closed, named reason, ordered in the runbook, tested (Phase 3), `manual-rerun` named as the delivery route.
- **R4 Lexer extraction** edits the web-1 sole-copy guard suite (one source line) — mitigated by identical pass count and floor and neuter-the-library rows on both suites; the alternative (a local copy) is recorded as a decision. Probe mutations on a scratch copy; read every floor back before commit (learning 2026-10-09).
- **R5 Residuals accepted and recited:** Doppler overwrite has no automated repair and the per-merge HALT blocks every infra merge until it is repaired; both-copies loss; header loss with lagging detection; Hetzner project deletion unverified; host token `read/write` (revocation of `doppler_service_token.inngest` is also a key-loss edge); an untargeted full apply would replace the server and attachment ungated.
- **R6 Merge queue and attestations:** never rebase after a record names a commit id.
- **R7 The natural repair of a refusal.** A stuck engineer meeting `Instance cannot be destroyed` will delete the `lifecycle` block, and one meeting `luks_volume_touched` will widen the gate. Guard 1 reds the first (rows 2-4) and the second is a named Cut; each refusal's comment points at the runbook section, which names the reviewed two-step unprotect as the only sanctioned route. A legitimate `moved` rename and an unrelated volume update (for example a size grow) are blocked/aborted until the guards are edited in a reviewed change.
- **R8 Drift detector degraded:** the full-root drift plan is already non-empty (pending server replace until #9786), so a new drift reason is distinguishable only by reading the plan text for the address.
- **Out of scope (explicit):** web-2 volume, git_data, rehearsal volume, ADR-198 credentials; #9703, #9786, #8316.

## References & Research

- Precedent: `apps/web-platform/infra/workspaces-luks.tf` (volume/attachment comments), `workspaces-luks.test.sh` Guard B4; PR #9348; learning `2026-10-01-the-guards-i-wrote-to-protect-the-sole-copy-scanned-a-shape-the-attack-did-not-take.md`.
- Gates: `tests/scripts/lib/inngest-host-replace-gate.sh`, `inngest-host-shape-gate.sh`, `destroy-guard-filter-web-platform.jq`.
- ADR-142 (addenda 2026-10-08 and 2026-10-09), ADR-006 (state-backend correction), ADR-119, ADR-263; counsel review 8248 item O4; destruction records (do not edit).
- Issues: #9879, #8285, #8620, #9786, #9703, #8316; PRs #9348, #9877, #9899, #9925.
