#!/usr/bin/env bash
# Unit + mutation battery for resolve_inngest_link in ci-deploy.sh (#10136, Guard 1 of the Inngest TLS plan).
#
# The resolver is the single chokepoint that decides which Inngest link the web container is handed
# (http only on a clean not-found or a lapsed lease; otherwise https or a FAILED deploy, never a
# downgrade) and which CA file becomes a trust anchor for every Node outbound TLS connection. This suite
# extracts the block between the `inngest-link-resolver` markers of the REAL ci-deploy.sh, sources it
# under stubs (`curl`, `logger`, `_doppler_get_observed`) and drives it against throwaway certificates
# synthesized here (never a real certificate or key, cq-test-fixtures-synthesized-only).
#
# ROWS are addressable functions (`row_<id>`) so a MUTATION row can run only the rows it must redden.
#   Guard 1 rows covered here: 5 (self-gate), 8 (third value), 9 (read error), 10 (CA validation, one row
#   per variant), 11 (allowlist, lease), plus the scope guard and the recheck. Harness rows:
#   H1  the curl stub is replaced by one that always succeeds: the CA-withheld case must go RED (a suite that
#       cannot see a vacuous self-gate proves nothing);
#   H2  must-PASS non-canonical input (flag unset, valid CA with CRLF / trailing blanks / leading prose,
#       two certificates): a suite that only accepts the canonical bytes is vacuous the other way;
#   H3  Node: a CA:FALSE self-signed certificate IS accepted as an extra root, and a leaf signed with its key
#       is NOT (a non-CA anchor cannot issue).
#
# Run: bash apps/web-platform/infra/inngest-link-resolver.test.sh   (unprivileged; openssl, python3, node optional for H3)
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_DEPLOY="${INNGEST_LINK_TEST_SRC:-$SCRIPT_DIR/ci-deploy.sh}"

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS + 1)); printf '[ok] %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '[FAIL] %s\n' "$1"; }
skip() { SKIP=$((SKIP + 1)); printf '[skip] %s\n' "$1"; }
die()  { printf 'HARNESS ABORT: %s\n' "$*" >&2; exit 2; }

# ok()/bad() self-test in a subshell, reported through printf + exit 2 (never through bad()).
got="$( PASS=0; FAIL=0; ok st-ok >/dev/null; bad st-bad >/dev/null; printf '%s/%s' "$PASS" "$FAIL" )"
[ "$got" = "1/1" ] || { printf 'INSTRUMENT FAIL - inngest-link-resolver.test.sh: ok()/bad() self-test got %s, want 1/1\n' "$got" >&2; exit 2; }

command -v openssl >/dev/null 2>&1 || die "openssl is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
command -v base64 >/dev/null 2>&1 || die "base64 is required"

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY\n' >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *) printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

WORK="$(mktemp -d -t inngest-link-resolver.XXXXXX)" || die "mktemp -d failed"
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT
FX="$WORK/fx"; BIN="$WORK/bin"; RUNS="$WORK/runs"
mkdir -p "$FX" "$BIN" "$RUNS" || die "mkdir failed"

# ---------------------------------------------------------------------------------------
# FIXTURES: throwaway certificates (ECDSA P-256), generated here, never committed.
# ---------------------------------------------------------------------------------------
gen_cert() { # <name> <san ext> <basicConstraints> <eku or -> [subj]
  local n="$1" san="$2" bc="$3" eku="$4" subj="${5:-/CN=soleur-inngest-link}" args=()
  args+=(-addext "subjectAltName=$san" -addext "basicConstraints=critical,$bc")
  if [ "$eku" != "-" ]; then args+=(-addext "extendedKeyUsage=$eku"); fi
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$FX/$n.key" -out "$FX/$n.crt" \
    -days 3650 -subj "$subj" "${args[@]}" >/dev/null 2>&1 || die "openssl req failed for $n"
}
gen_cert good  "IP:10.0.1.40"            "CA:FALSE" "serverAuth"
gen_cert other "IP:10.0.1.40"            "CA:FALSE" "serverAuth" "/CN=another-server"
gen_cert badsan "IP:10.0.1.41"           "CA:FALSE" "serverAuth"
gen_cert dnssan "IP:10.0.1.40,DNS:inngest.example.invalid" "CA:FALSE" "serverAuth"
gen_cert catrue "IP:10.0.1.40"           "CA:TRUE"  "serverAuth"
gen_cert clientauth "IP:10.0.1.40"       "CA:FALSE" "clientAuth"
gen_cert bothauth "IP:10.0.1.40"         "CA:FALSE" "serverAuth,clientAuth"
gen_cert noeku "IP:10.0.1.40"            "CA:FALSE" "-"
gen_cert loop  "IP:127.0.0.1"            "CA:FALSE" "serverAuth" "/CN=loopback-anchor"

# An expired self-signed certificate (openssl ca -selfsign with an explicit validity window).
make_expired() {
  local d="$FX/exp"; mkdir -p "$d"
  ( cd "$d" || exit 1
    openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout k.pem -out r.csr -subj /CN=soleur-inngest-link >/dev/null 2>&1 || exit 1
    printf '[ca]\ndefault_ca=c\n[c]\ndatabase=idx\nserial=serial\nnew_certs_dir=.\ndefault_md=sha256\npolicy=p\nunique_subject=no\n[p]\ncommonName=supplied\n[ext]\nsubjectAltName=IP:10.0.1.40\nbasicConstraints=critical,CA:FALSE\nextendedKeyUsage=serverAuth\n' > ca.cnf
    : > idx; echo 01 > serial
    openssl ca -batch -selfsign -config ca.cnf -keyfile k.pem -in r.csr -out out.pem -startdate 20200101000000Z -enddate 20200102000000Z -extensions ext -notext >/dev/null 2>&1 || exit 1
    openssl x509 -in out.pem -outform PEM > "$FX/expired.crt" ) || die "could not synthesize the expired certificate"
}
make_expired

# A leaf that is NOT self-signed: SAN/EKU/CA:FALSE all fine, issuer is another name (signed by `other`).
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$FX/leaf.key" -out "$FX/leaf.csr" -subj /CN=soleur-inngest-link >/dev/null 2>&1 || die "leaf csr failed"
printf 'subjectAltName=IP:10.0.1.40\nbasicConstraints=critical,CA:FALSE\nextendedKeyUsage=serverAuth\n' > "$FX/leaf.ext"
openssl x509 -req -in "$FX/leaf.csr" -CA "$FX/other.crt" -CAkey "$FX/other.key" -CAcreateserial -out "$FX/notself.crt" -days 3650 -extfile "$FX/leaf.ext" >/dev/null 2>&1 || die "notself leaf failed"

# Derived PEM variants (CA text delivered through Doppler, before the base64 the secret stores).
cp "$FX/good.crt" "$FX/v-good.pem"
cat "$FX/good.crt" "$FX/good.key" > "$FX/v-privkey-concat.pem"
cp "$FX/good.key" "$FX/v-privkey-only.pem"
cp "$FX/badsan.crt" "$FX/v-badsan.pem"
cp "$FX/dnssan.crt" "$FX/v-dnssan.pem"
cp "$FX/catrue.crt" "$FX/v-catrue.pem"
cp "$FX/clientauth.crt" "$FX/v-clientauth.pem"
cp "$FX/bothauth.crt" "$FX/v-bothauth.pem"
cp "$FX/noeku.crt" "$FX/v-noeku.pem"
cp "$FX/expired.crt" "$FX/v-expired.pem"
cp "$FX/notself.crt" "$FX/v-notself.pem"
cat "$FX/good.crt" "$FX/good.crt" "$FX/good.crt" > "$FX/v-three.pem"
cat "$FX/good.crt" "$FX/other.crt" > "$FX/v-two.pem"
printf 'this is not a certificate\n' > "$FX/v-garbage.pem"
: > "$FX/v-empty.pem"
{ cat "$FX/good.crt"; for _i in $(seq 1 54); do printf '# padding line %03d to push the PEM text just over four KiB of input\n' "$_i"; done; } > "$FX/v-oversize.pem"
{ cat "$FX/good.crt"; printf 'x-----BEGIN PRIVATE KEY-----\n'; sed '1d;$d' "$FX/good.key"; printf -- '-----END PRIVATE KEY-----\n'; } > "$FX/v-privkey-prefixed.pem"
# non-canonical but valid: CRLF endings, trailing blanks, leading prose, extra blank lines, no final newline
{ printf 'Soleur Inngest link CA (comment, not PEM)\r\n\r\n'; sed 's/$/\r/' "$FX/good.crt"; printf '\r\n\r\n'; } | sed 's/-----$/----- /' > "$FX/v-noncanon.pem"
printf '%s' "$(cat "$FX/good.crt")" > "$FX/v-nonl.pem"
# a PEM whose prose tries to spoof link-env keys (must never reach /etc/soleur/inngest-link.env)
{ printf 'INNGEST_LINK_URL=http://evil.invalid:1\nINNGEST_LINK_SCHEME=http\n'; cat "$FX/good.crt"; } > "$FX/v-spoof.pem"

