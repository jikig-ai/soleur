# Runbook — registry_zot_log_credential_shape (#10321)

Standing Better Stack Logs alert `soleur-registry-zot-log-credential-shape-prd`
(`logtail_exploration` + `logtail_exploration_alert` in
`apps/web-platform/infra/betterstack-logs-alerts.tf`, source 2457081).

## What fires it

One or more `SOLEUR_ZOT_LOG` envelope rows on the prd Logs source carrying any of
three credential shapes — the same arms `scripts/followthroughs/zot-log-channel-7440.sh`
graded before its tracker #7455 closed and the probe went dormant:

- **(a) unmasked Authorization value** — any `Authorization:[<v>` on the row whose
  value is neither the zot `***` mask (three or more asterisks) nor the shipper's
  `REDACTED` marker. Evaluated per occurrence; a leading decoy cannot mask a real
  credential. An `Authorization:[` whose value is whitespace-only also fires;
  a literal `Authorization:[]` is benign.
- **(b) Doppler token prefix** — `dp.(pt|st|sa|ct).` followed by a token run with
  ≥16 non-separator characters (`.` `_` `-` stripped — padding does not count).
- **(c) bcrypt prefix** — `$2[aby]$<2 digits>$`.

Any single matching row pages (`value = 0`, `higher_than`; check 300 s, query
900 s, recovery 1800 s). Every matching row counts — there is no newest-boot
scoping; the probe's boot-span existed to attribute delivery, not to bound leaks.

## What to do (in order)

1. **Counts only.** Identify WHICH shape fired and how many rows — never echo the
   matched value into a comment, issue, PR, chat, or this page. Query the alert's
   exploration for row COUNT by shape, not row content. The probe file
   `scripts/followthroughs/zot-log-channel-7440.sh` remains the manual
   deep-grader (runnable under `scripts/betterstack-query.sh` with
   `BETTERSTACK_QUERY_*` env) and it also prints counts, never values.
2. **Rotate the affected credential FIRST** — before touching `redact()`. A
   leaked credential stays valid while you debug the emitter; rotation bounds the
   exposure. (The zot push credential protects the image supply chain.)
3. Then fix the emitter (`redact()` in the registry log shipper, ADR-184) and let
   the alert's own recovery window close the incident.

## What it does NOT cover

- Credential shapes outside the three patterns above (a fourth shape needs a new
  disjunct — amend the predicate and the drift guard together).
- Rows the shipper's rate cap never emitted.
- A leak on a different source.
- The channel going dark — that is the registry heartbeats' job
  (`betteruptime_heartbeat.registry_prd`, the `ci/zot-telemetry-silent` arm), not
  this alert's (`on_missing_data = treat_as_zero`).

## Lineage

The probe's tracker #7455 auto-closed on PASS 2026-08-13; the sweeper's read set
(open issues + `CLOSED_LOOKBACK_DAYS=14`) dropped it ~2026-08-27 while its header
still claimed "enrolled as a REGRESSION detector" — #10321. The dormant-detector
rule lives in `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`:
a check meant to outlive its tracker is a standing alert, not a probe.
Drift guard: `apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh`.
