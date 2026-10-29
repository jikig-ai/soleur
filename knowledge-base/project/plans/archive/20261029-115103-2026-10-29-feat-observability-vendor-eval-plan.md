---
title: Right-size observability spend — Sentry monitor prune + Better Stack ingest cut
feature: feat-observability-vendor-eval
date: 2026-10-29
spec: knowledge-base/project/specs/feat-observability-vendor-eval/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-10-29-observability-vendor-eval-brainstorm.md
issues: [4296, 6590, 6591, 7577]
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
---

# Plan — Right-size observability spend

## Overview

Execute the recorded #4296 re-decision: stay multi-provider, reduce
€156.67/mo observability spend toward ~€55–90/mo by cutting the two measured
drivers — (a) ~67 `sentry_cron_monitor` PAYG seats at $0.78 (#6590, ADR-031
amendment + deep prune) and (b) Better Stack log ingest volume (#7577, Vector
chokepoint). No vendor migration; no transport or wake-path changes.

## Research Insights

**Premise Validation (ran at brainstorm):** #6590, #6591, #7577, #4296 all OPEN;
#4273 OPEN with Path B/C dead; `feat-sentry-monitor-spend` spec (July) already
shipped the PAYG-cap raise ($50→$75) and delete-path fix. No stale premises.

**Property List:** (1) lower monthly bill without capability regression;
(2) every retained detection property still fires; (3) monitor count reflects
live producers; (4) ingest volume reflects what the 19 `logtail_exploration_alert`
rules actually read.

**Cut List:** vendor migration of any kind (cut at brainstorm — ~370–450 files,
~185 TF resources, ~20–38-mo payback); new observability surfaces; emit-path
changes (the ask needs none — `reportSilentFallback`/`postSentryHeartbeat` stay).

**Key file anchors:**
- `apps/web-platform/infra/sentry/cron-monitors.tf` — 67 `sentry_cron_monitor`
  blocks vs ~44 live `postSentryHeartbeat` producers (`server/inngest/functions/cron-*.ts`
  + `_cron-shared.ts:382`) → ~23 orphan candidates.
- `apps/web-platform/infra/vector.toml` — 6 sources (`inngest_journald`,
  `system_journald`, `app_container_journald`, `egress_gw_journald`,
  `host_scripts_journald`, `host_metrics`), 3-stage VRL PII pipeline
  (`pii_scrub_*`, HMAC via `SENTRY_USERID_PEPPER`), `sinks.betterstack` HTTP sink.
- `apps/web-platform/infra/betterstack-logs-alerts.tf` — 19+19
  `logtail_exploration`/`_alert` pairs (the consume-side of the ingest cut).
- `apps/web-platform/scripts/sentry-monitors-audit.sh`,
  `plugins/soleur/lib/heartbeat-live-reconcile.ts` — live-vs-declared diff tools.
- `knowledge-base/engineering/architecture/decisions/ADR-031-*.md` —
  monitor-per-cron policy to amend.
- `knowledge-base/operations/expenses.md:49-50` — Sentry $73.56 / Better Stack
  ~$68 rows to correct post-change.
- `apps/web-platform/infra/uptime-alerts.tf` — 8 `betteruptime_monitor` + 13
  `betteruptime_heartbeat` (NOT in scope — Better Stack heartbeats are cheap
  here and ADR-218 load-bearing).

**Institutional learnings:** sentry-iac-billing (per-seat billing, `.enabled`
drift, probe `GET /api/0/customers/<org>/` before applies); monitor-prune must
preserve "silence-is-undetectable" coverage (#6590's own framing); Better Stack
has NO usage API — volume must be inferred from `betterstack-query.sh` row counts
or invoice deltas.

## Implementation Phases

### Phase 1 — Enumerate, don't guess

1. Run `apps/web-platform/scripts/sentry-monitors-audit.sh` +
   `plugins/soleur/scripts/reconcile-live-heartbeats.ts` to produce the
   live-vs-declared monitor diff. Cross-reference each declared
   `sentry_cron_monitor` slug against `grep -rl "postSentryHeartbeat\|<slug>"`
   producers. Output: `keep` / `orphan-delete` / `needs-verdict` list, written
   to `knowledge-base/project/specs/feat-observability-vendor-eval/monitor-prune-inventory.md`.
2. For `needs-verdict` rows, consult #6591 evidence (has the monitor ever
   caught a real miss?) — prefer deleting monitors that have never fired over
   ones that have. Dead-man/self-watch monitors (the ones whose silence is
   undetectable elsewhere — e.g., watchdog-of-watchdog chain) are KEEP by
   #6590's framing.
