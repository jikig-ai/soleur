#!/usr/bin/env bash
# Tests for _cf-admin-token.sh — shared Cloudflare admin-token verify +
# self-revoke helpers (issue #3950 item 3). PATH-shadows curl with a queued
# STATUS<space>BODY response stream, same convention as gdpr-override.test.sh
# (no bats — the suite convention is `.test.sh` with PATH-shadowed mocks).
# RED-first per cq-write-failing-tests-before.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/_cf-admin-token.sh"

red()    { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
# yellow is consumed only by the sourced helper (cf_token_self_revoke), so it
# looks unreachable from this file (SC2317).
# shellcheck disable=SC2317
yellow() { printf '\033[33m%s\033[0m\n' "$*" >&2; }

if [[ ! -r "$HELPER" ]]; then
  red "FAIL: $HELPER does not exist (RED phase expected output)."
  exit 1
fi
command -v jq >/dev/null || { red "FAIL: jq not on PATH"; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# PATH-shadow curl: emits the next queued `STATUS BODY` line (split on the FIRST
# space; status is always a 3-digit code with no spaces). 2xx → exit 0, else 22
# (mirrors curl -fsS on a 4xx/5xx). Records the HTTP method for assertions.
mk_curl_stub() {
  cat > "$work/curl" <<EOF
#!/usr/bin/env bash
queue="$work/curl.queue"
log="$work/curl.log"
argvlog="$work/curl.argv"
stdinlog="$work/curl.stdin"
method=GET
first="\${1:-}"
cfg=""
noproxy=0
printf '%s\n' "\$@" >> "\$argvlog"
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -X)         method="\$2"; shift 2 ;;
    -H)         shift 2 ;;
    --config)   cfg="\$2"; shift 2 ;;
    --noproxy)  noproxy=1; shift 2 ;;
    --max-time) shift 2 ;;
    -fsS|-fS|-s|-S|-f) shift ;;
    *)          shift ;;
  esac
done
# The bearer must arrive as a curl config on stdin (--config -); record it.
if [[ "\$cfg" == "-" ]]; then cat >> "\$stdinlog"; fi
read -r line < "\$queue" || { echo "curl stub: queue empty" >&2; exit 99; }
sed -i '1d' "\$queue"
status="\${line%% *}"
body="\${line#* }"
printf 'method=%s first=%s noproxy=%s cfg=%s\n' "\$method" "\$first" "\$noproxy" "\$cfg" >> "\$log"
printf '%s' "\$body"
case "\$status" in 2*) exit 0 ;; *) exit 22 ;; esac
EOF
  chmod +x "$work/curl"
}

prime_queue() {
  : > "$work/curl.log"; : > "$work/curl.argv"; : > "$work/curl.stdin"
  printf '%s\n' "$@" > "$work/curl.queue"
}

# shellcheck source=/dev/null
source "$HELPER"

export PATH="$work:$PATH"
fail=0

# ── (a) verify active + id present → echoes id, exit 0 ──────────────────────
mk_curl_stub
prime_queue '200 {"result":{"status":"active","id":"tok-abc"}}'
if id=$(cf_token_verify "fake-bearer" 2>/dev/null); then
  if [[ "$id" == "tok-abc" ]]; then
    green "PASS: (a) cf_token_verify active+id → echoes id, exit 0"
  else
    red "FAIL: (a) expected id=tok-abc, got id=$id"; fail=1
  fi
else
  red "FAIL: (a) expected exit 0 on active+id"; fail=1
fi

# ── (b) status != active → non-zero ────────────────────────────────────────
mk_curl_stub
prime_queue '200 {"result":{"status":"disabled","id":"tok-abc"}}'
if id=$(cf_token_verify "fake-bearer" 2>/dev/null); then
  red "FAIL: (b) expected non-zero on status!=active (got id=$id)"; fail=1
else
  green "PASS: (b) cf_token_verify status!=active → non-zero (caller || branch fires)"
fi

# ── (c) empty id → non-zero (the bootstrap upgrade) ────────────────────────
mk_curl_stub
prime_queue '200 {"result":{"status":"active","id":""}}'
if id=$(cf_token_verify "fake-bearer" 2>/dev/null); then
  red "FAIL: (c) expected non-zero on empty id (got id=$id)"; fail=1
else
  green "PASS: (c) cf_token_verify empty id → non-zero (defensive upgrade)"
