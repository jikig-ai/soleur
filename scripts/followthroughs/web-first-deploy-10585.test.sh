#!/usr/bin/env bash
# Fixture suite for the #10585 standing first-deploy watchdog probe —
# scripts/followthroughs/web-first-deploy-10585.sh. A PATH-stubbed `gh` serves
# run lists, jobs JSON and job logs in GitHub's real `--log` shape
# (job<TAB>step<TAB>timestamp text), including ANSI-prefixed echoed `run:`
# source lines (the #9905 trap). The Better Stack transport is stubbed through
# the probe's FT10585_QUERY_SH seam and answers from per-host fixture files
# (control count + marker timestamp), so marker-staleness is graded against the
# boot bound the probe actually sends.
#
# The property under test: the probe NEVER exits 0 or 1 (notify-only — the
# tracker must stay open). 5 = an owed host's first deploy is overdue; 2 = the
# standing quiet state; 3 = the measurement could not be made; 78 = xtrace
# refusal with a live credential. A dark boot, an echoed-source-only trail, a
# re-replaced host's stale boot, or a roster-retired key must never create an
# obligation, and the SECOND owed host's overdue verdict must still fire after
# the first is accounted.
#
# All data synthesized (cq-test-fixtures-synthesized-only): fabricated run ids,
# timestamps, host keys and counts only — no live captures.
set -uo pipefail

WORK=$(mktemp -d -t ft10585root.XXXXXXXX) || { echo "FATAL: could not create scratch root" >&2; exit 1; }
[[ "$WORK" == /* && -d "$WORK" && ! -L "$WORK" ]] || { echo "FATAL: bad scratch root: $WORK" >&2; exit 1; }
trap 'rm -rf -- "$WORK"' EXIT

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
assert_fixture_dir "$WORK"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/web-first-deploy-10585.sh"
[[ -f "$PROBE" ]] || { echo "FATAL: probe not found at $PROBE" >&2; exit 1; }

BIN="$WORK/bin"
assert_fixture_dir "$BIN"
mkdir -p "$BIN" "$WORK/fx"

# ── gh stub ─────────────────────────────────────────────────────────────────
# Serves the three gh calls the probe makes. Refuses (exit 64) any argv it was
# not written for, so a probe asking GitHub the wrong question cannot read a
# right-shaped fixture. `*.fail` sentinels flip a call to a transport failure.
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
FX="$GH_FX"
case "$*" in
  "run view --repo "*" --job "*" --log")
    jid=$(printf '%s' "$*" | sed -n 's/.*--job \([0-9][0-9]*\).*/\1/p')
    [ -f "$FX/log.$jid.fail" ] && exit 1
    [ -f "$FX/log.$jid" ] || { echo "stub gh: no log fixture for job $jid" >&2; exit 64; }
    cat "$FX/log.$jid"; exit 0 ;;
  "run view "*" --repo "*" --json jobs")
    id=$(printf '%s' "$*" | sed -n 's/^run view \([0-9][0-9]*\) .*/\1/p')
    [ -f "$FX/jobs.$id.fail" ] && exit 1
    [ -f "$FX/jobs.$id" ] || { echo "stub gh: no jobs fixture for run $id" >&2; exit 64; }
    cat "$FX/jobs.$id"; exit 0 ;;
  "run list "*)
    [ -f "$FX/list.fail" ] && exit 1
    [ -f "$FX/list" ] || { echo "stub gh: no list fixture" >&2; exit 64; }
    cat "$FX/list"; exit 0 ;;
esac
echo "stub gh: unexpected argv: $*" >&2; exit 64
STUB
chmod +x "$BIN/gh"