3. Enumerate which fields/sources the 19 `logtail_exploration` queries read:
   `grep -oE 'from.*where|SYSLOG_IDENTIFIER|source ==' betterstack-logs-alerts.tf`
   — every ingest cut must map against what alerts consume. Output to
   `knowledge-base/project/specs/feat-observability-vendor-eval/alert-ingest-map.md`.

### Phase 2 — Sentry prune (#6590)

4. Amend ADR-031: add `## Amendment 2026-10-29` section — monitor-per-cron
   policy replaced by "monitor where silence is undetectable elsewhere or
   where the monitor has demonstrated catch value"; new-cron monitors now
   opt-in per risk, not automatic.
5. Delete pruned `sentry_cron_monitor` blocks from
   `apps/web-platform/infra/sentry/cron-monitors.tf`. Commit inventory first
   so deletions map 1:1 to list entries.
6. Apply path: `apply-sentry-infra.yml` handles destroy on main-merge (the
   July spec fixed the `-target` delete path — verify one deletion lands in
   plan output before merging the full prune). Expected: monitor count 67 →
   ~15–20; PAYG ≈ $52 → ~$12–16/mo.

### Phase 3 — Better Stack ingest cut (#7577)

7. `vector.toml`: add a compaction transform for multi-line container logs
   (join continuation lines of `app_container_journald` — the 75%-of-ingest
   producer) before `tag_journald`; keep the 3-stage `pii_scrub_*` pipeline
   AFTER the join so scrubbing still sees full messages.
8. `vector.toml`: reduce `host_metrics` — raise scrape interval and/or filter
   to only the metric families the alert map (Phase 1.3) shows are consumed;
   drop the rest before the sink.
9. `vector validate` in CI (existing gate pattern from the July spec).
   Redeploy via the standard infra-apply path; verify ingest row rate drops
   in `scripts/betterstack-query.sh` over 24–48 h before changing plan tier.
10. Verify the ~$68 Better Stack plan name/tier (ledger row is unverified) and
    downgrade if post-cut volume fits Nano ($30 EU, 40 GB) or a lower PAYG
    shape. Update `expenses.md:50` (and :49 with post-prune Sentry number).

### Phase 4 — Verify and record

11. Coverage regression check: every retained property fires — cron-dark
    detection on at least one kept monitor, `app_health` body-keyword pager,
    redirect-health `follow_redirects=false`, one `logtail_exploration_alert`,
    send-failed pager, incident-mirror → GitHub issue.
12. Comment on #6590/#7577 closing the executed scope; leave #4296 to operator
    closure (verdict comment already posted).

## Files to Edit

- `apps/web-platform/infra/sentry/cron-monitors.tf` — delete pruned blocks
- `apps/web-platform/infra/vector.toml` — compaction transform + host_metrics trim
- `knowledge-base/engineering/architecture/decisions/ADR-031-*.md` — amendment section
- `knowledge-base/operations/expenses.md` — corrected amounts post-change
- `apps/web-platform/infra/uptime-alerts.tf` — ONLY IF a stray Sentry-cron
  reference needs re-homing (audit first; expected: none)

## Files to Create

- `knowledge-base/project/specs/feat-observability-vendor-eval/monitor-prune-inventory.md`
- `knowledge-base/project/specs/feat-observability-vendor-eval/alert-ingest-map.md`

## Scope Check

- Ask → plan mapping: "right-size current vendors" → Phase 2 (Sentry seats) +
  Phase 3 (ingest volume). Both spec FRs (FR2–FR5) map to phases; FR1/FR6 are
  bookkeeping/verification covered by Phase 4.
- Item provenance: every phase traces to spec FRs or the two carrying issues;
  no inferred items.
- Split assessment: single PR is acceptable — two orthogonal tf edits + docs;
  if the prune inventory reveals >40 contested deletions, split prune and
  ingest into separate PRs at work time.

## Domain Review

**Domains relevant:** Engineering, Operations, Finance, Legal (carried forward
from brainstorm `## Domain Assessments`; Product gate = NONE — no UI surface).

