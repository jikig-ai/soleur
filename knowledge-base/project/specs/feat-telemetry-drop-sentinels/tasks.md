# Tasks: Telemetry-Drop Sentinels

Derived from `knowledge-base/project/plans/2026-05-10-feat-telemetry-drop-sentinels-plan.md`. Tracks #3509.

Phase order is load-bearing for TDD — Phase 1 (helper, dormant) ships before any caller depends on it; Phase 2 (rotation contract) ships before Phase 3 wires it; Phase 4 (aggregator filter) ships before any sentinel reaches a weekly cron.

## Phase 1 — Helper inline in `lib/incidents.sh`

- [x] **1.1** Edit `.claude/hooks/lib/incidents.sh`: add `_emit_drop_sentinel <active_file_path> <hook_event_literal> <class>` function with full schema-doc header (schema shape, three covered classes, fs_error scope-out citing #3523, discriminator = `error` key presence, no-recursion contract, aggregator-filter contract, compound Phase 3.5 contract, strict-lower-bound caveat for `flock_timeout`).
- [x] **1.2** Add backref one-liner above `emit_incident` pointing readers to `_emit_drop_sentinel`.
- [x] **1.3** Add standalone test for `_emit_drop_sentinel` to `tests/hooks/test_incidents.sh`: `set -u`-clean call signature, fixed-string format (no jq), non-blocking flock fallback when sibling shell holds the lock.
- [x] **1.4** Run `tests/hooks/test_incidents.sh` — all existing tests still green; new test passes.

## Phase 2 — Rotation primitive contract change

- [x] **2.1** Edit `.claude/hooks/lib/log-rotation.sh`: change archive-write-failure path to `return 1` (currently silently returns 0). Preserve `/tmp/log-rotation-warned-$$` rate-limited stderr warn.
- [x] **2.2** Update `lib/log-rotation.sh` header to document the new return-code contract; note existing `|| true` callers unaffected.
- [x] **2.3** Add T-N to `.claude/hooks/log-rotation.test.sh`: assert `rotate_if_needed` returns 1 on archive-write failure (induce via read-only parent dir or read-only archive target).
- [x] **2.4** Run `log-rotation.test.sh` — existing tests stay green; new T-N passes.

## Phase 3 — Hook-side sentinel emission

- [x] **3.1** `.claude/hooks/agent-token-tee.sh`: source `lib/incidents.sh` (for `_emit_drop_sentinel`); replace L116 `rotate_if_needed ... || true` with explicit guard + `_emit_drop_sentinel "$file" "PostToolUse" rotation_fail`; replace L121-130 jq fail-soft exit with sentinel + same exit; at L135 `flock -w 5` timeout, add sentinel emission (preserve the existing stderr echo).
- [x] **3.2** Add fixtures to `agent-token-tee.test.sh`: jq_fail, flock_timeout, rotation_fail (3 cases).
- [x] **3.3** `.claude/hooks/skill-invocation-logger.sh`: source `lib/incidents.sh`; wrap rotation call with sentinel guard; replace L62-68 jq fail-soft exit with sentinel + same exit. Do NOT add `flock -w 5` (decided in plan-review).
- [x] **3.4** Add fixtures to `skill-invocation-logger.test.sh`: jq_fail, rotation_fail (2 cases).
- [x] **3.5** `.claude/hooks/lib/incidents.sh::emit_incident`: wrap rotation call with sentinel guard; on jq line-build fail, emit sentinel before `return 0`. Do NOT add `flock -w 5` (decided in plan-review). Preserve existing per-`$$` rate-limited stderr warn.
- [x] **3.6** Add fixtures to `tests/hooks/test_incidents.sh`: emit_incident jq_fail, rotation_fail (2 cases).
- [x] **3.7** Run all hook test files — all green.

## Phase 4 — Aggregator updates + compound Phase 3.5 prose + spec alignment

- [x] **4.1** `scripts/rule-metrics-aggregate.sh`: tighten L107 `valid_stream` filter to `jq -R 'fromjson? | select(. != null) | select(.schema == 1) | select(.rule_id != null)'`. This is the load-bearing fix — sentinels never enter `valid_lines` or the reduce; existing operator-facing semantics preserved.
- [x] **4.2** `scripts/rule-metrics-aggregate.sh`: add separate jq pass over `INCIDENTS_MERGED` filtering `select(.error != null)` grouped by `.error`; populate `summary.drops_jq_fail_count` and `summary.drops_rotation_fail_count` (no flock_timeout for this sink).
- [x] **4.3** `scripts/rule-metrics-aggregate.sh`: confirm orphan-gate behavior unchanged (existing `te-*` exemption stays untouched).
- [x] **4.4** Add fixture to `scripts/rule-metrics-aggregate.test.sh`: input with one sentinel + one valid `deny` line → assert no `"null"` rule_id in output, `drops_jq_fail_count == 1`, `summary.orphan_rule_ids` unchanged. Plus archived (gzipped) sentinel fixture asserts cross-archive count.
- [x] **4.5** `scripts/skill-freshness-aggregate.sh`: add separate jq pass for `drops_jq_fail_count` and `drops_rotation_fail_count`.
- [x] **4.6** Add fixtures to `scripts/skill-freshness-aggregate.test.sh`: drops counted; sentinels never appear in `skills[]`.
- [x] **4.7** `plugins/soleur/skills/compound/scripts/token-efficiency-report.sh`: add separate jq pass over `SESSION_TOKENS_MERGED` for all three drop classes (this sink HAS flock_timeout via agent-token-tee.sh).
- [x] **4.8** `plugins/soleur/skills/compound/scripts/token-efficiency-report.sh`: render an above-table line when total drops > 0 — format: `Subagent envelopes incomplete: <N> drops (<class>=<count>, ...)`. Suppress entire line when 0; suppress per-class zeros in breakdown; always plural.
- [x] **4.9** Add fixtures to token-efficiency report tests: render-line behavior (one class non-zero, all three non-zero, total zero); archived sentinel counts.
- [x] **4.10** `plugins/soleur/skills/compound/SKILL.md` Phase 3.5 (line 162 area): edit prose to add explicit "filter event_type ∈ {deny, bypass} and ignore lines where `error` is set" instruction.
- [x] **4.11** `knowledge-base/project/specs/feat-telemetry-drop-sentinels/spec.md`: spec alignment already applied in plan-review (FR2 and FR4 updated). Verify no other sections drifted.
- [x] **4.12** Run `scripts/rule-metrics-aggregate.test.sh`, `scripts/skill-freshness-aggregate.test.sh`, and token-efficiency report tests — all green.

## Phase 5 — Cross-cutting validation

- [x] **5.1** Run all hook + aggregator + lib test files in sequence. All green.
- [x] **5.2** Manual smoke: source `lib/incidents.sh`, call `_emit_drop_sentinel /tmp/sink.jsonl PostToolUse jq_fail`, verify file contains exactly one well-formed sentinel line with correct schema/hook_event/error/ts.
- [x] **5.3** Manual smoke: induce a real `flock_timeout` in a test harness on `agent-token-tee.sh` (sibling shell holds lock for 6s); verify sentinel lands in `.claude/.session-tokens.jsonl` AND existing stderr echo also fires.
- [x] **5.4** Run `bash scripts/rule-metrics-aggregate.sh --dry-run` against a fixture with sentinels mixed in; verify exit 0, no orphan-gate failure, drop counts populated.
- [ ] **5.5** Push branch and run plan-review (already done 2026-05-10) → multi-agent review at PR-ready time per `/soleur:review`.
- [ ] **5.6** PR body: `Closes #3509` AND `Ref #3523`. Verify scanner does not flag `Ref #3523` as auto-close (it is keyword-safe).
- [ ] **5.7** Post-merge: monitor first weekly rule-metrics cron run; verify no orphan-gate failure.
- [ ] **5.8** Post-merge: monitor first compound run with diff ≥ 50 lines; verify above-table render (or absence on healthy run).

## Acceptance Criteria Mapping

Tasks above map 1:1 to plan AC bullets. Pre-merge AC: tasks 1.x–4.x + 5.1–5.6. Post-merge AC: tasks 5.7–5.8.

## Rollout

Single PR (#3512). All Phase 1-5 changes merge together. Phase order is TDD-load-bearing (Phase 4's filter must be in the same merge as Phase 3's first sentinel emitter — pre-PR rule-metrics would crash on `"null"` rule_id otherwise).
