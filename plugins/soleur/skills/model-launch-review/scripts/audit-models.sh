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
# At each launch: (1) ADD a pair for the newly-superseded id, AND (2) RETARGET
# every existing same-tier pair's RHS to the new current id. Step 2 is not
# optional — `--fix` applies pairs sequentially, so a CHAINED map
# (4-7=4-8 alongside 4-8=5) is order-dependent and lands on a stale id.
# The SINGLE-HOP INVARIANT below enforces this mechanically: no target may
# also appear as a source. Source of truth for current ids: the claude-api
# skill table + https://platform.claude.com/docs/en/about-claude/models/overview.md
# (pricing: https://platform.claude.com/docs/en/about-claude/pricing.md).
AUTOFIX_PAIRS=(
  "claude-opus-4-8=claude-opus-5"
  "claude-opus-4-7=claude-opus-5"
  "claude-opus-4-6=claude-opus-5"
  "claude-sonnet-4-6=claude-sonnet-5"
  "claude-sonnet-4-5=claude-sonnet-5"
  "claude-fable-5=claude-fable-5-1"
)

# SINGLE-HOP INVARIANT (fail-fast). A convergent map rewrites every stale id
# in ONE pass; if any RHS is also an LHS, `--fix` leaves files on an
# intermediate id and `--detect` re-flags them forever (a permanently-red
# drift cron that auto-files issues it cannot fix). Cheap to assert, so assert
# it on every invocation rather than trusting the editor to have retargeted.
assert_single_hop() {
  local p from to q other
  for p in "${AUTOFIX_PAIRS[@]}"; do
    to="${p#*=}"
    for q in "${AUTOFIX_PAIRS[@]}"; do
      other="${q%%=*}"
      if [[ "$to" == "$other" ]]; then
        from="${p%%=*}"
        echo "audit-models: NON-CONVERGENT AUTOFIX_PAIRS — '${from}' maps to '${to}', which is itself a source id." >&2
        echo "  Retarget every same-tier pair directly to the current id (no chaining)." >&2
        exit 78
      fi
    done
  done
}
assert_single_hop
# The stale ids (LHS of each pair), '|'-joined for grep.
autofix_from_re() {
  local p out=""
  for p in "${AUTOFIX_PAIRS[@]}"; do out="${out:+$out|}${p%%=*}"; done
  printf '%s' "$out"
}

# RIGHT-BOUNDARY of a model id: the next char must not extend the id. Model ids
# are [0-9A-Za-z-], so a bare alternation would match a PREFIX of a longer id.
#
# This is not hypothetical: `claude-fable-5` is a strict prefix of its own
# successor `claude-fable-5-1` — the first pair in this table where that is
# true (opus-4-8 -> opus-5 and sonnet-4-6 -> sonnet-5 share no prefix). The
# `--fix` sed has always been anchored, but SELECTION was not, so a file
# already sitting on `claude-fable-5-1` was picked as a hit, `--fix` reported
# "fixed" while changing nothing, and `--detect` re-flagged it forever: the
# permanently-red drift cron that auto-files issues it cannot fix — the same
# failure mode the single-hop invariant above exists to prevent, reached by
# prefix-shadowing instead of chaining. `assert_single_hop` does NOT catch it
# ('claude-fable-5-1' is not itself a source id).
#
# Selection and rewriting MUST use this one boundary, or they can disagree
# again: the sed cannot fix what only the grep considers stale.
ID_BOUNDARY='([^0-9A-Za-z-]|$)'

# Anchored matcher — the ONLY pattern that may decide "this file is stale".
autofix_match_re() { printf '%s%s' "($(autofix_from_re))" "$ID_BOUNDARY"; }

FLAG_ONLY_STALE_RE='claude-3[._-]|claude-(opus|sonnet|haiku)-[0-9.]+-20250[0-9]+'

DELETION_GUARD=20   # abort --fix if any file would lose more than this many lines

# Path classes excluded from the config (auto-fix) surface. knowledge-base/** is
# archival/historical prose (learnings, plans, brainstorms) — it never selects a
# model at runtime, so a stale id there is not operational drift.
# `\.generated\.` keeps the sweeper out of generated artifacts: those have a
# generator that reads the TS registry (eval-harness/scripts/gen-models.sh), and
# a blind sed here would make the generator no longer the sole writer — exactly
# the second-SSOT the generator's own header promises does not exist.
EXCLUDE_RE='(/node_modules/|/\.git/|/\.next/|/test/|/__tests__/|/spike/|/archive/|knowledge-base/|/community/|\.test\.|\.spec\.|\.generated\.|/model-launch-review/)'

