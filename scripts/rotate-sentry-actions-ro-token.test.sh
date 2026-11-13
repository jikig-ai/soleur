#!/usr/bin/env bash
# Predicate helpers are invoked through check "<desc>" <helper>, which shellcheck cannot follow.
# shellcheck disable=SC2329
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
# they REFUSE (exit 64, one line in $T/rec/refusals) any argv or environment the script must
# never produce, so a wrong CLI form reds instead of reading the right fixture. Stored values
# and stdin are compared BYTE-for-byte (cmp), never through $(...), which strips trailing LF.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/rotate-sentry-actions-ro-token.sh"
ADR031="$(cd "$(dirname "$0")/.." && pwd)/knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md"
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
  : > "$T/rec/calls"; : > "$T/rec/refusals"; echo 0 > "$T/gh-seq"
  # A real rotation always finds the secret name ALREADY present, next to a prefix decoy.
  printf '%s\t%s\n' \
    SENTRY_ACTIONS_RO_TOKEN 2026-01-01T00:00:00Z SENTRY_ACTIONS_RO_TOKEN_OLD 2026-01-01T00:00:00Z \
    SENTRY_IAC_AUTH_TOKEN 2026-05-19T19:50:38Z SENTRY_IAC_AUTH_TOKEN_OLD 2026-05-19T19:50:38Z \
    UNRELATED_SECRET 2026-01-01T00:00:00Z > "$T/gh-secrets"
  # rec <tool> <argv...>: append the call, print its 1-based sequence number.
  cat > "$T/lib/rec.sh" <<'REC'
rec() {
  local f="$STUB_STATE/rec/calls" n
  n=$(( $(wc -l < "$f") + 1 ))
  { printf '%s' "$1"; shift; printf ' %s' "$@"; printf '\n'; } >> "$f"
  printf '%s' "$n"
}
refuse() { printf '%s\n' "$*" >> "$STUB_STATE/rec/refusals"; exit 64; }
REC

  cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$STUB_STATE/lib/rec.sh"
n="$(rec gh "$@")"
S="$STUB_STATE/gh-secrets"
set_done() { [[ -e "$STUB_STATE/gh-set-done" ]]; }
case "${1:-} ${2:-}" in
  "secret set")
    if [[ "$#" -eq 4 && "$4" == "--no-store" ]]; then
      timeout 2 cat > "$STUB_STATE/rec/$n.stdin"
      bytes=$(wc -c < "$STUB_STATE/rec/$n.stdin")
      len=$(( (48 + bytes + 2) / 3 * 4 ))
      head -c "$len" /dev/zero | tr '\0' 'A'; printf '\n'
      exit 0
    fi
    [[ "$#" -eq 3 || ( "$#" -eq 5 && "$4" == "-R" && "$5" == "jikig-ai/soleur" ) ]] || refuse "gh bad set argv: $*"
    timeout 2 cat > "$STUB_STATE/rec/$n.stdin"
    rc="${STUB_GH_SET_RC:-0}"; [[ "$rc" -eq 0 ]] || exit "$rc"
    [[ -n "${STUB_GH_SET_NOOP:-}" ]] && exit 0
    seq=$(( $(cat "$STUB_STATE/gh-seq") + 1 )); echo "$seq" > "$STUB_STATE/gh-seq"
    ts="$(printf '2026-11-13T00:00:%02dZ' "$seq")"
    awk -F'\t' -v n="$3" -v ts="$ts" 'BEGIN{OFS="\t"} $1==n{$2=ts; f=1} {print} END{if(!f) print n, ts}' "$S" > "$S.new" && mv "$S.new" "$S"
    touch "$STUB_STATE/gh-set-done"
    exit 0 ;;
  "secret list")
    if set_done; then rc="${STUB_GH_LIST_RC:-0}"; else rc="${STUB_GH_LIST_RC_PRE:-0}"; fi
    [[ "$rc" -eq 0 ]] || { echo "HTTP 401: Bad credentials" >&2; exit "$rc"; }
    if [[ "$#" -eq 2 ]]; then cat "$S"; exit 0; fi
    [[ "$#" -eq 6 && "$3 $4 $5 $6" == "-R jikig-ai/soleur --json name,updatedAt" ]] || refuse "gh bad list argv: $*"
    jq -R -n '[inputs | split("\t") | {name: .[0], updatedAt: .[1]}]' < "$S" ;;
  *) refuse "gh unhandled: $*" ;;
