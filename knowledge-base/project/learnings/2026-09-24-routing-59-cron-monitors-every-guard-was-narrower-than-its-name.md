---
title: "Routing 59 Sentry cron monitors: the provider could express it, and every guard I added was narrower than its name"
date: 2026-09-24
category: integration-issues
module: apps/web-platform/infra/sentry
tags: [sentry, terraform, jianyuan-sentry, cron-monitors, guards, review, observability]
issues: ["#8630", "#8704"]
pr: 8694
---

# Learning: routing Sentry cron monitors to an alert workflow

## Problem

59 `sentry_cron_monitor` detectors had `workflowIds: []`, so a missed or failed check-in
opened a Sentry issue that emailed nobody (#8630). Five monitors were also muted. The
question was whether `jianyuan/sentry` 0.15.7 could express the link at all.

## Solution

- **The link lives on the ALERT side.** `sentry_alert.monitor_ids` is the workflow's
  `detectorIds`, and `sentry_cron_monitor.id` is the detector id (provider source at
  `v0.15.7`; the vendor's own example binds `sentry_cron_monitor.default.id`). One
  `sentry_alert.cron_monitor_failure` in `cron-monitor-alerts.tf` binds all 59.
- **Verify hop 2 on a live event before building on it.** The latest event of a real cron
  issue carried `evidenceData.detectorId`, and `GET detectors/<id>/` resolved it to the
  monitor with `workflowIds: []`. Note the API field is camelCase `detectorId`; the source
  names it `detector_id`.
- **Mute is per monitor ENVIRONMENT and not provider-expressible.** Every muted monitor is
  routed anyway, so an unmute emails with no further change; the unmute itself is a tracked
  operator write (#8704), not Terraform.
- **The two-PR rule** (declare in PR 1 via `cron_monitor_alert_unrouted`, route in PR 2) exists
  because an id unknown at plan time renders as `null` in `planned_values`; a same-PR route
  would project `null` and turn `main` red after a complete apply (#8050 class). Removal is
  two PRs as well: Terraform orders an update that depends on a destroyed resource AFTER the
  destroy, not before.

## Key Insight

A 12-seat review panel reduced ~44 findings to ONE structural cause: each guard's assembly
was narrower than the property its name claims, and the fixtures were one-of-one, so a
first-member or single-shape implementation passed. The structural-enumeration seat (a MAP
of every path to the sink, not a findings list) named all three guards' gaps in one report:

- the binding gate took its verdict from bash `read` over raw jq `-r` rows, so an id
  containing `\n` split one row into two passing rows; and it skipped every row whose actions
  contained `delete`, which includes a replace;
- Guard 1 took the union of every `monitor_ids = [` line in the file, so a decoy `locals`
  list, a `/* */`-commented element or a `.tf.json` declaration all read as "routed";
- the muted count read `done < <(jq …)`, so a jq error and "no monitor carries isMuted" both
  printed `0`, byte-identical to "checked, none muted".

The fix pattern each time: compute the verdict in ONE language (jq) and hand bash only
numbers; scope a parser to the exact block it certifies; make "could not measure" its own
printed state.

## Session Errors

1. **(Forwarded) The draft plan missed `scripts/sentry-monitor-binding-gate.sh`**, which requires every `sentry_alert` to bind the issue-stream detector — Recovery: deepen-plan's architecture review found it; became Guard 3. **Prevention:** before adding a `sentry_alert` with non-issue-stream `monitor_ids`, grep `scripts/` for every consumer of `monitor_ids` (already in the plan's Sharp Edges).
2. **(Forwarded) `BASELINE_DECLARED_PROBES` ratchet owed a bump** — Recovery: bumped 24→25 with the PLACEMENT/TRUTH/NO SUBSTITUTE comment. **Prevention:** a plan declaring `credentials_required` owns the bump; plan phase already lists it.
3. **(Forwarded) `lint-encryption-posture.py` is ledger-scoped** — Recovery: manual check. **Prevention:** none needed (by design).
4. **Wrong Sentry org slug in a hand-built probe** (`jikigai` → 403; the org is `jikigai-eu`) — Recovery: re-ran with the right slug. **Prevention:** use `$SENTRY_ORG` from Doppler `prd` rather than typing the slug.
5. **The plan-prescribed `issue.category:cron` issue query returned `[]` live** — Recovery: a `Cron failure` title search found the issue. **Prevention:** treat a plan-quoted API query as a claim; probe it once before relying on an empty result.
6. **jq syntax error** (`{slug?}` is not valid object construction) — one-off. **Prevention:** none.
7. **`tail -1` over multiple files errored** — one-off. **Prevention:** none.
8. **`gh issue create` for #8704 hook-denied** (no user-visible consequence named) — Recovery: added `--label meta/machinery`. **Prevention:** the hook works as designed.
9. **A CI-watch Monitor expired silently after 20 min**: its `head -1` over a mixed run list never matched, and a one-off `-L 20` listing hid the `pull_request` runs so I briefly believed they were missing — Recovery: listed per workflow. **Prevention:** poll per `--workflow`, match every terminal state, and never conclude "no run" from a truncated cross-workflow list.
10. **The new rule shipped with `frequency_minutes = 1440`, the same dedup key as `anthropic_credit_exhausted`** (copied from the #8505 shape; the test pinning that rule's frequency uniqueness read only `issue-alerts.tf`) — Recovery: moved to 1441, widened the test to every sentry `*.tf`. Measuring the premise afterwards showed two groups of three LIVE rules already share such a key (created on the legacy API), so the POST-time dedup the convention guards against is itself unmeasured on the workflows endpoint; the comments were softened to say so. **Prevention:** a new `sentry_alert` picks an unused `frequency_minutes` (sentry README); a uniqueness test must read the whole root.
11. **Three guards failed open** (newline split, replace skip, decoys, fail-open muted count) — Recovery: fixed inline with RED rows and mutation proofs. **Prevention:** run the structural-enumeration seat on every guard-shaped PR (review/SKILL.md already prescribes it).
12. **I wrote an unmeasured Terraform ordering claim into the README** ("the alert update is ordered before the destroy"; Terraform does the reverse) — Recovery: removal became two PRs. **Prevention:** existing work/SKILL.md rule — a platform-semantics claim is a measurement not yet taken.
13. **The plan's observability block claimed `lastTriggered` is read; no code reads it** — Recovery: rewrote it as configuration-only liveness plus a README read recipe; DC-5 records the residual. **Prevention:** the observability reviewer's layer-citation check caught it.
14. **AC10 was unsatisfiable as written** — its grep matched the plan quoting its own search phrase — Recovery: amended to exclude `knowledge-base/project/plans`. **Prevention:** routed to plan-sharp-edges (an AC sweep must exclude the file that defines it).
15. **A fidelity suite ran past the 120 s foreground timeout** and was moved to the background — one-off. **Prevention:** run suites known to exceed 2 min with `run_in_background`.
16. **Infra Validation on `ca83c8edf0` cancelled at its 27-minute cap on both attempts** — pre-existing, tracked by #8688. **Prevention:** #8688.

## Tags

category: integration-issues
module: apps/web-platform/infra/sentry
