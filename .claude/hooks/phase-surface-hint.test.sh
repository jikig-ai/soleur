#!/usr/bin/env bash
# Tests for phase-surface-hint.sh (PostToolUse, matcher Skill) + the
# .claude/phase-surface-map.json registry consistency (#5768).
#
# Mirrors plugins/soleur/skills/eval-harness/test/registry-completeness.test.sh
# (PARITY / CHARSET / NEGATIVE) and the three accumulate-then-exit foot-guns from
# knowledge-base/project/learnings/test-failures/2026-06-29-bash-accumulate-then-exit-gate-test-three-footguns.md:
#   (a) nonzero command-sub (diff/grep) wrapped with `|| true`, gated on emptiness
#   (b) data-derived loop carries a minimum-cardinality guard
#   (c) NEGATIVE injects real-shaped bad data and asserts the verifier flags it
#
# Auto-discovered by scripts/test-all.sh (.claude/hooks/*.test.sh glob).
set -uo pipefail

HOOK_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -P "$HOOK_DIR/../.." && pwd -P)"
HOOK="$HOOK_DIR/phase-surface-hint.sh"
MAP="$REPO_ROOT/.claude/phase-surface-map.json"
SKILLS_DIR="$REPO_ROOT/plugins/soleur/skills"
AGENTS_DIR="$REPO_ROOT/plugins/soleur/agents"

fails=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

run_hook() { # stdin -> hook; echoes stdout. optional $1 overrides map path.
  local map="${1:-$MAP}"
  PHASE_SURFACE_MAP="$map" bash "$HOOK" 2>/dev/null
}

# --- Pre-req: hook + map must exist (RED guard) ---
[[ -x "$HOOK" || -f "$HOOK" ]] || { fail "hook not found at $HOOK (RED: implement phase-surface-hint.sh)"; printf '\n%d failure(s)\n' "$fails"; exit 1; }
[[ -f "$MAP" ]] || { fail "map not found at $MAP"; printf '\n%d failure(s)\n' "$fails"; exit 1; }
jq -e . "$MAP" >/dev/null 2>&1 || { fail "map is not valid JSON"; printf '\n%d failure(s)\n' "$fails"; exit 1; }

# --- BEHAVIOR: mapped skill emits a hint naming that phase ---
out="$(printf '{"tool_name":"Skill","tool_input":{"skill":"soleur:work"}}' | run_hook)"
if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
  if printf '%s' "$ctx" | grep -qi 'work'; then pass "mapped skill (soleur:work) emits work-phase hint"
  else fail "mapped skill hint does not name the work phase"; fi
  # hookEventName must be PostToolUse
  ev="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // empty')"
  [[ "$ev" == "PostToolUse" ]] && pass "emits hookEventName=PostToolUse" || fail "missing/incorrect hookEventName ($ev)"
else
  fail "mapped skill (soleur:work) did not emit a valid hookSpecificOutput object"
fi

# --- BEHAVIOR: unmapped skill -> empty output, exit 0 (fail-open) ---
out="$(printf '{"tool_name":"Skill","tool_input":{"skill":"soleur:help"}}' | run_hook)"; rc=$?
[[ -z "$out" ]] && pass "unmapped skill (soleur:help) emits nothing" || fail "unmapped skill emitted output: $out"
[[ "$rc" -eq 0 ]] && pass "unmapped skill exits 0" || fail "unmapped skill non-zero exit ($rc)"

# --- BEHAVIOR: missing skill field -> empty, exit 0 ---
out="$(printf '{"tool_name":"Skill","tool_input":{}}' | run_hook)"; rc=$?
[[ -z "$out" && "$rc" -eq 0 ]] && pass "missing skill field -> empty, exit 0" || fail "missing skill field not fail-open (out=$out rc=$rc)"

# --- BEHAVIOR: missing/corrupt map -> empty, exit 0 ---
out="$(printf '{"tool_input":{"skill":"soleur:work"}}' | run_hook "$REPO_ROOT/.claude/does-not-exist.json")"; rc=$?
[[ -z "$out" && "$rc" -eq 0 ]] && pass "missing map -> empty, exit 0" || fail "missing map not fail-open (out=$out rc=$rc)"
bad="$(mktemp)"; printf 'not json {{{' > "$bad"
out="$(printf '{"tool_input":{"skill":"soleur:work"}}' | run_hook "$bad")"; rc=$?
[[ -z "$out" && "$rc" -eq 0 ]] && pass "corrupt map -> empty, exit 0" || fail "corrupt map not fail-open (out=$out rc=$rc)"
rm -f "$bad"

