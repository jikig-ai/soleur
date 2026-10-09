#!/usr/bin/env bash
# shellcheck disable=SC2016  # shim heredocs carry literal source text, never expanded here
# tests/scripts/test-dispatch-web-redeploy.sh — .github/actions/dispatch-web-redeploy/track.sh
# (#8211 PR2: the same-version redeploy lever, rebuilt on /hooks/deploy — the
# web-platform-release run poll is gone; this suite pins the webhook contract).
#
# Property: track.sh confirms a redeploy ONLY on a deploy-status frame with
# component=web-platform AND tag==v<running semver> AND start_ts > the baseline read
# BEFORE the POST — and only when that frame's reason is `ok`. A degraded fan-out, a
# terminal failure, a stale frame and a timeout are all refused with stable verdicts.
#
# Hermetic: curl is a PATH shim that answers /health, /hooks/deploy-status and
# /hooks/deploy from env knobs and logs every request (method, URL, headers, POST body)
# to $TL. openssl/jq are REAL — the HMAC header is verified by recomputation. sleep is
# shimmed instant so the poll loop runs synchronously.
#
#   row   scenario                                                        expected
#   X     bash -x                                                         78 before any curl
#   C1..  a credential unset                                              2, verdict=redeploy_credential_absent
#   T1    curl not on PATH                                                2, verdict=redeploy_tool_absent
#   H1    /health unreachable (rc)                                        1, verdict=redeploy_tag_unresolved
#   H2    /health version not semver                                      1, redeploy_tag_unresolved
#   S1    status GET non-200                                              1, verdict=redeploy_status_unreadable
#   S2    status start_ts non-numeric                                     1, verdict=redeploy_baseline_unreadable
#   D1    POST != 202                                                     1, verdict=redeploy_dispatch_rejected
#   P1    stale frame (start_ts == prior) then ok frame                    0; stale frame ignored
#   P2    peers CSV + command + HMAC on the POST                          verified by recompute
#   P3    ok_peer_fanout_degraded at a fresh start_ts                     1, verdict=redeploy_peer_fanout_degraded
#   P4    lock_contention frame then ok                                   0 (NON-TERMINAL logged)
#   P5    exit_code<0 running frame then ok                               0
#   P6    terminal failure reason                                          1, verdict=redeploy_terminal_failure
#   P7    only stale frames forever                                        1, verdict=redeploy_timeout
#   P8    wrong component, then our tag                                    0 (foreign frame ignored)
#   P9    no peers env -> POST body carries NO peers key                   0, body lacks peers
set -uo pipefail   # NOT -e: run_case deliberately captures the SUT's non-zero exits.
cd "$(dirname "$0")/../.."

SCRIPT=".github/actions/dispatch-web-redeploy/track.sh"
passes=0; fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }
_st="$( (pass x >/dev/null; fail y >/dev/null; printf '%s %s' "$passes" "$fails") )"
[ "$_st" = "1 1" ] || { printf 'FAIL INSTRUMENT: pass()/fail() self-test read "%s"\n' "$_st" >&2; exit 1; }

[ -f "$SCRIPT" ] || { printf 'FAIL SETUP: %s not found\n' "$SCRIPT" >&2; exit 1; }
for b in openssl jq; do
  command -v "$b" >/dev/null 2>&1 || { printf 'FAIL SETUP: %s not on PATH\n' "$b" >&2; exit 1; }
done

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
BIN="$T/bin"; mkdir -p "$BIN" || exit 1

# --- curl shim ----------------------------------------------------------------------
# Answers by URL suffix; records every request. /hooks/deploy-status consumes
# $SEQ_FILE lines in order (one JSON object per line), repeating the last when
# exhausted — the baseline read takes line 1, each poll the next.
cat > "$BIN/curl" <<'SHIM'
#!/usr/bin/env bash
method=GET; out=""; wfmt=""; data=""; url=""; failflag=0; prev=""
for a in "$@"; do
  if [ -n "$prev" ]; then
    case "$prev" in
      -o) out="$a" ;; -X) method="$a" ;; -d) data="$a" ;; -w) wfmt="$a" ;;
      -H) printf '  hdr %s\n' "$a" >> "$TL" ;;
      *) : ;;
    esac
    prev=""; continue
  fi
  case "$a" in
    -o|-X|-d|-w|-H|--max-time) prev="$a" ;;
    -f) failflag=1 ;;
    -*) : ;;
    *) url="$a" ;;
  esac
