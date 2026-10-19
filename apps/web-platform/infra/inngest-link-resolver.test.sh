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
#   Guard 1 rows covered here: 5 (self-gate, run on the CANDIDATE before install), 8 (third value), 9 (read error), 10 (CA
#   validation, one row per variant: size, private key, exactly one certificate, expired, CA:TRUE, keyCertSign with and
#   without basicConstraints), 11 (allowlist, lease), the scope guard (present-and-wrong fails, absent warns), the trust-anchor
#   ordering (flag absent: the Doppler CA is never read or installed), the downgrade memory (last-scheme) and the canary
#   cause tokens. Name/SAN/EKU/self-signature are NOT validated by the resolver (the self-gate and the canary's CA-withheld
#   negative control prove the pinned file against the real listener). Harness rows:
#   H1  the curl stub is replaced by one that always succeeds: the CA-withheld case must go RED (a suite that
#       cannot see a vacuous self-gate proves nothing);
#   H2  must-PASS non-canonical input (flag unset, valid CA with CRLF / trailing blanks / leading prose): a suite that
#       only accepts the canonical bytes is vacuous the other way;
#   H3  Node: a CA:FALSE self-signed certificate IS accepted as an extra root, and a leaf signed with its key
#       is NOT (a non-CA anchor cannot issue).
#
# Run: bash apps/web-platform/infra/inngest-link-resolver.test.sh   (unprivileged; openssl, python3, node optional for H3)
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_DEPLOY="${INNGEST_LINK_TEST_SRC:-$SCRIPT_DIR/ci-deploy.sh}"
CLOUD_INIT="${INNGEST_LINK_TEST_CLOUD_INIT:-$SCRIPT_DIR/cloud-init.yml}"

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
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
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
gen_cert catrue "IP:10.0.1.40"           "CA:TRUE"  "serverAuth"
gen_cert loop  "IP:127.0.0.1"            "CA:FALSE" "serverAuth" "/CN=loopback-anchor"

# An expired self-signed certificate (openssl ca -selfsign with an explicit validity window).
make_expired() { # [name] [IP SAN]: FX/<name>.crt + .key, an expired self-signed CA:FALSE certificate
  local name="${1:-expired}" ip="${2:-10.0.1.40}" d="$FX/exp-${1:-expired}"; mkdir -p "$d"
  ( cd "$d" || exit 1
    openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout k.pem -out r.csr -subj /CN=soleur-inngest-link >/dev/null 2>&1 || exit 1
    printf '[ca]\ndefault_ca=c\n[c]\ndatabase=idx\nserial=serial\nnew_certs_dir=.\ndefault_md=sha256\npolicy=p\nunique_subject=no\n[p]\ncommonName=supplied\n[ext]\nsubjectAltName=IP:%s\nbasicConstraints=critical,CA:FALSE\nextendedKeyUsage=serverAuth\n' "$ip" > ca.cnf
    : > idx; echo 01 > serial
    openssl ca -batch -selfsign -config ca.cnf -keyfile k.pem -in r.csr -out out.pem -startdate 20200101000000Z -enddate 20200102000000Z -extensions ext -notext >/dev/null 2>&1 || exit 1
    openssl x509 -in out.pem -outform PEM > "$FX/$name.crt" && cp k.pem "$FX/$name.key" ) || die "could not synthesize the expired certificate"
}
make_expired
make_expired expired-loop 127.0.0.1

# Certificates whose PROFILE the deny-list must judge (security F1): a v3 certificate WITHOUT basicConstraints and with
# keyUsage=keyCertSign is a working issuing CA; the real terraform profile (CA:FALSE, digitalSignature+keyEncipherment,
# serverAuth, IP SAN) must stay accepted. `openssl x509 -req -signkey -extfile` adds exactly the extensions given.
gen_cert_ext() { # <name> <extension lines (newline separated)>
  printf '%s\n' "$2" > "$FX/$1.ext"
  openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$FX/$1.key" -out "$FX/$1.csr" -subj /CN=soleur-inngest-link >/dev/null 2>&1 || die "openssl req failed for $1"
  openssl x509 -req -in "$FX/$1.csr" -signkey "$FX/$1.key" -out "$FX/$1.crt" -days 3650 -extfile "$FX/$1.ext" >/dev/null 2>&1 || die "openssl x509 failed for $1"
}
gen_cert_ext kcsnobc "keyUsage=keyCertSign
subjectAltName=IP:10.0.1.40"
gen_cert_ext kcsfalse "basicConstraints=critical,CA:FALSE
keyUsage=digitalSignature,keyCertSign
subjectAltName=IP:10.0.1.40"
# the conventional CA profile prints "Certificate Sign, CRL Sign" (the deny-list must not be anchored at the end of the line) and a
# mid-list form "Digital Signature, Certificate Sign, CRL Sign"
gen_cert_ext kcscrl "keyUsage=keyCertSign,cRLSign
subjectAltName=IP:10.0.1.40"
gen_cert_ext kcsmid "basicConstraints=critical,CA:FALSE
keyUsage=digitalSignature,keyCertSign,cRLSign
subjectAltName=IP:10.0.1.40"
gen_cert_ext tfprofile "basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=IP:10.0.1.40"

