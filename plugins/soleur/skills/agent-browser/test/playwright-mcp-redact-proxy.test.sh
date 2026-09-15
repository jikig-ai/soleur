#!/usr/bin/env bash
# Guard-contract suite for playwright-mcp-redact-proxy.py (#7980).
#
# Mirrors redact-a11y-snapshot.test.sh: ok/bad helpers, an instrument
# self-test, helper controls that must REJECT, then the rows, then a verdict
# reported with printf + exit (never through the helpers it backstops) and a
# MIN_ASSERTIONS floor bound ADJACENT to the floor block.
#
# Every session is driven by fixtures/proxy-session-driver.py against the
# table-driven stub fixtures/fake-playwright-mcp.py, fed the capture directory
# DERIVED from the .mcp.json pin; every process assertion is scoped to the pgid
# the proxy logs (never a machine-wide name match). Mutants are standalone copies
# written by fixtures/make-proxy-mutant.py (one edit, asserted landed by `diff -q`
# AND inside the named function's ast range), counted in THIS shell so a mutant
# that stops landing reds the run instead of silently deleting its row.
# An "absent" observable is only ever asserted together with a positive proof
# that the thing which would have produced it ran. `grep -q` reads herestrings or
# files only, never a producer pipe (SIGPIPE under pipefail is a false negative).
#
# Three proxy paths: PROXY_SHIPPED (the file under test, and the source of every
# mutant), PROXY (what the rows drive; PROXY_UNDER_TEST points it at
# fixtures/fake-passthrough-proxy.py to observe the RED rows RED, QG5), and the
# per-row variant copies that sit beside a modified redactor.
set -Eeuo pipefail
# An abort names its line: under `set -e` a silent exit 1 is indistinguishable from a verdict.
trap 'printf "[ABORT] line %s: %s (rc=%s)\n" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR
export TMPDIR="${TMPDIR:-/var/tmp}"
export PLAYWRIGHT_MCP_PROXY_GRACE_S=1

# Refuses an empty, relative, root or synthetic-fs fixture dir (byte-identical copy; the
# fixture-dir-operand-assert suite pins every tracked copy).
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
REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
assert_fixture_dir "$REPO_ROOT"
SKILL="$REPO_ROOT/plugins/soleur/skills/agent-browser"
PROXY_SHIPPED="$SKILL/scripts/playwright-mcp-redact-proxy.py"
PROXY="${PROXY_UNDER_TEST:-$PROXY_SHIPPED}"
REDACTOR="$SKILL/scripts/redact-a11y-snapshot.py"
FIX="$SKILL/test/fixtures"
STUB="$FIX/fake-playwright-mcp.py"
PASSTHROUGH="$FIX/fake-passthrough-proxy.py"
DRV="$FIX/proxy-session-driver.py"
export FACTS="$FIX/session-facts.py"
MUTATE="$FIX/make-proxy-mutant.py"
ODD="$FIX/odd-shapes"
# The capture directory is DERIVED from the .mcp.json pin and handed to the stub
# on every session: a bump that forgets to re-capture reds here.
PIN="$(python3 -c "import json,re,sys; s=json.load(open(sys.argv[1]))['mcpServers']['playwright']['args'][1]; print(re.search(r'@playwright/mcp@([0-9.]+)', s).group(1))" "$REPO_ROOT/.mcp.json")"
CAPTURES="$FIX/playwright-mcp-$PIN"
SENTINEL='ZZQP-SENTINEL-7980'
BENIGN='ZZQP-BENIGN-7980'
WORK="$(mktemp -d -t proxy-suite.XXXXXXXX)"
assert_fixture_dir "$WORK"
MUT="$WORK/mutants"; mkdir -p "$MUT"; cp "$REDACTOR" "$MUT/"   # every mutant loads the REAL predicate beside it
# Every child group a session logged. A FAKE_PW_HOLD stub ignores SIGTERM, so a row whose proxy
# does no teardown (the passthrough, a teardown mutant) leaves it alive; reap_all SIGKILLs each
# recorded group that still holds a stub process, at the hygiene row and again on EXIT.
PGIDS="$WORK/pgids"
stub_groups() { local pg; [[ -s "$PGIDS" ]] || return 0; while read -r pg; do if [[ -n "$pg" ]] && pgrep -g "$pg" -a 2>/dev/null | grep -qF -e "$STUB" -e 'sleep 300'; then printf '%s\n' "$pg"; fi; done < <(sort -u "$PGIDS"); }
reap_all() { local pg; while read -r pg; do pkill -KILL -g "$pg" 2>/dev/null || true; done < <(stub_groups); }
trap 'reap_all; rm -rf "$WORK"' EXIT

INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{"roots":{}},"clientInfo":{"name":"suite","version":"0"}}}'
LIST='{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
SNAP='{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}'
SNAP4='{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}'
NAV='{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"browser_navigate","arguments":{"url":"http://127.0.0.1:1/"}}}'
FIND='{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"browser_find","arguments":{"text":"Token"}}}'
EVAL='{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"browser_evaluate","arguments":{"function":"() => 1"}}}'
SHOT='{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"browser_take_screenshot","arguments":{}}}'
CLOSE='{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"browser_close","arguments":{}}}'
NOTIF='{"jsonrpc":"2.0","method":"notifications/initialized"}'
FILENAME_REQ() { printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{"filename":"%s"}}}' "$1" "$2"; }

pass=0; fail=0; cases=0; mutants_declared=0; red_rows=0
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
# Session + fact helpers (exported at definition: `bash -c` rows use them)
# ---------------------------------------------------------------------------
# session <name> <proxy> [driver args...] ; prints the out dir. The stub is the
# server unless the caller passes --server; the pin-derived capture dir is the
# stub's fixture dir unless the caller passes its own FAKE_PW_FIXTURE_DIR.
session() {
  local name="$1" proxy="$2"; shift 2
  local out="$WORK/s-$name"; rm -rf "$out"
  local args=(--env "FAKE_PW_FIXTURE_DIR=$CAPTURES" "$@")
  [[ " $* " == *" --server "* ]] || args+=(--server python3 "$STUB")
  python3 "$DRV" --out "$out" --proxy "$proxy" "${args[@]}" >/dev/null 2>&1 || true
  printf '%s\n' "$(cat "$out/child_pgid" 2>/dev/null || true)" >> "$PGIDS"
  printf '%s' "$out"
}
fact() { python3 "$FACTS" "$@" 2>/dev/null || printf 'ERR'; }
rcof() { cat "$1/rc" 2>/dev/null || printf 'none'; }
stderr_has() { [[ -f "$1/stderr.txt" ]] && grep -qF -- "$2" "$1/stderr.txt"; }   # file, never a pipe
stdout_has() { [[ -f "$1/stdout.bin" ]] && grep -qaF -- "$2" "$1/stdout.bin"; }
# leaks <out> <id> — a response for <id> was DELIVERED and carries the sentinel
leaks() { [[ "$(fact "$1" "$2" found)" == "1" && "$(fact "$1" "$2" sentinel)" != "0" ]]; }
# delivered_ok <out> <id> — a RESULT for <id> was delivered: not a JSON-RPC error, not an isError result
delivered_ok() { [[ "$(fact "$1" "$2" found)" == "1" && "$(fact "$1" "$2" jsonrpc_error)" == "0" && "$(fact "$1" "$2" isError)" != "true" ]]; }
# started <out> — the proxy got past startup: not a refusal, and it logged the child
started() { [[ "$(rcof "$1")" != "2" && "$(rcof "$1")" != "none" ]] && stderr_has "$1" 'child pgid'; }
text_has() { [[ "$(fact "$1" "$2" text)" == *"$3"* ]]; }
# `A && B` as a function's last list trips `set -e` when B fails, and pkill on an already-empty group fails
reap_group() { local pg; pg="$(cat "$1/child_pgid" 2>/dev/null || true)"; if [[ -n "$pg" ]]; then pkill -KILL -g "$pg" 2>/dev/null || true; fi; }
export -f fact rcof stderr_has stdout_has leaks delivered_ok started text_has

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
  got="$(fact "$out" "$id" rawline)"; want="$(fact "$out" "$id" expected_line "$fixture")"
  if [[ -z "$got" ]]; then bad "$label — no response for id $id"
  elif [[ "$got" != "$want" ]]; then bad "$label — bytes differ from the stub's line"
  else ok "$label"; fi
}
# assert_withheld <label> <out> <id-json> <reason-needle> — refused OR withheld result
assert_withheld() {
  local label="$1" out="$2" id="$3" needle="$4"
  cases=$((cases + 1))
  local found err sent text
  found="$(fact "$out" "$id" found)"; err="$(fact "$out" "$id" isError)"; sent="$(fact "$out" "$id" sentinel)"; text="$(fact "$out" "$id" text)"
  if [[ "$found" != "1" ]]; then bad "$label — no response for id $id (a dropped result is as RED as a raw one)"
  elif [[ "$err" != "true" ]]; then bad "$label — not withheld (isError=$err)"
  elif [[ "$sent" != "0" ]]; then bad "$label — sentinel present in the withheld result"
  elif [[ "$text" != *"$needle"* ]]; then bad "$label — reason lacks '$needle'"
  elif [[ "$text" != *"withheld by playwright-mcp-redact-proxy:"* && "$text" != *"refused by playwright-mcp-redact-proxy:"* ]]; then bad "$label — text lacks the pinned proxy prefix"
  elif [[ "$text" != *"call browser_snapshot with no filename"* ]]; then bad "$label — next-step line missing"
  else ok "$label"; fi
}
# assert_refused_start <label> <out> <reason-needle>
assert_refused_start() {
  local label="$1" out="$2" needle="$3"
  cases=$((cases + 1))
  local rc lines pg
  rc="$(rcof "$out")"; lines="$(fact "$out" 0 lines)"; pg="$(cat "$out/child_pgid" 2>/dev/null || true)"
  if [[ "$rc" != "2" ]]; then bad "$label — exit $rc, expected 2"
  elif ! stderr_has "$out" "playwright-mcp-redact-proxy: refusing to start:"; then bad "$label — no 'playwright-mcp-redact-proxy: refusing to start:' line"
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
# mutant <name> <function> <old> <new> — writes $MUT/<name>.py and sets MUTANT_PATH
# (empty when the edit did not land). Runs in THIS shell: its verdict and its
# count survive, so a mutant that stops landing is a FAIL, never a vanished row.
MUTANT_PATH=""
mutant() {
  local name="$1" func="$2" old="$3" new="$4"
  local out="$MUT/$name.py"
  cases=$((cases + 1)); mutants_declared=$((mutants_declared + 1)); MUTANT_PATH=""
  if python3 "$MUTATE" "$PROXY_SHIPPED" "$out" "$func" "$old" "$new" >/dev/null 2>"$MUT/$name.err" && ! diff -q "$PROXY_SHIPPED" "$out" >/dev/null; then
    ok "mutant $name landed inside $func"; MUTANT_PATH="$out"
  else
    bad "mutant $name did NOT land: $(tr '\n' ' ' < "$MUT/$name.err")"
  fi
}
# red <label> <shell-test...> — a mutation row is ok when the DEFECT is observable
red() { local label="$1"; shift; cases=$((cases + 1)); red_rows=$((red_rows + 1)); if "$@"; then ok "$label"; else bad "$label — mutant survived"; fi; }

# ---------------------------------------------------------------------------
# Helper control: every verdict-owning helper driven with an input it MUST
# reject. Counters are unwound afterwards; the suite refuses to continue if any
# helper failed to reject.
# ---------------------------------------------------------------------------
_helper_control() {
  local _p=$pass _f=$fail _c=$cases _m=$mutants_declared _r=$red_rows
  local leak; leak="$(session hc-leak "$PASSTHROUGH" --send "$INIT" --send "$SNAP" --end eof)"
  local clean="$WORK/s-hc-clean"; mkdir -p "$clean"
  printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"- textbox \"Token\" [ref=e1]: <redacted>"}]}}' > "$clean/stdout.bin"
  printf 'playwright-mcp-redact-proxy: refusing to start: synthetic\n' > "$clean/stderr.txt"; printf '2\n' > "$clean/rc"; printf '\n' > "$clean/child_pgid"; printf '3\n' > "$clean/group_after"
  assert_redacted_result 'helper control: assert_redacted_result must REJECT a leak (EXPECTED)' "$leak" 3 1
  assert_withheld 'helper control: assert_withheld must REJECT a raw forwarded result (EXPECTED)' "$leak" 3 'x'
  assert_byte_identical 'helper control: assert_byte_identical must REJECT a differing line (EXPECTED)' "$leak" 3 "$CAPTURES/navigate.json"
  assert_refused_start 'helper control: assert_refused_start must REJECT a started proxy (EXPECTED)' "$leak" 'x'
  assert_stderr_marker 'helper control: assert_stderr_marker must REJECT a wrong count (EXPECTED)' "$leak" 'child pgid' 7
  assert_group_empty 'helper control: assert_group_empty must REJECT a missing pgid (EXPECTED)' "$clean"
  assert_rc 'helper control: assert_rc must REJECT a wrong exit (EXPECTED)' "$clean" 9
  assert_true 'helper control: assert_true must REJECT false (EXPECTED)' false
  red 'helper control: red must REJECT an unobservable defect (EXPECTED)' false
  assert_true 'helper control: leaks must be FALSE on a redacted response (EXPECTED)' leaks "$clean" 3
  assert_true 'helper control: leaks must be TRUE on the passthrough (EXPECTED)' bash -c '! leaks "$1" 3' _ "$leak"
  assert_true 'helper control: started must be FALSE on a refused start (EXPECTED)' started "$clean"
  assert_true 'helper control: delivered_ok must be FALSE on a missing id (EXPECTED)' delivered_ok "$clean" 99
  mutant hc-nonunique-EXPECTED rewrite_result 'self' 'this'   # <old> is not unique, so it must not land
  if [[ $fail -ne $((_f + 14)) ]]; then
    printf 'HELPER CONTROL BROKEN: expected 14 rejections, fail %d->%d\n' "$_f" "$fail" >&2; exit 1
  fi
  pass=$_p; fail=$_f; cases=$_c; mutants_declared=$_m; red_rows=$_r
}