# ── Better Stack transport stub (the FT10585_QUERY_SH seam) ─────────────────
# Answers the probe's per-host aggregate query from $GH_FX/bs.<host_name>:
#   control=<n>      ci-deploy/webhook row count
#   marker=<ts|none> a Deploy-succeeded-class row timestamp; counted only when
#                    >= the dt bound the SQL carries (stale markers do not count)
cat > "$BIN/bsq" <<'STUB'
#!/usr/bin/env bash
printf 'INVOCATION\n' >> "${STUB_CALLS:-/dev/null}"
if [ -n "${STUB_BSQ_RC:-}" ] && [ "${STUB_BSQ_RC}" != "0" ]; then
  echo "stub bsq: injected transport failure" >&2
  exit "${STUB_BSQ_RC}"
fi
sql="$*"
host=$(printf '%s' "$sql" | grep -oE "soleur-[a-z0-9-]+" | head -1)
bound=$(printf '%s' "$sql" | grep -oE "toDateTime(64)?\('[^']*'" | head -1 | sed -E "s/.*\('//")
f="$GH_FX/bs.${host}"
[ -f "$f" ] || { echo "stub bsq: no fixture for host '$host'" >&2; exit 64; }
control=$(sed -n 's/^control=//p' "$f" | head -1)
marker=$(sed -n 's/^marker=//p' "$f" | head -1)
mrows=0
if [ -n "$marker" ] && [ "$marker" != "none" ] && [ ! "$marker" \< "$bound" ]; then
  mrows=1
fi
printf '{"control_rows":%s,"marker_rows":%s}\n' "${control:-0}" "$mrows"
STUB
chmod +x "$BIN/bsq"

passes=0
FAILURES=()
SEEN_RCS=()
pass() { echo "  PASS: $1"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; FAILURES+=("$1"); }

# ── fixture builders ─────────────────────────────────────────────────────────
S="Surface fresh-host Sentry breadcrumb trail (best-effort — R2/R3/R4/R5)"

# emitted output line of the trail step: <job>\t<step>\t<ts> <line>
l()   { printf 'web_host_replace\t%s\t%s %s\n' "${3:-$S}" "$2" "$1"; }
# echoed run:-source line (ANSI-prefixed — the #9905 trap shape)
src() { printf 'web_host_replace\t%s\t%s \033[36;1m%s\n' "$S" "$2" "$1"; }

ts()  { date -u -d "$1" '+%Y-%m-%dT%H:%M:%S.0000000Z'; }   # log-line timestamp
sql() { date -u -d "$1" '+%Y-%m-%d %H:%M:%S'; }            # marker timestamp

PTR()  { printf 'web-host-%s %s — fresh-host Sentry pointer (job=success)' "$2" "$1"; }
READY='fresh-host boot reached fresh_boot_ready — the host booted clean and reported ready.'

list() { # <id,status> ...   -> $WORK/fx/list
  { for pair in "$@"; do
      printf '{"databaseId":%s,"createdAt":"%s","status":"%s","conclusion":"success"}\n' \
        "${pair%%,*}" "$(ts '2026-10-29')" "${pair##*,}"
    done; } | jq -s '.' > "$WORK/fx/list"
}
job() { # <run-id> <job-id> <job-name> <conclusion>
  printf '{"jobs":[{"databaseId":%s,"name":"%s","conclusion":"%s"}]}\n' "$2" "$3" "$4" > "$WORK/fx/jobs.$1"
}
bs() { # <host_name> <control> <marker-ts|none>
  printf 'control=%s\nmarker=%s\n' "$2" "$3" > "$WORK/fx/bs.$1"
}

reset_fx() {
  rm -rf -- "$WORK/fx"
  assert_fixture_dir "$WORK/fx"
  mkdir -p "$WORK/fx"
  # roster: web-1/web-2/web-3 declared; web-9 deliberately absent.
  cat > "$WORK/fx/variables.tf" <<'TF'
variable "web_hosts" {
  default = {
    "web-1" = { location = "hel1", private_ip = "10.0.1.10" }
    "web-2" = { location = "hel1", private_ip = "10.0.1.12" }
    "web-3" = { location = "hel1", private_ip = "10.0.1.13" }
  }
}
TF
}

