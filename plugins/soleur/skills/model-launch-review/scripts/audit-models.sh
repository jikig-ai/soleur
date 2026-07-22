#!/usr/bin/env bash
# audit-models.sh — deterministic auditor for the per-Anthropic-model-release checklist.
#
# Modes:
#   (default)   full audit report to stdout; every check group is named (no silent green).
#   --detect    cron signal: exit 10 if config-class model-ID drift is found, 0 if clean.
#               One-line summary to stdout. Used by the rule-audit.yml detection step.
#   --fix       apply MECHANICAL model-ID swaps to config-class files only (auto-fix surface).
#               pin / pricing / tier-map / dormant are FLAG-ONLY and never mutated here.
#
# Options:
#   --root DIR  scan DIR instead of the git repo root (test harness uses this).
#
# Auto-fix surface = stale model IDs in config. Excluded from auto-fix (never mutated):
#   test fixtures (*/test/*, *.test.*), archives (**/archive/**), spikes (*/spike/*),
#   all of knowledge-base/** (docs/plans/specs/brainstorms/learnings — archival prose
#   that never selects a model at runtime), community digests.
# Source of truth for current IDs: the claude-api skill table + official docs.
set -euo pipefail

ROOT=""
MODE="audit"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --detect) MODE="detect"; shift ;;
    --fix) MODE="fix"; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
ROOT="${ROOT%/}"   # normalize: trailing slash breaks rel() prefix-strip

# --- current landscape — update at each model launch ---
# Each superseded id maps to the CURRENT same-tier id as "<stale>=<current>".
# Add a pair when a new model ships in an existing tier (the next Sonnet/Opus);
# `--fix` rewrites each stale id to ITS OWN target, so multiple tiers coexist.
# Older families (claude-3, dated 2025 ids) stay flag-only (too old for a blind
# swap). Source of truth for current ids: the claude-api skill table + docs.
AUTOFIX_PAIRS=(
  "claude-opus-4-7=claude-opus-4-8"
  "claude-opus-4-6=claude-opus-4-8"
  "claude-sonnet-4-6=claude-sonnet-5"
  "claude-sonnet-4-5=claude-sonnet-5"
)
# The stale ids (LHS of each pair), '|'-joined for grep.
autofix_from_re() {
  local p out=""
  for p in "${AUTOFIX_PAIRS[@]}"; do out="${out:+$out|}${p%%=*}"; done
  printf '%s' "$out"
}
FLAG_ONLY_STALE_RE='claude-3[._-]|claude-(opus|sonnet|haiku)-[0-9.]+-20250[0-9]+'

DELETION_GUARD=20   # abort --fix if any file would lose more than this many lines

# Path classes excluded from the config (auto-fix) surface. knowledge-base/** is
# archival/historical prose (learnings, plans, brainstorms) — it never selects a
# model at runtime, so a stale id there is not operational drift.
EXCLUDE_RE='(/node_modules/|/\.git/|/\.next/|/test/|/__tests__/|/spike/|/archive/|knowledge-base/|/community/|\.test\.|\.spec\.|/model-launch-review/)'

# Collect config-class files containing any auto-fixable stale ID.
collect_config_hits() {
  local re
  re="$(autofix_from_re)"
  grep -rEl "$re" "$ROOT" \
    --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.next \
    --exclude-dir=test --exclude-dir=__tests__ --exclude-dir=spike --exclude-dir=archive \
    --exclude-dir=community \
    --exclude='*.test.*' --exclude='*.spec.*' 2>/dev/null \
    | grep -vE "$EXCLUDE_RE" || true
}

rel() { echo "${1#"$ROOT"/}"; }

