#!/usr/bin/env bash
# web-fresh-boot-zot-8651.test.sh — fixture test for the issue-8651 closure probe.
# A PATH-stubbed `gh` serves run lists, job JSON and job logs in GitHub's real `--log` shape
# (job<TAB>step<TAB>timestamp text), including the echoed `run:` source lines GitHub prints with
# an ANSI prefix. The stub REFUSES any argv it was not written for (exit 64), so a probe that
# asks GitHub the wrong question cannot read the right fixture. Every sweeper exit code is
# driven, each verdict pinned by BOTH its exit code and its leading word.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$DIR/web-fresh-boot-zot-8651.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }
# Instrument self-test (ported from zot-soak-6122.test.sh): drive no() and ok() once each and
# require that EACH moved its own counter, then unwind. A no() that fed $pass would turn every
# real failure into a pass and this suite's verdict green. Reported with printf + exit, never
# through the helpers under test.
no "self-test (expected)" 2>/dev/null; ok "self-test (expected)" >/dev/null
if [ "$fail" -ne 1 ] || [ "$pass" -ne 1 ]; then
  printf 'FATAL: the verdict helpers do not count (fail=%s pass=%s)\n' "$fail" "$pass" >&2
  exit 1
fi
pass=0; fail=0

BIN="$WORK/bin"; mkdir -p "$BIN" "$WORK/fx"
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
FX="$GH_FX"
case "$*" in
  "run list --repo jikig-ai/soleur --workflow apply-web-platform-infra.yml --event workflow_dispatch -L 40 --json databaseId --jq .[].databaseId")
    [ -f "$FX/list.fail" ] && exit 1; cat "$FX/list"; exit 0 ;;
  "run view "*" --repo jikig-ai/soleur --json jobs")
    id="${3}"; [ -f "$FX/jobs.$id" ] || { echo "stub: no jobs fixture $id" >&2; exit 64; }; cat "$FX/jobs.$id"; exit 0 ;;
  "run view --repo jikig-ai/soleur --job "*" --log")
    jid="${6}"; [ -f "$FX/log.$jid.fail" ] && exit 1
    [ -f "$FX/log.$jid" ] || { echo "stub: no log fixture $jid" >&2; exit 64; }; cat "$FX/log.$jid"; exit 0 ;;
esac
echo "stub gh: unexpected argv: $*" >&2; exit 64
STUB
chmod +x "$BIN/gh"

S="Surface fresh-host Sentry breadcrumb trail (best-effort — R2/R3/R4/R5)"
TS="2026-09-24T10:00:00.0000000Z"
l() { printf 'web_host_replace\t%s\t%s %s\n' "${2:-$S}" "$TS" "$1"; }            # a step output line
src() { printf 'web_host_replace\t%s\t%s \033[36;1m%s\n' "$S" "$TS" "$1"; }        # an echoed-source line
PTR="web-host-replace web-2 — fresh-host Sentry pointer (job=success)"
ZOT='- image-origin (`soleur-web-2`, since run anchor): `stage=app_zot host=soleur-web-2 time=2026-09-24T10:05:00Z detail=zot_login=ok ghcr_login=fail nic=ready:0 zot=[login=ok,n=1,cause=other]`'
READY="fresh-host boot reached fresh_boot_ready — the host booted clean and reported ready."

reset_fx() { rm -rf "$WORK/fx"; mkdir -p "$WORK/fx"; }
job() {  # <run-id> <job-id> <name> <conclusion> [trail-step-conclusion=success] [trail-startedAt]
  # startedAt defaults to a real timestamp so recovery-capable fixtures carry
  # it; pass "-" for the absent arm (the probe's `// "-"` then reads no usable
  # startedAt). `gh run view --json jobs` spells the field camelCase.
  local st_json
  if [[ "${6:-}" == "-" ]]; then st_json='null'; else st_json="\"${6:-$ST_START}\""; fi
  printf '{"jobs":[{"databaseId":1,"name":"preflight","conclusion":"success"},{"databaseId":%s,"name":"%s","conclusion":"%s","steps":[{"name":"%s","conclusion":"%s","startedAt":%s,"completedAt":%s}]}]}\n' \
    "$2" "$3" "$4" "$S" "${5:-success}" "$st_json" "$st_json" > "$WORK/fx/jobs.$1"
}
ST_START="2026-09-24T10:00:00Z"   # the trail step's startedAt for recovery-capable fixtures

