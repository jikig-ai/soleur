---
title: "chore: cut ~7k Better Stack rows/day — throttle flip-FSM terminal heartbeat + dedupe resolve-origin rejections"
date: 2026-10-07
slug: chore-log-noise-cutdown-7696-7665
branch: feat-one-shot-7696-7665-log-noise
issue: 7696
---

## Overview

Two steady-state log emitters burn ~7k Better Stack rows/day on the quota-constrained
`vector.toml` channels, and neither row carries information worth that volume:

- **#7696** — `emit_state` in `apps/web-platform/infra/inngest-cutover-flip.sh` calls
  `logger` unconditionally on EVERY arm, including the terminal `noop-*` arms that fire on
  a 30s systemd timer for the life of the dedicated inngest host (~2,040 rows/day measured
  2026-08-25, ~1.42/min).
- **#7665** — `resolveOrigin` in `apps/web-platform/lib/auth/resolve-origin.ts` emits a
  non-JSON `console.warn` per rejected request origin. A non-JSON line escapes
  `transforms.app_container_warn_filter`'s `level >= 40` cut through the deliberate
  `parse_err != null` arm, so each rejection is one shipped row.

Both are code + tests only. No terraform, no SSH, no on-host change. The flip script reaches
the dedicated host via the replace/infra-config path and takes effect there; the
resolve-origin change reaches prod via the normal container deploy.

## Research Insights

### Premise Validation

- Issue #7696 is OPEN; cited predecessor #7692 is MERGED (2026-08-27) and #7674 is CLOSED —
  their scope was the liveness gate, not the emit leak. The `emit_state` function, the
  `noop-*` terminal arms, `FLIP_LIVENESS_SINCE="15m"`, and the G3.7 `silent` outcome all
  verified present on `origin/main`.
- Issue #7665 is OPEN; no closing/linked PRs. `resolve-origin.ts` and the
  `console.warn("[resolve-origin] Rejected origin:", …)` call verified present.
