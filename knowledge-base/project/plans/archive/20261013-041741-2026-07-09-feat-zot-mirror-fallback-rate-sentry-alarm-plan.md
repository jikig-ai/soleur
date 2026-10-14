---
title: Provision the live zot mirror-staleness Sentry fallback-rate alarm (>3/1h) + inngest-bootstrap mirror push-notification signal
issue: 6278
branch: feat-one-shot-6278-zot-mirror-staleness-alarm
type: observability-infra
lane: single-domain
brand_survival_threshold: aggregate pattern
date: 2026-07-09
labels: [priority/p3-low, domain/engineering, observability, deferred-automation]
---

# Provision the live zot mirror-staleness Sentry alarm (#6278)

> **IMPLEMENTATION NOTE (supersedes the "Branch B primary" framing below).** During Phase-0
> the `soleur:engineering:cto` agent ruled **Branch A (`sentry_issue_alert` + `event_frequency`)**
> as the shipped mechanism, and rejected Branch B (`sentry_metric_alert`): metric-alert actions
> require a numeric notify target that does not exist in the Sentry TF root and is unresolvable
> in an autonomous session (CI-only auth token) → risk of paging nobody. The per-issue-group
> sensitivity of Branch A is accepted (it reliably pages the dominant shared-tag outage) and
> operator-surfaced; the metric-alert upgrade is a filed follow-up. Full rationale + rejected
> alternatives: `../specs/feat-one-shot-6278-zot-mirror-staleness-alarm/decision-challenges.md`.

## Overview

ADR-096 (self-hosted zot registry migration) mitigates the "zot is a boot-time SPOF"
risk on four axes. One axis — **"Loud, no-SSH signal"** — states *"every fallback emits a
Sentry `registry:"ghcr-fallback"` … event (the fallback-rate alarm pages at >3/1h)."* The
emit side of that axis is live (`ci-deploy.sh registry_pull_event`, merged), but the alarm
itself was recorded as **"design intent, not yet provisioned"** and deferred as #6278 (from
#6274). It becomes **load-bearing at the ADR-096 Phase-5 GHCR-push retirement**: post-cutover
a silently-missing (or present-but-unsigned) zot copy can gate a host boot, and the only
no-SSH page for a sustained fallback is this alarm.

This plan delivers two things:

1. **The live runtime fallback-rate Sentry alarm** — a new `sentry_issue_alert` (or, per the
   Phase-0 provider-schema probe, a `sentry_metric_alert`) in
   `apps/web-platform/infra/sentry/issue-alerts.tf` that pages when the fallback/degrade event
   rate exceeds **>3 in 1h**. This is the **live runtime** alarm — separate IaC from the
   **create-time CI degraded signal** (`mirror_status=degraded` → Slack ⚠️ + `::warning::`)
   that merged in PR #6276 (#6274).

