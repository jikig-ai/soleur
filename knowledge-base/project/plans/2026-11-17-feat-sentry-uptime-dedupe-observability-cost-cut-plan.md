---
title: "feat: cut Sentry + Better Stack observability spend: one Sentry uptime slot for the app, marketing uptime on Better Stack, host-kernel paging routed to Sentry"
date: 2026-11-17
slug: feat-sentry-uptime-dedupe-observability-cost-cut
branch: feat-sentry-cost-consolidation
pr: 12844
issue: 6606
closes: 6606
type: enhancement
priority: p3-low
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# Cut Sentry + Better Stack observability spend (technical cuts only)

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Addendum - 2026-11-17 (D2 second re-ruling, CI run 44095436160)

The import of 1422253 described below is **superseded**. `plan_pr` failed
`scripts/sentry-adoption-plan-assert.sh`, which runs unconditionally in `plan_pr` and the apply job
and reads any import or forget row as the #7650 alert adoption; no import and no `removed {}` can
pass it. The CTO re-ruled (decision-challenges D2): `sentry_uptime_monitor.app` is declared as a
new monitor, and 1422253 is deleted through the API (GET, DELETE, GET expecting 404, D3a). The
delete runs immediately before the merge, because the post-apply fidelity probe runs under `set -e`
and fails on any live non-manual uptime monitor. Better Stack pages for the app in the minutes
between the delete and the apply. The import text in the sections below is kept as the record of
the first ruling; the amended steps are Phase 7 steps 0, 2 and 4 and AC1, AC3 and AC11, plus (at
review, 2026-11-17) User-Brand Impact, the Observability block, Phase 6, the Test Scenarios plan
verify, and the vendor-split slot count. Any other line that says the monitor is imported, that a
first apply flips it from mode 3 to 1, or that a delete happens only on a fallback describes the
superseded ruling and is not an instruction.

## Enhancement Summary

**Deepened on:** 2026-11-17
**Sections enhanced:** 7 (Research Insights, Phases 1, 4, 7, Observability, Guard Contract,
Dependencies & Risks)
**Agents used:** soleur:engineering:infra:terraform-architect,
soleur:engineering:review:observability-coverage-reviewer; plus mechanical gate checks (guard
contract lint, scope-check count, discoverability tokenizer, rule-id, label, issue-state and ADR
ordinal probes on fresh `origin/main`).

### Key Improvements

1. The import would have planned a replace: `project` is never read back by provider 0.15.7, so
   `sentry_uptime_monitor.app` carries `lifecycle { ignore_changes = [project] }` (verified in
   the provider source and its own import test).
2. The uptime check now routes through the fidelity script's existing `_finding`/FAILED path,
   runs before any rule-side exit, writes its own `uptime_verdict` output that gates the
   unavailable filer and both closers, and is pinned off fixture mode at both call sites.
3. Every failure mode names its layer; a paused-changelog-monitor mode was added; public issue
   output strips URL userinfo and query.
4. HCL shown multi-line (one-line `import`/`removed` with two arguments does not parse); the
   fallback commit carries `[ack-destroy]` because a `forget` counts as a destroy.

### New Considerations Discovered

- `eu.sentry.io`, `de.sentry.io` and `jikigai-eu.sentry.io` all answered the detector read with
  200 today; the plan keeps the pinned org subdomain because the script refuses any other host.
- The discoverability `expected_output` is a whitespace-free token (`uptime_verdict=clean`),
  because Check 10 rejects an all-whitespace-token literal.

## Overview

Sentry bills each uptime monitor beyond the one included at $1.00/mo. Live Sentry has five,
so four are billed. Better Stack includes ten uptime monitors and uses seven. This plan:

- brings Sentry down to exactly one uptime monitor ($0);
- moves the one marketing check worth keeping into a free Better Stack slot;
- records where the four paused host-kernel heartbeats will page from, so arming them does
  not buy a second Better Stack heartbeat pack.

The plan differs from the brief in which monitor keeps the free Sentry slot. The brief said
keep the ACME probe and delete the auto-detected app.soleur.ai monitor. The CTO ruled the
other way (decision-challenges D1, D1a, D1b). The ACME probe always passes since the
Cloudflare Pages cutover. The app monitor is Sentry's only watch on the production app, and
an operator ruling on 2026-07-17 (DC-1, #6606) kept the app on two vendors. Sentry uptime
spend is $0 either way.

The auto-detected monitor (id 1422253) is **adopted into Terraform by `import`**, not deleted
and replaced (D2, re-ruled after plan review). The provider's update call sends
`mode = MANUAL` to Sentry's detectors API, which flips an auto-detected monitor to manual. So
after the first apply there is no auto-detected monitor left, and #6606 (import the unmanaged
monitor) closes as written. Deleting and re-creating it is the fallback, used only if the
flip fails.

Savings, stated honestly (CFO review):

- Sentry uptime: $4.00/mo PAYG becomes $0. That is the whole direct saving of this PR.
- The current billing period (2026-11-17 to 2026-12-16) already shows $4.00 of uptime
  accrued. Whether removal refunds it is unverified, so the 2026-12-16 invoice is $50.06 to
  $55.06 (the top end if the new app monitor bills as a sixth uptime monitor this period;
  widened 2026-11-17 at review). From the following period the steady state is $50.06/mo ($29 base + 27 billable
  cron seats x $0.78).
- Host-kernel routing: arming on Sentry costs $3.12/mo, against $20/mo for a second Better
  Stack pack. That is $16.88/mo avoided, realized in the #12386 arming PR, not here.
- The 2026-11-17 invoice ($84.48) is billing lag from the 2026-10-29 prune, not a live figure.

## Research Reconciliation: Brief vs. Codebase

| Brief claim | Reality (measured 2026-11-17) | Plan response |
|---|---|---|
| Keep `soleur_acme_probe` as Sentry's included monitor | Its own `description` in `uptime-monitors.tf` says it is VACUOUS after the ADR-194 cutover: Cloudflare Pages serves its own 404.html whatever Rule 10 does. Live headers show no `x-github-request-id`, so the cutover has happened (#7640 closed) | Drop it (D1b). The lost property stays tracked on #7799; a comment there says so |
| Delete the auto-detected "Uptime Monitoring for https://app.soleur.ai" because Better Stack duplicates it | It is the only Sentry uptime monitor on the production app. #6606 and DC-1 record an operator ruling (2026-07-17): do not delete, keep two vendors | Adopt it into Terraform by `import`; the first apply flips it to manual (D1a, D2) |
| Disable org-level auto-detection through the API or IaC | No public field. `PUT /organizations/{org}/` has no uptime option and the provider has no resource. Sentry's own code sets `sentry:uptime_autodetection` to False after it creates the first auto monitor and allows one per org. The docs say deleted auto monitors are not re-created. `GET /organizations/jikigai-eu/` shows no uptime key for either token | No setting write (D3). The import removes the one auto monitor; a scheduled check reports any `mode != 1` monitor or a live count above the declared count |
| Sentry uptime = 5 monitors, reserved 1 | `GET /customers/jikigai-eu/`: uptime usage 5, reserved 1, $4.00 accrued; monitorSeats usage 28, reserved 1, $21.06 accrued; period ends 2026-12-16 | Matches. Projection stated as a range (see Overview) |
| 28 active cron monitors, 27 billable | 28 `sentry_cron_monitor` blocks in `cron-monitors.tf`, 28 live | Matches. The 2026-10-29 projection of 23-24 billable predates later monitor additions (#12293, #12331 and others) |
| Better Stack: 7 monitors, 21 heartbeats, 17 active, 4 paused host-kernel | Live GET confirms all of it. 7 `betteruptime_monitor` blocks in `uptime-alerts.tf` | Matches |
| The 4 paused heartbeats could move to Sentry if the emitter supports a check-in | The emitter is `scripts/deadman-heartbeat-feeder.sh`, run hourly by `scheduled-deadman-heartbeat-feeder.yml`, which already posts a Sentry check-in through `./.github/actions/sentry-heartbeat` | Route to 4 per-host Sentry cron monitors, built in the #12386 arming PR (D4) |

## Research Insights

**Premise Validation.** Checked: draft PR #12844 open; #6606 open (the import ask this plan
now closes as written); #12386 open (arming); #12007 closed; #7640 closed (cutover done);
#7799 open (ADR-194 deferred cleanup); #12827 open (Responder 2->1, out of scope); #6590,
#6591, #7577, #4296 open and not touched. The brief's premise that the app monitor duplicates
Better Stack was explicitly rejected by the 2026-07-17 operator ruling. The brief's premise that
the ACME probe still guards something is contradicted by the probe's own description. Both are
handled as User-Challenges in `decision-challenges.md`. The live counts in the brief all held.

**Property List.**

1. P1: Sentry uptime usage equals the one included monitor, so uptime PAYG is $0.
2. P2: the production app stays watched by two vendors. Better Stack pages; Sentry detects
   (opens an issue) as a second source and does not page (D-F-E).
3. P3: every marketing-site property Sentry watched today is either watched by Better Stack
   or recorded as dropped with a reason.
4. P4: an auto-detected or hand-made Sentry uptime monitor cannot come back silently.
5. P5: arming the host-kernel heartbeats does not buy a second Better Stack pack.
6. P6: the expense ledger and cost model state the live counts and the projected invoice.

**Cut List.**

- Org-level auto-detection write -> P4 -> cut. No public field exists, a guessed key cannot be
  read back, and Sentry already turns the option off after its first auto monitor.
- Terraform management of the auto-detection setting -> P4 -> cut. The provider has no resource.
- A new declared monitor plus a scripted delete of 1422253 -> P2 -> cut to fallback only. The
  import adopts the same monitor with no overlap window, no 6-monitor billing peak and no
  delete script (D2 re-ruled).
