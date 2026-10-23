#!/usr/bin/env bash
#
# Unit suite for lib/apt-bounded.sh (#9379, #9395): one shared budget of apt seconds on every in-container apt
# cycle in the six consumer suites (git-data-ownership, git-data-runcmd-rehearsal, git-data-cutover-access,
# htpasswd-stdin, cloud-init-inngest-provision-unit and sandbox-masked-proc-docker), with expiry routed to the declared
# environment decline (FIXTURE_APT_FAILED + exit 100) and every non-timeout failure keeping its own rc.
#
# Host-only: a stub `apt-get` on PATH and the real coreutils `timeout`; no docker, no network.
# Behaviour rows drive the helper in a fresh `bash` (set -u, the shell the container drivers give it).
# The assembly row is DERIVED from the six consumer suites and binds each docker site to its arm, its mount,
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
SMP="${DIR}/sandbox-masked-proc-docker.test.sh"
HTP="${DIR}/htpasswd-stdin.test.sh"

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
trap 'chmod -R u+rwX "$W" 2>/dev/null; rm -rf "$W"' EXIT
STUB="$W/bin"; mkdir -p "$STUB"
# Stub apt-get. Mode comes from GD_STUB_MODE; every invocation appends one line to GD_STUB_CALLS.
cat > "$STUB/apt-get" <<'STUBEOF'
#!/usr/bin/env bash
echo "$*" >> "${GD_STUB_CALLS:?}"
n=$(wc -l < "${GD_STUB_CALLS}")
# CACHE SIMULATION (Guard 4, #10781). Modes cache, cache-stall-once, cache-perms and cache-perms-fail model apt's use of
# `-o Dir::State::lists=` / `-o Dir::Cache::archives=`: a network cost is recorded in GD_STUB_NET ONLY when the lists are
# empty (FETCH-INDEX) or the package is neither in the archives dir (FETCH-PKG) nor resumable from archives/partial
# (RESUME-PKG); a populated lists dir costs one REVALIDATE (the conditional GET, not a download). A missing partial/ dir
# is fatal exactly as in real apt (rc 100); `install` needs the lists. Without a -o the call uses a fresh, private
# default dir of its own, so every call pays the network (what a per-container private cache looks like). The stub is
# EXACT-ARGV: any `-o` key it does not model (only Dir::State::lists, Dir::Cache::archives, Acquire::Retries) and any flag
# beyond -qq/-y/--no-install-recommends exits 64, so an option the lib quietly gains cannot ride along green.
_opt() { local k="$1" a prev=""; shift; for a in "$@"; do if [ "$prev" = -o ]; then case "$a" in "$k"=*) printf '%s' "${a#*=}"; return ;; esac; fi; prev="$a"; done; }
_cache_apt() {
  local verb="$1" lists archives p prev="" a; shift
  local -a pkgs=()
  lists="$(_opt Dir::State::lists "$@")"; archives="$(_opt Dir::Cache::archives "$@")"
  for a in "$@"; do
    if [ "$prev" = -o ]; then
      case "${a%%=*}" in Dir::State::lists|Dir::Cache::archives|Acquire::Retries) ;; *) echo "stub: unmodeled -o key '${a%%=*}'" >&2; return 64 ;; esac
      prev=""; continue
    fi
    case "$a" in -o) prev=-o ;; -qq|-y|--no-install-recommends) ;; -*) echo "stub: unmodeled flag '$a'" >&2; return 64 ;; *) pkgs+=("$a") ;; esac
  done
  case "${GD_STUB_MODE}" in cache-perms*) [ -z "$lists" ] || chmod -R u+rwX "$lists" 2>/dev/null; [ -z "$archives" ] || chmod -R u+rwX "$archives" 2>/dev/null ;; esac
  case "$verb" in
    update)
      if [ -z "$lists" ]; then echo "FETCH-INDEX private" >> "${GD_STUB_NET:?}"
      else
        [ -d "$lists/partial" ] || { echo "E: List directory $lists/partial is missing. - Acquire (2: No such file or directory)" >&2; return 100; }
        if [ -e "$lists/InRelease" ]; then echo "REVALIDATE" >> "${GD_STUB_NET:?}"; else echo "FETCH-INDEX shared" >> "${GD_STUB_NET:?}"; : > "$lists/InRelease"; fi
      fi ;;
    install)
      if [ -n "$lists" ] && [ ! -e "$lists/InRelease" ]; then echo "E: Unable to locate package ${pkgs[0]:-?}" >&2; return 100; fi
      if [ -n "$archives" ]; then
        [ -d "$archives/partial" ] || { echo "E: Archives directory $archives/partial is missing. - Acquire (2: No such file or directory)" >&2; return 100; }
        for p in "${pkgs[@]}"; do
          if [ -e "$archives/$p.deb" ]; then continue
          elif [ -e "$archives/partial/$p.deb.part" ]; then echo "RESUME-PKG $p" >> "${GD_STUB_NET:?}"; mv "$archives/partial/$p.deb.part" "$archives/$p.deb"
          else
            echo "FETCH-PKG $p" >> "${GD_STUB_NET:?}"
            if [ "${GD_STUB_MODE}" = cache-stall-once ] && [ ! -e "${GD_STUB_STALLED:?}" ]; then
              : > "$GD_STUB_STALLED"; : > "$archives/partial/$p.deb.part"
              sleep 300 & echo "$!" > "${GD_STUB_CHILD:?}"; wait
            fi
            : > "$archives/$p.deb"
          fi
        done
      else for p in "${pkgs[@]}"; do echo "FETCH-PKG $p private" >> "${GD_STUB_NET:?}"; done; fi ;;
  esac
  case "${GD_STUB_MODE}" in
    cache-perms*) # what a root apt leaves behind: download-user dirs and files the host user cannot remove
      for d in "$lists" "$archives"; do [ -z "$d" ] || { : > "$d/partial/lock"; chmod 600 "$d/partial/lock" "$d/InRelease" 2>/dev/null; chmod 500 "$d/partial"; }; done ;;
  esac
  return 0
}
case "${GD_STUB_MODE:?}" in
  cache|cache-stall-once|cache-perms) _cache_apt "$@"; exit $? ;;
  cache-perms-fail) case "$1" in update) _cache_apt "$@"; exit $? ;; *) _cache_apt "$@" || exit $?; echo "E: install failed" >&2; exit 100 ;; esac ;;
  ok)   exit 0 ;;
  fail) echo "E: Failed to fetch http://alice:s3cr3t@proxy.invalid:3128/ubuntu/dists/noble/InRelease  Unable to connect" >&2
        echo "E: Failed to fetch http://bob:p@ss/w0rd@proxy2.invalid:3128/x  Unable to connect" >&2
        echo "W: carol:hunter2@proxy3.invalid failed" >&2
        echo "Proxy-Authorization: Basic dXNlcjpwdw==" >&2
        echo "Get:1 http://archive.ubuntu.com/ubuntu noble InRelease" >&2
        exit 100 ;;
  fail-long) i=0; while [ "$i" -lt 30 ]; do i=$((i + 1)); printf 'Get:%s http://archive.ubuntu.com/ubuntu noble/main amd64 Packages [%s] %0120d\n' "$i" "$i" 0 >&2; done; exit 100 ;;
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
  OUT="$W/out"; ERR="$W/err"; CALLS="$W/calls"; NET="$W/net"; : > "$CALLS"; : > "$NET"; : > "$OUT"; : > "$ERR"
  rm -f "$W/child"
  if [ "${KEEP_STATE:-0}" != 1 ]; then
    chmod -R u+rwX "$W/state" 2>/dev/null; rm -rf "$W/state"; rm -f "$W/stalled"
    if [ "$budget" != unset ]; then mkdir -p "$W/state"; printf '%s\n' "$budget" > "$W/state/budget"; printf '%s\n' "${PRE_SPENT:-}" | sed '/^$/d' > "$W/state/spent"; fi
  fi
  local t0; t0=$(date +%s)
  RC=0
  # shellcheck disable=SC2016  # single-quoted on purpose: expands inside the fresh bash
  env PATH="$STUB:$PATH" GD_STUB_MODE="$mode" GD_STUB_CALLS="$CALLS" GD_STUB_NET="$NET" GD_STUB_STALLED="$W/stalled" GD_STUB_CHILD="$W/child" \
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
if printf '%s\n' "$_ao" | grep -cx >/dev/null 'rc2=0 budget=7 spent=3' && printf '%s\n' "$_ao" | grep -cx >/dev/null 'GD_APT: spent=3s of budget=7s across 1 apt attempt(s)' \
   && cmp -s "$LIB" "$_ad/apt-bounded.sh" && [ "$_oct" = 8 ] && [ "$_badrc" -eq 2 ] && [ "$_ia" -eq 0 ]; then
  pass "A19: arm is idempotent on disk and keeps spent, copies the lib, normalises 08, rejects abc; the summary reports; the armed dir drives the helper"