### Engineering — reviewed
Emit layer untouched; IaC layer is the entire change. Monitor prune must
preserve "silence-undetectable" coverage; ingest cut must not starve any of the
19 log-alert explorations (Phase 1.3 maps consumers first).

### Operations — reviewed
Verify the unnamed ~$68 Better Stack plan before/after cut; the wake path
(Slack + push + GitHub-issue mirror) is byte-identical throughout — no
Responder seat introduced.

### Finance — reviewed
Target: Sentry ≤ ~$40/mo, Better Stack ≤ ~$40/mo. Both levers are
volume/count-driven, so savings survive user growth until the cron fleet or
log volume grows again — monitor-count governance is the durable fix (ADR-031
amendment).

### Legal — reviewed
No new sub-processor, no residency change, no new processing activity. The
ingest CUT *reduces* data sent to Better Stack (whose Art. 28(3) DPA is still
unexecuted — #7529) — a posture improvement. `vector.toml` PII transforms must
remain after compaction (TR ordering in Phase 3.7); gdpr-gate runs at work
Phase 2 exit per `hr-gdpr-gate-on-regulated-data-surfaces`.

### Product/UX Gate
NONE — no user-facing surface.

## User-Brand Impact

**Threshold:** `single-user incident`. **Artifact:** the observability wake
path during alpha onboarding (1/10 testers). **Vector:** a pruned monitor or
starved alert that silently stops paging during a real incident. **Mitigation:**
Phase 1 enumeration + Phase 4 fire-test before any close.

## Observability

```yaml
liveness_signal:    what=retained sentry_cron_monitor check-ins + betteruptime heartbeats / cadence=per-cron / alert_target=Better Stack policies + GitHub-issue mirror / configured_in=infra/sentry/cron-monitors.tf + uptime-alerts.tf (unchanged paths)
error_reporting:    destination=Sentry (unchanged) + Better Stack log alerts (unchanged) / fail_loud=yes — a monitor that stops checking in pages by construction
failure_modes:
  - mode: "pruned monitor masked a live failure"
    detection: "Phase 1 inventory requires an explicit keep/delete verdict per slug with surviving-signal citation"
    alert_route: "Phase 4 fire-test on one retained monitor + incident mirror"
  - mode: "ingest cut starves a logtail_exploration_alert"
    detection: "alert-ingest-map.md consumer enumeration; post-cut betterstack-query.sh row-rate check"
    alert_route: "monitor_send_failed + workspaces_luks_deadman pager remain armed throughout"
  - mode: "Sentry PAYG cliff re-arms"
    detection: "post-prune count × $0.78 + uptime × $1.00 << $75 cap (AC1 check)"
    alert_route: "Sentry spend notification + expenses.md row"
logs:               where=Better Stack source 2457081 (reduced volume — intended) / retention=unchanged
discoverability_test:
  command: "git grep -c 'resource \"sentry_cron_monitor\"' apps/web-platform/infra/sentry/cron-monitors.tf"
  expected_output: "a single integer (post-prune count, target ≤ 20)"
```

## Architecture Decision (ADR) Gate

**Deliverable in-plan:** ADR-031 amendment (monitor-per-cron → monitored-where-
silence-undetectable) — a reversal/extension of an existing ADR, written into
the same file per the repo's amendment convention. No new substrate or trust
boundary; C4 unchanged (vendor edges are identical).

## Test Scenarios

- `sentry-monitors-audit.sh` post-prune: zero "live-undeclared" and zero
  "declared-but-never-fired-without-verdict" rows.
- `sentry-audit-gate` + `scheduled-sentry-alert-drift`: green post-merge.
- `vector validate`: passes; `betterstack-query.sh` 24-h row-count delta
  shows ≥50% ingest reduction on `app_container_journald`/`host_metrics`.
- Pager fire-test: force one retained heartbeat miss → Better Stack alert →
  GitHub issue via incident mirror (end-to-end, not mocked).

## Acceptance Criteria

- AC1 — Sentry projected invoice ≤ ~$40/mo (base + ≤20 monitors + 4 uptime).
- AC2 — Better Stack projected ≤ ~$40/mo post-ingest-cut.
- AC3 — Zero coverage regressions on retained properties (fire-test pass).
- AC4 — ADR-031 amendment committed; #6590/#7577 comments record execution.