# --- SECURITY (P1): adversarial skill name never executes / never appears in output ---
mal='soleur:work";injected\n$(touch /tmp/phase_surface_pwn)'
rm -f /tmp/phase_surface_pwn
out="$(printf '{"tool_input":{"skill":%s}}' "$(jq -Rn --arg s "$mal" '$s')" | run_hook)"; rc=$?
[[ ! -f /tmp/phase_surface_pwn ]] && pass "adversarial skill name executes no command" || { fail "COMMAND INJECTION: /tmp/phase_surface_pwn created"; rm -f /tmp/phase_surface_pwn; }
if printf '%s' "$out" | grep -qF 'injected'; then fail "adversarial substring leaked into output"; else pass "adversarial substring absent from output"; fi
# output must be empty (unmapped -> fail-open) OR a single valid hookSpecificOutput object
if [[ -z "$out" ]]; then pass "adversarial input -> empty (fail-open)"
elif printf '%s' "$out" | jq -e '.hookSpecificOutput' >/dev/null 2>&1; then pass "adversarial input -> valid single hookSpecificOutput"
else fail "adversarial input produced malformed output"; fi
[[ "$rc" -eq 0 ]] && pass "adversarial input exits 0" || fail "adversarial input non-zero exit"

# --- CONSISTENCY: skill_to_phase keys resolve to real SKILL.md ---
n=0
while IFS= read -r skill; do
  [[ -z "$skill" ]] && continue
  n=$((n + 1))
  base="${skill#soleur:}"
  [[ -f "$SKILLS_DIR/$base/SKILL.md" ]] || fail "skill_to_phase key '$skill' has no SKILL.md at $SKILLS_DIR/$base/SKILL.md"
done < <(jq -r '.skill_to_phase | keys[]' "$MAP")
[[ "$n" -ge 1 ]] && pass "skill_to_phase keys resolved ($n skills)" || fail "skill_to_phase empty / unreadable (cardinality guard)"

# --- CONSISTENCY: every skill_to_phase value is a phase_to_surface key (dangling-phase, spec-flow #6) ---
dangling="$(jq -r '
  (.phase_to_surface | keys) as $phases
  | .skill_to_phase | to_entries[]
  | select((.value as $v | $phases | index($v)) | not)
  | "\(.key)->\(.value)"' "$MAP" 2>/dev/null || true)"
[[ -z "$dangling" ]] && pass "no dangling phase values" || fail "dangling phase value(s): $dangling"

# --- CONSISTENCY: relevant_agents resolve to a real agent file (basename match) ---
m=0
while IFS= read -r agent; do
  [[ -z "$agent" ]] && continue
  m=$((m + 1))
  found="$(find "$AGENTS_DIR" -name "$agent.md" -print -quit 2>/dev/null || true)"
  [[ -n "$found" ]] || fail "relevant_agent '$agent' has no agent file under $AGENTS_DIR"
done < <(jq -r '.phase_to_surface[].relevant_agents[]?' "$MAP")
# Minimum-cardinality guard (foot-gun b): a data-derived loop that yields zero
# iterations must not pass vacuously. Mirrors the skill_to_phase loop above.
[[ "$m" -ge 1 ]] && pass "relevant_agents checked ($m references)" || fail "relevant_agents loop iterated zero times (cardinality guard)"

# --- CONSISTENCY: 5 core phases present ---
for phase in brainstorm plan work review ship; do
  jq -e --arg p "$phase" '.phase_to_surface[$p]' "$MAP" >/dev/null 2>&1 \
    && pass "core phase '$phase' present" || fail "core phase '$phase' missing from phase_to_surface"
done

# --- NEGATIVE: verify the verifier — inject a dangling phase value, assert detection ---
neg="$(mktemp)"
jq '.skill_to_phase["soleur:__probe__"] = "nonexistent_phase"' "$MAP" > "$neg"
dangling_neg="$(jq -r '
  (.phase_to_surface | keys) as $phases
  | .skill_to_phase | to_entries[]
  | select((.value as $v | $phases | index($v)) | not)
  | "\(.key)->\(.value)"' "$neg" 2>/dev/null || true)"
if printf '%s' "$dangling_neg" | grep -qF 'soleur:__probe__->nonexistent_phase'; then
  pass "NEGATIVE: dangling-phase injection is detected"
else
  fail "NEGATIVE: verifier failed to detect injected dangling phase"
fi
rm -f "$neg"

printf '\n%d failure(s)\n' "$fails"
[[ "$fails" -eq 0 ]] || exit 1
