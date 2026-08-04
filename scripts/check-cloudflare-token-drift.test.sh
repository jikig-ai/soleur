#!/usr/bin/env bash
# Tests the Cloudflare ACCESS SERVICE TOKEN arm of check-cloudflare-token-drift.sh.
#
# Background: the script's own header cites REGISTRY_PUSH_ACCESS_TOKEN_* as the first
# case that motivated it, but its enumeration regex was `CF_API_TOKEN[A-Z0-9_]*` — an
# anchored pattern that cannot match a key which does not begin with CF_API_TOKEN. So the
# script reported "0 dead" on a fleet where exactly that token had gone stale. A clean
# bill of health for a question that was never asked is worse than no script at all, and
# these tests exist to keep that specific shape from coming back.
#
# The verification arm was wrong too: an Access service token is a client-id/secret PAIR,
# and /user/tokens/verify with an `Authorization: Bearer` header is the API-TOKEN
# endpoint. It cannot say anything true about a pair.
#
# Method: `doppler` and `curl` are stubbed on PATH, so nothing here touches Cloudflare,
# Doppler, or the network. Every credential is SYNTHESIZED (cq-test-fixtures-synthesized-only)
# — the id/secret values below are structurally shaped like the real thing and are not,
# and have never been, valid anywhere.
#
# Run: bash scripts/check-cloudflare-token-drift.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$REPO_ROOT/scripts/check-cloudflare-token-drift.sh"

# /tmp is a machine-global 4 GiB tmpfs shared with every sibling worktree; a suite that
# builds sandboxes there has its verdicts turned into a function of another session's
# disk usage. Default to /var/tmp when invoked directly (test-all.sh already exports it).
export TMPDIR="${TMPDIR:-/var/tmp}"

# AMBIENT-CREDENTIAL HYGIENE. The SUT now takes its credential from DOPPLER_TOKEN and
# refuses to run without one, so a suite that inherits an operator's real DOPPLER_TOKEN /
# DOPPLER_CONFIG would (a) put a live credential on a stubbed child's environment and
# (b) make the "unset credential" cases unreachable — they would silently test the
# operator's laptop instead of the code. Every case declares its own credential through
# run_sut; nothing here may come from the environment.
unset DOPPLER_TOKEN DOPPLER_CONFIG

PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d) || { echo "FATAL: could not create sandbox"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
STUB_DIR="$TMP/bin"
mkdir -p "$STUB_DIR" || { echo "FATAL: could not create stub dir"; exit 2; }

# ---------------------------------------------------------------------------
# Synthesized fixtures. Access service-token ids are <32 hex>.access, and secrets are
# 64 hex — the real shape, so a future format check would exercise the same path. These
# specific values are invented.
# ---------------------------------------------------------------------------
FIX_ID="0123456789abcdef0123456789abcdef.access"
FIX_SECRET="fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
# The Doppler CREDENTIAL the SUT scans with. Shaped like a service-account token
# (`dp.sa.<40>`) so a future format check exercises the same path. Invented, and never
# valid anywhere. It doubles as the P11 sentinel: it must reach NO sink.
FIX_CRED="dp.sa.SYNTHETICNOTREALSYNTHETICNOTREAL0000"

# `doppler` stub. Reads its fixture world from two files so each case can reshape it
# without rewriting the stub:
#   $MOCK_CONFIGS  — one config name per line
#   $MOCK_SECRETS  — "<config>|<KEY>|<value>" per line
# NOTE ON FIXTURE CARDINALITY (the axis a mutation battery cannot see):
# this script exists because "5 of 7 configs stale after a dashboard roll". A suite whose
# every fixture holds ONE config cannot observe that requirement at all — measured:
# rewriting `for cfg in "${CONFIGS[@]}"` to `"${CONFIGS[0]}"` at any of the three loops
# left an 8/8 green suite while destroying the script's entire purpose. T9 below is the
# two-config case that kills all three of those mutants.
cat > "$STUB_DIR/doppler" <<'STUB'
#!/usr/bin/env bash
[[ -n "${MOCK_DOPPLER_LOG:-}" ]] && printf '%s\n' "$*" >> "$MOCK_DOPPLER_LOG"
# NFR1 ORDERING PROBE. How many `::add-mask::` directives had the SUT emitted by the time
# it first invoked the Doppler CLI? Written once, at the FIRST invocation. The sibling
# snapshot in the curl stub answers the same question for the first network PROBE; this one
# is what pins "masked BEFORE the first doppler invocation of any kind", which is the
# ordering NFR1 requires and the curl snapshot cannot see (every doppler read precedes it).
if [[ -n "${MOCK_MASK_SNAPSHOT_DOPPLER:-}" && ! -f "${MOCK_MASK_SNAPSHOT_DOPPLER}" && -n "${MOCK_SUT_STDOUT:-}" ]]; then
  _dseen=$(grep -c '::add-mask::' "${MOCK_SUT_STDOUT}" 2>/dev/null || true)
  printf '%s' "${_dseen:-0}" > "${MOCK_MASK_SNAPSHOT_DOPPLER}"
fi
# Credential and ambient-config observability, recorded for EVERY invocation.
# `set`/`unset` only — the VALUE is deliberately not written here, because this log is
# read by assertions whose whole point is that no credential value reaches a file.
[[ -n "${MOCK_DOPPLER_ENV_LOG:-}" ]] && \
  printf 'TOKEN=%s CONFIG=%s\n' "${DOPPLER_TOKEN:+set}" "${DOPPLER_CONFIG:+set}" >> "$MOCK_DOPPLER_ENV_LOG"
# THE STUB FAILS LOUDLY WITH NO EXPLICIT CREDENTIAL, and the real CLI does not — that
# asymmetry is the point. Given no token, real `doppler` falls back to the ambient login
# and answers confidently about a scope nobody asked for; the failure is silent and the
# verdict is wrong. A stub that also answered would make "the SUT delivers its credential
# explicitly" untestable, so the one observable difference between an explicit credential
# and an ambient one is manufactured here.
if [[ -z "${DOPPLER_TOKEN:-}" ]]; then
  echo "STUB ERROR: doppler invoked with no explicit DOPPLER_TOKEN — refusing to answer from an ambient credential" >&2
  exit 3
fi

# TOKEN->CONFIG BINDING FIXTURE. `$MOCK_TOKEN_BINDING` is a file of `token|config` lines.
# When set, this stub enforces the binding the REAL CLI enforces, measured 2026-08-03
# against live Doppler with ephemeral config-scoped tokens:
#
#   token bound to prd,  -c dev  -> exit 1, "This token does not have access to requested config 'dev'"
#   token bound to prd,  -c prd  -> the config's keys
#
# Without this the stub answers for ANY config given ANY token, so a fan-out whose 13
# credentials are all bound to ONE config reads 13 configs successfully and reports a
# confident 13/13 — the exact defect the per-config shape has to be able to detect. A stub
# that dispatches only on `$1` puts the fixture seam above the code under test.
#
# Unset => legacy behaviour: any token answers for any config. Every pre-#7234 case relies
# on that, and single-credential mode genuinely has no binding to assert.
_bound_cfg_for_token() {
  [[ -z "${MOCK_TOKEN_BINDING:-}" || ! -s "${MOCK_TOKEN_BINDING:-/nonexistent}" ]] && return 1
  grep -E "^${DOPPLER_TOKEN}\|" "$MOCK_TOKEN_BINDING" 2>/dev/null | head -1 | cut -d'|' -f2
  return 0
}
_assert_binding() { # $1 = requested config; echoes the real CLI's error and exits 1 on mismatch
  local _want="$1" _bound
  _bound=$(_bound_cfg_for_token) || return 0
  [[ -z "$_bound" ]] && { echo "doppler: Invalid token" >&2; exit 1; }
  if [[ "$_bound" != "$_want" ]]; then
    echo "This token does not have access to requested config '${_want}'" >&2
    exit 1
  fi
  return 0
}

case "${1:-}" in
  configs)
    # Enumeration failure injection: a NON-EMPTY credential that the API rejects (revoked,
    # expired, or scoped to nothing). Its stderr is the only line saying which, and the
    # SUT must not swallow it.
    if [[ -n "${MOCK_ENUM_FAIL:-}" ]]; then
      echo "doppler: ${MOCK_ENUM_FAIL}" >&2
      exit 1
    fi
    # A bound token's listing is silently scoped to itself (measured: one entry,
    # success, no error) — the property that made the old shape's narrowing invisible.
    if _b=$(_bound_cfg_for_token); then
      [[ -n "$_b" ]] && { printf '[{"name":"%s"}]\n' "$_b"; exit 0; }
      echo "doppler: Invalid token" >&2; exit 1
    fi
    printf '['
    _first=1
    while read -r c; do
      [[ -z "$c" ]] && continue
      [[ "$_first" == 1 ]] || printf ','
      printf '{"name":"%s"}' "$c"
      _first=0
    done < "$MOCK_CONFIGS"
    printf ']\n'
    ;;
  secrets)
    # `doppler secrets get KEY -p P -c CFG --plain` vs `doppler secrets -p P -c CFG --only-names`
    if [[ "${2:-}" == "get" ]]; then
      _key="$3"; _cfg=""
      # Positional scan: the flag order is fixed by the caller, but scanning is robust to
      # it changing, which a positional index would not be.
      for ((i=1; i<=$#; i++)); do
        [[ "${!i}" == "-c" ]] && { j=$((i+1)); _cfg="${!j}"; }
      done
      # Same hard error as the --only-names branch below, and for the same reason: a value
      # read with no explicit config grades the wrong config's bytes in production.
      if [[ -z "$_cfg" ]]; then
        echo "STUB ERROR: 'doppler secrets get ${_key}' invoked with no -c <config>" >&2
        exit 4
      fi
      _assert_binding "$_cfg"
      _v=$(grep -E "^${_cfg}\|${_key}\|" "$MOCK_SECRETS" 2>/dev/null | head -1 | cut -d'|' -f3-)
      [[ -n "$_v" ]] && printf '%s\n' "$_v"
      exit 0
    fi
    _cfg=""
    for ((i=1; i<=$#; i++)); do
      [[ "${!i}" == "-c" ]] && { j=$((i+1)); _cfg="${!j}"; }
    done
    # NO `-c` IS A HARD STUB ERROR. With DOPPLER_CONFIG unset in the SUT there is nothing
    # for an implicit bind to reach, but the real CLI would bind whatever the environment
    # carried and grade another config's bytes. A stub that answered anyway would let a
    # dropped `-c <cfg>` pass every verdict assertion in this file.
    if [[ -z "$_cfg" ]]; then
      echo "STUB ERROR: 'doppler secrets --only-names' invoked with no -c <config>" >&2
      exit 4
    fi
    _assert_binding "$_cfg"
    # Per-config read failure injection. This is N1's subtle form: a role that can
    # ENUMERATE configs but cannot READ their secrets. The config still lists.
    if [[ "${MOCK_UNREADABLE:-}" == "ALL" || ",${MOCK_UNREADABLE:-}," == *",${_cfg},"* ]]; then
      echo "doppler: you do not have access to config '${_cfg}'" >&2
      exit 1
    fi
    # Anchored: an unanchored `grep -F "prd|"` also matches `prd_terraform|…`, which would
    # silently bleed one config's keys into another the moment cardinality exceeds 1 —
    # exactly when the two-config cases below need it to be exact.
    grep -E "^${_cfg}\|" "$MOCK_SECRETS" 2>/dev/null | cut -d'|' -f2
    ;;
esac
exit 0
STUB
chmod +x "$STUB_DIR/doppler"

# `curl` stub. Records every invocation's full argv to $MOCK_CURL_LOG so the tests can
# assert HOW the token was presented, not merely what verdict came back — a verdict-only
# assertion would pass against an implementation that kept using the wrong endpoint and
# happened to get the right answer. $MOCK_HTTP_CODE drives the response.
# `curl` stub. Records argv to $MOCK_CURL_LOG so the tests can assert HOW a token was
# presented, not merely what verdict came back.
#
# It MODELS THE FLAGS, which the first version did not — and that omission was the
# suite's single largest blind spot. Measured: deleting `-o /dev/null -w '%{http_code}'`
# from the SUT left 8/8 green, while in production it makes `code` the response BODY,
# which for the tcp:// registry ingress is EMPTY — so `case "" in 200)` falls through and
# EVERY Access token reports DEAD on every release preflight. A stub whose correctness
# depends on a flag it ignores cannot see the flag being removed.
#
# Two response channels, because the two arms parse differently: the Access arm reads the
# `-w` status code, the API arm parses a JSON BODY. A stub that returned the status code
# as the body made the API arm's json.load() raise on every call, so it always printed
# DEAD — which meant a mutation forcing every API token to LIVE was invisible.
#
# It also MODELS THE ACCESS STAMP and `-D`, because the verdict is now drawn from the
# response HEADERS, not the status code. A stub that emitted no headers would make every
# response indistinguishable from an ungated one, so every case would grade `gate-absent`
# — the stub would decide the verdict instead of observing it.
#
# Shapes are the MEASURED ones (2026-08-01, real hosts):
#   uncredentialed -> 403 + cf-access-aud + cf-access-domain   (Access denial page)
#   admitted       -> 200, zero-byte body, NO cf-access-*       (edge answered)
# so the stub's defaults reproduce production rather than a convenient invention.
#
# And it MODELS curl's EXIT STATUS. The old stub ended `exit 0` unconditionally, which is
# how `code=$(curl ... || printf '000')` shipped: real curl prints its -w output AND exits
# non-zero on a transport failure, concatenating to `000000` / `200000`. A stub that
# cannot exit non-zero cannot see that.
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
[[ -n "${MOCK_CURL_LOG:-}" ]] && printf '%s\n' "$*" >> "$MOCK_CURL_LOG"
# curl is given NO env prefix by the SUT, so it sees whatever the SUT's own environment
# still holds. That makes it the instrument for "the credential was snapshotted and both
# Doppler variables were then unset": if the SUT had kept relying on an ambient
# DOPPLER_TOKEN / DOPPLER_CONFIG, this child would inherit them.
[[ -n "${MOCK_CURL_ENV_LOG:-}" ]] && \
  printf 'TOKEN=%s CONFIG=%s\n' "${DOPPLER_TOKEN:+set}" "${DOPPLER_CONFIG:+set}" >> "$MOCK_CURL_ENV_LOG"
# ORDERING INSTRUMENT for ::add-mask::. At the moment of the FIRST probe, record how many
# mask directives the SUT had already written to its (redirected, unbuffered) stdout.
# Presence alone cannot distinguish "masked before anything was probed" from "masked on
# the way past" — this reads the real interleaving instead of a proxy for it.
if [[ -n "${MOCK_MASK_SNAPSHOT:-}" && ! -f "${MOCK_MASK_SNAPSHOT}" && -n "${MOCK_SUT_STDOUT:-}" ]]; then
  _seen=$(grep -c '::add-mask::' "${MOCK_SUT_STDOUT}" 2>/dev/null || true)
  printf '%s' "${_seen:-0}" > "${MOCK_MASK_SNAPSHOT}"
fi
_want_code=0
_outfile=""
_hdrfile=""
_credentialed=0
_host=""
for ((i=1; i<=$#; i++)); do
  case "${!i}" in
    -w) j=$((i+1)); [[ "${!j}" == *'%{http_code}'* ]] && _want_code=1 ;;
    -o) j=$((i+1)); _outfile="${!j}" ;;
    -D) j=$((i+1)); _hdrfile="${!j}" ;;
    -H) j=$((i+1)); [[ "${!j}" == CF-Access-Client-Id:* ]] && _credentialed=1 ;;
    https://*) _host="${!i}"; _host="${_host#https://}"; _host="${_host%%/*}" ;;
  esac
done

# Per-host override file: "<host>|<control_code>|<control_stamped>|<cred_code>|<cred_stamped>".
# Without this a single MOCK_HTTP_CODE governs every host, which makes a fixture carrying
# two bases structurally unable to express "this host admits, that one rejects" — the axis
# the previous suite could not test at all.
# Field order: host|c_code|c_stamp|r_code|r_stamp|r_mitigated|c_access_redirect
# The last two model the two refusal shapes that carry NO cf-access-* header and are
# therefore invisible to the stamp alone: Cloudflare's own block/challenge (cf-mitigated)
# and an Access identity-policy redirect to the IdP login (Location).
_c_code=""; _c_stamp=""; _r_code=""; _r_stamp=""; _r_mitig=""; _c_redir=""
if [[ -n "${MOCK_HOSTS:-}" && -f "${MOCK_HOSTS}" && -n "$_host" ]]; then
  _line=$(grep -E "^${_host}\|" "$MOCK_HOSTS" 2>/dev/null | head -1)
  if [[ -n "$_line" ]]; then
    IFS='|' read -r _ _c_code _c_stamp _r_code _r_stamp _r_mitig _c_redir <<< "$_line"
  fi
fi
: "${_r_mitig:=0}"
: "${_c_redir:=0}"
: "${_c_code:=${MOCK_CONTROL_CODE:-403}}"
: "${_c_stamp:=${MOCK_CONTROL_STAMPED:-1}}"
: "${_r_code:=${MOCK_HTTP_CODE:-200}}"
# The credentialed stamp is NEVER inferred from the status code. It used to default
# `403 -> stamped, else -> unstamped`, and that inference made the suite tautological: a
# case setting only MOCK_HTTP_CODE produced the same verdict under a STAMP rule and under
# a STATUS rule, so six cases could not tell the two apart. Measured — inserting
# `elif [[ "$PROBE_CODE" == 200 ]]; then LIVE` ahead of the stamp test, i.e. restoring the
# exact instrument this PR exists to remove, passed 27/27.
#
# Default is now UNSTAMPED, and any case asserting a rejection must say so explicitly.
# That makes the stamp an INPUT the case controls rather than a shadow of the code.
: "${_r_stamp:=${MOCK_CRED_STAMPED:-0}}"

if [[ "$_credentialed" == 1 ]]; then _code="$_r_code"; _stamped="$_r_stamp"
else _code="$_c_code"; _stamped="$_c_stamp"
fi

# Per-CREDENTIAL override: "<client-id>|<code>|<stamped>". Without this the stub keys on
# HOST only, so every config in a fixture necessarily gets the same answer — and the suite
# was structurally unable to express the incident that motivated this script ("5 of 7
# configs stale after a dashboard roll"). Measured: dropping the id/secret from the memo
# cache key passed 27/27, while under a credential-aware fixture it turned
# `live: 1 dead: 1` into `live: 2 dead: 0` — a clean bill of health on the exact failure.
if [[ "$_credentialed" == 1 && -n "${MOCK_CREDS:-}" && -f "${MOCK_CREDS}" ]]; then
  _cid=""
  for ((i=1; i<=$#; i++)); do
    [[ "${!i}" == CF-Access-Client-Id:* ]] && _cid="${!i#CF-Access-Client-Id: }"
  done
  _cline=$(grep -F "${_cid}|" "$MOCK_CREDS" 2>/dev/null | head -1)
  if [[ -n "$_cline" ]]; then
    IFS='|' read -r _ _code _stamped <<< "$_cline"
  fi
fi

if [[ "$_credentialed" == 1 ]]; then _mitig="$_r_mitig"; _redir=0
else _mitig=0; _redir="$_c_redir"
fi

if [[ -n "$_hdrfile" ]]; then
  {
    printf 'HTTP/2 %s \r\n' "$_code"
    printf 'server: cloudflare\r\n'
    if [[ "$_stamped" == 1 ]]; then
      printf 'cf-access-domain: %s\r\n' "$_host"
      printf 'cf-access-aud: 0000000000000000000000000000000000000000000000000000000000000000\r\n'
    fi
    [[ "$_mitig" == 1 ]] && printf 'cf-mitigated: challenge\r\n'
    [[ "$_redir" == 1 ]] && printf 'location: https://example.cloudflareaccess.com/cdn-cgi/access/login/%s\r\n' "$_host"
    printf '\r\n'
  } > "$_hdrfile" 2>/dev/null || true
fi

_body="${MOCK_HTTP_BODY:-}"
if [[ -n "$_outfile" ]]; then
  printf '%s' "$_body" > "$_outfile" 2>/dev/null || true
else
  printf '%s' "$_body"
fi
[[ "$_want_code" == 1 ]] && printf '%s' "$_code"
# Transport failure: curl still emits -w, then exits non-zero. Both halves matter.
exit "${MOCK_CURL_EXIT:-0}"
STUB
chmod +x "$STUB_DIR/curl"

# `mktemp` stub. Only fails when a case asks it to, otherwise delegates to the real one.
# Without this the `detector-env` branch is UNREACHABLE from the suite, and mapping a
# local disk failure back onto "the host is unreachable" passed the whole battery.
cat > "$STUB_DIR/mktemp" <<'STUB'
#!/usr/bin/env bash
[[ "${MOCK_MKTEMP_FAIL:-0}" == 1 ]] && exit 1
exec /usr/bin/mktemp "$@"
STUB
chmod +x "$STUB_DIR/mktemp"

# Run the SUT against a fixture world.
#
# Called DIRECTLY, never as `rc=$(run_sut ...)`. Command substitution runs the function in
# a SUBSHELL, so every effect except stdout is discarded — the artifact paths this sets
# would come back empty in the parent and every assertion would grep a nonexistent file
# and "fail" for a reason that has nothing to do with the code under test. (Measured
# here: 0/8, with `grep: : No such file or directory` on every line.) A function that
# both returns a value AND sets caller-visible state cannot be called that way; this one
# sets globals and reports rc through $RC.
#
# Paths are derived from the case label rather than $RANDOM so a failing case's artifacts
# are findable by name after the run.
RC=""
OUT=""
CURL_LOG=""
DOPPLER_LOG=""
DOPPLER_ENV_LOG=""
CURL_ENV_LOG=""
GH_OUTPUT=""
MASK_SNAPSHOT=""
run_sut() {
  local label="$1" http_code="$2" secrets_body="$3" configs_body="${4:-prd}" only_arg="${5:-}"
  local cfgs="$TMP/$label.configs" secs="$TMP/$label.secrets"
  OUT="$TMP/$label.out"; CURL_LOG="$TMP/$label.curl"; DOPPLER_LOG="$TMP/$label.doppler"
  DOPPLER_ENV_LOG="$TMP/$label.dopplerenv"; CURL_ENV_LOG="$TMP/$label.curlenv"
  GH_OUTPUT="$TMP/$label.ghoutput"; MASK_SNAPSHOT="$TMP/$label.masksnap"
  MASK_SNAPSHOT_DOPPLER="$TMP/$label.masksnapdop"
  : > "$DOPPLER_LOG"
  : > "$DOPPLER_ENV_LOG"
  : > "$CURL_ENV_LOG"
  : > "$GH_OUTPUT"
  rm -f "$MASK_SNAPSHOT" "$MASK_SNAPSHOT_DOPPLER"
  printf '%s\n' "$configs_body" > "$cfgs" || { echo "FATAL: fixture write failed"; exit 2; }
  printf '%s\n' "$secrets_body" > "$secs" || { echo "FATAL: fixture write failed"; exit 2; }
  : > "$CURL_LOG"
  # THE CREDENTIAL, declared per case rather than inherited. `unset` and `empty` are
  # DIFFERENT states to a shell and the same state to the Doppler CLI (which treats an
  # empty value as absent and rebinds to the ambient credential), so both are expressible.
  local -a _cred=()
  case "${MOCK_CRED_MODE:-set}" in
    set)   _cred=(DOPPLER_TOKEN="${MOCK_TOKEN_VALUE:-$FIX_CRED}") ;;
    empty) _cred=(DOPPLER_TOKEN=) ;;
    unset) _cred=() ;;
    # #7234 fan-out modes. `map` is the shipped shape; `map_empty` is the merge->apply
    # window (secret declared, not yet published) and must land in the SAME arm as
    # `unset`, which is the property D3 pins by selecting on -n rather than definedness.
    map)       _cred=(DOPPLER_TOKEN_MAP="${MOCK_TOKEN_MAP:-}") ;;
    map_empty) _cred=(DOPPLER_TOKEN_MAP=) ;;
    both)      _cred=(DOPPLER_TOKEN_MAP="${MOCK_TOKEN_MAP:-}" DOPPLER_TOKEN="${MOCK_TOKEN_VALUE:-$FIX_CRED}") ;;
    *)     echo "FATAL: unknown MOCK_CRED_MODE '${MOCK_CRED_MODE:-}'"; exit 2 ;;
  esac
  # An AMBIENT DOPPLER_CONFIG, set deliberately. The SUT must unset it so no child can
  # inherit it and no read site can bind it implicitly.
  local -a _ambient=()
  [[ -n "${MOCK_AMBIENT_CONFIG:-}" ]] && _ambient=(DOPPLER_CONFIG="$MOCK_AMBIENT_CONFIG")
  # `env -u` first: the suite unsets both variables at file scope, but a direct invocation
  # from an operator shell that exported them would otherwise leak a real credential into
  # every case.
  # shellcheck disable=SC2086
  env -u DOPPLER_TOKEN -u DOPPLER_CONFIG -u DOPPLER_TOKEN_MAP \
  ${_cred[@]+"${_cred[@]}"} ${_ambient[@]+"${_ambient[@]}"} \
  MOCK_CONFIGS="$cfgs" MOCK_SECRETS="$secs" \
  MOCK_HTTP_CODE="$http_code" MOCK_CURL_LOG="$CURL_LOG" \
  MOCK_HTTP_BODY="${MOCK_HTTP_BODY:-}" \
  MOCK_CONTROL_CODE="${MOCK_CONTROL_CODE:-403}" \
  MOCK_CONTROL_STAMPED="${MOCK_CONTROL_STAMPED:-1}" \
  MOCK_CRED_STAMPED="${MOCK_CRED_STAMPED:-}" \
  MOCK_CURL_EXIT="${MOCK_CURL_EXIT:-0}" \
  MOCK_HOSTS="${MOCK_HOSTS:-}" \
  MOCK_CREDS="${MOCK_CREDS:-}" \
  MOCK_MKTEMP_FAIL="${MOCK_MKTEMP_FAIL:-0}" \
  MOCK_ENUM_FAIL="${MOCK_ENUM_FAIL:-}" \
  MOCK_UNREADABLE="${MOCK_UNREADABLE:-}" \
  MOCK_TOKEN_BINDING="${MOCK_TOKEN_BINDING:-}" \
  MOCK_DOPPLER_LOG="$DOPPLER_LOG" \
  MOCK_DOPPLER_ENV_LOG="$DOPPLER_ENV_LOG" \
  MOCK_CURL_ENV_LOG="$CURL_ENV_LOG" \
  MOCK_SUT_STDOUT="$OUT" \
  MOCK_MASK_SNAPSHOT="$MASK_SNAPSHOT" \
  MOCK_MASK_SNAPSHOT_DOPPLER="$MASK_SNAPSHOT_DOPPLER" \
  GITHUB_ACTIONS="${MOCK_GITHUB_ACTIONS:-}" \
  GITHUB_OUTPUT="$GH_OUTPUT" \
  APP_DOMAIN_BASE="soleur.ai" \
  PATH="$STUB_DIR:$PATH" \
    bash "$SUT" $only_arg > "$OUT" 2>&1
  RC=$?
}

