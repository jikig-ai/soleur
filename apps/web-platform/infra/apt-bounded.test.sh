#!/usr/bin/env bash
#
# Unit suite for lib/apt-bounded.sh (#9379, #9395): one shared budget of apt seconds on every in-container apt
# cycle in the four consumer suites (three git-data suites and the provision-unit Tier B build), with expiry routed to the declared environment decline
# (FIXTURE_APT_FAILED + exit 100) and every non-timeout failure keeping its own rc.
#
# Host-only: a stub `apt-get` on PATH and the real coreutils `timeout`; no docker, no network.
# Behaviour rows drive the helper in a fresh `bash` (set -u, the shell the container drivers give it).
# The assembly row is DERIVED from the four consumer suites and binds each docker site to its arm, its mount,
# its source line and its rc handling; it reads the suites' text, so it pins what the text says, and the
# containers' run-time behaviour is covered by the rows above it.
#
# Run: bash apps/web-platform/infra/apt-bounded.test.sh
# Presence under apps/web-platform/infra/ IS registration — derived and run by run-registered-suites.sh (#8736).

# shellcheck disable=SC1090  # the lib path is computed from this file's location
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${DIR}/lib/apt-bounded.sh"
OWN="${DIR}/git-data-ownership.test.sh"
REH="${DIR}/git-data-runcmd-rehearsal.test.sh"
CUT="${DIR}/git-data-cutover-access.test.sh"
PUS="${DIR}/cloud-init-inngest-provision-unit.test.sh"

passes=0; fails=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# INSTRUMENT SELF-TEST (ADR-193): drive both helpers once inside a subshell and refuse to continue
# unless every observable moved. Reported with printf + exit, never through the helpers it guards.
_st="$( { pass st-a; fail st-b; } >/dev/null 2>&1; printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}" )"
if [ "$_st" != "1 1 1" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() did not move their counters and ledger (got "%s", want "1 1 1").\n' "$_st" >&2
  exit 1
fi

W="$(mktemp -d "${TMPDIR}/aptb.XXXXXX")"
trap 'rm -rf "$W"' EXIT
STUB="$W/bin"; mkdir -p "$STUB"
# Stub apt-get. Mode comes from GD_STUB_MODE; every invocation appends one line to GD_STUB_CALLS.
cat > "$STUB/apt-get" <<'STUBEOF'
#!/usr/bin/env bash
echo "$*" >> "${GD_STUB_CALLS:?}"
n=$(wc -l < "${GD_STUB_CALLS}")
case "${GD_STUB_MODE:?}" in
  ok)   exit 0 ;;
  fail) echo "E: Failed to fetch http://alice:s3cr3t@proxy.invalid:3128/ubuntu/dists/noble/InRelease  Unable to connect" >&2
        echo "E: Failed to fetch http://bob:p@ss/w0rd@proxy2.invalid:3128/x  Unable to connect" >&2
        echo "W: carol:hunter2@proxy3.invalid failed" >&2
        echo "Proxy-Authorization: Basic dXNlcjpwdw==" >&2
        echo "Get:1 http://archive.ubuntu.com/ubuntu noble InRelease" >&2
        exit 100 ;;
  fail-install) case "$1" in update) exit 0 ;; *) echo "E: install failed" >&2; exit 100 ;; esac ;;
  hang) sleep 300 & echo "$!" > "${GD_STUB_CHILD:?}"; wait ;;
  hang-once) if [ "$n" -eq 1 ]; then sleep 300 & echo "$!" > "${GD_STUB_CHILD:?}"; wait; fi; exit 0 ;;
  slow) sleep "${GD_STUB_SLEEP:-1}"; exit 0 ;;
  fail-then-ok) [ "$n" -eq 1 ] && { echo "E: transient" >&2; exit 100; }; exit 0 ;;
  oom)  exit 137 ;;
esac
exit 99
STUBEOF
chmod +x "$STUB/apt-get"