else fail "A19: host arm/summary" "arm-out=[$(printf '%s' "$_ao" | tr '\n' '|')] oct=[$_oct] bad-rc=$_badrc helper-rc=$_ia"; fi

# ── Guard 4: the shared apt cache (#10781) ───────────────────────────────────────────────
# A cache-simulating stub (modes cache*, above) records a network cost only when the lists are empty or the package is
# not in the archives dir, so a warm run that still costs a fetch turns a row red. The state dir is armed by the REAL
# host half (gd_apt_state_arm), not hand-built, so a missing partial/ dir is fatal here exactly as in real apt.
arm_state() { local d="${2:-$W/state}"; chmod -R u+rwX "$d" 2>/dev/null; rm -rf "$d" "$W/stalled"; ( . "$LIB"; gd_apt_state_arm "$d" "$1" ) >/dev/null 2>&1; }
n_net() { grep -c "^$1" "$NET" || true; }

# G4-1 — cold then warm on the SAME state dir: the second container makes ZERO downloads (one REVALIDATE only).
row
arm_state 60
KEEP_STATE=1 run_helper cache 60 curl python3
_c_rc=$RC; _c_calls=$(calls); _c_fetch=$(n_net FETCH); _c_net="$(tr '\n' '|' < "$NET")"
KEEP_STATE=1 run_helper cache 60 curl python3
_w_rc=$RC; _w_calls=$(calls); _w_fetch=$(n_net FETCH); _w_reval=$(n_net REVALIDATE)
if [ "$_c_rc" -eq 0 ] && [ "$_c_calls" -eq 2 ] && [ "$_c_fetch" -eq 3 ] \
   && [ "$_w_rc" -eq 0 ] && [ "$_w_calls" -eq 2 ] && [ "$_w_fetch" -eq 0 ] && [ "$_w_reval" -eq 1 ]; then
  pass "G4-1: cold container downloads the index and both packages (3 fetches); the warm second container makes 0 downloads (1 revalidation)"
else fail "G4-1: shared cache cold/warm" "cold rc=$_c_rc calls=$_c_calls fetches=$_c_fetch net=[$_c_net] stderr=[$(head -c 200 "$ERR")]; warm rc=$_w_rc calls=$_w_calls fetches=$_w_fetch revalidations=$_w_reval net=[$(tr '\n' '|' < "$NET")]"; fi

# G4-2 — BOTH apt calls carry the same -o Dir::State::lists / Dir::Cache::archives, derived from the state dir
# (an alternate dir proves no second literal), placed before Acquire::Retries. The WHOLE argv of each call is pinned,
# not a substring: an extra `-o` (AllowInsecureRepositories, Check-Valid-Until, Dir::State::status) or flag is a finding.
row
_alt="$W/alt"; arm_state 60 "$_alt"
GD_APT_STATE_DIR="$_alt" KEEP_STATE=1 run_helper cache 60 curl python3
_u="$(grep '^update ' "$CALLS" || true)"; _i="$(grep '^install ' "$CALLS" || true)"
_exp_o="-o Dir::State::lists=${_alt}/lists -o Dir::Cache::archives=${_alt}/archives -o Acquire::Retries=5"
if [ "$RC" -eq 0 ] && [ "$_u" = "update -qq ${_exp_o}" ] && [ "$_i" = "install -y -qq ${_exp_o} curl python3" ] && [ "$(calls)" -eq 2 ]; then
  pass "G4-2: update AND install pass EXACTLY -qq/-y, -o Dir::State::lists=<state>/lists -o Dir::Cache::archives=<state>/archives (derived from GD_APT_STATE_DIR) -o Acquire::Retries=5, nothing else; the A1 shape still holds"
else fail "G4-2: shared -o options on both calls" "rc=$RC update=[$_u] install=[$_i] stderr=[$(head -c 200 "$ERR")]"; fi
rm -rf "$_alt"

# G4-3 — the arm creates lists/partial and archives/partial, and a NON-CANONICAL state (a pre-existing populated lists/
# and a different budget) still works: the index is not re-downloaded, the packages are.
row
rm -rf "$W/state" "$W/stalled"; mkdir -p "$W/state/lists"; : > "$W/state/lists/InRelease"
( . "$LIB"; gd_apt_state_arm "$W/state" 45 ) >/dev/null 2>&1; _arm_rc=$?
_parts=no; [ -d "$W/state/lists/partial" ] && [ -d "$W/state/archives/partial" ] && _parts=yes
KEEP_STATE=1 run_helper cache 45 curl
if [ "$_arm_rc" -eq 0 ] && [ "$_parts" = yes ] && [ "$(cat "$W/state/budget")" = 45 ] && [ "$RC" -eq 0 ] \
   && [ "$(n_net FETCH-INDEX)" -eq 0 ] && [ "$(n_net FETCH-PKG)" -eq 1 ]; then
  pass "G4-3: arm creates lists/partial and archives/partial; a pre-existing lists/ with another budget (45) still arms and cycles (index reused, package fetched)"
else fail "G4-3: arm partial dirs / pre-existing lists" "arm-rc=$_arm_rc partial-dirs=$_parts budget=$(cat "$W/state/budget" 2>/dev/null) rc=$RC net=[$(tr '\n' '|' < "$NET")] stderr=[$(head -c 200 "$ERR")]"; fi

# G4-4 — a download stalled mid-package is cut at the attempt cap and the retry RESUMES from archives/partial
# instead of starting over, inside the budget; the shared dirs are what make the retry cheap.
row
arm_state 60
GD_APT_ATTEMPT_CAP=2 KEEP_STATE=1 run_helper cache-stall-once 60 curl
reap_child
if [ "$RC" -eq 0 ] && [ "$ELAPSED" -le 10 ] && [ "$(calls)" -eq 4 ] && [ "$(n_net FETCH-PKG)" -eq 1 ] && [ "$(n_net RESUME-PKG)" -eq 1 ] && [ "$(spent_total)" -le 10 ]; then
  pass "G4-4: a stalled download is cut at the cap and the retry resumes from archives/partial (rc 0 after ${ELAPSED}s, 4 apt calls, 1 fetch + 1 resume, charged $(spent_total)s)"
else fail "G4-4: capped then resumed" "rc=$RC elapsed=${ELAPSED}s calls=$(calls) net=[$(tr '\n' '|' < "$NET")] spent=$(spent_total)"; fi