# Count credentialed vs control probes from the recorded argv. The cache promise ("verify
# each distinct pair once") had no instrument at all before this, which is why both memo
# caches could be dead code through every green run.
# `|| true`, NOT `|| printf '0'`: grep -c PRINTS 0 and EXITS 1 on no match, so the printf
# form concatenates to "00" and every `== "0"` comparison fails. That is the same
# print-and-fail shape as curl's `-w` output that this suite pins in the SUT (T20) —
# reproduced here in the helper written to measure it.
cred_probes()    { grep -c 'CF-Access-Client-Id' "$CURL_LOG" 2>/dev/null || true; }
# CONTROL probes are the ones WITHOUT credentials. The first version of this counted
# `grep -c 'https://'` — every probe of either kind — so it could not have measured what
# its name claimed even if a case had called it. It was also defined and never called.
control_probes() { grep -cv 'CF-Access-Client-Id' "$CURL_LOG" 2>/dev/null || true; }

echo "=== check-cloudflare-token-drift: Access service-token arm ==="
echo ""

ACCESS_FIXTURE="prd|REGISTRY_PUSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|REGISTRY_PUSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}"

# T1 — the regression that motivates the whole change. The key must be ENUMERATED at all.
# Asserted via the curl log rather than the verdict: if enumeration silently misses the
# key, the script reports 0 live / 0 dead and exits 0, which is indistinguishable from a
# healthy fleet by exit code alone. That indistinguishability IS the bug.
echo "T1: REGISTRY_PUSH_ACCESS_TOKEN_* is enumerated (the key the old regex could not match)"
run_sut t1 200 "$ACCESS_FIXTURE"
if grep -qF 'CF-Access-Client-Id' "$CURL_LOG"; then
  pass "the Access token was actually probed (old enumeration regex could not reach it)"
else
  fail "REGISTRY_PUSH_ACCESS_TOKEN_* was never probed — enumeration missed it (curl log empty)"
fi

# T2 — LIVE verdict: a 200 from the protected hostname means Access accepted the pair.
echo "T2: 200 from the Access-protected hostname -> LIVE, exit 0"
run_sut t2 200 "$ACCESS_FIXTURE"
if [[ "$RC" == "0" ]] && grep -qE 'live entries: [1-9]' "$OUT" && grep -qE 'dead entries: 0' "$OUT"; then
  pass "200 -> LIVE, exit 0"
else
  fail "200 should be LIVE with exit 0 (rc=$RC): $(grep -E 'live entries' "$OUT" || true)"
fi

# T3 — DEAD verdict: 403 is Access refusing the pair, which is the stale-rotation shape.
echo "T3: 403 from the Access-protected hostname -> DEAD, exit 1"
MOCK_CRED_STAMPED=1 run_sut t3 403 "$ACCESS_FIXTURE"
if [[ "$RC" == "1" ]] && grep -qE 'dead entries: [1-9]' "$OUT" && grep -qF 'REGISTRY_PUSH_ACCESS_TOKEN' "$OUT"; then
  pass "403 -> DEAD, exit 1, and the report names the key"
else
  fail "403 should be DEAD with exit 1 and name the key (rc=$RC)"
fi

# T4 — the pair is presented as Access headers, NOT as a Bearer API token. The original
# verify_value() used /user/tokens/verify with `Authorization: Bearer`, which is the
# API-token endpoint and cannot say anything true about a client-id/secret pair. Pinning
# the request SHAPE is what stops a future edit from quietly routing this family back
# through the wrong endpoint while the verdicts still look plausible.
echo "T4: the pair is presented as CF-Access-Client-Id/-Secret against the protected host"
run_sut t4 200 "$ACCESS_FIXTURE"
_t4=1
grep -qF "CF-Access-Client-Id: ${FIX_ID}" "$CURL_LOG" || _t4=0
grep -qF "CF-Access-Client-Secret: ${FIX_SECRET}" "$CURL_LOG" || _t4=0
grep -qF 'https://registry.soleur.ai/' "$CURL_LOG" || _t4=0
grep -qF 'user/tokens/verify' "$CURL_LOG" && _t4=0
if [[ "$_t4" == "1" ]]; then
  pass "presented as Access headers to the protected hostname; the Bearer API-token endpoint is not used for this family"
else
  fail "must present CF-Access-Client-Id/-Secret to https://registry.soleur.ai/ and NOT hit user/tokens/verify"
fi

# T5 — fail CLOSED on a non-200/403 response. A timeout or 5xx means this script did not
# LEARN the token is good, and "did not learn" must never render as LIVE. Every
# silent-green bug in this area has that same shape.
# T5 — fail-closed on a probe that measured nothing. The ASSERTION CHANGED with the
# Access-stamp rewrite and the change is the point: this used to require `dead entries:
# >= 1`, i.e. an unreachable host rendered the credential STALE. That is a cause nothing
# measured, and the DEAD section's remedy is "set the live value on the prd ROOT config"
# — so a DNS blip instructed the operator to overwrite a healthy credential across every
# config that inherits it. Fail-closed is preserved (exit 1, never LIVE); what changed is
# that it now fails closed to UNVERIFIABLE, which carries a "do NOT rotate" remedy.
echo "T5: a probe that got no answer is NOT live and NOT stale (fail closed, no false cause)"
MOCK_CURL_EXIT=7 run_sut t5 000 "$ACCESS_FIXTURE"
_t5=1
[[ "$RC" == "1" ]] || _t5=0
grep -qE 'live entries: 0' "$OUT" || _t5=0
grep -qE 'unverifiable: [1-9]' "$OUT" || _t5=0
grep -q 'STALE' "$OUT" && _t5=0
if [[ "$_t5" == "1" ]]; then
  pass "unreachable -> UNVERIFIABLE, exit 1, and never under the STALE heading"
else
  fail "an unreachable probe must fail closed WITHOUT claiming the credential is stale — the STALE remedy overwrites the ROOT config every branch inherits (rc=$RC)"
fi

# T6 — a half-propagated rotation. One half present authenticates as nothing, and is a
# distinct, worse state than the token being absent; it must be reported, not skipped.
echo "T6: only one half of the pair present -> reported DEAD"
run_sut t6 200 "prd|REGISTRY_PUSH_ACCESS_TOKEN_ID|${FIX_ID}"
if [[ "$RC" == "1" ]] && grep -qF 'only one half present' "$OUT"; then
  pass "half-present pair reported explicitly"
else
  fail "a pair with only one half present must be reported DEAD (rc=$RC)"
fi

# T7 — an enumerated token with no hostname mapping is UNVERIFIABLE, not LIVE. This is
# the fail-closed property for the script's own coverage: a newly-added Access token
# family is surfaced as a gap rather than silently counted healthy, which is exactly the
# failure mode being fixed, one level up.
echo "T7: an enumerated token with no hostname mapping fails closed, not silently LIVE"
run_sut t7 200 "prd|SOMETHING_NEW_ACCESS_TOKEN_ID|${FIX_ID}
prd|SOMETHING_NEW_ACCESS_TOKEN_SECRET|${FIX_SECRET}"
_t7=1
[[ "$RC" == "1" ]] || _t7=0
grep -qF 'UNVERIFIABLE' "$OUT" || _t7=0
grep -qF 'add a hostname mapping' "$OUT" || _t7=0
# The half with teeth: an unverifiable key must NOT be reported as a stale credential.
# Doing so sends an operator to rotate a healthy token — a different false claim, and the
# same name-an-unmeasured-cause defect this PR exists to drain. Measured before the fix:
# the row printed under "STALE — these configs hold a token value Cloudflare no longer
# accepts" with "set the live value on the prd ROOT config" as its remedy.
grep -qE 'STALE.*\n?.*SOMETHING_NEW' "$OUT" && _t7=0
awk '/^STALE/{s=1} /^UNVERIFIABLE/{s=0} s && /SOMETHING_NEW/{found=1} END{exit !found}' "$OUT" && _t7=0
if [[ "$_t7" == "1" ]]; then
  pass "unmappable token reported as UNVERIFIABLE with a detector-side remedy, never as STALE"