# run_helper <mode> <budget|unset> [pkg...] — sets RC OUT ERR CALLS ELAPSED. The state dir is rebuilt
# per call unless KEEP_STATE=1 (rows that chain calls to prove the budget is SHARED); PRE_SPENT seeds it.
run_helper() {
  local mode="$1" budget="$2"; shift 2
  OUT="$W/out"; ERR="$W/err"; CALLS="$W/calls"; : > "$CALLS"; : > "$OUT"; : > "$ERR"
  rm -f "$W/child"
  if [ "${KEEP_STATE:-0}" != 1 ]; then
    rm -rf "$W/state"
    if [ "$budget" != unset ]; then mkdir -p "$W/state"; printf '%s\n' "$budget" > "$W/state/budget"; printf '%s\n' "${PRE_SPENT:-}" | sed '/^$/d' > "$W/state/spent"; fi
  fi
  local t0; t0=$(date +%s)
  RC=0
  # shellcheck disable=SC2016  # single-quoted on purpose: expands inside the fresh bash
  env PATH="$STUB:$PATH" GD_STUB_MODE="$mode" GD_STUB_CALLS="$CALLS" GD_STUB_CHILD="$W/child" \
    GD_APT_LOG="$W/apt.log" GD_APT_BACKOFFS="${GD_APT_BACKOFFS:-0 0}" GD_APT_STATE_DIR="${GD_APT_STATE_DIR:-$W/state}" \
    bash --noprofile --norc -c 'set -u; . "$1" || exit 97; shift; gd_apt_install_bounded "$@"' _ "$LIB" "${@:-curl}" \
    >"$OUT" 2>"$ERR" || RC=$?
  ELAPSED=$(( $(date +%s) - t0 ))
}
calls() { wc -l < "$CALLS" | tr -d ' '; }
last_err_line() { tail -n 1 "$ERR"; }
spent_total() { awk '{s += $1} END {print s + 0}' "$W/state/spent"; }
reap_child() { local c; c="$(cat "$W/child" 2>/dev/null || true)"; [ -n "$c" ] && kill "$c" 2>/dev/null || true; }

checked=0
row() { checked=$((checked + 1)); }

# ── Behaviour rows ───────────────────────────────────────────────────────────────────────
row; run_helper ok 60 curl python3
if [ "$RC" -eq 0 ] && [ "$(calls)" -eq 2 ] && grep -q '^update ' "$CALLS" && grep -qE '^install .*Acquire::Retries=5.* curl python3$' "$CALLS" && ! grep -q . "$ERR"; then
  pass "A1: healthy archive — rc 0, update then install once each, nothing on stderr"
else fail "A1: healthy archive" "rc=$RC calls=$(calls) calls-file=[$(tr '\n' '|' < "$CALLS")] stderr=[$(head -c 200 "$ERR")]"; fi

row; run_helper hang 3 curl
_child="$(cat "$W/child" 2>/dev/null || true)"
_orphan=yes; for _i in 1 2 3 4 5; do if [ -n "$_child" ] && kill -0 "$_child" 2>/dev/null; then sleep 0.2; else _orphan=no; break; fi; done
if [ "$RC" -eq 100 ] && [ "$ELAPSED" -le 10 ] && [ "$(last_err_line)" = "FIXTURE_APT_FAILED" ] \
   && grep -qE '^FIXTURE_APT_CAUSE: timeout ' "$ERR" && [ -n "$_child" ] && [ "$_orphan" = no ] && [ "$(spent_total)" -ge 3 ]; then
  pass "A2: hung archive — bounded (${ELAPSED}s), rc 100, cause=timeout then the bare marker LAST, no orphan child, the time is charged"
else fail "A2: hung archive" "rc=$RC elapsed=${ELAPSED}s orphan=$_orphan child=[$_child] spent=$(spent_total) last=[$(last_err_line)] stderr=[$(head -c 300 "$ERR")]"; fi
reap_child

row; PRE_SPENT=40 run_helper ok 30 curl
if [ "$RC" -eq 100 ] && [ "$(calls)" -eq 0 ] && [ "$(last_err_line)" = "FIXTURE_APT_FAILED" ] && grep -qE '^FIXTURE_APT_CAUSE: timeout ' "$ERR"; then
  pass "A3: budget already spent by earlier containers — no apt invoked, same marker, rc 100"
else fail "A3: budget already spent" "rc=$RC calls=$(calls) last=[$(last_err_line)]"; fi

# A3b — the BOUNDARY: spent == budget exactly is the normal end state (a clamped last attempt charges its whole
# allotment). With `left == 0` the cap would otherwise become `timeout 0`, which means NO timeout.
row; PRE_SPENT=5 run_helper hang 5 curl
if [ "$RC" -eq 100 ] && [ "$(calls)" -eq 0 ] && [ "$ELAPSED" -le 3 ] && [ "$(last_err_line)" = "FIXTURE_APT_FAILED" ]; then
  pass "A3b: spent == budget runs no apt and declines at once (never an unbounded timeout 0)"
else fail "A3b: spent == budget" "rc=$RC calls=$(calls) elapsed=${ELAPSED}s"; fi
reap_child

row; run_helper fail-then-ok 60 curl
if [ "$RC" -eq 0 ] && [ "$(calls)" -eq 3 ]; then
  pass "A4: transient failure then success — retry preserved (3 apt calls: update fail, update, install)"
else fail "A4: transient failure then success" "rc=$RC calls=$(calls)"; fi

