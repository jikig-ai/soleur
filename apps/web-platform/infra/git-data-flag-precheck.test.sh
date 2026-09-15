#!/usr/bin/env bash
#
# git-data-flag-precheck.sh — Guard 1 of #8189: the flag read fails closed and stays away from
# host bytes.
#
# Property: no run of git-data-cutover.yml reaches the bridge unless the GIT_DATA_STORE_ENABLED
# read succeeded and the value is not exactly `true`, and the `prd` read token
# (DOPPLER_TOKEN_PRD) is bound in no step other than the flag precheck.
#
# The script is driven through a PER-NAME Doppler shim that answers per project/config/secret
# AND per --no-exit-on-missing-secret presence, mirroring the measured CLI v3.75.3 semantics
# recorded in the script's header. The workflow is parsed as YAML (`on:` via the True-key lookup).
#
# Harness conventions (plan › Guard Contract): each matrix row runs as a MUTANT through mutate()
# (copy, sed the copy, assert the edit landed on the expected diff-line count, point the suite's
# override at the copy, require the NAMED case RED). Floors are reported with printf + exit.
#
# Seams of the SUITE: GDC_PRECHECK (the script), GDC_WORKFLOW (git-data-cutover.yml).
#
# Run: bash apps/web-platform/infra/git-data-flag-precheck.test.sh
# Registered as a step in .github/workflows/infra-validation.yml.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
PRECHECK="${GDC_PRECHECK:-$DIR/git-data-flag-precheck.sh}"
WF="${GDC_WORKFLOW:-$ROOT/.github/workflows/git-data-cutover.yml}"
IV="$ROOT/.github/workflows/infra-validation.yml"

passes=0; fails=0; SKIPPED=0; MUTANTS_RUN=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Instrument self-test (ADR-193).
_st="$( (pass x >/dev/null; fail y >/dev/null; printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}") )"
if [ "$_st" != "1 1 1" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() self-test read "%s", expected "1 1 1"\n' "$_st" >&2; exit 1
fi

for f in "$PRECHECK" "$WF" "$IV"; do
  [ -f "$f" ] || { printf 'FAIL SETUP: %s not found\n' "$f" >&2; exit 1; }
done
python3 -c 'import yaml' 2>/dev/null || { printf 'FAIL SETUP: python3 yaml module unavailable\n' >&2; exit 1; }

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert
# suite pins every tracked copy byte-identical). Executed as a statement before writes under a
# caller-supplied root so the P1b relative-operand ratchet can see the operand is absolute.
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

T="$(mktemp -d "${TMPDIR}/gdf-precheck.XXXXXX")" || { printf 'FAIL SETUP: mktemp\n' >&2; exit 1; }
_REACHED_VERDICT=""; _rc=0
trap '_rc=$?; rm -rf "$T"; if [ "$_rc" -eq 0 ] && [ -z "$_REACHED_VERDICT" ]; then printf "FAIL: suite exited 0 before its verdict\n" >&2; exit 1; fi' EXIT
BIN="$T/bin"
mkdir -p "$BIN" "$T/mut" || { printf 'FAIL SETUP: mkdir %s\n' "$BIN" >&2; exit 1; }

printf '\n=== git-data flag precheck (Guard 1, #8189) ===\n\n'

# Per-name Doppler shim. A store is $DOPPLER_STORE/<project>/<config>/<NAME>; a missing config
# directory is "nonexistent or unauthorized config" (exit 1 even with the flag).
cat > "$BIN/doppler" <<'SHIM'
#!/usr/bin/env bash
printf 'doppler %s\n' "$*" >> "$DOPPLER_LOG"
[ "${1:-}" = secrets ] && [ "${2:-}" = get ] || { echo "doppler-shim: unsupported: $*" >&2; exit 64; }
name="${3:-}"; shift 3
plain=0; noexit=0; proj=""; cfg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plain) plain=1; shift ;;
    --no-exit-on-missing-secret) noexit=1; shift ;;
    -p|--project) proj="${2:-}"; shift 2 ;;
    -c|--config) cfg="${2:-}"; shift 2 ;;
    *) echo "doppler-shim: unknown argument $1" >&2; exit 64 ;;
  esac
