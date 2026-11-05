#!/usr/bin/env bash
#
# Host-replace inherited-done preflight (#7228) fails closed, and the CI flip credential cannot write
# (Ref #9927 item 8; plan: knowledge-base/project/plans/2026-11-05-chore-retire-inngest-arm-write-cutover-ops-plan.md).
#
# Guard 1 - the single `Preflight` step of job `inngest_host_replace` in apply-web-platform-infra.yml.
#   Its `run:` body is extracted BY NAME and EXECUTED under a stubbed `doppler` (and a toggled `jq`), so a
#   grep cannot stand in for a decision. An empty token, an erroring or empty or non-object names list, a
#   missing doppler/jq, and a failing `get` of a present key all exit 1; xtrace exits 78. A successful read
#   of any flag value stays exit 0 with its warning, by design.
# Guard 3 - inngest-flip-read-token.tf: `access = "read"`, by-reference project/config, published under the
#   secret name the preflight reads with plaintext_value equal to its OWN token's key, and outside the
#   token-drift map and the config inventory. Pins run on comment-stripped, whitespace-collapsed text.
#
# Harness conventions: code-edit rows run as MUTANTS (copy, sed the copy, assert the edit LANDED on the
# expected diff-line count, require the NAMED violation); the unmutated control runs first and must be clean;
# floors are reported with printf + exit, never through pass()/fail().
#
# Run: bash apps/web-platform/infra/inngest-host-replace-preflight.test.sh
# Presence under apps/web-platform/infra/ IS registration - derived and run by run-registered-suites.sh (#8736).

# The sed mutation expressions are deliberately single-quoted literals.
# shellcheck disable=SC2016
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
WF_REAL="${PF_WORKFLOW:-$ROOT/.github/workflows/apply-web-platform-infra.yml}"
TF_REAL="${PF_TF:-$DIR/inngest-flip-read-token.tf}"
DRIFT_REAL="$DIR/token-drift-read-tokens.tf"
INVENTORY_REAL="$DIR/doppler-config-inventory.txt"
STEP_NAME='Preflight - inherited-done check, fails closed (#7228, #9927)'
JOB='inngest_host_replace'
SECRET_NAME='DOPPLER_TOKEN_INNGEST_FLIP_READ'
OLD_SECRET='DOPPLER_TOKEN_INNGEST_ARM'

passes=0; fails=0; MUTANTS_RUN=0; ROWS_RUN=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Instrument self-test (ADR-193): drive both helpers once in a subshell; both counters must move.
_st="$( (pass x >/dev/null; fail y >/dev/null; printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}") )"
if [ "$_st" != "1 1 1" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() self-test read "%s", expected "1 1 1"\n' "$_st" >&2; exit 1
fi

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (fixture-dir-operand-assert pins every
# tracked copy byte-identical), executed as a statement before writes under a caller-supplied root.
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

for f in "$WF_REAL" "$DRIFT_REAL" "$INVENTORY_REAL"; do
  [ -f "$f" ] || { printf 'FAIL SETUP: %s not found\n' "$f" >&2; exit 1; }
done
python3 -c 'import yaml' 2>/dev/null || { printf 'FAIL SETUP: python3 yaml module unavailable\n' >&2; exit 1; }
REAL_JQ="$(command -v jq)" || { printf 'FAIL SETUP: jq not found\n' >&2; exit 1; }
REAL_TR="$(command -v tr)" || { printf 'FAIL SETUP: tr not found\n' >&2; exit 1; }
REAL_BASH="$(command -v bash)" || { printf 'FAIL SETUP: bash not found\n' >&2; exit 1; }

SANDBOX="$(mktemp -d)"; assert_fixture_dir "$SANDBOX"
trap 'rm -rf "$SANDBOX"' EXIT

# --- the doppler stub: scripted by STUB_NAMES / STUB_GET / STUB_VALUE; refuses (exit 64) any argv it was
# not told to expect, so querying the wrong project/config or the wrong verb cannot read a fixture. ---
STUBDIR="$SANDBOX/stub"; mkdir -p "$STUBDIR"
# The shebang is the ABSOLUTE bash: the step's PATH holds only the stub, tr and jq, so `env bash` would not resolve.
{ printf '#!%s\n' "$REAL_BASH"; cat <<'STUB'
printf '%s|%s\n' "$*" "${DOPPLER_TOKEN-<unset>}" >> "${STUB_LOG:?}"
case "${1-} ${2-}" in
  "secrets --only-names")
    [[ "$*" == *"--json"* && "$*" == *"-p soleur-inngest"* && "$*" == *"-c prd"* ]] || exit 64
    case "${STUB_NAMES:?}" in
      ok_key)   printf '{"INNGEST_CUTOVER_FLIP":{},"INNGEST_SIGNING_KEY":{}}\n' ;;
      ok_nokey) printf '{"INNGEST_SIGNING_KEY":{},"INNGEST_EVENT_KEY":{}}\n' ;;
      empty)    : ;;
      emptyobj) printf '{}\n' ;;
      invalid)  printf 'this is not json\n' ;;
      array)    printf '["INNGEST_CUTOVER_FLIP"]\n' ;;
      rc1)      exit 1 ;;
      *)        exit 64 ;;
    esac ;;
  "secrets get")
    [[ "$*" == *"INNGEST_CUTOVER_FLIP"* && "$*" == *"-p soleur-inngest"* && "$*" == *"-c prd"* && "$*" == *"--plain"* ]] || exit 64
    case "${STUB_GET:?}" in
      val)   printf '%b' "${STUB_VALUE-}" ;;
      fail)  printf 'Doppler Error: boom\n' >&2; exit 1 ;;
      *)     exit 64 ;;
    esac ;;
  *) exit 64 ;;