row; GD_STUB_SLEEP=1 run_helper slow 30 curl
if [ "$RC" -eq 0 ] && [ "$(calls)" -eq 2 ]; then
  pass "A5: slow archive inside the budget still passes (the bound must not reject a slow day)"
else fail "A5: slow archive inside the budget" "rc=$RC calls=$(calls) elapsed=${ELAPSED}s"; fi

row; run_helper oom 60 curl
if [ "$RC" -eq 137 ] && [ "$(calls)" -eq 1 ] && ! grep -qx FIXTURE_APT_FAILED "$ERR"; then
  pass "A6: an OOM-shaped kill (rc 137, no timeout) keeps its rc, is not retried, and does NOT emit the decline marker"
else fail "A6: OOM-shaped kill" "rc=$RC calls=$(calls) last=[$(last_err_line)]"; fi

# A7 — exhausted apt errors; the scrub must remove every credential shape AND keep an ordinary archive URL.
row; run_helper fail 60 curl
_leak=""; for _s in s3cr3t 'p@ss' w0rd hunter2 dXNlcjpwdw; do grep -qF "$_s" "$ERR" && _leak="$_leak $_s"; done
if [ "$RC" -eq 100 ] && [ "$(last_err_line)" = "FIXTURE_APT_FAILED" ] && [ -z "$_leak" ] && grep -q '\*\*\*' "$ERR" \
   && grep -qF 'archive.ubuntu.com/ubuntu noble InRelease' "$ERR" \
   && grep -qE '^FIXTURE_APT_CAUSE: apt-error ' "$ERR" && [ "$(calls)" -eq 3 ]; then
  pass "A7: exhausted apt errors — 3 attempts, every credential shape scrubbed, an ordinary archive URL retained, cause=apt-error, marker last, rc 100"
else fail "A7: exhausted apt errors" "rc=$RC calls=$(calls) leaked=[$_leak] last=[$(last_err_line)] stderr=[$(head -c 400 "$ERR")]"; fi

row; run_helper ok unset curl
_rc_unarmed=$RC; _calls_unarmed=$(calls); _marker_unarmed=no; grep -qx FIXTURE_APT_FAILED "$ERR" && _marker_unarmed=yes
rm -rf "$W/state"; mkdir -p "$W/state"; printf '9\n' > "$W/state/budget"   # half-armed: budget without spent
KEEP_STATE=1 run_helper ok 9 curl
if [ "$_rc_unarmed" -eq 98 ] && [ "$_calls_unarmed" -eq 0 ] && [ "$_marker_unarmed" = no ] && [ "$RC" -eq 98 ] && [ "$(calls)" -eq 0 ]; then
  pass "A8: an UNARMED or half-armed state (mount forgotten / spent missing) is a loud harness defect (rc 98), never a silent fallback or the decline"
else fail "A8: unarmed state" "unarmed rc=$_rc_unarmed calls=$_calls_unarmed marker=$_marker_unarmed; half-armed rc=$RC calls=$(calls)"; fi

# A11 — the budget is SHARED: a second container inherits what the first spent. Two calls, one state.
row
GD_STUB_SLEEP=2 run_helper slow 6 curl      # ~4 s of apt time charged (update + install, 2 s each)
_first_rc=$RC
KEEP_STATE=1 run_helper hang 6 curl         # only ~2 s left: must be cut off near 2 s, not near 6
if [ "$_first_rc" -eq 0 ] && [ "$RC" -eq 100 ] && [ "$ELAPSED" -le 6 ] && [ "$(spent_total)" -ge 6 ]; then
  pass "A11: shared budget — the second container inherited the first one's spend (cut off after ${ELAPSED}s, total charged $(spent_total)s of 6)"
else fail "A11: shared budget" "first-rc=$_first_rc rc=$RC elapsed=${ELAPSED}s spent=$(spent_total)"; fi
reap_child

# A12 — only APT time is charged: sleeping OUTSIDE the helper between two containers spends nothing.
row
run_helper ok 3 curl
_first_rc=$RC
sleep 4
KEEP_STATE=1 run_helper ok 3 curl
if [ "$_first_rc" -eq 0 ] && [ "$RC" -eq 0 ] && [ "$(spent_total)" -le 2 ]; then
  pass "A12: non-apt time is not charged (4 s elapsed between containers on a 3 s budget; charged $(spent_total)s)"
else fail "A12: non-apt time charged" "first-rc=$_first_rc rc=$RC spent=$(spent_total)"; fi

# A13 — a STALLED attempt is cut at the per-attempt cap and retried: the first apt call hangs, the cap (2 s)
# kills it, the retry succeeds, and the 20 s budget was never close to spent. Without the cap the first
# attempt would own the whole budget (20 s) and the container would decline.
row; GD_APT_ATTEMPT_CAP=2 run_helper hang-once 20 curl
reap_child
if [ "$RC" -eq 0 ] && [ "$ELAPSED" -le 8 ] && [ "$(calls)" -eq 3 ] && [ "$(spent_total)" -le 8 ]; then
  pass "A13: a stalled attempt is cut at the per-attempt cap and retried (rc 0 after ${ELAPSED}s, 3 apt calls, charged $(spent_total)s of 20)"