done
printf 'CURL %s %s\n' "$method" "$url" >> "$TL"
[ -n "$data" ] && printf '  body %s\n' "$data" >> "$TL"
code=200; body=""
case "$url" in
  */health)
    code="${SHIM_HEALTH_CODE:-200}"
    body="${SHIM_HEALTH_BODY-{\"version\":\"1.2.3\"}}"
    [ "${SHIM_HEALTH_RC:-0}" != 0 ] && exit "$SHIM_HEALTH_RC"
    ;;
  */hooks/deploy-status)
    code="${SHIM_STATUS_CODE:-200}"
    idxf="${SHIM_SEQ_IDX:-/dev/null}"
    i=0; [ -f "$idxf" ] && i="$(cat "$idxf")"
    frame="$(sed -n "$((i + 1))p" "$SEQ_FILE" 2>/dev/null)"
    [ -z "$frame" ] && frame="$(tail -1 "$SEQ_FILE" 2>/dev/null)"
    echo $((i + 1)) > "$idxf" 2>/dev/null || true
    body="$frame"
    ;;
  */hooks/deploy)
    code="${SHIM_POST_CODE:-202}"
    ;;
esac
if [ "$failflag" = 1 ] && [ "$code" -ge 400 ]; then exit 22; fi
if [ -n "$out" ]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
[ -n "$wfmt" ] && printf '%s' "$code"
exit 0
SHIM
# sleep: instant — the poll loop is driven by frame count, not wall clock.
cat > "$BIN/sleep" <<'SHIM'
#!/usr/bin/env bash
exit 0
SHIM
chmod +x "$BIN/curl" "$BIN/sleep" || exit 1

SECRET="test-webhook-secret-synthetic"   # fixture — never a real credential
ID="test-cf-id"; SC="test-cf-secret"

# run_case <name> [VAR=val ...] — env -i, shimmed PATH, script under test. Sets RC, OUT, TLF.
run_case() {
  local name="$1"; shift
  TLF="$T/$name.tl"; OUT="$T/$name.out"; SEQ="$T/$name.seq"
  : > "$TLF"; : > "$OUT"
  SEQ_FILE="$SEQ"
  env -i PATH="$BIN:/usr/bin:/bin" HOME="$T" TMPDIR="$T" TL="$TLF" SEQ_FILE="$SEQ" \
    SHIM_SEQ_IDX="$T/$name.idx" \
    APP_DOMAIN_BASE=example.test \
    WEBHOOK_DEPLOY_SECRET="$SECRET" CF_ACCESS_CLIENT_ID="$ID" CF_ACCESS_CLIENT_SECRET="$SC" \
    WEB_HOST_PRIVATE_IPS="10.0.1.10,10.0.1.11" \
    REDEPLOY_POLL_INTERVAL_S=1 REDEPLOY_TIMEOUT_S=2 \
    "$@" bash "$SCRIPT" > "$OUT" 2>&1
  RC=$?
}
verdict() { grep -oE 'verdict=[a-z_]+' "$OUT" | tail -1 | sed 's/^verdict=//'; }

echo "=== dispatch-web-redeploy track.sh (webhook contract) ==="

# X — xtrace refusal before anything runs.
rc=0
env -i PATH="$BIN:/usr/bin:/bin" TL=/dev/null bash -x "$SCRIPT" > "$T/x.out" 2>&1 || rc=$?
if [ "$rc" = 78 ]; then pass "X: bash -x -> exit 78 before any curl"; else fail "X: xtrace not refused"; fi

# C — each credential unset refuses rc 2 before any network call.
for v in WEBHOOK_DEPLOY_SECRET CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET; do
  run_case "c-$v" "$v="
  if [ "$RC" = 2 ] && [ "$(verdict)" = "redeploy_credential_absent" ] && [ ! -s "$TLF" ]; then
    pass "C: unset $v -> verdict=redeploy_credential_absent, no request"
  else fail "C: unset $v was not refused" "$(tail -2 "$OUT")"; fi
done

# T1 — curl not on PATH (bash by absolute path; the rest of PATH is empty).
rc=0
env -i PATH="$T/emptybin" TL=/dev/null WEBHOOK_DEPLOY_SECRET=x CF_ACCESS_CLIENT_ID=x CF_ACCESS_CLIENT_SECRET=x \
  /usr/bin/bash "$SCRIPT" > "$T/t1.out" 2>&1 || rc=$?
if [ "$rc" = 2 ] && grep -q 'verdict=redeploy_tool_absent' "$T/t1.out"; then
  pass "T1: curl absent -> verdict=redeploy_tool_absent"
else fail "T1: a missing tool was not refused" "$(tail -2 "$T/t1.out")"; fi

