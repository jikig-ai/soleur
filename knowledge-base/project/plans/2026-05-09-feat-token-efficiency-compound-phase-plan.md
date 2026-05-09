---
feature: feat-token-efficiency-analysis
issue: 3494
companion: 3493
deferred: 3497
brainstorm: knowledge-base/project/brainstorms/2026-05-09-token-efficiency-analysis-brainstorm.md
spec: knowledge-base/project/specs/feat-token-efficiency-analysis/spec.md
branch: feat-token-efficiency-analysis
draft_pr: 3495
date: 2026-05-09
type: feat
classification: workflow-tooling
requires_cpo_signoff: false
---

# Plan: Token-Efficiency Analysis as Compound Phase 1.6 with PostToolUse Hook Tee

## Overview

Add a recurring, advisory token-efficiency measurement step to the `compound` skill (new Phase 1.6, after Phase 1.5 Deviation Analyst, before Constitution Promotion). The phase reads three signals from the just-completed session, identifies top-3 cost line items, proposes mitigations through the existing Accept/Skip/Edit gate, and emits `incidents.sh warn` telemetry under a synthetic `te-*` rule_id namespace when an outlier triggers. A weekly aggregator surfaces longitudinal patterns.

This is the **producer** for the four optimizations cataloged in #3493 (the **consumers**). Without measurement, those optimizations would ship blind.

The PR ships **three foundations-with-contract surfaces atomically**: a PostToolUse hook tee writing subagent token envelopes to `.claude/.session-tokens.jsonl`, an aggregator extension that recognizes `te-*` as a reserved synthetic-prefix namespace (without it the orphan-gate fails the weekly cron on first emit), and the compound Phase 1.6 itself. Per the foundations-PR Sharp Edge, none can ship ahead of the others — the contract (orphan-gate-immune `te-*` events) and its consumer (Phase 1.6 emit) are intertwined.

## Research Insights

### What the brainstorm-time research did NOT establish

The brainstorm CTO assessment (2026-05-09) flagged subagent envelope sizes as "needs new infrastructure" without specifying which hook event surfaces them, what the exact JSON shape is, or how the aggregator handles unknown rule_ids. Those gaps are resolved here.

### Resolved during plan-time research (this PR will not redo)