# G4-5 — the host can REMOVE the state dir after a run on EVERY exit path. The stub leaves what a root apt leaves
# (download-user dirs mode 0500 or 0700, files 0600); the helper's container-side chmod must open them, on success, on
# exhausted apt errors, with the budget already spent (no apt run at all) and on a timeout. "Open" means files rw for
# others AND directories rwx for others (a directory without x cannot be entered, so the host rm -rf would fail on a
# different uid), except the sourced script, which is deliberately 0644 (below); and the script the NEXT container sources as root is NOT left group/other-writable (G4-7).
row
_g5=""
_g5_check() { # <label>: nothing left non-rw for others (and no directory without x for others), the sourced script not g/o-writable, and the host removes the tree
  local bad badx lax rmrc=0
  bad="$(find "$W/state" \( -type d -o -type f \) ! -perm -006 ! -path "$W/state/apt-bounded.sh" 2>/dev/null | head -3 | tr '\n' ' ')"
  badx="$(find "$W/state" -type d ! -perm -007 2>/dev/null | head -3 | tr '\n' ' ')"
  lax="$(find "$W/state/apt-bounded.sh" -perm /022 2>/dev/null | head -1)"
  rm -rf "$W/state" 2>/dev/null || rmrc=$?
  if [ -n "$bad" ] || [ -n "$badx" ] || [ -n "$lax" ] || [ "$rmrc" -ne 0 ] || [ -e "$W/state" ]; then _g5="${_g5} $1:[non-open=${bad:-none} dirs-without-o-x=${badx:-none} script-g/o-writable=${lax:-no} rm-rc=$rmrc still-there=$( [ -e "$W/state" ] && echo yes || echo no )]"; fi
  chmod -R u+rwX "$W/state" 2>/dev/null; rm -rf "$W/state"
}
_seed_perms() { # a 0500 download-user dir (the stub's shape) and a 0700 one holding a 0600 file, as a root apt leaves them
  mkdir -p "$W/state/archives/partial" "$W/state/lists/partial"
  : > "$W/state/archives/partial/lock"; chmod 600 "$W/state/archives/partial/lock"; chmod 500 "$W/state/archives/partial"
  : > "$W/state/lists/partial/lock"; chmod 600 "$W/state/lists/partial/lock"; chmod 700 "$W/state/lists/partial"
}
arm_state 60; _seed_perms; KEEP_STATE=1 run_helper cache-perms 60 curl;             [ "$RC" -eq 0 ]   || _g5="${_g5} success:[rc=$RC]";  _g5_check success
arm_state 60; _seed_perms; KEEP_STATE=1 run_helper cache-perms-fail 60 curl;        [ "$RC" -eq 100 ] || _g5="${_g5} apt-error:[rc=$RC]"; _g5_check apt-error
arm_state 60; _seed_perms; printf '99\n' >> "$W/state/spent"; KEEP_STATE=1 run_helper cache-perms 60 curl
[ "$RC" -eq 100 ] && [ "$(calls)" -eq 0 ] || _g5="${_g5} spent:[rc=$RC calls=$(calls)]";                                                                        _g5_check spent
arm_state 3; _seed_perms; GD_APT_ATTEMPT_CAP=1 KEEP_STATE=1 run_helper hang 3 curl; reap_child
[ "$RC" -eq 100 ] || _g5="${_g5} timeout:[rc=$RC]";                                                                                                               _g5_check timeout
if [ -z "$_g5" ]; then
  pass "G4-5: after success, exhausted apt errors, a spent budget and a timeout every file is rw and every directory rwx for others, the sourced script is not g/o-writable, and the host can remove the state dir"
else fail "G4-5: state dir not removable by the host" "$_g5"; fi

# G4-6 — a --no-install-recommends call site (sandbox-masked-proc-docker, cloud-init-inngest-provision-unit) keeps its
# argument order: the flag stays the first package-side argument, after the shared options.
row
arm_state 60
KEEP_STATE=1 run_helper cache 60 --no-install-recommends bubblewrap procps
_i="$(grep '^install ' "$CALLS" || true)"
if [ "$RC" -eq 0 ] && printf '%s\n' "$_i" | grep -qE '^install -y -qq -o Dir::State::lists=[^ ]+ -o Dir::Cache::archives=[^ ]+ -o Acquire::Retries=5 --no-install-recommends bubblewrap procps$' && [ "$(n_net FETCH-PKG)" -eq 2 ]; then
  pass "G4-6: --no-install-recommends keeps its position (after the shared options and Acquire::Retries, before the packages)"
else fail "G4-6: --no-install-recommends order" "rc=$RC install=[$_i] net=[$(tr '\n' '|' < "$NET")]"; fi

# G4-7 — the script the NEXT container sources AS ROOT (<state>/apt-bounded.sh) must not be group/other-writable: the
# open-everything chmod the host rm -rf needs (directory permissions) must not make the code root executes writable by any
# other uid. Checked right after the HOST arm and again after a run (the container-side wrapper re-opens the tree), and
# the host must still be able to remove the dir with the script's go-w cleared.
row
arm_state 60
_lax_arm="$(find "$W/state/apt-bounded.sh" -perm /022 2>/dev/null | head -1)"
_ro_arm=no; [ -r "$W/state/apt-bounded.sh" ] && _ro_arm=yes
KEEP_STATE=1 run_helper cache-perms 60 curl
_lax_run="$(find "$W/state/apt-bounded.sh" -perm /022 2>/dev/null | head -1)"
_rmrc=0; rm -rf "$W/state" 2>/dev/null || _rmrc=$?
if [ -z "$_lax_arm" ] && [ "$_ro_arm" = yes ] && [ "$RC" -eq 0 ] && [ -z "$_lax_run" ] && [ "$_rmrc" -eq 0 ] && [ ! -e "$W/state" ]; then
  pass "G4-7: the sourced <state>/apt-bounded.sh is readable and not group/other-writable right after the arm and after a run, and the host still removes the dir"
else fail "G4-7: sourced script left writable" "after-arm=[${_lax_arm:-ok}] readable=$_ro_arm run-rc=$RC after-run=[${_lax_run:-ok}] rm-rc=$_rmrc"; fi
chmod -R u+rwX "$W/state" 2>/dev/null; rm -rf "$W/state"

# G4-8 — the sticky bit. G4-7 clears go-w on the script, but the state dir is a+rwX (0777) so that the host user can remove a
# tree root created: without the sticky bit ANY uid with write on the DIRECTORY (the download user `_apt` runs inside the same
# container) can `mv new <state>/apt-bounded.sh` over a file it cannot write, or `rm` it, and the next root container sources the
# replacement. The dir must carry `t` after the HOST arm AND after the container-side wrapper (a hand-built, non-sticky state dir
# stands in for one whose bit was lost), and the host user must still be able to remove the tree.
row
arm_state 60
_st_arm=no; [ -k "$W/state" ] && _st_arm=yes
_st_mode="$(stat -c %a "$W/state")"
rm -rf "$W/state"
run_helper ok 60 curl      # hand-built state dir (budget + spent only): the wrapper alone must set the bit
_st_run=no; [ -k "$W/state" ] && _st_run=yes
_st_rc=$RC
_st_rm=0; chmod -R u+rwX "$W/state" 2>/dev/null; rm -rf "$W/state" 2>/dev/null || _st_rm=$?
if [ "$_st_arm" = yes ] && [ "$_st_mode" = 1777 ] && [ "$_st_run" = yes ] && [ "$_st_rc" -eq 0 ] && [ "$_st_rm" -eq 0 ] && [ ! -e "$W/state" ]; then
  pass "G4-8: the state dir is sticky (1777) after the host arm and after the container-side wrapper, and the host user still removes the tree"
else fail "G4-8: state dir not sticky" "after-arm=$_st_arm mode=$_st_mode after-run=$_st_run run-rc=$_st_rc rm-rc=$_st_rm"; fi
chmod -R u+rwX "$W/state" 2>/dev/null; rm -rf "$W/state"

# G4-9 — the REAL attempt: as a uid that owns neither the dir nor the script, inside a container, create a file in the state dir
# (must still work: apt writes its own files there), then try to rename it over <state>/apt-bounded.sh and to remove the script
# (both must be refused and the script must be byte-identical afterwards), then the host removes the tree. Docker-gated: with no
# daemon or no local bash:3.2 the row says so out loud (a SKIP (loud) line) and G4-8 carries the host-side proof.
row
if docker info >/dev/null 2>&1 && docker image inspect bash:3.2 >/dev/null 2>&1; then
  arm_state 60
  _other_uid=1234; [ "$(id -u)" = "$_other_uid" ] && _other_uid=1235
  # shellcheck disable=SC2016  # the script expands inside the container
  _g9="$(docker run --rm --user "$_other_uid" -v "$W/state:/w" bash:3.2 bash -c '
    : > /w/replacement && echo CREATED
    mv -f /w/replacement /w/apt-bounded.sh 2>/dev/null && echo RENAMED_OVER
    rm -f /w/apt-bounded.sh 2>/dev/null
    [ -e /w/apt-bounded.sh ] || echo REMOVED
    echo END' 2>&1)"
  _g9_same=no; cmp -s "$LIB" "$W/state/apt-bounded.sh" && _g9_same=yes
  _g9_rm=0; chmod -R u+rwX "$W/state" 2>/dev/null; rm -rf "$W/state" 2>/dev/null || _g9_rm=$?
  if printf '%s\n' "$_g9" | grep -qx CREATED && printf '%s\n' "$_g9" | grep -qx END && ! printf '%s\n' "$_g9" | grep -qxE 'RENAMED_OVER|REMOVED' \
     && [ "$_g9_same" = yes ] && [ "$_g9_rm" -eq 0 ] && [ ! -e "$W/state" ]; then
    pass "G4-9: as uid ${_other_uid} in a container the state dir accepts new files but refuses a rename over, and a removal of, the sourced script (still byte-identical); the host removes the tree"
  else fail "G4-9: another uid could replace or remove the sourced script" "container-out=[$(printf '%s' "$_g9" | tr '\n' '|' | head -c 300)] script-identical=$_g9_same host-rm-rc=$_g9_rm"; fi
  chmod -R u+rwX "$W/state" 2>/dev/null; rm -rf "$W/state"
