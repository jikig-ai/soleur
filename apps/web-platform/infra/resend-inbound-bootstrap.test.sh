#!/usr/bin/env bash
set -euo pipefail

# Tests for resend-inbound-bootstrap.sh (#7898 §2 — Guard 3: key shape + path
# allowlist + argv-position transport confinement on the `--config` channel).
#
# The bootstrap is a laptop one-shot run under `doppler run -c prd`, so the
# whole suite runs under `env -i` with a FAKE key by construction: no inherited
# credential can reach the script. The curl shim asserts on its `--config` fd
# IN-PROCESS and writes only PASS/FAIL-shaped counts, so the key — fake or
# otherwise — is never written to a log or artifact.
#
# Rows:
#   (a) key with an embedded newline → exit 2, reason=key-shape on stderr, shim
#       never invoked (the measured curl config-directive injection vector);
#       plus the must-PASS complement: a well-formed fake key clears the check
#       and the shim IS invoked.
#   (b) resend_api with a traversal / authority-smuggling path → exit 2,
#       reason=path-shape on STDERR (stdout is swallowed by `$( … )` at every
#       call site).
#   (c) well-formed GET/PATCH → argv[1..6] are the four transport flags and the
#       --config fd holds exactly one `header =` line and zero `url =` lines.
#   (d) `bash -x` → exit 78, HALT marker on stdout, no curl and no doppler run.
#   (e) no call site wraps `$(resend_api …)` in if/||/&& (a wrapper would
#       swallow the in-function `exit 2`).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/resend-inbound-bootstrap.sh"

PASS=0
FAIL=0
TOTAL=0

# One owning EXIT trap for every tempdir this suite allocates (ADR-129 / #6734):
# per-test `mktemp -d` calls land under a suite-owned scratch dir via TMPDIR, so
# a suite that dies between allocation and its own `rm -rf` leaks nothing. The
# trap runs once, in this shell — a `$( … )` test subshell does not inherit it.
SUITE_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/resend-inbound-bootstrap-test.XXXXXX")"
export TMPDIR="$SUITE_SCRATCH"
trap 'rm -rf "$SUITE_SCRATCH"' EXIT

FAKE_KEY="re_test_fake_key_123"

# Shim dir: curl (records argv positions + validates the --config fd
# in-process), doppler (no-op, satisfies the precondition loop), jq/bash and the
# coreutils the script needs, resolved from the inherited PATH so `env -i` still
# finds them.
make_shims() {
  local d="$1"
  mkdir -p "$d/bin"
  cat > "$d/bin/curl" << 'MOCK'
#!/bin/bash
# Records argv[1..6] and the SHAPE of the --config fd (counts only; the fd
# carries the Authorization header and must never be echoed).
out="${CURL_SHIM_OUT:?}"
printf 'argv1_6=%s|%s|%s|%s|%s|%s\n' "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" >> "$out"
# --noproxy cardinality (a later `--noproxy ''` silently supersedes the first)
# and the TLS-env canary the script's unset prologue must have cleared.
n=0; for a in "$@"; do [[ "$a" == "--noproxy" ]] && n=$((n + 1)); done
[[ "$n" -eq 1 ]] || printf 'violation NOPROXY_COUNT n=%s\n' "$n" >> "$out"
[[ -z "${SSLKEYLOGFILE:-}${CURL_CA_BUNDLE:-}" ]] || printf 'violation TLS_ENV_LEAK\n' >> "$out"
cfg=""; prev=""
for a in "$@"; do
  if [[ "$prev" == "--config" ]]; then cfg="$a"; fi
  prev="$a"
done
if [[ -n "$cfg" ]]; then
  cfg_text="$(cat "$cfg")"
  h=$(grep -c '^header = ' <<<"$cfg_text" || true)
  u=$(grep -c '^url = ' <<<"$cfg_text" || true)
  printf 'config header_lines=%s url_lines=%s\n' "$h" "$u" >> "$out"
fi
echo '{"data":[]}'
exit 0
MOCK
  cat > "$d/bin/doppler" << MOCK
#!/bin/bash
echo "doppler \$*" >> "$d/doppler_args"
exit 0
MOCK
  chmod +x "$d/bin/curl" "$d/bin/doppler"
  local bin real
  for bin in bash jq sed grep cat head tail column tr wc printf env; do
    real="$(command -v "$bin" 2>/dev/null || true)"
    [[ -n "$real" && ! -e "$d/bin/$bin" ]] && ln -sf "$real" "$d/bin/$bin"
  done
  echo "$d/bin"
}

# Run the WHOLE script under env -i with the given key. Args: dir key [bash-flags…]
run_script() {
  local d="$1" key="$2"; shift 2
  env -i PATH="$d/bin" CURL_SHIM_OUT="$d/curl_out" RESEND_API_KEY="$key" HOME="$d" \
    SSLKEYLOGFILE="$d/keys.log" CURL_CA_BUNDLE="$d/ca.pem" \
    bash "$@" "$SCRIPT"
}

