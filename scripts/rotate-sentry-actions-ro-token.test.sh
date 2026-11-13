#!/usr/bin/env bash
# rotate-sentry-actions-ro-token.test.sh -- end-to-end runs of the Sentry token rotation chain
# against stub gh / curl / doppler / agent-browser on PATH. No network, no real credential:
# every token below is synthesized (cq-test-fixtures-synthesized-only).
#
# WHY IT EXISTS. The rotation script is run by hand, rarely, against a live credential, so a
# defect in it surfaces at the worst moment (rotate-supabase-db-credential.test.sh, #7966, is
# the precedent: that script had never completed a run and nothing noticed). Rows R* pin the
# `ro` profile (SENTRY_ACTIONS_RO_TOKEN, GitHub repo secret only); rows I* pin the `iac`
# profile (SENTRY_IAC_AUTH_TOKEN: GitHub repo secret + Doppler soleur/prd + soleur/prd_terraform).
#
# Stubs record every call to $T/rec/calls (one line per call: tool + argv) and the stdin of
# every store-shaped call to $T/rec/<n>.stdin. They read stdin ONLY on their store arms, and
# they refuse (exit 64) an argv shape the script must never send, so a wrong CLI form reds
# instead of reading the right fixture.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/rotate-sentry-actions-ro-token.sh"
TOKEN="$(printf 'synthROk%.0s' 1 2 3 4 5 6 7 8)"   # 64 chars, non-hex, synthesized
SENTINEL="ZZQP-SENTINEL-7947"

cases=0; failures=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; failures=$((failures + 1)); }
# check <description> <command...>: one executed assertion.
check() { local d="$1"; shift; cases=$((cases + 1)); if "$@"; then pass "$d"; else fail "$d"; fi; }

# Instrument self-test: both verdict paths must move the counters, or every row below is void.
check "selftest pass arm" true >/dev/null
check "selftest fail arm" false >/dev/null
if [[ "$cases" -ne 2 || "$failures" -ne 1 ]]; then
  printf 'INSTRUMENT BROKEN: cases=%s failures=%s after the self-test (want 2/1)\n' "$cases" "$failures"; exit 1
fi
cases=0; failures=0

T=""
trap 'rm -rf "${T:-}"' EXIT INT TERM HUP

setup() {
  T="$(mktemp -d)"
  mkdir -p "$T/bin" "$T/lib" "$T/tmp" "$T/rec" "$T/src"
  : > "$T/rec/calls"; : > "$T/gh-secrets"
  # rec <tool> <argv...>: append the call, print its 1-based sequence number.
  cat > "$T/lib/rec.sh" <<'REC'
rec() {
  local f="$STUB_STATE/rec/calls" n
  n=$(( $(wc -l < "$f") + 1 ))
  { printf '%s' "$1"; shift; printf ' %s' "$@"; printf '\n'; } >> "$f"
  printf '%s' "$n"
}
REC

  cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$STUB_STATE/lib/rec.sh"
n="$(rec gh "$@")"
case "${1:-} ${2:-}" in
  "secret set")
    [[ "$#" -eq 3 || ( "$#" -eq 4 && "$4" == "--no-store" ) ]] || { echo "stub gh: bad set argv: $*" >&2; exit 64; }
    timeout 2 cat > "$STUB_STATE/rec/$n.stdin"
    if [[ "${4:-}" == "--no-store" ]]; then
      bytes=$(wc -c < "$STUB_STATE/rec/$n.stdin")
      len=$(( (48 + bytes + 2) / 3 * 4 ))
      head -c "$len" /dev/zero | tr '\0' 'A'; printf '\n'
      exit 0
    fi
    rc="${STUB_GH_SET_RC:-0}"
    [[ "$rc" -eq 0 ]] && printf '%s\n' "$3" >> "$STUB_STATE/gh-secrets"
    exit "$rc" ;;
  "secret list")
    [[ "$#" -eq 2 ]] || exit 64
    rc="${STUB_GH_LIST_RC:-0}"
    [[ "$rc" -eq 0 ]] || { echo "HTTP 401: Bad credentials" >&2; exit "$rc"; }
    while IFS= read -r s; do printf '%s\t2026-11-13T00:00:00Z\n' "$s"; done < "$STUB_STATE/gh-secrets"
    printf 'UNRELATED_SECRET\t2026-01-01T00:00:00Z\n' ;;
  *) echo "stub gh: unhandled: $*" >&2; exit 64 ;;
