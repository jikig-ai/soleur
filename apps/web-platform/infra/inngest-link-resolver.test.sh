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
#       is NOT (a non-CA anchor cannot issue);
#   H4  Node executes both in-container canary scripts against a loopback https server;
#   H1b/H8 (#10934)  an always-succeeding curl, and a stub that ignores the profile list, turn the phase rows RED;
#   H7a-H7c (#10934) the shared curl profile printer: the table is exactly the named set, it refuses an unknown variable or profile, and
#       the refusal reaches the per-row sentinel through the real self-gate;
#   H6/H9 (#10934)   the REAL self-gate against REAL curl and local TLS listeners: each profile matches what real curl prints and the
#       phase the real function emits equals the phase the stub profile emits; H9 flips one profile column at a time (five rows) and
#       each must turn the comparison RED.
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

# an ambient override of the shared profile file would be sourced by every curl double: only H9 sets it, deliberately, in a subshell.
# CURL_W_SENTINEL is the same class: the in-process rows (H7a, h6_compare) source the fixture in THIS shell, where curlw_fail appends to the
# ambient path (the doubles bake their own sentinel path and are not affected). The scenario knobs below are read by scenario() with a
# default, so a developer's exported value would silently change every row that does not name the knob itself.
unset CURL_W_PROFILES_FILE CURL_W_SENTINEL
unset SNAP_EXTRA SNAP_SCOPE CA_MODE CA_FILE CA_RAW SERVER_CERT SKIP_SNAPSHOT PRE LINK_SUBDIR PATH_OVERRIDE NO_COMMIT COMMIT_CHMOD
unset CURL_ALWAYS_OK CURL_FAIL_FIRST CURL_CODE CURL_PROFILES CURL_PROFILES_IGNORED KEEP_SENTRY SG_ATTEMPTS SCEN_IFS SCEN_AGAIN
WORK="$(mktemp -d -t inngest-link-resolver.XXXXXX)" || die "mktemp -d failed"
assert_fixture_dir "$WORK"
# H6_PID (the local TLS listener of the H6 rows) is owned by this trap too: a suite killed mid-H6 must not leave the process behind
H6_PID=""
trap '[ -z "${H6_PID:-}" ] || kill "$H6_PID" 2>/dev/null; rm -rf "$WORK"' EXIT
FX="$WORK/fx"; BIN="$WORK/bin"; RUNS="$WORK/runs"
mkdir -p "$FX" "$BIN" "$RUNS" || die "mkdir failed"