# H — the target tag comes from /health; an unreadable or non-semver answer fails closed.
run_case h1-rc SHIM_HEALTH_RC=7
if [ "$RC" = 1 ] && [ "$(verdict)" = "redeploy_tag_unresolved" ] && ! grep -q 'hooks/deploy' "$TLF"; then
  pass "H1: /health unreachable -> redeploy_tag_unresolved, nothing dispatched"
else fail "H1: an unreadable health check was not refused" "$(tail -2 "$OUT")"; fi
run_case h2-nosemver 'SHIM_HEALTH_BODY={"version":"latest"}'
if [ "$RC" = 1 ] && [ "$(verdict)" = "redeploy_tag_unresolved" ]; then
  pass "H2: a non-semver running version -> redeploy_tag_unresolved"
else fail "H2: a non-semver version was accepted" "$(tail -2 "$OUT")"; fi

# S — the baseline must read before dispatch; an unreadable status or non-numeric
# start_ts fails closed (baseline 0 would accept every historical frame).
printf '%s\n' '{"start_ts":100}' > "$T/s1-http.seq"
run_case s1-http SHIM_STATUS_CODE=503
if [ "$RC" = 1 ] && [ "$(verdict)" = "redeploy_status_unreadable" ] && ! grep -q 'POST' "$TLF"; then
  pass "S1: status non-200 -> redeploy_status_unreadable, no POST"
else fail "S1: an unreadable status was not refused" "$(tail -2 "$OUT")"; fi
printf '%s\n' '{"component":"web-platform"}' > "$T/s2-nostart.seq"
run_case s2-nostart
if [ "$RC" = 1 ] && [ "$(verdict)" = "redeploy_baseline_unreadable" ]; then
  pass "S2: no numeric start_ts -> redeploy_baseline_unreadable"
else fail "S2: a missing baseline was accepted" "$(tail -2 "$OUT")"; fi

# D1 — a rejected POST.
printf '%s\n' '{"start_ts":100}' > "$T/d1-post.seq"
run_case d1-post SHIM_POST_CODE=403
if [ "$RC" = 1 ] && [ "$(verdict)" = "redeploy_dispatch_rejected" ] && grep -q 'CURL POST .*/hooks/deploy' "$TLF"; then
  pass "D1: POST != 202 -> redeploy_dispatch_rejected"
else fail "D1: a rejected POST was not refused" "$(tail -2 "$OUT")"; fi

# P1 — stale frame (start_ts == prior, NOT >) ignored; then our frame.
printf '%s\n' \
  '{"start_ts":100}' \
  '{"component":"web-platform","tag":"v1.2.3","reason":"ok","exit_code":0,"start_ts":100}' \
  '{"component":"web-platform","tag":"v1.2.3","reason":"ok","exit_code":0,"start_ts":101}' \
  > "$T/p1-stale-then-ok.seq"
run_case p1-stale-then-ok
if [ "$RC" = 0 ] && grep -q "ignoring frame" "$OUT" && grep -q "terminal: reason=ok" "$OUT"; then
  pass "P1: a frame with start_ts==prior is ignored; the fresh ok frame confirms (exit 0)"
else fail "P1: stale-frame rejection wrong" "$(tail -4 "$OUT")"; fi

# P2 — the POST body carries command + peers CSV, signed HMAC-SHA256 over the body.
BODY="$(grep '  body ' "$T/p1-stale-then-ok.tl" | sed 's/^  body //')"
# The hdr lines precede their CURL line; pair the most recent signature with the POST.
SIG="$(awk '/X-Signature-256/{s=$0} /^CURL POST/{sub(/.*sha256=/,"",s); print s; exit}' "$T/p1-stale-then-ok.tl")"
WANT_SIG="$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | sed 's/.*= //')"
if [ "$SIG" = "$WANT_SIG" ] && printf '%s' "$BODY" | grep -c >/dev/null '"peers":"10.0.1.10,10.0.1.11"' \
   && printf '%s' "$BODY" | grep -c >/dev/null 'deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.2.3'; then
  pass "P2: POST body carries command+peers and the X-Signature-256 HMAC verifies"
else fail "P2: the POST contract broke" "body=$BODY sig=$SIG want=$WANT_SIG"; fi

# P3 — a degraded fan-out is a FAILURE (the fleet is mixed; the cutover cannot accept it).
printf '%s\n' \
  '{"start_ts":100}' \
  '{"component":"web-platform","tag":"v1.2.3","reason":"ok_peer_fanout_degraded","exit_code":0,"start_ts":101}' \
  > "$T/p3-degraded.seq"