PROBE_OUT=""
PROBE_RC=0
# run_probe [VAR=val ...] — the sweeper's env -i shape: only named vars forward.
run_probe() {
  local rc=0
  PROBE_OUT=$(env -i PATH="$BIN:$PATH" HOME="$WORK" GH_FX="$WORK/fx" \
    GH_TOKEN=ft10585-stub BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
    FT10585_QUERY_SH="$BIN/bsq" FT10585_VARS_TF="$WORK/fx/variables.tf" \
    STUB_CALLS="$WORK/stub-calls.log" \
    "$@" bash "$PROBE" 2>&1) || rc=$?
  PROBE_RC=$rc
  SEEN_RCS+=("$rc")
  assert_fixture_dir "$WORK/stub-calls.log"
  : > "$WORK/stub-calls.log"
}
check() { # <want-rc> <want-word|-> <label>
  local want="$1" word="$2" label="$3"
  if [[ "$PROBE_RC" == "$want" ]] && { [[ "$word" == "-" ]] || grep -qF "$word" <<<"$PROBE_OUT"; }; then
    pass "$label (rc=$PROBE_RC)"
  else
    fail "$label: want rc=$want word='$word', got rc=$PROBE_RC: $(tr '\n' ' ' <<<"$PROBE_OUT" | head -c 240)"
  fi
}

echo "web-first-deploy-10585 probe:"

# 0. Artifact hygiene — a non-executable probe is skipped silently by the sweeper.
if [ -x "$PROBE" ]; then pass "probe is executable"; else fail "probe is not executable ($PROBE)"; fi

# 1. Accounted: proven boot + marker at/after boot + live control -> quiet state.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '1 hour ago')
{ l "$(PTR web-2 replace)" "$B"; l "$READY" "$B"; } > "$WORK/fx/log.9011"
bs soleur-web-2 7 "$(sql '30 minutes ago')"
run_probe; check 2 "NOT YET" "accounted host (marker postdates boot) is the quiet state"

# 2. Pending: proven boot inside the 2d window, no marker yet -> NOT YET.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '1 hour ago')
{ l "$(PTR web-2 replace)" "$B"; l "$READY" "$B"; } > "$WORK/fx/log.9011"
bs soleur-web-2 3 none
run_probe; check 2 "NOT YET" "boot inside the deadline with no marker is pending (2)"

# 3. Overdue: boot older than 2d, no marker -> ACTION REQUIRED naming host,
#    boot ts, run URL and the control count.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '3 days ago')
{ l "$(PTR web-2 replace)" "$B"; l "$READY" "$B"; } > "$WORK/fx/log.9011"
bs soleur-web-2 4 none
run_probe
check 5 "soleur-web-2" "overdue first deploy names the host"
check 5 "$B" "overdue comment names the boot timestamp"
check 5 "actions/runs/901" "overdue comment names the dispatch run URL"
check 5 "control_rows=4" "overdue comment names the control count"

# 4. Channel-dark past the deadline is still ACTION REQUIRED — "no evidence of
#    a completed deploy", never a quiet pass.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '3 days ago')
{ l "$(PTR web-2 replace)" "$B"; l "$READY" "$B"; } > "$WORK/fx/log.9011"
bs soleur-web-2 0 none
run_probe; check 5 "channel" "control=0 past the deadline is ACTION REQUIRED (channel dark)"

# 5. Mutation 3: the SECOND owed host's overdue verdict must still fire when
#    the first is accounted — a probe that stops at the first member is the
#    defect.
reset_fx; list "901,completed" "900,completed"
job 901 9011 web_host_replace success; job 900 9001 web_host_replace success
B1=$(ts '1 hour ago'); B2=$(ts '3 days ago')
{ l "$(PTR web-2 replace)" "$B1"; l "$READY" "$B1"; } > "$WORK/fx/log.9011"
{ l "$(PTR web-3 replace)" "$B2"; l "$READY" "$B2"; } > "$WORK/fx/log.9001"
bs soleur-web-2 9 "$(sql '30 minutes ago')"; bs soleur-web-3 5 none
run_probe; check 5 "soleur-web-3" "second owed host overdue still exits 5 after the first is accounted"