else
  echo "SKIP (loud): G4-9 needs a reachable docker daemon and a local bash:3.2 image; the host-side sticky bit is asserted by G4-8" >&2
  pass "G4-9: SKIPPED (no docker daemon or no local bash:3.2) — loud skip printed; G4-8 asserts the sticky bit on the host"
fi

# ── gd_apt_out_tail: the host-side excerpt of a captured container log ──────────────────────
# The suites' failure/skip excerpts must start with the FIXTURE_APT_CAUSE line (the runner keeps only grep -A3 around the
# first FAIL marker, 40 lines, 2000 chars per line, and the one-line consumers join the tail with `tr`), then the SCRUBBED
# block and nothing else: the lines around it in a captured log are unscrubbed container stdout.
_ct="$W/cap"
_mkcap() { # <err-file> <pre-lines>: noise + the helper's real stderr + noise, like `docker run ... > file 2>&1`
  { local i=0; while [ "$i" -lt "$2" ]; do i=$((i + 1)); printf 'PRE-NOISE-%s unscrubbed container stdout\n' "$i"; done; cat "$1"; printf 'POST-NOISE-1 FIXTURE-FAIL: after the helper\nPOST-NOISE-2\n'; } > "$_ct"
}

# H1 — a full 20-line scrubbed block: the cause FIRST, then exactly GD_APT_TAIL_LINES scrubbed lines (the last ones), and no
# noise from either side; the output is bounded by 1 + GD_APT_TAIL_LINES.
row
run_helper fail-long 60 curl; _h1_rc=$RC
_mkcap "$ERR" 6
_h1="$( ( . "$LIB"; gd_apt_out_tail "$_ct" 5 ) 2>&1 )"
_h1_n=$(printf '%s\n' "$_h1" | wc -l | tr -d ' ')
_h1_want=$(( $( . "$LIB"; printf '%s' "$GD_APT_TAIL_LINES" ) + 1 ))
if [ "$_h1_rc" -eq 100 ] && [ "$_h1_want" -eq 21 ] && printf '%s\n' "$_h1" | head -n 1 | grep -qE '^FIXTURE_APT_CAUSE: apt-error ' \
   && [ "$_h1_n" -eq "$_h1_want" ] && printf '%s\n' "$_h1" | grep -qE '^Get:30 ' && printf '%s\n' "$_h1" | grep -qE '^Get:11 ' \
   && ! printf '%s\n' "$_h1" | grep -qE '^Get:10 ' && ! printf '%s\n' "$_h1" | grep -qE 'NOISE|FIXTURE_APT_FAILED'; then
  pass "gd_apt_out_tail H1: cause line first, then exactly the last $(( _h1_want - 1 )) scrubbed lines, bounded at ${_h1_want} lines in all, none of the unscrubbed lines around them"
else fail "gd_apt_out_tail H1: full block" "apt rc=$_h1_rc lines=$_h1_n want=$_h1_want head=[$(printf '%s\n' "$_h1" | head -n 2 | cut -c1-120 | tr '\n' '|')] tail=[$(printf '%s\n' "$_h1" | tail -n 2 | cut -c1-100 | tr '\n' '|')]"; fi

# H2 — a SHORT scrubbed block (fewer lines than the cap, here the 5-line `fail` stub accumulated over 3 attempts): the
# helper takes the exact count the cause line carries, so it never reaches back into the unscrubbed lines above the block.
row
run_helper fail 60 curl; _h2_rc=$RC
_h2_blk=$(( $(wc -l < "$ERR") - 2 ))   # stderr = scrubbed block + cause + marker
_mkcap "$ERR" 30
_h2="$( ( . "$LIB"; gd_apt_out_tail "$_ct" 5 ) 2>&1 )"
_h2_n=$(printf '%s\n' "$_h2" | wc -l | tr -d ' ')
if [ "$_h2_rc" -eq 100 ] && [ "$_h2_blk" -ge 3 ] && [ "$_h2_blk" -lt 20 ] && [ "$_h2_n" -eq $(( _h2_blk + 1 )) ] \
   && printf '%s\n' "$_h2" | head -n 1 | grep -qE '^FIXTURE_APT_CAUSE: apt-error ' && ! printf '%s\n' "$_h2" | grep -qE 'NOISE' \
   && printf '%s\n' "$_h2" | grep -qF 'archive.ubuntu.com/ubuntu noble InRelease' && ! printf '%s\n' "$_h2" | grep -qF 's3cr3t'; then
  pass "gd_apt_out_tail H2: a ${_h2_blk}-line scrubbed block yields the cause plus exactly those ${_h2_blk} lines (no reach into the 30 unscrubbed lines above), credentials still scrubbed"
else fail "gd_apt_out_tail H2: short block" "apt rc=$_h2_rc block=$_h2_blk lines=$_h2_n head=[$(printf '%s\n' "$_h2" | head -n 2 | cut -c1-120 | tr '\n' '|')]"; fi

# H3 — no cause line (an httpd/alpine arm, or a container that died before apt): the plain short tail the caller asked for.
row
printf 'l1\nl2\nl3\nl4\nl5\nl6\n' > "$_ct"
_h3="$( ( . "$LIB"; gd_apt_out_tail "$_ct" 3 ) 2>&1 )"
_h3m="$( ( . "$LIB"; gd_apt_out_tail "$W/does-not-exist" 3 ) 2>&1 )"
if [ "$_h3" = "$(printf 'l4\nl5\nl6')" ] && [ -z "$_h3m" ]; then
  pass "gd_apt_out_tail H3: with no cause line it is the caller's plain tail -n; a missing capture prints nothing"
else fail "gd_apt_out_tail H3: no-cause fallback" "got=[$(printf '%s' "$_h3" | tr '\n' '|')] missing=[$_h3m]"; fi

# H4 — THE RUNNER'S EXCERPT PATH, executed with the real MARKER_ERE and caps read from run-registered-suites.sh: grep -E -A3
# around the FAIL marker, the first DUMP_CAP lines, cut -c1-2000 per line. The three shapes the suites print (a `echo FAIL:` with
# a multi-line detail, the same with a leading note, and the one-line `tr` form of the ownership/htpasswd/cutover suites) must
# all keep the cause, on 20 LONG lines where the one-line form is far over 2000 characters.
row
RUNNER="${DIR}/run-registered-suites.sh"
_mre="$(sed -n "s/^MARKER_ERE='\(.*\)'\$/\1/p" "$RUNNER" | head -n 1)"; _cap="$(sed -n 's/^DUMP_CAP=\([0-9][0-9]*\)$/\1/p' "$RUNNER" | head -n 1)"
run_helper fail-long 60 curl; _mkcap "$ERR" 6
_excerpt() { grep -E -A3 --no-group-separator "$_mre" | head -n "$_cap" | cut -c1-2000; }
_oneline_len=$( ( . "$LIB"; gd_apt_out_tail "$_ct" 5 | tr '\n' ' ' ) | wc -c | tr -d ' ')
_x_multi="$( { echo "FAIL: T5 MUTATION: shape one"; echo "      $( . "$LIB"; gd_apt_out_tail "$_ct" 5)"; } | _excerpt )"
_x_note="$( { echo "FAIL: T5 MUTATION: shape two"; echo "      docker rc=1 (measured classes); tail: $( . "$LIB"; gd_apt_out_tail "$_ct" 5)"; } | _excerpt )"
_x_one="$( { printf '  FAIL %s\n       %s\n' "runtime arm: the driver did not complete" "$( . "$LIB"; gd_apt_out_tail "$_ct" 5 | tr '\n' ' ')"; } | _excerpt )"
_hx=ok; for _v in "$_x_multi" "$_x_note" "$_x_one"; do printf '%s\n' "$_v" | grep -qF 'FIXTURE_APT_CAUSE: apt-error ' || _hx=lost; done
if [ -n "$_mre" ] && [ -n "$_cap" ] && [ "$_oneline_len" -gt 2000 ] && [ "$_hx" = ok ]; then
  pass "gd_apt_out_tail H4: through the runner's real excerpt (MARKER_ERE, grep -A3, ${_cap} lines, cut 2000) the cause survives in all three suite shapes, including a ${_oneline_len}-char one-line form"