# Derived PEM variants (CA text delivered through Doppler, before the base64 the secret stores).
cp "$FX/good.crt" "$FX/v-good.pem"
cat "$FX/good.crt" "$FX/good.key" > "$FX/v-privkey-concat.pem"
cp "$FX/good.key" "$FX/v-privkey-only.pem"
cp "$FX/catrue.crt" "$FX/v-catrue.pem"
cp "$FX/expired.crt" "$FX/v-expired.pem"
cp "$FX/kcsnobc.crt" "$FX/v-kcsnobc.pem"
cp "$FX/kcsfalse.crt" "$FX/v-kcsfalse.pem"
cp "$FX/kcscrl.crt" "$FX/v-kcscrl.pem"
cp "$FX/kcsmid.crt" "$FX/v-kcsmid.pem"
cp "$FX/tfprofile.crt" "$FX/v-tfprofile.pem"
cat "$FX/good.crt" "$FX/good.crt" "$FX/good.crt" > "$FX/v-three.pem"
cat "$FX/good.crt" "$FX/other.crt" > "$FX/v-two.pem"
printf 'this is not a certificate\n' > "$FX/v-garbage.pem"
: > "$FX/v-empty.pem"
{ cat "$FX/good.crt"; for _i in $(seq 1 54); do printf '# padding line %03d to push the PEM text just over four KiB of input\n' "$_i"; done; } > "$FX/v-oversize.pem"
{ cat "$FX/good.crt"; printf 'x-----BEGIN PRIVATE KEY-----\n'; sed '1d;$d' "$FX/good.key"; printf -- '-----END PRIVATE KEY-----\n'; } > "$FX/v-privkey-prefixed.pem"
# non-canonical but valid: CRLF endings, trailing blanks, leading prose, extra blank lines, no final newline
{ printf 'Soleur Inngest link CA (comment, not PEM)\r\n\r\n'; sed 's/$/\r/' "$FX/good.crt"; printf '\r\n\r\n'; } | sed 's/-----$/----- /' > "$FX/v-noncanon.pem"
printf '%s' "$(cat "$FX/good.crt")" > "$FX/v-nonl.pem"
# a PEM whose prose tries to spoof link-env keys (must never reach the link env)
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
n=$(( $(cat "$RUN_DIR/curl.count" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$RUN_DIR/curl.count"
# FX_CURL_FAIL_FIRST=N: the first N calls fail verification (exit 60); FX_CURL_CODE: the HTTP code a TLS-verified call reports
if [ -n "${FX_CURL_FAIL_FIRST:-}" ] && [ "$n" -le "$FX_CURL_FAIL_FIRST" ]; then exit 60; fi
if [ "${FX_CURL_ALWAYS_OK:-}" = 1 ]; then printf '%s' "${FX_CURL_CODE:-200}"; exit 0; fi
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
if [ -n "$got" ] && [ "$got" = "$want" ]; then printf '%s' "${FX_CURL_CODE:-200}"; exit 0; fi
exit 60
STUB
cat > "$BIN/sleep" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${RUN_DIR:?}/sleep.log"
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
# SCENARIO RUNNER: one resolver call in a fresh subshell and a fresh link dir.
#   env: SNAP_EXTRA (extra snapshot lines), SNAP_SCOPE (override the two scope lines), CA_MODE, CA_FILE,
#        SERVER_CERT, SKIP_SNAPSHOT=1 (pass a path that does not exist), PRE (a bash snippet run in $LINKDIR first),
#        LINK_SUBDIR (INNGEST_LINK_DIR is $LINKDIR/<LINK_SUBDIR>, which does not exist yet: the resolver must mkdir -p it)
# Result files in $RUN: out (key=value), logger.log, curl.argv, and the link dir listing in $LINKDIR.
# ---------------------------------------------------------------------------------------
RUN=""; LINKDIR=""
scenario() { # <block file> <run id>
  local block="$1" id="$2" snap
  RUN="$RUNS/$id"; LINKDIR="$RUN/linkdir"
  assert_fixture_dir "$RUN"
  rm -rf "$RUN"; mkdir -p "$LINKDIR" || die "mkdir $LINKDIR"
  : > "$RUN/logger.log"; : > "$RUN/curl.argv"; : > "$RUN/doppler.calls"; : > "$RUN/sleep.log"
  snap="$RUN/snapshot.env"
  { printf '%b' "${SNAP_SCOPE-DOPPLER_PROJECT=soleur\nDOPPLER_CONFIG=prd\nDOPPLER_ENVIRONMENT=prd\n}"
    printf 'KEY=value\nGITHUB_APP_ID=4242\n'
    printf '%b' "${SNAP_EXTRA:-}"; } > "$snap"
  [ "${SKIP_SNAPSHOT:-}" = 1 ] && snap="$RUN/does-not-exist.env"
  [ -n "${PRE:-}" ] && ( cd "$LINKDIR" && eval "$PRE" )
  (
    export FX_NOW="$NOW"
    export RUN_DIR="$RUN" FX_SERVER_CERT="${SERVER_CERT:-$FX/good.crt}" FX_CURL_ALWAYS_OK="${CURL_ALWAYS_OK:-}" FX_CURL_FAIL_FIRST="${CURL_FAIL_FIRST:-}" FX_CURL_CODE="${CURL_CODE:-}"
    export PATH="$BIN:${PATH_OVERRIDE:-$PATH}"
    LOG_TAG=ci-deploy
    unset SENTRY_INGEST_DOMAIN SENTRY_PROJECT_ID SENTRY_PUBLIC_KEY
    if [ "${KEEP_SENTRY:-}" = 1 ]; then SENTRY_INGEST_DOMAIN=sentry.invalid; SENTRY_PROJECT_ID=7; SENTRY_PUBLIC_KEY=pk; fi
    # shellcheck disable=SC1090
    source "$block" || exit 99
    INNGEST_LINK_DIR="$LINKDIR${LINK_SUBDIR:+/$LINK_SUBDIR}"
    if [ "${SG_ATTEMPTS-2}" = unset ]; then unset INNGEST_LINK_SELFGATE_ATTEMPTS; else INNGEST_LINK_SELFGATE_ATTEMPTS="${SG_ATTEMPTS-2}"; fi
    _doppler_get_observed() { # <NAME> <DEST_VAR>: the real contract, driven by CA_MODE
      printf '%s\n' "$1" >> "$RUN/doppler.calls"
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
    # the deploy records the scheme only once the production container started (ci-deploy.sh calls inngest_link_commit_scheme there);
    # NO_COMMIT=1 models a deploy that died before that point (failed canary, aborted swap)
    if [ "$rc" = 0 ] && [ "${COMMIT_CHMOD:-}" = 1 ]; then chmod 0555 "$INNGEST_LINK_DIR"; fi
    if [ "$rc" = 0 ] && [ "${NO_COMMIT:-}" != 1 ]; then inngest_link_commit_scheme; fi
    if [ "${COMMIT_CHMOD:-}" = 1 ]; then chmod 0755 "$INNGEST_LINK_DIR"; fi
    {
      printf 'rc=%s\n' "$rc"
      printf 'url=%s\n' "${INNGEST_BASE_URL_RESOLVED-<unset>}"
      printf 'state=%s\n' "${INNGEST_LINK_STATE-<unset>}"
      printf 'reason=%s\n' "${INNGEST_LINK_REASON-<unset>}"
    } > "$RUN/out"
  ) > "$RUN/stdout" 2>&1
  [ -s "$RUN/out" ] || printf 'rc=harness\n' > "$RUN/out"
}
val() { grep -m1 "^$1=" "$RUN/out" | cut -d= -f2-; }
caf() { printf '%s/inngest-ca.pem' "$LINKDIR"; }
envf() { printf '%s/inngest-link.env' "$LINKDIR"; }
ca_fp() { fp "$(caf)"; }
leftovers() { ls -A "$LINKDIR" 2>/dev/null | grep -vxE 'inngest-ca\.pem|inngest-link\.env|last-scheme' || true; }
curl_calls() { cat "$RUN/curl.count" 2>/dev/null || echo 0; }
sleep_calls() { wc -l < "$RUN/sleep.log" | tr -d ' '; }
doppler_calls() { wc -l < "$RUN/doppler.calls" | tr -d ' '; }
b64f() { base64 -w0 < "$1"; }
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
  need "the Doppler CA was read with the flag absent ($(doppler_calls) call(s))" "$([ "$(doppler_calls)" = 0 ] && echo 0 || echo 1)" || return 1
}
row_A1b_unset_with_ca_never_installed() {
  # security F1: with the flag ABSENT a valid Doppler CA is neither read nor installed - it would be a trust anchor in a
  # non-strict state with no self-gate. The bind-source placeholder stays EMPTY, from Doppler and from the snapshot alike.
  SNAP_EXTRA='' CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$1" "$ROW_ID-a"
  need "url=$(val url)" "$([ "$(val url)" = http://10.0.1.40:8288 ] && echo 0 || echo 1)" || return 1
  need "a CA was installed with the flag absent" "$([ -f "$(caf)" ] && [ ! -s "$(caf)" ] && echo 0 || echo 1)" || return 1
  need "Doppler was asked for the CA with the flag absent" "$([ "$(doppler_calls)" = 0 ] && echo 0 || echo 1)" || return 1
  SNAP_EXTRA="INNGEST_TLS_CA=$(b64f "$FX/v-good.pem")\n" CA_MODE=ok scenario "$1" "$ROW_ID-b"
  need "the snapshot CA was installed with the flag absent" "$([ -f "$(caf)" ] && [ ! -s "$(caf)" ] && echo 0 || echo 1)" || return 1
  SNAP_EXTRA='' CA_MODE=ok CA_FILE="$FX/v-kcsnobc.pem" scenario "$1" "$ROW_ID-c"
  need "a hostile CA fails a flag-off deploy (rc=$(val rc))" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "a hostile CA was validated or installed with the flag absent" "$([ -f "$(caf)" ] && [ ! -s "$(caf)" ] && ! log_has 'class=ca_invalid' && echo 0 || echo 1)" || return 1
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
  need "the self-gate did not run curl --cacert <the CANDIDATE file> against https://10.0.1.40:8443/health: $argv" \
    "$(case "$argv" in *"--cacert /tmp/inngest-ca-cand."*"https://10.0.1.40:8443/health"*) echo 0 ;; *) echo 1 ;; esac)" || return 1
  need "the self-gate ran against the INSTALLED path (the CA must be proven BEFORE it is installed)" \
    "$(case "$argv" in *"--cacert $(caf)"*) echo 1 ;; *) echo 0 ;; esac)" || return 1
  need "the self-gate passes --noproxy" "$(case "$argv" in *"--noproxy"*) echo 0 ;; *) echo 1 ;; esac)" || return 1
  need "the self-gate passes -k/--insecure/--capath: $argv" "$(case " $argv " in *" -k "*|*"--insecure"*|*"--capath"*|*" -sk "*) echo 1 ;; *) echo 0 ;; esac)" || return 1
}
row_A3_pending_live_https() {
  SNAP_EXTRA="INNGEST_LINK_TLS=pending:$((NOW - 5))\n" CA_MODE=ok scenario "$1" "$ROW_ID"
  ok_https || return 1
  need "state=$(val state)" "$([ "$(val state)" = https_pending ] && echo 0 || echo 1)" || return 1
}
row_A3b_pending_honoured_boundaries() {
  # the pinned clock makes the boundaries exact: epoch == now+1860 (the 31-minute skew bound) is honoured, and so is now-1799
  # (one second before the 30-minute lease ends); now+1861 is refused in B2 and now-1800 is expired in B1
  local d
  for d in 1860 -1799; do
    SNAP_EXTRA="INNGEST_LINK_TLS=pending:$((NOW + d))\n" CA_MODE=ok scenario "$1" "$ROW_ID$d"
    ok_https || return 1
    need "epoch now${d/#[0-9]/+}: state=$(val state)" "$([ "$(val state)" = https_pending ] && echo 0 || echo 1)" || return 1
  done
}

# --- Guard 1 row 5: the self-gate ---------------------------------------------------------------
row_A4_wrong_server_fails_closed() {
  SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" SERVER_CERT="$FX/other.crt" scenario "$1" "$ROW_ID"
  fails_closed || return 1
  need "reason=$(val reason)" "$([ "$(val reason)" = inngest_link_selfgate_failed ] && echo 0 || echo 1)" || return 1
  need "the self-gate made no curl --cacert attempt" "$(grep -q -- '--cacert' "$RUN/curl.argv" && echo 0 || echo 1)" || return 1
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

# --- the CA source: the snapshot first (perf), Doppler only when the snapshot lacks it ----------------------------------
row_A6_strict_reads_ca_from_snapshot() {
  # CA_MODE=absent: a Doppler call would FAIL, so a pass proves the snapshot value was used and no extra call was made
  SNAP_EXTRA="${ONFLAG}INNGEST_TLS_CA=$(b64f "$FX/v-good.pem")\n" CA_MODE=absent scenario "$1" "$ROW_ID"
  ok_https || return 1
  need "Doppler was called although the snapshot carries the CA ($(doppler_calls) call(s))" "$([ "$(doppler_calls)" = 0 ] && echo 0 || echo 1)" || return 1
}
row_A6b_snapshot_ca_invalid_fails_without_fallback() {
  SNAP_EXTRA="${ONFLAG}INNGEST_TLS_CA=$(b64f "$FX/v-catrue.pem")\n" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$1" "$ROW_ID"
  fails_closed || return 1
  need "reason=$(val reason)" "$([ "$(val reason)" = inngest_link_ca_invalid ] && echo 0 || echo 1)" || return 1
  need "an invalid snapshot CA fell back to a Doppler value" "$([ "$(doppler_calls)" = 0 ] && echo 0 || echo 1)" || return 1
}
row_A6c_strict_falls_back_to_doppler_when_snapshot_lacks_ca() {
  SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$1" "$ROW_ID"
  ok_https || return 1
  need "Doppler was not asked for the CA" "$([ "$(doppler_calls)" = 1 ] && echo 0 || echo 1)" || return 1
}

# --- the self-gate itself: --disable leads, a verified non-200 fails, and the retry loop retries ---------------------------------
row_A7_selfgate_leads_with_disable_and_requires_200() {
  SNAP_EXTRA="$ONFLAG" CA_MODE=ok scenario "$1" "$ROW_ID-a"
  ok_https || return 1
  need "the self-gate curl does not lead with --disable (a ~/.curlrc could void the verdict): $(head -n1 "$RUN/curl.argv")" \
    "$(case "$(head -n1 "$RUN/curl.argv")" in "--disable "*) echo 0 ;; *) echo 1 ;; esac)" || return 1
  # a TLS-verified answer that is not 200 (a terminator answering 502 with a valid certificate) is not a pass
  CURL_CODE=502 SNAP_EXTRA="$ONFLAG" CA_MODE=ok scenario "$1" "$ROW_ID-502"
  fails_closed || return 1
  need "reason=$(val reason)" "$([ "$(val reason)" = inngest_link_selfgate_failed ] && echo 0 || echo 1)" || return 1
  need "the selfgate_failed event does not carry rc=0 http=502: $(grep selfgate_failed "$RUN/logger.log")" "$(log_has 'class=selfgate_failed level=error rc=0 http=502' && echo 0 || echo 1)" || return 1
  need "a 502 answer installed a CA" "$([ ! -s "$(caf)" ] && echo 0 || echo 1)" || return 1
}
row_A8_selfgate_retries_with_a_pause() {
  # fails once, then verifies: resolves https after exactly two calls and one sleep
  CURL_FAIL_FIRST=1 SNAP_EXTRA="$ONFLAG" CA_MODE=ok scenario "$1" "$ROW_ID-once"
  ok_https || return 1
  need "calls=$(curl_calls), want 2 (one failure, one success)" "$([ "$(curl_calls)" = 2 ] && echo 0 || echo 1)" || return 1
  need "sleeps=$(sleep_calls), want 1 between the two tries" "$([ "$(sleep_calls)" = 1 ] && echo 0 || echo 1)" || return 1
  # fails every attempt (ATTEMPTS=2): exactly 2 calls, 1 sleep, then the deploy fails
  CURL_FAIL_FIRST=99 SNAP_EXTRA="$ONFLAG" CA_MODE=ok scenario "$1" "$ROW_ID-all"
  fails_closed || return 1
  need "reason=$(val reason)" "$([ "$(val reason)" = inngest_link_selfgate_failed ] && echo 0 || echo 1)" || return 1
  need "calls=$(curl_calls), want 2 attempts" "$([ "$(curl_calls)" = 2 ] && echo 0 || echo 1)" || return 1
  need "sleeps=$(sleep_calls), want 1" "$([ "$(sleep_calls)" = 1 ] && echo 0 || echo 1)" || return 1
  need "no sleep of 2 seconds was requested: $(cat "$RUN/sleep.log")" "$([ "$(head -n1 "$RUN/sleep.log")" = 2 ] && echo 0 || echo 1)" || return 1
  # the production default (INNGEST_LINK_SELFGATE_ATTEMPTS unset) is 3 attempts
  SG_ATTEMPTS=unset CURL_FAIL_FIRST=99 SNAP_EXTRA="$ONFLAG" CA_MODE=ok scenario "$1" "$ROW_ID-default"
  need "default attempts: calls=$(curl_calls), want 3" "$([ "$(curl_calls)" = 3 ] && echo 0 || echo 1)" || return 1
  need "default attempts: sleeps=$(sleep_calls), want 2" "$([ "$(sleep_calls)" = 2 ] && echo 0 || echo 1)" || return 1
}
row_A6d_duplicate_snapshot_ca_lines_are_not_trusted() {
  # two INNGEST_TLS_CA lines are ambiguous: neither is taken (the last one here is hostile); the resolver asks Doppler instead
  SNAP_EXTRA="${ONFLAG}INNGEST_TLS_CA=$(b64f "$FX/v-good.pem")\nINNGEST_TLS_CA=$(b64f "$FX/v-kcsnobc.pem")\n" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$1" "$ROW_ID"
  ok_https || return 1
  need "the snapshot CA was used despite two lines (doppler calls=$(doppler_calls))" "$([ "$(doppler_calls)" = 1 ] && echo 0 || echo 1)" || return 1
  SNAP_EXTRA="${ONFLAG}INNGEST_TLS_CA=$(b64f "$FX/v-good.pem")\nINNGEST_TLS_CA=$(b64f "$FX/v-good.pem")\n" CA_MODE=absent scenario "$1" "$ROW_ID-absent"
  fails_closed || return 1
  need "reason=$(val reason)" "$([ "$(val reason)" = inngest_link_ca_unavailable ] && echo 0 || echo 1)" || return 1
}

# --- security F2: the self-gate runs on the candidate, install is last, a failed gate leaves the previous file alone ----
row_F2_selfgate_failure_leaves_previous_ca() {
  PRE='cp "$FX/other.crt" inngest-ca.pem' SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" SERVER_CERT="$FX/other.crt" scenario "$1" "$ROW_ID"
  # the server presents other.crt but the candidate is good.crt: the gate fails; the previously installed other.crt must survive
  fails_closed || return 1
  need "reason=$(val reason)" "$([ "$(val reason)" = inngest_link_selfgate_failed ] && echo 0 || echo 1)" || return 1
  need "the rejected CA replaced the previously installed file" "$([ "$(fp "$(caf)")" = "$(fp "$FX/other.crt")" ] && echo 0 || echo 1)" || return 1
}
row_F2b_selfgate_failure_installs_nothing_when_no_previous() {
  SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" SERVER_CERT="$FX/other.crt" scenario "$1" "$ROW_ID"
  fails_closed || return 1
  need "a rejected CA was installed" "$([ ! -s "$(caf)" ] && echo 0 || echo 1)" || return 1
  need "the link env was written after a failed gate" "$([ ! -e "$(envf)" ] && echo 0 || echo 1)" || return 1
}

# --- security F1(c): the issuing-CA shapes the old CA:TRUE-only deny-list let through ------------------------------------
row_F1_kcs_without_basicconstraints_rejected() { BLK="$1" ca_rejected "$FX/v-kcsnobc.pem" "keyCertSign with NO basicConstraints (a working issuing CA)" "ca"; }
row_F1b_kcs_with_ca_false_rejected() { BLK="$1" ca_rejected "$FX/v-kcsfalse.pem" "CA:FALSE but keyUsage Certificate Sign" "ca"; }
row_F1d_kcs_with_crl_sign_rejected() { BLK="$1" ca_rejected "$FX/v-kcscrl.pem" "keyUsage 'Certificate Sign, CRL Sign' (the conventional CA profile; Certificate Sign is NOT the end of the line)" "ca"; }
row_F1e_kcs_mid_list_rejected() { BLK="$1" ca_rejected "$FX/v-kcsmid.pem" "keyUsage 'Digital Signature, Certificate Sign, CRL Sign'" "ca"; }
row_F1c_terraform_profile_accepted() {
  # the real inngest-tls.tf profile (CA:FALSE, digitalSignature+keyEncipherment, serverAuth, IP SAN) must stay accepted
  SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-tfprofile.pem" SERVER_CERT="$FX/tfprofile.crt" scenario "$1" "$ROW_ID"
  need "rc=$(val rc) reason=$(val reason)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "the terraform-profile CA was not installed" "$([ "$(fp "$(caf)")" = "$(fp "$FX/tfprofile.crt")" ] && echo 0 || echo 1)" || return 1
}

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
  local d
  for d in 1900 1861; do   # 1861 is the first second past the 31-minute skew bound
    SNAP_EXTRA="INNGEST_LINK_TLS=pending:$((NOW + d))\n" CA_MODE=ok scenario "$1" "$ROW_ID$d"
    fails_closed || return 1
    need "now+$d: reason=$(val reason)" "$([ "$(val reason)" = inngest_link_flag_invalid ] && echo 0 || echo 1)" || return 1
  done
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
row_B5_scope_guard_present_and_wrong_fails() {
  local s
  for s in 'DOPPLER_PROJECT=soleur-inngest\nDOPPLER_CONFIG=prd\n' 'DOPPLER_PROJECT=soleur\nDOPPLER_CONFIG=dev\n' 'DOPPLER_PROJECT=soleur\nDOPPLER_PROJECT=soleur\nDOPPLER_CONFIG=prd\n' 'DOPPLER_CONFIG=dev\n' 'DOPPLER_PROJECT=other\n'; do
    SNAP_SCOPE="$s" SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID"
    need "scope lines [$s] did not fail the deploy (rc=$(val rc))" "$([ "$(val rc)" != 0 ] && [ -z "$(val url)" ] && echo 0 || echo 1)" || return 1
    need "reason for [$s] is $(val reason)" "$([ "$(val reason)" = inngest_link_scope_mismatch ] && echo 0 || echo 1)" || return 1
  done
}
row_B5b_scope_lines_absent_flag_absent_warns_and_continues() {
  # userimpact F1: a snapshot without the metadata lines cannot be judged wrong. With the flag absent it must not fail every deploy.
  local s
  for s in '' 'DOPPLER_PROJECT=soleur\n' 'DOPPLER_CONFIG=prd\n'; do
    SNAP_SCOPE="$s" SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID"
    need "scope lines [$s] failed a flag-absent deploy (rc=$(val rc) reason=$(val reason))" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
    need "url [$s]=$(val url)" "$([ "$(val url)" = http://10.0.1.40:8288 ] && echo 0 || echo 1)" || return 1
    need "state [$s]=$(val state)" "$([ "$(val state)" = http_default ] && echo 0 || echo 1)" || return 1
    need "no scope_unverified warning for [$s]" "$(log_has 'class=scope_unverified level=warning' && echo 0 || echo 1)" || return 1
  done
}
row_B5c_scope_lines_absent_flag_set_fails_closed() {
  local s f
  for f in '1' "pending:$((NOW - 5))"; do
    for s in '' 'DOPPLER_PROJECT=soleur\n' 'DOPPLER_CONFIG=prd\n'; do
      SNAP_SCOPE="$s" SNAP_EXTRA="INNGEST_LINK_TLS=$f\n" CA_MODE=ok scenario "$1" "$ROW_ID"
      need "scope [$s] flag [$f]: an unverifiable scope did not fail the flagged deploy (rc=$(val rc))" "$([ "$(val rc)" != 0 ] && [ -z "$(val url)" ] && echo 0 || echo 1)" || return 1
      need "scope [$s] flag [$f]: reason=$(val reason)" "$([ "$(val reason)" = inngest_link_scope_mismatch ] && echo 0 || echo 1)" || return 1
    done
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
row_C_catrue() { BLK="$1" ca_rejected "$FX/v-catrue.pem" "CA:TRUE" "ca"; }
row_C_expired() { BLK="$1" ca_rejected "$FX/v-expired.pem" "expired" "expired"; }
row_C_three() { BLK="$1" ca_rejected "$FX/v-three.pem" "three certificates" "count"; }
row_C_two() { BLK="$1" ca_rejected "$FX/v-two.pem" "two certificates (a second trust anchor for every outbound TLS connection)" "count"; }
row_C_garbage() { BLK="$1" ca_rejected "$FX/v-garbage.pem" "not PEM" "count"; }
row_C_oversize() { BLK="$1" ca_rejected "$FX/v-oversize.pem" "over 4 KiB" "size"; }
row_C_tool_missing_fails_closed() {
  # no openssl on PATH: a flag-on deploy must fail closed (never trust an unvalidated file) and say why=tool
  local farm="$RUNS/farm" t
  rm -rf "$farm"; mkdir -p "$farm"
  for t in base64 tr wc grep awk sed paste cp rm mktemp timeout cat cut sha256sum date sleep mv chmod dirname basename head ls stat install mkdir rmdir; do
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

# flag off: the Doppler CA is never read, validated or installed, so no variant of it can touch a flag-off deploy
row_C9_flag_off_never_reads_or_installs_ca() {
  local v
  for v in good privkey-concat catrue kcsnobc two three garbage; do
    SNAP_EXTRA='' CA_MODE=ok CA_FILE="$FX/v-$v.pem" scenario "$1" "$ROW_ID"
    need "$v: rc=$(val rc)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
    need "$v: url=$(val url)" "$([ "$(val url)" = http://10.0.1.40:8288 ] && echo 0 || echo 1)" || return 1
    need "$v: a CA was written with the flag off" "$([ -f "$(caf)" ] && [ ! -s "$(caf)" ] && echo 0 || echo 1)" || return 1
    need "$v: Doppler was asked for the CA with the flag off" "$([ "$(doppler_calls)" = 0 ] && echo 0 || echo 1)" || return 1
    need "$v: a ca_invalid event was emitted with the flag off" "$(log_has 'class=ca_invalid' && echo 1 || echo 0)" || return 1
  done
}
row_C9b_flag_off_replaces_a_stale_pinned_ca_only_after_the_container_started() {
  # on->off: the pinned CA of an earlier https deploy must not stay mounted in the http state - but the reset happens only once the new
  # container started (inngest_link_commit_scheme), because the OLD https container is live through the canary and the cron drain and a
  # restart of it re-mounts the path. A hard link outside the dir stands for the running container's bind mount.
  # (a) a deploy that dies before the prod start (NO_COMMIT=1): the OLD bytes are still at the path, same inode
  PRE='cp "$FX/good.crt" inngest-ca.pem && ln inngest-ca.pem "../held.pem"' NO_COMMIT=1 SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID-aborted"
  need "rc=$(val rc)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "the pinned CA was emptied at RESOLVE time (an aborted deploy would leave the live https container's restart mounting nothing)" "$([ "$(ca_fp)" = "$GOOD_FP" ] && echo 0 || echo 1)" || return 1
  need "the CA path got a new inode at resolve time" "$([ "$(stat -c %i "$(caf)")" = "$(stat -c %i "$RUN/held.pem")" ] && echo 0 || echo 1)" || return 1
  # (b) after the production container started: replaced through a NEW inode; the old inode keeps its bytes
  PRE='cp "$FX/good.crt" inngest-ca.pem && ln inngest-ca.pem "../held.pem"' SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID"
  need "rc=$(val rc)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "a non-empty pinned CA survived the commit of a flag-off deploy" "$([ -f "$(caf)" ] && [ ! -s "$(caf)" ] && echo 0 || echo 1)" || return 1
  need "the CA path was truncated IN PLACE (the running container's inode lost its bytes)" "$([ "$(fp "$RUN/held.pem")" = "$GOOD_FP" ] && echo 0 || echo 1)" || return 1
  need "the CA path still shares the old inode" "$([ "$(stat -c %i "$(caf)")" != "$(stat -c %i "$RUN/held.pem")" ] && echo 0 || echo 1)" || return 1
  need "Doppler was asked for the CA" "$([ "$(doppler_calls)" = 0 ] && echo 0 || echo 1)" || return 1
  need "a temp file was left behind: $(leftovers)" "$([ -z "$(leftovers)" ] && echo 0 || echo 1)" || return 1
  # (c) an already-empty placeholder is left alone (same inode) and nothing is staged
  PRE=': > inngest-ca.pem && ln inngest-ca.pem "../held.pem"' SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID-empty"
  need "an already-empty placeholder was replaced (its inode changed)" "$([ "$(stat -c %i "$(caf)")" = "$(stat -c %i "$RUN/held.pem")" ] && echo 0 || echo 1)" || return 1
  # (d) a failing reset never fails the deploy and is reported: the directory is made unwritable AFTER the resolve (the commit runs last)
  PRE='cp "$FX/good.crt" inngest-ca.pem' COMMIT_CHMOD=1 SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID-unwritable"
  if [ "$(id -u)" != 0 ]; then
    need "rc=$(val rc): an unwritable dir at commit time failed the deploy" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
    need "no ca_reset_failed warning" "$(log_has 'class=ca_reset_failed level=warning' && echo 0 || echo 1)" || return 1
    need "the old bytes were lost although the reset failed" "$([ "$(ca_fp)" = "$GOOD_FP" ] && echo 0 || echo 1)" || return 1
  fi
}
row_C9d_unverified_scope_never_resets_the_pinned_ca() {
  # a snapshot whose scope cannot be verified (and no https memory) continues on http but must not touch a pinned CA, before or after commit
  PRE='cp "$FX/good.crt" inngest-ca.pem' SNAP_SCOPE='' SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID"
  need "rc=$(val rc)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "an unverified-scope run reset the pinned CA" "$([ "$(ca_fp)" = "$GOOD_FP" ] && echo 0 || echo 1)" || return 1
}
row_C9c_flag_off_lapsed_lease_never_installs_ca() {
  SNAP_EXTRA="INNGEST_LINK_TLS=pending:$((NOW - 1900))\n" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$1" "$ROW_ID"
  need "state=$(val state)" "$([ "$(val state)" = http_lease_expired ] && echo 0 || echo 1)" || return 1
  need "a CA was installed on a lapsed lease" "$([ -f "$(caf)" ] && [ ! -s "$(caf)" ] && echo 0 || echo 1)" || return 1
  need "Doppler was asked for the CA on a lapsed lease" "$([ "$(doppler_calls)" = 0 ] && echo 0 || echo 1)" || return 1
}

# --- H2: must-PASS non-canonical input -------------------------------------------------------------
row_H2_noncanonical_passes() {
  local v
  for v in noncanon nonl spoof; do
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

row_D3_dest_is_directory() {
  # an EMPTY directory at the CA path (what docker creates for a missing bind source) is removed and replaced, flag on or off
  PRE='mkdir inngest-ca.pem' SNAP_EXTRA="$ONFLAG" CA_MODE=ok scenario "$1" "$ROW_ID-on"
  need "flag on, empty directory at the CA path: rc=$(val rc) reason=$(val reason)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "flag on: the empty directory was not replaced by the CA file" "$([ -f "$(caf)" ] && [ ! -d "$(caf)" ] && [ "$(ca_fp)" = "$GOOD_FP" ] && echo 0 || echo 1)" || return 1
  PRE='mkdir inngest-ca.pem' SNAP_EXTRA='' CA_MODE=ok scenario "$1" "$ROW_ID-off"
  need "flag off, empty directory at the CA path: rc=$(val rc)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "flag off: the empty directory was not replaced by an empty placeholder FILE" "$([ -f "$(caf)" ] && [ ! -d "$(caf)" ] && [ ! -s "$(caf)" ] && echo 0 || echo 1)" || return 1
  # a NON-empty directory cannot be replaced: flag on fails closed, flag off continues loudly
  PRE='mkdir inngest-ca.pem && : > inngest-ca.pem/keep' SNAP_EXTRA="$ONFLAG" CA_MODE=ok scenario "$1" "$ROW_ID-ne-on"
  need "flag on with a non-empty directory at the CA path must fail (rc=$(val rc))" "$([ "$(val rc)" != 0 ] && [ -z "$(val url)" ] && echo 0 || echo 1)" || return 1
  need "flag on, non-empty directory: reason=$(val reason), want inngest_link_write_failed" "$([ "$(val reason)" = inngest_link_write_failed ] && echo 0 || echo 1)" || return 1
  PRE='mkdir inngest-ca.pem && : > inngest-ca.pem/keep' SNAP_EXTRA='' CA_MODE=ok scenario "$1" "$ROW_ID-ne-off"
  need "flag off with a non-empty directory at the CA path must not fail the deploy (rc=$(val rc))" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "flag off, non-empty directory: no ca_unwritable warning" "$(log_has 'class=ca_unwritable level=warning' && echo 0 || echo 1)" || return 1
}
row_D5_missing_dir_is_created() {
  # the directory (/mnt/data/inngest-link on a real host) may not exist on the first deploy after merge: the resolver creates it,
  # and the bind source FILE exists afterwards (placeholder with the flag off, the validated PEM with the flag on)
  LINK_SUBDIR=inngest-link SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID-off"
  need "flag off: rc=$(val rc)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "flag off: the placeholder CA file was not created in the missing directory" "$([ -f "$LINKDIR/inngest-link/inngest-ca.pem" ] && [ ! -s "$LINKDIR/inngest-link/inngest-ca.pem" ] && echo 0 || echo 1)" || return 1
  need "flag off: the link env was not created in the missing directory" "$([ -f "$LINKDIR/inngest-link/inngest-link.env" ] && echo 0 || echo 1)" || return 1
  LINK_SUBDIR=inngest-link SNAP_EXTRA="$ONFLAG" CA_MODE=ok scenario "$1" "$ROW_ID-on"
  need "flag on: rc=$(val rc) reason=$(val reason)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "flag on: the CA file in the created directory is not the good certificate" "$([ "$(fp "$LINKDIR/inngest-link/inngest-ca.pem")" = "$GOOD_FP" ] && echo 0 || echo 1)" || return 1
}
row_D4_install_failure_fails_strict() {
  # the link dir is not writable: flag on fails closed, flag off proceeds (best effort, loud)
  PRE='chmod 0555 .' SNAP_EXTRA="$ONFLAG" CA_MODE=ok scenario "$1" "$ROW_ID-on"
  local rc_on url_on; rc_on="$(val rc)"; url_on="$(val url)"
  chmod 0755 "$LINKDIR" 2>/dev/null
  if [ "$(id -u)" = 0 ]; then return 0; fi   # root ignores the mode bits: the row is vacuous there, not red
  need "flag on with an unwritable dir must fail (rc=$rc_on url=$url_on)" "$([ "$rc_on" != 0 ] && [ -z "$url_on" ] && echo 0 || echo 1)" || return 1
  PRE='chmod 0555 .' SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID-off"
  local rc_off; rc_off="$(val rc)"; chmod 0755 "$LINKDIR" 2>/dev/null
  need "flag off with an unwritable dir must not fail the deploy (rc=$rc_off)" "$([ "$rc_off" = 0 ] && echo 0 || echo 1)" || return 1
}


# --- security F4: the downgrade memory (last-scheme) ---------------------------------------------------------------
last() { cat "$LINKDIR/last-scheme" 2>/dev/null; }
row_G1_https_to_http_emits() {
  PRE='printf "https\n" > last-scheme' SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID-a"
  need "rc=$(val rc)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "a https->http transition did not emit https_to_http at warning level" "$(log_has 'class=https_to_http level=warning' && echo 0 || echo 1)" || return 1
  need "the downgrade FAILED the deploy (off is legitimate): url=$(val url)" "$([ "$(val url)" = http://10.0.1.40:8288 ] && echo 0 || echo 1)" || return 1
  need "last-scheme was not updated to http: [$(last)]" "$([ "$(last)" = http ] && echo 0 || echo 1)" || return 1
  PRE='printf "https\n" > last-scheme' SNAP_EXTRA="INNGEST_LINK_TLS=pending:$((NOW - 1900))\n" CA_MODE=absent scenario "$1" "$ROW_ID-b"
  need "a lapsed lease after https did not emit https_to_http" "$(log_has 'class=https_to_http level=warning' && echo 0 || echo 1)" || return 1
}
row_G2_no_event_without_a_downgrade() {
  PRE='printf "http\n" > last-scheme' SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID-hh"
  need "http->http emitted https_to_http" "$(log_has 'class=https_to_http' && echo 1 || echo 0)" || return 1
  SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID-first"
  need "a first run (no last-scheme) emitted https_to_http" "$(log_has 'class=https_to_http' && echo 1 || echo 0)" || return 1
  need "a first run did not persist last-scheme=http: [$(last)]" "$([ "$(last)" = http ] && echo 0 || echo 1)" || return 1
  PRE='printf "https\n" > last-scheme' SNAP_EXTRA="$ONFLAG" CA_MODE=ok scenario "$1" "$ROW_ID-ss"
  need "https->https emitted https_to_http" "$(log_has 'class=https_to_http' && echo 1 || echo 0)" || return 1
  need "last-scheme not https after an https resolve: [$(last)]" "$([ "$(last)" = https ] && echo 0 || echo 1)" || return 1
  PRE='printf "http\n" > last-scheme' SNAP_EXTRA="$ONFLAG" CA_MODE=ok scenario "$1" "$ROW_ID-up"
  need "http->https (the flip) emitted https_to_http" "$(log_has 'class=https_to_http' && echo 1 || echo 0)" || return 1
  need "last-scheme not https after the flip: [$(last)]" "$([ "$(last)" = https ] && echo 0 || echo 1)" || return 1
}
row_G3_corrupt_last_scheme_reads_as_unknown() {
  local v
  for v in 'garbage' 'https extra' 'HTTPS' 'https\nhttps' ''; do
    PRE="printf '$v\\n' > last-scheme" SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID"
    need "last-scheme [$v] emitted https_to_http" "$(log_has 'class=https_to_http' && echo 1 || echo 0)" || return 1
    need "last-scheme [$v] was not rewritten with a valid token: [$(last)]" "$([ "$(last)" = http ] && echo 0 || echo 1)" || return 1
  done
  # a symlink is never followed on read (it could point at a file that says https), and the rename replaces it
  printf 'https\n' > "$RUNS/elsewhere"
  PRE="ln -s $RUNS/elsewhere last-scheme" SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID-sym"
  need "a symlinked last-scheme was followed" "$(log_has 'class=https_to_http' && echo 1 || echo 0)" || return 1
  need "the symlink survived the persist" "$([ ! -L "$LINKDIR/last-scheme" ] && [ "$(last)" = http ] && echo 0 || echo 1)" || return 1
  need "the symlink target was written through" "$([ "$(cat "$RUNS/elsewhere")" = https ] && echo 0 || echo 1)" || return 1
}
row_G4_last_scheme_is_atomic_and_world_readable() {
  SNAP_EXTRA="$ONFLAG" CA_MODE=ok scenario "$1" "$ROW_ID"
  need "last-scheme content is [$(last)]" "$([ "$(cat "$LINKDIR/last-scheme")" = https ] && echo 0 || echo 1)" || return 1
  need "last-scheme mode is $(stat -c %a "$LINKDIR/last-scheme"), want 644" "$([ "$(stat -c %a "$LINKDIR/last-scheme")" = 644 ] && echo 0 || echo 1)" || return 1
  need "a temp file was left behind: $(leftovers)" "$([ -z "$(leftovers)" ] && echo 0 || echo 1)" || return 1
}
row_G5_downgrade_event_reaches_sentry() {
  # the cq-silent-fallback mirror: a warning is POSTed to Sentry (store endpoint, classification tag), the info `resolved` row is not
  PRE='printf "https\n" > last-scheme' KEEP_SENTRY=1 SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID"
  need "no POST to the Sentry store endpoint for https_to_http: $(cat "$RUN/curl.argv")" "$(grep -q 'https://sentry.invalid/api/7/store/' "$RUN/curl.argv" && echo 0 || echo 1)" || return 1
  need "the Sentry POST does not lead with --disable: $(grep 'store/' "$RUN/curl.argv" | head -n1 | cut -c1-60)" "$(case "$(grep 'store/' "$RUN/curl.argv" | head -n1)" in "--disable "*) echo 0 ;; *) echo 1 ;; esac)" || return 1
  need "the Sentry body does not carry the https_to_http classification" "$(grep -q 'https_to_http' "$RUN/curl.argv" && echo 0 || echo 1)" || return 1
  need "exactly one Sentry POST expected (the info resolved row must stay off Sentry): $(grep -c 'store/' "$RUN/curl.argv")" "$([ "$(grep -c 'store/' "$RUN/curl.argv")" = 1 ] && echo 0 || echo 1)" || return 1
}

row_G6_scheme_is_recorded_only_after_the_container_started() {
  # a flip whose canary failed (the deploy died before the production start) must leave the memory alone, so the revert's
  # flag-off deploy is not a spurious https->http downgrade
  NO_COMMIT=1 SNAP_EXTRA="$ONFLAG" CA_MODE=ok scenario "$1" "$ROW_ID-a"
  need "rc=$(val rc)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "last-scheme was written at resolve time: [$(last)]" "$([ ! -e "$LINKDIR/last-scheme" ] && echo 0 || echo 1)" || return 1
  PRE='printf "http\n" > last-scheme' NO_COMMIT=1 SNAP_EXTRA="$ONFLAG" CA_MODE=ok scenario "$1" "$ROW_ID-b"
  need "an aborted https deploy flipped last-scheme to [$(last)]" "$([ "$(last)" = http ] && echo 0 || echo 1)" || return 1
  # ...and the revert (flag off) that follows is then NOT a downgrade
  PRE='printf "http\n" > last-scheme' SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID-revert"
  need "a revert after a never-started https deploy emitted https_to_http" "$(log_has 'class=https_to_http' && echo 1 || echo 0)" || return 1
}
row_H5_unverified_scope_after_https_fails_closed() {
  local s
  for s in '' 'DOPPLER_PROJECT=soleur\n' 'DOPPLER_CONFIG=prd\n'; do
    PRE='printf "https\n" > last-scheme' SNAP_SCOPE="$s" SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID"
    fails_closed || return 1
    need "scope [$s]: reason=$(val reason)" "$([ "$(val reason)" = inngest_link_scope_mismatch ] && echo 0 || echo 1)" || return 1
    need "scope [$s]: the event does not read field=unverified previous=https" "$(log_has 'class=scope_mismatch level=error field=unverified previous=https' && echo 0 || echo 1)" || return 1
    need "scope [$s]: last-scheme was overwritten: [$(last)]" "$([ "$(last)" = https ] && echo 0 || echo 1)" || return 1
    need "scope [$s]: the deploy would have started on cleartext (url=$(val url))" "$([ -z "$(val url)" ] && echo 0 || echo 1)" || return 1
  done
}
row_H5b_unverified_scope_without_https_memory_continues_and_records_nothing() {
  local m
  SNAP_SCOPE='' SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID-none"
  need "no memory: rc=$(val rc) reason=$(val reason)" "$([ "$(val rc)" = 0 ] && [ "$(val url)" = http://10.0.1.40:8288 ] && echo 0 || echo 1)" || return 1
  need "an unverified-scope run recorded a scheme: [$(last)]" "$([ ! -e "$LINKDIR/last-scheme" ] && echo 0 || echo 1)" || return 1
  for m in http 'garbage'; do
    PRE="printf '$m\\n' > last-scheme" SNAP_SCOPE='DOPPLER_CONFIG=prd\n' SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID-$m"
    need "memory [$m]: rc=$(val rc) reason=$(val reason)" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
    need "memory [$m]: the scope_unverified warning is missing" "$(log_has 'class=scope_unverified level=warning' && echo 0 || echo 1)" || return 1
    need "memory [$m]: an unverified run rewrote last-scheme to [$(last)]" "$([ "$(last)" = "$m" ] && echo 0 || echo 1)" || return 1
  done
}
row_H5c_verified_scope_off_after_https_warns_and_proceeds() {
  PRE='printf "https\n" > last-scheme' SNAP_EXTRA='' CA_MODE=absent scenario "$1" "$ROW_ID"
  need "rc=$(val rc) reason=$(val reason)" "$([ "$(val rc)" = 0 ] && [ "$(val url)" = http://10.0.1.40:8288 ] && echo 0 || echo 1)" || return 1
  need "no https_to_http warning" "$(log_has 'class=https_to_http level=warning' && echo 0 || echo 1)" || return 1
  need "the verified off was not recorded: [$(last)]" "$([ "$(last)" = http ] && echo 0 || echo 1)" || return 1
}

# --- one directory: the resolver default, the docker bind sources and the probes' defaults are the same literal --------------
row_K1_default_dir_matches_docker_bind_source_and_probes() {
  local d src n
  d="$(env -u INNGEST_LINK_DIR bash -c 'source "$1" >/dev/null 2>&1; printf %s "$INNGEST_LINK_DIR"' _ "$1")"
  need "the resolver default dir is [$d]" "$([ "$d" = /mnt/data/inngest-link ] && echo 0 || echo 1)" || return 1
  n=0
  while IFS= read -r src; do
    n=$((n + 1))
    need "docker -v source [$src] != [$d/inngest-ca.pem]" "$([ "$src" = "$d/inngest-ca.pem" ] && echo 0 || echo 1)" || return 1
  done < <(grep -oE -- '-v [^ ]+:/etc/soleur/inngest-ca\.pem:ro' "$CI_DEPLOY" | sed -E 's/^-v //; s/:\/etc\/soleur\/inngest-ca\.pem:ro$//')
  need "expected exactly 2 docker -v CA sources (canary + prod), found $n" "$([ "$n" = 2 ] && echo 0 || echo 1)" || return 1
  local probe df_env df_ca
  for probe in inngest-registry-probe.sh inngest-doublefire-probe.sh; do
    df_env="$(grep -oE 'INNGEST_LINK_ENV_FILE:-[^}]+' "$SCRIPT_DIR/$probe" | head -1 | sed 's/^INNGEST_LINK_ENV_FILE:-//')"
    df_ca="$(grep -oE '"\$cacert" = "[^"]+"' "$SCRIPT_DIR/$probe" | head -1 | sed -E 's/^"\$cacert" = "//; s/"$//')"
    need "$probe default link env [$df_env] != [$d/inngest-link.env]" "$([ "$df_env" = "$d/inngest-link.env" ] && echo 0 || echo 1)" || return 1
    need "$probe pinned CA path [$df_ca] != [$d/inngest-ca.pem]" "$([ "$df_ca" = "$d/inngest-ca.pem" ] && echo 0 || echo 1)" || return 1
  done
}

# --- the canary layer (inngest_link_canary_check): five in-container checks, only while the resolver chose https ----------------
canary() { # <block> <run id> [STRICT=1]: runs the check under the docker stub; $RUN/out gets rc= and reason=
  local block="$1" id="$2"
  RUN="$RUNS/$id"; LINKDIR="$RUN/linkdir"
  assert_fixture_dir "$RUN"
  rm -rf "$RUN"; mkdir -p "$LINKDIR"; : > "$RUN/logger.log"; : > "$RUN/docker.argv"
  (
    export RUN_DIR="$RUN" PATH="$BIN:$PATH"
    LOG_TAG=ci-deploy
    unset SENTRY_INGEST_DOMAIN SENTRY_PROJECT_ID SENTRY_PUBLIC_KEY
    # shellcheck disable=SC1090
    source "$block" || exit 99
    INNGEST_LINK_DIR="$LINKDIR"; INNGEST_LINK_CA_STRICT="${STRICT:-1}"; CANARY_FAIL_REASON=""
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
  need "the negative control must run with env -u NODE_EXTRA_CA_CERTS" "$([ "$(grep -cE '^exec soleur-web-platform-canary env -u NODE_EXTRA_CA_CERTS /usr/local/bin/node -e ' "$RUN/docker.argv")" = 1 ] && echo 0 || echo 1)" || return 1
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
row_E7_canary_event_carries_check_and_cause() {
  local t want out_pos
  # <positive output tail>|<expected event detail>
  for t in 'health=fail:ECONNREFUSED events=ok send=ok registry=ok|check=health cause=ECONNREFUSED' \
           'health=ok events=fail:HTTP_401 send=ok registry=ok|check=events cause=HTTP_401' \
           'health=ok events=ok send=fail:DEPTH_ZERO_SELF_SIGNED_CERT registry=ok|check=send cause=DEPTH_ZERO_SELF_SIGNED_CERT' \
           'health=ok events=ok send=ok registry=fail:EMPTY|check=registry cause=EMPTY' \
           'health=fail events=ok send=ok registry=ok|check=health cause=unknown' \
           'health=fail:ETIMEDOUT events=fail:HTTP_500 send=ok registry=ok|check=health cause=ETIMEDOUT'; do
    out_pos="${t%%|*}"; want="${t#*|}"
    FX_POS="inngest_link_canary $out_pos" canary "$1" "$ROW_ID"
    canary_fails || { WHY="[$out_pos]: ${WHY:-}"; return 1; }
    need "[$out_pos]: the event does not read '$want': $(grep canary_failed "$RUN/logger.log")" "$(log_has "class=canary_failed level=error $want" && echo 0 || echo 1)" || return 1
  done
  FX_NEG='inngest_link_canary_neg=accepted' canary "$1" "$ROW_ID"
  need "negative control accepted: the event does not read 'check=negative_control cause=accepted'" "$(log_has 'class=canary_failed level=error check=negative_control cause=accepted' && echo 0 || echo 1)" || return 1
  for t in 'inngest_link_canary_neg=a;rm -rf' 'inngest_link_canary_neg=aaaaaaaaaaaaaaaaaaaaaaaaa' 'inngest_link_canary_neg=ACCEPTED' 'inngest_link_canary_neg=other
class=forged level=info'; do
    FX_NEG="$t" canary "$1" "$ROW_ID"
    need "hostile negative-control token [$t] did not read cause=no_verdict: $(grep canary_failed "$RUN/logger.log")" "$(log_has 'class=canary_failed level=error check=negative_control cause=no_verdict' && echo 0 || echo 1)" || return 1
    need "hostile negative-control token [$t] forged a second event line" "$([ "$(grep -c 'class=forged' "$RUN/logger.log")" = 0 ] && echo 0 || echo 1)" || return 1
  done
  FX_INSPECT=http canary "$1" "$ROW_ID"
  need "inspect failure: the event does not read 'check=inspect cause=none'" "$(log_has 'class=canary_failed level=error check=inspect cause=none' && echo 0 || echo 1)" || return 1
  FX_POS='garbage' canary "$1" "$ROW_ID"
  need "no verdict: the event does not read 'check=no_verdict cause=none'" "$(log_has 'class=canary_failed level=error check=no_verdict cause=none' && echo 0 || echo 1)" || return 1
}
row_E6_canary_unparseable_output_is_a_failure() {
  local t
  # a hostile or oversized cause token never parses (it would otherwise reach the event and Sentry)
  for t in 'garbage' 'inngest_link_canary health=fail:a;rm events=ok send=ok registry=ok' 'inngest_link_canary health=fail:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA events=ok send=ok registry=ok' 'inngest_link_canary health=fail: events=ok send=ok registry=ok' 'inngest_link_canary health=ok events=ok send=ok registry=ok EXTRA=secret' 'x inngest_link_canary health=ok events=ok send=ok registry=ok' ''; do
    FX_POS="$t" canary "$1" "$ROW_ID"
    canary_fails || { WHY="out=[$t]: ${WHY:-}"; return 1; }
    need "out=[$t]: unparseable output must read check=no_verdict, not leak a token: $(grep canary_failed "$RUN/logger.log")" "$(log_has 'class=canary_failed level=error check=no_verdict cause=none' && echo 0 || echo 1)" || return 1
  done
  FX_EXEC_RC=7 canary "$1" "$ROW_ID"
  canary_fails || { WHY="docker exec rc 7: ${WHY:-}"; return 1; }
}

ROW_IDS=(
  A1_unset_http A1b_unset_with_ca_never_installed A1c_unset_empty_value_is_absent
  A2_flag_on_https A3_pending_live_https A3b_pending_honoured_boundaries
  A4_wrong_server_fails_closed A4b_pending_wrong_server_fails_closed A5_ca_absent_fails A5b_ca_read_error_fails A5c_ca_empty_fails A5d_pending_ca_absent_fails
  A6_strict_reads_ca_from_snapshot A6b_snapshot_ca_invalid_fails_without_fallback A6c_strict_falls_back_to_doppler_when_snapshot_lacks_ca A6d_duplicate_snapshot_ca_lines_are_not_trusted
  A7_selfgate_leads_with_disable_and_requires_200 A8_selfgate_retries_with_a_pause
  F2_selfgate_failure_leaves_previous_ca F2b_selfgate_failure_installs_nothing_when_no_previous F1_kcs_without_basicconstraints_rejected F1b_kcs_with_ca_false_rejected F1c_terraform_profile_accepted F1d_kcs_with_crl_sign_rejected F1e_kcs_mid_list_rejected
  B1_lease_expired_http B2_pending_too_far_ahead_fails B3_non_allowlisted_fail B4_snapshot_unreadable_fails B5_scope_guard_present_and_wrong_fails B5b_scope_lines_absent_flag_absent_warns_and_continues B5c_scope_lines_absent_flag_set_fails_closed B6_duplicate_flag_fails
  C_privkey_concat C_privkey_prefixed C_privkey_only C_catrue C_expired C_three C_two C_garbage C_oversize C_tool_missing_fails_closed C_empty_value C_bad_base64 C_huge_base64
  C9_flag_off_never_reads_or_installs_ca C9b_flag_off_replaces_a_stale_pinned_ca_only_after_the_container_started C9c_flag_off_lapsed_lease_never_installs_ca C9d_unverified_scope_never_resets_the_pinned_ca
  H2_noncanonical_passes H2b_unset_and_valid_pass
  D1_link_env_not_derived_from_text D3_dest_is_directory D4_install_failure_fails_strict D5_missing_dir_is_created
  G1_https_to_http_emits G2_no_event_without_a_downgrade G3_corrupt_last_scheme_reads_as_unknown G4_last_scheme_is_atomic_and_world_readable G5_downgrade_event_reaches_sentry
  G6_scheme_is_recorded_only_after_the_container_started H5_unverified_scope_after_https_fails_closed H5b_unverified_scope_without_https_memory_continues_and_records_nothing H5c_verified_scope_off_after_https_warns_and_proceeds
  K1_default_dir_matches_docker_bind_source_and_probes
  E1_canary_flag_off_is_a_noop E2_canary_all_good E3_canary_inspect_must_show_https E4_canary_each_positive_check_gates
  E5_canary_negative_control_must_fail_verification E6_canary_unparseable_output_is_a_failure E7_canary_event_carries_check_and_cause
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
L_GAK="$(lineno 'github_app_key_canary_check; then')"
L_LAYER5="$(lineno '! inngest_link_canary_check; then')"
L_SWAP="$(lineno 'echo "Canary passed, swapping to production..."')"
L_PROD_RUN="$(lineno '--name soleur-web-platform \')"
wire_ok() { # <desc> <a> <b> : a < b, both non-empty
  ROWS=$((ROWS + 1))
  if [ -n "$2" ] && [ -n "$3" ] && [ "$2" -lt "$3" ]; then ok "wiring: $1 ($2 < $3)"; else bad "wiring: $1 (got '$2' then '$3')"; fi
}
wire_ok "the resolver runs before the canary docker run" "$L_RES" "$L_CANARY_RUN"
wire_ok "the canary layer-5 check runs after the GitHub App key check and before promotion" "$L_GAK" "$L_LAYER5"
wire_ok "layer 5 gates promotion (before the swap)" "$L_LAYER5" "$L_SWAP"
ROWS=$((ROWS + 1))
if [ "$(grep -c 'INNGEST_BASE_URL="\$INNGEST_BASE_URL_RESOLVED"' "$CI_DEPLOY")" = 2 ] && ! grep -qE '^[[:space:]]+-e INNGEST_BASE_URL=http' "$CI_DEPLOY"; then ok "wiring: both docker run sites take the resolver expansion and no literal URL remains"; else bad "wiring: a docker run site does not take the resolver expansion (or a literal URL remains)"; fi

# --- the first-boot placeholder (cloud-init.yml): a fresh web host must have the CA bind source as a FILE before its first `docker run` ---
L_CI_DIR="$(grep -nF -- 'install -d -o deploy -g deploy -m 0755 /mnt/data/inngest-link' "$CLOUD_INIT" | head -1 | cut -d: -f1)"
L_CI_PH="$(grep -nF -- "[ -f /mnt/data/inngest-link/inngest-ca.pem ] || install -o deploy -g deploy -m 0644 /dev/null /mnt/data/inngest-link/inngest-ca.pem" "$CLOUD_INIT" | head -1 | cut -d: -f1)"
L_CI_RUN="$(grep -nF -- '      --name soleur-web-platform \' "$CLOUD_INIT" | head -1 | cut -d: -f1)"
wire_ok "cloud-init.yml creates /mnt/data/inngest-link (deploy-owned) before the placeholder file" "$L_CI_DIR" "$L_CI_PH"
wire_ok "cloud-init.yml creates the empty CA placeholder file before the first-boot docker run" "$L_CI_PH" "$L_CI_RUN"
ROWS=$((ROWS + 1))
if [ "$(grep -cF -- '-v /mnt/data/inngest-link/inngest-ca.pem:/etc/soleur/inngest-ca.pem:ro' "$CLOUD_INIT")" = 1 ]; then ok "wiring: cloud-init.yml first-boot docker run mounts the placeholder as the CA file"; else bad "wiring: cloud-init.yml first-boot docker run does not mount /mnt/data/inngest-link/inngest-ca.pem exactly once"; fi

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
# H4: Node executes BOTH in-container canary scripts (the exact strings the host passes to `docker exec ... node -e`) against a
# loopback https server presenting a synthesized CA:FALSE certificate. A syntax slip, a wrong Bearer derivation or a token drift would
# otherwise surface only at the production flip. The server records the Authorization header of /v1/events and the body of /e/<key>.
# ---------------------------------------------------------------------------------------
if command -v node >/dev/null 2>&1; then
  ( source "$BLOCK_REAL" >/dev/null 2>&1; printf '%s' "$INNGEST_LINK_CANARY_POS" ) > "$WORK/canary-pos.js"
  ( source "$BLOCK_REAL" >/dev/null 2>&1; printf '%s' "$INNGEST_LINK_CANARY_NEG" ) > "$WORK/canary-neg.js"
  cat > "$WORK/canary-harness.cjs" <<'JS'
const https = require("https"), fs = require("fs"), crypto = require("crypto"), { spawn } = require("child_process");
const [cert, key, posf, negf, xcert, xkey] = process.argv.slice(2);
const POS = fs.readFileSync(posf, "utf8"), NEG = fs.readFileSync(negf, "utf8");
const HEX = "ab".repeat(32), SK = "signkey-prod-" + HEX, EK = "evkey123";
let mode = "ok", auth = "", sendBody = "", sendPath = "";
const srv = https.createServer({ cert: fs.readFileSync(cert), key: fs.readFileSync(key) }, (q, r) => {
  let body = ""; q.on("data", (d) => (body += d));
  q.on("end", () => {
    const u = q.url.split("?")[0];
    const reply = (code, obj) => { r.statusCode = code; r.setHeader("content-type", "application/json"); r.end(JSON.stringify(obj)); };
    if (u === "/health" && mode === "garbage") { q.socket.write("THIS IS NOT HTTP\r\n\r\n"); return setTimeout(() => q.socket.destroy(), 200); }
    if (u === "/health") return reply(mode === "health503" ? 503 : 200, {});
    if (u === "/v1/events") { auth = q.headers.authorization || ""; return reply(mode === "events401" ? 401 : 200, { data: [] }); }
    if (u.startsWith("/e/")) { sendBody = body; sendPath = u; return reply(200, { ids: ["x"] }); }
    if (u === "/v0/gql") return reply(200, { data: { functions: mode === "emptyreg" ? [] : [{ id: "fn-a" }] } });
    return reply(404, {});
  });
});
const run = (script, env) => new Promise((res) => {
  const c = spawn(process.execPath, ["-e", script], { env: Object.assign({ PATH: process.env.PATH }, env) });
  let out = ""; c.stdout.on("data", (d) => (out += d)); c.on("close", () => res(out.trim()));
});
srv.listen(0, "127.0.0.1", async () => {
  const base = "https://127.0.0.1:" + srv.address().port;
  const E = { INNGEST_BASE_URL: base, INNGEST_SIGNING_KEY: SK, INNGEST_EVENT_KEY: EK, NODE_EXTRA_CA_CERTS: cert };
  const NOCA = Object.assign({}, E); delete NOCA.NODE_EXTRA_CA_CERTS;
  const out = [];
  mode = "ok"; out.push(["pos_ok", await run(POS, E)]);
  const want = "Bearer signkey-prod-" + crypto.createHash("sha256").update(Buffer.from(HEX, "hex")).digest("hex");
  out.push(["bearer", auth === want ? "match" : "mismatch"]);
  out.push(["send", (JSON.parse(sendBody || "[]")[0] || {}).name + " " + (sendPath === "/e/" + EK ? "key-in-path" : "wrong-path")]);
  mode = "health503"; out.push(["pos_health503", await run(POS, E)]);
  mode = "events401"; out.push(["pos_events401", await run(POS, E)]);
  mode = "emptyreg"; out.push(["pos_emptyreg", await run(POS, E)]);
  mode = "ok"; out.push(["pos_noca", await run(POS, NOCA)]);
  out.push(["neg_withca", await run(NEG, E)]);
  out.push(["neg_noca", await run(NEG, NOCA)]);
  mode = "garbage"; out.push(["pos_unmapped", await run(POS, E)]);
  // an EXPIRED (but pinned) certificate: a second listener presenting it, trusted through NODE_EXTRA_CA_CERTS
  await new Promise((res) => {
    const xsrv = https.createServer({ cert: fs.readFileSync(xcert), key: fs.readFileSync(xkey) }, (q, r) => { r.end("{}"); });
    xsrv.listen(0, "127.0.0.1", async () => {
      const XE = Object.assign({}, E, { INNGEST_BASE_URL: "https://127.0.0.1:" + xsrv.address().port, NODE_EXTRA_CA_CERTS: xcert });
      out.push(["pos_expired", await run(POS, XE)]);
      out.push(["neg_expired", await run(NEG, XE)]);
      xsrv.close(); res();
    });
  });
  srv.close();
  out.push(["pos_refused", await run(POS, E)]);
  out.push(["neg_refused", await run(NEG, E)]);
  for (const [n, v] of out) console.log(n + "|" + v);
  process.exit(0);
});
JS
  H4="$(timeout 120 node "$WORK/canary-harness.cjs" "$FX/loop.crt" "$FX/loop.key" "$WORK/canary-pos.js" "$WORK/canary-neg.js" "$FX/expired-loop.crt" "$FX/expired-loop.key" 2>&1)"
  h4() { grep -m1 "^$1|" <<< "$H4" | cut -d'|' -f2-; }
  h4_expect() { # <name> <expected>
    ROWS=$((ROWS + 1))
    if [ "$(h4 "$1")" = "$2" ]; then ok "H4 canary under Node: $1 -> $2"; else bad "H4 canary under Node: $1 printed '$(h4 "$1")', want '$2'"; fi
  }
  CAUSE_NOCA=DEPTH_ZERO_SELF_SIGNED_CERT
  h4_expect pos_ok "inngest_link_canary health=ok events=ok send=ok registry=ok"
  h4_expect bearer "match"
  h4_expect send "soleur.tls-canary.ping key-in-path"
  h4_expect pos_health503 "inngest_link_canary health=fail:HTTP_503 events=ok send=ok registry=ok"
  h4_expect pos_events401 "inngest_link_canary health=ok events=fail:HTTP_401 send=ok registry=ok"
  h4_expect pos_emptyreg "inngest_link_canary health=ok events=ok send=ok registry=fail:EMPTY"
  h4_expect pos_noca "inngest_link_canary health=fail:$CAUSE_NOCA events=fail:$CAUSE_NOCA send=fail:$CAUSE_NOCA registry=fail:$CAUSE_NOCA"
  h4_expect pos_unmapped "inngest_link_canary health=fail:other events=ok send=ok registry=ok"
  h4_expect pos_expired "inngest_link_canary health=fail:CERT_HAS_EXPIRED events=fail:CERT_HAS_EXPIRED send=fail:CERT_HAS_EXPIRED registry=fail:CERT_HAS_EXPIRED"
  h4_expect neg_expired "inngest_link_canary_neg=other"
  h4_expect pos_refused "inngest_link_canary health=fail:ECONNREFUSED events=fail:ECONNREFUSED send=fail:ECONNREFUSED registry=fail:ECONNREFUSED"
  h4_expect neg_withca "inngest_link_canary_neg=accepted"
  h4_expect neg_noca "inngest_link_canary_neg=verify_error"
  h4_expect neg_refused "inngest_link_canary_neg=other"
  # every line either script printed matches the grammar the host parser accepts (bounded cause tokens, nothing else)
  ROWS=$((ROWS + 1))
  H4_POS="$(grep -E '^pos_' <<< "$H4" | cut -d'|' -f2-)"
  if ! grep -vqE '^inngest_link_canary health=(ok|fail:[A-Za-z0-9_]{1,40}) events=(ok|fail:[A-Za-z0-9_]{1,40}) send=(ok|fail:[A-Za-z0-9_]{1,40}) registry=(ok|fail:[A-Za-z0-9_]{1,40})$' <<< "$H4_POS"; then
    ok "H4 every positive-script line fits the host grammar"
  else bad "H4 a positive-script line does not fit the host grammar: $H4"; fi
else
  ROWS=$((ROWS + 14)); SKIP=$((SKIP + 14)); printf '[skip] H4 node is not installed: the canary scripts were not executed\n'
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
  # an anchor that no longer matches is reported as its OWN [FAIL] and the battery continues (a nearby legitimate edit must not
  # hide which behaviour rows still pass or fail behind a HARNESS ABORT)
  blk="$(mut_block "$mid" "$@")" || { ROWS=$((ROWS + 1)); bad "mutation $mid: its anchor was not found in the block (or the edit changed nothing): the mutation did not land, update the anchor"; return 0; }
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
  'if ! _inngest_link_selfgate "$cand"; then' 'if false; then'
kill_mut M05b-selfgate-without-cacert "A2_flag_on_https" \
  '      --cacert "$1" "$INNGEST_LINK_HTTPS_URL/health"' '      "$INNGEST_LINK_HTTPS_URL/health"'
kill_mut M05c-selfgate-insecure "A2_flag_on_https A4_wrong_server_fails_closed" \
  '      --cacert "$1" "$INNGEST_LINK_HTTPS_URL/health"' '      -k --cacert "$1" "$INNGEST_LINK_HTTPS_URL/health"'
kill_mut M05d-downgrade-on-gate-failure "A4_wrong_server_fails_closed A4b_pending_wrong_server_fails_closed" \
  'then rm -f "$cand"; INNGEST_LINK_REASON=inngest_link_selfgate_failed; return 1; fi' 'then INNGEST_LINK_STATE=http_default; INNGEST_LINK_CA_STRICT=0; fi'
kill_mut M05e-ca-absent-continues "A5_ca_absent_fails" \
  '      if [[ -z "$b64" ]]; then' '      if false; then'
# Guard 1 row 8: a third value
kill_mut M08a-third-https-value "A2_flag_on_https A3_pending_live_https" \
  'INNGEST_LINK_HTTPS_URL="https://10.0.1.40:8443"' 'INNGEST_LINK_HTTPS_URL="http://10.0.1.40:8443"'
kill_mut M08b-third-http-value "A1_unset_http B1_lease_expired_http" \
  'INNGEST_LINK_HTTP_URL="http://10.0.1.40:8288"' 'INNGEST_LINK_HTTP_URL="http://10.0.1.40:8443"'
kill_mut M08c-link-env-from-flag-text "A3_pending_live_https D1_link_env_not_derived_from_text" \
  '"$url" "$scheme" "$cacert"' '"$url" "$scheme" "$cacert $flag"'
# Guard 1 row 9: a read error is not an absence
SNAPFAIL='|| { INNGEST_LINK_REASON=inngest_link_snapshot_unreadable; inngest_link_event snapshot_unreadable error; return 1; }'
kill_mut M09a-read-error-falls-through "B4_snapshot_unreadable_fails" \
  "_inngest_link_snap_get \"\$snap\" INNGEST_LINK_TLS $SNAPFAIL" '_inngest_link_snap_get "$snap" INNGEST_LINK_TLS || true' \
  "_inngest_link_snap_get \"\$snap\" DOPPLER_PROJECT $SNAPFAIL" '_inngest_link_snap_get "$snap" DOPPLER_PROJECT || true' \
  "_inngest_link_snap_get \"\$snap\" DOPPLER_CONFIG $SNAPFAIL" '_inngest_link_snap_get "$snap" DOPPLER_CONFIG || true'
kill_mut M09b-project-scope-guard-removed "B5_scope_guard_present_and_wrong_fails" \
  'if [[ "$proj_n" -gt 1 || ( "$proj_n" == 1 && "$proj_v" != soleur ) ]]; then' 'if false; then'
kill_mut M09c-config-scope-guard-removed "B5_scope_guard_present_and_wrong_fails" \
  'if [[ "$cfg_n" -gt 1 || ( "$cfg_n" == 1 && "$cfg_v" != prd ) ]]; then' 'if false; then'
kill_mut M09d-unverifiable-scope-passes-a-flagged-fleet "B5c_scope_lines_absent_flag_set_fails_closed" \
  'if [[ -n "$flag" ]]; then INNGEST_LINK_REASON=inngest_link_scope_mismatch; inngest_link_event scope_mismatch error "field=unverified"; return 1; fi' ':'
kill_mut M09e-absent-scope-fails-every-deploy "B5b_scope_lines_absent_flag_absent_warns_and_continues" \
  'inngest_link_event scope_unverified warning "project_lines=$proj_n config_lines=$cfg_n action=http_default"' 'INNGEST_LINK_REASON=inngest_link_scope_mismatch; return 1'
kill_mut M09f-absent-scope-is-silent "B5b_scope_lines_absent_flag_absent_warns_and_continues" \
  'inngest_link_event scope_unverified warning' ':'
# Guard 1 row 10: CA validation weakened, one mutation per variant
kill_mut M10a-private-key-allowed "C_privkey_prefixed" \
  "if grep -q 'PRIVATE KEY' \"\$raw\"; then _IL_WHY=key; break; fi" 'if false; then break; fi'
kill_mut M10c-ca-true-allowed "C_catrue F1_kcs_without_basicconstraints_rejected" \
  "if grep -qE 'CA:TRUE|Certificate Sign' <<< \"\$x509\"; then _IL_WHY=ca; break; fi" 'if false; then break; fi'
kill_mut M10h-certificate-sign-allowed "F1_kcs_without_basicconstraints_rejected F1b_kcs_with_ca_false_rejected" \
  "'CA:TRUE|Certificate Sign'" "'CA:TRUE'"
kill_mut M10i-keyusage-not-parsed "F1_kcs_without_basicconstraints_rejected F1b_kcs_with_ca_false_rejected" \
  '-ext basicConstraints,keyUsage' '-ext basicConstraints'
kill_mut M10d-second-certificate-allowed "C_two C_three" \
  '[[ "$n_begin" == 1 && "$n_cert" == 1 ]]' '[[ "$n_begin" -le 3 && "$n_begin" == "$n_cert" ]]'
kill_mut M10e-expiry-unchecked "C_expired" \
  '*"will expire"*) _IL_WHY=expired; break ;;' '*"will expire"*) : ;;'
kill_mut M10g-size-unbounded "C_oversize" \
  '-le 4096 ]] || { _IL_WHY=size; break; }' '-le 4096000 ]] || { _IL_WHY=size; break; }'
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
  '"$out" != "inngest_link_canary_neg=verify_error" ]]; then' '"$out" == "__never__" ]]; then'
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
  'if [[ "$val" != ok ]]; then' 'if [[ "$val" != ok && "$name" != send ]]; then'
kill_mut M13d-verdict-unanchored "E6_canary_unparseable_output_is_a_failure" \
  '{1,40})?)$ ]]; then' '{1,40})?) ]]; then'
kill_mut M13f-cause-dropped-from-the-event "E7_canary_event_carries_check_and_cause" \
  'inngest_link_event canary_failed error "check=$why cause=$cause"' 'inngest_link_event canary_failed error "check=$why"'
kill_mut M13g-bare-fail-has-no-cause-default "E7_canary_event_carries_check_and_cause" \
  'cause="${cause:-unknown}"' 'cause="${cause:-}"'
kill_mut M13e-canary-runs-with-flag-off "E1_canary_flag_off_is_a_noop" \
  '  [[ "$INNGEST_LINK_CA_STRICT" == 1 ]] || return 0
  envs=' '  envs='
# the flag-off placeholder, the install failure, the gate-before-install ordering, the downgrade memory
kill_mut M12a-flag-off-takes-the-strict-path "A1_unset_http A1b_unset_with_ca_never_installed C9_flag_off_never_reads_or_installs_ca C9c_flag_off_lapsed_lease_never_installs_ca" \
  'if [[ "$INNGEST_LINK_CA_STRICT" != 1 ]]; then' 'if false; then'
kill_mut M12d-mkdir-p-removed "D5_missing_dir_is_created" \
  '  mkdir -p "$(dirname "$2")" 2>/dev/null || true
' ''
kill_mut M12b-strict-install-failure-ignored "D3_dest_is_directory" \
  'INNGEST_LINK_REASON=inngest_link_write_failed; inngest_link_event write_failed error "file=ca"; return 1' ':'
kill_mut M12e-empty-directory-not-removed "D3_dest_is_directory" \
  '  if [[ -d "$2" && ! -L "$2" ]]; then rmdir "$2" 2>/dev/null || true; fi
' ''
kill_mut M12f-stale-pinned-ca-left-mounted-with-flag-off "C9b_flag_off_replaces_a_stale_pinned_ca_only_after_the_container_started" \
  'if [[ -f "$ca_dest" && ! -L "$ca_dest" && ! -s "$ca_dest" ]]; then' 'if [[ -f "$ca_dest" && ! -L "$ca_dest" ]]; then'
kill_mut M14a-selfgate-on-the-installed-path "A2_flag_on_https F2_selfgate_failure_leaves_previous_ca" \
  'if ! _inngest_link_selfgate "$cand"; then' 'if ! _inngest_link_selfgate "$ca_dest"; then'
kill_mut M14b-install-before-gate "F2_selfgate_failure_leaves_previous_ca F2b_selfgate_failure_installs_nothing_when_no_previous A2_flag_on_https" \
  'if ! _inngest_link_selfgate "$cand"; then rm -f "$cand";' '_inngest_link_install "$cand" "$ca_dest" 0644; if ! _inngest_link_selfgate "$ca_dest"; then rm -f "$cand";'
kill_mut M14d-snapshot-ca-ignored "A6_strict_reads_ca_from_snapshot" \
  'if [[ "$_IL_N" == 1 && -n "$_IL_VAL" ]]; then' 'if false; then'
kill_mut M15a-downgrade-not-signalled "G1_https_to_http_emits" \
  'if [[ "$scheme" == http && "$_IL_PREV" == https ]]; then' 'if false; then'
kill_mut M15b-event-on-every-http "G2_no_event_without_a_downgrade" \
  '&& "$_IL_PREV" == https ]]; then' '&& 1 == 1 ]]; then'
kill_mut M15c-last-scheme-symlink-followed "G3_corrupt_last_scheme_reads_as_unknown" \
  '[[ -f "$f" && ! -L "$f" && -r "$f" ]] || return 0' '[[ -f "$f" && -r "$f" ]] || return 0'
kill_mut M15e-last-scheme-never-persisted "G1_https_to_http_emits G2_no_event_without_a_downgrade G4_last_scheme_is_atomic_and_world_readable" \
  '"$INNGEST_LINK_DIR/last-scheme" 0644' '"$INNGEST_LINK_DIR/.last-scheme.x" 0644'
kill_mut M15f-downgrade-fails-the-deploy "G1_https_to_http_emits" \
  'inngest_link_event https_to_http warning "state=$INNGEST_LINK_STATE previous=https"' 'inngest_link_event https_to_http warning "state=$INNGEST_LINK_STATE previous=https"; return 1'
kill_mut M17a-unverified-scope-after-https-passes "H5_unverified_scope_after_https_fails_closed" \
  'if [[ "$_IL_PREV" == https ]]; then INNGEST_LINK_REASON=inngest_link_scope_mismatch;' 'if false; then INNGEST_LINK_REASON=inngest_link_scope_mismatch;'
kill_mut M17b-unverified-run-records-the-scheme "H5b_unverified_scope_without_https_memory_continues_and_records_nothing" \
  'if [[ "$scope_verified" == 1 ]]; then INNGEST_LINK_PENDING_SCHEME="$scheme"; fi' 'INNGEST_LINK_PENDING_SCHEME="$scheme"'
kill_mut M17c-scheme-recorded-at-resolve "G6_scheme_is_recorded_only_after_the_container_started" \
  'if [[ "$scope_verified" == 1 ]]; then INNGEST_LINK_PENDING_SCHEME="$scheme"; fi' 'if [[ "$scope_verified" == 1 ]]; then INNGEST_LINK_PENDING_SCHEME="$scheme"; inngest_link_commit_scheme; fi'
kill_mut M17d-unverified-scope-fails-every-flag-off-deploy "H5b_unverified_scope_without_https_memory_continues_and_records_nothing" \
  '    scope_verified=0
' '    scope_verified=0; INNGEST_LINK_REASON=inngest_link_scope_mismatch; return 1
'
kill_mut M17e-commit-never-records "G1_https_to_http_emits G4_last_scheme_is_atomic_and_world_readable" \
  '  [[ "$INNGEST_LINK_PENDING_SCHEME" == https || "$INNGEST_LINK_PENDING_SCHEME" == http ]] || return 0' '  return 0'
kill_mut M18a-selfgate-curl-without-disable "A7_selfgate_leads_with_disable_and_requires_200" \
  'code="$(timeout 20 curl --disable --noproxy' 'code="$(timeout 20 curl --noproxy'
kill_mut M18b-selfgate-accepts-any-http-code "A7_selfgate_leads_with_disable_and_requires_200" \
  'if [[ "$rc" -eq 0 && "$code" == 200 ]]; then return 0; fi' 'if [[ "$rc" -eq 0 ]]; then return 0; fi'
kill_mut M18c-selfgate-never-retries "A8_selfgate_retries_with_a_pause" \
  'if [[ "$i" -ge "$max" ]]; then break; fi' 'break'
kill_mut M18d-selfgate-retries-without-pause "A8_selfgate_retries_with_a_pause" \
  '    sleep 2
    i=$((i + 1))' '    i=$((i + 1))'
kill_mut M18e-selfgate-default-one-attempt "A8_selfgate_retries_with_a_pause" \
  'max="${INNGEST_LINK_SELFGATE_ATTEMPTS:-3}"' 'max="${INNGEST_LINK_SELFGATE_ATTEMPTS:-1}"'
kill_mut M18f-future-bound-one-second-late "B2_pending_too_far_ahead_fails" \
  'if (( epoch > now + 1860 )); then' 'if (( epoch > now + 1861 )); then'
kill_mut M18g-future-bound-one-second-early "A3b_pending_honoured_boundaries" \
  'if (( epoch > now + 1860 )); then' 'if (( epoch > now + 1859 )); then'
kill_mut M18h-lease-ends-early "A3b_pending_honoured_boundaries" \
  'elif (( now >= epoch + 1800 )); then' 'elif (( now >= epoch + 1795 )); then'
kill_mut M18i-certificate-sign-anchored-at-line-end "F1d_kcs_with_crl_sign_rejected F1e_kcs_mid_list_rejected" \
  "'CA:TRUE|Certificate Sign'" "'CA:TRUE|Certificate Sign\$'"
kill_mut M18j-snapshot-takes-the-last-duplicate-ca "A6d_duplicate_snapshot_ca_lines_are_not_trusted" \
  'if [[ "$_IL_N" == 1 && -n "$_IL_VAL" ]]; then' 'if [[ "$_IL_N" -ge 1 && -n "$_IL_VAL" ]]; then'
kill_mut M18k-negative-control-cause-unbounded "E7_canary_event_carries_check_and_cause" \
  '"$cause" =~ ^[a-z_]{1,20}$' '"$cause" =~ ^.*$'
kill_mut M19a-ca-reset-at-resolve-time "C9b_flag_off_replaces_a_stale_pinned_ca_only_after_the_container_started" \
  'if [[ "$scope_verified" == 1 ]]; then INNGEST_LINK_PENDING_CA_RESET=1; fi' 'if [[ "$scope_verified" == 1 ]]; then INNGEST_LINK_PENDING_CA_RESET=1; inngest_link_commit_scheme; fi'
kill_mut M19b-unverified-scope-resets-the-ca "C9d_unverified_scope_never_resets_the_pinned_ca" \
  'if [[ "$scope_verified" == 1 ]]; then INNGEST_LINK_PENDING_CA_RESET=1; fi' 'INNGEST_LINK_PENDING_CA_RESET=1'
kill_mut M19c-commit-never-resets-the-ca "C9b_flag_off_replaces_a_stale_pinned_ca_only_after_the_container_started" \
  'if [[ "$INNGEST_LINK_PENDING_CA_RESET" == 1 ]]; then' 'if false; then'
kill_mut M19d-ca-reset-failure-is-silent "C9b_flag_off_replaces_a_stale_pinned_ca_only_after_the_container_started" \
  'inngest_link_event ca_reset_failed warning "dir=$INNGEST_LINK_DIR action=continue"' ':'
kill_mut M16a-link-dir-default-moved "K1_default_dir_matches_docker_bind_source_and_probes" \
  'INNGEST_LINK_DIR="${INNGEST_LINK_DIR:-/mnt/data/inngest-link}"' 'INNGEST_LINK_DIR="${INNGEST_LINK_DIR:-/mnt/data/inngest-link2}"'


# ---------------------------------------------------------------------------------------
# LEDGER
# ---------------------------------------------------------------------------------------
printf '\n=== inngest-link-resolver: %d passed, %d failed, %d skipped (%d rows) ===\n' "$PASS" "$FAIL" "$SKIP" "$ROWS"
# The anti-vacuity floor comes FIRST: scripts/guard-vacuity-floor.test.sh neuters every counter and runs the first floor it
# finds, which must be this one (the accounting identity below holds trivially at zero).
MIN_ROWS=168
if [ "$ROWS" -lt "$MIN_ROWS" ]; then
  printf '[FATAL] anti-vacuity floor: only %s rows ran, floor is %s\n' "$ROWS" "$MIN_ROWS" >&2
  exit 1
fi
if [ "$((PASS + FAIL + SKIP))" -lt "$ROWS" ]; then
  printf '[FATAL] accounting: passes(%s)+fails(%s)+skips(%s) < rows(%s) - a verdict was discarded\n' "$PASS" "$FAIL" "$SKIP" "$ROWS" >&2
  exit 1
fi
# The floor is pinned EXACTLY to the measured row count: deleting a row is as visible as lowering the literal.
if [ "$ROWS" -gt "$MIN_ROWS" ]; then
  printf '[FATAL] floor drift: %s rows ran but MIN_ROWS is %s - set MIN_ROWS=%s\n' "$ROWS" "$MIN_ROWS" "$ROWS" >&2
  exit 1
fi
if [ "$FAIL" -gt 0 ]; then printf 'FAIL: %d check(s) failed\n' "$FAIL"; exit 1; fi
printf 'OK\n'
