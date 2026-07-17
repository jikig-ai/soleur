---
title: "fix(observability): host_name telemetry mislabel — web-1 self-labels soleur-inngest-prd"
issue: 6616
branch: feat-one-shot-6616-host-name-telemetry-mislabel
date: 2026-07-17
type: fix
lane: single-domain
brand_survival_threshold: aggregate pattern
milestone: "Post-MVP / Later"
status: draft
---

# 🐛 fix(observability): `host_name` telemetry mislabel — web-1 self-labels `soleur-inngest-prd`

Ref #6616. Surfaced by #6594 (CLOSED, superseded by #6613 MERGED); poisons attributions built on `host_name`.

## Overview

A **web** host emits its Better Stack Logs telemetry (source 2457081) stamped
`host_name = "soleur-inngest-prd"`, colliding with the dedicated Inngest host on the sole
per-host discriminator. #6594 recorded the tell: gate rows carry **`host = soleur-web-platform`
AND `host_name = soleur-inngest-prd`** simultaneously. `host` is Vector's auto-derived OS
hostname (correct); `host_name` is the Vector-injected literal (wrong). The mislabeled host is
**web-1** — the only web host shipping telemetry (web-2 is dark: 0 lines/24h per the
2026-07-16 web-2-retire brainstorm).

**The premise in the issue body is stale in its remedy, correct in its symptom.** The issue
proposes "make `host_name` derive from the actual host identity (not a static literal)." That
fix **already shipped** in #6396 / PR #6401 (`c749e4e6a`): `vector.toml` carries an
`@@HOST_NAME@@` sentinel rendered per-host from the Terraform-injected `SOLEUR_HOST_NAME`
(`server.tf:225` → `soleur-web-platform` / `soleur-web-2`), and the fresh-host bootstrap
renders it correctly (`soleur-host-bootstrap.sh:324`). **The templating code is not the bug.**

The bug is **create-time-render drift on a long-lived running host** — the identical class the
C4 model already documents for the #6425/#6594 tunnel-connector coin-flip (`model.c4:178`: "a
construction-time gate presented as a runtime precondition — it governs only future fresh
hosts"). web-1 predates #6344 (which gated co-located Inngest behind `web_colocate_inngest`,
default false) and #6396/ADR-100 (dedicated Inngest host). It booted in the co-located-Inngest
era, so it runs an **inngest-owned `vector.service`** whose config was `sed`-rendered
`host_name=soleur-inngest-prd` (`inngest-bootstrap.sh:714`, unit `EnvironmentFile=
/etc/default/inngest-server`). Because `hcloud_server.web` carries
`lifecycle { ignore_changes = [user_data, …] }` (`server.tf:255`), web-1 **never re-ran
cloud-init** to pick up #6396's per-host name — and even a re-run of the web-install path would
**skip** it, by design, while the inngest-owned unit exists (`soleur-host-bootstrap.sh:348-357`).

**Correcting web-1's running label is impossible in this PR.** It requires an immutable
redeploy (recreate) — SSH edits are forbidden (`hr-no-ssh-fallback-in-runbooks`,
`hr-prod-host-config-change-immutable-redeploy`) — and there is **no `web-1-recreate` dispatch
target** (`apply-web-platform-infra.yml:91-104`), with recreate itself blocked (cx33 unorderable
in all 3 EU DCs; ADR-119 §(e); sole prod host + plaintext `/workspaces` volume). So this plan
does **not** attempt the physical relabel. It delivers what is achievable and brand-safe now:

1. **Diagnose from live data** (not code-reading): a read-only Better Stack ClickHouse query that
   pins exactly which `host` values wear `host_name=soleur-inngest-prd`, confirming the web-1
   collision before any conclusion is frozen.
2. **Make the mislabel self-detecting**: a standing cross-label alarm (GH-cron poller via
   `betterstack-query.sh`, the zot-restart-loop pattern) that FIRES when `host_name` is emitted by
   more than one distinct `host` — turning a silently-poisoned attribution surface into a paged one.
3. **Correct the attribution record**: fix the C4 overclaim (`model.c4:404`), add a learning, and
   re-derive the `host_name`-based readings the issue flags as suspect.
4. **Enroll the deferred physical relabel** as a follow-through so it rides the next web-1
   recreate (GA blue-green / ADR-119 host-replaceability work) instead of being lost to memory.

