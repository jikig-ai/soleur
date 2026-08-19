---
title: "main's web-platform infra apply was red for 3 days — an SSH-provisioned resource was -target'd in the bridge-less plan stage, and no channel reported the red"
date: 2026-08-17
incident_pr: 7568
incident_window: "2026-08-13T11:41:20Z (first red push-run, 31696609210) → 2026-08-16T22:28:56Z (last red push-run, 31976455160). Every push-triggered run that actually executed the `apply` job in that window failed; 10 runs total."
recovery_at: "2026-08-17 (fix merged in #7568; recovery verified by the post-merge `Apply web-platform infra` run on the merge commit reaching a green `Terraform plan (allow-list, non-SSH resources only)` step)"
suspected_change: "0d6443960 (#7457, 2026-08-12T20:18:09Z) appended `-target=terraform_data.inngest_consumer_probe_install` to the stage-1 `Terraform plan (allow-list, non-SSH resources only)` step. That resource carries an SSH provisioner, but stage 1 runs BEFORE the cf-tunnel-ssh-bridge composite, so it has no credential channel to the host."
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - availability (infrastructure apply pipeline / web-platform Terraform)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale: availability-only degradation of the INFRASTRUCTURE APPLY
# pipeline. No personal data was accessed, altered, disclosed or lost — the failure is a
# Terraform plan step aborting before it can reach a host, so no data path is involved at
# all. Production web-platform kept serving on its last-applied configuration throughout
# (/health stayed 200; the app deploy path is web-platform-release.yml, a DIFFERENT
# workflow that was unaffected). Art. 33 and Art. 34 are therefore both false. The
# threshold is `aggregate pattern` rather than `single-user incident`: the harm is
# fleet-wide configuration drift and a blinded detection channel, not a named user's
# incident.
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

For three days, every push to `main` that executed the `apply` job of `apply-web-platform-infra.yml` failed at the same step, so **no declared infrastructure change reached production**. The declared-but-unapplied set included four inngest-consumer resources and #7457's `vector.toml`, which never reached web-1.

Two independent defects compose here, and the second is the one that made the first expensive:

1. **The fault.** A `-target=` naming an SSH-provisioned resource was appended to the stage-1 plan step, which runs before the SSH bridge exists. Terraform cannot plan a provisioner-bearing resource it has no channel to reach, so the step aborted.
2. **The blindness.** A red `Apply web-platform infra` run reaches **no notification channel**. Nothing paged, nothing emailed, nothing posted. The red was discoverable only by a human choosing to look at the Actions tab.

Defect 1 is a one-line placement mistake that any reviewer could make. Defect 2 is why it survived 10 runs and three days.

## Status

resolved — the `-target=` line is moved to the post-bridge stage-2 apply step in #7568, and a build-time guard (`terraform-target-parity.test.ts`) now fails any PR that targets a `terraform_data` before the bridge in any bridge-using workflow.

## Symptom

`apply-web-platform-infra.yml`, job `apply`, step **`Terraform plan (allow-list, non-SSH resources only)`** → failure. Verified identical on both ends of the window: the first red run (31696609210, 2026-08-13T11:41:20Z) and the last (31976455160, 2026-08-16T22:28:56Z) fail at that same named step.

## Incident Timeline