esac
STUB
} > "$STUBDIR/doppler"
chmod +x "$STUBDIR/doppler"

# make_path <name> <with_doppler 0|1> <with_jq 0|1>: a symlink farm holding ONLY what the step may use.
make_path() {
  local d="$SANDBOX/path.$1"; assert_fixture_dir "$d"; mkdir -p "$d"
  ln -sf "$REAL_TR" "$d/tr"
  if [ "$2" = 1 ]; then ln -sf "$STUBDIR/doppler" "$d/doppler"; fi
  if [ "$3" = 1 ]; then ln -sf "$REAL_JQ" "$d/jq"; fi
  printf '%s' "$d"
}
PATH_FULL="$(make_path full 1 1)"; PATH_NODOP="$(make_path nodop 0 1)"; PATH_NOJQ="$(make_path nojq 1 0)"

# extract_step <workflow> <outdir>: writes <outdir>/body.sh and <outdir>/meta (key=value lines).
extract_step() {
  local wf="$1" out="$2"; assert_fixture_dir "$out"; mkdir -p "$out"
  python3 - "$wf" "$out" "$STEP_NAME" "$JOB" <<'PY'
import sys, yaml
wf, out, name, job = sys.argv[1:5]
d = yaml.safe_load(open(wf))
steps = d["jobs"][job]["steps"]
exact = [s for s in steps if s.get("name") == name]
pre = [s for s in steps if isinstance(s.get("name"), str) and s["name"].startswith("Preflight")]
body = exact[0].get("run", "") if len(exact) == 1 else ""
open(out + "/body.sh", "w").write(body)
env = exact[0].get("env") or {} if len(exact) == 1 else {}
lines = [l for l in body.splitlines() if l.strip() and not l.strip().startswith("#")]
meta = {
    "found": len(exact),
    "preflight_steps": len(pre),
    "coe": "1" if len(exact) == 1 and "continue-on-error" in exact[0] else "0",
    "env_keys": ",".join(sorted(env)),
    "env_vals": "|".join(str(env[k]) for k in sorted(env)),
    "body_lines": len(lines),
}
open(out + "/meta", "w").write("\n".join("%s=%s" % kv for kv in meta.items()) + "\n")
PY
}
meta_get() { sed -n "s/^$2=//p" "$1/meta" | head -1; }