esac
STUB

  # curl: routes on the URL, writes the -o body, prints the HTTP code. Never reads stdin.
  cat > "$T/bin/curl" <<'STUB'
#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$STUB_STATE/lib/rec.sh"
rec curl "$@" >/dev/null
out=""; url=""
while (( $# > 0 )); do
  case "$1" in
    -o) out="$2"; shift ;;
    -w|-H|--max-time|--noproxy) shift ;;
    http*) url="$1" ;;
  esac
  shift
done
[[ -n "$out" && -n "$url" ]] || exit 64
case "$url" in
  "https://jikigai-eu.sentry.io/api/0/") printf '{"auth":{"scopes":%s}}' "$STUB_SCOPES" > "$out" ;;
  "https://sentry.io/api/0/organizations/jikigai-eu/") printf '{"links":{"regionUrl":"%s"}}' "$STUB_REGION" > "$out" ;;
  *) printf '[]' > "$out" ;;
esac
if [[ -n "${STUB_CURL_FAIL:-}" && "$url" == *"$STUB_CURL_FAIL"* ]]; then printf '%s' "${STUB_CURL_FAIL_CODE:-403}"; else printf '200'; fi
STUB

  cat > "$T/bin/agent-browser" <<'STUB'
#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$STUB_STATE/lib/rec.sh"
rec agent-browser "$@" >/dev/null
[[ "${1:-} ${2:-}" == "get value" && "$#" -eq 3 ]] || exit 64
printf '%s' "$STUB_TOKEN"
STUB

  # doppler: per-config state $T/dop/<cfg>/<NAME>; exact argv shapes only.
  cat > "$T/bin/doppler" <<'STUB'
#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$STUB_STATE/lib/rec.sh"
n="$(rec doppler "$@")"
D="$STUB_STATE/dop"
if [[ "$*" == "configs -p soleur --json" ]]; then
  rc="${STUB_DOP_CONFIGS_RC:-0}"; [[ "$rc" -eq 0 ]] || { echo "Doppler Error: unauthorized" >&2; exit "$rc"; }
  cat "$STUB_STATE/dop-configs.json"; exit 0
fi
if [[ "$#" -eq 7 && "${1:-} ${2:-} ${3:-} ${4:-} ${6:-} ${7:-}" == "secrets -p soleur -c --only-names --json" ]]; then
  cfg="$5"; [[ -d "$D/$cfg" ]] || exit 1
  ( cd "$D/$cfg" && ls -1 ) | jq -R -n '[inputs | {key: ., value: {}}] | from_entries'; exit 0
fi
if [[ "${1:-} ${2:-}" == "secrets get" && "$#" -eq 8 && "${4:-} ${5:-} ${6:-} ${8:-}" == "-p soleur -c --plain" ]]; then
  name="$3"; cfg="$7"
  v="STUB_DOP_GET_RC_$cfg"; rc="${!v:-0}"; [[ "$rc" -eq 0 ]] || exit "$rc"
  v="STUB_DOP_GET_CORRUPT_$cfg"; [[ -z "${!v:-}" ]] || { printf 'corrupted-readback\n'; exit 0; }
  [[ -f "$D/$cfg/$name" ]] || exit 1
  cat "$D/$cfg/$name"; printf '\n'; exit 0
fi
if [[ "${1:-} ${2:-}" == "secrets set" && "$#" -eq 8 && "${4:-} ${5:-} ${6:-} ${8:-}" == "-p soleur -c --no-interactive" ]]; then
  name="$3"; cfg="$7"
  timeout 2 cat > "$STUB_STATE/rec/$n.stdin"
  v="STUB_DOP_SET_RC_$cfg"; rc="${!v:-0}"
  if [[ "$rc" -eq 0 ]]; then mkdir -p "$D/$cfg"; cp "$STUB_STATE/rec/$n.stdin" "$D/$cfg/$name"; fi
  # The real CLI prints every other secret of the config on a write.
  echo "STUB-ALL-OTHER-SECRETS-CANARY"
  exit "$rc"
fi
echo "stub doppler: unhandled: $*" >&2; exit 64
STUB
  chmod +x "$T/bin/"*
}

