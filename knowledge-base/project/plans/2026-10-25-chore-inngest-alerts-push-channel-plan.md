---
title: "infra(observability): Inngest alert resources route email-only — wrong-volume alert + server-probe heartbeat never reach a read channel"
type: chore
date: 2026-10-25
slug: chore-inngest-alerts-push-channel
branch: feat-one-shot-11068-inngest-alerts-push
issue: 11068
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# infra(observability): Inngest alert resources route email-only — wrong-volume alert + server-probe heartbeat never reach a read channel

## Overview

Two P1-class Inngest-serving alert resources in `apps/web-platform/infra/` declare `email = true` with `push/call/sms = false`, so their pages land only on an inbox surface: `logtail_exploration_alert.inngest_luks_wrong_volume` (betterstack-logs-alerts.tf) and `betteruptime_heartbeat.inngest_server_probe` (uptime-alerts.tf). A third Inngest-serving alert in the same file, `logtail_exploration_alert.inngest_step_524`, carries the identical routing block; the issue's own finding quantifies over "every Inngest-serving alert resource", so it is folded in. The fleet's measured-flip precedent (#9168 on `betteruptime_monitor.app_health`; PR #11001 on `betteruptime_heartbeat.inngest_prd` and `.inngest_consumer`, applied green 2026-10-25T03:52Z) sets `push = true` per resource, measured at apply time, with `push = false` as the revert if the vendor plan refuses the attribute. This plan applies that precedent to the three Inngest-serving resources that still lack it.

## Problem Statement / Motivation

`inngest_luks_wrong_volume` pages when the dedicated Inngest host's `/mnt/data` sits on a non-encrypted volume — Redis writes landing unencrypted. `inngest_server_probe` is the hourly dead-man's switch for the probe pipeline itself (#8516, #9703 — feeder landed, heartbeat armed 2026-10-12 after an observed beat, per the resource comment). `inngest_step_524` pages on a lost Inngest function-step response (a double-billed run). All three are Inngest-serving alerts whose only vendor-channel delivery is `email = true` — the surface the 09-15 and 09-28 Supabase outages proved unread in time (#9168). The fleet already carries `push = true` on three sibling resources; the Inngest-serving set is the residual.

## Research Insights

**Premise Validation (Phase 0.6).** Checked: (a) issue #11068 is OPEN; (b) both named resources exist at `betterstack-logs-alerts.tf:264` and `uptime-alerts.tf:531` and still declare `push = false` — the premise holds as filed; (c) all cited refs resolved — #8516 CLOSED, #9703 CLOSED, #8296 CLOSED, #9168 CLOSED (the app_health measured flip), #11011 and #7662 OPEN (context, not blockers); (d) stale-premise callout: the issue says the two alerts "never reach a read channel", but `scheduled-betterstack-incident-mirror.yml` + `scripts/betterstack-incident-mirror.sh` (merged same-day via PR #11001, ADR-248) already mirror `GET uptime.betterstack.com/api/v2/incidents?resolved=false` into `[ci/betterstack-incident]` GitHub issues every 15 min — a channel that provably reached the operator on 2026-10-22. The heartbeat's incidents are uptime-surface incidents and are covered. Whether telemetry-sourced (logtail) alert incidents appear in that uptime API list is unverified — noted as a residual, and immaterial to the fix: push is the vendor's real-time channel and is additive, never a replacement for email or the mirror; (e) mechanism-vs-ADR check: `push = true` appears in no ADR's rejected-alternatives table; ADR-218's "email-acceptable surface" (quoting ADR-096) scoped the *substrate* choice for log alerts, not the notification channel — flipping `push` is orthogonal and consistent.

**Property List (Phase 0.6b).**

- P1: every Inngest-serving alert resource delivers to a channel that is not an unread inbox (push and/or incident mirror).
- P2: the change is measured at apply — a vendor refusal is loud (422) and reverts per the #9168 convention, never silently widened to other resources.

**Cut List (Phase 0.6b).**

- `var.betterstack_paid_tier = true` → buys P1 through `policy_id` attachment but changes every monitor's escalation linkage fleet-wide and presumes a paid plan whose existence is unverified — the per-resource `push` flip buys the same property at smaller blast radius.
- Dedicated Slack/webhook channel → buys P1, but the issue itself marks it "subsumed by the default-notification-posture direction in #7662" — cut as already-covered machinery.

**Relevant file paths.**

- `apps/web-platform/infra/betterstack-logs-alerts.tf:264` — `logtail_exploration_alert.inngest_luks_wrong_volume` (push at ~L298).
- `apps/web-platform/infra/betterstack-logs-alerts.tf:725` — `logtail_exploration_alert.inngest_step_524` (push at ~L740).
- `apps/web-platform/infra/uptime-alerts.tf:531` — `betteruptime_heartbeat.inngest_server_probe` (push at L538).
- `apps/web-platform/infra/uptime-alerts.tf:220-236` — `app_health` measured-flip comment + `push = true` precedent.
- `apps/web-platform/infra/inngest.tf:325,415` — `inngest_prd`/`inngest_consumer` heartbeats already carrying `push = true` (#11001).
- `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh:73-90` — the ONLY test pinning the channel block: `(d)` asserts `call/sms/push all false`; `EXPECTED_PASSES=21` (L190).
- `.github/workflows/apply-web-platform-infra.yml:619,622,642,654,660` — all three target addresses already ride the per-merge `-target` allow-list; no workflow edit needed.
- `scripts/betterstack-incident-mirror.sh` — the mirror; reads uptime incidents only (no logtail coverage claim found).
- `plugins/soleur/scripts/inngest-luks-alert-armed-probe.ts` — precedent for the Check-10-compatible discoverability probe shape.

**Institutional learnings.**

- `knowledge-base/project/learnings/2026-09-23-the-alert-i-was-told-paged-routed-to-nobody.md` — "a claim that an alert 'pages' is a claim about three hops": emit path, rule, delivery. This change touches only hop 3 (delivery channel); hops 1-2 are already verified live (heartbeat armed with measured beat, wrong-volume alert armed via `var.inngest_luks_cutover_complete` default `true`).

**External documentation.** Better Stack Logs API `logtail_exploration_alert` schema carries `push` as a first-class boolean beside `call`/`sms`/`email` (docs: betterstack.com/docs/logs/api/exploration-alerts/ — response example shows `"push": false`). Push notifications sit under Better Stack's on-call feature set; acceptance on the current plan is the known unknown the measured-flip convention exists to resolve. On `betteruptime_heartbeat` it is already measured: PR #11001 merged push=true ×2 on 2026-10-25 and the merge-triggered apply (run at 03:52:15Z) completed `success` — the vendor accepted the attribute on this plan, on this resource type, that day.

**Related issues/PRs.** #11068 (this fix); #9168 (measured-flip precedent); #11001 (push=true on heartbeat type, applied green); #8516 + #9703 (heartbeat + feeder); #9705 OPEN (review evidence for the heartbeat's birth — see Open Code-Review Overlap); #7662 (default-notification-posture direction); #11011 (sibling failure-class issue, pull-channel variant).

**Functional/community discovery.** Not run — no Task/subagent surface in this harness (Devin subagent, inline-fallback); the stack (Terraform + Better Stack providers) is already covered in-repo with three live precedents, so no community artifact could add coverage.

## Proposed Solution

Flip `push = false` → `push = true` on the three Inngest-serving alert resources, update the one test that pins `push = false`, and ship a Check-10-compatible discoverability probe. No new resources, no variable changes, no workflow edits — the diff is channel attributes on existing resources plus their static guards.

- `logtail_exploration_alert.inngest_luks_wrong_volume`: `push = true`, comment notes the #11068 flip under the #9168 convention.
- `logtail_exploration_alert.inngest_step_524`: `push = true`, same comment convention.
- `betteruptime_heartbeat.inngest_server_probe`: `push = true`, comment names the inngest_prd/inngest_consumer sibling parity.
- `inngest-server-probe-heartbeat.test.sh` section (d): the third `has` flips from `push = false` to `push = true`; assertion count stays 21; labels/comments updated ("ops@ email only, like DP-10" is no longer the invariant — push parity with inngest_prd/inngest_consumer is).
- `plugins/soleur/scripts/inngest-alerts-push-probe.ts`: standalone probe that extracts the three resource blocks and exits 0 with `PUSH_ARMED` only when all declare `push = true`; else `PUSH_MISSING <resource>` exit 1. Standalone file (not `bun -e`) because preflight Check 10's sandbox rejects shell-active tokens — the inngest-luks-alert-armed-probe.ts precedent.

Vendor acceptance is measured by the merge-triggered apply itself: all three addresses already ride the `-target` allow-list, so the apply attempts the attribute diff. A 422 or refusal fails the run loudly → revert the refused `push` attribute(s) to `false` in a follow-up and record the measurement in the resource comment — the exact #9168/#11001 convention.

## Technical Considerations

- **Measured, not assumed.** `push = true` is live-proven on this vendor plan for `betteruptime_monitor` (#9168) and `betteruptime_heartbeat` ×2 (#11001, applied 2026-10-25). For `logtail_exploration_alert` the attribute is in-schema but vendor-plan acceptance is unmeasured — the apply is the measurement, with `push = false` the documented revert.
- **No escalation change.** `policy_id`/`escalation_target.policy_id` stay `var.betterstack_paid_tier`-gated; this plan does not touch escalation policy or paid-tier state.
- **Push is additive and bounded.** `email = true` stays; `call`/`sms` stay `false`; `critical_alert = false` stays on the logtail alerts. Push delivery presumes a Better Stack mobile app on the receiving device — a vendor-side precondition Terraform cannot provision; the inngest.tf comment already records that limitation and names the GitHub-issue mirror the deliverable channel.
- **`ignore_changes = [paused]` untouched.** The heartbeat's external arming (unpaused after an observed beat, per the resource comment) is unaffected; `paused` is not in scope.
- **Drift posture.** `push` has no `ignore_changes`, so a console-side toggle is reverted by the next apply — desired: source-of-truth stays Terraform.
- **No test coverage gap elsewhere.** Verified: only `inngest-server-probe-heartbeat.test.sh` pins these resources' channel attributes; `terraform-target-parity.test.ts` covers `-target` edges (unchanged); `heartbeat-live-reconcile.ts` reads `paused`/`pausedReason` live (push flip is invisible to it — no drift report).

## Files to Edit

1. `apps/web-platform/infra/betterstack-logs-alerts.tf` — `push = true` on `logtail_exploration_alert.inngest_luks_wrong_volume` (~L298) and `logtail_exploration_alert.inngest_step_524` (~L740); one comment line per resource naming #11068 and the measured-flip convention.
2. `apps/web-platform/infra/uptime-alerts.tf` — `push = true` on `betteruptime_heartbeat.inngest_server_probe` (L538); comment naming the inngest_prd/inngest_consumer parity + #11068.
3. `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` — section (d): assert `push = true` for `inngest_server_probe` (keep `call`/`sms` `false`); update the "ops@ email only, like DP-10" label and block comment; `EXPECTED_PASSES` stays 21 (expectation flips, count unchanged).

## Files to Create

1. `plugins/soleur/scripts/inngest-alerts-push-probe.ts` — ~50-line probe; discovers the three resource blocks in `apps/web-platform/infra/{betterstack-logs-alerts,uptime-alerts}.tf` and prints `PUSH_ARMED` (exit 0) when every one declares `push = true`, else `PUSH_MISSING <resource>` (exit 1). `argv[2]` test seam mirroring inngest-luks-alert-armed-probe.ts for a synthesized pre-change root.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/betterstack-logs-alerts.tf` and `apps/web-platform/infra/uptime-alerts.tf` — three `push` attribute flips on existing resources. No new resources, no provider additions, no new variables, no sensitive values.

### Apply path

Per-merge `apply-web-platform-infra.yml` apply — all three addresses (`logtail_exploration_alert.inngest_luks_wrong_volume`, `logtail_exploration_alert.inngest_step_524`, `betteruptime_heartbeat.inngest_server_probe`) are already on the `-target` allow-list (workflow lines 619-660). In-place attribute update: zero downtime, blast radius confined to notification routing on the three resources. A vendor refusal (422) fails the run loudly and is answered by the documented `push = false` revert — never silently.

### Host fan-out

None — no `terraform_data` SSH provisioners touched; no host state changes.

### Distinctness / drift safeguards

prd-scoped resources only (each name carries the `-prd` suffix). `push` carries no `ignore_changes`, so Terraform owns it; a console-side drift is corrected by the next apply. No secret values land in state from this change.

### Vendor-tier reality check

Current plan already accepts `push = true` on `betteruptime_monitor` (live since #9168) and `betteruptime_heartbeat` ×2 (#11001, apply green 2026-10-25T03:52Z). `logtail_exploration_alert` push is in-schema but unmeasured on this plan — the merge apply measures it; refusal reverts per the convention recorded at `uptime-alerts.tf:220-225` and `inngest.tf:334`. `var.betterstack_paid_tier` stays `false`; the `betteruptime_policy.uptime`/`inngest` count-gating is unchanged.

## Observability

```yaml
liveness_signal:
  what:            Better Stack heartbeat inngest_server_probe (hourly dead-probe switch) + the two logtail threshold alerts; after this change their pages route email + push (+ GitHub-issue mirror for uptime-surface incidents)
  cadence:         heartbeat 3600s period / 1800s grace; logtail alerts 300s check
  alert_target:    email + push notification (Better Stack mobile) + [ci/betterstack-incident] issue mirror (uptime surface)
  configured_in:   apps/web-platform/infra/uptime-alerts.tf:531, apps/web-platform/infra/betterstack-logs-alerts.tf:264,725

error_reporting:
  destination:     apply-web-platform-infra.yml run result (vendor refusal fails the run) + [ci/betterstack-incident] issues via scripts/betterstack-incident-mirror.sh
  fail_loud:       a 422/refusal at apply fails the workflow run; a mirror read/write failure exits non-zero and checks Sentry error

failure_modes:
  - mode:          vendor refuses push on a logtail_exploration_alert (free-tier gate on the telemetry surface)
    detection:     apply-web-platform-infra run fails at the attribute apply (loud)
    alert_route:   failed CI run on main; revert to push = false in follow-up per #9168 convention
  - mode:          push accepted but no Better Stack mobile app on the receiving device
    detection:     none available to the repo (vendor-side delivery); email + issue mirror still cover the same incident
    alert_route:   unchanged email + [ci/betterstack-incident] mirror (no regression vs today)
  - mode:          regression — a resource silently reverts to push = false in a later edit
    detection:     plugins/soleur/scripts/inngest-alerts-push-probe.ts exits 1 (PUSH_MISSING <resource>); inngest-server-probe-heartbeat.test.sh row (d) fails for the heartbeat
    alert_route:   CI red on the PR carrying the revert

logs:
  where:           apply-web-platform-infra.yml run logs (attribute diff); Better Stack incident timeline (delivery records); mirror run logs
  retention:       GitHub Actions retention; vendor incident history per plan

discoverability_test:
  command:         bun plugins/soleur/scripts/inngest-alerts-push-probe.ts
  expected_output: PUSH_ARMED
```

## Encryption Posture

```yaml
at_rest:           # no persistent store introduced — attribute flips on existing alert resources
  - store:            apps/web-platform/infra/*.tf resource config (lands in terraform.tfstate via existing encrypted backend)
    mechanism:        provider-managed:existing-R2-state-backend (no new secret material — push is a boolean flag)
    evidence:         apps/web-platform/infra/*.tf (no sensitive value added); state backend per main.tf
    defends_against:  n/a — non-sensitive config only
    does_not_defend:  nothing new — same exposure class as every existing alert resource in state
    disclosed_as:     not-publicly-claimed
    live_verification: available — terraform plan output shows the attribute diff
in_transit:
  - connection:        Better Stack incident service -> receiving device (push notification channel, vendor-managed delivery)
    enforced_at:       vendor side — same connection class already live on betteruptime_heartbeat.inngest_prd / inngest_consumer (#11001)
    tls:               vendor-managed HTTPS/APNs delivery
    cert_verification: on
    does_not_defend:   a lost or app-less device — delivery is best-effort, email + issue mirror remain
    disclosed_as:      not-publicly-claimed
```

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing — the worst case is status quo (email-only paging on three internal infra alerts) or a loud apply failure. No user-facing artifact changes.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — notification-channel flags on internal observability resources carry no user data.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the change flips notification routing on internal-only alert resources; the signal content is unchanged and no user surface is touched — `none`, not `single-user incident`.
- `threshold: none, reason: alert-notification channel config on internal observability resources — no user data, no user-facing surface, blast radius confined to vendor notification routing`

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Every Inngest-serving alert resource routes `email = true` with `push/call/sms = false`" + "Flip `push = true` on the two Inngest resources, mirroring the measured `app_health` flip (#9168). Smallest diff" [issue #11068] | FR-1/FR-2/FR-3 (push=true on inngest_luks_wrong_volume, inngest_server_probe, inngest_step_524) — Files-to-Edit 1-2 | mapped |
| 2 | "Enable `var.betterstack_paid_tier` so `betteruptime_policy.uptime` attaches. Wider blast radius: it changes routing for every monitor in the file and requires the paid plan to actually exist" [issue #11068] | — | descoped — justification: the paid plan's existence is unverified and the change re-wires every monitor's `policy_id` fleet-wide; the per-resource flip buys the same property (P1) at smaller blast radius |
| 3 | "Dedicated channel (Slack/webhook integration in IaC). Largest change; subsumed by the default-notification-posture direction in #7662" [issue #11068] | — | descoped — justification: the issue itself marks it subsumed by #7662 (still OPEN) |
| 4 | "pick at implement time" [issue #11068 — the three-way design fork] | Proposed Solution — push flip chosen | mapped — ruled by investigation: push=true is measured-accepted on this vendor plan for both resource types already flipped (monitor #9168, heartbeats #11001); the other two shapes carry wider blast radius or are explicitly subsumed |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `push = true` on `logtail_exploration_alert.inngest_luks_wrong_volume` | "Flip `push = true` on the two Inngest resources" | asked |
| `push = true` on `betteruptime_heartbeat.inngest_server_probe` | "Flip `push = true` on the two Inngest resources" | asked |
| `push = true` on `logtail_exploration_alert.inngest_step_524` | "Every Inngest-serving alert resource routes `email = true` with `push/call/sms = false`" | inferred — justification: the issue's own finding quantifies over every Inngest-serving alert resource; `inngest_step_524` is the third member of that set carrying the identical email-only block — skipping it leaves the stated property false and re-files the same issue one resource later |
| `inngest-server-probe-heartbeat.test.sh` row (d) update | — | inferred — justification: the suite pins `push = false` at L81; without the update the merge is red (the guard exists precisely to pin this block, so the pin must move with the intended state) |
| `plugins/soleur/scripts/inngest-alerts-push-probe.ts` | — | inferred — justification: the Observability gate requires a discoverability_test; the property (push=true inside three named resource blocks across two files) cannot be asserted by a bare grep without a block-scoped extractor, and preflight Check 10 rejects shell-active tokens — the inngest-luks-alert-armed-probe.ts standalone-file precedent |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `plugins/soleur`
- Planned files: 4 | Estimated changed lines: ~90 (mostly probe + comments)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

**Merging this PR alone mutates production:** `apply-web-platform-infra.yml` fires `on: push` to main for `apps/web-platform/infra/**`, and all three addresses are on its `-target` allow-list — the merge click is the per-command authorization, and the apply result is the vendor-acceptance measurement. PR body carries `Ref #11068`, not `Closes` (ADR-218 precedent: a Better Stack alert change verified by merge-triggered apply keeps its issue open until the apply verdict is in).

### Pre-merge (PR)

- [ ] `logtail_exploration_alert.inngest_luks_wrong_volume` declares `push = true` in `apps/web-platform/infra/betterstack-logs-alerts.tf`.
- [ ] `logtail_exploration_alert.inngest_step_524` declares `push = true` in `apps/web-platform/infra/betterstack-logs-alerts.tf`.
- [ ] `betteruptime_heartbeat.inngest_server_probe` declares `push = true` in `apps/web-platform/infra/uptime-alerts.tf`.
- [ ] On all three resources: `email` stays `true`, `call`/`sms` stay `false`, `critical_alert`/`paused`/`ignore_changes`/`policy_id` gating unchanged.
- [ ] Census: every Inngest-serving alert resource declares `push = true` — `inngest_luks_wrong_volume`, `inngest_step_524`, `inngest_server_probe`, `inngest_prd`, `inngest_consumer` (the last two already carry it; the census is the property, not the diff).
- [ ] `bash apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` reports 21/21 passes with the updated `push = true` assertion.
- [ ] `bun plugins/soleur/scripts/inngest-alerts-push-probe.ts` exits 0 printing `PUSH_ARMED` post-change; on the pre-change tree it exits 1 naming the first missing resource (`PUSH_MISSING`).
- [ ] No new resources, no workflow edits, no variable changes — all three addresses already ride the per-merge `-target` allow-list in apply-web-platform-infra.yml.

### Post-merge (automated apply verdict)

- [ ] The merge-triggered apply-web-platform-infra run either applies the push diff green, or — on a vendor refusal (422/no-op) — a follow-up reverts the refused `push` attribute(s) to `false` and records the measurement in the resource comment (#9168 convention). The apply result, not the merge, is the vendor-acceptance measurement; #11068 closes on the green verdict, or stays open carrying the refusal measurement if reverted.

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering

**Status:** reviewed (inline — no Task/subagent surface in this harness; Devin subagent, inline-fallback per the PR #9699/#11001 precedent)
**Assessment:** Minimal architectural implication — a channel-attribute flip on three existing resources with three live same-plan precedents (app_health #9168; inngest_prd/inngest_consumer #11001). No new substrate, no trust boundary, no ADR needed (alert-notification posture direction is already tracked under #7662). The apply-as-measurement convention bounds the vendor unknown to a loud apply failure + one-line revert.

### Operations

**Status:** reviewed (inline — same harness constraint)
**Assessment:** No procurement or vendor change — stays on the current plan; the paid-tier alternative is explicitly descoped (unverified paid plan + fleet-wide policy re-wire). Push delivery effectiveness depends on a Better Stack mobile app being present on the receiving device — a vendor-side precondition outside Terraform's reach, recorded as a channel limitation rather than a provisioning step; the incident mirror remains the guaranteed read channel.

## Open Code-Review Overlap

- **#9705** (OPEN) — `review: dead-probe heartbeat for inngest wrong-volume alert — evidence for PR #9699` names `inngest_server_probe` and `inngest_luks_wrong_volume`. **Acknowledge** — it is a point-in-time review-evidence record of the heartbeat's birth state (`push = false` was the intended invariant then, pinned by the same test row (d) this plan now updates). Flipping `push` does not invalidate its findings; the issue remains open as the review ledger. Not folded in, not deferred.

## Test Scenarios

- **unit (probe):** Given the pre-change tree (synthesized root via `argv[2]` seam), when `bun plugins/soleur/scripts/inngest-alerts-push-probe.ts` runs, then exit 1 with `PUSH_MISSING inngest_luks_wrong_volume` (first missing resource in enumeration order).
- **unit (probe):** Given the post-change tree, when the probe runs, then exit 0 with `PUSH_ARMED`.
- **unit (static suite):** Given `push = true` on the heartbeat, when `bash apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` runs, then row (d) passes and the suite reports 21 passed / 0 failed.
- **mutation:** Given any one of the three resources reverted to `push = false`, when the probe runs, then exit 1 naming that resource — and, for the heartbeat, the suite row (d) fails.
- **integration (vendor measurement):** Given the merged diff, when the per-merge apply runs, then the plan output shows `push: false -> true` on the three addresses and the apply exits green; a refusal surfaces as a failed run (loud, with the revert follow-up as the recorded remedy).
- **e2e (delivery) — `pyramid-justified: the property under fix is vendor notification delivery, which no lower layer can observe`:** on the next alert firing (issue's own re-evaluation trigger), the incident produces a push notification in addition to email + mirror-filed issue. Not gateable in-repo; the apply green is the merge-time verdict.

## Context

- Measured-flip convention: `uptime-alerts.tf:220-225` and `inngest.tf:334` — "`push` armed under the #9168 measured-flip convention: a vendor-attribute flip measured on apply — if the vendor refuses or no-ops, revert to `push = false` in a follow-up."
- The GitHub-issue mirror (`scheduled-betterstack-incident-mirror.yml`, #10390 WS1 / ADR-248) is the guaranteed read channel for uptime-surface incidents; push adds the real-time channel. Telemetry-sourced (logtail) incident visibility in the uptime incidents API is unverified — the flip is independent of that answer.
- `inngest-server-probe-heartbeat.test.sh` EXPECTED_PASSES=21 is an anti-vacuity count: the update keeps the count and flips the expectation — do not add or delete assertions.

## Deepen Pass (soleur:deepen-plan, 2026-10-25)

Halt-gate results (inline run — no Task/subagent surface in this harness; research fan-out agents unavailable, gates run mechanically in-process):

- 4.6 User-Brand Impact: PASS — section present, threshold `none` with scope-out reason (internal observability surfaces only).
- 4.7 Observability: PASS — all 5 fields populated; `discoverability_test.command` = `bun plugins/soleur/scripts/inngest-alerts-push-probe.ts` (verb `bun` on the Check-10 allowlist, no ssh, no shell-active tokens); `expected_output: PUSH_ARMED` is a matchable literal; the probe script ships in the same PR so the command exists in this tree.
- 4.8 PAT-shaped variable: PASS — no PAT tokens referenced.
- 4.9 UI wireframe: N/A — no UI-surface files in Files to Create/Edit.
- 4.10 Encryption Posture: PASS — section present; `does_not_defend` populated on every row; no plaintext-exception / cert_verification-off rows, so no `exception` block required.
- 4.11 Guard Contract: N/A — the deliverable carries no guard/gate/lint; `inngest-alerts-push-probe.ts` is a Phase 2.9 discoverability probe (read-only verifier), not a standing gate. The updated `inngest-server-probe-heartbeat.test.sh` row (d) is an existing assertion whose expectation flips with the intended state — its assembly and count (21) are unchanged.
- 4.12 Scope Check: PASS — exactly one unfenced `## Scope Check`; all four asks mapped or descoped with justification; three `inferred` items each carry a justification.
- 4.13 Task Design: N/A — no new autonomous-task surface.
- 4.5 network-outage / 4.55 downtime-cutover / 4.4 precedent-diff: N/A — no SSH patterns; in-place attribute update with zero downtime; the change pattern is itself the repo precedent (app_health #9168, inngest_prd/inngest_consumer #11001), cited inline.

Deepen findings applied at plan time (folded in before this pass): third Inngest-serving alert `inngest_step_524` folded into scope; `Ref #11068` semantics over `Closes` (ADR-218 precedent for apply-verified alert changes); pre/post-merge AC split; merge-mutates-production statement; mirror-coverage nuance recorded in Premise Validation.

## References

- Issue: #11068
- Precedents: #9168 (app_health measured flip), PR #11001 (push=true on betteruptime_heartbeat ×2, apply green 2026-10-25)
- Sibling/context: #8516, #9703, #9705, #7662, #11011
- ADRs: ADR-218 (logtail alerts via Terraform), ADR-248 (incident mirror substrate), ADR-222 (readiness pager)