# run_step <outdir> <path> <token> <names> <get> <value> [shellopts]: sets RUN_RC and LAST_* (never call it in $(...): the globals would die with the subshell).
LAST_OUT=""; LAST_SUMMARY=""; LAST_LOG=""; RUN_RC=""
run_step() {
  local od="$1" pth="$2" tok="$3" names="$4" get="$5" val="$6" sopts="${7:-}"
  LAST_OUT="$od/out.$ROWS_RUN"; LAST_SUMMARY="$od/summary.$ROWS_RUN"; LAST_LOG="$od/stub.$ROWS_RUN"
  : > "$LAST_SUMMARY"; : > "$LAST_LOG"
  ROWS_RUN=$((ROWS_RUN + 1)); printf x >> "$SANDBOX/rows.count"
  local -a envv=("HOME=$od" "PATH=$pth" "GITHUB_STEP_SUMMARY=$LAST_SUMMARY" "GITHUB_ENV=$od/ghenv"
                 "STUB_LOG=$LAST_LOG" "STUB_NAMES=$names" "STUB_GET=$get" "STUB_VALUE=$val")
  if [ -n "$tok" ]; then envv+=("$SECRET_NAME=$tok"); fi
  if [ -n "$sopts" ]; then envv+=("SHELLOPTS=$sopts"); fi
  local rc=0
  env -i "${envv[@]}" "$REAL_BASH" --noprofile --norc -eo pipefail "$od/body.sh" > "$LAST_OUT" 2>&1 || rc=$?
  RUN_RC=$rc
}

# rows <workflow> <label>: executes every behavioural row; prints one "BAD:<row>" per failing row.
rows() {
  local wf="$1" od="$SANDBOX/rows.$2" rc
  extract_step "$wf" "$od"
  if [ "$(meta_get "$od" found)" != "1" ]; then printf 'BAD:step-not-found-once\n'; return 0; fi
  expect() { # name want_rc [grep-pattern-in-output]
    if [ "$rc" != "$2" ]; then printf 'BAD:%s(rc=%s,want=%s)\n' "$1" "$rc" "$2"; return 0; fi
    if [ -n "${3:-}" ] && ! grep -qE -- "$3" "$LAST_OUT"; then printf 'BAD:%s(output-missing:%s)\n' "$1" "$3"; fi
  }
  local TOK='tok-A1b2C3-synthetic'
  run_step "$od" "$PATH_FULL" "" ok_key val 'done'; rc=$RUN_RC;                        expect empty-token 1 "$SECRET_NAME"
  run_step "$od" "$PATH_FULL" "$TOK" empty val 'done'; rc=$RUN_RC;                     expect names-empty-rc0 1
  run_step "$od" "$PATH_FULL" "$TOK" emptyobj val 'done'; rc=$RUN_RC;                  expect names-empty-object 1
  run_step "$od" "$PATH_FULL" "$TOK" invalid val 'done'; rc=$RUN_RC;                   expect names-invalid-json 1
  run_step "$od" "$PATH_FULL" "$TOK" array val 'done'; rc=$RUN_RC;                     expect names-not-object 1
  run_step "$od" "$PATH_FULL" "$TOK" rc1 val 'done'; rc=$RUN_RC;                       expect names-rc1 1
  run_step "$od" "$PATH_NODOP" "$TOK" ok_key val 'done'; rc=$RUN_RC;                   expect doppler-missing 1
  run_step "$od" "$PATH_NOJQ" "$TOK" ok_key val 'done'; rc=$RUN_RC;                    expect jq-missing 1
  run_step "$od" "$PATH_FULL" "$TOK" ok_key fail ''; rc=$RUN_RC;                       expect get-fails 1
  run_step "$od" "$PATH_FULL" "$TOK" ok_nokey val ''; rc=$RUN_RC;                      expect key-absent 0 'UNSET'
  run_step "$od" "$PATH_FULL" "$TOK" ok_key val ''; rc=$RUN_RC;                        expect value-empty 0 'UNSET'
  run_step "$od" "$PATH_FULL" "$TOK" ok_key val 'flushed \r\n  '; rc=$RUN_RC;          expect value-flushed-crlf 0 'no inherited-done hazard'
  if grep -qE 'WILL (strand|leave)' "$LAST_OUT"; then printf 'BAD:value-flushed-crlf(false-hazard-text)\n'; fi
  run_step "$od" "$PATH_FULL" "tok-Z9y8X7-other-valid" ok_key val 'done\n'; rc=$RUN_RC; expect value-done-other-token 0 'WILL leave inngest-server refusing'
  if ! grep -qF 'op=resume' "$LAST_SUMMARY"; then printf 'BAD:value-done(summary-lacks-recover)\n'; fi
  local seen; seen="$(sed -n 's/^.*|//p' "$LAST_LOG" | sort -u | tr '\n' ' ')"
  if [ "$seen" != "tok-Z9y8X7-other-valid " ]; then printf 'BAD:value-done(stub-token-not-flip-read:%s)\n' "$seen"; fi
  if ! grep -qE '^secrets --only-names --json .*-p soleur-inngest -c prd\|' "$LAST_LOG" && \
     ! grep -qE '^secrets --only-names .*-p soleur-inngest .*-c prd.*\|' "$LAST_LOG"; then printf 'BAD:value-done(argv-scope)\n'; fi
  run_step "$od" "$PATH_FULL" "$TOK" ok_key val 'armed'; rc=$RUN_RC;                   expect value-armed 0 'WILL strand the scheduler'
  run_step "$od" "$PATH_FULL" "$TOK" ok_key val 'weird'; rc=$RUN_RC;                   expect value-other 0 'outside inngest-server-flip-guard'
  run_step "$od" "$PATH_FULL" "$TOK" ok_key val 'done' 'xtrace'; rc=$RUN_RC;           expect xtrace-refused 78
  return 0
}

