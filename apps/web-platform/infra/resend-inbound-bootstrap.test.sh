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
  printf '%s\n' "$err" | grep -qF "SOLEUR_RESEND_INBOUND_BOOTSTRAP_REFUSED reason=key-shape" || ok=0
  [[ ! -f "$d/curl_out" ]] || ok=0
  # must-PASS complement: a well-formed fake key clears the check (the script
  # then proceeds until the shim's empty domain list makes step 1 fail — exit
  # 1, NOT the key-shape exit 2) and the shim was invoked.
  local err2 rc2
  err2=$(run_script "$d" "$FAKE_KEY" 2>&1 >/dev/null) && rc2=0 || rc2=$?
  [[ "$rc2" -ne 2 ]] || ok=0
  printf '%s\n' "$err2" | grep -qF "reason=key-shape" && ok=0
  [[ -f "$d/curl_out" ]] || ok=0
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
    printf '%s\n' "$err" | grep -qF "SOLEUR_RESEND_INBOUND_BOOTSTRAP_REFUSED reason=path-shape" || ok=0
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
  local description="GET/PATCH: four transport flags first; --config fd has one header line and zero url lines"
  local d; d=$(mktemp -d); make_shims "$d" >/dev/null
  local rc ok=1
  run_resend_api "$d" GET /domains/3f1a2b3c-4d5e-4f60-8a71-b2c3d4e5f607 >/dev/null 2>&1 && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || ok=0
  run_resend_api "$d" PATCH /domains/3f1a2b3c-4d5e-4f60-8a71-b2c3d4e5f607 '{"capabilities":{"receiving":"enabled"}}' >/dev/null 2>&1 && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || ok=0
  run_resend_api "$d" POST /webhooks '{"endpoint":"x","events":["email.received"]}' >/dev/null 2>&1 && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || ok=0
  [[ "$(grep -c '^argv1_6=--disable|--noproxy|\*|--proto|=https|-g$' "$d/curl_out" 2>/dev/null || true)" -eq 3 ]] || ok=0
  [[ "$(grep -c '^config header_lines=1 url_lines=0$' "$d/curl_out" 2>/dev/null || true)" -eq 3 ]] || ok=0
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
  local wrapped total
  wrapped=$(grep -cE '(^[[:space:]]*if |\|\||&&).*\$\(resend_api' "$SCRIPT" || true)
  total=$(grep -cE '\$\(resend_api ' "$SCRIPT" || true)
  if [[ "$wrapped" -eq 0 && "$total" -ge 8 ]]; then PASS=$((PASS + 1)); echo "  PASS: $description ($total bare call sites)"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $description (wrapped=$wrapped total=$total)"; fi
}
test_bare_call_sites

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