done
[ -n "${DOPPLER_TOKEN:-}" ] || { echo "Doppler Error: you must provide a token" >&2; exit 1; }
[ "${SHIM_SCOPE_ERROR:-0}" = 1 ] && { echo "Doppler Error: This token does not have access to requested config '$cfg'" >&2; exit 1; }
[ "$plain" = 1 ] || { echo "doppler-shim: --plain required" >&2; exit 64; }
d="$DOPPLER_STORE/$proj/$cfg"
if [ -z "$proj" ] || [ -z "$cfg" ] || [ ! -d "$d" ]; then echo "Doppler Error: Could not find requested config '$cfg'" >&2; exit 1; fi
if [ -f "$d/$name" ]; then cat "$d/$name"; exit 0; fi
# SHIM_IGNORE_FLAG models an argument-blind shim (or a CLI that ignores the flag).
if [ "$noexit" = 1 ] && [ "${SHIM_IGNORE_FLAG:-0}" != 1 ]; then exit 0; fi
echo "Doppler Error: Could not find requested secret: $name" >&2; exit 1
SHIM
chmod +x "$BIN/doppler" || { printf 'FAIL SETUP: chmod shim\n' >&2; exit 1; }

# run_case <name> <value|ABSENT> [VAR=value ...] — the flag's stored value (printf, no newline
# unless given), then the script (CASE_SCRIPT, default the real one). Sets OUT, RC, DLOG.
run_case() {
  local name="$1" value="$2"; shift 2
  local store="$T/store-$name"
  assert_fixture_dir "$store"
  rm -rf "$store"; mkdir -p "$store/soleur/prd" "$store/soleur/prd_terraform" || { printf 'FAIL SETUP: store\n' >&2; exit 1; }
  [ "$value" = ABSENT ] || printf '%s' "$value" > "$store/soleur/prd/GIT_DATA_STORE_ENABLED"
  OUT="$T/$name.out"; DLOG="$T/$name.dlog"; : > "$DLOG"
  timeout -k 3 30 env -i PATH="$BIN:/usr/bin:/bin" HOME="$T" DOPPLER_STORE="$store" DOPPLER_LOG="$DLOG" \
    DOPPLER_TOKEN=fixture-prd-read "$@" bash "${CASE_SCRIPT:-$PRECHECK}" > "$OUT" 2>&1
  RC=$?
}
ARGV='doppler secrets get GIT_DATA_STORE_ENABLED --plain --no-exit-on-missing-secret -p soleur -c prd'

