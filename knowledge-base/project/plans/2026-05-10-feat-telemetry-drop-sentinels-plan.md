---
title: "feat: Telemetry-Drop Sentinels (Cross-Sink Schema)"
type: feat
date: 2026-05-10
issue: 3509
spec: knowledge-base/project/specs/feat-telemetry-drop-sentinels/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-10-telemetry-drop-sentinels-brainstorm.md
requires_cpo_signoff: false
---

# Plan: Telemetry-Drop Sentinels (Cross-Sink Schema)

Tracks #3509. Brainstorm captured 2026-05-10. Sequencing prereqs #3495 (token-efficiency analysis) and #3508 (shared log-rotation) both merged 2026-05-10 — clean to implement.

Plan-review applied 2026-05-10 (DHH + Kieran + Simplicity reviewers). Three P1 correctness fixes folded in (phase order, `$HOOK_EVENT` shape, `valid_lines` semantics). `flock -w 5` parity additions dropped per DHH (gold-plating; no observed wedged sessions). Helper file + runbook collapsed per DHH + Simplicity (YAGNI).

## Overview

Three telemetry sinks under `.claude/` are written by Bash hooks following a fire-and-forget contract: every error path returns success silently. Compound Phase 1.6, the rule-metrics weekly cron, and the skill-freshness aggregator have no in-band signal to detect when their input streams are incomplete. Add an in-band sentinel-line schema (`{schema:1, hook_event, error, ts}`) so three drop classes (`jq_fail`, `flock_timeout`, `rotation_fail`) become countable. The fourth class (`fs_error`) is undetectable in-band by definition (a sentinel write to the same disk fails for the same reason as the data write) and is scoped out as follow-up #3523.

## User-Brand Impact

- **If this lands broken, the user experiences:** Phase 1.6 cost reports under- or over-count subagent envelopes; rule-metrics weekly aggregator misreports rule-fire activity; operator decisions on bad telemetry (retire a load-bearing rule, miss a runaway-cost pattern, under-investigate a real incident).
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A. Sentinel lines contain only `hook_event` and class-string literals — no session content, no PII, no secrets.
- **Brand-survival threshold:** none

The sensitive-path regex in `plugins/soleur/skills/preflight/SKILL.md` Check 6.1 covers `apps/web-platform/...`, `apps/[^/]+/infra/`, and credential-handling workflows. This PR's diff lands in `.claude/hooks/`, `scripts/`, and `plugins/soleur/skills/compound/scripts/` — none match. Check 6 will SKIP at ship time. No `threshold: none, reason:` scope-out bullet required.

## Research Insights

