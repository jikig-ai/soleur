#!/usr/bin/env bash
# Tests for scripts/rundevoo-dns-set-equality.sh (#12971).
#
# Method: `curl` is stubbed on PATH and answers fixture JSON keyed on the
# dns_records URL's page= param (the last argv item — the helper emits the URL
# last). No network, no real credentials: CLOUDFLARE_API_TOKEN is a synthesized
# placeholder that satisfies the script's non-empty check (its shape is pinned
# by the helper's _cf_bearer_ok alphabet — alnum plus ._~+/=-).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="$REPO_ROOT/scripts/rundevoo-dns-set-equality.sh"
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
STUB_DIR="$TMPD/stubs"; mkdir -p "$STUB_DIR"
pass=0; fail=0
EXPECTED_TESTS=15

_report() {
  if [[ "$2" == "ok" ]]; then pass=$((pass + 1)); echo "[ok] $1"
  else fail=$((fail + 1)); echo "[FAIL] $1 $3" >&2; fi
}

if [[ ! -f "$SUT" ]]; then
  echo "ERROR: $SUT does not exist — RED phase expected this." >&2
  exit 1
fi

# curl stub: last argv item is the URL. Emits $LIVE_PAGE1 / $LIVE_PAGE2 from
# env (each test sets the fixture world). Calls log appended to $CURL_LOG.
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null  # consume the stdin config channel (the bearer)
echo "$*" >> "${CURL_LOG:-/dev/null}"
url="${@: -1}"
case "$url" in
  */dnssec)
    printf '{"success":true,"result":{"status":"%s"}}' "${DNSSEC_STATUS:-active}"
    exit 0
    ;;
esac
page=1
case "$url" in *page=2*) page=2 ;; esac
if [[ "$page" == "2" ]]; then
  printf '%s' "${LIVE_PAGE2:-SENTINEL_UNSET}"
else
  printf '%s' "${LIVE_PAGE1:-SENTINEL_UNSET}"
fi
STUB
chmod +x "$STUB_DIR/curl"

export PATH="$STUB_DIR:$PATH"
export CLOUDFLARE_API_TOKEN="synthesized-test-token-AAAA_0000"
export CURL_LOG="$TMPD/curl.log"; : > "$CURL_LOG"
# Exported once here: later plain assignments stay exported into the stub.
export LIVE_PAGE1 LIVE_PAGE2 DNSSEC_STATUS

# A state document carrying three managed records (the declared posture).
state_doc() {
  cat <<'JSON'
{"values":{"root_module":{"resources":[
  {"type":"cloudflare_record","values":{"type":"MX","name":"rundevoo.run","content":"."}},
  {"type":"cloudflare_record","values":{"type":"TXT","name":"rundevoo.run","content":"v=spf1 -all"}},
  {"type":"cloudflare_record","values":{"type":"TXT","name":"_dmarc.rundevoo.run","content":"v=DMARC1; p=reject"}},
  {"type":"cloudflare_zone","values":{"id":"4a16c6fcd6949d1887d6247f95a0d91e"}}
]}}}
JSON
}
STATE="$TMPD/state.json"; state_doc > "$STATE"

live_doc() { # $1..$N = "type|name|content" triples -> CF API response JSON
  local out='{"success":true,"result_info":{"page":1,"per_page":500,"total_pages":1},"result":['
  local first=1 t
  for t in "$@"; do
    [[ "$first" == "1" ]] && first=0 || out+=','
    IFS='|' read -r ty nm ct <<<"$t"
    out+="{\"type\":\"$ty\",\"name\":\"$nm\",\"content\":\"$ct\"}"
  done
  printf '%s' "$out]}"
}

OUT="$TMPD/out.txt"
_run() { # sets rc via return; stdout/stderr captured to $OUT — call directly,
  # never in a command substitution (a subshell would discard $OUT's writes).
  : > "$OUT"
  bash "$SUT" "$STATE" >"$OUT" 2>&1
}