fp() { openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null; }
GOOD_FP="$(fp "$FX/good.crt")"
[ -n "$GOOD_FP" ] || die "could not fingerprint the good certificate"

# ---------------------------------------------------------------------------------------
# STUBS: curl (a faithful-enough TLS verifier), logger. `_doppler_get_observed` is defined in the scenario.
# ---------------------------------------------------------------------------------------
cat > "$BIN/logger" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${RUN_DIR:?}/logger.log"
exit 0
STUB
cat > "$BIN/curl" <<'STUB'
#!/bin/bash
# Records argv; behaves like curl --cacert against a server that presents $FX_SERVER_CERT:
#   -k / --insecure                  -> accepted (this is exactly what the resolver must never pass)
#   --cacert F, F fingerprint match  -> 200
#   no --cacert / mismatch / no PEM  -> exit 60 (certificate verification failed)
printf '%s\n' "$*" >> "${RUN_DIR:?}/curl.argv"
if [ "${FX_CURL_ALWAYS_OK:-}" = 1 ]; then printf '200'; exit 0; fi
cacert=""; insecure=0; prev=""
for a in "$@"; do
  case "$a" in -k|--insecure|-sk|-ks) insecure=1 ;; esac
  if [ "$prev" = "--cacert" ]; then cacert="$a"; fi
  prev="$a"
done
if [ "$insecure" = 1 ]; then printf '200'; exit 0; fi
[ -n "$cacert" ] || exit 60
want="$(openssl x509 -in "$FX_SERVER_CERT" -noout -fingerprint -sha256 2>/dev/null)"
got="$(openssl x509 -in "$cacert" -noout -fingerprint -sha256 2>/dev/null)"
if [ -n "$got" ] && [ "$got" = "$want" ]; then printf '200'; exit 0; fi
exit 60
STUB
cat > "$BIN/sleep" <<'STUB'
#!/bin/bash
exit 0
STUB
cat > "$BIN/date" <<'STUB'
#!/bin/bash
# a pinned clock for the lease arithmetic: `date +%s` prints $FX_NOW when set, everything else is the real date
if [ -n "${FX_NOW:-}" ] && [ "${1:-}" = "+%s" ]; then printf '%s\n' "$FX_NOW"; exit 0; fi
exec /usr/bin/date "$@"
STUB
cat > "$BIN/docker" <<'STUB'
#!/bin/bash
# canary-layer stub: `docker inspect` prints the container env per $FX_INSPECT; `docker exec ... env -u NODE_EXTRA_CA_CERTS ...` is the
# negative control (prints $FX_NEG), any other `docker exec` is the positive script (prints $FX_POS). FX_EXEC_RC forces an exit code.
printf '%s\n' "$*" >> "${RUN_DIR:?}/docker.argv"
case "$1" in
  inspect)
    case "${FX_INSPECT:-https}" in
      https) printf 'PATH=/usr/bin\nINNGEST_BASE_URL=https://10.0.1.40:8443\nNODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem\n' ;;
      http) printf 'INNGEST_BASE_URL=http://10.0.1.40:8288\nNODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem\n' ;;
      noca) printf 'INNGEST_BASE_URL=https://10.0.1.40:8443\n' ;;
      twice) printf 'INNGEST_BASE_URL=https://10.0.1.40:8443\nINNGEST_BASE_URL=http://10.0.1.40:8288\nNODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem\n' ;;
      none) exit 1 ;;
    esac
    exit 0 ;;
  exec)
    if [ -n "${FX_EXEC_RC:-}" ]; then exit "$FX_EXEC_RC"; fi
    case "$*" in
      *"env -u NODE_EXTRA_CA_CERTS"*) printf '%s\n' "${FX_NEG-inngest_link_canary_neg=verify_error}" ;;
      *) printf '%s\n' "${FX_POS-inngest_link_canary health=ok events=ok send=ok registry=ok}" ;;
    esac
    exit 0 ;;
esac
exit 0
STUB
sed -i "s#/usr/bin/date#$(command -v date)#" "$BIN/date"
chmod +x "$BIN/logger" "$BIN/curl" "$BIN/sleep" "$BIN/date" "$BIN/docker"

# ---------------------------------------------------------------------------------------
# THE BLOCK UNDER TEST (extracted from the real file; a mutation edits a COPY)
# ---------------------------------------------------------------------------------------
BLOCK_REAL="$WORK/block.real.sh"
extract_block() { # <src> <dst>
  sed -n '/^# >>> inngest-link-resolver >>>$/,/^# <<< inngest-link-resolver <<</p' "$1" > "$2" || return 1
  [ "$(grep -c '^# >>> inngest-link-resolver >>>$' "$2")" = 1 ] && [ "$(grep -c '^# <<< inngest-link-resolver <<<$' "$2")" = 1 ]
}
extract_block "$CI_DEPLOY" "$BLOCK_REAL" || BLOCK_REAL=""

NOW="$(date +%s)"

# ---------------------------------------------------------------------------------------
# SCENARIO RUNNER: one resolver call in a fresh subshell and a fresh "etc" dir.
#   env: SNAP_EXTRA (extra snapshot lines), SNAP_SCOPE (override the two scope lines), CA_MODE, CA_FILE,
#        SERVER_CERT, SKIP_SNAPSHOT=1 (pass a path that does not exist), PRE (a bash snippet run in $ETC first)
# Result files in $RUN: out (key=value), logger.log, curl.argv, and the etc dir listing in $ETC.
# ---------------------------------------------------------------------------------------
RUN=""; ETC=""
scenario() { # <block file> <run id>
  local block="$1" id="$2" snap
  RUN="$RUNS/$id"; ETC="$RUN/etc"
  assert_fixture_dir "$RUN"
  rm -rf "$RUN"; mkdir -p "$ETC" || die "mkdir $ETC"
  : > "$RUN/logger.log"; : > "$RUN/curl.argv"
  snap="$RUN/snapshot.env"
  { printf '%b' "${SNAP_SCOPE-DOPPLER_PROJECT=soleur\nDOPPLER_CONFIG=prd\nDOPPLER_ENVIRONMENT=prd\n}"
    printf 'KEY=value\nGITHUB_APP_ID=4242\n'
    printf '%b' "${SNAP_EXTRA:-}"; } > "$snap"
  [ "${SKIP_SNAPSHOT:-}" = 1 ] && snap="$RUN/does-not-exist.env"
  [ -n "${PRE:-}" ] && ( cd "$ETC" && eval "$PRE" )
  (
    export FX_NOW="$NOW"
    export RUN_DIR="$RUN" FX_SERVER_CERT="${SERVER_CERT:-$FX/good.crt}" FX_CURL_ALWAYS_OK="${CURL_ALWAYS_OK:-}"
    export PATH="$BIN:${PATH_OVERRIDE:-$PATH}"
    LOG_TAG=ci-deploy
    unset SENTRY_INGEST_DOMAIN SENTRY_PROJECT_ID SENTRY_PUBLIC_KEY
    # shellcheck disable=SC1090
    source "$block" || exit 99
    INNGEST_LINK_DIR="$ETC"
    INNGEST_LINK_SELFGATE_ATTEMPTS=2
    _doppler_get_observed() { # <NAME> <DEST_VAR>: the real contract, driven by CA_MODE
      CRED_RC=0; CRED_EMPTY=0; CRED_ERR=""
      case "${CA_MODE:-absent}" in
        ok) printf -v "$2" '%s' "$(base64 -w0 < "${CA_FILE:-$FX/v-good.pem}")"; return 0 ;;
        raw) printf -v "$2" '%s' "${CA_RAW:-}"; return 0 ;;
        empty) printf -v "$2" '%s' ""; CRED_EMPTY=1; return 1 ;;
        error) printf -v "$2" '%s' ""; CRED_RC=1; CRED_EMPTY=1; return 1 ;;
        *) printf -v "$2" '%s' ""; CRED_RC=1; CRED_EMPTY=1; return 1 ;;
      esac
    }
    rc=0
    resolve_inngest_link "$snap" || rc=$?
    {
      printf 'rc=%s\n' "$rc"
      printf 'url=%s\n' "${INNGEST_BASE_URL_RESOLVED-<unset>}"
      printf 'state=%s\n' "${INNGEST_LINK_STATE-<unset>}"
      printf 'reason=%s\n' "${INNGEST_LINK_REASON-<unset>}"
      rr=0; inngest_link_ca_recheck || rr=$?
      printf 'recheck=%s\n' "$rr"
    } > "$RUN/out"
  ) > "$RUN/stdout" 2>&1
  [ -s "$RUN/out" ] || printf 'rc=harness\n' > "$RUN/out"
}
val() { grep -m1 "^$1=" "$RUN/out" | cut -d= -f2-; }
caf() { printf '%s/inngest-ca.pem' "$ETC"; }
envf() { printf '%s/inngest-link.env' "$ETC"; }
ca_fp() { fp "$(caf)"; }
leftovers() { ls -A "$ETC" 2>/dev/null | grep -vxE 'inngest-ca\.pem|inngest-link\.env' || true; }
log_has() { grep -qF -- "$1" "$RUN/logger.log"; }
env_exact() { # <url> <scheme> <cacert>
  [ "$(cat "$(envf)" 2>/dev/null)" = "$(printf 'INNGEST_LINK_URL=%s\nINNGEST_LINK_SCHEME=%s\nINNGEST_LINK_CACERT=%s' "$1" "$2" "$3")" ]
}