- Moving the ACME probe to Better Stack -> P3 -> cut. A check that cannot fail buys nothing.
- Moving `soleur_apex` and `soleur_www_reachability` to Better Stack -> P3 -> already covered.
  `betteruptime_monitor.soleur_apex` watches https://soleur.ai/ at 180s.
  `betteruptime_monitor.soleur_www_redirect` requires a 301 with `follow_redirects = false`,
  so it also fails on DNS, TLS and 5xx errors on www.
- The `SENTRY_MONITORS` leg of CUT8 -> no property -> cut (D-F-A). Sentry watches no marketing
  URL after this PR, and no workflow runs `cutover-verify.sh`.
- A full live==declared Sentry uptime parity script -> P4 -> cut to an "unmanaged only" section
  inside the existing `sentry-alert-live-fidelity.sh` (D-F-B). The terraform drift leg already
  catches a declared monitor missing from live.
- A routed Sentry alert for the app uptime monitor -> P2 -> cut (D-F-E). Better Stack already
  pages for the app; a second route would page the same outage twice.
- Building the 4 Sentry host-kernel cron monitors now -> P5 -> deferred to #12386. With no
  emitter feeding them they would bill or page falsely.

**Value-proposition measurement.** The saving is measured, not asserted:
`doppler run -p soleur -c prd_terraform --command 'printf "Authorization: Bearer %s\n" "$SENTRY_IAC_AUTH_TOKEN" | curl --disable --noproxy "*" -sS -H @- https://jikigai-eu.sentry.io/api/0/customers/jikigai-eu/' | jq '.categories | {monitorSeats, uptime}'` (amended 2026-11-17: the earlier `-- curl -H "...$SENTRY_IAC_AUTH_TOKEN"` form expanded the variable in the outer shell, before Doppler set it)
returned uptime usage 5, reserved 1, onDemandSpendUsed 400 (cents). Direct saving: $4.00/mo.

**Import target, measured read-only 2026-11-17.**
`GET https://de.sentry.io/api/0/organizations/jikigai-eu/detectors/1422253/` with
`SENTRY_IAC_AUTH_TOKEN` returned 200: `type: uptime_domain_failure`, project `web-platform`
(id 4511404943671376), `enabled: true`, `mode: 3`, `url: "https://app.soleur.ai"` (no
trailing slash), interval 60, `name: "Uptime Monitoring for https://app.soleur.ai"`,
`environment` null. The work phase uses the repo's pinned host `jikigai-eu.sentry.io` for every
call, because `sentry-alert-live-fidelity.sh` refuses any other host. (Measured 2026-11-17:
`eu.sentry.io`, `de.sentry.io` and `jikigai-eu.sentry.io` all return 200 on this detector read.
The `sentry` element in `model.c4` records a 302-then-401 on `eu.sentry.io` for other reads, so
the pinned org subdomain is the safe choice; this plan does not depend on which is right.)

**Relevant files.**

- `apps/web-platform/infra/sentry/uptime-monitors.tf`: the 4 declared Sentry uptime monitors.
  Header: full-root auto-apply by `apply-sentry-infra.yml` since #6589, so a removed block is a
  real destroy, gated by `sentry-destroy-required` until `[ack-destroy]` sits on its own line in
  a commit BODY.
- `apps/web-platform/infra/sentry/issue-alerts.tf`: two existing `import {}` blocks
  (`sentry_alert.auth_per_user_loop`, `sentry_alert.git_data_boot_warning`) are the in-root
  precedent for the import shape `id = "${var.sentry_org}/<id>"`. The Sentry root has no
  `*.tftest.hcl`, so the mock-provider import failure of learning 2026-09-27 does not apply.
- `apps/web-platform/infra/uptime-alerts.tf`: 7 `betteruptime_monitor`, the host-kernel
  heartbeats (block comment starting `# #12007 - per-host dead-man heartbeats`), the
  526-coverage list (`The post-mortem scenario this policy was meant to alert on`), and the
  www-redirect comment (`# ── The www→apex 301 redirect alarm (#7798, ADR-204)`) that names
  `sentry_uptime_monitor.soleur_www_reachability`.
- `.github/workflows/apply-web-platform-infra.yml`: the web-platform root still applies a
  `-target=` allow-list. A new `betteruptime_monitor` must be added there or it never applies.
- `apps/web-platform/infra/cutover-verify.sh`: `SENTRY_MONITORS` and `BETTERSTACK_MONITORS`
  arrays for CUT8, three loops over `SENTRY_MONITORS`, and the `CUT8_TOTAL` sum. The comment
  above the arrays says an added monitor must get its baseline row in the same change.
- `apps/web-platform/infra/cutover-monitor-baseline.txt`: generated by
  `cutover-verify.sh --capture-monitor-baseline` (needs credentials).
- `apps/web-platform/infra/www-apex-canonicalizer.test.sh`: W14 (`eq_case '4'` on the Sentry
  name set equal to `SENTRY_MONITORS`) and the sibling `pronounceable_name` count (`eq_case '6'`).
- `apps/web-platform/infra/www-apex-canonicalizer-mutation.test.sh`: `case_row W-sentry-name`
  and `EXPECTED_ROWS=28`.
- `scripts/sentry-alert-live-fidelity.sh` and `tests/scripts/test-sentry-alert-live-fidelity.sh`:
  pinned host `jikigai-eu.sentry.io` via `SENTRY_API_HOST`, fixture seam `SENTRY_FIXTURE_RULES`
  with a loud fixture-mode warning, one verdict consumed by the drift workflow.
- `.github/workflows/scheduled-sentry-alert-drift.yml`: probe step writes
  `verdict=clean|drift|unavailable` to `$GITHUB_OUTPUT`; filer, closer and `close_unavailable`
  key on it. `tests/scripts/test-sentry-alert-drift-workflow.sh` pins that wiring.
- `scripts/sentry-create-gate.sh`: a planned create passes only when matched by an added
  `resource` block. An import is an update, not a create, so the gate is not reached.
- `tests/scripts/lib/destroy-guard-filter-sentry.jq`: uptime deletes count in
  `resource_deletes`.
- `plugins/soleur/lib/heartbeat-live-reconcile.ts`: already asserts every live Better Stack
  monitor maps to a declared `betteruptime_monitor` by `url`, so the new Better Stack monitor is
  covered with no extra wiring.
- `knowledge-base/engineering/architecture/diagrams/model.c4`, `sentry -> founder` edge: "The
  uptime monitors open an issue on downtime, but their detectors are bound to no workflow, so
  this edge claims no route for them". This is why P2 says Sentry detects but does not page.

**Applicable learnings.**

- `2026-07-17-target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop.md`: verify
  the live monitor is gone after apply, not only the plan output.
- `2026-09-27-an-import-block-breaks-terraform-test-and-a-count-ack-reaches-every-destroy.md`:
  `[ack-destroy]` is a boolean over the destroy count, so it would also approve a replace of the
  freshly imported monitor. The plan's change set must be asserted by identity.
- `2026-07-17-unmanaged-is-not-dead-and-a-plan-premise-about-a-repo-setting-is-checkable.md`:
  the origin of DC-1.
- `2026-10-19-a-plan-predicted-a-vendor-objects-state-after-a-toggle-and-the-briefs-cost-premise-was-not-the-bill.md`:
  read the billing API before ruling on a cost lever (done; it surfaced the accrued $4).
- `2026-06-16-recurring-vendor-expense-ledger-gate-and-cost-model-refresh.md`: dated review
  notes are immutable; a recurring-cost change cascades through derived totals.
- `2026-10-05-i-told-the-operator-a-count-was-wrong-and-my-grep-had-counted-a-comment.md`:
  count resources by parsing `resource` blocks after stripping comments.
- `2026-07-18-shared-delivery-substrate-and-reused-heartbeat-url-masking.md`: one signal per
  (host, target); the reason the host-kernel routing keeps 4 monitors, not 1 aggregate.
- `2026-06-02-sentry-cron-margin-must-absorb-gha-dispatch-jitter.md`: relevant to the #12386
  arming design (recorded there, not built here).
- `2026-06-29-c4-source-edit-requires-regenerate-model-json-orphan-suite.md`: regenerate
  `model.likec4.json` after any `.c4` edit.

**External facts (research, getsentry/sentry master and provider source, 2026-11-17).**

- Provider pin: `sentry/versions.tf` and `.terraform.lock.hcl` both pin `jianyuan/sentry`
  `0.15.7`, the version whose source the CTO read. The v0.15.7 docs
  (`docs/resources/uptime_monitor.md`, `## Import`) give the import id as
  `{organization}/{id}`, so `"${var.sentry_org}/1422253"` is the documented form; `organization`
  and `project` are required attributes.

- `UptimeMonitorMode`: MANUAL=1, AUTO_DETECTED_ONBOARDING=2, AUTO_DETECTED_ACTIVE=3. Mode 3
  takes an uptime seat like a manual monitor.
- Provider jianyuan/sentry v0.15.7, `resource_uptime_monitor_impl.go`:
  `getUpdateJSONRequestBody` returns `getCreateJSONRequestBody`, so every update sends
  `config.mode = MANUAL` to `PUT /0/organizations/{org}/detectors/{id}/`. Only `organization`
  and `project` force a replace (`resource_uptime_monitor_gen.go`). (CTO re-ruling, D2.)
- `project` is null after import: `ImportState` calls `ImportState2Part` (sets `organization`
  and `id` only) and `Fill()` in `resource_uptime_monitor_impl.go` never sets `m.Project`. The
  provider's own test says so: `ImportStateVerifyIgnore: []string{"project", "body", "assertion_json"}`
  (`internal/provider/resource_uptime_monitor_test.go`, v0.15.7, lines 177 and 189). So
  `sentry_uptime_monitor.app` carries `ignore_changes = [project]`. The update then sends an
  empty `projectId`; Sentry's detector PUT reads the linked project from the detector and its
  validator has no `projectId` field (getsentry master `organization_detector_details.py`,
  `validators/base/detector.py`; terraform-architect deepen review). If the PUT rejects it anyway,
  the apply errors on `.app` and Phase 7 step 4 (fallback) runs.