# Extract `emit_refusal()` + `resend_api()` from the script (the function under
# test, not a re-declared copy) and call resend_api with the given args.
run_resend_api() {
  local d="$1"; shift
  local driver="$d/driver.sh"
  {
    echo 'set -euo pipefail'
    echo 'RESEND_API="https://api.resend.com"'
    sed -n '/^emit_refusal()/,/^}/p' "$SCRIPT"
    sed -n '/^resend_api()/,/^}/p' "$SCRIPT"
    printf 'resend_api'
    printf ' %q' "$@"
    printf '\n'
  } > "$driver"
  env -i PATH="$d/bin" CURL_SHIM_OUT="$d/curl_out" RESEND_API_KEY="$FAKE_KEY" HOME="$d" \
    bash "$driver"
}

echo "=== resend-inbound-bootstrap.sh tests (#7898 §2) ==="
echo ""

# (a) key shape
test_key_shape() {
  TOTAL=$((TOTAL + 1))
  local description="key with an embedded curl directive is refused (exit 2, reason=key-shape, no curl); a well-formed key is accepted"
  local d; d=$(mktemp -d); make_shims "$d" >/dev/null
  local err rc ok=1
  err=$(run_script "$d" $'re_x\nurl = "https://127.0.0.1:9/exfil"' 2>&1 >/dev/null) && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || ok=0
  printf '%s\n' "$err" | grep -qF "SOLEUR_RESEND_INBOUND_BOOTSTRAP_REFUSED channel=resend reason=key-shape" || ok=0
  [[ ! -f "$d/curl_out" ]] || ok=0
  # must-PASS complement: a well-formed fake key clears the check (the script
  # then proceeds until the shim's empty domain list makes step 1 fail — exit
  # 1, NOT the key-shape exit 2) and the shim was invoked — including a key
  # carrying `-`, which the class admits on purpose (rotation-breakage risk).
  local err2 rc2 k
  for k in "$FAKE_KEY" "re_ok-123"; do
    rm -f "$d/curl_out"
    err2=$(run_script "$d" "$k" 2>&1 >/dev/null) && rc2=0 || rc2=$?
    [[ "$rc2" -ne 2 ]] || ok=0
    printf '%s\n' "$err2" | grep -qF "reason=key-shape" && ok=0
    [[ -f "$d/curl_out" ]] || ok=0
    grep -q '^violation' "$d/curl_out" 2>/dev/null && ok=0   # unset prologue cleared the TLS canary
  done
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS + 1)); echo "  PASS: $description"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $description (rc=$rc rc2=$rc2)"; echo "        stderr: $err"; echo "        stderr2: $err2"; fi
  rm -rf "$d"
}
test_key_shape

# (b) path allowlist
test_path_shape() {
  TOTAL=$((TOTAL + 1))
  local description="resend_api refuses traversal and authority-smuggling paths (exit 2, reason=path-shape on stderr, no curl)"
  local d; d=$(mktemp -d); make_shims "$d" >/dev/null
  local err rc ok=1 path
  for path in '/domains/../webhooks' '@evil.example/domains' '/domains?x=1' '/domains/abc/def'; do
    rm -f "$d/curl_out"
    err=$(run_resend_api "$d" GET "$path" 2>&1 >/dev/null) && rc=0 || rc=$?
    [[ "$rc" -eq 2 ]] || { ok=0; echo "        path '$path' rc=$rc"; }
    printf '%s\n' "$err" | grep -qF "SOLEUR_RESEND_INBOUND_BOOTSTRAP_REFUSED channel=resend reason=path-shape" || ok=0
    [[ ! -f "$d/curl_out" ]] || ok=0
  done
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS + 1)); echo "  PASS: $description"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $description (last rc=$rc)"; echo "        stderr: $err"; fi
  rm -rf "$d"
}
test_path_shape

# (c) argv position + --config fd shape on well-formed calls
test_confined_call() {
  TOTAL=$((TOTAL + 1))
  local description="GET/PATCH/POST + /webhooks/<id>: four transport flags first, one --noproxy, --config fd has one header line and zero url lines"
  local d; d=$(mktemp -d); make_shims "$d" >/dev/null
  local rc ok=1
  run_resend_api "$d" GET /domains/3f1a2b3c-4d5e-4f60-8a71-b2c3d4e5f607 >/dev/null 2>&1 && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || ok=0
  run_resend_api "$d" PATCH /domains/3f1a2b3c-4d5e-4f60-8a71-b2c3d4e5f607 '{"capabilities":{"receiving":"enabled"}}' >/dev/null 2>&1 && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || ok=0
  run_resend_api "$d" POST /webhooks '{"endpoint":"x","events":["email.received"]}' >/dev/null 2>&1 && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || ok=0
  # every in-file call-site shape must be a must-PASS: /webhooks/<id> is the
  # one the allowlist's second alternation exists for.
  run_resend_api "$d" GET /webhooks/3f1a2b3c-4d5e-4f60-8a71-b2c3d4e5f607 >/dev/null 2>&1 && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || ok=0
  [[ "$(grep -c '^argv1_6=--disable|--noproxy|\*|--proto|=https|-g$' "$d/curl_out" 2>/dev/null || true)" -eq 4 ]] || ok=0
  [[ "$(grep -c '^config header_lines=1 url_lines=0$' "$d/curl_out" 2>/dev/null || true)" -eq 4 ]] || ok=0
  grep -q '^violation' "$d/curl_out" 2>/dev/null && ok=0     # exactly one --noproxy, TLS canary cleared
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS + 1)); echo "  PASS: $description"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $description (rc=$rc)"; echo "        curl_out: $(cat "$d/curl_out" 2>/dev/null)"; fi
  rm -rf "$d"
}
test_confined_call

