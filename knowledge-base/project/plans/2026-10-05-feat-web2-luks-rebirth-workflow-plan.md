---
title: "infra: convert the live web-2 to LUKS-at-boot via a single-use gated volume rebirth"
date: 2026-10-05
slug: web2-luks-rebirth-workflow
branch: feat-one-shot-9372-web2-luks-rebirth-workflow
issue: 9372
type: feat
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# infra: convert the live web-2 to LUKS-at-boot via a single-use gated volume rebirth

## Overview

A dispatch-only, single-use workflow that replaces the empty plaintext volume behind the live web-2 standby with a raw volume
that the guest-side provisioner formats as LUKS at first boot (ADR-263). It is a new file because
`apply-web-platform-infra.yml` sits at its byte cap. Every destructive call is preceded by evidence and pinned to a physical
id, every step is idempotent, and a re-dispatch either heals or refuses. This change writes the workflow, a two-mode plan
gate, a state classifier, an emptiness-evidence helper, their tests and fixtures, the registrations that keep CI honest, a
runbook, the ADR-263 addendum and one follow-through arm. It runs nothing: no dispatch, no apply, no token mint, no secret write.

## Research Insights

**Premise validation (Phase 0.6).** #9372 is OPEN. Its 2026-10-04 comment lists the retirement checklist for
`apply-web-escrow-create.yml`; every file it names exists on `origin/main`. `scripts/followthroughs/web2-luks-live-6931.sh`
and `scripts/lib/web2-luks-rows.sh` already exist, so scope item 5 is enrolment text plus a missing grading arm, not a new
probe. The issue's `web2_allow` blocker does not exist by that name: the jq filter carries `web2_retire_allow`, a different
operation's contract (it REQUIRES the volume destroy; its own comment forbids reusing it for a replace). The sibling worktree
`.worktrees/resume-9372-web2-luks-conversion` is stale (no commits ahead of main, no PR) and is not read or touched.

**CTO ruling (2026-10-05, applied throughout).** One new workflow plus a new two-mode gate library; no reuse of
`web-host-replace-gate.sh` (it requires the volume to survive) or `web-host-birth-gate.sh` (it requires zero destroys); five
`-target`s; two graded plans (`pre` before anything is touched, `post` after `state rm`); physical-id pins on every destroy;
no refusal to format on `escrow!=ok` (the verdict goes RED and the existing marker/weight gate keeps web-2 dark); the rotation
HALT create-exemption flip is mechanically required before the apply path runs; emptiness evidence from raw Better Stack SQL
with explicit gap and spread rules; the reboot proof needs a new follow-through arm because `boot_id` is diagnostic-only today.

**CPO and CLO rulings (2026-10-05, applied throughout).** CPO: APPROVE-WITH-CONDITIONS. Conditions folded in: the User-Brand
Impact section (below); fail-closed emptiness evidence; a per-dispatch go-ahead from a named human who has read the dispatch
summary; the summary content list (Closing checklist, item 0); no "LUKS-backed at boot" claim anywhere before the graded
reboot proof; the soak marker (and so weight) must depend on the reboot proof, not the readiness row alone; web-1 refused in
code and test with the volume id re-asserted on every re-run; partial-failure states alert without SSH with a runbook step per
state; host-key re-pin tracked with a decision date before 2026-10-22; the workflow is deleted after use and ADR-263 records it.
CLO: NO LEGAL BLOCKER, with conditions. The ship-time Counsel-Review gate does not fire (no `knowledge-base/legal/**` or
`docs/legal/**` edit; the runbook and checklist live outside those paths); the ADR-263 addendum is conditioned, never past
tense; the first apply-path step refuses unless the retirement change has merged (the "closing-change record"); the birth-time
recovery check is strengthened to a header-UUID comparison plus a test-passphrase unlock, and fails the workflow rather than
logging; the workflow and runbook never claim "recoverable", "restore-tested" or "Art. 32(1)(c) satisfied"; the closing change
records run id, SHA, approver and timestamps (Art. 5(2)).

**Property List (Phase 0.6b).**

1. P1 — no call can delete or reformat any volume other than the one pinned by physical id (106466179).
2. P2 — emptiness and never-pooled are proven from independent evidence before the first destructive call.
3. P3 — web-1 is unreachable by this workflow, by name and by id.
4. P4 — a crash at any step boundary leaves a state a re-dispatch heals or refuses before any write.
5. P5 — the replacement volume is raw (no filesystem baked at create) and the host boots on an image that carries the provisioner.
6. P6 — the readiness evidence is read from telemetry, newer than the run, with `luks=1 luks_arm=formatted escrow=ok`.
7. P7 — the workflow claims only what it measured: "reboot issued", never "reopen proven".
8. P8 — the workflow is single-use and its retirement is a written checklist.

**Cut List.**

| Mechanism | Property it would buy | What already covers it, or why cut |
|---|---|---|
| A separate read-only `evidence` job | P2 | Duplicates credential loading; one job with mutating steps behind `plan_only != true` (CTO G.4) |
| New passphrase-recovery test harness | P7 (Art. 32 honesty) | A birth-time read-only check plus a runbook; the restore itself stays with #7992 |
| Any `.tf` edit | P5 | `hcloud_volume.workspaces` is already born raw with `ignore_changes=[format]`; no Terraform change is needed |
| Reusing or relaxing `web-host-replace-gate.sh` / `web2_retire_allow` | P1 | Wrong contracts; reuse would grade the plan against the wrong operation |
| An `apply_target` in `apply-web-platform-infra.yml` | single use | The file is at its byte cap (forget-workflow header) |
| A refusal to format when escrow is missing | P6 | The volume is empty at birth; the `web2_marker` job and `lb-weight-gate-with-marker.sh` already withhold weight and data |

## Research Reconciliation — Spec vs. Codebase

