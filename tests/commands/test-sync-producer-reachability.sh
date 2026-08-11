#!/usr/bin/env bash
# test-sync-producer-reachability.sh — the decisive cell for #7442.
#
# Run via:  bash tests/commands/test-sync-producer-reachability.sh
#
# Simulates the reported failure: /soleur:sync invoked from a CUSTOMER repo (not
# this monorepo) with CLAUDE_PLUGIN_ROOT UNSET, where the customer's own tree
# contains files with the same names as our producers. Under the pre-fix
# CWD-relative form those decoys EXECUTE. Under the shipped form they must not.
#
# Fixtures are synthesized (cq-test-fixtures-synthesized-only) — no real repo is
# read, and no decoy contains anything but a marker write.
#
# The matrix cell that matters is customer-CWD + var-UNSET + decoys planted at
# BOTH the repo-root `scripts/` path AND the payload `plugins/soleur/scripts/`
# path. A suite that SETS the variable whose absence is the bug is a
# manufactured pass; this suite never sets it for the negative cells.
set -uo pipefail

# /tmp is a machine-global 4 GiB tmpfs shared by parallel worktrees; a direct
# invocation of this suite would otherwise inherit it and its verdicts would be
# a function of another session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_MD="$REPO_ROOT/plugins/soleur/commands/sync.md"
[[ -f "$SYNC_MD" ]] || { echo "FATAL: sync.md not found at $SYNC_MD" >&2; exit 2; }