if [[ ! -f "$PROXY" ]]; then
  printf 'FAIL - proxy missing at %s\n\nRED: the proxy does not exist yet (expected pre-implementation state).\n' "$PROXY"; exit 1
fi
if [[ ! -d "$CAPTURES" ]]; then
  printf 'FAIL - capture directory %s missing: the .mcp.json pin is %s; re-run fixtures/capture-playwright-mcp-fixtures.py\n' "$CAPTURES" "$PIN"; exit 1
fi
_helper_control

# ---------------------------------------------------------------------------
# Instrument rows: the stub, driven through the PASSTHROUGH (no rewrite), must
# produce the artefacts the matrix rows assert on.
# ---------------------------------------------------------------------------
out="$(session inst "$PASSTHROUGH" --env FAKE_PW_ARGV_OUT="$WORK/inst-argv" --env FAKE_PW_REQUEST_LOG="$WORK/inst-req" \
  --send "$INIT" --send "$(FILENAME_REQ 3 "$WORK/inst-raw.yml")" --send "$SNAP4" --end eof)"
assert_true 'instrument: stub WRITES the raw tree for a filename call' test -s "$WORK/inst-raw.yml"
assert_true 'instrument: the written file carries the sentinel' grep -qF "$SENTINEL" "$WORK/inst-raw.yml"
assert_true 'instrument: stub request log records the call' grep -qF '"name": "browser_snapshot"' "$WORK/inst-req"
assert_true 'instrument: stub records its argv' test -f "$WORK/inst-argv"
assert_true 'instrument: passthrough forwards the raw tree (known negative)' leaks "$out" 4
assert_true 'instrument: the stub refuses to run without FAKE_PW_FIXTURE_DIR' bash -c 'rc=0; env -u FAKE_PW_FIXTURE_DIR python3 "$1" </dev/null >/dev/null 2>&1 || rc=$?; [[ $rc == 64 ]]' _ "$STUB"
out="$(session inst-notify "$PASSTHROUGH" --env FAKE_PW_NOTIFY=1 --env FAKE_PW_SERVER_REQUEST=1 --send "$INIT" --send "$SNAP" --end eof)"
assert_true 'instrument: FAKE_PW_NOTIFY / FAKE_PW_SERVER_REQUEST put a tree on the wire (known negative)' bash -c '[[ "$(grep -caF "notifications/message" "$1/stdout.bin")" == "1" && "$(grep -caF "sampling/createMessage" "$1/stdout.bin")" == "1" ]] && stdout_has "$1" ZZQP-SENTINEL-7980' _ "$out"
out="$(session inst-cancel "$PASSTHROUGH" --env FAKE_PW_CANCEL=1 --send "$INIT" --send "$SNAP" --end eof)"
assert_true 'instrument: FAKE_PW_CANCEL puts a tree in a relayed-set reason, _meta and requestId (known negative)' bash -c '[[ "$(grep -caF "notifications/cancelled" "$1/stdout.bin")" == "2" ]] && [[ "$(grep -caF "\"_meta\"" "$1/stdout.bin")" == "1" ]] && stdout_has "$1" ZZQP-SENTINEL-7980' _ "$out"
hold="$(session inst-hold "$PASSTHROUGH" --env FAKE_PW_HOLD=1 --send "$INIT" --end eof --timeout 3)"
assert_true 'instrument: FAKE_PW_HOLD keeps the group alive past stdin EOF (passthrough does no teardown)' test "$(cat "$hold/group_after")" -gt 0
reap_group "$hold"
gc="$(session inst-grandchild "$PASSTHROUGH" --env FAKE_PW_GRANDCHILD=1 --send "$INIT" --end eof --timeout 3)"
assert_true 'instrument: FAKE_PW_GRANDCHILD — the SIGTERM-ignoring grandchild holds the group past stdin EOF' bash -c '[[ "$(cat "$1/group_after")" -gt 0 ]]' _ "$gc"
reap_group "$gc"

# ---------------------------------------------------------------------------
# FR1/FR2/FR2b/FR10/FR10b/FR11 — the shipped path, one canonical session
# ---------------------------------------------------------------------------
main="$(session main "$PROXY" --send "$INIT" --send "$NOTIF" --send "$LIST" --send "$SNAP" --send "$NAV" --send "$FIND" --send "$EVAL" --send "$SHOT" --send "$CLOSE" --end eof)"
assert_byte_identical 'FR1/FR11: initialize result forwarded byte-identical' "$main" 1 "$CAPTURES/initialize.json"
assert_redacted_result 'FR2: bare browser_snapshot — password/Token redacted, Notes intact (P3)' "$main" 3 1
assert_true 'FR2: <redacted> marker present on the credential rows' bash -c 'text_has "$1" 3 "\"Enter your password\" [ref=e4]: <redacted>" && text_has "$1" 3 "\"Token\" [ref=e6]: <redacted>"' _ "$main"
assert_true 'FR2: Email address survives in clear (must-PASS)' text_has "$main" 3 'probe-user@example.invalid'
assert_redacted_result 'FR2b/P7: browser_find result redacted by SHAPE (no tool-name allowlist)' "$main" 6 0
assert_true 'FR10b: tree-carrying result ends with the trailer block' test "$(fact "$main" 3 trailer)" = "1"
assert_true 'FR10b: browser_find result ends with the trailer block' test "$(fact "$main" 6 trailer)" = "1"
assert_true 'FR10b: browser_navigate (no tree) carries NO trailer' bash -c 'delivered_ok "$1" 5 && [[ "$(fact "$1" 5 trailer)" == "0" ]]' _ "$main"
assert_byte_identical 'FR11/P1: browser_navigate forwarded byte-identical' "$main" 5 "$CAPTURES/navigate.json"
assert_byte_identical 'FR11/P2: browser_evaluate object result forwarded byte-identical' "$main" 7 "$CAPTURES/evaluate.json"
assert_byte_identical 'FR11/P4: screenshot (text + image) forwarded byte-identical' "$main" 8 "$CAPTURES/screenshot.json"
assert_byte_identical 'FR11/P5: browser_close result (no isClose on the wire) forwarded' "$main" 9 "$CAPTURES/close.json"
assert_true 'FR10: tools/list — browser_snapshot description ends with the marker' bash -c 'd="$(fact "$1" 2 description:browser_snapshot)"; [[ "$d" == *"redacted in flight"* && "$d" == *"filename is refused — call browser_snapshot with no filename.]" ]]' _ "$main"
assert_true 'FR10: other tool descriptions untouched' python3 - "$main" "$CAPTURES/tools-list.json" <<'PY'
import json, sys
fx = {t["name"]: t["description"] for t in json.load(open(sys.argv[2]))["result"]["tools"]}
for o in json.load(open(sys.argv[1] + "/responses.json")):
    if isinstance(o, dict) and o.get("id") == 2:
        got = {t["name"]: t["description"] for t in o["result"]["tools"]}
        sys.exit(0 if len(got) == len(fx) and all(got[n] == fx[n] for n in fx if n != "browser_snapshot") else 1)
sys.exit(1)
PY
assert_stderr_marker 'B7: initialize logs what was wrapped' "$main" 'wrapping Playwright' 1
assert_stderr_marker 'B4: child pgid logged once' "$main" 'child pgid' 1
assert_stderr_marker 'B10: teardown line on stdin EOF' "$main" 'child exited rc=0' 1
assert_group_empty 'FR14: stdin EOF → child group empty' "$main"
assert_rc 'FR14: clean child exit → proxy exit 0' "$main" 0
assert_true 'NFR2: every stdout line of a full session is a JSON-RPC object' test "$(fact "$main" 0 alljson)" = "1"

# roots/list from the server (P5): rebuilt to method + id, map untouched
roots="$(session roots "$PROXY" --env FAKE_PW_ROOTS_COLLIDE=1 --send "$INIT" --send "$SNAP" --end eof)"
assert_true 'FR11/P5: roots/list server request forwarded (with a COLLIDING id)' stdout_has "$roots" '{"jsonrpc":"2.0","id":3,"method":"roots/list"}'
assert_redacted_result 'FR11b: colliding roots/list id — result still redacted and delivered' "$roots" 3 1

