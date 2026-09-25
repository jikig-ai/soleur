#!/usr/bin/env bash
# Exit-code harness for c4-zero-view-model-8740.sh (#8740 follow-through close gate).
#
# The probe's exit code IS the close authorization: the sweeper closes #8740 on 0.
# The cardinal sin is a vacuous 0 -- sink dead, fix not live, a non-200 or non-array
# body read as "0 events", or an op slug the route no longer emits. Rows 1-15 are
# the plan's rows (knowledge-base/project/plans/2026-09-25-fix-c4-zero-view-model-
# project-diagnostic-plan.md, Phase 1 item 8 and the Guard Contract).
#
# STUBS: `curl` and `git` only, in a stub dir put on PATH for the probe run alone
# (an env prefix, never exported). Each logs its argv, answers only the calls it
# routes, and logs UNROUTED + exits 99 on anything else. No call reaches real git
# or the network. `jq` stays real.
#
# The token below is synthesized (cq-test-fixtures-synthesized-only).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/c4-zero-view-model-8740.sh"
ROUTE="$HERE/../../apps/web-platform/app/api/kb/c4/project/route.ts"
fails=0; total=0
pass() { total=$((total + 1)); printf '  PASS: %s\n' "$1"; }
fail() { total=$((total + 1)); printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required (kept real)" >&2; exit 1; }

# Instrument self-test (ADR-193): both counters must move before any verdict is trusted.
_p0=$total; pass "instrument: pass() moves the counter" >/dev/null; _f0=$fails
fail "instrument: fail() moves the counter" 2>/dev/null
if [[ $total -ne $((_p0 + 2)) || $fails -ne $((_f0 + 1)) ]]; then
  printf 'FATAL: instrument self-test -- pass()/fail() did not both move their counters\n' >&2; exit 1
fi
total=$_p0; fails=$_f0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
STUB="$WORK/stub"; FX="$WORK/fx"; LOG="$WORK/calls.log"; CWD="$WORK/cwd"
mkdir -p "$STUB" "$FX" "$CWD"

FAKE_TOKEN="synthetic-test-token-8740-not-a-secret"
BUILD="0123456789abcdef0123456789abcdef01234567"
INTRO_SHA="89abcdef0123456789abcdef0123456789abcdef"
PROBE_REL="scripts/followthroughs/$(basename "$SUT")"

# ── stubs ─────────────────────────────────────────────────────────────────────
cat > "$STUB/curl" <<STUBEOF
#!/usr/bin/env bash
FX='$FX'; LOG='$LOG'
{ printf 'curl'; printf ' [%s]' "\$@"; printf '\n'; } >> "\$LOG"
url=""; wfmt=""; stdin_hdr=0; auth_argv=0
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -w) wfmt="\$2"; shift 2 ;;
    -H) [[ "\$2" == "@-" ]] && stdin_hdr=1
        [[ "\$2" == [Aa]uthorization:* ]] && auth_argv=1
        shift 2 ;;
    https://*) url="\$1"; shift ;;
    *) shift ;;
  esac
done
if (( stdin_hdr )); then
  hdr="\$(cat)"
  if [[ "\$hdr" == "Authorization: Bearer "?* ]]; then echo "curl-stdin-auth ok" >> "\$LOG"
  else echo "curl-stdin-auth BAD" >> "\$LOG"; fi
fi
(( auth_argv )) && echo "curl-argv-auth PRESENT" >> "\$LOG"
case "\$url" in
  https://app.soleur.ai/health) key=health ;;
  https://sentry.io/api/0/organizations/jikigai-eu/events/\?*query=*zero-view-model*) key=signal ;;
  https://sentry.io/api/0/organizations/jikigai-eu/events/\?*query=*server-startup*) key=live ;;
  *) echo "UNROUTED curl \$url" >> "\$LOG"; exit 99 ;;
esac
status="\$(cat "\$FX/\$key.status")"
cat "\$FX/\$key.body"
wpat='%{http_code}'
if [[ -n "\$wfmt" ]]; then printf '%b' "\${wfmt//"\$wpat"/\$status}"; fi
exit 0
STUBEOF

cat > "$STUB/git" <<STUBEOF
#!/usr/bin/env bash
FX='$FX'; LOG='$LOG'
{ printf 'git'; printf ' [%s]' "\$@"; printf '\n'; } >> "\$LOG"
if [[ "\${1:-}" == "log" && " \$* " == *" --diff-filter=A "* ]]; then
  cat "\$FX/git.intro"; exit 0