- STALE PREMISE CORRECTED: the issue text says `FLIP_LIVENESS_SINCE` is env-overridable —
  it is not, by design. `scripts/cutover-inngest.sh` pins it to the literal `"15m"`
  (deliberate: "an operator-reachable knob whose only effect is to weaken the gate is not a
  knob worth shipping"), and `cutover-inngest-workflow.test.sh` asserts both the literal and
  that the name never reaches the workflow env. So the plan takes the cadence branch of the
  constraint only: terminal emission stays **strictly under 15 minutes**; the window literal
  does not move.

### The 15s caller for #7665 — DIAGNOSED (read-only, via betterstack-query.sh)

Measured 2026-10-07 against the live warehouse (hot window):

- `soleur-web-platform` (prod container): `Rejected origin: http://10.0.1.10:3000` —
  **2,866 rows / 24h, flat ~120/hr**. This is the dedicated inngest host's registration
  poll: `inngest-host.tf` sets `sdk_url = "http://10.0.1.10:3000/api/inngest"` and
  `inngest-bootstrap.sh` ExecStart carries `--poll-interval 60`; each sync poll runs through
  middleware, which calls `resolveOrigin` before the public-path check.
- `soleur-web-platform-canary`: `http://localhost:3001` — 48 rows, only inside deploy
  windows (the canary probe loop in ci-deploy.sh, ~1/s bursts).
- `http://localhost:3000` — zero rows in the last 24h; it appeared in the issue's earlier
  window from the same probe/deploy classes.
- Long-tail scanner origins (`dokploy.cristianruben.com` etc.) — ~tens/day, working as
  intended.

**Verdict: legitimately rejected, not misconfigured.** The inngest poll is correct
(ADR-100's private-interface `--sdk-url`), does not consume the resolved origin (it is a
sync poll, not a browser redirect target), and must NOT be *admitted*: `resolveOrigin`
prefers `x-forwarded-host`, which any internet client can set, so whitelisting
`http://10.0.1.10:3000` in `PRODUCTION_ORIGINS` would let an attacker-controlled header
pass the origin gate — an open-redirect/CSP-host weakening for zero caller benefit. The
fix is therefore the issue's option 3: rate-limit the warn, per distinct origin, once per
process lifetime.

### Mechanism already on main (the load-bearing research finding)

The SIBLING FSM `apps/web-platform/infra/inngest-luks-cutover.sh` (same host, same 30s
timer shape, same Better Stack tag channel) already ships exactly this fix: `emit_noop()`
throttles terminal heartbeats to 300s via a `$STATE_DIR/noop-emitted` mtime stamp, and its
comment cites the same G3 liveness gate ("Three rows per window keeps that gate answerable
while cutting volume ~10x"). The plan mirrors that established pattern onto the flip FSM —
no new mechanism is invented.

### Property List / Cut List (Phase 0.6b)

Properties required:

1. `noop-*` emissions cadence strictly < 15 min (G3.7 `H` window) and never transition-only
   (H depends on the terminal heartbeat).
2. ~order-of-magnitude row reduction on both channels; first occurrence of a rejected
   origin still visible (the row is the diagnostic).
3. No new env-reachable knob in production on the flip path — the `--fixture-seams` argv
   gate unsets every `CUTOVER_*`/`INNGEST_CUTOVER_*` name in prod.

Cut list: no new mechanisms — stamp-file throttle and a `Set` dedupe both reuse idioms
already in-tree (luks `emit_noop`, `LRUCache` family). `FLIP_LIVENESS_SINCE` stays `"15m"`.

### Pins that constrain the implementation shape

- `cutover-inngest-workflow.test.sh` extracts emitter reasons with
  `grep -oE 'emit_state [^ ]+ [^ ]+ "[^"]*"'` and pins (a) every non-noop reason is
  anchored, (b) every reason except `noop-done` is a `DRIFT_GREPS` term in
  `scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh`. → noop arms keep calling
  `emit_state` with the same quoted reason literals; the throttle lives INSIDE
  `emit_state`, keyed on the `noop-*` reason prefix.
- Same suite pins `emit_state` emitting a top-level `flag` key and logging via
  `"${CUTOVER_LOGGER_CMD:-logger}" -t "$LOG_TAG" "$json"` (shape-pinned) — that line is
  preserved verbatim.
- `inngest-cutover-flip.test.sh` derives the seam set from every `CUTOVER_*`/
  `INNGEST_CUTOVER_*` expansion in the script and asserts equality with the gate's unset
  list → the new interval seam `CUTOVER_NOOP_THROTTLE_S` MUST be added to the gate list
  (16 → 17) and the prose count updated.
- `MIN_ASSERTIONS=163` floor in the flip suite — raise in lockstep with added assertions.
- `resolve-origin.ts` runs in the edge middleware bundle — no `@/server/logger` (pino)
  import allowed; `console.warn` stays the emit mechanism. A non-JSON line always passes
  Vector's warn filter (`parse_err != null` arm), so structured-JSON downgrade is NOT an
  option in the edge bundle; in-process dedupe is the fix.

## Implementation Phases

### Phase 1 — #7696: throttle terminal-arm emission (300s stamp)

`apps/web-platform/infra/inngest-cutover-flip.sh`:

- Add `CUTOVER_NOOP_THROTTLE_S` to the seam-gate unset list; update the "SIXTEEN" prose
  count to seventeen.
- Add `NOOP_THROTTLE_S="${CUTOVER_NOOP_THROTTLE_S:-300}"` (300s ⇒ ≤3 emissions per 15-min
  liveness window; ~2,040 → ~288 rows/day) and
  `NOOP_EMIT_STAMP="${STATE_FILE}.noop-emitted"` — derived, so it follows the
  `INNGEST_CUTOVER_STATE` seam into the test workdir, lives in writable `/var/lock` in prod,
  and (being tmpfs) self-clears on boot so the first post-boot fire always emits.
- In `emit_state`: keep the state-slot write unconditional; for `reason == noop-*` gate the
  logger call on stamp age (`now - mtime >= NOOP_THROTTLE_S`), touching the stamp on a real
  emission. Unreadable/absent stamp ⇒ emit — fail toward audibility, never silence.
- Update the header P0-2 comment to describe the throttled heartbeat.
- Comment-only touch-up in `scripts/cutover-inngest.sh` (the WINDOW block cites "~42s
  terminal-arm cadence" — record the new 300s cadence). `FLIP_LIVENESS_SINCE` unchanged.

`apps/web-platform/infra/inngest-cutover-flip.test.sh`: new cases — first noop emits,
immediate repeat suppressed (no logger line but state slot still written), aged stamp
emits again (`touch -d`), transition arms unaffected by a fresh noop stamp, seam
interval honoured under `--fixture-seams` (small `CUTOVER_NOOP_THROTTLE_S` makes a second
fire emit); update header bullet + `MIN_ASSERTIONS` (+~8 → 171).

### Phase 2 — #7665: per-origin dedupe on the rejection warn

`apps/web-platform/lib/auth/resolve-origin.ts`:

- Module-scope `loggedRejectedOrigins: Set<string>` + cap `REJECTED_ORIGIN_LOG_CAP = 256`
  with FIFO eviction (insertion-ordered `Set`; evict oldest when full so a novel origin is
  never starved by scanner churn — bounded ~13 KB, single-process isolate).
- Rejected branch: log only on first sighting of a given `computed` origin; the warn text
  marks the dedupe (`(first occurrence; further rejections of this origin suppressed until
  restart)`). Return value / control flow unchanged.
- Document in the header comment WHY the inngest `--sdk-url` poll is rejected-and-quiet
  rather than admitted (host-header trust boundary).

New `apps/web-platform/lib/auth/resolve-origin.test.ts` (vitest, `lib/**/*.test.ts`
project): first rejection logs once; repeat suppressed; distinct origins each log once;
cap eviction permits re-log; fallback return unchanged; `NODE_ENV=development`
`localhost:3000` admit path unaffected. `vi.resetModules()` + dynamic import to reset the
module-scoped Set between cases.

## Files to Edit

- `apps/web-platform/infra/inngest-cutover-flip.sh` — noop throttle + seam list + comments
- `apps/web-platform/infra/inngest-cutover-flip.test.sh` — new cases + floor bump
- `apps/web-platform/lib/auth/resolve-origin.ts` — per-origin dedupe
- `scripts/cutover-inngest.sh` — comment-only: refresh the cadence citation in the
  FLIP_LIVENESS_SINCE WINDOW block

## Files to Create

- `apps/web-platform/lib/auth/resolve-origin.test.ts` — dedupe coverage

## Open Code-Review Overlap

None. Open `code-review` issues were queried for each planned path; only #2591 names
`middleware.ts`, which this plan does not edit.

## User-Brand Impact

- threshold: none, reason: observability-cost hygiene only — the diff changes log-emission
  cadence on an infra FSM and log dedupe on an origin reject; no auth verdict, routing,
  CSP, or user-visible behavior changes.
- Sensitive-path note: `apps/web-platform/lib/auth/` and `apps/web-platform/infra/` match
  the sensitive-path regex — the touched function keeps byte-identical verdict semantics
  (rejected origins still return the `https://app.soleur.ai` fallback); only the warn's
  repetition rate changes.
- Residual risk surface that DOES carry user impact is ops-facing: if the flip FSM's
  heartbeat were silenced outright, G3.7 would refuse legitimate arms — the plan's binding
  constraint keeps terminal-arm cadence at 300s, strictly under the 15-minute window.

## Observability

```yaml
liveness_signal:
  what: "inngest-cutover-flip journald rows (the noop-* heartbeat IS the signal — G3.7 H counts them in a 15m window); post-change cadence 300s = ~3 rows/window"
  cadence: "300s per terminal-state emit; transitions unconditional"
  alert_target: "scripts/cutover-inngest.sh G3.7 silent refusal + scheduled-inngest-health watchdog"
  configured_in: "apps/web-platform/infra/inngest-cutover-flip.sh (emit_state throttle); scripts/cutover-inngest.sh FLIP_LIVENESS_SINCE"

error_reporting:
  destination: "Better Stack via vector.toml journald allowlist (tag inngest-cutover-flip); app-container console via app_container_warn_filter"
  fail_loud: "flip FSM: unexpected-exit / verify-* / refuse-* markers still emit unconditionally (non-noop reasons are never throttled); resolve-origin: first rejection per origin per process still logs"

failure_modes:
  - mode: "noop stamp unreadable or unwritable (/var/lock)"
    detection: "emit falls back to emitting (fail toward audibility) — rows return, never silence"
    alert_route: "Better Stack row volume / G3.7 H stays answerable"
  - mode: "throttle interval mis-set above the 15m liveness window"
    detection: "suite pins the default literal below FLIP_LIVENESS_SINCE; seam is gate-unset in prod (Doppler cannot inject it)"
    alert_route: "inngest-cutover-flip.test.sh reds"
  - mode: "resolve-origin dedupe hides a NEW recurring rejection"
    detection: "first occurrence per process still logs; FIFO cap eviction re-admits evicted origins"
    alert_route: "Better Stack [resolve-origin] rows (one per origin per deploy)"

logs:
  where: "journald -> Vector -> Better Stack (unchanged channels)"
  retention: "Better Stack hot window + s3 archive (unchanged)"

discoverability_test:
  command: "bash -c 'grep -q CUTOVER_NOOP_THROTTLE_S apps/web-platform/infra/inngest-cutover-flip.sh && grep -q loggedRejectedOrigins apps/web-platform/lib/auth/resolve-origin.ts && echo log-noise-fixes-present'"
  expected_output: "log-noise-fixes-present"
```

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "any rate-limit MUST (1) keep terminal-arm cadence strictly under 15 minutes and (2) NOT become transition-only emission" [#7696] | Phase 1 emit_state throttle (300s, transitions unconditional) | mapped |
| 2 | "identify the ~15s caller … and establish whether it SHOULD be admitted" [#7665] | Research Insights (diagnosed: inngest --sdk-url poll; verdict = legitimately rejected) | mapped |
| 3 | "If legitimately rejected → downgrade: rate-limit or emit as structured pino at debug/info" [#7665] | Phase 2 per-origin dedupe | mapped |
| 4 | "update decision-table tests" [#7696] | T2 flip-suite cases + MIN_ASSERTIONS bump | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| emit_state noop throttle + stamp | "any rate-limit MUST (1) keep terminal-arm cadence strictly under 15 minutes" | asked |
| resolve-origin dedupe | "downgrade: rate-limit or emit as structured pino" | asked |
| seam-gate list + comment updates | — | inferred — justification: the tripwire test derives the seam set from the file; a new CUTOVER_ name not in the unset list reds the suite |
| scripts/cutover-inngest.sh comment refresh | — | inferred — justification: the WINDOW comment cites a 42s cadence this change retires; stale citation misleads the next gate author |
| new resolve-origin.test.ts | — | inferred — justification: cq-write-failing-tests-before requires the dedupe be proven red-then-green |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform` (infra + lib), `scripts`
- Planned files: 4 edited + 1 created | Estimated changed lines: ~180
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] A `noop-*` arm emits at most one `logger -t inngest-cutover-flip` row per
  `CUTOVER_NOOP_THROTTLE_S` seconds (default 300) and ALWAYS emits when the stamp is absent
  or unreadable.
- [ ] The emit_state state-slot write remains unconditional on every arm.
- [ ] Every non-`noop-*` `emit_state` reason still emits unconditionally (transition rows
  are not throttled).
- [ ] `CUTOVER_NOOP_THROTTLE_S` appears in the seam-gate unset list; the derived-set
  tripwire stays green; `FLIP_LIVENESS_SINCE` remains the literal `"15m"`.
- [ ] `resolveOrigin` logs a given rejected origin at most once per process, still returns
  the `https://app.soleur.ai` fallback, and a novel origin is never permanently starved by
  the cap (FIFO eviction).
- [ ] `bash apps/web-platform/infra/inngest-cutover-flip.test.sh` green, floor raised for
  the new assertions.
- [ ] `cd apps/web-platform && npx vitest run lib/auth/` green.
- [ ] PR body carries `Closes #7696` and `Closes #7665`, each on its own line.

## Test Scenarios

1. `noop-unset` fired twice in a row (fresh stamp → first emits; second suppressed;
   `LOGTRACE` line count 1) — proves the throttle engages.
2. Same, with `touch -d '1 hour ago'` on the stamp between fires — emits again (cadence).
3. `rollback` arm immediately after a fresh noop emission — the `rolled-back` transition
   row still emits (non-noop arms never throttled).
4. `resolveOrigin("10.0.1.10:3000","http",null)` twice — one `console.warn`; a second
   distinct origin warns once; both calls return the fallback origin.