esac
STUB

  # curl: accepts ONLY the exact argv the script builds; the bearer must arrive in the -H @file
  # header file (a wrong or missing token answers 401); routes on the URL. Never reads stdin.
  cat > "$T/bin/curl" <<'STUB'
#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$STUB_STATE/lib/rec.sh"
rec curl "$@" >/dev/null
[[ -z "${SSLKEYLOGFILE:-}" ]] || refuse "curl ran with SSLKEYLOGFILE set"
[[ "$#" -eq 13 && "$1 $2 $3 $4 $5 $6 $7" == "--disable --noproxy * -sS --max-time 25 -o" \
   && "$9" == "-w" && "${10}" == "%{http_code}" && "${11}" == "-H" && "${12}" == @/* ]] || refuse "curl bad argv: $*"
out="$8"; url="${13}"; hdr="${12#@}"
if [[ "$(cat "$hdr")" != "Authorization: Bearer $STUB_TOKEN" ]]; then printf '{}' > "$out"; printf '401'; exit 0; fi
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
[[ "${1:-} ${2:-}" == "get value" && "$#" -eq 3 ]] || refuse "agent-browser bad argv: $*"
printf '%s' "$STUB_TOKEN"
STUB

  # The retry loop's sleep is a no-op here, so a row that exhausts it stays fast.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/sleep"

  # doppler: per-config state $T/dop/<cfg>/<NAME>; a config dir holding `.inherits` falls back
  # to soleur/prd for names it does not override (the branch-config model). The pinned API
  # host must lead the argv, and no host/proxy override may reach the process.
  cat > "$T/bin/doppler" <<'STUB'
#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$STUB_STATE/lib/rec.sh"
[[ -z "${DOPPLER_API_HOST:-}${HTTPS_PROXY:-}${https_proxy:-}${HTTP_PROXY:-}${ALL_PROXY:-}${SSLKEYLOGFILE:-}" ]] || refuse "doppler ran with a host/proxy override in its env"
[[ "${1:-} ${2:-}" == "--api-host https://api.doppler.com" ]] || refuse "doppler without the pinned --api-host: $*"
shift 2
n="$(rec doppler "$@")"
D="$STUB_STATE/dop"
val_file() { # val_file <cfg> <name>: the file holding the effective value, or nothing
  if [[ -f "$D/$1/$2" ]]; then printf '%s' "$D/$1/$2"
  elif [[ -e "$D/$1/.inherits" && -f "$D/prd/$2" ]]; then printf '%s' "$D/prd/$2"; fi
}
if [[ "$*" == "configs -p soleur --json" ]]; then
  rc="${STUB_DOP_CONFIGS_RC:-0}"; [[ "$rc" -eq 0 ]] || { echo "Doppler Error: unauthorized" >&2; exit "$rc"; }
  cat "$STUB_STATE/dop-configs.json"; exit 0
fi
if [[ "$#" -eq 7 && "$1 $2 $3 $4 $6 $7" == "secrets -p soleur -c --only-names --json" ]]; then
  cfg="$5"; [[ -d "$D/$cfg" ]] || exit 1
  { ( cd "$D/$cfg" && ls -1 ); if [[ -e "$D/$cfg/.inherits" ]]; then ( cd "$D/prd" && ls -1 ); fi; } \
    | sort -u | jq -R -n '[inputs | {key: ., value: {}}] | from_entries'; exit 0
fi
if [[ "$#" -eq 8 && "$1 $2 $4 $5 $6 $8" == "secrets get -p soleur -c --plain" ]]; then
  name="$3"; cfg="$7"
  if [[ -e "$D/$cfg/.written" ]]; then
    v="STUB_DOP_GET_RC_$cfg"; rc="${!v:-0}"; [[ "$rc" -eq 0 ]] || exit "$rc"
    v="STUB_DOP_GET_CORRUPT_$cfg"; [[ -z "${!v:-}" ]] || { printf 'corrupted-readback\n'; exit 0; }
    v="STUB_DOP_GET_EMPTY_$cfg"; [[ -z "${!v:-}" ]] || { printf '\n'; exit 0; }
  else
    v="STUB_DOP_GET_RC_PRE_$cfg"; rc="${!v:-0}"; [[ "$rc" -eq 0 ]] || exit "$rc"
  fi
  f="$(val_file "$cfg" "$name")"; [[ -n "$f" ]] || exit 1
  cat "$f"; printf '\n'; exit 0
fi
if [[ "$#" -eq 8 && "$1 $2 $4 $5 $6 $8" == "secrets set -p soleur -c --no-interactive" ]]; then
  name="$3"; cfg="$7"
  timeout 2 cat > "$STUB_STATE/rec/$n.stdin"
  v="STUB_DOP_SET_RC_$cfg"; rc="${!v:-0}"
  if [[ "$rc" -eq 0 ]]; then mkdir -p "$D/$cfg"; cp "$STUB_STATE/rec/$n.stdin" "$D/$cfg/$name"; touch "$D/$cfg/.written"; fi
  # The real CLI prints every other secret of the config on a write.
  echo "STUB-ALL-OTHER-SECRETS-CANARY"
  v="STUB_DOP_SET_SIGNAL_$cfg"
  # SIGTERM the script under test: doppler's parent is timeout, whose parent is the script.
  if [[ -n "${!v:-}" ]]; then kill -TERM "$(ps -o ppid= -p "$PPID" | tr -d ' ')"; fi
  exit "$rc"
fi
refuse "doppler unhandled: $*"
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
stdin_file() { # stdin_file <grep pattern>: the stdin file of the FIRST matching call
  local n; n="$(grep -n -- "$1" "$T/rec/calls" | head -1 | cut -d: -f1 || true)"
  if [[ -n "$n" ]]; then printf '%s' "$T/rec/$n.stdin"; fi
}
stdin_is() { # stdin_is <grep pattern> <expected bytes>
  local f; f="$(stdin_file "$1")"
  if [[ -n "$f" ]] && cmp -s "$f" <(printf '%s' "$2"); then return 0; fi
  return 1
}
no_leak() { # the token is in no recorded argv and in no script output
  ! grep -qF "$TOKEN" "$T/rec/calls" && ! grep -qF "$TOKEN" "$T/all"
}
no_refusals() { [[ ! -s "$T/rec/refusals" ]] || { sed 's/^/       refused: /' "$T/rec/refusals"; false; }; }
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
check "no-store stdin is the sentinel, byte-exact" stdin_is '^gh secret set ZZ_DRYRUN_7946' "$SENTINEL"
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
  check "eight curl calls, every one the exact modelled argv" test "$(calls_of curl)" -eq 8
  check "one store: gh secret set SENTRY_ACTIONS_RO_TOKEN, no body flag" \
    test "$(grep -c '^gh secret set SENTRY_ACTIONS_RO_TOKEN$' "$T/rec/calls")" -eq 1 -a "$(grep -c -- '--body' "$T/rec/calls")" -eq 0
  check "store stdin is the token, byte-exact" stdin_is '^gh secret set SENTRY_ACTIONS_RO_TOKEN$' "$TOKEN"
  check "gh secret list ran after the write" test "$(grep -n '^gh ' "$T/rec/calls" | tail -1 | cut -d' ' -f2-)" == "secret list"
  check "zero doppler calls" test "$(calls_of doppler)" -eq 0
  check "token never in argv or output" no_leak
  check "trap dir removed" trap_dir_gone
  check "no stub refused anything" no_refusals
}
# norm_records: calls + output with the per-run paths normalised, for byte comparison.
norm_records() { cat "$T/rec/calls" "$T/out" "$T/err" | sed -E "s#${T}#<T>#g; s#tmp\.[A-Za-z0-9]+#<TD>#g"; }

echo "== R4: ro live happy path (--from-file); --profile ro == the default"
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
check "store stdin is the token, byte-exact" stdin_is '^gh secret set SENTRY_ACTIONS_RO_TOKEN$' "$TOKEN"
check "token never in argv or output" no_leak
rm -rf "$T"

# ---------------------------------------------------------------------------------------
# iac profile. The Doppler fixture follows soleur's shape: `prd` is the root, `prd_terraform`
# a branch. prd_alpha INHERITS the root value (no override), prd_beta holds its OWN copy,
# prd_gamma does not carry the key, prd_delta's names cannot be read, prd_epsilon carries only
# a prefix decoy, prd_zeta lists NO keys at rc 0 (a broken listing, not "no carrier"), and a
# dev branch carries the key (the census filters on environment).
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
L_NEW="HOLD THE NEW TOKEN (...${TOKEN: -4}): "
L_UNV='UNVERIFIED (may hold the new token; value unknown): '
L_OLD='UNCHANGED BY THIS RUN (hold whatever they held before it): '
L_OTHER='OTHER prd CONFIGS CARRYING SENTRY_IAC_AUTH_TOKEN '
ALL_THREE='all three targets hold the new token'
DO_NOT='do NOT revoke the old token yet'

cfg_json() { printf '{"name":"%s","root":%s,"environment":"%s"}' "$1" "$2" "$3"; }
setup_iac() { # setup_iac [no-carriers|no-prd-terraform|prd-not-root|ptf-root]
  setup; put_src "$TOKEN"
  local base list c
  base="$(cfg_json dev true dev),$(cfg_json dev_x false dev)"
  case "${1:-}" in
    no-carriers)      list="$base,$(cfg_json prd true prd),$(cfg_json prd_terraform false prd)" ;;
    no-prd-terraform) list="$base,$(cfg_json prd true prd),$(cfg_json prd_alpha false prd)" ;;
    prd-not-root)     list="$base,$(cfg_json prd false prd),$(cfg_json prd_terraform false prd)" ;;
    ptf-root)         list="$base,$(cfg_json prd true prd),$(cfg_json prd_terraform true prd)" ;;
    *) list="$base,$(cfg_json prd true prd)"
       for c in prd_alpha prd_beta prd_gamma prd_delta prd_epsilon prd_zeta; do list="$list,$(cfg_json "$c" false prd)"; done
       list="$list,$(cfg_json prd_terraform false prd)" ;;
  esac
  printf '[%s]\n' "$list" > "$T/dop-configs.json"
  for c in prd prd_terraform prd_beta dev_x; do
    mkdir -p "$T/dop/$c"; printf '%s' "$OLD" > "$T/dop/$c/SENTRY_IAC_AUTH_TOKEN"; printf 'x' > "$T/dop/$c/OTHER_KEY"
  done
  mkdir -p "$T/dop/prd_alpha" "$T/dop/prd_gamma" "$T/dop/prd_epsilon" "$T/dop/prd_zeta"
  touch "$T/dop/prd_alpha/.inherits"; printf 'x' > "$T/dop/prd_alpha/OTHER_KEY"
  printf 'x' > "$T/dop/prd_gamma/OTHER_KEY"
  printf 'x' > "$T/dop/prd_epsilon/SENTRY_IAC_AUTH_TOKEN_OLD"
}
run_iac() { STUB_SCOPES="$IAC_SCOPES" run capture --profile iac --from-file "$T/src/cap"; }
dop_writes() { grep '^doppler secrets set ' "$T/rec/calls" || true; }
dop_value_is() { cmp -s "$T/dop/$1/SENTRY_IAC_AUTH_TOKEN" <(printf '%s' "$2"); }
gh_updated() { awk -F'\t' -v n="$1" '$1==n{print $2}' "$T/gh-secrets"; }
line_is() { # line_is <label prefix> <expected rest>: exactly ONE report line for that list, exactly
  [[ "$(grep -cF -- "$1" "$T/all")" -eq 1 && "$(grep -F -- "$1" "$T/all")" == "$1$2" ]]
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
check "the dry run previews the candidate configs" line_is "$L_OTHER" '(not written; classified by digest after a live store): prd_alpha, prd_beta; names unreadable: prd_delta, prd_zeta'
check "trap dir removed" trap_dir_gone
check "Doppler state untouched" dop_value_is prd "$OLD"
check "no stub refused anything" no_refusals
rm -rf "$T"

echo "== I2: iac happy path stores to all three targets, each proven"
setup_iac
run_iac
check_exit 0
check "curl URLs are /api/0/ plus the four iac probes, in order, org host only" test "$(url_list)" == "$IAC_URLS"
check "five curl calls, every one the exact modelled argv" test "$(calls_of curl)" -eq 5
check "one gh store, SENTRY_IAC_AUTH_TOKEN -R jikig-ai/soleur, no body flag" \
  test "$(grep -c '^gh secret set SENTRY_IAC_AUTH_TOKEN -R jikig-ai/soleur$' "$T/rec/calls")" -eq 1 -a "$(grep -c -- '--body' "$T/rec/calls")" -eq 0
check "gh store stdin is the token, byte-exact" stdin_is '^gh secret set SENTRY_IAC_AUTH_TOKEN ' "$TOKEN"
check "the repo secret's updatedAt moved" test "$(gh_updated SENTRY_IAC_AUTH_TOKEN)" != "2026-05-19T19:50:38Z"
check "exactly two Doppler writes, prd then prd_terraform, exact argv" test "$(dop_writes)" == "$DOP_WRITES_WANT"
check "Doppler prd write stdin is the token, byte-exact" stdin_is ' -c prd --no-interactive$' "$TOKEN"
check "Doppler prd_terraform write stdin is the token, byte-exact" stdin_is ' -c prd_terraform --no-interactive$' "$TOKEN"
check "Doppler prd holds the new value" dop_value_is prd "$TOKEN"
check "Doppler prd_terraform holds the new value" dop_value_is prd_terraform "$TOKEN"
check "an own-copy branch is not written" dop_value_is prd_beta "$OLD"
check "other prd configs classified by digest" line_is "$L_OTHER" '(no known reader in repo; not written): follow soleur/prd (now new): prd_alpha; own copy (still the old value; removal tracked in #12740): prd_beta; unreadable: prd_delta, prd_zeta'
check "all-three line printed" grep -q "$ALL_THREE" "$T/all"
check "no partial-state report" absent "$DO_NOT"
check "the CLI's all-secrets dump never reaches output" no_canary
check "token never in argv or output" no_leak
check "trap dir removed" trap_dir_gone
check "no stub refused anything" no_refusals
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

echo "== I7: the Doppler prd write fails after GitHub landed -> prd UNVERIFIED (it may have landed)"
setup_iac
STUB_DOP_SET_RC_prd=1 run_iac
check_exit 3
check "HOLD NEW: GitHub only" line_is "$L_NEW" "$T_GH"
check "UNVERIFIED: prd" line_is "$L_UNV" "$T_PRD"
check "UNCHANGED: prd_terraform" line_is "$L_OLD" "$T_PTF"
check "do NOT revoke the old token yet" grep -q "$DO_NOT" "$T/all"
check "no all-three line" absent "$ALL_THREE"
check "prd_terraform never written" test "$(dop_writes | grep -c prd_terraform || true)" -eq 0
check "the CLI's all-secrets dump never reaches output" no_canary
rm -rf "$T"

echo "== I8: the prd read-back does not match"
setup_iac
STUB_DOP_GET_CORRUPT_prd=1 run_iac
check_exit 3
check "HOLD NEW: GitHub only" line_is "$L_NEW" "$T_GH"
check "UNVERIFIED: prd" line_is "$L_UNV" "$T_PRD"
check "UNCHANGED: prd_terraform" line_is "$L_OLD" "$T_PTF"
check "do NOT revoke the old token yet" grep -q "$DO_NOT" "$T/all"
rm -rf "$T"

echo "== I9: the prd_terraform read-back fails -- a failed read is never a match"
setup_iac
STUB_DOP_GET_RC_prd_terraform=1 run_iac
check_exit 3
check "HOLD NEW: GitHub and prd" line_is "$L_NEW" "$T_GH; $T_PRD"
check "UNVERIFIED: prd_terraform" line_is "$L_UNV" "$T_PTF"
check "UNCHANGED: none" line_is "$L_OLD" '(none)'
check "no all-three line" absent "$ALL_THREE"
rm -rf "$T"

echo "== I9b: an EMPTY read-back with rc 0 is a read failure, not a mismatch"
setup_iac
STUB_DOP_GET_EMPTY_prd=1 run_iac
check_exit 3
check "UNVERIFIED: prd" line_is "$L_UNV" "$T_PRD"
check "reported as a read-back failure" grep -q 'soleur/prd read-back failed after the write' "$T/all"
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
check "names the missing config" grep -q 'soleur/prd_terraform is absent or not a prd branch config' "$T/err"
check "no store anywhere" no_stores
rm -rf "$T"

echo "== I10c: prd is not a root config -> 2"
setup_iac prd-not-root
run_iac
check "exit 2" test "$rc" -eq 2
check "names the reason" grep -q 'soleur/prd is absent or not a root config' "$T/err"
check "no store anywhere" no_stores
rm -rf "$T"

echo "== I10d: prd_terraform is a root config -> 2"
setup_iac ptf-root
run_iac
check "exit 2" test "$rc" -eq 2
check "no store anywhere" no_stores
rm -rf "$T"

echo "== I10e: the key is unreadable in prd_terraform before the run -> 2, nothing captured"
setup_iac
STUB_DOP_GET_RC_PRE_prd_terraform=1 run_iac
check "exit 2" test "$rc" -eq 2
check "names the unreadable config" grep -q 'SENTRY_IAC_AUTH_TOKEN is absent or unreadable in soleur/prd_terraform' "$T/err"
check "no store anywhere" no_stores
check "zero curl calls" test "$(calls_of curl)" -eq 0
rm -rf "$T"

echo "== I11: the GitHub write fails first -> revoke the NEW token, no Doppler write"
setup_iac
STUB_GH_SET_RC=1 run_iac
check_exit 1
check "revoke-the-NEW-token message" grep -q 'REVOKE THE NEW TOKEN' "$T/all"
check "zero Doppler writes" test -z "$(dop_writes)"
check "no partial-state report" absent "$DO_NOT"
rm -rf "$T"

echo "== I12: gh secret list fails after the write -> GitHub UNVERIFIED, no Doppler write"
setup_iac
STUB_GH_LIST_RC=1 run_iac
check_exit 3
check "UNVERIFIED: GitHub" line_is "$L_UNV" "$T_GH"
check "UNCHANGED: prd and prd_terraform" line_is "$L_OLD" "$T_PRD; $T_PTF"
check "zero Doppler writes" test -z "$(dop_writes)"
check "do NOT revoke the old token yet" grep -q "$DO_NOT" "$T/all"
rm -rf "$T"

echo "== I12b: gh secret list fails BEFORE the write -> nothing stored, revoke the NEW token"
setup_iac
STUB_GH_LIST_RC_PRE=1 run_iac
check_exit 1
check "says nothing was stored" grep -q 'failed before the write.*nothing was stored' "$T/all"
check "no store anywhere" no_stores
check "no partial-state report" absent "$DO_NOT"
rm -rf "$T"

echo "== I13: a hostile environment (Doppler host, proxies, TLS key log) reaches no child"
setup_iac
DOPPLER_API_HOST=http://127.0.0.1:1 HTTPS_PROXY=http://127.0.0.1:1 ALL_PROXY=http://127.0.0.1:1 \
  SSLKEYLOGFILE="$T/keylog" run_iac
check_exit 0
check "no stub refused anything" no_refusals
rm -rf "$T"

echo "== I14: gh secret set exits 0 but updatedAt never moves -> GitHub UNVERIFIED"
setup_iac
STUB_GH_SET_NOOP=1 run_iac
check_exit 3
check "UNVERIFIED: GitHub" line_is "$L_UNV" "$T_GH"
check "names the unchanged updatedAt" grep -q 'updatedAt did not change after the write' "$T/all"
check "zero Doppler writes" test -z "$(dop_writes)"
rm -rf "$T"

echo "== I15: SIGTERM during the prd write prints the partial-state report"
setup_iac
STUB_DOP_SET_SIGNAL_prd=1 run_iac
check_exit 143
check "says the store was interrupted" grep -q 'interrupted during the store' "$T/all"
check "HOLD NEW: GitHub only" line_is "$L_NEW" "$T_GH"
check "UNVERIFIED: prd (the write in flight)" line_is "$L_UNV" "$T_PRD"
check "UNCHANGED: prd_terraform" line_is "$L_OLD" "$T_PTF"
check "do NOT revoke the old token yet" grep -q "$DO_NOT" "$T/all"
check "trap dir removed" trap_dir_gone
check "prd_terraform never written" test "$(dop_writes | grep -c prd_terraform || true)" -eq 0
rm -rf "$T"

echo "== I16: prd and prd_terraform held different values before the run -> noted"
setup_iac
printf 'synthOLD2-%s' "$OLD" > "$T/dop/prd_terraform/SENTRY_IAC_AUTH_TOKEN"
run_iac
check_exit 0
check "the pre-run divergence is noted" grep -q 'held DIFFERENT values before this run' "$T/all"
rm -rf "$T"

echo "== H2: no other carriers -> success, nothing to classify, all-three line printed"
setup_iac no-carriers
run_iac
check_exit 0
check "other-config line is all (none)" line_is "$L_OTHER" '(no known reader in repo; not written): follow soleur/prd (now new): (none); own copy (still the old value; removal tracked in #12740): (none); unreadable: (none)'
check "all-three line printed" grep -q "$ALL_THREE" "$T/all"
rm -rf "$T"

echo "== P1: the iac EXPECTED_SCOPES equals ADR-031's stated scope set"
adr_scopes() { # the sorted JSON array behind ADR-031's `auth.scopes = [...]` (wrapped over lines)
  awk '/auth\.scopes = \[alerts:read/{f=1} f{printf "%s ", $0} f && /\]/{exit}' "$ADR031" \
    | sed -E 's/.*auth\.scopes = \[([^]]*)\].*/\1/' | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' \
    | grep -v '^$' | sort | jq -R -c -n '[inputs]'
}
script_scopes() { awk '/^  iac\)/{f=1} f && /EXPECTED_SCOPES=/{print; exit}' "$SCRIPT" | sed -E "s/.*EXPECTED_SCOPES='([^']*)'.*/\1/"; }
check "ADR-031 scope set == the script's iac EXPECTED_SCOPES" test -n "$(script_scopes)" -a "$(adr_scopes)" == "$(script_scopes)"

# Exact executed-assertion count: a row that stops running cannot pass silently. Reported
# with printf + exit, never through fail(), which this floor backstops.
EXPECTED_CASES=156
echo
echo "cases=$cases failures=$failures"
if [[ "$cases" -ne "$EXPECTED_CASES" ]]; then
  printf 'ASSERTION COUNT %s != expected %s -- a row was skipped or added without updating the count\n' "$cases" "$EXPECTED_CASES"; exit 1
fi
if [[ "$failures" -ne 0 ]]; then printf 'FAILED: %s of %s assertions\n' "$failures" "$cases"; exit 1; fi
exit 0