BASE_RECORDS=("MX|rundevoo.run|." "TXT|rundevoo.run|v=spf1 -all" "TXT|_dmarc.rundevoo.run|v=DMARC1; p=reject" "NS|rundevoo.run|laila.ns.cloudflare.com" "NS|rundevoo.run|lennon.ns.cloudflare.com")

# T1: live == managed (apex NS ignored) -> 0.
t_set_equality_passes() {
  LIVE_PAGE1=$(live_doc "${BASE_RECORDS[@]}")
  local rc=0
  _run || rc=$?
  [[ "$rc" == "0" ]] && _report "T1 live==managed passes (apex NS excluded)" ok \
    || _report "T1 live==managed passes" fail "rc=$rc; $(tail -3 "$OUT")"
}

# T2: one extra live record -> 1, and the record is named.
t_unmanaged_record_trips() {
  LIVE_PAGE1=$(live_doc "${BASE_RECORDS[@]}" "A|evil.rundevoo.run|203.0.113.66")
  local rc=0
  _run || rc=$?
  if [[ "$rc" == "1" ]] && grep -q "evil.rundevoo.run" "$OUT"; then
    _report "T2 unmanaged live A record trips, named in output" ok
  else
    _report "T2 unmanaged live A record trips" fail "rc=$rc; $(tail -3 "$OUT")"
  fi
}

# T3: a managed record missing live -> 1.
t_missing_record_trips() {
  LIVE_PAGE1=$(live_doc "MX|rundevoo.run|." "TXT|rundevoo.run|v=spf1 -all" "NS|rundevoo.run|laila.ns.cloudflare.com")
  local rc=0
  _run || rc=$?
  if [[ "$rc" == "1" ]] && grep -q "_dmarc.rundevoo.run" "$OUT"; then
    _report "T3 managed record missing live trips" ok
  else
    _report "T3 managed record missing live trips" fail "rc=$rc; $(tail -3 "$OUT")"
  fi
}

# T4: a subdomain NS delegation is NOT in the apex-NS exclusion — it trips.
t_subdomain_ns_trips() {
  LIVE_PAGE1=$(live_doc "${BASE_RECORDS[@]}" "NS|sub.rundevoo.run|ns1.example.net")
  local rc=0
  _run || rc=$?
  if [[ "$rc" == "1" ]] && grep -q "sub.rundevoo.run" "$OUT"; then
    _report "T4 delegated subdomain NS is not exempt — trips" ok
  else
    _report "T4 delegated subdomain NS is not exempt" fail "rc=$rc; $(tail -3 "$OUT")"
  fi
}

# T5: success:false API response -> fail closed.
t_api_failure_fails_closed() {
  LIVE_PAGE1='{"success":false,"errors":[{"code":9109}]}'
  local rc=0
  _run || rc=$?
  [[ "$rc" == "1" ]] && _report "T5 success:false fails closed" ok \
    || _report "T5 success:false fails closed" fail "rc=$rc; $(tail -3 "$OUT")"
}