PASS=0
FAIL=0
pass() { echo "[ok] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

# --- fake customer repo -------------------------------------------------------
# A customer repo that (a) is NOT this monorepo, (b) has a populated scripts/
# dir, and (c) also has a plugins/soleur/scripts/ path — so the fix's own new
# prefix is covered too, not just the old one.
CUST="$(mktemp -d "$TMPDIR/sync-reach.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$CUST"' EXIT

MARKERS="$CUST/.executed"
mkdir -p "$CUST/scripts" "$CUST/plugins/soleur/scripts" "$MARKERS" || {
  echo "FATAL: fixture mkdir failed" >&2; exit 2; }

plant_decoy() {
  # $1 = path relative to the fake customer repo, $2 = marker name
  local rel="$1" name="$2"
  cat > "$CUST/$rel" <<EOF
#!/usr/bin/env bash
# DECOY — stands in for a customer file that happens to share our name.
touch "$MARKERS/$name"
EOF
  chmod +x "$CUST/$rel" || { echo "FATAL: chmod failed for $rel" >&2; exit 2; }
}

plant_decoy "scripts/rule-prune.sh"                    "rule-prune"
plant_decoy "scripts/rule-metrics-aggregate.sh"        "rule-metrics-aggregate"
plant_decoy "scripts/domain-model-drift.sh"            "domain-model-drift"
plant_decoy "plugins/soleur/scripts/write-kb-coverage.ts"        "write-kb-coverage"
plant_decoy "plugins/soleur/scripts/generate-c4-from-components.ts" "generate-c4"

# A stand-in `bun` on PATH, so a `bun <path>` line executes the target the same
# way `bash <path>` would. Mirrors the `gh` shim in test-sync-rule-prune.sh.
SHIM="$CUST/.shim"
mkdir -p "$SHIM" || { echo "FATAL: shim mkdir failed" >&2; exit 2; }
cat > "$SHIM/bun" <<'EOF'
#!/usr/bin/env bash
# Execute the script operand exactly as a real runner would reach it.
exec bash "$@"
EOF
chmod +x "$SHIM/bun" || { echo "FATAL: chmod bun shim failed" >&2; exit 2; }

# --- extract the producer invocations from the REAL sync.md -------------------
# Anchored on the syntactic call shape, not a bare token, so an explanatory
# comment naming a producer cannot satisfy or break the extraction
# (cq-assert-anchor-not-bare-token).
mapfile -t INVOCATIONS < <(
  grep -nE '^[[:space:]]*(bash|bun|node|sh|python3?)[[:space:]]+[^[:space:]]' "$SYNC_MD" \
    | sed 's/^[0-9]*:[[:space:]]*//'
)

if [[ "${#INVOCATIONS[@]}" -lt 1 ]]; then
  echo "FATAL: extracted zero invocations from sync.md — the extractor is broken," >&2
  echo "       which would make every assertion below vacuously green." >&2
  exit 2
fi

# --- T0a: form — NO producer operand may be CWD-relative ----------------------
# This is the real invariant, and it is deliberately stronger than an
# exemption list. An exemption list ("these two literals may stay relative
# because an `if` guards them") is launderable: any invocation can be wrapped in
# an `if` to buy the exemption, and — measured while writing this suite — a gate
# on a SEPARATE LINE does not survive a line-wise reader anyway. Requiring the
# operand itself to be non-relative makes each invocation line safe in
# isolation, which is the property that actually protects the customer.
#
# Accepted: `${CLAUDE_PLUGIN_ROOT}/…` (payload producers), `"$VAR/…` (the
# monorepo-only pair, fail-closed to /… when VAR is unset), or a literal `/…`.
# Rejected: anything else, i.e. anything that resolves against the CWD.
unanchored=0
for inv in "${INVOCATIONS[@]}"; do
  operand="$(awk '{print $2}' <<<"$inv")"
  case "$operand" in
    '${CLAUDE_PLUGIN_ROOT}'/*) continue ;;
    '"$'*/*)                   continue ;;
    /*)                        continue ;;
  esac
  fail "T0a: producer operand is CWD-relative (resolves into the customer's tree): $inv"
  unanchored=$((unanchored + 1))
done
[[ "$unanchored" -eq 0 ]] && pass "T0a: no producer operand is CWD-relative"

# --- T0b: no `:-` / `:?` default anywhere in the command surface --------------
# grep -F: `$`, `{`, `}` are BRE metacharacters and a plain grep returns 0 here,
# a false negative in the direction that hides the bug.
if grep -Fq '${CLAUDE_PLUGIN_ROOT:-' "$SYNC_MD" || grep -Fq '${CLAUDE_PLUGIN_ROOT:?' "$SYNC_MD"; then
  fail "T0b: sync.md contains a \${CLAUDE_PLUGIN_ROOT:-…} or :? default — that is the vector"
else
  pass "T0b: no \${CLAUDE_PLUGIN_ROOT:-…} / :? default in sync.md"
fi

# --- T0c: THE DECISIVE CELL — customer CWD + var UNSET, decoys must not run ---
rm -f "$MARKERS"/* 2>/dev/null
for inv in "${INVOCATIONS[@]}"; do
  # `<n>` is a bash input redirect and would fail before path resolution;
  # substitute every placeholder class first so we test path resolution.
  cmd="${inv//<n>/8}"
  cmd="${cmd//<a>/anchor}"
  cmd="${cmd//<s>/statement}"
  cmd="${cmd%\\}"
  (
    cd "$CUST" || exit 0
    unset CLAUDE_PLUGIN_ROOT
    PATH="$SHIM:$PATH"
    eval "$cmd" >/dev/null 2>&1
  )
done

executed="$(find "$MARKERS" -type f -printf '%f\n' 2>/dev/null | sort | tr '\n' ' ')"
if [[ -n "${executed// /}" ]]; then
  fail "T0c: DECOYS EXECUTED from the customer tree: $executed"
else
  pass "T0c: customer CWD + CLAUDE_PLUGIN_ROOT unset → no decoy executed"
fi

# --- T0d: POSITIVE CONTROL — the harness can actually detect an execution -----
# Without this, T0c is satisfied by "nothing executed", which is also what a
# broken extractor, a bad shim, or an unwritable marker dir produce. This cell
# runs the PRE-FIX literal form and REQUIRES the decoy to fire.
rm -f "$MARKERS"/* 2>/dev/null
(
  cd "$CUST" || exit 0
  unset CLAUDE_PLUGIN_ROOT
  PATH="$SHIM:$PATH"
  # The exact form sync.md carried before #7442.
  eval 'bun plugins/soleur/scripts/write-kb-coverage.ts' >/dev/null 2>&1
  eval 'bash scripts/domain-model-drift.sh drift --repo .' >/dev/null 2>&1
)
if [[ -f "$MARKERS/write-kb-coverage" && -f "$MARKERS/domain-model-drift" ]]; then
  pass "T0d: positive control — pre-fix form DOES execute the customer's files"
else
  fail "T0d: positive control did not fire; T0c's green is UNTRUSTWORTHY (harness defect, not a passing SUT)"
fi

# --- T0e: residency — every anchored operand exists in the payload ------------
# Catches a producer that is perfectly anchored but points at a path no
# marketplace install would carry.
missing=0
for inv in "${INVOCATIONS[@]}"; do
  operand="$(awk '{print $2}' <<<"$inv")"
  [[ "$operand" == '${CLAUDE_PLUGIN_ROOT}'* ]] || continue
  rel="${operand#\$\{CLAUDE_PLUGIN_ROOT\}/}"
  if [[ ! -e "$REPO_ROOT/plugins/soleur/$rel" ]]; then
    fail "T0e: anchored operand does not exist in the payload: plugins/soleur/$rel"
    missing=$((missing + 1))
  fi
done
[[ "$missing" -eq 0 ]] && pass "T0e: every anchored operand resides in the plugin payload"

# --- T0f: the rule-prune halt is executable, not prose ------------------------
HALT='SOLEUR_SYNC_AREA_UNAVAILABLE area=rule-prune reason=monorepo-only-maintenance-area'
halt_count="$(grep -Fc "$HALT" "$SYNC_MD" || true)"
if [[ "$halt_count" -ge 2 ]]; then
  pass "T0f: rule-prune halt literal present at both gated call sites ($halt_count)"
else
  fail "T0f: expected the halt literal at >=2 call sites, found $halt_count"
fi

# --- T0g: rule-prune is de-advertised ----------------------------------------
if grep -nE '^argument-hint:' "$SYNC_MD" | grep -Fq 'rule-prune'; then
  fail "T0g: rule-prune still advertised in argument-hint"
elif grep -nE '^\*\*Valid areas:\*\*' "$SYNC_MD" | grep -Fq 'rule-prune'; then
  fail "T0g: rule-prune still advertised in Valid areas"
else
  pass "T0g: rule-prune de-advertised from argument-hint and Valid areas"
fi

echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
