# Learning: a `--poll-interval` config does NOT make recovery poll-driven — manifest-registration recovery is push-bound

## Problem

A standalone restart of the self-hosted `inngest-server.service` de-planned ALL
production crons (drift guards, KB template health, OAuth probes, community
monitors, release digests) until something external re-registered the app. PR
#5146 (#5145) had already widened the post-restart cron-plan verify budget to
120s on the assumption that recovery was poll-driven and merely slow — the
server runs `--poll-interval 60 --sdk-url http://127.0.0.1:3000/api/inngest`, so
"it'll re-sync on the next poll" looked obviously true. It was false: on
2026-06-11 the full widened budget elapsed across 5+ consecutive poll cycles
with `"inngest_crons": {}`, twice. The registry only repopulated when a manual
`curl -X PUT https://app.soleur.ai/api/inngest` fired (`modified:true`) or when
a concurrent app-container restart re-registered at boot.

## Solution

Fire the re-registration push from the restart path itself. The fix adds a
fire-and-forget loopback `curl -sf --max-time 10 -X PUT
http://127.0.0.1:3000/api/inngest || true` **inside** `verify_inngest_health`'s
cron-plan loop (every iteration, before the `/v1/functions` poll), converting a
passive poll loop into active push-and-poll. One in-function edit covers both
the restart arm and the deploy-inngest arm (both call the function arg-less).

Two design points that generalize:
- **Push inside the retry loop, not once before it.** A one-shot push before the
  loop races readiness of the push target (the web-platform `:3000` container
  may be mid-restart in the deploy arm); `|| true` swallows the connection-refused
  and the loop then waits out the full budget — reproducing the bug. Re-firing
  each iteration self-heals a transient not-ready window. The push is an
  idempotent upsert, so re-firing up to N times is free, and the loop early-exits
  on first success (1–2 fires in the happy path).
- **Counting the new additive cost in the cross-file drift guard.** The in-loop
  push is sequential+additive per cron iteration, so the server worst case rose
  ~640s→~1040s, exceeding the client poll window. The fix widened the window
  (MAX_POLLS 140→240 = 1200s) AND extended the `#5145` drift guard to extract the
  push `--max-time` by shape — a guard that ignores a new operand is a
  false-green (see `2026-06-11-cross-file-drift-guards-extract-every-operand-by-shape.md`).

## Key Insight

A `--poll-interval` (or any "we poll the source every N seconds") configuration
proves the system *polls*; it does NOT prove *recovery* is poll-driven. When the
state being recovered is a **registration/manifest that the source must push**
(SDK function registration, webhook subscription re-arm, service-discovery
announce), the poller only refreshes what the source re-advertises — it cannot
manufacture a registration the source never re-sends after a restart. Recovery
is push-bound. The diagnostic tell: a budget-widening fix that "should" work
keeps failing across many cycles. When that happens, stop widening the budget
and ask "what actually performs the recovery action, and does anything fire it
on this path?" A budget fix is necessary-but-insufficient when the recovery
*mechanism* — not its timing — is the gap. Live evidence (the manual PUT
returning `modified:true`) refutes the poll-driven hypothesis faster than any
amount of budget arithmetic.

## Session Errors

- **systemctl prose hook false-positive (plan phase, forwarded via session-state.md).** The IaC-routing hook flagged `systemctl restart` prose describing the *existing* script behavior being modified. Recovery: documented `iac-routing-ack` opt-out comment in the plan frontmatter (the edit routes through the existing `deploy_pipeline_fix` bridge, not a new manual step). Prevention: already-mitigated — the opt-out exists for exactly this "prose describes existing infra, not a new provisioning step" case. One-off.
- **Foreground wait wrapper timed out on a background task (exit 143) while the task itself completed exit 0.** Recovery: read the background output file directly after the harness re-notified on completion. Prevention: don't wrap a harness-tracked `run_in_background` task in a foreground `while kill -0 … ; sleep` poll — the harness re-invokes on completion; read the output file on notification instead. One-off.
- **`code-quality-analyst` review agent hit a transient API rate-limit (returned no output).** Recovery: inline doc-quality fallback per the review skill's Rate-Limit Fallback gate (5 other orthogonal agents returned substantive output). Prevention: already-covered — the gate permits partial coverage; only an all-agents-failed case triggers a full inline review. One-off.

## Tags
category: integration-issues
module: apps/web-platform/infra
issue: 5159
