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
#
# Command position, not line start. A runner can sit in second position —
# `[ -f x ] && bun x`, `cd d && bash y` — and a line-start-only extractor returns
# ZERO for that shape. It does not FAIL anything; it drops the invocation out of
# INVOCATIONS, which silently vacuates T0a, T0c, T0e AND the producer inventory
# T0j/T0k/T0l derive from. Measured (#7474): with this normalization removed, the
# `&&`-form mutation of a guarded site reports "target not in inventory" instead
# of the defect it actually introduces. Stripping one leading `&&` / `||` / `;`
# also leaves an eval-able command for T0c. Mirrors RUNNER_RE's command-position
# reasoning in apps/web-platform/test/plugin-root-anchoring.test.ts.
to_command_position() { sed -E 's/^[[:space:]]*((\&\&|\|\||;)[[:space:]]*)?//'; }

extract_from() {
  local md="$1"
  {
    to_command_position < "$md" \
      | grep -E '^(bash|bun|node|sh|python3?)[[:space:]]+[^[:space:]]'
    grep -oE '`[^`]+`' "$md" | tr -d '`' | to_command_position \
      | grep -E '^(bash|bun|node|sh|python3?)[[:space:]]+[^[:space:]]'
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

Command-position pre-fix variant — the runner is NOT at line start:

```bash
[ -f plugins/soleur/scripts/generate-c4-from-components.ts ] \
  && bun plugins/soleur/scripts/generate-c4-from-components.ts
```
EOF
mapfile -t FIXTURE_INVOCATIONS < <(extract_from "$FIXTURE")
if [[ "${#FIXTURE_INVOCATIONS[@]}" -ne 3 ]]; then
  fail "T0d: control extracted ${#FIXTURE_INVOCATIONS[@]} of 3 invocations — the EXTRACTOR is broken, so T0c's green is untrustworthy"
else
  for inv in "${FIXTURE_INVOCATIONS[@]}"; do run_invocation "$inv"; done
  # `generate-c4` is the COMMAND-POSITION control. Without it, narrowing
  # extract_from back to `^\s*(bash|bun)` leaves this case green while every
  # command-position invocation silently drops out of T0a / T0c / T0e and out of
  # the producer inventory T0j/T0k/T0l derive from.
  if [[ -f "$MARKERS/write-kb-coverage" && -f "$MARKERS/domain-model-drift" && -f "$MARKERS/generate-c4" ]]; then
    pass "T0d: positive control — pre-fix form (line-start AND command-position), via the same extractor, DOES execute the customer's files"
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
# ADR-179 decision 2. Without this, the block carrying the whole safety argument
# is deletable with the suite green.
if grep -Fq '"${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"' "$SYNC_MD"; then
  pass "T0h: sync.md carries the fail-closed plugin-identity preflight"
else
  fail "T0h: sync.md has no plugin-identity preflight (ADR-179 decision 2)"
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

# --- T0j / T0k / T0l: the per-site producer guard (#7474) ----------------------
# The identity preflight (T0h/T0i) answers whether the root is genuinely ours. It
# cannot answer whether that root CARRIES the producer this run is about to
# invoke: an identity-valid root missing a producer passes the preflight, then
# dies on a bare interpreter error with no marker and no attribution.
#
# These three cases are a set, and the set is the point — each alone is
# satisfiable by a wrong implementation:
#   T0j — producer ABSENT          → marker emitted, producer NOT invoked.
#         (alone: satisfied by a guard that emits unconditionally)
#   T0k — producer PRESENT         → NO marker, producer invoked.
#         (alone: satisfied by deleting the guard entirely)
#   T0l — producer PRESENT, FAILS  → NO marker; it ran, so it is not missing.
#         (alone: satisfied by never emitting)
GUARDDIR="$CUST/guards"
mkdir -p "$GUARDDIR" || { echo "FATAL: guard dir mkdir failed" >&2; exit 2; }
# Deliberately form-AGNOSTIC: it accepts both the shipped `if …; then … else …; fi`
# block and the `[ -f … ] && … || echo …` one-liner. If it only recognized the
# shipped syntax, T0l could never fail — swapping in the `&&`/`||` form would
# make the block invisible and T0j would fail first, for the wrong reason. The
# property under test is the SEMANTICS (never report a present producer as
# missing), not which syntax spells it.
awk -v out="$GUARDDIR" '
  /^[[:space:]]*(if )?\[ -f "\$\{CLAUDE_PLUGIN_ROOT\}\// {
    n++; inblk = 1; ifform = ($0 ~ /^[[:space:]]*if /)
  }
  inblk {
    print > (out "/g" n ".sh")
    if (ifform) { if ($0 ~ /^[[:space:]]*fi[[:space:]]*$/) inblk = 0 }
    else        { if ($0 !~ /\\[[:space:]]*$/)             inblk = 0 }
  }
' "$SYNC_MD"
mapfile -t GUARD_BLOCKS < <(find "$GUARDDIR" -name 'g*.sh' -type f 2>/dev/null | sort)

# Producer inventory, derived from sync.md — never hardcoded here, so a fourth
# producer is covered without editing this suite.
mapfile -t PRODUCER_RELS < <(
  for inv in "${INVOCATIONS[@]}"; do
    operand="$(awk '{print $2}' <<<"$inv")"
    bare="${operand%\"}"; bare="${bare#\"}"
    case "$bare" in
      '${CLAUDE_PLUGIN_ROOT}'/*) echo "${bare#\$\{CLAUDE_PLUGIN_ROOT\}/}" ;;
    esac
  done | sort -u
)

# An identity-VALID root (manifest + name + scripts/) carrying a synthesized
# marker-toucher for every producer except `omit`. Synthesized, never the real
# payload: running the real producers would mutate this repo's knowledge-base.
mk_synth_root() {
  local root="$1" omit="${2:-}" rel
  mkdir -p "$root/.claude-plugin" "$root/scripts" || return 1
  printf '{ "name": "soleur" }\n' > "$root/.claude-plugin/plugin.json" || return 1
  for rel in "${PRODUCER_RELS[@]}"; do
    [[ "$rel" == "$omit" ]] && continue
    mkdir -p "$root/$(dirname "$rel")" || return 1
    cat > "$root/$rel" <<EOF
#!/usr/bin/env bash
touch "$MARKERS/ran-$(basename "$rel")"
EOF
    chmod +x "$root/$rel" || return 1
  done
}

run_guards() {
  local root="$1" g
  (
    cd "$CUST" || exit 0
    set +u
    export PATH="$SHIM:$PATH"
    export CLAUDE_PLUGIN_ROOT="$root"
    for g in "${GUARD_BLOCKS[@]}"; do bash "$g"; done
  ) 2>/dev/null
}

OMIT="scripts/generate-c4-from-components.ts"
OMIT_RAN="ran-$(basename "$OMIT")"

if [[ "${#GUARD_BLOCKS[@]}" -lt 1 ]]; then
  fail "T0j: extracted ZERO per-site producer guards from sync.md — the guard is absent or its shape changed, so T0k/T0l below would be vacuous"
  fail "T0k: skipped — no guard blocks extracted"
  fail "T0l: skipped — no guard blocks extracted"
elif ! printf '%s\n' "${PRODUCER_RELS[@]}" | grep -Fqx "$OMIT"; then
  fail "T0j: fixture target $OMIT is not in the derived producer inventory — the case would be vacuous"
  fail "T0k: skipped — fixture target not in inventory"
  fail "T0l: skipped — fixture target not in inventory"
else
  # T0j — absent.
  rm -f "$MARKERS"/* 2>/dev/null
  ROOT_MISSING="$CUST/root-missing"
  mk_synth_root "$ROOT_MISSING" "$OMIT" || { echo "FATAL: synth root failed" >&2; exit 2; }
  out_missing="$(run_guards "$ROOT_MISSING")"
  ran_missing="$(marker_names)"
  if ! grep -Fq "SOLEUR_SYNC_PRODUCER_MISSING producer=$OMIT" <<<"$out_missing"; then
    fail "T0j: producer absent from an identity-valid root emitted NO marker — the bare-error case (#7474) is open"
  elif ! grep -Fq "reason=absent-from-verified-root" <<<"$out_missing"; then
    fail "T0j: marker emitted without reason=absent-from-verified-root"
  elif [[ "$ran_missing" == *"$OMIT_RAN"* ]]; then
    fail "T0j: the ABSENT producer was invoked anyway — the guard is advisory, not enforcing"
  elif [[ "$ran_missing" != *"ran-write-kb-coverage.ts"* ]]; then
    fail "T0j: guard over-suppressed — a PRESENT sibling producer did not run (ran: $ran_missing)"
  else
    pass "T0j: producer absent → named marker, producer not invoked, present siblings still run"
  fi

  # T0k — present. Guards against the false-alarm-on-a-healthy-install regression.
  rm -f "$MARKERS"/* 2>/dev/null
  ROOT_FULL="$CUST/root-full"
  mk_synth_root "$ROOT_FULL" || { echo "FATAL: synth root failed" >&2; exit 2; }
  out_full="$(run_guards "$ROOT_FULL")"
  ran_full="$(marker_names)"
  if grep -Fq "SOLEUR_SYNC_PRODUCER_MISSING" <<<"$out_full"; then
    fail "T0k: a COMPLETE root emitted a producer-missing marker — false alarm on a healthy install"
  elif [[ "$ran_full" != *"$OMIT_RAN"* ]]; then
    fail "T0k: the guard suppressed a PRESENT producer (ran: $ran_full)"
  else
    pass "T0k: complete root → zero markers, every producer invoked"
  fi

  # T0l — present but exits non-zero. This is the case that separates
  # `if [ -f … ]; then …; else …; fi` from `[ -f … ] && … || echo …`: under the
  # latter, a non-zero exit from a producer that IS present falls through to the
  # `||` and reports it MISSING. That is a confidently wrong remedy, which the
  # plan ranks as strictly worse than today's unattributed error.
  rm -f "$MARKERS"/* 2>/dev/null
  ROOT_FAIL="$CUST/root-failing"
  mk_synth_root "$ROOT_FAIL" || { echo "FATAL: synth root failed" >&2; exit 2; }
  printf '#!/usr/bin/env bash\ntouch "%s/%s"\nexit 1\n' "$MARKERS" "$OMIT_RAN" > "$ROOT_FAIL/$OMIT"
  chmod +x "$ROOT_FAIL/$OMIT" || { echo "FATAL: chmod failing-producer failed" >&2; exit 2; }
  out_fail="$(run_guards "$ROOT_FAIL")"
  ran_fail="$(marker_names)"
  if [[ "$ran_fail" != *"$OMIT_RAN"* ]]; then
    fail "T0l: fixture defect — the failing producer never ran, so the assertion below is vacuous"
  elif grep -Fq "SOLEUR_SYNC_PRODUCER_MISSING producer=$OMIT" <<<"$out_fail"; then
    fail "T0l: a PRESENT producer that exited non-zero was reported MISSING — the remedy names a cause that is not the operator's"
  else
    pass "T0l: present-but-failing producer → not reported as missing"
  fi
fi

# --- T0m: the operator-facing message carries all four required properties -----
# The marker is machine-readable; this message is the half a founder actually
# reads, and without it the guard converts a bare error into a bare marker. It is
# matched against a WHITESPACE-NORMALIZED sync.md (blockquote markers stripped,
# newlines collapsed) because a prose anchor that happens to straddle a line wrap
# is a property of the reflow, not of the message — pinning the raw bytes would
# make every reflow a false failure and tempt the fix of deleting the anchor.
NORM_SYNC="$(sed 's/^[[:space:]]*>[[:space:]]*/ /' "$SYNC_MD" | tr '\n' ' ' | tr -s ' ')"
missing_props=""
# (1) attribution: the operator's project is not at fault.
grep -Fq "not with your project" <<<"$NORM_SYNC" || missing_props="$missing_props attribution"
# (2) a concrete remedy, and (3) WHY the obvious action is insufficient.
grep -Fq "reinstall the Soleur plugin" <<<"$NORM_SYNC" || missing_props="$missing_props remedy"
grep -Fq "does not update an installed plugin" <<<"$NORM_SYNC" || missing_props="$missing_props remedy-rationale"
# (4) an explicit fallback for when the remedy does not clear it.
grep -Fq "this is a bug in Soleur" <<<"$NORM_SYNC" || missing_props="$missing_props fallback"
# (5) what still succeeded — a partial run must not read as a failed one.
grep -Fq "completed normally" <<<"$NORM_SYNC" || missing_props="$missing_props what-still-worked"
# The headless arm must NOT tell a web-platform user to reinstall a plugin they
# never installed.
grep -Fq "Soleur-side defect" <<<"$NORM_SYNC" || missing_props="$missing_props headless-variant"
if [[ -n "$missing_props" ]]; then
  fail "T0m: producer-missing operator message is missing required properties:$missing_props"
else
  pass "T0m: operator message carries attribution, remedy, remedy-rationale, fallback, what-still-worked, and a headless variant"
fi

# --- anti-vacuity floor -------------------------------------------------------
# Neutering pass()/fail() or deleting a case otherwise summarizes green and
# exits 0. Absolute and hand-ratcheted; a floor derived from the cases would
# simply descend with a deletion.
EXPECTED_CASES=13
if [[ "$CASES" -ne "$EXPECTED_CASES" ]]; then
  echo "[FAIL] anti-vacuity: ran $CASES of $EXPECTED_CASES cases — a case was deleted or its counter neutered" >&2
  FAIL=$((FAIL + 1))
fi

echo "=== $PASS passed, $FAIL failed ($CASES/$EXPECTED_CASES cases) ==="
[[ "$FAIL" -eq 0 && "$CASES" -eq "$EXPECTED_CASES" ]]
