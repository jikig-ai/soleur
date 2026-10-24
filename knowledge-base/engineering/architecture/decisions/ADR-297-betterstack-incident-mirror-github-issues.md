---
title: "ADR-297: Better Stack incidents mirror to deduplicated GitHub issues via a repo-side watchdog workflow; Responder-tier escalation deferred (operator-reserved); push=true measured on the two inngest heartbeats"
status: accepted
date: 2026-10-24
supersedes: none
amends: none
issue: 10390
related: [10390, 9703, 10853, 10854, 10918, 10584, 6645]
related_adrs: [ADR-260, ADR-248, ADR-222, ADR-204, ADR-117]
tags: [observability, better-stack, alert-routing, github-issues, watchdog, inngest]
brand_survival_threshold: none
---

# ADR-297: Better Stack incidents mirror to deduplicated GitHub issues via a repo-side watchdog workflow

> **Ordinal note — PROVISIONAL.** `297` was the next free ordinal when this
> record was authored (highest on the branch base: ADR-296). It is re-verified
> by `soleur:ship`'s ADR-Ordinal Collision Gate against a freshly-fetched
> `origin/main` at merge time; on a renumber, sweep
> `grep -rn 'ADR-297' knowledge-base/project/{plans,specs}/` in the same edit.

## Status

**Accepted on merge — 2026-10-24 (epic #10390).** The channel is live on merge:
the mirror workflow, its dispatch-table row and its Sentry cron monitor apply
through the ordinary per-merge machinery, so no soak-gated `adopting` state is
carried. The Sentry monitor lands **unrouted** per the two-PR rule (sentry
README §186) — a missed check-in opens a Sentry issue but emails nobody until
the routing follow-up PR; the workflow `::error::`s and files issues
regardless, so the gap is bounded.

## Context

On 2026-10-22 the dedicated-host replace caused the two Better Stack heartbeat
monitors on the Inngest serving path (`soleur-inngest-server-prd`,
`soleur-inngest-consumer-prd`) to miss beats and open incidents — correctly.
Their only delivery channel was an unwatched email inbox (`email = true`,
`call`/`sms`/`push = false`, `policy_id = null` — the Responder-tier escalation
policy is gated on `var.betterstack_paid_tier`, which is unset). What the
operator actually saw were the scheduled-inngest-health watchdog's GitHub
issues (#10853, #10854). Detection was timely; notice was late.

ADR-260 established Slack as the primary wake path and declined the Responder
seat "unless the Slack channel proves insufficient". The wired Slack
integration posts all new incidents to one channel, yet the Oct-22 heartbeat
incidents still went unseen — so the durable fix is a channel whose reading is
already proven: GitHub issues on this repo, the surface the operator provably
watches.

## Decision

1. **A repo-side incident mirror.** `scripts/betterstack-incident-mirror.sh`,
   run by `.github/workflows/scheduled-betterstack-incident-mirror.yml` every
   15 minutes (watchdog-dispatch primary per ADR-248 — eligibility clause 1:
   it watches the paging substrate whose outages include Inngest's own, so it
   cannot be Inngest-scheduled — plus `schedule:` fallback and
   `workflow_dispatch`), reads `GET /api/v2/incidents?resolved=false` and
   heartbeat/monitor `status` with `BETTERSTACK_API_TOKEN_READONLY` (GET-only;
   bearer on curl's stdin config, never argv). For each open incident it files
   or dedupes a `[ci/betterstack-incident]` issue (labels
   `ci/betterstack-incident`, `action-required`, `priority/p1-high`) keyed on a
   `<!-- betterstack-incident id=<n> -->` body marker — never on title alone
   (the #10918 title-confusion class). An incident leaving the open set gets a
   resolved comment; only mirror-filed issues are ever closed. Read failures
   are fail-loud (error Sentry check-in + `::error::`).
2. **Self-watched per convention.** `sentry_cron_monitor.scheduled_betterstack_incident_mirror`
   receives the workflow's terminal `sentry-heartbeat` check-in, so a dead
   mirror pages (the 2026-06-12 detector-cron learning). Unrouted at first
   apply per the two-PR rule; routing is the follow-up.
3. **`push = true` measured on the two inngest heartbeats.** A secondary arm:
   `betteruptime_heartbeat.inngest_prd` and `.inngest_consumer` flip `push` to
   `true` under the #9168 measured-flip convention (one apply measures
   acceptance; a vendor refusal or no-op reverts to `push = false` in the same
   PR). It needs the operator's Better Stack mobile app installed and watched —
   which the plan cannot guarantee — so it is secondary, and the mirror is the
   deliverable.
4. **Responder-tier escalation stays deferred (operator-reserved).** The
   `betteruptime_policy` arm requires the Responder seat ($29–34/mo) the
   operator declined at ADR-260. It is named, not built; the trigger remains
   ADR-260's revisit condition.
5. **The post-merge read lands in `postmerge` + a generic soak verifier.**
   `soleur:postmerge` Phase 3.9 is an advisory point read of the alert
   channels after the deploy verdict (report, never block);
   `scripts/followthroughs/post-deploy-incident-soak.sh` is the generic,
   enrollable time-windowed soak (`earliest=<deploy+Nh>` on a `follow-through`
   tracker). The mirror is the always-on arm; these are the point-read and
   windowed complements, not replacements.

## Alternatives Considered

| Option | Verdict |
|---|---|
| Paid-tier escalation policy (`betteruptime_policy` arm) | Deferred — operator-reserved (money). Requires the Responder seat declined at ADR-260; the revisit condition stands as the trigger. The mirror needs nothing the current tier lacks. |
| `betteruptime_outgoing_webhook` → Slack | Rejected — ADR-260's rejection stands: raw webhook payloads are not Slack-format-compatible. The mirror is a repo-side read, not the rejected webhook route. |
| Mirror folded into `scheduled-inngest-health.yml` or `scheduled-inngest-probe-heartbeat.yml` | Rejected. Both are Inngest-scoped in name, permissions and Sentry-monitor semantics; a generic incident mirror is a different property and would blur the liveness watchdog's failure domain and the feeder's eligibility grant. |
| Extend the wired Slack integration | Cut pending measurement — the basic integration already posts all incidents to one channel (since #9168) and the Oct-22 heartbeat incidents still went unseen. The mirror is built regardless as the durable watched channel. |
| Telemetry (`logtail_exploration_alert`) incident mirroring in the same job | Deferred — a different API surface (`/api/v2/alerts`, not `/api/v2/incidents`); #10584 is the tracker and names this mirror as the pattern to copy. |

## Consequences

- Any open Better Stack incident surfaces as a deduplicated GitHub issue
  within ~15 minutes — the channel observed to work on Oct-22 — with
  auto-resolve comments when the incident clears.
- Incident filing under `github.token` does not recurse: issues are not
  workflow triggers.
- The mirror reads incident metadata only (monitor names, timestamps, causes)
  and projects every printed/field line — heartbeat ping URLs are
  beat-capability-bearing and never echo (public-comment discipline).
- `paused`/`pending` heartbeats are not incidents; manifest-vs-live drift
  stays with the nightly heartbeat-live-reconcile job.
- The `push = true` flip is measured at one apply with a documented revert;
  if the vendor refuses it, nothing else changes.
- `soleur:postmerge` reports the alert-channel state on every merge, and a
  post-deploy soak can be enrolled with one directive line on a tracker.