| Issue / brief claim | Reality (measured) | Plan response |
|---|---|---|
| "the `web2_allow` blocker is largely stale" | No `web2_allow` identifier exists; `web2_retire_allow` (jq:142) is the retire contract | New gate library with its own allow-set; measure by fixtures |
| Delete volume via API, `state rm` it, "then destroy the server and attachment", then `web-host-create` | A destroy-mode plan on the server would also destroy dependents, including `hcloud_firewall_attachment.web` (strips web-1's firewall) | One `-replace` of the server over five explicit `-target`s; the volume is created via a state-absent create; firewall attachment may only UPDATE |
| Reboot proof "graded by the follow-through" | `boot_id` is "diagnostic only, never joined or required" (W2L:33) | Add a reboot-seen arm to `web2-luks-live-6931.sh`; the workflow claims "reboot issued" only |
| "first confirm Vector ships the field" | `vector.toml` ships `filesystem` for `/mnt/data` tagged with the host; no repo consumer queries the JSON paths | First live query is the positive control; the PR states the paths are unconfirmed; fail closed |
| "`host_metrics` excludes `dm-*`, so evidence exists only while plaintext" | The exclusion matches device names; the mapper device may not match `dm-*` | Do not rely on absence in either direction |
| Escrow preflight census recognises literal `-target`/`-replace` with `terraform apply` | The new workflow spells both | Enrol it in the census and put the preflight before the first Hetzner call |
| Hetzner volume delete | Hetzner refuses to delete an attached volume | Detach, poll the action, then delete; 404 means already gone |

## Problem Statement

The live web-2 volume (`soleur-web-platform-data-web-2`, id 106466179) was created ext4, so the provisioner's discriminator
correctly refuses it. It holds no user data and was never pooled, so it can be replaced, but `prevent_destroy` blocks the
Terraform route and the operation needs its own review, approval environment and evidence. The encryption-posture exception on
`hcloud_volume.workspaces` expires 2026-10-22.

## Proposed Solution

`.github/workflows/web2-luks-rebirth.yml`: `workflow_dispatch` only, `plan_only` default true, typed confirm
`REBIRTH-web-2-LUKS`, the pinned volume id as a constant the input must equal, a required explicit `image_tag`, a free-text
`reason`. Workflow-level concurrency `terraform-apply-web-platform-host` (the lockless R2 state serializer), job-level
`web-1-swap` (the firewall attachment singleton), environment `web-platform-infra-apply`, a main-only `if:`, permissions
`contents: read, packages: read, actions: read` (the push-apply pause assertion calls the Actions API and refuses on every run without `actions: read`), `timeout-minutes: 60`.

One job. Steps (the mutating ones carry `if: inputs.plan_only != true`):

| # | Step | Writes? |
|---|---|---|
| S1 | Validate inputs (typed confirm, pin equality, `image_tag` shape), refuse xtrace | no |
| S2 | Load credentials (tiered loader), `SENTRY_DSN` non-empty (ADR-128 R1) | no |
| S2b | Escrow preflight as its own step, exactly `bash scripts/web-host-escrow-preflight.sh` (`timeout-minutes: 2`, env `DOPPLER_TOKEN` only, no `if:`/`shell:`/`working-directory:`/`continue-on-error`), before ANY step containing a terraform command, including S4's `terraform state pull` | no |
| S3 | Presence proof: GET web-1 holds the live LUKS volume (a 404 below means gone, not wrong project); capture web-2's server id | no |
| S4 | Classify state: Hetzner GETs plus `terraform state pull` through ONE field-selecting jq, into `web2_rebirth_classify`; REFUSE or name the heal window | no |
| S5 | Emptiness evidence (7-day Better Stack aggregate) and never-pooled proof (marker name absent; anti-pooling check green at the ref) | no |
| S6 | Digest pin from the explicit `image_tag`, amd64 runner assert, coherence preflight (image label equals `local.host_scripts_content_hash`) | no |
| S7 | `pre` plan on current state, graded by `web_host_rebirth_gate pre`; stock preflight; push-apply pause assertion; flip-precondition check | no |
| S8 | Detach (only if attached), poll the action, DELETE the pinned volume (404 = already gone) | yes |
| S9 | `terraform state rm` of the volume and its attachment: serial +1, lineage unchanged, ids equal the pin | yes |
| S10 | `post` plan, graded by `web_host_rebirth_gate post`; then apply of exactly that plan file | yes |
| S11 | Poll Better Stack for `SOLEUR_FRESH_BOOT_READY` newer than the run anchor; RED unless `luks=1 luks_arm=formatted escrow=ok host=soleur-web-2` | no |
| S12 | Birth-time read-only recovery check; any failure fails the run. (a) the escrowed header object exists under the volume's LUKS UUID, a ranged GET of bytes 0-5 equals `LUKS\xba\xbe`, and its UUID equals the live volume's UUID (from the readiness row); (b) the Doppler and Terraform-state passphrase copies agree (boolean only); (c) `cryptsetup open --test-passphrase --header <downloaded backup>` succeeds with the passphrase fed on stdin from one process (never argv, never a file). Prints "birth-time consistency check; restore not exercised; open until #7992 and a restore drill" | no |
| S13 | hcloud reboot action (API only), target re-resolved by NAME `soleur-web-2` and asserted not web-1's server id and equal to the id in post-apply state; on failure of any step a final `if: failure()` step names the heal window; summary prints "reboot issued", the follow-through directive text with `earliest` computed, and the evidence list in the Closing checklist | yes |

### The two-mode gate (`tests/scripts/lib/web-host-rebirth-gate.sh`)

First statement: the by-name web-1 refusal, then the shared plan-gate preamble (rejects missing, scalar or `actions:[]`
entries). Actions are compared as sorted sets and must equal the address's permitted list exactly, so a volume delete,
forget or replace is unrepresentable. Pins come from Hetzner at S3, never from the plan under test.

| Mode | Address | Allowed actions | Pin |
|---|---|---|---|
| pre | `hcloud_server.web["web-2"]` | `["delete","create"]` | `before.id` = captured server id, `before.name` = `soleur-web-2` |
| pre | `hcloud_server_network.web["web-2"]` | `["delete","create"]` | `before.server_id` = captured id |
| pre | `hcloud_volume_attachment.workspaces["web-2"]` | `["delete","create"]` | `before.volume_id` = `106466179` |
| pre | `hcloud_firewall_attachment.web` | `["update"]` | — |
| pre | `hcloud_volume.workspaces["web-2"]` | no-op (absence means mis-scoped) | — |
| post | server, server_network | `["delete","create"]`, or `["create"]` if the server is already absent from state | as above |
| post | `hcloud_volume.workspaces["web-2"]` | `["create"]`; exactly one entry; name `soleur-web-platform-data-web-2`; `format` null and not unknown; size 20; labels `{app:"soleur-web-platform"}` | — |
| post | `hcloud_volume_attachment.workspaces["web-2"]` | `["create"]` | — |
| post | `hcloud_firewall_attachment.web` | `["update"]` | — |

Requirements as well as prohibitions: exactly one server create and it is web-2; the NIC, attachment and firewall entries
are present; `reboot_updates` 0; `luks_passphrase_rotations` 0; `undecidable_entries` 0; any `forget` is a violation; any
other address with a non-no-op action is a violation. Plan files are never uploaded (their `prior_state` carries a passphrase).

### The state classifier (`web2_rebirth_classify`)

Inputs are plain JSON (Hetzner volume GET, name lookup, server GET, a state summary); output is one of `proceed`,
`heal:<window>` or `refuse:<reason>`. REFUSE (before any write): the pinned volume exists with `format != "ext4"` or a
mismatched name/label; state holds a volume id other than the pin that is attached to web-2 (already reborn); the pin 404s
and the name lookup returns an id that is neither the pin nor state's; state holds an id other than the pin that Hetzner does
not know; web-2 holds a different volume or the pin is attached elsewhere; the push-apply pause is not real on an apply run.
Heal windows: detach done; delete done (404, state still holds the addresses); `state rm` done (re-plan in `post`); apply
died midway (server create alone, or volume created and server not, are both allowed in `post`). A failed boot is not healed
here; the existing `web_host_replace` for web-2 carries the new volume forward by design.

### Emptiness evidence (`scripts/web2-rebirth-emptiness.sh`)

Raw SQL through `scripts/betterstack-query.sh` (hot and archive arms) filtered to `host_name='soleur-web-2'`,
`filesystem_used_bytes`, mountpoint `/mnt/data`, and `filesystem_total_bytes` between 15e9 and 21.5e9 (the 20 GB volume, not
the root disk). PASS only if: at least 160 of 168 hours covered, newest row at most 1800 s old, and maximum at most 1 GiB. Zero rows is a
named RED ("field absent or web-2 dark"). A transport failure is not a verdict. (Plan review cut the row-count, spread and
diagnostic-count rules as redundant with hour coverage plus the ceiling.)

### Flip precondition (acceptance item 4)

On apply runs only, S7 runs the checked-out jq filter over a tracked fixture with a `create` at both web-class passphrase
addresses and requires `luks_passphrase_rotations == 2`, and requires `apply-web-escrow-create.yml` to be absent from the
checkout. The rebirth is what first formats web-2, so this blocks the dispatch until the retirement change (which deletes the
escrow-create workflow and flips the exemption) has merged. `plan_only` runs print both as PENDING.

### Reboot proof and follow-through

`scripts/lib/web2-luks-rows.sh` gains one small function, `w2l_reboot_seen <probe_verdict> <ready_verdict>`, comparing the
`boot_id=` tokens the existing verdicts already print: GREEN only when both are known and differ (an `unknown` or equal id is
RED, fail closed; no second row parse). It is called from BOTH `w2l_judge`'s marker-absent branch (so `WORKSPACES_LUKS_CUTOVER_AT`, and with it
any weight, cannot be written on the readiness row alone, CPO condition 6) and `web2-luks-live-6931.sh` (so the
follow-through grades the reopen). One definition, two callers; `boot_id` stops being diagnostic-only for the marker-absent
decision. The probe is daily, so reopen evidence arrives up to about 26 h after the reboot; the directive is
`earliest = rebirth + 3d` computed in the dispatch summary, never guessed. The workflow claims "reboot issued" only.