else
  fail "an unmappable Access token must exit 1, print under UNVERIFIABLE, and never appear under STALE (rc=$RC)"
fi

# T9 — the cardinality case. Every fixture above holds ONE config, which cannot observe
# the requirement this script exists for ("5 of 7 configs stale after a dashboard roll").
# Measured: with only single-config fixtures, rewriting any of the three `for cfg in
# "${CONFIGS[@]}"` loops to `"${CONFIGS[0]}"` left the suite 8/8 green.
echo "T9: a token stale in ONE config of TWO is found, and the report names that config"
MOCK_CRED_STAMPED=1 run_sut t9 403 "prd|REGISTRY_PUSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|REGISTRY_PUSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd_terraform|REGISTRY_PUSH_ACCESS_TOKEN_ID|${FIX_ID}
prd_terraform|REGISTRY_PUSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}" $'prd\nprd_terraform'
if [[ "$RC" == "1" ]] && grep -qE 'configs scanned: 2' "$OUT" && grep -qE 'dead entries: 2' "$OUT"; then
  pass "both configs scanned and both dead entries reported (single-config loops would report 1)"
else
  fail "a two-config fleet must be scanned in full (rc=$RC): $(grep -E 'configs scanned|dead entries' "$OUT" | tr '\n' ' ')"
fi

# T10 — the non-Cloudflare lookalike. This is the live defect: the enumeration matched
# X_ACCESS_TOKEN_SECRET (an X/Twitter OAuth secret in 11 of 13 real configs), derived base
# X_ACCESS_TOKEN, and rendered a FABRICATED X_ACCESS_TOKEN_ID/_SECRET row — a credential
# that has never existed — into a twice-daily ops email. The pair requirement is what
# discriminates: no `_ID` half anywhere in the fleet means it is not an Access pair.
echo "T10: a *_ACCESS_TOKEN_SECRET with no _ID half is NOT treated as a Cloudflare pair"
run_sut t10 200 "prd|X_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd|REGISTRY_PUSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|REGISTRY_PUSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}"
if [[ "$RC" == "0" ]] && ! grep -qF 'X_ACCESS_TOKEN' "$OUT"; then
  pass "secret-only vendor key ignored; no fabricated _ID/_SECRET row, exit 0"
else
  fail "a *_ACCESS_TOKEN_SECRET with no _ID must be ignored, not reported (rc=$RC): $(grep -F 'X_ACCESS_TOKEN' "$OUT" | head -1)"
fi

# T11 — `--only` is the release preflight's only argument and had zero coverage.
# A filter matching nothing must NOT exit 0: the caller prints "verified live" on 0, so a
# renamed key would produce a clean bill of health for a question never asked. This suite's
# own header calls that indistinguishability "the bug".
echo "T11: --only matching no key is a coverage gap (exit 2), not a clean bill of health"
run_sut t11 200 "prd|REGISTRY_PUSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|REGISTRY_PUSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}" prd "--only NOSUCHFAMILY"
if [[ "$RC" == "2" ]] && grep -qF 'COVERAGE GAP' "$OUT"; then
  pass "--only matching nothing exits 2 and says nothing was checked"
else
  fail "--only with no matches must exit 2, not report clean (rc=$RC)"
fi

# T12 — and the positive direction: --only must actually scope, not silently no-op.
echo "T12: --only scopes the scan to the named family"
run_sut t12 200 "prd|REGISTRY_PUSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|REGISTRY_PUSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd|CF_API_TOKEN_DNS_EDIT|synthetic-not-real" prd "--only REGISTRY_PUSH_ACCESS_TOKEN"
if grep -qF 'CF-Access-Client-Id' "$CURL_LOG" && ! grep -qF 'user/tokens/verify' "$CURL_LOG"; then
  pass "--only probed the Access pair and did NOT probe the excluded API token"
else
  fail "--only must scope the scan: expected the Access probe and no API-token probe"
fi

# T8 — the pre-existing API-token family still works. The Access arm is additive; a
# change that fixed one family by breaking the other would be a net loss.
echo "T8: the CF_API_TOKEN* family is unaffected (Bearer verify still used for it)"
run_sut t8 200 "prd|CF_API_TOKEN_DNS_EDIT|synthetic-api-token-value-not-real"
if grep -qF 'user/tokens/verify' "$CURL_LOG" && grep -qF 'Authorization: Bearer' "$CURL_LOG"; then
  pass "API tokens still verified as Bearer against /user/tokens/verify"
else
  fail "the CF_API_TOKEN* arm must still use the Bearer /user/tokens/verify endpoint"
fi

# T13 — the API-token family's VERDICT, not just its request shape. T8 asserts the Bearer
# endpoint is used; nothing asserted what the answer means. With the old stub returning the
# status code as the response BODY, the arm's json.load() raised on every call and always
# printed DEAD — so a mutation hardcoding LIVE for every Cloudflare API token was
# invisible, in the family the script already claimed to cover.
echo "T13: CF_API_TOKEN* verdict follows Cloudflare's answer (success true/false)"
MOCK_HTTP_BODY='{"success":true}' run_sut t13a 200 "prd|CF_API_TOKEN_DNS_EDIT|synthetic-not-real"
_t13=1
[[ "$RC" == "0" ]] || _t13=0
grep -qE 'live entries: 1' "$OUT" || _t13=0
MOCK_HTTP_BODY='{"success":false}' run_sut t13b 200 "prd|CF_API_TOKEN_DNS_EDIT|synthetic-not-real"
[[ "$RC" == "1" ]] || _t13=0
grep -qE 'dead entries: 1' "$OUT" || _t13=0
if [[ "$_t13" == "1" ]]; then
  pass "success:true -> LIVE exit 0; success:false -> DEAD exit 1"
else
  fail "the API-token verdict must track Cloudflare's success field in BOTH directions"
fi

# T14 — --json-file exists so ONE scan can serve two consumers: the run log needs the
# human report (which remediation applies), the caller needs counts it can branch an
# operator email on. The caller branches three ways on this file, and the wrong branch
# sends an operator to rotate a healthy credential — so the file's presence, its
# parseability, and the coexistence with stdout are all load-bearing.
echo "T14: --json-file writes the verdict AND still prints the human report"
JF="$TMP/t14.json"
MOCK_CRED_STAMPED=1 run_sut t14 403 "$ACCESS_FIXTURE" prd "--json-file $JF"
# The human report is what distinguishes --json-file from --json. Without this assertion,
# an implementation that silently behaved like --json (JSON on stdout, no report) would
# pass every other check here.
if grep -qF 'Cloudflare token drift check' "$OUT"; then
  pass "--json-file still prints the human report to stdout"
else
  fail "--json-file must NOT suppress the human report (that is what --json is for)"
fi
if [[ -s "$JF" ]] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d["dead"] >= 1 else 1)' "$JF"; then
  pass "--json-file wrote a parseable verdict carrying the DEAD count"
else
  fail "--json-file must write parseable JSON with the dead count (got: $(head -c 120 "$JF" 2>/dev/null || echo '<no file>'))"
fi
# Fail-closed on an unwritable path. A missing verdict file makes the caller take its
# could-not-determine arm, so a silent write failure would report a wrong cause rather
# than no cause — the defect class this script exists to prevent.
                                                                                     # T14c
# THE PRODUCER SIDE OF `configs`. The consumer suite
# (plugins/soleur/test/token-drift-workflow-causes.test.sh) pins the workflow's parsing of
# this field against hand-written JSON fixtures, which cannot observe what the DETECTOR
# actually writes. Measured: replacing `"${#CONFIGS[@]}"` in emit_json with the literal
# `"1"` — every scan forever reporting single-config, filing the coverage issue and
# hedging every email — left BOTH suites fully green, as did deleting the `"configs":`
# key outright. The field this PR exists to add was pinned by nothing.
#
# TWO fixture sizes, because a one-size fixture cannot distinguish a real count from a
# hardcoded one: with a single 1-config case, the literal `"1"` mutation passes.
echo "T14c: --json-file reports the NUMBER OF CONFIGS ENUMERATED, not a constant"
T14C_OK=1
for _n_cfg in 1 3; do
  case "$_n_cfg" in
    1) _cfg_body='prd' ;;
    3) _cfg_body=$'prd\nprd_terraform\ndev' ;;
  esac
  JF3="$TMP/t14c-${_n_cfg}.json"
  MOCK_CRED_STAMPED=1 run_sut "t14c${_n_cfg}" 403 "$ACCESS_FIXTURE" "$_cfg_body" "--json-file $JF3"
  _got=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("configs","<absent>"))' "$JF3" 2>/dev/null || echo '<unparseable>')
  if [[ "$_got" != "$_n_cfg" ]]; then
    T14C_OK=0
    echo "    ${_n_cfg} config(s) enumerated but the verdict reported configs=${_got}"
  fi
done
if [[ "$T14C_OK" == "1" ]]; then
  pass "configs tracks the enumerated config count across fixture sizes (1 and 3)"
else
  fail "the verdict's 'configs' field does not track the configs actually enumerated. Every consumer's coverage signal is derived from this number, so a constant here makes the whole fan-out-coverage ladder report a fiction — in the confident direction if the constant is >= 2"
fi

echo "T14b: --json-file on an unwritable path exits 2 rather than continuing silently"
run_sut t14b 200 "$ACCESS_FIXTURE" prd "--json-file $TMP/no-such-dir/x.json"
if [[ "$RC" == "2" ]]; then
  pass "unwritable --json-file path exits 2"
else
  fail "unwritable --json-file path must exit 2, got rc=$RC"
fi

# ---------------------------------------------------------------------------
# T15-T24 — the ACCESS-STAMP arm (replaces the status-code arm removed with #7127).
#
# What is being pinned: the verdict comes from whether Cloudflare Access's own denial
# stamp (cf-access-aud / cf-access-domain) is still on the response once credentials are
# attached — NOT from the status code.
#
# The predecessor graded 5xx as LIVE on the theory that an admitted request reaches
# cloudflared, which then fails to speak HTTP to sshd. MEASURED 2026-08-01 against
# registry.soleur.ai with a live credential: the admitted response is HTTP 200, zero-byte
# body, no cf-access-* header. tunnel.tf records that ssh:// and tcp:// are the same
# raw-TCP service type, so ssh.<base> answers the same way — the 5xx arm could never fire
# and 200 fell to the catch-all, trading DEAD-forever for UNVERIFIABLE-forever. T15 is
# that case, and it is the one the previous suite had no test for.
# ---------------------------------------------------------------------------
CI_SSH_FIXTURE="prd|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}"

echo "T15: admitted probe answers 200 with NO Access stamp -> LIVE"
run_sut t15 200 "$CI_SSH_FIXTURE"
if [[ "$RC" == "0" ]] && grep -qE 'live entries: 1' "$OUT" && grep -qE 'dead entries: 0' "$OUT"; then
  pass "an empty 200 with the stamp gone grades LIVE — the measured admitted shape"
else
  fail "the MEASURED admitted response (200, no cf-access-*) must grade LIVE; a rule that cannot accept it reports a healthy token unverifiable forever (rc=$RC)"
fi

echo "T16: credentials still met Access's denial page -> DEAD"
MOCK_CRED_STAMPED=1 run_sut t16 403 "$CI_SSH_FIXTURE"
if [[ "$RC" == "1" ]] && grep -qE 'dead entries: 1' "$OUT"; then
  pass "a stamped response with credentials attached grades DEAD"
else
  fail "a stamped 403 WITH credentials means Access refused them — must stay DEAD (rc=$RC)"
fi

echo "T17: an unstamped 403 (WAF/bot-fight in FRONT of Access) is NOT a stale credential"
MOCK_CRED_STAMPED=0 run_sut t17 403 "$CI_SSH_FIXTURE"
if [[ "$RC" != "0" ]] && ! grep -qE 'dead entries: 1' "$OUT"; then
  pass "a 403 without the Access stamp does not render as a stale credential"
else
  fail "an unstamped 403 comes from in FRONT of Access (WAF, bot-fight, IP rule); grading it DEAD sends the operator to overwrite a healthy secret (rc=$RC)"
fi

echo "T18: control probe unrefused -> gate-absent, never LIVE"
MOCK_CONTROL_STAMPED=0 MOCK_CONTROL_CODE=200 run_sut t18 200 "$CI_SSH_FIXTURE"
_t18=1
grep -qE 'live entries: 0' "$OUT" || _t18=0
grep -q 'gate-absent' "$OUT" || _t18=0
[[ "$RC" == "1" ]] || _t18=0
if [[ "$_t18" == "1" ]]; then
  pass "an ungated host renders gate-absent and never certifies the credential"
else
  fail "if an UNCREDENTIALED request is not refused, nothing is gating the host — grading the credential LIVE there is a false-LIVE on the one verdict that emails nobody (rc=$RC)"
fi

# The anchor here is `access_hostname_for`, NOT the sentence "add a hostname mapping":
# the report wraps that phrase across two echo lines, so a grep for it matches nothing on
# ANY output and the assertion passed for the wrong reason. Caught by mutation M8, which
# forced the no-probe-configured footer to print unconditionally and still left the suite
# 26/26. Anchor on a token that survives line-wrapping.
echo "T19: gate-absent names the GATE, not a hostname mapping"
MOCK_CONTROL_STAMPED=0 MOCK_CONTROL_CODE=200 run_sut t19 200 "$CI_SSH_FIXTURE"
if grep -q 'gate-absent' "$OUT" && ! grep -q 'access_hostname_for' "$OUT"; then
  pass "the gate-absent remedy does not tell the operator to add a mapping that exists"
else
  fail "gate-absent must not print the no-probe-configured remedy — CI_SSH_ACCESS_TOKEN already HAS a mapping, so 'add a hostname mapping' is unperformable and the state never clears"
fi

echo "T20: a transport failure renders UNVERIFIABLE and never fabricates a status"
MOCK_CURL_EXIT=7 run_sut t20 000 "$CI_SSH_FIXTURE"
_t20=1
grep -qE 'live entries: 0' "$OUT" || _t20=0
grep -qE 'unverifiable: 1' "$OUT" || _t20=0
grep -q '000000' "$OUT" && _t20=0
[[ "$RC" == "1" ]] || _t20=0
if [[ "$_t20" == "1" ]]; then
  pass "curl exiting non-zero yields UNVERIFIABLE with no concatenated status"
else
  fail "real curl prints its -w output AND exits non-zero; \`\$(curl ... || printf '000')\` concatenates to 000000/200000, and 'did not learn' must never read as LIVE (rc=$RC)"
fi

echo "T21: a transport failure must NOT print the mapping remedy either"
MOCK_CURL_EXIT=7 run_sut t21 000 "$CI_SSH_FIXTURE"
if ! grep -q 'add a hostname mapping' "$OUT" && grep -qE 'host-unreachable|probe-failed' "$OUT"; then
  pass "an unreachable host is reported as unreachable, not as a detector coverage gap"
else
  fail "a DNS/TLS blip must not email the operator 'add a hostname mapping to access_hostname_for()' for a key that has one — that is naming a cause nothing measured"
fi

echo "T22: the pair verdict is cached — N configs holding one pair cost ONE credentialed probe"
run_sut t22 200 "prd|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd_a|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd_a|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd_b|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd_b|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}" "prd
prd_a
prd_b"
_n=$(cred_probes)
if [[ "$_n" == "1" ]]; then
  pass "three configs, one identical pair, one credentialed probe"
else
  fail "expected 1 credentialed probe for 3 configs holding identical bytes, got $_n — the memo cache is dead (command substitution runs it in a subshell), so one transient blip grades the SAME BYTES live in two configs and dead in the third, and the DEAD remedy overwrites the ROOT config all three inherit"
fi

echo "T23: per-base dispatch — one admitting host and one rejecting host in ONE run"
printf 'ssh.soleur.ai|403|1|200|0\nregistry.soleur.ai|403|1|403|1\n' > "$TMP/t23.hosts"
MOCK_HOSTS="$TMP/t23.hosts" run_sut t23 200 "prd|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd|REGISTRY_PUSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|REGISTRY_PUSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}"
if grep -qE 'live entries: 1' "$OUT" && grep -qE 'dead entries: 1' "$OUT"; then
  pass "each base is graded against its OWN host's answer"
else
  fail "a fixture carrying two bases must grade each against its own host; every previous fixture held one base, so a sticky/first-base-wins dispatch was invisible (rc=$RC)"
fi

# Both halves are NAMED but hold no value — the shape a Doppler token scoped to read
# secret names but not values produces, and the shape of a read that fails mid-scan. Every
# `doppler secrets get` returns empty, every loop `continue`s, and nothing is measured.
echo "T24: a run that concludes NOTHING is not a clean fleet"
run_sut t24 200 "prd|CI_SSH_ACCESS_TOKEN_ID|
prd|CI_SSH_ACCESS_TOKEN_SECRET|"
_t24=1
[[ "$RC" == "2" ]] || _t24=0
grep -q 'PROBED ZERO' "$OUT" || _t24=0
if [[ "$_t24" == "1" ]]; then
  pass "zero probes exits 2 rather than reporting a clean fleet"
else
  fail "a Doppler token that reads NAMES but not VALUES makes every read empty and every loop continue; falling through to exit 0 reports 'clean' with nothing measured and the alarm goes dark (rc=$RC)"
fi

