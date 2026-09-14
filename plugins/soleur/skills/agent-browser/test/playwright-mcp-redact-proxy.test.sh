#!/usr/bin/env bash
# Guard-contract suite for playwright-mcp-redact-proxy.py (#7980).
#
# Mirrors redact-a11y-snapshot.test.sh: ok/bad helpers, an instrument
# self-test, helper controls that must REJECT, then the rows, then a verdict
# reported with printf + exit (never through the helpers it backstops) and a
# MIN_ASSERTIONS floor bound ADJACENT to the floor block.
#
# Every session is driven by fixtures/proxy-session-driver.py against the
# table-driven stub fixtures/fake-playwright-mcp.py; every process assertion is
# scoped to the pgid the proxy logs (never a machine-wide name match). Mutants
# are standalone copies written by fixtures/make-proxy-mutant.py (one edit,
# asserted landed by `diff -q` AND inside the named function's ast range).
# `grep -q` reads herestrings or files only, never a producer pipe (SIGPIPE
# under pipefail is a false negative). PROXY_UNDER_TEST overrides the proxy
# path so the suite can be pointed at fixtures/fake-passthrough-proxy.py — the
# pre-fix artefact — to observe the RED rows RED (QG5).
set -euo pipefail
exec 3>&1   # verdict lines from helpers whose stdout is captured by $(...) go here
export TMPDIR="${TMPDIR:-/var/tmp}"
export PLAYWRIGHT_MCP_PROXY_GRACE_S=1

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
SKILL="$REPO_ROOT/plugins/soleur/skills/agent-browser"
PROXY_SHIPPED="$SKILL/scripts/playwright-mcp-redact-proxy.py"
PROXY="${PROXY_UNDER_TEST:-$PROXY_SHIPPED}"
REDACTOR="$SKILL/scripts/redact-a11y-snapshot.py"
FIX="$SKILL/test/fixtures"
STUB="$FIX/fake-playwright-mcp.py"
PASSTHROUGH="$FIX/fake-passthrough-proxy.py"
DRV="$FIX/proxy-session-driver.py"
FACTS="$FIX/session-facts.py"
MUTATE="$FIX/make-proxy-mutant.py"
OD="$FIX/odd-shapes"
# The fixture directory is DERIVED from the .mcp.json pin: a bump that forgets
# to re-capture reddens here instead of testing stale captures.
PIN="$(python3 -c "import json,re,sys; s=json.load(open(sys.argv[1]))['mcpServers']['playwright']['args'][1]; print(re.search(r'@playwright/mcp@([0-9.]+)', s).group(1))" "$REPO_ROOT/.mcp.json")"
FX="$FIX/playwright-mcp-$PIN"
SENTINEL='ZZQP-SENTINEL-7980'
BENIGN='ZZQP-BENIGN-7980'
WORK="$(mktemp -d -t proxy-suite.XXXXXXXX)"
MUT="$WORK/mutants"; mkdir -p "$MUT"; cp "$REDACTOR" "$MUT/"   # every mutant loads the REAL predicate beside it
trap 'rm -rf "$WORK"' EXIT

INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{"roots":{}},"clientInfo":{"name":"suite","version":"0"}}}'
LIST='{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
SNAP='{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}'
NAV='{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"browser_navigate","arguments":{"url":"http://127.0.0.1:1/"}}}'
FIND='{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"browser_find","arguments":{"text":"Token"}}}'
EVAL='{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"browser_evaluate","arguments":{"function":"() => 1"}}}'
SHOT='{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"browser_take_screenshot","arguments":{}}}'
CLOSE='{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"browser_close","arguments":{}}}'
NOTIF='{"jsonrpc":"2.0","method":"notifications/initialized"}'

pass=0; fail=0; cases=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n' "$1"; fail=$((fail + 1)); }

# ---------------------------------------------------------------------------
# Instrument self-test (runs BEFORE any real row): both verdict helpers must
# move their counters or the suite refuses to continue.
# ---------------------------------------------------------------------------
_p0=$pass; _f0=$fail
ok  "instrument self-test: ok() increments"
bad "instrument self-test: bad() increments (EXPECTED, not a real failure)"
if [[ $pass -ne $((_p0 + 1)) || $fail -ne $((_f0 + 1)) ]]; then
  printf 'INSTRUMENT BROKEN: ok()/bad() did not both move\n' >&2; exit 1
fi
pass=0; fail=0; cases=0

# ---------------------------------------------------------------------------
# Session + fact helpers
# ---------------------------------------------------------------------------
# session <name> <proxy> [driver args...] ; prints the out dir. Always appends
# the stub as the server unless the caller already passed --server.
session() {
  local name="$1" proxy="$2"; shift 2
  local out="$WORK/s-$name"; rm -rf "$out"
  local args=("$@")
  local has_server=0; for a in "${args[@]}"; do [[ "$a" == "--server" ]] && has_server=1; done
  if [[ $has_server -eq 0 ]]; then args+=(--server python3 "$STUB"); fi
  python3 "$DRV" --out "$out" --proxy "$proxy" "${args[@]}" >/dev/null 2>&1 || true
  printf '%s' "$out"
}
fact() { python3 "$FACTS" "$1" "$2" "$3" 2>/dev/null || printf 'ERR'; }
export -f fact 2>/dev/null || true
fact_extra() { python3 "$FACTS" "$1" "$2" "$3" "$4" 2>/dev/null || printf 'ERR'; }
rcof() { cat "$1/rc" 2>/dev/null || printf 'none'; }
stderr_has() { grep -qF -- "$2" "$1/stderr.txt"; }   # file, never a pipe

# ---------------------------------------------------------------------------
# Verdict-owning helpers. Each increments `cases`; each is driven with an input
# it MUST reject in the helper control below.
# ---------------------------------------------------------------------------
# assert_redacted_result <label> <out> <id-json> <benign-count>
# The NEGATIVE half (sentinel count 0) is load-bearing; the benign count
# proves the helper can discriminate an over-aggressive rewrite from a leak.
assert_redacted_result() {
  local label="$1" out="$2" id="$3" want_benign="$4"
  cases=$((cases + 1))
  local found sent ben err
  found="$(fact "$out" "$id" found)"; sent="$(fact "$out" "$id" sentinel)"; ben="$(fact "$out" "$id" benign)"; err="$(fact "$out" "$id" isError)"
  if [[ "$found" != "1" ]]; then bad "$label — no response for id $id was delivered"
  elif [[ "$err" == "true" ]]; then bad "$label — result was withheld, not redacted"
  elif [[ "$sent" != "0" ]]; then bad "$label — sentinel survived ($sent occurrences)"
  elif [[ "$ben" != "$want_benign" ]]; then bad "$label — benign count $ben, expected $want_benign (over- or under-rewrite)"
  else ok "$label"; fi
}
# assert_byte_identical <label> <out> <id-json> <fixture.json>
assert_byte_identical() {
  local label="$1" out="$2" id="$3" fixture="$4"
  cases=$((cases + 1))
  local got want
  got="$(fact "$out" "$id" rawline)"; want="$(fact_extra "$out" "$id" expected_line "$fixture")"
  if [[ -z "$got" ]]; then bad "$label — no response for id $id"
  elif [[ "$got" != "$want" ]]; then bad "$label — bytes differ from the stub's line"
  else ok "$label"; fi
}
# assert_withheld <label> <out> <id-json> <reason-needle>
assert_withheld() {
  local label="$1" out="$2" id="$3" needle="$4"
  cases=$((cases + 1))
  local found err sent text
  found="$(fact "$out" "$id" found)"; err="$(fact "$out" "$id" isError)"; sent="$(fact "$out" "$id" sentinel)"; text="$(fact "$out" "$id" text)"
  if [[ "$found" != "1" ]]; then bad "$label — no response for id $id (a dropped result is as RED as a raw one)"
  elif [[ "$err" != "true" ]]; then bad "$label — not withheld (isError=$err)"
  elif [[ "$sent" != "0" ]]; then bad "$label — sentinel present in the withheld result"
  elif [[ "$text" != *"$needle"* ]]; then bad "$label — reason lacks '$needle'"
  elif [[ "$text" != *"snapshot withheld:"* && "$text" != *"refused:"* ]]; then bad "$label — text lacks the pinned prefix"
  elif [[ "$text" != *"call browser_snapshot with no filename"* ]]; then bad "$label — caveat line missing"
  else ok "$label"; fi
}
# assert_refused_start <label> <out> <reason-needle>
assert_refused_start() {
  local label="$1" out="$2" needle="$3"
  cases=$((cases + 1))
  local rc lines pg
  rc="$(rcof "$out")"; lines="$(fact "$out" 0 lines)"; pg="$(cat "$out/child_pgid" 2>/dev/null || true)"
  if [[ "$rc" != "2" ]]; then bad "$label — exit $rc, expected 2"
  elif ! stderr_has "$out" "refusing to start:"; then bad "$label — no 'refusing to start:' line"
  elif ! stderr_has "$out" "$needle"; then bad "$label — reason lacks '$needle'"
  elif [[ "$lines" != "0" ]]; then bad "$label — wrote $lines stdout line(s) before refusing"
  elif [[ -n "$pg" ]]; then bad "$label — a child was spawned (pgid $pg)"
  else ok "$label"; fi
}
# assert_stderr_marker <label> <out> <needle> <count>
assert_stderr_marker() {
  local label="$1" out="$2" needle="$3" want="$4"
  cases=$((cases + 1))
  local n; n="$(fact "$out" 0 "stderr_count:$needle")"
  if [[ "$n" == "$want" ]]; then ok "$label"; else bad "$label — '$needle' appears $n time(s), expected $want"; fi
}
# assert_group_empty <label> <out>
assert_group_empty() {
  local label="$1" out="$2"
  cases=$((cases + 1))
  local pg n; pg="$(cat "$out/child_pgid" 2>/dev/null || true)"; n="$(cat "$out/group_after" 2>/dev/null || echo -1)"
  if [[ -z "$pg" ]]; then bad "$label — proxy never logged the child pgid"
  elif [[ "$n" != "0" ]]; then bad "$label — group $pg still has $n member(s)"
  else ok "$label"; fi
}
# assert_rc <label> <out> <expected>
assert_rc() {
  local label="$1" out="$2" want="$3"
  cases=$((cases + 1))
  local rc; rc="$(rcof "$out")"
  if [[ "$rc" == "$want" ]]; then ok "$label"; else bad "$label — exit $rc, expected $want"; fi
}
# assert_true <label> <shell-test...> — for one-off observables
assert_true() {
  local label="$1"; shift
  cases=$((cases + 1))
  if "$@"; then ok "$label"; else bad "$label"; fi
}