else fail "A13: per-attempt cap" "rc=$RC elapsed=${ELAPSED}s calls=$(calls) spent=$(spent_total)"; fi

# A14 — a PERSISTENT stall is bounded by attempts x cap, not by the whole budget: 3 attempts of 1 s.
row; GD_APT_ATTEMPT_CAP=1 run_helper hang 30 curl
reap_child
if [ "$RC" -eq 100 ] && [ "$ELAPSED" -le 10 ] && [ "$(calls)" -eq 3 ] && [ "$(last_err_line)" = "FIXTURE_APT_FAILED" ] && grep -qE '^FIXTURE_APT_CAUSE: timeout .*attempt=3 ' "$ERR"; then
  pass "A14: a persistent stall is bounded by 3 capped attempts (${ELAPSED}s of a 30 s budget), cause=timeout, marker last"
else fail "A14: persistent stall" "rc=$RC elapsed=${ELAPSED}s calls=$(calls) stderr=[$(head -c 300 "$ERR")]"; fi

# A15 — a cap of 0 (or garbage) must NOT disable the bound (`timeout 0` = no timeout): it falls back to the default.
row; GD_APT_ATTEMPT_CAP=0 run_helper hang 3 curl
reap_child
if [ "$RC" -eq 100 ] && [ "$ELAPSED" -le 10 ] && [ "$(last_err_line)" = "FIXTURE_APT_FAILED" ]; then
  pass "A15: GD_APT_ATTEMPT_CAP=0 still ends within the budget (${ELAPSED}s), not unbounded"
else fail "A15: cap 0" "rc=$RC elapsed=${ELAPSED}s"; fi

# A16 — a leading-zero budget is decimal, never octal (`08` is an arithmetic error under $(( ))).
row; run_helper ok 08 curl
if [ "$RC" -eq 0 ] && [ "$(calls)" -eq 2 ]; then
  pass "A16: a leading-zero budget (08) is read as decimal"
else fail "A16: leading-zero budget" "rc=$RC calls=$(calls) stderr=[$(head -c 200 "$ERR")]"; fi

# A17 — the cause line names the stage that failed: update succeeds, install fails.
row; run_helper fail-install 30 curl
if [ "$RC" -eq 100 ] && [ "$(calls)" -eq 6 ] && grep -qE '^FIXTURE_APT_CAUSE: apt-error stage=install ' "$ERR" && [ "$(last_err_line)" = "FIXTURE_APT_FAILED" ]; then
  pass "A17: an install-stage failure is named stage=install (3 attempts of update+install)"
else fail "A17: install stage" "rc=$RC calls=$(calls) stderr=[$(head -c 300 "$ERR")]"; fi

# A18 — backoff is APT-cycle time: it is charged, and a backoff that would consume the rest of the budget
# ends the run as apt-error instead of sleeping the remainder and mislabelling the cause as a timeout.
row
GD_APT_BACKOFFS="1 1" run_helper fail 30 curl
_b1_rc=$RC; _b1_calls=$(calls); _b1_spent=$(spent_total); _b1_el=$ELAPSED
GD_APT_BACKOFFS="10 30" run_helper fail 3 curl
if [ "$_b1_rc" -eq 100 ] && [ "$_b1_calls" -eq 3 ] && [ "$_b1_spent" -ge 2 ] && [ "$_b1_el" -ge 2 ] \
   && [ "$RC" -eq 100 ] && [ "$(calls)" -eq 1 ] && [ "$ELAPSED" -le 3 ] && grep -qE '^FIXTURE_APT_CAUSE: apt-error ' "$ERR"; then
  pass "A18: backoff is charged to the budget (spent>=${_b1_spent}s over 3 attempts); a backoff longer than the remainder ends as apt-error without sleeping"
else fail "A18: backoff" "b1 rc=$_b1_rc calls=$_b1_calls spent=$_b1_spent elapsed=$_b1_el; b2 rc=$RC calls=$(calls) elapsed=${ELAPSED}s stderr=[$(head -c 300 "$ERR")]"; fi

