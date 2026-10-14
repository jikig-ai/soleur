#!/usr/bin/env bash
# write-budget-marker.sh <dim> — write the classified `budget-capped` artifact
# for a ship/merge-pr phase-7 poll gate STOP (#9403). Emits nothing; exits 0
# always (fail-open like the tally itself). Extracted so the ship↔merge-pr
# mirror carries one implementation, not a byte-copied block.
set -uo pipefail

dim="${1:?usage: write-budget-marker.sh <dim>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

show="$(bash "$ROOT/scripts/pipeline-tally.sh" show 2>/dev/null || true)"
cnt="$(printf '%s\n' "$show" | grep -o "${dim}=[0-9]*" | head -1 | cut -d= -f2 || true)"
cap="$(printf '%s\n' "$show" | grep -o "cap:${dim}=[0-9]*" | head -1 | cut -d= -f2 || true)"
# $() strips the newline before tr sees it; tr inside the substitution would
# map it to a stray '-'. Marker lands in the specs/<feature>/ dir the resume
# contract greps — the same shape the skills' classified-stop blocks write.
b="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
ss="knowledge-base/project/specs/$(printf '%s' "${b:-HEAD}" | tr -c 'A-Za-z0-9._-' '-')"
mkdir -p "$ss" 2>/dev/null \
  && printf 'status: budget-capped\nbudget-capped: %s=%s/%s\nresume: bash "%s/scripts/pipeline-tally.sh" init --max-%s <N>, then re-run the skill\n' \
       "$dim" "${cnt:-0}" "${cap:-0}" "$ROOT" "$(printf '%s' "$dim" | tr '_' '-')" \
       >> "$ss/session-state.md" || true
exit 0
