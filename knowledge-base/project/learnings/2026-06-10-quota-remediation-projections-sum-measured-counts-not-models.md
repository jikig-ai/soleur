# Learning: Quota-remediation projections must sum MEASURED per-unit counts, not modeled estimates

## Problem

The first Better Stack quota remediation (PR #5105: host_metrics scrape 30s → 300s + `loop*`/`dm-*` device excludes) predicted ~19.6k rows/day. The AC12 runtime verdict on #5110 came back `RESULT: FAIL`: measured steady state was 198 rows per 300s scrape ≈ 57k rows/day — 2.3× over the 25k threshold and a 2.9× prediction miss. The prediction modeled per-scrape series counts instead of measuring them; the filesystem collector alone emitted 108 rows/scrape (4 metrics × 27 mountpoints, 21 of them virtual filesystems that the *device* excludes don't touch).

## Solution

Second pass (PR #5131): query the live table for the per-collector breakdown first (`GROUP BY JSONExtractString(raw, 'name')` + per-5-min buckets), then design the trim so every projection term is an observed count: drop the network collector (−33 measured rows; grep-verified zero consumers), allowlist filesystem to 3 mountpoints via `mountpoints.includes` (108 → 12 = observed 4 metrics/mount × 3). Projection 69 rows/scrape ≈ 19.9k/day with 20% margin. Added a two-stage verdict: a fast per-bucket query (~30 min post-deploy, ≤86 rows/bucket + filesystem-presence check) catches a third overshoot without waiting 24h for the daily verdict.

## Key Insight

When a capacity/quota fix is gated on a numeric threshold, the remediation design must derive every projection term from a measurement of the live system, and the post-deploy verification needs a fast leading indicator (per-bucket rate) in addition to the lagging gate (daily total). A steady-state rate that is flat across ≥3 cycles is verdict-grade evidence even before the formal measurement window: rendering `RESULT: FAIL` early is safe when FAIL is the non-closing direction of the gate (the sweeper only auto-closes on PASS), and it saves a full day of quota burn.

Secondary insights from this session:

- **Validators silent on a failure class need their guard promoted to CI.** Vector 0.43.1 `vector validate` silently ignores misspelled filter *sub*-keys (`mountpoints.include` singular = silent no-op restoring full ingest). The byte-exact grep that guards the spelling must live in `.github/workflows/validate-vector-config.yml`, not only in a plan file's AC list — plans are read once; CI runs forever.
- **Exclusive-boundary diff gates when the marker itself changes.** An AC asserting "everything before marker X is byte-identical" must use an exclusive boundary (`awk '/marker/{exit} {print}'`) when the PR changes the marker line itself — an inclusive `sed -n '1,/marker/p'` range false-fails permanently. Running the AC against the unmodified baseline at plan time is the cheap self-test that catches this.
- **Records updated pre-merge must not assert post-merge state.** Writing "deployed via vinngest-v1.1.13" into a post-mortem before the tag exists is a temporal-qualifier miss; three review agents flagged it independently. Phrase as "deploying via … (tag pushed post-merge; outcome pending the verdict)".

## Session Errors

1. **Subagent Task-tool unavailability (forwarded from session-state.md)** — the planning subagent could not spawn its own agents; plan-review/deepen fan-outs ran inline. Recovery: inline passes recorded transparently in the plan's Domain Review / Enhancement Summary. **Prevention:** known pipeline limitation; inline execution with transparent recording is the accepted fallback.
2. **AC6 inclusive-sed false-fail (forwarded, caught at plan time)** — Recovery: rewritten to the exclusive awk boundary and baseline-tested green. **Prevention:** always run plan AC verification commands against the unmodified baseline at plan time (the plan skill's self-test step did exactly this).
3. **ClickHouse nested-tag extraction returned empty strings** — `JSONExtractString(raw, 'tags.mountpoint')` (dotted path) silently yields `''`; the multi-key form `JSONExtractString(raw, 'tags', 'mountpoint')` is required. Recovery: sampled one raw row to see the JSON shape. **Prevention:** runbook note appended to `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (this session).
4. **Pre-deploy past-tense deploy claim in the post-mortem** — Recovery: review commit 61d8fddab added temporal qualifiers. **Prevention:** when a PR updates incident records before the deploy it describes, use "deploying / pending verdict" phrasing; the review skill's temporal-qualifier check (PR #4455 precedent) catches this class.

## Tags

category: integration-issues
module: observability/better-stack