# A19 — the HOST half, executed: arm is idempotent ON DISK (even from a command substitution, which discards
# exports), keeps `spent`, copies the lib, normalises a leading zero, rejects a bad budget; the summary reports.
row
_ad="$W/armstate"
# shellcheck source=lib/apt-bounded.sh
_ao="$( ( . "$LIB"; gd_apt_state_arm "$_ad" 7 2>/dev/null; printf '3\n' >> "$_ad/spent"
          _x="$(gd_apt_state_arm "$_ad" 99 2>/dev/null)"; _rc2=$?
          printf 'rc2=%s budget=%s spent=%s\n' "$_rc2" "$(cat "$_ad/budget")" "$(awk '{s += $1} END {print s + 0}' "$_ad/spent")"
          gd_apt_state_summary ) 2>&1 )"
_oct="$( ( . "$LIB"; gd_apt_state_arm "$W/armoct" 08 2>/dev/null; cat "$W/armoct/budget" ) 2>&1 )"
_badrc=0; ( . "$LIB"; gd_apt_state_arm "$W/armbad" abc ) >/dev/null 2>&1 || _badrc=$?
_ia=0
# shellcheck disable=SC2016  # single-quoted on purpose: expands inside the fresh bash
env PATH="$STUB:$PATH" GD_STUB_MODE=ok GD_STUB_CALLS="$W/calls2" GD_APT_STATE_DIR="$_ad" GD_APT_LOG="$W/apt2.log" \
  bash --noprofile --norc -c 'set -u; . "$1/apt-bounded.sh" || exit 97; gd_apt_install_bounded curl' _ "$_ad" >/dev/null 2>&1 || _ia=$?
if printf '%s\n' "$_ao" | grep -qx 'rc2=0 budget=7 spent=3' && printf '%s\n' "$_ao" | grep -qx 'GD_APT: spent=3s of budget=7s across 1 apt attempt(s)' \
   && cmp -s "$LIB" "$_ad/apt-bounded.sh" && [ "$_oct" = 8 ] && [ "$_badrc" -eq 2 ] && [ "$_ia" -eq 0 ]; then
  pass "A19: arm is idempotent on disk and keeps spent, copies the lib, normalises 08, rejects abc; the summary reports; the armed dir drives the helper"
else fail "A19: host arm/summary" "arm-out=[$(printf '%s' "$_ao" | tr '\n' '|')] oct=[$_oct] bad-rc=$_badrc helper-rc=$_ia"; fi