# run <args...>: the script under test, stdin closed, scratch under $T/tmp.
run() {
  set +e
  STUB_STATE="$T" STUB_TOKEN="$TOKEN" STUB_SCOPES="${STUB_SCOPES:-}" STUB_REGION="${STUB_REGION:-}" \
    TMPDIR="$T/tmp" PATH="$T/bin:$PATH" bash "$SCRIPT" "$@" < /dev/null > "$T/out" 2> "$T/err"
  rc=$?
  set -e
  cat "$T/out" "$T/err" > "$T/all"
}
show() { sed 's/^/       | /' "$T/all"; }
check_exit() { check "exit $1" test "$rc" -eq "$1"; [[ "$rc" -eq "$1" ]] || show; }
calls_of() { grep -c "^$1 " "$T/rec/calls" || true; }
url_list() { grep '^curl ' "$T/rec/calls" | grep -oE 'https://[^ ]+$' || true; }
stdin_of_call() { # stdin_of_call <grep pattern>: the stdin file of the FIRST matching call
  local n; n="$(grep -n -- "$1" "$T/rec/calls" | head -1 | cut -d: -f1 || true)"
  if [[ -n "$n" ]]; then cat "$T/rec/$n.stdin"; fi
}
no_leak() { # the token is in no recorded argv and in no script output
  ! grep -qF "$TOKEN" "$T/rec/calls" && ! grep -qF "$TOKEN" "$T/all"
}
trap_dir_gone() { [[ -z "$(ls -A "$T/tmp")" ]]; }
put_src() { printf '%s' "$1" > "$T/src/cap"; }

RO_URLS="https://jikigai-eu.sentry.io/api/0/
https://sentry.io/api/0/organizations/jikigai-eu/
https://sentry.io/api/0/organizations/jikigai-eu/events/?per_page=1&field=title&field=timestamp
https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/events/?field=count()&statsPeriod=1h
https://sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-terraform-drift/checkins/?limit=5
https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-community-monitor/checkins/?per_page=1
https://de.sentry.io/api/0/projects/jikigai-eu/web-platform/issues/?limit=1
https://de.sentry.io/api/0/projects/jikigai-eu/web-platform/events/?per_page=1"
export STUB_SCOPES='["project:read","event:read","org:read"]' STUB_REGION="https://de.sentry.io/"

echo "== R1: refuses to run under xtrace (78) before touching anything"
setup; put_src "$TOKEN"
set +e
STUB_STATE="$T" TMPDIR="$T/tmp" PATH="$T/bin:$PATH" bash -x "$SCRIPT" capture --from-file "$T/src/cap" < /dev/null > "$T/all" 2>&1; rc1=$?
STUB_STATE="$T" TMPDIR="$T/tmp" PATH="$T/bin:$PATH" env SHELLOPTS=xtrace bash "$SCRIPT" capture --from-file "$T/src/cap" < /dev/null >> "$T/all" 2>&1; rc2=$?
set -e
check "bash -x exits 78" test "$rc1" -eq 78
check "SHELLOPTS=xtrace exits 78" test "$rc2" -eq 78
check "no stub was called" test "$(wc -l < "$T/rec/calls")" -eq 0
check "source file untouched" test -f "$T/src/cap"
rm -rf "$T"

echo "== R2: usage errors exit 2"
setup
run; check "no args -> 2" test "$rc" -eq 2
run capture --from-file "$T/src/cap" --dry-run; check "--dry-run without --expect -> 2" test "$rc" -eq 2
run capture --selector '#tok' --from-file "$T/src/cap"; check "both capture forms -> 2" test "$rc" -eq 2
run capture --profile xyz --from-file "$T/src/cap"; check "--profile xyz -> 2" test "$rc" -eq 2
run capture --from-file "$T/src/cap" --profile; check "--profile without a value -> 2" test "$rc" -eq 2
check "no stub was called" test "$(wc -l < "$T/rec/calls")" -eq 0
rm -rf "$T"

echo "== R3: ro dry run writes nothing and proves the gh store form"
setup; put_src "$SENTINEL"
run capture --from-file "$T/src/cap" --dry-run --expect "$SENTINEL"
check_exit 0
check "exactly one gh call, the no-store form" test "$(grep -c '^gh secret set ZZ_DRYRUN_7946 --no-store$' "$T/rec/calls")" -eq 1 -a "$(calls_of gh)" -eq 1
check "no-store stdin is the sentinel" test "$(stdin_of_call '^gh secret set ZZ_DRYRUN_7946')" == "$SENTINEL"
check "zero curl calls" test "$(calls_of curl)" -eq 0
check "zero doppler calls" test "$(calls_of doppler)" -eq 0
check "trap dir removed" trap_dir_gone
check "source file shredded" test ! -e "$T/src/cap"
rm -rf "$T"