# ---------------------------------------------------------------------------
# Helper control: every verdict-owning helper driven with an input it MUST
# reject, against the passthrough (leaks by construction) or synthetic dirs.
# Counters are unwound afterwards; the suite refuses to continue if any helper
# failed to reject.
# ---------------------------------------------------------------------------
_helper_control() {
  local _p=$pass _f=$fail _c=$cases
  local leak; leak="$(session hc-leak "$PASSTHROUGH" --send "$INIT" --send "$SNAP" --end eof)"
  assert_redacted_result 'helper control: assert_redacted_result must REJECT a leak (EXPECTED)' "$leak" 3 1
  assert_withheld 'helper control: assert_withheld must REJECT a raw forwarded result (EXPECTED)' "$leak" 3 'x'
  assert_byte_identical 'helper control: assert_byte_identical must REJECT a differing line (EXPECTED)' "$leak" 3 "$FX/navigate.json"
  assert_refused_start 'helper control: assert_refused_start must REJECT a started proxy (EXPECTED)' "$leak" 'x'
  assert_stderr_marker 'helper control: assert_stderr_marker must REJECT a wrong count (EXPECTED)' "$leak" 'child pgid' 7
  local synth="$WORK/s-hc-synth"; mkdir -p "$synth"; printf '' > "$synth/child_pgid"; printf '3\n' > "$synth/group_after"; printf '0\n' > "$synth/rc"
  assert_group_empty 'helper control: assert_group_empty must REJECT a missing pgid (EXPECTED)' "$synth"
  assert_rc 'helper control: assert_rc must REJECT a wrong exit (EXPECTED)' "$synth" 9
  assert_true 'helper control: assert_true must REJECT false (EXPECTED)' false
  if [[ $fail -ne $((_f + 8)) ]]; then
    printf 'HELPER CONTROL BROKEN: expected 8 rejections, fail %d->%d\n' "$_f" "$fail" >&2; exit 1
  fi
  pass=$_p; fail=$_f; cases=$_c
}

if [[ ! -f "$PROXY" ]]; then
  printf 'FAIL - proxy missing at %s\n\nRED: the proxy does not exist yet (expected pre-implementation state).\n' "$PROXY"; exit 1
fi
if [[ ! -d "$FX" ]]; then
  printf 'FAIL - fixture directory %s missing: the .mcp.json pin is %s; re-run fixtures/capture-playwright-mcp-fixtures.py\n' "$FX" "$PIN"; exit 1
fi
_helper_control

# ---------------------------------------------------------------------------
# Instrument rows: the stub, driven through the PASSTHROUGH (no rewrite), must
# produce the artefacts the matrix rows assert on. A stub that does not write
# the file / log the request / hold the group would make rows 6/7/12/19/20/27
# vacuous.
# ---------------------------------------------------------------------------
out="$(session inst "$PASSTHROUGH" --env FAKE_PW_ARGV_OUT="$WORK/inst-argv" --env FAKE_PW_REQUEST_LOG="$WORK/inst-req" \
  --send "$INIT" --send '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{"filename":"'"$WORK"'/inst-raw.yml"}}}' --send '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}' --end eof)"
assert_true 'instrument: stub WRITES the raw tree for a filename call' test -s "$WORK/inst-raw.yml"
assert_true 'instrument: the written file carries the sentinel' grep -qF "$SENTINEL" "$WORK/inst-raw.yml"
assert_true 'instrument: stub request log records the call' grep -qF '"name": "browser_snapshot"' "$WORK/inst-req"
assert_true 'instrument: stub records its argv' test -f "$WORK/inst-argv"
assert_true 'instrument: passthrough forwards the raw tree (known negative)' test "$(fact "$out" 4 sentinel)" != "0"
hold="$(session inst-hold "$PASSTHROUGH" --env FAKE_PW_HOLD=1 --send "$INIT" --end eof --timeout 3)"
assert_true 'instrument: FAKE_PW_HOLD keeps the group alive past stdin EOF (passthrough does no teardown)' test "$(cat "$hold/group_after")" -gt 0
pkill -KILL -g "$(cat "$hold/child_pgid")" 2>/dev/null || true

# ---------------------------------------------------------------------------
# FR1/FR2/FR2b/FR10/FR10b/FR11 — the shipped path, one canonical session
# ---------------------------------------------------------------------------
main="$(session main "$PROXY" --send "$INIT" --send "$NOTIF" --send "$LIST" --send "$SNAP" --send "$NAV" --send "$FIND" --send "$EVAL" --send "$SHOT" --send "$CLOSE" --end eof)"
assert_byte_identical 'FR1/FR11: initialize result forwarded byte-identical' "$main" 1 "$FX/initialize.json"
assert_redacted_result 'FR2: bare browser_snapshot — password/Token redacted, Notes intact (P3)' "$main" 3 1
assert_true 'FR2: <redacted> marker present on the credential rows' bash -c '[[ "$(python3 "$1" "$2" 3 text)" == *"\"Enter your password\" [ref=e4]: <redacted>"* && "$(python3 "$1" "$2" 3 text)" == *"\"Token\" [ref=e6]: <redacted>"* ]]' _ "$FACTS" "$main"
assert_true 'FR2: Email address survives in clear (must-PASS)' bash -c '[[ "$(python3 "$1" "$2" 3 text)" == *"probe-user@example.invalid"* ]]' _ "$FACTS" "$main"
assert_redacted_result 'FR2b/P7: browser_find result redacted by SHAPE (no tool-name allowlist)' "$main" 6 0
assert_true 'FR10b: tree-carrying result ends with the trailer block' test "$(fact "$main" 3 trailer)" = "1"
assert_true 'FR10b: browser_find result ends with the trailer block' test "$(fact "$main" 6 trailer)" = "1"
assert_true 'FR10b: browser_navigate (no tree) carries NO trailer' test "$(fact "$main" 5 trailer)" = "0"
assert_byte_identical 'FR11/P1: browser_navigate forwarded byte-identical' "$main" 5 "$FX/navigate.json"
assert_byte_identical 'FR11/P2: browser_evaluate object result forwarded byte-identical (the CLI envelope arm would refuse it)' "$main" 7 "$FX/evaluate.json"
assert_byte_identical 'FR11/P4: screenshot (text + image) forwarded byte-identical' "$main" 8 "$FX/screenshot.json"
assert_byte_identical 'FR11/P5: browser_close result (no isClose on the wire) forwarded' "$main" 9 "$FX/close.json"
assert_true 'FR10: tools/list — browser_snapshot description carries the marker' bash -c 'python3 - "$1" <<'"'"'PY'"'"'
import json,sys
for o in json.load(open(sys.argv[1]+"/responses.json")):
    if isinstance(o,dict) and o.get("id")==2:
        d=[t["description"] for t in o["result"]["tools"] if t["name"]=="browser_snapshot"][0]
        sys.exit(0 if d.endswith("filename is refused — call browser_snapshot with no filename.]") and "redacted in flight" in d else 1)
sys.exit(1)
PY' _ "$main"
assert_true 'FR10: other tool descriptions untouched' bash -c 'python3 - "$1" "$2" <<'"'"'PY'"'"'
import json,sys
fx={t["name"]:t["description"] for t in json.load(open(sys.argv[2]))["result"]["tools"]}
for o in json.load(open(sys.argv[1]+"/responses.json")):
    if isinstance(o,dict) and o.get("id")==2:
        got={t["name"]:t["description"] for t in o["result"]["tools"]}
        sys.exit(0 if all(got[n]==fx[n] for n in fx if n!="browser_snapshot") else 1)