else fail "gd_apt_out_tail H4: runner excerpt" "marker-ere=[${_mre:-<not found in run-registered-suites.sh>}] cap=[${_cap:-?}] oneline-chars=$_oneline_len verdict=$_hx multi=[$(printf '%s' "$_x_multi" | head -c 160)] one=[$(printf '%s' "$_x_one" | head -c 160)]"; fi

# H5 — workflow-command defence is IN the helper, so every consumer gets it: a `::error::` (or `##[error]`) opener in the captured
# container output, in the scrubbed block, the cause line or the no-cause fallback, is defused, and the text around it survives.
row
_cause_ok='FIXTURE_APT_CAUSE: apt-error stage=update attempt=3 attempt_secs=1 spent_before=0s budget=60s rc=100 tail_lines=2'
printf 'PRE\n::error::injected-leading\nE: Failed ::warning::mid-line ##[error]hash-form\n%s\n' "$_cause_ok" > "$_ct"
_h5a="$( ( . "$LIB"; gd_apt_out_tail "$_ct" 5 ) 2>&1 )"
printf '::notice::fallback-leading\nplain ##[group]x\n' > "$_ct"
_h5b="$( ( . "$LIB"; gd_apt_out_tail "$_ct" 5 ) 2>&1 )"
printf 'FIXTURE_APT_CAUSE: ::stop-commands::tok tail_lines=0\n' > "$_ct"
_h5c="$( ( . "$LIB"; gd_apt_out_tail "$_ct" 5 ) 2>&1 )"
_h5bad=""; for _v in "$_h5a" "$_h5b" "$_h5c"; do printf '%s\n' "$_v" | grep -qE '::|##\[' && _h5bad="${_h5bad} [$(printf '%s' "$_v" | tr '\n' '|' | head -c 120)]"; done
if [ -z "$_h5bad" ] && printf '%s\n' "$_h5a" | grep -qF 'injected-leading' && printf '%s\n' "$_h5a" | grep -qF 'mid-line' && printf '%s\n' "$_h5a" | grep -qF 'hash-form' \
   && printf '%s\n' "$_h5b" | grep -qF 'fallback-leading' && printf '%s\n' "$_h5c" | grep -qF 'stop-commands'; then
  pass "gd_apt_out_tail H5: no '::' or '##[' survives in the scrubbed block, the cause line or the no-cause fallback, and the surrounding text is kept"
else fail "gd_apt_out_tail H5: workflow-command openers not defused" "still-live=${_h5bad:-none} a=[$(printf '%s' "$_h5a" | tr '\n' '|' | head -c 200)] b=[$(printf '%s' "$_h5b" | tr '\n' '|' | head -c 100)]"; fi

# H6 — the lines above a cause line are trusted ONLY with a valid tail_lines= (the scrubbed block's own count). No count, an empty or
# non-numeric one: the cause line ALONE (the lines above could be unscrubbed stdout). A forged oversized count is clamped at
# GD_APT_TAIL_LINES, never at the forged number. An honest small count is still honoured exactly.
row
_h6_n() { # <cause-line>: the number of lines gd_apt_out_tail prints with 30 unscrubbed lines above that cause line
  { local i=0; while [ "$i" -lt 30 ]; do i=$((i + 1)); printf 'UNSCRUBBED-%s secret-ish container stdout\n' "$i"; done; printf '%s\n' "$1"; } > "$_ct"
  ( . "$LIB"; gd_apt_out_tail "$_ct" 5 ) 2>&1 | wc -l | tr -d ' '
}
_h6_bare="$(_h6_n 'FIXTURE_APT_CAUSE: x')"
_h6_none="$(_h6_n 'FIXTURE_APT_CAUSE: timeout stage=update attempt=1 rc=124')"
_h6_abc="$(_h6_n 'FIXTURE_APT_CAUSE: timeout stage=update attempt=1 tail_lines=abc')"
_h6_empty="$(_h6_n 'FIXTURE_APT_CAUSE: timeout stage=update attempt=1 tail_lines=')"
_h6_forged="$(_h6_n 'FIXTURE_APT_CAUSE: timeout stage=update attempt=1 tail_lines=999')"
_h6_huge="$(_h6_n 'FIXTURE_APT_CAUSE: timeout stage=update attempt=1 tail_lines=99999999999999999999999')"
_h6_wrap="$(_h6_n 'FIXTURE_APT_CAUSE: timeout stage=update attempt=1 tail_lines=18446744073709551617')"
_h6_three="$(_h6_n 'FIXTURE_APT_CAUSE: timeout stage=update attempt=1 tail_lines=3')"
_h6_cap=$(( $( . "$LIB"; printf '%s' "$GD_APT_TAIL_LINES" ) + 1 ))
_h6_leak="$( { printf 'UNSCRUBBED-1 secret\n'; printf 'FIXTURE_APT_CAUSE: x\n'; } > "$_ct"; ( . "$LIB"; gd_apt_out_tail "$_ct" 5 ) 2>&1 | grep -c UNSCRUBBED || true )"
if [ "$_h6_bare" -eq 1 ] && [ "$_h6_none" -eq 1 ] && [ "$_h6_abc" -eq 1 ] && [ "$_h6_empty" -eq 1 ] && [ "$_h6_forged" -eq "$_h6_cap" ] && [ "$_h6_huge" -eq "$_h6_cap" ] && [ "$_h6_wrap" -eq "$_h6_cap" ] \
   && [ "$_h6_three" -eq 4 ] && [ "$_h6_leak" -eq 0 ]; then
  pass "gd_apt_out_tail H6: a cause line with no valid tail_lines= prints itself alone (bare, absent, abc, empty), a forged 999, 23-digit or 2^64+1 (wraps to 1 in shell arithmetic) count is clamped to ${_h6_cap} lines, an honest 3 gives 4"
else fail "gd_apt_out_tail H6: tail_lines trust" "bare=$_h6_bare absent=$_h6_none abc=$_h6_abc empty=$_h6_empty forged999=$_h6_forged (want $_h6_cap) huge=$_h6_huge (want $_h6_cap) wrap2^64+1=$_h6_wrap (want $_h6_cap) three=$_h6_three (want 4) unscrubbed-leak=$_h6_leak"; fi