# ---------------------------------------------------------------------------
# FR3 — refusals before the server sees the call (filename; ""; _meta)
# ---------------------------------------------------------------------------
ref="$(session refuse "$PROXY" --env FAKE_PW_REQUEST_LOG="$WORK/ref-req" --send "$INIT" \
  --send "$(FILENAME_REQ 10 "$WORK/ref-raw.yml")" \
  --send '{"jsonrpc":"2.0","id":"11","method":"tools/call","params":{"name":"browser_snapshot","arguments":{"filename":""}}}' \
  --send '{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{"_meta":{"json":true}}}}' \
  --send '{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"browser_navigate","arguments":{"_meta":{"raw":true},"url":"x"}}}' \
  --send "$SNAP" --end eof)"
assert_withheld 'FR3: browser_snapshot + filename refused (id type int preserved)' "$ref" 10 'filename'
assert_withheld 'FR3: browser_snapshot + filename:"" refused on KEY presence (id type str preserved)' "$ref" '"11"' 'filename'
assert_withheld 'FR3: tools/call with arguments._meta refused' "$ref" 12 '_meta'
assert_withheld 'FR3: _meta refused on ANY tool, not only browser_snapshot' "$ref" 13 '_meta'
assert_true 'FR3: refusal text carries the proxy-unique token (the S2 signal)' text_has "$ref" 10 'refused by playwright-mcp-redact-proxy: filename writes the raw tree to disk'
assert_true 'FR3: the refused calls never reached the stub, which did receive the session' bash -c 'grep -qF "\"method\": \"initialize\"" "$1" && ! grep -qF "filename" "$1" && ! grep -qF "_meta" "$1"' _ "$WORK/ref-req"
assert_true 'FR3: no raw file was written' test ! -e "$WORK/ref-raw.yml"
assert_redacted_result 'FR3: the bare call after the refusals is still served' "$ref" 3 1
assert_stderr_marker 'FR7b: one pinned stderr line per refusal' "$ref" 'refused tool=' 4
assert_true 'FR7b/B9: stderr refusal lines never quote the input path' bash -c 'stderr_has "$1" "refused tool=" && ! grep -qF "ref-raw.yml" "$1/stderr.txt"' _ "$ref"

# ---------------------------------------------------------------------------
# FR4 — the injected flag
# ---------------------------------------------------------------------------
session argv "$PROXY" --env FAKE_PW_ARGV_OUT="$WORK/argv-out" --send "$INIT" --end eof >/dev/null
assert_true 'FR4: child argv ends with --snapshot-mode none' bash -c 'test -f "$1" && [[ "$(tail -n 2 "$1" | tr "\n" " ")" == "--snapshot-mode none " ]]' _ "$WORK/argv-out"

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
printf 'saveSession = true\n' > "$WORK/cfg-save.ini"
r="$(session saveini "$PROXY" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --config="$WORK/cfg-save.ini")"
assert_refused_start 'FR5: a config the proxy cannot parse as JSON (the server reads INI) refuses to start' "$r" 'not JSON'
r="$(session cfgmissing "$PROXY" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --config="$WORK/nope.json")"
assert_refused_start 'FR5: a --config that does not exist refuses to start with a named reason' "$r" 'does not exist'
printf '{"saveVideo": {"width": 800, "height": 600}}\n' > "$WORK/cfg-video.json"
r="$(session savevideo "$PROXY" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --config="$WORK/cfg-video.json")"
assert_refused_start 'FR5: config saveVideo refuses to start' "$r" 'saveVideo'
printf '{"capabilities": ["devtools"]}\n' > "$WORK/cfg-caps.json"
r="$(session cfgcaps "$PROXY" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --config="$WORK/cfg-caps.json")"
assert_refused_start 'FR5: config capabilities other than vision refuses to start' "$r" 'capabilities'
printf '{"server": {"port": 8931}}\n' > "$WORK/cfg-port.json"
r="$(session cfgport "$PROXY" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --config="$WORK/cfg-port.json")"
assert_refused_start 'FR5: config server.port refuses to start' "$r" 'server.port'
r="$(session port "$PROXY" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --port 8931)"
assert_refused_start 'FR5: --port (HTTP transport around the relay) refuses to start' "$r" '--port'
r="$(session portenv "$PROXY" --env PLAYWRIGHT_MCP_PORT=8931 --send "$INIT" --end eof --timeout 3)"
assert_refused_start 'FR5: PLAYWRIGHT_MCP_PORT refuses to start' "$r" '--port'
r="$(session host "$PROXY" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --host=0.0.0.0)"
assert_refused_start 'FR5: --host refuses to start' "$r" '--host'
r="$(session caps "$PROXY" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --caps=vision,devtools)"
assert_refused_start 'FR5: --caps with devtools refuses to start' "$r" '--caps'
r="$(session capsenv "$PROXY" --env PLAYWRIGHT_MCP_CAPS=storage --send "$INIT" --end eof --timeout 3)"
assert_refused_start 'FR5: PLAYWRIGHT_MCP_CAPS=storage refuses to start' "$r" '--caps'
r="$(session outmode "$PROXY" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --output-mode file)"
assert_refused_start 'FR5: --output-mode file refuses to start' "$r" 'output-mode'
printf '{"snapshot": {"mode": "full"}, "capabilities": ["vision"]}\n' > "$WORK/cfg-ok.json"
r="$(session cfgok "$PROXY" --send "$INIT" --send "$SNAP" --end eof --server python3 "$STUB" --config="$WORK/cfg-ok.json" --caps vision)"
assert_redacted_result 'FR5 companion: a benign JSON --config=<file> and --caps vision start and serve' "$r" 3 1
for dbg in 'pw:mcp:server:response' '*' 'pw:*' 'pw:api *' '*:response' 'express:router, *' 'p*'; do
  r="$(session "debug-$(printf '%s' "$dbg" | md5sum | cut -c1-8)" "$PROXY" --env "DEBUG=$dbg" --send "$INIT" --end eof --timeout 3)"
  assert_refused_start "FR5: DEBUG='$dbg' (enables a pw:* logger) refuses to start" "$r" 'DEBUG'
done
assert_true 'FR5: the DEBUG reason never quotes the value' bash -c 'stderr_has "$1" "refusing to start" && ! grep -qF "p*" "$1/stderr.txt"' _ "$r"
r="$(session debugfile "$PROXY" --env DEBUG_FILE="$WORK/dbg" --send "$INIT" --end eof --timeout 3)"
assert_refused_start 'FR5: DEBUG_FILE refuses to start' "$r" 'DEBUG_FILE'
r="$(session debugother "$PROXY" --env 'DEBUG=express:router,-pw:*' --send "$INIT" --send "$SNAP" --end eof)"
assert_redacted_result 'FR5 companion: an unrelated DEBUG namespace (plus a pw exclusion) starts and serves' "$r" 3 1
usage_rc=0; python3 "$PROXY" -- </dev/null >"$WORK/usage.out" 2>"$WORK/usage.err" || usage_rc=$?
assert_true 'B1: empty server argv → exit 2, usage on stderr, nothing on stdout' bash -c '[[ "$1" == "2" ]] && grep -qF "refusing to start: usage:" "$2" && [[ ! -s "$3" ]]' _ "$usage_rc" "$WORK/usage.err" "$WORK/usage.out"
usage_rc=0; python3 "$PROXY" python3 "$STUB" </dev/null >"$WORK/usage2.out" 2>"$WORK/usage2.err" || usage_rc=$?
assert_true 'B1: missing -- separator → exit 2 (the server argv is never guessed)' bash -c '[[ "$1" == "2" ]] && grep -qF "no \`--\` separator" "$2"' _ "$usage_rc" "$WORK/usage2.err"

# ---------------------------------------------------------------------------
# FR6 — redactor variants make the proxy refuse (self-test), FR7 — raising predicate
# ---------------------------------------------------------------------------
mk_variant() {  # <dir> <proxy> <python-replace-old> <python-replace-new>
  mkdir -p "$1"; cp "$2" "$1/proxy.py"
  python3 - "$REDACTOR" "$1/redact-a11y-snapshot.py" "$3" "$4" <<'PY'
import sys
src = open(sys.argv[1]).read(); old, new = sys.argv[3], sys.argv[4].encode().decode("unicode_escape")
assert src.count(old) == 1, (old, src.count(old))
open(sys.argv[2], "w").write(src.replace(old, new))
PY
}
mk_variant "$WORK/v-identity" "$PROXY" 'def redact_text(text: str) -> str:' 'def redact_text(text: str) -> str:\n    return text\n\ndef _unused_redact_text(text: str) -> str:'
r="$(session v-identity "$WORK/v-identity/proxy.py" --send "$INIT" --end eof --timeout 3)"
assert_refused_start 'FR6: a redactor returning its input unchanged → refuse to start' "$r" 'self-test'
mk_variant "$WORK/v-append" "$PROXY" 'def redact_text(text: str) -> str:' 'def redact_text(text: str) -> str:\n    return text + " <redacted>"\n\ndef _unused_redact_text(text: str) -> str:'
r="$(session v-append "$WORK/v-append/proxy.py" --send "$INIT" --end eof --timeout 3)"
assert_refused_start 'FR6/row 9 input: a redactor appending <redacted> without removing the value → refuse' "$r" 'self-test'
mk_variant "$WORK/v-false" "$PROXY" 'def looks_like_a11y_tree(value: str) -> bool:' 'def looks_like_a11y_tree(value: str) -> bool:\n    return False\n\ndef _unused_looks(value: str) -> bool:'
r="$(session v-false "$WORK/v-false/proxy.py" --send "$INIT" --end eof --timeout 3)"
assert_refused_start 'FR6/row 29 input: constant-False looks_like_a11y_tree → refuse' "$r" 'looks_like_a11y_tree'
# raises only for long text, so the startup self-test passes (row 34's input)
mk_variant "$WORK/v-raise" "$PROXY" 'def redact_text(text: str) -> str:' 'def redact_text(text: str) -> str:\n    if len(text) > 200:\n        raise RuntimeError("boom")\n    return _orig_redact_text(text)\n\ndef _orig_redact_text(text: str) -> str:'
r="$(session v-raise "$WORK/v-raise/proxy.py" --send "$INIT" --send "$SNAP" --end eof)"
assert_withheld 'FR7: redact_text raising → withheld, no sentinel, session continues' "$r" 3 'raised'
assert_true 'FR7: the withhold says the action may already have run' text_has "$r" 3 'its result was withheld, not its action'
assert_stderr_marker 'FR7b: one withheld line for the raise' "$r" 'withheld tool=browser_snapshot' 1
assert_rc 'FR7: the session ended cleanly after the withhold' "$r" 0
# the four-name contract: a redactor missing one name → refuse, not a per-result withhold
mk_variant "$WORK/v-rename" "$PROXY" 'def main() -> None:' 'del looks_like_a11y_tree\n\n\ndef main() -> None:'
r="$(session v-rename "$WORK/v-rename/proxy.py" --send "$INIT" --end eof --timeout 3)"
assert_refused_start 'B2: a redactor missing one of the four names → refuse (not a per-result withhold)' "$r" 'does not export looks_like_a11y_tree'
# FR13 behavioural: a SPY redactor tags every string it is handed. Every text block
# the proxy delivers must carry the tag — a proxy-side predicate that skips some
# text (a literal, a tool-name allowlist, any spelling of either) cannot hide.
mk_variant "$WORK/v-spy" "$PROXY" 'def redact_text(text: str) -> str:' 'def redact_text(text: str) -> str:\n    return _orig_redact_text(text) + "\\n[[SPY]]"\n\ndef _orig_redact_text(text: str) -> str:'
spy_check() {  # <out> — every non-trailer text block of ids 3,5,6,7 ends with the spy tag
  python3 - "$1" <<'PY'
import json, sys
seen = 0
for o in json.load(open(sys.argv[1] + "/responses.json")):
    if isinstance(o, dict) and o.get("id") in (3, 5, 6, 7) and isinstance(o.get("result"), dict):
        for b in o["result"]["content"]:
            if b.get("type") == "text" and not b["text"].startswith("[Soleur:"):
                seen += 1
                if not b["text"].endswith("[[SPY]]"):
                    sys.exit(1)
sys.exit(0 if seen >= 4 else 2)
PY
}
export -f spy_check
r="$(session v-spy "$WORK/v-spy/proxy.py" --send "$INIT" --send "$SNAP" --send "$NAV" --send "$FIND" --send "$EVAL" --end eof)"
assert_true 'FR13 behavioural: every delivered text block passed through redact_text (spy)' spy_check "$r"

