---
title: "chore: route the scheduled-integration-suites Sentry monitor into cron_monitor_failure (two-PR rule, PR 2)"
type: chore
date: 2026-10-11
slug: route-scheduled-integration-suites-monitor
branch: feat-one-shot-9959-route-sentry-monitor
issue: 9959
closes: 9959
lane: cross-domain
priority: p3-low
brand_survival_threshold: none
---

# chore: route the scheduled-integration-suites Sentry monitor into cron_monitor_failure (two-PR rule, PR 2)

## Overview

GitHub issue #9959 is the second PR of the two-PR rule (`apps/web-platform/infra/sentry/README.md`
§"Adding or removing a cron monitor — the two-PR rule (#8630)") for the `scheduled-integration-suites`
cron monitor, declared in PR #9947 (squash `21331e94e3`, merged). PR 1 put the label in
`local.cron_monitor_alert_unrouted` because a monitor's detector id does not exist until its first
apply — a same-PR route would leave `monitor_ids` referencing an id unknown at plan time and red
`main` after a complete apply.

Both preconditions are now met (verified, see Premise Validation): the apply created the detector
(live read: id `2403709`, `workflowIds: []`), and the first measured check-in landed (run
38130672233 posted `error`). The change is therefore a pure routing move:

1. `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`: remove the `scheduled_integration_suites`
   entry and its `#9855` comment block from `local.cron_monitor_alert_unrouted`; add
   `sentry_cron_monitor.scheduled_integration_suites.id,` to
   `sentry_alert.cron_monitor_failure.monitor_ids` in sorted position (between
   `scheduled_inngest_health` and `scheduled_legal_audit`).
2. `apps/web-platform/infra/sentry/alert-reference.json`: append `"2403709"` to the
   `cron-monitor-failure` rule's `detectorIds` (string-sorted last, after `"2359391"`). Derived
   locally per precedent #9511 — the detector id was read live at plan time, so no credentials are
   needed at work time. The `plan_pr` `sentry-alert-reference` gate is the proof; only if it reds,
   take the `sentry-alert-reference-expected-<run-id>` CI artifact (the path the issue names) and
   diff it against the local edit before copying — any hunk beyond the one id is a finding.

Until this lands, a missed or errored check-in on this monitor opens a Sentry issue but emails
nobody; the in-run `ci/integration-suites` GitHub issue remains the primary channel for
run-internal reds either way (that channel is unaffected by this change — it is the workflow's own
failure reporter, not the dead-man monitor).

## Research Insights

### Premise Validation