# H7 — a skip message must carry its apt cause inside the first 400 bytes, because run-registered-suites.sh relays every
# `SKIP (loud): ` line through `cut -b1-400` (relay_grep). gd_apt_skip_field gives the short `apt=<cause> stage=<s> attempt=<n>`
# token, and every `arm_skip "T5|S1|T17 ..."` call site of the rehearsal suite (the three prefixes the follow-through probe
# matches) and every other arm_skip that embeds the S1 note must open with it, with only a short literal before it.
row
run_helper fail 60 curl; _mkcap "$ERR" 4
_h7_f="$( . "$LIB"; gd_apt_skip_field "$_ct" )"
printf 'no cause here\n' > "$_ct";                                          _h7_none="$( . "$LIB"; gd_apt_skip_field "$_ct" )"
printf 'FIXTURE_APT_CAUSE: ::error::evil stage=x attempt=1\n' > "$_ct";    _h7_evil="$( . "$LIB"; gd_apt_skip_field "$_ct" )"
printf 'FIXTURE_APT_CAUSE: x\n' > "$_ct";                                   _h7_bare="$( . "$LIB"; gd_apt_skip_field "$_ct" )"
_h7_src="$(sed 's/^[[:space:]]*#.*$//' "$REH")"
_h7_sites="$(printf '%s\n' "$_h7_src" | grep -E '^[[:space:]]*(did-not-run\) )?arm_skip "(T5|S1|T17|S2)[ (]' || true)"
_h7_n=$(printf '%s\n' "$_h7_sites" | grep -c . || true)
_h7_bad=""
while IFS= read -r _l; do
  [ -n "$_l" ] || continue
  _lit="${_l#*arm_skip \"}"; _lit="${_lit%%\$\{*}"       # the literal text before the first expansion
  # shellcheck disable=SC2016  # literal source text
  printf '%s\n' "$_l" | grep -qE 'arm_skip "(T5|S1|T17|S2)[^$]*\$\{(S1_APT|S1_NOTE|_t5m_apt|_t17m_apt)\}' && [ "${#_lit}" -le 200 ] || _h7_bad="${_h7_bad} [${_l:0:70}… literal-before-field=${#_lit}]"
done <<< "$_h7_sites"
# shellcheck disable=SC2016  # literal source text
_h7_note=$(printf '%s\n' "$_h7_src" | grep -c 'S1_NOTE="\${S1_APT}; ' || true)
# 400 bytes minus the 'SKIP (loud): ' the line is printed with, minus the 200-byte literal cap, leaves room for the field (<= 80 bytes).
if [ "$_h7_f" = "apt=apt-error stage=update attempt=3" ] && [ "$_h7_none" = "apt=none" ] && [ "$_h7_evil" = "apt=none" ] && [ "$_h7_bare" = "apt=none" ] \
   && [ "$_h7_n" -ge 9 ] && [ -z "$_h7_bad" ] && [ "$_h7_note" -eq 1 ] && [ $(( 13 + 200 + 80 )) -le 400 ]; then
  pass "gd_apt_out_tail H7: gd_apt_skip_field yields '${_h7_f}' (apt=none for no/forged/bare cause); all ${_h7_n} rehearsal T5/S1/T17/S2 arm_skip sites open with it within 200 literal bytes, so it survives the runner's cut -b1-400"
else fail "gd_apt_out_tail H7: skip cause not first" "field=[$_h7_f] none=[$_h7_none] evil=[$_h7_evil] bare=[$_h7_bare] sites=$_h7_n (want >=9) note-assignments=$_h7_note (want 1) offenders:${_h7_bad:- none}"; fi

# ── Derived assembly row ─────────────────────────────────────────────────────────────────
# For each consumer suite (comment-stripped, continuation-joined): every `docker run` site is either mounted
# with the EXACT state mount token or is one of the declared unmounted sites (the rehearsal's R1 container and
# the provision-unit suite's systemd boot container run no apt); each arm line (the suite's OWN state variable) is
# followed, as the next statement, by a MOUNTED docker run; every helper call carries a pass-through rc form
# (`|| exit $?`, S1's re-raise, R4's fixture_fail) and none a hardcoded `|| exit 100` / `|| true`; every call is
# preceded by the `. /work/apt/apt-bounded.sh || exit 97` (or fixture_fail) source line; every arm line checks its
# own return; and no apt/dpkg/pip appears in command position outside the helper.
#
# The grammar arms (separators, keywords, wrapper words, apt binaries and verbs, docker verbs) live in ARRAYS: the
# regexes are BUILT from them and the sample loops below are generated from the same arrays, so an arm cannot exist
# unsampled. A population census over every `*.test.sh` under the infra directory (recursive, as
# run-registered-suites.sh registers them) keeps the consumer list from being a hand-listed snapshot (#9395): any
# suite with a docker verb AND apt text anywhere in its code must be a declared consumer or carry an explicit
# EXEMPT line with a reason (and a stale exemption is itself a finding). The census is deliberately looser than the
# site grammars: a false candidate costs one SPECS or EXEMPT line, a miss is silent.
# BOUNDARY: non-suite scripts and scripts outside this directory (for example apps/web-platform/scripts/*-in-image.sh)
# are not covered by this row. Known spellings it does NOT see: apt-get download|source, add-apt-repository, apt-key,
# ${APT:-apt-get}, nerdctl, python subprocess, apt/pip text in a sibling helper file, a container-side pip install in a
# suite outside SPECS, and an unpinned APT_BUDGET_S value; the A10 legend states the budget rule.
_strip() { sed 's/^[[:space:]]*#.*$//' "$1"; }
_joined() { _strip "$1" | sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba' -e '}'; }
_join() { local IFS='|'; printf '%s' "$*"; }
_SEPS=(';' '&' '|' '(' ')' '{' '!' '`')
_KWS=('then' 'do' 'if' 'elif' 'else' 'while' 'until' 'exec' 'RUN')
_WRAPS=(sudo env command nohup time nice stdbuf xargs flock X XS)
_APT_BINS=(apt-get apt aptitude apt-fast dpkg)
_PIP_BINS=(pip pip3)
_APT_VERBS=(update install upgrade dist-upgrade full-upgrade build-dep reinstall -i --install)
_DOCK_VERBS=(run exec create build start compose)
_SEPCLASS="[$(printf '%s' "${_SEPS[@]}")]"
_CMDPOS="(^|${_SEPCLASS}|-c[[:space:]]+['\"]|(^|[[:space:]])($(_join "${_KWS[@]}")))[[:space:]]*"
_END="([[:space:];&|)<>}\`'\"]|\$)"
# Wrapper words and `docker run|exec ... ` may precede the tool; timeout may carry any flags/duration; both are
# generous on purpose (no `{n,m}` interval: ADJ_RE is evaluated by awk and old mawk builds lack intervals).
_WRAP="(($(_join "${_WRAPS[@]}")|docker[[:space:]]+(run|exec))[[:space:]]+['\"]?([^;&|]*[[:space:]])?)?"
_VARPFX='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
_TMO='(timeout[[:space:]]+([^;&|]*[[:space:]])?)?'
_BIN='(/[^[:space:]]*/)?'
DOCK_RE="${_CMDPOS}${_WRAP}${_VARPFX}${_TMO}${_BIN}docker[[:space:]]+(container[[:space:]]+)?run${_END}"
ADJ_RE="^[[:space:]]*((if|elif|while|until|exec)[[:space:]]+)?(![[:space:]]+)?${_WRAP}${_VARPFX}${_TMO}${_BIN}docker[[:space:]]+(container[[:space:]]+)?run${_END}"
RAW_RE="${_CMDPOS}${_WRAP}${_VARPFX}${_TMO}${_BIN}($(_join "${_APT_BINS[@]}" "${_PIP_BINS[@]}")|python3?[[:space:]]+-m[[:space:]]+pip)[[:space:]]+([^;&|]*[[:space:]])?($(_join "${_APT_VERBS[@]}"))${_END}"
_DVAR='\$\{?[A-Za-z_]*(DOCKER|docker)[A-Za-z_]*\}?"?'
CENS_DOCK_RE="(^|[^A-Za-z0-9_-])(docker|podman)[^;&|]*[[:space:]]($(_join "${_DOCK_VERBS[@]}"))${_END}|(docker|podman)-compose|${_DVAR}[[:space:]]+(run|exec|create|build)${_END}"
CENS_APT_RE="(^|[^A-Za-z0-9_-])($(_join "${_APT_BINS[@]}"))[[:space:]]+([^;&|]*[[:space:]])?($(_join "${_APT_VERBS[@]}"))${_END}|gd_apt_install_bounded|gd_apt_state_arm"
# shellcheck disable=SC2016  # the literal mount token as it appears in the suites' text
MNT_LIT='-v "$GD_APT_STATE:/work/apt"'
# One TAB-separated spec per consumer: file, declared-unmounted sites, state variable the suite arms, mounted sites.
# A new consumer is one line here PLUS its conversion; the totals below are derived from this list.
TAB=$'\t'
SPECS=("${OWN}${TAB}0${TAB}TMP${TAB}1" "${REH}${TAB}1${TAB}TMP${TAB}5" "${CUT}${TAB}0${TAB}T${TAB}1" "${PUS}${TAB}1${TAB}W${TAB}1" "${SMP}${TAB}2${TAB}WORK${TAB}1" "${HTP}${TAB}4${TAB}TMP${TAB}1")
# Suites that quote another script's docker/apt text as DATA (assertion strings), not as commands. Format: file TAB reason.
EXEMPT=("cloud-init-inngest-bootstrap.test.sh${TAB}asserts on the rendered cloud-init text; its docker/apt strings are grep targets"
        "cron-egress-firewall.test.sh${TAB}asserts on the egress firewall script text; its docker exec/apt lines are grep targets")
_asm=""; _tot=0; _unm=0; _exp_tot=0; _exp_unm=0; _SAMP_CALLS=0
# _samp <regex> <match|nomatch> <label> <items...>: a sample list shorter than 3 is itself a finding (an emptied list
# would otherwise iterate zero times and stay green), and the number of calls is pinned below.
_samp() {
  local re="$1" want="$2" label="$3" it; shift 3
  _SAMP_CALLS=$((_SAMP_CALLS + 1))
  [ "$#" -ge 3 ] || { _asm="${_asm} ${label}:[fewer than 3 samples]"; return; }
  for it in "$@"; do
    if grep -Eq -- "$re" <<<"$it"; then
      [ "$want" = match ] || _asm="${_asm} ${label}-matches-non-site:[${it}]"
    else
      [ "$want" = nomatch ] || _asm="${_asm} ${label}-misses:[${it}]"
    fi
  done
}
_dk=(); for c in "${_SEPS[@]}"; do _dk+=("true ${c} docker run img"); done
for k in "${_KWS[@]}"; do _dk+=("${k} docker run img"); done
for w in "${_WRAPS[@]}"; do _dk+=("${w} docker run img" "${w} -u root docker run img"); done
# shellcheck disable=SC2016  # sample lines: literal `$VAR` text, not an expansion
_dk+=("docker run --rm img" "timeout -k 10 480 docker run img" "timeout 480 docker run img" "timeout -s KILL 480 docker run img" "timeout 600s docker run img" \
      'timeout "$T" docker run img' "timeout 1.5m docker run img" "FOO=1 docker run img" "/usr/bin/docker run img" "docker container run img" \
      "bash -c 'docker run img'" "sh -c \"docker run img\"" "if ! docker run --name x img")
_samp "$DOCK_RE" match docker-grammar "${_dk[@]}"
_samp "$DOCK_RE" nomatch docker-grammar 'echo "docker run failed"' 'tb_unbootable "docker run failed (x)"' 'dockerrun img' 'echo docker run' 'docker rm -f x' 'docker exec c true'
_samp "$ADJ_RE" match adj-grammar "timeout -k 10 480 docker run -v x img" "if ! timeout 480 docker run -v x img" "docker run -v x img" "FOO=1 docker run img" "sudo docker run img"
_samp "$ADJ_RE" nomatch adj-grammar 'echo docker run' ': docker run' 'gd_apt_state_arm x docker run'
_rw=()
for b in "${_APT_BINS[@]}" "${_PIP_BINS[@]}"; do for v in "${_APT_VERBS[@]}"; do _rw+=("${b} ${v} x"); done; done
for c in "${_SEPS[@]}"; do _rw+=("true ${c} apt-get update"); done
for k in "${_KWS[@]}"; do _rw+=("${k} apt-get update"); done
for w in "${_WRAPS[@]}"; do _rw+=("${w} apt-get install x" "${w} -u root apt-get install x"); done
_rw+=("apt-get -o Acquire::Retries=5 install -y curl" "apt-get -y --no-install-recommends install curl" "timeout -k 5 30 apt-get install -y curl" "timeout 600s apt-get update" \
      "FOO=1 apt-get update" "/usr/bin/apt-get install curl" "python3 -m pip install x" "python -m pip install x" "bash -c 'apt-get install -y x'" \
      "docker run img apt-get install -y curl" "docker exec -u root c apt-get install curl" "XS 'apt-get install x'" "RUN apt-get install -y x")
_samp "$RAW_RE" match raw-apt-grammar "${_rw[@]}"
_samp "$RAW_RE" nomatch raw-apt-grammar 'echo "apt-get install failed"' 'gd_apt_install_bounded curl' 'apt-bounded' 'apt-get remove install-info' 'x=apt-get' 'ga_row "x apt-get update"'
_cd=()
for v in "${_DOCK_VERBS[@]}"; do _cd+=("docker ${v} x" "podman ${v} x" "docker -H tcp://x ${v} img"); done
# shellcheck disable=SC2016  # sample lines: literal `$VAR` text, not an expansion
_cd+=("docker-compose up" "podman-compose run x" 'docker container run img' '$DOCKER run img' '"$docker_bin" exec c true' "sudo docker run img")
_samp "$CENS_DOCK_RE" match census-docker-grammar "${_cd[@]}"
_samp "$CENS_DOCK_RE" nomatch census-docker-grammar 'docker is absent' 'nodocker run x' 'echo docker' 'docker.io/library/ubuntu'
_ca=()
for b in "${_APT_BINS[@]}"; do for v in "${_APT_VERBS[@]}"; do _ca+=("${b} ${v} x"); done; done
# shellcheck disable=SC2016  # sample lines: literal `$VAR` text, not an expansion
_ca+=("apt-get -o K=V install -y x" "RUN apt-get install -y x" "gd_apt_install_bounded curl" 'gd_apt_state_arm "$W/aptstate" 1' "bash -c 'apt-get update'")
_samp "$CENS_APT_RE" match census-apt-grammar "${_ca[@]}"
_samp "$CENS_APT_RE" nomatch census-apt-grammar 'echo apt is missing' 'apt-bounded' 'dpkg -l' 'pip3 install x'
[ "$_SAMP_CALLS" -eq 10 ] || _asm="${_asm} sample-loops:[ran ${_SAMP_CALLS} of 10 sample calls]"
for spec in "${SPECS[@]}"; do
  IFS="$TAB" read -r f want_unmounted sv want_mounted <<<"$spec"
  [[ "$want_unmounted" =~ ^[0-9]+$ && "$want_mounted" =~ ^[0-9]+$ ]] || { _asm="${_asm} $(basename "$f"):[non-numeric SPECS field]"; continue; }
  _exp_tot=$((_exp_tot + 10#$want_mounted)); _exp_unm=$((_exp_unm + 10#$want_unmounted))
  [ -f "$f" ] || { _asm="${_asm} $(basename "$f"):[missing]"; continue; }
  j="$(_joined "$f")"; u="$(_strip "$f")"
  dock="$(printf '%s\n' "$j" | grep -E -- "$DOCK_RE" || true)"
  # Count SITES, not lines: split the logical lines on ';', '&&' and '||' first so two sites on one line count twice.
  total=$(printf '%s\n' "$dock" | sed -e 's/&&/\n/g' -e 's/||/\n/g' | tr ';' '\n' | grep -cE -- "$DOCK_RE" || true)
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
  # The first statement after an arm must be a docker run that carries the mount (joined text: the whole site); an
  # arm with no following statement at all is also a finding.
  adj=$(printf '%s\n' "$j" | awk -v re="$ADJ_RE" -v mnt="$MNT_LIT" '/^[[:space:]]*gd_apt_state_arm[[:space:]]/ {a=1; next} NF && a {a=0; if ($0 !~ re || index($0, mnt) == 0) bad++} END {if (a) bad++; print bad + 0}')
  raw=$(printf '%s\n' "$u" | grep -cE -- "$RAW_RE" || true)
  _tot=$((_tot + c)); _unm=$((_unm + total - mounted))
  if [ "$mounted" -ne "$want_mounted" ] || [ "$((total - mounted))" -ne "$want_unmounted" ] || [ "$mounted" -ne "$c" ] || [ "$c_ok" -ne "$c" ] \
     || [ "$c_bad" -ne 0 ] || [ "$src" -ne "$c" ] || [ "$g" -ne "$mounted" ] || [ "$g_ok" -ne "$g" ] || [ "$adj" -ne 0 ] || [ "$raw" -ne 0 ]; then
    _sites="$(printf '%s\n' "$dock" | cut -c1-80 | head -4 | tr '\n' '|')"
    _asm="${_asm} $(basename "$f"):[docker-sites=$total (lines: ${_sites}) mounted=$mounted (want $want_mounted) calls=$c rc-ok=$c_ok rc-bad=$c_bad source=$src arms=$g arm-checked=$g_ok arm-not-before-mounted-docker=$adj raw-apt=$raw]"
  fi
done
# Tier B's classification is only as good as its call site: pin the exact call so a flipped or constant condition is a finding.
# shellcheck disable=SC2016  # literal source text
_pin=$(printf '%s\n' "$(_joined "$PUS")" | grep -cE '^[[:space:]]*if \[ "\$\(tb_build_verdict "\$rc" "\$W/tierb-apt\.log"\)" = skip \]; then$' || true)
[ "$_pin" -eq 1 ] || _asm="${_asm} provision-unit:[tb_build_verdict call-site pin=$_pin, want 1]"
# Population census, derived from the tree and independent of the stored list above.
# This suite is the guard itself and carries the grammars as text, so it is the one file not scanned.
_decl="${TAB}"; for spec in "${SPECS[@]}"; do _spec_f="${spec%%"${TAB}"*}"; _decl="${_decl}${_spec_f#"${DIR}"/}${TAB}"; done
_exm="${TAB}"; for e in "${EXEMPT[@]}"; do _exm="${_exm}${e%%"${TAB}"*}${TAB}"; done
_seen=0; _exm_hit=""
while IFS= read -r cf; do
  rel="${cf#"${DIR}"/}"
  case "$_decl" in *"${TAB}${rel}${TAB}"*) _seen=$((_seen + 1)) ;; esac
  [ "$rel" = "apt-bounded.test.sh" ] && continue
  grep -qiE 'docker|podman' "$cf" || continue
  cj="$(_joined "$cf")"
  if grep -Eq -- "$CENS_DOCK_RE" <<<"$cj" && grep -Eq -- "$CENS_APT_RE" <<<"$cj"; then
    case "$_exm" in *"${TAB}${rel}${TAB}"*)
      _exm_hit="${_exm_hit}${rel}${TAB}"
      _ju="$(_joined "$cf")"
      if grep -Eq -- "$DOCK_RE" <<<"$_ju" || grep -Eq -- "$RAW_RE" <<<"$_ju"; then _asm="${_asm} census:[EXEMPT ${rel} now holds a real command-position docker run or raw apt — declare it in SPECS instead]"; fi
      continue ;; esac
    case "$_decl" in *"${TAB}${rel}${TAB}"*) : ;; *) _asm="${_asm} census:[${rel} holds a docker verb and apt text but is not a declared consumer — if it runs apt in a container, convert it to lib/apt-bounded.sh (recipe: the header of that file; gd_apt_state_arm exports GD_APT_STATE for the -v mount) and add a SPECS line (file, declared-unmounted, state var, mounted sites; an already-converted suite only needs the line); if the docker/apt text is only DATA (assertion strings), add an EXEMPT line with the reason]" ;; esac
  fi