# 6. Mutation 1: a trail that emitted `booted DARK` (no fresh_boot_ready)
#    creates NO obligation — that failure is already loud in the run itself.
reset_fx; list "901,completed"; job 901 9011 web_host_replace failure
B=$(ts '3 days ago')
{ l "$(PTR web-2 replace)" "$B"; l '##[error]web-2 (soleur-web-2) booted DARK at stage pull: x' "$B"; } > "$WORK/fx/log.9011"
run_probe; check 2 "NOT YET" "a dark boot creates no first-deploy obligation"

# 7. Mutation 2: the marker text existing ONLY as ANSI-prefixed echoed run:
#    source (unexpanded vars / literal echo of the marker) derives NO host.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '3 days ago')
{ src 'echo "${DISPATCH_LABEL} ${WEB_HOST_KEY:-?} — fresh-host Sentry pointer (job=${JOB_STATUS})"' "$B"
  src "web-host-replace web-2 — fresh-host Sentry pointer (job=success)" "$B"
  src 'fresh-host boot reached fresh_boot_ready — the host booted clean and reported ready.' "$B"; } > "$WORK/fx/log.9011"
run_probe; check 2 "NOT YET" "echoed-source-only trail derives no obligation (ANSI excluded)"

# 8. Mutation 4 / re-replace: a host re-replaced after an earlier boot owes only
#    the NEWEST boot's deadline — the old boot's overdue-ness is superseded.
reset_fx; list "901,completed" "900,completed"
job 901 9011 web_host_replace success; job 900 9001 web_host_replace success
B_OLD=$(ts '3 days ago'); B_NEW=$(ts '1 hour ago')
{ l "$(PTR web-2 replace)" "$B_OLD"; l "$READY" "$B_OLD"; } > "$WORK/fx/log.9001"
{ l "$(PTR web-2 replace)" "$B_NEW"; l "$READY" "$B_NEW"; } > "$WORK/fx/log.9011"
bs soleur-web-2 3 none
run_probe; check 2 "NOT YET" "re-replaced host owes only the newest boot (old overdue boot superseded)"

# 9. Stale evidence: a marker row that PREDATES the boot must not account the
#    host (2026-10-28 learning) — past the deadline it is still ACTION REQUIRED.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '3 days ago')
{ l "$(PTR web-2 replace)" "$B"; l "$READY" "$B"; } > "$WORK/fx/log.9011"
bs soleur-web-2 4 "$(sql '4 days ago')"
run_probe; check 5 "ACTION REQUIRED" "a marker predating the boot does not account the host"

# 10. Roster gate: a replaced-then-retired key owes nothing.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '3 days ago')
{ l "$(PTR web-9 replace)" "$B"; l "$READY" "$B"; } > "$WORK/fx/log.9011"
run_probe; check 2 "NOT YET" "a key retired from var.web_hosts owes nothing"

# 11. web_host_create is covered by the same arm (the pointer alternation).
reset_fx; list "901,completed"; job 901 9011 web_host_create success
B=$(ts '1 hour ago')
{ l "$(PTR web-3 create success)" "$B"; l "$READY" "$B"; } > "$WORK/fx/log.9011"
bs soleur-web-3 6 "$(sql '30 minutes ago')"
run_probe; check 2 "NOT YET" "a web_host_create boot is owed and accounted identically"

# 12. No obligations at all: no dispatch runs / no qualifying job / a skipped job.
reset_fx; printf '[]\n' > "$WORK/fx/list"
run_probe; check 2 "NOT YET" "no dispatch runs in window"
reset_fx; list "901,in_progress"
run_probe; check 2 "NOT YET" "a non-completed run is not a population source"
reset_fx; list "901,completed"; job 901 9011 web_host_replace skipped
: > "$WORK/fx/log.9011"
run_probe; check 2 "NOT YET" "a skipped replace job derives no obligation"
reset_fx; list "901,completed"; job 901 9011 build success
run_probe; check 2 "NOT YET" "a dispatch run for another apply_target derives no obligation"