- `gh issue view 9959` → `OPEN`, title "Route scheduled-integration-suites Sentry monitor into
  cron_monitor_failure (two-PR rule, PR 2)", labels `domain/engineering, meta/machinery,
  priority/p3-low, type/chore`; both checklist boxes unchecked — the issue is live and undone.
- Precondition 1 (detector exists): PR #9947 MERGED, mergeCommit
  `21331e94e352fd95502751ee0d91658fed0e0b84`; `Apply sentry infra (cron + uptime monitors)` run
  **38105510428** succeeded on that commit — the monitor was applied.
- Precondition 2 (first measured check-in): run **38130672233** (`Scheduled: integration suites`,
  workflow_dispatch) — `Sentry check-in (final)` step `success`; run conclusion `failure` (5/8
  suites red → the check-in posted `error`, which is exactly the measured signal the two-PR rule
  waits for).
- Live route state (read-only, `doppler run --project soleur --config prd` + `curl
  /api/0/organizations/$SENTRY_ORG/detectors/?query=scheduled-integration-suites`):
  `{id: "2403709", name: "scheduled-integration-suites", type: "monitor_check_in_failure",
  workflowIds: []}` — detector `2403709` exists and is bound to no workflow, consistent with the
  declared-unrouted entry.
- Mechanics verified against the tree (line numbers are pre-edit anchors):
  - `cron-monitor-alerts.tf` lines 59–63: the `#9855` comment block +
    `scheduled_integration_suites = "route after the first measured check-in (#9959)"` — the only
    `#9959` references in the file.
  - `monitor_ids` is one `sentry_cron_monitor.<label>.id,` per line, LC_ALL=C sorted; insertion
    point between `scheduled_inngest_health.id,` (line 105) and `scheduled_legal_audit.id,`
    (line 106): byte-order `…inngest…` < `…integration…` (third letter `n` < `t`) and
    `…integration…` < `…legal…` (`i` < `l`).
  - `alert-reference.json` line 711: `"2359391"` is the last `detectorIds` element of
    `cron-monitor-failure` (60 entries, verified `. == sort`); `"2403709"` string-sorts after it →
    one-line append, 60 → 61.
  - `terraform fmt -check apps/web-platform/infra/sentry/cron-monitor-alerts.tf` → clean pre-edit;
    the sibling-style insert keeps it clean (CI `infra-validation.yml` runs `fmt -check -recursive`).
  - Guard: `apps/web-platform/test/server/inngest/sentry-cron-monitor-routing-parity.test.ts`
    (Guard 1, #8630) — XOR over {declared monitors} × {monitor_ids ∪ unrouted map}; the move
    satisfies it on both sides. CI runs it via `bash scripts/test-all.sh webplat` (vitest shard).
  - Unrouted-map consumers swept repo-wide: `sentry-monitors-audit.sh` (awk state machine reads the
    map keys dynamically → Class A "declared pending"), the routing-parity guard, the
    reference-gate script, the projection jq, `apply-sentry-infra.yml`, README/ADRs. None hardcode
    `scheduled_integration_suites`; no consumer edit needed.
  - `apps/web-platform/test/server/inngest/function-registry-count.test.ts`
    `NON_INNGEST_MONITORS` lists `scheduled-integration-suites` — stays (the monitor still exists,
    still GHA-fired; the exemption is about executor placement, not routing).
  - `cron-monitors.tf` lines 321–327 comment names schedule/margin/slug only — no pending-routing
    remark to update (unlike #9511, whose monitor comment said "email routing lands with #9493").

### Property List (Phase 0.6b)

1. After the diff, every declared `sentry_cron_monitor` is either in `monitor_ids` or in
   `cron_monitor_alert_unrouted` — the guard stays green with `scheduled_integration_suites` on the
   routed side.
2. `monitor_ids` remains LC_ALL=C sorted with exactly one added element.
3. `alert-reference.json` remains the `jq -S` canonical projection of the plan — exactly one added
   `detectorIds` element, `"2403709"`, in sorted position.
4. After merge + apply, the live `cron-monitor-failure` workflow binds detector `2403709` (the
   post-merge read-back is the proof the route fires).

### Cut List

- **Two-push CI-artifact-only regeneration** (push `.tf` → red `plan_pr` → download artifact →
  commit → push) → the sanctioned route when the detector id is unknown, but the id was already
  read live at plan time (`2403709`), so the local append is one exact line and lands the
  merge-blocker artifact in the first push — precedent #9511 did exactly this. The artifact path
  stays as the mandated fallback if `plan_pr` reds.
- **Full local `terraform plan` + `sentry-alert-projection.jq` regeneration** → needs the Doppler
  `prd_terraform` triplet (verified present on this host: `SENTRY_IAC_AUTH_TOKEN`, `AWS_*`) and a
  live-state plan — heavier and secret-touching; the single-element diff does not need it. Kept as
  the documented third option (README §"Local invocation" + §Drift detection regen recipe).
- **Hand-editing `cron-monitors.tf` / `function-registry-count.test.ts`** → nothing to update; see
  Premise Validation.

### Relevant files

- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` — `local.cron_monitor_alert_unrouted`
  (the `#9855` block + entry, lines 59–63) and `sentry_alert.cron_monitor_failure.monitor_ids`
  (insert between lines 105/106). Header lines 8–15 restate the routing rule and the derivation
  command.
- `apps/web-platform/infra/sentry/alert-reference.json` — `cron-monitor-failure` entry at line 636;
  `detectorIds` multiline array, last element `"2359391"` at line 711.
- `apps/web-platform/infra/sentry/README.md` — §"Adding or removing a cron monitor — the two-PR
  rule (#8630)" (the governing doc), §Drift detection (the regen recipe + the
  "PR round-trip IS the regeneration route" line for credential-free regen).
- `apps/web-platform/test/server/inngest/sentry-cron-monitor-routing-parity.test.ts` — Guard 1
  (XOR routing parity). Do not edit — the file's own fixture rows pin the behavior.
- `scripts/sentry-alert-reference-gate.sh` — the `plan_pr` gate that compares committed
  `alert-reference.json` to the plan projection; on a `detectorIds`-only divergence of
  `cron-monitor-failure` it prints the two-PR-rule hint + the exact `gh run download` remedy.
- `.github/workflows/apply-sentry-infra.yml` — `plan_pr` job runs the gate (~line 397), uploads
  the artifact `sentry-alert-reference-expected-<run-id>` on red (upload step ~line 602–615), and
  the post-merge `apply` job applies the route.
- `apps/web-platform/scripts/sentry-monitors-audit.sh` — Class A partition reads
  `cron_monitor_alert_unrouted` via awk (declared-pending vs live drift); dynamic, no edit.
- `tests/scripts/lib/sentry-alert-projection.jq` — the projection both gate sides share; its
  detector-id floor is WHY the two-PR rule exists. Do not edit.

### Institutional learnings

- `knowledge-base/project/learnings/2026-09-24-routing-59-cron-monitors-every-guard-was-narrower-than-its-name.md`
  — the #8630 class this routing scheme was built against; the guard checks exactly what it
  claims, so move the label, never widen it.
- `knowledge-base/project/learnings/2026-10-08-a-comment-skip-added-in-review-swallowed-the-real-map.md`
  — the unrouted map is data a guard reads; keep the diff to the map entry + comment block,
  nothing else.
- `apps/web-platform/infra/sentry/README.md` line ~290: "Do not 'fix' the apply job to read the
  committed file" — a rule cannot be captured before it is applied (run 34491157462 redded `main`
  on that coupling); this plan never couples the apply to the committed reference.
- ADR-031 (`knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`) + #8630
  amendment — Sentry-as-IaC decisions record; the two-PR rule is its routing corollary.

### Research decisions

- External research: skipped — the whole mechanism is repo-internal and verified against live
  state; nothing external to learn.
- Precedents: PR #9234 (squash `1362aa0a97`, `scheduled-supabase-watchdog`) and PR #9511 (squash
  `0b35762459`, `scheduled_merge_queue_stall_dispatch`) — the only two prior PR-2 routings; this
  plan mirrors #9511's shape minus its measurement/ADR legs (not applicable here).