**Files verified on rebased main (post #3495 + #3508 merge):**

| File | Role | Notes |
|---|---|---|
| `.claude/hooks/agent-token-tee.sh` | PostToolUse Task hook → `.session-tokens.jsonl` | Has explicit `flock -w 5` timeout (line 135) with stderr-only echo |
| `.claude/hooks/skill-invocation-logger.sh` | PreToolUse Skill hook → `.skill-invocations.jsonl` | Indefinite `flock -x 9` (no `flock_timeout` site — kept indefinite per DHH review) |
| `.claude/hooks/lib/incidents.sh::emit_incident` | Library → `.rule-incidents.jsonl` | Indefinite `flock`; per-`$$` rate-limited stderr warn on write fail (preserved). Will host the new `_emit_drop_sentinel` helper inline |
| `.claude/hooks/lib/log-rotation.sh` | Generic `rotate_if_needed <path>` (#3508) | Currently always `return 0`; this PR adds `return 1` on archive-write failure |
| `scripts/rule-metrics-aggregate.sh` | Weekly cron aggregator | `te-*` orphan-gate exemption at L200-205; output-schema gate at L232 but no consumer-side `select(.schema == 1)` before reduce |
| `scripts/skill-freshness-aggregate.sh` | Monthly skill-freshness aggregator | Filter at L114: `.schema == 1 and .skill != null and (.ts \| type) == "string"` — sentinels (no `.skill`) implicitly excluded from data |
| `plugins/soleur/skills/compound/scripts/token-efficiency-report.sh` | Phase 1.6 outlier detector + render | Filter at L191: `.schema == 1 and .session_id == $s and .ts < $cts` — sentinels (no `.session_id`) implicitly excluded |

**Fourth reader the spec missed:** `plugins/soleur/skills/compound/SKILL.md` Phase 3.5 (line 162) reads `.rule-incidents.jsonl` directly inside the compound skill's Deviation Analyst prose, filtering to `event_type ∈ {deny, bypass}` — sentinels have no `event_type`, so they are excluded incidentally. This is currently prose-implicit, not contractual; add explicit "ignore lines with `error` set" to the prose.

**Critical sharp edges from prior learnings (lifted from `learnings-researcher` survey):**

1. `flock` locks are per-inode, not per-path. Canonicalize via `cd -P + pwd -P` on every emit-side path (precedent: `2026-04-24-rule-metrics-emit-incident-coverage-session-gotchas.md` Gotcha 1). All three production hooks already do this — sentinel emission must use the same canonical path.
2. Schema version must be asserted at every consumer (`jq -e '.schema == 1'`), not only on emit (`2026-04-18-schema-version-must-be-asserted-at-consumer-boundary.md`). Sentinel lines stamp `schema:1`; the consumer-side gate already exists in skill-freshness and token-efficiency-report; rule-metrics has the output-shape gate but no input-shape gate. Fold the missing gate in.
3. Field-additive schema changes are NOT safe with `select(.field == X)` consumers (`2026-04-24-...-session-gotchas.md` Gotcha 3). `select(.error == "jq_fail")` over a record where `.error` is null returns false silently. Grep all `select(...)` consumers in fixtures + production scripts before relying on field-additive.
4. `PIPE_BUF` (4096B) atomicity does NOT apply to regular files. The flock is load-bearing, not belt-and-suspenders. Cap line size + assume O_APPEND only guarantees cursor position.
5. Hook test stubs must place sentinels INSIDE recognized `case` branches with a catch-all `*)` failure (`test-failures/2026-04-22-path-prefix-gh-stub-signal-drift-resistance.md`).

External research: skipped per Phase 1.6 (strong local context, no external API). Functional overlap: skipped — internal hook telemetry has no skill/agent registry analog.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified) | Plan response |
|---|---|---|
| "All three hooks have a `flock_timeout` site" | Only `agent-token-tee.sh` has `flock -w 5`. `skill-invocation-logger.sh` and `incidents.sh::emit_incident` use indefinite `flock -x 9` | Document `flock_timeout` as N/A for those two hooks (per-hook map in Phase 3). Do NOT add timeouts (gold-plating per DHH review). |
| "Aggregators expose `drops_<class>_count`" | `rule-metrics-aggregate.sh` reduces by `.rule_id` and would create a `"null"` key for sentinels (jq object indexing by null) | Add `select(.rule_id != null)` BEFORE the reduce in rule-metrics; verify the other two aggregators do not have a corresponding hazard |
| "Orphan-gate exempts sentinels via `error` key presence" | Existing `te-*` exemption is unrelated; sentinels have no `rule_id` to be flagged on, so the orphan-set diff already excludes them — but only AFTER the reduce gate prevents the `"null"` key from poisoning `$known_ids` | Strict ordering: filter `.rule_id != null` BEFORE reduce → sentinel never enters `$counts` → never appears in orphan-set computation. The `te-*` exemption stays untouched. |
| "Aggregator `valid_lines` semantics unchanged" | Sentinels are truthy parses and would inflate `valid_lines` in rule-metrics (Kieran P1 finding) | `valid_lines` filter tightened to `select(.rule_id != null)`; sentinels counted only in `drops_<class>_count`. Existing operator-facing semantics (valid = data) preserved. |
| "Compound Phase 1.6 surfaces 'Subagent envelopes incomplete'" | `token-efficiency-report.sh` already filters by `.session_id == $s` for the data path. A separate sentinel-counting pass needs to read across `SESSION_TOKENS_MERGED` (active + archives, already merged at L60-64) without the session_id gate | Add a separate sentinel-count pass over `SESSION_TOKENS_MERGED` filtering on `select(.error != null)`. Render the line above the existing top-3 cost table when N > 0 (a quality-of-data caveat, not a cost row). Spec FR4 updated in the same PR. |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal observability infrastructure with no user-brand-critical signal, no new user-facing capability, no marketing surface, no expense or vendor signal. Brainstorm Phase 0.5 carry-forward (all 8 domains assessed, no leaders spawned). Product/UX Gate: NONE — no new component files, no user-facing pages.

## Files to Edit

- `.claude/hooks/lib/incidents.sh` — add `_emit_drop_sentinel <active_file_path> <hook_event_literal> <class>` function inline (no separate file per DHH/Simplicity review); document the schema, three classes, fs_error scope-out, discriminator, no-recursion contract, and aggregator-filter contract in the function's header banner. Update `emit_incident` body: emit sentinel on `jq_fail` and `rotation_fail` drop sites (no `flock_timeout` — indefinite flock retained).
- `.claude/hooks/agent-token-tee.sh` — source nothing new (already sources `lib/log-rotation.sh`; needs to source `lib/incidents.sh` to access the helper); emit sentinel on `jq_fail`, `flock_timeout` (existing site), `rotation_fail`; check `rotate_if_needed`'s new return code.
- `.claude/hooks/skill-invocation-logger.sh` — source `lib/incidents.sh` for the helper; emit sentinel on `jq_fail` and `rotation_fail` (no `flock_timeout` — indefinite flock retained per review).
- `.claude/hooks/lib/log-rotation.sh` — `rotate_if_needed` returns 1 on archive-write failure (currently always 0); update header to document the new return-code contract; preserve fire-and-forget for callers via existing `|| true` patterns (still safe — non-zero return is opt-in for sentinel-aware callers).
- `scripts/rule-metrics-aggregate.sh` — tighten `valid_stream` filter at L107 to `fromjson? | select(.) | select(.rule_id != null)` so sentinels never enter the reduce (fixes the `"null"` rule_id hazard at the source); add consumer-side `select(.schema == 1)` to the same filter; add a separate jq pass over `INCIDENTS_MERGED` to count sentinels by class → add `drops_jq_fail_count`, `drops_rotation_fail_count` fields to `summary` (no `flock_timeout` for this sink — `emit_incident` keeps indefinite flock); existing operator-facing `valid_lines` and orphan-gate semantics unchanged.
- `scripts/skill-freshness-aggregate.sh` — existing filter (`schema == 1 and .skill != null`) already excludes sentinels from data; add a separate jq pass over `INVOCATIONS_MERGED` for `drops_jq_fail_count`, `drops_rotation_fail_count` (no `flock_timeout` for this sink).
- `plugins/soleur/skills/compound/scripts/token-efficiency-report.sh` — existing filter (`session_id == $s`) already excludes sentinels from envelope-sum; add a separate jq pass over `SESSION_TOKENS_MERGED` for `drops_jq_fail_count`, `drops_flock_timeout_count`, `drops_rotation_fail_count` (this sink HAS a `flock_timeout` site via agent-token-tee.sh); render an above-table line when total drops > 0 (per format below).
- `plugins/soleur/skills/compound/SKILL.md` — Phase 3.5 reader prose: add explicit "ignore lines where `error` is set" instruction (3-line edit; was implicit).
- `knowledge-base/project/specs/feat-telemetry-drop-sentinels/spec.md` — align FR4 wording with plan: render line is ABOVE the table (a quality-of-data caveat), not a row in the cost table. Update FR2's `flock_timeout` coverage claim to N/A for `skill-invocation-logger.sh` and `incidents.sh::emit_incident`.
- `.claude/hooks/agent-token-tee.test.sh` — add fixtures for jq_fail, flock_timeout, rotation_fail (3 cases).
- `.claude/hooks/skill-invocation-logger.test.sh` — add fixtures for jq_fail, rotation_fail (2 cases).
- `tests/hooks/test_incidents.sh` — add fixtures for `emit_incident` jq_fail and rotation_fail (2 cases); add fixture for `_emit_drop_sentinel` standalone (1 case asserting `set -u` clean call signature; fixed-string formatting; non-blocking flock fallback).
- `.claude/hooks/log-rotation.test.sh` — assert new return code on rotation failure (induce via read-only parent); existing tests stay green.
- `scripts/rule-metrics-aggregate.test.sh` — assert no `"null"` rule_id appears in output when sentinels are present; assert `drops_<class>_count` populated; assert orphan-gate untouched; one fixture with archived (gzipped) sentinel asserts cross-archive count.
- `scripts/skill-freshness-aggregate.test.sh` — assert `drops_<class>_count` populated; assert sentinels never appear in `skills[]`.
- Token-efficiency report tests (verify existing test surface; add if absent) — assert above-table render when N>0; suppressed when N=0; per-class breakdown shows only non-zero classes.

## Files to Create

None. Helper folds into existing `lib/incidents.sh`; runbook dropped per DHH/Simplicity review.

## Open Code-Review Overlap

**Status:** None. Verified against 70 open `code-review` issues (`gh issue list --label code-review --state open`). No issue body contains any of the planned file paths.

## Implementation Phases

### Phase 1 — Helper inline in `lib/incidents.sh` (foundations, no behavior change)

1. Edit `.claude/hooks/lib/incidents.sh`. Add a new banner-separated section:

   ```text
   # --- Telemetry-drop sentinels --------------------------------------------
   # Schema: {"schema":1,"hook_event":"<PreToolUse|PostToolUse>","error":"<jq_fail|flock_timeout|rotation_fail>","ts":"<iso8601>"}
   # Three classes covered; fs_error scoped out (#3523) — sentinel write to same disk fails for same reason as data write.
   # Discriminator: `error` key presence. Data lines have no `error`; sentinels do.
   # No-recursion contract: helper has exactly one failure mode (silently drop the sentinel).
   #   - Pre-formatted JSON string (no jq) elides the jq_fail class for the sentinel itself.
   #   - Non-blocking `flock -n` elides the flock-contention class — sentinel under sustained
   #     contention is by definition uncountable (the same lock is held); coverage is best-effort.
   # Aggregator filter contract:
   #   - rule-metrics-aggregate.sh: `select(.rule_id != null)` BEFORE reduce.
   #   - skill-freshness-aggregate.sh: existing `.skill != null` already excludes.
   #   - token-efficiency-report.sh: existing `.session_id == $s` already excludes.
   # Compound Phase 3.5 contract:
   #   - filter event_type ∈ {deny, bypass} AND ignore lines with `error` set.
   # `flock_timeout` counts are a strict LOWER BOUND under sustained contention.
   _emit_drop_sentinel() {
     local active="${1:-}" hook_event="${2:-}" class="${3:-}"
     [[ -z "$active" || -z "$hook_event" || -z "$class" ]] && return 0
     local ts
     ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || ts="1970-01-01T00:00:00Z"
     # Pre-formatted JSON. Class is from a known-safe enum (caller responsibility).
     # No jq. Single-line. Will land in <80 bytes.
     local sentinel="{\"schema\":1,\"hook_event\":\"${hook_event}\",\"error\":\"${class}\",\"ts\":\"${ts}\"}"
     # Best-effort append. Non-blocking flock; on contention or fs error, drop silently.
     ( flock -n 9 || exit 0; printf '%s\n' "$sentinel" >&9 ) 9>>"$active" 2>/dev/null || true
     return 0
   }
   ```

2. Header docstring above `emit_incident` adds a one-line backref: "See `_emit_drop_sentinel` below for the sentinel-line discriminator and aggregator-filter contract."
3. No callers wired yet — Phase 1 ships the helper only.
4. Update `tests/hooks/test_incidents.sh` with one standalone test for `_emit_drop_sentinel` (fixed-string format; `set -u` clean call; non-blocking flock fallback when held by sibling shell). Existing `emit_incident` tests stay green.

### Phase 2 — Rotation primitive contract change

1. Edit `.claude/hooks/lib/log-rotation.sh`:
   - Change archive-write-failure path to `return 1` (currently exits the subshell silently, returns 0).
   - Update header: document the new return-code contract. Existing fire-and-forget callers using `|| true` are unaffected; new sentinel-aware callers use `if ! rotate_if_needed ...; then _emit_drop_sentinel ...; fi`.
   - Preserve the existing `/tmp/log-rotation-warned-$$` rate-limited stderr warn.
2. Update `.claude/hooks/log-rotation.test.sh`: add T-N — assert `rotate_if_needed` returns 1 on archive-write failure (induce via read-only parent dir or a read-only archive target). Existing tests must continue to pass.

### Phase 3 — Hook-side emission

For each of `agent-token-tee.sh`, `skill-invocation-logger.sh`, `incidents.sh::emit_incident`:

1. Source `lib/incidents.sh` if not already (the function lives there; `agent-token-tee.sh` and `skill-invocation-logger.sh` will source it). For `incidents.sh::emit_incident` the helper is already in the same file — no source needed.
2. Replace each silent-exit site with a sentinel emit + same exit, per the per-hook drop-site map below.
3. For each `rotate_if_needed` call: `if ! rotate_if_needed "$file"; then _emit_drop_sentinel "$file" "$HOOK_EVENT_LITERAL" rotation_fail; fi`. The `$HOOK_EVENT_LITERAL` is a STRING LITERAL passed at the call site — `"PostToolUse"` for `agent-token-tee.sh`, `"PreToolUse"` for `skill-invocation-logger.sh`. No global variable; helper signature takes the literal at every call site (Kieran P1 fix).

**Per-hook drop-site → class map (footnote: `mkdir`/`touch`/post-flock write-fail sites are `fs_error` class, scoped out as #3523 — undetectable in-band):**

| Hook | Site (line ref before edit) | Class | Notes |
|---|---|---|---|
| `agent-token-tee.sh` | L116 `rotate_if_needed ... \|\| true` | `rotation_fail` | Replace `\|\| true` with explicit guard + sentinel |
| `agent-token-tee.sh` | L121-130 `jq -nc ... \|\| exit 0` | `jq_fail` | Sentinel + same exit |
| `agent-token-tee.sh` | L135 `flock -w 5` timeout | `flock_timeout` | Sentinel replaces stderr-only echo (preserve echo too — operator-visible signal) |
| `skill-invocation-logger.sh` | rotate site (post Phase 2) | `rotation_fail` | New emit |
| `skill-invocation-logger.sh` | L62-68 `jq -nc ... \|\| exit 0` | `jq_fail` | Sentinel + same exit |
| `skill-invocation-logger.sh` | L72 indefinite flock | (`flock_timeout` N/A) | No timeout site — keep indefinite per DHH review |
| `incidents.sh::emit_incident` | rotate site (post Phase 2) | `rotation_fail` | New emit |
| `incidents.sh::emit_incident` | jq -nc fail (existing) | `jq_fail` | Sentinel + same return |
| `incidents.sh::emit_incident` | indefinite `flock -x 9` | (`flock_timeout` N/A) | No timeout site — keep indefinite per DHH review |

4. Update each hook's test file with applicable fixtures (3 for agent-token-tee, 2 for skill-invocation-logger, 2 for emit_incident).

### Phase 4 — Aggregator updates + compound Phase 3.5 prose

1. **`scripts/rule-metrics-aggregate.sh`** (highest-risk; lands first within Phase 4):
   - Tighten `valid_stream` filter at L107: `jq -R 'fromjson? | select(. != null) | select(.schema == 1) | select(.rule_id != null)'` — sentinels never enter `valid_lines` or the reduce; existing `valid_lines` operator-facing semantics preserved (Kieran P1 fix).
   - Add a separate jq pass over `INCIDENTS_MERGED`: `jq -R 'fromjson? | select(.error != null)'` grouped by `.error`, populating `drops_jq_fail_count` and `drops_rotation_fail_count` in the `summary` block. Note: no `drops_flock_timeout_count` for this sink (emit_incident has no timeout site post-review).
   - Verify orphan-gate untouched — `te-*` exemption stays. The new filter at L107 prevents `"null"` rule_ids from ever reaching `$known_ids`.
2. **`scripts/skill-freshness-aggregate.sh`**:
   - Existing filter excludes sentinels from data — confirm via test.
   - Add separate jq pass for `drops_jq_fail_count` and `drops_rotation_fail_count` (no `flock_timeout` for this sink).
3. **`plugins/soleur/skills/compound/scripts/token-efficiency-report.sh`**:
   - Existing filter excludes sentinels from envelope-sum — confirm via test.
   - Add separate jq pass over `SESSION_TOKENS_MERGED` for `drops_jq_fail_count`, `drops_flock_timeout_count`, `drops_rotation_fail_count` (this sink HAS the timeout site via agent-token-tee.sh).
   - Render: above the existing `### Phase 1.6: token-efficiency report` block, when total drops > 0:
     ```
     Subagent envelopes incomplete: <N> drops (<non-zero classes only as `class=count` joined by comma>).
     ```
     Format pinned by golden-file test (one class non-zero, all three non-zero); always plural ("drops"); per-class breakdown only includes non-zero classes; suppress entire line when total = 0.
4. **`plugins/soleur/skills/compound/SKILL.md`** Phase 3.5 (line 162 area):
   - Add explicit "ignore lines where `error` is set" to the prose. 3-line edit.
5. **`knowledge-base/project/specs/feat-telemetry-drop-sentinels/spec.md`** FR4: update wording so it says "above the top-3 cost table" (was "in"). FR2: update `flock_timeout` coverage claim to N/A for two of three hooks.

### Phase 5 — Tests + cross-cutting fixtures

1. Add fixture in `scripts/rule-metrics-aggregate.test.sh`: archived sentinel (gzip a small JSONL with one sentinel line) → verify the merge path counts it via `drops_<class>_count` AND confirm no `"null"` rule_id appears anywhere in output.
2. Add fixture in token-efficiency-report tests: sentinels in archive only → assert the render line appears above the table.
3. Document fixture in `tests/hooks/test_incidents.sh`: example sentinel line in a fixture file referenced from compound's Phase 3.5 prose audit (the Deviation-Analyst contract test).
4. All fixtures use synthesized data per AGENTS.md `cq-test-fixtures-synthesized-only`.

## Risks & Sharp Edges

1. **rule-metrics aggregator is NOT fail-soft against sentinels in pre-PR builds.** If hooks emit sentinels before the aggregator filter ships, the next weekly cron run fails (`exit 1` on orphan with `"null"` rule_id). Mitigation: atomic-land in single PR — Phase 1 (helper, dormant) → Phase 2 (rotation contract) → Phase 3 (hook emission, the first sentinel emitter) → Phase 4 (aggregator filter). All in one merge.
2. **Sentinel write under sustained contention is best-effort, not guaranteed.** The non-blocking `flock -n` for sentinel emission means sentinels under sustained load are themselves dropped. `flock_timeout` counts are a STRICT LOWER BOUND — they may under-report by an order of magnitude when fan-out is the cause. Schema-doc header calls this out explicitly.
3. **Sentinel emission must use canonicalized path.** All three hooks already canonicalize via `cd -P + pwd -P`. The helper takes the active file path as an argument (caller-resolved); helper does NOT re-resolve. Different inode = different lock = race.
4. **Schema discriminator is `error` key presence.** Field-additive on v1. Schema-doc lives in `_emit_drop_sentinel` header next to `emit_incident` — single source of truth.
5. **Compound Phase 3.5 is prose-implicit, not script-enforced.** The agent reading SKILL.md interprets the filter intent. Plan adds the explicit "ignore lines with `error` set" sentence; future drift would be caught at the next compound test/audit. Per Kieran P3, a script-side guard would be over-engineered for this surface.
6. **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6 and preflight Check 6. Fill it before requesting deepen-plan or `/work`.** This plan's section is filled.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `_emit_drop_sentinel` function exists in `.claude/hooks/lib/incidents.sh` with header banner documenting schema, three covered classes, fs_error scope-out (#3523), discriminator (`error` key presence), no-recursion contract, aggregator filter contract, compound Phase 3.5 contract, and the strict-lower-bound caveat for `flock_timeout`.
- [ ] All three hooks emit sentinels on each applicable drop class per the per-hook map. `flock_timeout` only present in `agent-token-tee.sh`. `skill-invocation-logger.sh` and `incidents.sh::emit_incident` keep indefinite `flock` (no `flock_timeout` site).
- [ ] `.claude/hooks/lib/log-rotation.sh` returns 1 on archive-write failure; header updated; existing `|| true` callers unaffected.
- [ ] `scripts/rule-metrics-aggregate.sh` filters `.rule_id != null` AND `select(.schema == 1)` at L107; orphan-gate behavior unchanged; `drops_jq_fail_count` and `drops_rotation_fail_count` populated in summary.
- [ ] `scripts/skill-freshness-aggregate.sh` exposes `drops_jq_fail_count` and `drops_rotation_fail_count`; existing filter unchanged.
- [ ] `plugins/soleur/skills/compound/scripts/token-efficiency-report.sh` exposes all three `drops_<class>_count` fields; render line emitted above top-3 cost table when total drops > 0; suppressed when 0; format pinned by golden-file test.
- [ ] `plugins/soleur/skills/compound/SKILL.md` Phase 3.5 prose explicitly states filter intent (`event_type ∈ {deny, bypass}`, ignore lines with `error` set).
- [ ] Spec updated: FR4 says "above the top-3 cost table"; FR2's `flock_timeout` claim updated to N/A for two of three hooks.
- [ ] Test coverage: agent-token-tee.test.sh has 3 fixtures (jq_fail, flock_timeout, rotation_fail); skill-invocation-logger.test.sh has 2 (jq_fail, rotation_fail); test_incidents.sh has 2 emit_incident fixtures + 1 `_emit_drop_sentinel` standalone test; log-rotation.test.sh asserts new return code; rule-metrics test asserts no `"null"` rule_id + drop counts + archived-sentinel; skill-freshness test asserts drop counts + sentinels excluded from `skills[]`; token-efficiency-report test asserts render-line behavior + archived sentinel.
- [ ] All existing tests still pass (no regression on data-line counting).
- [ ] PR body uses `Closes #3509` (this PR resolves the issue).
- [ ] PR body uses `Ref #3523` (the deferred fs-error monitor follow-up — must NOT auto-close).

### Post-merge (operator)

- [ ] First weekly rule-metrics cron run after merge succeeds (no orphan-gate failure on sentinel input).
- [ ] First compound run after merge with non-trivial diff (LINES ≥ 50) renders successfully — drop count line present iff drops occurred.
- [ ] File a Python `emit_incident` parity tracking issue if any Python-side drop site is identified post-merge (currently `security_reminder_hook.py` doesn't emit `error` and the bash-side filter is monotonic — defer until a Python drop site emerges).

## Test Strategy

Existing convention: `.test.sh` bash test files (per Sharp Edges check — `bats` not installed; do not introduce a new framework). Tests source the target script with overridden repo-root env vars (`INCIDENTS_REPO_ROOT`, `SKILL_LOGGER_REPO_ROOT`, `AGENT_TOKEN_TEE_REPO_ROOT`, `TE_REPORT_REPO_ROOT`).

Hook-side fixture classes (7 total — down from 15+ per review):

| Test file | New cases |
|---|---|
| `agent-token-tee.test.sh` | jq_fail, flock_timeout, rotation_fail (3) |
| `skill-invocation-logger.test.sh` | jq_fail, rotation_fail (2) |
| `tests/hooks/test_incidents.sh` | emit_incident jq_fail, rotation_fail (2) + `_emit_drop_sentinel` standalone (`set -u` clean call, fixed-string format, non-blocking flock fallback) (1) |
| `log-rotation.test.sh` | rotation-fail returns 1 (1) |
| `rule-metrics-aggregate.test.sh` | no `"null"` rule_id; drops_<class>_count correctness; archived sentinel; orphan-gate unchanged (1 fixture, 4 assertions) |
| `skill-freshness-aggregate.test.sh` | drops_<class>_count correctness; sentinels excluded from `skills[]` (1) |
| Token-efficiency report tests | Render line appears when N>0; suppressed when N=0; per-class breakdown shows only non-zero classes; archived sentinel counts (1 fixture, 4 assertions) |

Test fixtures use synthesized data only per AGENTS.md `cq-test-fixtures-synthesized-only`.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| **Out-of-band drop sink** (`.claude/.telemetry-drops.jsonl`) | Decided in brainstorm. Adds new sink + new aggregator surface for marginal gain. |
| **Stderr-only sentinel + harness-side aggregation** | Hook stderr in subagents goes to tmpfs; not reliably surfaced by Claude Code. Lossy. |
| **Schema v2 bump** | Field-additive on v1 keeps old aggregator versions fail-soft. Discriminator is `error` key presence — semantically clear and grep-stable. |
| **Per-class file split** | 3× file count, 3× rotation surface, 3× canonicalization risk. Shared sink is the right granularity. |
| **Sentinel write retries** | Tight retry loops on contended lock create disk-fill / cross-session noise. Single attempt, then drop. |
| **Add `session_id` and `cause_snippet` to schema** | Forensic correlation rides on adjacent data lines (drops cluster temporally). Larger writes are MORE likely to fail under the same contention they're trying to detect. |
| **Add Python `emit_incident` parity in same PR** | Deferred. `security_reminder_hook.py` doesn't currently set `error`; bash-side filter is monotonic. Add when a Python drop site emerges. |
| **Add `flock -w 5` parity to skill-invocation-logger.sh + incidents.sh::emit_incident** | Rejected per DHH plan-review. Those hooks have shipped without timeouts; adding now is gold-plating. Document `flock_timeout` as N/A. |
| **Separate `lib/telemetry-sentinels.sh` helper file** | Rejected per DHH + Simplicity plan-review. One function; folds into existing `lib/incidents.sh`. Drops a file + test file + sourcing-order concern. |
| **Operator runbook (`telemetry-drop-investigation.md`)** | Rejected per DHH + Simplicity plan-review. SRE 101 triage; the schema header's one-line pointer suffices. |
| **Defer entire PR; ship `select(.rule_id != null)` alone first; measure 2 weeks** | Rejected. The `null` rule_id hazard is dormant — only manifests when sentinels exist. Cannot split. Brainstorm rejected "measure first" because the design floor was clear post-#3508. |

## Deferred Items (tracking issues required)

- **#3523** (already filed) — `fs_error` disk-space monitor (out-of-band; cannot be detected in-band).
- **Python `emit_incident` sentinel parity** — file follow-up issue at PR-merge time. Re-evaluation: when `security_reminder_hook.py` adds a flock-protected write or jq-equivalent path that can fail.

## Rollout / Sequencing Notes

Single-PR atomic merge. Phase order is load-bearing for TDD: helper (Phase 1, dormant) → rotation contract change (Phase 2) → hook emission (Phase 3, first sentinels) → aggregator filter (Phase 4, before any sentinel reaches a weekly cron). Pre-merge CI runs all tests; post-merge the next weekly rule-metrics cron is the first integration test in the wild — that's why Acceptance Criteria includes a post-merge cron-success check.
