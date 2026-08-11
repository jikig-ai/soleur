#!/usr/bin/env bash
# test-sync-producer-reachability.sh — the decisive cell for #7442.
#
# Run via:  bash tests/commands/test-sync-producer-reachability.sh
#
# Simulates the reported failure: /soleur:sync invoked from a CUSTOMER repo with
# CLAUDE_PLUGIN_ROOT UNSET, where the customer's own tree contains files with the
# same names as our producers. Under the pre-fix CWD-relative form those decoys
# EXECUTE; under the shipped form they must not.
#
# Fixtures are synthesized (cq-test-fixtures-synthesized-only).
#
# The matrix cell that matters is customer-CWD + var-UNSET + decoys planted at
# BOTH the repo-root `scripts/` path AND the payload `plugins/soleur/scripts/`
# path. A suite that SETS the variable whose absence is the bug is a manufactured
# pass; this suite never sets it for the negative cells.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_MD="$REPO_ROOT/plugins/soleur/commands/sync.md"
[[ -f "$SYNC_MD" ]] || { echo "FATAL: sync.md not found at $SYNC_MD" >&2; exit 2; }

PASS=0
FAIL=0
CASES=0
pass() { echo "[ok] $1"; PASS=$((PASS + 1)); CASES=$((CASES + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); CASES=$((CASES + 1)); }

# --- fake customer repo -------------------------------------------------------
CUST="$(mktemp -d "$TMPDIR/sync-reach.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$CUST"' EXIT

MARKERS="$CUST/.executed"
mkdir -p "$CUST/scripts" "$CUST/plugins/soleur/scripts" "$MARKERS" || {
  echo "FATAL: fixture mkdir failed" >&2; exit 2; }

plant_decoy() {
  local rel="$1" name="$2"
  cat > "$CUST/$rel" <<EOF
#!/usr/bin/env bash
touch "$MARKERS/$name"
EOF
  chmod +x "$CUST/$rel" || { echo "FATAL: chmod failed for $rel" >&2; exit 2; }
}

plant_decoy "scripts/rule-prune.sh"                                 "rule-prune"
plant_decoy "scripts/rule-metrics-aggregate.sh"                     "rule-metrics-aggregate"
plant_decoy "scripts/domain-model-drift.sh"                         "domain-model-drift"
plant_decoy "plugins/soleur/scripts/write-kb-coverage.ts"           "write-kb-coverage"
plant_decoy "plugins/soleur/scripts/generate-c4-from-components.ts" "generate-c4"

SHIM="$CUST/.shim"
mkdir -p "$SHIM" || { echo "FATAL: shim mkdir failed" >&2; exit 2; }
cat > "$SHIM/bun" <<'EOF'
#!/usr/bin/env bash
exec bash "$@"
EOF
chmod +x "$SHIM/bun" || { echo "FATAL: chmod bun shim failed" >&2; exit 2; }

marker_names() { find "$MARKERS" -type f -exec basename {} \; 2>/dev/null | sort | tr '\n' ' '; }

# --- extraction ---------------------------------------------------------------
# Fenced/indented lines AND inline code spans. The inline branch is load-bearing:
# the two rule-prune invocations this suite characterizes were inline spans inside
# numbered list items before #7442, and a line-start-only extractor returns ZERO
# for such a site — making every assertion below vacuous for exactly the shape the
# fix exists to constrain.
extract_from() {
  local md="$1"
  {
    grep -nE '^[[:space:]]*(bash|bun|node|sh|python3?)[[:space:]]+[^[:space:]]' "$md" \
      | sed 's/^[0-9]*:[[:space:]]*//'
    grep -oE '`[^`]+`' "$md" | tr -d '`' \
      | grep -E '^[[:space:]]*(bash|bun|node|sh|python3?)[[:space:]]+[^[:space:]]'
  } | sed 's/[[:space:]]*$//' | sort -u
}

mapfile -t INVOCATIONS < <(extract_from "$SYNC_MD")
if [[ "${#INVOCATIONS[@]}" -lt 1 ]]; then
  echo "FATAL: extracted zero invocations from sync.md — the extractor is broken," >&2
  echo "       which would make every assertion below vacuously green." >&2
  exit 2
fi

# Run one invocation in the fake customer repo with the plugin root UNSET.
#
# `set +u` is load-bearing and was a real defect: this suite's own `set -u` made
# bash abort at PARAMETER EXPANSION for all 8 invocations, so not one ever
# reached path resolution and T0c was green because bash died early rather than
# because the fix works. A Claude Code Bash block does not run under `set -u`, so
# inheriting it here tested a shell mode the real surface never inhabits.
run_invocation() {
  local cmd="$1"
  cmd="${cmd//<n>/8}"; cmd="${cmd//<a>/anchor}"; cmd="${cmd//<s>/statement}"
  cmd="${cmd%\\}"
  (
    cd "$CUST" || exit 0
    set +u
    unset CLAUDE_PLUGIN_ROOT SOLEUR_MONOREPO
    PATH="$SHIM:$PATH"
    eval "$cmd" >/dev/null 2>&1
  )
}

# --- T0a: no producer operand may be CWD-relative ------------------------------
# Stronger than an exemption list, which is launderable: any invocation can be
# wrapped in an `if` to buy an exemption, and a gate on a SEPARATE LINE does not
# survive a line-wise reader. Requiring the operand itself to be non-relative
# makes each invocation line safe in isolation.
unanchored=0
for inv in "${INVOCATIONS[@]}"; do
  operand="$(awk '{print $2}' <<<"$inv")"
  bare="${operand%\"}"; bare="${bare#\"}"
  case "$bare" in
    '${CLAUDE_PLUGIN_ROOT}'/*)   ;;
    '${SOLEUR_MONOREPO:?'*)      ;;
    /*)                          ;;
    *) fail "T0a: producer operand is CWD-relative: $inv"; unanchored=$((unanchored + 1)); continue ;;
  esac
  # `..` escapes the payload after normalization even from an anchored prefix.
  case "$bare" in
    */../*|*/..) fail "T0a: operand escapes the payload via ..: $inv"; unanchored=$((unanchored + 1)) ;;
  esac