# T25 — the enumeration is read ONCE per config, and its exit status is checked.
#
# The file's own comment promised "ONE --only-names read per config", and the code did two:
# the second was `doppler ... 2>/dev/null || true`, the exact shape the comment three lines
# below it condemns as "how a scope-denied token renders as a clean fleet". Measured on the
# unfixed code with the second read failing: a genuinely stale credential reported
# `live entries: 1  dead entries: 0`, exit 0.
#
# Nothing pinned it — mutation M10 restored the second read and the suite stayed 26/26 —
# because no test had ever counted a Doppler call. This is that instrument.
echo "T25: secret NAMES are enumerated once per config, not twice"
run_sut t25 200 "prd|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd_a|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd_a|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}" "prd
prd_a"
_n=$(grep -c -- '--only-names' "$DOPPLER_LOG" 2>/dev/null || printf '0')
if [[ "$_n" == "2" ]]; then
  pass "two configs, two --only-names reads (one each)"
else
  fail "expected 2 --only-names reads for 2 configs, got $_n — a second read is a second chance to return empty silently, and an empty enumeration renders as a clean fleet"
fi

# ---------------------------------------------------------------------------
# T26-T36 — the mutants that survived the first battery. Each case below exists
# because a specific edit passed 27/27, and the pass-count is recorded with it.
# ---------------------------------------------------------------------------

echo "T26: a STAMPED 200 is not admission — the stamp decides, not the status"
MOCK_CRED_STAMPED=1 run_sut t26 200 "$CI_SSH_FIXTURE"
_t26=1
grep -qE 'live entries: 0' "$OUT" || _t26=0
grep -q 'stamped-non-refusal' "$OUT" || _t26=0
[[ "$RC" == "1" ]] || _t26=0
if [[ "$_t26" == "1" ]]; then
  pass "a stamped 200 does not grade LIVE, and is not called a rejection either"
else
  fail "this is THE case that separates a stamp rule from a status rule; without it, inserting \`elif [[ \$PROBE_CODE == 200 ]]; then LIVE\` ahead of the stamp test — restoring the instrument this PR removes — passed 27/27 (rc=$RC)"
fi

echo "T27: an unstamped 5xx is NOT certified — LIVE requires positive 2xx success"
run_sut t27 502 "$CI_SSH_FIXTURE"
_t27=1
grep -qE 'live entries: 0' "$OUT" || _t27=0
grep -q 'unexpected-status' "$OUT" || _t27=0
[[ "$RC" == "1" ]] || _t27=0
if [[ "$_t27" == "1" ]]; then
  pass "an unstamped 502 renders unexpected-status, never LIVE"
else
  fail "the first revision made LIVE the catch-all \`else\` and narrowed only 401/403 out of it — measured, a rate-limit 429, a challenge 503, an identity 302 and a tunnel 530 ALL graded LIVE at rc=0, on the one verdict that emails nobody (rc=$RC)"
fi

echo "T28: an unstamped 401 is a refusal, not admission"
run_sut t28 401 "$CI_SSH_FIXTURE"
if [[ "$RC" == "1" ]] && ! grep -qE 'live entries: 1' "$OUT"; then
  pass "401 unstamped does not certify the credential"
else
  fail "narrowing the refusal set from {401,403} to {403} left an unstamped 401 grading LIVE at 27/27 (rc=$RC)"
fi

echo "T29: a Cloudflare-mitigated answer (rate limit / challenge) is a refusal"
printf 'ssh.soleur.ai|403|1|429|0|1\n' > "$TMP/t29.hosts"
MOCK_HOSTS="$TMP/t29.hosts" run_sut t29 429 "$CI_SSH_FIXTURE"
_t29=1
grep -qE 'live entries: 0' "$OUT" || _t29=0
grep -q 'refused-unstamped' "$OUT" || _t29=0
if [[ "$_t29" == "1" ]]; then
  pass "cf-mitigated is read as Cloudflare's own block, not as admission"
else
  fail "a 429 rate-limit carries no cf-access-* stamp; without reading cf-mitigated it is indistinguishable from an admitted response and grades LIVE (rc=$RC)"
fi

echo "T30: refused-unstamped is labelled as ITSELF, not as an unreachable host"
printf 'ssh.soleur.ai|403|1|429|0|1\n' > "$TMP/t30.hosts"
MOCK_HOSTS="$TMP/t30.hosts" run_sut t30 429 "$CI_SSH_FIXTURE"
if grep -q '\[refused-unstamped\]' "$OUT" && ! grep -q 'host-unreachable' "$OUT"; then
  pass "the cause label names the WAF/challenge case specifically"
else
  fail "relabelling refused-unstamped to host-unreachable passed 27/27 — the two have opposite remedies ('check your WAF' vs 're-run, nothing was measured') and the workflow branches its email on this exact token"
fi

echo "T31: a credentialed probe that got no answer is UNVERIFIABLE, never LIVE"
printf 'ssh.soleur.ai|403|1|000|0|0\n' > "$TMP/t31.hosts"
MOCK_HOSTS="$TMP/t31.hosts" run_sut t31 000 "$CI_SSH_FIXTURE"
_t31=1
grep -qE 'live entries: 0' "$OUT" || _t31=0
grep -q 'probe-failed' "$OUT" || _t31=0
[[ "$RC" == "1" ]] || _t31=0
if [[ "$_t31" == "1" ]]; then
  pass "control succeeds, credentialed probe fails -> probe-failed"
else
  fail "this branch was UNREACHABLE in the suite: every 000 case failed the CONTROL probe too, so the credentialed arm was never entered and \`probe-failed -> LIVE\` passed 27/27 (rc=$RC)"
fi

echo "T32: an identity-policy redirect to the IdP is a GATE, not a missing gate"
printf 'ssh.soleur.ai|302|0|200|0|0|1\n' > "$TMP/t32.hosts"
MOCK_HOSTS="$TMP/t32.hosts" run_sut t32 200 "$CI_SSH_FIXTURE"
if grep -qE 'live entries: 1' "$OUT" && [[ "$RC" == "0" ]]; then
  pass "a 302 to the Access login page is recognised as Access answering, and the credential is then graded"
else
  fail "an Access app with an identity policy 302s anonymous requests and carries no cf-access-* header; calling that 'nothing is gating this host' puts a fabricated SECURITY claim in an operator email (rc=$RC)"
fi

echo "T33: gate-absent requires an anonymous request to actually SUCCEED"
printf 'ssh.soleur.ai|530|0|200|0|0|0\n' > "$TMP/t33.hosts"
MOCK_HOSTS="$TMP/t33.hosts" run_sut t33 200 "$CI_SSH_FIXTURE"
if grep -q 'gate-indeterminate' "$OUT" && ! grep -q 'gate-absent' "$OUT"; then
  pass "a 530 tunnel outage is not reported as a removed Access gate"
else
  fail "only a 2xx to an anonymous request is evidence nothing refused it; a 530/429/302 unstamped control graded gate-absent and emailed 'the host may be exposed' (rc=$RC)"
fi

echo "T34: a stale pair and a rotated pair in TWO configs are graded separately"
printf '%s|200|0\n%s|403|1\n' "$FIX_ID" "${FIX_ID%.access}.stale" > "$TMP/t34.creds"
MOCK_CREDS="$TMP/t34.creds" run_sut t34 200 "prd|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd_terraform|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID%.access}.stale
prd_terraform|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}" "prd
prd_terraform"
_t34=1
grep -qE 'live entries: 1' "$OUT" || _t34=0
grep -qE 'dead entries: 1' "$OUT" || _t34=0
grep -q 'prd_terraform' "$OUT" || _t34=0
if [[ "$_t34" == "1" ]]; then
  pass "one rotated, one stale -> 1 live 1 dead, and the report names the stale config"
else
  fail "this is the incident the script exists to catch ('5 of 7 configs stale after a dashboard roll'). Dropping the credential from the memo cache key passed 27/27 because EVERY fixture wrote identical bytes to every config; under this fixture it reports 'live: 2 dead: 0' — a clean bill of health on the real failure (rc=$RC)"
fi

echo "T35: the CONTROL probe is cached per host, not repeated per credential"
printf '%s|200|0\n%s|403|1\n' "$FIX_ID" "${FIX_ID%.access}.stale" > "$TMP/t35.creds"
MOCK_CREDS="$TMP/t35.creds" run_sut t35 200 "prd|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd_terraform|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID%.access}.stale
prd_terraform|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}" "prd
prd_terraform"
_c=$(control_probes); _r=$(cred_probes)
if [[ "$_c" == "1" && "$_r" == "2" ]]; then
  pass "two distinct credentials on one host: 1 control probe, 2 credentialed"
else
  fail "expected 1 control + 2 credentialed, got control=$_c cred=$_r — the control probe doubles the request volume against the Access edge, which is what makes a rate-limit response reachable in the first place"
fi

echo "T36: the API-token memo cache is real too"
run_sut t36 200 "prd|CF_API_TOKEN_X|tokenvalue
prd_a|CF_API_TOKEN_X|tokenvalue
prd_b|CF_API_TOKEN_X|tokenvalue" "prd
prd_a
prd_b"
_n=$(grep -c 'tokens/verify' "$CURL_LOG" 2>/dev/null || printf '0')
if [[ "$_n" == "1" ]]; then
  pass "three configs, one identical API token, one verify call"
else
  fail "expected 1 /user/tokens/verify call for 3 configs holding one value, got $_n — the SUT comment says the subshell bug hit 'every memoised helper in this file', but only the Access cache had an instrument, so neutering this one passed 27/27"
fi

echo "T37: the probe does NOT follow redirects"
run_sut t37 200 "$CI_SSH_FIXTURE"
if ! grep -qE '(^| )(-L|--location)( |$)' "$CURL_LOG"; then
  pass "no -L: header blocks cannot come from a different response than %{http_code}"
else
  fail "curl APPENDS each response's headers into one -D file, so under -L the stamp grep (an OR over the whole file) can see an early block's stamp while %{http_code} reports the final response — an admitted-after-redirect would grade DEAD, the destructive direction"
fi

echo "T38: a STAMPED 401 is a refusal and must stay DEAD"
MOCK_CRED_STAMPED=1 run_sut t38 401 "$CI_SSH_FIXTURE"
if [[ "$RC" == "1" ]] && grep -qE 'dead entries: 1' "$OUT"; then
  pass "401 with the Access stamp grades DEAD, same as 403"
else
  fail "narrowing the DEAD refusal set from {401,403} to {403} passed 39/39 — a stamped 401 is Access refusing the credential and must not be downgraded to 'could not verify' (rc=$RC)"
fi

echo "T39: the report states how many network probes were actually made"
run_sut t39 200 "$CI_SSH_FIXTURE"
if grep -qE 'network probes: [1-9]' "$OUT"; then
  pass "the summary line carries a non-zero probe count"
else
  fail "deleting the probe counter's increment passed 39/39: the one number separating 'measured something' from 'concluded from Doppler reads alone' was computed and never reported"
fi

echo "T40: a local mktemp failure is NOT reported as an unreachable host"
MOCK_MKTEMP_FAIL=1 run_sut t40 200 "$CI_SSH_FIXTURE"
_t40=1
grep -q 'detector-env' "$OUT" || _t40=0
grep -q 'host-unreachable' "$OUT" && _t40=0
[[ "$(cred_probes)" == "0" ]] || _t40=0
if [[ "$_t40" == "1" ]]; then
  pass "a full/read-only TMPDIR renders detector-env, with zero requests sent"
else
  fail "mapping a local disk fault onto 'the host got no answer (timeout / DNS / TLS)' sends the operator to investigate Cloudflare while the runner disk is full — and zero requests were sent (rc=$RC)"
fi

# ===========================================================================
# P1-P15 — THE SINGLE CREDENTIAL AND THE COVERAGE LADDER (#7159).
#
# What is being pinned here is a GATE/REPORT SPLIT, and every case below exists to keep
# the two apart:
#
#   the FLOOR gates      `configs >= configs_floor` decides `coverage`, and nothing else
#                        does. The floor is DECLARED by the caller — a caller cannot be
#                        wrong about a number it declares — and the comparison is `>=`,
#                        never `==`, because the live config set is expected to grow.
#   the INVENTORY reports it supplies `configs_expected`, `configs_unread` and
#                        `inventory_age_days`, and gates NOTHING. P7/P7b/P8 are the
#                        regression guards for that: a short, long or missing inventory
#                        must move the printed ratio and no state at all.
#
# And `configs` counts configs whose secret-name read SUCCEEDED, never configs listed
# (P5c). A role that can enumerate but not read would otherwise satisfy any floor with a
# credential that measures nothing — which is the whole failure this ladder exists to
# make loud.
# ---------------------------------------------------------------------------

# Doppler's own listing order is NOT alphabetical, and this fixture is deliberately
# unsorted: `config_names` is a published contract field, so the sort has to be done by
# the SUT. A pre-sorted fixture would let the sort be deleted without any case noticing.
P_CFG13=$'prd\nprd_terraform\nci\ncli\ncli_ops\ndev\ndev_personal\ndev_scheduled\nprd_cla\nprd_ghcr\nprd_kb_drift_walker\nprd_scheduled\nprd_workspaces_luks'
P_CFG13_SORTED='ci,cli,cli_ops,dev,dev_personal,dev_scheduled,prd,prd_cla,prd_ghcr,prd_kb_drift_walker,prd_scheduled,prd_terraform,prd_workspaces_luks'
P_CFG14="$P_CFG13"$'\nprd_git_data'
# The seven `prd*` configs — the shape narrowing N2 (a membership scoped to one
# environment) produces on a 13-config project.
P_CFG7=$'prd\nprd_terraform\nprd_cla\nprd_ghcr\nprd_kb_drift_walker\nprd_scheduled\nprd_workspaces_luks'

# One DISTINCT token value per config, so a 13-config run carries 13 distinct values.
# Identical values across configs would collapse under the memo cache and make P14's
# "one ::add-mask:: per distinct value" unable to tell 13 masks from 1.
p_secrets_for() {
  local cfgs="$1" out="" c
  while read -r c; do
    [[ -z "$c" ]] && continue
    out+="${c}|CF_API_TOKEN_X|synthetic-token-value-${c}"$'\n'
  done <<< "$cfgs"
  printf '%s' "${out%$'\n'}"
}
P_SEC13="$(p_secrets_for "$P_CFG13")"
P_SEC14="$(p_secrets_for "$P_CFG14")"
P_SEC7="$(p_secrets_for "$P_CFG7")"

# The committed inventory's shape: an ISO-8601 `# generated:` header, the regeneration
# command, then sorted names matching `^[a-z0-9_]+$` — the SAME syntax the repo-internal
# floor/inventory equality check counts, because two checks counting different things
# would pin nothing.
p_write_inventory() {
  local path="$1" names="$2" stamp="${3:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  {
    printf '# generated: %s\n' "$stamp"
    printf '# command: doppler configs -p soleur --json | jq -r .[].name | sort\n'
    printf '%s\n' "$names"
  } > "$path" || { echo "FATAL: could not write inventory fixture $path" >&2; exit 2; }
}
P_INV13="$TMP/inv13.txt"
p_write_inventory "$P_INV13" "$(printf '%s\n' "$P_CFG13" | sort)"
P_INV2="$TMP/inv2.txt"
p_write_inventory "$P_INV2" $'prd\nprd_terraform'
P_INV20="$TMP/inv20.txt"
p_write_inventory "$P_INV20" "$(printf '%s\n' "$(printf '%s\n' "$P_CFG13" | sort)"; printf 'extra_%02d\n' 1 2 3 4 5 6 7)"
P_INV_STALE="$TMP/inv_stale.txt"
p_write_inventory "$P_INV_STALE" "$(printf '%s\n' "$P_CFG13" | sort)" '2020-01-01T00:00:00Z'
P_INV_MISSING="$TMP/no-such-inventory.txt"
rm -f "$P_INV_MISSING"

# Read one field out of a verdict file. Prints a distinguishable marker rather than an
# empty string on any failure — an empty string compares equal to too many things.
jget() {
  python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("<unparseable>"); raise SystemExit(0)
v = d.get(sys.argv[2], "<absent>")
print(",".join(v) if isinstance(v, list) else v)
' "$1" "$2" 2>/dev/null || printf '<unparseable>'
}

echo "P1: with --configs-floor and --inventory absent, the pre-existing contract is unchanged"
# The three existing call sites pass neither flag. They must keep their exit code, keep
# every field they already parse (two of them read three fields with no compile-time link
# to this file), and land on a coverage state rather than an error.
JP1="$TMP/p1.json"
run_sut p1 200 "$CI_SSH_FIXTURE" prd "--json-file $JP1"
_p1=1
[[ "$RC" == "0" ]] || _p1=0
grep -qF 'Cloudflare token drift check' "$OUT" || _p1=0
python3 - "$JP1" <<'PY' || _p1=0
import json, sys
d = json.load(open(sys.argv[1]))
for k, t in (("live", int), ("dead", int), ("unverifiable", int), ("probes", int),
             ("configs", int), ("stale", list), ("unverifiable_keys", list)):
    if k not in d or isinstance(d[k], bool) or not isinstance(d[k], t):
        raise SystemExit(1)
# The default floor is 1, so a single-config caller stays at-floor and no caller has to
# learn a new flag to keep its current behaviour.
if d.get("configs_floor") != 1 or d.get("coverage") != "at-floor":
    raise SystemExit(1)
# No inventory was supplied, so there is no denominator to print — and none is invented.
if d.get("configs_expected") != -1 or d.get("coverage_ratio") != "-":
    raise SystemExit(1)
PY
if [[ "$_p1" == "1" ]]; then
  pass "flags absent: exit code, human report and the seven pre-existing JSON keys all intact; floor defaults to 1"