# static_viol <workflow>: prints one VIOL:<code> per static violation of Guard 1.
static_viol() {
  local wf="$1" od="$SANDBOX/static.$2"
  extract_step "$wf" "$od"
  [ "$(meta_get "$od" found)" = "1" ] || printf 'VIOL:step-not-found-once\n'
  [ "$(meta_get "$od" preflight_steps)" = "1" ] || printf 'VIOL:preflight-step-count\n'
  [ "$(meta_get "$od" coe)" = "0" ] || printf 'VIOL:continue-on-error\n'
  [ "$(meta_get "$od" env_keys)" = "$SECRET_NAME" ] || printf 'VIOL:env-keys\n'
  [ "$(meta_get "$od" env_vals)" = '${{ secrets.'"$SECRET_NAME"' }}' ] || printf 'VIOL:env-value\n'
  local n; n="$(meta_get "$od" body_lines)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" -ge 40 ] || printf 'VIOL:body-too-short\n'
  if grep -qE 'secrets\.|secrets\[|toJSON\(' "$od/body.sh"; then printf 'VIOL:body-secrets-access\n'; fi
  if grep -qF "$OLD_SECRET" "$wf"; then printf 'VIOL:residual-arm-reference\n'; fi
  if ! grep -qE '^[[:space:]]*case "\$-" in \*x\*\)' "$od/body.sh"; then printf 'VIOL:xtrace-refusal-missing\n'; fi
}

# tf_viol <tf> <drift> <inventory> <workflow>: prints one VIOL:<code> per Guard 3 violation.
tf_viol() {
  local tf="$1" drift="$2" inv="$3" wf="$4" norm
  if [ ! -s "$tf" ]; then printf 'VIOL:tf-missing\n'; return 0; fi
  norm="$(sed -e 's/#.*//' -e 's#//.*##' "$tf" | tr -s '[:space:]' ' ')"
  case "$norm" in *'resource "doppler_service_token" "inngest_flip_read" {'*) : ;; *) printf 'VIOL:token-resource\n' ;; esac
  case "$norm" in *'resource "github_actions_secret" "doppler_token_inngest_flip_read" {'*) : ;; *) printf 'VIOL:secret-resource\n' ;; esac
  [ "$(printf '%s' "$norm" | grep -o 'access *=' | wc -l)" = "1" ] || printf 'VIOL:access-count\n'
  case "$norm" in *' access = "read" '*) : ;; *) printf 'VIOL:access-not-read\n' ;; esac
  case "$norm" in *'read/write'*) printf 'VIOL:read-write-literal\n' ;; esac
  case "$norm" in *' project = doppler_project.inngest.name '*) : ;; *) printf 'VIOL:project-ref\n' ;; esac
  case "$norm" in *' config = doppler_environment.inngest_prd.slug '*) : ;; *) printf 'VIOL:config-ref\n' ;; esac
  [ "$(printf '%s' "$norm" | grep -o 'plaintext_value *=' | wc -l)" = "1" ] || printf 'VIOL:plaintext-count\n'
  case "$norm" in *' plaintext_value = doppler_service_token.inngest_flip_read.key '*) : ;; *) printf 'VIOL:plaintext-not-own-key\n' ;; esac
  case "$norm" in *' secret_name = "'"$SECRET_NAME"'" '*) : ;; *) printf 'VIOL:secret-name\n' ;; esac
  if grep -qE 'inngest_flip_read|inngest-ci-flip-read|FLIP_READ' "$drift" "$inv"; then printf 'VIOL:in-drift-inventory\n'; fi
  local od="$SANDBOX/tfwf.$MUTANTS_RUN"; extract_step "$wf" "$od"
  [ "$(meta_get "$od" env_keys)" = "$SECRET_NAME" ] || printf 'VIOL:preflight-env-name\n'
}