done < <(find "$DIR" -type f -name '*.test.sh' | sort)
[ "$_seen" -eq "${#SPECS[@]}" ] || _asm="${_asm} census:[saw ${_seen} of ${#SPECS[@]} declared consumers under ${DIR}]"
for e in "${EXEMPT[@]}"; do
  _ef="${e%%"${TAB}"*}"
  case "${TAB}${_exm_hit}" in *"${TAB}${_ef}${TAB}"*) : ;; *) _asm="${_asm} census:[stale EXEMPT ${_ef}: no longer a docker+apt candidate (or missing) — remove its line]" ;; esac
done
row
if [ -z "$_asm" ] && [ "$_tot" -eq "$_exp_tot" ] && [ "$_unm" -eq "$_exp_unm" ]; then
  pass "A10: assembly (derived) — each apt-bearing docker run is armed just before it, mounts the exact state token, sources the lib and calls the helper with a pass-through rc; no raw apt (${_exp_tot} mounted sites + ${_exp_unm} declared unmounted, ${#SPECS[@]} suites, census clean)"
else fail "A10: assembly drift" "${_asm:-ok} total-helper-calls=$_tot (want $_exp_tot) unmounted=$_unm (want $_exp_unm). Legend: docker=docker run sites, mounted=sites carrying -v \"\$GD_APT_STATE:/work/apt\", calls=gd_apt_install_bounded calls (each needs '|| exit \$?' and a preceding '. /work/apt/apt-bounded.sh || exit 97'), arms=gd_apt_state_arm lines (exactly 'gd_apt_state_arm \"\$<var>/aptstate\" \"\$APT_BUDGET_S\" || { ...; exit 2; }', directly before a MOUNTED docker run), raw-apt must be 0. Keep APT_BUDGET_S plus the container's non-apt time under the site's host timeout and the suite bound."; fi

