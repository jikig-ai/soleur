#!/usr/bin/env bash
# render-c4-model.test.sh — the plugin-owned C4 renderer works in a CUSTOMER-shaped repo.
#
# The renderer moved out of this repo's scripts/ into the plugin so the merge resolver can
# regenerate model.likec4.json in a self-hosted install (ADR-235 amendment). The freshness
# suite covers THIS repo's diagrams; nothing covered the shape soleur:sync actually writes
# elsewhere, which is spec.c4 + views.c4 + generated-components.c4 and NO model.c4. The old
# all-three source guard refused exactly that shape, so these rows render it for real.
#
# Runs the real pinned likec4 through npx, like c4-model-freshness.test.sh. Without npx the
# suite SKIPS and says so on stdout; it never reports a pass it did not measure.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RENDERER="$SCRIPT_DIR/../scripts/render-c4-model.sh"
CANON_CLI="$SCRIPT_DIR/../lib/c4-canonical-cli.mjs"

passes=0; fails=0; CASES_RUN=0; FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; FAILED=(); CASES_RUN=0

[[ -f "$RENDERER" ]] || { echo "[FATAL] renderer not found at $RENDERER" >&2; exit 1; }

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

SANDBOX="$(mktemp -d)"; assert_fixture_dir "$SANDBOX"
trap 'rm -rf "$SANDBOX"' EXIT
DIAG="knowledge-base/engineering/architecture/diagrams"

echo "=== render-c4-model (plugin-owned renderer) ==="

# ── The discoverability probe the plan's Observability block names. No likec4 needed. ──────
CASES_RUN=$((CASES_RUN + 1))
if bash "$RENDERER" --help 2>/dev/null | grep -q -- '--root'; then
  pass "--help documents --root (the flag the resolver passes)"
else
  fail "--help does not document --root"
fi
CASES_RUN=$((CASES_RUN + 1))
_rc=0; bash "$RENDERER" --root "$SANDBOX/no-such-dir" >/dev/null 2>&1 || _rc=$?
[[ "$_rc" -eq 2 ]] && pass "a --root that is not a directory is a usage error (rc 2)" \
  || fail "a missing --root returned rc=$_rc, expected 2"

# synced_repo <name> — the shape soleur:sync writes into a customer repo: no model.c4.
synced_repo() {
  local r="$SANDBOX/$1"; assert_fixture_dir "$r"
  mkdir -p "$r/$DIAG"
  printf 'specification {\n  element system\n  element component\n}\n' > "$r/$DIAG/spec.c4"
  printf 'model {\n  app = system %s {\n    web = component %s\n  }\n}\n' "'App'" "'Web'" \
    > "$r/$DIAG/generated-components.c4"
  printf 'views {\n  view index {\n    include *\n  }\n}\n' > "$r/$DIAG/views.c4"
  git -C "$r" init -q -b main
  git -C "$r" config user.email t@t; git -C "$r" config user.name t
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q -m base
  printf '%s' "$r"
}

# No .c4 at all is refused before likec4 is ever fetched.
_empty="$SANDBOX/empty"; assert_fixture_dir "$_empty"; mkdir -p "$_empty/$DIAG"
CASES_RUN=$((CASES_RUN + 1))
_rc=0; _out="$(bash "$RENDERER" --root "$_empty" 2>&1)" || _rc=$?
if [[ "$_rc" -ne 0 && "$_out" == *"no .c4 source"* ]]; then
  pass "a diagrams directory with no .c4 source is refused by name"
else
  fail "no-source dir: rc=$_rc out=$_out"
fi