- Subagent fan-out: this planning context has no agent-spawn tool; research ran in-process against
  the real files and the live org (read-only).

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch; the brief arrived as verified context in the pipeline
invocation and every claim was re-verified against the tree, GitHub, and the live Sentry org. One
refinement vs. the brief's mechanics: the brief framed the CI-artifact download as THE regen path;
precedent #9511 establishes local derivation as the first-push path with the artifact as the
contingency, and the detector id is already known (`2403709`), so the plan adopts the precedent
shape. The issue's checkbox ("Regenerate `alert-reference.json` from the
`sentry-alert-reference-expected-<run>` CI artifact") is preserved as the fallback, not dropped.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. A mis-move either leaves the
  monitor unrouted (status quo: Sentry issue opens, no email) or reds `plan_pr`/`apply-sentry-infra`
  on `infra/sentry` until fixed — an internal gate red, not a product surface. No runtime path, no
  user artifact.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no vector — the diff is a
  routing config for an operator-only email list plus one id in a generated projection file; no
  user data, credentials, or workspace content is read or written.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the diff touches apps/web-platform/infra/ (a sensitive path) only to
  route an operator-only cron monitor to the existing email alert — no user data, auth, billing or
  runtime behaviour.`

## Observability

Required: Files-to-Edit touches `apps/web-platform/infra/` (sensitive-path class). The deliverable
itself IS observability machinery — it wires an existing liveness signal to email.

```yaml
liveness_signal:
  what: "the scheduled-integration-suites Sentry cron monitor check-in (posted by the workflow's final sentry-heartbeat step, nightly 04:30 UTC); after this change a missed or errored check-in emails via sentry_alert.cron_monitor_failure"
  cadence: "nightly ('30 4 * * *'); checkin_margin 1440 min tolerates one wholly dropped daily run"
  alert_target: "email to all active Sentry org members (issue_owners → ActiveMembers fallthrough), throttled to one email per monitor group per ~24 h (frequency_minutes 1441)"
  configured_in: "apps/web-platform/infra/sentry/cron-monitor-alerts.tf (monitor_ids) and cron-monitors.tf (the monitor)"