elif [[ "\${1:-}" == "cat-file" && "\${2:-}" == "-e" && \$# -eq 3 ]]; then
  exit "\$(cat "\$FX/git.catfile.rc")"
elif [[ "\${1:-}" == "merge-base" && "\${2:-}" == "--is-ancestor" && \$# -eq 4 ]]; then
  exit "\$(cat "\$FX/git.mb.rc")"
fi
echo "UNROUTED git \$*" >> "\$LOG"; exit 99
STUBEOF
chmod 0755 "$STUB/curl" "$STUB/git"

# ── fixtures ──────────────────────────────────────────────────────────────────
events_body() {  # events_body <n> -- n synthesized events, newest first, extra fields
  local n="$1" i sep=""
  printf '{"data":['
  for ((i = 0; i < n; i++)); do
    printf '%s{"timestamp":"2026-10-0%dT12:00:00+00:00","id":"ev%d","project.name":"web-platform","dir":"SENTINEL-DIR-leak","modelPath":"SENTINEL-MODELPATH-leak","userIdHash":"SENTINEL-UIDHASH-leak","elementCount":987654}' "$sep" $(( 9 - i % 9 )) "$i"
    sep=","
  done
  printf '],"meta":{"fields":{"timestamp":"date"},"units":{}},"extraTopLevel":true}'
}
put() { printf '%s' "$2" > "$FX/$1"; }

# green: signal 0, deployed, liveness 3 events, extra fields everywhere.
set_green() {
  put signal.status 200; put signal.body "$(events_body 0)"
  put health.status 200
  put health.body "{\"status\":\"ok\",\"version\":\"9.9.9\",\"build_sha\":\"$BUILD\",\"uptime\":12,\"supabase\":\"connected\"}"
  put live.status 200; put live.body "$(events_body 3)"
  put git.intro "$INTRO_SHA"
  put git.catfile.rc 0
  put git.mb.rc 0
}

# run_probe [env-mode] -- sets RC, OUT. mode "notoken" unsets the token.
run_probe() {
  : > "$LOG"
  if [[ "${1:-}" == "notoken" ]]; then
    OUT="$(cd "$CWD" && env -u SENTRY_ACTIONS_RO_TOKEN PATH="$STUB:$PATH" "$SUT" 2>&1)"; RC=$?
  else
    OUT="$(cd "$CWD" && PATH="$STUB:$PATH" SENTRY_ACTIONS_RO_TOKEN="$FAKE_TOKEN" "$SUT" 2>&1)"; RC=$?
  fi
}

# check <desc> <expected-rc> <reason-pattern (bash glob, whole line)>
# Asserts: exit code; output is exactly ONE line matching the reason; the call log
# is non-empty; no UNROUTED entry; no sentinel field value and no token in output.
check() {
  local desc="$1" expected="$2" pat="$3" ok=1 lines
  lines="$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
  if [[ "$RC" -ne "$expected" ]]; then fail "$desc -- expected exit=$expected got exit=$RC :: ${OUT:0:240}"; ok=0; fi
  # shellcheck disable=SC2053  # $pat is a glob on purpose
  if [[ "$lines" != "1" || "$OUT" != $pat ]]; then fail "$desc -- reason line: expected one line matching '$pat', got ($lines lines) '${OUT:0:240}'"; ok=0; fi
  if [[ ! -s "$LOG" ]]; then fail "$desc -- stub call log is empty"; ok=0; fi
  if grep -q '^UNROUTED' "$LOG"; then fail "$desc -- unrouted stub call: $(grep '^UNROUTED' "$LOG" | head -1)"; ok=0; fi
  if [[ "$OUT" == *SENTINEL* || "$OUT" == *987654* || "$OUT" == *"$FAKE_TOKEN"* ]]; then fail "$desc -- output leaks a body field or the token"; ok=0; fi
  (( ok )) && pass "$desc (exit=$RC)"
}

no_git_rev_calls() {  # row 10: an invalid build_sha must never reach git
  if grep -qE '^git \[(cat-file|merge-base)\]' "$LOG"; then fail "$1 -- build_sha reached git: $(grep -E '^git' "$LOG" | head -1)"
  else pass "$1 -- no cat-file/merge-base call"; fi
}

# 1. all green -> 0
set_green; run_probe
check "row 1: signal 0, deployed, liveness 3, extra fields -> PASS" 0 "PASS: 0 production zero-view loads in 14d (proof by absence; fix live at ${BUILD:0:12})"
ROW1_LOG="$(cat "$LOG")"

# 2. signal 1, not deployed, liveness absent -> 1 (signal wins over both)
set_green; put signal.body "$(events_body 1)"; put git.mb.rc 1; put live.body "$(events_body 0)"
run_probe
check "row 2: signal 1, not deployed, liveness 0 -> FAIL (signal wins)" 1 "FAIL: 1 production zero-view loads in 14d, newest 2026-10-09T12:00:00+00:00"
# 2b. a full page reads >=100; a non-ISO timestamp is never printed.
set_green; put signal.body "$(events_body 100)"; run_probe
check "row 2b: full page -> FAIL '>=100'" 1 "FAIL: >=100 production zero-view loads in 14d, newest *"
set_green; put signal.body '{"data":[{"timestamp":"<!-- x --> SENTINEL"}]}'; run_probe
check "row 2c: non-ISO newest timestamp is withheld" 1 "FAIL: 1 production zero-view loads in 14d, newest unknown"

# 3. signal 0, not deployed -> 2
set_green; put git.mb.rc 1; run_probe
check "row 3: merge-base rc 1 -> NOT YET" 2 "NOT YET: fix not live*"

# 4. liveness 0 -> 3 (vacuous-PASS guard)
set_green; put live.body "$(events_body 0)"; run_probe
check "row 4: liveness 0 -> CANNOT ESTABLISH" 3 "CANNOT ESTABLISH: no production server-startup in window"

# 5-7. HTTP 500 on each call -> 3
set_green; put signal.status 500; put signal.body '{"detail":"SENTINEL internal"}'; run_probe
check "row 5: signal query 500 -> 3" 3 "CANNOT ESTABLISH: signal query 500"
set_green; put health.status 500; put health.body 'SENTINEL oops'; run_probe
check "row 6: /health 500 -> 3" 3 "CANNOT ESTABLISH: /health 500"
set_green; put live.status 500; put live.body '{"detail":"SENTINEL internal"}'; run_probe
check "row 7: liveness query 500 -> 3" 3 "CANNOT ESTABLISH: liveness query 500"

# 8-9. signal body not JSON / {} -> 3
set_green; put signal.body '<html>SENTINEL captive portal</html>'; run_probe
check "row 8: signal body not JSON -> 3" 3 "CANNOT ESTABLISH: signal query 200 (body is not an event array)"
set_green; put signal.body '{}'; run_probe
check "row 9: signal body {} -> 3" 3 "CANNOT ESTABLISH: signal query 200 (body is not an event array)"
# 9b. the same shape guard on the liveness arm.
set_green; put live.body '{}'; run_probe
check "row 9b: liveness body {} -> 3" 3 "CANNOT ESTABLISH: liveness query 200 (body is not an event array)"

# 10. invalid build_sha -> 3, never passed to git
for bad in dev HEAD -h "" "${BUILD:0:7}"; do
  set_green; put health.body "{\"status\":\"ok\",\"build_sha\":\"$bad\"}"; run_probe
  check "row 10: build_sha '$bad' -> 3" 3 "CANNOT ESTABLISH: /health build_sha is not a 40-hex commit id"
  no_git_rev_calls "row 10: build_sha '$bad'"
done
set_green; put health.body 'SENTINEL not json'; run_probe
check "row 10b: /health body not JSON -> 3" 3 "CANNOT ESTABLISH: /health build_sha is not a 40-hex commit id"

# 11. empty INTRO -> 3
set_green; put git.intro ""; run_probe
check "row 11: empty introducing commit -> 3" 3 "CANNOT ESTABLISH: introducing commit of this probe not derivable*"
# 11b. cat-file failure -> 3
set_green; put git.catfile.rc 1; run_probe
check "row 11b: build_sha not in checkout -> 3" 3 "CANNOT ESTABLISH: deployed build_sha ${BUILD:0:12} is not a commit in this checkout"

# 12. merge-base rc 128 -> 3
set_green; put git.mb.rc 128; run_probe
check "row 12: merge-base rc 128 -> 3" 3 "CANNOT ESTABLISH: merge-base --is-ancestor rc 128"

# 13. token unset -> 3, no network call (and no git call) at all
set_green; run_probe notoken
if [[ "$RC" -eq 3 && "$OUT" == "CANNOT ESTABLISH: token unset" ]]; then pass "row 13: token unset -> 3 (exit=$RC)"
else fail "row 13: token unset -- expected exit=3 'CANNOT ESTABLISH: token unset', got exit=$RC '${OUT:0:200}'"; fi
if [[ -s "$LOG" ]]; then fail "row 13: token unset -- a stub was called: $(head -1 "$LOG")"
else pass "row 13: token unset -- no network or git call"; fi

# 14. row 1's argv: each Sentry URL is production- and project-pinned, the signal
#     query carries the probe's own feature/op constants, merge-base argument order,
#     the token only on stdin, and no Authorization on /health.
feat_const="$(sed -n 's/^readonly SIGNAL_FEATURE="\([^"]*\)"$/\1/p' "$SUT")"
op_const="$(sed -n 's/^readonly SIGNAL_OP="\([^"]*\)"$/\1/p' "$SUT")"
sentry_lines="$(printf '%s\n' "$ROW1_LOG" | grep -E '^curl .*\[https://sentry\.io/' || true)"
n_sentry="$(printf '%s' "$sentry_lines" | grep -c . || true)"
if [[ "$n_sentry" == "2" ]]; then pass "row 14: two Sentry queries in the all-green run"
else fail "row 14: expected 2 Sentry queries, got '$n_sentry'"; fi
while IFS= read -r l; do
  [[ -z "$l" ]] && continue
  u="$(printf '%s\n' "$l" | grep -oE '\[https://sentry\.io/[^]]*\]')"
  if [[ "$u" == *"environment%3Aproduction"* && "$u" == *"project=4511404943671376"* ]]; then
    pass "row 14: Sentry URL pins environment:production and the project (${u:0:90}...)"
  else fail "row 14: Sentry URL lacks environment%3Aproduction or the project pin: $u"; fi
done <<< "$sentry_lines"
sig_url="$(printf '%s\n' "$sentry_lines" | grep -F "op%3A${op_const}" || true)"
if [[ -n "$feat_const" && -n "$op_const" && "$sig_url" == *"feature%3A${feat_const}%20op%3A${op_const}%20environment%3Aproduction"* ]]; then
  pass "row 14: signal query carries the probe's feature/op constants"
else fail "row 14: signal query does not carry feature:${feat_const} op:${op_const}"; fi
if printf '%s\n' "$ROW1_LOG" | grep -qxF "git [merge-base] [--is-ancestor] [$INTRO_SHA] [$BUILD]"; then
  pass "row 14: merge-base --is-ancestor <INTRO> <build_sha> in that order"
else fail "row 14: merge-base not called as --is-ancestor <INTRO> <build_sha>: $(printf '%s\n' "$ROW1_LOG" | grep '^git \[merge-base' || echo none)"; fi
if printf '%s\n' "$ROW1_LOG" | grep -qxF "git [log] [--diff-filter=A] [--format=%H] [-1] [--] [$PROBE_REL]"; then
  pass "row 14: introducing commit derived from this probe's own path"
else fail "row 14: git log --diff-filter=A not called on $PROBE_REL"; fi
n_auth_ok="$(printf '%s\n' "$ROW1_LOG" | grep -cx 'curl-stdin-auth ok' || true)"
if [[ "$n_auth_ok" == "2" ]] && ! printf '%s\n' "$ROW1_LOG" | grep -qE 'curl-stdin-auth BAD|curl-argv-auth'; then
  pass "row 14: token reaches curl on stdin only"
else fail "row 14: token delivery -- stdin-ok=$n_auth_ok, argv/BAD present?"; fi
if [[ "$ROW1_LOG" == *"$FAKE_TOKEN"* ]]; then fail "row 14: token appears in a stub argv"; else pass "row 14: token on no argv"; fi
health_line="$(printf '%s\n' "$ROW1_LOG" | grep -F '[https://app.soleur.ai/health]' || true)"
if [[ -n "$health_line" && "$health_line" != *"[@-]"* && "$health_line" != *uthorization* ]]; then
  pass "row 14: /health call carries no Authorization"
else fail "row 14: /health call missing or carries auth: ${health_line:0:200}"; fi

# 15. drift: the probe's own constants are what the route's mirrorWarnWithDebounce emits.
if [[ -z "$feat_const" || -z "$op_const" ]]; then
  fail "row 15: could not read SIGNAL_FEATURE/SIGNAL_OP from the probe"
elif [[ ! -f "$ROUTE" ]]; then
  fail "row 15: route.ts not found at $ROUTE"
else
  op_n="$(grep -oF "op: \"${op_const}\"" "$ROUTE" | wc -l | tr -d ' ')"
  if [[ "$op_n" == "1" ]]; then pass "row 15: op: \"${op_const}\" occurs exactly once in route.ts"
  else fail "row 15: op: \"${op_const}\" occurs ${op_n} times in route.ts (want exactly 1)"; fi
  blocks="$(awk -v op="op: \"${op_const}\"" -v ft="feature: \"${feat_const}\"" '
    /mirrorWarnWithDebounce\(/ { inb = 1; hasop = 0; hasft = 0 }
    inb { if (index($0, op)) hasop = 1; if (index($0, ft)) hasft = 1 }
    inb && /^[[:space:]]*\);[[:space:]]*$/ { if (hasop && hasft) found++; inb = 0 }
    END { print found + 0 }' "$ROUTE")"
  if [[ "$blocks" == "1" ]]; then pass "row 15: feature \"${feat_const}\" and op \"${op_const}\" share the mirrorWarnWithDebounce block"
  else fail "row 15: no mirrorWarnWithDebounce block in route.ts carries both feature \"${feat_const}\" and op \"${op_const}\" (found ${blocks})"; fi
fi

printf '\n%d/%d passed\n' "$((total - fails))" "$total"
[[ $fails -eq 0 ]]