## Technical Considerations

- **Shell semantics.** Steps without `shell:` run `bash -e {0}`; the suite executes each writing step's real body under that
  shell with stubs (learning 2026-10-04: a suite that never executes the writing step proves nothing).
- **Lockless state.** `use_lockfile` stays false; the group literal must be byte-identical to the other appliers.
- **No token in argv.** Hetzner helpers use the stdin config form (`--config -`); `-w`, never `-f`; every annotation is
  `%`/CR/LF-escaped.
- **Credentials.** R2 backend extraction uses the heredoc-delimiter `GITHUB_ENV` form; Hetzner and Better Stack credentials are
  read masked, in-process.
- **Image.** The default tag reads the RUNNING version, which does not carry the provisioner, so `image_tag` is required and
  the coherence preflight is mandatory.
- **Private NIC.** `-target` walks dependencies, not dependents, so the target set includes the NIC and attachment; the
  summary points at the `SOLEUR_PRIVATE_NIC` marker rather than any host login.

## Implementation Phases

**Phase 0 — measurements, offline.** Read `server.tf` volume/server user_data references and record the five-target set;
read `web-host-replace-gate.sh` for the shared preamble and its by-name refusal (unchanged); read `betterstack-query.sh --help`
and one caller; confirm `vector.toml` lines.

**Phase 1 — gate library, tests first.** `tests/scripts/lib/web-host-rebirth-gate.sh`, fixtures under
`tests/scripts/fixtures/web-host-rebirth/` (synthesized plan JSON), `tests/scripts/test-web-host-rebirth-gate.sh` with the
Guard 1 matrix. RED first.

**Phase 2 — state classifier.** `tests/scripts/lib/web2-rebirth-classify.sh` plus tests for every refuse and heal window.

**Phase 3 — emptiness helper.** `scripts/web2-rebirth-emptiness.sh` with a curl/query shim and the Guard 4 matrix.

**Phase 4 — the workflow.** `.github/workflows/web2-luks-rebirth.yml` assembled from the S1-S13 table; Hetzner helpers
copied byte-identical from the forget workflow (a parity row pins that).

**Phase 5 — workflow suite.** `apps/web-platform/infra/web2-luks-rebirth-workflow.test.sh` runs the writing steps' bodies
under `bash -e` with stubs and carries the Guard 3 matrix.