2. **A live/push-notification signal for the inngest-bootstrap mirror degrade path.** The
   `build-inngest-bootstrap-image.yml` `zot_mirror` step's `degraded()` currently emits
   `::warning::` + step-summary only ("annotations-only by design"), unlike its sibling
   `reusable-release.yml` which also posts a Slack ⚠️ line (PR #6276). Before cutover this
   path should get an equivalent push signal.

Both are **P3-low, deferred-automation** follow-ups; neither is user-facing.

## Enhancement Summary

**Deepened on:** 2026-07-09 · **Research agents:** Explore (provider-schema verification), architecture-strategist (alarm-design review).

### Key improvements from deepen-plan
1. **`event_frequency` IS in the beta2 provider schema — repo comments are stale.** The Explore
   agent inspected the cached provider binary (`.../jianyuan/sentry/0.15.0-beta2/.../terraform-provider-sentry_v0.15.0-beta2`,
   present in the sibling worktree `feat-one-shot-anthropic-cost-attribution`) and found
   `event_frequency`, `event_frequency_count`, `event_frequency_percent` as first-class
   `conditions_v2` block types (same field shape as the proven `event_unique_user_frequency`:
   `comparison_type`/`value`/`interval`/`comparison_interval`). The claims at
   `issue-alerts.tf:838-839` + `ADR-062:120` ("no verified event_frequency support") are **false** —
   only "no in-repo precedent" is literally true. This de-risks the Phase-0 gate to a network-free probe.
2. **Primary mechanism flipped to `sentry_metric_alert` (aggregate) — issue-alert is under-sensitive.**
   architecture-strategist (P1) showed the runbook specifies an *aggregate* count>3/1h across the
   OR-of-three, but issue-alert `event_frequency` evaluates **per fingerprinted issue-group**, and
   the three signals fingerprint into distinct issues — *worsened* by per-message fingerprinting
   (`ci-deploy.sh:561` builds `"…(web:<tag>)"` vs `"…(inngest:<tag>)"`; `:590` varies by reason).
   A distributed outage (2 inngest + 2 web + 1 gate-degraded = aggregate 5) pages **zero** groups at
   3/1h → the issue alert stays **silent** on exactly the distributed sustained-degradation the alarm
   targets. Under-sensitivity is the wrong failure direction for a deliberately-low page threshold.
   **Branch B (metric alert) is now primary**; Branch A (issue-alert + event_frequency) is the
   fallback, and if selected the PR MUST surface the per-path (non-aggregate) sensitivity to the operator.
3. **Branch-B query bug fixed:** these are `store`-API events with `level:warning` and **no
   exception** → `event.type:default`, not `error`. The earlier `event.type:error`-prefixed query
   would exclude every event → a silent-no-op alarm. Query prefix dropped; Phase-0 must confirm the
   metric-alert dataset matches `event.type:default` warning events.
4. **Branch-B guard gap closed (P1):** `tests/scripts/lib/destroy-guard-filter-sentry.jq` needs a new
   `sentry_metric_alert` nested-clause (array-of-blocks `trigger[]`/`action[]`) — omitting it is a
   silent destroy-guard bypass for the new type. Added to Branch-B Files to Edit + Phase 2 + Sharp Edges.
5. **Boot-coverage overstatement corrected (P2):** the main **app-image** fresh-boot pull
   (`cloud-init.yml:485-501`) does zot→GHCR fallback but emits **no** fallback breadcrumb (only a
   `stage=pull` *fatal* on total failure) — so a fresh-boot zot miss on the primary web container that
   *succeeds* via GHCR is invisible and no alarm can page on it. Added an in-scope emit task (Phase 1b)
   + a 4th signal so the alarm genuinely covers the boot path, with a descope-to-blind-spot alternative.

### Verified-correct premises (no change)
`frequency = 23` is genuinely free; `event_unique_user_frequency` correctly rejected (host events carry
no `user`); `filter_match="any"` over the globally-unique tag-values is safe (Q3 endorsed — no other
emitter uses these values); Branch-A guard sweep ("only the `-target` line") verified complete (Q4).

## Premise Validation

All cited artifacts verified against the worktree (`origin/main` tip) — **no stale premises**:

- **Issue #6278** — OPEN, milestone "Post-MVP / Later". Its body is the source of scope.
- **Infra path `apps/web-platform/infra/sentry/issue-alerts.tf`** — EXISTS (1319 lines, 20
  `sentry_issue_alert` resources: 4 import-only auth rules + 16 apply-created rules).
- **Emitting marker `feature:supply-chain op:image-pull registry:"ghcr-fallback"`** — genuinely
  emitted by `apps/web-platform/infra/ci-deploy.sh:562-564` (`registry_pull_event ghcr-fallback`,
  `level: warning`). Confirmed via `git grep`. The `zot-soak-6122.sh` follow-through already
  queries this exact string (`sentry_count 'feature:supply-chain op:image-pull registry:"ghcr-fallback"'`).
- **PR #6276 (#6274)** — merged 2026-07; added the CI-level `mirror_status=degraded` signal to
  BOTH mirror workflows + the Slack ⚠️ line to `reusable-release.yml` only. Confirmed via
  `reusable-release.yml:829-914` (Slack step reads `MIRROR_STATUS`) and the
  `build-inngest-bootstrap-image.yml` `zot_mirror` comment ("No Slack step in this workflow …
  annotations-only by design").
- **ADR-096** — Status "Adopting"; the "Loud, no-SSH signal" bullet + the CI-push sub-bullet
  explicitly call this alarm "design intent, not yet provisioned — a separate IaC follow-up".
- **Runbook `zot-registry-revert.md`** — §"Fallback-rate alarm" is the authoritative operational
  design of the alarm (see Research Reconciliation — it is BROADER than the issue body).
- **Own-capability bound (hr-verify-repo-capability-claim-before-assert):** the claim "beta2's
  `conditions_v2` supports raw event-count thresholds" was NOT assumed — ADR-062:120 + the
  `container-restart-monitor` comment (issue-alerts.tf:838) both state beta2's `conditions_v2`
  has **no verified `event_frequency` support**. This is the load-bearing Phase-0 gate below,
  not an assumption.

## Research Reconciliation — Spec vs. Codebase

Three material divergences between the issue body's literal ask and codebase/runbook reality.
The plan resolves each explicitly rather than inheriting the issue's simplification.

| Spec claim (issue body) | Reality (verified) | Plan response |
|---|---|---|
| Alarm matches `feature:supply-chain op:image-pull registry:"ghcr-fallback"` (one signal). | The **authoritative runbook** (`zot-registry-revert.md` §Fallback-rate alarm) specifies the alarm should page on the **OR of three** runtime signals: `registry:"ghcr-fallback"` (rolling deploy) **OR** `stage:"inngest_ghcr_fallback"` (fresh-boot inngest pull, `cloud-init.yml:650`) **OR** `registry:"zot-gate-degraded"` (`ci-deploy.sh zot_gate_degraded_event`). ADR-096's axis — which the issue cites — names the broad alarm. | **Recommend covering all three** (see Phase 1 design decision). Leaving `inngest_ghcr_fallback` + `zot-gate-degraded` unpaged reopens the exact boot-gating gap #6278 exists to close at cutover. The issue's single-signal wording is a simplification, not a scope ceiling. |
| A `>3/1h` "fallback-rate" threshold is trivially a raw event-count condition. | **[deepen-plan CORRECTED]** `event_frequency` IS in the beta2 `conditions_v2` schema (Explore agent verified the cached provider binary — `event_frequency`/`event_frequency_count`/`event_frequency_percent` block types exist). The `ADR-062:120` + `issue-alerts.tf:838` "no verified support" comments are **stale** ("no in-repo precedent" is the only true part). These host-emitted events carry **no `user`** → `event_unique_user_frequency` (the sibling that IS used in-repo) would count 0 users and never fire. | **Primary = `sentry_metric_alert` (aggregate)** — architecture-strategist P1: issue-alert `event_frequency` thresholds are **per-issue-group**, and the 3 signals fingerprint into distinct issues (further split by message string), so a distributed 2+2+1 outage never reaches 3/group and the alarm stays silent — the wrong failure direction. Metric alerts aggregate across the query. **Fallback = `sentry_issue_alert` + `event_frequency`** (now schema-confirmed); if used, the PR must surface the per-path (non-aggregate) sensitivity to the operator. `event_unique_user_frequency` **rejected** (no user on events). Phase-0 confirms the metric-alert dataset matches these `event.type:default` warning events. |
| The three signals all share `feature:supply-chain op:image-pull` (implied by the runbook prose). | The fresh-boot `inngest_ghcr_fallback` event (`cloud-init.yml:316,650` via `soleur-boot-emit`) carries only `{stage, image_ref, host_id, detail}` — **NOT** `feature`/`op`. Only the two `ci-deploy.sh` signals carry `feature:supply-chain op:image-pull`. | A single `filter_match="all"` on `feature`+`op` CANNOT match the inngest path. Filter design must be `filter_match="any"` over the tag-values (issue-alert branch) or an OR query (metric-alert branch). Phase-0 confirms each emit site's exact tag set before freezing the filter. |

## Implementation Phases

### Phase 0 — Provider-schema + dataset probe (load-bearing; blocks all design choices)

The provider binary is **already cached** in the sibling worktree
`.worktrees/feat-one-shot-anthropic-cost-attribution/apps/web-platform/infra/sentry/.terraform/…/jianyuan/sentry/0.15.0-beta2/`
— so the schema probe needs **no `terraform init` / no network**. Record answers into spec before Phase 1.

1. **`sentry_metric_alert` shape (PRIMARY branch).** Confirm the resource + its `aggregate`,
   `dataset`, `query`, `time_window` (seconds), `threshold_type`, nested `trigger { alert_threshold,
   action {…} }` attributes.
   ```bash
   terraform -chdir=<sibling-sentry-dir> providers schema -json \
     | jq '.provider_schemas["registry.terraform.io/jianyuan/sentry"].resource_schemas.sentry_metric_alert.block'
   ```
2. **Metric-alert dataset matchability of `event.type:default` warning events (P1 — architecture-strategist).**
   These fallback events are `store`-API posts with `level:warning` and **no exception** →
   `event.type:default`, NOT `error`. Confirm the chosen `dataset` (likely `events`, not `errors`) +
   query returns them; **the query must NOT be prefixed `event.type:error`** (that excludes every one →
   silent-no-op alarm). If the metric-alert dataset cannot match default/warning events, fall back to Branch A.
3. **`event_frequency` block in `conditions_v2` (FALLBACK branch — already CONFIRMED present).**
   ```bash
   terraform -chdir=<sibling-sentry-dir> providers schema -json \
     | jq '.provider_schemas["registry.terraform.io/jianyuan/sentry"].resource_schemas.sentry_issue_alert.block.block_types.conditions_v2.block.block_types | keys'
   # expect: [..."event_frequency","event_frequency_count","event_frequency_percent","event_unique_user_frequency"...]
   ```
4. **Re-confirm the exact tags each emit site carries** (freezes the filter/query):
   - `ci-deploy.sh:564` → `feature=supply-chain op=image-pull registry=ghcr-fallback image=<web|inngest>`
   - `ci-deploy.sh:592` → `feature=supply-chain op=image-pull registry=zot-gate-degraded zot_gate_reason=<...>`
   - `cloud-init.yml:316/650` (`soleur-boot-emit inngest_ghcr_fallback warning`) → `stage=inngest_ghcr_fallback image_ref=<...> host_id=<...>` (NO feature/op).
   - **[Phase 1b] app-image boot fallback** — after adding the emit, confirm `cloud-init.yml:~496` emits `stage=app_ghcr_fallback` on the zot→GHCR web-boot fallback branch.
5. **Pick a free `frequency` value** (issue-alert fallback branch only). Taken:
   5,10,11,12,13,14,15,16,17,18,19,20,21,22,30,60,61,62. **Use `frequency = 23`** (free).

**No `.tf` edit is frozen until this probe resolves.** Decision rule: **Branch B (metric alert)
unless step 2 proves the dataset cannot match default/warning events**, in which case Branch A with an
operator-surfaced per-path-sensitivity note.

### Phase 1 — Add the fallback-rate alarm resource to `issue-alerts.tf`

**Design decision:** cover the runtime fallback/degrade signals in ONE aggregate alarm. Primary is a
`sentry_metric_alert` (true aggregate count>3/1h across the OR — matches the runbook spec);
`sentry_issue_alert` + `event_frequency` is the Phase-0 fallback (its per-issue-group threshold is
under-sensitive to distributed degradation — architecture-strategist P1).

**Branch B (PRIMARY) — `sentry_metric_alert` (aggregate):** the native rate primitive; the runbook
explicitly sanctions "Sentry issue/**metric** alert". Final `aggregate`/`dataset`/`query`/trigger
shape frozen against the Phase-0 schema dump. Shape (illustrative — attribute names confirmed in Phase 0):
```hcl
# ── zot mirror fallback-rate alarm (#6278 / ADR-096 "Loud, no-SSH signal") ──
# APPLY-CREATED. Pages when the AGGREGATE runtime fallback/degrade rate exceeds
# >3 events in 1h across the OR-of-signals (zot-registry-revert.md §Fallback-rate
# alarm). Aggregate (not per-issue-group) so a distributed outage scattered across
# signals/images still pages (architecture-strategist P1). The live complement to
# the create-time CI degraded signal (#6274 / PR #6276).
resource "sentry_metric_alert" "zot_mirror_fallback_rate" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "zot-mirror-fallback-rate"
  dataset      = "events"       # Phase-0: MUST match event.type:default warning events, NOT "errors"
  aggregate    = "count()"
  time_window  = 60             # minutes → the "/1h" window
  # NO `event.type:error` prefix — these are level:warning/default store events (P1 fix).
  # Covers the 3 (→4 with Phase 1b) runtime signals; unique tag-values, so no feature/op needed.
  query          = "registry:ghcr-fallback OR registry:zot-gate-degraded OR stage:inngest_ghcr_fallback OR stage:app_ghcr_fallback"
  threshold_type = 0            # 0 = above
  trigger {
    label             = "critical"
    threshold_type    = 0
    alert_threshold   = 3       # >3 in the 60-min window
    resolve_threshold = 0
    action {
      type             = "email"
      target_type      = "team"   # Phase-0: confirm the notify-owners/team shape for a solo-founder org
      target_identifier = "<ops-team-or-member-id>"
    }
  }
}
```
Because this is a **new resource TYPE** for this root, Branch B ALSO requires: the `-target` set
(`apply-sentry-infra.yml`), the destroy-guard scope-guard allowlist, AND the destroy-guard **jq
filter** (`destroy-guard-filter-sentry.jq` — a `sentry_metric_alert` nested-clause summing
`trigger[]`/`action[]` deltas; omitting it is a silent destroy-guard bypass — architecture-strategist P1).

**Branch A (FALLBACK) — `sentry_issue_alert` + `event_frequency` (schema-confirmed):**
```hcl
resource "sentry_issue_alert" "zot_mirror_fallback_rate" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "zot-mirror-fallback-rate"
  action_match = "all"
  filter_match = "any"          # OR across the unique signal tag-values (Q3 endorsed)
  frequency    = 23             # free value; POST-time dedup avoidance
  conditions_v2 = [
    { event_frequency = { comparison_type = "count", value = 3, interval = "1h" } }
  ]
  filters_v2 = [
    { tagged_event = { key = "registry", match = "EQUAL", value = "ghcr-fallback" } },
    { tagged_event = { key = "registry", match = "EQUAL", value = "zot-gate-degraded" } },
    { tagged_event = { key = "stage",    match = "EQUAL", value = "inngest_ghcr_fallback" } },
    { tagged_event = { key = "stage",    match = "EQUAL", value = "app_ghcr_fallback" } },
  ]
  actions_v2 = [
    { notify_email = { target_type = "IssueOwners", fallthrough_type = "ActiveMembers" } }
  ]
  lifecycle { ignore_changes = [environment] }
}
```
**Branch A caveat (must be surfaced to the operator if used):** `event_frequency` evaluates
**per Sentry issue-group**, and the signals fingerprint into distinct issues (further split by
message string), so this fires at **per-path 3/1h**, NOT aggregate — a distributed 2+2+1 outage
would NOT page. Branch A only needs the `-target` line (Branch-A guard sweep verified complete, Q4).

### Phase 1b — Emit an app-image fresh-boot fallback breadcrumb (close the boot blind spot)

architecture-strategist P2: the main **app-image** fresh-boot pull (`cloud-init.yml:485-501`) does
zot→GHCR fallback (`N>=2 ⇒ REF="$IMAGE_REF"`) but emits **no** fallback signal — only a `stage=pull`
*fatal* on total failure. So a fresh-boot zot miss on the primary web container that *succeeds* via
GHCR is invisible; no alarm can page on it, and "closes the boot-gating gap" would be overstated.

Add a `soleur-boot-emit app_ghcr_fallback warning` on the web-boot zot→GHCR fallback branch
(`cloud-init.yml:~496`), symmetric with the inngest path at `:650`, and include `stage:app_ghcr_fallback`
as a 4th signal in the Phase-1 query/filter (already reflected above).

**Descope alternative (if the emit is judged out of scope for an alarm-provisioning PR):** drop the
4th signal, correct the plan/PR framing to "covers the rolling-deploy + inngest-boot + gate-degraded
signals; the app-image fresh-boot fallback remains an un-emitted blind spot", and file a follow-up
issue to add the emit before Phase-5 cutover. Do NOT ship the overstated "closes the gap" framing.

### Phase 2 — Wire apply + the cross-artifact op-contract test

1. **`.github/workflows/apply-sentry-infra.yml`** — append `-target=sentry_metric_alert.zot_mirror_fallback_rate \`
   (Branch B) or `-target=sentry_issue_alert.zot_mirror_fallback_rate \` (Branch A) to the `-target`
   block (after line 261).
   - **Branch B (metric alert — new resource TYPE) guard sweep (architecture-strategist P1):** ALSO
     (a) extend the scope-guard allowlist `tests/scripts/test-destroy-guard-sentry-scope-guard.sh:52`
     (`grep -vxE '…|sentry_metric_alert'`); (b) **add a `sentry_metric_alert` nested-clause to
     `tests/scripts/lib/destroy-guard-filter-sentry.jq`** summing `trigger[]`/`action[]` block deltas,
     mirroring `sentry_issue_alert_blocks_count` (`:50-54`) — the filter is the load-bearing artifact
     the whole suite exists to force; omitting it is a silent destroy-guard bypass for the new type;
     (c) add a counter-test fixture case (`test-destroy-guard-counter-sentry.sh`) exercising a
     metric-alert `trigger`/`action` nested delete.
   - **Branch A (issue-alert) guard sweep — verified complete (Q4):** the scope-guard keys on resource
     TYPE (`sentry_issue_alert` already allowed); the counter-test T4 anchors on a zero-changes captured
     baseline (`tfplan-sentry-real-baseline.json`, unaffected by a CREATE); the jq `sentry_issue_alert`
     clause excludes CREATEs (`before=null` → negative → `select(.>0)` drops it). **Only the `-target`
     line** is needed.
2. **New test `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`** —
   mirror `sentry-inbox-action-required-alert-op-contract.test.ts`: assert the emit site
   (`infra/ci-deploy.sh`) carries `registry: "ghcr-fallback"` + `registry: "zot-gate-degraded"` +
   `feature: "supply-chain"` / `op: "image-pull"`, that `cloud-init.yml` carries
   `inngest_ghcr_fallback`, and that `issue-alerts.tf` pins all three tag values + declares the
   resource. This is the "a rename in either artifact silently darks the alert" guard.

### Phase 3 — inngest-bootstrap mirror push-notification signal

Add a Slack ⚠️ push signal to `build-inngest-bootstrap-image.yml` matching the
`reusable-release.yml:906-914` pattern, so the inngest mirror degrade is not annotations-only
pre-cutover.

- Add a **`Post to Slack (inngest mirror status)`** step after the `zot_mirror` step, gated
  `if: steps.zot_mirror.outputs.mirror_status == 'degraded'` (only fires on degrade — this
  workflow has no per-release happy-path Slack, so a degrade-only notification is the minimal
  push signal), `continue-on-error: true`, reading `SLACK_RELEASES_WEBHOOK_URL` (same secret as
  `reusable-release.yml`; Phase-0 confirm it is a repo secret visible to this workflow).
- Reuse the exact injection-inert Slack posting shape from `reusable-release.yml:895-914`
  (jq-built payload, `--add-mask`, `|| echo 000` transport guard, HTTP-2xx check).
- Message: `⚠️ inngest-bootstrap zot mirror degraded (<TAG>) — GHCR unaffected, zot redundancy reduced; backfill needed.`
- **Update the `zot_mirror` step comment** ("annotations-only by design") to note the Slack signal
  was added per #6278 (pre-cutover push-notification parity with `reusable-release.yml`).

### Phase 4 — Verify (no SSH)

- `cd apps/web-platform/infra/sentry && terraform validate` (accept the documented
  `sentry_issue_alert` deprecation warning; issue-alerts.tf:16-38).
- `terraform plan` shows exactly **1 to add** (the new alarm), **0 to change/destroy** — scoped
  to the `-target` set. No import needed (apply-created).
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`.
- `actionlint .github/workflows/build-inngest-bootstrap-image.yml` + `bash -n` on the extracted
  Slack `run:` snippet.
- Post-merge (auto-apply): `apply-sentry-infra.yml` fires on the `issue-alerts.tf` path and creates
  the rule. Verify via Sentry API `GET /api/0/projects/jikigai-eu/web-platform/rules/` that the
  rule named `zot-mirror-fallback-rate` exists (no dashboard eyeballing;
  hr-no-dashboard-eyeball-pull-data-yourself).

## Files to Edit

- `apps/web-platform/infra/sentry/issue-alerts.tf` — add the `sentry_metric_alert.zot_mirror_fallback_rate` resource (Branch B, primary) OR `sentry_issue_alert.zot_mirror_fallback_rate` (Branch A, fallback). Also correct the stale `event_frequency` comment at `:838-839` if Branch A is used.
- `.github/workflows/apply-sentry-infra.yml` — append the new resource to the `-target` set.
- `.github/workflows/build-inngest-bootstrap-image.yml` — add the degrade-gated Slack step + update the `zot_mirror` "annotations-only by design" comment.
- `apps/web-platform/infra/cloud-init.yml` — **Phase 1b**: add `soleur-boot-emit app_ghcr_fallback warning` on the web-boot zot→GHCR fallback branch (`~:496`). (Descope alternative: skip + file follow-up.)
- `tests/scripts/lib/destroy-guard-filter-sentry.jq` — **Branch B only** (add `sentry_metric_alert` nested-clause; architecture-strategist P1 — the load-bearing omission).
- `tests/scripts/test-destroy-guard-sentry-scope-guard.sh` — **Branch B only** (add `sentry_metric_alert` to allowlist).
- `tests/scripts/test-destroy-guard-counter-sentry.sh` — **Branch B only** (new metric-alert nested-delete fixture case).
- `knowledge-base/engineering/architecture/decisions/ADR-096-…md` — optional one-line status annotation flipping the "design intent, not yet provisioned" line to "provisioned (#6278)".
- `knowledge-base/engineering/architecture/decisions/ADR-062-…md:120` — optional: correct the stale "no in-repo precedent for event_frequency / no verified support" note (schema DOES carry it; only "no precedent" is true).

## Files to Create

- `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` — cross-artifact op/tag contract test.

## Open Code-Review Overlap

None found. (`gh issue list --label code-review --state open` cross-checked against the file
paths above — no open scope-out names `issue-alerts.tf`, `apply-sentry-infra.yml`, or
`build-inngest-bootstrap-image.yml`. Re-run at Step 1.7.5 in deepen-plan against the final list.)

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — this is operator-facing infra
observability. A broken alarm means the *operator* is not paged when the zot mirror sustains a
fallback/degrade rate post-cutover; the concrete artifact is a missing Sentry page + a
still-green build/deploy while zot redundancy silently erodes.

**If this leaks, the user's data is exposed via:** no user data on this surface. The alarm's
events carry only `registry`/`stage`/`image`/`host_id`/`zot_gate_reason` tags (no PII); the
`ci-deploy.sh` emitter already scrubs docker stderr to a coarse classification before it enters
the payload (security-sentinel #7, ci-deploy.sh:518-521). The Slack step reuses the
injection-inert `md-to-mrkdwn`/jq-escaped shape.

**Brand-survival threshold:** aggregate pattern. A *single* transient `ghcr-fallback` is
self-healing (the host already fell back to GHCR and served correctly — runbook §"When to
revert"); only a *sustained* fallback pattern (>3/1h) is the incident this alarm exists to page.
No per-PR CPO sign-off required (threshold is not `single-user incident`). No sensitive-path
touched (no schema/auth/API route) → no `threshold: none` scope-out bullet needed.

## Acceptance Criteria

### Pre-merge (PR)

1. `terraform validate` in `apps/web-platform/infra/sentry/` passes (documented `sentry_issue_alert`
   deprecation warning accepted; no new errors).
2. `terraform plan` (scoped to the `-target` set) shows **1 to add, 0 to change, 0 to destroy**.
3. The new resource encodes an **aggregate >3 events / 1h**: Branch B metric alert
   `aggregate="count()"`, `time_window=60`, critical `alert_threshold=3`, dataset that matches
   `event.type:default` warning events, and **no `event.type:error` prefix** in the query; OR (fallback)
   Branch A `event_frequency` count>3/1h with the operator-sensitivity note in the PR body.
   `event_unique_user_frequency` is NOT used.
4. The alarm's query/filter matches all runtime signals: `registry:ghcr-fallback`,
   `registry:zot-gate-degraded`, `stage:inngest_ghcr_fallback`, AND `stage:app_ghcr_fallback` (Phase 1b).
   If Phase 1b is descoped, `app_ghcr_fallback` is dropped, the "closes the gap" framing is corrected,
   and a follow-up issue for the app-image emit is filed in the same PR.
5. `sentry-zot-mirror-fallback-alert-op-contract.test.ts` passes: emit sites + `issue-alerts.tf`
   pin all asserted tag values; a rename in either breaks CI (`grep -c` on the resource declaration ≥ 1).
6. `.github/workflows/apply-sentry-infra.yml` `-target` set contains the new resource
   (`grep -c 'target=sentry_\(issue\|metric\)_alert.zot_mirror_fallback_rate' … == 1`).
7. `build-inngest-bootstrap-image.yml` has a degrade-gated Slack step
   (`if: steps.zot_mirror.outputs.mirror_status == 'degraded'`) reading `SLACK_RELEASES_WEBHOOK_URL`;
   `actionlint` clean; the `zot_mirror` "annotations-only by design" comment is updated to cite #6278.
8. **Branch B only:** all THREE guard artifacts updated — `destroy-guard-filter-sentry.jq` has a
   `sentry_metric_alert` nested-clause, the scope-guard allowlist includes `sentry_metric_alert`, and a
   counter-test fixture case exercises a metric-alert `trigger`/`action` nested delete (guard suites green).
9. PR body uses `Closes #6278` (this is a code PR that self-satisfies on merge — the alarm exists
   in IaC at merge; the auto-apply is the deploy, not a separate operator remediation).

### Post-merge (operator — all automatable, no SSH)

10. `apply-sentry-infra.yml` auto-fires on the `issue-alerts.tf` path change and applies the rule.
    Verify (automatable via Sentry API, not dashboard): `GET /api/0/projects/jikigai-eu/web-platform/rules/`
    returns a rule named `zot-mirror-fallback-rate`. No `[skip-sentry-apply]` in the merge commit.
    *Automation: the merge IS the apply trigger; verification is a `curl` against the Sentry API — no operator step is genuinely manual.*

## Domain Review

**Domains relevant:** Engineering (CTO) only.

### Engineering

**Status:** reviewed (inline — infra/observability-only change; deepen-plan spawns the CTO/architecture panel).
**Assessment:** Pure IaC + CI-workflow change against an already-provisioned surface (the Sentry
Terraform root + the emit sites both exist and are live). The load-bearing risk is provider-schema
expressiveness (`event_frequency` in beta2 `conditions_v2`), gated at Phase 0. No new secret, no new
vendor, no new host. Sequencing note: the alarm is inert-but-harmless until the events exist
(pre-cutover the fleet emits zero) — provisioning early is safe and is exactly the ADR-096 Phase-5
prerequisite. No Product/UX (no UI surface), no Finance/Legal/Sales/Marketing/Support implications.

## Infrastructure (IaC)

### Terraform changes
- **Files:** `apps/web-platform/infra/sentry/issue-alerts.tf` (existing root; extend). Provider
  `jianyuan/sentry@0.15.0-beta2` (pinned, `.terraform.lock.hcl`). No new provider, no new variable,
  no new secret. Auth: `SENTRY_AUTH_TOKEN` (GitHub repo secret `SENTRY_IAC_AUTH_TOKEN` in CI; ADR-031
  secret-store divergence — NOT Doppler). R2 backend creds from Doppler `prd_terraform`.
- **New resource:** one `sentry_issue_alert.zot_mirror_fallback_rate` (Branch A) OR one
  `sentry_metric_alert.zot_mirror_fallback_rate` (Branch B). Apply-created (no import).

### Apply path
- **Cloud-init-only? No — auto-apply via existing pipeline.** `apply-sentry-infra.yml` fires on
  push-to-main touching `issue-alerts.tf` and runs `terraform apply` scoped to the `-target` set.
  The PR merge IS the human authorization (`hr-menu-option-ack-not-prod-write-auth`). Blast radius:
  a single new alert rule; the `-target` scoping never touches the import-only auth rules. Zero
  downtime. No operator SSH, no dashboard click.

### Distinctness / drift safeguards
- `lifecycle { ignore_changes = [environment] }` — the provider recomputes `environment` on read for
  project-wide rules (matches every sibling apply-created rule). `dev != prd`: N/A (Sentry IaC is a
  single prd org `jikigai-eu`, not dev/prd-split). Secret values do NOT land in this rule (no token
  attributes). Distinct `frequency = 23` avoids Sentry POST-time exact-duplicate dedup.

### Vendor-tier reality check
- No paid-tier gate. Sentry issue/metric alerts on the existing project are within the current plan
  (the project already carries 20 issue alerts + cron/uptime monitors). No `count = var.*_paid_tier`
  guard needed.

## Observability

```yaml
liveness_signal:
  what: "The alarm resource IS a liveness signal for the zot mirror. Its own existence is verified by the op-contract test (source-of-truth pinning) + a post-apply Sentry-API rule-list read."
  cadence: "Real-time (Sentry evaluates on each matching event); pages at >3 fallback events / 1h."
  alert_target: "IssueOwners → ActiveMembers fallthrough (founder + ops@soleur.ai) — repo convention."
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf (this PR)."
error_reporting:
  destination: "Sentry (jikigai-eu/web-platform). The alarm consumes existing warning-level events from ci-deploy.sh + cloud-init.yml."
  fail_loud: "The emitters are fail-open (must never break a deploy) but WARN-level; the alarm is the fail-loud layer on their aggregate rate. The inngest-mirror Slack step is fail-open (continue-on-error) but emits ::warning:: even if Slack POST fails."
failure_modes:
  - mode: "Alarm never provisioned / darked by a tag rename in an emit site."
    detection: "sentry-zot-mirror-fallback-alert-op-contract.test.ts (CI) — a rename in ci-deploy.sh/cloud-init.yml/issue-alerts.tf breaks the build."
    alert_route: "CI red on PR."
  - mode: "Metric-alert dataset/query cannot match the level:warning/event.type:default store events → silent-no-op alarm."
    detection: "Phase-0 step 2 (probe the metric-alert dataset against a default/warning event); no event.type:error prefix."
    alert_route: "Falls back to Branch A (issue-alert + event_frequency, schema-confirmed) with an operator per-path-sensitivity note."
  - mode: "inngest mirror degrades silently (pre-#6278: annotations-only)."
    detection: "New degrade-gated Slack step in build-inngest-bootstrap-image.yml + the existing ::warning:: + step summary."
    alert_route: "Slack #releases (push notification) + GitHub Actions annotation."
logs:
  where: "Sentry event stream (alarm); GitHub Actions run logs + step summary (mirror step); host journald (logger -t ci-deploy) for the underlying pull events."
  retention: "Sentry project retention (90d default); GitHub Actions log retention (90d)."
discoverability_test:
  command: "curl -s -H \"Authorization: Bearer $SENTRY_AUTH_TOKEN\" https://jikigai-eu.sentry.io/api/0/projects/jikigai-eu/web-platform/rules/ | jq '.[] | select(.name==\"zot-mirror-fallback-rate\")'"
  expected_output: "A non-empty rule object with the >3/1h frequency condition + the three-signal filter."
```

## Architecture Decision (ADR/C4)

**No new ADR.** This plan *implements* an architectural decision already recorded in **ADR-096**
(the "Loud, no-SSH signal" axis explicitly names "the fallback-rate alarm pages at >3/1h" and marks
it "design intent, not yet provisioned"). Provisioning it realizes a stated ADR-096 Phase-5
prerequisite — it neither reverses nor extends the decision.

- **ADR annotation (optional, in-scope):** flip the ADR-096 line "The *live* fallback-rate Sentry
  alarm … is **design intent, not yet provisioned**" to "provisioned in #6278" once merged. Not a
  new `## Decision`.
- **C4 views — no impact (completeness-checked).** Read all three `.c4` files
  (`knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`). Enumerated for this
  change: (a) external human actor — none new (the operator/founder receiving the page is already
  modeled); (b) external system/vendor — Sentry is already modeled and the `supply-chain image-pull`
  relationship is already present (per ADR-082:171 → `model.c4:164-166, :240, :300`); (c)
  container/data-store — none new; (d) actor↔surface access relationship — none changes. This adds a
  Sentry *alert rule* (config within an already-modeled system), not a new actor/system/edge. "No C4
  impact" is therefore supported by the enumeration above, not an unsupported "None".

## Sharp Edges

- **Phase 0 is not optional.** The `event_frequency`-in-beta2 question is unresolved in-repo (ADR-062
  says "no verified support"); freezing a `conditions_v2 = [{ event_frequency = … }]` block without
  the schema probe risks a `terraform validate` config-phase rejection (same class as the
  #3811 import-only-schema-validation Sharp Edge). Probe first, then write the `.tf`.
- **`event_unique_user_frequency` is a trap here.** It is the ONLY proven in-repo frequency condition,
  but it counts distinct USERS; these host-emitted events have no `user` → it would count 0 and never
  page. Do not copy the `sandbox_startup_failure` condition verbatim.
- **The inngest fresh-boot signal breaks a `filter_match="all"` on feature/op.** `soleur-boot-emit
  inngest_ghcr_fallback` carries `stage` only (no feature/op). A single `all`-match rule scoped to
  feature+op silently excludes it. Use `filter_match="any"` (issue-alert) or an OR query (metric
  alert), verified against the actual emit tags in Phase 0.
- **Issue-alert `event_frequency` is per-issue-group, not aggregate.** If the three signals must page
  on a *combined* 3/1h count, an issue alert (which thresholds each fingerprinted issue independently)
  is the wrong primitive — use a `sentry_metric_alert` whose query aggregates across the OR. Decide
  the semantics in Phase 0/QA before committing to Branch A.
- **Branch B changes the resource TYPE** → THREE guard artifacts, not two: the destroy-guard
  scope-guard allowlist (`test-destroy-guard-sentry-scope-guard.sh:52`), the `-target` set, AND
  **`tests/scripts/lib/destroy-guard-filter-sentry.jq`** (a new `sentry_metric_alert` nested-clause
  summing `trigger[]`/`action[]` deltas). The jq filter is the one the plan reliably misses and is
  the load-bearing artifact — omitting it silently bypasses the nested-delete guard for the new type
  (architecture-strategist P1; #4419/#4364 bug class).
- **Metric-alert query must NOT filter `event.type:error`.** These fallback events are `store`-API
  posts with `level:warning` and no exception → `event.type:default`. An `event.type:error` prefix
  (or an `errors`-only dataset) excludes every event → a silent-no-op alarm (the worst outcome for an
  observability control). Phase-0 step 2 confirms dataset matchability before the query is frozen.
- **Issue-alert `event_frequency` is per-issue-group, not aggregate** — worsened by message-string
  fingerprinting (`ci-deploy.sh:561` `"…(web:<tag>)"` vs `"…(inngest:<tag>)"`). A distributed 2+2+1
  outage never reaches 3/group and stays silent. Prefer the metric alert; if Branch A is forced,
  surface the reduced sensitivity to the operator in the PR body.
- **The app-image fresh-boot fallback is un-emitted** (`cloud-init.yml:485-501` emits no breadcrumb on
  a successful zot→GHCR web-boot fallback). Either add the emit (Phase 1b) or the alarm does NOT cover
  the primary-container boot path — do not claim it does.
- **The repo's `event_frequency` "no verified support" comments are stale** (issue-alerts.tf:838,
  ADR-062:120). Verified present in the beta2 schema via the cached provider binary. Do not re-inherit
  the stale claim.
- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold will fail
  `deepen-plan` Phase 4.6. This section is filled (threshold: aggregate pattern).

## Test Scenarios

1. **Alarm expresses >3/1h** — `terraform plan` diff shows the condition with `value=3, interval="1h"` (or metric `threshold>3, time_window=60`).
2. **Three-signal coverage** — op-contract test asserts all three tag values pinned in `issue-alerts.tf`; `filter_match="any"` (or metric OR query) present.
3. **Rename-darks-alert guard** — mutate a tag string in `ci-deploy.sh` in a scratch branch → op-contract test fails.
4. **Scoped apply** — `terraform plan -target=…` shows 1-to-add, 0-change, 0-destroy.
5. **inngest Slack degrade path** — simulate `mirror_status=degraded` output; the new step's `if:` gate evaluates true; `actionlint` + `bash -n` clean.
6. **Post-apply existence** — Sentry-API rule-list contains `zot-mirror-fallback-rate` (AC10).