# row bodies: print nothing, return 0 when the property holds. `why` names the first failed clause.
WHY=""
need() { # <desc> <cond rc>
  if [ "$2" -ne 0 ]; then WHY="${WHY:-$1}"; return 1; fi
  return 0
}

ONFLAG='INNGEST_LINK_TLS=1\n'
fails_closed() { # the shared "deploy fails, nothing handed to the container" predicate
  need "rc=$(val rc), want non-zero" "$([ "$(val rc)" != 0 ] && echo 0 || echo 1)" || return 1
  need "a URL was handed over: $(val url)" "$([ "$(val url)" = "" ] && echo 0 || echo 1)" || return 1
  need "a reason was not set" "$([ -n "$(val reason)" ] && echo 0 || echo 1)" || return 1
  need "link env advertises https after a failure" "$(if [ -f "$(envf)" ] && grep -q 'SCHEME=https' "$(envf)"; then echo 1; else echo 0; fi)" || return 1
  need "a temp file was left behind: $(leftovers)" "$([ -z "$(leftovers)" ] && echo 0 || echo 1)" || return 1
}
ok_https() {
  need "rc=$(val rc), want 0 (reason $(val reason))" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "url=$(val url)" "$([ "$(val url)" = https://10.0.1.40:8443 ] && echo 0 || echo 1)" || return 1
  need "link env is not the https triple" "$(env_exact https://10.0.1.40:8443 https "$(caf)"; echo $?)" || return 1
  need "CA file is not the canonical good certificate" "$([ "$(ca_fp)" = "$GOOD_FP" ] && echo 0 || echo 1)" || return 1
  need "a temp file was left behind: $(leftovers)" "$([ -z "$(leftovers)" ] && echo 0 || echo 1)" || return 1
}