else
  fail "adding the ladder must not change what the three existing call sites see: same exit code, same seven keys with the same types, --configs-floor defaulting to 1 (rc=$RC)"
fi

echo "P10: an unrecognised argument exits 2 with a named message"
# The old `*) shift ;;` catch-all swallowed typos silently. Every flag here narrows or
# instruments the scan, so a swallowed typo does not disable a feature — it silently
# widens or blinds the check while the run stays green.
run_sut p10 200 "$CI_SSH_FIXTURE" prd "--configs-floorr 13"
_p10=1
[[ "$RC" == "2" ]] || _p10=0
grep -qF 'unrecognised argument' "$OUT" || _p10=0
grep -qF -- "--configs-floorr" "$OUT" || _p10=0
if [[ "$_p10" == "1" ]]; then
  pass "a typo'd flag exits 2 and the message names the offending argument"
else
  fail "an unknown argument must exit 2 and name itself — the previous catch-all shifted past a misspelled --inventory and printed a caveat nobody asked for (rc=$RC)"
fi

echo "P10b: an unparseable floor publishes coverage: unknown BEFORE it fails"
JP10="$TMP/p10b.json"
run_sut p10b 200 "$CI_SSH_FIXTURE" prd "--configs-floor abc --json-file $JP10"
_p10b=1
[[ "$RC" == "2" ]] || _p10b=0
[[ -s "$JP10" ]] || _p10b=0
[[ "$(jget "$JP10" coverage)" == "unknown" ]] || _p10b=0
if [[ "$_p10b" == "1" ]]; then
  pass "a floor that does not parse yields the fail-closed 'unknown', published rather than swallowed"
else
  fail "a gate with no threshold must publish coverage: unknown and exit 2 — deriving 'at-floor' from an unparseable demand is a confident state drawn from garbage (rc=$RC, coverage=$(jget "$JP10" coverage))"
fi

echo "P2: 13 configs at floor 13 -> at-floor at 13/13, names sorted"
JP2="$TMP/p2.json"
MOCK_HTTP_BODY='{"success":true}' run_sut p2 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV13 --json-file $JP2"
_p2=1
[[ "$RC" == "0" ]] || _p2=0
[[ "$(jget "$JP2" configs)" == "13" ]] || _p2=0
[[ "$(jget "$JP2" configs_floor)" == "13" ]] || _p2=0
[[ "$(jget "$JP2" coverage)" == "at-floor" ]] || _p2=0
[[ "$(jget "$JP2" coverage_ratio)" == "13/13" ]] || _p2=0
[[ "$(jget "$JP2" config_names)" == "$P_CFG13_SORTED" ]] || _p2=0
[[ "$(jget "$JP2" configs_unread)" == "" ]] || _p2=0
if [[ "$_p2" == "1" ]]; then
  pass "the full fleet reads at-floor at 13/13 with a sorted name list and nothing unread"
else
  fail "13 of 13 read at a declared floor of 13 must be at-floor with ratio 13/13 and sorted config_names (rc=$RC, configs=$(jget "$JP2" configs), coverage=$(jget "$JP2" coverage), ratio=$(jget "$JP2" coverage_ratio), names=$(jget "$JP2" config_names))"
fi

echo "P2b: 14 configs at floor 13 -> STILL at-floor (the gate is >=, not ==)"
# C7: the live config set is expected to grow — a config at git-data birth, ephemeral
# rehearsal configs. An equality gate would red a twice-daily cron the first time growth
# was legitimate, and a red on legitimate growth trains the operator to ignore the channel.
JP2B="$TMP/p2b.json"
MOCK_HTTP_BODY='{"success":true}' run_sut p2b 200 "$P_SEC14" "$P_CFG14" "--configs-floor 13 --inventory $P_INV13 --json-file $JP2B"
_p2b=1
[[ "$RC" == "0" ]] || _p2b=0
[[ "$(jget "$JP2B" configs)" == "14" ]] || _p2b=0
[[ "$(jget "$JP2B" coverage)" == "at-floor" ]] || _p2b=0
[[ "$(jget "$JP2B" coverage_ratio)" == "14/13" ]] || _p2b=0
grep -q '::warning' "$OUT" && _p2b=0
if [[ "$_p2b" == "1" ]]; then
  pass "growth past the floor stays at-floor, pushes the ratio above 1, and fires nothing"
else
  fail "the gate must be 'configs >= floor', not '=='. A 14th config is legitimate growth and must not flip a state or raise a warning (rc=$RC, configs=$(jget "$JP2B" configs), coverage=$(jget "$JP2B" coverage), ratio=$(jget "$JP2B" coverage_ratio))"
fi

echo "P3: every Doppler read names its config explicitly (-c <cfg>), at all four read sites"
# With 13 configs in play an implicit bind does not fail — it grades ANOTHER config's
# bytes and reports a confident wrong answer. The stub exits 4 on any `secrets` call
# without a `-c`, so a dropped argument is loud rather than merely wrong; this case then
# pins that the config named is the config being graded, at each of the four sites.
P3_FIXTURE="prd|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd|CF_API_TOKEN_DNS_EDIT|synthetic-api-prd
prd_terraform|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd_terraform|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd_terraform|CF_API_TOKEN_DNS_EDIT|synthetic-api-prd-terraform"
MOCK_HTTP_BODY='{"success":true}' run_sut p3 200 "$P3_FIXTURE" $'prd\nprd_terraform'
_p3=1
_p3_secrets=$(grep -E '^secrets' "$DOPPLER_LOG" 2>/dev/null || true)
[[ -n "$_p3_secrets" ]] || _p3=0
# Not one `secrets` invocation without a config.
_p3_no_c=$(grep -cv -- ' -c ' <<<"$_p3_secrets" || true)
[[ "${_p3_no_c:-1}" == "0" ]] || _p3=0
# All four sites, for BOTH configs. Anchored on the invocation shape, which no comment in
# any file can produce, and matched per config so a site that reads the right key from
# the wrong config fails.
for _cfg in prd prd_terraform; do
  grep -qF "secrets -p soleur -c ${_cfg} --only-names" <<<"$_p3_secrets" || _p3=0
  grep -qF "secrets get CF_API_TOKEN_DNS_EDIT -p soleur -c ${_cfg} --plain" <<<"$_p3_secrets" || _p3=0
  grep -qF "secrets get CI_SSH_ACCESS_TOKEN_ID -p soleur -c ${_cfg} --plain" <<<"$_p3_secrets" || _p3=0
  grep -qF "secrets get CI_SSH_ACCESS_TOKEN_SECRET -p soleur -c ${_cfg} --plain" <<<"$_p3_secrets" || _p3=0
done
if [[ "$_p3" == "1" ]]; then
  pass "all four read sites name their config, and each config is read at every site"
else
  fail "each of the four Doppler reads (--only-names, and `secrets get` for the API key, the _ID half and the _SECRET half) must pass an explicit -c matching the config being graded; an implicit bind grades another config's bytes. Log:\n$_p3_secrets"
fi

echo "P4: an unset or empty DOPPLER_TOKEN is a failed credential, never an ambient fallback"
# The Doppler CLI treats an EMPTY token exactly as it treats an absent one: it rebinds to
# whatever credential the runner carries and answers confidently about a scope nobody
# asked for. Both states must therefore refuse to invoke the CLI at all — and the strongest
# available evidence of that is an empty invocation log.
for _mode in unset empty; do
  JP4="$TMP/p4-$_mode.json"
  MOCK_CRED_MODE="$_mode" run_sut "p4$_mode" 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV13 --json-file $JP4"
  _p4=1
  [[ "$RC" == "2" ]] || _p4=0
  [[ -s "$DOPPLER_LOG" ]] && _p4=0
  [[ "$(jget "$JP4" configs)" == "0" ]] || _p4=0
  [[ "$(jget "$JP4" coverage)" == "degraded" ]] || _p4=0
  [[ "$(jget "$JP4" coverage_ratio)" == "0/13" ]] || _p4=0
  if [[ "$_p4" == "1" ]]; then
    pass "DOPPLER_TOKEN $_mode -> degraded at 0/13, and the Doppler CLI was never invoked"
  else
    fail "an $_mode DOPPLER_TOKEN must publish degraded at 0/13 WITHOUT invoking the CLI — an empty value is treated as unset and silently rebinds to the ambient credential (rc=$RC, configs=$(jget "$JP4" configs), coverage=$(jget "$JP4" coverage), doppler calls=$(wc -l < "$DOPPLER_LOG"))"
  fi
done

echo "P5: a non-empty credential that enumerates nothing is loud, and the verdict is still published"
# This is the REVOKED-credential path. It used to exit before emit_json, so no verdict
# file existed at all: the caller parsed configs as -1, coverage landed on 'unknown', and
# 'unknown' tells the reader to fix the verdict file — unperformable for a dead credential.
JP5="$TMP/p5.json"
MOCK_ENUM_FAIL='Invalid Auth token (revoked)' run_sut p5 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV13 --json-file $JP5"
_p5=1
[[ "$RC" == "2" ]] || _p5=0
grep -qF 'Invalid Auth token (revoked)' "$OUT" || _p5=0
[[ -s "$JP5" ]] || _p5=0
[[ "$(jget "$JP5" configs)" == "0" ]] || _p5=0
[[ "$(jget "$JP5" coverage)" == "degraded" ]] || _p5=0
[[ "$(jget "$JP5" coverage_ratio)" == "0/13" ]] || _p5=0
if [[ "$_p5" == "1" ]]; then
  pass "a revoked credential exits 2, shows the CLI's own stderr, and STILL publishes degraded at 0/13"
else
  fail "the enumeration's stderr must not be swallowed (it is the only line saying whether the credential was revoked, expired or scoped to nothing), and emit_json must run before the exit-2 return so a revoked credential surfaces as degraded rather than blinding the scan (rc=$RC, verdict written=$([[ -s "$JP5" ]] && echo yes || echo no))"
fi

echo "P5b: the three narrowings all produce degraded — 0/13, 7/13 and 1/13"
# Three ways a SINGLE credential's reach can shorten: a role downgrade (0/13), scoping to
# one environment (7/13), and a swap to a config-scoped token (1/13). All three SHORTEN
# what the credential reaches and none can lengthen it, which is what makes a one-sided
# floor sound. Each must be nameable, not merely non-green.
#
# These keep their value under the per-config map (#7234) even though the project-scoped
# identity they were written against is gone: they are the single-credential path, which
# five call sites still drive, and the 1/13 case is now ALSO what the fan-out step looks
# like if it is repointed at a bare DOPPLER_TOKEN. The map's own failure modes are M1-M9.
#
# Written as three explicit tuples rather than one packed loop variable: both the config
# lists and the secrets fixtures carry newlines AND `|`, so any single-string encoding of
# them is silently truncated by `read` — measured here, n1 and n2 both collapsed to the
# 1-config default and the case still reported a narrowing.
p5b_case() {
  local _lbl="$1" _want="$2" _cfgs="$3" _secs="$4"
  local JP5B="$TMP/p5b-$_lbl.json"
  local _p5b=1 _p5b_unread
  MOCK_HTTP_BODY='{"success":true}' run_sut "p5b$_lbl" 200 "$_secs" "$_cfgs" "--configs-floor 13 --inventory $P_INV13 --json-file $JP5B"
  [[ "$(jget "$JP5B" configs)" == "$_want" ]] || _p5b=0
  [[ "$(jget "$JP5B" coverage)" == "degraded" ]] || _p5b=0
  [[ "$(jget "$JP5B" coverage_ratio)" == "${_want}/13" ]] || _p5b=0
  _p5b_unread=$(jget "$JP5B" configs_unread)
  [[ "$(printf '%s\n' "$_p5b_unread" | tr ',' '\n' | grep -c .)" == "$((13 - _want))" ]] || _p5b=0
  if [[ "$_p5b" == "1" ]]; then
    pass "narrowing $_lbl reads ${_want}/13 -> degraded, with the $((13 - _want)) missing configs named"
  else
    fail "narrowing $_lbl must produce degraded at ${_want}/13 and name every config it did not reach — a narrowing that reports a bare state gives the operator nothing to act on (configs=$(jget "$JP5B" configs), coverage=$(jget "$JP5B" coverage), ratio=$(jget "$JP5B" coverage_ratio), unread=$_p5b_unread)"
  fi
}
# N1 — the membership role is downgraded: the enumeration itself returns nothing.
# A bare "" cannot express this: run_sut's `${4:-prd}` default fires on a NULL argument as
# well as an unset one, so an empty config list silently became the 1-config default and
# the case graded a narrowing it never produced. A lone newline is non-null to the shell
# and still renders as `[]` from the stub.
p5b_case n1 0 $'\n' ""
# N2 — the membership is scoped to one environment: the 7 prd* configs, and only those.
p5b_case n2 7 "$P_CFG7" "$P_SEC7"
# N3 — DOPPLER_TOKEN_DRIFT is repointed at a config-scoped service token: 1 of 13.
p5b_case n3 1 'prd' 'prd|CF_API_TOKEN_X|synthetic-token-value-prd'

echo "P5c: 13 configs LISTED with every read failing counts 0, not 13"
# N1's subtle form: a role that can enumerate configs but not read their secrets. Counting
# LISTINGS would satisfy a floor of 13 with a credential that measured nothing at all —
# a green coverage signal earned by a credential that read zero bytes.
JP5C="$TMP/p5c.json"
MOCK_UNREADABLE=ALL run_sut p5c 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV13 --json-file $JP5C"
_p5c=1
[[ "$(jget "$JP5C" configs)" == "0" ]] || _p5c=0
[[ "$(jget "$JP5C" coverage)" == "degraded" ]] || _p5c=0
[[ "$(jget "$JP5C" config_names)" == "" ]] || _p5c=0
[[ "$(jget "$JP5C" configs_unread)" == "$P_CFG13_SORTED" ]] || _p5c=0
if [[ "$_p5c" == "1" ]]; then
  pass "configs counts configs READ, not configs listed — 13 listings with 0 reads is 0"
else
  fail "a role that lists 13 configs and can read none of them must count 0, not 13. Counting listings lets the floor be satisfied by a credential that measures nothing (configs=$(jget "$JP5C" configs), coverage=$(jget "$JP5C" coverage), unread=$(jget "$JP5C" configs_unread))"
fi

echo "P6: configs_unread is the inventory minus the read set, sorted, and the age is parsed"
JP6="$TMP/p6.json"
MOCK_HTTP_BODY='{"success":true}' run_sut p6 200 "$P_SEC7" "$P_CFG7" "--configs-floor 13 --inventory $P_INV13 --json-file $JP6"
_p6=1
[[ "$(jget "$JP6" coverage_ratio)" == "7/13" ]] || _p6=0
[[ "$(jget "$JP6" configs_expected)" == "13" ]] || _p6=0
[[ "$(jget "$JP6" configs_unread)" == "ci,cli,cli_ops,dev,dev_personal,dev_scheduled" ]] || _p6=0
# Parsed from the `# generated:` header, so staleness is bounded with no credential and no
# network call — the denominator cannot be quietly ancient.
[[ "$(jget "$JP6" inventory_age_days)" == "0" ]] || _p6=0
if [[ "$_p6" == "1" ]]; then
  pass "the six unreached configs are named in sorted order and the inventory age parses to 0 days"
else
  fail "configs_unread must be the inventory minus the read set, sorted, and inventory_age_days must come from the '# generated:' header (ratio=$(jget "$JP6" coverage_ratio), unread=$(jget "$JP6" configs_unread), age=$(jget "$JP6" inventory_age_days))"
fi

echo "P6b: a stale inventory changes the caveat and nothing else"
JP6B="$TMP/p6b.json"
MOCK_HTTP_BODY='{"success":true}' run_sut p6b 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV_STALE --json-file $JP6B"
_p6b=1
[[ "$(jget "$JP6B" coverage)" == "at-floor" ]] || _p6b=0
[[ "$(jget "$JP6B" coverage_ratio)" == "13/13" ]] || _p6b=0
_p6b_age=$(jget "$JP6B" inventory_age_days)
[[ "$_p6b_age" =~ ^[0-9]+$ && "$_p6b_age" -gt 90 ]] || _p6b=0
[[ "$(jget "$JP6B" coverage_caveat)" == *"days old"* ]] || _p6b=0
if [[ "$_p6b" == "1" ]]; then
  pass "an inventory generated in 2020 carries a staleness caveat and moves no state"
else
  fail "a stale denominator must be DISCLOSED (a caveat past 90 days) and must not move a state — bounding staleness is what keeps the printed ratio honest without a credential (coverage=$(jget "$JP6B" coverage), age=$_p6b_age, caveat=$(jget "$JP6B" coverage_caveat))"
fi

echo "P7: a SHORT inventory changes the ratio and NOTHING else"
# The regression guard for the rejected design in which the denominator gated. A two-line
# file must not be able to derive the healthy state, fire the close arm and silence the
# channel while the job stays green.
JP7="$TMP/p7.json"
MOCK_HTTP_BODY='{"success":true}' run_sut p7 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV2 --json-file $JP7"
_p7=1
[[ "$RC" == "0" ]] || _p7=0
[[ "$(jget "$JP7" coverage_ratio)" == "13/2" ]] || _p7=0
[[ "$(jget "$JP7" configs_expected)" == "2" ]] || _p7=0
[[ "$(jget "$JP7" coverage)" == "at-floor" ]] || _p7=0
[[ "$(jget "$JP7" configs)" == "13" ]] || _p7=0
[[ "$(jget "$JP7" configs_unread)" == "" ]] || _p7=0
if [[ "$_p7" == "1" ]]; then
  pass "a 2-name inventory prints 13/2 and leaves coverage, the exit code and the read count untouched"