# mutate <src> <label> <expected-diff-lines> <sed args...>: sets MUT to the mutated copy's path; aborts the
# suite if the edit did not land on exactly the expected number of diff lines. NEVER call it in $(...):
# the abort and the MUTANTS_RUN counter would die with the subshell.
mutate() {
  local src="$1" label="$2" want="$3"; shift 3
  local dst="$SANDBOX/mut.$label"; cp "$src" "$dst"
  sed -i "$@" "$dst" || { printf 'FAIL HARNESS: sed failed for %s\n' "$label" >&2; exit 1; }
  local got; got="$(diff "$src" "$dst" | grep -cE '^[<>]')"
  if [ "$got" != "$want" ]; then
    printf 'FAIL HARNESS: mutation %s landed on %s diff lines, expected %s\n' "$label" "$got" "$want" >&2; exit 1
  fi
  MUTANTS_RUN=$((MUTANTS_RUN + 1)); MUT="$dst"
}

# --- control: the unmutated tree must be clean ---
echo "== Guard 1 control (unmutated workflow)"
v="$(static_viol "$WF_REAL" real)"
if [ -z "$v" ]; then pass "G1 static: step found once, no continue-on-error, env pinned, no residual arm reference, xtrace refusal"; else fail "G1 static violations on the real workflow" "$(printf '%s' "$v" | tr '\n' ' ')"; fi
b="$(rows "$WF_REAL" real)"
if [ -z "$b" ]; then pass "G1 behavioural: every stubbed execution decided as required"; else fail "G1 behavioural rows" "$(printf '%s' "$b" | tr '\n' ' ')"; fi
CONTROL_ROWS="$(wc -c < "$SANDBOX/rows.count" 2>/dev/null || echo 0)"
echo "== Guard 3 control (unmutated token file)"
v="$(tf_viol "$TF_REAL" "$DRIFT_REAL" "$INVENTORY_REAL" "$WF_REAL")"
if [ -z "$v" ]; then pass "G3: access read, by-reference scope, secret carries its own key, outside the drift map and inventory"; else fail "G3 violations on the real token file" "$(printf '%s' "$v" | tr '\n' ' ')"; fi

# need_viol <fn-output> <code> <label>
need() { if printf '%s\n' "$1" | grep -qF -- "$2"; then pass "$3"; else fail "$3" "wanted $2, got: $(printf '%s' "$1" | tr '\n' ' ')"; fi; }

