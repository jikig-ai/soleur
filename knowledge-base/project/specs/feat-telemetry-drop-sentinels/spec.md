# Feature: Telemetry-Drop Sentinels (Cross-Sink Schema)

Tracks: #3509. Brainstorm: `knowledge-base/project/brainstorms/2026-05-10-telemetry-drop-sentinels-brainstorm.md`.

## Problem Statement

The three telemetry sinks under `.claude/` (`.session-tokens.jsonl`,
`.skill-invocations.jsonl`, `.rule-incidents.jsonl`) are written by hooks that
follow a fire-and-forget contract: every error path returns success silently.
Compound Phase 1.6 and the weekly aggregators (`skill-freshness-aggregate.sh`,
`rule-metrics-aggregate.sh`, `token-efficiency-report.sh`) have no in-band
signal to detect when their input streams are incomplete. Long-running
operators may see "n/a" or zero-count signals that are actually drops.

The drops are real: each emit path has at least one of `flock -w 5` timeout,
jq line-build failure, mkdir/fs error, or post-flock write failure. With
#3508's rotation primitive on main, a fourth class — rotation failure — is
now also a silent-drop site.

Bad-telemetry decision loops are the user-impact: the operator may retire a
rule that's actually load-bearing, miss a runaway-cost pattern, or
under-investigate a real incident because the report under-counted.

## Goals

- Detect three drop classes (`jq_fail`, `flock_timeout`, `rotation_fail`) via
  in-band sentinel lines written to the same JSONL the data was supposed to
  land in.
- Surface drop counts in all three aggregators' existing JSON output.
- Render a single "Subagent envelopes incomplete: N drops" line in compound
  Phase 1.6's top-3 cost table when N > 0.
- Keep the schema minimal and field-additive (no schema-version bump).
- Exempt sentinel lines from the rule-metrics orphan-gate.

## Non-Goals

- Detecting `fs-error` class drops. A sentinel write to the same disk fails
  for the same reason as the data write — undetectable in-band. A separate
  disk-space monitor is the right mitigation; tracked as a follow-up issue.
- Adding an out-of-band drop sink (`.claude/.telemetry-drops.jsonl`).
  Rejected as over-engineered in the brainstorm.
- Schema v2. Field-additive on v1: data lines have no `error` key, sentinels
  do — that's the discriminator.
- Python `emit_incident` sibling parity (`security_reminder_hook.py`). Out of
  scope until a Python-side drop site emerges.
- Always-on Phase 1.6 render. Zero-drop windows produce no render line.
- Rendering drops in operator-facing per-session output. Drops surface in
  weekly/Phase-1.6 aggregator output only.

## Functional Requirements

### FR1: Sentinel Schema

Each silent-drop site emits one JSON line with shape:

```json
{"schema":1,"hook_event":"<PreToolUse|PostToolUse>","error":"<jq_fail|flock_timeout|rotation_fail>","ts":"<iso8601>"}
```

- `schema`: `1` (no bump from existing data lines).
- `hook_event`: matches the data-line `hook_event` field for that sink.
- `error`: one of the three string literals above.
- `ts`: UTC ISO-8601 (`date -u +%Y-%m-%dT%H:%M:%SZ` format).

No `session_id`, no `cause_snippet` in v1. Forensic correlation rides on
adjacent data lines (drops cluster temporally).

### FR2: Hook-Side Sentinel Emission

Each of the three hook scripts emits a sentinel on each detectable drop class:

- `.claude/hooks/agent-token-tee.sh` — emits on `flock_timeout` (replaces the
  existing stderr-only echo at the `flock -w 5` timeout site), `jq_fail`
  (when the line builder returns non-zero), `rotation_fail` (when
  `rotate_if_needed` reports failure).
- `.claude/hooks/skill-invocation-logger.sh` — emits on `jq_fail`,
  `rotation_fail`. The `flock_timeout` class is N/A — the hook keeps its
  indefinite `flock -x 9` (decided in plan-review 2026-05-10: adding a
  timeout for parity is gold-plating; no operator has reported a wedged
  session). Documented in the sentinel-schema header.
- `.claude/hooks/lib/incidents.sh::emit_incident` — emits on `jq_fail`,
  `rotation_fail`. The `flock_timeout` class is N/A (uses indefinite
  `flock -x 9`). Keep the existing rate-limited per-`$$` stderr warning;
  sentinel emission is additive.

Sentinel emission MUST itself be fail-soft: a fixed pre-formatted string
(no jq), one append under non-blocking `flock -n`. On contention or fs
error, drop the sentinel silently (no recursive sentinel). `flock_timeout`
counts under sustained contention are a strict LOWER BOUND — sentinel's
non-blocking flock fails for the same reason the data flock did.