# T6: pagination — total_pages=2, the unmanaged record on page 2 is found.
t_page_two_unmanaged_found() {
  LIVE_PAGE1=$(live_doc "MX|rundevoo.run|." "TXT|rundevoo.run|v=spf1 -all" "TXT|_dmarc.rundevoo.run|v=DMARC1; p=reject" "NS|rundevoo.run|laila.ns.cloudflare.com")
  LIVE_PAGE1=${LIVE_PAGE1/\"total_pages\":1/\"total_pages\":2}
  LIVE_PAGE2=$(live_doc "A|deep.rundevoo.run|198.51.100.7")
  : > "$CURL_LOG"
  local rc=0
  _run || rc=$?
  if [[ "$rc" == "1" ]] && grep -q "deep.rundevoo.run" "$OUT" && grep -q "page=2" "$CURL_LOG"; then
    _report "T6 page-2 unmanaged record found; page 2 was fetched" ok
  else
    _report "T6 page-2 unmanaged record found" fail "rc=$rc; log=$(cat "$CURL_LOG")"
  fi
}

# T7: unbounded pagination claim -> fail closed (total_pages=99).
t_runaway_pagination_fails_closed() {
  LIVE_PAGE1=$(live_doc "MX|rundevoo.run|.")
  LIVE_PAGE1=${LIVE_PAGE1/\"total_pages\":1/\"total_pages\":99}
  LIVE_PAGE2=$(live_doc "MX|rundevoo.run|.")
  LIVE_PAGE2=${LIVE_PAGE2/\"total_pages\":1/\"total_pages\":99}

  local rc=0
  _run || rc=$?
  [[ "$rc" == "1" ]] && _report "T7 runaway pagination fails closed" ok \
    || _report "T7 runaway pagination fails closed" fail "rc=$rc; $(tail -3 "$OUT")"
}

# T8: missing CLOUDFLARE_API_TOKEN -> 1 (no silent fallback).
t_missing_token_refuses() {
  local saved="$CLOUDFLARE_API_TOKEN"
  unset CLOUDFLARE_API_TOKEN
  local rc=0
  bash "$SUT" "$STATE" >/dev/null 2>&1 || rc=$?
  # Restore WITH export — a bare re-assignment leaves the variable set but
  # unexported, so later cases would see "no token" in the child process.
  export CLOUDFLARE_API_TOKEN="$saved"
  [[ "$rc" == "1" ]] && _report "T8 missing token refuses" ok \
    || _report "T8 missing token refuses" fail "rc=$rc"
}

# T9: the zone id is the committed import-block literal — a repointed zone.tf
# changes which zone is probed; pin the derivation to the real file.
t_zone_id_from_import_block() {
  local want got
  want=$(grep -oE -m1 '[0-9a-f]{32}' < <(grep -oE '^[[:space:]]*id = "[0-9a-f]{32}"' "$REPO_ROOT/infra/rundevoo-run/zone.tf") || true)
  LIVE_PAGE1=$(live_doc "${BASE_RECORDS[@]}")
  : > "$CURL_LOG"
  _run >/dev/null || true
  got=$(grep -oE -m1 'zones/[0-9a-f]{32}' "$CURL_LOG" | cut -d/ -f2 || true)
  if [[ "$got" == "$want" && ${#want} -eq 32 ]]; then
    _report "T9 probe targets the committed import-block zone id" ok
  else
    _report "T9 probe targets the committed import-block zone id" fail "got '$got' want '$want'"
  fi
}

# T10: bearer rides the stdin config channel, never argv — a token in argv is
# world-readable via /proc for the life of the process.
t_token_not_in_argv() {
  LIVE_PAGE1=$(live_doc "${BASE_RECORDS[@]}")
  : > "$CURL_LOG"
  _run >/dev/null || true
  # Liveness: an empty log would mean the stub never ran and the grep below
  # passes vacuously — assert the calls happened before reading them.
  if [[ ! -s "$CURL_LOG" ]]; then
    _report "T10 token never reaches curl argv" fail "curl stub was never invoked — vacuous"
  elif grep -qF "$CLOUDFLARE_API_TOKEN" "$CURL_LOG"; then
    _report "T10 token never reaches curl argv" fail "token literal found in argv log"
  else
    _report "T10 token never reaches curl argv" ok
  fi
}

# T11: apex CDS/CDNSKEY records — auto-published by Cloudflare once DNSSEC is
# enabled (RFC 8078) and never Terraform resources — are excluded at the apex
# only, like apex NS. Without the exclusion the first apply would red.
t_apex_dnssec_records_excluded() {
  LIVE_PAGE1=$(live_doc "${BASE_RECORDS[@]}" \
    "CDS|rundevoo.run|2371 13 2 AABBCCDDEEFF" \
    "CDNSKEY|rundevoo.run|257 3 13 mdsswUyr3DPW132mOi8V9xESWE8jTo0dXfjjSPtA")
  local rc=0
  _run || rc=$?
  [[ "$rc" == "0" ]] && _report "T11 apex CDS/CDNSKEY excluded" ok \
    || _report "T11 apex CDS/CDNSKEY excluded" fail "rc=$rc; $(tail -3 "$OUT")"
}

# T12: absent result_info.total_pages must fail closed — a `// 1` default
# would silently skip page 2+ and let unmanaged records hide past the
# page boundary.
t_missing_total_pages_fails_closed() {
  LIVE_PAGE1='{"success":true,"result_info":{"page":1,"per_page":500},"result":[]}'
  local rc=0
  _run || rc=$?
  if [[ "$rc" == "1" ]] && grep -qi "total_pages" "$OUT"; then
    _report "T12 absent total_pages fails closed" ok
  else
    _report "T12 absent total_pages fails closed" fail "rc=$rc; $(tail -3 "$OUT")"
  fi
}

# T13: an out-of-band DNSSEC disable trips the probe — plan cannot see it
# (status is computed-only) and the record set cannot either.
t_dnssec_disabled_trips() {
  LIVE_PAGE1=$(live_doc "${BASE_RECORDS[@]}")
  DNSSEC_STATUS="disabled"
  local rc=0
  _run || rc=$?
  unset DNSSEC_STATUS
  if [[ "$rc" == "1" ]] && grep -qi "dnssec" "$OUT"; then
    _report "T13 dnssec status 'disabled' fails closed" ok
  else
    _report "T13 dnssec status 'disabled' fails closed" fail "rc=$rc; $(tail -3 "$OUT")"
  fi
}

# T14: CDS/CDNSKEY at a NON-apex name are not exempt — only the apex forms
# are the Cloudflare auto-published set.
t_nonapex_dnssec_records_trip() {
  LIVE_PAGE1=$(live_doc "${BASE_RECORDS[@]}" \
    "CDS|sub.rundevoo.run|2371 13 2 AABBCCDDEEFF" \
    "CDNSKEY|sub.rundevoo.run|257 3 13 mdsswUyr3DPW132mOi8V9xESWE8jTo0dXfjjSPtA")
  local rc=0
  _run || rc=$?
  if [[ "$rc" == "1" ]] && grep -q "sub.rundevoo.run" "$OUT"; then
    _report "T14 non-apex CDS/CDNSKEY trip as unmanaged" ok
  else
    _report "T14 non-apex CDS/CDNSKEY trip" fail "rc=$rc; $(tail -3 "$OUT")"
  fi
}

# T15: DNSSEC 'pending' is accepted — the post-enable propagation window
# must not red the first post-apply run.
t_dnssec_pending_accepted() {
  LIVE_PAGE1=$(live_doc "${BASE_RECORDS[@]}")
  DNSSEC_STATUS="pending"
  local rc=0
  _run || rc=$?
  unset DNSSEC_STATUS
  [[ "$rc" == "0" ]] && _report "T15 dnssec 'pending' accepted" ok \
    || _report "T15 dnssec 'pending' accepted" fail "rc=$rc; $(tail -3 "$OUT")"
}

t_set_equality_passes
t_unmanaged_record_trips
t_missing_record_trips
t_subdomain_ns_trips
t_api_failure_fails_closed
t_page_two_unmanaged_found
t_runaway_pagination_fails_closed
t_missing_token_refuses
t_zone_id_from_import_block
t_token_not_in_argv
t_apex_dnssec_records_excluded
t_missing_total_pages_fails_closed
t_dnssec_disabled_trips
t_nonapex_dnssec_records_trip
t_dnssec_pending_accepted

echo "=== $pass passed, $fail failed ==="
ran=$((pass + fail))
if [[ "$ran" -ne "$EXPECTED_TESTS" ]]; then
  echo "[FAIL] harness: ran $ran test(s), expected $EXPECTED_TESTS" >&2
  exit 1
fi
[[ "$fail" -eq 0 ]]