| Open Question (from spec/brainstorm) | Resolution |
|---|---|
| 1. Which Claude Code lifecycle hook surfaces agent-result blocks? | **PostToolUse on the `Task` tool matcher.** Only `PreToolUse` and `PostToolUse` are wired in this project (`.claude/settings.json`). The exact `tool_input`/`tool_response` shape needs empirical inspection per the precedent in `.claude/hooks/skill-invocation-logger.sh:13-22` ("Empirically verified hook input shape (transcript inspection 2026-05-04)"). The hook implementation phase below includes a transcript-inspection task. |
| 2. Skill-manifest discovery for Phase 1.6 (brainstorm Open Question #2) | **Re-use the existing `.claude/.skill-invocations.jsonl` file** written by `skill-invocation-logger.sh` (PreToolUse on Skill matcher). Filter to current `session_id`. No new manifest infrastructure required. |
| 3. Whether `scripts/rule-metrics-aggregate.sh` accepts `te-*` rule_ids cleanly | **It does NOT.** The aggregator's orphan-gate (`scripts/rule-metrics-aggregate.sh:214-221`) exits 5 when any rule_id in `.rule-incidents.jsonl` is not present in AGENTS.md. Emitting `te-*` events without extending the aggregator's known set would fail the weekly cron on every Phase 1.6 outlier. **This makes the aggregator extension a hard prerequisite — not optional.** |
| 4. Final ratio heuristic for relative-axis outlier emit | Starts at **2k tokens/line**. Tuning after 4–6 weeks of `te-*` data is tracked in #3497 (deferred-tracking issue). |

### Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| TR1 hook tee can write to `.claude/.session-tokens.jsonl` | Confirmed — `.claude/.skill-invocations.jsonl` already follows this pattern (gitignored, flock'd, schema-versioned). | Mirror `skill-invocation-logger.sh` directly (different matcher, different field extraction). |
| FR2 hook intercepts agent-result blocks via "PostToolUse or equivalent" | Only PostToolUse and PreToolUse are wired in this project; SubagentStop is not used by any existing hook. | Use PostToolUse on `Task` matcher. Document the empirical input shape per existing precedent. |
| TR2 `te-*` rule_id namespace must not collide with real AGENTS.md ids | Confirmed via `scripts/lib/rule-metrics-constants.sh` and `cq-rule-ids-are-immutable` — section prefixes are `hr|wg|cq|rf|pdr|cm`. `te-` cannot collide. | Add `RULE_ID_SYNTHETIC_PREFIXES=("te-")` to constants file. Aggregator's orphan-filter excludes synthetic-prefix matches. |
| TR3 aggregator integration "may need a partition" | Aggregator's existing `counts` map already tracks per-id stats for arbitrary rule_ids — synthetic ids will appear in `counts` but be filtered out of `enriched` (which joins with AGENTS.md). The orphan-gate is the only blocker. | Patch the orphan-detection jq to allow synthetic prefixes; optionally surface a `synthetic_metrics.token_efficiency` summary subsection (deferred — first land the orphan-gate fix). |
| Spec: "Phase 1.6 token budget ≤1.5k tokens added per fire" | Inline rubric ≤30 lines × ~45 chars/line = ~1350 chars ≈ 340 tokens. Bash + awk computation adds maybe 100 lines of skill body ≈ 4500 chars ≈ 1100 tokens. Generated output cap ≤600 tokens. **Total ≈ 2k tokens** worst case if rubric is fat. | Tighten the rubric to ≤25 lines and the computation block to ≤80 lines so total stays ≤1.5k. Verify post-edit with `wc -c` snapshot before/after. |

## Implementation Phases

### Phase 1 — PostToolUse hook tee for `Task` tool

**Files to create:**

1. `.claude/hooks/agent-token-tee.sh` — modeled after `skill-invocation-logger.sh:1-72`. Differences:
   - Matcher: `Task` (vs `Skill`)
   - Extracted fields: `tool_name`, `tool_response.content` or `tool_response.usage` (whichever carries the `total_tokens` line — see Step 1.1 below)
   - Output file: `.claude/.session-tokens.jsonl`
   - Kill-switch env var: `SOLEUR_DISABLE_AGENT_TOKEN_TEE=1`
   - JSONL line shape:
     ```json
     {"schema":1,"ts":"<ISO>","session_id":"<id>","subagent_type":"<type>","total_tokens":<int>,"tool_uses":<int>,"duration_ms":<int>,"hook_event":"PostToolUse"}
     ```

2. `.claude/hooks/agent-token-tee.test.sh` — modeled after `skill-invocation-logger.test.sh`. Test cases:
   - Valid Task result → JSONL line written with all fields populated
   - Result missing `total_tokens` → graceful skip, no line written, exit 0
   - Malformed JSON input → exit 0, no crash
   - Concurrent writes (two parallel `agent-token-tee.sh < fixture` invocations) → both lines present, no truncation
   - Kill-switch env var set → no-op exit 0

**Step 1.1 — Empirical hook-input-shape verification (BEFORE writing the hook).** Per `skill-invocation-logger.sh:13-22`, the precedent for new hooks is "transcript inspection". Steps:

1. Cross-reference Claude Code's bundled hook documentation (`claude --help` / docs site) for the documented `tool_response` shape on `Task` invocations. Capture any documented fields.
2. Set up a logging-only stub PostToolUse hook on `Task` matcher that writes raw stdin to `/tmp/task-hook-stdin.json`.
3. Capture **two** invocations in a scratch session:
   - **Flat case**: a Task whose body does not spawn nested Tasks.
   - **Nested case**: a Task whose body spawns a child Task (e.g., one of the review skills).
   Confirm both produce the same `tool_response` shape, OR document any difference. If shape differs, the hook MUST handle both branches.
4. Enumerate every JSONL field the hook will write (`total_tokens`, `tool_uses`, `duration_ms`, `subagent_type`) and verify each is present + extractable in BOTH captured cases. If `tool_uses` or `duration_ms` are absent, use defensive `// 0` jq fallback rather than failing the hook.
5. Document the verified shape AND any cross-case differences in the hook header comment with date stamp.

If `total_tokens` is in `tool_response.content` (text), regex-extract via `grep -oE 'total_tokens": *[0-9]+'`; if it's structured (e.g., `tool_response.usage.total_tokens`), use `jq -r`.

**Step 1.2 — Wire matcher in `.claude/settings.json`.** Add a new entry under `"PostToolUse"`:

```json
{
  "matcher": "Task",
  "hooks": [
    { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/agent-token-tee.sh" }
  ]
}
```

**Step 1.3 — Add gitignore entries.** Append to `.gitignore`:

```
.claude/.session-tokens.jsonl
.claude/.session-tokens-*.jsonl.gz
```

(Mirrors the existing `.skill-invocations.jsonl` and `.rule-incidents.jsonl` patterns.)

### Phase 2 — Aggregator synthetic-prefix extension (one-line jq change)

**File to edit:** `scripts/rule-metrics-aggregate.sh` — modify the orphan-detection jq filter (around line 180-185). The current logic:

```jq
($enriched | map(.id)) as $known_ids
| ($counts | keys | map(select(. as $id | ($known_ids | index($id)) | not))) as $orphan_ids
```

Hardcode the `te-` synthetic-prefix exclusion in the jq pipeline:

```jq
($enriched | map(.id)) as $known_ids
| ($counts | keys
    | map(select(. as $id
        | ($known_ids | index($id)) | not))
    | map(select(startswith("te-") | not))) as $orphan_ids
```

Synthetic-prefix events still appear in the `counts` map (so per-id stats are preserved); they're filtered out of `orphan_rule_ids` so the weekly cron's `exit 5` orphan-gate is not tripped.

**Why hardcoded vs. constants array:** Per plan-review, a `RULE_ID_SYNTHETIC_PREFIXES=("te-")` bash array for one prefix is YAGNI scaffolding. When a second synthetic prefix actually exists, the refactor is ~5 lines. Keep the commitment, defer the abstraction.

Add an inline comment in the aggregator next to the new line: `# 'te-' prefix reserved for token-efficiency telemetry (issue #3494). Section prefixes for AGENTS.md rules are hr|wg|cq|rf|pdr|cm; te- cannot collide.`

**Step 2.1 — Test the orphan-gate fix.** Add to `scripts/rule-metrics-aggregate.test.sh`:

- Fixture jsonl containing `{"rule_id":"te-subagent-overshoot","event_type":"warn",...}` → aggregator does NOT include this in `summary.orphan_rule_ids`, exit 0.
- Fixture jsonl containing both `te-subagent-overshoot` AND a fabricated `xx-typo` → only `xx-typo` appears in orphan list, exit 5.
- Fixture jsonl with all `te-*` events → orphan list empty, exit 0.

**Step 2.2 — Deferred: `synthetic_metrics` summary subsection.** Out of scope for this PR. File a follow-up issue at the end of Phase 5 IF the per-prefix counts would benefit from a structured summary (likely yes once 4–6 weeks of data accumulate). Initial behavior: synthetic events appear in `counts` but produce no extra summary block — operators read them by querying the raw `.rule-incidents.jsonl`.

**Step 2.3 — Pin `incidents.sh` API.** Phase 1.6's emit calls use `emit_incident <rule_id> <event_type> <prefix> [command_snippet]`. This signature is documented at `.claude/hooks/lib/incidents.sh:48-65`. The `event_type` "warn" is one of `{deny, bypass, applied, warn}` per the API; aggregator counting semantics (line 110-122) include `warn_count`, so emitted events flow through the existing pipeline.

### Phase 3 — Compound Phase 1.6 (external script + thin SKILL.md insertion)

**Decision:** Per plan-review consensus, the bash + jq computation lives in a standalone script. The compound `SKILL.md` Phase 1.6 section is a thin invocation (~3 lines) plus the operator-facing rubric (≤25 lines) plus the Sharp Edge. This drops the per-fire token cost loaded into main context dramatically — only the SKILL.md text is in main context; the script is bash-executed, never tokenized.

**Files:**
- **Create:** `plugins/soleur/skills/compound/scripts/token-efficiency-report.sh` (all bash + jq computation, all three trigger code paths, ratio-emit gated off via flag).
- **Edit:** `plugins/soleur/skills/compound/SKILL.md` — insert Phase 1.6 section between Phase 1.5 empty-case and Knowledge Base Integration (after line ~236).

#### Step 3.1 — Create `plugins/soleur/skills/compound/scripts/token-efficiency-report.sh`

The script implements all three trigger code paths but ships with the **ratio-emit gated off** until #3497 lands a tuned threshold. This preserves the dual-axis trigger architecture from the brainstorm/spec while addressing the reviewers' tuning-blind concern.

Structure:

```bash
#!/usr/bin/env bash
# Token-efficiency report — invoked from compound Phase 1.6.
#
# Reads three signals from the just-completed session, prints a top-3 cost
# table, and emits incidents.sh `warn` telemetry under the `te-*` synthetic
# rule_id namespace when an outlier triggers.
#
# Outputs: a Markdown block to stdout (≤600 tokens of generated text).
# Side effects: appends to .claude/.rule-incidents.jsonl on outlier detection.
#
# Issue: #3494. Companion catalog: #3493. Tuning follow-up: #3497.
set -euo pipefail

# Feature flags (flip when tuning lands).
: "${RATIO_EMIT_ENABLED:=0}"   # gated off until #3497 produces a tuned threshold

# Thresholds.
SUBAGENT_OVERSHOOT_TOKENS=100000
SKILL_PAYLOAD_FLOOR_BYTES=200000
RATIO_THRESHOLD_X1000=2000     # 2k tokens/line × 1000 scaling for integer math
SKIP_LINES_THRESHOLD=50
TURN_COUNT_PROXY=25            # fixed approximation; refined via #3497

REPO_ROOT="$(git rev-parse --show-toplevel)"
SESSION_ID="${CLAUDE_SESSION_ID:-}"

# 1) Skip rule (Kieran-corrected: merge-base fallback for first-commit-on-branch).
if git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
  DIFF_BASE="HEAD~1"
else
  DIFF_BASE="$(git merge-base HEAD main 2>/dev/null || git rev-parse HEAD)"
fi
LINES=$(git diff --shortstat "$DIFF_BASE" 2>/dev/null \
  | grep -oE '[0-9]+ (insertion|deletion)' \
  | grep -oE '[0-9]+' \
  | awk '{s+=$1} END {print s+0}')

if (( LINES < SKIP_LINES_THRESHOLD )); then
  echo "### Phase 1.6: skipped (small diff: $LINES lines changed)"
  exit 0
fi

# 2) Read three signals.
AGENTS_BYTES=$(wc -c < "$REPO_ROOT/AGENTS.md")
AGENTS_FLOOR=$((AGENTS_BYTES * TURN_COUNT_PROXY))

# 2a) Resolve compound's own entry timestamp for recursive self-exclusion (R6).
SKILL_INVOCATIONS="$REPO_ROOT/.claude/.skill-invocations.jsonl"
COMPOUND_ENTRY_TS=""
if [[ -f "$SKILL_INVOCATIONS" && -n "$SESSION_ID" ]]; then
  COMPOUND_ENTRY_TS=$(jq -r --arg s "$SESSION_ID" \
    'select(.session_id == $s and .skill == "soleur:compound") | .ts' \
    "$SKILL_INVOCATIONS" 2>/dev/null | sort | tail -1)
fi

# 2b) Skill-payload sum, with namespace-aware path resolution.
PAYLOAD_TOTAL=0
LARGEST_SKILL=""
LARGEST_SKILL_BYTES=0
if [[ -f "$SKILL_INVOCATIONS" && -n "$SESSION_ID" ]]; then
  while IFS= read -r skill; do
    [[ -z "$skill" ]] && continue
    case "$skill" in
      soleur:*) skill_md="$REPO_ROOT/plugins/soleur/skills/${skill#soleur:}/SKILL.md" ;;
      *:*) plugin="${skill%%:*}"; sub="${skill#*:}"
           skill_md="$REPO_ROOT/plugins/${plugin}/skills/${sub}/SKILL.md" ;;
      *)  skill_md=$(find "$REPO_ROOT/plugins" -maxdepth 4 \
            -path "*/skills/${skill}/SKILL.md" -type f 2>/dev/null | head -1) ;;
    esac
    if [[ -f "$skill_md" ]]; then
      bytes=$(wc -c < "$skill_md")
      PAYLOAD_TOTAL=$((PAYLOAD_TOTAL + bytes))
      if (( bytes > LARGEST_SKILL_BYTES )); then
        LARGEST_SKILL="$skill"
        LARGEST_SKILL_BYTES=$bytes
      fi
    fi
  done < <(jq -r --arg s "$SESSION_ID" \
    'select(.session_id == $s) | .skill' "$SKILL_INVOCATIONS" 2>/dev/null \
    | sort -u)
fi

# 2c) Subagent envelopes, with R6 self-exclusion.
SESSION_TOKENS="$REPO_ROOT/.claude/.session-tokens.jsonl"
MAX_ENVELOPE=0
SUM_ENVELOPES=0
TOP_OFFENDER=""
if [[ -f "$SESSION_TOKENS" && -n "$SESSION_ID" ]]; then
  cts="${COMPOUND_ENTRY_TS:-9999-12-31T23:59:59Z}"
  read MAX_ENVELOPE TOP_OFFENDER <<<"$(jq -r --arg s "$SESSION_ID" --arg cts "$cts" \
    'select(.session_id == $s and .ts < $cts) | "\(.total_tokens) \(.subagent_type)"' \
    "$SESSION_TOKENS" 2>/dev/null | sort -nr | head -1)"
  MAX_ENVELOPE="${MAX_ENVELOPE:-0}"
  SUM_ENVELOPES=$(jq -r --arg s "$SESSION_ID" --arg cts "$cts" \
    'select(.session_id == $s and .ts < $cts) | .total_tokens' \
    "$SESSION_TOKENS" 2>/dev/null | awk '{s+=$1} END {print s+0}')
fi

# 3) Compute ratio (always; emit gated by flag).
RATIO_X1000=0
if (( SUM_ENVELOPES > 0 && LINES > 0 )); then
  RATIO_X1000=$((SUM_ENVELOPES * 1000 / LINES))
fi

# 4) Render top-3 cost table (sort by raw byte/token magnitude).
# … (use awk to sort {AGENTS_FLOOR, PAYLOAD_TOTAL, SUM_ENVELOPES} descending) …

# 5) Outlier detection — emit incidents.sh warn (ratio gated by RATIO_EMIT_ENABLED).
source "$REPO_ROOT/.claude/hooks/lib/incidents.sh"

if (( MAX_ENVELOPE > SUBAGENT_OVERSHOOT_TOKENS )); then
  emit_incident te-subagent-overshoot warn \
    "subagent envelope > 100k tokens" \
    "subagent_type=$TOP_OFFENDER total_tokens=$MAX_ENVELOPE"
fi

if (( PAYLOAD_TOTAL > SKILL_PAYLOAD_FLOOR_BYTES )); then
  emit_incident te-skill-payload-floor warn \
    "skill payload sum > 200k chars" \
    "largest_skill=$LARGEST_SKILL largest_bytes=$LARGEST_SKILL_BYTES total=$PAYLOAD_TOTAL"
fi

# Ratio emit is GATED — present in code path for testability, off until #3497.
if (( RATIO_EMIT_ENABLED == 1 )) && (( RATIO_X1000 > RATIO_THRESHOLD_X1000 )); then
  emit_incident te-agents-md-turn-cost warn \
    "session ratio > 2k tokens/line" \
    "ratio_x1000=$RATIO_X1000 sum_envelopes=$SUM_ENVELOPES lines=$LINES"
fi

# 6) Render Markdown output (top-3 table + 1–3 mitigation suggestions matched to triggered outliers).
# … (template substitution; total generated text capped at ~600 tokens) …
```

**Test entry point:** the script accepts an optional `--fixture-mode` flag for unit tests, allowing tests to inject fixture paths via environment variables (`SESSION_TOKENS_PATH`, `SKILL_INVOCATIONS_PATH`, `INCIDENTS_REPO_ROOT`) instead of resolving from `git rev-parse`.

#### Step 3.2 — Edit `plugins/soleur/skills/compound/SKILL.md` (thin invocation)

Insert this section between Phase 1.5 empty-case and Knowledge Base Integration:

```markdown
<!-- phase-1.6-start -->
## Phase 1.6: Token-Efficiency Analysis (sequential, advisory)

After Phase 1.5 Deviation Analyst, run the cost-efficiency report:

```bash
bash "$(git rev-parse --show-toplevel)/plugins/soleur/skills/compound/scripts/token-efficiency-report.sh"
```

The script prints a top-3 cost table and emits `te-*` `warn` telemetry to `.claude/.rule-incidents.jsonl` when an outlier triggers. Outlier proposals route through the same Accept/Skip/Edit gate as the Deviation Analyst (Phase 1.5 step 7).

### Cost-breakdown rubric (operator reference)

- **AGENTS.md floor**: `wc -c AGENTS.md` × ~25 turns/session ≈ session-floor cost.
- **Skill payload floor**: sum of `wc -c` for each SKILL.md invoked this session (read from `.claude/.skill-invocations.jsonl` filtered by session_id).
- **Subagent envelopes**: sum of `total_tokens` per Task invocation (read from `.claude/.session-tokens.jsonl` filtered by session_id and `ts < compound_entry_ts` for self-exclusion).
- **Lines changed**: insertion+deletion count from `git diff --shortstat`. Skip Phase 1.6 entirely when <50.
- **Outlier triggers**: subagent envelope >100k → `te-subagent-overshoot`; skill payload sum >200k chars → `te-skill-payload-floor`; ratio >2k tokens/line → `te-agents-md-turn-cost` (emit gated off until #3497).
- **Budget for the phase itself**: ≤1.5k tokens loaded per fire (script bytes don't count — bash-executed, not in main context).

### Sharp Edge

> Token-efficiency reports are advisory. Only large outliers (subagent envelope >100k OR skill payload >200k) warrant a follow-up issue. Smaller drifts compound through the weekly aggregator's longitudinal trend; a single noisy session shouldn't prompt a learning file.
<!-- phase-1.6-end -->
```

The `<!-- phase-1.6-{start,end} -->` sentinels are the anchors for the budget assertion in Phase 5 step 6 (`wc -c` between the markers ≤ 1200 chars).

#### Step 3.3 — Ratio-emit deferral (in-script flag)

The script ships with `RATIO_EMIT_ENABLED=0`. The code path is exercised by tests but produces no telemetry until #3497 lands a tuned threshold. When tuning is ready, flip the default to `1` in a follow-up PR (or invert: drop the flag and use the new threshold value directly).

This preserves the dual-axis trigger architecture from the brainstorm/spec without shipping a tuning-blind ratio emit that would generate false positives for 4–6 weeks.

### Phase 4 — Tests

Each test file follows the pattern of its sibling (`skill-invocation-logger.test.sh`, `rule-metrics-aggregate.test.sh`).

**Test scenarios (mapped to spec TR5):**

1. **Hook smoke test**: PostToolUse on Task with valid fixture → JSONL line appended with all required fields.
2. **Hook missing-field graceful skip**: `tool_response` missing `total_tokens` → no line written, exit 0.
3. **Hook concurrent writes**: 4 parallel invocations with distinct session_ids → 4 lines, no truncation, no interleaving. Verify `flock -w 5` timeout fallback exits 0 silently when contention exceeds budget.
4. **Aggregator synthetic-prefix passes**: jsonl with only `te-*` events → exit 0, no orphan failure.
5. **Aggregator mixed orphan handling**: jsonl with `te-foo` + `xx-typo` → only `xx-typo` flagged, exit 5.
6. **token-efficiency-report.sh skip on small diff**: planted git fixture with 3-line diff → `### Phase 1.6: skipped` output, no telemetry emit.
7. **token-efficiency-report.sh subagent overshoot**: planted `.claude/.session-tokens.jsonl` with `total_tokens: 120000` → `te-subagent-overshoot` warn line in `.rule-incidents.jsonl`.
8. **token-efficiency-report.sh skill-payload-floor**: planted skill-invocations + skill SKILL.md fixtures summing >200k chars → `te-skill-payload-floor` warn.
9. **token-efficiency-report.sh ratio code path (gated off)**: planted 30-line diff + 80k subagent envelope (ratio 2666/1000 > 2000/1000 threshold) with `RATIO_EMIT_ENABLED=0` → ratio computed but **NO** `te-agents-md-turn-cost` warn. Same fixture with `RATIO_EMIT_ENABLED=1` → warn fires. Confirms the code path works AND the gate works.
10. **token-efficiency-report.sh missing session-tokens file**: file absent → graceful "subagent envelopes: not captured this session" output, no crash, no spurious emit.
11. **token-efficiency-report.sh first-commit-on-branch fallback (R7 regression)**: planted git fixture where `HEAD~1` does not exist; merge-base fallback resolves and counts the commit's lines correctly (does NOT skip when the commit is >50 lines).
12. **token-efficiency-report.sh recursive self-exclusion (R6 regression)**: planted session-tokens with TWO envelopes — one with `ts < compound_entry_ts` (counted), one with `ts > compound_entry_ts` (excluded). Assert only the pre-entry envelope contributes to `MAX_ENVELOPE` and `SUM_ENVELOPES`.
13. **token-efficiency-report.sh non-namespaced skill path resolution**: planted skill-invocations with `find-skills` (unscoped name) → script resolves the SKILL.md via `find` fallback and counts its bytes.
14. **Phase 1.6 SKILL.md budget assertion**: `wc -c` between `<!-- phase-1.6-start -->` and `<!-- phase-1.6-end -->` markers ≤ **1200** chars (conservative byte cap; markdown with code fences tokenizes worse than prose).

### Phase 5 — Verification (pre-merge)

1. Run `bash scripts/rule-metrics-aggregate.test.sh` — all existing + new synthetic-prefix tests pass.
2. Run `bash .claude/hooks/agent-token-tee.test.sh` — all hook tests pass.
3. Run `bash plugins/soleur/skills/compound/test/phase-16.test.sh` (new test file) — all scenarios from Phase 4 pass.
4. Run `bash scripts/rule-metrics-aggregate.sh --dry-run` against a fixture session → no orphan failure with planted `te-*` events.
5. **Live integration:** run `skill: soleur:compound` against a real >50-line-diff branch with the hook tee active. Observe Phase 1.6 output block appears. Plant an artificial 120k subagent envelope and re-run; verify `te-subagent-overshoot` line appears in `.claude/.rule-incidents.jsonl`. Exact plant command:

   ```bash
   # CLAUDE_SESSION_ID is captured in Phase 1 Step 1.1 (empirical verification
   # confirms its env var name; if Claude Code exposes it differently, replace
   # with the verified name). Use a recent ISO-8601 timestamp.
   printf '{"schema":1,"ts":"%s","session_id":"%s","subagent_type":"test-overshoot","total_tokens":120000,"tool_uses":1,"duration_ms":1000,"hook_event":"PostToolUse"}\n' \
     "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     "${CLAUDE_SESSION_ID:?CLAUDE_SESSION_ID env var must be set}" \
     >> .claude/.session-tokens.jsonl
   ```

6. **Phase 1.6 token budget check:** `wc -c` the new compound SKILL.md section (sentinel-delimited via `<!-- phase-1.6-start -->` and `<!-- phase-1.6-end -->` markers in the source) before commit. Must be ≤ **1200** chars. If over, trim the rubric or the bash block. Char count is a conservative proxy for tokens — markdown with code fences and jq pipes tokenizes worse than prose, so the 1200-byte cap leaves headroom under the brainstorm's 1.5k-token Phase 1.6 budget.
7. **AGENTS.md not modified.** Confirm via `git diff main...HEAD -- AGENTS.md` returns empty. This work is `[skill-enforced: compound Phase 1.6]`; no AGENTS.md rule warranted (per `cq-agents-md-tier-gate`: domain-scoped → owning skill, not AGENTS.md).

## Files to Create

- `.claude/hooks/agent-token-tee.sh` — PostToolUse hook on Task matcher (modeled after `skill-invocation-logger.sh`).
- `.claude/hooks/agent-token-tee.test.sh` — hook unit tests.
- `plugins/soleur/skills/compound/scripts/token-efficiency-report.sh` — externalized Phase 1.6 bash + jq computation (per plan-review consensus to drop inline-bash from SKILL.md).
- `plugins/soleur/skills/compound/test/phase-16.test.sh` — new directory + test file for Phase 1.6 scenarios. Verify via `ls plugins/soleur/skills/compound/` first to confirm the `test/` subdirectory needs creation. **Why this path**: sibling skills like `git-worktree` and `archive-kb` follow the `<skill>/scripts/` and `<skill>/test/` convention.

## Files to Edit

- `.claude/settings.json` — add PostToolUse Task matcher entry pointing to `agent-token-tee.sh`.
- `.gitignore` — add `.claude/.session-tokens.jsonl` and `.claude/.session-tokens-*.jsonl.gz`.
- `scripts/rule-metrics-aggregate.sh` — extend orphan-detection jq filter to exclude `te-*` (one-line `startswith` change at lines ~180-185).
- `scripts/rule-metrics-aggregate.test.sh` — add three synthetic-prefix test cases (Phase 4 scenarios 4-5).
- `plugins/soleur/skills/compound/SKILL.md` — insert Phase 1.6 section between Phase 1.5 empty-case and Knowledge Base Integration (after line ~236).

(Note: `scripts/lib/rule-metrics-constants.sh` is NOT edited — the synthetic-prefix is hardcoded in the aggregator's jq filter per the YAGNI consensus from plan-review.)

## Open Code-Review Overlap

1 open code-review issue touches a planned-edit file path:

- **#2348 (vitest mock-factory export drift)** — incidental keyword match on `.claude/hooks/`; the issue body discusses vitest mock-factories for React component mocks (`@/components/kb/kb-breadcrumb`), an entirely different surface. **Disposition: acknowledge.** This plan's hook code does not interact with vitest, mock factories, or the kb-breadcrumb component. The issue remains open and will be addressed in its own cycle.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] All files in `## Files to Create` and `## Files to Edit` lists land per spec.
- [ ] All hook unit tests + aggregator orphan-gate tests + Phase 1.6 unit tests pass (Phase 4 scenarios 1–10).
- [ ] Aggregator: `te-*` events do NOT trigger orphan-gate (`exit 5`); only real fabricated/typo rule_ids do.
- [ ] Phase 1.6 SKILL.md addition (sentinel-delimited) ≤ **1200** chars; inline rubric ≤25 lines.
- [ ] **No `references/token-efficiency-rubric.md` file created** (explicitly rejected per brainstorm).
- [ ] **No per-session learning files written under `knowledge-base/project/learnings/efficiency/`** (explicitly rejected — telemetry-only capture).
- [ ] No AGENTS.md rule added; work is `[skill-enforced: compound Phase 1.6]`.
- [ ] **Recursive-bias self-exclusion:** Phase 1.6 only counts subagent envelopes with `ts < compound_entry_ts` (verified by test scenario 7+8 + dedicated R6 regression test).
- [ ] Live integration test passes: real >50-line-diff branch + planted 120k envelope → `te-subagent-overshoot` written to `.rule-incidents.jsonl`.
- [ ] PR body includes a `## Changelog` section per plugin AGENTS.md.
- [ ] PR body uses `Closes #3494` on its own line; `Ref #3493` and `Ref #3497` for the catalog and tuning issues.

### Post-merge (operator)

- [ ] Trigger one manual run of the weekly `rule-metrics-aggregate` workflow via `gh workflow run rule-metrics-aggregate.yml`. Poll until complete; verify exit 0 and that the synthetic-prefix logic landed on main per `wg-after-merging-a-pr-that-adds-or-modifies` (workflow-modification verification).
- [ ] After 7 days of normal operator activity, inspect `.claude/.rule-incidents.jsonl` for any `te-*` events. If any fired, confirm the per-event count appears in `knowledge-base/project/rule-metrics.json`'s `counts` map without orphan-gate failure.

## Test Scenarios

Mapped to Phase 4 — see that section for the full list. Five categories:

1. Hook unit tests (4 scenarios) — `agent-token-tee.test.sh`.
2. Aggregator orphan-gate tests (3 scenarios) — `rule-metrics-aggregate.test.sh`.
3. Compound Phase 1.6 unit tests (4 scenarios) — `plugins/soleur/skills/compound/test/phase-16.test.sh`.
4. Phase 1.6 budget assertion — `wc -c < <patched-section>` ≤ 1500.
5. Live integration — manual operator action with planted envelope (Phase 5 step 5).

## Risks and Mitigations

### R1 — Hook input shape drift between Claude Code releases (high impact, low likelihood)

The empirical hook-input shape inspection (Phase 1 Step 1.1) captures the shape AT IMPLEMENTATION TIME. If a future Claude Code version changes the field name (`tool_response.content` → `tool_response.body`), the hook silently writes empty `total_tokens` lines. Mitigation: defensive jq with `// empty` fallback per `2026-03-18-stop-hook-jq-invalid-json-guard.md`; aggregator-level test asserts that lines with `total_tokens: 0` are not counted as zero-cost subagents (treat 0 as unknown/missing). Document the verified shape in the hook header comment with a date stamp so a future drift can be triaged quickly.

### R2 — Concurrent-writes race with skill-invocation-logger (low impact, low likelihood)

Both hooks may fire concurrently when a parent invocation chains a Skill into a Task. Each writes to a different JSONL file, so there's no inter-hook race; intra-file race is handled by `flock -x` on each.

### R3 — Aggregator orphan-gate regression (high impact, hard to detect)

If a future edit to `scripts/rule-metrics-aggregate.sh` reverts the synthetic-prefix exclusion, the weekly cron would silently start failing on every Phase 1.6 outlier. Mitigation: the synthetic-prefix test cases (Phase 4 scenarios 4-5) catch this at PR time. Long-term: the constant in `rule-metrics-constants.sh` is the contract anchor; both consumers (aggregator + any future synthetic-prefix emitter) must reference it. Per `cq-pg-security-definer-search-path-pin-pg-temp`-style sharp-edge, treat the constant as the canonical source.

### R5 — Phase 1.6 budget creep (medium impact, medium likelihood)

The Phase 1.6 SKILL.md addition may grow over time as new outlier triggers are added (per #3493 follow-ups). Mitigation: AC line `≤1200 chars` enforced in Phase 5 verification (down from 1500 — Kieran flagged that markdown with code fences and jq pipes tokenizes worse than prose; the conservative ceiling builds tokenization-uncertainty headroom). Budget headroom check (1200 − current bytes) documented in PR. If a future PR pushes the section over budget, it must trim before merge OR justify with a learning file documenting the necessity (per `cq-agents-md-why-single-line` precedent for size discipline).

### R6 — Recursive measurement bias (HIGH likelihood — Kieran caught the original framing was wrong)

**The original "no bias to correct" claim was incorrect.** When `/review` (or any compound-spawning pipeline) fans out reviewer agents and then `compound` runs Phase 1.6 at the end, the reviewer envelopes are summed into the same session that Phase 1.6 is now measuring — Phase 1.6 would emit `te-subagent-overshoot` warning about its own grandparent's review fan-out, which is real signal but mis-attributed.

**Mitigation:** Phase 1.6 computes which subagent envelopes to count by filtering `.claude/.session-tokens.jsonl` to entries written BEFORE the compound skill itself was invoked. Use `.claude/.skill-invocations.jsonl` to find the timestamp of `soleur:compound`'s entry; only count subagent envelopes with `ts < compound_entry_ts`. Compound's own children (Deviation Analyst's parallel subagents, route-to-definition agents) are excluded from the measurement.

**Test:** scenario added to Phase 4 — plant a session with two envelopes, one before and one after the synthetic compound-entry timestamp; assert only the pre-entry envelope is counted.

**Sharp Edge documented in Step 3.5 below.**

### R7 — First-commit-on-branch falls through correctly (Kieran caught: original was wrong)

The original plan claimed `LINES=0` skip was "correct" on first-commit-on-branch. **It is NOT correct** — first commits are often the largest. The skip-rule now uses `git merge-base HEAD main` as a fallback (see Step 3.1.1). The remaining edge case is true zero-diff (no commits between HEAD and merge-base): Phase 1.6 still skips, which is correct (genuinely no work delivered).

## User-Brand Impact

**If this lands broken, the user experiences:** a non-blocking advisory output block in compound that is missing, malformed, or noisy. The compound phase's existing functionality (Deviation Analyst, Constitution Promotion, learning-write) is unaffected — Phase 1.6 is sequential after the existing phases and contains no shared mutation surface.

**If this leaks, the user's data is exposed via:** the only data flowing through this feature is operator-local session metadata (subagent total_tokens, AGENTS.md byte size, lines changed) written to gitignored `.claude/.session-tokens.jsonl`. No user PII, no credentials, no payment data, no cross-tenant surface. The JSONL never leaves the operator's machine unless they manually commit it (which `.gitignore` prevents).

**Brand-survival threshold:** none

The diff touches: `.claude/hooks/`, `.claude/settings.json`, `.gitignore`, `scripts/rule-metrics-aggregate.sh`, `scripts/lib/rule-metrics-constants.sh`, `plugins/soleur/skills/compound/SKILL.md`. None match `SENSITIVE_PATH_RE` (verified — the regex covers `apps/web-platform/server`, `apps/web-platform/lib/(stripe|auth|byok|...)`, `apps/*/infra/`, `*/doppler*.{yml,yaml,sh}`, and credential-handling workflow files). No scope-out bullet required.

## Domain Review

**Domains relevant:** Engineering (carry-forward from brainstorm); none added at plan time.

### Engineering (CTO — carry-forward)

**Status:** reviewed (carry-forward from `knowledge-base/project/brainstorms/2026-05-09-token-efficiency-analysis-brainstorm.md` Domain Assessments section)

**Assessment:** Compound Phase 1.6 over ship Phase 5.6 — per-commit frequency aligns with token cost as a flow signal. Inline rubric mandatory (5k-char reference file would defeat the measurement). Realistic in-process signals: AGENTS.md size + declared skill payload + `.rule-incidents.jsonl` are grabbable; subagent envelope sizes need a hook tee (now resolved as PostToolUse on Task). Capture via existing `incidents.sh emit_incident` with synthetic `te-*` rule_id namespace. Token budget ≤1.5k per fire, no subagent spawn. Skip on small diffs. **Plan-time addition:** the orphan-gate dependency (atomic delivery requirement) was not surfaced in the brainstorm CTO assessment — surfaced and resolved during plan-time research.

No Product domain (internal workflow tooling, no user-facing UI, no flows). No Marketing/Legal/Sales/Finance/Support/Operations relevance.

### Product/UX Gate

**Tier:** none — internal workflow tooling.

## Sharp Edges

Carry forward from brainstorm + plan-time additions + Kieran/code-simplicity review:

1. **Atomic delivery (foundations-with-contract).** Hook + aggregator extension (1-line jq change) + Phase 1.6 ship in one PR. The `te-*` contract (orphan-gate-immune events) and its consumer (Phase 1.6 emit) are intertwined; partial delivery would either silently drop events or fail the weekly cron. Reviewer note: the aggregator change is now small enough (one jq line) that the bundling complexity is minimal.
2. **Token-efficiency reports are advisory** — see Step 3.3.
3. **Turn-count proxy is a fixed approximation** (25 turns/session). When data permits, refine via #3497.
4. **The hook input shape inspection MUST happen before writing the hook** — empirical verification per `skill-invocation-logger.sh` precedent. Capture BOTH flat and nested Task cases. Cross-reference Claude Code's bundled hook documentation. Don't trust documented field names without inspection.
5. **AGENTS.md is not edited.** This work is `[skill-enforced: compound Phase 1.6]`; no AGENTS.md rule is added (per `cq-agents-md-tier-gate`: domain-scoped → owning skill).
6. **Section prefix `te-`** is reserved permanently for token-efficiency telemetry. No future AGENTS.md rule may use it (the section-prefix vocabulary is `hr|wg|cq|rf|pdr|cm`).
7. **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's threshold is `none` with explicit sensitive-path verification — should pass.
8. **Phase 1.6 must self-exclude.** Compound's own subagent envelopes (Deviation Analyst's parallel agents, route-to-definition agents, AND any reviewer-fan-out from a parent `/review` skill) are filtered out via the `compound_entry_ts` clause in Step 3.5. Without this filter, Phase 1.6 emits `te-subagent-overshoot` warning about itself when a parent pipeline ran review.
9. **`flock -x` contention with rapid Task fan-out.** The hook-tee writes under `flock -x`. Eight parallel review subagents finishing within milliseconds will queue. Add `flock -w 5` (5-second timeout); on timeout, log to stderr (`>&2`) and exit 0 — never block tool dispatch. Hook contract is fire-and-forget per `incidents.sh:14`.
10. **`.claude/.session-tokens.jsonl` unbounded growth.** No rotation in this PR. The aggregator's existing rotation pattern for `.rule-incidents.jsonl` (`.rule-incidents-YYYY-MM-DD.jsonl.gz`, mirrored in `.gitignore` for both files in this PR) is the model. Rotation policy is parallel to skill-invocations.jsonl which has the same gap; folding both rotations into one workflow is a follow-up. File a tracking issue at end of Phase 5 if growth is observed.
11. **Path resolution for non-namespaced skills** (Step 3.6). The naive `${skill#soleur:}` substitution silently undercounts payload sums when skills like `find-skills` or `frontend-design` are loaded. Use the case-statement pattern in Step 3.6.
12. **`emit_incident` API signature pinned** at `.claude/hooks/lib/incidents.sh:48-65`. Phase 1.6 uses `emit_incident <rule_id> warn <prefix> <kv>` — `warn` is one of the recognized event_types in `{deny, bypass, applied, warn}`; `warn_count` flows through the existing aggregator pipeline.

## Plan Carry-Forward

### Resolved during plan-time research

- **Q1 — hook event:** PostToolUse on Task matcher (mirrors skill-invocation-logger pattern).
- **Q2 — skill-manifest discovery:** `.claude/.skill-invocations.jsonl` already exists; filter by session_id.
- **Q3 — aggregator handling:** Orphan-gate fails on unknown rule_ids; synthetic-prefix extension is mandatory and atomic with the hook + Phase 1.6 (now reflected in the AC and Risks).

### Remaining for #3497 (deferred)

- **Q4 — ratio heuristic tuning:** Ship with 2k tokens/line starting heuristic. After 4–6 weeks of `te-agents-md-turn-cost` data, recompute p90 of routine work and tune. Tracked at #3497.

### Surfaced during plan-time, deferred as out-of-scope

- **Synthetic-metrics summary subsection** (Phase 2 Step 2.2): the aggregator could surface per-prefix counts in a structured top-level summary block. Initial PR ships without this — operators query the raw jsonl. File a follow-up issue at end of Phase 5 if 4–6 weeks of data show structured access would help. (Tracking will piggyback on #3497's re-evaluation.)
- **Real turn-count instead of fixed 25 proxy** (Step 3.4): would require either a SessionStart hook tee or transcript-line-count parsing. Out of scope; #3497 covers the longer-tail tuning question and may absorb this.