sys.exit(1)
PY' _ "$main" "$FX/tools-list.json"
assert_stderr_marker 'B7: initialize logs what was wrapped' "$main" 'wrapping Playwright' 1
assert_stderr_marker 'B4: child pgid logged once' "$main" 'child pgid' 1
assert_stderr_marker 'B10: teardown line on stdin EOF' "$main" 'child exited rc=0' 1
assert_group_empty 'FR14: stdin EOF → child group empty' "$main"
assert_rc 'FR14: clean child exit → proxy exit 0' "$main" 0
assert_true 'NFR2: every stdout line of a full session is a JSON-RPC object' test "$(fact "$main" 0 alljson)" = "1"

# roots/list from the server (P5): forwarded byte-identical, map untouched
roots="$(session roots "$PROXY" --env FAKE_PW_ROOTS_COLLIDE=1 --send "$INIT" --send "$SNAP" --end eof)"
assert_true 'FR11/P5: roots/list server request forwarded (with a COLLIDING id)' bash -c 'grep -qF "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"roots/list\"}" "$1/stdout.bin"' _ "$roots"
assert_redacted_result 'FR11b: colliding roots/list id — result still redacted and delivered (classify keys on result/error)' "$roots" 3 1

# ---------------------------------------------------------------------------
# FR3 — refusals before the server sees the call (filename; ""; _meta)
# ---------------------------------------------------------------------------
ref="$(session refuse "$PROXY" --env FAKE_PW_REQUEST_LOG="$WORK/ref-req" --send "$INIT" \
  --send '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{"filename":"'"$WORK"'/ref-raw.yml"}}}' \
  --send '{"jsonrpc":"2.0","id":"11","method":"tools/call","params":{"name":"browser_snapshot","arguments":{"filename":""}}}' \
  --send '{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{"_meta":{"json":true}}}}' \
  --send '{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"browser_navigate","arguments":{"_meta":{"raw":true},"url":"x"}}}' \
  --send "$SNAP" --end eof)"
assert_withheld 'FR3: browser_snapshot + filename refused (id type int preserved)' "$ref" 10 'filename'
assert_withheld 'FR3: browser_snapshot + filename:"" refused on KEY presence (id type str preserved)' "$ref" '"11"' 'filename'
assert_withheld 'FR3: tools/call with arguments._meta refused' "$ref" 12 '_meta'
assert_withheld 'FR3: _meta refused on ANY tool, not only browser_snapshot' "$ref" 13 '_meta'
assert_true 'FR3: the refused calls never reached the stub (request log)' bash -c '! grep -qF "filename" "$1" && ! grep -qF "_meta" "$1"' _ "$WORK/ref-req"
assert_true 'FR3: no raw file was written' test ! -e "$WORK/ref-raw.yml"
assert_redacted_result 'FR3: the bare call after the refusals is still served' "$ref" 3 1
assert_stderr_marker 'FR7b: one pinned stderr line per refusal' "$ref" 'refused tool=' 4
assert_true 'FR7b/B9: stderr refusal lines never quote the input path' bash -c '! grep -qF "ref-raw.yml" "$1/stderr.txt"' _ "$ref"

# ---------------------------------------------------------------------------
# FR4 — the injected flag
# ---------------------------------------------------------------------------
argv="$(session argv "$PROXY" --env FAKE_PW_ARGV_OUT="$WORK/argv-out" --send "$INIT" --end eof)"
assert_true 'FR4: child argv ends with --snapshot-mode none' bash -c '[[ "$(tail -n 2 "$1" | tr "\n" " ")" == "--snapshot-mode none " ]]' _ "$WORK/argv-out"

# ---------------------------------------------------------------------------
# FR5 — refuse to start (no child spawned)
# ---------------------------------------------------------------------------
NOSIB="$WORK/nosib"; mkdir -p "$NOSIB"; cp "$PROXY" "$NOSIB/proxy.py"
r="$(session nosib "$NOSIB/proxy.py" --send "$INIT" --end eof --timeout 3)"
assert_refused_start 'FR5: proxy beside no redactor refuses to start' "$r" 'missing'
r="$(session savesess "$PROXY" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --save-session)"
assert_refused_start 'FR5: --save-session in the wrapped argv refuses to start' "$r" 'save-session'
printf '{"saveSession": true}\n' > "$WORK/cfg-save.json"
r="$(session savecfg "$PROXY" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --config "$WORK/cfg-save.json")"
assert_refused_start 'FR5: config saveSession (via --config) refuses to start' "$r" 'saveSession'
r="$(session savecfgenv "$PROXY" --env PLAYWRIGHT_MCP_CONFIG="$WORK/cfg-save.json" --send "$INIT" --end eof --timeout 3)"
assert_refused_start 'FR5: config saveSession (via $PLAYWRIGHT_MCP_CONFIG) refuses to start' "$r" 'saveSession'
printf '{"snapshot": {"mode": "full"}}\n' > "$WORK/cfg-ok.json"
r="$(session cfgok "$PROXY" --send "$INIT" --send "$SNAP" --end eof --server python3 "$STUB" --config="$WORK/cfg-ok.json")"
assert_redacted_result 'FR5 companion: a benign --config=<file> starts and serves' "$r" 3 1
r="$(session debug "$PROXY" --env DEBUG=pw:mcp:server:response --send "$INIT" --end eof --timeout 3)"
assert_refused_start 'FR5: DEBUG=pw:mcp* refuses to start (reason names the variable)' "$r" 'DEBUG'
assert_true 'FR5: the DEBUG reason never quotes the value' bash -c '! grep -qF "pw:mcp:server:response" "$1/stderr.txt"' _ "$r"
r="$(session debugstar "$PROXY" --env 'DEBUG=*' --send "$INIT" --end eof --timeout 3)"
assert_refused_start 'FR5: DEBUG=* refuses to start' "$r" 'DEBUG'
r="$(session debugfile "$PROXY" --env DEBUG_FILE="$WORK/dbg" --send "$INIT" --end eof --timeout 3)"
assert_refused_start 'FR5: DEBUG_FILE refuses to start' "$r" 'DEBUG_FILE'
r="$(session debugother "$PROXY" --env DEBUG=express:router --send "$INIT" --send "$SNAP" --end eof)"
assert_redacted_result 'FR5 companion: an unrelated DEBUG namespace starts and serves' "$r" 3 1
usage_rc=0; python3 "$PROXY" -- </dev/null >"$WORK/usage.out" 2>"$WORK/usage.err" || usage_rc=$?
assert_true 'B1: empty server argv → exit 2, usage on stderr, nothing on stdout' bash -c '[[ "$1" == "2" ]] && grep -qF "refusing to start: usage:" "$2" && [[ ! -s "$3" ]]' _ "$usage_rc" "$WORK/usage.err" "$WORK/usage.out"
usage_rc=0; python3 "$PROXY" python3 "$STUB" </dev/null >"$WORK/usage2.out" 2>"$WORK/usage2.err" || usage_rc=$?
assert_true 'B1: missing -- separator → exit 2 (the server argv is never guessed)' bash -c '[[ "$1" == "2" ]] && grep -qF "no \`--\` separator" "$2"' _ "$usage_rc" "$WORK/usage2.err"

# ---------------------------------------------------------------------------
# FR6 — redactor variants make the proxy refuse (self-test), FR7 — raising predicate
# ---------------------------------------------------------------------------
mk_variant() {  # <dir> <python-replace-old> <python-replace-new>
  mkdir -p "$1"; cp "$PROXY" "$1/proxy.py"
  python3 - "$REDACTOR" "$1/redact-a11y-snapshot.py" "$2" "$3" <<'PY'
import sys
src=open(sys.argv[1]).read(); old, new = sys.argv[3], sys.argv[4].encode().decode("unicode_escape")
assert src.count(old)==1, (old, src.count(old))
open(sys.argv[2],"w").write(src.replace(old,new))
PY
}
mk_variant "$WORK/v-identity" 'def redact_text(text: str) -> str:' 'def redact_text(text: str) -> str:\n    return text\n\ndef _unused_redact_text(text: str) -> str:'
r="$(session v-identity "$WORK/v-identity/proxy.py" --send "$INIT" --end eof --timeout 3)"
assert_refused_start 'FR6: a redactor returning its input unchanged → refuse to start' "$r" 'self-test'
mk_variant "$WORK/v-append" 'def redact_text(text: str) -> str:' 'def redact_text(text: str) -> str:\n    return text + " <redacted>"\n\ndef _unused_redact_text(text: str) -> str:'
r="$(session v-append "$WORK/v-append/proxy.py" --send "$INIT" --end eof --timeout 3)"
assert_refused_start 'FR6/row 9 input: a redactor appending <redacted> without removing the value → refuse' "$r" 'self-test'
mk_variant "$WORK/v-false" 'def looks_like_a11y_tree(value: str) -> bool:' 'def looks_like_a11y_tree(value: str) -> bool:\n    return False\n\ndef _unused_looks(value: str) -> bool:'
r="$(session v-false "$WORK/v-false/proxy.py" --send "$INIT" --end eof --timeout 3)"
assert_refused_start 'FR6/row 29 input: constant-False looks_like_a11y_tree → refuse' "$r" 'looks_like_a11y_tree'
# raises only for long text, so the startup self-test passes (row 34's input)
mk_variant "$WORK/v-raise" 'def redact_text(text: str) -> str:' 'def redact_text(text: str) -> str:\n    if len(text) > 200:\n        raise RuntimeError("boom")\n    return _orig_redact_text(text)\n\ndef _orig_redact_text(text: str) -> str:'
r="$(session v-raise "$WORK/v-raise/proxy.py" --send "$INIT" --send "$SNAP" --end eof)"
assert_withheld 'FR7: redact_text raising → withheld, no sentinel, session continues' "$r" 3 'raised'
assert_stderr_marker 'FR7b: one withheld line for the raise' "$r" 'withheld tool=browser_snapshot' 1
assert_rc 'FR7: the session ended cleanly after the withhold' "$r" 0
# renamed provider name → refuse (the four-name contract)
mk_variant "$WORK/v-rename" '_looks_like_a11y_tree = looks_like_a11y_tree' '_looks_like_a11y_tree = looks_like_a11y_tree\ndel looks_like_a11y_tree'
r="$(session v-rename "$WORK/v-rename/proxy.py" --send "$INIT" --end eof --timeout 3)"
assert_refused_start 'B2: a redactor missing one of the four names → refuse (not a per-result withhold)' "$r" 'does not export looks_like_a11y_tree'