error_reporting:
  destination: "Sentry issue group per monitor environment (fingerprint crons:{monitor_env.id}); the in-run ci/integration-suites GitHub issue stays the primary channel for run-internal reds"
  fail_loud: "a red suite posts status=error (run 38130672233); a missed run pages 'missed check-in'"

failure_modes:
  - mode: "nightly leg never runs (dropped schedule, pending-eviction)"
    detection: "Sentry monitor 'scheduled-integration-suites' missed check-in"
    alert_route: "sentry_alert.cron_monitor_failure email — this change is what adds that route"
  - mode: "suites run and fail (5/8 red was the first measured case)"
    detection: "error-status check-in + the workflow's own ci/integration-suites GitHub issue"
    alert_route: "GitHub issue (primary) + Sentry issue; email via cron_monitor_failure after this change"
  - mode: "stale committed reference after this PR (only via bypass-merge)"
    detection: "daily scheduled-sentry-alert-drift.yml probe (sentry-alert-live-fidelity.sh) diffs live workflows vs committed alert-reference.json"
    alert_route: "one daily infra-drift issue naming the regeneration remedy"

logs:
  where: "GitHub Actions run logs (apply-sentry-infra.yml, plan_pr); Sentry cron monitor history; workflow detectorIds lastTriggered"
  retention: "GitHub run retention; Sentry issue retention"

discoverability_test:
  command: grep -c 'sentry_cron_monitor.scheduled_integration_suites.id' apps/web-platform/infra/sentry/cron-monitor-alerts.tf
  expected_output: "1"
```

The probe prints `0` pre-change (the label is only an unrouted-map key, which the pattern does not
match) and `1` post-change; the post-merge read-back in Implementation Phase 3 is the live probe.
The command is a single `grep -c` read of the `.tf` — sub-second, verb allowlist `grep`, no
suite-shape tokens.

## Implementation Phases

### Phase 1 — The routing move (`.tf` + generated artifact)

1. `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`: delete the four `#9855` comment lines +
   the entry (lines 59–63 pre-edit):

   ```hcl
    # #9855 — the nightly integration-suites leg's dead-man monitor, added under
    # the two-PR rule: the in-run ci/integration-suites GitHub issue is the
    # primary channel for run-internal reds; the never-ran class (dropped
    # schedule, pending-eviction) is the monitor's alone. Routing it is #9959.
    scheduled_integration_suites = "route after the first measured check-in (#9959)"
   ```

   Leave the three remaining map entries (`scheduled_bot_pr_reaper`,
   `workspaces_luks_verify_web2`, `image_cve_scan`) and their comments untouched.

2. Same file, `sentry_alert.cron_monitor_failure.monitor_ids`: insert

   ```hcl
    sentry_cron_monitor.scheduled_integration_suites.id,
   ```

   between `sentry_cron_monitor.scheduled_inngest_health.id,` and
   `sentry_cron_monitor.scheduled_legal_audit.id,` (LC_ALL=C sorted position; indentation matches
   siblings — `terraform fmt -check` must stay green).

