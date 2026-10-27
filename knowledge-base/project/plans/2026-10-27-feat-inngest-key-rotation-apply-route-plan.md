---
title: "INNGEST_SIGNING_KEY / INNGEST_EVENT_KEY rotation apply route: minimal apply_target for the dedicated and app copies"
date: 2026-10-27
slug: inngest-key-rotation-apply-route
branch: feat-one-shot-10540-inngest-key-rotation-route
issue: 10540
closes: 10540
type: feat
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

<!-- lane: no spec.md exists for this branch, so lane defaulted to cross-domain (TR2 fail-closed). -->
<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 review note: the whole route is automated and IaC-routed (Terraform -replace plus a workflow). The only phrases the write guard matches are verbatim quotes of the issue text and runbook wording (the issue says the app copy is copied "out of band"), which this plan replaces. The CTO agent reviewed the infrastructure routing on 2026-10-27. -->

## Overview

Build the repo-side route that a later, owner-authorised rotation of the two Inngest shared secrets will travel through. The route covers the dedicated-host copy (`soleur-inngest/prd`) and the web app copy (`soleur/prd`) of each key, the same-window event-key rotation, and the back-to-back host restart and fleet redeploy. This change delivers the route only. It executes no rotation and no production apply; the first (and only) dispatch this change permits itself is a read-only `mode=plan` rehearsal after merge.

Three facts found while planning reshape the issue's text, and each was ruled by the CTO agent (see Research Insights and `decision-challenges.md`):

1. The issue's "minimal apply_target" cannot be a new job in `apply-web-platform-infra.yml`: that file is 489,696 bytes against a 490,000-byte gate. The route is a dedicated workflow, `.github/workflows/inngest-key-rotate.yml`.
2. The runbook's "restart `inngest-server` with `restart-inngest-server.yml`" does not reach the dedicated host. The `/hooks` channel terminates on web-1, which refuses to restart its quiesced scheduler. The only no-SSH lever that reaches 10.0.1.40 is a Hetzner control-plane soft reboot, so the route reboots the host.
3. Terraform prints a `random_id`'s `id` (the key bytes in base64url) on every create, destroy and refresh line, and this repository is public. The route therefore never lets raw Terraform output reach a log.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited | Check | Result |
|---|---|---|
| #10540 | `gh issue view` | OPEN, p1-high, label `deferred-scope-out`, milestone "Phase 4: Validate + Scale". Held. |
| #10205 (parent epic) | `gh issue view` | OPEN ("complete the zot registry arc"). Held; the PR body uses `Ref #10205`, never `Closes`. |
| #11215 (48 h TLS soak) | `gh issue view` | OPEN; directive `earliest=2026-10-28T13:56:10Z`. Held. The route refuses until it is closed COMPLETED. |
| #11218 (owner-ask probe) | `gh issue view` | OPEN; treats #10540 closed COMPLETED as "route done". Held. |
| #10542, #10543 (loss defects the runbook wants fixed before A5) | `gh issue view` | Both CLOSED. Held. |
| PR #11287 | `gh pr view` | Draft, not in the merge queue. Held; pushes are allowed. |
| "dedicated doppler_secret carries ignore_changes?" | read `inngest-host.tf` | **No.** `doppler_secret.inngest_{signing,event}_key_dedicated` carry no `lifecycle` block; their comment says rotation re-propagates in one apply via `-replace` on the `random_id`. The `_prd` app copies in `inngest.tf` DO carry `ignore_changes = [value]`. |
| "restart `inngest-server` (restart-inngest-server.yml)" (runbook A5 row) | read the runbook sections "Reading host state without SSH" and the web-scheduler-stopped note ("`restart-inngest-server.yml` is LB-routed to the *web* host"); `ci-deploy.sh` `inngest_quiesced_restart_refused` | **Stale.** The hook channel terminates on web-1; web-1's quiesced unit refuses `restart inngest`; `deploy-status` reports web-1, not 10.0.1.40. |
| Mechanism vs ADR corpus (grep ADR-100, ADR-294) | read `## Decision` / alternatives | ADR-100 §4 Amendment (2026-07-24) records the manual-copy contract; nothing rejects a Terraform-derived app copy. ADR-294 names #10540 as the filed follow-up. Held; both get amendments. |
| Collision pre-check | `collision-precheck.sh 10540` | Only PR #11287 (this branch). Foreign `test-all.sh` processes belong to other worktrees. |

### Property List and Cut List (Phase 0.6b)

Properties the issue buys (each is an observable outcome):