## Research Reconciliation — Spec vs. Codebase

| Premise (issue #6616 body) | Codebase reality (measured) | Plan response |
|---|---|---|
| "Likely cause: `host_name` is a `sed`-rendered Vector literal (#6396) not re-templated per host" | #6396/PR #6401 **already** re-templated it per-host for FRESH hosts (`vector.toml:374,389` `@@HOST_NAME@@`; `server.tf:225`; `soleur-host-bootstrap.sh:324`). The `sed`-literal path now renders **only** the dedicated Inngest host (`inngest-bootstrap.sh:714`) — correct. | Do NOT re-touch templating. Reframe cause as **create-time-render drift on the running pre-#6396 web-1 host**. |
| "Fix: make `host_name` derive from actual host identity, then re-audit" | The derive-from-identity fix is merged; the residual is a running host that predates it and cannot re-run cloud-init (`ignore_changes=[user_data]`, `server.tf:255`). | Diagnose + detect + correct-record + enroll deferred recreate. No code templating change. |
| "explains the `host=…web-platform` / `host_name=…inngest-prd` conflict #6594 flagged as UNVERIFIED" | **Confirmed as the mechanism.** `host` = Vector auto OS-hostname (`soleur-web-platform`, correct); `host_name` = Vector literal (`soleur-inngest-prd`, stale). Gate rows (`ci-deploy`, `infra-config-apply`) originate on web-1 (`hooks.json.tmpl`; `vector.toml:141-146` Source 4). | Phase 0 query confirms live before freezing; detector encodes the invariant. |
| "#6425's reading that the false `inngest-down` alarms came from web-2 … should be re-derived once the label is fixed" | #6425's attribution was via **Cloudflare connector colo census** (`model.c4:178`; #6425 body), **NOT** `host_name` telemetry (web-2 ships 0 lines). It is **unaffected** by this mislabel and stands. | Re-derivation = document that #6425 did not depend on `host_name`; the suspect readings are any that treat `host_name=soleur-inngest-prd` rows as "the dedicated Inngest host." |
| #6396 status | PR #6401 MERGED. | — |
| #6594 / #6613 status | #6594 CLOSED; #6613 MERGED. | Cite as provenance only. |

**Premise Validation note:** All four referenced issues were probed (`gh issue/pr view`). #6396's
remedy is already implemented, so this plan's shape is **remediation of a running-host drift +
observability + record-correction**, not a templating code change. No external premise remained
that would re-shape the plan beyond this reframe.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — Better Stack Logs is a
management-plane surface; `app.soleur.ai` is a direct CF-proxied A-record to web-1
(`dns.tf:16`) and never traverses this telemetry path. The user-reaching risk is **indirect and
diagnostic**: during a real web-1 incident, operators/agents reading `host_name` attribute
web-1's signal to the (healthy) dedicated Inngest host — or miss a genuine web-1 problem filed
under `soleur-inngest-prd` — and remediate the wrong host. The sole serving host being the one
that lies makes a mis-routed remediation the acute failure mode.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — no new data surface;
`host_name`/`host` are infra identity labels, journald + host_metrics are already PII-scrubbed
(`vector.toml` `pii_scrub_*`). The detector reads telemetry read-only via an existing
Doppler-scoped ClickHouse connection; all untrusted decoded fields pass `strip_log_injection`
before any `::error::`/issue-body echo (zot-alarm precedent).

**Brand-survival threshold:** `aggregate pattern` — the harm is a *pattern* of poisoned
attribution across analyses ("every attribution built on `host_name` is suspect"), not a
single user's data/money/workflow. No per-PR CPO sign-off; the standing detector is the
structural mitigation.

## Hypotheses (diagnosis-first — the fix does not begin until H1 is confirmed live)

Per `2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`: the
deciding datum is which physical `host` emits `host_name=soleur-inngest-prd` in source 2457081.
That datum is in Better Stack, not the repo. Code-reading (below) makes H1 the overwhelming
favorite but **cannot** confirm it — Phase 0 runs the query.

| # | Hypothesis | Status (repo evidence) | Discriminator (Phase 0 query) |
|---|---|---|---|
| H1 | web-1's pre-#6396 inngest-owned `vector.service` stamps all its rows (incl. gate rows) `soleur-inngest-prd`; two distinct hosts collapse on that label. | **Strongly supported, not confirmed** — `inngest-bootstrap.sh:714`, `server.tf:255`, `soleur-host-bootstrap.sh:348-357`, #6594 body, git log #6344/#6396. | `≥2` distinct `host` values carry `host_name='soleur-inngest-prd'`, one of them a web hostname. |
| H2 | The `host=…web-platform / host_name=…inngest-prd` pairing is a **misread** of source-name vs discriminator (no real mislabel). | **Weakened** — `host` is not the source name; source 2457081 is named `soleur-inngest-vector-prd` (`inngest.tf:369`), and Vector does not set `.host`, so `host` is the auto OS-hostname. | Exactly `1` `host` per `host_name` → premise stale, re-scope to record-only. |
| H3 | web-2 (not web-1) is the mislabeled emitter. | **Refuted** — web-2 ships 0 lines/24h (web-2-retire brainstorm, live-measured). | web-2's OS hostname absent from source 2457081 rows. |

If Phase 0 returns H2 (single host per label), **STOP the code changes** and reduce this PR to a
record-correction (the detector and C4 note still ship, but the "web-1 collision" framing is
struck). Do not build the detector's apparatus on an unconfirmed collision.

## Implementation Phases

### Phase 0 — Ground-truth diagnosis (read-only, no prod write)
- Run the cross-label query and record its output verbatim into the spec's `session-state.md`
  (and summarized into a durable artifact `ship` reads for the PR body — never author the PR body
  directly, per the PR-body Sharp Edge):
  ```bash
  doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh "
    SELECT JSONExtractString(raw,'host_name') AS host_name,
           JSONExtractString(raw,'host')      AS host,
           count() AS n
    FROM (
      SELECT raw FROM remote(\$BS_TABLE)
      UNION ALL
      SELECT raw FROM s3Cluster(primary, \$BS_TABLE_S3)
    )
    WHERE dt > now() - INTERVAL 24 HOUR
    GROUP BY host_name, host
    ORDER BY host_name, n DESC
    FORMAT JSONEachRow"
  ```
  (Include the archive arm — the hot window is ~40 min; `betterstack-query.sh:74-82`.)
- Verdict rule (deterministic, `hr-no-dashboard-eyeball-pull-data-yourself`): if any `host_name`
  value is emitted by `≥2` distinct `host` values → **H1 confirmed**, proceed. If the query errors
  or creds are unset → this is a probe fault, re-run wrapped in `doppler run` (NOT "no access");
  do not proceed on a failed probe. If `1:1` throughout → **H2**, branch to record-only scope.
- Pin the exact web `host` value(s) wearing `soleur-inngest-prd` — the detector's expected-good
  map is derived from this measured set, not from the plan author's recollection.

### Phase 1 — Standing cross-label alarm (RED → GREEN)
- `scripts/hostname-mislabel-alarm.sh` — a continuous poller modeled on
  `scripts/zot-restart-loop-alarm.sh`. Queries source 2457081 over a WINDOW, builds the
  `host_name → {distinct host}` map, and classifies:
  - **FIRE (exit 1):** any `host_name` emitted by `≥2` distinct `host` values (the cross-label
    collision), OR a `host_name='soleur-inngest-prd'` row whose `host` is not the single expected
    Inngest OS-hostname (pinned from Phase 0). Opens/updates a deduped `action-required` issue
    `[ci/hostname-mislabel]` with the decoded map.
  - **GREEN (exit 0):** every `host_name` maps to exactly one `host` → auto-close the issue.
  - **TRANSIENT (exit 2):** query fault / creds unset / control-marker query also empty (Better
    Stack unreachable) → NO issue; the workflow emits an ERRORED Sentry check-in.
  - **PRODUCER-SILENT (exit 3):** control marker returns rows (BS reachable) but the window is
    empty → the source went dark; open `[ci/hostname-telemetry-silent]`.
  - Untrusted decoded fields → `strip_log_injection` before any `::error::`/`$GITHUB_OUTPUT`/issue
    echo. Exit code is DATA captured to `$GITHUB_OUTPUT`; the step never `exit 1`s (never
    self-darks the final Sentry check-in). No `github.event.*` inputs.
- `scripts/hostname-mislabel-alarm.test.sh` — synthesized-fixture tests (`cq-test-fixtures-
  synthesized-only`) for each exit class: 1:1 map → GREEN; web host wearing inngest label → FIRE;
  creds-unset → TRANSIENT; empty-window-with-control → PRODUCER-SILENT; log-injection payload in a
  decoded `host` value → sanitized. Write these BEFORE the script body (`cq-write-failing-tests-before`).

### Phase 2 — Scheduled workflow + Sentry self-liveness (IaC)
- `.github/workflows/scheduled-hostname-mislabel.yml` — mirrors `scheduled-zot-restart-loop.yml`
  (probe → classify → dedup-issue → Sentry-heartbeat). Include the
  `gate-override: new-scheduled-cron-prefer-inngest` header with the same ADR-033 I7 / credential-
  heavy-bash-cron justification (this is a `betterstack-query.sh` ClickHouse read + `gh issue`).
  `MONITOR_SLUG` = `scheduled-hostname-mislabel`; `secrets:` pass `BETTERSTACK_QUERY_{HOST,
  USERNAME,PASSWORD}` from Doppler `prd_terraform`. Cadence 30 min (window-bound detection, per zot).
- `apps/web-platform/infra/sentry/cron-monitors.tf` — add `resource "sentry_cron_monitor"
  "scheduled_hostname_mislabel"` (slug = workflow filename sans `.yml`), so a DARK alarm pages.
  Auto-applies on merge via `apply-sentry-infra.yml` (full-root, `paths: infra/sentry/**`).

### Phase 3 — Attribution correction (docs / C4 / learning)
- `model.c4:404` (`hetzner -> betterstack`): correct the overclaim "every web host ships logs
  post-ADR-100 (#6396)". Add the create-time-drift caveat: web-1 predates #6396 and, under
  `ignore_changes=[user_data]`, still ships as `host_name=soleur-inngest-prd` until its next
  recreate — so source 2457081 currently has a `host_name` collision (web-1 + the dedicated
  Inngest host). Mirror the `model.c4:178` connector-caveat style. Reconcile with `model.c4:182`
  (web-1 can-never-re-run-cloud-init note) and `:266-268` / `:403` (source-2457081 collision).
- Run the C4 syntax + render tests (`apps/web-platform/test/c4-code-syntax.test.ts`,
  `c4-render.test.ts`). No new elements/views (existing `hetzner`/`inngest`/`betterstack` cover it).
- New learning `knowledge-base/project/learnings/<topic>.md` (author picks date at write time, no
  hardcoded filename): the create-time-render-drift class (`host_name` is a boot-time render, not a
  runtime-guaranteed discriminator), the web-1 mislabel, and the standing-detector remedy. Note the
  #6425 re-derivation: its false-alarm attribution used the connector census, NOT `host_name`, so it
  is unaffected; the suspect readings are any that treat `soleur-inngest-prd` rows as the dedicated
  Inngest host's.

### Phase 4 — Enroll the deferred physical relabel (follow-through)
- The running-host relabel rides the next **web-1 recreate** (a fresh `-replace` with
  `web_colocate_inngest=false` has no pre-existing inngest unit → the skip-guard does not bite →
  #6396's per-host name installs). That recreate is blocked today (cx33 unorderable; ADR-119 §(e);
  ADR-068 §(c) blue-green prereqs). Do NOT open a redundant tracking issue for the recreate itself
  — it is already the GA host-replaceability work.
- Add a **soak-gated follow-through** so closure is automated (`followthrough-convention.md`):
  `scripts/followthroughs/hostname-mislabel-web1-6616.sh` — exit 0 only when source 2457081 shows
  `host_name=soleur-inngest-prd` emitted by exactly ONE `host` (the dedicated Inngest node) over the
  window; TRANSIENT on probe fault; require a positive liveness marker before treating a zero-count
  as PASS (`#5934` vacuous-pass guard). Tracker directive
  `<!-- soleur:followthrough script=scripts/followthroughs/hostname-mislabel-web1-6616.sh
  earliest=<web-1-recreate-date, unknown → far-future placeholder or the GA-window issue> secrets=
  BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->` + label
  `follow-through`. Wire the `secrets=` into `.github/workflows/scheduled-followthrough-sweeper.yml`
  if not already present.
- Because the `earliest` date is not yet known (recreate is blocked), attach the follow-through to
  the existing GA host-replaceability tracker rather than inventing a date; the sweeper skips until
  `earliest`. (Confirm at deepen-plan which open issue is the correct GA-recreate home.)

## Files to Create
- `scripts/hostname-mislabel-alarm.sh`
- `scripts/hostname-mislabel-alarm.test.sh`
- `.github/workflows/scheduled-hostname-mislabel.yml`
- `scripts/followthroughs/hostname-mislabel-web1-6616.sh`
- `knowledge-base/project/learnings/<date>-host-name-create-time-render-drift-web1-mislabel.md` (date at write time)

## Files to Edit
- `apps/web-platform/infra/sentry/cron-monitors.tf` — add `sentry_cron_monitor.scheduled_hostname_mislabel`
- `knowledge-base/engineering/architecture/diagrams/model.c4` — correct `:404` overclaim + collision note
- `.github/workflows/scheduled-followthrough-sweeper.yml` — add `secrets=` if the query creds are not already wired
- `knowledge-base/project/specs/feat-one-shot-6616-host-name-telemetry-mislabel/session-state.md` — Phase 0 query output (diagnosis record)

**Explicitly NOT edited:** `apps/web-platform/infra/vector.toml`, `soleur-host-bootstrap.sh`,
`inngest-bootstrap.sh`, `server.tf` — the templating is already correct (#6396); touching it would
be a no-op change that risks the AC22 lockstep guard.

## Open Code-Review Overlap

None. (Checked all planned paths against 61 open `code-review` issues via
`jq --arg path … contains`; zero matches.)

## Acceptance Criteria

### Pre-merge (PR)
1. `scripts/hostname-mislabel-alarm.test.sh` passes all 5 exit-class cases (GREEN/FIRE/TRANSIENT/
   PRODUCER-SILENT/log-injection-sanitized); run via the repo's actual runner (verify
   `package.json`/existing `*.test.sh` convention — these are bash `.test.sh`, not a JS runner).
2. `scripts/hostname-mislabel-alarm.sh` FIRE path opens exactly one deduped `[ci/hostname-mislabel]`
   issue body containing the decoded `host_name → {host}` map; GREEN auto-closes it (asserted in test).
3. `.github/workflows/scheduled-hostname-mislabel.yml` validates: `actionlint` (workflow YAML) +
   `bash -c` on each extracted `run:` snippet (NOT `bash -n` on the `.yml`). Carries the
   `gate-override: new-scheduled-cron-prefer-inngest` header. The checker step never `exit 1`s
   (exit code captured to `$GITHUB_OUTPUT`).
4. `apps/web-platform/infra/sentry/cron-monitors.tf` contains
   `resource "sentry_cron_monitor" "scheduled_hostname_mislabel"` with `slug`/`name` matching the
   workflow's `MONITOR_SLUG`; `terraform validate` (or the repo's sentry-infra lint) passes.
5. `model.c4` edit: `c4-code-syntax.test.ts` + `c4-render.test.ts` green; `:404` no longer asserts
   "every web host ships logs post-ADR-100" without the create-time-drift caveat (grep the caveat
   marker phrase present ≥1; anchor on a punctuation-free substring, `cq-assert-anchor-not-bare-token`).
6. Learning file exists under `knowledge-base/project/learnings/`; every `knowledge-base/` path it
   cites resolves (`grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' | xargs -I{} test -f {}`).
7. `scripts/followthroughs/hostname-mislabel-web1-6616.sh` exists, exits TRANSIENT (not PASS) on
   probe fault, and requires a positive liveness marker before PASS (vacuous-pass guard).
8. PR body uses **`Ref #6616`**, not `Closes` (the physical relabel is deferred; do not auto-close
   at merge — `wg-use-closes-n-in-pr-body-not-title-to` + the ops-remediation Sharp Edge).

### Post-merge (operator / automated)
9. `apply-sentry-infra.yml` applies the new `sentry_cron_monitor` on merge (auto; full-root paths
   filter). Verify the monitor exists via the Sentry API read (automatable; `hr-no-dashboard-eyeball`).
10. First scheduled run of `scheduled-hostname-mislabel.yml` reaches a terminal classification and
    the Sentry check-in lands GREEN (self-liveness proven). Confirm via `gh run list`.
11. The FIRE issue it opens on the live web-1 collision (expected until web-1 recreate) is the
    signal, not a regression — annotate it as the tracked-deferred state, linked to the GA-recreate
    follow-through. `Ref #6616` closes when the follow-through soak passes post-recreate.

## Domain Review

**Domains relevant:** Engineering (infra / observability).

### Engineering (CTO / platform-strategist)
**Status:** carried forward from repo research (headless pipeline; no live leader spawn).
**Assessment:** Pure infra/observability, no UI, no data-model change. The core call — *do not
attempt the running-host relabel; defer to the (independently-blocked) web-1 recreate and ship a
standing detector + record correction instead* — is consistent with `hr-prod-host-config-change-
immutable-redeploy`, `hr-no-ssh-fallback-in-runbooks`, ADR-119 §(e), and the web-2-retire
brainstorm's finding that recreate is the only quiesce mechanism. Detector follows the established
zot-restart-loop / connector-census precedent. deepen-plan should run the precedent-diff gate
(Phase 4.4) against `scripts/zot-restart-loop-alarm.sh` and `scheduled-zot-restart-loop.yml`.

### Product/UX Gate
**Tier:** none — no user-facing surface (no `components/**`, `app/**/page.tsx`, or UI-surface file
in Files lists). Better Stack is management-plane. Skipped.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/sentry/cron-monitors.tf` — one new `sentry_cron_monitor` for the
  detector's self-liveness. Providers unchanged (`jianyuan/sentry`, existing pins). No new
  sensitive variables — `BETTERSTACK_QUERY_*` already live in Doppler `prd_terraform`; the workflow
  reads them at run time, not Terraform.

### Apply path
- **(a) auto-apply on merge** — `apply-sentry-infra.yml` fires on push to main touching
  `infra/sentry/**` (full-root plan, #6589). No `-target`, no operator step. Zero downtime (adds a
  monitor resource; no host touched).

### Distinctness / drift safeguards
- `dev != prd`: Sentry infra is prd-only (org `jikigai-eu`). No `lifecycle.ignore_changes` needed.
- No secret value lands in `terraform.tfstate` (the monitor resource carries no secret).

### Vendor-tier reality check
- Sentry cron monitors are within the existing paid tier already provisioning ~8 monitors
  (`cron-monitors.tf`); adding one is in-budget. No new tier gate.

## Observability

```yaml
liveness_signal:
  what: scheduled-hostname-mislabel.yml completes a classification every 30 min and check-ins to Sentry
  cadence: "*/30"
  alert_target: sentry_cron_monitor.scheduled_hostname_mislabel (missed check-in opens a Sentry issue)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf + .github/workflows/scheduled-hostname-mislabel.yml
error_reporting:
  destination: Sentry ERRORED check-in on TRANSIENT (probe fault); action-required GitHub issue on FIRE/PRODUCER-SILENT
  fail_loud: true  # exit code is DATA; a probe fault escalates as a Sentry monitor problem, never a silent pass
failure_modes:
  - mode: web host wearing another host's host_name (the #6616 collision)
    detection: hostname-mislabel-alarm.sh — host_name emitted by >=2 distinct `host` values (in-source telemetry probe)
    alert_route: "[ci/hostname-mislabel] action-required issue"
  - mode: source 2457081 goes dark (producer-silent)
    detection: control-marker query returns rows but the window is empty
    alert_route: "[ci/hostname-telemetry-silent] action-required issue"
  - mode: the alarm itself goes dark
    detection: missed Sentry cron check-in
    alert_route: Sentry issue-alert (no-SSH paging path)
logs:
  where: GitHub Actions run logs + the deduped issue body (decoded, strip_log_injection'd)
  retention: GH Actions default; Better Stack source 2457081 (queried, not written by the alarm)
discoverability_test:
  command: "doppler run -p soleur -c prd_terraform -- scripts/hostname-mislabel-alarm.sh; echo exit=$?"
  expected_output: "exit=1 (FIRE) while web-1 carries the stale label; exit=0 (GREEN) after web-1 recreate — NO ssh"
```

### Affected-surface note (2.9.2)
web-1's Vector unit is a blind surface (no SSH). The detector's discriminating fields — `host`
(auto OS identity) **and** `host_name` (Vector label) in a single query — discriminate ALL
competing hypotheses (H1 collision vs H2 misread vs H3 web-2) from one event stream, satisfying the
in-surface-probe requirement.

## Architecture Decision (ADR/C4)

**Detection fires:** a new cross-cutting invariant every telemetry consumer must honor —
"`host_name` in source 2457081 is a create-time render, not a runtime-guaranteed 1:1 discriminator;
treat `host_name=soleur-inngest-prd` as suspect until every emitting host is post-#6396-born."

### ADR
- **No new ADR; no ADR amendment required.** This is remediation *within* ADR-100/#6396/ADR-119,
  not a new decision — the same disposition the #6425/#6594 connector-drift took (recorded as a C4
  caveat, not a new ADR). The invariant is captured in the C4 prose + the new learning.

### C4 views
- **Edit `model.c4` directly** (workflow-committed, not deferred). Correct `:404`
  (`hetzner -> betterstack`) overclaim and add the create-time-drift + collision caveat; reconcile
  `:182`, `:266-268`, `:403`. **C4 completeness enumeration** (all three `.c4` files read):
  - external human actors: none new (operator/founder already modeled; they *read* the telemetry).
  - external systems / vendors: **Better Stack** (`betterstack`, `model.c4:266`) — already modeled;
    source 2457081 collision is a description correction, not a new system.
  - containers / data stores: `hetzner` web hosts + `inngest` host — already modeled; no new store.
  - actor↔surface access relationships: the `hetzner -> betterstack` and `inngest -> betterstack`
    edges — already present; only their descriptions change. **No new element, tag, or `view
    include` line** → `views.c4` unchanged. "No new C4 elements" is asserted against this
    enumeration, not a bare grep.

### Sequencing
- The C4 correction is true *now* (web-1 is mislabeled now); it ships in this PR. The "collision
  resolved" state is soak-gated on the deferred web-1 recreate (Phase 4 follow-through).

## Test Scenarios
- Detector unit tests (Phase 1): 5 exit classes over synthesized ClickHouse-JSON fixtures.
- Workflow lint: `actionlint` + per-`run:`-snippet `bash -c`.
- Sentry IaC: `terraform validate` / repo sentry-infra lint; monitor slug ↔ workflow `MONITOR_SLUG`.
- C4: `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- Follow-through: dry-run `hostname-mislabel-web1-6616.sh` asserts TRANSIENT on creds-unset and
  vacuous-pass-guard behavior.

## Sharp Edges
- **The `## User-Brand Impact` section must be non-placeholder** — an empty/`TBD` section fails
  `deepen-plan` Phase 4.6. It is filled above (threshold `aggregate pattern`).
- **Do not attempt to fix web-1's running config.** No SSH (`hr-no-ssh-fallback-in-runbooks`); no
  `web-1-recreate` dispatch target exists; recreate is blocked (cx33 unorderable, ADR-119). Any
  phase that "just re-runs the bootstrap" is wrong — the skip-guard (`soleur-host-bootstrap.sh:
  348-357`) refuses while the inngest unit exists. The relabel rides a future fresh `-replace`.
- **Do not touch the templating (`vector.toml`/`server.tf:225`/bootstrap `sed`).** It is already
  correct (#6396); a no-op change risks the AC22 lockstep guard
  (`soleur-host-bootstrap-observability.test.sh`).
- **PR-body record:** the diagnosis + deferral record must be routed through `ship` (the sole
  PR-body author) via a durable `specs/…` artifact — `work`/`plan` cannot author the PR body. For
  operator visibility, the deferred relabel lives as an `action-required` issue, not a PR-body block.
- **`Ref #6616`, not `Closes`** — auto-close at merge would falsely mark the mislabel resolved
  before the (deferred) web-1 recreate.
- **Detector map cardinality, not a hardcoded web hostname** — key the FIRE on "`host_name` emitted
  by ≥2 distinct `host`", pinning the single legitimate `soleur-inngest-prd`↔inngest-host pairing
  from the Phase-0 measured set. A hardcoded `soleur-web-2` misses future web-N hosts.

## Non-Goals / Deferred
- Physical relabel of web-1 → deferred to the next web-1 recreate (GA blue-green / ADR-119
  host-replaceability). Enrolled as a soak follow-through (Phase 4). No redundant tracking issue.
- Changing the per-host templating (already shipped in #6396).
- web-2 (dark, being retired per the 2026-07-16 web-2-retire brainstorm) — out of scope; it emits
  nothing to mislabel.