# ── UNKNOWN STEP (attribution-expired) fixture builders — #11607 ─────────────
# GitHub drops step-name attribution ~2-3 wk post-completion: every line comes
# back under field 2 "UNKNOWN STEP" while the content survives (#11600).
# GH_LOG_BOM — the UTF-8 byte-order mark gh writes at the start of EVERY step
# section after the first (only the stream head is bare). NOT decoration: a
# lone-BOM document cannot tell `${log//…/}` from `${log/…/}` — the single-strip
# mutation is pinned only while a SECOND BOM'd section exists.
GH_LOG_BOM=$'\357\273\277'
# ul — one emitted line under "UNKNOWN STEP" (field 2); ANSI-echoed variants
#   are passed literally in the payload args.  ul <line> <ts> <job> [bom]
ul()   { printf '%s\tUNKNOWN STEP\t%s%s %s\n' "$3" "${4:-}" "$2" "$1"; }
# ulog <job-name> <startedAt-ISO> <line>... — a faithful attribution-expired
# document: BARE `Set up job` head (gh strips the BOM only from the stream
# head), a BOM'd prelude ##[group]Run stamped BEFORE startedAt (the ts>=ps
# gate must skip it AND it puts the second BOM in the file — the must-PASS
# prelude), the BOM'd trail-step ##[group]Run AT startedAt, the payload lines
# stamped at startedAt, then a BOM'd next-step header bounding the region.
#   ULOG_NO_BOUND=1  omits the closing header (region runs to EOF)
#   ULOG_EARLY_HDR=1 stamps the trail header BEFORE startedAt (the
#                    "no ##[group]Run header at/after startedAt" arm)
ulog() {
  local jn="$1" st="$2"; shift 2
  local base epoch pre post l hdr_ts
  base=${st%Z}; base=${base%%.*}
  # Epoch arithmetic: `date -d "<ISO> - 10 minutes"` misparses the relative
  # clause on this platform — go through %s.
  epoch=$(date -u -d "${base}Z" +%s)
  pre=$(date -u -d "@$((epoch - 600))" '+%Y-%m-%dT%H:%M:%S.0000000Z')
  post=$(date -u -d "@$((epoch + 600))" '+%Y-%m-%dT%H:%M:%S.0000000Z')
  hdr_ts="$st"; [[ "${ULOG_EARLY_HDR:-0}" == 1 ]] && hdr_ts="$pre"
  printf '%s\tUNKNOWN STEP\t%s ##[group]Run Set up job\n' "$jn" "$pre"
  ul '##[group]Run terraform plan' "$pre" "$jn" "$GH_LOG_BOM"
  ul 'prelude step output line (not the trail)' "$pre" "$jn"
  ul '##[group]Run Surface the fresh-host Sentry breadcrumb trail' "$hdr_ts" "$jn" "$GH_LOG_BOM"
  for l in "$@"; do printf '%s\tUNKNOWN STEP\t%s %s\n' "$jn" "$st" "$l"; done
  [[ "${ULOG_NO_BOUND:-0}" == 1 ]] || ul '##[group]Run Post job cleanup' "$post" "$jn" "$GH_LOG_BOM"
}
run() {  # <want-rc> <want-word> <label>
  local out rc=0
  out=$(PATH="$BIN:$PATH" GH_FX="$WORK/fx" bash "$PROBE" 2>&1) || rc=$?
  if [ "$rc" = "$1" ] && grep -q "^$2" <<<"$out"; then ok "$3 → exit $1 ($2)"
  else no "$3: want exit $1 + '$2', got exit $rc: $(tr '\n' ' ' <<<"$out" | head -c 260)"; fi
}