else
  fail "THE DENOMINATOR REPORTS AND MUST NOT GATE. A short inventory may change the printed ratio and nothing else — if it can move `coverage`, a two-line file can derive the healthy state and silence the channel (rc=$RC, ratio=$(jget "$JP7" coverage_ratio), coverage=$(jget "$JP7" coverage))"
fi

echo "P7b: a LONG inventory likewise — the floor decides, never the inventory"
JP7B="$TMP/p7b.json"
MOCK_HTTP_BODY='{"success":true}' run_sut p7b 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV20 --json-file $JP7B"
_p7b=1
[[ "$RC" == "0" ]] || _p7b=0
[[ "$(jget "$JP7B" coverage_ratio)" == "13/20" ]] || _p7b=0
[[ "$(jget "$JP7B" coverage)" == "at-floor" ]] || _p7b=0
[[ "$(tr ',' '\n' <<<"$(jget "$JP7B" configs_unread)" | grep -c .)" == "7" ]] || _p7b=0
if [[ "$_p7b" == "1" ]]; then
  pass "a 20-name inventory prints 13/20, names the 7 it did not reach, and stays at-floor"
else
  fail "the inventory cannot manufacture `degraded` any more than it can manufacture `at-floor` — only the declared floor decides (ratio=$(jget "$JP7B" coverage_ratio), coverage=$(jget "$JP7B" coverage), unread=$(jget "$JP7B" configs_unread))"
fi

echo "P8: a MISSING inventory leaves the ratio absent with a caveat, and coverage still derives from the floor"
JP8="$TMP/p8.json"
MOCK_HTTP_BODY='{"success":true}' run_sut p8 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV_MISSING --json-file $JP8"
_p8=1
[[ "$RC" == "0" ]] || _p8=0
[[ "$(jget "$JP8" coverage)" == "at-floor" ]] || _p8=0
[[ "$(jget "$JP8" configs_expected)" == "-1" ]] || _p8=0
# Absent, not fabricated. A `13/13` invented from the read count would be a denominator
# derived from the scan's own credential — exactly the structurally blind measure the
# design rejects.
[[ "$(jget "$JP8" coverage_ratio)" == "-" ]] || _p8=0
[[ "$(jget "$JP8" coverage_caveat)" == *"missing or unreadable"* ]] || _p8=0
if [[ "$_p8" == "1" ]]; then
  pass "no inventory: ratio absent, caveat named, coverage still decided by the floor"
else
  fail "with no readable inventory the ratio must be ABSENT with a caveat — never back-filled from the scan's own count, which would be a denominator that narrows in lockstep with the credential (rc=$RC, coverage=$(jget "$JP8" coverage), ratio=$(jget "$JP8" coverage_ratio), caveat=$(jget "$JP8" coverage_caveat))"
fi