# Collect config-class files containing any auto-fixable stale ID.
# Returns 2 (and prints to stderr) if the scan itself failed. That distinction
# is load-bearing: `|| true` alone swallows grep's error exit (>=2: unreadable
# dir, bad regex) as indistinguishable from its no-match exit (1), so --detect
# would report a confident "none — config model IDs are current" from a scan
# that never ran. A detector that cannot tell "clean" from "could not look" is
# the failure mode #5100 exists to prevent.
collect_config_hits() {
  local re out rc
  re="$(autofix_match_re)"
  out="$(grep -rEl "$re" "$ROOT" \
    --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.next \
    --exclude-dir=test --exclude-dir=__tests__ --exclude-dir=spike --exclude-dir=archive \
    --exclude-dir=community \
    --exclude='*.test.*' --exclude='*.spec.*' 2>/dev/null)"
  rc=$?
  if (( rc >= 2 )); then
    echo "audit-models: scan FAILED (grep rc=$rc) under '$ROOT' — refusing to report clean." >&2
    return 2
  fi
  [[ -n "$out" ]] || return 0
  printf '%s\n' "$out" | grep -vE "$EXCLUDE_RE" || true
}

rel() { echo "${1#"$ROOT"/}"; }

# Shared hits capture. `mapfile -t hits < <(collect_config_hits)` DISCARDS the
# function's exit code, so a failed scan would fall straight through to the
# "clean" branch in every mode — the exact absent-vs-could-not-look conflation
# this script was fixed for. Route the capture through a file so the rc
# survives, and give EVERY mode the same abort. One owning trap (ADR-129).
_HITS_TMP="$(mktemp)"
trap 'rm -f "$_HITS_TMP"' EXIT

# Populates the global `hits` array, or aborts naming the mode that failed.
load_hits() { # $1 = label for the failure line
  if ! collect_config_hits > "$_HITS_TMP"; then
    echo "$1: UNKNOWN — scan failed; treat as un-run, not clean."
    exit 1
  fi
  mapfile -t hits < "$_HITS_TMP"
}