# ---------------- detect mode (cron) ----------------
if [[ "$MODE" == "detect" ]]; then
  mapfile -t hits < <(collect_config_hits)
  if [[ ${#hits[@]} -gt 0 ]]; then
    echo "model-drift: ${#hits[@]} config file(s) carry a stale model ID (auto-fixable via /soleur:model-launch-review)."
    for f in "${hits[@]}"; do echo "  - $(rel "$f")"; done
    exit 10
  fi
  echo "model-drift: none (config model IDs current)."
  exit 0
fi

# ---------------- fix mode (mechanical model-ID swaps only) ----------------
if [[ "$MODE" == "fix" ]]; then
  mapfile -t hits < <(collect_config_hits)
  for f in "${hits[@]}"; do
    before=$(wc -l < "$f")
    tmp="$(mktemp)"
    cp "$f" "$tmp"
    for pair in "${AUTOFIX_PAIRS[@]}"; do
      from="${pair%%=*}"; to="${pair#*=}"
      # anchored: preserve the trailing char so a longer/dated variant
      # (e.g. claude-opus-4-7-20260101) is NOT corrupted by a prefix swap.
      sed -i -E "s/${from}([^0-9A-Za-z-]|\$)/${to}\1/g" "$f"
    done
    after=$(wc -l < "$f")
    # deletion guard: a 1-for-1 ID swap must not change line count materially.
    if (( before - after > DELETION_GUARD )); then
      cp "$tmp" "$f"   # revert
      rm -f "$tmp"
      echo "ABORT: $(rel "$f") would lose $((before - after)) lines (> DELETION_GUARD=$DELETION_GUARD); reverted." >&2
      exit 1
    fi
    rm -f "$tmp"
    echo "fixed: $(rel "$f")"
  done
  exit 0
fi

# ---------------- audit mode (report; no silent green) ----------------
echo "== model-launch-review audit =="
echo "root: $ROOT"
echo

echo "[1] model-ID inventory (AUTO-FIX)"
mapfile -t hits < <(collect_config_hits)
if [[ ${#hits[@]} -gt 0 ]]; then
  echo "  stale config model IDs found (mechanical same-tier swap):"
  for f in "${hits[@]}"; do
    ids="$(grep -oE "$(autofix_from_re)" "$f" | sort -u | tr '\n' ' ')"
    echo "    - $(rel "$f")  [${ids}]"
  done
  echo "  → run with --fix (each stale id → its current same-tier id), then open a CI-gated PR."
else
  echo "  none — config model IDs are current."
fi
# flag-only: very old families
mapfile -t old < <(grep -rEl "$FLAG_ONLY_STALE_RE" "$ROOT" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.next 2>/dev/null \
  | grep -vE "$EXCLUDE_RE" || true)
if [[ ${#old[@]} -gt 0 ]]; then
  echo "  FLAG (manual, too old for blind swap):"
  for f in "${old[@]}"; do echo "    - $(rel "$f")"; done
fi
echo

echo "[2] claude-code-action pin freshness (FLAG-ONLY)"
mapfile -t pins < <(grep -rl 'anthropics/claude-code-action@' "$ROOT/.github" 2>/dev/null || true)
if [[ ${#pins[@]} -gt 0 ]]; then
  echo "  workflows pinning claude-code-action:"
  for f in "${pins[@]}"; do
    echo "    - $(rel "$f"): $(grep -oE 'claude-code-action@[a-f0-9]+ # v[0-9.]+' "$f" | head -1)"
  done
  echo "  → resolve tip via: gh api repos/anthropics/claude-code-action/releases --jq '.[0].tag_name'"
  echo "    bump a pin ONLY when coupled to a --model swap in the same workflow (#2540 invariant)."
else
  echo "  no claude-code-action pins under .github (or scanning a test root)."
fi
echo

echo "[3] pricing + tier-map + dormant work (FLAG-ONLY)"
echo "  - pricing: compare apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts"
echo "    MODEL_PRICING rows against the claude-api source-of-truth; never auto-edit (billing constant)."
echo "  - tier-map: re-check cron model literals + ADR-053 / plugins/soleur/AGENTS.md policy vs new pricing."
echo "    (workflow-model-pins.test.ts PIN_ALLOWLIST is a don't-mutate invariant, not a pricing surface.)"
echo "  - dormant: gh issue list --state open -L 200 --search 'deferred model OR pricing'"
echo "  - thinking-API shape: carried by the claude-code-action pin's SDK; no config params today (no-op)."
echo
echo "== end audit =="