- `environment` (live null) updates in place to `"production"`; `assertion_json` is a normalized
  JSON type overwritten from the server response, so expect a one-time change and no repeat
  diff (the four existing monitors with the same local already plan as no-op).
- Terraform floor `required_version = ">= 1.9"` (CI 1.10.5): interpolated import ids (>= 1.6)
  and `removed { lifecycle { destroy = false } }` (>= 1.7) are both valid.
- Sentry `UptimeDomainCheckFailureConfigValidator.validate`
  (`src/sentry/uptime/endpoints/validators.py`) accepts `mode` on update and sets an
  auto-detected monitor to MANUAL when a non-superuser edits it. The "Mode can only be
  specified on creation" error is in the legacy `/uptime/` validator, which the provider does
  not call.
- An update happens only if config differs from live. The declared `name` and `environment`
  differ from live (above), so the first apply is guaranteed to be an `update`, never a no-op
  that would leave mode 3.
- Docs, "Disabling Automatic Detection": deleted auto-detected monitors are not re-created.
  https://docs.sentry.io/product/monitors-and-alerts/monitors/uptime-monitoring/automatic-detection/
- Fallback only: `DELETE /api/0/projects/{org}/{project}/uptime/{id}/` returns 202 and accepts
  `project:write`, `project:admin` or `alerts:write`; `SENTRY_IAC_AUTH_TOKEN` carries
  `alerts:write` and `project:admin`.

**Apply workflows reaching the changed resources.** `apply-sentry-infra.yml` applies the
whole `infra/sentry/` root on push to main (its `paths:` cover the tree). Only
`apply-web-platform-infra.yml` carries `-target=betteruptime_monitor.*` lines
(`grep -l "target=betteruptime_monitor" .github/workflows/*.yml`), so it is the only workflow
that can create the new Better Stack monitor. Other workflows that mention `infra/` paths
(`scheduled-terraform-drift.yml`, `infra-validation.yml`, `sentry-audit-gate.yml`) plan or
validate but do not apply these resources. The opaque ids 1221114-1221117 and 1422253 appear
only in learnings, post-mortems and archived plans (`git grep`), never in scripts or fixtures.
`cutover-verify.sh` is run by no workflow (`deploy-docs.yml` mentions it only in a comment).

**CLI verification.** No CLI invocation lands in user-facing docs. Commands in this plan use
`curl`, `jq`, `doppler run`, `terraform`, `gh` with forms already used in this repo.

**Community / functional overlap.** No uncovered stack. Functional-discovery found no overlap
(adjacent Better Stack and Sentry read-only skills only); nothing installed.

## Implementation Phases

### Phase 0: Pre-flight read (agent-run, read-only)

1. Re-read live state with host `jikigai-eu.sentry.io` and paste the output into the PR body:
   - Sentry uptime detectors: expect 1221114-1221117 (mode 1) and 1422253 (mode 3,
     `https://app.soleur.ai`, project `web-platform`).
   - Sentry billing (`GET /customers/jikigai-eu/` `.categories.uptime`): usage 5.
   - Better Stack monitors: 7.
2. If any count differs, or 1422253 is no longer `uptime_domain_failure` on `web-platform`,
   stop: there is no import target and the D2 fallback (Phase 7 fallback) applies.

### Phase 1: Sentry IaC (`apps/web-platform/infra/sentry/uptime-monitors.tf`)

1. Write the failing test changes first (Phase 3 and Phase 4 test edits) so they go RED against
   the current files, per `cq-write-failing-tests-before`.
