---
title: "Tasks — fix(observability): host_name telemetry mislabel (#6616)"
issue: 6616
branch: feat-one-shot-6616-host-name-telemetry-mislabel
lane: single-domain
plan: knowledge-base/project/plans/2026-07-17-fix-host-name-telemetry-mislabel-plan.md
---

# Tasks — host_name telemetry mislabel (#6616)

> No `spec.md` exists for this branch; `lane: single-domain` set deliberately (engineering /
> infra-observability only). Derived from the finalized plan.

## Phase 0 — Ground-truth diagnosis (read-only)
- [ ] 0.1 Run the `betterstack-query.sh` cross-label query (host_name × host × count, 24h + archive arm) wrapped in `doppler run -p soleur -c prd_terraform`.
- [ ] 0.2 Apply the verdict rule: `≥2` distinct `host` per `host_name` → H1 confirmed (proceed); `1:1` → H2 (record-only re-scope); query fault → re-run wrapped, do NOT proceed on probe fault.
- [ ] 0.3 Record verbatim output into `specs/feat-one-shot-6616-host-name-telemetry-mislabel/session-state.md`; pin the exact web `host` value(s) wearing `soleur-inngest-prd` (feeds the detector's expected-good map).

## Phase 1 — Standing cross-label alarm (TDD)
- [ ] 1.1 Write `scripts/hostname-mislabel-alarm.test.sh` FIRST — 5 exit-class cases (GREEN 1:1 / FIRE cross-label / TRANSIENT creds-unset / PRODUCER-SILENT empty-window-with-control / log-injection sanitized), synthesized fixtures only.
- [ ] 1.2 Implement `scripts/hostname-mislabel-alarm.sh` on the `zot-restart-loop-alarm.sh` pattern: build `host_name → {distinct host}` map; classify FIRE/GREEN/TRANSIENT/PRODUCER-SILENT; exit code is DATA; `strip_log_injection` on decoded fields; no `github.event.*`.
- [ ] 1.3 GREEN the test suite (repo `.test.sh` runner, not a JS runner).

## Phase 2 — Scheduled workflow + Sentry self-liveness
- [ ] 2.1 Author `.github/workflows/scheduled-hostname-mislabel.yml` mirroring `scheduled-zot-restart-loop.yml`; include `gate-override: new-scheduled-cron-prefer-inngest` header (ADR-033 I7 justification); `*/30` cadence; pass `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}`; `MONITOR_SLUG=scheduled-hostname-mislabel`; checker step never `exit 1`s.
- [ ] 2.2 Lint: `actionlint` on the YAML + `bash -c` on each extracted `run:` snippet.
- [ ] 2.3 Add `resource "sentry_cron_monitor" "scheduled_hostname_mislabel"` to `apps/web-platform/infra/sentry/cron-monitors.tf` (slug ↔ MONITOR_SLUG); `terraform validate`.

## Phase 3 — Attribution correction (docs / C4 / learning)
- [ ] 3.1 Edit `model.c4:404` — correct the "every web host ships logs post-ADR-100" overclaim; add create-time-drift + source-2457081 collision caveat (mirror `:178` style); reconcile `:182`,`:266-268`,`:403`.
- [ ] 3.2 Run `c4-code-syntax.test.ts` + `c4-render.test.ts` (green; no new elements/views).
- [ ] 3.3 Write learning `knowledge-base/project/learnings/<date>-host-name-create-time-render-drift-web1-mislabel.md` (date at write time); document the class + the #6425 re-derivation (connector-census-based, `host_name`-independent → unaffected). Verify all `knowledge-base/` citations resolve.

## Phase 4 — Enroll deferred physical relabel
- [ ] 4.1 Write `scripts/followthroughs/hostname-mislabel-web1-6616.sh` — PASS only when `soleur-inngest-prd` maps to exactly ONE `host`; TRANSIENT on probe fault; positive-liveness-marker guard before PASS.
- [ ] 4.2 Add the `<!-- soleur:followthrough script=… earliest=<GA-recreate> secrets=BETTERSTACK_QUERY_* -->` directive + `follow-through` label to the correct GA host-replaceability tracker (confirm which at deepen-plan); wire `secrets=` into `scheduled-followthrough-sweeper.yml` if missing.

## Phase 5 — Ship
- [ ] 5.1 Route the Phase-0 diagnosis + deferral record through a durable `specs/…` artifact for `ship` to fold into the PR body (never author the body from `work`/`plan`).
- [ ] 5.2 PR body uses `Ref #6616` (NOT `Closes`); file the deferred relabel as an `action-required` issue for operator visibility.
- [ ] 5.3 Pre-merge ACs 1–8 green; post-merge ACs 9–11 (Sentry monitor applied + first run GREEN + FIRE-on-live-collision annotated as tracked-deferred).
