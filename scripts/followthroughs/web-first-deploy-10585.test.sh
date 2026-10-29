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
# The `api ... --jq` call is answered by evaluating the probe's OWN --jq
# expression against the API-shaped fixture, so a broken filter fails green
# rather than being stubbed around.
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
FX="$GH_FX"
case "$*" in
  "run view --repo "*" --job "*" --log")
    jid=$(printf '%s' "$*" | sed -n 's/.*--job \([0-9][0-9]*\).*/\1/p')
    [ -f "$FX/log.$jid.fail" ] && exit 1
    [ -f "$FX/log.$jid" ] || { echo "stub gh: no log fixture for job $jid" >&2; exit 64; }
    cat "$FX/log.$jid"; exit 0 ;;
  "api repos/"*"/actions/runs/"*"/jobs"[?]"per_page=100 --jq "*)
    argv="$*"   # ${*##pat} maps over each positional param; strip on the joined string
    id=$(printf '%s' "$argv" | sed -n 's|.*/actions/runs/\([0-9][0-9]*\)/jobs.*|\1|p')
    [ -f "$FX/jobs.$id.fail" ] && exit 1
    [ -f "$FX/jobs.$id" ] || { echo "stub gh: no jobs fixture for run $id" >&2; exit 64; }
    jq -r "${argv##*--jq }" "$FX/jobs.$id"; exit $? ;;
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

# emitted output line of the trail step: l <line> <ts> <job> -> <job>\t<step>\t<ts> <line>
l()   { printf '%s\t%s\t%s %s\n' "$3" "$S" "$2" "$1"; }
# echoed run:-source line (ANSI-prefixed — the #9905 trap shape)
src() { printf '%s\t%s\t%s \033[36;1m%s\n' "$3" "$S" "$2" "$1"; }

ts()  { date -u -d "$1" '+%Y-%m-%dT%H:%M:%S.0000000Z'; }   # log-line timestamp
sql() { date -u -d "$1" '+%Y-%m-%d %H:%M:%S'; }            # marker timestamp

PTR()  { printf 'web-host-%s %s — fresh-host Sentry pointer (job=%s)' "$2" "$1" "${3:-success}"; }
READY='fresh-host boot reached fresh_boot_ready — the host booted clean and reported ready.'