2. Add a multi-line import block in the shape of the `issue-alerts.tf` precedent (a one-line
   HCL block may hold only one argument, so the one-line form does not parse):

   ```hcl
   import {
     to = sentry_uptime_monitor.app
     id = "${var.sentry_org}/1422253" # uptime detector id (GET /organizations/{org}/detectors/)
   }
   ```

   with a comment: why it is imported (DC-1, #6606), and that the first apply flips it from
   mode 3 to manual.
3. Add `resource "sentry_uptime_monitor" "app"`: `organization = var.sentry_org` and
   `project = data.sentry_project.web_platform.slug` (as every existing block has),
   `name = "soleur-app-reachability"`, `url = "https://app.soleur.ai"` (the exact live string,
   no trailing slash), `method = "GET"`, `interval_seconds = 60`, `timeout_ms = 10000`,
   `downtime_threshold = 3`, `recovery_threshold = 1`, `environment = "production"`,
   `assertion_json = local.uptime_assertion_2xx`,
   `lifecycle { ignore_changes = [project] }` (permanent: the provider's import and read never
   set `project`, so state holds null and `project` has `RequiresReplace`; without this the
   import plans a destroy-and-create; see External facts), and a `description` stating: the one included
   Sentry uptime slot; two-vendor coverage of the production app (DC-1, ADR-328); Better Stack
   pages for this URL (`betteruptime_monitor.app`, `betteruptime_monitor.app_health`), and this
   monitor detects (opens a Sentry issue) without paging.
4. Delete the blocks `soleur_apex`, `soleur_www_reachability`, `soleur_changelog_deep`,
   `soleur_acme_probe`, and the `moved { from = sentry_uptime_monitor.soleur_www ... }` block
   (it targets a destroyed address; a `moved` to an absent resource errors at plan time).
5. Rewrite the file header: "WHY ONE MONITOR" replaces "WHY FOUR MONITORS". State: Sentry
   includes one uptime monitor; it goes to the production app, adopted from the auto-detected
   monitor; marketing-site uptime is Better Stack's (ADR-328); the ACME probe was removed as
   vacuous (#7799); a second monitor bills $1.00/mo and the drift check reports it. Keep the
   AUTO-APPLY, BETA STATUS and ASSERTION SEMANTICS paragraphs, trimmed to the one monitor.
6. Commit with `[ack-destroy]` on its own line in the commit BODY (not the subject).
7. Verify the plan by identity before pushing (agent-run, `prd_terraform` Doppler config, same
   as `apply-sentry-infra.yml`):
   `cd apps/web-platform/infra/sentry && terraform plan -out=tfplan`, then
   `terraform show -json tfplan | jq -r '.resource_changes[] | select((.change.actions != ["no-op"]) or (.change.importing != null)) | "\(.change.actions|join(",")) \(.address) \(.change.importing.id // "")" | rtrimstr(" ")'`.
   The uptime lines must be exactly: `update sentry_uptime_monitor.app jikigai-eu/1422253` and
   `delete` for the 4 removed addresses. A `create` on `.app` means the import did not bind
   (`sentry-create-gate.sh` would pass it, so this check is the only stop); a
   `delete,create` / `create,delete` on `.app` is a replace. Either one blocks the push. Any
   non-uptime change is listed and explained in the PR, and no `delete` outside the 4
   addresses is allowed.

### Phase 2: Better Stack IaC (`apps/web-platform/infra/uptime-alerts.tf`)

1. Add `resource "betteruptime_monitor" "soleur_changelog_deep"` with the same keys and order as
   `soleur_apex`: `monitor_type = "status"`, `url = "https://soleur.ai/changelog/"`,
   `pronounceable_name = "soleur dot ai changelog deep path"`, `check_frequency = 180`,
   `request_timeout = 10`, `confirmation_period = 60`, `recovery_period = 60`,
   `follow_redirects = true`, `email = true`, `call = false`, `sms = false`, `push = false`,
   `team_name = "Your team"`,
   `policy_id = var.betterstack_paid_tier ? betteruptime_policy.uptime[0].id : null`,
   `verify_ssl = true`, `paused = false`. Comment: moved from Sentry at ADR-328; guards "root
   200 but deep pages 404" (Eleventy half-build).
2. Add `-target=betteruptime_monitor.soleur_changelog_deep \` to
   `.github/workflows/apply-web-platform-infra.yml` next to the other `betteruptime_monitor`
   targets.
3. Update the header comment ("Why apex only ... The 4 Sentry monitors give us per-URL coverage
   already"): Better Stack now owns marketing-site uptime (apex, www redirect, changelog deep
   path, 3 redirect samples); Sentry's one slot watches the app. Keep the ADR-204 amendment
   paragraphs. Fix "Sentry stays at 5min because four probes at 5min" (no longer true).
4. Update the 526-coverage list (`sentry_uptime_monitor.soleur_apex` / `soleur_www_reachability`
   / `soleur_acme_probe` lines) to `betteruptime_monitor.soleur_apex`,
   `betteruptime_monitor.soleur_www_redirect`, `betteruptime_monitor.soleur_changelog_deep`.
5. Update the www-redirect comment (`# ── The www→apex 301 redirect alarm (#7798, ADR-204)`):
   "Two alarms now watch www" becomes one, because `soleur_www_reachability` is removed
   (ADR-328); this monitor also fails on DNS, TLS and 5xx.
6. One-line pointer in the `# #12007 - per-host dead-man heartbeats` comment (D4, D-F-D):
   `ROUTING: arming re-routes these 4 to per-host Sentry cron monitors; decision and must-dos on #12386.`

### Phase 3: Consumer sweep

1. `apps/web-platform/infra/cutover-verify.sh` (D-F-A): delete the `SENTRY_MONITORS=(...)`
   assignment, its three loops, the Sentry branch of `probe_monitor_health` (so no Sentry token
   is sent), and the `${#SENTRY_MONITORS[@]}` term of `CUT8_TOTAL`. Rewrite the comment above
   the arrays: CUT8 grades only Better Stack monitors after ADR-328, because Sentry watches no
   marketing URL. Do NOT append the changelog monitor to `BETTERSTACK_MONITORS` here; that
   entry and its baseline row land together in the follow-up PR (D-F-F, the file's own
   same-change rule).
2. `apps/web-platform/infra/cutover-monitor-baseline.txt`: not edited in this PR. Phase 7 step 6
   regenerates it in the follow-up PR, together with the `BETTERSTACK_MONITORS` append, after the
   Better Stack monitor is live (the capture refuses an `unknown` row). Until then the file still
   lists the 4 Sentry rows, which CUT8 no longer reads.
3. `apps/web-platform/infra/www-apex-canonicalizer.test.sh` W14: replace the
   `SENTRY_MONITORS`-equality check with two asserts: (a) `cutover-verify.sh` contains no
   `SENTRY_MONITORS=(` line; (b) the Sentry file was parsed (at least 1
   `sentry_uptime_monitor` block found, so an empty extraction cannot pass) and no
   `sentry_uptime_monitor` `url` host is `soleur.ai` or `www.soleur.ai`. Update the asymmetry
   comment around `sentry_uptime_monitor.soleur_www_reachability, ~15 min`: a hard 522 on www is
   now detected only by Better Stack `soleur_www_redirect` (~23 min), the same timer as the
   Camp-B failure.
4. Same file, sibling `pronounceable_name` count: `eq_case '6'` becomes `eq_case '7'`, with the
   comment listing `soleur_changelog_deep`.
5. `apps/web-platform/infra/www-apex-canonicalizer-mutation.test.sh`: retarget
   `case_row W-sentry-name` to a mutation that adds a marketing-host `sentry_uptime_monitor`
   (`url = "https://soleur.ai/x"`); it must be killed with the new W14 verdict text. Add one row
   that re-adds a `SENTRY_MONITORS=(x)` line to the cutover script; killed. Bump
   `EXPECTED_ROWS` 28 -> 29.
6. `apps/web-platform/infra/dns.tf`: the Camp-B comment that cites
   `sentry_uptime_monitor.soleur_www` / `soleur_www_reachability` detection timing: update to
   Better Stack only.
7. `knowledge-base/engineering/operations/runbooks/www-redirect-alarm.md`: remove the
   `soleur-ai-www-reachability` row, the "Sentry half" paragraph and its `jq` lookup; state that
   www reachability now pages only through `soleur dot ai www redirect 301`, which also fails on
   DNS, TLS and 5xx.
8. `knowledge-base/engineering/operations/runbooks/cloudflare-pages-cutover.md`: add a dated
   amendment note under the 2026-09-07 one: CUT8 no longer grades Sentry monitors (ADR-328);
   the baseline re-capture is the follow-up PR of #12844. The earlier note is kept as written.
9. `apps/web-platform/infra/sentry/README.md`: "4 uptime monitors" becomes "1 uptime monitor
   (the production app, adopted by import; ADR-328)".
10. ADRs: create ADR-328 via `soleur:architecture` (see `## Architecture Decision (ADR/C4)`);
    add the "Amended by ADR-328" pointers to ADR-204. Before committing, check that no ADR-328
    exists on `origin/main` or any `origin/*` ref; if taken, take the next free number and sweep
    this plan, `tasks.md` and the ADR for the old one.
11. `knowledge-base/engineering/architecture/diagrams/model.c4`: the `betterstack` element
    sentence "Apex reachability is deliberately second-sourced across Sentry and Better Stack"
    becomes "The production app is deliberately second-sourced across Sentry and Better Stack
    (Better Stack pages; Sentry detects); marketing-site uptime is Better Stack only (ADR-328)".
    The `sentry` element sentence "Do not 'consolidate' the two — the redundancy is the design"
    gets scoped to the production app, and "the uptime monitors (uptime-monitors.tf)" becomes
    "the one uptime monitor on the production app (uptime-monitors.tf)". Regenerate
    `model.likec4.json` and run `apps/web-platform/test/c4-code-syntax.test.ts`,
    `apps/web-platform/test/c4-render.test.ts` and
    `bash plugins/soleur/test/c4-count-parity.test.sh`.
12. Comment on #7799 (agent-run `gh issue comment`): the vacuous ACME probe was removed in this
    PR; the lost carve-out property remains open there.
13. Grep sweep, must print nothing:
    `git grep -n -E "soleur-ai-apex|soleur-ai-www-reachability|soleur-ai-changelog-deep|soleur-ai-acme-carveout-probe|sentry_uptime_monitor\.(soleur_apex|soleur_www_reachability|soleur_changelog_deep|soleur_acme_probe)" -- . ':(exclude,glob)knowledge-base/project/**/archive/**' ':(exclude)knowledge-base/engineering/architecture/decisions' ':(exclude)knowledge-base/project/learnings' ':(exclude)knowledge-base/engineering/operations/post-mortems' ':(exclude)knowledge-base/project/plans/2026-11-17-feat-sentry-uptime-dedupe-observability-cost-cut-plan.md' ':(exclude)knowledge-base/project/specs/feat-sentry-cost-consolidation' ':(exclude)apps/web-platform/infra/cutover-monitor-baseline.txt'`.
    Learnings, post-mortems and accepted ADR bodies are point-in-time records and keep the old
    names. Dated amendment notes that name an old monitor in a quoted past tense are allowed
    only inside `cloudflare-pages-cutover.md`'s existing 2026-09-07 note; if the sweep hits that
    note, exclude that one file by path and say so in the PR. The baseline file is excluded
    until the follow-up PR regenerates it.

### Phase 4: Sentry uptime "unmanaged" check (D3, D-F-B)

1. Add an uptime section to `scripts/sentry-alert-live-fidelity.sh`, reusing its pinned
   `SENTRY_API_HOST` (`jikigai-eu.sentry.io`), pinned `SENTRY_ORG`, `_safe` output and verdict:
   - Live: the org's uptime detectors (list endpoint chosen in work; the detectors API the
     provider uses is the default), refused at 100 or more rows (pagination ceiling).
   - Declared count: `resource "sentry_uptime_monitor"` blocks in
     `apps/web-platform/infra/sentry/*.tf` after stripping comments; 0 found is `unavailable`,
     never a pass.
   - Fails when any live uptime detector has `mode != 1`, or the live count is greater than the
     declared count. Each failure calls the script's existing `_finding` (one per monitor), so the
     existing `ERROR: sentry_alert live fidelity FAILED` line and exit 1 carry it; the workflow
     derives its verdict from those, not from the marker.
   - Each finding prints `id:mode:` plus the URL's scheme, host and path only (userinfo and query
     stripped) through `_safe`, because the drift issue body is public.
   - The section runs BEFORE the first rule-side `exit` in the script, so a rule failure cannot
     skip it.
   - One marker line: `SENTRY_UPTIME uptime_verdict=<clean|drift|unavailable> unmanaged=<n> live=<n> declared=<n>`.
   - Fixture seam `SENTRY_FIXTURE_UPTIME=<json file>`, announced loudly in the same way as
     `SENTRY_FIXTURE_RULES`; in fixture mode the marker reads `uptime_verdict=fixture-clean`
     so a fixture run cannot satisfy the discoverability probe.