ro_happy() { # ro_happy [extra args...]: R4's assertions; leaves $T for the caller
  setup; put_src "$TOKEN"
  run capture --from-file "$T/src/cap" "$@"
  check_exit 0
  check "curl URLs are /api/0/, the control-host org read and the six ro probes, in order" test "$(url_list)" == "$RO_URLS"
  check "every curl call carries --disable --noproxy '*' and -H @file" \
    test "$(grep '^curl ' "$T/rec/calls" | grep -c -- '^curl --disable --noproxy \* .* -H @/')" -eq 8
  check "one store: gh secret set SENTRY_ACTIONS_RO_TOKEN, no body flag" \
    test "$(grep -c '^gh secret set SENTRY_ACTIONS_RO_TOKEN$' "$T/rec/calls")" -eq 1 -a "$(grep -c -- '--body' "$T/rec/calls")" -eq 0
  check "store stdin is the token" test "$(stdin_of_call '^gh secret set SENTRY_ACTIONS_RO_TOKEN$')" == "$TOKEN"
  check "gh secret list ran after the write" test "$(grep -n '^gh ' "$T/rec/calls" | tail -1 | cut -d' ' -f2-)" == "secret list"
  check "zero doppler calls" test "$(calls_of doppler)" -eq 0
  check "token never in argv or output" no_leak
  check "trap dir removed" trap_dir_gone
}

# norm_records: calls + output with the per-run paths normalised, for byte comparison.
norm_records() { cat "$T/rec/calls" "$T/out" "$T/err" | sed -E "s#${T}#<T>#g; s#tmp\.[A-Za-z0-9]+#<TD>#g"; }

echo "== R4: ro live happy path (--from-file); --profile ro is byte-identical to no --profile"
ro_happy
plain="$(norm_records)"
rm -rf "$T"
ro_happy --profile ro
check "--profile ro records and output == no --profile" test "$(norm_records)" == "$plain"
rm -rf "$T"

echo "== R5: an extra scope blocks the store"
setup; put_src "$TOKEN"
STUB_SCOPES='["event:read","org:read","project:read","project:write"]' run capture --from-file "$T/src/cap"
check "exit 1" test "$rc" -eq 1
check "no gh secret set" test "$(grep -c '^gh secret set' "$T/rec/calls" || true)" -eq 0
check "token never in argv or output" no_leak
rm -rf "$T"

echo "== R6: one probe 403 blocks the store"
setup; put_src "$TOKEN"
STUB_CURL_FAIL="web-platform/issues/" run capture --from-file "$T/src/cap"
check "exit 1" test "$rc" -eq 1
check "no gh secret set" test "$(grep -c '^gh secret set' "$T/rec/calls" || true)" -eq 0
check "the failing probe is named" grep -q 'FAIL\] 403 https://de.sentry.io/api/0/projects/jikigai-eu/web-platform/issues/' "$T/all"
rm -rf "$T"

echo "== R7: an unpinned regionUrl blocks the store"
setup; put_src "$TOKEN"
STUB_REGION="https://us.sentry.io" run capture --from-file "$T/src/cap"
check "exit 1" test "$rc" -eq 1
check "no gh secret set" test "$(grep -c '^gh secret set' "$T/rec/calls" || true)" -eq 0
rm -rf "$T"

echo "== R8: --selector capture through agent-browser"
setup
run capture --selector 'input[aria-label="Generated token"]'
check_exit 0
check "agent-browser get value called once with the selector" \
  test "$(grep -c '^agent-browser get value input\[aria-label="Generated token"\]$' "$T/rec/calls")" -eq 1
check "store stdin is the token" test "$(stdin_of_call '^gh secret set SENTRY_ACTIONS_RO_TOKEN$')" == "$TOKEN"
check "token never in argv or output" no_leak
rm -rf "$T"

