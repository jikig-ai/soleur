---
title: "observability(infra): dead-probe heartbeat for the Inngest wrong-volume alert (treat_as_zero reads a silent probe as healthy)"
date: 2026-10-07
slug: inngest-probe-dead-probe-heartbeat
branch: feat-one-shot-8516-dead-probe-heartbeat
issue: 8516
closes: [8516]
lane: single-domain
type: chore
---

## Overview

`logtail_exploration_alert.inngest_luks_wrong_volume` (armed since the #8296 PR-2 apply, run
35605929787) evaluates a count of "wrong volume" probe rows over
`SOLEUR_INNGEST_SERVER_PROBE` emissions from `host_role=dedicated`. It runs with
`on_missing_data = "treat_as_zero"`: zero rows read as zero violations — a silent probe is
indistinguishable from a healthy one. If the hourly emission dies (dead emitter, a Vector
journald-allowlist regression, a sink outage), a silent rollback onto the plaintext backstop
`hcloud_volume.inngest_redis` goes unpaged. `scripts/followthroughs/inngest-luks-property-8296.sh`
notices the same silence as `3 CANNOT ESTABLISH` — a daily comment on a tracker issue, not a page.

This plan delivers the dead-man's-switch sibling the issue prescribes: a
`betteruptime_heartbeat` resource mirroring `betteruptime_heartbeat.workspaces_luks` ("DP-10"),
sized to the probe's hourly emission cadence, plus its Doppler URL secret — both born
`paused = true` + `ignore_changes = [paused]` exactly as DP-10 was, with the feeder and the
unpause carried by a tracked follow-up. Task 1 cites #8516 inside the wrong-volume alert's
comment so the blind spot and its remedy are co-located in the file.

## Research Insights

**Premise validation (Phase 0.6).** Every artifact the issue cites was verified on this branch:

- `logtail_exploration_alert.inngest_luks_wrong_volume` exists at
  `apps/web-platform/infra/betterstack-logs-alerts.tf:261` with `on_missing_data = "treat_as_zero"`
  and `paused = !var.inngest_luks_cutover_complete`; its exploration reads the probe rows at
  `betterstack-logs-alerts.tf:226-237` (`position(...'SOLEUR_INNGEST_SERVER_PROBE') = 1`,
  `host_role=dedicated`, missing `data_mount_devid=<luks alias>` ⇒ row counts).
- `betteruptime_heartbeat.workspaces_luks` exists at `apps/web-platform/infra/uptime-alerts.tf:475`
  — period 86400, grace 3600, `paused = true`, `lifecycle { ignore_changes = [paused] }`,
  `policy_id` gated on `var.betterstack_paid_tier`; its URL rides
  `doppler_secret.workspaces_luks_heartbeat_url` (uptime-alerts.tf:501).
- `scripts/followthroughs/inngest-luks-property-8296.sh` exists; its `3 producer_silent` arm
  fires when the newest dedicated probe row is older than 3 h — the daily, notify-only interim
  coverage the issue describes.
- The emitter is `inngest-server-probe.timer` (`OnUnitActiveSec=1h`, `AccuracySec=1min`,
  `apps/web-platform/infra/inngest-bootstrap.sh:1272-1283`) driving
  `/usr/local/bin/inngest-server-probe.sh`, which logs `SOLEUR_INNGEST_SERVER_PROBE` under
  `SYSLOG_IDENTIFIER=inngest-server-probe` through journald → Vector → Better Stack source
  2457081.
- #8296's archived parent plan (`plans/archive/20260921-231850-…-arm-wrong-volume-alert-plan.md`,
  `## Deferred Capabilities` D1) prescribes exactly this shape: "A dead-probe heartbeat for the
  wrong-volume alert … a new `betteruptime_heartbeat`".

**Mechanism vs ADR corpus.** The dead-probe/heartbeat mechanism is the repo's established one —
ADR-117 (every heartbeat needs an executable feeder declaration), ADR-222 (Better Stack object
quota bookkeeping), ADR-248/`watchdog-dispatch-table.ts` (reliable trigger for GHA-side timers).
Grep of `knowledge-base/engineering/architecture/decisions/` found no ADR rejecting a
`betteruptime_heartbeat` for this purpose; the mechanism is the affirmed pattern.

**Mechanism minimality (Phase 0.6b).** Property list and cut list:

- P1 — a reader of `betterstack-logs-alerts.tf` can trace the `treat_as_zero` blind spot to its
  remedy. Covered by: issue citation comment (task 1 of #8516, verbatim ask).
- P2 — a Better Stack dead-man's-switch exists that can page when the dedicated probe row stops
  arriving. Covered by: new `betteruptime_heartbeat` + `doppler_secret` (task 2 of #8516).
- P3 — the switch must eventually be fed and armed. Covered partially: born paused per DP-10;
  the feeder+unpause is out of this issue's stated scope and gets a tracking issue (see
  `## Deferred Capabilities`), the same delivery shape DP-10 itself used.
- CUT — a new `logtail_exploration_alert` on probe-row *presence*: rejected by the issue's own
  mechanism choice (`betteruptime_heartbeat` is prescribed); a log-derived alert shares the
  warehouse read path it would be measuring.
- CUT — host-side push inside `inngest-server-probe.sh`: `inngest-bootstrap.sh` reaches the
  dedicated host only through the baked OCI image + host replace (#6780; `cloud-init-inngest.yml`
  CF-3 note), so it cannot land in this PR regardless of coverage merit.
- CUT — extending `inngest-luks-property-8296.sh` to push the beat: it is enrolled on tracker
  #8285, which closes exactly when this alarm becomes load-bearing (backstop destruction
  2026-10-22); a feeder bound to a closing tracker silently dies with it.

**Key findings for implementation.**

- *Delivery path:* `plugins/soleur/test/terraform-target-parity.test.ts` requires every `.tf`
  resource to ride the per-merge `-target=` allow-list in
  `.github/workflows/apply-web-platform-infra.yml` (the bridge-less plan list at ~line 530-715,
  applied via the saved tfplan at ~line 1008) or sit in `OPERATOR_APPLIED_EXCLUSIONS`.
  `betteruptime_heartbeat.git_data_prd` + `doppler_secret.git_data_heartbeat_url_prd` moved to the
  per-merge `-target` list under #8754 — that is the precedent to copy, NOT the DP-10 pair's
  exclusion (the push-apply is this change's delivery path; an excluded resource would never
  leave the plan).
- *Feeder manifest:* `plugins/soleur/lib/heartbeat-manifest.ts` `MANIFEST` must carry a row for
  the new heartbeat or `heartbeat-reprovision-parity.test.ts` reds. With no feeder yet the honest
  row is `feeder: { kind: "none", url_secret: "INNGEST_SERVER_PROBE_HEARTBEAT_URL",
  tracking_issue: <N> }` + `arming_pending: { tracking_issue: <N> }`; the parity test then asserts
  nothing dereferences `$INNGEST_SERVER_PROBE_HEARTBEAT_URL` — true today.
- *Born paused is load-bearing:* `inngest_prd`'s comment (inngest.tf:325-348) records why —
  Better Stack starts expecting pings at creation, so an unfed unpaused heartbeat pages falsely.
  `paused = true` + `ignore_changes = [paused]` is verbatim DP-10.
- *Naming/`team_name`:* `"Your team"` is the literal workplace team (case-sensitive provider
  lookup — inngest.tf:333-337). `policy_id` uses `betteruptime_policy.uptime[0].id` under
  `var.betterstack_paid_tier`, mirroring workspaces_luks.
- *C4 model already names this gap:* `model.c4`'s `inngestRedis` description ends
  "(a probe pipeline that goes silent reads as healthy to the alert; #8516)" — freshened in
  `## Architecture Decision (ADR/C4)` below.
- *Comment drift noticed:* uptime-alerts.tf:23-24 points at "inngest.tf:108-138" for the inngest
  heartbeat/policy; the resources moved (heartbeat now ~inngest.tf:325, policy ~355). Low value;
  cq-cite-content-anchor-not-line-number is the write-side convention, so this diff does not add
  another line-number citation to chase. Leave as-is.
- *Test discovery:* `apps/web-platform/infra/**/*.test.sh` is presence-registered
  (`scripts/test-all.sh` ~line 5353 comment + infra-validation.yml glob) — a new test file needs
  no registration line.
- *Learnings consulted:* ADR-117 (feeder must be executable, not prose);
  the #7587-era lesson that a guard must be drivable RED (mutation matrix required for the new
  assertion suite); the #6416/#5566 apply-allow-list lineage (a resource neither targeted nor
  excluded is the silent-un-applied defect class).
- *Code-review overlap (Phase 1.7.5):* `gh issue list --label code-review --state open` bodies
  contain none of the four touched paths — `## Open Code-Review Overlap` records `None`.
- *External research:* skipped — the shape authority, delivery path, and guard contract are all
  in-repo (Phase 1.6 "strong local context").