- P1. Both copies of each selected key hold a fresh value after one owner-authorised dispatch, with no value printed anywhere.
- P2. The app copy equals the host copy after the same window (the shared-channel contract of ADR-100 §4).
- P3. The event key can rotate in the same window, and only when the owner's go names it.
- P4. The running scheduler and the web fleet pick up the new values back to back, in an order that keeps the old web containers running if the scheduler is not serving.
- P5. A later flag-off rollback cannot silently carry the new key over plaintext `:8288`.
- P6. Merging this change performs no rotation and no production write.
- P7. The run leaves value-free evidence that it landed (for the owner's A5/A6 records).

Cut List (mechanism, property it would buy, what already covers it or why cut):

| Mechanism | Property | Disposition |
|---|---|---|
| New Tier-B job + `apply_target` option in `apply-web-platform-infra.yml` | P1 | Cut: 304 bytes of headroom under the 490,000 gate; a dedicated workflow has precedent (`workspaces-luks-cutover.yml`, `inngest-link-flip.yml`). |
| Doppler CLI `get \| set` copy of the host value into `soleur/prd` | P2 | Cut: plaintext through a shell, and no CI token can write the `soleur/prd` root generically (`DOPPLER_TOKEN_WRITE` is `prd_terraform`-only; `DOPPLER_TOKEN_GIT_DATA_FLAG` is purpose-limited, bound to another environment, scope unverified). Terraform-derivation uses the provider token that already writes `soleur/prd`. |
| New narrow write token / `restart-inngest-server.yml` / `inngest-host-replace` as restart lever | P4 | Cut: new credential surface; cannot reach 10.0.1.40; replace is owner-gated twice and heavy. |
| `INNGEST_SIGNING_KEY_FALLBACK` two-phase rotation | P4 | Cut: the SDK supports it, but a self-hosted-server flag is unverified and the event key has no fallback at all. |
| `mode=reboot-check` (a reboot with no key change, own owner go, required before `rotate`) | P4 | Cut (CTO R2): a second sole-scheduler downtime for the same LUKS-reopen risk; the two-phase order already separates a host problem from the app key, and the A4 soak means the host has not rebooted since 2026-10-20. Phase 0 reads the rehearsal runbook's reboot leg for evidence and the owner's go states the residual. |
| Web-host hook for an HTTP-level "old key rejected" check | P7 | Deferred, tracked as #11292 (non-blocking; a single-key server refuses the old key by construction and the old value exists nowhere after rotation). |
| Hard block of `inngest-link-flip.yml action=off` after rotation | P5 | Cut: it would remove the rollback during an incident; an extra explicit confirm gives the same protection against the silent case. |
| `removed {}` / destroy of the now-unreferenced `random_id.inngest_{signing,event}_key_prd` | none | Deferred, tracked as #11293 (their destroy handling in the shape gate and parity tests is unverified). |
| Rotating the `_dev` copies, `INNGEST_MANUAL_TRIGGER_SECRET`, `INNGEST_REDIS_PASSWORD` | none | Out of scope: the issue names the signing and event keys only. |

### Findings that shape the design

- **Terraform prints key bytes.** Measured 2026-10-27 with a throwaway 8-byte `random_id` in a scratch directory (no repository secret was read): `random_id.t: Creation complete after 0s [id=<11-char base64url>]`. `hex` is not sensitive either, so a `terraform plan` of a replace prints the OLD `hex`. The repository is public (`gh repo view --json visibility`). Existing dispatch jobs that print Terraform output unfiltered may already have published the dedicated pair; filed as #11294 (type/security, p1). The new route captures every Terraform stream to a file under `$RUNNER_TEMP`, never prints it, never uploads the plan, and emits only jq-derived addresses and actions.
- **The shape gate refuses rotation on the existing path.** `apply_target=inngest-host` lists the dedicated `random_id`s but is additive-only (`inngest_host_shape_gate` reason `generated_secret_touched`), so it cannot be reused.
- **Dedicated pair is dispatch-applied only.** `random_id.inngest_*_dedicated` and `doppler_secret.inngest_*_dedicated` sit in the parity test's exclusion list (`terraform-target-parity.test.ts`); the app `_prd` secrets are per-merge targets (`apply-web-platform-infra.yml` (content anchor: the `-target=doppler_secret.inngest_signing_key_prd` block in the per-merge apply)).
- **The link canary proves the new key.** `ci-deploy.sh` runs a canary (`/health`, `/v1/events` with the hashed-signing-key bearer, a real event send, a registry read) before the swap when the resolver chose https. It returns 200 only if the scheduler holds the same keys as the app copy, and a failure keeps the old containers. This makes the order (scheduler first, then redeploy) mandatory.
- **Evidence for the dedicated host comes from Better Stack only.** `scripts/inngest-host-state.sh` pins `host=soleur-inngest` AND `host_role=dedicated`; the `tls-health` row (every 5 minutes) carries `boot_id`, `listener`, `fetch_rc`, `served_sha256`/`cert_sha256`. The probe timer runs `OnBootSec=90s` then hourly.
- **Soak signal is machine-readable.** Tracker #11215 closed COMPLETED is the A4 PASS (the sweeper closes it); the route reads `state`/`stateReason`.
- **The `done-owner` marker survives a reboot** (root disk) and is destroyed only by a replace, so the start guard takes the ALLOW arm. Unverified: the production dedicated host has never been rebooted with its LUKS volume and live scheduler. The owner's go must name this.

### Institutional learnings applied

- `best-practices/2026-06-18-live-credential-rotation-and-argv-to-env-redeploy.md`: `ignore_changes=[value]` blocks rotation by tainting the `random_*` alone; replace both, check the plan shows the value change, update Doppler before the service restarts; never roll back to an argv-form image.
- `integration-issues/2026-05-29-targeted-apply-workflow-needs-new-resource-in-target-list.md`: a missing `-target` merges green and never applies; one `random_id` shared across copies makes `-replace` cascade (the design here).
- `2026-06-17-terraform-target-parity-test-guards-only-terraform-data-subset.md`: the parity test does not cover `random_id`/`doppler_secret` spellings, so the new workflow gets its own target-pinning test.
- `2026-07-23-terraform-destroy-guard-address-vs-physical-id-and-replace-recovery-arm.md`: `-replace` is destroy-then-create; a failed apply between the two strands the resource and a re-dispatch plans a bare create. The plan gate accepts `["delete","create"]` and, for the recovery arm, a bare `["create"]` whose `before` is null.
- `2026-07-17-workflow-env-gate-references-unprovisioned-environment-auto-approves.md`: a job on an unprovisioned environment auto-approves; `infra-privileged` is provisioned and has a census guard, which this workflow must satisfy.
- `2026-10-11-sole-copy-pins-the-required-check-anchor-must-not-be-a-subset-of-the-advisory-guard.md`: fail closed when a read cannot be validated; capture under `pipefail`; never print the value.

### CTO rulings (all `Ruled by CTO agent, 2026-10-27`)

| Fork | Ruling |
|---|---|
| F1 route shape | Dedicated workflow `inngest-key-rotate.yml` (dispatch-only, environment `infra-privileged`, shared concurrency group `terraform-apply-web-platform-host` on the Terraform job only). "minimal apply_target" means a minimal Terraform target set. |
| F2 app copy | Terraform-derived: `inngest.tf` app secrets take their value from the dedicated `random_id`s; keep `ignore_changes=[value]`; rotation is one apply with `-replace` on the dedicated `random_id`s and the app `doppler_secret`s. Keep the orphaned `random_id.inngest_*_key_prd` this PR. |
| F3 ordering | Forward-only: apply, reboot, wait for SERVING, canary-then-prod redeploy. No `INNGEST_SIGNING_KEY_FALLBACK`. `converge` is the retry; a second `rotate` is a new rotation. |
| F4 key scope | Required input `keys: signing\|event\|both`, no default, part of the typed confirm. |
| F5 rollback | `rotate` refuses unless the link flag resolves `1`; `inngest-link-flip.sh off` needs an extra explicit confirm once a successful rotate run exists. |
| F6 verification | Value-silent copy equality, new differs from prior, Better Stack evidence from the rebooted host, redeploy canary. HTTP-level old-key check deferred (#11292). |
| F7 dry run | Required `mode: plan\|rotate\|converge`; `plan` is the read-only rehearsal. |
| Restart lever (re-ruled) | Hetzner API soft reboot of the server named `soleur-inngest` inside the workflow; refusals listed under Guard 4; at most one POST per run; no auto-retry. |
| R1 two-phase (plan review, architecture) | Phase 1 `-replace`s only the dedicated `random_id`s and updates the dedicated secrets; reboot + verify; phase 2 `-replace`s only the app secrets, then the fleet redeploy at once. The `soleur/prd` key that unrelated deploys read is untouched until the scheduler is verified SERVING. Reboot + verify are one job under `deploy-inngest-restart`; a workflow-level group `inngest-key-rotate` (cancel false); the in-flight-run refusal re-runs immediately before apply1, reboot, apply2 and redeploy. |
| R2 | `mode=reboot-check` rejected; ACPI wait bounded at 10 minutes (no probe row with a new `boot_id` = `host_silent`); the route never hard-resets (a hard reset is a separate owner go). |
| R3 | The rotation plan gate refuses any bare `create` of `random_id.*_dedicated` except the documented recovery shape; Phase 0 reads whether the host unit has a Doppler fallback cache. Dropped: the per-merge RED fixture, the state-vs-Doppler hash, the forced-reboot arm (a stale boot key fails the redeploy canary, which is the safe detector). |
| R4 | SERVING pre-check for `rotate` only; `guard` refuses `run_attempt > 1` for `rotate`/`converge` (a re-run bypasses the owner go; only `plan` may be re-run); `converge` derives `keys` and `rotated_at` from the newest non-plan run that reached apply1 (a guard-refused run does not qualify); no age limit (copies-equal and boot-start-after-`rotated_at` decide); skips the reboot POST when a Hetzner action is running or finished after `rotated_at`; every post-apply failure prints one stop sentence with the exact `converge` command (needs the owner's per-command go; no agent runs it) and files the issue; green `converge` prints the same `S5-A5-DONE` line; the off-confirm counts any non-plan run. |
| R5 | Keep `converge`, the typed confirm and `quiet_window` (cron-quiet cannot be machine-checked); cut the in-script `kr_require_go` (YAML `needs` graph + a structure test replace it); verify = `inngest-host-state.sh` `SERVING=yes` (it includes `registry_fns`) + `boot_id` differs from the pre-reboot capture + a `tls-health` row with the new `boot_id` and `listener=1`; ADR-294 gets a one-line pointer to ADR-304; evidence lands in an issue comment, not only the step summary (summaries expire with run logs). |
| Closes | `Closes #10540` is honest only with the reboot lever, the runbook corrections, the F5 confirm, and the two follow-up issues in the same PR/tracker; otherwise `Ref`. |

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / runbook) | Reality | Plan response |
|---|---|---|
| "a minimal apply_target" | `apply-web-platform-infra.yml` is 489,696 / 490,000 bytes | Dedicated workflow; Terraform target set kept minimal (six addresses at most) |
| App copy "copied out of band per inngest.tf" | No CI token can write the `soleur/prd` root generically | Terraform-derived app copy; the SHARED-CHANNEL CONTRACT comment and the closing `ignore_changes` NOTE in `inngest.tf` rewritten |
| Runbook A5 and "Key rotation order (A5)" step 3: restart with `restart-inngest-server.yml` | Cannot reach 10.0.1.40; web-1 refuses (quiesced) | Hetzner soft reboot; runbook rows corrected in this PR |
| Runbook "Key rotation": every `doppler_secret` carries `ignore_changes`; taint `random_id.<KEY>_prd` | The dedicated pair has none, and the dedicated `random_id` becomes the source | "Key rotation" section rewritten around the route |
| Runbook "Reading host state without SSH" `deploy-status` recipe as A5 evidence | Reads web-1 | Evidence rewritten to Better Stack rows |
| Probe `inngest-a5-a6-owner-ask-10136.sh`: owner "executes the rotation" or "gives a go" | Route now exists | Ask text names the exact dispatch lines and the `S5-A5-DONE` handoff |
| Runbook: "no command for the old-key check exists, so A5 is not dispatchable by an agent" | A5 remains owner-human regardless | Wording corrected; non-blocking follow-up #11292 |

## Proposed Solution

### The route

One workflow, `.github/workflows/inngest-key-rotate.yml`, dispatch-only (a push trigger scoped to its own path exists only to register the workflow, and every job is guarded by `if: github.event_name == 'workflow_dispatch'`, as in `restart-inngest-server.yml`). `run-name: inngest-key-rotate ${{ inputs.mode }} ${{ inputs.keys }}` so other tools can tell a `plan` run from a `rotate` run.

Inputs (all consumed through `env:`, never interpolated into a `run:` body): `mode` (choice `plan|rotate|converge`, required), `keys` (choice `signing|event|both`, required), `confirm` (string), `reason` (string, required), `rotated_at` (string, `converge` only), `quiet_window` (boolean attestation).

Typed confirms (typo-guards, NOT the authorization; the authorization is the owner's in-session go naming the exact command): `rotate` needs `ROTATE-INNGEST-<KEYS>-<YYYY-MM-DD>` and `converge` needs `CONVERGE-INNGEST-<KEYS>-<YYYY-MM-DD>` (KEYS upper-cased, the UTC date of the run). `plan` needs none.

Jobs (each least-privilege; a credential is bound to the job that needs it; `infra-privileged` has no required reviewer (ADR-241), so there is no per-job approval click and no late-approval gap):

1. `guard` (no writes). Runs through `.github/actions/infra-credentials` (the census forbids reading `prd_terraform` Tier-B names outside the loader) and uses the read-only Hetzner token, not the write token. For `plan` it reports each check below as a boolean and never refuses on soak, flag or attestation; for `rotate` and `converge` it refuses, with a fixed verdict token, unless all hold: `github.run_attempt` is 1 (a re-run reuses the inputs and would bypass the owner's go; only `plan` may be re-run); mode/keys/confirm well-formed; `quiet_window` true (attests no claude cron in flight, no approved Concierge action in flight, no recent `payment_failed` pending, no Art. 15 request mid-response); link flag resolves `1` (`TF_VAR_inngest_link_tls`; `pending:*`, empty or anything else refuses); tracker #11215 is CLOSED/COMPLETED; no in-flight run of `apply-web-platform-infra`, `inngest-link-flip`, `cutover-inngest`, `deploy-inngest-image`, `web-platform-release` or another `inngest-key-rotate`; exactly one server named `soleur-inngest` with private IP 10.0.1.40; for `rotate` only, the pre-reboot host read is `SERVING=yes` with `listener=1`. Outputs the server id and the pre-reboot `boot_id`. The same in-flight refusal runs again as the first step of every write job below.
2. `apply1` (Tier-B Terraform; skipped for `converge` unless the observed state shows phase 1 not done). Environment `infra-privileged`; job-level group `terraform-apply-web-platform-host`. Records a value-silent prior hash of the host copy, plans with a fixed `-target` set and `-replace` flags derived only from the validated `keys`, runs Gate A (Guard 1: only the dedicated `random_id`s `["delete","create"]` and the dedicated `doppler_secret`s `["update"]`), and for `mode=plan` also evaluates Gate B against a plan of the app-secret replacement and stops. For `rotate` it applies, then asserts new-differs-from-prior by hashing on the pipe and printing a boolean. Between the phases the two copies legitimately differ (the G3.5 arm gate fails closed in that window; stated in the runbook).
3. `reboot` (skipped for `plan`; one job for the POST and the wait). Group `deploy-inngest-restart` (the shared inngest mutex). Holds the Hetzner write token from the loader in the POST step only, under an `env -i` allow-list, `::add-mask::`, curl stdin config. One `POST /v1/servers/<id>/actions/reboot` per run (a per-process latch refuses a second), action polled to `success`. Then polls Better Stack up to 15 minutes through `scripts/inngest-host-state.sh` and `scripts/betterstack-query.sh`: pass = the script's `SERVING=yes` (it already includes `registry_fns`; #8015 showed active plus 200 can be a diagnostic boot), `boot_id` different from the pre-reboot capture, and a `tls-health` row with that new `boot_id` and `listener=1`. No probe row with a new `boot_id` within 10 minutes of the POST is `host_silent` (the first probe row comes about 90 seconds after boot, behind the graceful stop and the LUKS reopen); a missing field is "no verdict" (script exit 5/6), never a NOT SERVING claim. Not serving or silent: stop, no retry, no hard reset, no redeploy, file one `action-required` issue, print the stop sentence. For `converge`: first read the host and the Hetzner action list; the POST happens only if the newest boot started before `rotated_at` and no reboot action is running or finished after it.
4. `apply2` (Tier-B Terraform; runs only after `reboot` passed, or in `converge` when the copies are unequal). Gate B: only the app `doppler_secret`s `["delete","create"]` (or the bare-create recovery shape with `before` null); the dedicated `random_id`s and secrets must be no-ops. It never mints a key. Asserts host-copy-equals-app-copy by hashing on the pipe, booleans only.
5. `redeploy` (skipped for `plan`). Holds the deploy-webhook credentials only. Canary-then-prod fleet redeploy through `.github/actions/dispatch-web-redeploy/track.sh` with the parity-pinned `WEB_HOST_PRIVATE_IPS` literal, immediately after `apply2`. A green `rotate` or `converge` prints the ready-to-paste `S5-A5-DONE: <UTC time ending in Z>` line and the value-free evidence block (timestamps, which keys, booleans, run URL); nothing in the workflow posts it, because the follow-through probe reads comments and an agent-posted line does not satisfy the owner record. The evidence block is also written as an issue comment on #10136 only by the owner's own paste; the run summary expires with the run logs, so the runbook tells the owner to paste the block with the `S5-A5-DONE` line.

Every post-apply failure (apply2, reboot, verify, redeploy) prints one stop-and-do-not-retry sentence plus the exact `converge` command (it needs the owner's own per-command go; no agent runs it) and files the `action-required` issue naming that action.

### Terraform change (`inngest.tf`)

`doppler_secret.inngest_signing_key_prd` value becomes `"signkey-prod-${random_id.inngest_signing_key_dedicated.hex}"` and `doppler_secret.inngest_event_key_prd` value becomes `random_id.inngest_event_key_dedicated.hex`. `ignore_changes = [value]` stays, so a per-merge plan still shows no diff. `random_id.inngest_{signing,event}_key_prd` stay in config, unreferenced, under a "retired, state-only; removal tracked in #11293" comment. The rotation runs in two phases. Phase 1 targets `random_id.inngest_{signing,event}_key_dedicated` and `doppler_secret.inngest_{signing,event}_key_dedicated` (restricted by `keys`) with `-replace` on the `random_id`s; the dedicated secrets update in place. Phase 2 targets only `doppler_secret.inngest_{signing,event}_key_prd` with `-replace`, whose value already derives from the replaced `random_id` in state. The per-merge `-target` list keeps the orphaned `_prd` `random_id`s (a no-op, commented as such). `-replace` on a `doppler_secret` is destroy-then-create (seconds with no key in `soleur/prd`; running containers keep their baked env; a deploy that starts inside the gap would fail, which the in-flight-run refusal and the quiet-window attestation cover). Phase 0 verifies the provider's replace order from the `mode=plan` output shape.

### Failure semantics

| Stage that fails | State left | Route behaviour |
|---|---|---|
| `guard` refuses | Nothing written | Fixed verdict token; fix the cause and re-dispatch |
| `apply1` fails at Gate A | Nothing written | Refusal names the first failing property; no apply |
| `apply1` fails mid-way | The dedicated copy may be half-replaced; app copy untouched | Stop sentence; a new `rotate` is a new rotation with its own confirm and go (`converge` resumes only from a completed phase 1) |
| `reboot` POST fails | Dedicated copy new, scheduler on old keys, app copy old | Stop; `converge` (reboot, wait, then apply2 and redeploy) |
| Host not serving or silent | Sole scheduler down; dedicated copy new, app copy old | Stop, no retry, no hard reset, no redeploy (web keeps running on the old app key), `action-required` issue; recovery per the runbook stage table, then `converge` |
| `apply2` fails | Copies differ | `converge` resumes at apply2 (copies unequal means phase 1 done) |
| `redeploy` canary fails | Old containers keep the old key; scheduler and Doppler have the new | `converge` runs the redeploy only (host booted after `rotated_at` and SERVING, copies equal) |
| `redeploy` reports `ok_peer_fanout_degraded` | Fleet mixed | Failure verdict; `converge` |

`converge` derives `keys` and `rotated_at` from the newest non-plan run of this workflow that reached `apply1` (a guard-refused run does not qualify; `run-name` carries the keys; owner-supplied values are optional and must agree). It never mints a key, refuses to redeploy while the host reads NOT SERVING, issues at most one reboot POST per run and none when the newest boot started after `rotated_at` or a Hetzner reboot action is running or finished after it. There is no age limit: the copies-equal check and the boot-start-after-`rotated_at` check decide what runs, and a stale run only yields a redeploy. A GitHub "Re-run failed jobs" on `rotate` or `converge` is refused (`run_attempt` must be 1); only `plan` may be re-run.

### Rollback accounting (P5)

Two guards. `rotate` refuses unless the link flag is `1`, so the new key never rides plaintext. `scripts/inngest-link-flip.sh` gains a check at the chokepoint `flip_apply_flag off`: when any non-`plan` run of `inngest-key-rotate.yml` exists (matched on `displayTitle` from `run-name`, queried with `--limit 200`; a rotate that applied and then failed is the exact case that already has the new key live, and a false positive only costs one extra confirm), `off` requires a new input `confirm_off_after_rotation=OFF-AFTER-ROTATION` whose error text states that the new key would cross plaintext `:8288` again and a re-rotation follows. The `revert` path simply logs the refusal through its existing warning branch (no special case). Accepted residuals, stated in ADR-304 and the runbook: GitHub's default 90-day run retention expires the marker, deleted run history resets it, and dispatching `apply-web-platform-infra.yml apply_target=inngest-link-flag inngest_link_value=off` directly bypasses the script. Phase 0 also verifies whether `flip` can start from a flag already at `1`; if it can, `flip` refuses while a rotation run exists (re-enabling TLS after a rollback goes through `off` first), because the revert path returns to the flag-absent state. Runbook "Rollback" step 3 is rewritten to match.

## Implementation Phases

Phase 0 — verify before building (read-only; no production contact beyond reads):

- 0.1 Measure on a throwaway root that `terraform plan -replace` of a `doppler_secret` + `random_id` pair prints `hex`/`id` (confirms the scrub requirement) and record the scrub regex set against synthesized values.
- 0.2 Read `.github/actions/infra-credentials/action.yml` for the exact exported names (`DOPPLER_TOKEN_TF`, `HCLOUD_TOKEN`, `TF_STATE_AWS_*`) and confirm the loader exports `TF_VAR_inngest_link_tls` when run with `doppler run -c prd_terraform --name-transformer tf-var`.
- 0.3 Check whether `inngest-link-flip.sh`'s idle guard and `scripts/lib/bearer-curl.sh` helpers are sourceable; if not, duplicate the small guard and pin parity in the suite.
- 0.4 Read `scripts/betterstack-query.sh` / `scripts/lib/betterstack-read-classify.sh` for the secret names and exit codes; read `tests/scripts/test-infra-privileged-tier-census.sh` Guards 1/2/4 to learn what a new Tier-B workflow must carry.
- 0.5 Read all three C4 files (`model.c4`, `views.c4`, `spec.c4`) before the C4 edit.
- 0.6 Verify whether `inngest-link-flip.sh flip` can start from a flag already at `1` (see Rollback accounting).
- 0.7 Read the rehearsal runbook's reboot leg (`knowledge-base/engineering/operations/runbooks/inngest-provision-rehearsal.md`) and `inngest-bootstrap.sh` (the Doppler fallback directory note near the unit launch) for LUKS-reopen-at-reboot evidence and whether the dedicated unit has a Doppler fallback cache; if there is no evidence, the owner's go names the residual in plain words.
- 0.8 Confirm the provider's `-replace` order for `doppler_secret` and that `-replace` on a resource carrying `ignore_changes=[value]` still creates with the new value (the CTO and the correctness review both rely on it; assert it in the suite).

Phase 1 — Terraform derivation (RED first): extend `inngest.test.sh` and `terraform-target-parity.test.ts` so the app value expressions must equal the dedicated expressions, the dedicated pair stays without `ignore_changes`, the per-merge closure gains the `random_id.*_dedicated` edge without an `hcloud_*` member, and the `inngest_host` shape gate still refuses `random_id` touches. Then edit `inngest.tf` (expressions and the two comments).

Phase 2 — the script (`scripts/inngest-key-rotate.sh`) test-first against stubs: refusal ladder (including `run_attempt`), the two plan gates, value-silent compare, reboot + wait, redeploy driver, converge derivation, summary tokens, `--print-contract`. No in-script go latch beyond the YAML `needs` graph (CTO R5d); the reboot function keeps a per-process one-POST latch.

Phase 3 — the workflow file and its static suite (`inngest-key-rotate-workflow.test.sh`): parsed-YAML posture (dispatch-only, pinned actions, inputs via env, per-job credential binding, every write job needs `guard` transitively and is conditioned on its output, workflow-level group `inngest-key-rotate`, no `restart-inngest-server.yml` / `restart inngest` reference, no raw Terraform output, reboot step `env -i` allow-listed with one POST and a name-plus-IP server resolution), mutation batteries from the Guard Contract.

Phase 4 — link-flip guard in `scripts/inngest-link-flip.sh` and `.github/workflows/inngest-link-flip.yml` (new input) with new rows in `inngest-link-flip-workflow.test.sh`; BUDGET TABLE pins (A40-A42) untouched.

Phase 5 — registrations and records: `infra-credential-tiers-8209.md` row; census and `trio-baseline.tsv` rows; `web-hosts-fanout-parity.test.sh` operand; `infra-validation.yml` path entries; ADR-304 plus ADR-100/ADR-294 amendments; `model.c4` edge text; runbook rewrite; owner-ask probe text and its suite.

Phase 6 — local verification only (all suites, `terraform fmt`/`validate` on the infra root, actionlint if present). No dispatch of `rotate` or `converge`, ever, by an agent without the owner's per-command go.

Post-merge (read-only): one `mode=plan` dispatch (see Production Actions).

## Files to Create

- `.github/workflows/inngest-key-rotate.yml`
- `scripts/inngest-key-rotate.sh`
- `apps/web-platform/infra/inngest-key-rotate-workflow.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-304-inngest-key-rotation-route.md` (ordinal provisional; re-verify against `origin/main` at ship)
- `knowledge-base/project/specs/feat-one-shot-10540-inngest-key-rotation-route/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-10540-inngest-key-rotation-route/decision-challenges.md`

## Files to Edit

- `apps/web-platform/infra/inngest.tf` (two value expressions; the SHARED-CHANNEL CONTRACT comment, the closing `ignore_changes` NOTE, the retired-resource comment)
- `apps/web-platform/infra/inngest.test.sh`, `apps/web-platform/infra/inngest-host.test.sh` (pins)
- `plugins/soleur/test/terraform-target-parity.test.ts` (closure edge; add the new workflow to the file list beside the `WEB_PLATFORM_WORKFLOW` / `DEPLOY_PIPELINE_FIX_WORKFLOW` constants that `extractAllTargets` reads, or its target pins never see it; update the exclusion comment on the dedicated pair, which still says only the `inngest_host` job applies them)
- `scripts/inngest-link-flip.sh`, `.github/workflows/inngest-link-flip.yml`, `apps/web-platform/infra/inngest-link-flip-workflow.test.sh`
- `scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh` and its `.test.sh`
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` (A5 row, "Key rotation order (A5)", "Key rotation", "Rollback" step 3, "Tracked follow-ups" table, evidence wording)
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` (Group 1/2 row for the new workflow's jobs)
- `tests/scripts/test-infra-privileged-tier-census.sh` (only if it keys on named jobs; verify in Phase 0.4), `tests/scripts/trio-baseline.tsv` (new files naming the deploy trio)
- `apps/web-platform/infra/web-hosts-fanout-parity.test.sh` (new operand for the workflow's roster literal)
- `.github/workflows/infra-validation.yml` (path entries for the new workflow and script)
- `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` (§4 Amendment: app copy now derived), `ADR-294-inngest-link-tls-terminator-and-flagged-flip.md` (a one-line pointer to ADR-304)
- `knowledge-base/engineering/architecture/diagrams/model.c4` (and `model.likec4.json` if generated by the render test) — the `github -> hetzner` edge text
- `plugins/soleur/test/stock-preflight-coverage.test.ts` only if Phase 0 shows it enumerates workflows other than `apply_target` options (expected: no change)

## Open Code-Review Overlap

- #8735 (infra-validation `notify-main-failure` misses cancelled jobs): Acknowledge. Different concern; this change only adds path entries to `infra-validation.yml`.
- #7942 (two `*.mutation.sh` batteries run in no gate): Acknowledge, and take the lesson: the new suite lives under `apps/web-platform/infra/*.test.sh`, which `infra-validation.yml` globs, and the new files are added to its `paths:` so an edit to only the workflow or script still runs it.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| New `inngest_key_rotate` job + `apply_target` in the big workflow | Byte gate (304 bytes headroom); extracting prose is an unrelated refactor inside a production-credential PR |
| Doppler CLI (`get \| set`) copy of the host value into `soleur/prd` | Plaintext through a shell; needs a `soleur/prd` write token that does not exist generically |
| Two-phase rotation with `INNGEST_SIGNING_KEY_FALLBACK` | Server-side flag unverified; event key has no fallback; two drain-bound redeploys |
| Restart via `restart-inngest-server.yml` | Cannot reach the dedicated host; would try to start web-1's quiesced scheduler |
| `inngest-host-replace` as the restart | Owner-gated twice (replace go + `op=resume` environment approval); disruption far beyond a key change |
| New in-place FSM state via the signed config-refresh bundle | New code on the sole scheduler's start path; larger than a minimal route |
| Leave the restart to the owner | Violates the exhaust-automated-options and no-SSH-runbook rules |
| Hard-block `action=off` after rotation | Removes the incident rollback; the extra confirm blocks only the silent case |

## User-Brand Impact

- **If this lands broken, the user experiences:** during the key-mismatch window (scheduler on the new key, old web containers on the old key, up to a 4200-second drain) an approved Concierge action or a Stripe `invoice.payment_failed` event can be rejected with 401 and lost or retried late; a reboot that comes back not serving leaves the sole scheduler down, so crons and reminders stop until the host is recovered; a wrongly-enabled `rotate` while the link is still plaintext would send the new key across `10.0.1.0/24`.
- **If this leaks, the user's workflow is exposed via:** a rotated or old key echoed into a public Actions log (Terraform prints `random_id` ids; `hex` is not sensitive), which would let anyone who can reach the Inngest endpoint forge `agent.spawn.requested` or `finance.payment_failed` events and read run lists (the Art. 15 audit surface).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one forged event or one lost approved action reaches a single named founder's data or money, which is the `single-user incident` definition; `aggregate pattern` would understate a key-exposure path. CPO sign-off: approve-with-conditions (conditions below). `soleur:engineering:review:user-impact-reviewer` runs at review.

CPO conditions carried into the plan: the owner-facing go text is plain words and states what the owner sees, the scheduler downtime (in minutes), that one cron tick inside the boot gap may be skipped and not replayed (unverified whether Inngest backfills; the text says so), the mismatch window and what is lost versus recoverable, the exact command with mode and keys, the `action=off` revert and its extra confirm in the same ask, that the go is a fresh in-session go (a go on #10382 does not count, no delegation covers it), and that rotation is the remedy for the forged-event risk. The `quiet_window` attestation widens beyond cron to Concierge actions, pending `payment_failed`, and an in-progress Art. 15 response (CLO). The workflow prints, never posts, `S5-A5-DONE`. The A6 ask stays gated on A5.

## Observability

```yaml
liveness_signal:
  what: "Per dispatch, the inngest-key-rotate run conclusion plus its fixed verdict token in the step summary (inngest-key-rotate verdict=<token>). For the rotated scheduler, Better Stack tls-health rows every 5 minutes with the new boot_id and listener=1."
  cadence: "per dispatch; tls-health every 5 minutes"
  alert_target: "red workflow run (GitHub notifications to the dispatching owner); one action-required GitHub issue filed on host-not-serving; Better Stack heartbeat monitors for the scheduler stay as they are"
  configured_in: ".github/workflows/inngest-key-rotate.yml; scripts/inngest-key-rotate.sh; apps/web-platform/infra/cloud-init-inngest.yml (existing tls-health timer)"

error_reporting:
  destination: "GitHub Actions run log and step summary (workflow context emits no Sentry events); action-required issue for the sole-scheduler-down case"
  fail_loud: "::error:: lines of the form inngest-key-rotate verdict=<token> with fixed tokens only; the job exits non-zero"

failure_modes:
  - mode: "Precondition refused (link flag not 1, soak not closed, run in flight, attestation missing, bad confirm)"
    detection: "workflow run log ::error:: verdict token (layer 6); nothing was written"
    alert_route: "red run to the dispatching owner"
  - mode: "Plan gate sees an address or action outside the allowlist"
    detection: "workflow run log ::error:: verdict=plan_gate_refused naming addresses only (layer 6)"
    alert_route: "red run; no apply"
  - mode: "Key material reaches a log"
    detection: "Guard 2 sentinel suite in CI; scrubbed excerpts only (workflow run log, layer 6)"
    alert_route: "CI red on the PR; the runtime path never prints raw Terraform streams"
  - mode: "Scheduler does not come back serving after the reboot"
    detection: "the reboot job polls Better Stack for 15 minutes (vector journald shipper, layer 3; host_silent after 10 minutes without a new boot_id) and prints verdict=host_not_serving or verdict=host_silent (workflow run log, layer 6)"
    alert_route: "red run plus one action-required issue; web is not redeployed"
  - mode: "Redeploy canary fails or fleet is mixed"
    detection: "track.sh terminal verdict in the workflow run log (layer 6); ci-deploy canary rows in Better Stack (vector journald shipper, layer 3)"
    alert_route: "red run; converge is the recovery"
  - mode: "Copies differ after a partial apply (expected between phase 1 and phase 2)"
    detection: "value-silent equality boolean in the workflow run log (layer 6)"
    alert_route: "red run with the exact converge command; apply2 resumes from the observed state"

logs:
  where: "GitHub Actions run logs of inngest-key-rotate.yml (scrubbed); Better Stack source for the dedicated host (journald via vector)"
  retention: "GitHub's Actions log retention for the repository (90 days default); Better Stack plan retention"

discoverability_test:
  command: bash scripts/inngest-key-rotate.sh --print-contract
  expected_output: "inngest-key-rotate verdict-tokens"
```

## Encryption Posture

```yaml
at_rest:
  stores: "none introduced. Existing stores touched by the rotation: the R2 Terraform state object (holds the random_id values) and Doppler soleur-inngest/prd and soleur/prd (hold the secrets); both are unchanged by this plan."
  does_not_defend: "This plan does not change, evidence or improve at-rest protection of either store; a reader of the state object or the Doppler configs sees the live keys."
  disclosed_as: "No new ledger row; rotation shortens the lifetime of whatever those stores held."
in_transit:
  - connection: "runner -> api.hetzner.cloud (reboot POST, name lookup)"
    tls: "TLS, public CA"
    cert_verification: on
    does_not_defend: "A compromised HCLOUD_TOKEN can still act within its scope; TLS does not bound the token."
    disclosed_as: "Existing github -> hetzner control-plane edge (model.c4), extended by this change."
  - connection: "runner -> Doppler API, Better Stack query host, deploy.soleur.ai (hooks)"
    tls: "TLS, public CA; hooks additionally HMAC-signed and behind Cloudflare Access"
    cert_verification: on
    does_not_defend: "TLS does not protect a value once it is in a runner process; the route keeps values on pipes and out of logs instead."
    disclosed_as: "Existing edges; no new connection class."
```

No plaintext exception is introduced; the route's precondition keeps the new key off the plaintext `:8288` hop.

## Task Design

```yaml
tasks:
  - task: inngest-key-rotate workflow
    trigger: workflow_dispatch only (owner-authorised; a path-scoped push trigger exists solely to register the workflow and every job is dispatch-guarded)
    services: "reads Doppler (prd_terraform through the loader), Terraform R2 state, Hetzner control plane (read-only token for the guard), Better Stack query, GitHub run list and issue state; writes Doppler (via the Terraform provider, two phases), one Hetzner reboot action (write token in that step only), the deploy webhook, and one issue on failure"
    next: "nothing; the owner posts S5-A5-DONE on #10136 and the A6 ask follows on #11218"
    human_reentry: "the dispatching owner reads the run summary and the stop sentence; recovery is the converge mode (needs the owner's own per-command go) or a fresh rotate under a fresh go; cancelling the run is safe before apply1, and after it converge finishes the window"
    dedupe: "typed confirm bound to keys and date; run_attempt must be 1 for rotate and converge (a GitHub re-run is refused); one rotation per dispatch (a second rotate is a new rotation, never a retry); converge resumes from the observed state, never mints, and issues at most one reboot POST (none when the newest boot started after rotated_at or a reboot action is running or finished after it); in-flight-run refusals before every write job; concurrency groups inngest-key-rotate (workflow), terraform-apply-web-platform-host (apply1/apply2) and deploy-inngest-restart (reboot)"
    source_dedupe: "not a ticket source"
```

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/inngest.tf` only: two `value` expressions and comments. No new resource, provider or variable. No sensitive variable: credentials come from the Tier-B loader. The reboot is a Hetzner control-plane API call, not a Terraform resource, because the hcloud provider has no reboot action; precedent is the reboot step of `inngest-provision-rehearsal.yml` (content anchor: the `actions/reboot` POST with the action poll) and the retired `web-host-reboot.yml`.

### Apply path

Two `terraform apply` phases with `-replace`, state-only on the Terraform side: phase 1 the dedicated pair, phase 2 the app secrets, with a soft reboot of the existing host and its verification between them. No `hcloud_*` address may appear in either plan (Guard 1), so no host is replaced. The Doppler-injected unit start loads the new values; the Redis AOF volume and the `done-owner` marker survive a reboot. Expected disruption: the sole scheduler is down for the boot (minutes; measure during the first `plan`/owner-go preparation and state it in the go text).

### Host fan-out

None: no `terraform_data` or SSH provisioner is touched.

### Distinctness / drift safeguards

Dev copies are untouched. The dedicated and app copies are equal by construction (same expression) and by runtime check. `ignore_changes=[value]` on the app secrets stays, so the per-merge plan stays quiet. The twice-daily drift plan sees no diff after a rotation because state and Doppler agree. The route adds no `prevent_destroy` change.

### Vendor-tier reality check

Doppler and Hetzner API calls need no paid tier. Better Stack read access uses the existing query credentials. No tier gate is needed.

## Architecture Decision (ADR/C4)

### ADR

Create ADR-304 "Inngest key rotation: dedicated workflow, two-phase apply, app copy derived from the dedicated random_id, Hetzner soft reboot as the restart lever" via `soleur:architecture` (ordinal provisional; `soleur:ship` re-verifies against `origin/main`). Amend ADR-100 §4 Amendment (the app copy is now derived, no longer copied across by a separate step; the G3.5 gate stays) and add an ADR-294 addendum (the route, the reboot lever, the off-after-rotation confirm). ADR-304 records the two-phase order, the lock topology (workflow group `inngest-key-rotate`, `terraform-apply-web-platform-host` on the apply jobs, `deploy-inngest-restart` on the reboot job; `web-platform-release` has a per-SHA group and is not serialized against the route, which is why the in-flight refusal is repeated before each write), the accepted residuals of Guard 3, and the Guard 1 anchor statement. Sequencing: written now, describing the target state; not deferred.

### C4 views

<!-- lint-infra-ignore start: documentation of the C4 enumeration; prescribes no infrastructure step -->
Read all three `.c4` files in Phase 0.5. Checked against the feature: external human actor (the owner who dispatches: modeled as `founder`, with the existing `founder -> github` approval edge, unchanged); external systems (Hetzner control plane, Doppler, Better Stack, Terraform R2 state, Cloudflare Access deploy hooks, all modeled; the `github -> hetzner` edge currently describes reads and one earlier write, so its text gains the reboot POST by this workflow, holding the Tier-B token); data stores touched (Doppler, tfstate, inngest host: modeled); actor-to-surface access (no change in who can reach what). Edit `model.c4` (the edge text only, plus the `github -> doppler` Tier-B edge sentence if it enumerates consumers), run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` (a new workflow can move a derived count).
<!-- lint-infra-ignore end -->

## Guard Contract

### Guard 1 — Rotation plan gates (blast radius, two phases)

**Property.** Each phase's plan may only replace or update its own allowlisted addresses for the selected keys, with the exact action arrays below; any other address, action, an unselected pair changing, a bare `create` of a dedicated `random_id` outside the documented recovery shape, or an empty plan refuses before apply.

**Assembly.** Three construction sites per phase must derive from one table in the script: the `-target` list, the `-replace` flags, and the jq allowlist applied to `terraform show -json`. Table: Gate A (phase 1) = `random_id.inngest_{signing,event}_key_dedicated` `["delete","create"]`, `doppler_secret.inngest_{signing,event}_key_dedicated` `["update"]`; Gate B (phase 2) = `doppler_secret.inngest_{signing,event}_key_prd` `["delete","create"]`, with the dedicated addresses `no-op`. The jq compares exact address equality, `index == null` and an exact `actions` array (never `contains`), and requires a change count equal to the table size for the selected keys (`all(...)` over `[]` is true, so the count is what makes an empty plan fail). `hcloud_*`, `terraform_data.*`, `tls_*` and every address outside the table are refused. The workflow's apply jobs call only the script function that builds all three from `keys`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `hcloud_server.inngest` to the target list | RED |
| 2 | Drop the `-replace` for the app secret so Gate B sees a no-op for it | RED (count short) |
| 3 | Plan fixture with a compliant first change plus a second `update` on `doppler_secret.inngest_redis_password_dedicated` | RED |
| 4 | Empty `resource_changes` (dispatch vacuity) | RED (count) |
| 5 | Gate B fixture where the app secret shows `["update"]` | RED |
| 6 | `keys=signing` plan that also changes the event pair | RED |
| 7 | Plan with a bare `["create"]` of `random_id.inngest_signing_key_dedicated` (a new key minted where none was in state) | RED |

**Harness rows:** (a) replace the gate call in the suite with `true`; the suite must go RED. (b) must-PASS non-canonical inputs: `keys=event` plan with reordered `resource_changes` and an extra no-op entry; the bare-`["create"]` recovery shape with `before` null for the app secret.

**Anchor.** The allowlist table and `terraform-target-parity.test.ts` pin the same set; both live in this repo, so the guard proves consistency, not integrity. Integrity rests on `infra-privileged` being main-only and on required review; stated plainly in ADR-304.

### Guard 2 — No key material reaches a log

**Property.** No step of the workflow or function of the script prints a Terraform stream (stdout, stderr or `TF_LOG` output), a Doppler value, or a string with key shape.

**Assembly.** Every `run:` body in the workflow and every function in the script that invokes `terraform`, `doppler`, `curl` or `gh`. The chokepoint is the `kr_tf` wrapper: all Terraform streams go to a file under `$RUNNER_TEMP`, are never printed, never uploaded, and `TF_LOG` is unset inside it. On failure the script prints only the exit code and jq-derived addresses; it never excerpts a Terraform stream (a scrubber over hex split across lines or `TF_LOG` escapes is brittle, so there is none for Terraform output). The one scrub that remains, `kr_scrub`, covers short Hetzner/Better Stack/`gh` error bodies. The suite parses the YAML and shell and rejects a bare `terraform plan|apply|show|state` or `doppler secrets get` outside the wrappers.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the redirect on `terraform apply` | RED |
| 2 | Add a bare `terraform show -no-color tfplan` | RED |
| 3 | Add a second Terraform call after a compliant first | RED |
| 4 | Set `TF_LOG=DEBUG` in the environment of the run | RED unless `kr_tf` unsets it |
| 5 | Stub `terraform` printing a synthesized `[id=<43-char base64url>]`, a 64-hex run and `signkey-prod-<64 hex>` on stdout and stderr; capture every stream of the whole script run | RED if any sentinel appears |
| 6 | Drop the `[id=...]` pattern from `kr_scrub` and feed it a synthesized error body containing one | RED |

**Harness rows:** (a) replace the sentinel grep with `true`; RED. (b) must-PASS input: a 40-hex git SHA and a run URL pass through unredacted.

**Anchor.** The sentinel strings are synthesized in the suite and independent of the implementation's patterns; a weakening must change the suite and the script together, which review sees.

### Guard 3 — Off-after-rotation confirm in the link flip

**Property.** After any non-`plan` run of `inngest-key-rotate.yml` exists, no path to a flag-off apply proceeds without `OFF-AFTER-ROTATION`; before any such run, `off` behaves exactly as today.

**Assembly.** Entry points: `flip_cmd_off` and `flip_cmd_revert`, both through `flip_apply_flag` with value `off`; the guard sits in `flip_apply_flag`. The run test matches `displayTitle` from `run-name` over `--limit 200` (the script's existing `--limit 20` would let frequent `plan` rehearsals push the marker out).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the guard | RED (off proceeds after a rotate run) |
| 2 | Drive the `revert` path with a rotate run present | RED unless it logs the refusal and returns without dispatching |
| 3 | Run list with a `plan` run first and a failed `rotate` (applied, then failed at reboot) second | guard must refuse (the second member counts) |
| 4 | Run list with only `plan` runs | RED if the guard refuses (false positive) |
| 5 | More than 20 `plan` runs after the rotate run | guard must still refuse |

**Harness rows:** (a) stub `gh run list` returning an empty list; `off` proceeds (must-PASS, differs from canonical). (b) remove the stub's `displayTitle` field; the guard must fail closed (refuse), and the suite goes RED if it proceeds.

**Anchor.** `gh run list` is read-only against GitHub; run-history retention (90 days) and deletion reset it, and a direct dispatch of the apply workflow bypasses it. Documented as accepted residuals in ADR-304 and the runbook.

### Guard 4 — Refusal ladder precedes every write

**Property.** No Terraform apply, Hetzner POST, Doppler-writing step or redeploy runs unless every precondition passed in the same attempt, and exactly one reboot POST is made per run.

**Assembly.** The jobs `apply1`, `reboot`, `apply2`, `redeploy` each declare `needs` (transitively) on `guard` and an `if:` on its `go` output, and each starts with the in-flight-run refusal; `guard` refuses `github.run_attempt != 1` for `rotate` and `converge`. The reboot function is the only caller of the Hetzner POST and holds a per-process latch.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `needs: guard` from `reboot` | RED |
| 2 | Run `guard` with the link flag `pending:1700000000` | RED if anything proceeds |
| 3 | Call the reboot function twice in one process | RED if a second POST is issued |
| 4 | `run_attempt=2` for `rotate` | RED if `guard` passes |
| 5 | Swap `reboot` and `apply2`/`redeploy` order in the job graph | RED (redeploy before SERVING) |
| 6 | `quiet_window=false`, wrong date in confirm, soak tracker open (each separately) | each RED if it proceeds |

**Harness rows:** (a) delete the stub POST-counter assertion; RED. (b) must-PASS: a `plan` run with the flag `pending:...`, no attestation and an open soak tracker reports booleans, writes nothing and exits 0; a `plan` re-run (`run_attempt=2`) passes.

**Anchor.** The soak state and link flag are read from GitHub and Doppler outside this commit, so a weakening of the refusal cannot fabricate them; a code change that skips the read is what the mutation rows target.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "a minimal apply_target for rotating the dedicated copy (soleur-inngest/prd) and the app copy (soleur/prd, ignore_changes=[value], copied out of band per inngest.tf)" [brief] | Route workflow, Terraform derivation, AC1, AC2 | mapped |
| 2 | "Verify whether the dedicated doppler_secret carries ignore_changes." [brief] | Premise Validation row (it does not) + pinning tests (AC3) | mapped |
| 3 | "Rotate the event key in the same window" [issue #10540] | `keys=both` option (AC4) | mapped |
| 4 | "Restart inngest-server and redeploy web back to back" [issue #10540] | `apply1`, `reboot`, `apply2`, `redeploy` jobs (AC4, AC5) | mapped |
| 5 | "after the signing-key rotation a flag-off rollback puts the NEW key back on :8288, so the route must account for that" [brief] | Link-flag precondition + off confirm (AC6) | mapped |
| 6 | "The PR delivers the route only; it must NOT execute any rotation or any production apply." [brief] | AC7, Production Actions | mapped |
| 7 | "never read or print secret values" [brief] | Guard 2 (AC10) | mapped |
| 8 | "route technical forks to the soleur:engineering:cto agent, never to the owner" [brief] | `decision-challenges.md` rows | mapped |
| 9 | "Parent epic: #10205 (use Ref, not Closes)" [brief] | PR body `Ref #10205` (AC9) | mapped |
| 10 | "Use `Closes #10540` in the PR body only if the route fully satisfies the issue's Done criteria; otherwise Ref." [brief] | AC9 closure conditions | mapped |
| 11 | "do not push to a PR in the merge queue; arm merges only with `gh pr merge --squash --auto`" [brief] | Ship-phase constraint (PR #11287 is a draft, not queued) | mapped |
| 12 | "no production writes without an in-session per-command go from the owner naming the command (a menu click does not count)" [brief] | Production Actions | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Dedicated workflow | "a minimal apply_target for rotating the dedicated copy" | asked |
| Terraform-derived app copy | "the app copy (soleur/prd, ignore_changes=[value], copied out of band per inngest.tf)" | asked |
| Hetzner soft reboot | "Restart inngest-server" | asked |
| Link-flag precondition and off confirm | "the route must account for that" | asked |
| `mode=plan` rehearsal arm | — | inferred — justification: CTO F7; the first real dispatch runs under an owner go, so the gate chain needs a read-only dress rehearsal |
| `converge` mode | — | inferred — justification: after the apply there is no old key to roll back to (it exists nowhere), so recovery must be a defined, Doppler-write-free mode (CTO F3) |
| Owner-ask probe text change | — | inferred — justification: CPO condition; the probe still says the owner "executes the rotation", which the route supersedes |
| ADR-304 + amendments, C4 edge text | — | inferred — justification: plan Phase 2.10 (new credential-rotation route; app-key source of truth moves into Terraform) |
| Runbook corrections (restart claim) | — | inferred — justification: the A5 row's restart mechanism is false for the dedicated host; `Closes #10540` is honest only with it corrected (CTO) |
| Follow-up issues #11292, #11293, #11294 | — | inferred — justification: deferral tracking rule; #11294 is a security finding made while planning |
| Scrub contract (Guard 2) | "never read or print secret values" | asked |
| Two-phase apply, `run_attempt` refusal, in-flight re-check before each write | — | inferred — justification: architecture and flow review; a re-run would bypass the owner's go and the unrelated-deploy window must not read an app key the scheduler cannot yet serve (CTO R1, R4) |
| `quiet_window` attestation | — | inferred — justification: CPO sign-off condition; kept by CTO R5c because cron-quiet cannot be machine-checked |

### Split Assessment

- Subsystems touched: 6 — `.github/workflows`, `scripts`, `apps/web-platform/infra`, `knowledge-base`, `plugins/soleur/test`, `tests/scripts`
- Planned files: 24 | Estimated changed lines: about 2,600 (the new suite and script dominate)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The Terraform derivation, the link-flip guard and the route are safety prerequisites of one another (the guard must land with the route that creates the hazard, and the route is unsafe without the derivation), so a split would ship an unguarded or unusable half; the line count is mostly mutation batteries.

## Acceptance Criteria

### Functional

- [ ] AC1. `.github/workflows/inngest-key-rotate.yml` exists, is dispatch-only (every job guarded; the push trigger only registers the workflow), has inputs `mode`, `keys`, `confirm`, `reason`, `rotated_at` (optional, cross-checked), `quiet_window` with no defaults on `mode` and `keys`, a workflow-level group `inngest-key-rotate`, and passes the static suite (every write job needs `guard` transitively and is conditioned on its output).
- [ ] AC2. `inngest.tf` app secrets derive from the dedicated `random_id`s with `ignore_changes=[value]` kept; `inngest.test.sh` fails if the expressions differ or if the dedicated pair gains an `ignore_changes`.
- [ ] AC3. The suite asserts the dedicated `doppler_secret`s carry no `lifecycle` block (the issue's "verify whether" question is answered by a test, not prose).
- [ ] AC4. `keys=both` rotates both pairs; `signing` and `event` rotate one pair; the confirm string includes the keys and the UTC date; phase 1 touches only the dedicated pair and phase 2 only the app secrets, each behind its own gate (Guard 1).
- [ ] AC5. The reboot job is the only caller of the Hetzner POST, makes at most one per run, resolves exactly one server by name and private IP, holds the Hetzner write token in that step only (guard uses the read-only token), waits at most 10 minutes for a new `boot_id` and never hard-resets; no file in the change references `restart-inngest-server.yml` or the `restart inngest` verb for this route.
- [ ] AC6. `rotate` and `converge` refuse unless the link flag is `1`, #11215 is CLOSED/COMPLETED and `run_attempt` is 1; `mode=plan` reports those checks as booleans and refuses on none of them; `inngest-link-flip.sh off` needs `OFF-AFTER-ROTATION` after any non-`plan` run of the workflow; `plan` runs do not trigger it.
- [ ] AC7. No dispatch of `rotate` or `converge`, and no production apply, occurs in this PR or its CI; no `S5-A5-DONE` line is posted by anything in the change.
- [ ] AC8. Runbook A5 row, "Key rotation order (A5)" step 3, "Key rotation" step 4, "Rollback" step 3, the "Reading host state without SSH" evidence wording and a between-phases note (copies legitimately differ; the G3.5 arm gate fails closed) are corrected; the owner-ask probe names the exact `plan`, `rotate` and `converge` lines and the `S5-A5-DONE` handoff, and says the converge line needs the owner's own go.
- [ ] AC9. PR body: `Ref #10205` (never Closes for the epic) and `Closes #10540`, the latter only if AC1-AC8 hold and #11292/#11293 exist; otherwise `Ref #10540`.

### Non-Functional

- [ ] AC10. Guard Contract suites pass, including every mutation row going RED and every must-PASS row going green; the sentinel test finds no synthesized key string in any captured stream (with `TF_LOG` set and with a stub that prints to both streams).
- [ ] AC11. Timeouts derive from a BUDGET TABLE in the script (apply, reboot, 15-minute verify poll, redeploy bounded by the 4800-second pipeline ceiling) and the suite pins them.
- [ ] AC12. Census and registration suites pass: Tier-B tier census, `terraform-target-parity.test.ts`, `web-hosts-fanout-parity.test.sh`, trio-baseline census, `c4-count-parity.test.sh`, `workflow-file-size.test.ts`, `terraform fmt -check` and `validate` on the infra root.

### Quality Gates

- [ ] AC13. Review runs `user-impact-reviewer`, `observability-coverage-reviewer`, `security-sentinel` and `test-design-reviewer` (single-user-incident threshold).
- [ ] AC14. Phase 0.6-0.8 findings are recorded in the PR (flip-from-`1`, rehearsal reboot evidence and unit fallback cache, provider replace order). `lint-infra-no-human-steps.py` passes on this plan, the runbook and the ADR (no human-run infrastructure step; dispatching a workflow under the owner's go is authorization, not an infrastructure act).

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled F1-F7 and re-ruled F3/F6 plus the restart lever after the plan found that `restart-inngest-server.yml` cannot reach the dedicated host; rulings recorded in `decision-challenges.md`. Main residual risk named by the CTO: the production dedicated host has never been rebooted with its LUKS volume and live scheduler; the owner's go must say so.

### Legal

**Status:** reviewed
**Assessment:** CLO agent: no Art. 30, DPA or subprocessor change rides this PR (no new processor, store or data flow); Art. 32 evidence is created when the rotation runs, so the workflow prints a value-free record and nothing in this PR asserts that keys were rotated; gdpr-gate is not triggered by the path regex (confirm with the lefthook check; if it fires, expect "no regulated data surface"); the go text must say rotation is key hygiene and does not add TLS, close A6 or discharge the 2026-11-12 re-review; the run-list route fails while keys differ, so no rotation during an Art. 15 response; the 2026-12-10 extension is not recorded in the legal records (unverified), and using it would require a published-text change first.

### Product/UX Gate

**Tier:** none (no UI surface; owner-facing text only)
**Decision:** reviewed (CPO sign-off at plan time, approve-with-conditions; conditions carried under User-Brand Impact)
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO: scope right; `quiet_window` must cover Concierge actions and pending `payment_failed`; workflow prints but does not post `S5-A5-DONE`; the probe text must name this route; a failed or partial run needs a single "stop, do not retry, tell me" message; A6 is not asked while a rotation is half-done.

## Test Scenarios

### Acceptance (RED first)

- Given `keys=both` and a phase-1 plan with the four allowlisted changes (two `random_id` replaces, two in-place dedicated secrets), when Gate A runs, then it passes; given any fifth address, it refuses. Given a phase-2 plan replacing the two app secrets with the dedicated pair as no-ops, Gate B passes.
- Given the link flag `pending:<epoch>`, empty, or `1` (with #11215 open), when `guard` runs, then each of the first two and the last refuses with a distinct token and writes nothing.
- Given a stub `terraform` that prints a synthesized `[id=...]`, a 64-hex run and a `signkey-prod-` string, when the whole script runs, then no stream contains any of them.
- Given a rotate run in the stubbed run list, when `inngest-link-flip.sh off` runs without `OFF-AFTER-ROTATION`, then it refuses; with it, it proceeds; with only a plan run listed, it proceeds.
- Given `converge` with unequal copies and a host booted after `rotated_at` and SERVING, then it runs apply2 and the redeploy and issues no POST; given a host that is NOT SERVING, it refuses to redeploy; given `run_attempt=2`, it refuses.
- Given `rotate` dispatched with the soak tracker open, then `mode=plan` reports `soak=false` and exits 0 while `rotate` refuses.

### Regression

- `inngest-link-flip-workflow.test.sh` existing rows (A40-A42 budget pins included) stay green; `inngest.test.sh` existing assertions about the `_prd` resources stay green apart from the intentionally changed value expressions.
- A per-merge `-target` plan model still shows no change for the app secrets (`ignore_changes`).

### Edge cases

- Soft-reboot action polled to `success` but no probe row with a new `boot_id` within 10 minutes yields `host_silent`, not `host_not_serving`; the 15-minute total bounds the SERVING and `tls-health` reads.
- `rotate` accepts a new `boot_id` different from the pre-reboot capture; `converge` additionally requires the newest boot to start after `rotated_at`, so an accepted-but-not-yet-restarted POST is not evidence.
- An owner-supplied `rotated_at` or `keys` that disagrees with the derived run refuses; a guard-refused run never qualifies as the derivation source.

### Integration verification (post-merge, read-only)

- `gh workflow run inngest-key-rotate.yml -f mode=plan -f keys=both -f reason='post-merge rehearsal'` completes green with `verdict=plan_ok` from Gates A and B only (the soak, flag and attestation booleans are reported, not required, so this does not depend on the sweeper having closed #11215 or on the live flag); the step summary lists addresses and actions only, and the run log contains no key-shaped string (checked with the Guard 2 pattern set, not by reading values). A red `plan` run is investigated before the A5 ask is allowed to proceed; it does not auto-reopen #10540.

## Production Actions (none performed by this change)

| Act | Authority | Status in this change |
|---|---|---|
| `mode=plan` rehearsal dispatch after merge | read-only (Terraform plan, Hetzner GET, Better Stack read); no write | Allowed once, by the post-merge step; a red result is investigated before A5 proceeds |
| `mode=rotate`, `mode=converge` | A5 is owner-human: a fresh in-session per-command go naming the exact command (mode, keys, confirm); a go on #10382 does not count; no delegation covers it | Never dispatched by this change or by an agent |
| `inngest-link-flip.yml action=off` after rotation | fresh in-session go (form (b)) plus `OFF-AFTER-ROTATION` | Not performed |
| `S5-A5-DONE` / `S6-A6-DONE` lines | owner-typed on #10136 | Not posted |

Earliest A5 date: after #11215 closes COMPLETED (earliest check 2026-10-28T13:56Z). Target for this PR's merge: 2026-11-05. Legal bridge: 2026-11-12.

## Dependencies & Risks

- Depends on: #11215 PASS (A4) before any real rotation; the infra-credentials loader exporting `HCLOUD_TOKEN`, `DOPPLER_TOKEN_TF`, `TF_STATE_AWS_*`.
- Risk: unverified production reboot of the sole scheduler (LUKS reopen at boot; runbook L31 stage table). Mitigation: pre-reboot SERVING check, refusal to redeploy until SERVING, no auto-retry, `action-required` issue.
- Risk: key-mismatch window up to a 4200-second drain. Mitigation: quiet-window attestation, in-flight-run refusals, canary keeps old containers on failure.
- Risk: raw Terraform output leaks key bytes. Mitigation: Guard 2; existing jobs tracked in #11294.
- Risk: unverified whether Inngest backfills a cron tick missed during the boot gap. The owner-facing text says "may be skipped".
- Risk: a soft (ACPI) reboot can stall. Mitigation: a 10-minute bounded wait for a new `boot_id`, then `host_silent`; the route never hard-resets (a hard reset is a separate owner go).
- Risk: the unit boots on a cached old key (Doppler fallback cache). Mitigation: Phase 0.7 reads the unit; if it ever happened, the redeploy canary fails against the mismatched server and the old containers keep running.
- Risk: a merge or release deploying between the phases reads the old app key against the new scheduler and fails its canary (a red release, no outage). Mitigation: the in-flight-run refusal before every write job and the quiet-window attestation; stated in the go text.
- Risk: per-merge closure now includes the dedicated `random_id`s through the new edge. Mitigation: closure test with no `hcloud_*` member; per-merge plan stays quiet by `ignore_changes`.
- Residual: the guard in Guard 3 reads GitHub run history; deleted history resets it (documented).

## References

- Issue #10540; parents #10382, #10136, #10205; trackers #11215, #11218, #11207; follow-ups #11292, #11293, #11294.
- ADR-100 §4 Amendment; ADR-294; ADR-241 (Tier-B credentials); ADR-280 (bearer-curl).
- Runbook `knowledge-base/engineering/operations/runbooks/inngest-server.md` ("Key rotation", "Key rotation order (A5)", "Production Envelope", "Rollback", "Reading host state without SSH").
- Precedents: `.github/workflows/inngest-host-state.yml` (host text never leaves the runner); `.github/workflows/inngest-link-flip.yml` + `scripts/inngest-link-flip.sh`; `.github/workflows/restart-inngest-server.yml` (registration push trigger); `.github/workflows/inngest-provision-rehearsal.yml` (Hetzner reboot step); `scripts/inngest-host-state.sh`; `.github/actions/dispatch-web-redeploy/track.sh`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `single-user incident`.
- Never publish the plan JSON, the `tfplan` file, or any Terraform stream: `random_id` ids and `hex` are key bytes.
- The typed confirm and the `quiet_window` attestation are typo-guards and statements of fact, not authorization.
- The ADR ordinal is provisional; `ADR-304` may be taken by a sibling PR before ship.
