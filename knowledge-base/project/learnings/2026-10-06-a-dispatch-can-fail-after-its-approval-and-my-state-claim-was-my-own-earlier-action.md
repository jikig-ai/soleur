# Learning: a gated dispatch can spend its approval before it fails, and a state claim written from memory contradicted the live state

## Problem

Resuming the web-2 LUKS rebirth (#9372) hit one defect class twice and one claim-hygiene error once.

1. **Approval spent on a run that could not work.** Both the first plan-only dispatch and the first `web-host-replace` dispatch failed in the image-digest step, which runs AFTER the `web-platform-infra-apply` environment approval. The first used a plugin release tag (`v3.324.0`; those are the plugin component, not the web-platform image, which is versioned by the `web-v*` releases and tagged `v0.326.0`). The second used `v0.326.0` on a workflow whose validator accepts `^v?X.Y.Z$` but whose resolver prepends its own `v`, so it became `vv0.326.0`. The rebirth workflow strips the `v` and says why in a comment; `apply-web-platform-infra.yml` does not (tracked as #9669). Neither failure wrote anything, but each spent a single-use approval and a dispatch go-ahead.
2. **A state claim contradicted the live state.** A review fix wrote that `apply-web-platform-infra.yml` "DOES fire on the merge". The workflow had been re-paused by the same session earlier, so it did not. QA read the live state and caught it.
3. **The replaced web-2 went dark after a soft hcloud reboot** (CPU 0%, no telemetry, ports refused, no Sentry stage event). A second replace brought it back and the Sentry boot trail reached `fresh_boot_ready` (`luks_arm=opened`). The cause of the first dark boot is unknown. This is evidence, not a LUKS claim: the graded reboot proof does not exist yet.

## Solution

- Derive the image tag from the live version the running fleet reports (`/health` `.version`), not from the newest release, and confirm the tag exists as a web-platform image before dispatching. For a workflow with no `v` strip, pass the bare version. #9669 tracks the fix.
- Before writing any sentence about a workflow's enabled state, read it (`gh api repos/<o>/<r>/actions/workflows/<file> --jq .state`) at the time of writing; a state this session changed is the likeliest to be wrong in prose.
- Treat an accepted reboot action as a request, not a result: confirm with an independent signal (telemetry rows, Hetzner CPU metrics, port state) before reading a host as up.

## Key Insight

A pre-approval validator that accepts a spelling the post-approval step rejects is a trap that bills the operator's approval. Check where each gate sits relative to the approval, and make validation reject exactly what the later steps reject.

## Session Errors

1. **Plan-only run #1 used the plugin tag `v3.324.0` as an image tag** — failed at the digest step, after the approval. Recovery: found the web-platform version via `/health` and re-dispatched with `v0.326.0`. **Prevention:** derive the tag from `/health` `.version` and confirm it before dispatching.
2. **First `web-host-replace` dispatch used `v0.326.0` and became `vv0.326.0`** — failed after the approval before any destroy. Recovery: re-dispatched with `0.326.0`. **Prevention:** #9669 (strip the `v`); until then use the bare version on `apply-web-platform-infra.yml`.
3. **Replaced web-2 dark after a soft hcloud reboot; cause unproven.** Recovery: a second replace. **Prevention:** after any reboot request, confirm with telemetry and ports; the graded reboot proof stays the only LUKS evidence.
4. **A review fix stated `apply-web-platform-infra.yml` fires on merge while it was `disabled_manually`** — caught by QA reading live state. Recovery: separated trigger from current state in the plan. **Prevention:** read the live workflow state when writing the claim.
5. **A local `terraform plan` could not run** (Terraform 1.9.8 vs ≥1.10; `hcloud_token`, `cf_api_token_r2`, `doppler_token_tf` absent from `prd_terraform`). Recovery: applied through CI. **Prevention:** one sharp-edge bullet added to the `admin-ip-refresh` skill.
6. **The first ADMIN_IPS membership check split on commas, but the value is a JSON list** — it printed "not in list" from a wrong parse. Recovery: re-checked with `jq`/grep on the JSON form. **Prevention:** parse a structured secret with its own format, and confirm a positive control.
7. **An AskUserQuestion was denied by the technical-fork hook** because it read as an investigation choice. Recovery: re-worded as an authorization naming the production write. **Prevention:** name the action being authorized.
8. **`doppler run --name-transformer none` is not a valid transformer.** Recovery: dropped the flag. **Prevention:** none needed beyond reading the error.
9. **A foreground `gh run watch` was rejected by the user as too long a block.** Recovery: switched to a Monitor on the run. **Prevention:** poll with Monitor, as `hr-monitor-not-run-in-background-for-polling` already says.
10. **The stop hook blocked about ten closings** that named a first-person future action. Recovery: state the blocking condition in a `<stop>` gate, not a promise. **Prevention:** write closings as state.

## Tags
category: workflow-issues
module: infra, deploy-pipeline