- *Community discovery / functional overlap:* not applicable — no new user stack or feature; the
  overlap surface is the heartbeat census enumerated above.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the failure shapes are a
  page that never comes (the pre-existing state today) or a false dead-probe page to ops@ (born
  `paused = true` forecloses that: a paused heartbeat ignores absent beats, so the worst case is
  inert, not noisy).
- **If this leaks, the user's [data / workflow / money] is exposed via:** the heartbeat URL is a
  bearer ping endpoint (`visibility = "masked"` in Doppler; the URL lands in `terraform.tfstate`
  like every sibling heartbeat URL — same disclosed surface as
  `doppler_secret.inngest_heartbeat_url_prd`). A leaked URL can only inject *beats*, suppressing
  a real dead-probe alarm — a denial-of-alarm, not a data exposure.
- **Brand-survival threshold:** none — internal observability plumbing; no customer data or
  customer-visible surface changes.
- scope-out: `threshold: none, reason: alerting-only resources; no data store, auth path, or
  customer surface is created or modified — the sensitive-path contact is the infra .tf file
  itself, which the apply allow-list machinery already gates`

## Files to Edit

- `apps/web-platform/infra/betterstack-logs-alerts.tf` — extend the comment block above
  `resource "logtail_exploration_alert" "inngest_luks_wrong_volume"` (~line 261) citing #8516:
  `treat_as_zero` reads a silent probe as healthy, and `betteruptime_heartbeat.inngest_server_probe`
  is the dead-probe sibling that carries the absence-of-signal case.