**Phase 6 — reboot-seen.** `w2l_reboot_seen` in `scripts/lib/web2-luks-rows.sh`, called from `w2l_judge` (marker-absent branch)
and `scripts/followthroughs/web2-luks-live-6931.sh`, with tests for equal, `unknown` and differing `boot_id`.

**Phase 7 — registrations.** `suite-shard-legs.tsv`, `suite-durations.tsv`, `run-registered-suites.sh` bounds,
`guard-vacuity-floor.test.sh` promoted files, `terraform-target-parity.test.ts` (new workflow in `MAIN_ROOT_TF_WORKFLOWS`,
census count 4 to 5, workflow-level `env.TERRAFORM_VERSION` equal to `TF_VAR_terraform_version`, a new row defining the
five-target pin; the escrow-preflight census is predicate-driven and needs no edit), `model.c4` edge clause and regenerated
`model.likec4.json`.

**Phase 8 — records.** New runbook `web2-luks-rebirth.md` with pointer lines in `web-host-birth.md` / `web-host-replace.md`;
ADR-263 addendum; the closing checklist (below).

**Phase 9 — verify.** Run the new suites, the parity test, `lint-guard-contract.py`, the c4 tests, markdown lint; mutation
battery per the Guard Contract on a sandbox copy.

## Closing checklist (describes the dispatch-time change; none of it merges now)

0. **Dispatch summary content (printed by the run, names and booleans only, no secret values).** Before deletion: old volume
   id, name, size, labels, attached server id; the 7-day `/mnt/data` used-bytes maximum, minimum and ceiling; serving weight 0
   and marker absent; web-1's server and volume ids; "web-1 untouched". Rebuild: the volume delete result and its follow-up
   404; the state addresses removed; new server and volume ids and region; `image_tag`, digest and the hash-equality result;
   commit SHA, run id, actor and approver. Birth: the readiness row fields; the escrow object key, size, ETag and version id;
   the LUKS-magic, header-UUID, test-passphrase and passphrase-agreement results. Closing line: "reboot issued; nothing is
   claimed until the graded reboot proof". The closing change copies this summary in (run logs expire).
1. The retirement change deletes `apply-web-escrow-create.yml`, its test, `scripts/web-escrow-create-names.sh`, the suite rows,
   the vacuity-floor entry, the parity constants and census count, the C4 clause and the runbook "Step 0a" sections, and flips
   the rotation HALT create exemption (the S7 precondition requires it).
2. After the apply: flip the `hcloud_volume.workspaces` ledger row to `luks` with `live_verification: available` and
   `live_coverage_floor` 2 to 3; supersede the Article 30 / compliance-posture sentences conditioned on this event; the CLO
   re-attests from the dispatch summary's evidence list; re-capture web-2's SSH host-key pin with
   `scripts/capture-web-2-host-key.sh` (the pipeline-fix apply fails closed until then). No cell, ledger row or public copy
   says "LUKS-backed at boot" before the graded reboot proof is green; until then the wording is "provisioned, proof pending".
   Web-2 stays at weight 0 and holds no workspace data until C3 items 2 and 3 (recovery for a data-bearing host, re-escrow)
   and #7992 are discharged: the birth-time check here is a partial answer, not their closure.
2b. The push-apply workflows are `disabled_manually` today; whoever re-enables them does so only after the host-key pin is
   re-captured, because the pipeline-fix apply fails closed until then (runbooks/cron-egress-blocked.md).
3. Enrol the directive on #6931 with the computed `earliest`.
4. Delete this workflow, its gate, classifier, suite and registrations in the same change that records the use in ADR-263.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Destroy-mode plan on the server, then `web_host_create` | Destroy mode takes dependents, including the firewall attachment; the create route is not dispatchable from here |
| A new `apply_target` in the large workflow | At its byte cap |
| Drop `prevent_destroy` for one apply | Weakens the guard on the sole-copy class permanently for a one-time need |
| Convert the volume in place (reformat when ext4 and empty) | "Empty" is unprovable on the failure path; rejected in the original plan |
| Reuse `web-host-replace-gate.sh` | It requires the volume to survive |

## Downtime & Cutover

**Offline-inducing operation.** Destroying and re-creating web-2. **Surface affected.** web-2 only: a weight-0 standby outside
the ingress rotation with no user data, gate-blocked from receiving any. **Zero-downtime path evaluated.** Blue-green is
impossible (the volume name is keyed to the host); nothing is served, so the only loss is the standby's own health signal for
the run. **Bounds.** 60 minutes, behind the environment reviewer; stop condition: no READY row inside the boot window plus the
device wait ends the run RED with a named reason and the standby stays dark and paged. **Rollback.** Before S8, do not dispatch;
after S8 there is nothing of value to restore (empty volume); recovery is a re-dispatch (heal) or the existing replace route.

## User-Brand Impact

- **If this lands broken, the user experiences:** a web host that boots with an empty or unreadable `/workspaces`, never
  starts the app, or, worst case, a format over a populated volume destroys a user's only copy of their source code.
- **If this leaks, the user's data is exposed via:** the LUKS passphrase or boot token through the Terraform state, a plan
  artifact, a CI log under xtrace, or argv; or a volume that is plaintext while a published claim says it is encrypted.
- **Brand-survival threshold:** `single-user incident`

web-2 holds no user data and takes no traffic today; the controls are the physical-id pins, the emptiness and never-pooled
evidence, the by-name web-1 refusal, the heal-or-refuse classifier and the weight gate that withholds data until the readiness
and marker evidence are green. `requires_cpo_signoff: true`.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_FRESH_BOOT_READY for host=soleur-web-2 (once per instance) and the daily luks-monitor probe row
  cadence: per birth and daily
  alert_target: Sentry issue owners via the escrow-stage alert rule; Better Stack query for the rows; the workflow run log and step summary for the dispatcher
  configured_in: apps/web-platform/infra/workspaces-luks-provision.sh, apps/web-platform/infra/luks-monitor.sh, apps/web-platform/infra/sentry/issue-alerts.tf
error_reporting:
  destination: Sentry web-platform via SENTRY_DSN (asserted non-empty at S2) and the GitHub Actions workflow run log
  fail_loud: every refusal and failure is an `::error::` annotation naming the stage, the classifier verdict or the heal window; the run ends RED and the step summary names the window