# ---------------------------------------------------------------------------
# FR8/FR9/FR11b — odd shapes through the shipped proxy
# ---------------------------------------------------------------------------
odd() { session "odd-$1" "$PROXY" --env FAKE_PW_RESULT_FILE="$ODD/$1.json" "${@:2}" --send "$INIT" --send "$SNAP" --end eof; }
r="$(odd two-text-blocks)"; assert_redacted_result 'row 2 input: two text blocks both redacted (second-member)' "$r" 3 2
r="$(odd link-result)"
assert_true 'FR9: a - [Snapshot]( file link is replaced by the do-not-read notice, result delivered' bash -c 'delivered_ok "$1" 3 && text_has "$1" 3 "[Snapshot withheld by playwright-mcp-redact-proxy: the server wrote a raw tree file"' _ "$r"
assert_true 'FR9: the server-emitted path is echoed nowhere (stdout, stderr)' bash -c 'stderr_has "$1" "replaced a snapshot file link" && ! grep -qaF "page-2026" "$1/stdout.bin" && ! grep -qF "page-2026" "$1/stderr.txt"' _ "$r"
r="$(odd dialog-link-injection)"
assert_redacted_result 'FR9: a page-controlled dialog line shaped like the link cannot withhold the result' "$r" 3 1
r="$(odd structured-content)"; assert_withheld 'FR11b: structuredContent → withheld' "$r" 3 'unrecognised result shape'
r="$(odd resource-block)"; assert_withheld 'FR11b: resource block → withheld' "$r" 3 'unrecognised result shape'
r="$(odd meta-in-result)"; assert_withheld 'FR11b: _meta in the result → withheld' "$r" 3 'unrecognised result shape'
r="$(odd result-and-method)"; assert_withheld 'FR11b: result AND method → withheld' "$r" 3 'unrecognised result shape'
r="$(odd no-content)"; assert_withheld 'FR11b: no content key → withheld' "$r" 3 'unrecognised result shape'
r="$(odd result-string)"; assert_withheld 'FR11b: result is a string → withheld' "$r" 3 'unrecognised result shape'
r="$(odd empty-content)"; assert_byte_identical 'edge: content: [] forwarded unchanged' "$r" 3 "$ODD/empty-content.json"
r="$(odd error-with-data)"; assert_withheld 'row 31: error with structured data → withheld' "$r" 3 'unrecognised shape'
r="$(odd error-and-result)"; assert_withheld 'row 31: an error frame that also carries a result → withheld' "$r" 3 'unrecognised shape'
r="$(odd error-string)"; assert_withheld 'row 31: a non-object error → withheld' "$r" 3 'unrecognised shape'
r="$(odd error-message-tree)"; assert_withheld 'row 46: an error message carrying tree rows → withheld' "$r" 3 'tree-shaped'
r="$(odd error-no-data)"; assert_true 'row 31 companion: a data-less prose error forwarded byte-identical' bash -c '[[ "$(fact "$1" 3 rawline | base64 -d)" == "{\"jsonrpc\":\"2.0\",\"id\":3,\"error\":{\"code\":-32000,\"message\":\"boom\"}}" ]]' _ "$r"
r="$(odd run-code-escaped)"; assert_withheld 'row 49: a JSON-escaped tree (browser_run_code_unsafe shape) → withheld' "$r" 3 'JSON-escaped'
r="$(odd evaluate-escaped-object)"; assert_withheld 'row 49: a tree inside a pretty-printed JSON object → withheld' "$r" 3 'JSON-escaped'
r="$(odd run-code-escaped-one-row)"; assert_withheld 'row 56: a ONE-ROW escaped tree (single-locator ariaSnapshot) → withheld' "$r" 3 'JSON-escaped'
r="$(odd quoted-key)"; assert_redacted_result 'quoted YAML key ("API Key #1") redacted through the proxy; "Notes #2" intact' "$r" 3 1
r="$(odd value-contains-link-substring)"; assert_true 'row 36: a VALUE containing the link substring outside ### Snapshot is redacted, not replaced' bash -c 'delivered_ok "$1" 3 && text_has "$1" 3 "\"Token\" [ref=e1]: <redacted>"' _ "$r"
r="$(odd value-contains-brace)"; assert_redacted_result 'P6 canary: a value containing { is delivered redacted (no envelope sniff)' "$r" 3 1
r="$(odd tree-no-credential)"; assert_true 'row 18: a tree with no credential-named field still gets the trailer' bash -c 'delivered_ok "$1" 3 && [[ "$(fact "$1" 3 trailer)" == "1" ]]' _ "$r"
r="$(odd invalid-utf8)"; assert_redacted_result 'row 14: one invalid UTF-8 byte in the text → decoded with replacement, still redacted' "$r" 3 1
r="$(odd unparsable-line)"; assert_true 'edge: unparsable server line dropped with a stderr line; session continues' bash -c 'stderr_has "$1" "dropped unparsable server line" && [[ "$(cat "$1/rc")" == "0" ]]' _ "$r"
r="$(session odd-list "$PROXY" --env FAKE_PW_RESULT_FILE="$ODD/list-two-results.json" --send "$INIT" --send "$SNAP" --send "$SNAP4" --end eof)"
assert_withheld 'row 21: list-shaped server line — first pending id answered by error_result' "$r" 3 'list line'
assert_withheld 'row 21: list-shaped server line — second pending id answered' "$r" 4 'list line'
assert_true 'row 21: the list line itself was not forwarded' bash -c 'stderr_has "$1" "dropped list line from server" && ! grep -qa "^\[" "$1/stdout.bin"' _ "$r"
# tools/list without a tools key: fed from a scratch capture dir
NOTOOLS="$WORK/notools"
assert_fixture_dir "$NOTOOLS"
mkdir -p "$NOTOOLS"
assert_fixture_dir "$CAPTURES"
cp "$CAPTURES/initialize.json" "$CAPTURES/snapshot.json" "$NOTOOLS/"
cp "$ODD/tools-list-no-tools.json" "$NOTOOLS/tools-list.json"
r="$(session notools "$PROXY" --env FAKE_PW_FIXTURE_DIR="$NOTOOLS" --send "$INIT" --send "$LIST" --send "$SNAP" --end eof)"
assert_byte_identical 'FR10/row 25: tools/list without a tools key forwarded unchanged (fail-safe)' "$r" 2 "$ODD/tools-list-no-tools.json"
assert_stderr_marker 'FR10/row 25: annotate failure noted on stderr' "$r" 'annotate failed' 1
assert_redacted_result 'FR10/row 25: the session continues after the annotate failure' "$r" 3 1
# an initialize answered with a content-bearing tree: routed by SHAPE, not by method
INITTREE="$WORK/inittree"; mkdir -p "$INITTREE"; cp "$CAPTURES/snapshot.json" "$INITTREE/initialize.json"; cp "$CAPTURES/snapshot.json" "$INITTREE/"
r="$(session inittree "$PROXY" --env FAKE_PW_FIXTURE_DIR="$INITTREE" --send "$INIT" --end eof)"
assert_redacted_result 'row 48: a content-bearing result answering initialize is rewritten (routed by shape)' "$r" 1 1
# unknown-id response dropped (row 23 shipped side)
r="$(session unprompted "$PROXY" --env FAKE_PW_UNPROMPTED=1 --send "$INIT" --send "$SNAP" --end eof)"
assert_true 'row 23: an unprompted result (id never sent) is dropped; no sentinel anywhere on stdout' bash -c 'delivered_ok "$1" 3 && [[ "$(fact "$1" 999 found)" == "0" ]] && ! stdout_has "$1" ZZQP-SENTINEL-7980' _ "$r"
assert_stderr_marker 'row 23: dropped unknown-id response noted' "$r" 'dropped unknown-id response' 1
# server notifications and requests outside the relayed set
r="$(session notify "$PROXY" --env FAKE_PW_NOTIFY=1 --send "$INIT" --send "$SNAP" --end eof)"
assert_true 'row 44: a notifications/message carrying a tree is dropped; the result still redacted' bash -c 'delivered_ok "$1" 3 && stderr_has "$1" "dropped a server notification" && ! stdout_has "$1" ZZQP-SENTINEL-7980 && ! stdout_has "$1" notifications/message' _ "$r"
r="$(session srvreq "$PROXY" --env FAKE_PW_SERVER_REQUEST=1 --env FAKE_PW_REQUEST_LOG="$WORK/srvreq-req" --send "$INIT" --send "$SNAP" --end eof)"
assert_true 'row 45: a sampling/createMessage server request is dropped, never reaching the client' bash -c 'delivered_ok "$1" 3 && stderr_has "$1" "dropped a server request" && ! stdout_has "$1" sampling/createMessage && ! stdout_has "$1" ZZQP-SENTINEL-7980' _ "$r"
assert_true 'row 45: the dropped server request is answered with an error on the server side' grep -qF '"response_id": "srv-1", "error": true' "$WORK/srvreq-req"
r="$(session cancel "$PROXY" --env FAKE_PW_CANCEL=1 --send "$INIT" --send "$SNAP" --end eof)"
assert_true 'row 54: relayed-set notifications are rebuilt — method and plain requestId arrive, reason/_meta/tree requestId do not' bash -c 'delivered_ok "$1" 3 && stdout_has "$1" "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":3}}" && stdout_has "$1" "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/tools/list_changed\"}" && stderr_has "$1" "dropped a cancellation whose requestId is not a plain id" && ! stdout_has "$1" ZZQP-SENTINEL-7980 && ! stdout_has "$1" _meta' _ "$r"
# FR8 — over the cap
python3 - "$WORK/big.json" "$SENTINEL" "$BENIGN" <<'PY'
import json, sys
big = f'- textbox "Token" [ref=e1]: {sys.argv[2]}\n' + (f'- textbox "Notes" [ref=e2]: {sys.argv[3]}\n' * (4 * 1024 * 1024 // 44 + 2))
assert len(big.encode()) > 4 * 1024 * 1024
json.dump({"result": {"content": [{"type": "text", "text": big}]}}, open(sys.argv[1], "w"))
PY
r="$(session big "$PROXY" --env FAKE_PW_RESULT_FILE="$WORK/big.json" --send "$INIT" --send "$SNAP" --end eof --timeout 20)"
assert_withheld 'FR8: text over MAX_INPUT_BYTES → withheld' "$r" 3 'size cap'
assert_stderr_marker 'FR8: withheld line on stderr' "$r" 'withheld tool=browser_snapshot' 1
# row 30 — ids keyed by their JSON text
r="$(session idtype "$PROXY" --send "$INIT" --send "$LIST" --send '{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}' --end eof)"
assert_true 'row 30: id 2 (tools/list) and id "2" (tools/call) are classified by their own requests' bash -c '[[ "$(fact "$1" 2 description:browser_snapshot)" == *"redacted in flight"* ]] && delivered_ok "$1" "\"2\"" && [[ "$(fact "$1" "\"2\"" sentinel)" == "0" ]]' _ "$r"
# row 47 — a request reusing a pending id is refused, never overwrites the entry
r="$(session reuse "$PROXY" --send "$INIT" --send "$SNAP" --send '{"jsonrpc":"2.0","id":3,"method":"tools/list"}' --end eof)"
assert_true 'row 47: a request reusing a pending id is refused; the original result is still redacted' bash -c '[[ "$(fact "$1" 3 count)" == "2" && "$(fact "$1" 3 jsonrpc_error)" == "1" ]] && ! stdout_has "$1" ZZQP-SENTINEL-7980' _ "$r"
assert_stderr_marker 'row 47: the reuse refusal is noted' "$r" 'refused a request reusing a pending id' 1
# an id of any JSON shape is keyed; one odd line never strands the lines behind it
r="$(session listid "$PROXY" --send "$INIT" --send '{"jsonrpc":"2.0","id":[1],"method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}' --send "$SNAP" --end eof)"
assert_true 'edge: a list-shaped id is keyed and answered, and the next request is served' bash -c 'delivered_ok "$1" "[1]" && delivered_ok "$1" 3 && ! stderr_has "$1" "pump error"' _ "$r"
# row 26 — unparsable client lines are dropped, never forwarded unvetted
bigint="$(python3 -c 'print("9" * 5000)')"
r="$(session badclient "$PROXY" --env FAKE_PW_REQUEST_LOG="$WORK/badclient-req" --send "$INIT" --send 'not json' \
  --send "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"tools/call\",\"params\":{\"name\":\"browser_snapshot\",\"arguments\":{\"filename\":\"$WORK/badclient.yml\",\"_meta\":{\"n\":$bigint}}}}" \
  --send "$SNAP" --end eof)"