reset_fx; echo 900 > "$WORK/fx/list"; job 900 9001 web_host_replace success
{ l "$PTR"; l "$ZOT"; l "$READY"; } > "$WORK/fx/log.9001";              run 0 PASS "zot-served boot with fresh_boot_ready"
# R4 (#8036 1d): the seed block no longer attempts a GHCR login, so the success detail carries no
# `ghcr_login=` field at all. The probe must PASS on that new format, not depend on the old field.
ZOT_1D='- image-origin (`soleur-web-2`, since run anchor): `stage=app_zot host=soleur-web-2 time=2026-09-24T10:05:00Z detail=zot_login=ok nic=ready:0 zot=[login=ok,n=1,cause=none]`'
{ l "$PTR"; l "$ZOT_1D"; l "$READY"; } > "$WORK/fx/log.9001";           run 0 PASS "R4: new-format success detail without ghcr_login= (post-#8036 1d)"
{ l "$PTR"; l "$READY"; } > "$WORK/fx/log.9001";                         run 2 "NOT YET" "newest run predates the fixed trail (no image-origin line)"
{ l "$PTR"; l "$ZOT"; l '##[error]web-2 (soleur-web-2) booted DARK at stage pull: nic=ready:0 zot=[login=ok,n=3,cause=manifest] ghcr=[login=fail,pull=not-attempted] pull_err: x'; } > "$WORK/fx/log.9001"
run 1 FAIL "fixed trail, booted DARK"
{ l "$PTR"; l "$ZOT"; l '##[error]web-2 (soleur-web-2) did not reach cloud_init_complete within 960s'; } > "$WORK/fx/log.9001"
run 1 FAIL "fixed trail, no terminal event (timeout)"
{ l "$PTR"; l '- image-origin (`soleur-web-2`, since run anchor): `stage=app_ghcr_served host=soleur-web-2 time=t detail=zot_login=fail ghcr_login=ok`'; l "$READY"; } > "$WORK/fx/log.9001"
run 1 FAIL "GHCR served the boot"
{ l "$PTR"; l "$ZOT"; l "Booted, readiness unconfirmed."; } > "$WORK/fx/log.9001";   run 2 "NOT YET" "inconclusive: app_zot but no fresh_boot_ready"
{ l "$PTR"; l "${ZOT/zot_login=ok/zot_login=fail}"; l "$READY"; } > "$WORK/fx/log.9001"; run 2 "NOT YET" "app_zot without zot_login=ok is not a pass"
{ l "$PTR"; l "- image-origin read FAILED (HTTP 500 or no data array) — UNKNOWN, not 'none'."; l "$READY"; } > "$WORK/fx/log.9001"
run 2 "NOT YET" "image-origin read failed on the fixed trail"
# DECOYS: the pass-shaped text appears only in echoed run-block SOURCE, or in another step.
{ l "$PTR"; src "$ZOT"; src "$READY"; l '- image-origin (`soleur-web-2`, since run anchor): `stage=none host=- time=- detail=-`'; l "Booted, readiness unconfirmed."; } > "$WORK/fx/log.9001"
run 2 "NOT YET" "echoed-source decoy lines are not graded (graded, they would read as a PASS)"
{ l "$PTR"; l "$ZOT" "Dispatch summary"; l "$READY" "Dispatch summary"; } > "$WORK/fx/log.9001"
run 2 "NOT YET" "pass-shaped lines in another step are not graded"
# Host selection: a newer web-1 run is skipped; the older web-2 run is the one graded.
reset_fx; printf '901\n900\n' > "$WORK/fx/list"; job 901 9011 web_host_replace success; job 900 9001 web_host_replace success
{ l "web-host-replace web-1 — fresh-host Sentry pointer (job=success)"; l '##[error]web-1 booted DARK at stage pull: x'; } > "$WORK/fx/log.9011"
{ l "$PTR"; l "$ZOT"; l "$READY"; } > "$WORK/fx/log.9001";              run 0 PASS "a newer web-1 run is skipped, web-2 graded"
# A newer web-2 run that went dark wins over an older passing one.
{ l "$PTR"; l "$ZOT"; l '##[error]web-2 (soleur-web-2) booted DARK at stage extract: x'; } > "$WORK/fx/log.9011"
run 1 FAIL "the NEWEST web-2 run decides (dark after an earlier pass)"
reset_fx; echo 900 > "$WORK/fx/list"; job 900 9001 web_host_replace skipped
run 2 "NOT YET" "a skipped replace job is not evidence"
reset_fx; : > "$WORK/fx/list";                                              run 2 "NOT YET" "no dispatch runs at all"
reset_fx; touch "$WORK/fx/list.fail";                                       run 3 TRANSIENT "gh run list fails"
reset_fx; echo 900 > "$WORK/fx/list"; job 900 9001 web_host_replace success; touch "$WORK/fx/log.9001.fail"
run 3 TRANSIENT "job log read fails"