# ---------------------------------------------------------------------------------------
# iac profile. The Doppler fixture mirrors soleur's shape (measured 2026-11-13): `prd` is the
# root, `prd_terraform` a branch, and branch configs hold INDEPENDENT copies (no live
# inheritance), so two of the other prd branches carry the key and one does not. A dev
# branch also carries it, to prove the stale-copies census filters on environment.
OLD="$(printf 'synthOLD%.0s' 1 2 3 4 5 6 7 8)"
IAC_SCOPES='["project:write","alerts:write","event:read","alerts:read","org:read","project:admin","project:read"]'
IAC_URLS="https://jikigai-eu.sentry.io/api/0/
https://jikigai-eu.sentry.io/api/0/projects/jikigai-eu/web-platform/
https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/workflows/?per_page=1
https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/monitors/?per_page=1
https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/issues/?query=is:unresolved&limit=1&statsPeriod=24h"
DOP_WRITES_WANT="doppler secrets set SENTRY_IAC_AUTH_TOKEN -p soleur -c prd --no-interactive
doppler secrets set SENTRY_IAC_AUTH_TOKEN -p soleur -c prd_terraform --no-interactive"
T_GH="GitHub repo secret SENTRY_IAC_AUTH_TOKEN"; T_PRD="Doppler soleur/prd"; T_PTF="Doppler soleur/prd_terraform"
REVOKE_OLD_LINE='all three targets hold the new token'

setup_iac() { # setup_iac [no-carriers|no-prd-terraform]
  setup; put_src "$TOKEN"
  local cfgs='{"name":"dev","root":true,"environment":"dev"},{"name":"dev_x","root":false,"environment":"dev"},{"name":"prd","root":true,"environment":"prd"}'
  case "${1:-}" in
    no-carriers)      cfgs="$cfgs"',{"name":"prd_terraform","root":false,"environment":"prd"}' ;;
    no-prd-terraform) cfgs="$cfgs"',{"name":"prd_alpha","root":false,"environment":"prd"}' ;;
    *) cfgs="$cfgs"',{"name":"prd_alpha","root":false,"environment":"prd"},{"name":"prd_beta","root":false,"environment":"prd"},{"name":"prd_gamma","root":false,"environment":"prd"},{"name":"prd_terraform","root":false,"environment":"prd"}' ;;
  esac
  printf '[%s]\n' "$cfgs" > "$T/dop-configs.json"
  local c
  for c in prd prd_terraform prd_alpha prd_beta dev_x; do
    mkdir -p "$T/dop/$c"; printf '%s' "$OLD" > "$T/dop/$c/SENTRY_IAC_AUTH_TOKEN"; printf 'x' > "$T/dop/$c/OTHER_KEY"
  done
  mkdir -p "$T/dop/prd_gamma"; printf 'x' > "$T/dop/prd_gamma/OTHER_KEY"
}
run_iac() { STUB_SCOPES="$IAC_SCOPES" run capture --profile iac --from-file "$T/src/cap"; }
dop_writes() { grep '^doppler secrets set ' "$T/rec/calls" || true; }
dop_value_is() { [[ "$(cat "$T/dop/$1/SENTRY_IAC_AUTH_TOKEN")" == "$2" ]]; }
line_is() { # line_is <label prefix> <expected rest>: the report line for one list, exactly
  [[ "$(grep -F -- "$1" "$T/all" | head -1)" == "$1$2" ]]
}
no_stores() {
  [[ "$(grep -c '^gh secret set SENTRY_IAC_AUTH_TOKEN' "$T/rec/calls" || true)" -eq 0 && -z "$(dop_writes)" ]]
}
no_canary() { ! grep -q 'STUB-ALL-OTHER-SECRETS-CANARY' "$T/all"; }
absent() { ! grep -qF -- "$1" "$T/all"; }

echo "== I1: iac dry run writes nothing and proves Doppler login + both configs read-only"
# Doppler's `secrets set` has no no-store mode (doppler v3.77.1 --help), so the dry run CANNOT
# prove the Doppler store form without writing. It proves Doppler login and both target configs
# read-only; the exact store argv + stdin is pinned by I2 below.
setup_iac; put_src "$SENTINEL"
STUB_SCOPES="$IAC_SCOPES" run capture --profile iac --from-file "$T/src/cap" --dry-run --expect "$SENTINEL"
check_exit 0
check "zero Doppler writes" test -z "$(dop_writes)"
check "zero curl calls" test "$(calls_of curl)" -eq 0
check "exactly one gh call, the no-store form" test "$(grep -c '^gh secret set ZZ_DRYRUN_7946 --no-store$' "$T/rec/calls")" -eq 1 -a "$(calls_of gh)" -eq 1
check "exactly one doppler configs enumeration" test "$(grep -c '^doppler configs -p soleur --json$' "$T/rec/calls")" -eq 1
check "output says Doppler has no no-store mode" grep -q 'Doppler has no no-store mode' "$T/all"
check "script header carries the same statement" grep -q "^# Doppler's \`secrets set\` has no no-store mode" "$SCRIPT"
check "trap dir removed" trap_dir_gone
check "Doppler state untouched" dop_value_is prd "$OLD"
rm -rf "$T"