assert_stderr_marker 'row 26: two unparsable client lines (text; an integer past the digit limit) dropped with a note' "$r" 'dropped unparsable client line' 2
assert_true 'row 26: neither reached the stub, which did receive the session; no raw file' bash -c 'grep -qF "\"method\": \"initialize\"" "$1" && ! grep -qF filename "$1" && [[ ! -e "$2" ]]' _ "$WORK/badclient-req" "$WORK/badclient.yml"
assert_redacted_result 'row 26: the next request is still relayed' "$r" 3 1
# row 38 — client list line dropped
r="$(session listclient "$PROXY" --send "$INIT" --send '[{"jsonrpc":"2.0","id":40,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}]' --send "$SNAP" --end eof)"
assert_stderr_marker 'row 38: client list line dropped with a stderr note' "$r" 'dropped list line from client' 1
assert_redacted_result 'row 38: the bare call after the dropped list line is still served' "$r" 3 1
# row 37 — a 65 MiB line: one clear MiB past MAX_LINE_BYTES (a line of exactly 64 MiB parses and is caught by the 4 MiB cap instead)
r="$(session oversize "$PROXY" --env FAKE_PW_OVERSIZE=$((65*1024*1024)) --send "$INIT" --send "$SNAP" --end eof --timeout 40)"
assert_withheld 'row 37: a line over MAX_LINE_BYTES is discarded and the pending call answered oversize' "$r" 3 'oversize'
assert_stderr_marker 'row 37: discard noted with the byte count only' "$r" 'discarding oversize server line' 1