# ── Derived assembly row ─────────────────────────────────────────────────────────────────
# For each consumer suite (comment-stripped, continuation-joined): every `docker run` site is either mounted
# with the EXACT state mount token or is one of the declared unmounted sites (the rehearsal's R1 container and
# the provision-unit suite's systemd boot container run no apt); each arm line (the suite's OWN state variable) is
# followed, as the next statement, by a MOUNTED docker run; every helper call carries a pass-through rc form
# (`|| exit $?`, S1's re-raise, R4's fixture_fail) and none a hardcoded `|| exit 100` / `|| true`; every call is
# preceded by the `. /work/apt/apt-bounded.sh || exit 97` (or fixture_fail) source line; every arm line checks its
# own return; and no apt/dpkg/pip appears in command position outside the helper. The grammars are defined ONCE
# below and asserted against a sample list (a grammar edit that stops seeing a site turns the row red with the
# sample that broke, not a quiet `total=0`), and a population census over every `*.test.sh` under the infra
# directory (recursively, as run-registered-suites.sh registers them) keeps the consumer list from being a
# hand-listed snapshot (#9395). BOUNDARY: the census reads infra suites; non-suite scripts and scripts outside
# this directory (for example apps/web-platform/scripts/*-in-image.sh) are not covered by this row.
_strip() { sed 's/^[[:space:]]*#.*$//' "$1"; }
_joined() { _strip "$1" | sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba' -e '}'; }
# Command position: start of line, after a separator or an opening bracket/negation, or after a keyword; then
# optional wrapper words, VAR= words and `timeout [flags] N [N]` (units allowed, no `{n,m}` interval: ADJ_RE is
# evaluated by awk and old mawk builds lack intervals).
_CMDPOS='(^|[;&|({!`]|-c[[:space:]]+['"'"'"]|(^|[[:space:]])(then|do|if|elif|else|while|until|exec|RUN))[[:space:]]*'
_END='([[:space:];&|)'"'"'"]|$)'
_WRAP='((sudo|env|command|nohup|time|nice)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*|docker[[:space:]]+exec[[:space:]]+(-[^[:space:]]+[[:space:]]+)*[^[:space:]]+[[:space:]]+)*'
_VARPFX='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
_TMO='(timeout[[:space:]]+(-[^[:space:]]+[[:space:]]+([A-Z]+[[:space:]]+)?)*([0-9]+[smhd]?[[:space:]]+)([0-9]+[smhd]?[[:space:]]+)?)?'
_BIN='(/[^[:space:]]*/)?'
DOCK_RE="${_CMDPOS}${_WRAP}${_VARPFX}${_TMO}${_BIN}docker[[:space:]]+(container[[:space:]]+)?run${_END}"
ADJ_RE="^[[:space:]]*((if|elif|while|until|exec)[[:space:]]+)?(![[:space:]]+)?${_WRAP}${_VARPFX}${_TMO}${_BIN}docker[[:space:]]+(container[[:space:]]+)?run${_END}"
RAW_RE="${_CMDPOS}${_WRAP}${_VARPFX}${_TMO}${_BIN}(apt-get|apt|aptitude|apt-fast|dpkg|pip3?|python3?[[:space:]]+-m[[:space:]]+pip)[[:space:]]+([^;&|]*[[:space:]])?(update|install|upgrade|dist-upgrade|full-upgrade|build-dep|reinstall|-i|--install)${_END}"
# Census predicates are deliberately looser than the site grammars in VERB (any docker verb that starts or enters
# a container; the whole apt family) but share their command-position anchor: a string that merely NAMES a command
# inside an assertion (`grep -qF 'apt-get install -y x'`) is data, not an apt cycle, and flagging it would turn
# every suite that tests another script's text into a candidate.
_DVAR='("?\$\{?[A-Za-z_]*(DOCKER|docker)[A-Za-z_]*\}?"?|(docker|podman))'
CENS_DOCK_RE="${_CMDPOS}${_WRAP}${_VARPFX}${_TMO}${_BIN}${_DVAR}[[:space:]]+([^;&|]*[[:space:]])?(run|exec|create|build|start|compose)${_END}|${_CMDPOS}${_BIN}(docker|podman)-compose${_END}"
# A suite that already uses the helper is a consumer too: leaving it out of SPECS must not silently drop its checks.
CENS_APT_RE="${RAW_RE}|(^|[^A-Za-z0-9_-])(gd_apt_install_bounded|gd_apt_state_arm)([[:space:]]|\$)"
# shellcheck disable=SC2016  # the literal mount token as it appears in the suites' text
MNT_LIT='-v "$GD_APT_STATE:/work/apt"'
# One TAB-separated spec per consumer: file, declared-unmounted sites, state variable the suite arms, mounted sites.
# A new consumer is one line here PLUS its conversion; the totals below are derived from this list.
TAB=$'\t'
SPECS=("${OWN}${TAB}0${TAB}TMP${TAB}1" "${REH}${TAB}1${TAB}TMP${TAB}5" "${CUT}${TAB}0${TAB}T${TAB}1" "${PUS}${TAB}1${TAB}W${TAB}1")
_asm=""; _tot=0; _unm=0; _exp_tot=0; _exp_unm=0
for _s in "docker run --rm img" "timeout -k 10 480 docker run --rm img" "timeout 480 docker run --rm img" \
          "timeout -s KILL 480 docker run --rm img" "timeout 600s docker run --rm img" "timeout -k 10s 480s docker run img" \
          "if ! docker run --name x img" "if docker run img" "elif docker run img" "while docker run img" "until docker run img" \
          "else docker run img" "FOO=1 docker run img" "cmd && docker run img" "sudo docker run img" "env A=1 docker run img" \
          "command docker run img" "/usr/bin/docker run img" "docker container run img"; do
  grep -Eq -- "$DOCK_RE" <<<"$_s" || _asm="${_asm} docker-grammar-misses-site:[${_s}]"
done
for _s in 'echo "docker run failed"' 'tb_unbootable "docker run failed (x)"' 'dockerrun img' 'echo docker run' 'docker rm -f x' 'docker exec c true'; do
  grep -Eq -- "$DOCK_RE" <<<"$_s" && _asm="${_asm} docker-grammar-matches-non-site:[${_s}]"
done
for _s in "timeout -k 10 480 docker run -v x img" "if ! timeout 480 docker run -v x img" "docker run -v x img" "FOO=1 docker run img"; do
  grep -Eq -- "$ADJ_RE" <<<"$_s" || _asm="${_asm} adj-grammar-misses-site:[${_s}]"
done
for _s in 'echo docker run' ': docker run' 'gd_apt_state_arm x docker run'; do
  grep -Eq -- "$ADJ_RE" <<<"$_s" && _asm="${_asm} adj-grammar-matches-non-site:[${_s}]"
done
for _s in "apt-get install -y curl" "timeout -k 5 30 apt-get install -y curl" "FOO=1 apt-get update" "x; do apt-get update -qq" \
          "apt-get -o Acquire::Retries=5 install -y curl" "apt-get -y --no-install-recommends install curl" "sudo apt-get install curl" \
          "env X=1 apt-get update" "/usr/bin/apt-get install curl" "if apt-get install -y curl; then :; fi" "until apt-get update; do :; done" \
          "else apt-get update" "apt install -y curl" "aptitude install curl" "dpkg -i x.deb" "dpkg --install x.deb" "pip3 install x" \
          "python3 -m pip install x" "apt-get dist-upgrade -y" "timeout 600s apt-get update"; do
  grep -Eq -- "$RAW_RE" <<<"$_s" || _asm="${_asm} raw-apt-grammar-misses:[${_s}]"