# ── A stubbed npx that speaks likec4's CI reporter (deterministic; no network) ────────────
# It prints ONLY the timestamped, ANSI-coloured `Invalid` line — no `Line N:` row to lean on —
# and still writes a plausible model, exactly what likec4 does on a syntax error. Both
# defences (the child env and the log normalisation) are bypassed by a stub that ignores the
# environment, so this pins the normalisation + prefix-tolerant pattern on their own.
_stub="$SANDBOX/stubbin"; assert_fixture_dir "$_stub"; mkdir -p "$_stub"
{
  printf '#!/usr/bin/env bash\n'
  printf 'out=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-o" ]] && out="$2"; shift; done\n'
  printf 'printf %s "$(printf "\\033")" "$(printf "\\033")" "$(printf "\\033")" "$(printf "\\033")"\n' \
    "'%s[2m15:32:23.971%s[0m %s[31mERROR%s[0m likec4 Invalid /r/m.c4\\n'"
  printf 'printf %s > "$out"\n' "'{\"elements\":{\"a\":{}},\"relations\":{},\"views\":{}}'"
} > "$_stub/npx"
chmod +x "$_stub/npx"
_sr="$SANDBOX/stubrepo"; assert_fixture_dir "$_sr"; mkdir -p "$_sr/$DIAG"
printf 'model {}\n' > "$_sr/$DIAG/m.c4"
_rc=0; _out="$(PATH="$_stub:$PATH" CI=true bash "$RENDERER" --root "$_sr" 2>&1)" || _rc=$?
CASES_RUN=$((CASES_RUN + 1))
if [[ "$_rc" -ne 0 && "$_out" == *"source validation error"* && ! -e "$_sr/$DIAG/model.likec4.json" ]]; then
  pass "a CI-formatted, ANSI-wrapped \`Invalid\` line alone is refused (stubbed reporter)"
else
  fail "CI-formatted diagnostic slipped through: rc=$_rc — $_out"
fi

# ── Every extension likec4 compiles counts as a source (.c4, .likec4, .like-c4) ─────────────
for _ext in likec4 like-c4; do
  _xr="$SANDBOX/ext-$_ext"; assert_fixture_dir "$_xr"; mkdir -p "$_xr/$DIAG"
  printf 'model {}\n' > "$_xr/$DIAG/m.$_ext"
  _rc=0; _out="$(PATH="$_stub:$PATH" bash "$RENDERER" --root "$_xr" 2>&1)" || _rc=$?
  CASES_RUN=$((CASES_RUN + 1))
  [[ "$_out" != *"no .c4 source"* ]] && pass "a lone .$_ext source passes the source guard" \
    || fail "a lone .$_ext source was refused as 'no .c4 source'"
done

if ! command -v npx >/dev/null 2>&1; then
  echo "SKIP: npx not on PATH — the likec4 rows below were NOT run (cases_run=$CASES_RUN)"
  exit 0
fi

# ── AC5: spec + views + generated-components, and NO model.c4 ──────────────────────────────
echo ""
echo "--- AC5: a soleur:sync-shaped repo (no model.c4) renders ---"
r="$(synced_repo synced)"
_rc=0; _out="$(timeout -k 10 600 bash "$RENDERER" --root "$r" 2>&1)" || _rc=$?
CASES_RUN=$((CASES_RUN + 1))
[[ "$_rc" -eq 0 ]] && pass "AC5: renders with spec.c4 + views.c4 and no model.c4" \
  || fail "AC5: rc=$_rc — $_out"
CASES_RUN=$((CASES_RUN + 1))
if [[ -f "$r/$DIAG/model.likec4.json" ]] && jq -e '(.elements | length) > 0' "$r/$DIAG/model.likec4.json" >/dev/null 2>&1; then
  pass "AC5: the artifact exists and has elements"
else
  fail "AC5: no non-empty artifact at $DIAG/model.likec4.json"
fi
CASES_RUN=$((CASES_RUN + 1))
[[ "$(node "$CANON_CLI" --check "$r/$DIAG/model.likec4.json" 2>&1)" == "canonical" ]] \
  && pass "AC5: the artifact is in the canonical line-per-value format" \
  || fail "AC5: the artifact is not canonical"
# P3 at the renderer: the resolver commits whatever this changes, so it must change ONE path.
CASES_RUN=$((CASES_RUN + 1))
_st="$(git -C "$r" status --porcelain --ignored)"
if [[ "$_st" == "?? $DIAG/model.likec4.json" ]]; then
  pass "the render wrote exactly one path (no cache, no temp left in the repo)"