# (d) xtrace refusal before any credentialed action
test_xtrace_halt() {
  TOTAL=$((TOTAL + 1))
  local description="bash -x → exit 78, HALT marker on stdout, no curl and no doppler invoked"
  local d; d=$(mktemp -d); make_shims "$d" >/dev/null
  local out rc ok=1
  out=$(run_script "$d" "$FAKE_KEY" -x 2>/dev/null) && rc=0 || rc=$?
  [[ "$rc" -eq 78 ]] || ok=0
  printf '%s\n' "$out" | grep -qF "SOLEUR_RESEND_INBOUND_BOOTSTRAP_HALT reason=xtrace-credential-bound" || ok=0
  [[ ! -f "$d/curl_out" ]] || ok=0
  [[ ! -f "$d/doppler_args" ]] || ok=0
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS + 1)); echo "  PASS: $description"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $description (rc=$rc)"; echo "        stdout: $out"; fi
  rm -rf "$d"
}
test_xtrace_halt

# (e) every call site is a bare `var="$(resend_api …)"` — never inside if/||/&&
test_bare_call_sites() {
  TOTAL=$((TOTAL + 1))
  local description="no resend_api call site is wrapped in if/||/&& (a wrapper would swallow the in-function exit 2)"
  # Comment lines are stripped first: the function's own docstring names the
  # forbidden shapes, and a bare-token grep would count them (cq-assert-anchor-not-bare-token).
  # Both wrapper directions: an operator/keyword BEFORE the call (if/while/
  # until/!/case/local … $(resend_api) and a list operator AFTER it
  # (x="$(resend_api …)" || true), plus `set +e` anywhere in the file.
  local wrapped total sete
  wrapped=$(grep -vE '^[[:space:]]*#' "$SCRIPT" | grep -cE '(^[[:space:]]*(if|while|until|!|case|local|elif) .*\$\(resend_api|\|\|.*\$\(resend_api|&&.*\$\(resend_api|\$\(resend_api [^)]*\)"?[[:space:]]*(\|\||&&))' || true)
  sete=$(grep -vE '^[[:space:]]*#' "$SCRIPT" | grep -cE '^[[:space:]]*set [-+]*\+e' || true)
  total=$(grep -vE '^[[:space:]]*#' "$SCRIPT" | grep -cE '\$\(resend_api ' || true)
  if [[ "$wrapped" -eq 0 && "$sete" -eq 0 && "$total" -ge 8 ]]; then PASS=$((PASS + 1)); echo "  PASS: $description ($total bare call sites)"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $description (wrapped=$wrapped set+e=$sete total=$total)"; fi
}
test_bare_call_sites

# (f) static shape: no credentialed curl follows redirects (a custom header is
# forwarded cross-host on a 3xx) and none is path-qualified (a `/usr/bin/curl`
# bypasses the PATH shim and the Rule D CURL_INVOKE regex).
test_static_curl_shape() {
  TOTAL=$((TOTAL + 1))
  local description="no resend_api curl follows redirects and none is path-qualified"
  local redirects pathq
  redirects=$(grep -cE '^[[:space:]]*([A-Za-z_]+="?\$\()?curl .* (-L|--location)( |$)' "$SCRIPT" || true)
  pathq=$(grep -cE '(^|[[:space:]"(])/[A-Za-z0-9_./-]*/curl([[:space:]]|$)' "$SCRIPT" || true)
  if [[ "$redirects" -eq 0 && "$pathq" -eq 0 ]]; then PASS=$((PASS + 1)); echo "  PASS: $description"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $description (redirects=$redirects path-qualified=$pathq)"; fi
}
test_static_curl_shape

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
# Anti-vacuity floor (ADR-193): CI reads only the exit status, so a deleted
# row-dispatch line would vanish green. Reported directly, never through the
# PASS/FAIL accounting this backstops. Ratchet when adding rows.
if [[ "$TOTAL" -lt 6 ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d row(s) ran, expected >= 6. A row was deleted or its dispatch line removed.\n' "$TOTAL" >&2
  exit 1
fi
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