### FR3: Aggregator Drop Counts

All three aggregators expose per-class drop counts in their existing JSON
output:

- `scripts/skill-freshness-aggregate.sh` — adds `drops_jq_fail_count`,
  `drops_flock_timeout_count` (if applicable), `drops_rotation_fail_count`
  to the top-level summary object.
- `scripts/rule-metrics-aggregate.sh` — adds the same three fields to its
  summary, AND extends the orphan-gate to exempt sentinel lines (lines with
  `error` key set are sentinels, not rule-id orphans).
- `plugins/soleur/skills/compound/scripts/token-efficiency-report.sh` —
  adds the same three fields to its summary.

Aggregators MUST filter sentinel lines out of their data-line aggregations
(e.g., session-tokens aggregation must not count a sentinel as an envelope).

### FR4: Compound Phase 1.6 Render

`token-efficiency-report.sh` (or its caller in compound Phase 1.6) renders a
single line ABOVE the top-3 cost table (a quality-of-data caveat on the
entire table, NOT a row in it) when total drops in the analysis window
> 0:

```
Subagent envelopes incomplete: <N> drops (jq_fail=<a>, flock_timeout=<b>, rotation_fail=<c>)
```

Suppress the line entirely when N = 0. Suppress per-class breakdowns where
the count is 0.

### FR5: Schema Documentation

Document the schema in `.claude/hooks/lib/incidents.sh`'s header (or a
sibling `lib/telemetry-sentinels.md` reference). Header MUST explicitly call
out:

- The three classes covered.
- That `fs-error` is undetectable in-band and tracked separately.
- The discriminator: `error` key presence.
- The aggregator-side filter contract.

## Technical Requirements

### TR1: No Schema Version Bump

Stay on `schema:1`. The discriminator is the presence of the `error` key.
This keeps old aggregator versions fail-soft (they would count sentinels as
data lines — under-count of drops, not over-count of data).

### TR2: Aggregator Backwards Compatibility

Aggregator changes MUST be monotonic with respect to existing JSON output:
add new fields, do not rename or remove existing fields. Tests for existing
aggregator output shape must continue to pass.

### TR3: Orphan-Gate Exemption Pattern

`rule-metrics-aggregate.sh` already exempts the synthetic `te-*` rule_id
prefix. Extend the exclusion using the more general "lines with `error` key
set are sentinels" check, NOT by adding a synthetic prefix. The general
check covers future drop classes without code change.

### TR4: Test Coverage

Test files exist for each component touched. Each must gain coverage for:

- Sentinel emission for each applicable drop class on each hook
  (inducing the failure mode is straightforward: `JQ=/bin/false` for
  `jq_fail`; `flock` busy file for `flock_timeout`; pre-set
  `LOG_ROTATION_DISABLE=1` then asserted-fail rotation for `rotation_fail`).
- Aggregator filter correctness (a fixture file mixing data + sentinel
  lines; the data aggregation must equal the data-only count, the drop
  count must equal the sentinel count).
- Orphan-gate exemption for `rule-metrics-aggregate.sh`.

Test fixtures MUST contain only synthesized data per
`cq-test-fixtures-synthesized-only`.

### TR5: Sentinel Write Latency Bound

Sentinel emission adds at most ~1 second per drop site (1s flock timeout for
the sentinel append). Total worst-case hook latency on a `flock_timeout`
drop: 5s data-write timeout + 1s sentinel-write timeout = 6s. Acceptable
under the existing fire-and-forget contract.

### TR6: No Python Sibling Changes (v1)

`security_reminder_hook.py emit_incident` is unchanged in v1. Its lines
never set `error`, so the bash-side sentinel filter is monotonic.

## Acceptance Criteria

- [ ] Schema documented in `.claude/hooks/lib/incidents.sh` header (or sibling reference) with the three classes, the fs-error scope-out, the discriminator, and the aggregator filter contract.
- [ ] All three hooks emit sentinels on every detectable drop class for that hook (`flock_timeout` only where applicable).
- [ ] All three aggregators expose `drops_<class>_count`, filter sentinels from data aggregations, and (rule-metrics) exempt sentinels from the orphan-gate.
- [ ] Compound Phase 1.6 renders the drop-count line only when N > 0.
- [ ] Tests pass for sentinel emission (per class per hook), aggregator filter correctness, and orphan-gate exemption.
- [ ] Follow-up issue filed for an `fs-error` disk-space monitor (deferred).
- [ ] Decision recorded for `skill-invocation-logger.sh` flock-timeout (add 5s timeout, or document as no-op for that class).