# The shared curl profile table and `-w` printer (#10934): both curl doubles of the two suites and the H6/H7 rows use ONE file. The stub
# bakes the absolute fixture and sentinel paths in at creation (a quoted heredoc cannot expand them) and exits 98 when the source fails,
# so an unset variable or a missing file cannot read as one more failed curl attempt. CURL_W_PROFILES_FILE overrides the fixture path
# at run time (H9 runs the comparison against a copy with one value flipped). Every row asserts the sentinel absent afterwards.
CURLW_FIXTURE="$SCRIPT_DIR/test-fixtures/curl-w-profiles.sh"
CURLW_SENTINEL="$WORK/curlw.sentinel"
[ -r "$CURLW_FIXTURE" ] || die "the shared curl profile fixture is missing: $CURLW_FIXTURE"
# shellcheck source=/dev/null
source "$CURLW_FIXTURE" || die "could not source $CURLW_FIXTURE"

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
# loopalt: a DIFFERENT self-signed certificate that DOES carry the loopback IP SAN (H6 pinned-certificate mismatch: with a non-matching SAN real
# curl 8.23 reports the name mismatch, ssl_verify_result 1, before the untrusted chain, 18; measured, see the H6 comment)
gen_cert loopalt "IP:127.0.0.1"          "CA:FALSE" "serverAuth" "/CN=loopback-other"

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
{
  printf '#!/bin/bash\nCURLW_FIXTURE=%q\nCURL_W_SENTINEL=%q\n' "$CURLW_FIXTURE" "$CURLW_SENTINEL"
  cat <<'STUB'
# Records argv; behaves like curl --cacert against a server that presents $FX_SERVER_CERT. EVERY self-gate outcome (a call with -w) is
# printed by the shared printer (test-fixtures/curl-w-profiles.sh) as a named profile: what real curl prints for the phase, never an
# empty stdout with a bare exit code. A call without -w (the Sentry POST) passes through silently.
#   -k / --insecure                  -> ok200 (this is exactly what the resolver must never pass)
#   --cacert F, F fingerprint match  -> ok200 (status502 when FX_CURL_CODE=502)
#   no --cacert / mismatch / no PEM  -> verify18 (rc 60: certificate verification failed)
#   FX_CURL_FAIL_FIRST=N             -> the first N calls print verify18 (rc 60)
#   FX_CURL_ALWAYS_OK=1              -> ok200 (status502 for FX_CURL_CODE=502) whatever the server presents
#   FX_CURL_PROFILES=p1,p2,...       -> the Nth -w call prints profile pN (the last repeats); <name>@<rc> overrides the exit code;
#                                       FX_CURL_PROFILES_IGNORED=1 disables the list (harness row H8: the stub then answers like a healthy server)
printf '%s\n' "$*" >> "${RUN_DIR:?}/curl.argv"
n=$(( $(cat "$RUN_DIR/curl.count" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$RUN_DIR/curl.count"
cacert=""; insecure=0; prev=""; fmt=""; have_w=0
for a in "$@"; do
  case "$a" in -k|--insecure|-sk|-ks) insecure=1 ;; esac
  if [ "$prev" = "--cacert" ]; then cacert="$a"; fi
  if [ "$prev" = "-w" ]; then fmt="$a"; have_w=1; fi
  prev="$a"
done
if [ "$have_w" != 1 ]; then exit 0; fi
# shellcheck disable=SC1090
source "${CURL_W_PROFILES_FILE:-$CURLW_FIXTURE}" || exit 98
wn=$(( $(cat "$RUN_DIR/curl.wcount" 2>/dev/null || echo 0) + 1 )); printf '%s' "$wn" > "$RUN_DIR/curl.wcount"
okspec=ok200
case "${FX_CURL_CODE:-200}" in 200) okspec=ok200 ;; 502) okspec=status502 ;; *) okspec="unmodelled-code-${FX_CURL_CODE}" ;; esac
spec=""
if [ -n "${FX_CURL_FAIL_FIRST:-}" ] && [ "$n" -le "$FX_CURL_FAIL_FIRST" ]; then spec=verify18
elif [ "${FX_CURL_ALWAYS_OK:-}" = 1 ]; then spec="$okspec"
elif [ -n "${FX_CURL_PROFILES:-}" ] && [ "${FX_CURL_PROFILES_IGNORED:-}" != 1 ]; then
  IFS=, read -r -a plist <<< "$FX_CURL_PROFILES"
  idx=$(( wn - 1 )); if [ "$idx" -ge "${#plist[@]}" ]; then idx=$(( ${#plist[@]} - 1 )); fi
  spec="${plist[$idx]}"
elif [ "$insecure" = 1 ]; then spec=ok200
elif [ -z "$cacert" ]; then spec=verify18
else
  want="$(openssl x509 -in "$FX_SERVER_CERT" -noout -fingerprint -sha256 2>/dev/null)"
  got="$(openssl x509 -in "$cacert" -noout -fingerprint -sha256 2>/dev/null)"
  if [ -n "$got" ] && [ "$got" = "$want" ]; then spec="$okspec"; else spec=verify18; fi
fi
curlw_print "$spec" "$fmt"
exit $?
STUB
} > "$BIN/curl"
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
      duphttp) printf 'INNGEST_BASE_URL=http://10.0.1.40:8288\nINNGEST_BASE_URL=http://10.0.1.40:8288\nNODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem\n' ;;
      dupca) printf 'INNGEST_BASE_URL=https://10.0.1.40:8443\nNODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem\nNODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem\n' ;;
      badca) printf 'INNGEST_BASE_URL=https://10.0.1.40:8443\nNODE_EXTRA_CA_CERTS=/tmp/other.pem\n' ;;
      empty) : ;;
      lookalike) printf 'PATH=/usr/bin\nXINNGEST_BASE_URL=http://other\nINNGEST_BASE_URL=https://10.0.1.40:8443\nPRE_INNGEST_BASE_URL=x\nNODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem\nXNODE_EXTRA_CA_CERTS=/y\nNODE_EXTRA_CA_CERTS_FILE=/z\n' ;;
      urlsuffix) printf 'INNGEST_BASE_URL=https://10.0.1.40:8443/evil\nNODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem\n' ;;
      casuffix) printf 'INNGEST_BASE_URL=https://10.0.1.40:8443\nNODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem.evil\n' ;;
      httpbadca) printf 'INNGEST_BASE_URL=http://10.0.1.40:8288\nNODE_EXTRA_CA_CERTS=/tmp/other.pem\n' ;;
      httpnoca) printf 'INNGEST_BASE_URL=http://10.0.1.40:8288\n' ;;
      twicenoca) printf 'INNGEST_BASE_URL=https://10.0.1.40:8443\nINNGEST_BASE_URL=http://10.0.1.40:8288\n' ;;
      manyca) printf 'INNGEST_BASE_URL=https://10.0.1.40:8443\n'; for _i in $(seq 1 150); do printf 'NODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem\n'; done ;;
      manyhttps) for _i in $(seq 1 150); do printf 'INNGEST_BASE_URL=https://10.0.1.40:8443\n'; done; printf 'NODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem\n' ;;
      tenca) printf 'INNGEST_BASE_URL=https://10.0.1.40:8443\n'; for _i in $(seq 1 12); do printf 'NODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem\n'; done ;;
      many) for _i in $(seq 1 150); do printf 'INNGEST_BASE_URL=http://10.0.1.40:8288\n'; done; printf 'NODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem\n' ;;
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
    export RUN_DIR="$RUN" FX_SERVER_CERT="${SERVER_CERT:-$FX/good.crt}" FX_CURL_ALWAYS_OK="${CURL_ALWAYS_OK:-}" FX_CURL_FAIL_FIRST="${CURL_FAIL_FIRST:-}" FX_CURL_CODE="${CURL_CODE:-}" FX_CURL_PROFILES="${CURL_PROFILES:-}" FX_CURL_PROFILES_IGNORED="${CURL_PROFILES_IGNORED:-}"
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
    if [ -n "${SCEN_IFS+x}" ]; then IFS="$SCEN_IFS"; fi   # S12: the resolver must not depend on the caller's IFS
    resolve_inngest_link "$snap" || rc=$?
    IFS=$' \t\n'
    # S13: SCEN_AGAIN runs a SECOND resolve in the SAME shell (the globals the first one left behind are the point): `pass` re-resolves the same
    # snapshot (the curl profile list moves on), `flagoff` re-resolves a snapshot without the flag. rc1 and phase1 are what the FIRST resolve left.
    rc1=""; phase1=""
    if [ -n "${SCEN_AGAIN:-}" ]; then
      rc1="$rc"; phase1="${INNGEST_LINK_SELFGATE_PHASE-<unset>}"
      if [ "$SCEN_AGAIN" = flagoff ]; then
        { printf '%b' "${SNAP_SCOPE-DOPPLER_PROJECT=soleur\nDOPPLER_CONFIG=prd\nDOPPLER_ENVIRONMENT=prd\n}"; printf 'KEY=value\nGITHUB_APP_ID=4242\n'; } > "$snap"
      fi
      rc=0
      resolve_inngest_link "$snap" || rc=$?
    fi
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
      printf 'phase=%s\n' "${INNGEST_LINK_SELFGATE_PHASE-<unset>}"
      printf 'rc1=%s\n' "$rc1"
      printf 'phase1=%s\n' "$phase1"
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
canary_fails() { # [expected reason]: the shared predicate: rc 1, the canary reason set, an error event
  local want="${1:-canary_inngest_link_failed}"
  need "rc=$(val rc), want 1" "$([ "$(val rc)" = 1 ] && echo 0 || echo 1)" || return 1
  need "reason=$(val reason), want $want" "$([ "$(val reason)" = "$want" ] && echo 0 || echo 1)" || return 1
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
row_E8_canary_counts_only_the_exact_names() {
  # lookalike names (a prefix or suffix on either name) are other variables: they are neither counted nor allowed to fail the check
  FX_INSPECT=lookalike canary "$1" "$ROW_ID"
  need "rc=$(val rc), want 0 (reason $(val reason)): $(grep canary_failed "$RUN/logger.log")" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
}
row_E3_canary_inspect_must_show_https() {
  local t m c
  # <stub inspect mode>:<the cause the event must name>; every inspect failure carries the inspect-specific deploy-state reason
  for t in http:url_value noca:ca_count twice:url_count duphttp:url_count dupca:ca_count badca:ca_value none:inspect_failed empty:inspect_failed many:url_count urlsuffix:url_value casuffix:ca_value httpbadca:url_value httpnoca:url_value twicenoca:url_count manyca:ca_count manyhttps:url_count tenca:ca_count; do
    m="${t%%:*}"; c="${t#*:}"
    FX_INSPECT="$m" canary "$1" "$ROW_ID"
    canary_fails canary_inngest_link_inspect_failed || { WHY="inspect=$m: ${WHY:-}"; return 1; }
    need "inspect=$m: an exec ran after a failed inspect" "$(grep -q '^exec ' "$RUN/docker.argv" && echo 1 || echo 0)" || return 1
    need "inspect=$m: the event does not name cause=$c: $(grep canary_failed "$RUN/logger.log")" "$(log_has "class=canary_failed level=error check=inspect cause=$c " && echo 0 || echo 1)" || return 1
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
  # one exact event line per inspect mode: the first failing condition, then the four fixed counts (never a value, a key or a path)
  for t in 'http|cause=url_value url_lines=1 url_https=0 ca_lines=1 ca_ok=1' \
           'noca|cause=ca_count url_lines=1 url_https=1 ca_lines=0 ca_ok=0' \
           'twice|cause=url_count url_lines=2 url_https=1 ca_lines=1 ca_ok=1' \
           'duphttp|cause=url_count url_lines=2 url_https=0 ca_lines=1 ca_ok=1' \
           'dupca|cause=ca_count url_lines=1 url_https=1 ca_lines=2 ca_ok=2' \
           'badca|cause=ca_value url_lines=1 url_https=1 ca_lines=1 ca_ok=0' \
           'none|cause=inspect_failed url_lines=0 url_https=0 ca_lines=0 ca_ok=0' \
           'empty|cause=inspect_failed url_lines=0 url_https=0 ca_lines=0 ca_ok=0' \
           'many|cause=url_count url_lines=99 url_https=0 ca_lines=1 ca_ok=1' \
           'urlsuffix|cause=url_value url_lines=1 url_https=0 ca_lines=1 ca_ok=1' \
           'casuffix|cause=ca_value url_lines=1 url_https=1 ca_lines=1 ca_ok=0' \
           'httpbadca|cause=url_value url_lines=1 url_https=0 ca_lines=1 ca_ok=0' \
           'httpnoca|cause=url_value url_lines=1 url_https=0 ca_lines=0 ca_ok=0' \
           'twicenoca|cause=url_count url_lines=2 url_https=1 ca_lines=0 ca_ok=0' \
           'manyca|cause=ca_count url_lines=1 url_https=1 ca_lines=99 ca_ok=99' \
           'manyhttps|cause=url_count url_lines=99 url_https=99 ca_lines=1 ca_ok=1' \
           'tenca|cause=ca_count url_lines=1 url_https=1 ca_lines=12 ca_ok=12'; do
    FX_INSPECT="${t%%|*}" canary "$1" "$ROW_ID"
    want="${t#*|}"
    need "inspect=${t%%|*}: the event does not read 'check=inspect $want': $(grep canary_failed "$RUN/logger.log")" "$(grep -qF -- "check=inspect $want" "$RUN/logger.log" && grep -q -- "check=inspect $want\$" < <(grep canary_failed "$RUN/logger.log") && echo 0 || echo 1)" || return 1
    # the line is integers and fixed tokens only: never 'cause=none', an IP, a path or a scheme
    need "inspect=${t%%|*}: the event is not the anchored grammar: $(grep canary_failed "$RUN/logger.log")" "$(grep -qE 'check=inspect cause=(inspect_failed|url_count|url_value|ca_count|ca_value) url_lines=[0-9]{1,2} url_https=[0-9]{1,2} ca_lines=[0-9]{1,2} ca_ok=[0-9]{1,2}$' < <(grep canary_failed "$RUN/logger.log") && echo 0 || echo 1)" || return 1
    need "inspect=${t%%|*}: the event leaks a value or says cause=none: $(grep canary_failed "$RUN/logger.log")" "$(grep -qE 'cause=none|10\.0\.1\.|https?://|/etc/' < <(grep canary_failed "$RUN/logger.log") && echo 1 || echo 0)" || return 1
  done
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

# ---------------------------------------------------------------------------------------
# THE ENV-FILE SCRUB (#10136): inngest_link_scrub_env_file removes every line naming INNGEST_BASE_URL or NODE_EXTRA_CA_CERTS from the
# env-file the canary and prod `docker run`s receive, so the `-e` flags are the ONLY source of those two names and the canary's
# `docker inspect` (which keeps an env-file entry AND a -e entry for one key) sees exactly one of each.
# ---------------------------------------------------------------------------------------
mkdir -p "$WORK/scrubin" "$WORK/scrubstubs" || die "mkdir scrub dirs"
REAL_GREP="$(command -v grep)"
# stubs that fail ONE step: a mktemp that cannot create the scrub temp, an mv that cannot rename it, a grep that ignores -v (the
# kept-lines write then emits the removed lines), a grep that drops the last kept line
mkdir -p "$WORK/scrubstubs/nomktemp" "$WORK/scrubstubs/nomv" "$WORK/scrubstubs/novv" "$WORK/scrubstubs/dropline"
printf '#!/bin/bash\nexit 1\n' > "$WORK/scrubstubs/nomktemp/mktemp"
printf '#!/bin/bash\nexit 1\n' > "$WORK/scrubstubs/nomv/mv"
cat > "$WORK/scrubstubs/novv/grep" <<STUB
#!/bin/bash
args=(); for a in "\$@"; do [ "\$a" = -v ] || args+=("\$a"); done
exec "$REAL_GREP" "\${args[@]}"
STUB
cat > "$WORK/scrubstubs/dropline/grep" <<STUB
#!/bin/bash
for a in "\$@"; do if [ "\$a" = -v ]; then "$REAL_GREP" "\$@" | sed '\$d'; exit "\${PIPESTATUS[0]}"; fi; done
exec "$REAL_GREP" "\$@"
STUB
chmod +x "$WORK"/scrubstubs/*/*
scrub() { # <block> <run id> <input file> [stub dir name]: one scrub call in a subshell; $RUN/out gets rc=, reason=, tmp=
  local block="$1" id="$2" f="$3" stubs="${4:-}"
  RUN="$RUNS/$id"; assert_fixture_dir "$RUN"
  rm -rf "$RUN"; mkdir -p "$RUN"; : > "$RUN/logger.log"
  (
    export RUN_DIR="$RUN" PATH="${stubs:+$WORK/scrubstubs/$stubs:}$BIN:$PATH"
    LOG_TAG=ci-deploy
    unset SENTRY_INGEST_DOMAIN SENTRY_PROJECT_ID SENTRY_PUBLIC_KEY
    # shellcheck disable=SC1090
    source "$block" || exit 99
    INNGEST_LINK_DIR="$RUN"; rc=0
    inngest_link_scrub_env_file "$f" || rc=$?
    printf 'rc=%s\nreason=%s\ntmp=%s\n' "$rc" "${INNGEST_LINK_REASON-<unset>}" "${_gak_tmp-<unset>}" > "$RUN/out"
  ) > "$RUN/stdout" 2>&1
  [ -s "$RUN/out" ] || printf 'rc=harness\n' > "$RUN/out"
}
scrub_leftover() { compgen -G "$WORK/scrubin/$1.scrub.*" || true; }
scrub_failed() { # <input> <orig copy> <stage>: rc 1, the fixed reason, the stage event, the input byte-identical, no temp left
  need "rc=$(val rc), want 1" "$([ "$(val rc)" = 1 ] && echo 0 || echo 1)" || return 1
  need "reason=$(val reason)" "$([ "$(val reason)" = inngest_env_scrub_failed ] && echo 0 || echo 1)" || return 1
  need "no 'class=env_scrub_failed level=error stage=$3' event: $(cat "$RUN/logger.log")" "$(grep -qE "class=env_scrub_failed level=error stage=$3\$" "$RUN/logger.log" && echo 0 || echo 1)" || return 1
  need "the input file was changed by a failed scrub" "$(cmp -s "$1" "$2" && echo 0 || echo 1)" || return 1
  need "a temp file was left behind: $(scrub_leftover "$(basename "$1")")" "$([ -z "$(scrub_leftover "$(basename "$1")")" ] && echo 0 || echo 1)" || return 1
  need "_gak_tmp is still set: $(val tmp)" "$([ -z "$(val tmp)" ] && echo 0 || echo 1)" || return 1
}
row_L1_scrub_removes_pinned_names_and_keeps_the_rest() {
  local in="$WORK/scrubin/L1" want="$WORK/scrubin/L1.want"
  # nine lines name a pinned variable (plain, leading space, space before '=', bare name, both names, behind a no-break space, behind a BOM with a CR);
  # fourteen others must survive byte for byte: lookalikes (an underscore, letter, dot or dash neighbour: all valid Docker name bytes), other INNGEST_ keys, a CRLF line, a non-UTF-8 byte, a NUL byte, a NUL before a pinned name
  printf '%b' '\xef\xbb\xbfINNGEST_BASE_URL=http://bom\r\nKEY=value\nINNGEST_BASE_URL=http://plain\n INNGEST_BASE_URL=http://lead\nINNGEST_BASE_URL =sp\nINNGEST_BASE_URL\nNODE_EXTRA_CA_CERTS=/tmp/a\n  NODE_EXTRA_CA_CERTS=/tmp/b\nNODE_EXTRA_CA_CERTS\n\xc2\xa0INNGEST_BASE_URL=http://nbsp\nINNGEST_LINK_TLS=1\nINNGEST_TLS_CA=QUJD\nINNGEST_SIGNING_KEY=signkey-prod-aabb\nINNGEST_EVENT_KEY=ek\nINNGEST_BASE_URL_EXTRA=keep\nNODE_EXTRA_CA_CERTS_X=keep\nXINNGEST_BASE_URL=keep\nINNGEST_BASE_URL.bak=keep\nINNGEST_BASE_URL-X=keep\ncrlf=keep\r\nbad=\xff\xfekeep\nnul=a\0bkeep\nnul2=a\0INNGEST_BASE_URL=keep\n' > "$in"
  printf '%b' 'KEY=value\nINNGEST_LINK_TLS=1\nINNGEST_TLS_CA=QUJD\nINNGEST_SIGNING_KEY=signkey-prod-aabb\nINNGEST_EVENT_KEY=ek\nINNGEST_BASE_URL_EXTRA=keep\nNODE_EXTRA_CA_CERTS_X=keep\nXINNGEST_BASE_URL=keep\nINNGEST_BASE_URL.bak=keep\nINNGEST_BASE_URL-X=keep\ncrlf=keep\r\nbad=\xff\xfekeep\nnul=a\0bkeep\nnul2=a\0INNGEST_BASE_URL=keep\n' > "$want"
  chmod 0600 "$in"
  scrub "$1" "$ROW_ID" "$in"
  need "rc=$(val rc), want 0 (reason $(val reason))" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "the kept lines are not byte-identical to the expected set" "$(cmp -s "$in" "$want" && echo 0 || echo 1)" || return 1
  need "mode is $(stat -c %a "$in"), want 600" "$([ "$(stat -c %a "$in")" = 600 ] && echo 0 || echo 1)" || return 1
  need "the event does not read 'class=env_scrubbed level=info removed=9': $(cat "$RUN/logger.log")" "$(grep -qE 'class=env_scrubbed level=info removed=9$' "$RUN/logger.log" && echo 0 || echo 1)" || return 1
  need "a temp file was left behind: $(scrub_leftover L1)" "$([ -z "$(scrub_leftover L1)" ] && echo 0 || echo 1)" || return 1
  need "_gak_tmp is still set: $(val tmp)" "$([ -z "$(val tmp)" ] && echo 0 || echo 1)" || return 1
  # a removed-count above the clamp reads 99
  local i; for i in $(seq 1 120); do printf 'INNGEST_BASE_URL=http://dup%s\n' "$i"; done > "$in"
  scrub "$1" "$ROW_ID" "$in"
  need "120 removed lines: the event does not read removed=99: $(cat "$RUN/logger.log")" "$(grep -qE 'class=env_scrubbed level=info removed=99$' "$RUN/logger.log" && echo 0 || echo 1)" || return 1
}
row_L2_scrub_no_match_is_a_noop_and_idempotent() {
  local in="$WORK/scrubin/L2" want="$WORK/scrubin/L2.want"
  printf 'KEY=value\nINNGEST_LINK_TLS=1\nINNGEST_BASE_URL_EXTRA=keep\n' > "$in"; cp "$in" "$want"
  scrub "$1" "$ROW_ID" "$in"
  need "rc=$(val rc), want 0" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "a no-match file was changed" "$(cmp -s "$in" "$want" && echo 0 || echo 1)" || return 1
  need "a no-match scrub spoke: $(cat "$RUN/logger.log")" "$([ ! -s "$RUN/logger.log" ] && echo 0 || echo 1)" || return 1
  : > "$in"; scrub "$1" "$ROW_ID" "$in"
  need "an empty file: rc=$(val rc), want 0" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "an empty file gained bytes" "$([ ! -s "$in" ] && echo 0 || echo 1)" || return 1
  # a matching line followed by a last line with NO trailing newline: the rewrite ends the file with exactly one newline
  printf 'INNGEST_BASE_URL=x\nKEY=value' > "$in"; printf 'KEY=value\n' > "$want"
  scrub "$1" "$ROW_ID" "$in"
  need "a file without a trailing newline: kept lines are not 'KEY=value' plus exactly one newline" "$(cmp -s "$in" "$want" && echo 0 || echo 1)" || return 1
  # idempotent: a second run changes nothing and logs nothing
  scrub "$1" "$ROW_ID" "$in"
  need "a second scrub changed the file" "$(cmp -s "$in" "$want" && echo 0 || echo 1)" || return 1
  need "a second scrub reported a removal: $(cat "$RUN/logger.log")" "$([ ! -s "$RUN/logger.log" ] && echo 0 || echo 1)" || return 1
}
row_L3_scrub_read_and_write_failures_leave_the_file_untouched() {
  local in="$WORK/scrubin/L3" orig="$WORK/scrubin/L3.orig"
  printf 'KEY=value\nINNGEST_BASE_URL=http://x\nINNGEST_TLS_CA=QUJD\n' > "$in"; cp "$in" "$orig"
  scrub "$1" "$ROW_ID" "$WORK/scrubin/L3.absent"
  need "a missing file: rc=$(val rc) reason=$(val reason), want 1 inngest_env_scrub_failed" "$([ "$(val rc)" = 1 ] && [ "$(val reason)" = inngest_env_scrub_failed ] && echo 0 || echo 1)" || return 1
  need "a missing file: no 'stage=read' event: $(cat "$RUN/logger.log")" "$(grep -qE 'class=env_scrub_failed level=error stage=read$' "$RUN/logger.log" && echo 0 || echo 1)" || return 1
  scrub "$1" "$ROW_ID" "$in" nomktemp
  scrub_failed "$in" "$orig" write || { WHY="mktemp failing: ${WHY:-}"; return 1; }
  scrub "$1" "$ROW_ID" "$in" nomv
  scrub_failed "$in" "$orig" write || { WHY="mv failing: ${WHY:-}"; return 1; }
}
row_L4_scrub_recount_failure_leaves_the_file_untouched() {
  local in="$WORK/scrubin/L4" orig="$WORK/scrubin/L4.orig"
  # two removed and two kept lines: a grep that ignores -v writes the REMOVED lines, so kept + removed still equals the total
  # (conservation holds) and only the recount of the written file can see the pinned names left in it
  printf 'KEY=value\nINNGEST_BASE_URL=http://x\nINNGEST_LINK_TLS=1\nNODE_EXTRA_CA_CERTS=/tmp/x\n' > "$in"; cp "$in" "$orig"
  scrub "$1" "$ROW_ID" "$in" novv
  scrub_failed "$in" "$orig" recount || return 1
}
row_L5_scrub_conservation_failure_leaves_the_file_untouched() {
  local in="$WORK/scrubin/L5" orig="$WORK/scrubin/L5.orig"
  printf 'KEY=value\nINNGEST_BASE_URL=http://x\nINNGEST_LINK_TLS=1\nINNGEST_TLS_CA=QUJD\n' > "$in"; cp "$in" "$orig"
  scrub "$1" "$ROW_ID" "$in" dropline
  scrub_failed "$in" "$orig" write || return 1
}
row_L6_scrub_all_lines_matching_yields_an_empty_file() {
  local in="$WORK/scrubin/L6"
  printf 'INNGEST_BASE_URL=http://x\nNODE_EXTRA_CA_CERTS=/tmp/x\n' > "$in"
  scrub "$1" "$ROW_ID" "$in"
  need "rc=$(val rc), want 0 (reason $(val reason))" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "the file is not empty after every line matched" "$([ ! -s "$in" ] && echo 0 || echo 1)" || return 1
  need "the event does not read removed=2: $(cat "$RUN/logger.log")" "$(grep -qE 'class=env_scrubbed level=info removed=2$' "$RUN/logger.log" && echo 0 || echo 1)" || return 1
}

row_L7_scrub_holds_under_a_utf8_locale() {
  local in="$WORK/scrubin/L7" want="$WORK/scrubin/L7.want"
  # a UTF-8 locale must not change the result: an invalid byte BEFORE the name still matches (the prefix class is any non-name byte), and an
  # invalid-UTF-8 line and a NUL line survive byte for byte (a locale-aware `grep -v` would drop both silently with rc 0)
  printf '%b' 'KEY=a\nbad=\xff\xfekeep\n\xffINNGEST_BASE_URL=http://bytepref\nnul=a\0bkeep\nINNGEST_BASE_URL=http://plain\n' > "$in"
  printf '%b' 'KEY=a\nbad=\xff\xfekeep\nnul=a\0bkeep\n' > "$want"
  chmod 0600 "$in"
  LC_ALL=C.UTF-8 scrub "$1" "$ROW_ID" "$in"
  need "rc=$(val rc), want 0 (reason $(val reason))" "$([ "$(val rc)" = 0 ] && echo 0 || echo 1)" || return 1
  need "under LC_ALL=C.UTF-8 the kept lines are not byte-identical to the expected set" "$(cmp -s "$in" "$want" && echo 0 || echo 1)" || return 1
  need "the event does not read removed=2: $(cat "$RUN/logger.log")" "$(grep -qE 'class=env_scrubbed level=info removed=2$' "$RUN/logger.log" && echo 0 || echo 1)" || return 1
}
row_L8_scrub_names_match_the_tuple_census_and_the_canary_counts() {
  local re req cnt
  re="$(grep -m1 '^INNGEST_LINK_SCRUB_RE=' "$1" | grep -oE '\(INNGEST[A-Z_|]*\)|\([A-Z_]+\|[A-Z_|]+\)' | head -1 | tr -d '()' | tr '|' '\n' | sort | paste -sd,)"
  req="$(grep -m1 '^REQUIRED_ENV' "$SCRIPT_DIR/lib/docker-run-tuple.py" | grep -oE '"[A-Z_]+"' | tr -d '"' | sort | paste -sd,)"
  cnt="$(sed -n '/^inngest_link_canary_check()/,/^}/p' "$1" | grep -oE "grep -c '\^[A-Z_]+=" | sed -E "s/grep -c '\^//; s/=\$//" | sort | paste -sd,)"
  need "the scrub regex names [$re] but REQUIRED_ENV in docker-run-tuple.py names [$req]" "$([ -n "$re" ] && [ "$re" = "$req" ] && echo 0 || echo 1)" || return 1
  need "the scrub regex names [$re] but the canary's inspect counts name [$cnt]" "$([ "$re" = "$cnt" ] && echo 0 || echo 1)" || return 1
}

# --- #10934: the self-gate failure event names the stage the LAST attempt reached --------------------------------------------------
# Event grammar (ruled by the CTO, decision-challenges.md F1/F2/R3a-R3e):
#   INNGEST_LINK: class=selfgate_failed level=error rc=<n> http=<ddd|none> attempts=<n> phase=<token> tcp=<0-99> tls=<0-99> verify=<0-99>
# Every row below compares the WHOLE logged line to an expected string (never a substring), pins SG_ATTEMPTS (scenario() defaults it
# to 2) and answers the self-gate from named profiles of the shared measured table (CURL_PROFILES=p1,p2,..: the Nth curl call prints pN,
# the last repeats; <name>@<rc> overrides the exit code). tcp/tls count the attempts (of all) whose time_connect / time_appconnect was
# a well-formed NON-zero number, each field judged on its own; phase describes the LAST attempt only. Every row is also checked by
# run_rows for the printer sentinel (an unknown variable or profile).
sg_line() { grep -F 'class=selfgate_failed' "$RUN/logger.log" | head -n1 | sed -E 's/^-t [^ ]+ //'; }
sg_count() { grep -cF 'class=selfgate_failed' "$RUN/logger.log" || true; }
sg_want() { # rc http attempts phase tcp tls verify
  printf 'INNGEST_LINK: class=selfgate_failed level=error rc=%s http=%s attempts=%s phase=%s tcp=%s tls=%s verify=%s' "$@"
}
sg_expect() { # <block> <tag> <profiles> <rc> <http> <attempts> <phase> <tcp> <tls> <verify>: a failing gate, the whole event line pinned
  local got want
  want="$(sg_want "$4" "$5" "$6" "$7" "$8" "$9" "${10}")"
  CURL_PROFILES="$3" SG_ATTEMPTS="$6" SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$1" "$ROW_ID-$2"
  got="$(sg_line)"
  fails_closed || { WHY="[$2] ${WHY:-}"; return 1; }
  need "[$2] the failure reason is [$(val reason)], want inngest_link_selfgate_failed" "$([ "$(val reason)" = inngest_link_selfgate_failed ] && echo 0 || echo 1)" || return 1
  need "[$2] no CA may be installed after a failed gate" "$([ ! -s "$(caf)" ] && echo 0 || echo 1)" || return 1
  need "[$2] exactly one selfgate_failed event expected, found $(sg_count)" "$([ "$(sg_count)" = 1 ] && echo 0 || echo 1)" || return 1
  need "[$2] the event line is [$got], want [$want]" "$([ "$got" = "$want" ] && echo 0 || echo 1)" || return 1
  need "[$2] curl calls=$(curl_calls), want $6 attempts" "$([ "$(curl_calls)" = "$6" ] && echo 0 || echo 1)" || return 1
}
sg_table() { # <block> <label> <table>: one sg_expect per line `profile|rc|http|phase|tcp|tls|verify` (a single attempt each)
  local prof rc http phase tcp tls ver
  while IFS='|' read -r prof rc http phase tcp tls ver; do
    [ -n "$prof" ] || continue
    sg_expect "$1" "$2-$prof" "$prof" "$rc" "$http" 1 "$phase" "$tcp" "$tls" "$ver" || { WHY="$prof: ${WHY:-}"; return 1; }
  done <<< "$3"
}
# the named profile sets (one table per scenario family; H7a asserts that these four sets plus ok200 are EXACTLY the measured table)
SG_S1='refused|7|000|connect|0|0|0
fw_drop|28|000|connect|0|0|0
ca_file|77|000|ca_file|1|0|0'
SG_S2='hs_close|35|000|handshake|1|0|0
hs_rst|35|000|handshake|1|0|0
hs_plain|35|000|handshake|1|0|0
hs_hang|28|000|handshake|1|0|0
verify18|60|000|verify|1|0|18
verify10|60|000|verify|1|0|10
verify1_san|60|000|verify|1|0|1'
SG_S3='req_reset|56|000|request|1|1|0
req_empty|52|000|request|1|1|0
req_hang|28|000|request|1|1|0
req_http09|1|000|request|1|1|0
req_partial|18|200|request|1|1|0
status_partial|18|502|status|1|1|0
status502|0|502|status|1|1|0'
SG_NAMED_SETS='refused fw_drop ca_file hs_close hs_rst hs_plain hs_hang verify18 verify10 verify1_san req_reset req_empty req_hang req_http09 req_partial status_partial status502 ok200'

row_S1_connect_and_ca_file() { sg_table "$1" s1 "$SG_S1"; }
row_S2_handshake_and_verify() { sg_table "$1" s2 "$SG_S2"; }
row_S3_request_and_status() {
  # req_partial (rc 18, a 200 header then a short body) is NOT status: it reads request with http=200, which the runbook decodes as
  # "a 200 header, body cut short", never healthy; status_partial (rc 18 with a 502 header) stays status
  sg_table "$1" s3 "$SG_S3"
}
row_S3b_same_times_any_rc_reads_request() {
  # the SAME times (the incident's 0.000138 / 0.004360, verify 0, code 000) with rc 52, 56 and 1: one wire event prints 52 on curl 8.5.0
  # and 56 on 7.81 and 8.23, so the phase comes from the times, never from an rc list
  local rc
  for rc in 52 56 1; do
    sg_expect "$1" "rc$rc" "req_reset@$rc" "$rc" 000 1 request 1 1 0 || { WHY="rc $rc: ${WHY:-}"; return 1; }
  done
}
row_S3c_tls_complete_but_not_200_fails_with_phase_status() {
  # the default stub path (no profile list): a verified TLS session answering 502 is not a pass, rc 0 or not
  CURL_CODE=502 SG_ATTEMPTS=1 SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$1" "$ROW_ID"
  fails_closed || return 1
  need "reason=$(val reason), want inngest_link_selfgate_failed" "$([ "$(val reason)" = inngest_link_selfgate_failed ] && echo 0 || echo 1)" || return 1
  need "the event is [$(sg_line)], want [$(sg_want 0 502 1 status 1 1 0)]" "$([ "$(sg_line)" = "$(sg_want 0 502 1 status 1 1 0)" ] && echo 0 || echo 1)" || return 1
  need "a 502 answer installed a CA" "$([ ! -s "$(caf)" ] && echo 0 || echo 1)" || return 1
}
row_S4_sequence_counts_and_last_phase() {
  # connect, handshake, request across three attempts: the phase is the LAST attempt's, the counters cover all three
  sg_expect "$1" seq 'refused,hs_close,req_reset' 56 000 3 request 2 1 0 || return 1
  # flapping fixtures (the worked lines the runbook quotes): a restart between tries shows up as a phase the counters contradict
  sg_expect "$1" flap1 'req_reset,refused,req_reset' 56 000 3 request 2 2 0 || return 1
  sg_expect "$1" flap2 'req_reset,refused,refused' 7 000 3 connect 1 1 0 || return 1
  sg_expect "$1" flap3 'refused,req_reset,hs_close' 35 000 3 handshake 2 1 0 || return 1
}
row_S4c_verify_does_not_outlive_its_attempt() {
  # an attempt that reads verify=18 followed by one that reads request: the event describes the LAST attempt, so verify is 0 again (the
  # per-attempt reset of the verification result; "0 unless phase=verify" is what the runbook tells the operator to rely on)
  sg_expect "$1" verify-then-request 'verify18,req_reset' 56 000 2 request 2 1 0
}
row_S4d_http_does_not_outlive_its_attempt() {
  # a 502 answer followed by an attempt that printed nothing (rc 124): http is the LAST attempt's, so none, not the earlier 502
  sg_expect "$1" status-then-empty 'status502,raw_empty@124' 124 none 2 unknown 1 1 0
}
row_S4b_counters_clamp() {
  # 120 attempts: the counters are clamped to 99 like the canary's integers (attempts= is the denominator and prints as is)
  sg_expect "$1" clamp req_reset 56 000 120 request 99 99 0
}
row_S5_event_grammar_on_both_sinks() {
  local p line re detail jd n sentry_body
  re='^INNGEST_LINK: class=selfgate_failed level=error rc=[0-9]{1,3} http=([0-9]{3}|none) attempts=[0-9]{1,3} phase=(connect|handshake|verify|ca_file|request|status|unknown) tcp=[0-9]{1,2} tls=[0-9]{1,2} verify=[0-9]{1,2}$'
  # every failing profile, the raw ones included: the whole event is a fixed grammar and never a URL, an address or curl text
  for p in refused fw_drop ca_file hs_close hs_rst hs_plain hs_hang verify18 verify10 verify1_san req_reset req_empty req_hang req_http09 req_partial \
           status_partial status502 raw_empty raw_garbage raw_short3 raw_nonnum raw_nonnum502 req_reset_comma req_reset@124 raw_empty@2 \
           raw_refused_comma raw_hs_comma raw_verify_nonnum raw_status204 raw_code2000 raw_tc_bad; do
    CURL_PROFILES="$p" SG_ATTEMPTS=1 SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$1" "$ROW_ID-${p//@/_}"
    line="$(sg_line)"
    need "[$p] no selfgate_failed event was logged (rc=$(val rc) reason=$(val reason))" "$([ -n "$line" ] && echo 0 || echo 1)" || return 1
    need "[$p] the event is not the anchored grammar: [$line]" "$(grep -qE "$re" <<< "$line" && echo 0 || echo 1)" || return 1
    need "[$p] the event carries a value (an address, a scheme or curl text): [$line]" "$(grep -qE '10\.0\.1\.|https?://|leak\.invalid|garbage' <<< "$line" && echo 1 || echo 0)" || return 1
  done
  # the same detail string reaches Sentry (extra.detail), with the classification tag: "no value in the event" covers the whole event
  for p in req_reset verify18 raw_garbage; do
    CURL_PROFILES="$p" KEEP_SENTRY=1 SG_ATTEMPTS=1 SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$1" "$ROW_ID-sentry-$p"
    line="$(sg_line)"; jd="${line#INNGEST_LINK: class=selfgate_failed level=error }"
    n="$(grep -c 'api/7/store/' "$RUN/curl.argv" || true)"
    detail="$(grep 'api/7/store/' "$RUN/curl.argv" | grep -o '"detail":"[^"]*"' | head -n1 | sed -e 's/^"detail":"//' -e 's/"$//')"
    need "[$p] exactly one Sentry POST expected for the selfgate_failed error, found $n" "$([ "$n" = 1 ] && echo 0 || echo 1)" || return 1
    need "[$p] the Sentry extra.detail is [$detail], want the journald detail [$jd]" "$([ -n "$jd" ] && [ "$detail" = "$jd" ] && echo 0 || echo 1)" || return 1
    sentry_body="$(grep 'api/7/store/' "$RUN/curl.argv" || true)"
    need "[$p] the Sentry event does not carry classification=selfgate_failed" "$(grep -q '"classification":"selfgate_failed"' <<< "$sentry_body" && echo 0 || echo 1)" || return 1
    need "[$p] the Sentry body carries a value: $(grep -oE '10\.0\.1\.[0-9]+|leak\.invalid' <<< "$sentry_body" | head -n1)" "$(grep -qE 'leak\.invalid|garbage|8443' <<< "$sentry_body" && echo 1 || echo 0)" || return 1
  done
}
SG_S6='raw_empty@124|124|none|unknown|0|0|0
raw_empty@2|2|none|unknown|0|0|0
raw_garbage@56|56|none|unknown|0|0|0
raw_short3@56|56|200|unknown|1|0|0
raw_nonnum@56|56|000|unknown|0|0|0
raw_nonnum@60|60|000|verify|0|0|18
raw_nonnum502@56|56|502|status|0|0|0
req_reset@124|124|000|unknown|1|1|0
raw_verify_nonnum|60|000|verify|1|0|0'
# the comma separator is a decimal separator for a ZERO timer too (a locale-affected build): `0,000000` is zero, never a stage that happened
SG_S6B='raw_refused_comma|7|000|connect|0|0|0
raw_hs_comma|35|000|handshake|1|0|0'
row_S6b_comma_decimal_zero_is_zero() { sg_table "$1" s6b "$SG_S6B"; }
row_S6_unknown_arms_and_validated_values() {
  # an empty line (rc 124: the timeout wrapper killed curl; rc 2: curl 8.23 with a MISSING CA file; an empty or garbage file is rc 77), a garbage first token (http=none, never
  # the raw token), a short line, non-numeric times (an rc-only arm still reads verify, a validated non-200 code still reads status), and
  # rc 124 beating perfectly good times (req_reset@124 reads unknown, never request), and a verification result that is text (raw_verify_nonnum
  # reads verify=0: the one field a curl line could inject text through is clamped to an integer): every row states its rc and its whole line
  sg_table "$1" s6 "$SG_S6"
}
row_S6c_one_unreadable_timer_beside_a_readable_one_reads_unknown() {
  # time_connect is text, time_appconnect is a readable non-zero number (rc 56): the phase is unknown (an unreadable timer says nothing about the
  # stage, whichever of the two it is), tcp counts nothing (its OWN field failed the shape check) and tls counts the attempt (its own field passed).
  # A shape check that looked at time_appconnect alone would read `request` here.
  sg_expect "$1" tcbad raw_tc_bad 56 000 1 unknown 0 1 0
}
row_S7_wflags_allowlist_is_the_four_names() {
  local names want n
  names="$(sed -n '/^_inngest_link_selfgate/,/^}/p' "$1" | grep -vE '^[[:space:]]*#' | grep -oE '%\{[a-z_]+\}' | sort -u | tr -d '%{}' | paste -sd' ')"
  want="http_code ssl_verify_result time_appconnect time_connect"
  need "the write-out variables in the self-gate text are [$names], want exactly [$want] (equality, not a subset: a dropped variable must red too)" "$([ "$names" = "$want" ] && echo 0 || echo 1)" || return 1
  n="$(sed -n '/^_inngest_link_selfgate/,/^}/p' "$1" | grep -vE '^[[:space:]]*#' | grep -cE -- "-w '[^']*'" || true)"
  need "the self-gate text carries $n -w options, want exactly 1 (one curl per attempt, no second probe)" "$([ "$n" = 1 ] && echo 0 || echo 1)" || return 1
}
row_S8_noncanonical_input_and_success_first() {
  local p
  # a healthy listener whose -w line is non-canonical still passes the gate: a comma decimal separator plus an extra trailing token, and a SHORT
  # line (rc 0, code 200, the later fields missing): the verdict is decided from the exit code and the first token before any other field
  for p in ok200_comma_extra raw_short3@0; do
    CURL_PROFILES="$p" SG_ATTEMPTS=1 SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$1" "$ROW_ID-${p//@/_}"
    ok_https || { WHY="[$p] ${WHY:-}"; return 1; }
    need "[$p] a passing gate emitted a selfgate_failed event: $(sg_line)" "$([ "$(sg_count)" = 0 ] && echo 0 || echo 1)" || return 1
    need "[$p] calls=$(curl_calls), want 1" "$([ "$(curl_calls)" = 1 ] && echo 0 || echo 1)" || return 1
  done
  # a FAILING profile with commas maps to its phase just like the dotted one
  sg_expect "$1" comma req_reset_comma 56 000 1 request 1 1 0
}
row_S8b_no_trailing_newline_parses_last_field() {
  # curl prints no trailing newline after -w; the double does not either (the last field, ssl_verify_result, still has to be read)
  local f="$RUNS/s8b.out"
  ( export RUN_DIR="$RUNS/s8b-run" FX_CURL_PROFILES=verify18; mkdir -p "$RUN_DIR"; "$BIN/curl" -w '%{http_code} %{time_connect} %{time_appconnect} %{ssl_verify_result}' https://127.0.0.1:1/health > "$f" 2>/dev/null )
  need "the double printed a trailing newline (curl does not): $(od -c "$f" | tail -n2 | head -n1)" "$([ "$(tail -c1 "$f" | od -An -c | tr -d ' ')" != '\n' ] && echo 0 || echo 1)" || return 1
  need "the double printed [$(cat "$f")], want the four verify18 fields" "$([ "$(cat "$f")" = '000 0.000119 0.000000 18' ] && echo 0 || echo 1)" || return 1
  sg_expect "$1" nonl verify18 60 000 1 verify 1 0 18
}

row_S10_pass_verdict_is_exactly_rc0_and_http_200_through_the_pinned_file() {
  local argv n flag
  # an HTTP 204 with good timers and rc 0 is NOT a pass (a gate that accepts any 2xx must fail closed here), and neither is the four-digit
  # code 2000 (a gate that matches the prefix 200 passes it): both read their own phase from the timers and the code
  sg_expect "$1" status204 raw_status204 0 204 1 status 1 1 0 || return 1
  sg_expect "$1" code2000 raw_code2000 0 none 1 request 1 1 0 || return 1
  # the argv of the self-gate's ONE curl call, from the stub's log: every flag once, the candidate file, no -k and no --capath
  argv="$(grep -F -- ' -w ' "$RUN/curl.argv" | head -n1)"
  need "exactly one self-gate curl call expected for one attempt, found $(grep -cF -- ' -w ' "$RUN/curl.argv" || true)" "$([ "$(grep -cF -- ' -w ' "$RUN/curl.argv" || true)" = 1 ] && echo 0 || echo 1)" || return 1
  for flag in ' --disable ' " --noproxy * " ' --connect-timeout 5 ' ' --max-time 10 ' ' --cacert '; do
    n="$(printf '%s' " $argv " | grep -oF -- "$flag" | wc -l | tr -d ' ')"
    need "the self-gate argv carries [$flag] $n time(s), want exactly 1: $argv" "$([ "$n" = 1 ] && echo 0 || echo 1)" || return 1
  done
  need "the self-gate does not pin the CANDIDATE file with --cacert: $argv" "$(case "$argv" in *" --cacert /tmp/inngest-ca-cand."*) echo 0 ;; *) echo 1 ;; esac)" || return 1
  need "the self-gate argv carries -k, --insecure or --capath: $argv" "$(case " $argv " in *" -k "*|*" -sk "*|*"--insecure"*|*"--capath"*) echo 1 ;; *) echo 0 ;; esac)" || return 1
}
row_S11_one_event_on_every_sink_and_no_raw_output() {
  local nlog nstore sinks raw emitted
  # a failing gate (three attempts) emits exactly ONE INNGEST_LINK line over the journald logger and exactly ONE Sentry POST, and no sink
  # (the logger, the POST body, the resolver's own stdout and stderr) carries curl's raw -w output: a new log line in the failure tail
  # would otherwise be invisible to every other row
  CURL_PROFILES=req_reset KEEP_SENTRY=1 SG_ATTEMPTS=3 SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$1" "$ROW_ID-fail"
  nlog="$(grep -c 'INNGEST_LINK' "$RUN/logger.log" || true)"
  nstore="$(grep -c 'api/7/store/' "$RUN/curl.argv" || true)"
  sinks="$(cat "$RUN/logger.log" "$RUN/stdout"; grep 'api/7/store/' "$RUN/curl.argv" || true)"
  need "a failing gate logged $nlog INNGEST_LINK line(s), want exactly 1: $(cat "$RUN/logger.log")" "$([ "$nlog" = 1 ] && echo 0 || echo 1)" || return 1
  need "a failing gate made $nstore Sentry POST(s), want exactly 1" "$([ "$nstore" = 1 ] && echo 0 || echo 1)" || return 1
  need "a failing gate emitted $(sg_count) selfgate_failed line(s) over the logger, want exactly 1" "$([ "$(sg_count)" = 1 ] && echo 0 || echo 1)" || return 1
  for raw in '000 0.' '0.000138' '0.004360'; do
    need "a sink carries curl's raw -w output [$raw]" "$(grep -qF -- "$raw" <<< "$sinks" && echo 1 || echo 0)" || return 1
  done
  # no EMITTED INNGEST_LINK line carries a URL, on any sink: the logger and the resolver's own stdout and stderr (every INNGEST_LINK line there), and
  # the Sentry extra.detail (the POST's own argv names the Sentry endpoint, so the body's detail fields are read, not the whole argv)
  emitted="$(grep -h 'INNGEST_LINK' "$RUN/logger.log" "$RUN/stdout" || true; grep 'api/7/store/' "$RUN/curl.argv" | grep -o '"detail":"[^"]*"' || true)"
  need "no INNGEST_LINK line was emitted on any sink (the check below would be vacuous)" "$([ -n "$emitted" ] && echo 0 || echo 1)" || return 1
  need "an emitted INNGEST_LINK line carries a URL (://): $(grep -F '://' <<< "$emitted" | head -n1)" "$(grep -qF '://' <<< "$emitted" && echo 1 || echo 0)" || return 1
  # the pass path emits no failure event: its one INNGEST_LINK line is the info `class=resolved` row, never a selfgate_failed or any warning or
  # error, there is no Sentry POST and no raw output
  CURL_PROFILES=ok200 KEEP_SENTRY=1 SG_ATTEMPTS=3 SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$1" "$ROW_ID-pass"
  ok_https || return 1
  nlog="$(grep 'INNGEST_LINK' "$RUN/logger.log" | grep -vc 'class=resolved level=info ' || true)"
  nstore="$(grep -c 'api/7/store/' "$RUN/curl.argv" || true)"
  sinks="$(cat "$RUN/logger.log" "$RUN/stdout"; grep 'api/7/store/' "$RUN/curl.argv" || true)"
  need "a passing gate logged $nlog INNGEST_LINK line(s) besides the info resolved row, want 0: $(cat "$RUN/logger.log")" "$([ "$nlog" = 0 ] && echo 0 || echo 1)" || return 1
  need "a passing gate made $nstore Sentry POST(s), want 0" "$([ "$nstore" = 0 ] && echo 0 || echo 1)" || return 1
  for raw in '200 0.' '0.000503' '0.009276'; do
    need "a sink carries curl's raw -w output [$raw] on the pass path" "$(grep -qF -- "$raw" <<< "$sinks" && echo 1 || echo 0)" || return 1
  done
}
row_S12_the_w_line_parse_does_not_depend_on_the_callers_ifs() {
  # the four fields are split on a single space whatever IFS the caller holds (the production read is `IFS=' ' read`): with IFS a newline the
  # incident line must still read phase=request tcp=1 tls=1
  SCEN_IFS=$'\n' sg_expect "$1" ifs-newline req_reset 56 000 1 request 1 1 0
}
row_S13_the_phase_belongs_to_one_resolve_and_is_never_left_over() {
  local first="$1"
  # (a) a gate that fails once and then passes (rc 0): the phase of the failed attempt must not outlive the pass. The variable is the empty
  # string (reset at the top of resolve_inngest_link), neither the failed attempt's `request` nor unset, and no failure event was emitted.
  CURL_PROFILES='req_reset,ok200' SG_ATTEMPTS=3 SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$first" "$ROW_ID-a"
  ok_https || return 1
  need "[a] curl calls=$(curl_calls), want 2 (one failed attempt, then the pass)" "$([ "$(curl_calls)" = 2 ] && echo 0 || echo 1)" || return 1
  need "[a] a gate that passed on its second attempt left the phase [$(val phase)] (want the empty string)" "$([ "$(val phase)" = "" ] && echo 0 || echo 1)" || return 1
  need "[a] a passing gate emitted a selfgate_failed event: $(sg_line)" "$([ "$(sg_count)" = 0 ] && echo 0 || echo 1)" || return 1
  # (b) ONE shell, two resolves: a failing resolve leaves request, and the next resolve (a pass, then a flag-off one) must leave it empty again
  CURL_PROFILES='req_reset,ok200' SCEN_AGAIN=pass SG_ATTEMPTS=1 SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$first" "$ROW_ID-b"
  need "[b] the first resolve did not fail (rc1=$(val rc1))" "$([ -n "$(val rc1)" ] && [ "$(val rc1)" != 0 ] && echo 0 || echo 1)" || return 1
  need "[b] the first (failing) resolve left the phase [$(val phase1)], want request" "$([ "$(val phase1)" = request ] && echo 0 || echo 1)" || return 1
  ok_https || return 1
  need "[b] the second (passing) resolve left the phase [$(val phase)] from the first (want the empty string)" "$([ "$(val phase)" = "" ] && echo 0 || echo 1)" || return 1
  CURL_PROFILES=req_reset SCEN_AGAIN=flagoff SG_ATTEMPTS=1 SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$first" "$ROW_ID-c"
  need "[c] the first resolve did not leave phase request (phase1=[$(val phase1)])" "$([ "$(val phase1)" = request ] && echo 0 || echo 1)" || return 1
  need "[c] the flag-off second resolve: rc=$(val rc) url=$(val url)" "$([ "$(val rc)" = 0 ] && [ "$(val url)" = http://10.0.1.40:8288 ] && echo 0 || echo 1)" || return 1
  need "[c] the flag-off second resolve left the phase [$(val phase)] from the first (want the empty string)" "$([ "$(val phase)" = "" ] && echo 0 || echo 1)" || return 1
}

# S9: the runbook decode tables name every token and every field of the grammar. The checker reads TABLE ROWS of the section headed
# "Reading `selfgate_failed`": a `|` row whose FIRST cell is the backticked name, a field in the table headed `Field` and a token in the table
# headed `phase` (a table is classified by the first cell of its header row). A word in the prose beside the tables never counts (the
# section is full of them). It is proved against known-bad copies: a synthetic document and, when the runbook is readable, copies of the real
# one with a token row, a field row, or a whole table deleted. The helper is run, not grepped, so a token that exists only in a comment
# cannot count.
RUNBOOK="${INNGEST_LINK_TEST_RUNBOOK:-$SCRIPT_DIR/../../../knowledge-base/engineering/operations/runbooks/inngest-server.md}"
SG_TOKENS='ca_file connect handshake request status unknown verify'
SG_FIELDS='attempts http phase rc tcp tls verify'
# sg_decode_awk <list|drop> <doc> [kind name]: `list` prints "<field|token> <name>" for every table row of the section; `drop` prints the
# document without the named row (kind and name), or without the whole table of that kind (name empty)
sg_decode_awk() {
  awk -v mode="$1" -v dk="${3-}" -v dn="${4-}" '
    { keep = 1; rowkind = "" }
    /^#+ .*Reading `selfgate_failed`/ { on = 1; intable = 0; if (mode == "drop") print; next }
    on && /^#+ / { on = 0; if (mode == "list") exit }
    on && /^\|/ {
      line = $0; sub(/^\|[ \t]*/, "", line); cell = line; sub(/[ \t]*\|.*$/, "", cell); c = cell; gsub(/`/, "", c)
      if (!intable) { intable = 1; hdr = 1; kind = "" }
      if (hdr) { if (tolower(c) == "field") kind = "field"; else if (c == "phase") kind = "token"; hdr = 0; rowkind = "hdr" }
      else if (cell ~ /^[-: ]+$/) rowkind = "sep"
      else if (cell ~ /^`[a-z_]+`$/) { rowkind = "row"; name = c }
      else rowkind = "other"
      if (mode == "list" && rowkind == "row" && kind != "") print kind, name
      if (mode == "drop" && kind == dk && (dn == "" || (rowkind == "row" && name == dn))) keep = 0
    }
    on && !/^\|/ { intable = 0 }
    mode == "drop" && keep { print }
  ' "$2"
}
sg_decode_check() { # <doc file>: every field has a row in the field table and every token a row in the phase table; prints the first miss, returns 1
  local rows t
  rows="$(sg_decode_awk list "$1" 2>/dev/null)"
  [ -n "$rows" ] || { printf 'no decode table rows under a "Reading `selfgate_failed`" heading'; return 1; }
  for t in $SG_FIELDS; do
    grep -qxF -- "field $t" <<< "$rows" || { printf 'the field table has no row whose first cell is `%s`' "$t"; return 1; }
  done
  for t in $SG_TOKENS; do
    grep -qxF -- "token $t" <<< "$rows" || { printf 'the phase table has no row whose first cell is `%s`' "$t"; return 1; }
  done
  return 0
}
row_S9_decode_names_every_token_and_field() {
  local tokens n miss
  # the helper prints exactly seven tokens: one input per branch, run under the real block (an absent helper reads an empty set)
  tokens="$( ( # shellcheck disable=SC1090
      source "$1" >/dev/null 2>&1 || exit 99
      declare -F _inngest_link_selfgate_phase >/dev/null || exit 98
      _inngest_link_selfgate_phase 124 '' '' ''; echo
      _inngest_link_selfgate_phase 77 000 0.000452 0.000000; echo
      _inngest_link_selfgate_phase 60 000 0.000119 0.000000; echo
      _inngest_link_selfgate_phase 0 502 0.000235 0.010363; echo
      _inngest_link_selfgate_phase 7 000 0.000000 0.000000; echo
      _inngest_link_selfgate_phase 35 000 0.000198 0.000000; echo
      _inngest_link_selfgate_phase 56 000 0.000138 0.004360; echo
    ) 2>/dev/null | grep -v '^$' | sort -u | paste -sd' ')"
  n="$(wc -w <<< "$tokens" | tr -d ' ')"
  need "the phase helper produced $n distinct tokens [$tokens], want exactly the seven of the grammar [$SG_TOKENS]" "$([ "$n" = 7 ] && [ "$tokens" = "$SG_TOKENS" ] && echo 0 || echo 1)" || return 1
  miss="$(sg_decode_check "$RUNBOOK")"
  need "the runbook decode tables do not cover the grammar: $miss" "$([ -z "$miss" ] && echo 0 || echo 1)" || return 1
}
s9_synth() { # <doc>: a complete synthetic section whose PROSE also names every token and field (so only a table row can satisfy the checker)
  local t
  {
    printf '# Runbook\n\n### Reading `selfgate_failed`\n\nProse: the %s fields and the %s tokens are named here in plain words.\n\n' "$SG_FIELDS" "$SG_TOKENS"
    printf '| Field | Meaning | Reading rule |\n|---|---|---|\n'
    for t in $SG_FIELDS; do printf '| `%s` | text | rule |\n' "$t"; done
    printf '\n| `phase` | The last attempt | Typical rc |\n|---|---|---|\n'
    for t in $SG_TOKENS; do printf '| `%s` | text | rc |\n' "$t"; done
    printf '\n### Next section\n\n| `handshake` | a row of another section |\n'
  } > "$1"
}
s9_expect_red() { # <label> <doc>: the checker must reject the doc
  need "the checker accepted a document with $1 (it cannot go red)" "$(sg_decode_check "$2" >/dev/null && echo 1 || echo 0)" || return 1
}
row_S9b_decode_checker_can_go_red() {
  local good="$RUNS/s9-good.md" bad="$RUNS/s9-bad.md"
  s9_synth "$good"
  need "the checker rejected a complete synthetic section: $(sg_decode_check "$good")" "$(sg_decode_check "$good" >/dev/null && echo 0 || echo 1)" || return 1
  # known-bad synthetic copies: the prose still names every word (and a `handshake` row sits in the NEXT section), only the section's rows go
  sg_decode_awk drop "$good" token handshake > "$bad"; cmp -s "$good" "$bad" && { WHY="the harness edit did not land (token row)"; return 1; }
  s9_expect_red "the handshake token row deleted" "$bad" || return 1
  sg_decode_awk drop "$good" field tcp > "$bad"; cmp -s "$good" "$bad" && { WHY="the harness edit did not land (field row)"; return 1; }
  s9_expect_red "the tcp field row deleted" "$bad" || return 1
  sg_decode_awk drop "$good" token "" > "$bad"; cmp -s "$good" "$bad" && { WHY="the harness edit did not land (phase table)"; return 1; }
  s9_expect_red "the whole phase table deleted" "$bad" || return 1
  sg_decode_awk drop "$good" field "" > "$bad"; cmp -s "$good" "$bad" && { WHY="the harness edit did not land (field table)"; return 1; }
  s9_expect_red "the whole field table deleted" "$bad" || return 1
  # `verify` is both a field and a token: dropping the phase-table row must red although the field table still has one
  sg_decode_awk drop "$good" token verify > "$bad"; cmp -s "$good" "$bad" && { WHY="the harness edit did not land (verify token row)"; return 1; }
  s9_expect_red "only the verify TOKEN row deleted (the verify field row remains)" "$bad" || return 1
  # the same, against the REAL runbook (absent in a sandbox without knowledge-base/: the synthetic proofs above stand alone there)
  if [ -r "$RUNBOOK" ]; then
    need "the real runbook is not GREEN for the checker: $(sg_decode_check "$RUNBOOK")" "$(sg_decode_check "$RUNBOOK" >/dev/null && echo 0 || echo 1)" || return 1
    sg_decode_awk drop "$RUNBOOK" token status > "$bad"; cmp -s "$RUNBOOK" "$bad" && { WHY="the harness edit did not land (real runbook, status row)"; return 1; }
    s9_expect_red "the real runbook's status phase row deleted" "$bad" || return 1
    sg_decode_awk drop "$RUNBOOK" token "" > "$bad"; cmp -s "$RUNBOOK" "$bad" && { WHY="the harness edit did not land (real runbook, phase table)"; return 1; }
    s9_expect_red "the real runbook's whole phase table deleted" "$bad" || return 1
    sg_decode_awk drop "$RUNBOOK" field tls > "$bad"; cmp -s "$RUNBOOK" "$bad" && { WHY="the harness edit did not land (real runbook, tls row)"; return 1; }
    s9_expect_red "the real runbook's tls field row deleted" "$bad" || return 1
  fi
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
  E8_canary_counts_only_the_exact_names
  L1_scrub_removes_pinned_names_and_keeps_the_rest L2_scrub_no_match_is_a_noop_and_idempotent L3_scrub_read_and_write_failures_leave_the_file_untouched
  L4_scrub_recount_failure_leaves_the_file_untouched L5_scrub_conservation_failure_leaves_the_file_untouched L6_scrub_all_lines_matching_yields_an_empty_file
  L7_scrub_holds_under_a_utf8_locale L8_scrub_names_match_the_tuple_census_and_the_canary_counts
  S1_connect_and_ca_file S2_handshake_and_verify S3_request_and_status S3b_same_times_any_rc_reads_request S3c_tls_complete_but_not_200_fails_with_phase_status
  S4_sequence_counts_and_last_phase S4b_counters_clamp S5_event_grammar_on_both_sinks S6_unknown_arms_and_validated_values S7_wflags_allowlist_is_the_four_names
  S8_noncanonical_input_and_success_first S8b_no_trailing_newline_parses_last_field S9_decode_names_every_token_and_field S9b_decode_checker_can_go_red
  S4c_verify_does_not_outlive_its_attempt S4d_http_does_not_outlive_its_attempt S6b_comma_decimal_zero_is_zero
  S10_pass_verdict_is_exactly_rc0_and_http_200_through_the_pinned_file S11_one_event_on_every_sink_and_no_raw_output S12_the_w_line_parse_does_not_depend_on_the_callers_ifs
  S6c_one_unreadable_timer_beside_a_readable_one_reads_unknown S13_the_phase_belongs_to_one_resolve_and_is_never_left_over
)

ROW_ID=""; ROW_WHY=""
# run_rows <block> <id>... : prints nothing, sets RES[id]=0 (held) or 1 (violated) and ROW_WHYS[id]
declare -A RES ROW_WHYS
run_rows() {
  local block="$1" id; shift
  for id in "$@"; do
    ROW_ID="$id"; WHY=""; rm -f "$CURLW_SENTINEL"
    if "row_$id" "$block"; then RES[$id]=0; else RES[$id]=1; ROW_WHYS[$id]="$WHY"; fi
    # the shared printer refused an unknown variable or profile during this row (the function under test swallows curl's exit and
    # stderr, so the exit alone would read as one more failed attempt): the row is violated whatever else it said
    if [ -e "$CURLW_SENTINEL" ]; then RES[$id]=1; ROW_WHYS[$id]="${ROW_WHYS[$id]:+${ROW_WHYS[$id]}; }the curl profile printer refused: $(head -n1 "$CURLW_SENTINEL")"; rm -f "$CURLW_SENTINEL"; fi
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
L_SCRUB="$(lineno 'inngest_link_scrub_env_file "$ENV_FILE" ||')"
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
# wiring: the env-file scrub runs once, after the resolver and before the FIRST docker run (so both app starts read the scrubbed file)
wire_ok "the env-file scrub runs after the resolver" "$L_RES" "$L_SCRUB"
wire_ok "the env-file scrub runs before the canary docker run" "$L_SCRUB" "$L_CANARY_RUN"
ROWS=$((ROWS + 1))
if [ "$(grep -cF -- 'inngest_link_scrub_env_file "$ENV_FILE" ||' "$CI_DEPLOY")" = 1 ]; then ok "wiring: the env-file scrub is called at exactly one site"; else bad "wiring: the env-file scrub call site is not unique"; fi
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
# the verdicts of the pristine run: kill_mut re-runs rows on a mutated block and overwrites RES, so the mutation rows that need "the named rows
# are GREEN on the pristine block" read this snapshot
declare -A PRISTINE
for id in "${ROW_IDS[@]}"; do PRISTINE[$id]="${RES[$id]:-1}"; done

# ---------------------------------------------------------------------------------------
# H1: the curl stub always succeeds -> the CA-withheld rows MUST go RED. A suite that stays green here
# cannot see a vacuous self-gate.
# ---------------------------------------------------------------------------------------
h1_rc=0
( CURL_ALWAYS_OK=1; export CURL_ALWAYS_OK; ROW_ID=A4_wrong_server_fails_closed; WHY=""; row_A4_wrong_server_fails_closed "$BLOCK_REAL" ) >/dev/null 2>&1 || h1_rc=$?
ROWS=$((ROWS + 1))
if [ "$h1_rc" -ne 0 ]; then ok "H1 an always-succeeding curl turns the wrong-server row RED (the suite can see a vacuous self-gate)"; else bad "H1 the wrong-server row stayed GREEN with an always-succeeding curl (vacuous self-gate not detectable)"; fi

# ---------------------------------------------------------------------------------------
# H1b (#10934): an always-succeeding curl turns the new phase rows RED too, and H8: a stub that IGNORES the profile list (it answers like a
# healthy server) turns S1 to S4 RED. A suite that cannot see either proves nothing about the phases.
# ---------------------------------------------------------------------------------------
h_reds() { # <env assignment> <row id>... : prints the rows that stayed GREEN under the harness edit (empty = every row went RED)
  local env="$1" id stayed=""; shift
  for id in "$@"; do
    ( export "${env?}"; ROW_ID="$id"; WHY=""; "row_$id" "$BLOCK_REAL" ) >/dev/null 2>&1 && stayed="$stayed $id"
  done
  printf '%s' "${stayed# }"
}
h1b_stayed="$(h_reds CURL_ALWAYS_OK=1 S1_connect_and_ca_file S2_handshake_and_verify S3_request_and_status S3b_same_times_any_rc_reads_request S4_sequence_counts_and_last_phase S6_unknown_arms_and_validated_values)"
ROWS=$((ROWS + 1))
if [ -z "$h1b_stayed" ]; then ok "H1b an always-succeeding curl turns the phase rows RED (S1, S2, S3, S3b, S4, S6)"; else bad "H1b these phase rows stayed GREEN with an always-succeeding curl: $h1b_stayed"; fi
h8_stayed="$(h_reds CURL_PROFILES_IGNORED=1 S1_connect_and_ca_file S2_handshake_and_verify S3_request_and_status S4_sequence_counts_and_last_phase)"
ROWS=$((ROWS + 1))
if [ -z "$h8_stayed" ]; then ok "H8 a stub that ignores the profile list turns S1 to S4 RED (the profiles are what the rows are answered from)"; else bad "H8 these rows stayed GREEN with the profile list ignored: $h8_stayed"; fi
rm -f "$CURLW_SENTINEL"

# ---------------------------------------------------------------------------------------
# H7: printer fidelity and refusal. (a) the measured table is EXACTLY the named set (a profile cannot be added or renamed unseen) and every
# measured profile prints the canonical four-field line with no trailing newline; (b) the double refuses an unknown variable and an unknown
# profile (rc 99 and the sentinel) and a missing fixture (rc 98); (c) through the REAL function: a -w naming an unknown variable drops the
# sentinel (the function swallows curl's exit and stderr, so the sentinel is the only evidence).
# ---------------------------------------------------------------------------------------
h7a_why=""
h7a_names="$(printf '%s\n' "$CURLW_MEASURED" | cut -d'|' -f1 | sort | paste -sd' ')"
# shellcheck disable=SC2086
h7a_want="$(printf '%s\n' $SG_NAMED_SETS | sort | paste -sd' ')"
[ "$h7a_names" = "$h7a_want" ] || h7a_why="the measured table names [$h7a_names] are not exactly the named sets [$h7a_want]"
h7a_in="$(printf '%s\n%s\n%s\n' "$SG_S1" "$SG_S2" "$SG_S3" | cut -d'|' -f1 | sort | paste -sd' ') ok200"
# shellcheck disable=SC2086
[ -n "$h7a_why" ] || [ "$(printf '%s\n' $h7a_in | sort | paste -sd' ')" = "$h7a_want" ] || h7a_why="the S1 to S3 tables do not iterate exactly the named sets: [$h7a_in]"
h7a_re='^[0-9]{3} [0-9]+\.[0-9]{6} [0-9]+\.[0-9]{6} [0-9]+$'
while IFS='|' read -r h7a_n _; do
  [ -n "$h7a_why" ] && break
  # shellcheck source=/dev/null
  h7a_out="$( ( source "$CURLW_FIXTURE"; curlw_print "$h7a_n" '%{http_code} %{time_connect} %{time_appconnect} %{ssl_verify_result}' ) 2>&1; printf x )"
  h7a_out="${h7a_out%x}"
  grep -qE "$h7a_re" <<< "$h7a_out" && [ "${h7a_out%$'\n'}" = "$h7a_out" ] || h7a_why="profile $h7a_n printed [$h7a_out] (want the canonical four fields, no trailing newline)"
done <<< "$CURLW_MEASURED"
ROWS=$((ROWS + 1))
if [ -z "$h7a_why" ]; then ok "H7a the measured table is exactly the named set and every profile prints the canonical four-field line without a trailing newline"; else bad "H7a $h7a_why"; fi

h7b_why=""
h7b_run() { # <profile> <fmt> [profiles file]: runs the resolver suite's stub directly; prints its rc; the sentinel is left for the caller
  ( export RUN_DIR="$RUNS/h7b-run" FX_CURL_PROFILES="$1" ${3:+CURL_W_PROFILES_FILE="$3"}; mkdir -p "$RUN_DIR"; "$BIN/curl" -s -o /dev/null -w "$2" https://127.0.0.1:1/health >/dev/null 2>&1; printf '%s' "$?" )
}
rm -f "$CURLW_SENTINEL"
[ "$(h7b_run ok200 '%{errormsg}')" = 99 ] && [ -s "$CURLW_SENTINEL" ] || h7b_why="an unknown write-out variable (%{errormsg}) did not exit 99 with the sentinel"
rm -f "$CURLW_SENTINEL"
[ -n "$h7b_why" ] || { [ "$(h7b_run no_such_profile '%{http_code}')" = 99 ] && [ -s "$CURLW_SENTINEL" ] || h7b_why="an unknown profile did not exit 99 with the sentinel"; }
rm -f "$CURLW_SENTINEL"
[ -n "$h7b_why" ] || { [ "$(h7b_run ok200 '%{http_code}' "$RUNS/no-such-fixture.sh")" = 98 ] || h7b_why="a missing profile file did not exit 98"; }
[ -n "$h7b_why" ] || { [ ! -e "$CURLW_SENTINEL" ] || h7b_why="a missing fixture dropped the printer sentinel (it never reached the printer)"; }
rm -f "$CURLW_SENTINEL"
[ -n "$h7b_why" ] || { [ "$(h7b_run ok200 '%{http_code}')" = 0 ] && [ ! -e "$CURLW_SENTINEL" ] || h7b_why="a valid profile and variable did not print cleanly (control)"; }
ROWS=$((ROWS + 1))
if [ -z "$h7b_why" ]; then ok "H7b the double refuses an unknown variable and an unknown profile (exit 99 plus the sentinel) and a missing fixture (exit 98)"; else bad "H7b $h7b_why"; fi
rm -f "$CURLW_SENTINEL"

# (c) through the real function: the first -w option of the self-gate text is rewritten to name %{errormsg}; the function swallows curl's exit
# and stderr, so only the sentinel can show the double refused it
h7c_blk="$WORK/block.h7c.sh"
python3 -I - "$BLOCK_REAL" "$h7c_blk" <<'PY' || die "H7c: could not build the control block"
import re, sys
s = open(sys.argv[1]).read()
n = len(re.findall(r"-w '[^']*'", s))
if n < 1:
    sys.exit(3)
open(sys.argv[2], "w").write(re.sub(r"-w '[^']*'", "-w '%{errormsg}'", s))
PY
CURL_PROFILES=ok200 SG_ATTEMPTS=1 SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$h7c_blk" "H7c"
ROWS=$((ROWS + 1))
if [ -s "$CURLW_SENTINEL" ] && grep -q 'errormsg' "$CURLW_SENTINEL"; then ok "H7c through the real function an unknown write-out variable drops the printer sentinel (the control the per-row sentinel check relies on)"; else bad "H7c a -w naming %{errormsg} did not drop the sentinel through the real function (rc=$(val rc))"; fi
rm -f "$CURLW_SENTINEL"

# ---------------------------------------------------------------------------------------
# H6: the REAL self-gate against REAL curl and local python `ssl` listeners, six scenarios; H9: the comparison against a COPY of the profile
# file with one value flipped goes RED. The comparison is on (exit-code class, http code, whether time_connect and time_appconnect are zero,
# ssl_verify_result), not on the phase alone, and 52 and 56 form ONE class (one wire event prints 52 on curl 8.5.0, 56 on 7.81 and 8.23).
# The function swallows curl's stdout and exit code, so a passthrough shim around real curl logs both. RST, the empty-CA-file case, the
# truncated body and the hang phases (5 s and 10 s timers) are stub-only and rest on the evidence file. Under CI a missing curl is a
# failure, not a skip; locally the skip is counted so the exact MIN_ROWS stays consistent (ROWS and SKIP both move by N, as H3 does).
# ---------------------------------------------------------------------------------------
H6_SCENARIOS='closed|refused|closed|loop.crt
plainclose|hs_close|plain_close|loop.crt
mismatch|verify18|tls_mismatch|loop.crt
tlsclose|req_empty|tls_clean_close|loop.crt
tls200|ok200|tls_200|loop.crt
tls502|status502|tls_502|loop.crt'
H6_N=11   # six scenarios plus the five H9 column flips
H6_DIR="$WORK/h6"
h6_phase_of() { # <event log file>: the phase= and verify= fields of the self-gate event the file holds, or `pass` when it holds none
  local ev
  ev="$(grep -F 'class=selfgate_failed' "$1" 2>/dev/null | head -n1 || true)"
  if [ -z "$ev" ]; then printf pass; else printf '%s' "$ev" | sed -E 's/.*(phase=[a-z_]+).*(verify=[0-9]+).*/\1 \2/'; fi
}
h6_class() { case "$1" in 52|56) printf '52or56' ;; *) printf '%s' "$1" ;; esac; }
h6_tstate() { # <time field>: missing | zero | nonzero
  if [[ ! "$1" =~ ^[0-9]+[.,][0-9]+$ ]]; then printf missing; elif [[ "$1" =~ ^[0.,]*$ ]]; then printf zero; else printf nonzero; fi
}
h6_compare() { # <label> <profile>: real curl's logged output against the profile of $CURL_W_PROFILES_FILE (default: the fixture); sets H6_WHY
  local label="$1" rrc rout rcode rtc rta rver prof pc pco ptc pta pver real_ph stub_ph
  H6_WHY=""
  rrc="$(cat "$H6_DIR/$label.rc" 2>/dev/null)"; rout="$(cat "$H6_DIR/$label.out" 2>/dev/null)"
  [ -n "$rrc" ] || { H6_WHY="the self-gate made no curl call"; return 1; }
  read -r rcode rtc rta rver <<< "$rout"
  # shellcheck source=/dev/null
  prof="$( ( source "${CURL_W_PROFILES_FILE:-$CURLW_FIXTURE}" || exit 98; curlw_lookup "$2" || exit 97
             printf '%s|%s|%s|%s|%s' "$CURLW_RC" "$CURLW_CODE" "$CURLW_TC" "$CURLW_TA" "$CURLW_VER" ) 2>/dev/null )" || { H6_WHY="profile $2 unreadable"; return 1; }
  IFS='|' read -r pc pco ptc pta pver <<< "$prof"
  [ "$(h6_class "$rrc")" = "$(h6_class "$pc")" ] || H6_WHY="rc class: real curl exited $rrc, profile $2 says $pc"
  [ -n "$H6_WHY" ] || [ "$rcode" = "$pco" ] || H6_WHY="http_code: real curl printed [$rcode], profile $2 says [$pco] (stdout was [$rout])"
  [ -n "$H6_WHY" ] || [ "$(h6_tstate "$rtc")" = "$(h6_tstate "$ptc")" ] || H6_WHY="time_connect: real curl printed [$rtc] ($(h6_tstate "$rtc")), profile $2 says [$ptc] ($(h6_tstate "$ptc"))"
  [ -n "$H6_WHY" ] || [ "$(h6_tstate "$rta")" = "$(h6_tstate "$pta")" ] || H6_WHY="time_appconnect: real curl printed [$rta] ($(h6_tstate "$rta")), profile $2 says [$pta] ($(h6_tstate "$pta"))"
  [ -n "$H6_WHY" ] || [ "$rver" = "$pver" ] || H6_WHY="ssl_verify_result: real curl printed [$rver], profile $2 says [$pver]"
  # the phase (and verify value) the REAL self-gate emitted for this scenario equals what the STUB profile makes the same function emit
  if [ -z "$H6_WHY" ]; then
    real_ph="$(h6_phase_of "$H6_DIR/$label.log")"
    CURL_PROFILES="$2" SG_ATTEMPTS=1 SNAP_EXTRA="$ONFLAG" CA_MODE=ok CA_FILE="$FX/v-good.pem" scenario "$BLOCK_REAL" "h6stub-$label"
    stub_ph="$(h6_phase_of "$RUN/logger.log")"
    [ "$real_ph" = "$stub_ph" ] || H6_WHY="phase: the REAL self-gate emitted [$real_ph], the stub profile $2 makes it emit [$stub_ph]"
  fi
  [ -z "$H6_WHY" ]
}
h6_all() { # compares every scenario; sets H6_ALL_WHY to the first miss
  local label prof _l _c
  H6_ALL_WHY=""
  while IFS='|' read -r label prof _l _c; do
    h6_compare "$label" "$prof" || { H6_ALL_WHY="$label: $H6_WHY"; return 1; }
  done <<< "$H6_SCENARIOS"
}
h6_tools_ok() { [ -n "$(command -v curl)" ] && command -v python3 >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1; }
h6_setup() { # starts the listeners, runs the six scenarios; returns 1 (and sets H6_SETUP_WHY) when the harness itself failed
  local i port label prof lis ca REAL_CURL REAL_SLEEP
  H6_SETUP_WHY=""
  REAL_CURL="$(command -v curl)"; REAL_SLEEP="$(command -v sleep)"
  mkdir -p "$H6_DIR/bin"
  {
    printf '#!/bin/bash\nREAL_CURL=%q\n' "$REAL_CURL"
    cat <<'SHIM'
# passthrough shim around REAL curl: the self-gate swallows curl's stdout and exit code, so log both
out="$("$REAL_CURL" "$@" 2>>"${H6_OUT_PREFIX:?}.err")"; rc=$?
printf '%s' "$out" > "$H6_OUT_PREFIX.out"; printf '%s' "$rc" > "$H6_OUT_PREFIX.rc"
printf '%s' "$out"; exit "$rc"
SHIM
  } > "$H6_DIR/bin/curl"
  printf '#!/bin/bash\nexit 0\n' > "$H6_DIR/bin/sleep"
  cat > "$H6_DIR/bin/logger" <<'SHIM'
#!/bin/bash
printf '%s\n' "$*" >> "${H6_OUT_PREFIX:?}.log"
exit 0
SHIM
  chmod +x "$H6_DIR/bin/curl" "$H6_DIR/bin/sleep" "$H6_DIR/bin/logger"
  cat > "$H6_DIR/server.py" <<'PY'
import os, signal, socket, ssl, sys, threading, time
signal.alarm(240)  # never outlive the suite by more than this, whatever happens to the parent
good_crt, good_key, other_crt, other_key, portfile = sys.argv[1:6]
def listener():
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", 0)); s.listen(16); return s
def ctx(crt, key):
    c = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); c.load_cert_chain(crt, key); return c
good, other = ctx(good_crt, good_key), ctx(other_crt, other_key)
def read_request(t):
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = t.recv(4096)
        if not chunk: break
        data += chunk
    return data
def handle(mode, conn):
    try:
        conn.settimeout(8)
        if mode == "plain_close":
            conn.close(); return
        t = (other if mode == "tls_mismatch" else good).wrap_socket(conn, server_side=True)
        read_request(t)
        if mode == "tls_clean_close":
            t.unwrap(); t.close(); return
        status = b"200 OK" if mode == "tls_200" else b"502 Bad Gateway"
        t.sendall(b"HTTP/1.1 " + status + b"\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
        t.close()
    except Exception:
        try: conn.close()
        except Exception: pass
def serve(mode, srv):
    while True:
        try: conn, _ = srv.accept()
        except Exception: return
        threading.Thread(target=handle, args=(mode, conn), daemon=True).start()
ports = {}
for mode in ("plain_close", "tls_mismatch", "tls_clean_close", "tls_200", "tls_502"):
    srv = listener(); ports[mode] = srv.getsockname()[1]
    threading.Thread(target=serve, args=(mode, srv), daemon=True).start()
c = socket.socket(); c.bind(("127.0.0.1", 0)); ports["closed"] = c.getsockname()[1]  # bound and NEVER listening, held for the process lifetime: connect is refused and nobody else can take the port
with open(portfile + ".tmp", "w") as f:
    for k, v in ports.items(): f.write("%s %s\n" % (k, v))
os.rename(portfile + ".tmp", portfile)
while True: time.sleep(1)
PY
  rm -f "$H6_DIR/ports"
  python3 -I "$H6_DIR/server.py" "$FX/loop.crt" "$FX/loop.key" "$FX/loopalt.crt" "$FX/loopalt.key" "$H6_DIR/ports" > "$H6_DIR/server.log" 2>&1 &
  H6_PID=$!
  i=0
  while [ ! -s "$H6_DIR/ports" ] && [ "$i" -lt 100 ]; do "$REAL_SLEEP" 0.1; i=$((i + 1)); done   # readiness poll on the port file (bounded, no fixed sleep)
  [ -s "$H6_DIR/ports" ] || { H6_SETUP_WHY="the local listeners did not come up: $(head -c 300 "$H6_DIR/server.log")"; return 1; }
  while IFS='|' read -r label prof lis ca; do
    port="$(awk -v k="$lis" '$1 == k {print $2}' "$H6_DIR/ports")"
    [ -n "$port" ] || { H6_SETUP_WHY="no port for listener $lis"; return 1; }
    rm -f "$H6_DIR/$label.out" "$H6_DIR/$label.rc" "$H6_DIR/$label.err" "$H6_DIR/$label.log"
    (
      unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy NO_PROXY no_proxy SENTRY_INGEST_DOMAIN SENTRY_PROJECT_ID SENTRY_PUBLIC_KEY
      export PATH="$H6_DIR/bin:$PATH" H6_OUT_PREFIX="$H6_DIR/$label"
      LOG_TAG=ci-deploy
      # shellcheck disable=SC1090
      source "$BLOCK_REAL" || exit 99
      # shellcheck disable=SC2034
      INNGEST_LINK_HTTPS_URL="https://127.0.0.1:$port"   # overridden AFTER sourcing: the block fixes it to the production address
      INNGEST_LINK_SELFGATE_ATTEMPTS=1
      _inngest_link_selfgate "$FX/$ca"
    ) > "$H6_DIR/$label.stdout" 2>&1
  done <<< "$H6_SCENARIOS"
  return 0
}
if h6_tools_ok; then
  h6_setup_rc=0; h6_setup || h6_setup_rc=$?
  if [ "$h6_setup_rc" -ne 0 ]; then
    for _i in $(seq 1 "$H6_N"); do ROWS=$((ROWS + 1)); bad "H6 the real-curl harness failed to start: $H6_SETUP_WHY"; done
  else
    while IFS='|' read -r h6_label h6_prof h6_lis _; do
      ROWS=$((ROWS + 1))
      if h6_compare "$h6_label" "$h6_prof"; then ok "H6 real curl against a local listener ($h6_lis): profile $h6_prof matches (rc class, code, zero-ness of the times, verify, and the phase the real self-gate emits)"; else bad "H6 $h6_lis vs profile $h6_prof: $H6_WHY"; fi
    done <<< "$H6_SCENARIOS"
    # H9: the same comparison against a copy of the profile file with ONE value flipped must go RED, once per column (rc, http_code,
    # time_connect, time_appconnect, ssl_verify_result), each taken from a profile of the six real-curl scenarios; the pristine comparison must
    # be GREEN first (a comparison that is red for every profile proves nothing about the flip). A flipped copy is run against the real
    # self-gate's recorded output, so a comparator arm that is neutered shows as a flip that stays GREEN.
    h9_pristine_why=""; h6_all || h9_pristine_why="$H6_ALL_WHY"
    h9_flip() { # <column> <from line> <to line>
      local col="$1" from="$2" to="$3" copy="$WORK/curl-w-profiles.flip-$1.sh"
      ROWS=$((ROWS + 1))
      awk -v f="$from" -v t="$to" '$0 == f { print t; next } { print }' "$CURLW_FIXTURE" > "$copy"
      if [ "$(grep -cxF -- "$from" "$CURLW_FIXTURE" || true)" != 1 ] || cmp -s "$CURLW_FIXTURE" "$copy"; then
        bad "H9 the $col flip did not land in the copy (the profile line [$from] is not in the table exactly once)"
      elif [ -n "$h9_pristine_why" ]; then
        bad "H9 precondition ($col): the pristine real-curl comparison is not GREEN ($h9_pristine_why)"
      elif ( CURL_W_PROFILES_FILE="$copy"; export CURL_W_PROFILES_FILE; h6_all ); then
        bad "H9 the real-curl comparison stayed GREEN against a profile file with the $col column flipped (a drifting $col is not detected)"
      else
        ok "H9 the real-curl comparison goes RED against a profile file with the $col column flipped (and is GREEN against the real one)"
      fi
    }
    h9_flip rc 'hs_close|35|000|0.000198|0.000000|1' 'hs_close|56|000|0.000198|0.000000|1'
    h9_flip http_code 'status502|0|502|0.000235|0.010363|0' 'status502|0|200|0.000235|0.010363|0'
    h9_flip time_connect 'hs_close|35|000|0.000198|0.000000|1' 'hs_close|35|000|0.000000|0.000000|1'
    h9_flip time_appconnect 'req_empty|52|000|0.000125|0.008238|0' 'req_empty|52|000|0.000125|0.000000|0'
    h9_flip ssl_verify_result 'verify18|60|000|0.000119|0.000000|18' 'verify18|60|000|0.000119|0.000000|1'
  fi
  if [ -n "$H6_PID" ]; then kill "$H6_PID" 2>/dev/null; wait "$H6_PID" 2>/dev/null; H6_PID=""; fi   # cleared: the EXIT trap must not signal a reaped (reusable) PID
elif [ -n "${CI:-}" ]; then
  for _i in $(seq 1 "$H6_N"); do ROWS=$((ROWS + 1)); bad "H6 curl, python3 or openssl is missing under CI: the real-curl differential is mandatory there"; done
else
  ROWS=$((ROWS + H6_N)); SKIP=$((SKIP + H6_N)); printf '[skip] H6/H9 curl, python3 or openssl is not installed: the real-curl differential did not run (a failure under CI)\n'
fi
rm -f "$CURLW_SENTINEL"

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
elif [[ "$url_n" != 1 ]]; then
EOA
)"
ANCH_B2="$(cat <<'EOA'
elif [[ "$https_n" != 1 ]]; then
EOA
)"
ANCH_B3="$(cat <<'EOA'
elif [[ "$ca_n" != 1 ]]; then
EOA
)"
kill_mut M13b1-inspect-single-url-line-unchecked "E3_canary_inspect_must_show_https" "$ANCH_B1" 'elif [[ "x" == "y" ]]; then'
kill_mut M13b2-inspect-https-value-unchecked "E3_canary_inspect_must_show_https" "$ANCH_B2" 'elif [[ "x" == "y" ]]; then'
kill_mut M13b3-inspect-ca-env-unchecked "E3_canary_inspect_must_show_https" "$ANCH_B3" 'elif [[ "x" == "y" ]]; then'
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
  'out="$(timeout 20 curl --disable --noproxy' 'out="$(timeout 20 curl --noproxy'
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

# the canary inspect check names the first failing condition (#10136): each edit below must redden the named rows
kill_mut M20a-inspect-failed-branch-dropped "E3_canary_inspect_must_show_https E7_canary_event_carries_check_and_cause" \
  'if [[ "$irc" -ne 0 || -z "$envs" ]]; then' 'if false; then'
kill_mut M20b-url-count-and-url-value-swapped "E3_canary_inspect_must_show_https E7_canary_event_carries_check_and_cause" \
  '  elif [[ "$url_n" != 1 ]]; then why="inspect"; cause="url_count"
  elif [[ "$https_n" != 1 ]]; then why="inspect"; cause="url_value"' \
  '  elif [[ "$https_n" != 1 ]]; then why="inspect"; cause="url_value"
  elif [[ "$url_n" != 1 ]]; then why="inspect"; cause="url_count"'
kill_mut M20c-ca-count-measured-by-exact-value "E3_canary_inspect_must_show_https E7_canary_event_carries_check_and_cause L8_scrub_names_match_the_tuple_census_and_the_canary_counts" \
  "ca_n=\"\$(printf '%s\\n' \"\$envs\" | grep -c '^NODE_EXTRA_CA_CERTS=')\"" \
  "ca_n=\"\$(printf '%s\\n' \"\$envs\" | grep -cxF 'NODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem')\""
kill_mut M20d-url-last-wins "E3_canary_inspect_must_show_https" \
  "url_n=\"\$(printf '%s\\n' \"\$envs\" | grep -c '^INNGEST_BASE_URL=')\"" \
  "url_n=\"\$(printf '%s\\n' \"\$envs\" | grep '^INNGEST_BASE_URL=' | tail -1 | grep -c .)\""
kill_mut M20e-event-loses-the-counts "E7_canary_event_carries_check_and_cause" \
  'cause=$cause url_lines=$url_n url_https=$https_n ca_lines=$ca_n ca_ok=$ca_ok"' 'cause=$cause"'
kill_mut M20f-inspect-never-runs "E3_canary_inspect_must_show_https E7_canary_event_carries_check_and_cause" \
  "envs=\"\$(docker inspect --format" "return 0; envs=\"\$(docker inspect --format"
kill_mut M20g-inspect-reason-not-split "E3_canary_inspect_must_show_https" \
  'CANARY_FAIL_REASON="canary_inngest_link_inspect_failed"' 'CANARY_FAIL_REASON="canary_inngest_link_failed"'

kill_mut M20h-url-count-unanchored "E8_canary_counts_only_the_exact_names" \
  "url_n=\"\$(printf '%s\\n' \"\$envs\" | grep -c '^INNGEST_BASE_URL=')\"" \
  "url_n=\"\$(printf '%s\\n' \"\$envs\" | grep -c 'INNGEST_BASE_URL=')\""
kill_mut M20i-https-value-by-prefix "E7_canary_event_carries_check_and_cause" \
  'grep -cxF "INNGEST_BASE_URL=$INNGEST_LINK_HTTPS_URL")' 'grep -cF "INNGEST_BASE_URL=$INNGEST_LINK_HTTPS_URL")'
kill_mut M20j-ca-value-by-prefix "E7_canary_event_carries_check_and_cause" \
  "grep -cxF 'NODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem')" "grep -cF 'NODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem')"
kill_mut M20k-ca-checks-before-the-url-value "E7_canary_event_carries_check_and_cause" \
  '  elif [[ "$https_n" != 1 ]]; then why="inspect"; cause="url_value"
  elif [[ "$ca_n" != 1 ]]; then why="inspect"; cause="ca_count"' \
  '  elif [[ "$ca_n" != 1 ]]; then why="inspect"; cause="ca_count"
  elif [[ "$https_n" != 1 ]]; then why="inspect"; cause="url_value"'
kill_mut M20l-count-clamp-moved-to-three-digits "E7_canary_event_carries_check_and_cause" \
  'if [[ "${#s}" -gt 2 ]]; then printf '"'"'99'"'"'' 'if [[ "${#s}" -gt 3 ]]; then printf '"'"'99'"'"''
kill_mut M20m-count-clamp-moved-to-one-digit "E7_canary_event_carries_check_and_cause" \
  'if [[ "${#s}" -gt 2 ]]; then printf '"'"'99'"'"'' 'if [[ "${#s}" -gt 1 ]]; then printf '"'"'99'"'"''

# the env-file scrub (#10136): each edit below must redden the named rows
kill_mut M21a-second-pinned-name-dropped-from-the-regex "L1_scrub_removes_pinned_names_and_keeps_the_rest L8_scrub_names_match_the_tuple_census_and_the_canary_counts" \
  '(INNGEST_BASE_URL|NODE_EXTRA_CA_CERTS)' '(INNGEST_BASE_URL)'
kill_mut M21b-bare-name-and-padded-name-not-matched "L1_scrub_removes_pinned_names_and_keeps_the_rest" \
  '([^A-Za-z0-9_.-]|$)' '(=)'
kill_mut M21c-recount-removed "L4_scrub_recount_failure_leaves_the_file_untouched" \
  'if [[ "$left" -ne 0 ]]; then' 'if false; then'
kill_mut M21d-conservation-removed "L5_scrub_conservation_failure_leaves_the_file_untouched" \
  'if [[ $((kept + n)) -ne "$total" ]]; then' 'if false; then'
kill_mut M21e-grep-rc-1-treated-as-error "L6_scrub_all_lines_matching_yields_an_empty_file" \
  'if [[ "$rc" -gt 1 ]]; then _inngest_link_scrub_fail write; return 1; fi' 'if [[ "$rc" -gt 0 ]]; then _inngest_link_scrub_fail write; return 1; fi'
kill_mut M21f-grep-without-binary-as-text "L1_scrub_removes_pinned_names_and_keeps_the_rest" \
  'LC_ALL=C grep -a -v -E' 'LC_ALL=C grep -v -E'
kill_mut M21g-regex-terminator-dropped "L1_scrub_removes_pinned_names_and_keeps_the_rest" \
  "(INNGEST_BASE_URL|NODE_EXTRA_CA_CERTS)([^A-Za-z0-9_.-]|\$)'" "(INNGEST_BASE_URL|NODE_EXTRA_CA_CERTS)'"
kill_mut M21h-dot-and-dash-treated-as-terminators "L1_scrub_removes_pinned_names_and_keeps_the_rest" \
  '([^A-Za-z0-9_.-]|$)' '([^A-Za-z0-9_]|$)'
kill_mut M21j-no-binary-as-text-on-the-first-count "L1_scrub_removes_pinned_names_and_keeps_the_rest" \
  'n="$(LC_ALL=C grep -a -c -E' 'n="$(LC_ALL=C grep -c -E'
kill_mut M21i-no-c-locale-on-the-write "L7_scrub_holds_under_a_utf8_locale" \
  'LC_ALL=C grep -a -v -E' 'grep -a -v -E'

# ---------------------------------------------------------------------------------------
# #10934: the self-gate's phase derivation and event (Guard Contract, mutation matrix M22a-M22t). Rows M22a to M22c, M22j and M22m are derived
# from the design (the seven-token map, the order of attempts, the verdict), not from the code's current shape.
#
# Every row is proven in THREE steps by kill_mut_sg: (1) the named rows are GREEN on the pristine block (the PRISTINE snapshot of the first run),
# (2) the mutation kills them (kill_mut), (3) every anchor occurs EXACTLY ONCE inside the `_inngest_link_selfgate*` text AND once in the whole
# block (the block also holds canary code with similar tokens; mut_block edits the first occurrence). An anchor that is absent or repeated
# is reported as its own [FAIL], never as a kill.
#
# The anchors are literal text of `_inngest_link_time_nonzero`, `_inngest_link_selfgate_phase` and the attempt loop of `_inngest_link_selfgate`
# in ci-deploy.sh (read those three, not a copy of them here); when the production text changes, move the anchor, not the row. The timers are
# interpreted in ONE place (_inngest_link_time_nonzero: rc 0 non-zero, 1 zero, 2 not a number), so the zero-test mutants edit the helper AND
# the counters' call site, and a mutant that gives the counters a private dot-only copy proves the two cannot drift unseen (row S6b).
# ---------------------------------------------------------------------------------------
SG_TEXT="$WORK/selfgate.text"
sed -n -e '/^_inngest_link_time_nonzero()/,/^}/p' -e '/^_inngest_link_selfgate/,/^}/p' "$BLOCK_REAL" > "$SG_TEXT"
sg_anchor_count() { # <file> <anchor>: how many times the anchor occurs in the file
  python3 -I - "$1" "$2" <<'PY'
import sys
print(open(sys.argv[1]).read().count(sys.argv[2]))
PY
}
kill_mut_sg() { # <mutation id> "<row id> ..." <old> <new> [<old> <new>]...   (kill_mut plus the pristine-green and anchor-unique steps)
  # SG_ANCHOR_FILE=<file> (default: the self-gate text) names the text each anchor must occur in exactly once besides the whole block: a mutant
  # of code OUTSIDE the `_inngest_link_*` self-gate functions (the reset at the top of resolve_inngest_link) passes SG_ANCHOR_FILE="$BLOCK_REAL".
  local mid="$1" rows="$2" id i a n_sg n_blk why="" af="${SG_ANCHOR_FILE:-$SG_TEXT}"
  shift 2
  for ((i = 1; i <= $#; i += 2)); do
    a="${!i}"
    n_sg="$(sg_anchor_count "$af" "$a")"; n_blk="$(sg_anchor_count "$BLOCK_REAL" "$a")"
    if [ "$n_sg" != 1 ] || [ "$n_blk" != 1 ]; then why="the anchor [${a:0:70}] occurs $n_sg time(s) in the self-gate text and $n_blk in the block, want exactly 1 in both"; break; fi
  done
  if [ -z "$why" ]; then for id in $rows; do if [ "${PRISTINE[$id]:-1}" != 0 ]; then why="named row $id is not GREEN on the pristine block"; break; fi; done; fi
  if [ -n "$why" ]; then ROWS=$((ROWS + 1)); bad "mutation $mid: $why"; return 0; fi
  kill_mut "$mid" "$rows" "$@"
}
A_RC77='if [[ "$rc" == 77 ]]; then printf ca_file; return 0; fi'
A_RC60='if [[ "$rc" == 60 ]]; then printf verify; return 0; fi'
A_STATUS='if [[ "$code" =~ $c3 && "$code" != 000 && "$code" != 200 ]]; then printf status; return 0; fi'
A_SHAPE='if [[ "$tcr" -eq 2 || "$tar" -eq 2 ]]; then printf unknown; return 0; fi'
A_UNK124='if [[ "$rc" == 124 || -z "$code$tc$ta" ]]; then printf unknown; return 0; fi'
A_CONNECT='if [[ "$tcr" -eq 1 ]]; then printf connect; return 0; fi'
A_VERDICT='if [[ "$rc" -eq 0 && "$code" == 200 ]]; then return 0; fi'
A_STATUS_TAIL=' && "$code" != 200 ]]; then printf status'
kill_mut_sg M22a-appconnect-zero-tested-before-the-verify-arm "S2_handshake_and_verify" \
  "$A_RC60" "_inngest_link_time_nonzero \"\$ta\" || tar=\$?; if [[ \"\$tar\" -eq 1 ]]; then printf handshake; return 0; fi; $A_RC60"
kill_mut_sg M22b-connect-zero-test-dropped "S1_connect_and_ca_file" "$A_CONNECT" ':'
kill_mut_sg M22c-status-branch-dropped "S3_request_and_status" "$A_STATUS" ':'
kill_mut_sg M22d-unparsable-arm-defaults-to-request "S6_unknown_arms_and_validated_values" \
  "$A_SHAPE" 'if [[ "$tcr" -eq 2 || "$tar" -eq 2 ]]; then printf request; return 0; fi'
kill_mut_sg M22e-rc124-and-empty-output-arm-dropped "S6_unknown_arms_and_validated_values" "$A_UNK124" ':'
kill_mut_sg M22f-time-shape-check-dropped "S6_unknown_arms_and_validated_values" "$A_SHAPE" ':'
kill_mut_sg M22g-rc77-arm-dropped "S1_connect_and_ca_file" "$A_RC77" ':'
kill_mut_sg M22h-rc60-arm-dropped "S2_handshake_and_verify" "$A_RC60" ':'
kill_mut_sg M22i-time-zero-tests-inverted "S1_connect_and_ca_file S2_handshake_and_verify S3_request_and_status" \
  'if [[ "$tcr" -eq 1 ]]; then printf connect' 'if [[ "$tcr" -ne 1 ]]; then printf connect' \
  'if [[ "$tar" -eq 1 ]]; then printf handshake' 'if [[ "$tar" -ne 1 ]]; then printf handshake'
kill_mut_sg M22j-phase-taken-from-the-first-attempt "S4_sequence_counts_and_last_phase" \
  'phase="$(_inngest_link_selfgate_phase "$rc" "$code" "$tc" "$ta")"' 'if [[ "$i" -eq 1 ]]; then phase="$(_inngest_link_selfgate_phase "$rc" "$code" "$tc" "$ta")"; fi'
kill_mut_sg M22k-tls-counter-counts-tcp "S4_sequence_counts_and_last_phase" \
  'if _inngest_link_time_nonzero "$ta"; then tlsn=$((tlsn + 1)); fi' 'if _inngest_link_time_nonzero "$tc"; then tlsn=$((tlsn + 1)); fi'
kill_mut_sg M22l-counter-clamp-removed "S4b_counters_clamp" \
  'tcp=$(_inngest_link_count99 "$tcpn") tls=$(_inngest_link_count99 "$tlsn")' 'tcp=$tcpn tls=$tlsn'
kill_mut_sg M22m-success-decided-on-the-whole-output "A2_flag_on_https S8_noncanonical_input_and_success_first" \
  "$A_VERDICT" 'if [[ "$rc" -eq 0 && "$out" == 200 ]]; then return 0; fi'
kill_mut_sg M22n-success-gated-on-the-full-shape-check "S8_noncanonical_input_and_success_first" \
  "$A_VERDICT" 'if [[ "$rc" -eq 0 && "$code" == 200 && "$tc" =~ $num && "$ta" =~ $num && "$ver" =~ ^[0-9]+$ ]]; then return 0; fi'
kill_mut_sg M22o-event-appends-the-url "S5_event_grammar_on_both_sinks" \
  'verify=$vv"' 'verify=$vv url=$INNGEST_LINK_HTTPS_URL"'
kill_mut_sg M22p-request-arm-keyed-on-the-exit-code "S3b_same_times_any_rc_reads_request" \
  'printf request' 'case "$rc" in 52 | 28) printf request ;; *) printf unknown ;; esac'
kill_mut_sg M22q-verify-printed-raw "S2_handshake_and_verify" \
  'verify=$vv"' 'verify=$(_inngest_link_count99 "$ver")"'
kill_mut_sg M22r-http-printed-from-the-raw-token "S6_unknown_arms_and_validated_values" \
  'http=$http attempts=$i' 'http=${code:-none} attempts=$i'
kill_mut_sg M22s-status-for-any-code-but-000 "S3_request_and_status" \
  "$A_STATUS_TAIL" ' ]]; then printf status'
kill_mut_sg M22t-status-gated-on-a-zero-exit-code "S3_request_and_status" \
  "$A_STATUS_TAIL" ' && "$code" != 200 && "$rc" == 0 ]]; then printf status'
# the pass verdict (rc 0 AND exactly the code 200) and the curl argv, #10934 review round 1
kill_mut_sg M22u-success-on-any-2xx-code "S10_pass_verdict_is_exactly_rc0_and_http_200_through_the_pinned_file" \
  "$A_VERDICT" 'if [[ "$rc" -eq 0 && "$code" == 2* ]]; then return 0; fi'
kill_mut_sg M22v-success-on-a-200-prefix "S10_pass_verdict_is_exactly_rc0_and_http_200_through_the_pinned_file" \
  "$A_VERDICT" 'if [[ "$rc" -eq 0 && "$code" == 200* ]]; then return 0; fi'
kill_mut_sg M22w-success-ignores-the-exit-code "S3_request_and_status" \
  "$A_VERDICT" 'if [[ "$code" == 200 ]]; then return 0; fi'
kill_mut_sg M22x-selfgate-curl-timers-dropped "S10_pass_verdict_is_exactly_rc0_and_http_200_through_the_pinned_file" \
  '--connect-timeout 5 --max-time 10' ''
# per-attempt state, the verification-result sanitiser, the one zero test, the IFS-independent parse, the sinks
kill_mut_sg M22y-verify-result-not-sanitised "S6_unknown_arms_and_validated_values" \
  'vv="$(_inngest_link_count99 "${ver%% *}")"' 'vv="${ver%% *}"'
kill_mut_sg M22z-verify-not-reset-per-attempt "S4c_verify_does_not_outlive_its_attempt" \
  $'    vv=0\n    if [[ "$phase" == verify ]]' '    if [[ "$phase" == verify ]]'
kill_mut_sg M22aa-http-not-reset-per-attempt "S4d_http_does_not_outlive_its_attempt" \
  $'    http=none\n    if [[ "$code" =~ $c3 ]]; then http="$code"; fi' '    if [[ "$code" =~ $c3 ]]; then http="$code"; fi'
kill_mut_sg M22ab-tcp-counter-keeps-a-private-dot-only-zero-test "S6b_comma_decimal_zero_is_zero" \
  'if _inngest_link_time_nonzero "$tc"; then tcpn=$((tcpn + 1)); fi' 'if [[ "$tc" =~ ^[0-9]+[.,][0-9]+$ && ! "$tc" =~ ^[0.]*$ ]]; then tcpn=$((tcpn + 1)); fi'
kill_mut_sg M22ac-shared-zero-test-is-dot-only "S6b_comma_decimal_zero_is_zero" \
  "local t=\"\${1-}\" num='^[0-9]+[.,][0-9]+\$' zero='^[0.,]*\$'" "local t=\"\${1-}\" num='^[0-9]+[.,][0-9]+\$' zero='^[0.]*\$'"
kill_mut_sg M22ad-shared-zero-test-dropped "S1_connect_and_ca_file" \
  'if [[ "$t" =~ $zero ]]; then return 1; fi' ':'
kill_mut_sg M22ae-w-line-split-on-the-callers-ifs "S12_the_w_line_parse_does_not_depend_on_the_callers_ifs" \
  "IFS=' ' read -r code tc ta ver" 'read -r code tc ta ver'
kill_mut_sg M22af-failure-tail-logs-the-raw-output "S11_one_event_on_every_sink_and_no_raw_output" \
  $'verify=$vv"\n  return 1' $'verify=$vv"\n  logger -t "$LOG_TAG" "INNGEST_LINK: raw=$out"\n  return 1'
# review round 2 (#10934): the phase belongs to ONE resolve, the event carries no URL on any sink, one unreadable timer reads unknown
kill_mut_sg M23a-phase-assigned-inside-the-attempt-loop "S13_the_phase_belongs_to_one_resolve_and_is_never_left_over" \
  'phase="$(_inngest_link_selfgate_phase "$rc" "$code" "$tc" "$ta")"' 'phase="$(_inngest_link_selfgate_phase "$rc" "$code" "$tc" "$ta")"; INNGEST_LINK_SELFGATE_PHASE="$phase"'
SG_ANCHOR_FILE="$BLOCK_REAL" kill_mut_sg M23b-reset-at-the-top-of-the-resolver-deleted "S13_the_phase_belongs_to_one_resolve_and_is_never_left_over" \
  'INNGEST_LINK_SELFGATE_PHASE=""' ':'
kill_mut_sg M23c-failure-tail-logs-a-second-line-carrying-the-url "S11_one_event_on_every_sink_and_no_raw_output" \
  $'verify=$vv"\n  return 1' $'verify=$vv"\n  logger -t "$LOG_TAG" "INNGEST_LINK: class=selfgate_trace level=info target=$INNGEST_LINK_HTTPS_URL"\n  return 1'
kill_mut_sg M23d-failure-tail-prints-a-line-carrying-the-url-on-stdout "S11_one_event_on_every_sink_and_no_raw_output" \
  $'verify=$vv"\n  return 1' $'verify=$vv"\n  printf \'INNGEST_LINK: class=selfgate_trace target=%s\\n\' "$INNGEST_LINK_HTTPS_URL"\n  return 1'
kill_mut_sg M23e-unreadable-timer-arm-tests-only-appconnect "S6c_one_unreadable_timer_beside_a_readable_one_reads_unknown" \
  "$A_SHAPE" 'if [[ "$tar" -eq 2 ]]; then printf unknown; return 0; fi'


# ---------------------------------------------------------------------------------------
# LEDGER
# ---------------------------------------------------------------------------------------
printf '\n=== inngest-link-resolver: %d passed, %d failed, %d skipped (%d rows) ===\n' "$PASS" "$FAIL" "$SKIP" "$ROWS"
# The anti-vacuity floor comes FIRST: scripts/guard-vacuity-floor.test.sh neuters every counter and runs the first floor it
# finds, which must be this one (the accounting identity below holds trivially at zero).
# #10934: 203 -> 249 (+46: S1 to S9b = 14 rows, H1b, H8, H7a to H7c, H6 x6, H9 = 12, M22a to M22t = 20), measured from the RED run on the unmodified block;
# re-measured from the GREEN run after the fix: 249 rows ran (252 passes, 0 failures, 0 skips; the H6 harness row was changed, no row was added)
# review round 1 (#10934): 249 -> 271 (+22: S4c, S4d, S6b, S10, S11, S12 = 6 rows; H9 one row -> five column flips = +4; M22u to M22af = 12 mutants), measured from the GREEN run
# review round 2 (#10934): 271 -> 278 (+7: S6c, S13 = 2 rows; M23a to M23e = 5 mutants), measured from the GREEN run
MIN_ROWS=278
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