2. Extend `tests/scripts/test-sentry-alert-live-fidelity.sh` with the Guard Contract rows.
3. `.github/workflows/scheduled-sentry-alert-drift.yml` (no new step, no new trigger):
   - The probe step also writes `uptime_verdict` to `$GITHUB_OUTPUT` from the marker line; a
     missing marker counts as `unavailable`.
   - The unavailable filer also fires when `uptime_verdict == 'unavailable'`;
     `close_unavailable` and the drift closer add `&& steps.probe.outputs.uptime_verdict == 'clean'`,
     so a rule drift cannot close an open uptime-unavailable issue.
   - Pin `SENTRY_FIXTURE_UPTIME: ""` in the probe step env, next to `SENTRY_FIXTURE_RULES: ""`.
   - Drift issue: keep the title (pinned by W9); add an `UPTIME UNMANAGED` bullet to the body:
     "import the monitor or DELETE it; re-running the apply does not fix it". (Amended 2026-11-17
     at review: no import, D2 re-ruling; re-run an unfinished apply first, else DELETE through the
     API; the bullet's exact text lives in the workflow and is pinned by W16.)
4. `.github/workflows/apply-sentry-infra.yml`: pin `SENTRY_FIXTURE_UPTIME: ""` in the post-apply
   probe step env, next to `SENTRY_FIXTURE_RULES: ""`. (That post-apply probe runs under
   `set -e`, so an unmanaged uptime monitor reds the merge's own apply: a synchronous signal.)
5. `tests/scripts/test-sentry-alert-drift-workflow.sh`: W7 runs the real probe with only
   `SENTRY_FIXTURE_RULES` set and would make a live GET once the uptime section exists, so W7 sets
   `SENTRY_FIXTURE_UPTIME`; add rows for the `uptime_verdict` gates in step 3 and the two fixture
   pins.
6. Bump `BASELINE_DECLARED_PROBES` in
   `plugins/soleur/test/preflight-discoverability-test.test.ts` (97 -> 98) with the
   PLACEMENT/TRUTH/NO SUBSTITUTE comment its failure text asks for, because this plan's
   `discoverability_test` declares `credentials_required`.

### Phase 5: Host-kernel heartbeat routing record (D4, D-F-D, no resource change)

1. The one-line pointer is in Phase 2 step 6.
2. Comment on #12386 (agent-run `gh issue comment`) with the routing decision: arming replaces
   the 4 paused Better Stack heartbeats with 4 per-host Sentry cron monitors fed by the same
   feeder (`ok` on beat, `error` on a withheld beat), because 17 -> 21 active heartbeats would
   buy a second $20 Better Stack pack while 4 Sentry seats cost $3.12, and the pager then sits
   on a different vendor from the Logs rows it reads. Must-dos for the arming PR: absorb GHA
   jitter with `failure_issue_threshold` (about 3 missed runs) rather than a margin past the
   60-minute parity ceiling; destroy the 4 paused heartbeats in the same PR with
   `[ack-destroy]`; move every parity gate a new cron monitor moves; the registry emitter keeps
   its own owner-approved PR. Link ADR-328 and this PR.

### Phase 6: Ledgers

Per the CFO review. Dated notes are append-only; earlier notes stay untouched.

1. `knowledge-base/operations/expenses.md`, Sentry Team row: Amount `73.56` becomes `54.06`
   (live-measured 2026-11-17: $29 + $21.06 cron + $4.00 uptime accrued); renewal column
   `2026-12-16`; append a `**2026-11-17 (#12844):**` note with the live counts (28 cron monitors,
   27 billable; uptime 5 -> 1 after this PR), the projection (2026-12-16 invoice $50.06-$55.06
   depending on whether the accrued $4 is refunded; $50.06/mo steady state; $53.18/mo after
   #12386 adds 4 host-kernel cron monitors), the note that the 2026-11-17 $84.48 invoice was
   billing lag, and the re-read command. The Amount moves to 50.06 only after a post-period
   API re-read or invoice read (tracked on the Phase 7 issue).
2. Same file, Better Stack row: Amount stays `20.60`; append a `**2026-11-17 (#12844):**` note:
   uptime monitors 7 -> 8 of 10 included ($0; 9 of 10 with the legal-terms monitor added at
   review, #12844), heartbeats 17 active of 21, the 4 paused
   host-kernel heartbeats are re-routed to Sentry at arming (avoids a second $20 pack, $16.88/mo
   net). The Responder row is not edited: the 2->1 cut stays an operator billing action tracked
   in #12827.
3. `knowledge-base/finance/cost-model.md`: bump `last_updated`; update the Sentry line
   (~"Sentry Team (error tracking + cron monitors, $29 base + $44.56 PAYG ...") to 54.06 with the
   new composition and anchor `[expenses.md@2026-11-17]`; update the Sentry and Better Stack
   risk-table rows (the "Active heartbeats above the next multiple of 10" row now states the
   Sentry re-route); add a `[2026-11-17 Review note]` carrying the totals that move with the
   Sentry line (product COGS 380.07 -> 360.57 per the CFO; recompute each total that sums the
   Sentry line rather than trusting that number) and the steady-state projection. The #12827
   Responder break-even analysis is not done here; the note says one line: it needs a
   re-derivation when #12827 lands.

### Phase 7: Post-merge (agent-run, same session)

0. **Immediately before the merge (amended 2026-11-17, D2/D3a).** Operator go-ahead given
   2026-11-17 for exactly this command. Preconditions on the final head SHA: every required check
   green, `plan_pr` shows `1 to add, 0 to change, 4 to destroy`, `sentry-destroy-required` green,
   and `[ack-destroy]` in a branch commit body. Then, with `U=https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/detectors/1422253/`:
   first, `doppler run -p soleur -c prd_terraform --command 'printf "%s %s\n" "$SENTRY_API_HOST" "$SENTRY_ORG"'`
   must print exactly `jikigai-eu.sentry.io jikigai-eu`, so the DELETE below resolves to `U`
   (its host and org come from that config); and
   `gh pr view 12844 --json mergeStateStatus --jq .mergeStateStatus` must print `CLEAN`
   immediately before the DELETE, so the merge cannot be refused after it (review FR-DI-3/4).
   GET: `doppler run -p soleur -c prd_terraform --command 'printf "Authorization: Bearer %s\n" "$SENTRY_IAC_AUTH_TOKEN" | curl --disable --noproxy "*" -sS --max-time 15 -H @- "https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/detectors/1422253/"'`
   (expect 200, `uptime_domain_failure`, `config.mode` 3, url `https://app.soleur.ai`,
   `workflowIds` `[]`, read 2026-11-17), then
   `doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$SENTRY_IAC_AUTH_TOKEN" | curl --disable --noproxy "*" -sS --max-time 15 -H @- -X DELETE -w "\nHTTP %{http_code}\n" "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/detectors/1422253/"'`
   (expect 2xx), then the same GET with `-o /dev/null -w "%{http_code}"` (expect 404). Any other result stops the merge. On 403, the token's
   scope does not cover the detectors path: stop and report. Then `gh pr merge --squash`. `main`
   has a merge queue (ruleset `merge_queue`), so this enqueues the PR: the gap is the queue's run
   plus the apply, not the apply alone (review FR-UI-1). Tripwire, so the gap is never silent:
   right after the DELETE, file the step 7 tracking issue with the DELETE's timestamp and a
   checkbox "PR merged and `sentry_uptime_monitor.app` read back"; the open issue is the record
   if the session ends. Watch the PR with Monitor until it is merged; if the queue ejects it, fix
   the cause and re-enqueue, and say so on the tracking issue. If the apply then
   refuses to create `.app`, Better Stack keeps paging for the app and the apply is fixed in a
   follow-up PR.
1. Watch `apply-sentry-infra.yml` and `apply-web-platform-infra.yml` on the merge commit to
   completion (Monitor tool with an until-loop on `gh run view`, per
   `hr-monitor-not-run-in-background-for-polling`). The apply runs only through these workflows,
   never a local apply.
2. Read back (agent, `jikigai-eu.sentry.io`; amended 2026-11-17): the new
   `sentry_uptime_monitor.app` detector has `mode: 1`, name `soleur-app-reachability`, url
   `https://app.soleur.ai`, environment `production`, bound to no workflow (`workflowIds == []`,
   so it detects and does not page), and at least one passing check (a non-2xx final response,
   such as a Cloudflare challenge, would open false downtime issues). The check, at least 10 min
   after the apply (3 failures at 60 s open an issue): `doppler run -p soleur -c prd_terraform --command 'printf "Authorization: Bearer %s\n" "$SENTRY_IAC_AUTH_TOKEN" | curl --disable --noproxy "*" -sS --max-time 15 -H @- "https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/issues/?project=-1&statsPeriod=1h&query=is:unresolved%20issue.category:uptime"'`
   returns `[]`. A 400 means Sentry does not accept that filter: record it on the tracking issue
   and read the same URL without `issue.category:uptime`, looking for an issue titled for
   `app.soleur.ai`; 1422253 and
   1221114-1221117 are gone (404). Better Stack
   lists `soleur dot ai changelog deep path` and `soleur dot ai legal terms page` (added at
   review) and both are up.
3. Run `doppler run -p soleur -c prd_terraform --command 'SENTRY_AUTH_TOKEN="$SENTRY_IAC_AUTH_TOKEN" SENTRY_API_HOST=jikigai-eu.sentry.io SENTRY_ORG=jikigai-eu bash scripts/sentry-alert-live-fidelity.sh'`:
   expect `SENTRY_UPTIME uptime_verdict=clean unmanaged=0 live=1 declared=1` and a clean verdict.
4. **Superseded 2026-11-17 — do not execute** (the delete of 1422253 is now Phase 7 step 0,
   before the merge; the legacy `projects/.../uptime/` path below was never checked against
   detector ids). Kept for the record: **Fallback, only if step 2 shows `mode: 3` or the apply errored on `.app`** (D2 fallback,
   D3a): in a new PR, replace the `import` with a multi-line
   `removed { from = sentry_uptime_monitor.app` / `lifecycle { destroy = false } }` block, declare
   a new `sentry_uptime_monitor.app_reachability` on the same URL, and commit with `[ack-destroy]`
   on its own line in the body (the `forget` counts as a destroy in
   `destroy-guard-filter-sentry.jq`). Until the delete, live holds 2 monitors with one in mode 3,
   so the post-apply probe reds that PR's apply and the scheduled check files drift: expected,
   and it clears after the delete. Merge, wait until the new monitor has at least 3 checks all
   `success`, then delete 1422253 with three agent-run calls: GET (expect mode 3 and
   URL `https://app.soleur.ai`), `DELETE /api/0/projects/jikigai-eu/web-platform/uptime/1422253/`
   (expect 202), GET (expect 404). Re-run step 3.
5. Re-read billing: `.categories.uptime.usage` is informational in this period (the accrued $4
   may not refund). Paste it into the PR. The step 7 tracking issue carries the check that
   counts: on the 2026-12-16 read, `.categories.uptime.usage == 1` (a higher value means a
   deleted detector is still billed).
6. Follow-up PR (agent-run, auto-merge): append `"soleur dot ai changelog deep path"` and
   `"soleur dot ai legal terms page"` (added at review) to
   `BETTERSTACK_MONITORS` in `cutover-verify.sh` and regenerate
   `cutover-monitor-baseline.txt` with
   `doppler run -p soleur -c prd_terraform -- bash apps/web-platform/infra/cutover-verify.sh --capture-monitor-baseline apps/web-platform/infra/cutover-monitor-baseline.txt`.
   Expect no Sentry rows, and a `healthy` row for each of the two new monitors.
7. File one tracking issue (agent-run `gh issue create`) listing the post-merge ACs with their
   cited output, the follow-up PR, and the 2026-12-16 ledger re-read (`expenses.md` Sentry Amount
   54.06 -> 50.06 on a post-period read), with a resume prompt. Tick each AC only with cited
   output.

## Files to Edit

- `apps/web-platform/infra/sentry/uptime-monitors.tf`
- `apps/web-platform/infra/uptime-alerts.tf`
- `.github/workflows/apply-web-platform-infra.yml`
- `.github/workflows/scheduled-sentry-alert-drift.yml` (uptime_verdict output, gates, fixture pin, issue body)
- `.github/workflows/apply-sentry-infra.yml` (`SENTRY_FIXTURE_UPTIME: ""` pin only)
- `scripts/sentry-alert-live-fidelity.sh`
- `tests/scripts/test-sentry-alert-live-fidelity.sh`
- `tests/scripts/test-sentry-alert-drift-workflow.sh`
- `apps/web-platform/infra/cutover-verify.sh`
- `apps/web-platform/infra/www-apex-canonicalizer.test.sh`
- `apps/web-platform/infra/www-apex-canonicalizer-mutation.test.sh`
- `apps/web-platform/infra/dns.tf` (comment only)
- `apps/web-platform/infra/sentry/README.md`
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (`BASELINE_DECLARED_PROBES` 97 -> 98)
- `knowledge-base/engineering/operations/runbooks/www-redirect-alarm.md`
- `knowledge-base/engineering/operations/runbooks/cloudflare-pages-cutover.md` (dated amendment note)
- `knowledge-base/engineering/architecture/decisions/ADR-204-redirect-health-moves-to-better-stack-because-sentry-cannot-express-it.md` (pointer lines only)
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated)
- `knowledge-base/operations/expenses.md`
- `knowledge-base/finance/cost-model.md`

Follow-up PR (Phase 7 step 6): `apps/web-platform/infra/cutover-verify.sh`
(`BETTERSTACK_MONITORS` append) and `apps/web-platform/infra/cutover-monitor-baseline.txt`.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-328-sentry-uptime-holds-one-slot-for-the-production-app.md` (ordinal provisional)

## Open Code-Review Overlap

1 open scope-out touches these files:

- #7098 (audit the 56 `run:` bodies whose `set` omits -e, `apply-web-platform-infra.yml`):
  **Acknowledge.** This plan adds one `-target=` line and no `run:` body; the audit is a
  different concern and stays open.

## Infrastructure (IaC)

### Terraform changes

- Root `apps/web-platform/infra/sentry/` (provider `jianyuan/sentry`, pinned in
  `sentry/versions.tf`, unchanged): +1 `import` and +1 `sentry_uptime_monitor.app` (adopts live
  1422253; plan action `update`), -4 `sentry_uptime_monitor` (`soleur_apex`,
  `soleur_www_reachability`, `soleur_changelog_deep`, `soleur_acme_probe`), -1 `moved` block.
  Applied by `apply-sentry-infra.yml` (full root) on push to main. No new variables or secrets.
- Root `apps/web-platform/infra/` (provider `BetterStackHQ/better-uptime`, unchanged):
  +1 `betteruptime_monitor.soleur_changelog_deep`, registered in the
  `apply-web-platform-infra.yml` `-target=` list. No new variables or secrets.

### Apply path

Path (a)-equivalent for vendor objects: no host is touched. Both roots auto-apply on merge.
Blast radius: the four destroyed Sentry monitors stop detecting; their properties are covered by
Better Stack as listed in the Cut List. The adopted app monitor keeps its id and check history.
Expected downtime: none.

### Host fan-out

None. No `terraform_data` SSH provisioner is added or changed.

### Distinctness / drift safeguards

- Change set asserted by identity in Phase 1 step 7 (`[ack-destroy]` is a count boolean and
  would also approve a replace of the imported monitor).
- `sentry-create-gate.sh` is not reached on the primary path (no create). On the fallback the
  new block's create is matched by its added `resource` line.
- The uptime section of `sentry-alert-live-fidelity.sh` covers "live but unmanaged"; the
  terraform drift leg already covers "declared but missing"; the Better Stack half is covered
  by `heartbeat-live-reconcile`.
- No secret value lands in state beyond what the existing resources already hold.

### Vendor-tier reality check

- Sentry: 1 uptime monitor included; this PR leaves exactly 1. A second monitor bills
  $1.00/mo and the uptime check reports it.
- Better Stack: 10 uptime monitors included; this PR adds 1 (8 declared unconditionally, plus
  `betteruptime_monitor.github_webhook_failures` only when `var.betterstack_paid_tier` is true).
  No `betteruptime_policy` change.

## Architecture Decision (ADR/C4)

### ADR

Create **ADR-328 (provisional ordinal)** via `soleur:architecture`: "Sentry uptime holds a
single slot, the production app; Better Stack owns marketing-site uptime." Decision:

- Sentry's one included uptime monitor watches https://app.soleur.ai, adopted from the
  auto-detected monitor by import (two-vendor coverage where user data lives, DC-1).
- Better Stack pages for the app; Sentry's monitor detects (opens an issue) and has no route.
- Marketing-site reachability, redirect health and the deep path are Better Stack only.
- Vendor split rule (CTO devex review): uptime goes to Better Stack while it has included
  slots (9 of 10 after this PR, with the legal-terms monitor added at review); dead-man and cron signals go to Sentry when the next Better
  Stack $20 heartbeat pack would be crossed; the app always stays on two vendors. Every
  further Sentry uptime monitor costs $1.00/mo and the uptime check reports it.

Alternatives Considered: brief option A (keep the ACME probe), a new declared monitor plus
delete of 1422253 (the fallback), move the ACME probe to Better Stack, keep both vendors on the
apex ($1/mo), a routed Sentry alert for the app monitor. Consequences: a Better Stack outage
leaves soleur.ai unwatched (dissent recorded).

Amend **ADR-204** by pointer only: an "Amended by ADR-328" line at its "Apex reachability is
deliberately second-sourced across Sentry and Better Stack" consequence, and at the rejected row
"Delete `sentry_uptime_monitor.soleur_www` outright" (its premise, "Better Stack carries no www
monitor today", no longer holds). The accepted body is not rewritten.

### C4 views

All three model files were checked by grep for this plan: `model.c4` at the `sentry` and
`betterstack` elements and their paging edges; `views.c4` already includes both elements in both
views; `spec.c4` has no sentry, betterstack or uptime element. The work phase re-reads all three
in full before editing. Checked:

- External human actors: the founder/operator (pager recipient) is modeled; no new actor.
- External systems: `sentry` and `betterstack` are modeled; no new vendor.
- Containers/data stores: none touched.
- Relationships: `betterstack -> founder` and `sentry -> founder` paging edges exist. The
  `sentry -> founder` edge already says uptime detectors have no route, which stays true.

Edits (Phase 3 step 11): prose only. No `views.c4` change. `c4-count-parity` counts cron
monitors and heartbeat workflows, neither of which this PR changes.

### Sequencing

ADR-328 is true at merge once both apply workflows finish. On the fallback path the 1422253
delete lands later (Phase 7 step 4); the ADR states that order.

## User-Brand Impact

- **If this lands broken, the user experiences:** an app.soleur.ai outage detected by one vendor
  only. From the pre-merge delete of 1422253 until the apply creates the new Sentry monitor, and
  indefinitely if that apply fails, Sentry does not watch the app; Better Stack still pages for it
  (about 4 min email, 6 min email and push) throughout. Or a marketing-site outage (soleur.ai, www,
  changelog) that pages through Better Stack only and stays silent if Better Stack is also down;
  that includes the terms and privacy pages a signed-in user opens from the accept-terms and signup
  screens (amended 2026-11-17).
- **If this leaks, the user's data is exposed via:** nothing new. The change moves synthetic
  HTTP probes of public URLs between two vendors already holding them; no user data, no new
  credential, no new egress.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the one surface where a single user's incident lives,
  the app, keeps both vendors (amended 2026-11-17: through a new monitor id that replaces 1422253,
  whose check history is lost); the surfaces that lose a vendor are static marketing pages, where
  harm comes from a pattern of unnoticed downtime, not from one user. A legal page that is down
  while Better Stack is also down is a double fault. The legal pages' final 200 URL was unwatched
  by either vendor before this PR; review added `betteruptime_monitor.soleur_legal_terms` on
  `https://soleur.ai/legal/terms-and-conditions/` (the page the signup and accept-terms links
  reach after their 301), so it is now watched by Better Stack.

## Observability

```yaml
liveness_signal:
  what: "Sentry uptime monitor soleur-app-reachability (declared new, replacing auto-detected 1422253, https://app.soleur.ai, 2xx) as a detection second source; Better Stack monitors app, app_health and 'soleur dot ai changelog deep path' as the paging source; the SENTRY_UPTIME section of sentry-alert-live-fidelity.sh in scheduled-sentry-alert-drift.yml"
  cadence: "Sentry 60s (3 failures open an issue); Better Stack 180s (60s confirmation); uptime check every scheduled drift run"
  alert_target: "Better Stack email (pages); Sentry opens an issue with no alert route (model.c4 sentry -> founder edge); a drift verdict opens a ci/sentry-alert-drift GitHub issue"
  configured_in: "apps/web-platform/infra/sentry/uptime-monitors.tf; apps/web-platform/infra/uptime-alerts.tf; scripts/sentry-alert-live-fidelity.sh; .github/workflows/scheduled-sentry-alert-drift.yml"

error_reporting:
  destination: "Sentry project web-platform (org jikigai-eu) for uptime issues; GitHub issues labelled ci/sentry-alert-drift for drift"
  fail_loud: "sentry-alert-live-fidelity.sh prints SENTRY_UPTIME unmanaged=<n> with id:mode:url per finding and returns the drift verdict; 0 declared blocks or a 100-row page returns unavailable, which files its own issue"

failure_modes:
  - mode: "Sentry re-creates an auto-detected uptime monitor, or someone adds one by hand"
    detection: "SENTRY_UPTIME reports unmanaged>0 (mode != 1) or live>declared; the fidelity script prints FAILED and exits 1"
    alert_route: "ci/sentry-alert-drift GitHub issue; layer: GitHub Actions workflow run log (::error:: + SENTRY_UPTIME line)"
  - mode: "1422253 still live at the apply, or the new app monitor not created (amended 2026-11-17: no import)"
    detection: "apply-sentry-infra.yml post-apply probe reds unless uptime_verdict=clean (a mode-3 row is drift, fewer live than declared is unavailable); Phase 7 step 2 read-back"
    alert_route: "failed apply workflow run + agent read-back in the post-merge session; layer: GitHub Actions workflow run log"
  - mode: "declared app monitor deleted outside Terraform"
    detection: "scheduled-terraform-drift.yml Sentry leg plans a create"
    alert_route: "existing terraform drift issue path; layer: GitHub Actions workflow run log"
  - mode: "changelog deep path starts returning 404 or 5xx"
    detection: "Better Stack monitor soleur dot ai changelog deep path goes down"
    alert_route: "Better Stack email + Slack integration; layer: external synthetic probe, outside the app's layers 1-7 by design (ADR-328)"
  - mode: "the terms page a signing user opens stops serving 200 (added at review)"
    detection: "Better Stack monitor soleur dot ai legal terms page goes down"
    alert_route: "Better Stack email + Slack integration; layer: external synthetic probe, outside the app's layers 1-7 by design (ADR-328)"
  - mode: "Better Stack changelog monitor never applied (missing -target)"
    detection: "heartbeat-live-reconcile reports the declared monitor absent-live"
    alert_route: "existing reconcile issue path; layer: GitHub Actions workflow run log"
  - mode: "Better Stack changelog monitor paused, or its email turned off, outside Terraform"
    detection: "heartbeat-live-reconcile MonitorField diff on paused/email (monitor-config-drift)"
    alert_route: "scheduled-terraform-drift.yml reconcile issue; layer: GitHub Actions workflow run log"

logs:
  where: "GitHub Actions run logs of scheduled-sentry-alert-drift.yml (the SENTRY_UPTIME marker line); Sentry uptime check history per monitor"
  retention: "GitHub Actions default 90 days; Sentry per plan retention"

discoverability_test:
  command: "bash scripts/sentry-alert-live-fidelity.sh"
  expected_output: "uptime_verdict=clean"
  credentials_required: "SENTRY_IAC_AUTH_TOKEN read scope (alerts:read) via doppler soleur/prd_terraform, with SENTRY_API_HOST=jikigai-eu.sentry.io and SENTRY_ORG=jikigai-eu — the live uptime detector set is only readable through the authenticated Sentry organization API; no public endpoint lists it"
```

## Encryption Posture

```yaml
at_rest: []
in_transit:
  - connection: "Better Stack probe -> https://soleur.ai/changelog/ (Cloudflare edge)"
    enforced_at: "apps/web-platform/infra/uptime-alerts.tf:betteruptime_monitor.soleur_changelog_deep (verify_ssl = true)"
    tls: "HTTPS, TLS 1.2+ as served by the Cloudflare edge"
    cert_verification: on
    does_not_defend: "a compromised Cloudflare edge or a forged 2xx; the probe reads only the status of a public page"
    disclosed_as: not-publicly-claimed
```

No persistent store is introduced. The Sentry app probe is unchanged in transport (same
monitor, same URL); only its Terraform ownership and name change.

## Guard Contract

### Guard 1 — no unmanaged Sentry uptime monitor

**Property.** Every live Sentry uptime detector in org jikigai-eu has `mode == 1`, and the live
count is not greater than the number of declared `sentry_uptime_monitor` blocks.

**Assembly.** Declared: every `resource "sentry_uptime_monitor"` block in
`apps/web-platform/infra/sentry/*.tf` after comment stripping. Live: the org-level uptime
detector list (all projects), refused at 100 or more rows. Both read inside the uptime section
of `scripts/sentry-alert-live-fidelity.sh`.

**Mutation matrix** (fixture rows in `tests/scripts/test-sentry-alert-live-fidelity.sh`):

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture adds a live row `mode: 3` on the declared app URL | drift, names `id:3:url` |
| 2 | Fixture adds a second live mode-1 row (live 2, declared 1) | drift (live > declared) |
| 3 | Declared parse finds 0 blocks (file emptied or the parser regex broken) | unavailable, not clean |
| 4 | Fixture returns a non-array body (error JSON) | unavailable |
| 5 | `SENTRY_API_HOST` set to a non-pinned value | refused, exit 2, token never sent |
| 6 | Fixture returns 100 rows | refused (pagination ceiling), unavailable |
| 7 | A rule-side failure that exits early, with an unmanaged uptime fixture | uptime finding still printed (section runs first) |
| 8 | Workflow test: rule verdict drift + `uptime_verdict=unavailable` | unavailable issue filed and NOT closed |
| 9 | Uptime fixture with a URL carrying `user:pass@` and `?token=` | finding prints scheme/host/path only |

**Harness rows:**

| # | Mutation | Expected |
|---|---|---|
| H1 | Must-PASS: one live mode-1 row, one declared block, live URL without trailing slash | clean |
| H2 | Must-PASS: declared block with different whitespace and a trailing comment | clean |

**Anchor.** No stored value; the comparison is live against the committed files each run.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Sentry uptime dedupe (apps/web-platform/infra/sentry/uptime-monitors.tf): remove duplicates of Better Stack coverage — soleur_apex ... and soleur_www_reachability" [brief] | Phase 1 step 4 | mapped |
| 2 | "Keep soleur_acme_probe in Sentry as the 1 included uptime monitor ($0)." [brief] | Phase 1 steps 2-4 (app monitor holds the slot; acme dropped) | mapped — changed by CTO ruling D1, operator (scope) row D1b |
| 3 | "Move soleur_changelog_deep to a free Better Stack uptime slot (betteruptime_monitor in apps/web-platform/infra/uptime-alerts.tf) or justify dropping it." [brief] | Phase 2 | mapped |
| 4 | "Destroys need the `[ack-destroy]` line in a commit BODY per the file header." [brief] | Phase 1 step 6 | mapped |
| 5 | "Check every consumer of the removed resources (alert rules, runbooks, tests, scheduled-sentry-alert-drift and any audit scripts that enumerate expected uptime monitors, ADR-204 text)." [brief] | Phase 3 (steps 1-13), Phase 4 | mapped |
| 6 | "Target: Sentry uptime usage 1 = reserved → $0 PAYG." [brief] | Phase 7 steps 3 and 5; AC4 | mapped |
| 7 | "Delete the Sentry AUTO-DETECTED uptime monitor \"Uptime Monitoring for https://app.soleur.ai\"" [brief] | Phase 1 steps 2-3 (adopted and converted to manual; delete only on fallback) | mapped — changed by CTO ruling D2, operator (scope) row D1a |
| 8 | "disable org-level uptime auto-detection so it is not recreated — via API/IaC, never a dashboard step." [brief] | Phase 4 + D3 (no writable setting exists) | mapped — mechanism changed by CTO ruling D3 |
| 9 | "a production-mutating API call must be planned as an agent-run step with a dry-run/read-back verification." [brief] | Phase 1 step 7 (plan by identity = dry run), Phase 7 steps 2-4 (read-back; fallback GET/DELETE/GET) | mapped |
| 10 | "Route that signal to Sentry cron monitors instead (~$3.12/mo) if the emitter supports a Sentry check-in, or record the routing decision where the unpause would happen. Find why they are paused and what would unpause them." [brief] | Phase 5, Phase 2 step 6 | mapped |
| 11 | "Spawn soleur:engineering:cto to rule on this technical fork" [brief] | decision-challenges D4 | mapped |
| 12 | "Update knowledge-base/operations/expenses.md (Sentry Team + Better Stack rows) and knowledge-base/finance/cost-model.md with the live counts above and the projected next Sentry invoice" [brief] | Phase 6 | mapped |
| 13 | "Note the Responder 2→1 license cut stays an operator billing action tracked separately." [brief] | Phase 6 step 2 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `sentry/uptime-monitors.tf` edits (import, app block, 4 deletes) | asks 1-4, 7 | asked |
| `uptime-alerts.tf` changelog monitor | ask 3 | asked |
| `apply-web-platform-infra.yml` `-target` line | — | inferred — justification: the web-platform root applies a `-target=` allow-list, so without the line the ask-3 monitor never reaches Better Stack |
| `cutover-verify.sh`, canonicalizer tests, mutation test, follow-up baseline PR | ask 5 ("tests ... audit scripts that enumerate expected uptime monitors") | asked |
| `dns.tf`, `www-redirect-alarm.md`, `cloudflare-pages-cutover.md`, `sentry/README.md`, ADR-204 pointer, `uptime-alerts.tf` comments | ask 5 ("runbooks ... ADR-204 text") | asked |
| uptime section in `sentry-alert-live-fidelity.sh` + tests + drift issue body | ask 8 ("so it is not recreated") | asked |
| ADR-328 + `model.c4` + `model.likec4.json` | — | inferred — justification: plan Phase 2.10 makes the ADR/C4 update a deliverable of the change that reverses ADR-204's apex second-sourcing |
| `uptime-alerts.tf` routing pointer, #12386 comment | ask 10 | asked |
| `expenses.md`, `cost-model.md` | asks 12-13 | asked |
| #7799 comment | — | inferred — justification: CTO must-do for D1b; the dropped probe's lost property must stay visibly tracked |
| Phase 7 tracking issue | — | inferred — justification: CTO ruling D-F-G; the post-merge ACs and the 2026-12-16 ledger re-read need an owner after the session ends |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform`, `.github`, `scripts`/`tests`/`plugins`, `knowledge-base`
- Planned files: 22 | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the 4-root count is driven by doc/ledger and test files that
  must move with the IaC change (a split would leave CI red on W14 or leave docs stating
  removed monitors); files and lines are under threshold. The baseline regeneration is a
  follow-up PR only because it needs the merged monitor to be live.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 (amended 2026-11-17): `plan_pr` output, pasted in the PR, shows for uptime exactly
      `create sentry_uptime_monitor.app` and `delete` of the 4 removed addresses, no import row,
      and no `delete` on any other address.
- [ ] AC2: a commit on the branch carries `[ack-destroy]` on its own line in its BODY;
      `sentry-destroy-required` is green.
- [ ] AC3: after stripping comments, `uptime-monitors.tf` has 1 `resource "sentry_uptime_monitor"`
      block and no `import` block (amended 2026-11-17); `uptime-alerts.tf` has 8
      `resource "betteruptime_monitor"` blocks; `grep -c 'betteruptime_monitor.soleur_changelog_deep' .github/workflows/apply-web-platform-infra.yml`
      prints `1`.
- [ ] AC5: `bash apps/web-platform/infra/www-apex-canonicalizer.test.sh` and
      `bash apps/web-platform/infra/www-apex-canonicalizer-mutation.test.sh` pass, with
      `EXPECTED_ROWS=29` and both new W14 rows killed.
- [ ] AC6: `bash tests/scripts/test-sentry-alert-live-fidelity.sh` and
      `bash tests/scripts/test-sentry-alert-drift-workflow.sh` pass; every Guard 1 row is a case;
      `SENTRY_FIXTURE_UPTIME: ""` appears in both `scheduled-sentry-alert-drift.yml` and
      `apply-sentry-infra.yml`.
- [ ] AC7: the Phase 3 step 13 grep sweep prints nothing.
- [ ] AC8: ADR-328 exists (ordinal checked free on every `origin/*` ref); ADR-204 carries the two
      "Amended by ADR-328" pointers; `model.c4` edits made and `model.likec4.json` regenerated;
      `c4-code-syntax`, `c4-render` and `c4-count-parity` pass.
- [ ] AC9: `expenses.md` Sentry row Amount reads `54.06` with a `2026-11-17 (#12844)` note;
      Better Stack row carries a `2026-11-17 (#12844)` note; `cost-model.md` carries a
      `[2026-11-17 Review note]` and its Sentry line cites `[expenses.md@2026-11-17]`.
- [ ] AC10: `uptime-alerts.tf` host-kernel comment carries the ROUTING pointer; #12386 and #7799
      carry the agent-posted comments.
- [ ] AC15: `preflight-discoverability-test.test.ts` passes with `BASELINE_DECLARED_PROBES = 98`.

### Post-merge (agent-run, Phase 7)

- [ ] AC4: `sentry-alert-live-fidelity.sh` (prd_terraform Doppler) prints
      `SENTRY_UPTIME uptime_verdict=clean unmanaged=0 live=1 declared=1`. The billing `.categories.uptime.usage`
      read is pasted as information; the ledger re-read after 2026-12-16 is on the tracking issue.
- [ ] AC11 (amended 2026-11-17): detector 1422253 reads back 404, and the new
      `sentry_uptime_monitor.app` reads `mode: 1`, name `soleur-app-reachability`.
- [ ] AC13: Better Stack lists `https://soleur.ai/changelog/` as up, and the next
      heartbeat-live-reconcile run reports no absent-live or unmanaged monitor.
- [ ] AC14: the follow-up PR merged with `BETTERSTACK_MONITORS` holding the changelog monitor
      and `cutover-monitor-baseline.txt` holding no Sentry rows and a changelog `healthy` row.
- [ ] AC16: the tracking issue exists and lists AC4, AC11, AC13, AC14 with cited output and the
      2026-12-16 ledger re-read.

## Domain Review

**Domains relevant:** Engineering, Finance

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled forks D1-D7 and, after plan review, D2 (re-ruled to import-first) and
D-F-A to D-F-G (see `decision-challenges.md`). Keep the production app on two vendors by
adopting the auto-detected monitor; drop the vacuous ACME probe; no auto-detection setting write
(none exists), an "unmanaged" check inside the existing fidelity script instead; host-kernel
paging moves to Sentry cron monitors in the arming PR; new ADR plus ADR-204 pointer; CUT8 stops
grading Sentry monitors by deleting that leg.

### Finance (CFO)

**Status:** reviewed
**Assessment:** Direct saving is the $4.00/mo uptime only; do not present $73.56 -> $50.06 as
this PR's saving (most of it is the 2026-10-29 prune). Record the Sentry Amount as the measured
54.06 now and move to 50.06 only on a post-period read. State the 2026-12-16 invoice as a range
($50.06-$54.06). Steady state $53.18 after #12386. The host-kernel re-route avoids $16.88/mo.
The renewal column is stale (2026-12-16). The #12827 Responder cut needs a re-derivation when it
lands.

### Product/UX Gate

Not relevant: no UI surface in Files to Edit or Files to Create.

## Plan Review (2026-11-17)

Panel: DHH, Kieran, code-simplicity (per mechanism), CTO (devex lens), plus the scoped advisor
consult. Applied: import-first (advisor, re-ruled D2); delete script and parity script cut;
CUT8 Sentry leg deleted, not emptied (D-F-A); uptime check merged into the existing fidelity
script, unmanaged-only (D-F-B); routing record reduced to #12386 plus one pointer (D-F-D);
Sentry app monitor stated as detect-only (D-F-E); `BETTERSTACK_MONITORS` append moved to the
follow-up PR with the baseline (D-F-F); tracking issue for post-merge ACs (D-F-G); Sentry host
pinned to `jikigai-eu.sentry.io`; grep-sweep pathspec fixed; missing `project`,
`recovery_period`, `team_name` keys added; exact live URL; `EXPECTED_ROWS` bump; ACs graded on
the diff and on live reads that the change controls; the `cost-model.md` Responder analysis
trimmed to one line. Not applied, with reasons in `decision-challenges.md`: DHH's "no new ADR"
(D-F-C keeps it) and code-simplicity's "drop changelog_deep" (D1 keeps the move).

## Test Scenarios

- Given one live mode-1 detector and one declared block, when the fidelity script's uptime
  section runs on a fixture, then it prints `SENTRY_UPTIME uptime_verdict=clean unmanaged=0 live=1 declared=1` and
  the verdict is clean. (unit)
- Given a fixture with an extra mode-3 row, when the uptime section runs, then the verdict is
  drift and the output names `1422253:3:https://app.soleur.ai`. (unit)
- Given 0 declared blocks, when the uptime section runs, then the verdict is unavailable. (unit)
- Given a non-pinned host env, when the script runs, then it refuses with exit 2 and sends no
  request. (unit)
- Given a marketing-host `sentry_uptime_monitor` added, when the canonicalizer runs, then W14
  fails. (unit, mutation)
- Given a `SENTRY_MONITORS=(x)` line re-added to `cutover-verify.sh`, when the canonicalizer
  runs, then W14 fails. (unit, mutation)
- Plan verify (pre-merge; amended 2026-11-17, no import): the Phase 1 step 7 identity command shows
  `create` for `sentry_uptime_monitor.app`, `delete` for the 4 removed addresses, and no import row.
- API verify (post-merge): `doppler run -p soleur -c prd_terraform --command 'SENTRY_AUTH_TOKEN="$SENTRY_IAC_AUTH_TOKEN" SENTRY_API_HOST=jikigai-eu.sentry.io SENTRY_ORG=jikigai-eu bash scripts/sentry-alert-live-fidelity.sh'`
  expects `SENTRY_UPTIME uptime_verdict=clean unmanaged=0 live=1 declared=1`.

## Dependencies & Risks

- **Import does not flip mode:** if the provider or server behaves differently from the source
  read, 1422253 stays mode 3. Detection: Phase 7 step 2 read-back. Mitigation: the Phase 7
  step 4 fallback.
- **Import becomes a replace:** `project` is null after import and forces a replace, which
  `[ack-destroy]` would approve. Mitigation: `ignore_changes = [project]` on `.app`, and the AC1
  identity check refuses any `delete,create` on `.app`.
- **Empty `projectId` on the update PUT:** with `project` ignored, the provider sends an empty
  `projectId`. Source reading says the detector PUT ignores it; if it does not, the apply errors
  on `.app` and the fallback runs.
- **Re-creation risk:** Sentry could auto-detect again. Per research it turns the option off
  after its first auto monitor and does not re-create deleted ones; the uptime check reports any
  `mode != 1` monitor within one scheduled run.
- **Billing risk:** the accrued $4 may not refund this period. Accepted; the ledger states the
  range.
- **ADR ordinal collision:** ADR-328 is provisional; probe every `origin/*` ref and re-probe
  right before merge; `soleur:ship` re-checks it.
- **Apply-order gap on the deep path:** `apply-sentry-infra.yml` (full root) and
  `apply-web-platform-infra.yml` (target-scoped) run independently on the merge, so the Sentry
  changelog monitor can be destroyed minutes before the Better Stack one exists. Accepted: the
  gap is one apply duration on a static page. Phase 7 step 2 confirms the Better Stack monitor
  is up before the work is called done.
- **Coverage loss (accepted, dissent recorded):** marketing apex and www reachability become
  Better Stack only; a Better Stack outage leaves the marketing site unwatched.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6.
- `[ack-destroy]` is a boolean over the destroy count: any other destroy, or a replace of the
  imported monitor, rides on it. AC1 asserts the set by identity; do not skip it.
- Do not drop `ignore_changes = [project]` from `sentry_uptime_monitor.app` in a later tidy-up:
  the provider never reads `project` back, so removing it plans a replace of the app monitor.
- An import whose config equals live plans as a no-op and does not flip the mode. The declared
  name and environment differ from live, so the first apply is an update; do not "tidy" them to
  match live before the first apply.
- The `moved` block must go with `soleur_www_reachability`; leaving it pointing at a removed
  address fails `terraform plan`.
- The web-platform root is `-target=`-scoped: a `betteruptime_monitor` block without its
  `-target=` line plans and applies nothing, silently.
- `cutover-monitor-baseline.txt` is generated; a hand edit does not survive the next capture and
  an `unknown` row is refused by the capture.
- Count resources by parsing `resource` blocks after stripping comments; both `.tf` files name
  the removed resources in comments.
- Use `jikigai-eu.sentry.io` for every Sentry API call: the fidelity script pins it and refuses
  any other host.