# 13. Credential and binary preflights -> CANNOT ESTABLISH (never 2-as-quiet).
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '1 hour ago')
{ l "$(PTR web-2 replace)" "$B"; l "$READY" "$B"; } > "$WORK/fx/log.9011"
bs soleur-web-2 3 none
run_probe GH_TOKEN=;      check 3 "CANNOT ESTABLISH" "GH_TOKEN unset"
run_probe BETTERSTACK_QUERY_PASSWORD=; check 3 "CANNOT ESTABLISH" "BETTERSTACK_QUERY_PASSWORD unset"
run_probe BETTERSTACK_QUERY_HOST=;     check 3 "CANNOT ESTABLISH" "BETTERSTACK_QUERY_HOST unset"
run_probe FT10585_GH=gh-does-not-exist-10585; check 3 "CANNOT ESTABLISH" "gh not on PATH"

# 14. Transport failures -> CANNOT ESTABLISH (gh read + query transport).
reset_fx; touch "$WORK/fx/list.fail"
run_probe; check 3 "CANNOT ESTABLISH" "gh run list transport failure"
reset_fx; list "901,completed"; job 901 9011 web_host_replace success; touch "$WORK/fx/log.9011.fail"
run_probe; check 3 "CANNOT ESTABLISH" "gh job-log transport failure"
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '1 hour ago')
{ l "$(PTR web-2 replace)" "$B"; l "$READY" "$B"; } > "$WORK/fx/log.9011"
bs soleur-web-2 3 none
run_probe STUB_BSQ_RC=1; check 3 "CANNOT ESTABLISH" "verdict-query transport failure"
run_probe STUB_BSQ_RC=3; check 3 "CANNOT ESTABLISH" "verdict-query 'nothing was queried' (rc 3)"

# 15. Unparseable verdict row -> CANNOT ESTABLISH, never a quiet 2.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '1 hour ago')
{ l "$(PTR web-2 replace)" "$B"; l "$READY" "$B"; } > "$WORK/fx/log.9011"
printf 'control=x\nmarker=none\n' > "$WORK/fx/bs.soleur-web-2"
run_probe; check 3 "CANNOT ESTABLISH" "non-numeric verdict row"

# 16. xtrace refusal with a live credential bound.
rc=0
env -i PATH="$BIN:$PATH" HOME="$WORK" GH_FX="$WORK/fx" \
  GH_TOKEN=ft10585-stub BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
  FT10585_QUERY_SH="$BIN/bsq" FT10585_VARS_TF="$WORK/fx/variables.tf" \
  bash -x "$PROBE" >/dev/null 2>&1 || rc=$?
SEEN_RCS+=("$rc")
if [[ "$rc" == "78" ]]; then pass "xtrace with a live credential refuses (rc=78)"
else fail "xtrace refusal: want rc=78, got rc=$rc"; fi

# ── Property sweep: the never-0 / never-1 invariant on every driven path ─────
bad_rc=0
for r in ${SEEN_RCS[@]+"${SEEN_RCS[@]}"}; do
  case "$r" in 5|2|3|78) : ;; *) bad_rc=$((bad_rc + 1)); echo "  FAIL: exit code $r is outside the notify-only vocabulary {5,2,3,78}" ;; esac
done
if [[ "$bad_rc" -eq 0 ]]; then
  pass "exit-code invariant: every driven path exited in {5,2,3,78} (${#SEEN_RCS[@]} runs)"
else
  fail "$bad_rc run(s) exited outside {5,2,3,78} — a 0 would close the standing tracker, a 1 reads as FAIL"
fi

if [ "${#FAILURES[@]}" -gt 0 ]; then
  printf '%s passed, %s failed\n' "$passes" "${#FAILURES[@]}"; exit 1
fi
# Anti-vacuity floor, reported outside the helpers it backstops.
if [[ "$passes" -lt 20 ]]; then
  printf '[FATAL] anti-vacuity floor: only %s cases passed (expected 20+)\n' "$passes" >&2
  exit 1
fi
printf '%s passed, 0 failed\n' "$passes"