- **Start time (detected):** 2026-08-13T13:53:14Z (issue #7539 filed)
- **End time (recovered):** 2026-08-17 (merge of #7568)
- **Duration (MTTR):** ~3d 10h from detection to fix merged

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-08-12T20:18:09Z | `0d6443960` (#7457) appends `-target=terraform_data.inngest_consumer_probe_install` to the stage-1, bridge-less plan step. |
| system | 2026-08-13T11:41:20Z | First red push-run on `main` (31696609210). No channel reports it. |
| human | 2026-08-13T13:53:14Z | Incident detected by looking at the Actions tab; #7539 filed — **with a misdiagnosis in its title** (blames the `[ack-destroy]` guard). |
| system | 2026-08-13T14:10:55Z → 2026-08-16T22:28:56Z | Nine further red push-runs. Still no channel. |
| agent | 2026-08-16 | Root cause correctly identified as the bridge-less `-target=`, superseding the title's `[ack-destroy]` hypothesis. |
| agent | 2026-08-16T22:14:18Z | #7586 filed — a red infra apply reaches no channel. |
| agent | 2026-08-17 | #7568: `-target=` moved to stage 2; build-time guard added; PIR written. |

## Participants and Systems Involved

`apply-web-platform-infra.yml` (job `apply`, stages 1 and 2), the `cf-tunnel-ssh-bridge` composite action, `apps/web-platform/infra/server.tf`, Terraform state for the web-platform root, and the web-1 host.

## Detection (+ MTTD)

- **How detected:** External/manual — a human read the Actions tab. **No monitoring system reported this.** That is the substance of #7586: 8 of the last 10 `main` runs had failed with nothing surfacing it.
- **MTTD (mean time to detect):** ~2h12m from the first red run; ~17h35m from the introducing commit. Both numbers understate the real exposure, because detection was luck rather than signal — with no channel, MTTD is bounded only by how often somebody happens to look.

## Triggered by

system — a self-inflicted configuration change in CI, not user action, market movement, or a provider fault.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The `[ack-destroy]` guard is blocking the apply (#7539's title) | The guard is a known blocker class and was recently active | The ack was already carried on `5c85b1c3e` and the guard **passed**; the failing step is the plan step, not the guard | **rejected** |
| An SSH-provisioned resource is `-target`'d in the bridge-less stage-1 plan step | Failing step is `Terraform plan (allow-list, non-SSH resources only)`; `terraform_data.inngest_consumer_probe_install` carries an SSH provisioner; introduced 2026-08-12 in `0d6443960` | none | **confirmed** |

## Resolution

Move the single `-target=terraform_data.inngest_consumer_probe_install` flag out of the stage-1 (bridge-less) plan step and into the stage-2 apply step, which runs after `cf-tunnel-ssh-bridge` has established the credential channel.

Everything else in #7568 is prevention: a build-time guard asserting that no `terraform_data` is `-target`'d before the bridge in **any** bridge-using workflow (derived by scanning `.github/workflows` for the composite's `uses:`, not a restated list), plus a pinned premise asserting `terraform_data` remains the only resource type carrying provisioners.

## Recovery verification

The post-merge `Apply web-platform infra` run on #7568's merge commit must reach a **green** `Terraform plan (allow-list, non-SSH resources only)` step in the `apply` job — the exact step that failed on both ends of the incident window. Verified in `/ship` Phase 7 / `/soleur:postmerge`.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why was main's infra apply red?** The stage-1 plan step exited non-zero.
2. **Why did the plan step fail?** It was asked to plan `terraform_data.inngest_consumer_probe_install`, which carries an SSH provisioner, and stage 1 has no SSH channel to the host.
3. **Why was that resource targeted in stage 1?** `0d6443960` appended the flag to the nearest `-target=` list without distinguishing the two stages — the stage boundary is expressed only by step ORDER relative to the bridge, which is invisible when you are editing a flag list.
4. **Why did nothing catch it at authoring time?** The only defense was prose: an `ALLOW-LIST MAINTENANCE` comment saying to exclude SSH-provisioned resources. It had been there since 2026-05-20 and was not read. Prose is not a gate.
5. **Why did it survive 10 runs and three days?** A red `Apply web-platform infra` reaches no notification channel, so the only detector was a human choosing to look. Root cause of the *duration* is the missing channel (#7586), not the missing guard.

## Versions of Components

- **Version(s) that triggered the outage:** `0d6443960` (2026-08-12, #7457) through `173f7889` (2026-08-16).
- **Version(s) that restored the service:** `70a32093f` in PR #7568.

## Impact details

### Services Impacted

The web-platform Terraform apply pipeline only. Declared-but-unapplied for the window: four inngest-consumer resources and #7457's `vector.toml`, which never reached web-1 (so the intended log-shipping change was inert on the host).

Explicitly NOT impacted: the application deploy path. `web-platform-release.yml` is a separate workflow and continued to deploy normally; production served on its last-applied infrastructure configuration throughout.

### Customer Impact (by role)

- Prospect: none — the marketing surface is unaffected by infra apply state.
- Authenticated app user: none observed. Prod continued serving on last-applied config; `/health` stayed 200.
- Legal-document signer: none.
- Admin via Access: none directly; an admin reading the Actions tab would have seen persistent red with no explanation.
- Billing customer: none.
- OAuth installation owner: none.

The real exposure is latent rather than realized: for three days, **any** infrastructure change — including a security or availability fix — would have silently failed to reach production. Nothing urgent happened to need applying. That is luck, and it is recorded as such below.

### Revenue Impact

None measured. No user-facing outage, no SLA breach.

### Team Impact

Three days of infra changes accumulating unapplied; one misdiagnosis (#7539's title) that had to be superseded before the real fix could be found; ~10 wasted CI runs.

## Lessons Learned

### Where we got lucky

Nothing urgent needed applying during the window. Had a security patch or an availability fix been declared in those three days, it would have failed to reach production exactly as silently. The blast radius was bounded by luck, not by design.

We were also lucky that the failure was **loud within the run** (a non-zero exit at a named step) rather than a silent partial apply. A `-target=` that half-applied would have left state and reality diverged with a green check.

### What went well

- The stage-1/stage-2 split did its job: the bridge-less stage refused to touch a resource it had no credential for, rather than attempting it with an absent or wrong credential.
- Once the correct hypothesis was formed, the fix was one line, and the guard that prevents recurrence was proven by mutation rather than by reading.
- The two residual defects were filed as their own issues (#7586, #7587) rather than bundled into an unrelated fix.

### What went wrong

- **A red production-infrastructure apply reaches no channel.** This is the finding that matters. Ten runs failed and the detector was a human's attention. Tracked as #7586.
- **The prose defense was already in place and did not work.** The `ALLOW-LIST MAINTENANCE` comment landed 2026-05-20 and said precisely what not to do; the violation was appended anyway. A comment that instructs is not a control that enforces.
- **The incident's own issue title carried a wrong diagnosis** (`[ack-destroy]` guard) and survived three days as the headline hypothesis. The ack was already carried on `5c85b1c3e` and the guard had passed. A misdiagnosis in a title is unusually durable, because every subsequent reader anchors on it.
- **The first guard written to close this was narrower than the property it named** — it matched only bare, line-leading `-target=` while the file's majority style is quoted. Two review agents proved the exact regression, single-quoted, passed 117/117 green. The fix for a defect nearly shipped with the defect intact.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur.

| Issue | Action | Status |
|---|---|---|
| #7586 | Give a RED `Apply web-platform infra` run a notification channel — the missing detector is the root cause of this incident's three-day duration, not its one-line fault. | open |
| #7587 | Fix the ARM gate's cumulative deadline (1860s) exceeding the `apply` job's `timeout-minutes: 15`, so a mid-poll cancellation cannot leave an unpaused-and-unfed monitor behind. | open |