echo "P16: the COMMITTED inventory and the WORKFLOW-DECLARED floor, executed together"
# NOTHING EVER RAN THESE TWO AGAINST EACH OTHER. This suite only ever used inventories it
# wrote itself, and the consumer suite replaces the detector invocation with
# `bash -c "exit $DET_RC"` — so the committed file and the declared floor were only ever
# GREPPED AS TEXT, by three static assertions. Six mutations survived that arrangement at a
# fully green consumer suite; this case observes the EFFECTIVE parameters instead of their
# spelling, and it is the only place the shipped inventory is ever parsed by the shipped parser.
#
# The fleet is built FROM the inventory, so the case says exactly one thing and says it
# honestly: *given a project whose configs are precisely the names this file lists, the floor
# the workflow declares grades that project `at-floor` at N/N with nothing unread.* Any
# divergence between the two counting rules breaks it — notably the duplicate-line case, where
# the file's raw line count and its DEDUPED name count differ: the detector dedupes, so a floor
# raised to match the raw count reds this case (measured: append one duplicate `prd`, set the
# floor to 14, and the detector reads 13 against a floor of 14 -> permanent `degraded`).
#
# It reads no credential and makes no network call. It cannot verify that these names exist in
# live Doppler — no offline check can — and it does not claim to.
P_REAL_INV="$REPO_ROOT/apps/web-platform/infra/doppler-config-inventory.txt"
P_REAL_WF="$REPO_ROOT/.github/workflows/scheduled-terraform-drift.yml"
[[ -r "$P_REAL_INV" ]] || { echo "FATAL: committed inventory unreadable at $P_REAL_INV" >&2; exit 2; }
[[ -r "$P_REAL_WF" ]] || { echo "FATAL: workflow unreadable at $P_REAL_WF" >&2; exit 2; }
# PARSED OUT OF THE YAML, never grepped: a `#` line inside a `run:` block scalar survives
# yaml.safe_load, and this workflow's comments quote the floor repeatedly.
P_WF_FLOOR=$(python3 - "$P_REAL_WF" <<'PYF'
import sys, yaml
for job in yaml.safe_load(open(sys.argv[1]))["jobs"].values():
    for st in job.get("steps", []) or []:
        if st.get("id") == "token_drift":
            sys.stdout.write(str((st.get("env") or {}).get("DOPPLER_CONFIGS_FLOOR", "")))
            raise SystemExit(0)
raise SystemExit(2)
PYF
) || { echo "FATAL: could not parse DOPPLER_CONFIGS_FLOOR out of the workflow" >&2; exit 2; }
[[ "$P_WF_FLOOR" =~ ^[0-9]+$ ]] || { echo "FATAL: workflow floor '${P_WF_FLOOR}' is not an integer" >&2; exit 2; }
# The SUT's own parse, reproduced: `^[a-z0-9_]+$` then `sort -u`.
mapfile -t P_REAL_NAMES < <(grep -E '^[a-z0-9_]+$' "$P_REAL_INV" | sort -u)
(( ${#P_REAL_NAMES[@]} > 0 )) || { echo "FATAL: the committed inventory yielded 0 parseable names" >&2; exit 2; }
P_REAL_CFGS=$(printf '%s\n' "${P_REAL_NAMES[@]}")
P_REAL_SECS="$(p_secrets_for "$P_REAL_CFGS")"
P_REAL_N=${#P_REAL_NAMES[@]}
JP16="$TMP/p16.json"
MOCK_HTTP_BODY='{"success":true}' run_sut p16 200 "$P_REAL_SECS" "$P_REAL_CFGS" "--configs-floor $P_WF_FLOOR --inventory $P_REAL_INV --json-file $JP16"
_p16=1
[[ "$RC" == "0" ]] || { _p16=0; echo "    rc=$RC"; }
[[ "$(jget "$JP16" configs)" == "$P_REAL_N" ]] || { _p16=0; echo "    configs=$(jget "$JP16" configs), expected $P_REAL_N"; }
[[ "$(jget "$JP16" configs_floor)" == "$P_WF_FLOOR" ]] || { _p16=0; echo "    configs_floor=$(jget "$JP16" configs_floor), expected $P_WF_FLOOR"; }
[[ "$(jget "$JP16" configs_expected)" == "$P_REAL_N" ]] || { _p16=0; echo "    configs_expected=$(jget "$JP16" configs_expected), expected $P_REAL_N"; }
[[ "$(jget "$JP16" coverage)" == "at-floor" ]] || { _p16=0; echo "    coverage=$(jget "$JP16" coverage)"; }
[[ "$(jget "$JP16" coverage_ratio)" == "${P_REAL_N}/${P_REAL_N}" ]] || { _p16=0; echo "    ratio=$(jget "$JP16" coverage_ratio), expected ${P_REAL_N}/${P_REAL_N}"; }
[[ "$(jget "$JP16" configs_unread)" == "" ]] || { _p16=0; echo "    configs_unread=$(jget "$JP16" configs_unread), expected empty"; }
# The committed file must not be stale enough to caveat, either — that caveat rides into both
# ops emails, and a permanently-caveated ratio is a permanently hedged one.
[[ "$(jget "$JP16" coverage_caveat)" == "-" || "$(jget "$JP16" coverage_caveat)" == "" ]] \
  || { _p16=0; echo "    the committed inventory carries a caveat: $(jget "$JP16" coverage_caveat)"; }
if [[ "$_p16" == "1" ]]; then
  pass "the committed inventory (${P_REAL_N} names) at the workflow's declared floor (${P_WF_FLOOR}) grades at-floor at ${P_REAL_N}/${P_REAL_N}, nothing unread, no caveat"
else
  fail "the SHIPPED inventory and the SHIPPED floor do not agree when actually executed together. Every other assertion on this pair — in either suite — compares them as TEXT: the consumer suite stubs the detector out entirely, and this suite otherwise writes its own inventories. If the two counting rules diverge (the raw line count vs the deduped name count is the measured case), the scheduled scan lands on a permanent 'degraded' that no static check can see (rc=$RC, configs=$(jget "$JP16" configs), floor=$(jget "$JP16" configs_floor), coverage=$(jget "$JP16" coverage), ratio=$(jget "$JP16" coverage_ratio))"
fi

echo "P17: a floor of 0 does NOT license the confident state — the positive-work floor"
# A THRESHOLD OF ZERO IS A THRESHOLD THAT GATES NOTHING. `0 < 0` is false, so the pure
# floor comparison assigned the CONFIDENT state to a run that read nothing and probed
# nothing. Measured before the fix: `--configs-floor 0` with an unusable credential
# published `configs: 0, probes: 0, coverage: at-floor` while the script's own stderr said
# "0 configs read, so coverage is 'degraded'" — the report and the published verdict
# disagreeing, with the published one being the optimistic lie.
#
# No shipped call site passes 0 today (the scheduled step declares 13, the other three take
# the default 1), which is exactly why this needs a test: the guarantee is the detector
# honouring its own contract rather than depending on every future caller to pass a sane
# floor.
JP17="$TMP/p17.json"
_p17=1
MOCK_CRED_MODE=empty run_sut p17 200 "$P_SEC13" "$P_CFG13" "--configs-floor 0 --inventory $P_INV13 --json-file $JP17"
[[ "$(jget "$JP17" configs)" == "0" ]] || { _p17=0; echo "    configs=$(jget "$JP17" configs), expected 0"; }
[[ "$(jget "$JP17" configs_floor)" == "0" ]] || { _p17=0; echo "    configs_floor=$(jget "$JP17" configs_floor), expected 0"; }
[[ "$(jget "$JP17" coverage)" == "degraded" ]] || { _p17=0; echo "    coverage=$(jget "$JP17" coverage), expected degraded"; }
# AND THE FLOOR MUST STILL GATE ABOVE ZERO — an override that forced `degraded` whenever the
# floor was 0 would pass the line above and destroy the ladder. A real read at a floor of 0
# is at-floor, because the positive-work floor is about WORK DONE, not about the threshold.
JP17B="$TMP/p17b.json"
MOCK_HTTP_BODY='{"success":true}' run_sut p17b 200 "$P_SEC13" "$P_CFG13" "--configs-floor 0 --inventory $P_INV13 --json-file $JP17B"
[[ "$(jget "$JP17B" configs)" == "13" ]] || { _p17=0; echo "    control: configs=$(jget "$JP17B" configs), expected 13"; }
[[ "$(jget "$JP17B" coverage)" == "at-floor" ]] || { _p17=0; echo "    control: 13 configs read at floor 0 published '$(jget "$JP17B" coverage)', expected at-floor"; }
if [[ "$_p17" == "1" ]]; then
  pass "a floor of 0 with zero configs read is degraded, while 13 read at a floor of 0 is still at-floor"
else
  fail "the confident state must never be reachable without at least one successful read. At a floor of 0 the bare comparison '0 < 0' is false, so a run that read nothing and probed nothing published 'at-floor' — a threshold of zero gates nothing, and the state that closes the operator's standing coverage issue was derived from a scan that did no work at all"
fi

echo "P9: the credential value never reaches a child process's argv"
MOCK_HTTP_BODY='{"success":true}' run_sut p9 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV13"
_p9=1
[[ -s "$DOPPLER_LOG" ]] || _p9=0
grep -qF -- '--token' "$DOPPLER_LOG" && _p9=0
grep -qF "$FIX_CRED" "$DOPPLER_LOG" && _p9=0
grep -qF "$FIX_CRED" "$CURL_LOG" && _p9=0
if [[ "$_p9" == "1" ]]; then
  pass "delivered as an env prefix: no --token flag and no credential bytes on any child argv"
else
  fail "the credential must be delivered as an env prefix, never as \`--token <value>\`: /proc/<pid>/cmdline is world-readable while /proc/<pid>/environ is 0400"
fi

echo "P11: the credential reaches none of the six sinks, in any mode"
# P9 covers ONE sink of six. The modes below are the ones that write: --json puts a
# payload on stdout, --json-file puts one on disk, the human report prints prose, and the
# three failure modes are the paths that newly un-swallow a CLI's stderr and newly publish
# a verdict before exiting.
_p11=1
_p11_detail=""
_p11_json="$TMP/p11.json"
p11_check() {
  local label="$1"
  local sink
  for sink in "$OUT" "$_p11_json" "$GH_OUTPUT" "$DOPPLER_LOG" "$CURL_LOG" "$DOPPLER_ENV_LOG"; do
    [[ -f "$sink" ]] || continue
    if grep -qF "$FIX_CRED" "$sink"; then
      _p11=0
      _p11_detail+="  ${label}: sentinel found in $(basename "$sink")"$'\n'
    fi
  done
}
rm -f "$_p11_json"
MOCK_HTTP_BODY='{"success":true}' run_sut p11a 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV13 --json"
p11_check "--json"
MOCK_HTTP_BODY='{"success":true}' run_sut p11b 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV13 --json-file $_p11_json"
p11_check "--json-file"
MOCK_HTTP_BODY='{"success":true}' run_sut p11c 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV13"
p11_check "human report"
rm -f "$_p11_json"
MOCK_CRED_MODE=empty run_sut p11d 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13"
p11_check "empty credential"
MOCK_ENUM_FAIL='Invalid Auth token (revoked)' run_sut p11e 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13"
p11_check "revoked credential"
run_sut p11f 200 "$P_SEC13" "$P_CFG13" "--bogus-flag"
p11_check "unknown flag"
if [[ "$_p11" == "1" ]]; then
  pass "sentinel absent from stdout/stderr, the JSON payload, the --json-file, \$GITHUB_OUTPUT and both child argv logs, across all six modes"
else
  fail "no credential value may reach any sink. The issue bodies and ops emails built from these fields are API payloads on a PUBLIC repository, so log masking does not reach them:\n$_p11_detail"
fi

echo "P12: a rejected credential's stderr is surfaced without echoing the credential"
# Un-swallowing the enumeration's stderr is the point of the change, and it is also the
# moment a credential could start appearing in a job log — the CLI is handed a bad secret
# and allowed to speak.
MOCK_ENUM_FAIL='Invalid Auth token' run_sut p12 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13"
_p12=1
grep -qF 'Invalid Auth token' "$OUT" || _p12=0
grep -qF "$FIX_CRED" "$OUT" && _p12=0
if [[ "$_p12" == "1" ]]; then
  pass "the CLI's rejection is visible and the credential is not"
else
  fail "dropping 2>/dev/null must surface the CLI's diagnosis without surfacing the credential it was handed"
fi

echo "P13: a config whose read fails is recorded by NAME, never by value"
JP13="$TMP/p13.json"
MOCK_UNREADABLE=prd_terraform MOCK_HTTP_BODY='{"success":true}' run_sut p13 200 \
  "prd|CF_API_TOKEN_X|synthetic-token-value-prd
prd_terraform|CF_API_TOKEN_X|synthetic-token-value-prd-terraform" $'prd\nprd_terraform' "--configs-floor 2 --json-file $JP13"
_p13=1
[[ "$(jget "$JP13" configs)" == "1" ]] || _p13=0
[[ "$(jget "$JP13" config_names)" == "prd" ]] || _p13=0
# No inventory here at all: an unreadable config must still be nameable, because that is
# the finding — not a gap in a denominator.
[[ "$(jget "$JP13" configs_unread)" == "prd_terraform" ]] || _p13=0
[[ "$(jget "$JP13" coverage)" == "degraded" ]] || _p13=0
grep -qF 'prd_terraform' "$OUT" || _p13=0
grep -qF 'synthetic-token-value-prd-terraform' "$OUT" && _p13=0
if [[ "$_p13" == "1" ]]; then
  pass "the unreadable config is named in configs_unread and in the report, with no value anywhere"
else
  fail "an enumerated-but-unreadable config must be recorded by NAME (it is the finding), must not enter the read count, and must never carry a secret value into the report (configs=$(jget "$JP13" configs), unread=$(jget "$JP13" configs_unread), coverage=$(jget "$JP13" coverage))"
fi

echo "P14: under GITHUB_ACTIONS every distinct scanned value is masked BEFORE the first probe"
# Actions auto-masks only `secrets.*`-sourced values, so everything read out of Doppler is
# unmasked in the job log by default. At 13 configs this is 13 distinct values transiting
# the runner rather than 1 — and the same change deliberately un-swallows stderr from the
# subsystem that handles them.
MOCK_GITHUB_ACTIONS=true MOCK_HTTP_BODY='{"success":true}' run_sut p14 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV13"
_p14=1
_p14_masks=$(grep -c '::add-mask::' "$OUT" 2>/dev/null || true)
[[ "${_p14_masks:-0}" == "13" ]] || _p14=0
# One per DISTINCT value, deduped, and naming the real bytes rather than a placeholder.
# `-x` (whole line), not a substring match: `…-value-prd` is a PREFIX of `…-value-prd_cla`
# and five other config names, so an unanchored count returns 7 and the dedup assertion
# would fail for a reason that has nothing to do with deduping.
for _cfg in prd ci cli_ops prd_workspaces_luks; do
  [[ "$(grep -cxF "::add-mask::synthetic-token-value-${_cfg}" "$OUT" 2>/dev/null || true)" == "1" ]] || _p14=0
done
# ORDERING, measured rather than assumed: at the moment of the first curl invocation, all
# 13 masks were already on stdout. "Masked eventually" is not the property — a value that
# reaches a probe before its mask can be echoed by a failing probe into an unmasked log.
[[ -f "$MASK_SNAPSHOT" ]] || _p14=0
[[ "$(cat "$MASK_SNAPSHOT" 2>/dev/null || echo missing)" == "13" ]] || _p14=0
if [[ "$_p14" == "1" ]]; then
  pass "13 distinct values, 13 ::add-mask:: directives, all emitted before the first probe"
else
  fail "every distinct scanned value must be registered with ::add-mask:: BEFORE the first probe (masks emitted=${_p14_masks:-0}, masks present at first probe=$(cat "$MASK_SNAPSHOT" 2>/dev/null || echo '<no probe>'))"
fi

echo "P14b: outside Actions nothing is masked — the directive is not printed into an operator's terminal"
MOCK_HTTP_BODY='{"success":true}' run_sut p14b 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13"
if ! grep -q '::add-mask::' "$OUT"; then
  pass "no ::add-mask:: outside GITHUB_ACTIONS"
else
  fail "::add-mask:: writes the value to stdout; outside Actions nothing consumes the directive, so it would print 13 live secrets into a local terminal for no benefit"
fi

echo "P15: DOPPLER_TOKEN and DOPPLER_CONFIG are unset once the credential is snapshotted"
# curl is given NO env prefix, so it inherits the SUT's own environment. If the SUT had
# kept relying on ambient variables rather than snapshotting and unsetting them, both
# would show up here — and a read site that forgot its `-c` would silently bind the
# ambient config instead of failing.
MOCK_AMBIENT_CONFIG=prd_terraform MOCK_HTTP_BODY='{"success":true}' run_sut p15 200 "$P3_FIXTURE" $'prd\nprd_terraform'
_p15=1
[[ -s "$CURL_ENV_LOG" ]] || _p15=0
[[ -s "$DOPPLER_ENV_LOG" ]] || _p15=0
grep -q 'TOKEN=set' "$CURL_ENV_LOG" && _p15=0
grep -q 'CONFIG=set' "$CURL_ENV_LOG" && _p15=0
grep -q 'CONFIG=set' "$DOPPLER_ENV_LOG" && _p15=0
_p15_tok=$(grep -c 'TOKEN=set' "$DOPPLER_ENV_LOG" 2>/dev/null || true)
_p15_all=$(grep -c . "$DOPPLER_ENV_LOG" 2>/dev/null || true)
[[ "${_p15_tok:-0}" == "${_p15_all:-1}" ]] || _p15=0
if [[ "$_p15" == "1" ]]; then
  pass "every Doppler call carries the credential explicitly; curl inherits neither variable, and the ambient DOPPLER_CONFIG reaches nothing"
else
  fail "the credential must be snapshotted and both variables then unset, so a missed read site fails loudly instead of binding the ambient config (doppler calls with a token: ${_p15_tok:-0}/${_p15_all:-0}; curl inherited: $(head -1 "$CURL_ENV_LOG" 2>/dev/null || echo '<no probe>'))"
fi

# ===========================================================================
# W1-W9 — CONSUMER WIRING (#7095).
#
# The detector above is only half the story. During the 2026-07-29 outage it produced the
# right answer three times over three days — naming the credential, the symptom, and the
# remedy — and production stayed down, because nothing CONSUMED the verdict. The gap was
# never detection; it was that the verdict blocked nothing and reached no one.
#
# These cases pin the wiring, not the detector: the gate that must fail the SSH bridge on a
# dead credential, and the escalation that must reach a human. They are static assertions
# over `.github/**` because that is where the wiring lives; there is no runtime seam to
# drive without dispatching a real workflow against production.
#
# ANCHORING DISCIPLINE (cq-assert-anchor-not-bare-token): every grep below anchors on a
# construct a COMMENT cannot produce — a `uses:` key, a `-replace=` flag, an `if:` guard —
# never on a bare word that the surrounding prose also names. These files are dense with
# explanatory comments that mention every token in play, so a bare-token grep here is
# guaranteed to false-pass.
# ---------------------------------------------------------------------------
GH_DIR="$REPO_ROOT/.github"
BRIDGE_ACTION="$GH_DIR/actions/cf-tunnel-ssh-bridge/action.yml"
DRIFT_WF="$GH_DIR/workflows/scheduled-terraform-drift.yml"
INFRA_WF="$GH_DIR/workflows/apply-web-platform-infra.yml"

# Fixture-precondition self-check. If a path moves, every assertion below would report a
# clean PASS on a file that does not exist — the exact vacuity shape this suite exists to
# prevent. Fail as a FIXTURE error, loudly, rather than as a silent green.
for _f in "$BRIDGE_ACTION" "$DRIFT_WF" "$INFRA_WF"; do
  [[ -f "$_f" ]] || { echo "FATAL: fixture precondition failed — $_f does not exist" >&2; exit 2; }
done

echo "W1: the bridge's liveness gate is defined exactly once, inside the shared composite"
# AC5d. Anchored at COMMAND POSITION (`^\s*bash `), not on the substring. The first
# version grepped the bare invocation, which the header comment describing the gate also
# satisfies — so a doc-only edit reddened it and a code-only deletion did not.
W1_N=$(grep -Ec '^\s*bash scripts/check-cloudflare-token-drift\.sh --only CI_SSH_ACCESS_TOKEN' "$BRIDGE_ACTION" 2>/dev/null || true)
if [[ "$W1_N" == "1" ]]; then
  pass "one definition in the composite — six callers inherit it"
else
  fail "expected exactly 1 scoped invocation at command position in the composite, found $W1_N (0 = gate absent or line-wrapped out of grep's reach; >1 = redundant)"
fi

echo "W2: the scoped check is not duplicated per bridge caller"
# There are exactly two legitimate call sites repo-wide and they are different consumers:
#   1. the composite    — gates the SSH bridge before any terraform destroy
#   2. the replace arm  — the AC10 halt gate, asserting a freshly minted credential is
#                         admitted BEFORE the operator is told the re-mint worked
# A third is per-caller duplication, which R2 rejected.
W2_TOTAL=$(grep -rEc '^\s*bash scripts/check-cloudflare-token-drift\.sh --only CI_SSH_ACCESS_TOKEN' "$GH_DIR" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
W2_IN_INFRA=$(grep -Ec '^\s*bash scripts/check-cloudflare-token-drift\.sh --only CI_SSH_ACCESS_TOKEN' "$INFRA_WF" 2>/dev/null || true)
if [[ "$W2_TOTAL" == "2" && "$W2_IN_INFRA" == "1" ]]; then
  pass "two call sites: the shared composite gate + the re-mint halt gate"
else
  fail "expected exactly 2 scoped call sites across .github/ (composite + re-mint halt gate), found $W2_TOTAL with $W2_IN_INFRA in apply-web-platform-infra.yml — a third means a caller re-implemented the bridge gate"
fi

# W3-W5 anchor on `echo "::error::<enum>` — an EMISSION, which a comment cannot produce.
# MEASURED: the previous bare-token form (`grep -qE 'ci_ssh_access_denied'`) was satisfied
# by this action's own header comment, which lists all three enums. Deleting the entire
# gate step left the suite fully green. That is the exact class this file's preamble
# claims to avoid, committed by the assertions immediately below it.
echo "W3: a DEAD verdict fails the bridge with the terminal reason ci_ssh_access_denied"
if grep -qE '^\s*echo "::error::ci_ssh_access_denied' "$BRIDGE_ACTION"; then
  pass "dead credential emits a named terminal reason"
else
  fail "the gate must EMIT ci_ssh_access_denied (echo \"::error::…\") — a header comment naming the enum is not the gate"
fi

echo "W4: DEAD and UNVERIFIABLE do not collapse into one reason"
# The detector exits 1 for BOTH "Cloudflare rejected this" and "nothing answered". Their
# remedies are opposite — #7127 exists because conflating them sends an operator to
# overwrite a healthy secret. Both consumers must branch on the structured verdict.
W4_OK=1
for _f in "$BRIDGE_ACTION" "$INFRA_WF"; do
  grep -qE '^\s*echo "::error::ci_ssh_liveness_unverifiable' "$_f" || W4_OK=0
  grep -qE '^\s*bash scripts/check-cloudflare-token-drift\.sh --only CI_SSH_ACCESS_TOKEN --json-file' "$_f" || W4_OK=0
done
if [[ "$W4_OK" == "1" ]]; then
  pass "both consumers branch on --json-file; unverifiable gets its own reason"
else
  fail "EVERY consumer must branch on the JSON verdict (dead vs unverifiable), not the bare exit code — exit 1 covers both. Missing in the composite and/or the re-mint halt gate."
fi

echo "W5: an unmeasured scan cannot be reported as clean"
# The detector reaches exit 0 with live=dead=unverifiable=0 when the key NAMES enumerate
# but every value read comes back empty (that read's status is discarded upstream). A gate
# that only checks dead/unverifiable then certifies ZERO pairs and lets terraform destroy.
W5_OK=1
for _f in "$BRIDGE_ACTION" "$INFRA_WF"; do
  grep -qE '^\s*if \[\[ "\$live" -gt 0 ' "$_f" || W5_OK=0
done
if [[ "$W5_OK" == "1" ]]; then
  pass "both consumers require a positive live count before reporting clean"
else
  fail "a clean verdict must be asserted POSITIVELY on live>0 — reaching success by exhausting negative branches reports clean on a scan that measured nothing"
fi

echo "W6: the gate is the FINAL step of the composite"
# Position IS the contract: the composite is consumed as one `uses:` step and GitHub
# guarantees step order, so "last step" ⇒ "before every caller step that follows".
# The step-boundary regex must match steps with NO `name:` key — `name:` is optional in a
# composite, so a `- uses:`/`- shell:` step appended after the gate would otherwise be
# invisible and W6 would pass while a step ran after the gate. MEASURED: appending a bare
# `- shell: bash / run:` step passed the previous `^    - name: `-only form.
W6_GATE_LINE=$(grep -nE '^\s*bash scripts/check-cloudflare-token-drift\.sh --only CI_SSH_ACCESS_TOKEN --json-file' "$BRIDGE_ACTION" | head -1 | cut -d: -f1)
W6_LAST_STEP=$(grep -nE '^    - (name|uses|shell|run|id|if|with|env):' "$BRIDGE_ACTION" | tail -1 | cut -d: -f1)
W6_GATE_STEP=$(awk -v g="${W6_GATE_LINE:-0}" 'NR<=g && /^    - (name|uses|shell|run|id|if|with|env):/{n=NR} END{print n+0}' "$BRIDGE_ACTION")
if [[ -n "$W6_GATE_LINE" && "$W6_GATE_STEP" == "$W6_LAST_STEP" && "$W6_LAST_STEP" != "0" ]]; then
  pass "gate is the last step — the bridge cannot report ready without having gated"
else
  fail "the gate must be the composite's final step (gate step starts at line ${W6_GATE_STEP:-none}, last step starts at line ${W6_LAST_STEP:-none})"
fi

echo "W7: the six bridge call sites are the expected six, by NAME"
# MEMBERSHIP, not cardinality. A count is invariant under substitution: MEASURED, pointing
# one caller at a different action and adding a spare `uses:` elsewhere kept the total at 6
# while a workflow that SSHes to a host silently lost the gate — and the failure string
# would have described exactly that, having never printed. Deriving the sorted filename
# list also makes a legitimate NEW adopter produce a diff that names the file, instead of
# a count mismatch blaming duplication.
W7_ACTUAL=$(grep -rlE '^\s+uses: \./\.github/actions/cf-tunnel-ssh-bridge\s*$' "$GH_DIR/workflows" 2>/dev/null | xargs -r -n1 basename | sort -u | paste -sd, -)
W7_EXPECTED="apply-deploy-pipeline-fix.yml,apply-web-platform-infra.yml,git-data-cutover.yml,workspaces-luks-cutover.yml,workspaces-luks-verify.yml"
W7_N=$(grep -rEc '^\s+uses: \./\.github/actions/cf-tunnel-ssh-bridge\s*$' "$GH_DIR/workflows" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
if [[ "$W7_ACTUAL" == "$W7_EXPECTED" && "$W7_N" == "6" ]]; then
  pass "5 workflows / 6 call sites (workspaces-luks-cutover uses it twice)"
else
  fail "bridge callers drifted. Expected files [$W7_EXPECTED] with 6 call sites; got [$W7_ACTUAL] with $W7_N. If you ADDED a caller, add it to W7_EXPECTED and bump the count; if a file disappeared from the list, that workflow silently lost the liveness gate."
fi

echo "W8: no -replace target names the .deploy service token"
# AC3. `.deploy` is the ONLY other remote write path to web-1, and web-1 cannot be
# replaced (cx33 stock 0/6). Replacing it on any failure between destroy and Doppler
# republish strands the host with no reachable channel at all.
# `[= ]` because terraform's flag parser accepts `-replace ADDRESS` as well as `-replace=`.
W8_HITS=$(grep -rEn -- '-replace[= ]+["'"'"']?[^ ]*access_service_token\.deploy' "$GH_DIR" 2>/dev/null || true)
if [[ -z "$W8_HITS" ]]; then
  pass "the working .deploy token is never a replace target"
else
  fail "a -replace target names the .deploy service token — this can strand an unreplaceable host: $W8_HITS"
fi

echo "W9: the ci-ssh-token-replace arm exists, is typo-guarded, and replaces the token"
# Anchored on the SHELL COMPARISON, not the token string: the confirm literal also appears
# in the dispatch-input DESCRIPTION prose, so a bare grep passed with the entire typo-guard
# step deleted. Likewise `-replace=` is anchored at flag position — MEASURED, commenting
# out the real flag left the previous form green while the arm planned nothing.
W9_OK=1
grep -qE '^\s+- ci-ssh-token-replace\s*$' "$INFRA_WF" || W9_OK=0
grep -qE '^\s*-replace=cloudflare_zero_trust_access_service_token\.ci_ssh' "$INFRA_WF" || W9_OK=0
grep -qE '"\$CONFIRM_RAW" != "REPLACE-CI-SSH-TOKEN"' "$INFRA_WF" || W9_OK=0
if [[ "$W9_OK" == "1" ]]; then
  pass "enum option, flag-position -replace, and an enforced typo-guard"
else
  fail "apply-web-platform-infra.yml needs the ci-ssh-token-replace enum option, a -replace= at flag position on the ci_ssh token, and a CONFIRM_RAW comparison against REPLACE-CI-SSH-TOKEN"
fi

echo "W10: the DEAD verdict's escalation is bound to the DEAD verdict"
# Two independent file-wide greps do not make an assertion: MEASURED, retargeting the
# escalation step's `if:` to verdict == 'unverifiable' left the previous form green, which
# restores the literal 2026-07-29 failure (dead credential → email only → nobody acts).
# Extract the step that files the issue and require ITS OWN guard to name 'dead'.
# Target the DEAD filer BY NAME, not by "first step containing --label
# action-required". The first-match form was correct while that was the only
# action-required filer in the job; the coverage filer added alongside the
# `coverage` output is a second one, and it sorts ABOVE the DEAD step — so
# first-match silently retargeted this assertion onto the wrong step and reported
# the DEAD guard missing when it was intact. Naming the step keeps the assertion
# pinned to the thing it is about, however many filers the job grows.
W10_STEP_START=$(awk '/^      - name: Open or update an action-required issue \(token drift — DEAD credential\)/{print NR; exit}' "$DRIFT_WF")
W10_GUARD=$(awk -v s="${W10_STEP_START:-0}" 'NR>s && NR<=s+3 && /^        if: /{print; exit}' "$DRIFT_WF")
# The priority-label conjunct needs the SAME step scoping as the guard above, and for the
# same reason — the retarget fixed one half and left this one file-wide. The coverage
# filer emits its own `--label priority/...` line, so a file-wide grep for a priority
# label is satisfiable by the WRONG step: measured, moving `p0-critical` off the DEAD
# filer and onto the coverage filer left this assertion PASS while the DEAD credential
# issue lost the label operator-digest sorts on. Bound to the DEAD step's own body, which
# runs to the next top-level `- name:`.
W10_BODY=$(awk -v s="${W10_STEP_START:-0}" 'NR>s { if (/^      - name: /) exit; print }' "$DRIFT_WF")
if [[ -n "$W10_STEP_START" ]] && grep -qE "verdict == 'dead'" <<<"$W10_GUARD" && grep -qE '^\s+--label priority/p0-critical' <<<"$W10_BODY"; then
  pass "the action-required filer is guarded on verdict == 'dead' and carries a priority label"
else
  fail "the step filing the action-required issue must itself be guarded on verdict == 'dead' (found guard: '${W10_GUARD:-none}') and must carry --label priority/p0-critical (operator-digest sorts on priority and caps the list, so an unprioritised issue is filed and still unseen)"
fi

# ---------------------------------------------------------------------------
# M1-M9 — MAP MODE (#7234): the per-config credential fan-out.
#
# The scan no longer asks Doppler to enumerate the project — no credential in this
# repository can — and instead receives one config-scoped read token per config as a JSON
# map. These cases cover what that shape can get wrong that the single-credential shape
# could not, and one thing it must keep doing exactly as before.
#
# The stub enforces the REAL binding rule here (see MOCK_TOKEN_BINDING): a token errors on
# a wrong -c rather than silently serving its bound config, measured against live Doppler
# on 2026-08-03. Without that, every case below would pass against a detector that ignored
# the binding entirely.
# ---------------------------------------------------------------------------
p_map_for() { # $1 = newline-separated configs -> {"cfg":"<distinct token>",...}
  local cfgs="$1" c out=""
  while read -r c; do
    [[ -z "$c" ]] && continue
    out+="$(printf '"%s":"dp.st.SYNTHETIC.%s"' "$c" "$c"),"
  done <<< "$cfgs"
  printf '{%s}' "${out%,}"
}
p_bind_for() { # $1 = configs, $2 = config each token is bound to (default: itself)
  local cfgs="$1" to="${2:-}" c out=""
  while read -r c; do
    [[ -z "$c" ]] && continue
    out+="dp.st.SYNTHETIC.${c}|${to:-$c}"$'\n'
  done <<< "$cfgs"
  printf '%s' "$out"
}
P_MAP13="$(p_map_for "$P_CFG13")"
P_BIND13="$TMP/bind13.txt";      p_bind_for "$P_CFG13"     > "$P_BIND13"
P_BIND_MISBOUND="$TMP/bindmis.txt"; p_bind_for "$P_CFG13" prd > "$P_BIND_MISBOUND"

echo "M1: 13 correctly-bound tokens read 13 of 13"
JM1="$TMP/m1.json"
MOCK_HTTP_BODY='{"success":true}' MOCK_CRED_MODE=map MOCK_TOKEN_MAP="$P_MAP13" \
  MOCK_TOKEN_BINDING="$P_BIND13" \
  run_sut m1 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV13 --json-file $JM1"
_m1=1
[[ "$RC" == "0" ]] || _m1=0
[[ "$(jget "$JM1" configs)" == "13" ]] || _m1=0
[[ "$(jget "$JM1" coverage)" == "at-floor" ]] || _m1=0
[[ "$(jget "$JM1" coverage_ratio)" == "13/13" ]] || _m1=0
[[ "$(jget "$JM1" config_names)" == "$P_CFG13_SORTED" ]] || _m1=0
[[ "$(jget "$JM1" configs_unread)" == "" ]] || _m1=0
# The map's keys ARE the config list: no `doppler configs` enumeration is performed.
[[ "$(grep -c '^configs' "$DOPPLER_LOG")" == "0" ]] || _m1=0
if [[ "$_m1" == "1" ]]; then
  pass "the fan-out reads every config from its own credential, with no project enumeration at all"
else
  fail "13 correctly-bound per-config tokens must read 13/13 at-floor with nothing unread, and must NOT call 'doppler configs' — enumeration is the capability no credential here has (rc=$RC, configs=$(jget "$JM1" configs), coverage=$(jget "$JM1" coverage), ratio=$(jget "$JM1" coverage_ratio), enum_calls=$(grep -c '^configs' "$DOPPLER_LOG"))"
fi

echo "M2 (n5'): 13 DISTINCT tokens all bound to ONE config must not report 13/13"
# THE PRODUCIBLE TERRAFORM DEFECT: `config = "prd"` in place of `config = each.key`. It
# mints 13 distinct tokens and 13 correct map keys, so it passes every shape check there
# is — pairwise distinctness included, which is why distinctness was rejected as the
# primary control. Only the read can tell, and only because a wrong -c errors.
JM2="$TMP/m2.json"
MOCK_HTTP_BODY='{"success":true}' MOCK_CRED_MODE=map MOCK_TOKEN_MAP="$P_MAP13" \
  MOCK_TOKEN_BINDING="$P_BIND_MISBOUND" \
  run_sut m2 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV13 --json-file $JM2"
_m2=1
[[ "$(jget "$JM2" coverage_ratio)" == "13/13" ]] && _m2=0   # the whole point
[[ "$(jget "$JM2" configs)" == "1" ]] || _m2=0
[[ "$(jget "$JM2" coverage)" == "degraded" ]] || _m2=0
grep -q 'token_drift_config_binding_mismatch' "$OUT" || _m2=0
if [[ "$_m2" == "1" ]]; then
  pass "a 13-token set all bound to one config grades 1/13 degraded and names the mismatch, not 13/13"
else
  fail "13 distinct tokens bound to a single config must NOT read as full coverage. This is the one mis-binding Terraform can produce and it passes shape validation — if it reports 13/13 the fan-out is decorative (configs=$(jget "$JM2" configs), coverage=$(jget "$JM2" coverage), ratio=$(jget "$JM2" coverage_ratio), mismatch_annotation=$(grep -c 'token_drift_config_binding_mismatch' "$OUT"))"
fi

echo "M3 (n4'): one revoked token -> 12 of 13, degraded, naming exactly that config"
JM3="$TMP/m3.json"
MOCK_HTTP_BODY='{"success":true}' MOCK_CRED_MODE=map MOCK_TOKEN_MAP="$P_MAP13" \
  MOCK_TOKEN_BINDING="$P_BIND13" MOCK_UNREADABLE="prd_ghcr" \
  run_sut m3 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV13 --json-file $JM3"
_m3=1
[[ "$(jget "$JM3" configs)" == "12" ]] || _m3=0
[[ "$(jget "$JM3" coverage)" == "degraded" ]] || _m3=0
[[ "$(jget "$JM3" configs_unread)" == "prd_ghcr" ]] || _m3=0
if [[ "$_m3" == "1" ]]; then
  pass "a single revoked per-config token is visible AS that config — the capability the whole-project credential never had"
else
  fail "one unreadable config must drop the count to 12, grade degraded, and name exactly it. Under the old project-scoped credential this failure was INVISIBLE: one revoked token was indistinguishable from a healthy fleet (configs=$(jget "$JM3" configs), coverage=$(jget "$JM3" coverage), unread=$(jget "$JM3" configs_unread))"
fi

echo "M4: a malformed map fails CLOSED to unknown, publishes 0/13, and makes ZERO doppler calls"
_m4=1
for _bad in '["not","an","object"]' '{}' '{"prd": 42}' '{"prd": ""}' 'not json at all' '{"PRD": "dp.st.x"}'; do
  JM4="$TMP/m4.json"; rm -f "$JM4"
  MOCK_CRED_MODE=map MOCK_TOKEN_MAP="$_bad" \
    run_sut m4 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV13 --json-file $JM4"
  [[ "$RC" == "2" ]]                                  || { _m4=0; echo "    '$_bad' exited $RC, expected 2"; }
  [[ -s "$JM4" ]]                                     || { _m4=0; echo "    '$_bad' published no verdict before exiting"; }
  [[ "$(jget "$JM4" coverage)" == "unknown" ]]        || { _m4=0; echo "    '$_bad' -> coverage $(jget "$JM4" coverage), expected unknown"; }
  [[ "$(jget "$JM4" coverage_ratio)" == "0/13" ]]     || { _m4=0; echo "    '$_bad' -> ratio $(jget "$JM4" coverage_ratio), expected 0/13"; }
  [[ ! -s "$DOPPLER_LOG" ]]                           || { _m4=0; echo "    '$_bad' invoked doppler $(grep -c . "$DOPPLER_LOG") time(s) before validating the map"; }
done
if [[ "$_m4" == "1" ]]; then
  pass "six malformed map shapes each publish unknown at 0/13 before exit 2, with no Doppler call made"
else
  fail "a credential SOURCE this run could not parse is not a measurement: it must publish 'unknown' (fail-closed), never 'degraded' (which asserts the credential is absent or narrowed — a claim a run that made no call cannot support), and it must not reach the network first"
fi

echo "M5: an ABSENT or EMPTY map is degraded 0/13, NOT unknown — the merge->apply window"
# D3 pins mode selection on -n rather than definedness precisely for this. A workflow
# writing `DOPPLER_TOKEN_MAP: ${{ secrets.X }}` with the secret not yet published yields a
# DEFINED, EMPTY variable, and that window is guaranteed to occur on every rollout of this
# change. `degraded` names a missing credential; `unknown` would tell the operator the
# Doppler identity is not at fault, which is the wrong remedy in the one window it fires.
_m5=1
for _mode in map_empty unset; do
  JM5="$TMP/m5.json"; rm -f "$JM5"
  MOCK_CRED_MODE="$_mode" run_sut m5 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV13 --json-file $JM5"
  [[ "$RC" == "2" ]]                              || { _m5=0; echo "    mode=$_mode exited $RC"; }
  [[ "$(jget "$JM5" coverage)" == "degraded" ]]   || { _m5=0; echo "    mode=$_mode -> $(jget "$JM5" coverage), expected degraded"; }
  [[ "$(jget "$JM5" coverage_ratio)" == "0/13" ]] || { _m5=0; echo "    mode=$_mode -> ratio $(jget "$JM5" coverage_ratio)"; }
  [[ ! -s "$DOPPLER_LOG" ]]                       || { _m5=0; echo "    mode=$_mode reached the CLI with no credential"; }
done
if [[ "$_m5" == "1" ]]; then
  pass "an empty map and an unset map both land in the missing-credential arm at degraded 0/13"
else
  fail "an empty DOPPLER_TOKEN_MAP must be diagnosed as a MISSING credential (degraded), not as a malformed one (unknown). Selecting the mode on definedness instead of non-emptiness inverts this, and the merge->apply window hits it on every rollout"
fi

echo "M6: both credentials set is ambiguous — exit 2, no read attempted"
JM6="$TMP/m6.json"
MOCK_CRED_MODE=both MOCK_TOKEN_MAP="$P_MAP13" \
  run_sut m6 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV13 --json-file $JM6"
_m6=1
[[ "$RC" == "2" ]] || _m6=0
[[ ! -s "$DOPPLER_LOG" ]] || _m6=0
if [[ "$_m6" == "1" ]]; then
  pass "DOPPLER_TOKEN_MAP and DOPPLER_TOKEN together refuse to guess a precedence"
else
  fail "two credentials selecting different scan modes have no defensible precedence — picking one silently would grade a config set nobody asked for (rc=$RC, doppler_calls=$(grep -c . "$DOPPLER_LOG"))"
fi

echo "M7 (NFR1): every map credential is masked BEFORE the first doppler invocation"
JM7="$TMP/m7.json"
MOCK_GITHUB_ACTIONS=true MOCK_HTTP_BODY='{"success":true}' MOCK_CRED_MODE=map \
  MOCK_TOKEN_MAP="$P_MAP13" MOCK_TOKEN_BINDING="$P_BIND13" \
  run_sut m7 200 "$P_SEC13" "$P_CFG13" "--configs-floor 13 --inventory $P_INV13 --json-file $JM7"
_m7=1
_masks_at_first_doppler=$(cat "$MASK_SNAPSHOT_DOPPLER" 2>/dev/null || echo "<none>")
[[ "$_masks_at_first_doppler" == "13" ]] || _m7=0
for _c in prd ci dev; do grep -q "::add-mask::dp.st.SYNTHETIC.${_c}\$" "$OUT" || _m7=0; done
if [[ "$_m7" == "1" ]]; then
  pass "all 13 credentials are registered with ::add-mask:: before the CLI is invoked even once"
else
  fail "Actions masks the map as ONE opaque string, so the values extracted from it are unmasked — and this detector deliberately does not suppress the Doppler CLI's stderr, so a rejected token can print itself into the job log. Masking must complete BEFORE the first invocation, not merely happen (masks at first doppler call: ${_masks_at_first_doppler}, expected 13)"
fi

echo "M8: single-credential mode is unchanged on the REAL argv of every legacy call site"
# None of the five shipped invocations passes --configs-floor, so all of them take the
# default of 1. Driving the real argv is the point: a case invented for this suite could
# pass while every actual caller broke.
_m8=1
_m8_case() { # $1=label $2=fixture $3=only_arg  (single credential, as every legacy site uses)
  local jf="$TMP/$1.json"; rm -f "$jf"
  MOCK_HTTP_BODY='{"success":true}' run_sut "$1" 200 "$2" "prd" "$3 --json-file $jf"
  [[ "$RC" == "0" ]] || { _m8=0; echo "    $1: rc=$RC"; return; }
  [[ "$(jget "$jf" configs_floor)" == "1" ]] || { _m8=0; echo "    $1: floor=$(jget "$jf" configs_floor), expected the default 1"; }
  [[ "$(jget "$jf" configs)" == "1" ]] || { _m8=0; echo "    $1: configs=$(jget "$jf" configs)"; }
  # The credential must still be delivered explicitly on every call, never ambiently.
  grep -q 'TOKEN=set' "$DOPPLER_ENV_LOG" || { _m8=0; echo "    $1: the credential was not delivered explicitly"; }
}
# The REAL argv of the shipped call sites, each with the fixture that actually carries the
# key it filters on — a --only whose key is absent trips the non-vacuity gate, which would
# make this case assert the gate rather than the single-credential contract.
_m8_case m8a "$ACCESS_FIXTURE"  "--only REGISTRY_PUSH_ACCESS_TOKEN"
_m8_case m8b "$CI_SSH_FIXTURE"  "--only CI_SSH_ACCESS_TOKEN"
_m8_case m8c "$P_SEC13"         ""
if [[ "$_m8" == "1" ]]; then
  pass "the five legacy single-credential call sites see the same behaviour, floor default included"
else
  fail "single-credential mode must be byte-for-byte what it was: the release preflight, the infra apply and the tunnel bridge actions all drive it, none passes --configs-floor, and two are branch-scoped"
fi

echo "M9 (C-d): a DUPLICATE in the enumeration must not inflate the config count"
# THE MUTATION PROOF FOR `sort -u`, and it is deliberately NOT the mis-binding case.
#
# The plan asserted that removing `-u` would make the 13-tokens-one-config case report
# 13/13. Measured: it does not, and cannot. That defect makes twelve reads FAIL (a wrong
# -c errors), so twelve configs never enter CONFIG_NAMES at all and there is nothing to
# deduplicate — the case passes identically with `sort` and `sort -u`, which was confirmed
# by mutation before this case was written.
#
# The reachable producer is the ENUMERATION. In single mode the config list is whatever
# `doppler configs` returned, and nothing downstream re-checks it for repeats; a listing
# that named one config twice would length-2 CONFIG_NAMES for one config actually read.
# That is what `-u` defends, and this case is what makes removing it go red.
JM9="$TMP/m9.json"
MOCK_HTTP_BODY='{"success":true}' \
  run_sut m9 200 "$P_SEC13" $'prd\nprd' "--configs-floor 1 --inventory $P_INV13 --json-file $JM9"
_m9=1
[[ "$(jget "$JM9" configs)" == "1" ]] || _m9=0
[[ "$(jget "$JM9" config_names)" == "prd" ]] || _m9=0
if [[ "$_m9" == "1" ]]; then
  pass "a config listed twice is counted once — the count reflects configs READ, not listings received"
else
  fail "'configs' is the number the entire coverage ladder grades, so a duplicate in the enumeration inflates coverage directly: one config read would report 2, and at a floor of 2 a single-config credential would publish 'at-floor'. Deduplication is the control, not tidiness (configs=$(jget "$JM9" configs), names=$(jget "$JM9" config_names))"
fi

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
# ANTI-VACUITY FLOOR. Without it, deleting every assertion call yields
# "0/0 passed, 0 failed" and exit 0 — measured — and test-all.sh reads only the exit code,
# so a suite that ran NOTHING is indistinguishable from one where everything passed. A
# FLOOR, not equality: adding a case must not require editing this line.
#
# Raised 13 -> 24 with the Access-stamp rewrite, then -> 40, then -> 50 with the #7095
# consumer-wiring block (W1-W10). 50 against 52 running keeps main's 2-assertion slack —
# derived from a green run, not chosen. At 13 against 26 running assertions the floor had
# 13 assertions of slack — measured: deleting T14 through T19, i.e. the ENTIRE arm the
# suite exists to cover, still reported "13/13 passed" and exit 0. A floor that far below
# the real count cannot distinguish "the feature's tests were removed" from "they passed".
# Still a floor, not equality, so adding a case does not require editing it — but it is now
# close enough to the count that deleting a feature's cases trips it.
# Raised 50 -> 53 with T14c. The remaining 2-assertion slack was deliberate but is not
# defensible: a floor below the count licenses deleting exactly the cases under review
# (measured in the sibling consumer suite — 20 against 22 let the two tests carrying that
# PR's only in-run deliverable be deleted at "20/20 passed", exit 0). Still a floor, so
# ADDING a case needs no edit here; only a removal trips it, which is the point.
#
# Raised 53 -> 78 with P1-P15 (the single-credential path and the coverage ladder). 78 is
# the REALIZED count on a green run, not a round number: the plan's provisional 68 was
# written before the cases were split per narrowing (P5b runs three) and per credential
# state (P4 runs two), and a floor below the realized count would license deleting exactly
# the cases this change adds.
#
# Raised 78 -> 80 with P16 (the committed inventory executed against the workflow-declared
# floor) and P17 (the positive-work floor). 80 is the REALIZED count on a green run.
#
# Raised 80 -> 89 with M1-M9, the per-config credential map (#7234): the fan-out itself,
# the producible mis-binding, a single revoked token, six malformed-map shapes, the
# empty-vs-malformed distinction, the both-credentials refusal, the mask ORDERING, the
# legacy single-credential argv, and the duplicate-enumeration case that is the actual
# mutation proof for `sort -u`. 89 is the REALIZED count on a green run.
if [[ "$((PASS + FAIL))" -lt 89 ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran; expected >= 89. The suite did not execute what it claims to." >&2
  exit 1
fi
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