# The mutants only mean something against a clean control; skip them (and say so) when it is not.
if [ "${#FAILURES[@]}" -eq 0 ]; then
  echo "== Guard 1 mutants"
  S='Preflight - inherited-done check, fails closed'
  RNG='/Preflight - inherited-done check/,/Extract backend credentials/'
  mutate "$WF_REAL" g1m1 1 "/$S/a\\        continue-on-error: true"; m=$MUT;             need "$(static_viol "$m" m1)" 'VIOL:continue-on-error' "G1 m1: continue-on-error re-added -> RED"
  mutate "$WF_REAL" g1m2 2 "/${SECRET_NAME} is empty/{n;s/exit 1/exit 0/}"; m=$MUT;       need "$(rows "$m" m2)" 'BAD:empty-token' "G1 m2: empty-token arm exit 0 -> RED"
  mutate "$WF_REAL" g1m3 2 "s/$S/Preflight - renamed/"; m=$MUT;                           need "$(static_viol "$m" m3)" 'VIOL:step-not-found-once' "G1 m3: step renamed (dispatch) -> RED, not vacuous"
  mutate "$WF_REAL" g1m4 2 's/|| blind "read of INNGEST_CUTOVER_FLIP exit \${FLAG_RC}"/|| exit 0/'; m=$MUT;        need "$(rows "$m" m4)" 'BAD:get-fails' "G1 m4: present-key get failure exit 0 -> RED"
  mutate "$WF_REAL" g1m5 2 "s/secrets\.${SECRET_NAME}/secrets.${OLD_SECRET}/"; m=$MUT;    need "$(static_viol "$m" m5)" 'VIOL:env-value' "G1 m5: env points back at the arm secret -> RED"
  mutate "$WF_REAL" g1m6 2 's/|| blind "names list exit \${NAMES_RC}"/|| exit 0/'; m=$MUT; need "$(rows "$m" m6)" 'BAD:names-rc1' "G1 m6: names-list error treated as absent -> RED"
  mutate "$WF_REAL" g1m7 1 '$a\          X: ${{ secrets.'"$OLD_SECRET"' }}'; m=$MUT;    need "$(static_viol "$m" m7)" 'VIOL:residual-arm-reference' "G1 m7: a second reader of the arm secret -> RED"
  mutate "$WF_REAL" g1m8 3 -e "$RNG{" -e "/jq -e 'type==\"object\" and length>0'/d" -e 's/^\( *\)1)$/\1*)/' -e '}'; m=$MUT; need "$(rows "$m" m8)" 'BAD:names-invalid-json' "G1 m8: jq non-zero treated as absent -> RED"
  mutate "$WF_REAL" g1m9 1 -e "$RNG{" -e '/^          set -uo pipefail$/a\          echo "${{ secrets.OTHER }}"' -e '}'; m=$MUT; need "$(static_viol "$m" m9)" 'VIOL:body-secrets-access' "G1 m9: another secrets access inside the body -> RED"
  mutate "$WF_REAL" g1m10 1 "$RNG{/case \"\$-\" in \*x\*)/d}"; m=$MUT;                           need "$(rows "$m" m10)" 'BAD:xtrace-refused' "G1 m10: xtrace refusal removed -> RED"
  # harness rows (suite edit): a names-list fail-open edit must turn the blind-instrument rows RED.
  mutate "$WF_REAL" g1h1 4 -e "$RNG{" -e "/jq -e 'type==\"object\" and length>0'/d" -e '/\[\[ -n "\$NAMES" \]\]/d' -e 's/\*) blind "jq exit \${HAS_RC}" ;;/*) exit 0 ;;/' -e '}'; m=$MUT; b="$(rows "$m" h1)"
  need "$b" 'BAD:names-empty-rc0' "G1 harness: empty-output row is not vacuous (RED when the empty check is removed)"
  need "$b" 'BAD:names-empty-object' "G1 harness: {} row is not vacuous (RED when the object check is removed)"

  echo "== Guard 3 mutants"
  mutate "$TF_REAL" g3m1 2 's/^  access *= *"read"/  access  = "read\/write"/'; m=$MUT;        need "$(tf_viol "$m" "$DRIFT_REAL" "$INVENTORY_REAL" "$WF_REAL")" 'VIOL:access-not-read' "G3 m1: access widened to read/write -> RED"
  mutate "$TF_REAL" g3m3 2 "s/^  secret_name *= *\"${SECRET_NAME}\"/  secret_name     = \"DOPPLER_TOKEN_INNGEST_RENAMED\"/"; m=$MUT; need "$(tf_viol "$m" "$DRIFT_REAL" "$INVENTORY_REAL" "$WF_REAL")" 'VIOL:secret-name' "G3 m3: secret renamed away from the preflight's env name -> RED"
  d="$SANDBOX/drift.mut"; cp "$DRIFT_REAL" "$d"; printf '\n  doppler_service_token.inngest_flip_read\n' >> "$d"; MUTANTS_RUN=$((MUTANTS_RUN + 1))
  need "$(tf_viol "$TF_REAL" "$d" "$INVENTORY_REAL" "$WF_REAL")" 'VIOL:in-drift-inventory' "G3 m4: token joins the token-drift map -> RED"
  need "$(tf_viol "$SANDBOX/does-not-exist.tf" "$DRIFT_REAL" "$INVENTORY_REAL" "$WF_REAL")" 'VIOL:tf-missing' "G3 m5: token file path typo -> RED, not vacuous"
  m="$SANDBOX/mut.g3m6"; cp "$TF_REAL" "$m"; printf '\nresource "doppler_service_token" "extra" {\n  access = "read/write"\n}\n' >> "$m"; MUTANTS_RUN=$((MUTANTS_RUN + 1))
  need "$(tf_viol "$m" "$DRIFT_REAL" "$INVENTORY_REAL" "$WF_REAL")" 'VIOL:access-count' "G3 m6: a second, read/write resource after the compliant first -> RED"
  mutate "$TF_REAL" g3m7 2 's/^  plaintext_value *= *doppler_service_token\.inngest_flip_read\.key/  plaintext_value = doppler_service_token.inngest_arm_write.key/'; m=$MUT; need "$(tf_viol "$m" "$DRIFT_REAL" "$INVENTORY_REAL" "$WF_REAL")" 'VIOL:plaintext-not-own-key' "G3 m7: the read-named secret carries the read/write key -> RED"
  mutate "$TF_REAL" g3m8 2 's/^  project *= *doppler_project\.inngest\.name/  project = "soleur-inngest"/'; m=$MUT; need "$(tf_viol "$m" "$DRIFT_REAL" "$INVENTORY_REAL" "$WF_REAL")" 'VIOL:project-ref' "G3 m8: project as a string literal -> RED"
  # permitted spellings must stay GREEN
  m="$SANDBOX/ok.g3a"; sed 's/access *= *"read"/access   =\n    "read"/' "$TF_REAL" > "$m"
  if [ -z "$(tf_viol "$m" "$DRIFT_REAL" "$INVENTORY_REAL" "$WF_REAL")" ]; then pass "G3 harness: access split across lines stays GREEN"; else fail "G3 harness: access split across lines went RED"; fi
  m="$SANDBOX/ok.g3b"; { cat "$TF_REAL"; printf '# read/write is NOT the access of this token\n'; } > "$m"
  if [ -z "$(tf_viol "$m" "$DRIFT_REAL" "$INVENTORY_REAL" "$WF_REAL")" ]; then pass "G3 harness: a trailing comment saying read/write stays GREEN"; else fail "G3 harness: a comment containing read/write went RED"; fi
