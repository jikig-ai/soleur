---
title: "Tasks — fix(observability): host_name telemetry mislabel (#6616)"
issue: 6616
branch: feat-one-shot-6616-host-name-telemetry-mislabel
lane: single-domain
plan: knowledge-base/project/plans/2026-07-17-fix-host-name-telemetry-mislabel-plan.md
---

# Tasks — host_name telemetry mislabel (#6616)

> No `spec.md` exists for this branch; `lane: single-domain` set deliberately (engineering /
> infra-observability only). Derived from the deepened plan (post 4-agent review; standing detector
> collapsed into a single identity-keyed follow-through).

## Phase 0 — Ground-truth diagnosis (read-only)
- [x] 0.1 Run the identity `betterstack-query.sh` query (host_name × host × count, 24h + archive arm) wrapped in `doppler run -p soleur -c prd_terraform`.
- [x] 0.2 Apply the identity verdict rule: mislabel confirmed iff `soleur-inngest-prd` is emitted by any `host` != `soleur-inngest-server-prd`; premise-stale iff emitted ONLY by `soleur-inngest-server-prd` WITH that host present (schema-liveness). Do NOT proceed on a probe fault — but if creds are unavailable in-session, defer live confirmation to the first prod sweeper run (do not dead-end).
- [x] 0.3 Pin the dedicated-node identity (authoritative), record query output in `session-state.md`. **CORRECTION (live data):** the node's telemetry `host` is `soleur-inngest` (service-fingerprint), NOT `soleur-inngest-server-prd` (that Hetzner resource `name` never appears in telemetry). Check re-keyed to FAIL on web-host identities (`server.tf:225`) + `soleur-inngest` liveness marker. See `session-state.md` §Work Phase + `decision-challenges.md` DC-2.

## Phase 1 — Attribution correction (docs / C4 / ADR)
- [x] 1.1 Edit `model.c4`: add the create-time-drift caveat to the `hetzner -> betterstack` edge (overclaim: "every web host ships logs post-ADR-100"); reconcile the `inngest -> betterstack` edge's "isolated" description against the documented collision. Cite by content anchor, not line number.
- [x] 1.2 Run `c4-code-syntax.test.ts` + `c4-render.test.ts` (green; no new elements/views).
- [x] 1.3 Add the one-line create-time-render pointer to `ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`.
- [x] 1.4 Write learning `knowledge-base/project/learnings/<date>-host-name-create-time-render-drift-web1-mislabel.md` (date at write time): the drift class, identity-not-cardinality discriminator, and the #6425 re-derivation (connector-census-based → unaffected). Verify all `knowledge-base/` citations resolve.

## Phase 2 — Arm automated closure (single read-only follow-through)
- [x] 2.1 Write `scripts/followthroughs/hostname-mislabel-web1-6616.sh` (~46 LOC on the `betterstack-quota-verdict-5105.sh` / `chardevice-wedge-nonrecurrence-5934.sh` precedent): PASS iff `soleur-inngest-prd` emitted only by `soleur-inngest-server-prd`; TRANSIENT (not PASS) on creds/query fault AND on missing schema-liveness marker (`≥1 soleur-inngest-server-prd` row); FAIL while a web host emits the label. Read-only.
- [x] 2.2 Write synthesized-fixture tests for each exit class, including the "`host` column all-empty → TRANSIENT not PASS" case (`cq-test-fixtures-synthesized-only`).
- [x] 2.3 Enroll the `<!-- soleur:followthrough script=… earliest=<merge+90d concrete date> secrets=BETTERSTACK_QUERY_* -->` directive + `follow-through` label on **#6616 itself**. Confirm `BETTERSTACK_QUERY_*` already wired in `scheduled-followthrough-sweeper.yml` (no workflow edit expected).

## Phase 3 — Ship
- [ ] 3.1 Write `decision-challenges.md` (detector-cut dissent) for `ship` to file as `action-required`.
- [ ] 3.2 Route the Phase-0 diagnosis + deferral record through the durable `specs/…` artifact for `ship` to fold into the PR body (never author the body from `work`/`plan`).
- [ ] 3.3 PR body uses `Ref #6616` (NOT `Closes`); the deferred relabel surfaces as an `action-required` issue for operator visibility.
- [ ] 3.4 Pre-merge ACs 1–8 green; post-merge AC9 (first sweeper run reaches FAIL/TRANSIENT, never false PASS).