failure_modes:
  - mode: emptiness evidence missing, gappy, zero or over the ceiling (workflow run log `::error::` from the emptiness step; verdict line RED reason=...)
    detection: S5 verdict in the workflow run log, exported as a step output and printed in the dispatch summary
    alert_route: workflow run RED to the dispatcher (GitHub notification)
  - mode: classifier refusal or an unhealable state (workflow run log `::error::` naming refuse:<reason>)
    detection: S4 verdict in the workflow run log before any write
    alert_route: workflow run RED to the dispatcher; the runbook table gives the next step per verdict
  - mode: detach, delete, state rm, plan gate or apply failure (workflow run log `::error::` naming the step)
    detection: the failing step's `::error::` annotation plus the failure step's heal-window summary
    alert_route: workflow run RED to the dispatcher; re-dispatch heals the window or refuses before writing
  - mode: host born but escrow missing or luks_arm not formatted
    detection: ready-poll verdict RED in the workflow run log; the verify leg keeps the soak marker absent
    alert_route: Sentry escrow-stage rule; weight gate stays closed
  - mode: readiness, recovery check or reboot failed after the apply
    detection: the failing step's `::error::` in the workflow run log; a re-dispatch resumes (resume:post_apply) without replacing anything
    alert_route: workflow run RED to the dispatcher
  - mode: reboot issued but no reopen
    detection: follow-through reboot-seen arm after rebirth + 3d (the window closes at earliest + 4d and the follow-through fails loudly then)
    alert_route: follow-through tracker on #6931
logs:
  where: GitHub Actions run log and step summary; Better Stack for the host rows
  retention: Actions default; Better Stack per its plan
discoverability_test:
  command: bash scripts/followthroughs/web2-luks-live-6931.sh
  expected_output: CANNOT ESTABLISH
  credentials_required: Better Stack query credentials (Doppler prd_terraform) — the readiness and probe rows exist only in Better Stack, so no unauthenticated probe verifies the same property
```

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.workspaces["web-2"]
    mechanism: plaintext-exception until the dispatch, then luks (guest-side, ADR-263)
    evidence: the encryption-posture ledger row for hcloud_volume.workspaces; after the dispatch the device_binding of the luks row
    defends_against: a seized or RMA'd disk, a raw volume snapshot
    does_not_defend: a compromised running host (the volume is unlocked while mounted), a leaked passphrase (held in Doppler and Terraform state, unversioned bucket, #7992), a header whose backup is stale after a later re-key
    disclosed_as: not-publicly-claimed for web-2 (docs/legal "Encrypted workspace storage" is scoped to web-1's volume)
    live_verification: unavailable:until the ledger row flips at dispatch time
in_transit:
  - connection: workflow runner -> Hetzner Cloud API, Better Stack query API, Cloudflare R2 (ranged GET)
    enforced_at: .github/workflows/web2-luks-rebirth.yml (curl over https, no -k, token via stdin config)
    tls: https, runner default minimum
    cert_verification: on
    does_not_defend: a compromised runner or a leaked token
    disclosed_as: not-publicly-claimed
exception:
  justification: the live web-2 volume is ext4 and empty; the dispatch this plan prepares retires the exception
  tracking_issue: "#9372"
  reevaluate_when: the dispatch completes, or 2026-10-22 arrives first
  expires_on: 2026-10-22
```

## Infrastructure (IaC)

### Terraform changes
None. The workflow runs the existing root (`apps/web-platform/infra`) with the five targets below and consumes no new variable:
`hcloud_server.web["web-2"]` (replaced), `hcloud_server_network.web["web-2"]`, `hcloud_volume.workspaces["web-2"]`,
`hcloud_volume_attachment.workspaces["web-2"]`, `hcloud_firewall_attachment.web`. Sensitive values (`HCLOUD_TOKEN`, the R2
backend pair, `SENTRY_DSN`) come from the tiered Doppler loader.

### Apply path
Option (c): `-replace` of the server, because `prevent_destroy` forbids a Terraform volume destroy; the volume is removed by
the Hetzner API and forgotten with `terraform state rm` first, which is why a state-absent create is planned.

### Distinctness / drift safeguards
The web-class passphrase is not touched (`luks_passphrase_rotations` 0). The key and volume id are pinned as constants.

### Vendor-tier reality check
Hetzner refuses to delete an attached volume (detach first); Better Stack hot retention is about 40 minutes, so the 7-day
window needs the archive arm.

## Architecture Decision (ADR/C4)

### ADR
Amend ADR-263 (addendum 2026-10-05): the single-use rebirth decision, its allow-set contract, its refusal and heal rules and
its retirement. It extends ADR-263; no new ADR.

### C4 views
Read all three `.c4` files. The workflow adds no actor or system: the Hetzner API, Doppler, Better Stack, Cloudflare R2 and
the GitHub-environment reviewer are already modelled. The `doppler -> hetzner` edge names `apply-web-escrow-create.yml`; the
same edge gains a clause naming `web2-luks-rebirth.yml`, and `model.likec4.json` is regenerated with
`bash plugins/soleur/scripts/render-c4-model.sh`. `plugins/soleur/test/c4-count-parity.test.sh` stays green.

### Sequencing
The addendum describes the target state now with the dispatch pending (`adopting` posture, as ADR-263 already is).

## Guard Contract

### Guard 1 — web-host rebirth plan gate

**Property.** The rebirth plan changes exactly the allowed addresses with exactly the allowed actions, destroys only objects
whose physical ids match the pins captured from Hetzner, and can never reach web-1.