else
  fail "mutants skipped: the unmutated control is not clean (fix the control first)"
fi

TOTAL=$((passes + fails))
printf '\n== %d passed, %d failed (%d assertions, %d stubbed executions in the control, %d mutants)\n' "$passes" "$fails" "$TOTAL" "$CONTROL_ROWS" "$MUTANTS_RUN"
# Anti-vacuity floors, reported with printf + exit so a neutered pass()/fail() cannot hide them.
MIN_ASSERTIONS=24; MIN_MUTANTS=17; MIN_CONTROL_ROWS=16
if [ "$TOTAL" -lt "$MIN_ASSERTIONS" ]; then printf 'FAIL FLOOR: %d assertions ran, floor %d\n' "$TOTAL" "$MIN_ASSERTIONS" >&2; exit 1; fi
if [ "$fails" -eq 0 ]; then
  if [ "$MUTANTS_RUN" -lt "$MIN_MUTANTS" ]; then printf 'FAIL FLOOR: %d mutants ran, floor %d\n' "$MUTANTS_RUN" "$MIN_MUTANTS" >&2; exit 1; fi
  if [ "$CONTROL_ROWS" -lt "$MIN_CONTROL_ROWS" ]; then printf 'FAIL FLOOR: %d control executions, floor %d\n' "$CONTROL_ROWS" "$MIN_CONTROL_ROWS" >&2; exit 1; fi
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then printf 'FAIL INSTRUMENT: fail() ledger (%d) disagrees with the counter (%d)\n' "${#FAILURES[@]}" "$fails" >&2; exit 1; fi
[ "$fails" -eq 0 ]