fi

# ── (d) self-revoke curl error → warn, exit 0 (best-effort) ────────────────
mk_curl_stub
prime_queue '500 '
out=$(cf_token_self_revoke "fake-bearer" "tok-abc" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && grep -qiE 'self-revoke failed' <<<"$out"; then
  green "PASS: (d) cf_token_self_revoke curl error → warn, exit 0"
else
  red "FAIL: (d) expected exit 0 + 'self-revoke failed' warn; got rc=$rc out=$out"; fail=1
fi

# ── (e) self-revoke empty id → warn, exit 0, NO curl call ──────────────────
mk_curl_stub
prime_queue '204 '
out=$(cf_token_self_revoke "fake-bearer" "" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] \
   && grep -qiE 'no admin-token id' <<<"$out" \
   && [[ ! -s "$work/curl.log" ]]; then
  green "PASS: (e) cf_token_self_revoke empty id → warn, exit 0, no curl call"
else
  red "FAIL: (e) expected exit 0 + 'no admin-token id' warn + 0 curl calls; got rc=$rc curl_calls=$(wc -l < "$work/curl.log" 2>/dev/null || echo NA)"; fail=1
fi

# ── (f) bearer travels on stdin, never argv; --disable first, --noproxy '*' ──
# A distinctive bearer so a leak into argv cannot hide behind a common substring.
mk_curl_stub
prime_queue '200 {"result":{"status":"active","id":"tok-abc"}}'
bearer_f="Zq9-synthetic_BEARER.f1"
if id=$(cf_token_verify "$bearer_f" 2>/dev/null) \
   && grep -qxF "header = \"Authorization: Bearer $bearer_f\"" "$work/curl.stdin" \
   && ! grep -qF "$bearer_f" "$work/curl.argv" \
   && ! grep -qiF 'Authorization' "$work/curl.argv" \
   && grep -q 'first=--disable noproxy=1 cfg=-' "$work/curl.log"; then
  green "PASS: (f) verify: bearer on stdin config, absent from argv; --disable first; --noproxy"
else
  red "FAIL: (f) verify bearer channel; log=$(cat "$work/curl.log")"; fail=1
fi

mk_curl_stub
prime_queue '200 {}'
if cf_token_self_revoke "$bearer_f" "tok-abc" >/dev/null 2>&1 \
   && grep -qxF "header = \"Authorization: Bearer $bearer_f\"" "$work/curl.stdin" \
   && ! grep -qF "$bearer_f" "$work/curl.argv" \
   && grep -q 'method=DELETE first=--disable noproxy=1 cfg=-' "$work/curl.log"; then
  green "PASS: (f2) self-revoke: bearer on stdin config, absent from argv; --disable first"
else
  red "FAIL: (f2) self-revoke bearer channel; log=$(cat "$work/curl.log")"; fail=1
fi

# ── (g) unusable bearer (newline / empty / space) → failure, ZERO curl calls ─
mk_curl_stub
for bad in $'abc\nurl = "http://evil.example/"' '' 'has space'; do
  prime_queue '200 {"result":{"status":"active","id":"tok-abc"}}'
  if id=$(cf_token_verify "$bad" 2>/dev/null); then
    red "FAIL: (g) expected non-zero for unusable bearer (got id=$id)"; fail=1
  elif [[ -s "$work/curl.log" ]]; then
    red "FAIL: (g) curl was invoked for an unusable bearer"; fail=1
  else
    green "PASS: (g) unusable bearer → non-zero, zero curl calls"
  fi
done

# ── (h) CF_API override off the pinned Cloudflare base → refused, zero calls ─
mk_curl_stub
prime_queue '200 {"result":{"status":"active","id":"tok-abc"}}'
if id=$(CF_API="https://evil.example/client/v4" cf_token_verify "$bearer_f" 2>/dev/null); then
  red "FAIL: (h) expected non-zero for CF_API off the pinned base (got id=$id)"; fail=1
elif [[ -s "$work/curl.log" ]]; then
  red "FAIL: (h) curl was invoked for an unpinned CF_API"; fail=1
else
  green "PASS: (h) CF_API off the Cloudflare base → non-zero, zero curl calls"
fi

if [[ "$fail" -eq 0 ]]; then
  green "ALL _cf-admin-token.sh tests passed."
fi
exit "$fail"
