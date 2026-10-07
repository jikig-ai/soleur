# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-07-chore-log-noise-cutdown-7696-7665-plan.md
- Status: complete

### Errors
- doppler-injection-bound guard: `CUTOVER_NOOP_THROTTLE_S` seam initially missing from the
  hand-transcribed `GUARD1_UNSET` copy (fixed in the same commit; the copy moves with the
  argv-gate list by design).
- A comment reproducing the `emit_state <ec> <dbsize> "<reason>"` call shape verbatim was
  read as a real call site by the workflow suite's raw-source reason extraction (emitter
  parity + probe parity red until reworded).
- `lint-shell-trace-credential-refusal --changed` bypasses baselines for edited files:
  the T5 comment edit to `scripts/cutover-inngest.sh` surfaced 20 pre-existing Rule-E
  argv-credential sites (introduced by #9681). Drawdown applied in-branch via a new
  `_sig_curl` wrapper; Rule-E baseline + census-ceiling rows removed.
- CI-only failure: the noop-throttle stamp at the host-default state path persisted
  across flip-suite cases where /var/lock is writable — a refused case's stamp
  suppressed the next case's authorised emit. `clean_host_state_slot` now clears the
  stamp too.
- `fixture-relative-assert` ratchet: `: > "$NOOP_EMIT_STAMP"` is a new counted site
  (flip.sh 4 -> 5); baseline regenerated per the lint's own recovery path.
- GuardA (cloud-init-inngest-bootstrap.test.sh, deploy-script-tests leg 4/4 — NOT a
  required check) is expectedly RED while HEAD's `inngest-cutover-flip.sh` drifts from
  the pinned image tag v1.1.45; the bot pin-bump cycle rebuilds the tag post-merge.

### Decisions
- #7696: mirror the sibling `inngest-luks-cutover.sh` `emit_noop` pattern — throttle `noop-*`
  emissions INSIDE `emit_state` (300s mtime stamp at `${STATE_FILE}.noop-emitted`) so the
  emitter-reason extraction and #8054 producer-contract pins stay green; transitions stay
  unconditional; stamp absent/unreadable fails toward EMITTING.
- #7665: caller diagnosed via live Better Stack read — the dedicated inngest host's
  `--sdk-url http://10.0.1.10:3000/api/inngest --poll-interval 60` sync poll (~120/hr) plus
  canary `localhost:3001` bursts. Verdict: legitimately rejected (admitting the internal
  literal would let a client-supplied `x-forwarded-host` claim it — never admit) → fix is
  per-origin once-per-process dedupe with a bounded FIFO cap in `resolve-origin.ts`.
- `FLIP_LIVENESS_SINCE` NOT touched — it is a deliberate literal, pinned `"15m"` by test
  (the issue's "env-overridable" claim is stale); 300s cadence keeps ~3 rows per window.
- `GUARD_REV` stays `7761` — the row-rate drop is itself the delivery observable; bumping
  would force a coupled EXPECTED_GUARD edit in the 7761 follow-through probe.

### Components Invoked
- soleur:plan (executed inline; no Skill tool in this harness)
- soleur:deepen-plan gates evaluated inline (4.6/4.7/4.12 sections added; conditional
  gates 4.5/4.55/4.8/4.9/4.10/4.11 not triggered)
- scripts/betterstack-query.sh (read-only, doppler prd_terraform) — #7665 caller diagnosis