# ---------------------------------------------------------------------------
# FR8/FR9/FR11b — odd shapes through the shipped proxy
# ---------------------------------------------------------------------------
odd() { session "odd-$1" "$PROXY" --env FAKE_PW_RESULT_FILE="$OD/$1.json" "${@:2}" --send "$INIT" --send "$SNAP" --end eof; }
r="$(odd two-text-blocks)"; assert_redacted_result 'row 2 input: two text blocks both redacted (second-member)' "$r" 3 2
r="$(odd link-result)";  assert_withheld 'FR9: - [Snapshot]( link line → withheld (drift arm)' "$r" 3 'output directory'
assert_true 'FR9: the reason names the directory only, never the server-emitted path' bash -c '! grep -qF "page-2026" "$1/stdout.bin" && ! grep -qF "page-2026" "$1/stderr.txt"' _ "$r"
r="$(odd structured-content)"; assert_withheld 'FR11b: structuredContent → withheld' "$r" 3 'unrecognised result shape'
r="$(odd resource-block)"; assert_withheld 'FR11b: resource block → withheld' "$r" 3 'unrecognised result shape'
r="$(odd meta-in-result)"; assert_withheld 'FR11b: _meta in the result → withheld' "$r" 3 'unrecognised result shape'
r="$(odd result-and-method)"; assert_withheld 'FR11b: result AND method → withheld' "$r" 3 'unrecognised result shape'
r="$(odd no-content)"; assert_withheld 'FR11b: no content key → withheld' "$r" 3 'unrecognised result shape'
r="$(odd result-string)"; assert_withheld 'FR11b: result is a string → withheld' "$r" 3 'unrecognised result shape'
r="$(odd empty-content)"; assert_byte_identical 'edge: content: [] forwarded unchanged' "$r" 3 "$OD/empty-content.json"
r="$(odd error-with-data)"; assert_withheld 'row 31: error with structured data → withheld' "$r" 3 'structured data'
r="$(odd error-no-data)"; assert_true 'row 31 companion: data-less error forwarded byte-identical' bash -c '[[ "$(python3 "$1" "$2" 3 rawline | base64 -d)" == "{\"jsonrpc\":\"2.0\",\"id\":3,\"error\":{\"code\":-32000,\"message\":\"boom\"}}" ]]' _ "$FACTS" "$r"
r="$(odd value-contains-link-substring)"; assert_redacted_result 'row 36: a VALUE containing the link substring is delivered redacted (whole-line startswith)' "$r" 3 1
r="$(odd value-contains-brace)"; assert_redacted_result 'P6 canary: a value containing { is delivered redacted (no envelope sniff)' "$r" 3 1
r="$(odd tree-no-credential)"; assert_true 'row 18: a tree with no credential-named field still gets the trailer' test "$(fact "$r" 3 trailer)" = "1"
r="$(odd invalid-utf8)"; assert_redacted_result 'row 14: one invalid UTF-8 byte in the text → decoded with replacement, still redacted' "$r" 3 1
r="$(odd unparsable-line)"; assert_true 'edge: unparsable server line dropped with a stderr line; session continues' bash -c 'grep -qF "dropped unparsable server line" "$1/stderr.txt" && [[ "$(cat "$1/rc")" == "0" ]]' _ "$r"
r="$(session odd-list "$PROXY" --env FAKE_PW_RESULT_FILE="$OD/list-two-results.json" --send "$INIT" --send "$SNAP" --send '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}' --end eof)"
assert_withheld 'row 21: list-shaped server line — first pending id answered by error_result' "$r" 3 'list line'
assert_withheld 'row 21: list-shaped server line — second pending id answered' "$r" 4 'list line'
assert_true 'row 21: the list line itself was not forwarded' bash -c '! grep -q "^\[" "$1/stdout.bin"' _ "$r"
# tools/list without a tools key: fed from a scratch fixture dir
NOTOOLS="$WORK/notools"; mkdir -p "$NOTOOLS"; cp "$FX/initialize.json" "$NOTOOLS/"; cp "$OD/tools-list-no-tools.json" "$NOTOOLS/tools-list.json"; cp "$FX/snapshot.json" "$NOTOOLS/"
r="$(session notools "$PROXY" --env FAKE_PW_FIXTURE_DIR="$NOTOOLS" --send "$INIT" --send "$LIST" --send "$SNAP" --end eof)"
assert_byte_identical 'FR10/row 25: tools/list without a tools key forwarded unchanged (fail-safe)' "$r" 2 "$OD/tools-list-no-tools.json"
assert_stderr_marker 'FR10/row 25: annotate failure noted on stderr' "$r" 'annotate failed' 1
assert_redacted_result 'FR10/row 25: the session continues after the annotate failure' "$r" 3 1
# unknown-id response dropped (row 23 shipped side)
r="$(session unprompted "$PROXY" --env FAKE_PW_UNPROMPTED=1 --send "$INIT" --send "$SNAP" --end eof)"
assert_true 'row 23: an unprompted result (id never sent) is dropped; no sentinel anywhere on stdout' bash -c '[[ "$(python3 "$1" "$2" 999 found)" == "0" ]] && ! grep -qF "ZZQP-SENTINEL-7980" "$2/stdout.bin"' _ "$FACTS" "$r"
assert_stderr_marker 'row 23: dropped unknown-id response noted' "$r" 'dropped unknown-id response' 1
# FR8 — over the cap
python3 - "$WORK/big.json" <<'PY'
import json,sys
big='- textbox "Token" [ref=e1]: ZZQP-SENTINEL-7980\n' + ('- textbox "Notes" [ref=e2]: ZZQP-BENIGN-7980\n' * (4*1024*1024 // 44 + 2))
assert len(big.encode()) > 4*1024*1024
json.dump({"result":{"content":[{"type":"text","text":big}]}}, open(sys.argv[1],"w"))
PY
r="$(session big "$PROXY" --env FAKE_PW_RESULT_FILE="$WORK/big.json" --send "$INIT" --send "$SNAP" --end eof --timeout 20)"
assert_withheld 'FR8: text over MAX_INPUT_BYTES → withheld' "$r" 3 'size cap'
assert_stderr_marker 'FR8: withheld line on stderr' "$r" 'withheld tool=browser_snapshot' 1
# row 30 — ids keyed (type, value)
r="$(session idtype "$PROXY" --send "$INIT" --send "$LIST" --send '{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}' --end eof)"
assert_true 'row 30: id 2 (tools/list) and id "2" (tools/call) are classified by their own requests' bash -c 'python3 - "$1" <<'"'"'PY'"'"'
import json,sys
R=json.load(open(sys.argv[1]+"/responses.json")); L=[o for o in R if isinstance(o,dict) and o.get("id")==2]; S=[o for o in R if isinstance(o,dict) and o.get("id")=="2"]
ok = L and "tools" in L[0].get("result",{}) and any("redacted in flight" in t["description"] for t in L[0]["result"]["tools"] if t["name"]=="browser_snapshot")
ok = ok and S and "content" in S[0].get("result",{}) and not S[0]["result"].get("isError") and "ZZQP-SENTINEL" not in json.dumps(S[0])
sys.exit(0 if ok else 1)
PY' _ "$r"
# row 26 — unparsable client line
r="$(session badclient "$PROXY" --send "$INIT" --send 'not json' --send "$SNAP" --end eof)"
assert_stderr_marker 'row 26: unparsable client line forwarded raw with a stderr note' "$r" 'forwarded unparsable client line' 1
assert_redacted_result 'row 26: the next request is still relayed' "$r" 3 1
# row 38 — client list line dropped
r="$(session listclient "$PROXY" --env FAKE_PW_REQUEST_LOG="$WORK/listclient-req" --send "$INIT" --send '[{"jsonrpc":"2.0","id":40,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}]' --send "$SNAP" --end eof)"
assert_stderr_marker 'row 38: client list line dropped with a stderr note' "$r" 'dropped list line from client' 1
assert_redacted_result 'row 38: the bare call after the dropped list line is still served' "$r" 3 1
# row 37 — a 65 MiB line: one clear MiB past MAX_LINE_BYTES (a line of exactly 64 MiB parses and is caught by the 4 MiB cap instead)
r="$(session oversize "$PROXY" --env FAKE_PW_OVERSIZE=$((65*1024*1024)) --send "$INIT" --send "$SNAP" --end eof --timeout 40)"
assert_withheld 'row 37: a line over MAX_LINE_BYTES is discarded and the pending call answered oversize' "$r" 3 'oversize'
assert_stderr_marker 'row 37: discard noted with the byte count only' "$r" 'discarding oversize server line' 1

# ---------------------------------------------------------------------------
# FR14 — lifecycle against the stub's pgid (HOLD models Chrome)
# ---------------------------------------------------------------------------
r="$(session hold-eof "$PROXY" --env FAKE_PW_HOLD=1 --send "$INIT" --end eof)"
assert_group_empty 'FR14/row 12: stdin EOF with a holding child → group empty (SIGKILL after grace)' "$r"
assert_stderr_marker 'FR14: SIGKILL-after-grace line' "$r" 'survived SIGTERM; SIGKILL sent' 1
r="$(session hold-term "$PROXY" --env FAKE_PW_HOLD=1 --send "$INIT" --end sigterm)"
assert_group_empty 'FR14/row 27: SIGTERM to the proxy → group empty' "$r"
r="$(session exit3 "$PROXY" --env FAKE_PW_EXIT_CODE=3 --send "$INIT" --send "$SNAP" --end none --timeout 5)"
assert_rc 'FR14/row 28: stub exit 3 → proxy exit 3' "$r" 3
assert_stderr_marker 'FR14: child exit logged' "$r" 'child exited rc=3' 1
r="$(session killchild "$PROXY" --send "$INIT" --end killchild --timeout 5)"
assert_rc 'FR14/row 28: stub group killed by SIGTERM → proxy exit 143 (clamped), never 241 or 0' "$r" 143
assert_stderr_marker 'FR14: the signal is named on stderr' "$r" 'child exited rc=-15 signal=15' 1

# ---------------------------------------------------------------------------
# FR13 / NFR1 / NFR3 — structure, with the redactor as oracle
# ---------------------------------------------------------------------------
assert_true 'FR13: no re.* call, no def redact_text, exactly one spec_from_file_location, no credential-shaped literal outside self_test/docstring' python3 - "$PROXY" "$REDACTOR" <<'PY'
import ast, sys, importlib.util
src=open(sys.argv[1]).read(); t=ast.parse(src)
spec=importlib.util.spec_from_file_location('r', sys.argv[2]); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
re_calls=[n for n in ast.walk(t) if isinstance(n,ast.Call) and isinstance(n.func,ast.Attribute) and isinstance(n.func.value,ast.Name) and n.func.value.id=='re']
defs=[n.name for n in ast.walk(t) if isinstance(n,ast.FunctionDef)]
sffl=sum(1 for n in ast.walk(t) if isinstance(n,ast.Call) and isinstance(n.func,ast.Attribute) and n.func.attr=='spec_from_file_location')
doc=ast.get_docstring(t, clean=False)
self_test=next(n for n in ast.walk(t) if isinstance(n,ast.FunctionDef) and n.name=='self_test')
inside=lambda n: self_test.lineno <= n.lineno <= self_test.end_lineno
bad=[n.value for n in ast.walk(t) if isinstance(n,ast.Constant) and isinstance(n.value,str) and n.value!=doc and not inside(n) and m._is_credential_name(n.value)]
# the self_test body must be the ONLY function carrying such literals, and it must carry at least one (the sentinel row)
st=[n.value for n in ast.walk(self_test) if isinstance(n,ast.Constant) and isinstance(n.value,str) and m._is_credential_name(n.value)]
sys.exit(0 if not re_calls and 'redact_text' not in defs and sffl==1 and not bad and st else 1)
PY
assert_true 'NFR1: stdlib-only imports' python3 - "$PROXY" <<'PY'
import ast,sys
t=ast.parse(open(sys.argv[1]).read())
mods=sorted({(n.names[0].name if isinstance(n, ast.Import) else n.module).split('.')[0] for n in ast.walk(t) if isinstance(n,(ast.Import,ast.ImportFrom))})
allowed={'__future__','importlib','json','os','selectors','signal','subprocess','sys','typing'}
sys.exit(0 if set(mods) <= allowed else 1)
PY
assert_true 'NFR3: no threading' bash -c '[[ "$(grep -c threading "$1")" == "0" ]]' _ "$PROXY"

# ---------------------------------------------------------------------------
# P6 — parity with the CLI on every tree-carrying fixture (P-ONE)
# ---------------------------------------------------------------------------
parity_n=0
for f in "$FX"/*.json "$OD"/*.json; do
  b="$(basename "$f" .json)"
  [[ "$b" == "snapshot-meta-json" ]] && continue   # the CLI's JSON arm redacts {"snapshot": …}; in-process redact_text does not — refused upstream by B5
  text="$(python3 -c 'import json,sys; o=json.load(open(sys.argv[1])); r=o.get("result"); c=r.get("content") if isinstance(r,dict) else None; print("\n".join(b.get("text","") for b in c if isinstance(b,dict) and b.get("type")=="text") if isinstance(c,list) else "")' "$f" 2>/dev/null || true)"
  [[ -z "$text" ]] && continue
  grep -q '^- \[Snapshot\](' <<<"$text" && continue   # drift arm withholds these by design (FR9)
  python3 -c 'import importlib.util,sys; s=importlib.util.spec_from_file_location("r",sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); sys.exit(0 if m.looks_like_a11y_tree(sys.stdin.read()) else 1)' "$REDACTOR" <<<"$text" || continue
  p="$(session "par-$b" "$PROXY" --env FAKE_PW_RESULT_FILE="$f" --send "$INIT" --send "$SNAP" --end eof)"
  [[ "$(fact "$p" 3 isError)" == "true" ]] && continue   # withheld shapes are asserted by their own rows above
  parity_n=$((parity_n + 1))
  cases=$((cases + 1))
  if python3 - "$FACTS" "$p" "$REDACTOR" "$f" <<'PYPAR'
import json, subprocess, sys
facts, out, redactor, fixture = sys.argv[1:]
got = subprocess.run([sys.executable, facts, out, "3", "text"], capture_output=True, text=True).stdout
trailer = "\n[Soleur: redacted in flight by playwright-mcp-redact-proxy]"
if not got.endswith(trailer): sys.exit(2)
got = got[: -len(trailer)]
text = "\n".join(b.get("text", "") for b in json.load(open(fixture))["result"]["content"] if isinstance(b, dict) and b.get("type") == "text")
cli = subprocess.run([sys.executable, redactor], input=text.encode(), capture_output=True)
if cli.returncode != 0: sys.exit(3)
sys.exit(0 if got.rstrip("\n") == cli.stdout.decode().rstrip("\n") else 1)
PYPAR
  then ok "P6 parity: proxy output == CLI output on $b"; else bad "P6 parity: proxy output differs from the CLI on $b (2 = no trailer, 3 = CLI failed)"; fi
done
assert_true "P6 parity population floor: $parity_n tree-carrying fixtures (>= 4)" test "$parity_n" -ge 4

# ---------------------------------------------------------------------------
# Guard 1 mutation matrix — standalone copies, one edit each, asserted landed
# ---------------------------------------------------------------------------
# mutant <name> <function> <old> <new> ; prints path or empty on failure
mutant() {
  local name="$1" func="$2" old="$3" new="$4"
  local out="$MUT/$name.py"
  cases=$((cases + 1))
  if python3 "$MUTATE" "$PROXY_SHIPPED" "$out" "$func" "$old" "$new" >/dev/null 2>"$MUT/$name.err" && ! diff -q "$PROXY_SHIPPED" "$out" >/dev/null; then
    ok "mutant $name landed inside $func" >&3; printf '%s' "$out"
  else
    bad "mutant $name did NOT land: $(cat "$MUT/$name.err")" >&3; printf ''
  fi
}
# leaks <out> <id> — true only when a response for <id> was DELIVERED and carries the sentinel
leaks() { [[ "$(fact "$1" "$2" found)" == "1" && "$(fact "$1" "$2" sentinel)" != "0" ]]; }
# started <out> — the proxy got past startup (a refusal would make most mutant rows vacuous)
started() { [[ "$(rcof "$1")" != "2" ]] && stderr_has "$1" 'child pgid'; }
export FACTS; export -f leaks started rcof stderr_has
# red <label> <shell-test...> — a mutation row is ok when the DEFECT is observable
red() { local label="$1"; shift; cases=$((cases + 1)); if "$@"; then ok "$label"; else bad "$label — mutant survived"; fi; }

m="$(mutant 01-no-redact rewrite_result 'new_text = self.redact_text(text)' 'new_text = text')"
[[ -n "$m" ]] && { r="$(session m01 "$m" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 1: redaction skipped → sentinel in stdout' leaks "$r" 3; }
m="$(mutant 02-first-block-only rewrite_result 'new_text = self.redact_text(text)' 'new_text = self.redact_text(text) if block is content[0] else text')"
[[ -n "$m" ]] && { r="$(session m02 "$m" --env FAKE_PW_RESULT_FILE="$OD/two-text-blocks.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 2: only content[0] processed → second block leaks' leaks "$r" 3; }
m="$(mutant 03-dispatch pump_client_to_server 'if "method" in req and "id" in req:' 'if req.get("method") == "tools/cal" and "id" in req:')"
[[ -n "$m" ]] && { r="$(session m03 "$m" --send "$INIT" --send "$SNAP" --end eof --timeout 3)"; red 'row 3: dispatch broken → the redacted result is never delivered (own-dispatch)' bash -c 'started "$1" && [[ "$(fact "$1" 3 found)" == "0" ]]' _ "$r"; }
m="$(mutant 05-swallow-load load_redactor '        refuse_start(f"cannot load {REDACTOR_BASENAME}: {type(exc).__name__}")' '        return (lambda t: t.replace("ZZQP-SENTINEL-7980", "<redacted>"), lambda t: t.startswith("- "), 4194304, "<redacted>")')"
[[ -n "$m" ]] && { BROKEN="$WORK/broken"; mkdir -p "$BROKEN"; cp "$m" "$BROKEN/proxy.py"; printf 'def (\n' > "$BROKEN/redact-a11y-snapshot.py"; r="$(session m05 "$BROKEN/proxy.py" --send "$INIT" --end eof --timeout 3)"; red 'row 5: load error swallowed → proxy starts and answers initialize' test "$(fact "$r" 1 found)" = "1"; }
m="$(mutant 06-no-flag spawn_child 'argv = list(server) + ["--snapshot-mode", "none"]' 'argv = list(server)')"
[[ -n "$m" ]] && { r="$(session m06 "$m" --env FAKE_PW_ARGV_OUT="$WORK/m06-argv" --send "$INIT" --end eof)"; red 'row 6: flag not appended → stub argv lacks it' bash -c '! grep -qx -- "--snapshot-mode" "$1"' _ "$WORK/m06-argv"; }
m="$(mutant 07-forward-filename refuse_request 'if name == "browser_snapshot" and "filename" in args:' 'if False and "filename" in args:')"
[[ -n "$m" ]] && { r="$(session m07 "$m" --env FAKE_PW_REQUEST_LOG="$WORK/m07-req" --send "$INIT" --send '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{"filename":"'"$WORK"'/m07-raw.yml"}}}' --end eof)"; red 'row 7: filename forwarded → stub writes the raw file and logs the call' bash -c 'test -s "$1" && grep -qF filename "$2"' _ "$WORK/m07-raw.yml" "$WORK/m07-req"; }
m="$(mutant 08-no-link-arm rewrite_result 'if tline.startswith("- [Snapshot]("):' 'if False and tline.startswith("- [Snapshot]("):')"
[[ -n "$m" ]] && { r="$(session m08 "$m" --env FAKE_PW_RESULT_FILE="$OD/link-result.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 8: link arm removed → link result forwarded instead of withheld' bash -c '[[ "$(fact "$1" 3 found)" == "1" && "$(fact "$1" 3 isError)" != "true" ]]' _ "$r"; }
m="$(mutant 09-weak-selftest self_test 'if redacted not in out or "ZZQP-SENTINEL-7980" in out:' 'if redacted not in out:')"
[[ -n "$m" ]] && { V="$WORK/m09"; mkdir -p "$V"; cp "$m" "$V/proxy.py"; cp "$WORK/v-append/redact-a11y-snapshot.py" "$V/"; r="$(session m09 "$V/proxy.py" --send "$INIT" --end eof --timeout 3)"; red 'row 9: self-test checks only <redacted> present → append-only redactor mutant starts the proxy' test "$(rcof "$r")" != "2"; }
m="$(mutant 10-own-predicate rewrite_result 'new_text = self.redact_text(text)' 'new_text = self.redact_text(text) if "password" in text else text')"
[[ -n "$m" ]] && red 'row 10: proxy-side predicate literal → FR13 AST row reds' bash -c 'python3 - "$1" "$2" <<'"'"'PY'"'"'
import ast,sys,importlib.util
t=ast.parse(open(sys.argv[1]).read()); spec=importlib.util.spec_from_file_location("r",sys.argv[2]); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
doc=ast.get_docstring(t, clean=False); st=next(n for n in ast.walk(t) if isinstance(n,ast.FunctionDef) and n.name=="self_test")
bad=[n.value for n in ast.walk(t) if isinstance(n,ast.Constant) and isinstance(n.value,str) and n.value!=doc and not (st.lineno<=n.lineno<=st.end_lineno) and m._is_credential_name(n.value)]
sys.exit(0 if bad else 1)
PY' _ "$m" "$REDACTOR"
m="$(mutant 11-no-annotate pump_server_to_client '            write_line(self.out, self.annotate_tools_list(msg, line))' '            write_line(self.out, line)')"
[[ -n "$m" ]] && { r="$(session m11 "$m" --send "$INIT" --send "$LIST" --end eof)"; red 'row 11: annotate skipped → tools/list lacks the marker' bash -c '[[ "$(fact "$1" 2 found)" == "1" ]] && ! grep -qF "redacted in flight" "$1/stdout.bin"' _ "$r"; }
m="$(mutant 12-no-eof-teardown run '                            self.teardown("stdin EOF")' '                            os._exit(0)')"
[[ -n "$m" ]] && { r="$(session m12 "$m" --env FAKE_PW_HOLD=1 --send "$INIT" --end eof --timeout 4)"; red 'row 12: EOF teardown removed → holding child survives' bash -c 'started "$1" && [[ "$(cat "$1/group_after")" -gt 0 ]]' _ "$r"; pkill -KILL -g "$(cat "$r/child_pgid")" 2>/dev/null || true; }
m="$(mutant 13-classify-pending-only classify 'if "result" not in msg and "error" not in msg:' 'if False:')"
[[ -n "$m" ]] && { r="$(session m13 "$m" --env FAKE_PW_ROOTS_COLLIDE=1 --send "$INIT" --send "$SNAP" --end eof --timeout 3)"; red 'row 13: classify keys on pending alone → colliding roots/list breaks delivery' bash -c 'started "$2" && { [[ "$(python3 "$1" "$2" 3 found)" == "0" || "$(python3 "$1" "$2" 3 isError)" == "true" ]]; }' _ "$FACTS" "$r"; }
m="$(mutant 14-strict-decoder pump_server_to_client 'msg = json.loads(line.decode("utf-8", errors="replace"))' 'msg = json.loads(line.decode("utf-8", errors="strict"))')"
[[ -n "$m" ]] && { r="$(session m14 "$m" --env FAKE_PW_RESULT_FILE="$OD/invalid-utf8.json" --send "$INIT" --send "$SNAP" --end eof --timeout 3)"; red 'row 14: strict decoder → invalid byte drops or leaks the result' bash -c 'started "$2" && { [[ "$(python3 "$1" "$2" 3 found)" == "0" || "$(python3 "$1" "$2" 3 sentinel)" != "0" ]]; }' _ "$FACTS" "$r"; }
m="$(mutant 15-no-refuse-argv refuse_argv_and_env 'if "--save-session" in server:' 'if False:')"
[[ -n "$m" ]] && { r="$(session m15 "$m" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --save-session)"; red 'row 15: --save-session check removed → proxy starts' test "$(rcof "$r")" != "2"; }
m="$(mutant 16-wide-whitelist rewrite_result 'if not isinstance(result, dict) or not set(result.keys()) <= RESULT_KEYS:' 'if not isinstance(result, dict):')"
[[ -n "$m" ]] && { r="$(session m16 "$m" --env FAKE_PW_RESULT_FILE="$OD/structured-content.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 16: whitelist widened → structuredContent tree leaks' leaks "$r" 3; }
m="$(mutant 17-resource-ignored rewrite_result '                else:
                    return error_result(rid, tool, "unrecognised result shape")
                new_content.append(block)' '                else:
                    pass
                new_content.append(block)')"
[[ -n "$m" ]] && { r="$(session m17 "$m" --env FAKE_PW_RESULT_FILE="$OD/resource-block.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 17: resource block ignored → leaks' leaks "$r" 3; }
m="$(mutant 18-trailer-on-change rewrite_result 'if tree_seen:
                new_content.append' 'if tree_seen and changed:
                new_content.append')"
[[ -n "$m" ]] && { r="$(session m18 "$m" --env FAKE_PW_RESULT_FILE="$OD/tree-no-credential.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 18: trailer only on change → credential-free tree lacks it' bash -c '[[ "$(fact "$1" 3 found)" == "1" && "$(fact "$1" 3 trailer)" == "0" ]]' _ "$r"; }
m="$(mutant 19-filename-truthy refuse_request 'if name == "browser_snapshot" and "filename" in args:' 'if name == "browser_snapshot" and args.get("filename"):')"
[[ -n "$m" ]] && { r="$(session m19 "$m" --env FAKE_PW_REQUEST_LOG="$WORK/m19-req" --send "$INIT" --send '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{"filename":""}}}' --end eof)"; red 'row 19: filename keyed on truthiness → filename:"" reaches the stub' grep -qF '"filename": ""' "$WORK/m19-req"; }
m="$(mutant 20-no-meta-check refuse_request 'if "_meta" in args:' 'if False:')"
[[ -n "$m" ]] && { r="$(session m20 "$m" --send "$INIT" --send '{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{"_meta":{"json":true}}}}' --end eof)"; red 'row 20: _meta not refused → JSON-escaped tree leaks past the line-anchored predicate' leaks "$r" 12; }
m="$(mutant 21-list-unhandled pump_server_to_client 'if isinstance(msg, list):' 'if False:')"
[[ -n "$m" ]] && { r="$(session m21 "$m" --env FAKE_PW_RESULT_FILE="$OD/list-two-results.json" --send "$INIT" --send "$SNAP" --send '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}' --end eof --timeout 3)"; red 'row 21: list line unhandled → pending ids left hanging or list forwarded' bash -c 'started "$2" && { [[ "$(python3 "$1" "$2" 3 found)" == "0" ]] || grep -q "^\[" "$2/stdout.bin"; }' _ "$FACTS" "$r"; }
m="$(mutant 22a-handbuilt-refusal refuse_request '        return error_result(req.get("id"), name, "filename writes the raw tree to disk; call browser_snapshot with no filename (the file form is only for an unwrapped registration)", refused=True)' '        return json.dumps({"jsonrpc": "2.0", "id": req.get("id"), "result": {"content": [{"type": "text", "text": "refused"}]}}).encode()')"
[[ -n "$m" ]] && { r="$(session m22a "$m" --send "$INIT" --send '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{"filename":"x"}}}' --end eof)"; red 'row 22a: a refusal arm bypassing error_result → no isError / no caveat' bash -c '[[ "$(python3 "$1" "$2" 10 found)" == "1" && "$(python3 "$1" "$2" 10 isError)" != "true" ]]' _ "$FACTS" "$r"; }
m="$(mutant 22b-error-result-field error_result '"isError": True}}' '}}')"
[[ -n "$m" ]] && { r="$(session m22b "$m" --env FAKE_PW_RESULT_FILE="$OD/structured-content.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 22b: a field dropped from error_result → every withhold row reds at once' bash -c '[[ "$(python3 "$1" "$2" 3 found)" == "1" && "$(python3 "$1" "$2" 3 isError)" != "true" ]]' _ "$FACTS" "$r"; }
m="$(mutant 23-forward-unknown pump_server_to_client '            log(f"dropped unknown-id response id={json.dumps(msg.get('"'"'id'"'"'))} ({len(line)} bytes)")
            return' '            write_line(self.out, line)
            return')"
[[ -n "$m" ]] && { r="$(session m23 "$m" --env FAKE_PW_UNPROMPTED=1 --send "$INIT" --send "$SNAP" --end eof)"; red 'row 23: unknown-id response forwarded raw → sentinel leaks' leaks "$r" 999; }
m="$(mutant 24-result-and-method pump_server_to_client '        if "method" in msg:
            write_line(self.out, error_result(msg.get("id"), tool, "unrecognised result shape (response carries a method)"))
            return' '        if False:
            write_line(self.out, error_result(msg.get("id"), tool, "unrecognised result shape (response carries a method)"))
            return')"
[[ -n "$m" ]] && { r="$(session m24 "$m" --env FAKE_PW_RESULT_FILE="$OD/result-and-method.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 24: result+method treated as a normal result → not withheld' bash -c '[[ "$(fact "$1" 3 found)" == "1" && "$(fact "$1" 3 isError)" != "true" ]]' _ "$r"; }
m="$(mutant 25-annotate-unwrapped annotate_tools_list '            log(f"annotate failed: {type(exc).__name__}")
            return line' '            raise')"
[[ -n "$m" ]] && { r="$(session m25 "$m" --env FAKE_PW_FIXTURE_DIR="$NOTOOLS" --send "$INIT" --send "$LIST" --send "$SNAP" --end eof --timeout 3)"; red 'row 25: annotate not fail-safe → tools/list result lost' bash -c 'started "$1" && [[ "$(fact "$1" 2 found)" == "0" ]]' _ "$r"; }
m="$(mutant 26-client-pump-unwrapped pump_client_to_server '            log(f"forwarded unparsable client line ({len(line)} bytes)")
            write_line(self.child.stdin, line)
            return' '            raise')"
[[ -n "$m" ]] && { r="$(session m26 "$m" --send "$INIT" --send 'not json' --send "$SNAP" --end eof --timeout 3)"; red 'row 26: client pump arm unwrapped → the forwarded-raw note disappears (pump error instead)' bash -c 'started "$1" && ! grep -qF "forwarded unparsable client line" "$1/stderr.txt"' _ "$r"; }
m="$(mutant 27-no-sigterm-handler run 'signal.signal(signal.SIGTERM, on_signal)' 'signal.signal(signal.SIGTERM, signal.SIG_DFL)')"
[[ -n "$m" ]] && { r="$(session m27 "$m" --env FAKE_PW_HOLD=1 --send "$INIT" --end sigterm --timeout 4)"; red 'row 27: SIGTERM handler removed → holding child survives' bash -c 'started "$1" && [[ "$(cat "$1/group_after")" -gt 0 ]]' _ "$r"; pkill -KILL -g "$(cat "$r/child_pgid")" 2>/dev/null || true; }
m="$(mutant 28-no-clamp teardown 'code = rc if rc >= 0 else 128 - rc' 'code = rc')"
[[ -n "$m" ]] && { r="$(session m28 "$m" --send "$INIT" --end killchild --timeout 5)"; red 'row 28: clamp removed → proxy exits 241 (raw -15) instead of 143' bash -c '[[ "$(cat "$1/rc")" == "241" ]]' _ "$r"; }
m="$(mutant 29-weak-tree-selftest self_test 'if not tree_true or prose_false:' 'if False:')"
[[ -n "$m" ]] && { V="$WORK/m29"; mkdir -p "$V"; cp "$m" "$V/proxy.py"; cp "$WORK/v-false/redact-a11y-snapshot.py" "$V/"; r="$(session m29 "$V/proxy.py" --send "$INIT" --send "$SNAP" --end eof --timeout 3)"; red 'row 29: tree self-test dropped → constant-False redactor starts and never appends the trailer' bash -c '[[ "$(cat "$1/rc")" != "2" && "$(python3 "$2" "$1" 3 trailer)" == "0" ]]' _ "$r" "$FACTS"; }
m="$(mutant 30-bare-id id_key 'return (type(rid).__name__, rid)' 'return ("id", str(rid))')"
[[ -n "$m" ]] && { r="$(session m30 "$m" --send "$INIT" --send "$LIST" --send '{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}' --end eof --timeout 3)"; red 'row 30: bare-id keying → 2 and "2" collide (tools/list misrouted)' bash -c '! python3 - "$1" <<'"'"'PY'"'"'
import json,sys
R=json.load(open(sys.argv[1]+"/responses.json")); L=[o for o in R if isinstance(o,dict) and o.get("id")==2]
sys.exit(0 if L and "tools" in L[0].get("result",{}) else 1)
PY' _ "$r"; }
m="$(mutant 31-error-data-forwarded rewrite_result 'if isinstance(err, dict) and "data" in err:' 'if False:')"
[[ -n "$m" ]] && { r="$(session m31 "$m" --env FAKE_PW_RESULT_FILE="$OD/error-with-data.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 31: error data forwarded raw → sentinel leaks' bash -c 'grep -qF "ZZQP-SENTINEL-7980" "$1/stdout.bin"' _ "$r"; }
m="$(mutant 32-no-cap rewrite_result 'if len(text.encode("utf-8", "surrogatepass")) > self.max_input_bytes:' 'if False:')"
[[ -n "$m" ]] && { r="$(session m32 "$m" --env FAKE_PW_RESULT_FILE="$WORK/big.json" --send "$INIT" --send "$SNAP" --end eof --timeout 30)"; red 'row 32: size cap removed → oversized text forwarded (not withheld)' bash -c '[[ "$(fact "$1" 3 found)" == "1" && "$(fact "$1" 3 isError)" != "true" ]]' _ "$r"; }
m="$(mutant 33-quotes-input rewrite_result 'return error_result(rid, tool, "result exceeds the redactor'"'"'s size cap")' 'return error_result(rid, tool, "cap: " + text[:100])')"
[[ -n "$m" ]] && { r="$(session m33 "$m" --env FAKE_PW_RESULT_FILE="$WORK/big.json" --send "$INIT" --send "$SNAP" --end eof --timeout 30)"; red 'row 33: reason quotes the input → sentinel in the isError text or stderr' bash -c 'grep -qF "ZZQP-SENTINEL-7980" "$1/stdout.bin" || grep -qF "ZZQP-SENTINEL-7980" "$1/stderr.txt"' _ "$r"; }
m="$(mutant 34-no-except-arm rewrite_result '            return error_result(rid, tool, f"redaction raised {type(exc).__name__}")' '            return line')"
[[ -n "$m" ]] && { V="$WORK/m34"; mkdir -p "$V"; cp "$m" "$V/proxy.py"; cp "$WORK/v-raise/redact-a11y-snapshot.py" "$V/"; r="$(session m34 "$V/proxy.py" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 34: except arm forwards raw → raising redactor leaks' leaks "$r" 3; }
m="$(mutant 35-ignore-debug refuse_argv_and_env 'debug = env.get("DEBUG", "")' 'debug = ""')"
[[ -n "$m" ]] && { r="$(session m35 "$m" --env DEBUG=pw:mcp:server:response --send "$INIT" --end eof --timeout 3)"; red 'row 35: DEBUG ignored → proxy starts under the response logger' test "$(rcof "$r")" != "2"; }
m="$(mutant 36-substring-drift rewrite_result 'if tline.startswith("- [Snapshot]("):' 'if "- [Snapshot](" in tline:')"
[[ -n "$m" ]] && { r="$(session m36 "$m" --env FAKE_PW_RESULT_FILE="$OD/value-contains-link-substring.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 36: drift arm keyed on substring → page-controlled withhold (DoS)' bash -c '[[ "$(fact "$1" 3 found)" == "1" && "$(fact "$1" 3 isError)" == "true" ]]' _ "$r"; }
m="$(mutant 37-no-line-cap run 'if len(buf) > MAX_LINE_BYTES and not discarding[side]:' 'if False:')"
[[ -n "$m" ]] && { r="$(session m37 "$m" --env FAKE_PW_OVERSIZE=$((65*1024*1024)) --send "$INIT" --send "$SNAP" --end eof --timeout 40)"; red 'row 37: line cap removed → the 65 MiB line is buffered whole and reaches the 4 MiB cap instead (no discard line, reason lacks oversize)' bash -c 'started "$2" && [[ "$(python3 "$1" "$2" 3 found)" == "1" && "$(python3 "$1" "$2" 3 text)" != *oversize* ]] && ! grep -qF "discarding oversize server line" "$2/stderr.txt"' _ "$FACTS" "$r"; }
m="$(mutant 38-forward-client-list pump_client_to_server '        if isinstance(req, list):
            log(f"dropped list line from client ({len(line)} bytes)")
            return' '        if False:
            return')"
[[ -n "$m" ]] && { r="$(session m38 "$m" --send "$INIT" --send '[{"jsonrpc":"2.0","id":40,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}]' --send "$SNAP" --end eof)"; red 'row 38: client list line forwarded → the drop note disappears' bash -c 'started "$1" && ! grep -qF "dropped list line from client" "$1/stderr.txt"' _ "$r"; }
m="$(mutant 39-name-allowlist rewrite_result 'new_text = self.redact_text(text)' 'new_text = self.redact_text(text) if tool == "browser_snapshot" else text')"
[[ -n "$m" ]] && { r="$(session m39 "$m" --send "$INIT" --send "$FIND" --end eof)"; red 'row 39: tool-name allowlist → browser_find leaks (Q1 by shape)' leaks "$r" 6; }

# ---------------------------------------------------------------------------
# Guard 2 — .mcp.json routing, EXECUTABLE (scratch HOME, npx shim on PATH)
# ---------------------------------------------------------------------------
G2="$WORK/g2"; mkdir -p "$G2/home" "$G2/bin"
cat > "$G2/bin/npx" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$SHIM_ARGV_OUT"
{ ps -o comm= -p "$PPID"; ps -o args= -p "$PPID"; } > "$SHIM_PARENT_OUT"
exit 0
SHIM
chmod +x "$G2/bin/npx"
# run_mcp_args <args1-string> <tag>; the wrapper's pkill/rm lines resolve $prof under the scratch HOME
run_mcp_args() {
  local cmd="$1" tag="$2"
  : > "$G2/$tag.argv"; : > "$G2/$tag.parent"
  ( cd "$REPO_ROOT" && export SHIM_ARGV_OUT="$G2/$tag.argv" SHIM_PARENT_OUT="$G2/$tag.parent" HOME="$G2/home" PATH="$G2/bin:$PATH" && sleep 5 | timeout 20 bash -c "$cmd" >/dev/null 2>"$G2/$tag.err" ) || true
}
MCP_ARGS="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['mcpServers']['playwright']['args'][1])" "$REPO_ROOT/.mcp.json")"
MCP_ARG0="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['mcpServers']['playwright']['args'][0])" "$REPO_ROOT/.mcp.json")"
assert_true 'Guard 2: .mcp.json playwright command is bash -c <string>' bash -c '[[ "$1" == "-c" ]]' _ "$MCP_ARG0"
run_mcp_args "$MCP_ARGS" g2
assert_true 'Guard 2: the npx shim'"'"'s PARENT is the proxy (pid-anchored: comm python3 + the proxy path in its argv)' bash -c '[[ "$(head -n1 "$1")" == "python3" ]] && grep -qF "playwright-mcp-redact-proxy.py -- npx" "$1"' _ "$G2/g2.parent"
assert_true "Guard 2: recorded argv carries @playwright/mcp@$PIN (the fixture directory's version)" grep -qxF "@playwright/mcp@$PIN" "$G2/g2.argv"
assert_true 'Guard 2: recorded argv carries --user-data-dir=<scratch>/.cache/playwright-mcp-profile' grep -qxF -- "--user-data-dir=$G2/home/.cache/playwright-mcp-profile" "$G2/g2.argv"
assert_true 'Guard 2: recorded argv carries --config=.claude/playwright-mcp.config.json' grep -qxF -- '--config=.claude/playwright-mcp.config.json' "$G2/g2.argv"
assert_true 'Guard 2: recorded argv ENDS with --snapshot-mode none' bash -c '[[ "$(tail -n 2 "$1" | tr "\n" " ")" == "--snapshot-mode none " ]]' _ "$G2/g2.argv"
# Guard 2 mutants of the args string
g2_mut() { local label="$1" mutated="$2" tag="$3"; shift 3; run_mcp_args "$mutated" "$tag"; cases=$((cases + 1)); if "$@"; then ok "$label"; else bad "$label — mutant survived"; fi; }
g2_mut 'Guard 2 mutant 1: proxy removed → shim parent is bash' "${MCP_ARGS//python3 plugins\/soleur\/skills\/agent-browser\/scripts\/playwright-mcp-redact-proxy.py -- /}" g2m1 bash -c '[[ "$(head -n1 "$1")" != "python3" ]]' _ "$G2/g2m1.parent"
assert_true 'Guard 2 mutant 1 landed' bash -c '[[ "$1" != "$2" ]]' _ "$MCP_ARGS" "${MCP_ARGS//python3 plugins\/soleur\/skills\/agent-browser\/scripts\/playwright-mcp-redact-proxy.py -- /}"
M2="$(python3 -c 'import sys; s=sys.argv[1]; p="python3 plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py -- "; i=s.index(p); s=s[:i]+s[i+len(p):]; print(s.rstrip()+" -- python3 plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py")' "$MCP_ARGS")"
g2_mut 'Guard 2 mutant 2: proxy AFTER the server → shim parent is bash' "$M2" g2m2 bash -c '[[ "$(head -n1 "$1")" != "python3" ]]' _ "$G2/g2m2.parent"
g2_mut 'Guard 2 mutant 3: --config dropped → argv lacks it' "${MCP_ARGS// --config=.claude\/playwright-mcp.config.json/}" g2m3 bash -c '! grep -qxF -- "--config=.claude/playwright-mcp.config.json" "$1"' _ "$G2/g2m3.argv"
g2_mut "Guard 2 mutant 4: version bumped in .mcp.json alone → argv no longer carries @playwright/mcp@$PIN" "${MCP_ARGS//@playwright\/mcp@$PIN/@playwright\/mcp@9.9.9}" g2m4 bash -c '! grep -qxF "@playwright/mcp@$2" "$1"' _ "$G2/g2m4.argv" "$PIN"
assert_true 'Guard 2 mutant 5: renaming the server key fails the lookup loudly' bash -c '! python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d[\"mcpServers\"][\"playwrite\"]=d[\"mcpServers\"].pop(\"playwright\"); print(d[\"mcpServers\"][\"playwright\"][\"args\"][1])" "$1" 2>/dev/null' _ "$REPO_ROOT/.mcp.json"
# Reaper discrimination (Phase 0.3): the wrapper's pkill patterns vs the executed group
assert_true 'reaper: the proxy pkill pattern is ordered BEFORE the child pkill in .mcp.json' bash -c 'p=$(grep -o "pkill[^;]*" <<<"$1" | head -1); [[ "$p" == *"[p]laywright-mcp-redact-proxy.py"* ]]' _ "$MCP_ARGS"
assert_true 'reaper: neither pkill pattern matches the wrapper'"'"'s own literal $prof line' bash -c 'pat1=$(grep -o "\[p\]laywright-mcp-redact-proxy.py [^\"]*" <<<"$1" | head -1); pat2=$(grep -o "\[b\]in/playwright-mcp [^\"]*" <<<"$1" | head -1); ! grep -qE "$pat1" <<<"$1" && ! grep -qE "$pat2" <<<"$1"' _ "$MCP_ARGS"

# ---------------------------------------------------------------------------
# Harness rows H1/H2 are the helper controls above (each helper shown to REJECT);
# the instrument self-test is the dispatch row. Verdict below.
# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed, %d cases\n' "$pass" "$fail" "$cases"

if [[ $((pass + fail)) -ne $cases ]]; then
  printf '[FATAL] vacuity accounting: pass+fail (%d) != cases (%d) — a row did not report\n' "$((pass + fail))" "$cases" >&2
  exit 1
fi
MIN_ASSERTIONS=150
if [[ $cases -lt $MIN_ASSERTIONS ]]; then
  printf '[FATAL] vacuity floor: only %d cases executed, expected at least %d\n' "$cases" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ $fail -eq 0 ]] || exit 1
exit 0