else
  fail "the render left more than the artifact behind: $(tr '\n' ' ' <<<"$_st")"
fi

# ── A syntax error: likec4 exits 0, so the diagnostic gate is what refuses ─────────────────
# Run twice: with CI unset and with CI=true. GitHub Actions sets CI, and under it likec4
# switches to a timestamped, ANSI-coloured reporter (`15:32:23 ERROR likec4 Invalid …`,
# `    ESC[2mLine 4:`) that no anchored diagnostic pattern matches — so without normalising
# the child's environment, a truncated model publishes at rc 0 exactly where CI runs this.
for _ci in "" "true"; do
  _lbl="CI=${_ci:-unset}"
  r="$(synced_repo "broken${_ci}")"
  printf 'model {\n  broken = component %s {\n' "'Broken'" >> "$r/$DIAG/generated-components.c4"
  _rc=0
  if [[ -n "$_ci" ]]; then
    _out="$(CI="$_ci" timeout -k 10 600 bash "$RENDERER" --root "$r" 2>&1)" || _rc=$?
  else
    _out="$(env -u CI timeout -k 10 600 bash "$RENDERER" --root "$r" 2>&1)" || _rc=$?
  fi
  CASES_RUN=$((CASES_RUN + 1))
  [[ "$_rc" -ne 0 ]] && pass "$_lbl: a syntax error exits non-zero" \
    || fail "$_lbl: a syntax error exited 0 — a truncated model would be published"
  CASES_RUN=$((CASES_RUN + 1))
  if grep -qE '^Invalid |Could not resolve|^[[:space:]]+Line [0-9]+:' <<<"$_out"; then
    pass "$_lbl: the refusal carries likec4's diagnostic text, not only an exit code"
  else
    fail "$_lbl: the refusal did not carry a diagnostic: $_out"
  fi
  CASES_RUN=$((CASES_RUN + 1))
  [[ ! -e "$r/$DIAG/model.likec4.json" ]] && pass "$_lbl: nothing was published on a refused render" \
    || fail "$_lbl: a refused render still published an artifact"
done

# ── An EMPTY model is refused by the element-count gate (the diagnostic gate cannot see it) ──
r="$(synced_repo emptymodel)"
printf 'model {\n}\n' > "$r/$DIAG/generated-components.c4"
_rc=0; _out="$(env -u CI timeout -k 10 600 bash "$RENDERER" --root "$r" 2>&1)" || _rc=$?
CASES_RUN=$((CASES_RUN + 1))
if [[ "$_rc" -ne 0 && "$_out" == *"empty/degenerate"* && ! -e "$r/$DIAG/model.likec4.json" ]]; then
  pass "an empty model is refused by the element-count gate and nothing is published"
else
  fail "empty model: rc=$_rc published=$([[ -e "$r/$DIAG/model.likec4.json" ]] && echo yes || echo no) — $_out"
fi

echo ""
echo "cases_run=$CASES_RUN passes=$passes fails=$fails ledger=${#FAILED[@]}"

_min_cases=17
if [[ "$CASES_RUN" -lt "$_min_cases" ]]; then
  printf '[FATAL] assertion floor: only %s case(s) ran, floor is %s\n' "$CASES_RUN" "$_min_cases" >&2; exit 1
fi
if [[ $((passes + fails)) -ne "$CASES_RUN" ]]; then
  printf '[FATAL] %s verdicts for %s cases — a case decided nothing\n' "$((passes + fails))" "$CASES_RUN" >&2; exit 1
fi
if [[ "${#FAILED[@]}" -ne "$fails" ]]; then
  printf '[FATAL] ledger/counter disagree: %s vs %s\n' "${#FAILED[@]}" "$fails" >&2; exit 1
fi
if [[ "${#FAILED[@]}" -ne 0 ]]; then
  printf '[FATAL] %s failing assertion(s):\n' "${#FAILED[@]}" >&2
  printf '  - %s\n' "${FAILED[@]}" >&2; exit 1
fi
echo "render-c4-model: all $passes assertions passed"