list() { # <id,status> ...   -> $WORK/fx/list
  { for pair in "$@"; do
      printf '{"databaseId":%s,"createdAt":"%s","status":"%s","conclusion":"success"}\n' \
        "${pair%%,*}" "$(ts '2026-10-29')" "${pair##*,}"
    done; } | jq -s '.' > "$WORK/fx/list"
}
job() { # <run-id> <job-id> <job-name> <conclusion> — REST /jobs response shape
  printf '{"total_count":1,"jobs":[{"id":%s,"name":"%s","status":"completed","conclusion":"%s"}]}\n' \
    "$2" "$3" "$4" > "$WORK/fx/jobs.$1"
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
STUB_INVOCATIONS=0
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
  assert_fixture_dir "$WORK"
  STUB_INVOCATIONS=$(grep -c '^INVOCATION$' "$WORK/stub-calls.log" 2>/dev/null || printf '0')
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

# 0b. Emitter-parity drift guard — the probe's population anchors on literals
#     EMITTED elsewhere. Assert each still exists in its emitter, or every
#     synthesized fixture below quietly stops matching production.
TRAIL_SH="$REPO_ROOT/apps/web-platform/infra/scripts/fresh-host-boot-trail.sh"
WF_YML="$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml"
grep -qF '— fresh-host Sentry pointer' "$TRAIL_SH" \
  && pass "emitted literal '— fresh-host Sentry pointer' still in fresh-host-boot-trail.sh" \
  || fail "fresh-host-boot-trail.sh no longer emits '— fresh-host Sentry pointer'"
grep -qF 'fresh-host boot reached fresh_boot_ready' "$TRAIL_SH" \
  && pass "emitted literal 'fresh-host boot reached fresh_boot_ready' still in fresh-host-boot-trail.sh" \
  || fail "fresh-host-boot-trail.sh no longer emits 'fresh-host boot reached fresh_boot_ready'"
grep -qF 'Surface fresh-host Sentry breadcrumb trail' "$WF_YML" \
  && pass "step name 'Surface fresh-host Sentry breadcrumb trail' still in the workflow" \
  || fail "the trail step name drifted in apply-web-platform-infra.yml"
grep -qF 'DISPATCH_LABEL=web-host-replace' "$WF_YML" \
  && pass "DISPATCH_LABEL=web-host-replace still in the workflow" \
  || fail "DISPATCH_LABEL=web-host-replace drifted"
grep -qF 'DISPATCH_LABEL=web-host-create' "$WF_YML" \
  && pass "DISPATCH_LABEL=web-host-create still in the workflow" \
  || fail "DISPATCH_LABEL=web-host-create drifted"
# The session-TZ-safe bound: a naive toDateTime('...') parses in the session TZ
# and silently shifts the boot bound (the stale-evidence class).
grep -qF "toDateTime64('" "$PROBE" && grep -qF "3, 'UTC'" "$PROBE" \
  && pass "verdict dt bound uses toDateTime64(..., 3, 'UTC')" \
  || fail "the toDateTime64(...,3,'UTC') bound idiom drifted back to a naive literal"

# 0c. Notify-only structural pins (followthrough-convention.md, post-#8296):
#     the xtrace refusal first, the rc-remapping EXIT trap DIRECTLY after, the
#     probe's ONLY trap, and no exec/kill to bypass it.
n_traps=$(grep -cE '^[[:space:]]*trap[[:space:]]' "$PROBE")
[[ "$n_traps" == "1" ]] \
  && pass "exactly one trap statement in the probe" \
  || fail "trap count: want exactly 1, got $n_traps"
grep -qF 'case "$rc" in 0|1)' "$PROBE" \
  && pass "the EXIT trap remaps an unplanned 0/1 to CANNOT ESTABLISH" \
  || fail "the rc-remapping EXIT trap body drifted"
ref_ln=$(grep -n 'case "$-"' "$PROBE" | head -1 | cut -d: -f1)
trap_ln=$(grep -nE '^[[:space:]]*trap[[:space:]]' "$PROBE" | head -1 | cut -d: -f1)
if [[ -n "$ref_ln" && -n "$trap_ln" && "$ref_ln" -lt "$trap_ln" ]]; then
  esac_ln=$(awk -v s="$ref_ln" 'NR>s && /^esac/ {print NR; exit}' "$PROBE")
  between=$(awk -v a="$esac_ln" -v b="$trap_ln" 'NR>a && NR<b' "$PROBE" | grep -vE '^[[:space:]]*(#|$)' || true)
  if [[ -z "$between" ]]; then
    pass "xtrace refusal first, EXIT trap directly after (nothing between)"
  else
    fail "executable lines between the refusal and the trap: $between"
  fi
else
  fail "ordering: the xtrace refusal (line $ref_ln) must precede the EXIT trap (line $trap_ln)"
fi
if grep -vE '^[[:space:]]*#' "$PROBE" | grep -qE '\b(exec|kill)\b'; then
  fail "exec/kill present in the probe — either can bypass the rc-remap"
else
  pass "no exec/kill in the probe"
fi

# 1. Accounted: proven boot + marker at/after boot + live control -> quiet state.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '1 hour ago')
{ l "$(PTR web-2 replace)" "$B" web_host_replace; l "$READY" "$B" web_host_replace; } > "$WORK/fx/log.9011"
bs soleur-web-2 7 "$(sql '30 minutes ago')"
run_probe; check 2 "NOT YET" "accounted host (marker postdates boot) is the quiet state"
[[ "$STUB_INVOCATIONS" == "1" ]] \
  && pass "one owed host -> exactly one verdict query" \
  || fail "STUB_CALLS: want 1 verdict invocation, got $STUB_INVOCATIONS"

# 2. Pending: proven boot inside the 2d window, no marker yet -> NOT YET.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '1 hour ago')
{ l "$(PTR web-2 replace)" "$B" web_host_replace; l "$READY" "$B" web_host_replace; } > "$WORK/fx/log.9011"
bs soleur-web-2 3 none
run_probe; check 2 "NOT YET" "boot inside the deadline with no marker is pending (2)"

# 3. Overdue: boot older than 2d, no marker -> ACTION REQUIRED naming host,
#    boot ts, run URL and the control count.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '3 days ago')
{ l "$(PTR web-2 replace)" "$B" web_host_replace; l "$READY" "$B" web_host_replace; } > "$WORK/fx/log.9011"
bs soleur-web-2 4 none
run_probe
check 5 "soleur-web-2" "overdue first deploy names the host"
check 5 "$B" "overdue comment names the boot timestamp"
check 5 "actions/runs/901" "overdue comment names the dispatch run URL"
check 5 "control_rows=4" "overdue comment names the control count"
check 5 "web-host-birth.md" "overdue pointer names BOTH runbooks"

# 4. Channel-dark past the deadline is still ACTION REQUIRED — "no evidence of
#    a completed deploy", never a quiet pass.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '3 days ago')
{ l "$(PTR web-2 replace)" "$B" web_host_replace; l "$READY" "$B" web_host_replace; } > "$WORK/fx/log.9011"
bs soleur-web-2 0 none
run_probe; check 5 "channel" "control=0 past the deadline is ACTION REQUIRED (channel dark)"

# 5. Mutation 3: the SECOND owed host's overdue verdict must still fire when
#    the first is accounted — a probe that stops at the first member is the
#    defect. STUB_CALLS pin: both owed hosts must have been queried.
reset_fx; list "901,completed" "900,completed"
job 901 9011 web_host_replace success; job 900 9001 web_host_replace success
B1=$(ts '1 hour ago'); B2=$(ts '3 days ago')
{ l "$(PTR web-2 replace)" "$B1" web_host_replace; l "$READY" "$B1" web_host_replace; } > "$WORK/fx/log.9011"
{ l "$(PTR web-3 replace)" "$B2" web_host_replace; l "$READY" "$B2" web_host_replace; } > "$WORK/fx/log.9001"
bs soleur-web-2 9 "$(sql '30 minutes ago')"; bs soleur-web-3 5 none
run_probe; check 5 "soleur-web-3" "second owed host overdue still exits 5 after the first is accounted"
[[ "$STUB_INVOCATIONS" == "2" ]] \
  && pass "two owed hosts -> exactly two verdict queries" \
  || fail "STUB_CALLS: want 2 verdict invocations, got $STUB_INVOCATIONS"

# 5b. A transport failure on the FIRST owed host must not mask the second's
#     real overdue — grade ALL hosts, then prefer exit 5 over exit 3.
reset_fx; list "901,completed" "900,completed"
job 901 9011 web_host_replace success; job 900 9001 web_host_replace success
B1=$(ts '1 hour ago'); B2=$(ts '3 days ago')
{ l "$(PTR web-2 replace)" "$B1" web_host_replace; l "$READY" "$B1" web_host_replace; } > "$WORK/fx/log.9011"
{ l "$(PTR web-3 replace)" "$B2" web_host_replace; l "$READY" "$B2" web_host_replace; } > "$WORK/fx/log.9001"
# no bs.soleur-web-2 fixture -> the stub transport fails (rc 64) for web-2 only
bs soleur-web-3 5 none
run_probe
check 5 "soleur-web-3" "a sibling's transport failure does not mask a real overdue (exit 5 over 3)"
check 5 "CANNOT ESTABLISH" "the failed host's measurement is still reported"
[[ "$STUB_INVOCATIONS" == "2" ]] \
  && pass "the verdict loop graded BOTH hosts despite the first failing" \
  || fail "STUB_CALLS: want 2 verdict invocations (one failed transport), got $STUB_INVOCATIONS"

# 5c. All-unmeasured: every owed host's transport fails and none is overdue
#     -> CANNOT ESTABLISH, never a quiet 2.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '1 hour ago')
{ l "$(PTR web-2 replace)" "$B" web_host_replace; l "$READY" "$B" web_host_replace; } > "$WORK/fx/log.9011"
run_probe; check 3 "CANNOT ESTABLISH" "an owed host that cannot be measured is never a quiet pass"

# 6. Mutation 1: a trail that emitted `booted DARK` (no fresh_boot_ready)
#    creates NO obligation — that failure is already loud in the run itself.
reset_fx; list "901,completed"; job 901 9011 web_host_replace failure
B=$(ts '3 days ago')
{ l "$(PTR web-2 replace)" "$B" web_host_replace; l '##[error]web-2 (soleur-web-2) booted DARK at stage pull: x' "$B" web_host_replace; } > "$WORK/fx/log.9011"
run_probe; check 2 "NOT YET" "a dark boot creates no first-deploy obligation"

# 7. Mutation 2: marker text carried ONLY by ANSI-prefixed echoed run: source
#    (unexpanded vars / literal echo of the marker) must not count — the real
#    pointer emits but the echoed ready copy must NOT read as fresh_boot_ready.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '3 days ago')
{ l "$(PTR web-2 replace)" "$B" web_host_replace
  src 'echo "${DISPATCH_LABEL} ${WEB_HOST_KEY:-?} — fresh-host Sentry pointer (job=${JOB_STATUS})"' "$B" web_host_replace
  src "web-host-replace web-2 — fresh-host Sentry pointer (job=success)" "$B" web_host_replace
  src 'fresh-host boot reached fresh_boot_ready — the host booted clean and reported ready.' "$B" web_host_replace; } > "$WORK/fx/log.9011"
run_probe; check 2 "NOT YET" "an echoed-source ready line derives no obligation (ANSI excluded)"

# 7b. Mutation / tripwire: a SUCCESS-conclusion job whose trail step emitted
#     ZERO parseable lines is a broken parse channel -> CANNOT ESTABLISH, not
#     a quiet empty population.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
: > "$WORK/fx/log.9011"
run_probe; check 3 "zero parseable" "success job with an empty trail reads CANNOT ESTABLISH (log-shape drift)"
# a success job whose log has steps but none of ours is the same shape class
{ printf 'web_host_replace\tCheckout\t%s ok\n' "$B"; printf 'web_host_replace\tSet up job\t%s ok\n' "$B"; } > "$WORK/fx/log.9011"
run_probe; check 3 "zero parseable" "success job with an unrelated-step-only log reads CANNOT ESTABLISH"

# 8. Mutation 4 / re-replace: a host re-replaced after an earlier boot owes only
#    the NEWEST boot's deadline — the old boot's overdue-ness is superseded.
reset_fx; list "901,completed" "900,completed"
job 901 9011 web_host_replace success; job 900 9001 web_host_replace success
B_OLD=$(ts '3 days ago'); B_NEW=$(ts '1 hour ago')
{ l "$(PTR web-2 replace)" "$B_OLD" web_host_replace; l "$READY" "$B_OLD" web_host_replace; } > "$WORK/fx/log.9001"
{ l "$(PTR web-2 replace)" "$B_NEW" web_host_replace; l "$READY" "$B_NEW" web_host_replace; } > "$WORK/fx/log.9011"
bs soleur-web-2 3 none
run_probe; check 2 "NOT YET" "re-replaced host owes only the newest boot (old overdue boot superseded)"

# 9. Stale evidence: a marker row that PREDATES the boot must not account the
#    host (2026-10-28 learning) — past the deadline it is still ACTION REQUIRED.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '3 days ago')
{ l "$(PTR web-2 replace)" "$B" web_host_replace; l "$READY" "$B" web_host_replace; } > "$WORK/fx/log.9011"
bs soleur-web-2 4 "$(sql '4 days ago')"
run_probe; check 5 "ACTION REQUIRED" "a marker predating the boot does not account the host"

# 10. Roster gate: a replaced-then-retired key owes nothing — and a same-named
#     key OUTSIDE `variable "web_hosts"` must not resurrect it.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '3 days ago')
{ l "$(PTR web-9 replace)" "$B" web_host_replace; l "$READY" "$B" web_host_replace; } > "$WORK/fx/log.9011"
run_probe; check 2 "NOT YET" "a key retired from var.web_hosts owes nothing"
# same key declared in a NEIGHBOURING variable block -> still owed nothing
cat >> "$WORK/fx/variables.tf" <<'TF'
variable "other_map" {
  default = {
    "web-9" = { location = "hel1" }
  }
}
TF
run_probe; check 2 "NOT YET" "the roster grep is scoped to the web_hosts block, not the whole file"

# 11. web_host_create is covered by the same arm (the pointer alternation).
reset_fx; list "901,completed"; job 901 9011 web_host_create success
B=$(ts '1 hour ago')
{ l "$(PTR web-3 create success)" "$B" web_host_create; l "$READY" "$B" web_host_create; } > "$WORK/fx/log.9011"
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

# 12b. The -L 100 cap: a result set of exactly the cap may be a truncated 30d
#      window -> CANNOT ESTABLISH naming the cap, never a quiet smaller
#      population.
reset_fx
pairs=(); for i in $(seq 1 100); do pairs+=("$((1000+i)),completed"); done
list "${pairs[@]}"
run_probe; check 3 "cap" "a run list at exactly the -L cap reads CANNOT ESTABLISH"

# 13. Credential and binary preflights -> CANNOT ESTABLISH (never 2-as-quiet).
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '1 hour ago')
{ l "$(PTR web-2 replace)" "$B" web_host_replace; l "$READY" "$B" web_host_replace; } > "$WORK/fx/log.9011"
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
{ l "$(PTR web-2 replace)" "$B" web_host_replace; l "$READY" "$B" web_host_replace; } > "$WORK/fx/log.9011"
bs soleur-web-2 3 none
run_probe STUB_BSQ_RC=1; check 3 "CANNOT ESTABLISH" "verdict-query transport failure"
run_probe STUB_BSQ_RC=3; check 3 "CANNOT ESTABLISH" "verdict-query 'nothing was queried' (rc 3)"

# 15. Unparseable verdict row -> CANNOT ESTABLISH, never a quiet 2.
reset_fx; list "901,completed"; job 901 9011 web_host_replace success
B=$(ts '1 hour ago')
{ l "$(PTR web-2 replace)" "$B" web_host_replace; l "$READY" "$B" web_host_replace; } > "$WORK/fx/log.9011"
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
if [[ "$passes" -lt 30 ]]; then
  printf '[FATAL] anti-vacuity floor: only %s cases passed (expected 30+)\n' "$passes" >&2
  exit 1
fi
printf '%s passed, 0 failed\n' "$passes"
