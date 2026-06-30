#!/usr/bin/env bash
# phase-surface-hint.sh — PostToolUse hook (matcher "Skill") for L3 per-phase
# tool/skill scoping (#5768, ADR-070).
#
# Reads the PostToolUse envelope on stdin, maps tool_input.skill -> a workflow
# phase via .claude/phase-surface-map.json, and injects that phase's
# fail-open ADDITIVE hint as hookSpecificOutput.additionalContext. Removes
# nothing — biases which skills/agents the model foregrounds, never restricts
# tool availability (two-tier fail-open rule, ADR-070).
#
# Live-verified (CC 2.1.196, #5768 Phase 0 probe): PostToolUse fires for the
# Skill tool and its additionalContext reaches the model as a <system-reminder>.
#
# Fail-open contract (load-bearing): exit 0 on EVERY path. A non-zero exit does
# not merely "not block" — it SILENTLY DROPS the additionalContext (CC: exit 2 =
# blocking error, any other non-zero = JSON output skipped). Any
# unmapped/missing-map/jq-failure => emit nothing => full surface.
#
# Security (tool_input.skill is MODEL-controlled, NOT config-trust — a
# prompt-injected model in a WebFetch/research flow can emit a crafted skill
# name): the emitted hint is composed from MAP-DERIVED CONSTANT TEXT ONLY (P1-1);
# the phase lookup parameterizes the skill via `jq --arg` (never interpolated
# into the filter / eval / a path) (P1-2); the envelope is built with `jq -n
# --arg` (never printf/concat) (P1-3). The skill name never appears in output.
#
# Precedent mirrored: pencil-collapse-guard.sh (PostToolUse emit + set flags +
# exit-0), skill-invocation-logger.sh:46 (stdin jq extract), session-rules-
# loader.sh:22-29,195-200 (ERR-trap / command-sub-in-assignment exemption).
#
# Kill-switch: SOLEUR_DISABLE_PHASE_HINT=1 short-circuits.
# Test seam: PHASE_SURFACE_MAP overrides the map path.
set -uo pipefail
# `set -e` is deliberately OFF: a non-zero exit drops the additionalContext
# (see contract above). Errors are handled inline; the trap is the backstop.
trap 'exit 0' ERR

[[ "${SOLEUR_DISABLE_PHASE_HINT:-}" == "1" ]] && exit 0

# Repo-root resolution (canonicalize via cd -P + pwd -P; mirrors
# skill-invocation-logger.sh so a symlinked .claude/ resolves consistently).
_repo_root() {
  if [[ -n "${PHASE_HINT_REPO_ROOT:-}" ]]; then echo "$PHASE_HINT_REPO_ROOT"; return; fi
  (cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd -P)
}

INPUT="$(cat 2>/dev/null || true)"
# P1-2: skill is extracted, never interpolated into a jq program / eval / path.
SKILL="$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null || true)"
[[ -z "$SKILL" ]] && exit 0

repo_root="$(_repo_root)" || exit 0
MAP="${PHASE_SURFACE_MAP:-$repo_root/.claude/phase-surface-map.json}"
[[ -f "$MAP" ]] || exit 0

# P1-2: parameterized lookup. jq --arg makes the model-controlled skill name an
# inert string argument — metacharacters / newlines / $(...) cannot escape into
# the filter program.
PHASE="$(jq -r --arg s "$SKILL" '.skill_to_phase[$s] // empty' "$MAP" 2>/dev/null || true)"
[[ -z "$PHASE" ]] && exit 0

# P1-1: hint is composed from MAP-DERIVED CONSTANT TEXT ONLY (phase name +
# phase_to_surface[phase]). The skill name (the model-controlled key) is NEVER
# echoed into the output. Build the hint string with jq from the map itself so
# no shell interpolation of map content occurs either.
HINT="$(jq -r --arg p "$PHASE" '
  .phase_to_surface[$p] as $s
  | if $s == null then empty else
      "[phase-scope] You are in the \($p) phase. "
      + (if ($s.relevant_skills // []) | length > 0
         then "Phase-relevant skills: " + (($s.relevant_skills) | join(", ")) + ". " else "" end)
      + (if ($s.relevant_agents // []) | length > 0
         then "Phase-relevant agents: " + (($s.relevant_agents) | join(", ")) + ". " else "" end)
      + (if ($s.not_live_note // "") != "" then "Not yet live: " + $s.not_live_note + " " else "" end)
      + "(Guidance only — all tools remain available; this never restricts what you can call.)"
    end' "$MAP" 2>/dev/null || true)"
[[ -z "$HINT" ]] && exit 0

# P1-3: envelope built with `jq -n --arg` — $hint is emitted as a fully-escaped
# JSON string value; it cannot break the envelope or smuggle a sibling field.
jq -n --arg hint "$HINT" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$hint}}' 2>/dev/null || exit 0

exit 0