run_case p3-degraded
if [ "$RC" = 1 ] && [ "$(verdict)" = "redeploy_peer_fanout_degraded" ]; then
  pass "P3: ok_peer_fanout_degraded -> verdict=redeploy_peer_fanout_degraded, exit 1"
else fail "P3: a degraded fan-out was accepted" "$(tail -2 "$OUT")"; fi

# P4 — lock_contention is NON-TERMINAL: keep polling for the winner's terminal.
printf '%s\n' \
  '{"start_ts":100}' \
  '{"component":"web-platform","tag":"v1.2.3","reason":"lock_contention","exit_code":1,"start_ts":101}' \
  '{"component":"web-platform","tag":"v1.2.3","reason":"ok","exit_code":0,"start_ts":102}' \
  > "$T/p4-lock.seq"
run_case p4-lock
if [ "$RC" = 0 ] && grep -q "NON-TERMINAL" "$OUT"; then
  pass "P4: lock_contention -> NON-TERMINAL, polls on to the ok frame"
else fail "P4: lock_contention was terminal" "$(tail -3 "$OUT")"; fi

# P5 — a running frame (exit_code<0) is not terminal either.
printf '%s\n' \
  '{"start_ts":100}' \
  '{"component":"web-platform","tag":"v1.2.3","reason":"running","exit_code":-1,"start_ts":101}' \
  '{"component":"web-platform","tag":"v1.2.3","reason":"ok","exit_code":0,"start_ts":102}' \
  > "$T/p5-running.seq"
run_case p5-running
if [ "$RC" = 0 ]; then
  pass "P5: exit_code<0 (running) is not terminal; the ok frame confirms"
else fail "P5: a running frame ended the poll" "$(tail -3 "$OUT")"; fi

# P6 — any other terminal reason fails.
printf '%s\n' \
  '{"start_ts":100}' \
  '{"component":"web-platform","tag":"v1.2.3","reason":"ssh_failed","exit_code":1,"start_ts":101}' \
  > "$T/p6-term.seq"
run_case p6-term
if [ "$RC" = 1 ] && [ "$(verdict)" = "redeploy_terminal_failure" ]; then
  pass "P6: a terminal failure reason -> verdict=redeploy_terminal_failure"
else fail "P6: a terminal failure was not refused" "$(tail -2 "$OUT")"; fi

# P7 — never-qualifying frames (all at/below baseline) -> timeout verdict.
printf '%s\n' \
  '{"start_ts":100}' \
  '{"component":"web-platform","tag":"v1.2.3","reason":"ok","exit_code":0,"start_ts":100}' \
  > "$T/p7-timeout.seq"
run_case p7-timeout REDEPLOY_TIMEOUT_S=1
if [ "$RC" = 1 ] && [ "$(verdict)" = "redeploy_timeout" ]; then
  pass "P7: only stale frames -> verdict=redeploy_timeout, exit 1"
else fail "P7: a stale-forever poll did not time out" "$(tail -3 "$OUT")"; fi

# P8 — a foreign component's frame is ignored even at a fresh start_ts.
printf '%s\n' \
  '{"start_ts":100}' \
  '{"component":"other-thing","tag":"v1.2.3","reason":"ok","exit_code":0,"start_ts":101}' \
  '{"component":"web-platform","tag":"v1.2.3","reason":"ok","exit_code":0,"start_ts":102}' \
  > "$T/p8-foreign.seq"
run_case p8-foreign
if [ "$RC" = 0 ] && grep -q "ignoring frame" "$OUT"; then
  pass "P8: a foreign component's ok frame is ignored; ours confirms"
else fail "P8: a foreign frame was accepted" "$(tail -3 "$OUT")"; fi

# P9 — no peers env -> the POST body omits the peers key entirely.
printf '%s\n' \
  '{"start_ts":100}' \
  '{"component":"web-platform","tag":"v1.2.3","reason":"ok","exit_code":0,"start_ts":101}' \
  > "$T/p9-nopeers.seq"
run_case p9-nopeers WEB_HOST_PRIVATE_IPS=""
if [ "$RC" = 0 ] && ! grep -q '"peers"' "$TLF"; then
  pass "P9: empty WEB_HOST_PRIVATE_IPS -> no peers key in the POST body (single-host lever)"
else fail "P9: an empty peers env still sent a peers field" "$(grep '  body' "$TLF")"; fi

echo
if [ "$fails" -gt 0 ]; then
  printf '=== test-dispatch-web-redeploy: %d passed, %d FAILED ===\n' "$passes" "$fails" >&2
  exit 1
fi
printf '=== test-dispatch-web-redeploy: %d passed, 0 failed ===\n' "$passes"
