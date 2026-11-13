#!/usr/bin/env bash
# rotate-sentry-actions-ro-token.test.sh -- end-to-end runs of the Sentry token rotation chain
# against stub gh / curl / doppler / agent-browser on PATH. No network, no real credential:
# every token below is synthesized (cq-test-fixtures-synthesized-only).
#
# WHY IT EXISTS. The rotation script is run by hand, rarely, against a live credential, so a
# defect in it surfaces at the worst moment (rotate-supabase-db-credential.test.sh, #7966, is
# the precedent: that script had never completed a run and nothing noticed). Rows R* pin the
# `ro` profile (SENTRY_ACTIONS_RO_TOKEN, GitHub repo secret only).
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
if [[ "${1:-} ${2:-} ${3:-} ${5:-} ${6:-} ${7:-} ${8:-}" == "secrets -p soleur -c --only-names --json " && "$#" -eq 6 ]]; then
  cfg="$4"; [[ -d "$D/$cfg" ]] || exit 1
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

echo "== R4: ro live happy path (--from-file)"
ro_happy
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

# Exact executed-assertion count: a row that stops running cannot pass silently. Reported
# with printf + exit, never through fail(), which this floor backstops.
EXPECTED_CASES=36
echo
echo "cases=$cases failures=$failures"
if [[ "$cases" -ne "$EXPECTED_CASES" ]]; then
  printf 'ASSERTION COUNT %s != expected %s -- a row was skipped or added without updating the count\n' "$cases" "$EXPECTED_CASES"; exit 1
fi
[[ "$failures" -eq 0 ]]