# ── UNKNOWN STEP (attribution-expired) job logs — #11607 ─────────────────────
# The trail must be recovered from the ##[group]Run region keyed on the step's
# startedAt, graded through the same emitted-vs-echoed filter, and a success
# job's degraded channel must trip TRANSIENT — never a silent "no run".
AST="2026-10-20T10:00:00Z"
# AC-1: a success job whose whole log is UNKNOWN STEP — BOM'd headers, a
# pre-startedAt prelude the ts gate must skip, emitted pointer+zot+ready —
# is graded by content through the recovered region: PASS, never "no run".
reset_fx; echo 900 > "$WORK/fx/list"; job 900 9001 web_host_replace success success "$AST"
ulog web_host_replace "$AST" "$PTR" "$ZOT" "$READY" > "$WORK/fx/log.9001"
run 0 PASS "aged UNKNOWN STEP success job: trail recovered from the ##[group]Run region"
# AC-2: recovery is conclusion-agnostic — a FAILURE job's aged log carrying
# pointer + booted DARK grades FAIL identically.
reset_fx; echo 900 > "$WORK/fx/list"; job 900 9001 web_host_replace failure success "$AST"
ulog web_host_replace "$AST" "$PTR" "$ZOT" '##[error]web-2 (soleur-web-2) booted DARK at stage pull: x' > "$WORK/fx/log.9001"
run 1 FAIL "aged UNKNOWN STEP failure job: the DARK trail still grades FAIL (conclusion-agnostic)"
# AC-3: the tripwire survives recovery — a success job whose recovered region
# holds zero trail-pattern lines exits 3 TRANSIENT; a log with no ##[group]Run
# header at/after startedAt (early header, no bound) is the same verdict.
reset_fx; echo 900 > "$WORK/fx/list"; job 900 9001 web_host_replace success success "$AST"
ulog web_host_replace "$AST" 'an unrelated output line' 'another quiet line' > "$WORK/fx/log.9001"
run 3 TRANSIENT "aged success job, recovered region with no trail-pattern lines reads TRANSIENT"
reset_fx; echo 900 > "$WORK/fx/list"; job 900 9001 web_host_replace success success "$AST"
ULOG_EARLY_HDR=1 ULOG_NO_BOUND=1 ulog web_host_replace "$AST" "$PTR" "$ZOT" "$READY" > "$WORK/fx/log.9001"
run 3 TRANSIENT "aged success job, no ##[group]Run header at/after startedAt reads TRANSIENT"
# AC-3: a success job whose jobs-JSON step entry carries no startedAt cannot
# be bounded — unbounded is unmeasured -> TRANSIENT.
reset_fx; echo 900 > "$WORK/fx/list"; job 900 9001 web_host_replace success success "-"
ulog web_host_replace "$AST" "$PTR" "$ZOT" "$READY" > "$WORK/fx/log.9001"
run 3 TRANSIENT "a missing startedAt on a success job reads TRANSIENT"
# AC-4: designed absence — a trail step skipped (plan_only) or absent from the
# jobs JSON keeps today's continue posture: NOT YET, no tripwire.
reset_fx; echo 900 > "$WORK/fx/list"; job 900 9001 web_host_replace success skipped
run 2 "NOT YET" "a skipped trail step is a designed absence, not a degraded channel"
reset_fx; echo 900 > "$WORK/fx/list"
printf '{"jobs":[{"databaseId":1,"name":"preflight","conclusion":"success"},{"databaseId":9001,"name":"web_host_replace","conclusion":"success","steps":[{"name":"Post job cleanup","conclusion":"success","startedAt":"%s","completedAt":"%s"}]}]}\n' "$AST" "$AST" > "$WORK/fx/jobs.900"
run 2 "NOT YET" "a run predating the trail step (absent from jobs JSON) is a designed absence"
# AC-5: the recovered region passes through the SAME emitted-vs-echoed filter —
# an ANSI-echoed ready copy inside the region derives no boot (success job:
# pointer+zot emitted, ready echoed -> inconclusive), and an ANSI-only region
# on a failure job credits nothing either.
reset_fx; echo 900 > "$WORK/fx/list"; job 900 9001 web_host_replace success success "$AST"
ulog web_host_replace "$AST" "$PTR" "$ZOT" $'\033[36;1m'"$READY" > "$WORK/fx/log.9001"
run 2 "NOT YET" "an ANSI-echoed ready line inside the recovered region derives no PASS"
reset_fx; echo 900 > "$WORK/fx/list"; job 900 9001 web_host_replace failure success "$AST"
ulog web_host_replace "$AST" $'\033[36;1m'"$PTR" $'\033[36;1m'"$ZOT" $'\033[36;1m'"$READY" > "$WORK/fx/log.9001"
run 2 "NOT YET" "an ANSI-echoed-only region on a failure job credits nothing"
# Matrix row 9 (must-PASS): the trail step as the log's LAST section — the
# region runs to EOF with no bounding header and still grades.
reset_fx; echo 900 > "$WORK/fx/list"; job 900 9001 web_host_replace success success "$AST"
ULOG_NO_BOUND=1 ulog web_host_replace "$AST" "$PTR" "$ZOT" "$READY" > "$WORK/fx/log.9001"
run 0 PASS "trail step as last section grades the EOF-terminated region"
# The patternless (not just empty) trigger: a named-attribution log whose trail
# step emitted lines but no trail-pattern line is the same degraded channel.
reset_fx; echo 900 > "$WORK/fx/list"; job 900 9001 web_host_replace success
{ l 'an unrelated emitted line'; l 'another quiet line'; } > "$WORK/fx/log.9001"
run 3 TRANSIENT "a named-attribution patternless trail on a success job reads TRANSIENT"

rc=0; GH_FX="$WORK/fx" PATH="$BIN:$PATH" bash -x "$PROBE" >/dev/null 2>&1 || rc=$?
[ "$rc" = 78 ] && ok "refuses to run under xtrace (exit 78)" || no "xtrace refusal: rc=$rc"

MIN_CASES=18
if [ $((pass + fail)) -lt "$MIN_CASES" ]; then
  printf 'assertion floor: %d < %d — a case stopped running\n' $((pass + fail)) "$MIN_CASES"; exit 1
fi
echo "=== web-fresh-boot-zot-8651: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