# ── cases (functions, so a mutant re-runs exactly the case its row names) ──────────────
case_absent() {
  run_case absent ABSENT "$@"
  [ "$RC" = 0 ] && [ "$(cat "$OUT")" = "flag=unset" ]
}
case_scope_error() {
  run_case scope false SHIM_SCOPE_ERROR=1
  [ "$RC" = 5 ] && [ "$(cat "$OUT")" = "[git-data-flag-precheck] verdict=flag_read_failed rc=1
::error title=git-data-flag-precheck::verdict=flag_read_failed rc=1" ]
}
case_true() {
  run_case "true$1" "$2"
  [ "$RC" = 5 ] && [ "$(cat "$OUT")" = "[git-data-flag-precheck] verdict=flag_already_true
::error title=git-data-flag-precheck::verdict=flag_already_true" ]
}
case_off() { # <label> <value>
  run_case "off$1" "$2"
  [ "$RC" = 0 ] && [ "$(cat "$OUT")" = "flag=off" ]
}

if case_absent; then pass "P1: an absent flag (exit 0, empty stdout WITH the flag) prints exactly flag=unset, exit 0"
else fail "P1: an absent flag was not flag=unset" "rc=$RC out=[$(tr '\n' '|' < "$OUT")]"; fi
if [ "$(cat "$DLOG")" = "$ARGV" ]; then pass "P1: doppler is called exactly once, as: $ARGV"
else fail "P1: the doppler argv differs" "$(tr '\n' '|' < "$DLOG")"; fi
if ! case_absent SHIM_IGNORE_FLAG=1 && [ "$RC" = 5 ] && grep -qF 'verdict=flag_read_failed' "$OUT"; then
  pass "H1: against a shim that exits non-zero on absent (ignores the flag) the absent case goes RED as flag_read_failed — the shim is flag-sensitive"
else fail "H1: the absent case did not react to a flag-blind shim" "rc=$RC out=[$(tr '\n' '|' < "$OUT")]"; fi
if case_scope_error; then pass "P4/S2: a scope error (non-zero rc) -> verdict=flag_read_failed rc=1, exit 5 — never read as unset"
else fail "P4/S2: a scope error was not flag_read_failed" "rc=$RC out=[$(tr '\n' '|' < "$OUT")]"; fi
run_case notoken false DOPPLER_TOKEN=
if [ "$RC" = 5 ] && grep -qxF '[git-data-flag-precheck] verdict=flag_read_failed rc=1' "$OUT"; then pass "P4b: an empty DOPPLER_TOKEN_PRD (no token) -> flag_read_failed, exit 5"
else fail "P4b: a missing token was not flag_read_failed" "rc=$RC out=[$(tr '\n' '|' < "$OUT")]"; fi
if case_true plain true; then pass "P3/S3: exactly true -> verdict=flag_already_true, exit 5"
else fail "P3/S3: true was not refused" "rc=$RC out=[$(tr '\n' '|' < "$OUT")]"; fi
if case_true nl $'true\n'; then pass "P3b: true with a trailing newline (as --plain may print) is still refused"
else fail "P3b: true + newline was not refused" "rc=$RC out=[$(tr '\n' '|' < "$OUT")]"; fi
if case_off false false; then pass "P2: false -> exactly flag=off, exit 0"
else fail "P2: false was not flag=off" "rc=$RC out=[$(tr '\n' '|' < "$OUT")]"; fi
if case_off upper TRUE; then pass "P5: TRUE is not true (the app compares === \"true\") -> flag=off"
else fail "P5: TRUE was not flag=off" "rc=$RC out=[$(tr '\n' '|' < "$OUT")]"; fi
if case_off space 'true '; then pass "P5b: 'true ' (trailing space) is not true -> flag=off"
else fail "P5b: 'true ' was not flag=off" "rc=$RC out=[$(tr '\n' '|' < "$OUT")]"; fi
if case_off canary 'off-CANARY-5d1e' && ! grep -q 'CANARY' "$OUT"; then pass "P6: the flag value itself is never printed"
else fail "P6: the flag value was printed" "out=[$(tr '\n' '|' < "$OUT")]"; fi
run_case xtrace false
: > "$DLOG"
timeout -k 3 30 env -i PATH="$BIN:/usr/bin:/bin" HOME="$T" DOPPLER_STORE="$T/store-xtrace" DOPPLER_LOG="$DLOG" DOPPLER_TOKEN=fixture-prd-read \
  bash -x "$PRECHECK" > "$OUT" 2>&1
RC=$?
if [ "$RC" = 78 ] && [ ! -s "$DLOG" ]; then pass "P7: under bash -x the precheck exits 78 before calling doppler"
else fail "P7: the xtrace refusal did not fire first" "rc=$RC"; fi

# ── workflow rows ─────────────────────────────────────────────────────────────────────
cat > "$T/wf.py" <<'PY'
import sys, yaml, json
wf_path, iv_path = sys.argv[1:3]
out = []
def check(name, cond, detail=""):
    out.append("%s\t%s\t%s" % ("ok" if cond else "FAIL", name, str(detail)[:240].replace("\t", " ").replace("\n", " ")))
wf = yaml.safe_load(open(wf_path)) or {}
on = wf.get(True) or wf.get("on") or {}
check("G1-on: workflow_dispatch trigger read through the True-key lookup", isinstance(on, dict) and "workflow_dispatch" in on, type(on).__name__)
steps = ((wf.get("jobs") or {}).get("cutover") or {}).get("steps") or []
pre = [i for i, s in enumerate(steps) if s.get("id") == "flag_precheck"]
bridge = [i for i, s in enumerate(steps) if s.get("uses") == "./.github/actions/cf-tunnel-ssh-bridge"]
key = [i for i, s in enumerate(steps) if s.get("id") == "key_fetch"]
run = [i for i, s in enumerate(steps) if isinstance(s.get("run"), str) and "git-data-cutover.sh" in s["run"]]
check("G1-order: exactly one flag precheck step, and it precedes the bridge, the key fetch and the script step",
      len(pre) == 1 and len(bridge) == 1 and len(key) == 1 and len(run) == 1 and pre[0] < bridge[0] and pre[0] < key[0] and pre[0] < run[0],
      (pre, bridge, key, run))
p = steps[pre[0]] if len(pre) == 1 else {}
check("G1-step: the precheck step runs the script, with no if: and no continue-on-error",
      str(p.get("run", "")).strip() == "bash apps/web-platform/infra/git-data-flag-precheck.sh" and "if" not in p and not p.get("continue-on-error"), p)
check("G1-env: the precheck step binds exactly {DOPPLER_TOKEN: secrets.DOPPLER_TOKEN_PRD}",
      p.get("env") == {"DOPPLER_TOKEN": "${{ secrets.DOPPLER_TOKEN_PRD }}"}, p.get("env"))
sites = [("step", s.get("id") or s.get("name")) for s in steps if "DOPPLER_TOKEN_PRD" in json.dumps(s)]
job = (wf.get("jobs") or {}).get("cutover") or {}
sites += [("job", k) for k, v in job.items() if k != "steps" and "DOPPLER_TOKEN_PRD" in json.dumps(v, default=str)]
sites += [("top", k) for k, v in wf.items() if k != "jobs" and "DOPPLER_TOKEN_PRD" in json.dumps(v, default=str)]
sites += [("job", j) for j, b in (wf.get("jobs") or {}).items() if j != "cutover" and "DOPPLER_TOKEN_PRD" in json.dumps(b, default=str)]
check("G1-census: DOPPLER_TOKEN_PRD is named only by the flag precheck step (%d steps scanned)" % len(steps),
      len(steps) >= 1 and sites == [("step", "flag_precheck")], sites)
iv = yaml.safe_load(open(iv_path))
ivsteps = [s for j in (iv.get("jobs") or {}).values() for s in (j.get("steps") or [])]
mine = [s for s in ivsteps if isinstance(s.get("run"), str) and s["run"].strip() == "bash apps/web-platform/infra/git-data-flag-precheck.test.sh"]
check("AC10: infra-validation.yml runs this suite in exactly one step with no if:/continue-on-error",
      len(mine) == 1 and "if" not in mine[0] and not mine[0].get("continue-on-error"), len(mine))
print("\n".join(out))
PY
# wf_row <tsv> <name-prefix> — 1 only when the named row is PRESENT and not ok. An ABSENT row (the
# YAML leg crashed on a mutant) returns 0, so a mutant can never read as RED for the wrong reason.
# shellcheck disable=SC2317  # invoked indirectly through mutant_red
wf_row() { awk -F'\t' -v p="$2" 'index($2, p) == 1 { found = 1; if ($1 != "ok") bad = 1 } END { exit (found && bad) ? 1 : 0 }' "$1"; }
python3 "$T/wf.py" "$WF" "$IV" > "$T/wf.tsv" 2> "$T/wf.err"
_wf_n=0
while IFS=$'\t' read -r v name detail; do
  [ -n "$v" ] || continue
  _wf_n=$((_wf_n + 1))
  if [ "$v" = ok ]; then pass "$name"; else fail "$name" "$detail"; fi
done < "$T/wf.tsv"
[ "$_wf_n" -ge 6 ] || fail "G1: only $_wf_n workflow verdicts were produced (expected 6) — the YAML leg crashed" "$(head -c 300 "$T/wf.err")"

# ── mutation matrix (Guard 1) ─────────────────────────────────────────────────────────
echo; echo "--- mutation matrix (each row must turn its named case RED)"
MUTANT=""
mutate() { # <name> <file> <expected-diff-lines> <sed -E program | python:<program-file>>
  local name="$1" src="$2" want="$3" expr="$4" got
  MUTANT="$T/mut/$name.$(basename "$src")"
  cp "$src" "$MUTANT" || { printf 'FAIL SETUP: mutation copy %s\n' "$name" >&2; exit 1; }
  if [ "${expr#python:}" != "$expr" ]; then
    python3 "${expr#python:}" "$MUTANT" 2>"$T/mut/$name.err" || { fail "M-$name: mutation program failed" "$(head -1 "$T/mut/$name.err")"; return 1; }
  elif ! sed -E -i "$expr" "$MUTANT" 2>"$T/mut/$name.err"; then
    fail "M-$name: mutation sed failed" "$(head -1 "$T/mut/$name.err")"; return 1
  fi
  got="$(diff "$src" "$MUTANT" | grep -cE '^[<>]' || true)"
  if [ "$got" != "$want" ]; then
    fail "M-$name: mutation landed on $got diff line(s), expected $want" "[$expr]"; return 1
  fi
  if [ "${src%.sh}" != "$src" ] && ! bash -n "$MUTANT" 2>/dev/null; then
    fail "M-$name: the mutant does not parse (bash -n)"; return 1
  fi
  MUTANTS_RUN=$((MUTANTS_RUN + 1))
  pass "M-$name: mutation landed on exactly $want diff line(s) of a pristine copy"
}
mutant_red() {
  local name="$1"; shift
  if "$@"; then fail "M-$name: the named case stayed GREEN against the mutant"
  else pass "M-$name: the named case goes RED against the mutant"; fi
}

# Row 1 — restore `|| echo ""` semantics: a non-zero rc reads as unset.
# shellcheck disable=SC2016  # sed programs are data
if mutate read-error-as-unset "$PRECHECK" 2 's#\|\| rc=\$\?$#|| flag=""#'; then
  CASE_SCRIPT="$MUTANT" mutant_red read-error-as-unset case_scope_error
fi
# Row 2 — REORDER: move the flag precheck step after the bridge step.
cat > "$T/mut/reorder.py" <<'PY'
import sys
p = sys.argv[1]; lines = open(p).read().split("\n")
def block(start_pred):
    s = next(i for i, l in enumerate(lines) if start_pred(l))
    e = next(i for i in range(s + 1, len(lines)) if lines[i].startswith("      - ") or (lines[i].startswith("      # ") and i + 1 < len(lines) and lines[i + 1].startswith("      ")) and not lines[i].startswith("        "))
    return s, e
s, e = block(lambda l: l.startswith("      - name: Flag precheck"))
chunk = lines[s:e]; del lines[s:e]
b = next(i for i, l in enumerate(lines) if l.strip() == "uses: ./.github/actions/cf-tunnel-ssh-bridge")
be = next(i for i in range(b + 1, len(lines)) if lines[i].startswith("      - ") or lines[i].startswith("      # "))
lines[be:be] = chunk
open(p, "w").write("\n".join(lines))
PY
if mutate precheck-after-bridge "$WF" 12 "python:$T/mut/reorder.py"; then
  python3 "$T/wf.py" "$MUTANT" "$IV" > "$T/mut/wf-order.tsv" 2>&1
  mutant_red precheck-after-bridge wf_row "$T/mut/wf-order.tsv" "G1-order:"
fi
# Row 3 — bind DOPPLER_TOKEN_PRD in the script step's env as well.
# shellcheck disable=SC2016
if mutate prd-in-script-step "$WF" 1 's#^          GIT_DATA_SSH: ssh -F .*$#&\n          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_PRD }}#'; then
  python3 "$T/wf.py" "$MUTANT" "$IV" > "$T/mut/wf-census.tsv" 2>&1
  mutant_red prd-in-script-step wf_row "$T/mut/wf-census.tsv" "G1-census:"
fi
# Row 4 — compare `true` case-insensitively.
# shellcheck disable=SC2016
if mutate true-case-insensitive "$PRECHECK" 2 's#^if \[ "\$flag" = true \]; then$#if [ "${flag,,}" = true ]; then#'; then
  CASE_SCRIPT="$MUTANT" mutant_red true-case-insensitive case_off upper TRUE
fi

# ── FLOOR + LEDGER ────────────────────────────────────────────────────────────────────
MUTANT_FLOOR=4   # Guard 1 matrix rows
if [ "$MUTANTS_RUN" -lt "$MUTANT_FLOOR" ]; then
  printf 'FAIL MUTANT FLOOR: only %s mutants executed, floor is %s\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" >&2; exit 1
fi
# Assertion FLOOR: script cases 12 + workflow rows 6 + mutants 4 x 2 = 26 (exact).
FLOOR=26
_ran=$((passes + fails + SKIPPED))
if [ "$_ran" -lt "$FLOOR" ]; then
  printf 'FAIL ANTI-VACUITY: only %s assertions ran, floor is %s\n' "$_ran" "$FLOOR" >&2; exit 1
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then
  printf 'FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}" >&2; exit 1
fi
printf '\n=== git-data-flag-precheck: %d passed, %d failed, %d skipped ===\n\n' "$passes" "$fails" "$SKIPPED"
_REACHED_VERDICT=1
exit $(( ${#FAILURES[@]} > 0 ))