done
[[ "$unanchored" -eq 0 ]] && pass "T0a: no producer operand is CWD-relative or ..-escaping"

# --- T0b ----------------------------------------------------------------------
if grep -Fq '${CLAUDE_PLUGIN_ROOT:-' "$SYNC_MD" || grep -Fq '${CLAUDE_PLUGIN_ROOT:?' "$SYNC_MD"; then
  fail "T0b: sync.md contains a \${CLAUDE_PLUGIN_ROOT:-…} or :? default — that is the vector"
else
  pass "T0b: no \${CLAUDE_PLUGIN_ROOT:-…} / :? default in sync.md"
fi

# --- T0c: THE DECISIVE CELL ---------------------------------------------------
rm -f "$MARKERS"/* 2>/dev/null
for inv in "${INVOCATIONS[@]}"; do run_invocation "$inv"; done
executed="$(marker_names)"
if [[ -n "${executed// /}" ]]; then
  fail "T0c: DECOYS EXECUTED from the customer tree: $executed"
else
  pass "T0c: customer CWD + CLAUDE_PLUGIN_ROOT unset → no decoy executed"
fi

# --- T0d: POSITIVE CONTROL, over the EXTRACTOR ---------------------------------
# The previous form eval'd two hardcoded literals and never touched the
# extractor, so narrowing the extractor to a subset left a live pre-fix producer
# undetected with T0d still green. This runs a synthesized sync.md variant
# through the SAME extraction and the SAME loop, and REQUIRES the decoy to fire.
rm -f "$MARKERS"/* 2>/dev/null
FIXTURE="$CUST/prefix-sync.md"
cat > "$FIXTURE" <<'EOF'
# synthesized pre-fix fixture

```bash
bun plugins/soleur/scripts/write-kb-coverage.ts
```

Inline pre-fix span: `bash scripts/domain-model-drift.sh drift --repo .`
EOF
mapfile -t FIXTURE_INVOCATIONS < <(extract_from "$FIXTURE")
if [[ "${#FIXTURE_INVOCATIONS[@]}" -ne 2 ]]; then
  fail "T0d: control extracted ${#FIXTURE_INVOCATIONS[@]} of 2 invocations — the EXTRACTOR is broken, so T0c's green is untrustworthy"
else
  for inv in "${FIXTURE_INVOCATIONS[@]}"; do run_invocation "$inv"; done
  if [[ -f "$MARKERS/write-kb-coverage" && -f "$MARKERS/domain-model-drift" ]]; then
    pass "T0d: positive control — pre-fix form, via the same extractor, DOES execute the customer's files"
  else
    fail "T0d: positive control did not fire ($(marker_names)); T0c's green is UNTRUSTWORTHY (harness defect)"
  fi
fi
rm -f "$MARKERS"/* 2>/dev/null

# --- T0e: residency -----------------------------------------------------------
missing=0
for inv in "${INVOCATIONS[@]}"; do
  operand="$(awk '{print $2}' <<<"$inv")"
  bare="${operand%\"}"; bare="${bare#\"}"
  case "$bare" in '${CLAUDE_PLUGIN_ROOT}'/*) ;; *) continue ;; esac
  rel="${bare#\$\{CLAUDE_PLUGIN_ROOT\}/}"
  if [[ ! -e "$REPO_ROOT/plugins/soleur/$rel" ]]; then
    fail "T0e: anchored operand does not exist in the payload: plugins/soleur/$rel"
    missing=$((missing + 1))
  fi
done
[[ "$missing" -eq 0 ]] && pass "T0e: every anchored operand resides in the plugin payload"

# --- T0f / T0g ----------------------------------------------------------------
HALT='SOLEUR_SYNC_AREA_UNAVAILABLE area=rule-prune reason=monorepo-only-maintenance-area'
halt_count="$(grep -Fc "$HALT" "$SYNC_MD" || true)"
if [[ "$halt_count" -ge 2 ]]; then
  pass "T0f: rule-prune halt literal present at both gated call sites ($halt_count)"
else
  fail "T0f: expected the halt literal at >=2 call sites, found $halt_count"
fi

if grep -nE '^argument-hint:' "$SYNC_MD" | grep -Fq 'rule-prune'; then
  fail "T0g: rule-prune still advertised in argument-hint"
elif grep -nE '^\*\*Valid areas:\*\*' "$SYNC_MD" | grep -Fq 'rule-prune'; then
  fail "T0g: rule-prune still advertised in Valid areas"
else
  pass "T0g: rule-prune de-advertised from argument-hint and Valid areas"
fi

# --- T0h: the fail-closed preflight exists ------------------------------------
# ADR-177 decision 2. Without this, the block carrying the whole safety argument
# is deletable with the suite green.
if grep -Fq '"${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"' "$SYNC_MD"; then
  pass "T0h: sync.md carries the fail-closed plugin-identity preflight"
else
  fail "T0h: sync.md has no plugin-identity preflight (ADR-177 decision 2)"
fi

# --- T0i: the preflight is EXECUTED, not spell-checked -------------------------
# T0h asserts a string is present, which is satisfied by a gutted gate that still
# mentions the manifest path — measured: downgrading the check to `[ -d "$X/scripts" ]`
# and neutralizing the whole block both left T0h green. This extracts the real
# block and runs it against a hostile root: a directory carrying a `scripts/`
# child but no Soleur manifest, which is exactly the ambient-CLAUDE_PLUGIN_ROOT
# vector (a .envrc / ~/.bashrc / postinstall export).
PREFLIGHT="$CUST/preflight.sh"
awk '/^SOLEUR_ROOT_OK=0$/{c=1} c{print} /^fi$/{if(c && ++n==2) exit}' "$SYNC_MD" > "$PREFLIGHT"
if [[ ! -s "$PREFLIGHT" ]]; then
  fail "T0i: could not extract the preflight block from sync.md — the assertion below would be vacuous"
else
  HOSTILE="$CUST/hostile-root"
  mkdir -p "$HOSTILE/scripts"
  hostile_rc=0
  ( cd "$CUST" && set +u && CLAUDE_PLUGIN_ROOT="$HOSTILE" bash "$PREFLIGHT" >/dev/null 2>&1 ) || hostile_rc=$?

  GOODROOT="$REPO_ROOT/plugins/soleur"
  good_rc=0
  ( cd "$CUST" && set +u && CLAUDE_PLUGIN_ROOT="$GOODROOT" bash "$PREFLIGHT" >/dev/null 2>&1 ) || good_rc=$?

  if [[ "$hostile_rc" -ne 0 && "$good_rc" -eq 0 ]]; then
    pass "T0i: preflight REFUSES a hostile root with a scripts/ child (rc=$hostile_rc) and ACCEPTS the real payload"
  elif [[ "$hostile_rc" -eq 0 ]]; then
    fail "T0i: preflight ACCEPTED a hostile root carrying only a scripts/ dir — the ambient-CLAUDE_PLUGIN_ROOT vector is open"
  else
    fail "T0i: preflight REJECTED the real payload root (rc=$good_rc) — it would refuse on every surface"
  fi
fi

# --- anti-vacuity floor -------------------------------------------------------
# Neutering pass()/fail() or deleting a case otherwise summarizes green and
# exits 0. Absolute and hand-ratcheted; a floor derived from the cases would
# simply descend with a deletion.
EXPECTED_CASES=9
if [[ "$CASES" -ne "$EXPECTED_CASES" ]]; then
  echo "[FAIL] anti-vacuity: ran $CASES of $EXPECTED_CASES cases — a case was deleted or its counter neutered" >&2
  FAIL=$((FAIL + 1))
fi

echo "=== $PASS passed, $FAIL failed ($CASES/$EXPECTED_CASES cases) ==="
[[ "$FAIL" -eq 0 && "$CASES" -eq "$EXPECTED_CASES" ]]