# ---------------- detect mode (cron) ----------------
if [[ "$MODE" == "detect" ]]; then
  load_hits "model-drift"
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
  load_hits "model-fix"
  for f in "${hits[@]}"; do
    before=$(wc -l < "$f")
    tmp="$(mktemp)"
    cp "$f" "$tmp"
    for pair in "${AUTOFIX_PAIRS[@]}"; do
      from="${pair%%=*}"; to="${pair#*=}"
      # anchored on the SAME boundary as selection (ID_BOUNDARY): preserve the
      # trailing char so a longer/dated variant (claude-opus-4-7-20260101) or a
      # successor that extends the stale id (claude-fable-5-1) is NOT corrupted
      # by a prefix swap.
      sed -i -E "s/${from}${ID_BOUNDARY}/${to}\1/g" "$f"
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
load_hits "  model-ID inventory"
if [[ ${#hits[@]} -gt 0 ]]; then
  echo "  stale config model IDs found (mechanical same-tier swap):"
  for f in "${hits[@]}"; do
    # Same anchored matcher as selection, then drop the boundary char the
    # pattern had to capture (an end-of-line match captures nothing to drop),
    # so the report names the id and not `claude-fable-5"`.
    ids="$(grep -oE "$(autofix_match_re)" "$f" | sed -E 's/[^0-9A-Za-z-]+$//' | sort -u | tr '\n' ' ')"
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
  # Compute the drift rather than telling a human to run a command
  # (hr-no-dashboard-eyeball-pull-data-yourself). Best-effort: `gh` may be
  # absent or unauthenticated in a cron sandbox, and that MUST read as
  # UNKNOWN — never as "the pin is fresh".
  if command -v gh >/dev/null 2>&1; then
    _tip="$(gh api repos/anthropics/claude-code-action/releases --jq '.[0].tag_name' 2>/dev/null || true)"
    _pin_sha="$(grep -ohE 'claude-code-action@[a-f0-9]{40}' "${pins[@]}" 2>/dev/null | head -1 | cut -d@ -f2)"
    # These pins are annotated TAG objects, so git/tags resolves them. A pin
    # produced by pin-github-action/Dependabot is a plain COMMIT sha, where
    # git/tags 404s and commits/<sha> is the correct call — try both.
    _pin_desc=""
    if [[ -n "$_pin_sha" ]]; then
      _pin_desc="$(gh api "repos/anthropics/claude-code-action/git/tags/$_pin_sha" --jq '"\(.tag) \(.tagger.date)"' 2>/dev/null \
        || gh api "repos/anthropics/claude-code-action/commits/$_pin_sha" --jq '"(commit) \(.commit.committer.date)"' 2>/dev/null \
        || true)"
    fi
    if [[ -n "$_tip" && -n "$_pin_desc" ]]; then
      echo "    pinned: $_pin_desc    tip: $_tip"
    else
      echo "    pin freshness: UNKNOWN (GitHub API unreachable) — NOT a freshness pass."
    fi
  else
    echo "    pin freshness: UNKNOWN (gh not on PATH) — NOT a freshness pass."
  fi
  echo "    bump a pin ONLY when coupled to a --model swap in the same workflow (#2540 invariant)."
else
  echo "  no claude-code-action pins under .github (or scanning a test root)."
fi
echo

echo "[2b] pinned claude-code CLI knows the tier models (FLAG-ONLY)"
# The `claude` CLI carries a BUNDLED per-model table. A model ID absent from it
# is treated exactly like a garbage ID: the CLI silently falls back to HALF the
# max_tokens (measured 64000 -> 32000, #6934), degrading every cron that passes
# --model. This is invisible to the model-ID sweep, to tsc, and to the suite —
# the argv is well-formed and the run succeeds. Grep the installed bundle when
# present; absence of node_modules is UNKNOWN, never a pass.
#
# WHAT IS MEASURED: the INSTALLED tree, which is not necessarily the PIN. The
# model table ships in the platform binary (@anthropic-ai/claude-code-linux-x64),
# fetched by the stub's postinstall — the npm tarball for @anthropic-ai/claude-code
# is a ~23 kB launcher that contains no model ids at all, so only an installed
# (or separately unpacked platform) tree can answer this question.
#
# A stale node_modules therefore reports DRIFT against ids the PIN actually
# knows. Observed 2026-09-03: node_modules held 2.1.142 while package.json
# pinned 2.1.219, and this check reported `claude-opus-5` and `claude-sonnet-5`
# ABSENT — both are present in 2.1.219. A false DRIFT here costs a needless
# dependency bump; the same skew in the other direction (node_modules NEWER
# than the pin) would report a false PASS, which is worse. So state the two
# versions and refuse to call a mismatch a measurement of the pin.
_cli_pinned="$(grep -oE '"@anthropic-ai/claude-code"[[:space:]]*:[[:space:]]*"[^"]+"' \
  "$ROOT/apps/web-platform/package.json" 2>/dev/null | grep -oE '[0-9][^"]*' || true)"
_cli_installed="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' \
  "$ROOT/apps/web-platform/node_modules/@anthropic-ai/claude-code/package.json" 2>/dev/null \
  | head -1 | grep -oE '[0-9][^"]*' || true)"
if [[ -n "$_cli_pinned" && -n "$_cli_installed" && "$_cli_pinned" != "$_cli_installed" ]]; then
  echo "    NOTE: measuring INSTALLED ${_cli_installed}, but package.json pins ${_cli_pinned}."
  echo "          Findings below describe the installed tree, NOT the pin — reinstall before trusting them."
elif [[ -n "$_cli_pinned" ]]; then
  echo "    measuring installed tree @ ${_cli_pinned} (matches the package.json pin)."
fi
_cli_dir="$ROOT/apps/web-platform/node_modules/@anthropic-ai"
if [[ -d "$_cli_dir" ]]; then
  # `fable` included: the alternation must cover every tier that can appear in
  # the scanned registries, or the one model whose id the pin lacks is the one
  # model never checked. (Fable reaches Soleur as the harness `model: fable`
  # ALIAS today, so no fable literal is in these files yet — this closes the
  # gap for the launch where one lands.)
  for _m in $(grep -ohE '"claude-(opus|sonnet|haiku|fable)-[0-9a-z-]+"' \
                "$ROOT/apps/web-platform/server/inngest/model-tiers.ts" \
                "$ROOT/apps/web-platform/server/inngest/leader-prompts/constants.ts" 2>/dev/null \
              | tr -d '"' | sort -u); do
    # -a: the linux-x64 CLI is a compiled binary; a text-mode grep silently
    # reports zero hits for EVERY id, including known-good ones (a null result
    # that reads exactly like a real one).
    if grep -raqF "$_m" "$_cli_dir" 2>/dev/null; then
      echo "    ok      $_m present in the pinned CLI bundle"
    else
      echo "    DRIFT   $_m ABSENT from the pinned CLI bundle — bump @anthropic-ai/claude-code"
    fi
  done
else
  echo "    UNKNOWN (apps/web-platform/node_modules absent) — NOT a pass; run after install."
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