done
for _s in 'echo "apt-get install failed"' 'gd_apt_install_bounded curl' 'apt-bounded' 'apt-get remove install-info' 'x=apt-get'; do
  grep -Eq -- "$RAW_RE" <<<"$_s" && _asm="${_asm} raw-apt-grammar-matches-non-site:[${_s}]"
done
# shellcheck disable=SC2016  # sample lines: literal `$DOCKER` text, not an expansion
for _s in "docker create --name x img" "docker exec c apt-get update" "docker build -t x ." "sudo docker run img" "docker -H tcp://x run img" "docker compose run x" \
          "docker container run img" "podman run img" '$DOCKER run img' '"$docker_bin" exec c true' "bash -c 'docker run img'" "if docker exec c true; then" "docker-compose run x"; do
  grep -Eq -- "$CENS_DOCK_RE" <<<"$_s" || _asm="${_asm} census-docker-grammar-misses:[${_s}]"
done
for _s in "assert x \"grep -qF 'docker create --name x'\"" "echo docker exec failed" "ga_row \"docker exec failing with rc 125\"" "docker is absent"; do
  grep -Eq -- "$CENS_DOCK_RE" <<<"$_s" && _asm="${_asm} census-docker-grammar-matches-non-site:[${_s}]"
done
for _s in "RUN apt-get install -y x" "gd_apt_state_arm \"\$W/aptstate\" 1" "gd_apt_install_bounded curl" "bash -c 'apt-get install -y x'" "sh -c \"apt-get update\"" "docker exec c apt-get install curl"; do
  grep -Eq -- "$CENS_APT_RE" <<<"$_s" || _asm="${_asm} census-apt-grammar-misses:[${_s}]"
done
for _s in "assert x \"grep -qF 'apt-get install -y cloudflared'\"" "echo apt-get install failed" "apt-get is missing"; do
  grep -Eq -- "$CENS_APT_RE" <<<"$_s" && _asm="${_asm} census-apt-grammar-matches-non-site:[${_s}]"
done
for spec in "${SPECS[@]}"; do
  IFS="$TAB" read -r f want_unmounted sv want_mounted <<<"$spec"
  _exp_tot=$((_exp_tot + want_mounted)); _exp_unm=$((_exp_unm + want_unmounted))
  [ -f "$f" ] || { _asm="${_asm} $(basename "$f"):[missing]"; continue; }
  j="$(_joined "$f")"; u="$(_strip "$f")"
  dock="$(printf '%s\n' "$j" | grep -E -- "$DOCK_RE" || true)"
  # Count SITES (occurrences), not lines: two sites on one logical line must count twice.
  total=$(printf '%s\n' "$dock" | grep -oE -- "$DOCK_RE" | wc -l)
  mounted=$(printf '%s\n' "$dock" | grep -oF -- "$MNT_LIT" | wc -l)
  calls_=$(printf '%s\n' "$j" | grep -E '^[[:space:]]*(if[[:space:]]+)?gd_apt_install_bounded[[:space:]]' || true)
  c=$(printf '%s' "$calls_" | grep -c . || true)
  # shellcheck disable=SC2016  # literal source text of `|| exit $?` etc.
  c_ok=$(printf '%s\n' "$calls_" | grep -cE '\|\| (exit \$\?|\{ _s1_apt_rc=\$\?|\{ _apt_rc=\$\?)' || true)
  c_bad=$(printf '%s\n' "$calls_" | grep -cE '\|\| (exit 100|true)' || true)
  src=$(printf '%s\n' "$j" | grep -cE '^[[:space:]]*\. /work/apt/apt-bounded\.sh \|\| (exit 97|fixture_fail)' || true)
  arms=$(printf '%s\n' "$j" | grep -E '^[[:space:]]*gd_apt_state_arm[[:space:]]' || true)
  g=$(printf '%s' "$arms" | grep -c . || true)
  # shellcheck disable=SC2016  # literal source text
  g_ok=$(printf '%s\n' "$arms" | grep -cE '^[[:space:]]*gd_apt_state_arm "\$'"${sv}"'/aptstate" "\$APT_BUDGET_S" \|\| \{[^}]*exit 2; \}' || true)
  # The first statement after an arm must be a docker run that carries the mount (joined text: the whole site).
  adj=$(printf '%s\n' "$j" | awk -v re="$ADJ_RE" -v mnt="$MNT_LIT" '/^[[:space:]]*gd_apt_state_arm[[:space:]]/ {a=1; next} NF && a {a=0; if ($0 !~ re || index($0, mnt) == 0) bad++} END {print bad + 0}')
  raw=$(printf '%s\n' "$u" | grep -cE -- "$RAW_RE" || true)
  _tot=$((_tot + c)); _unm=$((_unm + total - mounted))
  if [ "$mounted" -ne "$want_mounted" ] || [ "$((total - mounted))" -ne "$want_unmounted" ] || [ "$mounted" -ne "$c" ] || [ "$c_ok" -ne "$c" ] \
     || [ "$c_bad" -ne 0 ] || [ "$src" -ne "$c" ] || [ "$g" -ne "$mounted" ] || [ "$g_ok" -ne "$g" ] || [ "$adj" -ne 0 ] || [ "$raw" -ne 0 ]; then
    _asm="${_asm} $(basename "$f"):[docker=$total mounted=$mounted (want $want_mounted) calls=$c rc-ok=$c_ok rc-bad=$c_bad source=$src arms=$g arm-checked=$g_ok arm-not-before-mounted-docker=$adj raw-apt=$raw]"
  fi
