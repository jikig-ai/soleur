---
date: 2026-05-10
topic: telemetry-drop-sentinels
issue: 3509
related_issues: [3494, 3495, 3508, 3122, 2865]
status: ready-to-plan
---

# Telemetry-Drop Sentinels — Cross-Sink Schema

## What We're Building

A minimal in-band sentinel-line schema written to the three telemetry JSONL sinks
(`.claude/.session-tokens.jsonl`, `.claude/.skill-invocations.jsonl`,
`.claude/.rule-incidents.jsonl`) so that compound Phase 1.6 and the weekly
aggregators can detect and count silent drops at the three emit-side failure
classes that ARE detectable in-band:

- `jq_fail` — JSON line builder returned non-zero
- `flock_timeout` — `flock -w 5` timed out under contention
- `rotation_fail` — `rotate_if_needed` (#3508) reported a non-zero outcome

Each drop emits one line:

```json
{"schema":1,"hook_event":"<PreToolUse|PostToolUse>","error":"<class>","ts":"<iso8601>"}
```

The three aggregators (`scripts/skill-freshness-aggregate.sh`,
`scripts/rule-metrics-aggregate.sh`,
`plugins/soleur/skills/compound/scripts/token-efficiency-report.sh`) each expose
`drops_<class>_count` in their existing JSON output, filter sentinels out of
their data-line aggregations, and (compound only) render
`Subagent envelopes incomplete: N drops` in the top-3 cost table when N > 0.

## Why This Approach

The issue (#3509) proposed an in-band shared sentinel schema. We pressure-tested
it and found one acceptance criterion ("All three hooks emit a sentinel on each
silent-drop class") is unachievable: an `fs-error` class drop means the disk
write itself failed, and a sentinel write to the same file fails for the same
reason. The honest scope is the three classes above — fs-error is an
undetectable floor that requires a separate disk-space monitor (out of scope).

Three architectures were considered:

1. **In-band sentinel** (chosen) — reuses three existing readers; smallest
   blast radius; cannot detect fs-error.
2. **Out-of-band drop sink** (`.claude/.telemetry-drops.jsonl`) — viable now
   that #3508 shipped a generic `rotate_if_needed`. Rejected as
   over-engineered: it doesn't actually escape the medium (drop sink shares
   the same disk), and adds a new aggregator surface for marginal gain.
3. **Measure first, schema later** — would have been sound if the parent PR
   chain were still in flight. With #3495 + #3508 merged, the implementation
   floor is clear and the cost of a minimal schema is small enough that
   shipping is cheaper than instrumentation-then-design.

The chosen schema is field-additive on existing JSONL: data lines have no
`error` field, sentinels do. Aggregators distinguish via `error` key presence
(no schema bump). This avoids touching the Python sibling
(`security_reminder_hook.py emit_incident`) for v1 — its lines never set
`error`, so the filter is monotonic.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Architecture | In-band, same JSONL | Zero new sinks; reuses existing readers; smallest delta. |
| Drop classes covered | `jq_fail`, `flock_timeout`, `rotation_fail` | Three in-band-detectable classes; fs-error documented as out-of-scope. |
| Schema fields | `{schema:1, hook_event, error, ts}` | Minimal, fits well under PIPE_BUF, less likely to fail under the same contention that triggered the drop. |
| Aggregator coverage | All three aggregators expose `drops_<class>_count` | Cross-sink visibility; the orphan-gate work is already required for one — extending to three is marginal. |
| Phase 1.6 render threshold | Only render the line when `N > 0` in window | Matches the issue's re-eval trigger; no noise on healthy runs. |
| Schema version bump | None (v1 retained) | Field-additive; `error` key presence is the discriminator. |
| Backward compat | Sentinels filtered at aggregator read time, not at write time | Old aggregator versions would count sentinels as data lines (under-count of drops, not over-count of data) — fail-soft. |

## Sequencing Constraints (resolved 2026-05-10)

- **Resolved:** PR #3495 merged at 12:53 UTC — `agent-token-tee.sh` and
  `token-efficiency-report.sh` now on main.
- **Resolved:** PR #3508 merged at 13:32 UTC — `.claude/hooks/lib/log-rotation.sh`
  shipped with generic `rotate_if_needed <path> [size] [age]`. Rotation-fail is
  now a real drop class to instrument.

No remaining cross-PR sequencing.

## Cross-Cutting Refactor Surface

Files touched (verified via `find` on rebased main):

**Hook-side (3 emit paths):**
- `.claude/hooks/agent-token-tee.sh` (PostToolUse, session-tokens)
- `.claude/hooks/skill-invocation-logger.sh` (PreToolUse, skill-invocations) — note: currently no `flock -w` timeout; `flock_timeout` class is therefore not yet reachable here. Plan should decide whether to (a) add a 5s timeout for parity, or (b) document that this hook has no timeout class.
- `.claude/hooks/lib/incidents.sh::emit_incident` (rule-incidents) — has rate-limited per-`$$` stderr warning on write fail; sentinel emission is additive.

**Aggregator-side (3 readers):**
- `scripts/skill-freshness-aggregate.sh`
- `scripts/rule-metrics-aggregate.sh` (orphan-gate already exempts `te-*` synthetic prefixes — extend the same pattern for sentinel lines via `error` key presence)
- `plugins/soleur/skills/compound/scripts/token-efficiency-report.sh` (Phase 1.6 render-site)

**Tests (existing test files indicate per-component test scope):**
- `.claude/hooks/agent-token-tee.test.sh`
- `.claude/hooks/skill-invocation-logger.test.sh`
- `tests/hooks/test_incidents.sh`
- `scripts/skill-freshness-aggregate.test.sh`
- `scripts/rule-metrics-aggregate.test.sh`

## Acceptance Criteria (revised from #3509)

- [ ] Schema for sentinel lines documented in `.claude/hooks/lib/incidents.sh` header AND a sibling reference (e.g., `lib/telemetry-sentinels.md` or inline header in each hook). Schema: `{schema:1, hook_event, error:<jq_fail|flock_timeout|rotation_fail>, ts}`.
- [ ] All three hooks emit a sentinel on each of the three in-band-detectable drop classes (jq_fail, flock_timeout, rotation_fail). `skill-invocation-logger.sh` may legitimately not have a `flock_timeout` site (no timeout currently) — plan-time decision.
- [ ] All three aggregators count drops, expose `drops_<class>_count` in their JSON output, filter sentinels out of data-line aggregations, and do not flag sentinels as orphans (rule-metrics).
- [ ] Compound Phase 1.6 surfaces "Subagent envelopes incomplete: N drops" (or per-class breakdown) in its top-3 cost table when N > 0; suppresses the line when N = 0.
- [ ] Tests cover: sentinel emission for each class on each hook (where applicable); aggregator filter correctness; orphan-gate exemption.
- [ ] `fs-error` class is explicitly documented as out-of-scope in the schema header; pointer to a follow-up disk-space monitor issue.

## Non-Goals

- **fs-error class detection.** Disk-write failures are an undetectable floor for any in-band sentinel. A separate disk-space monitor is the right mitigation; out of scope here.
- **Python `emit_incident` sibling parity.** `security_reminder_hook.py` does not currently emit sentinels. Its lines never set `error`, so the bash-side filter is monotonic. Add Python parity only if a Python-side drop class is later identified.
- **Schema v2 / extra fields.** No `session_id`, no `cause_snippet`. Forensic correlation rides on the next adjacent data line's timestamp + session_id (drops cluster temporally).
- **Always-on Phase 1.6 render.** Zero-drop windows produce no render line.
- **Drop sink as separate file.** Out-of-band sink rejected; do not introduce `.claude/.telemetry-drops.jsonl`.

## Deferred Items (need tracking issues)

- **`fs-error` disk-space monitor** — parallel issue to track an out-of-band disk-watcher (e.g., periodic `df -h .claude` check + threshold warning). Re-evaluation: when first operator reports a "zero counts after disk-full" incident, OR when the rotation primitive's stderr warnings show non-trivial frequency.
- **Python `emit_incident` sentinel parity** — out-of-scope until a Python-side drop site emerges. Re-evaluation: when `security_reminder_hook.py` adds a flock-protected write or jq-equivalent path that can fail.
- **`skill-invocation-logger.sh` flock timeout** — plan-time decision: add a 5s timeout for parity OR document this hook has no `flock_timeout` class. If we add the timeout, file the decision as a small follow-up. Re-evaluation: at plan time.

## Open Questions (for plan-time, not blocking spec)

1. **Rotation-fail signaling.** `rotate_if_needed` currently has its own
   stderr warning + `/tmp/log-rotation-warned-$$` rate-limiter. Does the
   plan extend it to return a non-zero status to its caller (so hooks can
   write a `rotation_fail` sentinel on their own write-fd), or extend
   `rotate_if_needed` itself to write the sentinel inside the caller's
   flock context? The latter avoids re-acquiring flock; the former keeps
   the rotation primitive single-purpose.
2. **Orphan-gate filter shape.** Extend the existing `te-*` synthetic
   exclusion to also exempt lines where `error` is set, OR introduce a
   first-class "is_sentinel" check based on `error` key presence. The
   second is more general; the first is one line of regex.
3. **Render granularity in Phase 1.6.** The issue body says "N drops"
   (single integer); the schema supports per-class counts. Plan should
   pick: single-line summary, per-class breakdown, or both.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

(No domain leaders spawned: this is internal observability infrastructure with
no user-brand-critical signal, no new user-facing capability, no marketing
surface, no expense or vendor signal. The brainstorm itself is the
engineering architectural assessment per the passive-routing rule that excludes
recursive CTO consultation during engineering brainstorms about architecture.)