# --- default path -----------------------------------------------------------------------
row_A1_unset_http() {
  SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID"
  need "rc=$(val rc)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "url=$(val url)" "$([ "$(val url)" = http://10.0.1.40:8288 ] && echo 0 || echo 1)" || return 1
  need "state=$(val state)" "$([ "$(val state)" = http_default ] && echo 0 || echo 1)" || return 1
  need "the CA placeholder file does not exist" "$([ -f "$(caf)" ] && echo 0 || echo 1)" || return 1
  need "the CA placeholder is not empty" "$([ ! -s "$(caf)" ] && echo 0 || echo 1)" || return 1
  need "link env is not the http triple" "$(env_exact http://10.0.1.40:8288 http ''; echo $?)" || return 1
  need "no curl self-gate may run on the http path" "$([ ! -s "$RUN/curl.argv" ] && echo 0 || echo 1)" || return 1
  need "recheck must be a no-op with the flag off (rc=$(val recheck))" "$([ "$(val recheck)" = 0 ] && echo 0 || echo 1)" || return 1
}
row_A1b_unset_with_ca_http() {
  SNAP_EXTRA='' CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$1" "$ROW_ID"
  need "url=$(val url)" "$([ "$(val url)" = http://10.0.1.40:8288 ] && echo 0 || echo 1)" || return 1
  need "the validated CA was not installed" "$([ "$(ca_fp)" = "$GOOD_FP" ] && echo 0 || echo 1)" || return 1
}
row_A1c_unset_empty_value_is_absent() {
  SNAP_EXTRA='INNGEST_LINK_TLS=\n' CA_MODE=absent scenario "$1" "$ROW_ID"
  need "rc=$(val rc)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "url=$(val url)" "$([ "$(val url)" = http://10.0.1.40:8288 ] && echo 0 || echo 1)" || return 1
}

# --- flag on, the happy paths ---------------------------------------------------------------
row_A2_flag_on_https() {
  SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$1" "$ROW_ID"
  ok_https || return 1
  need "the CA file mode is not 0644: $(stat -c %a "$(caf)" 2>/dev/null)" "$([ "$(stat -c %a "$(caf)" 2>/dev/null)" = 644 ] && echo 0 || echo 1)" || return 1
  local argv; argv="$(cat "$RUN/curl.argv")"
  need "the self-gate did not run curl --cacert <the installed file> against https://10.0.1.40:8443/health" \
    "$(case "$argv" in *"--cacert $(caf)"*"https://10.0.1.40:8443/health"*) echo 0 ;; *) echo 1 ;; esac)" || return 1
  need "the self-gate passes --noproxy" "$(case "$argv" in *"--noproxy"*) echo 0 ;; *) echo 1 ;; esac)" || return 1
  need "the self-gate passes -k/--insecure/--capath: $argv" "$(case " $argv " in *" -k "*|*"--insecure"*|*"--capath"*|*" -sk "*) echo 1 ;; *) echo 0 ;; esac)" || return 1
  need "recheck failed right after a good install (rc=$(val recheck))" "$([ "$(val recheck)" = 0 ] && echo 0 || echo 1)" || return 1
}
row_A3_pending_live_https() {
  SNAP_EXTRA="INNGEST_LINK_TLS=pending:$((NOW - 5))\n" CA_MODE=ok scenario "$1" "$ROW_ID"
  ok_https || return 1
  need "state=$(val state)" "$([ "$(val state)" = https_pending ] && echo 0 || echo 1)" || return 1
}
row_A3b_pending_upper_boundaries() {
  # epoch exactly now+1860 (the 31-minute skew bound) is honoured; now-1799 is still inside the lease
  SNAP_EXTRA="INNGEST_LINK_TLS=pending:$((NOW + 1800))\n" CA_MODE=ok scenario "$1" "$ROW_ID-a"
  ok_https || return 1
  SNAP_EXTRA="INNGEST_LINK_TLS=pending:$((NOW - 1790))\n" CA_MODE=ok scenario "$1" "$ROW_ID-b"
  ok_https || return 1
}

# --- Guard 1 row 5: the self-gate ---------------------------------------------------------------
row_A4_wrong_server_fails_closed() {
  SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" SERVER_CERT="$FX/other.crt" scenario "$1" "$ROW_ID"
  fails_closed || return 1
  need "reason=$(val reason)" "$([ "$(val reason)" = inngest_link_selfgate_failed ] && echo 0 || echo 1)" || return 1
  need "no curl --cacert attempt was made" "$(grep -q -- '--cacert' "$RUN/curl.argv" && echo 0 || echo 1)" || return 1
  need "a failed gate must not be retried silently with -k" "$(grep -qE -- '(^| )(-k|--insecure)( |$)' "$RUN/curl.argv" && echo 1 || echo 0)" || return 1
}
row_A4b_pending_wrong_server_fails_closed() {
  SNAP_EXTRA="INNGEST_LINK_TLS=pending:$((NOW - 5))\n" CA_MODE=ok SERVER_CERT="$FX/other.crt" scenario "$1" "$ROW_ID"
  fails_closed || return 1
}
row_A5_ca_absent_fails() { SNAP_EXTRA="$ONFLAG" CA_MODE=absent scenario "$1" "$ROW_ID"; fails_closed || return 1
  need "reason=$(val reason)" "$([ "$(val reason)" = inngest_link_ca_unavailable ] && echo 0 || echo 1)" || return 1; }
row_A5b_ca_read_error_fails() { SNAP_EXTRA="$ONFLAG" CA_MODE=error scenario "$1" "$ROW_ID"; fails_closed || return 1; }
row_A5c_ca_empty_fails() { SNAP_EXTRA="$ONFLAG" CA_MODE=empty scenario "$1" "$ROW_ID"; fails_closed || return 1; }
row_A5d_pending_ca_absent_fails() { SNAP_EXTRA="INNGEST_LINK_TLS=pending:$((NOW - 5))\n" CA_MODE=absent scenario "$1" "$ROW_ID"; fails_closed || return 1; }

# --- the lease and the allowlist (Guard 1 row 11) -------------------------------------------------
row_B1_lease_expired_http() {
  SNAP_EXTRA="INNGEST_LINK_TLS=pending:$((NOW - 1900))\n" CA_MODE=ok scenario "$1" "$ROW_ID-a"
  need "rc=$(val rc)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "url=$(val url)" "$([ "$(val url)" = http://10.0.1.40:8288 ] && echo 0 || echo 1)" || return 1
  need "state=$(val state)" "$([ "$(val state)" = http_lease_expired ] && echo 0 || echo 1)" || return 1
  need "no lease-expired event" "$(log_has 'class=lease_expired' && echo 0 || echo 1)" || return 1
  need "link env is not the http triple" "$(env_exact http://10.0.1.40:8288 http ''; echo $?)" || return 1
  need "curl ran on an expired lease" "$([ ! -s "$RUN/curl.argv" ] && echo 0 || echo 1)" || return 1
  SNAP_EXTRA="INNGEST_LINK_TLS=pending:$((NOW - 1800))\n" CA_MODE=ok scenario "$1" "$ROW_ID-b"
  need "the boundary now==epoch+1800 must be expired (state=$(val state))" "$([ "$(val state)" = http_lease_expired ] && echo 0 || echo 1)" || return 1
}
row_B2_pending_too_far_ahead_fails() {
  SNAP_EXTRA="INNGEST_LINK_TLS=pending:$((NOW + 1900))\n" CA_MODE=ok scenario "$1" "$ROW_ID"
  fails_closed || return 1
  need "reason=$(val reason)" "$([ "$(val reason)" = inngest_link_flag_invalid ] && echo 0 || echo 1)" || return 1
}
row_B3_non_allowlisted_fail() {
  local v
  for v in 0 true yes 01 ' 1' '1 ' pending: pending:abc pending:12345678901 'pending:1 2' PENDING:1 'on' '1;id'; do
    SNAP_EXTRA="INNGEST_LINK_TLS=$v\n" CA_MODE=ok scenario "$1" "$ROW_ID"
    need "flag value '$v' did not fail the deploy (rc=$(val rc) url=$(val url))" "$([ "$(val rc)" != 0 ] && [ -z "$(val url)" ] && echo 0 || echo 1)" || return 1
    need "reason for '$v' is $(val reason)" "$([ "$(val reason)" = inngest_link_flag_invalid ] && echo 0 || echo 1)" || return 1
  done
}
row_B6_duplicate_flag_fails() {
  SNAP_EXTRA='INNGEST_LINK_TLS=1\nINNGEST_LINK_TLS=1\n' CA_MODE=ok scenario "$1" "$ROW_ID"
  fails_closed || return 1
}

# --- Guard 1 row 9: a read error is not an absence ----------------------------------------------
row_B4_snapshot_unreadable_fails() {
  SKIP_SNAPSHOT=1 CA_MODE=ok scenario "$1" "$ROW_ID"
  fails_closed || return 1
  need "reason=$(val reason)" "$([ "$(val reason)" = inngest_link_snapshot_unreadable ] && echo 0 || echo 1)" || return 1
}
row_B5_scope_guard() {
  local s
  for s in 'DOPPLER_PROJECT=soleur-inngest\nDOPPLER_CONFIG=prd\n' 'DOPPLER_PROJECT=soleur\nDOPPLER_CONFIG=dev\n' 'DOPPLER_CONFIG=prd\n' 'DOPPLER_PROJECT=soleur\n' '' 'DOPPLER_PROJECT=soleur\nDOPPLER_PROJECT=soleur\nDOPPLER_CONFIG=prd\n'; do
    SNAP_SCOPE="$s" SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID"
    need "scope lines [$s] did not fail the deploy (rc=$(val rc))" "$([ "$(val rc)" != 0 ] && [ -z "$(val url)" ] && echo 0 || echo 1)" || return 1
    need "reason for [$s] is $(val reason)" "$([ "$(val reason)" = inngest_link_scope_mismatch ] && echo 0 || echo 1)" || return 1
  done
}

# --- Guard 1 row 10: CA validation, one row per variant ------------------------------------------
ca_rejected() { # <variant file> <label> <why token the ca_invalid event must carry>
  SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$1" scenario "$BLK" "$ROW_ID"
  fails_closed || return 1
  need "$2: the ca_invalid event does not carry why=$3" "$(log_has "class=ca_invalid level=error b64_len=" && log_has "why=$3" && echo 0 || echo 1)" || return 1
  need "$2: reason=$(val reason), want inngest_link_ca_invalid" "$([ "$(val reason)" = inngest_link_ca_invalid ] && echo 0 || echo 1)" || return 1
  need "$2: a rejected CA reached the CA file" "$([ ! -s "$(caf)" ] && echo 0 || echo 1)" || return 1
  need "$2: curl ran against an unvalidated CA" "$([ ! -s "$RUN/curl.argv" ] && echo 0 || echo 1)" || return 1
}
row_C_privkey_concat() { BLK="$1" ca_rejected "$FX/v-privkey-concat.pem" "cert plus PRIVATE KEY block" "key" || return 1
  need "key bytes landed in the CA file" "$(grep -q 'PRIVATE KEY' "$(caf)" 2>/dev/null && echo 1 || echo 0)" || return 1; }
row_C_privkey_prefixed() { BLK="$1" ca_rejected "$FX/v-privkey-prefixed.pem" "PRIVATE KEY text hidden behind a prefix (not a counted BEGIN line)" "key"; }
row_C_privkey_only() { BLK="$1" ca_rejected "$FX/v-privkey-only.pem" "PRIVATE KEY only" "key"; }
row_C_badsan() { BLK="$1" ca_rejected "$FX/v-badsan.pem" "SAN IP:10.0.1.41" "san"; }
row_C_dnssan() { BLK="$1" ca_rejected "$FX/v-dnssan.pem" "SAN IP plus DNS" "san"; }
row_C_catrue() { BLK="$1" ca_rejected "$FX/v-catrue.pem" "CA:TRUE" "ca"; }
row_C_clientauth() { BLK="$1" ca_rejected "$FX/v-clientauth.pem" "EKU clientAuth only" "eku"; }
row_C_bothauth() { BLK="$1" ca_rejected "$FX/v-bothauth.pem" "EKU serverAuth+clientAuth" "eku"; }
row_C_noeku() { BLK="$1" ca_rejected "$FX/v-noeku.pem" "no EKU" "eku"; }
row_C_expired() { BLK="$1" ca_rejected "$FX/v-expired.pem" "expired" "expired"; }
row_C_notself() { BLK="$1" ca_rejected "$FX/v-notself.pem" "not self-signed" "notself"; }
row_C_three() { BLK="$1" ca_rejected "$FX/v-three.pem" "three certificates" "count"; }
row_C_garbage() { BLK="$1" ca_rejected "$FX/v-garbage.pem" "not PEM" "count"; }
row_C_oversize() { BLK="$1" ca_rejected "$FX/v-oversize.pem" "over 4 KiB" "size"; }
row_C_tool_missing_fails_closed() {
  # no openssl on PATH: a flag-on deploy must fail closed (never trust an unvalidated file) and say why=tool
  local farm="$RUNS/farm" t
  rm -rf "$farm"; mkdir -p "$farm"
  for t in base64 tr wc grep awk sed paste cp rm mktemp timeout cat cut sha256sum date sleep mv chmod dirname basename head ls stat; do
    command -v "$t" >/dev/null 2>&1 && ln -s "$(command -v "$t")" "$farm/$t"
  done
  PATH_OVERRIDE="$farm" SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$1" "$ROW_ID"
  fails_closed || return 1
  need "reason=$(val reason)" "$([ "$(val reason)" = inngest_link_ca_invalid ] && echo 0 || echo 1)" || return 1
  need "the event does not say why=tool" "$(log_has 'why=tool' && echo 0 || echo 1)" || return 1
  PATH_OVERRIDE="$farm" SNAP_EXTRA='' CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$1" "$ROW_ID-off"
  need "flag off without openssl must still resolve to http (rc=$(val rc))" "$([ "$(val rc)" = 0 ] && [ "$(val url)" = http://10.0.1.40:8288 ] && echo 0 || echo 1)" || return 1
  need "flag off without openssl must leave the empty placeholder" "$([ ! -s "$(caf)" ] && echo 0 || echo 1)" || return 1
}
row_C_empty_value() { SNAP_EXTRA="$ONFLAG" CA_MODE=empty scenario "$1" "$ROW_ID"; fails_closed || return 1; }
row_C_bad_base64() {
  SNAP_EXTRA="$ONFLAG" CA_MODE=raw CA_RAW='%%%not*base64***' scenario "$1" "$ROW_ID"
  fails_closed || return 1
  need "reason=$(val reason)" "$([ "$(val reason)" = inngest_link_ca_invalid ] && echo 0 || echo 1)" || return 1
}
row_C_huge_base64() {
  SNAP_EXTRA="$ONFLAG" CA_MODE=raw CA_RAW="$(head -c 20000 /dev/zero | tr '\0' 'A')" scenario "$1" "$ROW_ID"
  fails_closed || return 1
}

# flag off: an invalid CA never lands, the placeholder stands in; the deploy is NOT failed
row_C9_flag_off_invalid_ca_placeholder() {
  local v
  for v in privkey-concat badsan catrue three garbage; do
    SNAP_EXTRA='' CA_MODE=ok CA_FILE="$FX/v-$v.pem" scenario "$1" "$ROW_ID"
    need "$v: rc=$(val rc)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
    need "$v: url=$(val url)" "$([ "$(val url)" = http://10.0.1.40:8288 ] && echo 0 || echo 1)" || return 1
    need "$v: an unvalidated CA was written with the flag off" "$([ ! -s "$(caf)" ] && echo 0 || echo 1)" || return 1
  done
}
row_C9b_flag_off_stale_ca_replaced() {
  PRE='printf "stale-or-tampered\n" > inngest-ca.pem' SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID"
  need "a stale CA file survived a flag-off resolve" "$([ ! -s "$(caf)" ] && echo 0 || echo 1)" || return 1
}

# --- H2: must-PASS non-canonical input -------------------------------------------------------------
row_H2_noncanonical_passes() {
  local v
  for v in noncanon nonl two spoof; do
    SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-$v.pem" scenario "$1" "$ROW_ID"
    need "$v: rc=$(val rc) reason=$(val reason)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
    need "$v: url=$(val url)" "$([ "$(val url)" = https://10.0.1.40:8443 ] && echo 0 || echo 1)" || return 1
    need "$v: the CA file does not carry the good certificate" "$(grep -c 'BEGIN CERTIFICATE' "$(caf)" >/dev/null && [ "$(fp "$(caf)")" = "$GOOD_FP" ] && echo 0 || echo 1)" || return 1
  done
}
row_H2b_unset_and_valid_pass() {
  SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID-a"
  need "unset: rc=$(val rc)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$1" "$ROW_ID-b"
  ok_https || return 1
}

# --- the link env is written from enum branches only ---------------------------------------------------
row_D1_link_env_not_derived_from_text() {
  SNAP_EXTRA="INNGEST_LINK_TLS=pending:$((NOW - 5))\n" CA_MODE=ok CA_FILE="$FX/v-spoof.pem" scenario "$1" "$ROW_ID"
  need "rc=$(val rc)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "the link env is not exactly the https triple" "$(env_exact https://10.0.1.40:8443 https "$(caf)"; echo $?)" || return 1
  need "spoofed text reached the link env" "$(grep -q 'evil.invalid' "$(envf)" && echo 1 || echo 0)" || return 1
  need "link env mode" "$([ "$(stat -c %a "$(envf)")" = 644 ] && echo 0 || echo 1)" || return 1
}

# --- the recheck immediately before docker run --------------------------------------------------------
row_D2_recheck_detects_tamper() {
  SNAP_EXTRA="$ONFLAG" CA_MODE=ok scenario "$1" "$ROW_ID"
  ok_https || return 1
  # replay the recheck against tampered states, inside a subshell that re-sources the block
  local st
  for st in 'printf x >> "$ETC/inngest-ca.pem"' 'rm -f "$ETC/inngest-ca.pem"' 'rm -f "$ETC/inngest-ca.pem"; ln -s /etc/hostname "$ETC/inngest-ca.pem"' 'rm -f "$ETC/inngest-ca.pem"; mkdir "$ETC/inngest-ca.pem"'; do
    local o; o="$(
      export PATH="$BIN:$PATH" RUN_DIR="$RUN"
      LOG_TAG=ci-deploy
      # shellcheck disable=SC1090
      source "$1"
      INNGEST_LINK_DIR="$ETC"
      INNGEST_LINK_CA_STRICT=1
      INNGEST_LINK_CA_SHA="$(openssl x509 -in "$FX/good.crt" -outform PEM | sha256sum | cut -d' ' -f1)"
      rm -rf "$ETC/inngest-ca.pem"; openssl x509 -in "$FX/good.crt" -outform PEM > "$ETC/inngest-ca.pem"
      eval "$st"
      rr=0; inngest_link_ca_recheck || rr=$?
      printf '%s' "$rr"
    )"
    need "recheck did not refuse the tampered state [$st] (rc=$o)" "$([ "$o" != 0 ] && [ -n "$o" ] && echo 0 || echo 1)" || return 1
  done
  # and it accepts the untampered state
  local o2; o2="$(
    export PATH="$BIN:$PATH" RUN_DIR="$RUN"; LOG_TAG=ci-deploy
    # shellcheck disable=SC1090
    source "$1"; INNGEST_LINK_DIR="$ETC"; INNGEST_LINK_CA_STRICT=1
    rm -rf "$ETC/inngest-ca.pem"
    openssl x509 -in "$FX/good.crt" -outform PEM > "$ETC/inngest-ca.pem"
    INNGEST_LINK_CA_SHA="$(sha256sum "$ETC/inngest-ca.pem" | cut -d' ' -f1)"
    rr=0; inngest_link_ca_recheck || rr=$?; printf '%s' "$rr"
  )"
  need "recheck refused an untampered state (rc=$o2)" "$([ "$o2" = 0 ] && echo 0 || echo 1)" || return 1
}
row_D3_dest_is_directory() {
  PRE='mkdir inngest-ca.pem' SNAP_EXTRA="$ONFLAG" CA_MODE=ok scenario "$1" "$ROW_ID-on"
  need "flag on with a directory at the CA path must fail (rc=$(val rc))" "$([ "$(val rc)" != 0 ] && [ -z "$(val url)" ] && echo 0 || echo 1)" || return 1
  need "flag on, directory at the CA path: reason=$(val reason), want inngest_link_write_failed" "$([ "$(val reason)" = inngest_link_write_failed ] && echo 0 || echo 1)" || return 1
  PRE='mkdir inngest-ca.pem' SNAP_EXTRA='' CA_MODE=ok scenario "$1" "$ROW_ID-off"
  need "flag off with a directory at the CA path must not fail the deploy (rc=$(val rc))" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
}
row_D4_install_failure_fails_strict() {
  # the etc dir is not writable: flag on fails closed, flag off proceeds (best effort, loud)
  PRE='chmod 0555 .' SNAP_EXTRA="$ONFLAG" CA_MODE=ok scenario "$1" "$ROW_ID-on"
  local rc_on url_on; rc_on="$(val rc)"; url_on="$(val url)"
  chmod 0755 "$ETC" 2>/dev/null
  if [ "$(id -u)" = 0 ]; then return 0; fi   # root ignores the mode bits: the row is vacuous there, not red
  need "flag on with an unwritable dir must fail (rc=$rc_on url=$url_on)" "$([ "$rc_on" != 0 ] && [ -z "$url_on" ] && echo 0 || echo 1)" || return 1
  PRE='chmod 0555 .' SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID-off"
  local rc_off; rc_off="$(val rc)"; chmod 0755 "$ETC" 2>/dev/null
  need "flag off with an unwritable dir must not fail the deploy (rc=$rc_off)" "$([ "$rc_off" = 0 ] && echo 0 || echo 1)" || return 1
}


# --- the canary layer (inngest_link_canary_check): five in-container checks, only while the resolver chose https ----------------
canary() { # <block> <run id> [STRICT=1]: runs the check under the docker stub; $RUN/out gets rc= and reason=
  local block="$1" id="$2"
  RUN="$RUNS/$id"; ETC="$RUN/etc"
  assert_fixture_dir "$RUN"
  rm -rf "$RUN"; mkdir -p "$ETC"; : > "$RUN/logger.log"; : > "$RUN/docker.argv"
  (
    export RUN_DIR="$RUN" PATH="$BIN:$PATH"
    LOG_TAG=ci-deploy
    unset SENTRY_INGEST_DOMAIN SENTRY_PROJECT_ID SENTRY_PUBLIC_KEY
    # shellcheck disable=SC1090
    source "$block" || exit 99
    INNGEST_LINK_DIR="$ETC"; INNGEST_LINK_CA_STRICT="${STRICT:-1}"; CANARY_FAIL_REASON=""
    rc=0; inngest_link_canary_check || rc=$?
    printf 'rc=%s\nreason=%s\n' "$rc" "$CANARY_FAIL_REASON" > "$RUN/out"
  ) > "$RUN/stdout" 2>&1
  [ -s "$RUN/out" ] || printf 'rc=harness\n' > "$RUN/out"
}
canary_fails() { # the shared predicate: rc 1, the canary reason set, an error event
  need "rc=$(val rc), want 1" "$([ "$(val rc)" = 1 ] && echo 0 || echo 1)" || return 1
  need "reason=$(val reason)" "$([ "$(val reason)" = canary_inngest_link_failed ] && echo 0 || echo 1)" || return 1
  need "no canary_failed event" "$(log_has 'class=canary_failed level=error' && echo 0 || echo 1)" || return 1
}
row_E1_canary_flag_off_is_a_noop() {
  STRICT=0 canary "$1" "$ROW_ID"
  need "rc=$(val rc), want 0" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "docker was called with the flag off" "$([ ! -s "$RUN/docker.argv" ] && echo 0 || echo 1)" || return 1
}
row_E2_canary_all_good() {
  canary "$1" "$ROW_ID"
  need "rc=$(val rc), want 0 (reason $(val reason))" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  local argv; argv="$(cat "$RUN/docker.argv")"
  need "no docker inspect" "$(case "$argv" in *"inspect"*soleur-web-platform-canary*) echo 0 ;; *) echo 1 ;; esac)" || return 1
  need "the positive script must run WITHOUT env -u" "$(grep -E '^exec soleur-web-platform-canary /usr/local/bin/node -e ' "$RUN/docker.argv" >/dev/null && echo 0 || echo 1)" || return 1
  need "the negative control must run with env -u NODE_EXTRA_CA_CERTS" "$(grep -cE '^exec soleur-web-platform-canary env -u NODE_EXTRA_CA_CERTS /usr/local/bin/node -e ' "$RUN/docker.argv" | grep -qx 1 && echo 0 || echo 1)" || return 1
  need "the scripts must name the synthetic event" "$(grep -q 'soleur.tls-canary.ping' "$RUN/docker.argv" && echo 0 || echo 1)" || return 1
  need "the scripts must not carry key material on argv (-e or an inline value)" "$(grep -qE -- '^exec (-e|--env)|signkey-[0-9a-f]{8}' "$RUN/docker.argv" && echo 1 || echo 0)" || return 1
}
row_E3_canary_inspect_must_show_https() {
  local m
  for m in http noca twice none; do
    FX_INSPECT="$m" canary "$1" "$ROW_ID"
    canary_fails || { WHY="inspect=$m: ${WHY:-}"; return 1; }
    need "inspect=$m: an exec ran after a failed inspect" "$(grep -q '^exec ' "$RUN/docker.argv" && echo 1 || echo 0)" || return 1
  done
}
row_E4_canary_each_positive_check_gates() {
  local t
  for t in 'health=fail events=ok send=ok registry=ok' 'health=ok events=fail send=ok registry=ok' 'health=ok events=ok send=fail registry=ok' 'health=ok events=ok send=ok registry=fail'; do
    FX_POS="inngest_link_canary $t" canary "$1" "$ROW_ID"
    canary_fails || { WHY="[$t]: ${WHY:-}"; return 1; }
  done
}
row_E5_canary_negative_control_must_fail_verification() {
  local t
  for t in 'inngest_link_canary_neg=accepted' 'inngest_link_canary_neg=other' ''; do
    FX_NEG="$t" canary "$1" "$ROW_ID"
    canary_fails || { WHY="neg=[$t]: ${WHY:-}"; return 1; }
  done
}
row_E6_canary_unparseable_output_is_a_failure() {
  local t
  for t in 'garbage' 'inngest_link_canary health=ok events=ok send=ok registry=ok EXTRA=secret' 'x inngest_link_canary health=ok events=ok send=ok registry=ok' ''; do
    FX_POS="$t" canary "$1" "$ROW_ID"
    canary_fails || { WHY="out=[$t]: ${WHY:-}"; return 1; }
  done
  FX_EXEC_RC=7 canary "$1" "$ROW_ID"
  canary_fails || { WHY="docker exec rc 7: ${WHY:-}"; return 1; }
}

ROW_IDS=(
  A1_unset_http A1b_unset_with_ca_http A1c_unset_empty_value_is_absent
  A2_flag_on_https A3_pending_live_https A3b_pending_upper_boundaries
  A4_wrong_server_fails_closed A4b_pending_wrong_server_fails_closed A5_ca_absent_fails A5b_ca_read_error_fails A5c_ca_empty_fails A5d_pending_ca_absent_fails
  B1_lease_expired_http B2_pending_too_far_ahead_fails B3_non_allowlisted_fail B4_snapshot_unreadable_fails B5_scope_guard B6_duplicate_flag_fails
  C_privkey_concat C_privkey_prefixed C_privkey_only C_badsan C_dnssan C_catrue C_clientauth C_bothauth C_noeku C_expired C_notself C_three C_garbage C_oversize C_tool_missing_fails_closed C_empty_value C_bad_base64 C_huge_base64
  C9_flag_off_invalid_ca_placeholder C9b_flag_off_stale_ca_replaced
  H2_noncanonical_passes H2b_unset_and_valid_pass
  D1_link_env_not_derived_from_text D2_recheck_detects_tamper D3_dest_is_directory D4_install_failure_fails_strict
  E1_canary_flag_off_is_a_noop E2_canary_all_good E3_canary_inspect_must_show_https E4_canary_each_positive_check_gates
  E5_canary_negative_control_must_fail_verification E6_canary_unparseable_output_is_a_failure
)

ROW_ID=""; ROW_WHY=""
# run_rows <block> <id>... : prints nothing, sets RES[id]=0 (held) or 1 (violated) and ROW_WHYS[id]
declare -A RES ROW_WHYS
run_rows() {
  local block="$1" id; shift
  for id in "$@"; do
    ROW_ID="$id"; WHY=""
    if "row_$id" "$block"; then RES[$id]=0; else RES[$id]=1; ROW_WHYS[$id]="$WHY"; fi
  done
}

# ---------------------------------------------------------------------------------------
# THE REAL BLOCK
# ---------------------------------------------------------------------------------------
if [ -z "$BLOCK_REAL" ]; then
  bad "X0 the inngest-link-resolver block is not present in ci-deploy.sh (extraction failed)"
  printf '\n=== inngest-link-resolver: %d passed, %d failed ===\n' "$PASS" "$FAIL"
  exit 1
fi
ok "X0 the inngest-link-resolver block is present exactly once in ci-deploy.sh"
if grep -qE 'curl[^#\n]*( -k | --insecure| --capath)' "$BLOCK_REAL"; then bad "X1 the block spells a curl -k/--insecure/--capath"; else ok "X1 the block never spells curl -k/--insecure/--capath"; fi
if grep -q 'source\|^\s*\. ' <(grep -v '^\s*#' "$BLOCK_REAL" | grep -E '(^|[;&| ])(source|\.)[[:space:]]+[^ ]*(link|snapshot|env|ca)'); then bad "X2 the block sources a file"; else ok "X2 the block never sources a file"; fi

ROWS=0
# --- wiring into the deploy flow (static order checks on the real file; the integration rows live in ci-deploy.test.sh) ---------------
lineno() { grep -nF -- "$1" "$CI_DEPLOY" | sed -n "${2:-1}p" | cut -d: -f1; }
L_RES="$(lineno 'resolve_inngest_link "$ENV_FILE" ||')"
L_CANARY_RUN="$(lineno '--name soleur-web-platform-canary \')"
L_RECHK1="$(lineno 'if ! inngest_link_ca_recheck; then' 1)"
L_GAK="$(lineno 'github_app_key_canary_check; then')"
L_LAYER5="$(lineno '! inngest_link_canary_check; then')"
L_SWAP="$(lineno 'echo "Canary passed, swapping to production..."')"
L_RECHK2="$(lineno 'if ! inngest_link_ca_recheck; then' 2)"
L_STOP="$(lineno '{ docker stop --time=12 soleur-web-platform')"
L_RECHK3="$(lineno 'if ! inngest_link_ca_recheck; then' 3)"
L_PROD_RUN="$(lineno '--name soleur-web-platform \')"
wire_ok() { # <desc> <a> <b> : a < b, both non-empty
  ROWS=$((ROWS + 1))
  if [ -n "$2" ] && [ -n "$3" ] && [ "$2" -lt "$3" ]; then ok "wiring: $1 ($2 < $3)"; else bad "wiring: $1 (got '$2' then '$3')"; fi
}
wire_ok "the resolver runs before the canary docker run" "$L_RES" "$L_CANARY_RUN"
wire_ok "the CA recheck runs immediately before the canary docker run" "$L_RECHK1" "$L_CANARY_RUN"
wire_ok "the canary layer-5 check runs after the GitHub App key check and before promotion" "$L_GAK" "$L_LAYER5"
wire_ok "layer 5 gates promotion (before the swap)" "$L_LAYER5" "$L_SWAP"
wire_ok "a recheck runs before the old container is stopped" "$L_RECHK2" "$L_STOP"
wire_ok "a second recheck runs immediately before the prod docker run" "$L_RECHK3" "$L_PROD_RUN"
ROWS=$((ROWS + 1))
if [ "$(grep -c 'INNGEST_BASE_URL="\$INNGEST_BASE_URL_RESOLVED"' "$CI_DEPLOY")" = 2 ] && ! grep -qE '^[[:space:]]+-e INNGEST_BASE_URL=http' "$CI_DEPLOY"; then ok "wiring: both docker run sites take the resolver expansion and no literal URL remains"; else bad "wiring: a docker run site does not take the resolver expansion (or a literal URL remains)"; fi

run_rows "$BLOCK_REAL" "${ROW_IDS[@]}"
for id in "${ROW_IDS[@]}"; do
  ROWS=$((ROWS + 1))
  if [ "${RES[$id]:-1}" = 0 ]; then ok "row $id holds"; else bad "row $id VIOLATED: ${ROW_WHYS[$id]:-unknown}"; fi
done

# ---------------------------------------------------------------------------------------
# H1: the curl stub always succeeds -> the CA-withheld rows MUST go RED. A suite that stays green here
# cannot see a vacuous self-gate.
# ---------------------------------------------------------------------------------------
h1_rc=0
( CURL_ALWAYS_OK=1; export CURL_ALWAYS_OK; ROW_ID=A4_wrong_server_fails_closed; WHY=""; row_A4_wrong_server_fails_closed "$BLOCK_REAL" ) >/dev/null 2>&1 || h1_rc=$?
ROWS=$((ROWS + 1))
if [ "$h1_rc" -ne 0 ]; then ok "H1 an always-succeeding curl turns the wrong-server row RED (the suite can see a vacuous self-gate)"; else bad "H1 the wrong-server row stayed GREEN with an always-succeeding curl (vacuous self-gate not detectable)"; fi

# ---------------------------------------------------------------------------------------
# H3: Node. A CA:FALSE self-signed certificate is accepted as an extra root; a leaf signed with its key is not.
# ---------------------------------------------------------------------------------------
node_probe() { # <server cert> <server key> <ca file> -> prints OK or the error code
  timeout 30 node -e '
    const https=require("https"),fs=require("fs"),{spawn}=require("child_process");
    const [cert,key]=[fs.readFileSync(process.argv[1]),fs.readFileSync(process.argv[2])];
    const srv=https.createServer({cert,key},(q,r)=>{r.end("hi")}).listen(0,"127.0.0.1",()=>{
      const port=srv.address().port;
      const child=`const https=require("https");const q=https.get({host:"127.0.0.1",port:${port},path:"/"},r=>{r.resume();r.on("end",()=>{console.log("OK");process.exit(0)})});q.on("error",e=>{console.log(e.code||e.message);process.exit(0)});q.setTimeout(8000,()=>{console.log("TIMEOUT");process.exit(0)})`;
      const c=spawn(process.execPath,["-e",child],{env:{PATH:process.env.PATH,NODE_EXTRA_CA_CERTS:process.argv[3]}});
      let out="";c.stdout.on("data",d=>out+=d);
      c.on("close",()=>{process.stdout.write(out.trim()+"\n");srv.close();process.exit(0)});
    });' "$1" "$2" "$3" 2>/dev/null
}
if command -v node >/dev/null 2>&1; then
  openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$FX/nleaf.key" -out "$FX/nleaf.csr" -subj /CN=leaf >/dev/null 2>&1
  printf 'subjectAltName=IP:127.0.0.1\nbasicConstraints=critical,CA:FALSE\nextendedKeyUsage=serverAuth\n' > "$FX/nleaf.ext"
  openssl x509 -req -in "$FX/nleaf.csr" -CA "$FX/loop.crt" -CAkey "$FX/loop.key" -CAcreateserial -out "$FX/nleaf.crt" -days 30 -extfile "$FX/nleaf.ext" >/dev/null 2>&1
  r1="$(node_probe "$FX/loop.crt" "$FX/loop.key" "$FX/loop.crt")"
  ROWS=$((ROWS + 1))
  if [ "$r1" = OK ]; then ok "H3a Node accepts a CA:FALSE self-signed certificate as an extra root (NODE_EXTRA_CA_CERTS)"; else bad "H3a Node rejected the CA:FALSE self-signed anchor: '$r1' (the flip would fail safely, but the plan assumption is wrong)"; fi
  r2="$(node_probe "$FX/nleaf.crt" "$FX/nleaf.key" "$FX/loop.crt")"
  ROWS=$((ROWS + 1))
  if [ -n "$r2" ] && [ "$r2" != OK ]; then ok "H3b a leaf signed with the anchor's own key does NOT validate in Node ($r2): a non-CA anchor cannot issue"; else bad "H3b a leaf issued by the CA:FALSE anchor VALIDATED in Node ('$r2')"; fi
  r3="$(node_probe "$FX/other.crt" "$FX/other.key" "$FX/loop.crt")"
  ROWS=$((ROWS + 1))
  if [ -n "$r3" ] && [ "$r3" != OK ]; then ok "H3c a certificate that is not the pinned anchor does not validate ($r3)"; else bad "H3c an unpinned certificate VALIDATED in Node ('$r3')"; fi
else
  ROWS=$((ROWS + 3)); SKIP=$((SKIP + 3)); printf '[skip] H3 node is not installed: the three Node anchor rows did not run\n'
fi

# ---------------------------------------------------------------------------------------
# MUTATION ROWS: each edits a COPY of the block, proves the edit LANDED, and requires the named rows to go RED.
# ---------------------------------------------------------------------------------------
mut_block() { # <id> <old> <new> [<old> <new>]... -> prints the mutated block path; an anchor that is absent aborts
  local out="$WORK/block.$1.sh" id="$1"
  shift
  python3 -I - "$BLOCK_REAL" "$out" "$@" <<'PY' || die "mutation $id: an anchor was not found in the block (the mutation did not land)"
import sys
s = open(sys.argv[1]).read()
pairs = sys.argv[3:]
for i in range(0, len(pairs), 2):
    o, n = pairs[i], pairs[i + 1]
    if o not in s:
        sys.exit(3)
    s = s.replace(o, n, 1)
open(sys.argv[2], "w").write(s)
PY
  cmp -s "$BLOCK_REAL" "$out" && die "mutation $id did not change the block"
  printf '%s\n' "$out"
}
kill_mut() { # <mutation id> "<row id> ..." <old> <new> [<old> <new>]...   (every named row must go RED)
  local mid="$1" rows="$2" blk id killed=0 total=0
  shift 2
  blk="$(mut_block "$mid" "$@")" || exit 2
  for id in $rows; do
    total=$((total + 1))
    unset "RES[$id]"; run_rows "$blk" "$id"
    if [ "${RES[$id]:-0}" = 1 ]; then killed=$((killed + 1)); fi
  done
  ROWS=$((ROWS + 1))
  if [ "$killed" -eq "$total" ]; then ok "mutation $mid killed ($killed/$total named rows went RED)"; else bad "mutation $mid NOT KILLED ($killed/$total named rows went RED): a regression of this shape would pass the suite"; fi
}


# Guard 1 row 5: the self-gate
kill_mut M05a-selfgate-neutered "A4_wrong_server_fails_closed A4b_pending_wrong_server_fails_closed" \
  'if ! _inngest_link_selfgate "$ca_dest"; then' 'if false; then'
kill_mut M05b-selfgate-without-cacert "A2_flag_on_https" \
  '      --cacert "$1" "$INNGEST_LINK_HTTPS_URL/health"' '      "$INNGEST_LINK_HTTPS_URL/health"'
kill_mut M05c-selfgate-insecure "A2_flag_on_https A4_wrong_server_fails_closed" \
  '      --cacert "$1" "$INNGEST_LINK_HTTPS_URL/health"' '      -k --cacert "$1" "$INNGEST_LINK_HTTPS_URL/health"'
kill_mut M05d-downgrade-on-gate-failure "A4_wrong_server_fails_closed A4b_pending_wrong_server_fails_closed" \
  'then INNGEST_LINK_REASON=inngest_link_selfgate_failed; return 1; fi' 'then INNGEST_LINK_STATE=http_default; INNGEST_LINK_CA_STRICT=0; fi'
kill_mut M05e-ca-absent-continues "A5_ca_absent_fails" \
  '    if [[ -z "$b64" ]]; then' '    if false; then'
# Guard 1 row 8: a third value
kill_mut M08a-third-https-value "A2_flag_on_https A3_pending_live_https" \
  'INNGEST_LINK_HTTPS_URL="https://10.0.1.40:8443"' 'INNGEST_LINK_HTTPS_URL="http://10.0.1.40:8443"'
kill_mut M08b-third-http-value "A1_unset_http B1_lease_expired_http" \
  'INNGEST_LINK_HTTP_URL="http://10.0.1.40:8288"' 'INNGEST_LINK_HTTP_URL="http://10.0.1.40:8443"'
kill_mut M08c-link-env-from-flag-text "A3_pending_live_https D1_link_env_not_derived_from_text" \
  '"$url" "$scheme" "$cacert" > "$cand"' '"$url" "$scheme" "$cacert $flag" > "$cand"'
# Guard 1 row 9: a read error is not an absence
kill_mut M09a-read-error-falls-through "B4_snapshot_unreadable_fails" \
  '_inngest_link_snap_get "$snap" DOPPLER_PROJECT || { INNGEST_LINK_REASON=inngest_link_snapshot_unreadable; inngest_link_event snapshot_unreadable error; return 1; }' '_inngest_link_snap_get "$snap" DOPPLER_PROJECT || true' \
  'if [[ "$_IL_N" != 1 || "$_IL_VAL" != soleur ]]; then' 'if false; then' \
  'if [[ "$_IL_N" != 1 || "$_IL_VAL" != prd ]]; then' 'if false; then' \
  '_inngest_link_snap_get "$snap" DOPPLER_CONFIG || { INNGEST_LINK_REASON=inngest_link_snapshot_unreadable; inngest_link_event snapshot_unreadable error; return 1; }' '_inngest_link_snap_get "$snap" DOPPLER_CONFIG || true' \
  '_inngest_link_snap_get "$snap" INNGEST_LINK_TLS || { INNGEST_LINK_REASON=inngest_link_snapshot_unreadable; inngest_link_event snapshot_unreadable error; return 1; }' '_inngest_link_snap_get "$snap" INNGEST_LINK_TLS || true'
kill_mut M09b-project-scope-guard-removed "B5_scope_guard" \
  'if [[ "$_IL_N" != 1 || "$_IL_VAL" != soleur ]]; then' 'if false; then'
kill_mut M09c-config-scope-guard-removed "B5_scope_guard" \
  'if [[ "$_IL_N" != 1 || "$_IL_VAL" != prd ]]; then' 'if false; then'
# Guard 1 row 10: CA validation weakened, one mutation per variant
kill_mut M10a-private-key-allowed "C_privkey_prefixed" \
  "if grep -q 'PRIVATE KEY' \"\$raw\"; then _IL_WHY=key; break; fi" 'if false; then break; fi'
kill_mut M10b-san-weakened "C_badsan C_dnssan" \
  '[[ "$san" == "IP Address:10.0.1.40" ]] || { _IL_WHY=san; break 2; }' 'true || break 2'
kill_mut M10c-ca-true-allowed "C_catrue" \
  '[[ "$bc" == *"CA:FALSE"* && "$bc" != *"CA:TRUE"* ]] || { _IL_WHY=ca; break 2; }' 'true || break 2'
kill_mut M10d-three-certs-allowed "C_three" \
  '"$n_begin" -le 2' '"$n_begin" -le 3'
kill_mut M10e-eku-weakened "C_clientauth C_bothauth C_noeku" \
  '[[ "$eku" == "TLS Web Server Authentication" ]] || { _IL_WHY=eku; break 2; }' 'true || break 2'
kill_mut M10f-expiry-unchecked "C_expired" \
  'openssl verify -CAfile "$p" -check_ss_sig "$p"' 'openssl verify -no_check_time -CAfile "$p" -check_ss_sig "$p"' \
  'timeout 10 openssl x509 -in "$p" -noout -checkend 0 >/dev/null 2>&1 || { _IL_WHY=expired; break 2; }' 'true'
kill_mut M10g-size-unbounded "C_oversize" \
  '-le 4096 ]] || { _IL_WHY=size; break; }' '-le 4096000 ]] || { _IL_WHY=size; break; }'
kill_mut M10h-self-signed-unchecked "C_notself" \
  '[[ -n "$subj" && "${subj#subject=}" == "${issuer#issuer=}" ]] || { _IL_WHY=notself; break 2; }' 'true || break 2' \
  'timeout 10 openssl verify -CAfile "$p" -check_ss_sig "$p" >/dev/null 2>&1 || { _IL_WHY=notself; break 2; }' 'true'
# Guard 1 row 11: the allowlist and the lease
kill_mut M11a-non-allowlisted-treated-as-absent "B3_non_allowlisted_fail" \
  'INNGEST_LINK_REASON=inngest_link_flag_invalid; inngest_link_event flag_invalid error "len=${#flag}"; return 1' 'INNGEST_LINK_STATE=http_default'
kill_mut M11b-lease-never-expires "B1_lease_expired_http" \
  'elif (( now >= epoch + 1800 )); then' 'elif false; then'
kill_mut M11c-lease-boundary-off-by-one "B1_lease_expired_http" \
  'elif (( now >= epoch + 1800 )); then' 'elif (( now > epoch + 1800 )); then'
kill_mut M11d-future-epoch-honoured "B2_pending_too_far_ahead_fails" \
  'if (( epoch > now + 1860 )); then' 'if false; then'
kill_mut M11e-duplicate-flag-lines-accepted "B6_duplicate_flag_fails" \
  'if [[ "$_IL_N" -gt 1 ]]; then INNGEST_LINK_REASON=inngest_link_flag_invalid' 'if [[ "$_IL_N" -gt 9 ]]; then INNGEST_LINK_REASON=inngest_link_flag_invalid'

# the canary layer
kill_mut M13a-negative-control-skipped "E5_canary_negative_control_must_fail_verification" \
  '"$out" != "inngest_link_canary_neg=verify_error" ]]; then why="negative_control"; fi' '"$out" == "__never__" ]]; then why="negative_control"; fi'
ANCH_B1="$(cat <<'EOA'
"$(printf '%s\n' "$envs" | grep -c '^INNGEST_BASE_URL=')" != 1
EOA
)"
ANCH_B2="$(cat <<'EOA'
"$(printf '%s\n' "$envs" | grep -cxF "INNGEST_BASE_URL=$INNGEST_LINK_HTTPS_URL")" != 1
EOA
)"
ANCH_B3="$(cat <<'EOA'
"$(printf '%s\n' "$envs" | grep -cxF 'NODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem')" != 1
EOA
)"
kill_mut M13b1-inspect-single-url-line-unchecked "E3_canary_inspect_must_show_https" "$ANCH_B1" '"x" == "y"'
kill_mut M13b2-inspect-https-value-unchecked "E3_canary_inspect_must_show_https" "$ANCH_B2" '"x" == "y"'
kill_mut M13b3-inspect-ca-env-unchecked "E3_canary_inspect_must_show_https" "$ANCH_B3" '"x" == "y"'
kill_mut M13c-send-unchecked "E4_canary_each_positive_check_gates" \
  'elif [[ "${BASH_REMATCH[3]}" != ok ]]; then why="send"' 'elif false; then why="send"'
kill_mut M13d-verdict-unanchored "E6_canary_unparseable_output_is_a_failure" \
  'registry=(ok|fail)$ ]]; then' 'registry=(ok|fail) ]]; then'
kill_mut M13e-canary-runs-with-flag-off "E1_canary_flag_off_is_a_noop" \
  '  [[ "$INNGEST_LINK_CA_STRICT" == 1 ]] || return 0
  envs=' '  envs='
# the flag-off placeholder, the install failure, the recheck
kill_mut M12a-flag-off-writes-unvalidated-ca "C9_flag_off_invalid_ca_placeholder" \
  '[[ -n "$cand" ]] && : > "$cand"' '[[ -n "$cand" ]] && { printf "%s" "$b64" | base64 -d > "$cand" 2>/dev/null || cp /dev/null "$cand"; }'
kill_mut M12b-strict-install-failure-ignored "D3_dest_is_directory" \
  'INNGEST_LINK_REASON=inngest_link_write_failed; inngest_link_event write_failed error "file=ca"; return 1' ':'
kill_mut M12c-recheck-sha-ignored "D2_recheck_detects_tamper" \
  'if [[ -z "$sha" || "$sha" != "$INNGEST_LINK_CA_SHA" ]]; then' 'if false; then'


# ---------------------------------------------------------------------------------------
# LEDGER
# ---------------------------------------------------------------------------------------
printf '\n=== inngest-link-resolver: %d passed, %d failed, %d skipped (%d rows) ===\n' "$PASS" "$FAIL" "$SKIP" "$ROWS"
if [ "$((PASS + FAIL + SKIP))" -lt "$ROWS" ]; then
  printf '[FATAL] accounting: passes(%s)+fails(%s)+skips(%s) < rows(%s) - a verdict was discarded\n' "$PASS" "$FAIL" "$SKIP" "$ROWS" >&2
  exit 1
fi
MIN_ROWS=95
if [ "$ROWS" -lt "$MIN_ROWS" ]; then
  printf '[FATAL] anti-vacuity floor: only %s rows ran, floor is %s\n' "$ROWS" "$MIN_ROWS" >&2
  exit 1
fi
# The floor is pinned EXACTLY to the measured row count: deleting a row is as visible as lowering the literal.
if [ "$ROWS" -gt "$MIN_ROWS" ]; then
  printf '[FATAL] floor drift: %s rows ran but MIN_ROWS is %s - set MIN_ROWS=%s\n' "$ROWS" "$MIN_ROWS" "$ROWS" >&2
  exit 1
fi
if [ "$FAIL" -gt 0 ]; then printf 'FAIL: %d check(s) failed\n' "$FAIL"; exit 1; fi
printf 'OK\n'