done
# Population census, derived from the tree and independent of the stored list above: every infra suite (recursive)
# that holds a docker verb AND apt text must be a declared consumer, and every declared consumer must be seen.
# This suite is the guard itself and carries the grammars as text, so it is the one file not scanned.
_decl="${TAB}"; for spec in "${SPECS[@]}"; do _spec_f="${spec%%"${TAB}"*}"; _decl="${_decl}${_spec_f#"${DIR}"/}${TAB}"; done
_seen=0
while IFS= read -r cf; do
  rel="${cf#"${DIR}"/}"
  case "$_decl" in *"${TAB}${rel}${TAB}"*) _seen=$((_seen + 1)) ;; esac
  [ "$rel" = "apt-bounded.test.sh" ] && continue
  grep -qE 'docker|podman' "$cf" || continue
  cj="$(_joined "$cf")"
  if grep -Eq -- "$CENS_DOCK_RE" <<<"$cj" && grep -Eq -- "$CENS_APT_RE" <<<"$cj"; then
    case "$_decl" in *"${TAB}${rel}${TAB}"*) : ;; *) _asm="${_asm} census:[${rel} holds a docker verb and apt text but is not a declared consumer — add a SPECS line (file, declared-unmounted, state var, mounted sites) and convert it to lib/apt-bounded.sh: arm, mount, source, call]" ;; esac
  fi
done < <(find "$DIR" -type f -name '*.test.sh' | sort)
[ "$_seen" -eq "${#SPECS[@]}" ] || { _asm="${_asm} census:[saw ${_seen} of ${#SPECS[@]} declared consumers under ${DIR}]"; }
row
if [ -z "$_asm" ] && [ "$_tot" -eq "$_exp_tot" ] && [ "$_unm" -eq "$_exp_unm" ]; then
  pass "A10: assembly (derived) — each apt-bearing docker run is armed just before it, mounts the exact state token, sources the lib and calls the helper with a pass-through rc; no raw apt (${_exp_tot} mounted sites + ${_exp_unm} declared unmounted, ${#SPECS[@]} suites, census clean)"
else fail "A10: assembly drift" "${_asm:-ok} total-helper-calls=$_tot (want $_exp_tot) unmounted=$_unm (want $_exp_unm). Legend: docker=docker run sites, mounted=sites carrying -v \"\$GD_APT_STATE:/work/apt\", calls=gd_apt_install_bounded calls (each needs '|| exit \$?' and a preceding '. /work/apt/apt-bounded.sh || exit 97'), arms=gd_apt_state_arm lines (exactly 'gd_apt_state_arm \"\$<var>/aptstate\" \"\$APT_BUDGET_S\" || { ...; exit 2; }', directly before a MOUNTED docker run), raw-apt must be 0. Keep APT_BUDGET_S plus the container's non-apt time under the site's host timeout and the suite bound."; fi

# ── FLOOR + LEDGER (ADR-193: printf + exit inside the block, never through pass()/fail()) ──
if [ "$checked" -lt 19 ]; then
  printf 'FAIL ANTI-VACUITY: only %s rows ran, floor is 19 — rows were deleted or the suite exited early.\n' "$checked" >&2
  exit 1
fi
if [ "$((passes + fails))" -ne "$checked" ]; then
  printf 'FAIL ANTI-VACUITY: %s rows ran but %s verdicts were counted — a row asserted nothing or twice.\n' "$checked" "$((passes + fails))" >&2
  exit 1
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then
  printf '  FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}"; exit 1
fi
printf '\n=== apt-bounded: %d passed, %d failed ===\n\n' "$passes" "$fails"
exit $(( ${#FAILURES[@]} > 0 ))