echo "== I2: iac happy path stores to all three targets, each proven"
setup_iac
run_iac
check_exit 0
check "curl URLs are /api/0/ plus the four iac probes, in order, org host only" test "$(url_list)" == "$IAC_URLS"
check "every curl call carries --disable --noproxy '*' and -H @file" \
  test "$(grep -c -- '^curl --disable --noproxy \* .* -H @/' "$T/rec/calls")" -eq 5 -a "$(calls_of curl)" -eq 5
check "one gh store, SENTRY_IAC_AUTH_TOKEN, no body flag" \
  test "$(grep -c '^gh secret set SENTRY_IAC_AUTH_TOKEN$' "$T/rec/calls")" -eq 1 -a "$(grep -c -- '--body' "$T/rec/calls")" -eq 0
check "gh store stdin is the token" test "$(stdin_of_call '^gh secret set SENTRY_IAC_AUTH_TOKEN$')" == "$TOKEN"
check "exactly two Doppler writes, prd then prd_terraform, exact argv" test "$(dop_writes)" == "$DOP_WRITES_WANT"
check "Doppler prd write stdin is the token" test "$(stdin_of_call ' -c prd --no-interactive$')" == "$TOKEN"
check "Doppler prd_terraform write stdin is the token" test "$(stdin_of_call ' -c prd_terraform --no-interactive$')" == "$TOKEN"
check "Doppler prd holds the new value" dop_value_is prd "$TOKEN"
check "Doppler prd_terraform holds the new value" dop_value_is prd_terraform "$TOKEN"
check "unlisted branch copies are not written" dop_value_is prd_alpha "$OLD"
check "STALE COPIES names prd_alpha and prd_beta only" line_is 'STALE COPIES (no known reader in repo): ' 'prd_alpha, prd_beta -- not written; removal tracked in #12740'
check "revoke-old guidance printed" grep -q "$REVOKE_OLD_LINE" "$T/all"
check "no partial-state report" absent 'do NOT revoke'
check "the CLI's all-secrets dump never reaches output" no_canary
check "token never in argv or output" no_leak
check "trap dir removed" trap_dir_gone
rm -rf "$T"

echo "== I5: the ro scope triple is refused for iac"
setup_iac
STUB_SCOPES='["event:read","org:read","project:read"]' run capture --profile iac --from-file "$T/src/cap"
check "exit 1" test "$rc" -eq 1
check "no store anywhere" no_stores
rm -rf "$T"

echo "== I6: a 403 on the second probe blocks every store; the loop still runs the rest"
setup_iac
STUB_CURL_FAIL="organizations/jikigai-eu/workflows/" run_iac
check "exit 1" test "$rc" -eq 1
check "no store anywhere" no_stores
check "probes 3 and 4 still ran" test "$(url_list | grep -cE '/(monitors|issues)/\?')" -eq 2
rm -rf "$T"

echo "== I7: the Doppler prd write fails after GitHub landed"
setup_iac
STUB_DOP_SET_RC_prd=1 run_iac
check "exit 1" test "$rc" -eq 1
check "HOLD NEW: GitHub only" line_is "HOLD THE NEW TOKEN (...${TOKEN: -4}): " "$T_GH"
check "UNVERIFIED: none" line_is 'UNVERIFIED (value unknown): ' '(none)'
check "STILL HOLD OLD: prd and prd_terraform" line_is 'STILL HOLD THE OLD TOKEN: ' "$T_PRD; $T_PTF"
check "do NOT revoke the old token yet" grep -q 'do NOT revoke the old token yet' "$T/all"
check "no revoke-old guidance" absent "$REVOKE_OLD_LINE"
check "prd_terraform never written" test "$(dop_writes | grep -c prd_terraform || true)" -eq 0
check "the CLI's all-secrets dump never reaches output" no_canary
rm -rf "$T"