# A10b — the EXCERPT side of the assembly: A10 proves every apt-bearing docker run goes through the helper; this proves every
# consumer reads that container's capture back through gd_apt_out_tail and not through a raw `tail`, which would show the unscrubbed
# stdout above the cause line and drop the cause when the capture is long. Derived from the same SPECS list (a new consumer is
# covered by its SPECS line): for each suite (comment-stripped) (a) the `gd_apt_out_tail "` call sites number at least its mounted
# docker sites, and (b) the capture each mounted site redirects into (`> "<path>" 2>&1`, first one after the mount token) is never
# the operand of a raw `tail -...`. The capture path is derived from the text, and a mounted site with no derivable capture is itself a
# finding (so the check cannot go vacuous by a changed redirect spelling).
row
_a10b=""
for spec in "${SPECS[@]}"; do
  IFS="$TAB" read -r f _wu sv want_mounted <<<"$spec"
  [ -f "$f" ] || { _a10b="${_a10b} $(basename "$f"):[missing]"; continue; }
  u="$(_strip "$f")"
  ncall=$(printf '%s\n' "$u" | grep -cE 'gd_apt_out_tail "' || true)
  caps="$(printf '%s\n' "$u" | awk -v mnt="$MNT_LIT" '
    index($0, mnt) { pend = 1; line = substr($0, index($0, mnt)) }
    pend { if (!line) line = $0
           if (match(line, />[ \t]*"[^"]+"[ \t]*2>&1/)) { m = substr(line, RSTART, RLENGTH); sub(/^>[ \t]*"/, "", m); sub(/"[ \t]*2>&1$/, "", m); print m; pend = 0 }
           line = "" }')"
  ncap=$(printf '%s\n' "$caps" | grep -c . || true)
  raw=""
  while IFS= read -r cp; do
    [ -n "$cp" ] || continue
    # a raw tail READS the capture: `tail -...` is in the same simple command (no | ; & between) as the path. `sed ... "$cp" | tail -1`
    # tails sed's output, and `grep ... "$cp" | tail -1` tails grep's, neither is a raw tail of the capture.
    while IFS= read -r ln; do
      seg="${ln%%"$cp"*}"; seg="${seg##*[|;&]}"
      # tail or head as the command that READS the capture (any argument shape: `tail -n 5 f`, `tail -5 f`, bare `tail f`, `head -c N f`), or
      # `cat <capture> | tail|head ...` (cat's output is the capture itself).
      after="${ln#*"$cp"}"; after="${after#\"}"
      if [[ "$seg" =~ (^|[^A-Za-z0-9_])(tail|head)[[:space:]] ]] \
         || { [[ "$seg" =~ (^|[^A-Za-z0-9_])cat[[:space:]]+([^[:space:]|;&]+[[:space:]]+)*\"?$ ]] && [[ "$after" =~ ^[[:space:]]*\|[[:space:]]*(tail|head)([[:space:]]|$) ]]; }; then
        raw="${raw} {${cp}: ${ln:0:90}}"; fi
    done < <(printf '%s\n' "$u" | grep -F -- "$cp" || true)
  done <<< "$caps"
  if [ "$ncall" -lt "$((10#$want_mounted))" ] || [ "$ncap" -lt "$((10#$want_mounted))" ] || [ -n "$raw" ]; then
    _a10b="${_a10b} $(basename "$f"):[gd_apt_out_tail call sites=$ncall (want >= $want_mounted) derived captures=$ncap (want >= $want_mounted) raw-tail-of-apt-capture:${raw:- none}]"
  fi
done
if [ -z "$_a10b" ]; then
  pass "A10b: assembly (derived) — in all ${#SPECS[@]} consumer suites every apt-bearing container's capture is read back through gd_apt_out_tail (at least one call per mounted site) and never through a raw tail"
else fail "A10b: raw tail of an apt capture, or no gd_apt_out_tail call" "${_a10b}. A raw tail shows unscrubbed container stdout and drops the cause line; use gd_apt_out_tail <capture> <n> (lib/apt-bounded.sh)."; fi

# ── FLOOR + LEDGER (ADR-193: printf + exit inside the block, never through pass()/fail()) ──
# Two statements, both loud: the first is the floor shape scripts/guard-vacuity-floor.test.sh mutation-tests (a literal threshold
# adjacent to the `if`, `-lt`, reported by printf + exit 1); the second makes the count EXACT, so an added-but-unregistered row is a
# finding as well as a deleted one. Move BOTH numbers together with the row count.
if [ "$checked" -lt 36 ]; then
  printf 'FAIL ANTI-VACUITY: only %s rows ran, floor is 36 — rows were deleted or the suite exited early.\n' "$checked" >&2
  exit 1
fi
if [ "$checked" -gt 36 ]; then
  printf 'FAIL ANTI-VACUITY: %s rows ran, expected exactly 36 — rows were added without moving this count.\n' "$checked" >&2
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