**Assembly.** `web_host_rebirth_gate` in `tests/scripts/lib/web-host-rebirth-gate.sh`, called at S7 (`pre`) and S10 (`post`) in
the workflow; the shared preamble and the by-name refusal it begins with; the allow-set table; the pin arguments; the plan
files graded. One chokepoint: both calls source the same function.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Plan carries a volume `["delete"]`, `["forget"]` or `["delete","create"]` | RED |
| 2 | Gate invoked with an empty plan or the call removed from S7 or S10 (the guard's own dispatch) | RED |
| 3 | A second server create after a compliant first | RED |
| 4 | Server destroy whose `before.id` differs from the captured id | RED |
| 5 | Attachment destroy whose `before.volume_id` is not `106466179` | RED |
| 6 | `format` is `ext4` or unknown on the planned volume, or two volume entries | RED |
| 7 | web-1 key supplied, or a web-1 server update appears | RED |
| 8 | Passphrase-pair address with any action, or an extra address | RED |
| 9 | `pre` plan with the volume not a no-op, or `post` plan with the volume a no-op | RED |
| 10 | Firewall attachment `["delete"]` | RED |
| 11 | `reboot_updates` > 0 on web-1 (pulled in through the firewall attachment's whole-map reference), or an `actions: []` entry (`undecidable_entries`) | RED |
| 12 | NIC `before.server_id` or server `before.name` pin wrong; NIC, attachment or firewall entry missing (requirement arms) | RED |
| 13 | `forget` at a non-volume address (RED); `no-op` and `read` entries at other addresses are allowed, as in the birth gate (must-PASS) | RED / PASS |
| 14 | The raw-volume check drifts from `web-host-birth-gate.sh`'s inline check (parity row over both bodies) | RED |

**Harness rows.** Delete the suite's assertion calls: the suite must exit non-zero on its own floor. A must-PASS fixture that is
not the canonical: `post` mode with the server already absent (`["create"]` only).

**Anchor.** The pins (server id, volume id) are read from Hetzner at S3 and compared with constants in the workflow; a commit
that edits the constant must also edit the live ids the evidence step reads, which the environment reviewer sees in the run.

### Guard 2 — state classifier

**Property.** Every combination of Hetzner and state observations maps to proceed, a named heal window, or a refusal before any write.

**Assembly.** `web2_rebirth_classify`; its callers S4 and S8-S9; the six refuse rules; the heal windows W0-W3; the `state rm`
serial/lineage/id check.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Each refuse rule inverted in turn (six rows) | RED |
| 2 | Classifier call removed from S4, or its output ignored (own dispatch) | RED |
| 3 | A second volume with the name after a compliant first | RED |
| 4 | `state rm` serial not +1, lineage changed, or id not the pin | RED |
| 5 | Each heal window returns the wrong action | RED |

### Guard 3 — workflow structure and writing steps

**Property.** No write is reachable under `plan_only`, the preflight precedes the first Hetzner call, the destroy steps run only
after the `pre` grade, and the constants and concurrency literals are the ones the other appliers use.

**Assembly.** `.github/workflows/web2-luks-rebirth.yml` step bodies; `web2-luks-rebirth-workflow.test.sh`; the parity and census tests.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `if: inputs.plan_only != true` from S8 | RED |
| 2 | Move the escrow preflight below the first Hetzner call | RED |
| 3 | Delete the suite's step-execution rows (own dispatch), or add a second Hetzner write step | RED |
| 4 | Typed confirm or pinned id no longer equals its constant | RED |
| 5 | Flip precondition reverted; `escrow!=ok` or `luks_arm!=formatted` no longer RED; stale READY row accepted | RED |
| 6 | Concurrency group literal changed; a plan artifact uploaded; token in argv | RED |
| 7 | S12 header-UUID, magic or test-passphrase check made non-fatal; passphrase on argv or in a file | RED |
| 7b | S13 reboot target not re-resolved by name, equals web-1's id, or differs from the post-apply state id | RED |
| 8 | `w2l_judge` marker-absent no longer requires `w2l_reboot_seen`; an `unknown` or equal `boot_id` accepted | RED |

**Harness rows.** A step with no `shell:` key is run under `bash -e`, not `bash -eo pipefail`. A must-PASS run with `plan_only`
true and every write step skipped.

### Guard 4 — emptiness evidence

**Property.** The volume is declared empty only from a complete, fresh, bounded 7-day series for the right host, mountpoint and device size.

**Assembly.** `scripts/web2-rebirth-emptiness.sh`; its SQL; the verdict thresholds; S5.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Zero rows, gap hours, stale newest row | RED |
| 2 | Maximum over the ceiling, or spread over the limit | RED |
| 3 | Wrong host, wrong mountpoint, `total_bytes` out of range; a transport failure treated as a verdict | RED |
| 4 | Verdict ignored by S5 (own dispatch) | RED |

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering
**Status:** reviewed
**Assessment:** CTO ruling 2026-10-05 (see Research Insights): new workflow and gate, two graded plans, physical-id pins, no
refusal to format on missing escrow, flip precondition, emptiness rules, reboot-seen follow-through arm.

### Product
**Status:** reviewed
**Assessment:** CPO APPROVE-WITH-CONDITIONS (single-user incident); the ten conditions are folded into S5, S12-S13, the
reboot-seen marker dependency, the dispatch summary list and the closing checklist (see Research Insights).

### Legal
**Status:** reviewed
**Assessment:** CLO NO LEGAL BLOCKER with conditions: no legal-path edit in this PR; conditioned ADR addendum; strengthened
S12 failing the run; no "recoverable / restore-tested / Art. 32(1)(c) satisfied" claim; closing change records run id, SHA,
approver and timestamps; supersession markers listed in the closing checklist.

## Open Code-Review Overlap

None recorded yet; the check runs once `## Files to Edit` is final (see Phase 0).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Implement #9372: the single-use, gated workflow that converts the live web-2 to LUKS-at-boot by a volume rebirth." | Proposed Solution, Phases 1-5 | mapped |
| 2 | "OFFLINE ONLY ... do NOT dispatch it, run terraform apply, mint a token, or write to Doppler." | Overview; AC 1 | mapped |
| 3 | "The by-name web-1 refusal in tests/scripts/lib/web-host-replace-gate.sh must stay first" | Guard 1 assembly; AC 3 | mapped |
| 4 | "Run bash scripts/web-host-escrow-preflight.sh before the first destructive step" | S2; Guard 3 row 2 | mapped |
| 5 | "Delete the volume through the Hetzner API first, then remove that one state address" | S8, S9 | mapped |
| 6 | "web-host-create for web-2 with an explicit image_tag ... preceded by a check that the image's host-script content-hash label equals host_scripts_content_hash" | S6, S10 (replace-with-create per CTO) | mapped |
| 7 | "Evidence with no SSH: SOLEUR_FRESH_BOOT_READY ... a workflow-issued hcloud reboot then a luks-monitor probe row" | S11, S13, follow-through arm | mapped |
| 8 | "Verify the destroy mechanism against destroy-guard-filter-web-platform.jq with a plan fixture" | Phase 1 fixtures; AC 6 | mapped |
| 9 | "Technical forks ... go to the CTO agent" | CTO ruling | mapped |
| 10 | "Do not touch any file that triggers the deploy_pipeline_fix auto-apply" | Files lists (no trigger file edited) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Two graded plans (pre/post) | "Verify the destroy mechanism against destroy-guard-filter-web-platform.jq with a plan fixture" | asked (CTO refinement) |
| Reboot-seen follow-through arm | "a workflow-issued hcloud reboot then a luks-monitor probe row with a new boot_id" | asked |
| Flip precondition on the apply path | "Flip the rotation HALT's create exemption" (issue comment item 4) | asked |
| Birth-time recovery check | "Define and test the recovery path" (issue comment item 2) | asked |
| Closing checklist | "retire every coupled artifact together so none is forgotten" (issue comment) | asked |

### Split Assessment

- Subsystems touched: 6 — `.github/workflows`, `tests/scripts`, `apps/web-platform/infra`, `scripts`, `plugins/soleur/test`, `knowledge-base`
- Planned files: about 24 | Estimated changed lines: about 3500
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the workflow, its gate, its suite and the registrations that keep required checks green are
  mutually dependent (a workflow without its registrations fails the parity census; a gate without its fixtures is unproven).

## Files to Create

- `.github/workflows/web2-luks-rebirth.yml`
- `tests/scripts/lib/web-host-rebirth-gate.sh`
- `tests/scripts/lib/web2-rebirth-classify.sh`
- `tests/scripts/test-web-host-rebirth-gate.sh` and `tests/scripts/fixtures/web-host-rebirth/*.json` (synthesized)
- `scripts/web2-rebirth-emptiness.sh` and its test
- `apps/web-platform/infra/web2-luks-rebirth-workflow.test.sh`
- `knowledge-base/engineering/operations/runbooks/web2-luks-rebirth.md`
- `knowledge-base/project/specs/feat-one-shot-9372-web2-luks-rebirth-workflow/{tasks.md,session-state.md}`

## Files to Edit

- `scripts/lib/web2-luks-rows.sh` (`w2l_reboot_seen`, called from `w2l_judge`), `scripts/followthroughs/web2-luks-live-6931.sh` and their tests, including the marker-writer suite's expectations
- `scripts/test-all.sh`, `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` (suites under `tests/scripts/` and `scripts/`; precedent `tests/scripts/web-host-replace-gate`)
- `apps/web-platform/infra/suite-shard-legs.tsv`, `suite-durations.tsv`, `run-registered-suites.sh`
- `scripts/guard-vacuity-floor.test.sh` (only if a new suite carries a `-lt` floor)
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `knowledge-base/engineering/architecture/diagrams/model.c4`, `model.likec4.json`
- `knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md`
- `knowledge-base/engineering/operations/runbooks/web-host-birth.md`, `web-host-replace.md` (pointer lines)

No `.tf` file and no `deploy_pipeline_fix` trigger file is edited.

## Test Scenarios

1. Given a `pre` plan carrying a volume delete, when graded, then the gate refuses (Guard 1 row 1).
2. Given the pinned volume 404s and state still holds the address, when classified, then `heal:delete-done`.
3. Given `plan_only` true, when the workflow's step bodies run under `bash -e` with stubs, then no write step executes.
4. Given a READY row older than the run anchor, when S11 reads it, then RED.
5. Given the escrow-create workflow still present, when S7 runs on an apply, then the flip precondition fails.
6. Given a probe row with the same `boot_id` as the readiness row, when the follow-through runs, then it is NOT YET.

## Dependencies & Risks

- **The first live query is the positive control** for the Better Stack JSON paths; the PR states they are unconfirmed.
- **`dm-*` exclusion** is unverified in either direction; evidence is not claimed to vanish after LUKS.
- **The R2 read credential** may be write-capable (#9461); the runbook says so rather than minting one.
- **Per-dispatch authorization** is the environment reviewer's, plus the owner's explicit go-ahead for each dispatch.
- **Timing.** The exception expires 2026-10-22. Decision date 2026-10-15: either the dispatch has run and the ledger flip is in
  review, or the exception is extended citing #6931 (a compliance event, recorded in the closing change). The host-key pin
  re-capture is a tracked step of the closing change, not an afterthought.
- **Marker semantics change.** `w2l_judge` marker-absent now needs a reboot-seen probe row. web-2 has no marker and no LUKS probe
  rows today, so live behaviour is unchanged until the rebirth; the marker-writer suite is updated in the same change.

## Acceptance Criteria

- [ ] AC1 — The change runs nothing: no workflow dispatch, no terraform apply, no token mint, no Doppler write (review of the PR's commands and the suite's stubs).
- [ ] AC2 — `web-host-rebirth-gate.sh` implements the allow-set table in both modes; Guard 1's matrix rows are all RED when mutated (sandbox battery).
- [ ] AC3 — The by-name web-1 refusal is the gate's first statement and `web-host-replace-gate.sh` is byte-unchanged (`git diff origin/main -- tests/scripts/lib/web-host-replace-gate.sh` empty).
- [ ] AC4 — The classifier returns the documented verdict for every refuse rule and heal window (Guard 2).
- [ ] AC5 — The workflow's writing steps are covered by step-body execution under `bash -e`; no write is reachable under `plan_only` (Guard 3).
- [ ] AC6 — A tracked plan fixture grades correctly against `destroy-guard-filter-web-platform.jq` counters (`luks_passphrase_rotations`, `undecidable_entries`, `reboot_updates`).
- [ ] AC7 — The emptiness helper passes and fails on the rows in Guard 4; a transport failure is not a verdict.
- [ ] AC8 — `w2l_reboot_seen` is required by both the marker judge (absent branch) and the follow-through; equal or `unknown` `boot_id` is RED; the marker-writer and follow-through suites pass.
- [ ] AC9 — Registrations: suite rows, bounds, vacuity-floor entry, parity census (count and five-target pin), escrow census wording, C4 clause and regenerated JSON; `check-adr-ordinals`, `lint-guard-contract.py`, c4 tests and markdown lint pass.
- [ ] AC10 — Runbook and ADR-263 addendum state only what was measured and name what is unconfirmed; the closing checklist lists the retirement of both single-use workflows.
- [ ] AC11 — No `.tf` file and no `deploy_pipeline_fix` trigger file is in the diff (`git diff --name-only origin/main...HEAD`).

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty, `TBD`, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `single-user incident`.
- Do not add the volume to a destroy-mode plan; dependents include the firewall attachment, which must only UPDATE.
- `plan_only` runs must print the flip precondition as PENDING, not skip it silently.
- The Better Stack JSON paths and the `dm-*` behaviour are unconfirmed until the first live query; fail closed on any absence.

## Plan-review fixes (architecture review, 2026-10-05, PROCEED-WITH-FIXES)

Applied above: `actions: read`; S2/S2b split with the exact preflight step shape; S13 reboot-target pin and Guard 3 row 7b;
Guard 1 rows 11-14; closing-checklist item 2b; registrations (`test-all.sh`, root TSVs, parity env equality and five-target
pin row); cuts (escrow-preflight edit, row-count/spread/diagnostic emptiness rules, token-compare `w2l_reboot_seen`).
Also decided here:

- **Orphan volume.** An apply that dies after the Hetzner volume create but before the state write leaves a raw, state-less
  volume. The classifier returns `refuse:orphan_raw_volume` with a runbook arm (delete it through the same pinned API path
  in a reviewed re-dispatch, never import by hand); it is never silently adopted.
- **Never-pooled marker read (S5).** The marker lives in the `prd_workspaces_luks_marker` Doppler config, which the tiered
  loader token may not reach. S5 reads the key NAME only, with `DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER` bound to that one step
  (as `web2_marker` binds it); an unreadable config is a refusal, never "absent". Phase 0 confirms the binding exists for this workflow.
- **Environment.** `web-platform-infra-apply` is used (not `infra-privileged`) because it carries a human reviewer set covered
  by the DP-11 F8 non-empty-reviewers guard; the forget and escrow-create precedents run non-destructive-to-hosts operations.
- **Tests that change with `w2l_reboot_seen`.** `scripts/followthroughs/web2-luks-live-6931.test.sh` (row helpers default both
  rows to one `boot_id`; T04 inverts), `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` Guard 3 fixtures,
  its header comment ("never a boot_id equality") and mutations 9, 11 and 16; re-run `lb-weight-gate-with-marker.test.sh` and
  `preflight-discoverability-test.test.ts`.

## Review round 1 (11-seat panel at ef785e632c, 2026-10-05): structural-cause roll-up and dispositions

**Structural cause (one gap, many instances).** The destructive path's wiring was pinned by what each step DECIDES and not by whether the decision is OBEYED:
a skipped evidence step, an `if:` widened with `always()`, a `|| true`, an unpinned apply operand, an unclassified new write step and an
unexercised presence proof all left the suites green (measured by four seats). Fixed at the chokepoint, not instance by instance:
`scripts/web2-rebirth.sh delete-volume` refuses unless the emptiness, never-pooled and pre-plan proofs are present (each is the step's own
output, empty when skipped) and every write subcommand refuses unless `APPLY=yes`; the workflow suite classifies EVERY step as read-only or write,
pins each write step's `if:` to an exact spelling, pins the apply operand to `tfplan-post`, drives the apply, readiness and recovery step bodies,
and carries a positive control for its own filter (the first draft of that filter errored silently and passed).

**Fixed inline (each with a row that reds without it):** nic-wait-gate scan (CI red) now names the rebirth's key-literal targets explicitly;
discoverability baseline 44 to 45 and the Observability block's layer citations; the gate is visible to the plan-gate-preamble census and
dedupes violations; the classifier gained `resume:post_apply` (post-apply failures were unresumable), `refuse:orphan_server`,
`refuse:inconsistent_pin_listing` and a foreign-volume refusal in every heal window; `heal:detach_done` no longer dead-ends on the freshness bound
(`W2R_DETACHED`); emptiness gained a non-zero floor (a missing value path read as 0) and the 64 MiB spread rule plan review had cut; never-pooled
refuses any list shape it cannot interpret; the readiness anchor is web-2's own Hetzner creation time; the `image_tag` strip (a `v` input burned a
dispatch); cryptsetup is installed with retries BEFORE the destructive steps; the summary claims only what the run measured and lists the
evidence the CPO/CLO required; flip-precondition rows run in a sandbox (they were time-bombed); parity rows for the Hetzner helper copies and the
volume name/label literals; the follow-through and marker suites gained the readiness-boot_id-unknown row; stale `boot_id`, custody and PASS-list prose.

**Deviations from this plan, recorded:** (1) S5's "anti-pooling check green at the ref" and the summary's "serving weight 0" are NOT implemented: no
weight orchestrator exists in the repo, so web-2's weight is not measurable here; the summary no longer asserts it and the dispatch is only from
`main`, where `lb-weight-gate.test.sh` has run. (2) S12(a) compares the escrowed header's own UUID to its object name, not to the live volume's UUID
(unobservable without host access). (3) The 1 GiB emptiness ceiling stays coarse by necessity (the real empty baseline is unmeasured offline): the
owner approves on the printed values.

**Accepted, not changed (P3 or out of scope), with the reason:** the env-name collision risk for `APPLY` against a Doppler secret of that name needs
write access to the Tier-B Doppler project, which already owns the infra; `terraform state rm` cannot prevent a lost update on the lockless R2
backend (detected after the fact, #7992); the post plan cannot be graded before the irreversible delete (a refused post plan leaves a safe stuck
state the classifier heals); the firewall-attachment `update` is pinned by action only (its `server_ids` are unknown at plan time); the stale
CONSUMERS comment on the marker token in `workspaces-luks-fresh-boot.tf` is corrected in the closing change (a `.tf` edit would wake the paused
push-apply); the C4 clause stays on the `doppler -> hetzner` edge. No scope-out issue was filed.