echo "== I8: the prd read-back does not match"
setup_iac
STUB_DOP_GET_CORRUPT_prd=1 run_iac
check "exit 1" test "$rc" -eq 1
check "HOLD NEW: GitHub only" line_is "HOLD THE NEW TOKEN (...${TOKEN: -4}): " "$T_GH"
check "UNVERIFIED: prd" line_is 'UNVERIFIED (value unknown): ' "$T_PRD"
check "STILL HOLD OLD: prd_terraform" line_is 'STILL HOLD THE OLD TOKEN: ' "$T_PTF"
check "do NOT revoke the old token yet" grep -q 'do NOT revoke the old token yet' "$T/all"
rm -rf "$T"

echo "== I9: the prd_terraform read-back fails -- a failed read is never a match"
setup_iac
STUB_DOP_GET_RC_prd_terraform=1 run_iac
check "exit 1" test "$rc" -eq 1
check "HOLD NEW: GitHub and prd" line_is "HOLD THE NEW TOKEN (...${TOKEN: -4}): " "$T_GH; $T_PRD"
check "UNVERIFIED: prd_terraform" line_is 'UNVERIFIED (value unknown): ' "$T_PTF"
check "STILL HOLD OLD: none" line_is 'STILL HOLD THE OLD TOKEN: ' '(none)'
check "no revoke-old guidance" absent "$REVOKE_OLD_LINE"
rm -rf "$T"

echo "== I10: the Doppler preflight fails before capture; the source file is named, not shredded"
setup_iac
STUB_DOP_CONFIGS_RC=1 run_iac
check "exit 2" test "$rc" -eq 2
check "source file still exists" test -f "$T/src/cap"
check "the message names the source file" grep -qF -- "$T/src/cap still holds the plaintext" "$T/all"
check "no store anywhere" no_stores
check "zero curl calls" test "$(calls_of curl)" -eq 0
rm -rf "$T"

echo "== I10b: prd_terraform absent from the enumeration -> 2"
setup_iac no-prd-terraform
run_iac
check "exit 2" test "$rc" -eq 2
check "names the missing config" grep -q 'prd_terraform' "$T/err"
check "no store anywhere" no_stores
rm -rf "$T"

echo "== I11: the GitHub write fails first -> revoke the NEW token, no Doppler write"
setup_iac
STUB_GH_SET_RC=1 run_iac
check "exit 1" test "$rc" -eq 1
check "revoke-the-NEW-token message" grep -q 'REVOKE THE NEW TOKEN' "$T/all"
check "zero Doppler writes" test -z "$(dop_writes)"
check "no partial-state report" absent 'do NOT revoke'
rm -rf "$T"

echo "== I12: gh secret list fails after the write -> GitHub UNVERIFIED, no Doppler write"
setup_iac
STUB_GH_LIST_RC=1 run_iac
check "exit 1" test "$rc" -eq 1
check "UNVERIFIED: GitHub" line_is 'UNVERIFIED (value unknown): ' "$T_GH"
check "STILL HOLD OLD: prd and prd_terraform" line_is 'STILL HOLD THE OLD TOKEN: ' "$T_PRD; $T_PTF"
check "zero Doppler writes" test -z "$(dop_writes)"
check "do NOT revoke the old token yet" grep -q 'do NOT revoke the old token yet' "$T/all"
rm -rf "$T"

echo "== H2: no other carriers -> success, STALE COPIES none, revoke-old guidance printed"
setup_iac no-carriers
run_iac
check_exit 0
check "STALE COPIES none" line_is 'STALE COPIES (no known reader in repo): ' '(none)'
check "revoke-old guidance printed" grep -q "$REVOKE_OLD_LINE" "$T/all"
rm -rf "$T"

# Exact executed-assertion count: a row that stops running cannot pass silently. Reported
# with printf + exit, never through fail(), which this floor backstops.
EXPECTED_CASES=117
echo
echo "cases=$cases failures=$failures"
if [[ "$cases" -ne "$EXPECTED_CASES" ]]; then
  printf 'ASSERTION COUNT %s != expected %s -- a row was skipped or added without updating the count\n' "$cases" "$EXPECTED_CASES"; exit 1
fi
[[ "$failures" -eq 0 ]]