# ---------------------------------------------------------------------------
# FR14 — lifecycle against the stub's pgid (HOLD and GRANDCHILD model Chrome)
# ---------------------------------------------------------------------------
r="$(session hold-eof "$PROXY" --env FAKE_PW_HOLD=1 --send "$INIT" --end eof)"
assert_group_empty 'FR14/row 12: stdin EOF with a holding child → group empty (SIGKILL after grace)' "$r"
assert_stderr_marker 'FR14: SIGKILL-after-grace line' "$r" 'survived SIGTERM; SIGKILL sent' 1
r="$(session grandchild "$PROXY" --env FAKE_PW_GRANDCHILD=1 --send "$INIT" --end eof)"
assert_group_empty 'FR14/row 50: direct child exits, a SIGTERM-ignoring grandchild holds → group still emptied' "$r"
assert_stderr_marker 'FR14/row 50: the grandchild needed the SIGKILL' "$r" 'survived SIGTERM; SIGKILL sent' 1
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
fr13_literals() {  # <proxy> — exit 0 when no credential-shaped literal sits outside self_test's `row =`
  python3 - "$1" "$REDACTOR" <<'PY'
import ast, importlib.util, sys
t = ast.parse(open(sys.argv[1]).read())
spec = importlib.util.spec_from_file_location("r", sys.argv[2]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
doc = ast.get_docstring(t, clean=False)
st = next(n for n in ast.walk(t) if isinstance(n, ast.FunctionDef) and n.name == "self_test")
rows = [a.value for a in ast.walk(st) if isinstance(a, ast.Assign) and any(isinstance(x, ast.Name) and x.id == "row" for x in a.targets)]
exempt = {id(c) for r in rows for c in ast.walk(r)}
consts = [n for n in ast.walk(t) if isinstance(n, ast.Constant) and isinstance(n.value, str)]
bad = [n.value for n in consts if n.value != doc and id(n) not in exempt and m._is_credential_name(n.value)]
shaped_row = [c.value for r in rows for c in ast.walk(r) if isinstance(c, ast.Constant) and isinstance(c.value, str) and m._is_credential_name(c.value)]
sys.exit(0 if not bad and shaped_row else 1)
PY
}
assert_true 'FR13: no re.* call, no def redact_text, exactly one spec_from_file_location' python3 - "$PROXY" <<'PY'
import ast, sys
t = ast.parse(open(sys.argv[1]).read())
re_calls = [n for n in ast.walk(t) if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and isinstance(n.func.value, ast.Name) and n.func.value.id == "re"]
defs = [n.name for n in ast.walk(t) if isinstance(n, ast.FunctionDef)]
sffl = sum(1 for n in ast.walk(t) if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == "spec_from_file_location")
sys.exit(0 if not re_calls and "redact_text" not in defs and sffl == 1 else 1)
PY
assert_true 'FR13: the only credential-shaped literal is the self-test sentinel row' fr13_literals "$PROXY"
assert_true 'NFR1/NFR3: stdlib-only imports, no threading' python3 - "$PROXY" <<'PY'
import ast, sys
t = ast.parse(open(sys.argv[1]).read())
mods = {(n.names[0].name if isinstance(n, ast.Import) else n.module).split(".")[0] for n in ast.walk(t) if isinstance(n, (ast.Import, ast.ImportFrom))}
allowed = {"__future__", "importlib", "json", "os", "selectors", "signal", "subprocess", "sys", "time", "typing"}
sys.exit(0 if mods <= allowed and "threading" not in mods else 1)
PY

# ---------------------------------------------------------------------------
# P6 — parity with the CLI on every sentinel-bearing tree fixture (P-ONE)
# ---------------------------------------------------------------------------
parity_n=0
for f in "$CAPTURES"/*.json "$ODD"/*.json; do
  b="$(basename "$f" .json)"
  [[ "$b" == "snapshot-meta-json" ]] && continue   # the CLI's JSON arm redacts {"snapshot": …}; in-process redact_text does not — refused upstream by B5
  text="$(python3 -c 'import json,sys; o=json.load(open(sys.argv[1])); r=o.get("result"); c=r.get("content") if isinstance(r,dict) else None; print("\n".join(b.get("text","") for b in c if isinstance(b,dict) and b.get("type")=="text") if isinstance(c,list) else "")' "$f" 2>/dev/null || true)"
  [[ "$text" == *"$SENTINEL"* ]] || continue
  grep -q '^- \[Snapshot\](' <<<"$text" && continue   # the drift arm rewrites these lines by design (FR9)
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
assert_true "P6 parity population floor: $parity_n sentinel-bearing tree fixtures (>= 5)" test "$parity_n" -ge 5

# ---------------------------------------------------------------------------
# Guard 1 mutation matrix — standalone copies of PROXY_SHIPPED, one edit each
# ---------------------------------------------------------------------------
beside() {  # <dir> <redactor-variant-dir> — copy the current mutant next to a variant redactor
  mkdir -p "$1"; cp "$MUTANT_PATH" "$1/proxy.py"; cp "$2/redact-a11y-snapshot.py" "$1/"
}
RD='new_text = self.redact_text(relinked)'
mutant 01-no-redact rewrite_result "$RD" 'new_text = relinked'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m01 "$MUTANT_PATH" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 1: redaction skipped → sentinel in stdout' leaks "$r" 3; fi
mutant 02-first-block-only rewrite_result "$RD" 'new_text = self.redact_text(relinked) if block is content[0] else relinked'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m02 "$MUTANT_PATH" --env FAKE_PW_RESULT_FILE="$ODD/two-text-blocks.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 2: only content[0] processed → second block leaks' leaks "$r" 3; fi
mutant 03-dispatch pump_client_to_server 'if "method" in req and "id" in req:' 'if req.get("method") == "tools/cal" and "id" in req:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m03 "$MUTANT_PATH" --send "$INIT" --send "$SNAP" --end eof --timeout 3)"; red 'row 3: dispatch broken → the redacted result is never delivered (own-dispatch)' bash -c 'started "$1" && [[ "$(fact "$1" 3 found)" == "0" ]]' _ "$r"; fi
mutant 05-swallow-load load_redactor '        refuse_start(f"cannot load {REDACTOR_BASENAME}: {type(exc).__name__}")' '        return (lambda t: t.replace("ZZQP-SENTINEL-7980", "<redacted>"), lambda t: t.startswith("- "), 4194304, "<redacted>")'
if [[ -n "$MUTANT_PATH" ]]; then BROKEN="$WORK/broken"; mkdir -p "$BROKEN"; cp "$MUTANT_PATH" "$BROKEN/proxy.py"; printf 'def (\n' > "$BROKEN/redact-a11y-snapshot.py"; r="$(session m05 "$BROKEN/proxy.py" --send "$INIT" --end eof --timeout 3)"; red 'row 5: load error swallowed → proxy starts and answers initialize' bash -c 'started "$1" && [[ "$(fact "$1" 1 found)" == "1" ]]' _ "$r"; fi
mutant 06-no-flag __init__ 'argv = list(server) + ["--snapshot-mode", "none"]' 'argv = list(server)'
if [[ -n "$MUTANT_PATH" ]]; then session m06 "$MUTANT_PATH" --env FAKE_PW_ARGV_OUT="$WORK/m06-argv" --send "$INIT" --end eof >/dev/null; red 'row 6: flag not appended → the stub ran and its argv lacks it' bash -c 'test -f "$1" && ! grep -qx -- "--snapshot-mode" "$1"' _ "$WORK/m06-argv"; fi
mutant 07-forward-filename refuse_request 'if name == "browser_snapshot" and "filename" in args:' 'if False and "filename" in args:'
if [[ -n "$MUTANT_PATH" ]]; then session m07 "$MUTANT_PATH" --env FAKE_PW_REQUEST_LOG="$WORK/m07-req" --send "$INIT" --send "$(FILENAME_REQ 10 "$WORK/m07-raw.yml")" --end eof >/dev/null; red 'row 7: filename forwarded → stub writes the raw file and logs the call' bash -c 'test -s "$1" && grep -qF filename "$2"' _ "$WORK/m07-raw.yml" "$WORK/m07-req"; fi
mutant 08-no-link-arm rewrite_result 'elif in_snapshot and tline.startswith("- [Snapshot]("):' 'elif False:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m08 "$MUTANT_PATH" --env FAKE_PW_RESULT_FILE="$ODD/link-result.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 8: link arm removed → the raw-file path reaches the client' bash -c 'delivered_ok "$1" 3 && grep -qaF "page-2026" "$1/stdout.bin"' _ "$r"; fi
mutant 09-weak-selftest self_test 'if redacted not in out or "ZZQP-SENTINEL-7980" in out:' 'if redacted not in out:'
if [[ -n "$MUTANT_PATH" ]]; then beside "$WORK/m09" "$WORK/v-append"; r="$(session m09 "$WORK/m09/proxy.py" --send "$INIT" --end eof --timeout 3)"; red 'row 9: self-test checks only <redacted> present → append-only redactor starts the proxy' started "$r"; fi
mutant 10-own-predicate rewrite_result "$RD" 'new_text = self.redact_text(relinked) if "password" in relinked else relinked'
if [[ -n "$MUTANT_PATH" ]]; then beside "$WORK/m10" "$WORK/v-spy"; r="$(session m10 "$WORK/m10/proxy.py" --send "$INIT" --send "$SNAP" --send "$NAV" --send "$FIND" --send "$EVAL" --end eof)"; red 'row 10: a proxy-side predicate skips some text → the spy tag is missing' bash -c 'started "$1" && ! spy_check "$1"' _ "$r"; fi
mutant 11-no-annotate pump_server_to_client '            write_line(self.out, self.annotate_tools_list(msg, line))' '            write_line(self.out, line)'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m11 "$MUTANT_PATH" --send "$INIT" --send "$LIST" --end eof)"; red 'row 11: annotate skipped → tools/list lacks the marker' bash -c '[[ "$(fact "$1" 2 found)" == "1" ]] && ! stdout_has "$1" "redacted in flight"' _ "$r"; fi
mutant 12-no-eof-teardown run 'self.teardown("stdin EOF" if side == "client" else "child stdout EOF")' 'os._exit(0)'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m12 "$MUTANT_PATH" --env FAKE_PW_HOLD=1 --send "$INIT" --end eof --timeout 4)"; red 'row 12: EOF teardown removed → holding child survives' bash -c 'started "$1" && [[ "$(cat "$1/group_after")" -gt 0 ]]' _ "$r"; reap_group "$r"; fi
mutant 13-classify-pending-only pump_server_to_client '        if "result" not in msg and "error" not in msg:' '        if False:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m13 "$MUTANT_PATH" --env FAKE_PW_ROOTS_COLLIDE=1 --send "$INIT" --send "$SNAP" --end eof --timeout 3)"; red 'row 13: responses keyed on pending alone → a colliding roots/list breaks delivery' bash -c 'started "$1" && ! delivered_ok "$1" 3' _ "$r"; fi
mutant 14-strict-decoder pump_server_to_client 'msg = json.loads(line.decode("utf-8", errors="replace"))' 'msg = json.loads(line.decode("utf-8", errors="strict"))'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m14 "$MUTANT_PATH" --env FAKE_PW_RESULT_FILE="$ODD/invalid-utf8.json" --send "$INIT" --send "$SNAP" --end eof --timeout 3)"; red 'row 14: strict decoder → the invalid byte drops or leaks the result' bash -c 'started "$1" && { [[ "$(fact "$1" 3 found)" == "0" ]] || leaks "$1" 3; }' _ "$r"; fi
mutant 15-no-refuse-argv refuse_argv_and_env 'if "--save-session" in server:' 'if False:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m15 "$MUTANT_PATH" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --save-session)"; red 'row 15: --save-session check removed → proxy starts' started "$r"; reap_group "$r"; fi
mutant 16-wide-whitelist rewrite_result 'if not isinstance(result, dict) or not set(result.keys()) <= RESULT_KEYS:' 'if not isinstance(result, dict):'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m16 "$MUTANT_PATH" --env FAKE_PW_RESULT_FILE="$ODD/structured-content.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 16: whitelist widened → structuredContent tree leaks' leaks "$r" 3; fi
mutant 17-resource-ignored rewrite_result '                else:
                    return error_result(rid, tool, UNRECOGNISED)
                new_content.append(block)' '                else:
                    pass
                new_content.append(block)'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m17 "$MUTANT_PATH" --env FAKE_PW_RESULT_FILE="$ODD/resource-block.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 17: resource block ignored → leaks' leaks "$r" 3; fi
mutant 18-trailer-on-change rewrite_result 'if tree_seen:
                new_content.append' 'if tree_seen and changed:
                new_content.append'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m18 "$MUTANT_PATH" --env FAKE_PW_RESULT_FILE="$ODD/tree-no-credential.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 18: trailer only on change → credential-free tree lacks it' bash -c 'delivered_ok "$1" 3 && [[ "$(fact "$1" 3 trailer)" == "0" ]]' _ "$r"; fi
mutant 19-filename-truthy refuse_request 'if name == "browser_snapshot" and "filename" in args:' 'if name == "browser_snapshot" and args.get("filename"):'
if [[ -n "$MUTANT_PATH" ]]; then session m19 "$MUTANT_PATH" --env FAKE_PW_REQUEST_LOG="$WORK/m19-req" --send "$INIT" --send '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{"filename":""}}}' --end eof >/dev/null; red 'row 19: filename keyed on truthiness → filename:"" reaches the stub' grep -qF '"filename": ""' "$WORK/m19-req"; fi
mutant 20-no-meta-check refuse_request 'if "_meta" in args:' 'if False:'
if [[ -n "$MUTANT_PATH" ]]; then session m20 "$MUTANT_PATH" --env FAKE_PW_REQUEST_LOG="$WORK/m20-req" --send "$INIT" --send '{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{"_meta":{"json":true}}}}' --end eof >/dev/null; red 'row 20: _meta not refused → the undocumented hook reaches the server' grep -qF '_meta' "$WORK/m20-req"; fi
mutant 21-list-unhandled pump_server_to_client 'if isinstance(msg, list):' 'if False:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m21 "$MUTANT_PATH" --env FAKE_PW_RESULT_FILE="$ODD/list-two-results.json" --send "$INIT" --send "$SNAP" --send "$SNAP4" --end eof --timeout 3)"; red 'row 21: list line unhandled → pending ids left hanging' bash -c 'started "$1" && [[ "$(fact "$1" 3 found)" == "0" ]]' _ "$r"; fi
mutant 22a-handbuilt-refusal refuse_request '        return error_result(req.get("id"), name, "filename writes the raw tree to disk; call browser_snapshot with no filename", refused=True)' '        return json.dumps({"jsonrpc": "2.0", "id": req.get("id"), "result": {"content": [{"type": "text", "text": "refused"}]}}).encode()'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m22a "$MUTANT_PATH" --send "$INIT" --send "$(FILENAME_REQ 10 x)" --end eof)"; red 'row 22a: a refusal arm bypassing error_result → no isError, no proxy token' bash -c '[[ "$(fact "$1" 10 found)" == "1" && "$(fact "$1" 10 isError)" != "true" ]]' _ "$r"; fi
mutant 22b-error-result-field error_result '"isError": True}}' '}}'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m22b "$MUTANT_PATH" --env FAKE_PW_RESULT_FILE="$ODD/structured-content.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 22b: a field dropped from error_result → every withhold row reds at once' bash -c '[[ "$(fact "$1" 3 found)" == "1" && "$(fact "$1" 3 isError)" != "true" ]]' _ "$r"; fi
mutant 23-forward-unknown pump_server_to_client '            log(f"dropped unknown-id response ({len(line)} bytes)")
            return' '            write_line(self.out, line)
            return'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m23 "$MUTANT_PATH" --env FAKE_PW_UNPROMPTED=1 --send "$INIT" --send "$SNAP" --end eof)"; red 'row 23: unknown-id response forwarded raw → sentinel leaks' leaks "$r" 999; fi
mutant 24-result-and-method pump_server_to_client '        if "method" in msg:
            write_line(self.out, error_result(rid, tool, UNRECOGNISED' '        if False:
            write_line(self.out, error_result(rid, tool, UNRECOGNISED'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m24 "$MUTANT_PATH" --env FAKE_PW_RESULT_FILE="$ODD/result-and-method.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 24: result+method treated as a normal result → not withheld' delivered_ok "$r" 3; fi
mutant 25-annotate-unwrapped annotate_tools_list '            log(f"annotate failed: {type(exc).__name__}")
            return line' '            raise'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m25 "$MUTANT_PATH" --env FAKE_PW_FIXTURE_DIR="$NOTOOLS" --send "$INIT" --send "$LIST" --send "$SNAP" --end eof --timeout 3)"; red 'row 25: annotate not fail-safe → tools/list result lost' bash -c 'started "$1" && [[ "$(fact "$1" 2 found)" == "0" ]]' _ "$r"; fi
mutant 26-forward-unparsable-client pump_client_to_server '            log(f"dropped unparsable client line ({len(line)} bytes)")
            return' '            write_line(self.child.stdin, line)
            return'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m26 "$MUTANT_PATH" --env FAKE_PW_REQUEST_LOG="$WORK/m26-req" --send "$INIT" --send 'not json' --send "$SNAP" --end eof)"; red 'row 26: unparsable client line forwarded → no drop note, and the server answered it' bash -c 'started "$1" && ! stderr_has "$1" "dropped unparsable client line" && stderr_has "$1" "dropped unknown-id response"' _ "$r"; fi
mutant 27-no-sigterm-handler __init__ 'signal.signal(signal.SIGTERM, self.on_signal)' 'signal.signal(signal.SIGTERM, signal.SIG_DFL)'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m27 "$MUTANT_PATH" --env FAKE_PW_HOLD=1 --send "$INIT" --end sigterm --timeout 4)"; red 'row 27: SIGTERM handler removed → holding child survives' bash -c 'stderr_has "$1" "child pgid" && [[ "$(cat "$1/group_after")" -gt 0 ]]' _ "$r"; reap_group "$r"; fi
mutant 28-no-clamp teardown 'code = rc if rc >= 0 else 128 - rc' 'code = rc'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m28 "$MUTANT_PATH" --send "$INIT" --end killchild --timeout 5)"; red 'row 28: clamp removed → proxy exits 241 (raw -15) instead of 143' bash -c '[[ "$(cat "$1/rc")" == "241" ]]' _ "$r"; fi
mutant 29-weak-tree-selftest self_test 'if not tree_true or prose_false:' 'if False:'
if [[ -n "$MUTANT_PATH" ]]; then beside "$WORK/m29" "$WORK/v-false"; r="$(session m29 "$WORK/m29/proxy.py" --send "$INIT" --send "$SNAP" --end eof --timeout 3)"; red 'row 29: tree self-test dropped → constant-False redactor starts and never appends the trailer' bash -c 'started "$1" && [[ "$(fact "$1" 3 trailer)" == "0" ]]' _ "$r"; fi
mutant 30-bare-id id_key 'return json.dumps(rid, sort_keys=True)' 'return json.dumps(str(rid))'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m30 "$MUTANT_PATH" --send "$INIT" --send "$LIST" --send '{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}' --end eof --timeout 3)"; red 'row 30: ids keyed by their string form → 2 and "2" collide' bash -c 'started "$1" && ! delivered_ok "$1" "\"2\""' _ "$r"; fi
mutant 31-error-shape-forwarded vet_error 'if "result" in msg or not isinstance(err, dict) or not set(err.keys()) <= ERROR_KEYS:' 'if False:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m31 "$MUTANT_PATH" --env FAKE_PW_RESULT_FILE="$ODD/error-with-data.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 31: error data forwarded raw → sentinel leaks' bash -c 'started "$1" && stdout_has "$1" ZZQP-SENTINEL-7980' _ "$r"; fi
mutant 32-no-cap rewrite_result 'if len(text.encode("utf-8", "surrogatepass")) > self.max_input_bytes:' 'if False:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m32 "$MUTANT_PATH" --env FAKE_PW_RESULT_FILE="$WORK/big.json" --send "$INIT" --send "$SNAP" --end eof --timeout 30)"; red 'row 32: size cap removed → oversized text forwarded (not withheld)' delivered_ok "$r" 3; fi
mutant 33-quotes-input rewrite_result 'return error_result(rid, tool, "result exceeds the redactor'"'"'s size cap")' 'return error_result(rid, tool, "cap: " + text[:100])'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m33 "$MUTANT_PATH" --env FAKE_PW_RESULT_FILE="$WORK/big.json" --send "$INIT" --send "$SNAP" --end eof --timeout 30)"; red 'row 33: reason quotes the input → sentinel in the isError text or stderr' bash -c 'started "$1" && { stdout_has "$1" ZZQP-SENTINEL-7980 || grep -qF ZZQP-SENTINEL-7980 "$1/stderr.txt"; }' _ "$r"; fi
mutant 34-no-except-arm rewrite_result '            return error_result(rid, tool, f"redaction raised {type(exc).__name__}")' '            return line'
if [[ -n "$MUTANT_PATH" ]]; then beside "$WORK/m34" "$WORK/v-raise"; r="$(session m34 "$WORK/m34/proxy.py" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 34: except arm forwards raw → raising redactor leaks' leaks "$r" 3; fi
mutant 35-ignore-debug refuse_argv_and_env 'patterns = env.get("DEBUG", "").replace(",", " ").split()' 'patterns = []'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m35 "$MUTANT_PATH" --env DEBUG=pw:mcp:server:response --send "$INIT" --end eof --timeout 3)"; red 'row 35: DEBUG ignored → proxy starts under the response logger' started "$r"; fi
mutant 36-substring-drift rewrite_result 'elif in_snapshot and tline.startswith("- [Snapshot]("):' 'elif "- [Snapshot](" in tline:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m36 "$MUTANT_PATH" --env FAKE_PW_RESULT_FILE="$ODD/value-contains-link-substring.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 36: drift arm keyed on substring → a page value rewrites the credential row away' bash -c 'delivered_ok "$1" 3 && ! text_has "$1" 3 "\"Token\" [ref=e1]: <redacted>"' _ "$r"; fi
mutant 37-no-line-cap run 'if len(buf) > MAX_LINE_BYTES and not discarding[side]:' 'if False:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m37 "$MUTANT_PATH" --env FAKE_PW_OVERSIZE=$((65*1024*1024)) --send "$INIT" --send "$SNAP" --end eof --timeout 40)"; red 'row 37: line cap removed → the 65 MiB line is buffered whole (no discard, reason lacks oversize)' bash -c 'started "$1" && [[ "$(fact "$1" 3 found)" == "1" ]] && ! text_has "$1" 3 oversize && ! stderr_has "$1" "discarding oversize server line"' _ "$r"; fi
mutant 38-forward-client-list pump_client_to_server '        if isinstance(req, list):
            log(f"dropped list line from client ({len(line)} bytes)")
            return' '        if False:
            return'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m38 "$MUTANT_PATH" --send "$INIT" --send '[{"jsonrpc":"2.0","id":40,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}]' --send "$SNAP" --end eof)"; red 'row 38: the client list arm removed → the drop note disappears' bash -c 'started "$1" && ! stderr_has "$1" "dropped list line from client"' _ "$r"; fi
mutant 39-name-allowlist rewrite_result "$RD" 'new_text = self.redact_text(relinked) if tool == "browser_snapshot" else relinked'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m39 "$MUTANT_PATH" --send "$INIT" --send "$FIND" --end eof)"; red 'row 39: tool-name allowlist → browser_find leaks (Q1 by shape)' leaks "$r" 6; fi
mutant 40-debug-wildcard debug_pattern_enables_pw '        if ch == "*":
            return True' '        if False:
            return True'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m40 "$MUTANT_PATH" --env 'DEBUG=*:response' --send "$INIT" --end eof --timeout 3)"; red 'row 40: debug wildcard not modelled → DEBUG=*:response starts' started "$r"; fi
mutant 41-ini-config-skipped refuse_argv_and_env '            refuse_start("the config file is not JSON, so its raw-sink settings cannot be checked")' '            cfg = {}'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m41 "$MUTANT_PATH" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --config="$WORK/cfg-save.ini")"; red 'row 41: a non-JSON config skipped → an INI saveSession starts' started "$r"; fi
mutant 42-port refuse_argv_and_env 'if argv_values(server, "--port") or "--port" in server or env.get("PLAYWRIGHT_MCP_PORT"):' 'if False:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m42 "$MUTANT_PATH" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --port 8931)"; red 'row 42: --port check removed → proxy starts' started "$r"; fi
mutant 43-caps refuse_argv_and_env 'if caps_open_sinks(argv_values(server, "--caps")) or caps_open_sinks([env.get("PLAYWRIGHT_MCP_CAPS", "")]):' 'if False:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m43 "$MUTANT_PATH" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --caps=devtools)"; red 'row 43: --caps check removed → devtools starts' started "$r"; fi
mutant 44-relay-notifications relay_server_message '        if method in PASSTHROUGH_NOTIFICATIONS:' '        if True:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m44 "$MUTANT_PATH" --env FAKE_PW_NOTIFY=1 --send "$INIT" --send "$SNAP" --end eof)"; red 'row 44: every notification relayed → a notifications/message reaches the client' bash -c 'started "$1" && stdout_has "$1" notifications/message' _ "$r"; fi
mutant 45-relay-requests relay_server_message '            if method in PASSTHROUGH_REQUESTS and self.plain_id(msg.get("id")):' '            if True:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m45 "$MUTANT_PATH" --env FAKE_PW_SERVER_REQUEST=1 --send "$INIT" --send "$SNAP" --end eof)"; red 'row 45: every server request relayed → a sampling/createMessage reaches the client' bash -c 'started "$1" && stdout_has "$1" sampling/createMessage' _ "$r"; fi
mutant 46-error-message-unchecked vet_error 'if not isinstance(message, str) or self.looks_like_a11y_tree(message) or self.redact_text(message) != message:' 'if False:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m46 "$MUTANT_PATH" --env FAKE_PW_RESULT_FILE="$ODD/error-message-tree.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 46: error message not vetted → tree row leaks' bash -c 'started "$1" && stdout_has "$1" ZZQP-SENTINEL-7980' _ "$r"; fi
mutant 47-reuse-overwrites pump_client_to_server '            if key in self.pending:' '            if False:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m47 "$MUTANT_PATH" --send "$INIT" --send "$SNAP" --send '{"jsonrpc":"2.0","id":3,"method":"tools/list"}' --end eof)"; red 'row 47: reuse not refused → no refusal, one answer for two requests' bash -c 'started "$1" && [[ "$(fact "$1" 3 count)" == "1" ]] && ! stderr_has "$1" "reusing a pending id"' _ "$r"; fi
mutant 48-route-by-method-only pump_server_to_client 'if method == "tools/call" or (isinstance(result, dict) and "content" in result):' 'if method == "tools/call":'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m48 "$MUTANT_PATH" --env FAKE_PW_FIXTURE_DIR="$INITTREE" --send "$INIT" --end eof)"; red 'row 48: routed by method only → a tree answering initialize leaks' leaks "$r" 1; fi
mutant 49-no-escaped-check rewrite_result 'if self.escaped_tree_in(text):' 'if False:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m49 "$MUTANT_PATH" --env FAKE_PW_RESULT_FILE="$ODD/run-code-escaped.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 49: escaped-tree check removed → the escaped tree leaks' leaks "$r" 3; fi
mutant 50-kill-only-live-child teardown '        if not self.wait_group_empty(self.grace):' '        if child.poll() is None and not self.wait_group_empty(self.grace):'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m50 "$MUTANT_PATH" --env FAKE_PW_GRANDCHILD=1 --send "$INIT" --end eof --timeout 4)"; red 'row 50: escalation keyed on the direct child → the grandchild survives' bash -c 'started "$1" && [[ "$(cat "$1/group_after")" -gt 0 ]]' _ "$r"; reap_group "$r"; fi
mutant 51-save-video refuse_argv_and_env '        if cfg.get("saveVideo"):' '        if False:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m51 "$MUTANT_PATH" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --config="$WORK/cfg-video.json")"; red 'row 51: saveVideo check removed → proxy starts' started "$r"; fi
mutant 52-output-mode refuse_argv_and_env 'if any(v != "stdout" for v in argv_values(server, "--output-mode")):' 'if False:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m52 "$MUTANT_PATH" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --output-mode file)"; red 'row 52: --output-mode check removed → proxy starts' started "$r"; fi
mutant 53-config-server refuse_argv_and_env 'if isinstance(srv, dict) and (srv.get("port") is not None or srv.get("host") is not None):' 'if False:'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m53 "$MUTANT_PATH" --send "$INIT" --end eof --timeout 3 --server python3 "$STUB" --config="$WORK/cfg-port.json")"; red 'row 53: config server.port check removed → proxy starts' started "$r"; fi
mutant 54-relay-verbatim relay_server_message '            write_line(self.out, json.dumps(rebuilt, separators=(",", ":")).encode())' '            write_line(self.out, json.dumps(msg, separators=(",", ":")).encode())'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m54 "$MUTANT_PATH" --env FAKE_PW_CANCEL=1 --send "$INIT" --send "$SNAP" --end eof)"; red 'row 54: relayed notifications not rebuilt → the reason/_meta tree reaches the client' bash -c 'started "$1" && stdout_has "$1" ZZQP-SENTINEL-7980' _ "$r"; fi
mutant 55-any-id-plain plain_id '        return isinstance(value, str) and not self.looks_like_a11y_tree(value) and self.redact_text(value) == value' '        return True'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m55 "$MUTANT_PATH" --env FAKE_PW_CANCEL=1 --send "$INIT" --send "$SNAP" --end eof)"; red 'row 55: requestId not vetted → a tree row rides a cancellation to the client' bash -c 'started "$1" && stdout_has "$1" ZZQP-SENTINEL-7980' _ "$r"; fi
mutant 56-escaped-needs-newline escaped_tree_in '            if any(self.looks_like_a11y_tree(s) for s in json_strings(parsed)):' '            if any("\n" in s and self.looks_like_a11y_tree(s) for s in json_strings(parsed)):'
if [[ -n "$MUTANT_PATH" ]]; then r="$(session m56 "$MUTANT_PATH" --env FAKE_PW_RESULT_FILE="$ODD/run-code-escaped-one-row.json" --send "$INIT" --send "$SNAP" --end eof)"; red 'row 56: escaped check requires a newline → a one-row tree leaks' leaks "$r" 3; fi
EXPECTED_MUTANTS=56   # rows 1-56 without row 4, with 22a/22b; exactly one mutation row each
EXPECTED_RED_ROWS=56

# ---------------------------------------------------------------------------
# Guard 2 — .mcp.json routing, EXECUTABLE (scratch HOME, npx shim on PATH)
# ---------------------------------------------------------------------------
G2="$WORK/g2"; mkdir -p "$G2/home" "$G2/bin" "$G2/stale"; printf '{}\n' > "$G2/second-config.json"
cp "$PASSTHROUGH" "$G2/stale/playwright-mcp-redact-proxy.py"
# The npx shim: one JSON record per call, APPENDED — the argv, and the parent resolved
# by pid. (Two files rather than a nested heredoc, which line-based heredoc scanners
# such as guard-vacuity-floor's cannot see the end of.)
cat > "$G2/npx-record.py" <<'PY'
import json, os, sys
ppid = sys.argv[1]
cmd = [c.decode() for c in open(f"/proc/{ppid}/cmdline", "rb").read().split(b"\0") if c]
cwd = os.readlink(f"/proc/{ppid}/cwd")
script = os.path.realpath(os.path.join(cwd, cmd[1])) if len(cmd) > 1 else ""
print(json.dumps({"argv": sys.argv[2:], "parent_comm": open(f"/proc/{ppid}/comm").read().strip(), "parent_script": script}))
PY
printf '#!/usr/bin/env bash\npython3 "%s" "$PPID" "$@" %s "$SHIM_OUT"\n' "$G2/npx-record.py" '>>' > "$G2/bin/npx"
chmod +x "$G2/bin/npx"
# run_mcp_args <args1-string> <tag>; the wrapper's pkill/rm lines resolve $prof under the scratch HOME
run_mcp_args() {
  local cmd="$1" tag="$2"
  : > "$G2/$tag.jsonl"
  ( cd "$REPO_ROOT" && export SHIM_OUT="$G2/$tag.jsonl" HOME="$G2/home" PATH="$G2/bin:$PATH" && sleep 5 | timeout 20 bash -c "$cmd" >/dev/null 2>"$G2/$tag.err" ) || true
}
# g2_prop <jsonl> <property> — exit 0 when the property holds; 3 when the shim never ran
g2_prop() {
  python3 - "$1" "$2" "$PROXY_SHIPPED" "$PIN" "$G2/home/.cache/playwright-mcp-profile" <<'PY'
import json, os, sys
path, prop, shipped, pin, prof = sys.argv[1:]
calls = [json.loads(l) for l in open(path) if l.strip()]
if not calls:
    sys.exit(3)
argv = calls[0]["argv"]
checks = {
    "one-call": len(calls) == 1,
    "parent-is-shipped-proxy": len(calls) == 1 and calls[0]["parent_comm"] == "python3" and calls[0]["parent_script"] == os.path.realpath(shipped),
    "pin-once": argv.count(f"@playwright/mcp@{pin}") == 1,
    "profile-once": argv.count(f"--user-data-dir={prof}") == 1 and sum(a.startswith("--user-data-dir") for a in argv) == 1,
    "config-once": argv.count("--config=.claude/playwright-mcp.config.json") == 1 and sum(a.startswith("--config") for a in argv) == 1,
    "flag-appended-once": argv[-2:] == ["--snapshot-mode", "none"] and argv.count("--snapshot-mode") == 1,
}
sys.exit(0 if checks[prop] else 1)
PY
}
export G2 PROXY_SHIPPED PIN
MCP_ARGS="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['mcpServers']['playwright']['args'][1])" "$REPO_ROOT/.mcp.json")"
MCP_ARG0="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['mcpServers']['playwright']['args'][0])" "$REPO_ROOT/.mcp.json")"
assert_true 'Guard 2: .mcp.json playwright command is bash -c <string>' test "$MCP_ARG0" = "-c"
assert_true 'Guard 2: the .mcp.json string itself carries no --snapshot-mode (only the proxy may append it)' bash -c '[[ "$1" != *"--snapshot-mode"* ]]' _ "$MCP_ARGS"
run_mcp_args "$MCP_ARGS" g2
for prop in one-call parent-is-shipped-proxy pin-once profile-once config-once flag-appended-once; do
  assert_true "Guard 2: $prop" g2_prop "$G2/g2.jsonl" "$prop"
done
# Guard 2 mutants of the args string: each must fail its property while the shim DID run
g2_mut() {  # <label> <mutated-args> <tag> <property>
  local label="$1" mutated="$2" tag="$3" prop="$4"
  cases=$((cases + 1))
  if [[ "$mutated" == "$MCP_ARGS" ]]; then bad "$label — mutation did not land"; return 0; fi
  run_mcp_args "$mutated" "$tag"
  local rc=0; g2_prop "$G2/$tag.jsonl" "$prop" || rc=$?
  if [[ $rc == 1 ]]; then ok "$label"; elif [[ $rc == 3 ]]; then bad "$label — the shim never ran"; else bad "$label — mutant survived"; fi
}
PROXY_REL='python3 plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py -- '
g2_mut 'Guard 2 mutant 1: proxy removed → the parent is not the shipped proxy' "${MCP_ARGS/"$PROXY_REL"/}" g2m1 parent-is-shipped-proxy
M2="$(python3 -c 'import sys; s,p=sys.argv[1],sys.argv[2]; i=s.index(p); s=s[:i]+s[i+len(p):]; print(s.rstrip()+" -- "+p.strip(" -"))' "$MCP_ARGS" "$PROXY_REL")"
g2_mut 'Guard 2 mutant 2: proxy AFTER the server → the parent is not the shipped proxy' "$M2" g2m2 parent-is-shipped-proxy
g2_mut 'Guard 2 mutant 3: --config dropped → argv lacks it' "${MCP_ARGS// --config=.claude\/playwright-mcp.config.json/}" g2m3 config-once
g2_mut "Guard 2 mutant 4: version bumped in .mcp.json alone → argv no longer carries @playwright/mcp@$PIN" "${MCP_ARGS//@playwright\/mcp@$PIN/@playwright\/mcp@9.9.9}" g2m4 pin-once
g2_mut 'Guard 2 mutant 6: a passthrough saved under the proxy'"'"'s filename → not the shipped proxy' "${MCP_ARGS/plugins\/soleur\/skills\/agent-browser\/scripts\/playwright-mcp-redact-proxy.py/$G2/stale/playwright-mcp-redact-proxy.py}" g2m6 parent-is-shipped-proxy
g2_mut 'Guard 2 mutant 7: an unwrapped npx run before the wrapped one → two calls' "${MCP_ARGS/exec env/npx @playwright/mcp@$PIN --probe; exec env}" g2m7 one-call
g2_mut 'Guard 2 mutant 8: a second --config later in the args → config not once' "${MCP_ARGS/--config=.claude\/playwright-mcp.config.json/--config=.claude/playwright-mcp.config.json --config=$G2/second-config.json}" g2m8 config-once
g2_mut 'Guard 2 mutant 9: a second --user-data-dir → profile not once' "${MCP_ARGS/--user-data-dir=\$prof/--user-data-dir=\$prof --user-data-dir=/tmp/other}" g2m9 profile-once
g2_mut 'Guard 2 mutant 10: --snapshot-mode full in the args → flag not appended once' "${MCP_ARGS/--user-data-dir=\$prof/--snapshot-mode full --user-data-dir=\$prof}" g2m10 flag-appended-once
assert_true 'Guard 2 mutant 5: renaming the server key fails the lookup loudly' bash -c '! python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d[\"mcpServers\"][\"playwrite\"]=d[\"mcpServers\"].pop(\"playwright\"); print(d[\"mcpServers\"][\"playwright\"][\"args\"][1])" "$1" 2>/dev/null' _ "$REPO_ROOT/.mcp.json"
# Reaper discrimination (Phase 0.3): the wrapper's pkill patterns vs the executed group
assert_true 'reaper: the proxy pkill pattern is ordered BEFORE the child pkill in .mcp.json' python3 - "$MCP_ARGS" <<'PY'
import sys
s = sys.argv[1]
a, b = s.find("[p]laywright-mcp-redact-proxy.py"), s.find("[b]in/playwright-mcp")
sys.exit(0 if 0 <= a < b else 1)
PY
assert_true 'reaper: neither pkill pattern matches the wrapper'"'"'s own literal $prof line' python3 - "$MCP_ARGS" <<'PY'
import re, sys
s = sys.argv[1]
pats = re.findall(r'pkill -9 -f "([^"]+)"', s)
# at pkill time $prof is EXPANDED in the pattern, while the wrapper's own command line still holds it literally
sys.exit(0 if len(pats) >= 3 and all(not re.search(p.replace("$prof", "/scratch/.cache/playwright-mcp-profile"), s) for p in pats) else 1)
PY
reap_all
assert_true 'hygiene: sessions recorded their child groups, and none still holding a stub outlives the reap' bash -c '[[ "$1" -gt 0 && -z "$2" ]]' _ "$(grep -c . "$PGIDS" || true)" "$(stub_groups)"

# ---------------------------------------------------------------------------
# Verdict. Reported with printf + exit, never through ok()/bad() (ADR-193).
# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed, %d cases (%d mutants, %d mutation rows)\n' "$pass" "$fail" "$cases" "$mutants_declared" "$red_rows"

if [[ $((pass + fail)) -ne $cases ]]; then
  printf '[FATAL] vacuity accounting: pass+fail (%d) != cases (%d) — a row did not report\n' "$((pass + fail))" "$cases" >&2
  exit 1
fi
if [[ $mutants_declared -ne $EXPECTED_MUTANTS || $red_rows -ne $EXPECTED_RED_ROWS ]]; then
  printf '[FATAL] mutation matrix: %d mutants / %d mutation rows ran, expected %d / %d — a row vanished\n' "$mutants_declared" "$red_rows" "$EXPECTED_MUTANTS" "$EXPECTED_RED_ROWS" >&2
  exit 1
fi
MIN_ASSERTIONS=284
if [[ $cases -lt $MIN_ASSERTIONS ]]; then
  printf '[FATAL] vacuity floor: only %d cases executed, expected at least %d\n' "$cases" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ $fail -eq 0 ]] || exit 1
exit 0