- `apps/web-platform/infra/uptime-alerts.tf` — append the
  `betteruptime_heartbeat.inngest_server_probe` resource (name `soleur-inngest-server-probe-prd`,
  `period = 3600`, `grace = 1800`, `email = true`, `call/sms/push = false`, `team_wait = 0`,
  `team_name = "Your team"`, `policy_id = var.betterstack_paid_tier ? betteruptime_policy.uptime[0].id
  : null`, `paused = true`, `lifecycle { ignore_changes = [paused] }`) and
  `doppler_secret.inngest_server_probe_heartbeat_url` (`project = "soleur"`, `config = "prd"`,
  `name = "INNGEST_SERVER_PROBE_HEARTBEAT_URL"`, `value = betteruptime_heartbeat.inngest_server_probe.url`,
  `visibility = "masked"`, `lifecycle { ignore_changes = [value] }`), beside the DP-10 pair with
  the same comment anatomy (#8516 + why paused + the deferred feeder).
- `.github/workflows/apply-web-platform-infra.yml` — append
  `-target=betteruptime_heartbeat.inngest_server_probe \` and
  `-target=doppler_secret.inngest_server_probe_heartbeat_url \` to the bridge-less allow-list
  (with the other `betteruptime_heartbeat`/`doppler_secret` inngest entries, ~line 667-672).
- `plugins/soleur/lib/heartbeat-manifest.ts` — new `MANIFEST` row:
  `name: "inngest_server_probe"`, `arming: "external-probe"`, `paused: true`,
  `feeder: { kind: "none", url_secret: "INNGEST_SERVER_PROBE_HEARTBEAT_URL",
  tracking_issue: <tracking issue #> }`, `arming_pending: { tracking_issue: <tracking issue #> }`,
  `exempt_reason` explaining the external (repo-side) feeder class — arming this heartbeat never
  requires `hcloud_server.inngest` reprovision, so ADR-103's `replace_target` does not fire.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — freshen the `inngestRedis`
  description's #8516 clause to reflect the post-merge state (dead-probe heartbeat exists, born
  paused, feeder tracked by the new issue).

## Files to Create

- `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` — assertion suite over the
  static shape (see Guard Contract): resource presence, `period = 3600` / `grace = 1800`,
  `paused = true` + `ignore_changes = [paused]`, policy gating, the doppler_secret wiring, the
  #8516 citation in betterstack-logs-alerts.tf, and both `-target=` lines in
  apply-web-platform-infra.yml. Presence-registered (infra glob) — no test-all.sh edit.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "cite this issue inside `logtail_exploration_alert.inngest_luks_wrong_volume` in `apps/web-platform/infra/betterstack-logs-alerts.tf`, in the next PR that edits that file for its own reason" [issue #8516] | Files-to-Edit #1; AC-1 | mapped |
| 2 | "Add a dead-probe heartbeat sibling alert. The shape authority is `betteruptime_heartbeat.workspaces_luks` (\"DP-10\") in `uptime-alerts.tf`." [issue #8516] | Files-to-Edit #2 (heartbeat + URL secret); AC-2–AC-4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `-target=` lines in apply-web-platform-infra.yml | "mirror that pattern for the `SOLEUR_INNGEST_SERVER_PROBE` emission cadence" (a mirrored resource that is never applied is not added) + asks 1–2 | inferred — justification: `terraform-target-parity.test.ts` reds on any `.tf` resource that is neither in the per-merge `-target` allow-list nor `OPERATOR_APPLIED_EXCLUSIONS`; #8754 is the heartbeat precedent for the target list |
| `heartbeat-manifest.ts` row | asks 1–2 | inferred — justification: ADR-117/`heartbeat-reprovision-parity.test.ts` fails discovered⊆manifest without a row; `kind:"none"` + `tracking_issue` is the manifest's own honest-unfed idiom |
| `inngest-server-probe-heartbeat.test.sh` | — | inferred — justification: `cq-write-failing-tests-before` + the DP-10 assertion precedent in `luks-monitor.test.sh:147` (`have 'resource "betteruptime_heartbeat" "workspaces_luks"'`); a new resource with no pinning assertion is unguarded |
| `model.c4` freshening | — | inferred — justification: plan Phase 2.10's C4 mandate requires correcting a description this change falsifies; `inngestRedis` already names #8516 as an open gap |
| tracking issue for the feeder + unpause | — | inferred — justification: `wg-when-deferring-a-capability-create-a`; the manifest row refuses a `kind:"none"` feeder without a `tracking_issue` |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform` (infra + KB diagram), `plugins/soleur` (manifest lib), `.github` (apply workflow)
- Planned files: 6 (5 edited + 1 created) | Estimated changed lines: ~140
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change: one vendor alerting object
and its URL secret, a manifest row, a wiring comment, an assertion suite, and a one-clause C4
description freshen. No customer-facing, legal, marketing, finance, sales, or support surface.
The infra specifics (apply routing, feeder honesty, quota note) are covered by the mechanical
gates listed in Research Insights rather than a domain fan-out.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/uptime-alerts.tf` (existing `apps/web-platform/infra` root — reuses
  the declared `betteruptime` + `doppler` providers; no new root, no new provider, no new
  variable): `betteruptime_heartbeat.inngest_server_probe` +
  `doppler_secret.inngest_server_probe_heartbeat_url` as specified in `## Files to Edit`.
- `apps/web-platform/infra/betterstack-logs-alerts.tf`: comment-only change inside the
  `inngest_luks_wrong_volume` block citing #8516.
- Sensitive variable list: none new. The heartbeat URL is written to
  `doppler_secret.inngest_server_probe_heartbeat_url` (`visibility = "masked"`) — a bearer ping
  endpoint; it also lands in `terraform.tfstate` like every sibling heartbeat URL (accepted,
  pre-existing disclosure class).

### Apply path

**The merged-PR push-apply** (`apply-web-platform-infra.yml` allow-list `-target` plan + saved-
tfplan apply) delivers both resources — the #8754 precedent (`betteruptime_heartbeat.git_data_prd`
pair ride the per-merge list), deliberately NOT the DP-10 pair's `OPERATOR_APPLIED_EXCLUSIONS`
route, which would leave the heartbeat uncreated until a manual untargeted apply outside CI.

**Blast-radius callout (required by the issue):** ANY edit under `apps/web-platform/infra/**`
fires the merge-triggered push-apply, which plans/applies the ENTIRE drifted allow-list, not just
this diff's resources — #8296 PR-1's apply carried two unrelated drift actions, which is why #8516
was deferred out of that PR. This plan adds two lines to that list; the merge's apply will also
process whatever drift the allow-list has accumulated. Expected actions from this diff itself:
`Create` on the heartbeat and the doppler secret — nothing else is planned or destroyed by these
edits. Postmerge reads the apply run on the merge SHA and reports what it did (drift included),
not just whether it went green.

Downtime: none — alerting-control-plane resources only; no host, volume, network, or DNS object is
touched. Blast radius inside Better Stack: a new paused heartbeat object + one masked secret;
the object is `paused = true`, so it cannot false-page on arrival.

### Distinctness / drift safeguards

- `lifecycle { ignore_changes = [paused] }` on the heartbeat — a later unpause done through the
  Better Stack UI/arm path (the follow-up's arming step) must not be reverted by subsequent
  applies; mirrors every sibling heartbeat.
- `lifecycle { ignore_changes = [value] }` on the secret — the URL is stable per resource
  lifetime; mirrors `doppler_secret.inngest_heartbeat_url_prd`.
- Single-config write (`soleur`/`prd`), same sink `inngest_heartbeat_url_prd` uses — no
  dev/prd distinctness issue (there is no dev heartbeat fleet).
- `paused = true` in source is the LOWER BOUND convention (`ignore_changes` decouples live state);
  the nightly live-reconcile tolerates it via `arming_pending`.

### Vendor-tier reality check

`policy_id` is gated on `var.betterstack_paid_tier` (null on the free tier — mirrors DP-10; the
provider rejects `betteruptime_policy` linkage on free tier). The heartbeat itself is a free-tier
object; the unresolved object-quota cap is the standing note at uptime-alerts.tf:60-61 — read the
`SOLEUR_HEARTBEAT_RECONCILE_INVENTORY` line (nightly reconcile output) before assuming headroom.
No `betteruptime_policy` resource is added by this change.

## Observability

```yaml
liveness_signal:
  what: "betteruptime_heartbeat.inngest_server_probe — a dead-man's-switch that pages when no beat arrives within period+grace (5400 s); beats certify that a fresh host_role=dedicated SOLEUR_INNGEST_SERVER_PROBE row is arriving at Better Stack"
  cadence: "designed for the probe's hourly emission (inngest-server-probe.timer, OnUnitActiveSec=1h); born paused — beats begin when the tracked feeder lands"
  alert_target: "Better Stack email (ops@ via team_name \"Your team\"); betteruptime_policy.uptime when var.betterstack_paid_tier"
  configured_in: "apps/web-platform/infra/uptime-alerts.tf (heartbeat + doppler_secret) + plugins/soleur/lib/heartbeat-manifest.ts (feeder/arming declaration)"
error_reporting:
  destination: "Better Stack heartbeat email; the feeder follow-up carries the beat emission"
  fail_loud: "a withheld beat is the alarm itself (dead-man's-switch); until armed, the nightly SOLEUR_HEARTBEAT_RECONCILE_* markers cover declared-vs-live drift"
failure_modes:
  - mode: "probe emitter dead / Vector allowlist regression / sink outage (rows stop arriving)"
    detection: "feeder withholds beats (it pushes only on a verified fresh row) — heartbeat pages after period+grace once armed"
    alert_route: "betteruptime_heartbeat.inngest_server_probe → email/policy"
  - mode: "heartbeat created but feeder never wired (inert monitor)"
    detection: "manifest feeder.kind=\"none\" + tracking_issue (CI-enforced honesty); arming_pending row keeps live-reconcile quiet only inside the deferred window"
    alert_route: "tracking issue + SOLEUR_HEARTBEAT_RECONCILE_MISMATCH absent-live if the apply never lands it"
  - mode: "this diff never applies"
    detection: "SOLEUR_HEARTBEAT_RECONCILE_MISMATCH reason=absent-live on the next nightly reconcile"
    alert_route: "nightly reconcile issue/marker"
logs:
  where: "apply output in the apply-web-platform-infra.yml run; nightly reconcile markers in its workflow log"
  retention: "GHA run retention (repo default)"
discoverability_test:
  command: "grep -c 'resource \"betteruptime_heartbeat\" \"inngest_server_probe\"' apps/web-platform/infra/uptime-alerts.tf"
  expected_output: "1"
```

## Encryption Posture

```yaml
at_rest:
  mechanism: "no new persistent store — a vendor monitor object plus one masked Doppler secret (the URL lands in the encrypted-at-rest R2 tfstate like every sibling betteruptime_heartbeat URL; see zot/git-data/inngest precedents)"
  evidence: "uptime-alerts.tf resources; no volume/bucket/table introduced"
  defends_against: "the monitor object's persisted state at the vendor is its config only (name/period/paused) — Better Stack's own store holds it; no payload data persists anywhere new"
  does_not_defend: "heartbeat URL is a bearer ping secret in tfstate + Doppler prd (masked); leakage enables beat forgery (alarm suppression), not data read"
  disclosed_as: "existing heartbeat-URL disclosure class — same as doppler_secret.inngest_heartbeat_url_prd"
  live_verification: "grep of uptime-alerts.tf shows no store resource; terraform plan's resource_changes are Create-only on the two new addresses"
in_transit:
  tls: "eventual beats travel HTTPS to the Better Stack heartbeat endpoint (uptime.betterstack.com); the doppler write rides the provider's TLS API"
  cert_verification: "on (provider default; nothing disables it)"
  does_not_defend: "a beat proves the verifier ran — it carries no probe payload; the measured signal itself is the Better Stack log row, which is already inside Better Stack"
  disclosed_as: "same vendor heartbeat-push path every sibling heartbeat uses (inngest_prd, git_data_prd, workspaces_luks)"
# no exception block — no plaintext mechanism and no cert_verification: off row
```

## Guard Contract

### Guard 1 — `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` (static shape suite)

**Property.** The dead-probe heartbeat exists with the DP-10-mirrored shape (paused birth,
hourly-cadence budget, policy gating, URL secret), the wrong-volume alert cites #8516, and both
resources ride the per-merge apply `-target` list.

**Assembly.** Chokepoints the suite greps: the resource block in `uptime-alerts.tf` (one
`resource "betteruptime_heartbeat" "inngest_server_probe"` block), the paired
`doppler_secret.inngest_server_probe_heartbeat_url` block, the `inngest_luks_wrong_volume` alert's
comment region in `betterstack-logs-alerts.tf`, the `-target=` allow-list region of
`apply-web-platform-infra.yml`, and the `MANIFEST` row in `heartbeat-manifest.ts`. Every read is
an anchored `grep`/`awk` over the named file — membership is structural (block-bounded extraction,
not bare-name presence).

**Mutation matrix.**

| # | Edit under test | Must drive the guard |
|---|-----------------|----------------------|
| M1 | delete the `betteruptime_heartbeat.inngest_server_probe` block | RED — resource presence |
| M2 | change `grace` to `180` (tighten the budget) | RED — pinned budget |
| M3 | drop `paused = true` (or flip to `false`) | RED — born-paused invariant |
| M4 | remove `ignore_changes = [paused]` from the lifecycle block | RED — unpause-revert protection |
| M5 | repoint `doppler_secret` `value` to `betteruptime_heartbeat.inngest_prd.url` | RED — URL identity |
| M6 | drop the `-target=betteruptime_heartbeat.inngest_server_probe` line from the workflow | RED — apply-allow-list wiring |
| M7 | remove the `#8516` citation from the wrong-volume alert's comment | RED — traceability |
| M8 | delete the `MANIFEST` row for `inngest_server_probe` | RED — manifest membership (this test) |

**Harness rows.** (a) Suite mutation: a doctored run that swallows `no()` output fails its own
totals — the harness counts failures and exits non-zero if any assertion is unverifiable. (b)
Must-PASS non-canonical input: the suite must pass when `#8516` is cited on a different comment
line inside the same block (position-free citation), i.e. the assertion greps the block, not a
pinned line number. (c) Must-PASS: whitespace-insensitive attribute matching (`paused = true` vs
`paused=true`).

**Anchor.** The asserted values (`3600`, `1800`, the resource names, the `-target` addresses) are
restatements of THIS plan's contract; a diff weakening both the .tf and the suite in one commit is
caught by `terraform-target-parity.test.ts` and `heartbeat-reprovision-parity.test.ts`, which
independently enumerate the resource set — the suite is not the sole census.

## Architecture Decision (ADR/C4)

### ADR

None. The change rides every existing decision (ADR-117 feeder honesty, ADR-222 Better Stack
quota bookkeeping, ADR-103/ADR-096 apply routing); it introduces no new substrate, boundary, or
trust relationship. Reversal check: no ADR's rejected-alternative table is re-entered — the
`betteruptime_heartbeat` dead-man's-switch is the corpus's affirmed mechanism.

### C4 views

Detection enumeration (the completeness rubric): (a) external human actors — none new
(ops@ email recipient is already a Better Stack fact, not an actor edge); (b) external
systems/vendors — Better Stack is already modeled (`betterstack` element + the
betterstack→slack→founder wake path in `views.c4`); (c) containers/data stores — none new;
(d) actor↔surface relationships — none change.

One description DOES go stale: `model.c4`'s `inngestRedis` description ends "(a probe pipeline
that goes silent reads as healthy to the alert; #8516)". Task: update that clause to name the
remedy's armed lifecycle — the heartbeat exists born-paused with the feeder tracked — so the
model stops describing #8516 as a fully-open gap once it merges. Validation: the C4 suites
(`apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`) stay green.

### Sequencing

n/a — no decision whose truth is deferred.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (2026-10-07) bodies contain none of the
files this plan touches (`betterstack-logs-alerts.tf`, `uptime-alerts.tf`,
`apply-web-platform-infra.yml`, `heartbeat-manifest.ts`).

## Deferred Capabilities

| # | Deferred | Tracking | Re-evaluation trigger |
|---|----------|----------|------------------------|
| D-A | The heartbeat's FEEDER + arming: a pusher that beats only when a fresh `host_role=dedicated` `SOLEUR_INNGEST_SERVER_PROBE` row is confirmed in the warehouse (covers emitter + Vector-allowlist + sink failures — a host-side push cannot see the latter two and needs an OCI re-bake + `inngest-host-replace`, #6780), then unpause after an observed beat. Candidate: a repo-side verifier on a reliable trigger (watchdog-dispatch-table per ADR-248, or the daily sweeper if period/grace are re-sized). Beats must arrive at least every `period+grace` (5400 s) | new issue filed in this pipeline; `heartbeat-manifest.ts` `tracking_issue`/`arming_pending` carry its number | **2026-10-22** — the issue's own re-evaluation date; after the backstop is destroyed under #8285 this monitor is the only dead-probe tripwire |

## Acceptance Criteria

- [ ] AC-1: `apps/web-platform/infra/betterstack-logs-alerts.tf` cites `#8516` inside the comment
  block of `resource "logtail_exploration_alert" "inngest_luks_wrong_volume"` and names the
  `treat_as_zero` blind spot plus the heartbeat sibling that covers it.
- [ ] AC-2: `uptime-alerts.tf` declares `resource "betteruptime_heartbeat" "inngest_server_probe"`
  with `name = "soleur-inngest-server-probe-prd"`, `period = 3600`, `grace = 1800`,
  `paused = true`, `lifecycle { ignore_changes = [paused] }`, `email = true`, and
  `policy_id = var.betterstack_paid_tier ? betteruptime_policy.uptime[0].id : null`.
- [ ] AC-3: `uptime-alerts.tf` declares `doppler_secret.inngest_server_probe_heartbeat_url`
  (`project = "soleur"`, `config = "prd"`, `name = "INNGEST_SERVER_PROBE_HEARTBEAT_URL"`,
  `value = betteruptime_heartbeat.inngest_server_probe.url`, `visibility = "masked"`,
  `lifecycle { ignore_changes = [value] }`).
- [ ] AC-4: `apply-web-platform-infra.yml`'s bridge-less allow-list carries
  `-target=betteruptime_heartbeat.inngest_server_probe` and
  `-target=doppler_secret.inngest_server_probe_heartbeat_url`; neither address is added to
  `OPERATOR_APPLIED_EXCLUSIONS`.
- [ ] AC-5: `plugins/soleur/lib/heartbeat-manifest.ts` carries a MANIFEST row for
  `inngest_server_probe` with `feeder.kind = "none"`,
  `url_secret = "INNGEST_SERVER_PROBE_HEARTBEAT_URL"`, a positive `tracking_issue`, and
  `arming_pending` naming the same issue.
- [ ] AC-6: the tracking issue for the feeder + arming exists on GitHub, carries a
  `follow-through`-appropriate body (candidate feeder shapes, the 5400 s beat budget, the
  2026-10-22 re-evaluation date), and is named in the manifest row.
- [ ] AC-7: `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` exists and passes;
  it must be drivable RED by at least the Guard-1 mutation matrix.
- [ ] AC-8: `terraform fmt -check -recursive` clean over `apps/web-platform/infra/`;
  `heartbeat-reprovision-parity.test.ts`, `terraform-target-parity.test.ts`, and
  `heartbeat-live-reconcile.test.ts` stay green.
- [ ] AC-9: `model.c4`'s `inngestRedis` description no longer reads #8516 as an open gap; the C4
  test suite stays green.
- [ ] AC-10: PR body carries `Closes #8516` on its own line.

## Test Scenarios

1. `bash apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` — green on the finished
   tree; drove red before implementation (TDD).
2. `bun test plugins/soleur/test/heartbeat-reprovision-parity.test.ts` — manifest row resolves;
   `kind:"none"` unfed probes stay unmatched (nothing dereferences
   `$INNGEST_SERVER_PROBE_HEARTBEAT_URL` in-repo).
3. `bun test plugins/soleur/test/terraform-target-parity.test.ts` — both new addresses are
   covered by the `-target` union; no exclusion-set entry needed.
4. `cd apps/web-platform/infra && terraform fmt -check -recursive` and `terraform validate`
   (validation where provider init permits) — clean.
5. Postmerge: read the `apply-web-platform-infra.yml` run on the merge SHA — the plan shows
   exactly `+2` create actions for the new addresses (plus any pre-existing drift, which is
   reported verbatim in the postmerge note, not silently absorbed); the heartbeat exists in
   Better Stack paused; the nightly reconcile sees no `absent-live` for it.

## Sharp Edges

- A `paused = true` heartbeat with `ignore_changes` is deliberately inert until armed — do not
  "fix" the paused state in this PR; arming follows an observed beat (the #6210 discipline:
  verify a real ping lands BEFORE unpausing).
- The `-target=` list is inside a backslash-continued shell block — comments are forbidden inside
  it (`#` makes the next line a command name, SC2215); append bare lines only.
- `team_name = "Your team"` is a literal, not a placeholder — the provider's case-sensitive
  lookup rejects other spellings (inngest.tf:333-337).
- The per-merge apply replans the whole allow-list, including drifted siblings — the run's plan
  output is evidence, not noise; postmerge reports it.
- `ignore_changes` on `paused` means `terraform apply` will not create the resource as unpaused
  even if a later plan flips intent — the live pause state is the real one.
- The plan's `## Observability.discoverability_test` command is executed by preflight Check 10
  in a sandbox — keep it the grep shown (first token allowlisted, <15 s).
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting
  deepen-plan or `soleur:work`.

## Risks

- **R1 — drifted-allowlist apply carries unrelated actions.** Mitigation: the two new addresses
  are the only diff-attributable changes; postmerge reads the plan/apply output and reports drift
  verbatim (the issue's own blast-radius note, operationalized).
- **R2 — inert monitor (born paused, no feeder).** This is the prescribed DP-10 shape, and the
  honesty machinery makes it loud: manifest `kind:"none"` + `tracking_issue`, `arming_pending`,
  and the tracking issue's 2026-10-22 trigger. The gap is *documented-open*, never silently so.
- **R3 — merge race with open infra PRs (#9348 held-draft, #9529 WIP, both touch
  `betterstack-logs-alerts.tf`).** Same-file edits conflict textually only if they touch the
  `inngest_luks_wrong_volume` block — our edit is a comment block beside the resource; rebase if
  one lands first.
- **R4 — free-tier object quota.** Standing quota note honored (uptime-alerts.tf:60-61); a
  single heartbeat object is within the pattern of past additions, and the reconcile inventory
  line is the measurement surface.

## Enhancement Summary

Deepen-plan gates run inline (headless pipeline; no Task subagent surface in this harness —
panels that would fan out were executed as inline checks and the limitation is disclosed in
session-state.md):

- Phase 4.6 User-Brand Impact halt — PASS (section present, `threshold: none` + scope-out
  bullet for the sensitive-path contact `apps/*/infra/` + `apply-web-platform-infra.yml`).
- Phase 4.7 Observability gate — PASS (5-field schema; `discoverability_test.command` = `grep`,
  allowlisted first token, <15 s, literal `expected_output` `1`).
- Phase 4.10 Encryption Posture halt — PASS (`.tf` trigger fired; `at_rest`/`in_transit`
  complete; no exception needed).
- Phase 4.11 Guard Contract halt — PASS (`python3 scripts/lint-guard-contract.py` rc=0;
  1 guard entry, 8-row mutation matrix, harness rows).
- Phase 4.12 Scope Check halt — PASS (2/2 asks mapped; 5 inferred items each carry a named
  enforcement contract as justification; single-PR recommendation).
- Phase 4.4 precedent-diff — satisfied: DP-10 (`betteruptime_heartbeat.workspaces_luks`,
  uptime-alerts.tf:475-510) is the named precedent and the Files-to-Edit spec is a side-by-side
  mirror; no new scheduled job (trigger check not fired).
- Phase 4.45 verify-the-negative — confirmed: (a) zero in-repo dereferences of
  `$INNGEST_SERVER_PROBE_HEARTBEAT_URL` (grep, 2026-10-07); (b) `var.betterstack_paid_tier`
  exists (variables.tf:653); (c) `betteruptime` + `doppler` providers declared (main.tf:37-94).
- Phase 4.5 / 4.55 — not triggered (no SSH/provisioner resource, no downtime-class operation;
  the resources are vendor-API objects delivered by the existing merge-triggered apply).
- plan-review standing check — no AC depends on ambient/concurrent state; all are deterministic
  file-content or workflow-output assertions.

### Key decision surfaced (see decision-challenges.md)

The heartbeat ships born-paused and UNFED (manifest `kind: "none"` + `arming_pending`), with the
feeder + unpause tracked by a follow-up issue — the literal DP-10 delivery shape the issue
prescribes. The alternative (building the external verifier + dispatch-clock wiring in this PR)
crosses into a second TF root (sentry cron-monitors) and triples the file surface; recorded as a
taste-class decision for the ship-phase render.