3. `apps/web-platform/infra/sentry/alert-reference.json`: inside the `cron-monitor-failure` entry,
   change the `detectorIds` tail `"2359391"` → `"2359391",` and append `      "2403709"` (6-space
   element indent). The id was read live at plan time: detector `2403709`,
   `type: monitor_check_in_failure`, `workflowIds: []` — the detector this route binds. Verify:

   ```bash
   jq -S . apps/web-platform/infra/sentry/alert-reference.json > /tmp/ref.json \
     && cmp /tmp/ref.json apps/web-platform/infra/sentry/alert-reference.json  # already canonical
   jq '.["cron-monitor-failure"].detectorIds | . == sort' \
     apps/web-platform/infra/sentry/alert-reference.json   # true
   jq '.["cron-monitor-failure"].detectorIds | length' \
     apps/web-platform/infra/sentry/alert-reference.json   # 61
   git diff origin/main...HEAD -- apps/web-platform/infra/sentry/alert-reference.json
   # exactly one added element; any other hunk is a finding, not noise
   ```

### Phase 2 — Local gates, then push

1. Install deps if absent (worktree was created `--no-install`):
   `npm ci --ignore-scripts --prefix apps/web-platform` (or the repo's standard install).
2. `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/sentry-cron-monitor-routing-parity.test.ts`
   — Guard 1 green.
3. `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` — hermetic, no credentials.
4. `bash plugins/soleur/test/c4-count-parity.test.sh` — the routing moves no monitor count; a red
   means a mis-edit.
5. `terraform fmt -check apps/web-platform/infra/sentry/cron-monitor-alerts.tf` → clean.
6. Commit + push. `plan_pr` runs `sentry-alert-reference-gate.sh`; it should be green on the first
   push.
7. **Contingency (only if `plan_pr` reds on the reference gate):** the gate prints the artifact
   name. `gh run download <run-id> -n sentry-alert-reference-expected-<run-id>` then `diff` the
   downloaded `sentry-alert-reference.expected.json` against the local file — only the expected
   `detectorIds` hunk may differ; copy it over
   `apps/web-platform/infra/sentry/alert-reference.json`, commit, push. (7-day artifact retention;
   `gh run rerun <run-id> --failed` regenerates.) Polling for the run is foreground-bounded per
   `hr-monitor-not-run-in-background-for-polling`.

### Phase 3 — Post-merge verification (standing apply path)

1. `apply-sentry-infra.yml` run on the merge commit: green; plan = one in-place update of
   `sentry_alert.cron_monitor_failure` (detectorIds +1), zero destroy, no `[ack-destroy]` needed.
2. Live read-back (README §"Read the live route"): the `cron-monitor-failure` workflow's
   `detectorIds` includes `2403709`:

   ```bash
   doppler run --project soleur --config prd --command '
     curl -s -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN" \
       "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/workflows/" \
       | jq ".[] | select(.name==\"cron-monitor-failure\") | .detectorIds | index(\"2403709\")"'
   ```

   prints an index (non-null). Note: the pre-apply audit inside the same run still reports the
   pre-apply state (README: the audit runs BEFORE the apply).
3. Tick the issue's two checklist boxes via the closing PR (PR body `Closes #9959`).

## Files to Edit

- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` — map entry + comment removal; one
  `monitor_ids` insert.
- `apps/web-platform/infra/sentry/alert-reference.json` — one `detectorIds` element appended.

Glob check: both paths exist on `origin/main`. Deliberately NOT edited: `cron-monitors.tf` (its
comment never mentioned pending routing), `function-registry-count.test.ts` (monitor count and
placement class unchanged), the guard test, the audit script, the projection jq, and every
workflow file.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9959-route-sentry-monitor/tasks.md` (derived from
  this plan).
- `knowledge-base/project/specs/feat-one-shot-9959-route-sentry-monitor/session-state.md`
  (plan-phase record).

## Open Code-Review Overlap

`gh issue list --label code-review --state open` (200 cap) → four sentry-adjacent issues, none
touching this diff: #3829 (new-monitor-type → sentry-scrub gate), #3828 (check-in fan-out
composite action), #3740 (sentry-post-merge-smoke), #2197 (billing refactor with a Sentry
breadcrumb item). No overlap with `cron-monitor-alerts.tf` or `alert-reference.json`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Move `scheduled_integration_suites` from `local.cron_monitor_alert_unrouted` into `sentry_alert.cron_monitor_failure.monitor_ids`" | Phase 1 steps 1–2 / AC-1–AC-3 | mapped |
| 2 | "Regenerate `alert-reference.json` from the `sentry-alert-reference-expected-<run>` CI artifact" | Phase 1 step 3 (local derivation per #9511) + Phase 2 step 7 (artifact path as contingency) / AC-4–AC-5 | mapped |
| 3 | "Until routed: a missed/errored check-in opens a Sentry issue but emails nobody — the in-run `ci/integration-suites` GitHub issue is the primary channel meanwhile" | Overview + Observability `failure_modes` (descriptive bullet, not a task — the route this PR adds) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.tf` unrouted-map removal + `monitor_ids` insert | "Move `scheduled_integration_suites` from `local.cron_monitor_alert_unrouted` into `sentry_alert.cron_monitor_failure.monitor_ids`" | asked |
| `alert-reference.json` regeneration | "Regenerate `alert-reference.json` from the `sentry-alert-reference-expected-<run>` CI artifact" | asked — resolved: local derivation first (id already read live; #9511 precedent), CI-artifact as mandated fallback |
| vitest + audit + c4-parity local gates | — | inferred — justification: precedent #9511's task 2.4; the routing change must not regress the guard, the audit self-test, or count parity |
| Post-merge apply + live `detectorIds` read-back | — | inferred — justification: precedent #9511 Phase 4; the route is live only after apply, so the proof is a post-merge read-back |
| PR body `Closes #9959` + first-line production effect | — | inferred — justification: `wg-use-closes-n-in-pr-body-not-title`; precedent #9511 required the first line to state the production effect of merging |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform/infra/sentry`
- Planned files: 2 (+2 KB spec docs) | Estimated changed lines: ~8
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `grep -c 'sentry_cron_monitor.scheduled_integration_suites.id' apps/web-platform/infra/sentry/cron-monitor-alerts.tf`
  prints `1`, and `grep -n 'scheduled_inngest_health.id\|scheduled_integration_suites.id\|scheduled_legal_audit.id'`
  shows the three in that file order.
- [ ] `grep -c '9959' apps/web-platform/infra/sentry/cron-monitor-alerts.tf` prints `0` (entry +
  comment block fully removed); `grep -c 'cron_monitor_alert_unrouted' apps/web-platform/infra/sentry/cron-monitor-alerts.tf`
  still prints `1` (the map itself stays for the three remaining entries).
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/sentry-cron-monitor-routing-parity.test.ts`
  exits 0 (Guard 1 green: routed, not unrouted, not double-listed).
- [ ] `jq '.["cron-monitor-failure"].detectorIds | index("2403709") != null and . == sort and length == 61'`
  on `apps/web-platform/infra/sentry/alert-reference.json` prints `true`; `jq -S` output is
  byte-identical to the committed file (canonical); `git diff origin/main...HEAD -- <file>` is
  exactly the one added element.
- [ ] `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` and
  `bash plugins/soleur/test/c4-count-parity.test.sh` exit 0.
- [ ] `terraform fmt -check apps/web-platform/infra/sentry/cron-monitor-alerts.tf` exits 0.
- [ ] `git diff --quiet origin/main...HEAD -- apps/web-platform/infra/sentry/cron-monitors.tf`
  exits 0 — the monitor declaration is untouched.
- [ ] The PR's `plan_pr` job is green — `sentry-alert-reference-gate.sh` passes on the committed
  reference (or, on the contingency path, the committed file is byte-identical to the run's
  `sentry-alert-reference-expected-<run-id>` artifact).
- [ ] The PR body's FIRST line states the production effect: merging applies one in-place update
  adding detector `2403709` to the `cron-monitor-failure` Sentry alert workflow; the merge click is
  the authorization. Body contains `Closes #9959`.
- [ ] Post-merge: `apply-sentry-infra.yml` run on the merge commit succeeds with one in-place
  update and zero destroy; the live read-back prints a non-null `index("2403709")`.

## Domain Review

**Domains relevant:** none

No cross-domain implications — infra/tooling routing config. Semantic pass: no marketing content;
no new architectural decision (ADR-031 + #8630 already decided the mechanism — this executes it);
no vendor/procurement change (same Sentry provider, same tier); no UI surface (Files-to-Edit: `.tf`
+ `.json`); no legal document; no sales/finance/support surface. Engineering's "significant infra
change" bar is not met by a single attribute move on an existing resource.

## Infrastructure (IaC)

### Terraform changes

Existing root `apps/web-platform/infra/sentry` (provider pins unchanged). One attribute edit on
`sentry_alert.cron_monitor_failure` (`monitor_ids` +1 element) and one `locals` map entry removed.
No new resource, no new variable, no new secret; `SENTRY_IAC_AUTH_TOKEN` usage unchanged.
`lifecycle.ignore_changes = [environment]` untouched.

### Apply path

The standing `apply-sentry-infra.yml` applies on merge to `main` (full-root plan then apply).
Expected blast radius: one in-place update of one alert workflow — no destroy, no downtime, no
`[ack-destroy]`. Never apply locally (`use_lockfile = false`; README's standing rule).

### Distinctness / drift safeguards

Routing-parity Guard 1 (vitest), the `plan_pr` reference gate (committed projection == plan),
the post-apply live-fidelity probe, and the daily `scheduled-sentry-alert-drift.yml` all stay in
place and unchanged; this PR moves data through them, not around them.

### Vendor-tier reality check

Sentry workflow/detector model unchanged — adding an existing detector to an existing workflow's
`detectorIds` is a standard in-place update, same shape the live org already carries for 60 other
detectors.

## Encryption Posture

Not applicable — no persistent data store introduced and no new cross-component/network
connection (the alert's email action and the Sentry API path already exist).

## Architecture Decision (ADR/C4)

No new ADR — the routing mechanism is ADR-031 + the #8630 amendment's own two-PR rule; this plan
executes it. No C4 edge changes (no new component or integration edge).

## Test Scenarios

- Given the edited `cron-monitor-alerts.tf`, when the routing-parity vitest runs, then Guard 1 is
  green — `integration` layer, `sentry-cron-monitor-routing-parity.test.ts` real-tree row.
- Given a deletion of the new `monitor_ids` element (mutation), when the guard runs, then RED
  naming `scheduled_integration_suites` as unrouted — derived from the guard's row-1/row-3 shape.
- Given a stale unrouted-map entry left behind (mutation: entry kept AND label routed), when the
  guard runs, then RED `in BOTH monitor_ids and cron_monitor_alert_unrouted` — the guard's row-6
  shape, verified in-file.
- Given the regenerated `alert-reference.json`, when `plan_pr` runs
  `sentry-alert-reference-gate.sh`, then PASS (plan projection == committed reference) — the gate's
  own `detectorIds`-only hint names this exact move if it ever reds.
- Given the merge, when `apply-sentry-infra.yml` completes, then the live workflow's
  `detectorIds` contains `2403709` — post-merge read-back, the only evidence the route fires.

## Deepen-Plan Enhancements

**Deepened on:** 2026-10-11 | **Halt gates:** all pass/skipped | **Mode:** in-process (no
agent-spawn tool in this pipeline subagent context; every gate and check ran against real files,
`gh`, and a read-only live Sentry query)

### Gate results

- Phase 4.4 precedent-diff: precedents verified in git history — PR #9234 (`1362aa0a97`) and PR
  #9511 (`0b35762459`), the two prior PR-2 routings; the prescribed edit reuses their shape
  verbatim (map removal + sorted `monitor_ids` insert + single-element `detectorIds` append). Not
  novel.
- Phase 4.45 verify-the-negative (in-process): "no unrouted-map consumer needs an edit" —
  confirmed (repo-wide grep: every reader is dynamic; zero hardcode `scheduled_integration_suites`
  outside `cron-monitor-alerts.tf`); "`cron-monitors.tf` needs no comment update" — confirmed
  (lines 321–327 carry no pending-routing remark); "the monitor emails nobody today" — confirmed
  live (`workflowIds: []`).
- Phase 4.5 network-outage: no trigger tokens; the plan drives no `terraform apply` and the
  Sentry root declares no `provisioner`/`connection` blocks — skipped.
- Phase 4.55 downtime: the apply is an in-place attribute update of one `sentry_alert` — no
  serving surface, no reboot/replace, no DDL — skipped.
- Phase 4.6 user-brand: PASS (`none` + non-empty scope-out on a sensitive-path diff).
- Phase 4.7 observability: PASS — 5-field schema present; `discoverability_test.command` is a
  single `grep -c` on a `.tf` (allowlist verb, <1 s, no suite-shape token).
- Phase 4.8 PAT shapes: clean — no GitHub-write token introduced; the read-only live query used
  the existing `SENTRY_IAC_AUTH_TOKEN` via `doppler run` (no paste, no new secret).
- Phase 4.9 UI: no UI surface — skipped. Phase 4.10 encryption: nothing introduced — skipped.
- Phase 4.11 guard contract: evaluated — the deliverable is routing DATA an existing guard
  checks; it creates or reshapes no guard/gate/lint/hook, so the contract does not attach (same
  disposition as precedent #9511's plan, which carried no section).
- Phase 4.12 scope check: 1 unfenced `## Scope Check`; 3 ask rows all mapped; `Recommendation:`
  present; no `status: BLOCKED`; no unjustified `descoped`/`inferred` row (each inferred row
  carries a justification).

### Quality checks

- `21331e94e3…` is an ancestor of `origin/main` (PR #9947 mergeCommit, fetched); apply run
  38105510428 `success` on that commit; check-in run 38130672233 `Sentry check-in (final)`
  `success`.
- Detector id `2403709` read live via the README's documented read-only pattern — used for the
  local derivation only; the CI gate independently proves the committed reference.
- Literal consistency: `scheduled_integration_suites` (TF label) / `scheduled-integration-suites`
  (monitor slug) / `2403709` (detector id) spelled identically across all sections.
- `#9959` OPEN at plan time; no duplicate `## Scope Check` sections; no new ADR/label/marker
  introduced.

## Context

- Issue: #9959 (checkbox items 1–2 are this PR; `Closes #9959` in the PR body, not the title).
- Follow-up chain: #9855 (monitor declaration) → PR #9947 (squash `21331e94e3`) → #9959 (this PR).
- The unrouted map keeps three entries after this PR: `scheduled_bot_pr_reaper` (#9274),
  `workspaces_luks_verify_web2` (#9372), `image_cve_scan` (#9858) — each its own future PR-2.
- The check-in is `error`-status whenever suites are red — the alert route added here is
  deliberately coarse: email once per ~24 h per monitor group (frequency_minutes 1441, ADR-031's
  no-re-page amendment).

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty/placeholder or lacks the threshold fails
  deepen-plan Phase 4.6 — filled above.
- Do NOT route `monitor_ids` elements that are not `sentry_cron_monitor.<label>.id` literals and
  do NOT hand-sort outside LC_ALL=C — Guard 1 rejects both non-reference elements and stale
  map entries.
- The `detectorIds` array is string-sorted, not numeric-sorted: `"2403709"` lands after
  `"2359391"` — appending at the tail is correct ONLY because it is the string-max element
  (verified at plan time); a future id could sort mid-array.
- The committed `alert-reference.json` must be `jq -S` canonical — a hand-append in the wrong
  order or with wrong indentation still passes `jq` but can fail the gate's byte-compare.
- The pre-apply audit in the merge run still reports the pre-apply state (README §Audit); do not
  read its Class A listing as proof the route failed.
