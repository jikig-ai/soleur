#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2015,SC2034 # SC2016: mutation anchors and grep patterns are literal; SC2015: pass/fail pairs; SC2034: tuple reads
# Suite for scripts/apply-delivery-gap.sh and .github/workflows/apply-delivery-gap-follower.yml
# (plan knowledge-base/project/plans/2026-10-23-feat-apply-delivery-gap-follower-plan.md; tracker #9454).
#
# PROPERTY UNDER TEST. A push to main that matched one of the two apply workflows' path filters and was cancelled
# (never applied) is reported in ONE deduplicated `apply-delivery-gap` issue naming each undelivered push, until a later
# run of the SAME workflow actually applied at that commit or a descendant; the follower never closes the issue or says
# "no gap" on a partial read; and the follower workflow cannot hold secrets, enter an environment, dispatch, or share
# the apply concurrency group.
#
# HOW THE SEAM IS BUILT. `gh` is a PATH shim (fixtures/apply-delivery-gap/shim/gh) that serves reduced SYNTHESIZED
# fixtures, models the real CLI's 404 shape, mutates issues.json on writes, logs every read and write, and REFUSES (exit
# 64) any request shape it was not written for. So the SUT's real api_get code path runs, and the exact read set is
# asserted (no search parameter is ever sent). Fixtures are synthetic (cq-test-fixtures-synthesized-only): invented
# messages, no actors, an example-org/example-repo slug; the replay fixtures reuse the PUBLIC incident run ids and head
# SHAs from the issue record (identifiers of public Actions runs, not payload captures).
#
# GROUPS. S1..S17 scenarios, R1..R4 incident replays, H1/H3/H4/H5 harness rows, W workflow wiring, M the mutation battery
# (MUTANT_FLOOR rows). Sub-case ids are `GROUP:name`; ADG_ONLY=S8:compare404,S2 runs those only.
#
# Knobs (tests only): ADG_ONLY=<ids> run only those groups/sub-cases; ADG_NO_META=1 skip the self-referential groups
# (H1 and M; children set it); ADG_SUT=<path> run against another script copy; ADG_WF=<path> run the wiring leg against
# another workflow copy; ADG_MUT_LOGS=<dir> keep the per-mutant logs there; ADG_PRINT_COUNTS=1 print per-group assertion counts (used to record the floor table).
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# Repo-relative literals: the suite names its SUT and the files it reads by these paths (the orphan census derives the
# suite -> SUT edge from them).
SUT_REL="scripts/apply-delivery-gap.sh"
WF_REL=".github/workflows/apply-delivery-gap-follower.yml"
DEPLOY_WF_REL=".github/workflows/apply-deploy-pipeline-fix.yml"
INFRA_WF_REL=".github/workflows/apply-web-platform-infra.yml"
SUT="${ADG_SUT:-$ROOT/$SUT_REL}"
WF="${ADG_WF:-$ROOT/$WF_REL}"
DEPLOY_WF="$ROOT/$DEPLOY_WF_REL"
INFRA_WF="$ROOT/$INFRA_WF_REL"
FIX="$SCRIPT_DIR/fixtures/apply-delivery-gap"
SELF="$SCRIPT_DIR/apply-delivery-gap-follower.test.sh"

MUTANT_FLOOR=22
# Per-group assertion floors, recorded from the first green full run (ADG_PRINT_COUNTS=1 prints the counts to re-derive
# them). Enforced only on a full run: a group that silently stops asserting reds the suite.
declare -A FLOOR=(
  [H1]=2 [H3]=3 [H3b]=3 [H4]=5 [H5]=5 [M]=24 [R]=22 [REASONS]=1 [S1]=18 [S10]=7 [S11a]=2 [S11b]=2 [S11c]=2 [S11d]=3 [S12a]=4
  [S12b]=5 [S13a]=9 [S13b]=2 [S13c]=2 [S14]=7 [S15]=14 [S16]=5 [S17]=3 [S1live]=1 [S2]=13 [S2b-ahead]=4 [S2b-behind]=4
  [S2b-diverged]=4 [S2b-identical]=4 [S3]=6 [S3c]=4 [S4]=10 [S4c]=3 [S4l]=2 [S4m]=3 [S4n]=4 [S4o]=3 [S4x]=3 [S5]=13
  [S6]=5 [S6d]=2 [S7]=6 [S7a]=40 [S7c]=1 [S7o]=4 [S8a]=9 [S8b]=9 [S8c]=9 [S8d]=9 [S8dg]=29 [S8e]=9 [S8f]=9 [S8g]=9
  [S8h]=9 [S8i]=9 [S8in]=7 [S8m]=48 [S8n]=5 [S8ok]=4 [S8r]=26 [S8t]=3 [S8t2]=10 [S8ti]=9 [S8u]=11 [S9]=23 [S9f]=7 [W]=35
)

ASSERTS=0 passes=0 fails=0 FAILED=()
pass() { passes=$((passes + 1)); ASSERTS=$((ASSERTS + 1)); }
fail() { fails=$((fails + 1)); ASSERTS=$((ASSERTS + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

# Instrument self-test: both verdict helpers must record before anything is trusted.
_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"; _iv_a="$ASSERTS"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) || "$ASSERTS" -ne $((_iv_a + 2)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 2
fi
passes=0; fails=0; FAILED=(); ASSERTS=0

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY\n' >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *) printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
assert_fixture_dir "$FIX"
[[ -d "$FIX/base" && -x "$FIX/shim/gh" ]] || { printf '[FATAL] fixture tree incomplete under %s\n' "$FIX" >&2; exit 2; }
for c in jq python3 timeout xargs; do command -v "$c" >/dev/null 2>&1 || { echo "[FATAL] $c is required" >&2; exit 2; }; done

SANDBOX="$(mktemp -d)" || { echo "[FATAL] mktemp -d failed" >&2; exit 2; }
assert_fixture_dir "$SANDBOX"
# shellcheck disable=SC2329 # invoked through the EXIT/INT/TERM traps
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

t()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
tn() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$d"; else pass "$d"; fi; }
eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (got <$2> want <$3>)"; fi; }
has() { if grep -qF -- "$3" "$2" 2>/dev/null; then pass "$1"; else fail "$1 (missing <$3> in $(basename "$2"))"; fi; }
lacks() { if grep -qF -- "$3" "$2" 2>/dev/null; then fail "$1 (unexpected <$3> in $(basename "$2"))"; else pass "$1"; fi; }
hasre() { if grep -qE -- "$3" "$2" 2>/dev/null; then pass "$1"; else fail "$1 (no match <$3> in $(basename "$2"))"; fi; }

# Positive controls for the verdict-owning helpers (a helper neutered to a no-op must RED the suite).
verdict_helper_controls() {
  local p_orig="$passes" f_orig="$fails" p0 f0 a0="$ASSERTS" n0="${#FAILED[@]}" bad="" tmp="$SANDBOX/vc.txt"
  printf 'abc\n' >"$tmp"
  p0="$passes"; f0="$fails"; { t vc true; } >/dev/null 2>&1; [[ "$passes" -eq $((p0 + 1)) && "$fails" -eq "$f0" ]] || bad="$bad t-pass"
  p0="$passes"; f0="$fails"; { t vc false; } >/dev/null 2>&1; [[ "$fails" -eq $((f0 + 1)) && "$passes" -eq "$p0" ]] || bad="$bad t-fail"
  p0="$passes"; f0="$fails"; { tn vc false; } >/dev/null 2>&1; [[ "$passes" -eq $((p0 + 1)) && "$fails" -eq "$f0" ]] || bad="$bad tn-pass"
  p0="$passes"; f0="$fails"; { tn vc true; } >/dev/null 2>&1; [[ "$fails" -eq $((f0 + 1)) && "$passes" -eq "$p0" ]] || bad="$bad tn-fail"
  p0="$passes"; f0="$fails"; { eq vc same same; } >/dev/null 2>&1; [[ "$passes" -eq $((p0 + 1)) && "$fails" -eq "$f0" ]] || bad="$bad eq-pass"
  p0="$passes"; f0="$fails"; { eq vc one two; } >/dev/null 2>&1; [[ "$fails" -eq $((f0 + 1)) && "$passes" -eq "$p0" ]] || bad="$bad eq-fail"
  p0="$passes"; f0="$fails"; { has vc "$tmp" abc; } >/dev/null 2>&1; [[ "$passes" -eq $((p0 + 1)) && "$fails" -eq "$f0" ]] || bad="$bad has-pass"
  p0="$passes"; f0="$fails"; { has vc "$tmp" xyz; } >/dev/null 2>&1; [[ "$fails" -eq $((f0 + 1)) && "$passes" -eq "$p0" ]] || bad="$bad has-fail"
  p0="$passes"; f0="$fails"; { lacks vc "$tmp" xyz; } >/dev/null 2>&1; [[ "$passes" -eq $((p0 + 1)) && "$fails" -eq "$f0" ]] || bad="$bad lacks-pass"
  p0="$passes"; f0="$fails"; { lacks vc "$tmp" abc; } >/dev/null 2>&1; [[ "$fails" -eq $((f0 + 1)) && "$passes" -eq "$p0" ]] || bad="$bad lacks-fail"
  passes="$p_orig"; fails="$f_orig"; ASSERTS="$a0"; FAILED=("${FAILED[@]:0:$n0}")
  if [[ -n "$bad" ]]; then printf '[FATAL] verdict helper positive control failed:%s\n' "$bad" >&2; exit 2; fi
}
verdict_helper_controls

# want <id>: run this group / sub-case? `S8:compare404` is selected by itself or by its group `S8`.
want() {
  [[ -z "${ADG_ONLY:-}" ]] && return 0
  [[ ",${ADG_ONLY}," == *",$1,"* ]] && return 0
  [[ "$1" == *:* && ",${ADG_ONLY}," == *",${1%%:*},"* ]] && return 0
  return 1
}

declare -A GCOUNT=()
G="" G0=0
grp() { G="$1"; G0="$ASSERTS"; }
gend() {
  GCOUNT[$G]=$((ASSERTS - G0))
  if [[ -z "${ADG_ONLY:-}" ]]; then
    [[ "${GCOUNT[$G]}" -ge 1 ]] || fail "group $G ran no assertion"
    if [[ -n "${FLOOR[$G]:-}" && "${GCOUNT[$G]}" -lt "${FLOOR[$G]}" ]]; then fail "group $G ran ${GCOUNT[$G]} assertions, floor ${FLOOR[$G]}"; fi
  fi
}

# ---- world builders ----------------------------------------------------------------------------------------------------
REPO_SLUG="example-org/example-repo"
NOW_ISO="2026-10-23T12:00:00Z"
TITLE='infra: apply delivery gap - trigger-file change not applied'
DEGRADED_TITLE='infra: apply delivery gap follower degraded'
# sha <N>: 40 hex whose FIRST seven characters are N zero-padded, so the sha7 a row prints is distinguishable
sha() { printf '%07x%033x' "$1" 0; }
ago() { date -u -d "$NOW_ISO - $1 minutes" +%Y-%m-%dT%H:%M:%SZ; }
mkrun() { # id event branch status conclusion|- shaN created updated [started] [message|@null]
  jq -cn --argjson id "$1" --arg ev "$2" --arg br "$3" --arg st "$4" --arg co "$5" --arg sha "$(sha "$6")" --arg cr "$7" --arg up "$8" \
    --arg sd "${9:-$7}" --arg msg "${10-synthetic commit message}" \
    '{id:$id,event:$ev,head_branch:$br,status:$st,conclusion:(if $co=="-" then null else $co end),head_sha:$sha,created_at:$cr,run_started_at:$sd,updated_at:$up,run_attempt:1,head_commit:(if $msg=="@null" then null else {message:$msg} end)}'
}
runs_file() { local f="$1"; shift; printf '%s\n' "$@" | jq -cs '{total_count: length, workflow_runs: .}' >"$f"; }
mkjobs() { local f="$ST/jobs.$1.json" total="$2" x; shift 2; local j=()
  for x in "$@"; do j+=("{\"name\":\"${x%%:*}\",\"conclusion\":\"${x#*:}\"}"); done
  if ((${#j[@]})); then printf '%s\n' "${j[@]}" | jq -cs --argjson t "$total" '{total_count:$t,jobs:.}' >"$f"; else printf '{"total_count":%s,"jobs":[]}\n' "$total" >"$f"; fi; }
mkcmp() { printf '{"status":"%s"}\n' "$3" >"$ST/compare.$(sha "$1").$(sha "$2").json"; }
mkissue() { # number title labels-csv login is_bot [state] [body]
  jq -cn --argjson n "$1" --arg t "$2" --arg l "$3" --arg lg "$4" --argjson bot "$5" --arg s "${6:-open}" --arg b "${7:-stale body}" \
    '{number:$n,title:$t,state:$s,labels:($l|split(",")|map(select(length>0))|map({name:.})),author:{login:$lg,is_bot:$bot},body:$b,comments:[]}'
}
issues_file() { printf '%s\n' "$@" | jq -cs . >"$ST/issues.json"; }
gap_issue() { mkissue "${1:-7}" "$TITLE" "${2:-apply-delivery-gap,action-required,priority/p1-high}" app/github-actions true; }
inj() { # key rc err [out] [count]
  { printf 'rc=%s\nerr=%s\n' "$2" "$3"; [[ -n "${4-}" ]] && printf 'out=%s\n' "$4"; [[ -n "${5-}" ]] && printf 'count=%s\n' "$5"; } >"$ST/fail.$1"
}

CASE="" ST="" SUT_RC=0
mk_case() { # <name> [scenario]
  CASE="$1"; ST="$SANDBOX/$1"; assert_fixture_dir "$ST"
  rm -rf "$ST"; mkdir -p "$ST/bin" "$ST/tmp" "$ST/out" || exit 2
  cp -R "$FIX/base/." "$ST/" || exit 2
  [[ -z "${2-}" ]] || cp -R "$FIX/$2/." "$ST/" || { echo "[FATAL] scenario $2 missing" >&2; exit 2; }
  cp "$FIX/shim/gh" "$ST/bin/gh" && chmod +x "$ST/bin/gh" || exit 2
  : >"$ST/out/reads.log"; : >"$ST/out/actions.log"; : >"$ST/out/refusals.log"
}
reset_logs() { : >"$ST/out/reads.log"; : >"$ST/out/actions.log"; : >"$ST/out/refusals.log"; }

# run_sut [VAR=value ...]: run the SUT with --fixture-dir in the current case.
run_sut() {
  local rc=0
  env -i PATH="$PATH" HOME="$ST" TMPDIR="$ST/tmp" GH_REPO="$REPO_SLUG" GH_TOKEN=synthetic-token GITHUB_RUN_ID=424242 \
    "$@" bash "$SUT" --fixture-dir "$ST" >"$ST/all.txt" 2>&1 || rc=$?
  SUT_RC=$rc
  check_harness
}
check_harness() {
  # H1: a green verdict with zero recorded reads means the harness (or the SUT) did nothing.
  if [[ "$SUT_RC" -eq 0 && ! -s "$ST/out/reads.log" ]]; then fail "H1 vacuous harness: case $CASE exited 0 with zero recorded reads"; fi
  # H4: the shim refused nothing.
  if [[ -s "$ST/out/refusals.log" ]]; then fail "H4 shim refusal in case $CASE: $(head -n 1 "$ST/out/refusals.log")"; else pass "no shim refusal in $CASE"; fi
}
last_line() { tail -n 1 "$ST/all.txt"; }
cnt() { local n; n="$(grep -c -- "$2" "$1" 2>/dev/null)" || true; printf '%s' "${n:-0}"; }
acts() { cnt "$ST/out/actions.log" "^$1"; }
rows() { cnt "$ST/all.txt" '^::notice title=apply-delivery-gap::row '; }
summary() { grep '^::notice::apply_delivery_gap_summary' "$ST/all.txt" | head -n 1; }
body() { printf '%s/out/bodies/%s.md' "$ST" "$1"; }

# expect_fail <reason> <class read|issue>: the failure contract of S8.
expect_fail() {
  local reason="$1" cls="$2"
  eq "[$CASE] rc is exactly 1" "$SUT_RC" 1
  eq "[$CASE] last line is the named error" "$(last_line)" "::error::apply_delivery_gap_${reason}"
  lacks "[$CASE] no summary line" "$ST/all.txt" "apply_delivery_gap_summary"
  lacks "[$CASE] no issue=closed" "$ST/all.txt" "issue=closed"
  eq "[$CASE] the open gap issue is not closed" "$(grep -c '^issue-close 7 ' "$ST/out/actions.log" 2>/dev/null || true)" 0
  eq "[$CASE] the open gap issue is not edited" "$(grep -c '^issue-edit 7 ' "$ST/out/actions.log" 2>/dev/null || true)" 0
  eq "[$CASE] no gap issue is created" "$(grep -c "^issue-create title=${TITLE}" "$ST/out/actions.log" 2>/dev/null || true)" 0
  if [[ "$cls" == "read-repeat" ]]; then
    :
  elif [[ "$cls" == "read" ]]; then
    has "[$CASE] degraded issue recorded" "$ST/out/actions.log" "title=${DEGRADED_TITLE} labels=apply-delivery-gap-degraded,action-required"
  else
    lacks "[$CASE] no degraded issue for an issue-API failure" "$ST/out/actions.log" "title=${DEGRADED_TITLE}"
  fi
  ASSERTED_REASONS+=("$reason")
}
ASSERTED_REASONS=()

# ---- Instrument + harness rows that need no SUT ---------------------------------------------------------------------
if [[ ! -f "$SUT" ]]; then
  printf '[NOTE] SUT %s does not exist yet: every SUT-dependent assertion will fail (RED)\n' "$SUT" >&2
fi

# ---- H5: --self-test in the Check-10 sandbox shape ------------------------------------------------------------------
if want H5; then
  grp H5
  RO="$SANDBOX/ro"; mkdir -p "$RO/scripts"
  [[ -f "$SUT" ]] && cp "$SUT" "$RO/scripts/apply-delivery-gap.sh"
  chmod -R a-w "$RO" 2>/dev/null
  t0=$(date +%s)
  out5="$(env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/var/tmp timeout 15s bash -c "cd '$RO' && bash scripts/apply-delivery-gap.sh --self-test" 2>&1)"; rc5=$?
  t1=$(date +%s)
  eq "H5 self-test prints the ok line" "$out5" "apply_delivery_gap_self_test=ok"
  eq "H5 self-test exits 0" "$rc5" 0
  if [[ $((t1 - t0)) -lt 5 ]]; then pass "H5 self-test under 5 s"; else fail "H5 self-test took $((t1 - t0)) s"; fi
  out5b="$(env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/var/tmp timeout 15s bash "$RO/scripts/apply-delivery-gap.sh" --self-test --extra 2>&1)"; rc5b=$?
  eq "H5 self-test with extra argv is rejected (rc 2)" "$rc5b" 2
  eq "H5 rejected argv names bad_input last" "$(printf '%s\n' "$out5b" | tail -n 1)" "::error::apply_delivery_gap_bad_input"
  chmod -R u+w "$RO" 2>/dev/null
  gend
fi

# ---- H4: the shim refuses what it was not written for -----------------------------------------------------------------
if want H4; then
  grp H4
  mk_case h4
  g() { env -i PATH="$ST/bin:$PATH" bash "$ST/bin/gh" "$@" >/dev/null 2>&1; echo $?; }
  eq "H4 a search parameter on the runs list is refused" "$(g api "repos/$REPO_SLUG/actions/workflows/apply-web-platform-infra.yml/runs?status=cancelled&per_page=100&page=1")" 64
  eq "H4 gh search is refused" "$(g search issues foo)" 64
  eq "H4 an unfiltered issue list is refused" "$(g issue list --state open --limit 5 --json number)" 64
  eq "H4 a --remove-label edit is refused" "$(g issue edit 7 --body-file /dev/null --add-label x --remove-label y)" 64
  eq "H4 refusals are logged" "$(wc -l <"$ST/out/refusals.log" | tr -d ' ')" 4
  gend
fi

# ---- S1: cancelled, zero jobs ------------------------------------------------------------------------------------------
if want S1; then
  grp S1
  mk_case s1 cancelled-zero-jobs
  run_sut
  eq "S1 rc 0 (a filed gap is a green run)" "$SUT_RC" 0
  eq "S1 exactly one row" "$(rows)" 1
  has "S1 row class and sha" "$ST/all.txt" "row workflow=deploy-fix sha=$(sha 0x101) class=evicted-before-start"
  eq "S1 exact read set" "$(cat "$ST/out/reads.log")" "repos/$REPO_SLUG/actions/workflows/apply-deploy-pipeline-fix.yml/runs?per_page=100&page=1
repos/$REPO_SLUG/actions/workflows/apply-web-platform-infra.yml/runs?per_page=100&page=1
repos/$REPO_SLUG/actions/runs/101/jobs?per_page=1
issue-list author=app/github-actions state=open limit=500 json=number,title,labels,author
issue-list author=github-actions[bot] state=open limit=500 json=number,title,labels,author"
  tn "S1 no search parameter in any read" grep -E '(status|event|branch|created)=' "$ST/out/reads.log"
  eq "S1 actions: a label create then one issue create" "$(cut -d' ' -f1,2 "$ST/out/actions.log" | sed 's/ title=.*//' | paste -sd'|')" "label-create apply-delivery-gap|issue-create"
  has "S1 issue create labels" "$ST/out/actions.log" "title=${TITLE} labels=apply-delivery-gap,action-required,priority/p1-high body="
  lacks "S1 no p0 on an evicted row" "$ST/out/actions.log" "priority/p0-critical"
  B="$(body 1)"
  hasre "S1 body carries the 40-hex sha" "$B" "$(sha 0x101)"
  has "S1 body carries the run URL" "$B" "https://github.com/$REPO_SLUG/actions/runs/101"
  has "S1 body carries the class" "$B" "evicted-before-start"
  has "S1 body minutes since cancel" "$B" "| 179 |"
  has "S1 a row with no later run renders the none cell after the minutes cell" "$B" "| evicted-before-start | 179 | none |"
  tn "S1 no created-epoch digits land in the later-run cell" grep -E 'actions/runs/[0-9]{10}\)' "$B"
  has "S1 the later-run column header says it is not proof of delivery" "$B" "| Latest later run (any outcome; not proof of delivery) |"
  lacks "S1 no dropped-by-kill-switch line when nothing was dropped" "$B" "Dropped by kill switch"
  cmdline="$(grep '^gh workflow run ' "$B")"
  hasre "S1 printed command shape" <(printf '%s\n' "$cmdline") "^gh workflow run [a-z0-9.-]+\.yml --ref main( -f [a-z_]+=[a-z-]+)* -f reason='apply-delivery-gap [0-9a-f]{7}'$"
  has "S1 printed command names the deploy-fix file and sha7" <(printf '%s\n' "$cmdline") "gh workflow run apply-deploy-pipeline-fix.yml --ref main -f reason='apply-delivery-gap 0000101'"
  tn "S1 body has no closing keyword next to a number" grep -qiE '(close[sd]?|fix(e[sd])?|resolve[sd]?)[: ]+#?[0-9]' "$B"
  tn "S1 body references no issue number" grep -qE '(^|[^&/a-z0-9])#[0-9]+' "$B"
  has "S1 summary: mode fixture, workflows_read" <(summary) "mode=fixture workflows_read=2 candidates=1 rows=1"
  gend
fi

# printed commands are cross-checked against the live workflow files (S1:live)
if want S1:live; then
  grp S1live
  py="$SANDBOX/s1live.py"
  cat >"$py" <<'PY'
import sys, yaml
root = sys.argv[1]
ok = True
def load(f):
    return yaml.safe_load(open(f))
for f, extra in (("apply-deploy-pipeline-fix.yml", None), ("apply-web-platform-infra.yml", "manual-rerun")):
    doc = load(root + "/.github/workflows/" + f)
    on = doc.get("on", doc.get(True))
    inputs = on["workflow_dispatch"]["inputs"]
    if not inputs["reason"].get("required"):
        print("FAIL reason is not required in " + f); ok = False
    if extra and extra not in inputs["apply_target"]["options"]:
        print("FAIL manual-rerun is not an apply_target option"); ok = False
print("OK" if ok else "BAD")
PY
  eq "S1 the printed dispatch inputs exist in the live apply workflows" "$(python3 -I "$py" "$ROOT" 2>&1 | tail -n 1)" OK
  gend
fi

# ---- S2 / S2b: delivered by a later descendant success -----------------------------------------------------------------
if want S2; then
  grp S2
  mk_case s2 cancelled-then-later-success-descendant
  run_sut
  eq "S2 rc 0" "$SUT_RC" 0
  eq "S2 no rows" "$(rows)" 0
  eq "S2 exactly one close" "$(acts issue-close)" 1
  has "S2 close reason completed" "$ST/out/actions.log" "issue-close 7 reason=completed comment="
  has "S2 close comment lists sha7" "$ST/out/actions.log" "0000201"
  has "S2 close comment lists the DELIVERING run id (not the earlier non-descendant)" "$ST/out/actions.log" "delivered by run 203, 63 minutes"
  eq "S2 no create" "$(acts issue-create)" 0
  eq "S2 no edit" "$(acts issue-edit)" 0
  has "S2 the earlier non-descendant was compared" "$ST/out/reads.log" "compare/$(sha 0x201)...$(sha 0x202)"
  lacks "S2 jobs of a non-descendant are never read" "$ST/out/reads.log" "runs/202/jobs"
  has "S2 apply-job leg read for the delivering run" "$ST/out/reads.log" "runs/203/jobs?per_page=100"
  has "S2 summary delivered=1 issue=closed" <(summary) "delivered=1 dropped=0 mid_run=0 inflight=0 issue=closed"
  gend
fi
for st in behind diverged identical ahead; do
  if want "S2b:$st"; then
    grp "S2b-$st"
    mk_case "s2b-$st" cancelled-then-later-success-descendant
    runs_file "$ST/runs.deploy-fix.json" \
      "$(mkrun 203 workflow_dispatch main completed success 0x203 2026-10-22T09:00:00Z 2026-10-22T09:04:00Z)" \
      "$(mkrun 201 push main completed cancelled 0x201 2026-10-22T08:00:00Z 2026-10-22T08:00:03Z)"
    mkcmp 0x201 0x203 "$st"; mkjobs 201 0
    run_sut
    eq "S2b[$st] rc 0" "$SUT_RC" 0
    if [[ "$st" == "behind" || "$st" == "diverged" ]]; then
      eq "S2b[$st] not a descendant: the row stays" "$(rows)" 1
      eq "S2b[$st] no close" "$(acts issue-close)" 0
    else
      eq "S2b[$st] a descendant: delivered" "$(rows)" 0
      eq "S2b[$st] closes" "$(acts issue-close)" 1
    fi
    gend
  fi
done

# ---- S3: cancelled with jobs (mid-run) --------------------------------------------------------------------------------
if want S3; then
  grp S3
  mk_case s3 cancelled-with-jobs
  run_sut
  eq "S3 rc 0" "$SUT_RC" 0
  has "S3 class" "$ST/all.txt" "class=cancelled-mid-run"
  has "S3 p0 label on create" "$ST/out/actions.log" "labels=apply-delivery-gap,action-required,priority/p1-high,priority/p0-critical"
  has "S3 body warns not to dispatch before reading the run" "$(body 1)" "do NOT dispatch before reading the run"
  has "S3 summary mid_run=1" <(summary) "mid_run=1"
  gend
fi
if want S3c; then
  grp S3c
  mk_case s3c cancelled-with-jobs
  runs_file "$ST/runs.deploy-fix.json" \
    "$(mkrun 302 push main completed failure 0x302 2026-10-23T10:30:00Z 2026-10-23T10:40:00Z)" \
    "$(mkrun 301 push main completed cancelled 0x301 2026-10-23T10:00:00Z 2026-10-23T10:12:00Z)"
  run_sut
  eq "S3c rc 0" "$SUT_RC" 0
  eq "S3c the row stays" "$(rows)" 1
  has "S3c later run cell shows the failed run and its URL" "$(body 1)" "[302](https://github.com/$REPO_SLUG/actions/runs/302) failure"
  gend
fi

# ---- S4: kill switch --------------------------------------------------------------------------------------------------
if want S4; then
  grp S4
  mk_case s4 cancelled-killswitch
  run_sut
  eq "S4 rc 0" "$SUT_RC" 0
  eq "S4 two rows (one per workflow) beside three dropped" "$(rows)" 2
  has "S4 deploy-fix qualifying row" "$ST/all.txt" "row workflow=deploy-fix sha=$(sha 0x405) "
  has "S4 infra row carrying ONLY the deploy-fix marker is NOT dropped" "$ST/all.txt" "row workflow=infra sha=$(sha 0x411) "
  has "S4 own-line marker dropped" "$ST/all.txt" "dropped killswitch workflow=deploy-fix sha=0000401"
  has "S4 middle-line marker dropped" "$ST/all.txt" "dropped killswitch workflow=deploy-fix sha=0000402"
  has "S4 infra own marker dropped" "$ST/all.txt" "dropped killswitch workflow=infra sha=0000410"
  has "S4 summary dropped=3" <(summary) "dropped=3"
  eq "S4 the dropped count is rendered right after the skip-marker footer line" "$(grep -A1 'never appears here' "$(body 1)" | tail -n 1)" "- Dropped by kill switch (not a gap): 3"
  # table completeness: every WATCHED row names a kill-switch function that the script defines
  ok=1; n=0
  while IFS='|' read -r _ _ _ ks _; do
    n=$((n + 1)); grep -qE "^${ks}\(\) \{" "$SUT" 2>/dev/null || ok=0
  done < <(grep -E '^  "[a-z-]+\|[a-z0-9.-]+\.yml\|' "$SUT" 2>/dev/null | tr -d '" ')
  [[ "$ok" -eq 1 && "$n" -ge 2 ]] && pass "S4 every WATCHED key has a defined kill-switch function ($n)" || fail "S4 a WATCHED key has no kill-switch function (n=$n)"
  gend
fi
s4_one() { # <name> <message|@null> <expected rows> [workflow key]
  mk_case "s4-$1"
  local wf="${4:-deploy-fix}"
  runs_file "$ST/runs.$wf.json" "$(mkrun 450 push main completed cancelled 0x450 2026-10-23T09:00:00Z 2026-10-23T09:00:02Z 2026-10-23T09:00:00Z "$2")"
  mkjobs 450 0
  run_sut
  eq "S4[$1] rc 0" "$SUT_RC" 0
  eq "S4[$1] rows" "$(rows)" "$3"
}
if want S4:midline; then grp S4m; s4_one midline 'chore [skip-deploy-fix-apply] trailing words' 1; gend; fi
if want S4:crlf; then grp S4c; s4_one crlf $'subject\r\n[skip-deploy-fix-apply]\r\nbody' 1; gend; fi
if want S4:null; then grp S4n; s4_one null '@null' 1; lacks "S4[null] no crash message" "$ST/all.txt" "jq:"; gend; fi
if want S4:own-line; then grp S4o; s4_one ownline $'subject\n[skip-deploy-fix-apply]' 0; gend; fi
if want S4:infra-cross; then grp S4x; s4_one cross $'subject\n[skip-web-platform-apply]' 1 deploy-fix; gend; fi
if want S4:later-marker; then
  grp S4l
  mk_case s4-later
  runs_file "$ST/runs.deploy-fix.json" \
    "$(mkrun 452 push main completed success 0x452 2026-10-23T10:00:00Z 2026-10-23T10:05:00Z 2026-10-23T10:00:00Z $'later\n[skip-deploy-fix-apply]')" \
    "$(mkrun 451 push main completed cancelled 0x451 2026-10-23T09:00:00Z 2026-10-23T09:00:02Z)"
  mkcmp 0x451 0x452 ahead; mkjobs 451 0; mkjobs 452 3 preflight:success apply:skipped
  run_sut
  eq "S4[later-marker] a kill-switched later success (apply skipped) does not deliver the earlier push" "$(rows)" 1
  gend
fi

# ---- S5: success only -------------------------------------------------------------------------------------------------
if want S5; then
  grp S5
  mk_case s5 success-only
  run_sut
  eq "S5 rc 0" "$SUT_RC" 0
  eq "S5 no rows" "$(rows)" 0
  tn "S5 no jobs or compare read" grep -E 'jobs|compare' "$ST/out/reads.log"
  has "S5 workflows_read=2 (anti-vacuity)" <(summary) "workflows_read=2 candidates=0"
  eq "S5 an open issue with delivered==0 is NOT closed" "$(acts issue-close)" 0
  eq "S5 exactly one aged-out marker comment" "$(acts issue-comment)" 1
  has "S5 marker text" "$ST/out/actions.log" "apply-delivery-gap:aged-out"
  has "S5 summary issue=aged-out-comment" <(summary) "issue=aged-out-comment"
  reset_logs; run_sut
  eq "S5 a second reconcile adds no second comment" "$(acts issue-comment)" 0
  mk_case s5b success-only; printf '[]\n' >"$ST/issues.json"
  run_sut
  eq "S5 with no issue there is no write at all" "$(wc -l <"$ST/out/actions.log" | tr -d ' ')" 0
  gend
fi

# ---- S6: non-candidates -----------------------------------------------------------------------------------------------
if want S6; then
  grp S6
  mk_case s6 non-push-or-non-main
  run_sut
  eq "S6 rc 0" "$SUT_RC" 0
  eq "S6 only the one qualifying cancelled push is a row (dispatch, other branch, schedule, 8 days old, failure kinds are not)" "$(rows)" 1
  has "S6 the qualifying row" "$ST/all.txt" "row workflow=deploy-fix sha=$(sha 0x608) "
  has "S6 summary candidates=1" <(summary) "candidates=1 rows=1"
  gend
fi
if want S6:dup; then
  grp S6d
  mk_case s6-dup
  runs_file "$ST/runs.deploy-fix.json" \
    "$(mkrun 611 workflow_dispatch main completed cancelled 0x609 2026-10-23T09:05:00Z 2026-10-23T09:05:02Z)" \
    "$(mkrun 610 push main completed cancelled 0x609 2026-10-23T09:00:00Z 2026-10-23T09:00:02Z)"
  mkjobs 610 0
  run_sut
  eq "S6 a cancelled push plus a cancelled dispatch on the same sha is ONE row" "$(rows)" 1
  gend
fi

# ---- S7: in-flight descendants ------------------------------------------------------------------------------------------
if want S7; then
  grp S7
  mk_case s7 inflight-descendant
  run_sut
  eq "S7 rc 0" "$SUT_RC" 0
  eq "S7 deferred, so no row" "$(rows)" 0
  has "S7 deferred notice" "$ST/all.txt" "::notice::apply_delivery_gap_deferred workflow=deploy-fix sha=0000701"
  eq "S7 an open issue is NOT closed" "$(acts issue-close)" 0
  has "S7 summary deferred=1 inflight=1" <(summary) "deferred=1 delivered=0 dropped=0 mid_run=0 inflight=1"
  gend
fi
s7_one() { # <wf> <status> <age-min> <expect deferred 1|0> [started-age]
  local wf="$1" st="$2" age="$3" want_def="$4" sage="${5:-$3}" c
  mk_case "s7-$wf-$st-$age"
  runs_file "$ST/runs.$wf.json" \
    "$(mkrun 702 workflow_dispatch main "$st" - 0x702 "$(ago "$age")" "$(ago "$age")" "$(ago "$sage")")" \
    "$(mkrun 701 push main completed cancelled 0x701 "$(ago 300)" "$(ago 299)")"
  mkcmp 0x701 0x702 ahead; mkjobs 701 0
  issues_file "$(gap_issue 7)"
  run_sut
  eq "S7[$wf $st ${age}m] rc 0" "$SUT_RC" 0
  c="$(cnt "$ST/all.txt" '::notice::apply_delivery_gap_deferred')"
  eq "S7[$wf $st ${age}m] deferred" "$c" "$want_def"
  eq "S7[$wf $st ${age}m] rows" "$(rows)" "$((1 - want_def))"
}
if want S7:ages; then
  grp S7a
  s7_one deploy-fix queued 30 1;  s7_one deploy-fix pending 30 1; s7_one deploy-fix requested 30 1
  s7_one deploy-fix waiting 30 1; s7_one deploy-fix waiting 61 0
  s7_one deploy-fix queued 149 1; s7_one deploy-fix queued 151 0
  s7_one deploy-fix in_progress 100 1 100
  s7_one infra queued 119 1; s7_one infra queued 121 0
  gend
fi
if want S7:otherwf; then
  grp S7o
  mk_case s7-other cancelled-then-later-success-descendant
  runs_file "$ST/runs.infra.json" "$(mkrun 780 push main in_progress - 0x780 "$(ago 10)" "$(ago 10)" "$(ago 10)")"
  run_sut
  eq "S7 delivered candidate, rows" "$(rows)" 0
  eq "S7 an in-flight run of the OTHER workflow blocks the close" "$(acts issue-close)" 0
  has "S7 summary inflight=1 delivered=1" <(summary) "delivered=1 dropped=0 mid_run=0 inflight=1"
  gend
fi
if want S7:caps; then
  grp S7c
  py="$SANDBOX/s7caps.py"
  cat >"$py" <<'PY'
import re, sys, yaml
root, sut = sys.argv[1], sys.argv[2]
src = open(sut).read()
bad = []
for key, f in (("deploy-fix", "apply-deploy-pipeline-fix.yml"), ("infra", "apply-web-platform-infra.yml")):
    doc = yaml.safe_load(open(root + "/.github/workflows/" + f))
    timeout = doc["jobs"]["apply"]["timeout-minutes"]
    m = re.search(r'"%s\|%s\|[^|]*\|[a-z_]+\|([0-9]+)"' % (re.escape(key), re.escape(f)), src)
    if not m:
        bad.append("no WATCHED row for " + key); continue
    if not int(m.group(1)) > timeout:
        bad.append("cap %s <= apply timeout %s for %s" % (m.group(1), timeout, key))
print("OK" if not bad else "; ".join(bad))
PY
  eq "S7 each stale cap exceeds the workflow's apply timeout-minutes" "$(python3 -I "$py" "$ROOT" "$SUT" 2>&1 | tail -n 1)" OK
  gend
fi

# ---- S8: failure contract ----------------------------------------------------------------------------------------------
s8_world() { mk_case "$1" api-failure; }
s8_case() { # <name> <reason> <class> <injection key> <rc> <err> [out] [count]
  s8_world "s8-$1"
  inj "$4" "$5" "$6" "${7-}" "${8-}"
  run_sut
  expect_fail "$2" "$3"
}
if want S8:ok; then
  grp S8ok
  s8_world s8-ok; run_sut
  eq "S8 control: the unbroken world is green" "$SUT_RC" 0
  eq "S8 control: the open issue is refreshed once" "$(acts issue-edit)" 1
  has "S8 control: 801 is the row, 803 delivered by 802" <(summary) "candidates=2 rows=1 deferred=0 delivered=1"
  gend
fi
if want S8:runs-p1; then grp S8a; s8_case runs-p1 runs_list_failed read runs.deploy-fix.p1 1 'gh: Server Error (HTTP 500)'; gend; fi
if want S8:runs-p2; then
  grp S8b
  mk_case s8-runs-p2
  runs_file "$ST/runs.deploy-fix.json" "$(mkrun 810 push main completed success 0x810 2026-10-23T08:00:00Z 2026-10-23T08:04:00Z)"
  runs_file "$ST/runs.infra.json" "$(mkrun 811 push main completed success 0x811 2026-10-23T08:00:00Z 2026-10-23T08:04:00Z)" "$(mkrun 812 push main completed success 0x812 2026-10-23T07:00:00Z 2026-10-23T07:04:00Z)"
  issues_file "$(gap_issue 7)"
  inj runs.infra.p2 1 'gh: Bad Gateway (HTTP 502)'
  run_sut APPLY_DELIVERY_GAP_PAGE_SIZE=2 APPLY_DELIVERY_GAP_MAX_PAGES=3
  expect_fail runs_list_failed read
  gend
fi
if want S8:jobs-class; then grp S8c; s8_case jobs-class jobs_read_failed read jobs.801 1 'gh: Server Error (HTTP 500)'; gend; fi
if want S8:jobs-apply; then grp S8d; s8_case jobs-apply jobs_read_failed read jobs.802 1 'gh: Server Error (HTTP 500)'; gend; fi
if want S8:compare-5xx; then grp S8e; s8_case compare-5xx compare_failed read "compare.$(sha 0x801).$(sha 0x802)" 1 'gh: Bad Gateway (HTTP 502)'; gend; fi
if want S8:compare-hostile; then
  grp S8f
  s8_case compare-hostile compare_failed read "compare.$(sha 0x801).$(sha 0x802)" 1 'gh: this text mentions 404 Not Found but the status is (HTTP 403)'
  gend
fi
if want S8:issue-list; then grp S8g; s8_case issue-list issue_list_failed issue issue-list 1 'gh: Server Error (HTTP 500)'; gend; fi
if want S8:issue-edit; then grp S8h; s8_case issue-edit issue_write_failed issue issue-edit 1 'gh: Server Error (HTTP 500)'; gend; fi
if want S8:label-create; then grp S8i; s8_case label-create label_failed issue label-create 1 'gh: Server Error (HTTP 500)'; gend; fi
if want S8:malformed; then
  grp S8m
  s8_world s8-mal-notarray; printf '{"total_count":1,"workflow_runs":"x"}\n' >"$ST/runs.deploy-fix.json"; run_sut; expect_fail malformed_response read
  s8_world s8-mal-sha
  runs_file "$ST/runs.deploy-fix.json" "$(mkrun 801 push main completed cancelled 0x801 2026-10-23T09:00:00Z 2026-10-23T09:00:02Z | jq -c '.head_sha="xyz"')"
  run_sut; expect_fail malformed_response read
  s8_world s8-mal-created
  runs_file "$ST/runs.deploy-fix.json" "$(mkrun 801 push main completed cancelled 0x801 2026-10-23T09:00:00Z 2026-10-23T09:00:02Z | jq -c '.created_at="yesterday"')"
  run_sut; expect_fail malformed_response read
  s8_world s8-mal-jobs; printf '{"total_count":"x","jobs":[]}\n' >"$ST/jobs.801.json"; run_sut; expect_fail malformed_response read
  s8_world s8-mal-compare; printf '{"message":"no status here"}\n' >"$ST/compare.$(sha 0x803).$(sha 0x802).json"; run_sut; expect_fail malformed_response read
  # an irrelevant malformed record (a failure run with a bad sha) is skipped with one warning, not fatal
  s8_world s8-mal-irrelevant
  runs_file "$ST/runs.infra.json" "$(mkrun 899 push main completed failure 0x899 2026-10-23T05:00:00Z 2026-10-23T05:10:00Z | jq -c '.head_sha="bad"')"
  run_sut
  eq "S8 an irrelevant malformed record does not abort" "$SUT_RC" 0
  has "S8 and is reported once as a warning" "$ST/all.txt" "::warning::apply_delivery_gap_skipped_malformed_records workflow=infra"
  gend
fi
if want S8:compare404; then
  grp S8n
  s8_world s8-c404
  inj "compare.$(sha 0x801).$(sha 0x802)" 1 'gh: Not Found (HTTP 404)' '{"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}'
  run_sut
  eq "S8 a compare 404 is not an error (rc 0)" "$SUT_RC" 0
  has "S8 and is a warning" "$ST/all.txt" "::warning::apply_delivery_gap_compare_unresolvable sha=0000801"
  eq "S8 the row for that sha stays (not read as delivered)" "$(rows)" 1
  has "S8 row is 801" "$ST/all.txt" "row workflow=deploy-fix sha=$(sha 0x801) "
  gend
fi
if want S8:retry; then
  grp S8r
  s8_world s8-retry-1; inj runs.deploy-fix.p1 1 'gh: Bad Gateway (HTTP 502)' '' 1; run_sut
  eq "S8 one transient 502 then success is green" "$SUT_RC" 0
  eq "S8 and still acts" "$(acts issue-edit)" 1
  eq "S8 the runs page was read twice" "$(cnt "$ST/out/reads.log" 'apply-deploy-pipeline-fix.yml/runs')" 2
  s8_world s8-retry-2; inj jobs.801 1 'gh: API rate limit exceeded for installation (HTTP 403)' '' 2; run_sut
  eq "S8 two rate-limited 403s then success is green" "$SUT_RC" 0
  s8_world s8-retry-3; inj runs.deploy-fix.p1 1 'gh: Bad Gateway (HTTP 502)' '' 3; run_sut
  expect_fail runs_list_failed read
  eq "S8 three failures made exactly three attempts" "$(cnt "$ST/out/reads.log" 'apply-deploy-pipeline-fix.yml/runs')" 3
  s8_world s8-retry-4; inj jobs.801 1 'gh: Unprocessable Entity (HTTP 422)' '' 1; run_sut
  expect_fail jobs_read_failed read
  eq "S8 a 422 is never retried" "$(cnt "$ST/out/reads.log" 'runs/801/jobs')" 1
  gend
fi
if want S8:budget; then
  grp S8u
  mk_case s8-budget
  objs=(); { for i in $(seq 1 151); do objs+=("$(mkrun $((2000 + i)) push main completed success $((0x3000 + i)) "$(ago $((200 - i)))" "$(ago $((199 - i)))")"); mkcmp 0x2000 $((0x3000 + i)) behind; done; }
  objs+=("$(mkrun 2000 push main completed cancelled 0x2000 "$(ago 300)" "$(ago 299)")")
  runs_file "$ST/runs.deploy-fix.json" "${objs[@]}"; mkjobs 2000 0
  issues_file "$(gap_issue 7)"
  run_sut APPLY_DELIVERY_GAP_PAGE_SIZE=1000
  expect_fail api_budget_exceeded read
  # 150 reads is within the budget
  mk_case s8-budget-ok
  objs=(); for i in $(seq 1 149); do objs+=("$(mkrun $((2000 + i)) push main completed success $((0x3000 + i)) "$(ago $((200 - i)))" "$(ago $((199 - i)))")"); mkcmp 0x2000 $((0x3000 + i)) behind; done
  objs+=("$(mkrun 2000 push main completed cancelled 0x2000 "$(ago 300)" "$(ago 299)")")
  runs_file "$ST/runs.deploy-fix.json" "${objs[@]}"; mkjobs 2000 0
  run_sut APPLY_DELIVERY_GAP_PAGE_SIZE=1000
  eq "S8 149 compares plus one jobs read (150 reads) is within budget" "$SUT_RC" 0
  gend
fi
if want S8:trigger; then
  grp S8t
  mk_case s8-trigger-late
  runs_file "$ST/runs.deploy-fix.json" "$(mkrun 900 push main in_progress - 0x900 "$(ago 5)" "$(ago 4)")"
  runs_file "$ST/runs.deploy-fix.r2.json" "$(mkrun 900 push main completed success 0x900 "$(ago 5)" "$(ago 1)")"
  run_sut TRIGGER_RUN_ID=900
  eq "S8 trigger run in_progress on attempt 1 and completed on attempt 2: proceeds" "$SUT_RC" 0
  eq "S8 both workflows were re-read" "$(cnt "$ST/out/reads.log" 'apply-deploy-pipeline-fix.yml/runs')" 2
  gend
  grp S8t2
  mk_case s8-trigger-never
  runs_file "$ST/runs.deploy-fix.json" "$(mkrun 900 push main in_progress - 0x900 "$(ago 5)" "$(ago 4)")"
  issues_file "$(gap_issue 7)"
  run_sut TRIGGER_RUN_ID=900
  expect_fail trigger_run_not_visible read
  eq "S8 three attempts" "$(cnt "$ST/out/reads.log" 'apply-deploy-pipeline-fix.yml/runs')" 3
  gend
fi
if want S8:trigger-invisible; then
  grp S8ti
  mk_case s8-trigger-never2
  runs_file "$ST/runs.deploy-fix.json" "$(mkrun 900 push main in_progress - 0x900 "$(ago 5)" "$(ago 4)")"
  issues_file "$(gap_issue 7)"
  run_sut TRIGGER_RUN_ID=900
  expect_fail trigger_run_not_visible read
  gend
fi
if want S8:degraded; then
  grp S8dg
  s8_world s8-deg-new; inj runs.deploy-fix.p1 1 'gh: Server Error (HTTP 500)'; run_sut
  expect_fail runs_list_failed read
  B="$(body 1)"
  has "S8 degraded body names the reason" "$B" "Reason: apply_delivery_gap_runs_list_failed"
  has "S8 degraded body links the run" "$B" "Run: https://github.com/$REPO_SLUG/actions/runs/424242"
  has "S8 the degraded label is created first" "$ST/out/actions.log" "label-create apply-delivery-gap-degraded"
  # a repeat comments on the existing degraded issue
  s8_world s8-deg-repeat
  issues_file "$(gap_issue 7)" "$(mkissue 9 "$DEGRADED_TITLE" apply-delivery-gap-degraded,action-required app/github-actions true)"
  inj runs.deploy-fix.p1 1 'gh: Server Error (HTTP 500)'; run_sut
  expect_fail runs_list_failed read-repeat
  has "S8 a repeat comments on the degraded issue" "$ST/out/actions.log" "issue-comment 9 body="
  eq "S8 and creates no second degraded issue" "$(grep -c "^issue-create" "$ST/out/actions.log" 2>/dev/null || true)" 0
  # a failing upsert is its own named error, after the original
  s8_world s8-deg-fail; inj runs.deploy-fix.p1 1 'gh: Server Error (HTTP 500)'; printf 'rc=1\nerr=gh: Server Error (HTTP 500)\n' >"$ST/fail.issue-create"; run_sut
  eq "S8 failing upsert: rc 1" "$SUT_RC" 1
  eq "S8 failing upsert: degraded_upsert_failed is last" "$(last_line)" "::error::apply_delivery_gap_degraded_upsert_failed"
  has "S8 failing upsert: the original reason is also printed" "$ST/all.txt" "::error::apply_delivery_gap_runs_list_failed"
  ASSERTED_REASONS+=(degraded_upsert_failed)
  # the next complete reconcile closes the degraded issue
  s8_world s8-deg-close
  issues_file "$(gap_issue 7)" "$(mkissue 9 "$DEGRADED_TITLE" apply-delivery-gap-degraded,action-required app/github-actions true)"
  run_sut
  eq "S8 a complete reconcile is green" "$SUT_RC" 0
  has "S8 and closes the degraded issue" "$ST/out/actions.log" "issue-close 9 reason=completed"
  gend
fi
if want S8:input; then
  grp S8in
  mk_case s8-input
  bad() { local rc=0; env -i PATH="$PATH" HOME="$ST" TMPDIR="$ST/tmp" "$@" >"$ST/all.txt" 2>&1 || rc=$?; SUT_RC=$rc; }
  bad GH_REPO="not a repo" bash "$SUT" --fixture-dir "$ST"
  eq "S8 bad GH_REPO: rc 2" "$SUT_RC" 2; eq "S8 bad GH_REPO: named" "$(last_line)" "::error::apply_delivery_gap_bad_input"
  bad GH_REPO="$REPO_SLUG" bash "$SUT" --bogus
  eq "S8 unknown argv: rc 2" "$SUT_RC" 2; eq "S8 unknown argv: named" "$(last_line)" "::error::apply_delivery_gap_bad_input"
  bad GH_REPO="$REPO_SLUG" bash "$SUT" --fixture-dir relative/dir
  eq "S8 relative fixture dir: rc 2" "$SUT_RC" 2
  bad GH_REPO="$REPO_SLUG" TRIGGER_RUN_ID=12ab bash "$SUT" --fixture-dir "$ST"
  eq "S8 non-digit TRIGGER_RUN_ID: rc 2" "$SUT_RC" 2
  bad GH_REPO="$REPO_SLUG" GITHUB_RUN_ID='1 2' bash "$SUT" --fixture-dir "$ST"
  eq "S8 non-digit GITHUB_RUN_ID: rc 2" "$SUT_RC" 2
  ASSERTED_REASONS+=(bad_input)
  gend
fi

# ---- S9: identity and dedup ---------------------------------------------------------------------------------------------
if want S9; then
  grp S9
  mk_case s9 dedup
  run_sut
  eq "S9 rc 0" "$SUT_RC" 0
  eq "S9 exactly one edit" "$(acts issue-edit)" 1
  eq "S9 no create" "$(acts issue-create)" 0
  has "S9 edit re-asserts the label and action-required" "$ST/out/actions.log" "issue-edit 7 body=bodies/1.md add-labels=apply-delivery-gap,action-required"
  lacks "S9 p1 is added at create only" "$ST/out/actions.log" "priority/p1-high"
  lacks "S9 no p0 without a mid-run row" "$ST/out/actions.log" "priority/p0-critical"
  tn "S9 no remove-label anywhere" grep -F -e '--remove-label' "$ST/out/actions.log"
  eq "S9 two rows in the body" "$(grep -c '^| Deploy-pipeline\|^| Apply deploy-pipeline-fix' "$(body 1)")" 2
  # same input again: again exactly one edit, same rows
  reset_logs; run_sut
  eq "S9 again: exactly one edit" "$(acts issue-edit)" 1
  eq "S9 again: the same body" "$(cat "$(body 2)")" "$(cat "$(body 1)")"
fi
if want S9; then
  # the label removed from the open issue: the SAME issue is edited, no create
  mk_case s9-nolabel dedup; issues_file "$(mkissue 7 "$TITLE" "" app/github-actions true)"
  run_sut
  eq "S9 label removed: still one edit of #7" "$(acts 'issue-edit 7')" 1
  eq "S9 label removed: no create" "$(acts issue-create)" 0
  # only a CLOSED issue exists -> a new issue is created
  mk_case s9-closed dedup; issues_file "$(mkissue 7 "$TITLE" apply-delivery-gap app/github-actions true closed)"
  run_sut
  eq "S9 only a closed issue: a new issue is created" "$(acts issue-create)" 1
  # open issue already carrying p0 with only p1 rows: the edit has no remove and no p0
  mk_case s9-p0 dedup; issues_file "$(mkissue 7 "$TITLE" apply-delivery-gap,priority/p0-critical app/github-actions true)"
  run_sut
  lacks "S9 p0 is never removed" "$ST/out/actions.log" "remove"
  # two matching bot issues: lowest refreshed, extras closed as not planned with a pointer
  mk_case s9-two dedup; issues_file "$(gap_issue 8)" "$(gap_issue 7)"
  run_sut
  eq "S9 two matches: the lowest is edited" "$(acts 'issue-edit 7 ')" 1
  eq "S9 two matches: the other is not edited" "$(acts 'issue-edit 8 ')" 0
  has "S9 two matches: the extra is closed not planned with a pointer" "$ST/out/actions.log" "issue-close 8 reason=not planned comment=Duplicate of #7"
  gend
fi
if want S9:foreign-title; then
  grp S9f
  # a bot-authored issue with a DIFFERENT title (even carrying our label) is not ours
  mk_case s9-foreign dedup
  issues_file "$(mkissue 5 'merge-queue stall: PR pending' apply-delivery-gap,action-required app/github-actions true)"
  run_sut
  eq "S9 a differently titled bot issue is never edited" "$(acts 'issue-edit 5 ')" 0
  eq "S9 and a fresh issue is created" "$(acts issue-create)" 1
  # a human-authored issue with the same title, returned by a lax author match, is never touched
  mk_case s9-human dedup; : >"$ST/lax-author"
  issues_file "$(mkissue 5 "$TITLE" apply-delivery-gap,action-required example-human false)"
  run_sut
  eq "S9 a human-authored issue with our title and label is never edited" "$(acts 'issue-edit 5 ')" 0
  eq "S9 a human-authored issue is never closed" "$(acts 'issue-close 5 ')" 0
  eq "S9 a fresh issue is created beside it" "$(acts issue-create)" 1
  gend
fi

# ---- S10: sibling success does not count ---------------------------------------------------------------------------------
if want S10; then
  grp S10
  mk_case s10 sibling-success-does-not-count
  run_sut
  eq "S10 rc 0" "$SUT_RC" 0
  eq "S10 deploy-fix candidate with infra successes (same sha AND a descendant) stays a row" "$(rows)" 1
  tn "S10 no compare or jobs read for the sibling's runs" grep -E 'compare|runs/100[23]/jobs' "$ST/out/reads.log"
  mk_case s10b
  runs_file "$ST/runs.infra.json" "$(mkrun 1201 push main completed cancelled 0x1201 "$(ago 200)" "$(ago 199)")"
  runs_file "$ST/runs.deploy-fix.json" "$(mkrun 1202 push main completed success 0x1201 "$(ago 199)" "$(ago 190)")"
  mkjobs 1201 0; mkjobs 1202 2 preflight:success apply:success
  run_sut
  eq "S10 infra candidate with a deploy-fix success at the same sha stays a row" "$(rows)" 1
  has "S10 the row is the infra one" "$ST/all.txt" "row workflow=infra sha=$(sha 0x1201) "
  gend
fi

# ---- S11: delivery requires the apply job -----------------------------------------------------------------------------
s11_world() { # keep: skipped | other | both
  mk_case "s11-$1" delivery-requires-apply-job
  case "$1" in
    skipped) runs_file "$ST/runs.infra.json" \
      "$(mkrun 1102 push main completed success 0x1102 2026-10-23T07:00:00Z 2026-10-23T07:10:00Z 2026-10-23T07:00:00Z '[skip-web-platform-apply]')" \
      "$(mkrun 1101 push main completed cancelled 0x1101 2026-10-23T06:00:00Z 2026-10-23T06:00:02Z)" ;;
    other) runs_file "$ST/runs.infra.json" \
      "$(mkrun 1103 workflow_dispatch main completed success 0x1103 2026-10-23T08:00:00Z 2026-10-23T08:05:00Z)" \
      "$(mkrun 1101 push main completed cancelled 0x1101 2026-10-23T06:00:00Z 2026-10-23T06:00:02Z)" ;;
  esac
}
if want S11:skipped; then grp S11a; s11_world skipped; run_sut; eq "S11 a push success whose apply job was SKIPPED does not deliver" "$(rows)" 1; gend; fi
if want S11:other-job-set; then grp S11b; s11_world other; run_sut; eq "S11 a dispatch success without an apply job (notify-apply-failure beside it) does not deliver" "$(rows)" 1; gend; fi
if want S11:both; then grp S11c; mk_case s11-both delivery-requires-apply-job; run_sut; eq "S11 both non-delivering successes leave the row" "$(rows)" 1; gend; fi
if want S11:delivers; then
  grp S11d
  mk_case s11-delivers delivery-requires-apply-job
  runs_file "$ST/runs.infra.json" \
    "$(mkrun 1104 workflow_dispatch main completed success 0x1104 2026-10-23T09:00:00Z 2026-10-23T09:06:00Z)" \
    "$(mkrun 1103 workflow_dispatch main completed success 0x1103 2026-10-23T08:00:00Z 2026-10-23T08:05:00Z)" \
    "$(mkrun 1102 push main completed success 0x1102 2026-10-23T07:00:00Z 2026-10-23T07:10:00Z 2026-10-23T07:00:00Z '[skip-web-platform-apply]')" \
    "$(mkrun 1101 push main completed cancelled 0x1101 2026-10-23T06:00:00Z 2026-10-23T06:00:02Z)"
  mkcmp 0x1101 0x1104 ahead; mkjobs 1104 2 preflight:success apply:success
  run_sut
  eq "S11 a dispatch success with [preflight, apply] success delivers" "$(rows)" 0
  has "S11 delivered=1" <(summary) "delivered=1"
  gend
fi

# ---- S12: a re-run of the cancelled push --------------------------------------------------------------------------------
if want S12:inflight; then
  grp S12a
  mk_case s12-inflight
  runs_file "$ST/runs.deploy-fix.json" "$(mkrun 1301 push main in_progress - 0x1301 "$(ago 120)" "$(ago 3)" "$(ago 3)")"
  issues_file "$(gap_issue 7)"
  run_sut
  eq "S12 the re-run is no longer a candidate" "$(rows)" 0
  eq "S12 an open issue is NOT written to while the re-run is in flight" "$(wc -l <"$ST/out/actions.log" | tr -d ' ')" 0
  has "S12 summary inflight=1" <(summary) "inflight=1"
  gend
fi
if want S12:completed; then
  grp S12b
  mk_case s12-completed
  runs_file "$ST/runs.deploy-fix.json" \
    "$(mkrun 1302 push main completed success 0x1302 "$(ago 100)" "$(ago 60)")" \
    "$(mkrun 1300 push main completed cancelled 0x1300 "$(ago 150)" "$(ago 149)")"
  mkcmp 0x1300 0x1302 ahead; mkjobs 1302 2 preflight:success apply:success
  issues_file "$(gap_issue 7)"
  run_sut
  eq "S12 after completion: delivered, closes completed" "$(acts 'issue-close 7 reason=completed')" 1
  mk_case s12-rerun-only
  runs_file "$ST/runs.deploy-fix.json" "$(mkrun 1303 push main completed success 0x1303 "$(ago 100)" "$(ago 60)")"
  issues_file "$(gap_issue 7)"
  run_sut
  eq "S12 re-run turned the cancelled run into a success (delivered==0): NOT closed" "$(acts issue-close)" 0
  eq "S12 one marker comment instead" "$(acts issue-comment)" 1
  gend
fi

# ---- S13: truncation boundary ---------------------------------------------------------------------------------------------
if want S13:trunc; then
  grp S13a
  mk_case s13-trunc
  runs_file "$ST/runs.deploy-fix.json" "$(mkrun 1401 push main completed success 0x1401 "$(ago 30)" "$(ago 29)")" "$(mkrun 1402 push main completed success 0x1402 "$(ago 40)" "$(ago 39)")"
  runs_file "$ST/runs.deploy-fix.p2.json" "$(mkrun 1403 push main completed success 0x1403 "$(ago 50)" "$(ago 49)")" "$(mkrun 1404 push main completed success 0x1404 "$(ago 60)" "$(ago 59)")"
  runs_file "$ST/runs.deploy-fix.p3.json" "$(mkrun 1405 push main completed success 0x1405 "$(ago 70)" "$(ago 69)")" "$(mkrun 1406 push main completed success 0x1406 "$(ago 80)" "$(ago 79)")"
  issues_file "$(gap_issue 7)"
  run_sut APPLY_DELIVERY_GAP_PAGE_SIZE=2 APPLY_DELIVERY_GAP_MAX_PAGES=3
  expect_fail run_window_truncated read
  gend
fi
if want S13:boundary; then
  grp S13b
  mk_case s13-edge
  runs_file "$ST/runs.deploy-fix.json" "$(mkrun 1401 push main completed success 0x1401 "$(ago 30)" "$(ago 29)")" "$(mkrun 1402 push main completed success 0x1402 "$(ago 40)" "$(ago 39)")"
  runs_file "$ST/runs.deploy-fix.p2.json" "$(mkrun 1403 push main completed success 0x1403 "$(ago 50)" "$(ago 49)")" "$(mkrun 1404 push main completed success 0x1404 "$(ago 60)" "$(ago 59)")"
  runs_file "$ST/runs.deploy-fix.p3.json" "$(mkrun 1405 push main completed success 0x1405 "$(ago 14400)" "$(ago 14399)")" "$(mkrun 1406 push main completed success 0x1406 "$(ago 14500)" "$(ago 14499)")"
  run_sut APPLY_DELIVERY_GAP_PAGE_SIZE=2 APPLY_DELIVERY_GAP_MAX_PAGES=3
  eq "S13 page 3 full but entirely beyond the cutoff is accepted" "$SUT_RC" 0
  gend
  grp S13c
  mk_case s13-dedup
  runs_file "$ST/runs.deploy-fix.json" "$(mkrun 1411 push main completed success 0x1411 "$(ago 20)" "$(ago 19)")" "$(mkrun 1410 push main completed cancelled 0x1410 "$(ago 60)" "$(ago 59)")"
  runs_file "$ST/runs.deploy-fix.p2.json" "$(mkrun 1410 push main completed cancelled 0x1410 "$(ago 60)" "$(ago 59)")" "$(mkrun 1409 push main completed failure 0x1409 "$(ago 60)" "$(ago 50)")"
  runs_file "$ST/runs.deploy-fix.p3.json" "$(mkrun 1408 push main completed failure 0x1408 "$(ago 20000)" "$(ago 19999)")"
  mkcmp 0x1410 0x1411 behind; mkjobs 1410 0
  run_sut APPLY_DELIVERY_GAP_PAGE_SIZE=2 APPLY_DELIVERY_GAP_MAX_PAGES=3
  eq "S13 a run repeated across pages 1 and 2 (page shift) yields one row" "$(rows)" 1
  gend
fi

# ---- S14: body bounds -----------------------------------------------------------------------------------------------------
if want S14; then
  grp S14
  mk_case s14
  objs=(); for i in $(seq 1 140); do objs+=("$(mkrun $((5000 + i)) push main completed cancelled $((0x5000 + i)) "$(ago $((1000 - i)))" "$(ago $((999 - i)))")"); mkjobs $((5000 + i)) 0; done
  runs_file "$ST/runs.deploy-fix.json" "${objs[@]}"
  run_sut APPLY_DELIVERY_GAP_PAGE_SIZE=1000
  eq "S14 rc 0" "$SUT_RC" 0
  eq "S14 one create" "$(acts issue-create)" 1
  [[ "$(wc -c <"$(body 1)")" -lt 65536 ]] && pass "S14 body under 65,536 bytes" || fail "S14 body too large"
  eq "S14 the table is capped at 40 rows" "$(grep -c '^| Apply deploy-pipeline-fix ' "$(body 1)")" 40
  has "S14 the +K more line counts the FULL set" "$(body 1)" "+100 more undelivered pushes not shown"
  has "S14 summary rows=140 (the full set)" <(summary) "rows=140"
  gend
fi

# ---- S15: poisoned fixture -------------------------------------------------------------------------------------------------
if want S15; then
  grp S15
  mk_case s15
  longs="$(printf 'A%.0s' $(seq 1 3000))"
  poison=$'\r\n::error::x @octocat [a](http://evil) <img src=x> '"$longs"
  runs_file "$ST/runs.deploy-fix.json" \
    "$(mkrun 1501 push main completed cancelled 0x1501 "$(ago 60)" "$(ago 59)" "$(ago 60)" "$poison" | jq -c --arg p "$poison" '.display_title=$p | .actor={login:"@octocat"} | .head_commit.author={name:$p}')" \
    "$(mkrun 1502 push 'feature/@octocat\r\n::error::x' completed cancelled 0x1502 "$(ago 61)" "$(ago 60)" | jq -c --arg p "$poison" '.display_title=$p')"
  mkjobs 1501 0
  run_sut
  eq "S15 rc 0" "$SUT_RC" 0
  eq "S15 one row" "$(rows)" 1
  for needle in '@octocat' '[a](http://evil)' '<img src=x>' 'AAAAAAAAAA' 'feature/'; do
    lacks "S15 '$needle' is not in the output" "$ST/all.txt" "$needle"
    lacks "S15 '$needle' is not in the issue body" "$(body 1)" "$needle"
  done
  eq "S15 no forged ::error:: annotation" "$(cnt "$ST/all.txt" '^::error::')" 0
  gend
fi

# ---- S16: clock skew --------------------------------------------------------------------------------------------------------
if want S16; then
  grp S16
  mk_case s16
  runs_file "$ST/runs.deploy-fix.json" "$(mkrun 1601 push main completed cancelled 0x1601 "$(ago 10)" 2026-10-23T13:00:00Z)"
  mkjobs 1601 0
  run_sut
  has "S16 updated_at later than now gives 0 minutes, never negative" "$(body 1)" "| 0 |"
  tn "S16 no negative minutes" grep -E '\| -[0-9]+ \|' "$(body 1)"
  mk_case s16b
  runs_file "$ST/runs.deploy-fix.json" \
    "$(mkrun 1603 workflow_dispatch main completed success 0x1603 "$(ago 20)" "$(ago 15)")" \
    "$(mkrun 1602 push main completed cancelled 0x1602 "$(ago 30)" "$(ago 10)")"
  mkcmp 0x1602 0x1603 ahead; mkjobs 1603 2 preflight:success apply:success
  issues_file "$(gap_issue 7)"
  run_sut
  has "S16 delivery before the recorded cancel time is 0 minutes" "$ST/out/actions.log" "delivered by run 1603, 0 minutes"
  gend
fi

# ---- S17: test-only overrides are inert in live mode --------------------------------------------------------------------
if want S17; then
  grp S17
  mk_case s17
  runs_file "$ST/runs.deploy-fix.json" "$(mkrun 1701 push main completed success 0x1701 "$(ago 10)" "$(ago 9)")" "$(mkrun 1702 push main completed success 0x1702 "$(ago 20)" "$(ago 19)")"
  rc=0
  env -i PATH="$ST/bin:$PATH" HOME="$ST" TMPDIR="$ST/tmp" GH_REPO="$REPO_SLUG" GH_TOKEN=synthetic-token \
    APPLY_DELIVERY_GAP_PAGE_SIZE=2 APPLY_DELIVERY_GAP_MAX_PAGES=1 bash "$SUT" >"$ST/all.txt" 2>&1 || rc=$?
  SUT_RC=$rc
  eq "S17 live mode ignores the page overrides (rc 0, no truncation)" "$SUT_RC" 0
  has "S17 reads use the production page size" "$ST/out/reads.log" "apply-deploy-pipeline-fix.yml/runs?per_page=100&page=1"
  has "S17 summary mode=live" <(summary) "mode=live"
  gend
fi

# ---- R1..R4: recorded incident replays ----------------------------------------------------------------------------------
if want R; then
  grp R
  for r in "37964350917:48d5144cf415851de1e0f425027777b5d0289e46" "37964762496:d7dfd05aacc19392f0e1c861bb72e16c35f60562" "38144232116:568dfade87e7bde0beeac025ad90838399dda693"; do
    id="${r%%:*}"; rsha="${r#*:}"
    mk_case "r-$id" "replay-$id"
    run_sut
    eq "R[$id] rc 0" "$SUT_RC" 0
    eq "R[$id] exactly one row" "$(rows)" 1
    has "R[$id] workflow deploy-fix, class evicted-before-start, recorded sha" "$ST/all.txt" "row workflow=deploy-fix sha=$rsha class=evicted-before-start"
    has "R[$id] URL carries the run id" "$(body 1)" "https://github.com/$REPO_SLUG/actions/runs/$id"
    hasre "R[$id] and ends in none, not an epoch" "$(body 1)" '\| [0-9]+ \| none \|$'
    tn "R[$id] no created-epoch digits in the later-run cell" grep -E 'actions/runs/[0-9]{10}\)' "$(body 1)"
  done
  mk_case r4 replay-incident-delivered
  run_sut
  eq "R4 rc 0" "$SUT_RC" 0
  eq "R4 zero rows" "$(rows)" 0
  has "R4 closes with reason completed" "$ST/out/actions.log" "issue-close 7 reason=completed"
  has "R4 both incident pushes are named" "$ST/out/actions.log" "48d5144"
  has "R4 and d7dfd05" "$ST/out/actions.log" "d7dfd05"
  has "R4 by the recorded dispatch run" "$ST/out/actions.log" "delivered by run 37976212395"
  gend
fi

# ---- H3: must-PASS non-canonical inputs -------------------------------------------------------------------------------------
if want H3; then
  grp H3
  mk_case h3
  runs_file "$ST/runs.infra.json" "$(mkrun 1801 push main completed success 0x1801 "$(ago 20)" "$(ago 19)")" "$(mkrun 1802 push main completed success 0x1802 "$(ago 30)" "$(ago 29)")"
  runs_file "$ST/runs.infra.p2.json" "$(mkrun 1803 push main completed cancelled 0x1803 "$(ago 60)" "$(ago 59)")" "$(mkrun 1804 push main completed success 0x1804 "$(ago 70)" "$(ago 69)")"
  runs_file "$ST/runs.infra.p3.json" "$(mkrun 1805 push main completed success 0x1805 "$(ago 80)" "$(ago 79)")"
  mkcmp 0x1803 0x1801 behind; mkcmp 0x1803 0x1802 behind; mkjobs 1803 0
  run_sut APPLY_DELIVERY_GAP_PAGE_SIZE=2 APPLY_DELIVERY_GAP_MAX_PAGES=5
  eq "H3 a candidate on page 2 of 3, on the SECOND listed workflow, is found" "$(rows)" 1
  has "H3 the row is the infra one" "$ST/all.txt" "row workflow=infra sha=$(sha 0x1803) "
  gend
  grp H3b
  mk_case h3b
  runs_file "$ST/runs.deploy-fix.json" "$(mkrun 1811 push main completed success 0x1811 "$(ago 20)" "$(ago 19)" "$(ago 20)" 'a different commit message')"
  runs_file "$ST/runs.infra.json" "$(mkrun 1812 push main completed success 0x1803 "$(ago 20)" "$(ago 10)")" "$(mkrun 1813 push main completed cancelled 0x1803 "$(ago 60)" "$(ago 59)")"
  mkjobs 1812 2 preflight:success apply:success; mkjobs 1813 0
  run_sut
  eq "H3 a success whose head EQUALS the candidate delivers (no compare needed)" "$(rows)" 0
  tn "H3 and made no compare call" grep -q compare "$ST/out/reads.log"
  gend
fi

# ---- W: workflow wiring -------------------------------------------------------------------------------------------------------
if want W; then
  grp W
  py="$SANDBOX/wiring.py"
  cat >"$py" <<'PY'
import re, sys, yaml
wf_path, deploy_path, infra_path, sut_path = sys.argv[1:5]
res = []
def chk(desc, cond):
    res.append(("PASS" if cond else "FAIL", desc))
try:
    text = open(wf_path).read()
    doc = yaml.safe_load(text)
except Exception as e:
    print("FAIL cannot parse the follower workflow: %s" % e); sys.exit(0)
dtext, itext, stext = open(deploy_path).read(), open(infra_path).read(), open(sut_path).read()
d, i = yaml.safe_load(dtext), yaml.safe_load(itext)
on = doc.get("on", doc.get(True))
chk("on is exactly workflow_run (non-empty)", isinstance(on, dict) and set(on) == {"workflow_run"})
wr = (on or {}).get("workflow_run", {}) if isinstance(on, dict) else {}
chk("types: [completed]", wr.get("types") == ["completed"])
chk("branches: [main]", wr.get("branches") == ["main"])
names = [d["name"], i["name"]]
chk("workflows: equals the live apply workflows' name: strings (apply workflow == follower workflows: == script WATCHED)", wr.get("workflows") == names)
for key, f, nm in (("deploy-fix", "apply-deploy-pipeline-fix.yml", d["name"]), ("infra", "apply-web-platform-infra.yml", i["name"])):
    m = re.search(r'"%s\|%s\|([^|]*)\|' % (re.escape(key), re.escape(f)), stext)
    chk("script WATCHED display name for %s equals the apply workflow name: (three copies must agree)" % key, bool(m) and m.group(1) == nm)
for nm, doc_ in (("deploy-fix", d), ("infra", i)):
    onk = doc_.get("on", doc_.get(True))
    chk("watched %s is triggered only by push/workflow_dispatch (no fork-controlled trigger can fire the follower)" % nm, set(onk) <= {"push", "workflow_dispatch"})
chk("permissions exactly {contents: read, actions: read, issues: write}", doc.get("permissions") == {"contents": "read", "actions": "read", "issues": "write"})
jobs = doc.get("jobs", {})
chk("no job-level permissions block", all("permissions" not in j for j in jobs.values()) and len(jobs) >= 1)
def group(x): return (x.get("concurrency") or {}).get("group")
conc = doc.get("concurrency") or {}
chk("concurrency group differs from the apply group", conc.get("group") not in (None, group(d), group(i)))
chk("cancel-in-progress is false", conc.get("cancel-in-progress") is False)
chk("every watched file exists and shares one group", group(d) == group(i) and group(d))
for lit, who, t in (("(^|$'\\n')\\[skip-deploy-fix-apply\\]($|$'\\n')", "deploy-fix", dtext), ("(^|$'\\n')\\[skip-web-platform-apply\\]($|$'\\n')", "infra", itext)):
    chk("kill-switch literal for %s appears in the script and in the apply workflow's preflight" % who, lit in stext and lit in t)
for word in ("secrets.", "environment:", "terraform", "workflow_dispatch", "gh workflow run", "/dispatches"):
    chk("raw text lacks '%s' (the follower is detection only; write it as 'the apply group', never by its literal)" % word, word not in text)
ev = re.findall(r"github\.event\.[A-Za-z_.]+", text)
chk("the only github.event.* text is the TRIGGER_RUN_ID env value", ev == ["github.event.workflow_run.id"])
uses = re.findall(r"uses:\s*(\S+)", text)
chk("every uses: is a 40-hex pin", len(uses) >= 1 and all(re.fullmatch(r"[\w./-]+@[0-9a-f]{40}", u) for u in uses))
steps = [s for j in jobs.values() for s in j.get("steps", [])]
chk("anti-vacuity: at least 2 parsed steps", len(steps) >= 2)
chk("checkout has no ref:", all("ref" not in (s.get("with") or {}) for s in steps if "checkout" in str(s.get("uses", ""))))
chk("checkout is sparse and credential-free", any((s.get("with") or {}).get("persist-credentials") is False and "apply-delivery-gap.sh" in str((s.get("with") or {}).get("sparse-checkout", "")) for s in steps))
runs = [s.get("run") for s in steps if s.get("run")]
chk("the run: line is exactly bash scripts/apply-delivery-gap.sh", runs == ["bash scripts/apply-delivery-gap.sh"])
chk("job timeout-minutes is set", all("timeout-minutes" in j for j in jobs.values()))
chk("no step env reads a secret", "secrets" not in str([s.get("env") for s in steps]))
for r in res: print(r[0] + "\t" + r[1])
PY
  while IFS=$'\t' read -r verdict desc; do
    [[ "$verdict" == PASS ]] && pass "W $desc" || fail "W $desc"
  done < <(python3 -I "$py" "$WF" "$DEPLOY_WF" "$INFRA_WF" "$SUT" 2>&1)
  [[ "$ASSERTS" -gt "$G0" ]] || fail "W produced no assertion"
  # chokepoint greps on the script
  if [[ -f "$SUT" ]]; then
    gh_sites="$(awk '/^[a-z_]+\(\) \{/ {fn=$1} /timeout 60 gh / && !/^[[:space:]]*#/ {print fn}' "$SUT" | tr -d '()' | paste -sd' ')"
    eq "W only api_get and gh_write call gh" "$gh_sites" "api_get gh_write"
    tn "W no bare 'gh api' or 'gh issue' outside the chokepoints" grep -E '^[^#]*[^a-z_]gh (api|issue) ' "$SUT"
    tn "W no '|| true' in the script" grep -F '|| true' "$SUT"
    tn "W no 2>&1 in the script" grep -F '2>&1' "$SUT"
    tn "W no --remove-label in the script" grep -F -e '--remove-label' "$SUT"
    ln_use="$(grep -n 'APPLY_DELIVERY_GAP_' "$SUT" | grep -v '^[0-9]*:#' | cut -d: -f1 | paste -sd' ')"
    fx_start="$(grep -n '^if \[\[ -n "\$FIXTURE" \]\]; then' "$SUT" | head -n 1 | cut -d: -f1)"
    fx_end="$(awk -v s="${fx_start:-0}" 'NR > s && /^fi$/ {print NR; exit}' "$SUT")"
    okfx=1; for l in $ln_use; do [[ -n "$fx_start" && "$l" -gt "$fx_start" && "$l" -lt "${fx_end:-0}" ]] || okfx=0; done
    [[ -n "$ln_use" && "$okfx" -eq 1 ]] && pass "W test-only overrides are read only inside the fixture branch" || fail "W a test-only override is read outside the fixture branch ($ln_use vs $fx_start-$fx_end)"
  else
    fail "W the script does not exist"
  fi
  gend
fi

# ---- reasons: the set of failure reasons in the script equals the set the scenarios assert ------------------------------------
if want S8 && [[ -z "${ADG_ONLY:-}" ]]; then
  grp REASONS
  if [[ -f "$SUT" ]]; then
    script_set="$( { grep -oE '(fail_loud|gh_write|api_get) [a-z_]+' "$SUT" | awk '{print $2}' | grep -E '_(failed|exceeded|truncated|response|visible)$'; printf 'bad_input\n'; } | sort -u | paste -sd' ')"
    test_set="$(printf '%s\n' "${ASSERTED_REASONS[@]}" | sort -u | paste -sd' ')"
    eq "REASONS the failure reasons in the script equal the ones the scenarios assert" "$script_set" "$test_set"
  else
    fail "REASONS the script does not exist"
  fi
  gend
fi

# ---- H1 and M: meta groups (skipped in children) ------------------------------------------------------------------------------
child() { # <sut> <only> -> rc
  ADG_SUT="$1" ADG_WF="${3:-$WF}" ADG_ONLY="$2" ADG_NO_META=1 timeout -k 5 150 bash "$SELF" >/dev/null 2>&1
  echo $?
}
if [[ -z "${ADG_NO_META:-}" ]] && want H1; then
  grp H1
  stub="$SANDBOX/stub.sh"; printf '#!/usr/bin/env bash\nexit 0\n' >"$stub"
  eq "H1 a stub SUT that exits 0 and prints nothing REDs the suite (S1)" "$(child "$stub" S1)" 1
  eq "H1 and the scenario S5 too" "$(child "$stub" S5)" 1
  gend
fi

# Mutation battery: one row per guard (plan table M1..M20, Y1, Y2). Fields (tab-separated):
#   id <TAB> target (script|workflow) <TAB> function (empty = whole file) <TAB> old <TAB> new <TAB> pinned sub-cases
# `<NL>` in old/new is a newline; `-` as the function means the whole file. The anchor must match EXACTLY ONCE inside the function; a mutant that does not land, or
# whose pristine control does not pass, is an instrument error and fails the suite. Only a child rc of 1 (an assertion
# failed) counts as "caught": 124/127/2 are reported as instrument errors.
MUTANTS=()
mut() { MUTANTS+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$@")"); }
mut M1 script descendant_status 'identical|ahead)' 'identical|ahead|behind)' 'S2,S2b:behind,R'
mut M2 script reconcile_workflow '| .[] | [.id, .sha, .ue] | @tsv'"'"' "$nf")"' '| .[] | [.id, .sha, .ue] | @tsv'"'"' "$WORK"/n.*.json)"' 'S10'
mut M3 script fail_loud 'apply_delivery_gap_%s\n'"'"' "$reason"<NL>  exit 1' 'apply_delivery_gap_%s\n'"'"' "$reason"<NL>  return 0' 'S8:malformed'
mut M4 script reconcile_workflow 'if "$ks" "$msg"; then' 'if false; then' 'S4'
mut M5 script - '|Apply web-platform infra (Doppler/Cloudflare/BetterStack/GitHub-App/Inngest/firewall)|ks_infra|' '|Apply web-platform infra (Doppler/Cloudflare/BetterStack/GitHub-App/Inngest/firewall)|ks_deploy_fix|' 'S4'
mut M6 script reconcile_workflow 'if is_descendant "$sha" "$rsha" && apply_job_ok "$rid"; then' 'if is_descendant "$sha" "$rsha"; then' 'S11:skipped'
mut M7 script jobs_have_apply_success '.conclusion == "success")'"'" '.conclusion == "success" or .conclusion == "skipped")'"'" 'S11:skipped'
mut M8 script reconcile_issue 'if [[ "$N_INFLIGHT" -gt 0 ]]; then' 'if false; then' 'S7:otherwf,S12:inflight'
mut M9 script read_runs 'if [[ "$p" -eq "$MAX_PAGES" ]]; then fail_loud run_window_truncated; fi' ':' 'S13:trunc'
mut M10 script reconcile_issue 'lbls="${LABEL},action-required"' 'lbls="${LABEL}"' 'S9'
mut M11 script is_descendant 'CMP[$k]="unresolvable"' 'CMP[$k]="ahead"' 'S8:compare404'
mut M12 script main 'if trigger_visible; then break; fi' 'break' 'S8:trigger-invisible'
mut M13 script reconcile_workflow '          break<NL>        fi<NL>      done <<<"$runs"' '          break<NL>        fi<NL>        break<NL>      done <<<"$runs"' 'S2'
mut M14 script ks_deploy_fix "(^|\$'\\n')\\[skip-deploy-fix-apply\\]($|\$'\\n')" '\[skip-deploy-fix-apply\]' 'S4:midline'
mut M15 script read_runs '&page=${p}"' '&page=${p}&status=cancelled"' 'S1'
mut M16 script api_get 'if [[ "$rc" -eq 0 ]]; then<NL>      API_OUT' 'if true; then<NL>      API_OUT' 'S8:runs-p1,S8:compare-5xx'
mut M17 script reconcile_issue 'elif [[ "$N_DELIVERED" -ge 1 ]]; then' 'elif true; then' 'S5'
mut M18 script render_body 'total="$(wc -l <"$ROWS")"' 'total="$(wc -l <"$WORK/rows.shown")"' 'S14'
mut M19 script degraded_upsert 'nums="$(issue_numbers "$DEGRADED_TITLE")"' 'nums="$(issue_numbers "$TITLE")"' 'S8:degraded'
mut M20 script issue_numbers ' and (.title == $t))' ')' 'S9:foreign-title'
mut Y1 workflow - '    timeout-minutes: 10<NL>' '    timeout-minutes: 10<NL>    permissions:<NL>      contents: write<NL>' 'W'
mut Y2 workflow - 'group: apply-delivery-gap-follower' 'group: terraform-apply-web-platform-host' 'W'

if [[ -z "${ADG_NO_META:-}" ]] && want M; then
  grp M
  MD="$SANDBOX/mut"; mkdir -p "$MD"
  cat >"$MD/mutate.py" <<'PY'
import os, re, sys
src, dst, func, old, new = os.environ["MUT_SRC"], os.environ["MUT_DST"], os.environ["MUT_FUNC"].lstrip("-"), os.environ["MUT_OLD"], os.environ["MUT_NEW"]
old, new = old.replace("<NL>", "\n"), new.replace("<NL>", "\n")
text = open(src).read()
if func:
    lines = text.split("\n")
    start = next((i for i, l in enumerate(lines) if re.match(r"^%s\(\) \{" % re.escape(func), l)), None)
    if start is None:
        print("no function " + func); sys.exit(3)
    end = start if lines[start].rstrip().endswith("}") and lines[start].count("{") <= lines[start].count("}") else next(i for i in range(start + 1, len(lines)) if lines[i] == "}")
    region = "\n".join(lines[start:end + 1])
    n = region.count(old)
    if n != 1:
        print("anchor matched %d times inside %s" % (n, func)); sys.exit(3)
    region = region.replace(old, new)
    text = "\n".join(lines[:start] + region.split("\n") + lines[end + 1:])
else:
    n = text.count(old)
    if n != 1:
        print("anchor matched %d times in the file" % n); sys.exit(3)
    text = text.replace(old, new)
open(dst, "w").write(text)
PY
  cat >"$MD/job.sh" <<'JOB'
#!/usr/bin/env bash
# job.sh <index>: build the mutant, assert it landed, run its pinned sub-cases; write <index>.res
set -u
i="$1"; MD="$2"; PRISTINE_SUT="$3"; PRISTINE_WF="$4"; SELF="$5"
IFS=$'\t' read -r id target func old new pins <"$MD/spec.$i"
if [[ "$target" == "script" ]]; then pristine="$PRISTINE_SUT"; ext=sh; else pristine="$PRISTINE_WF"; ext=yml; fi
dst="$MD/$id.$ext"
if ! out="$(MUT_SRC="$pristine" MUT_DST="$dst" MUT_FUNC="$func" MUT_OLD="$old" MUT_NEW="$new" python3 -I "$MD/mutate.py" 2>&1)"; then
  printf 'ERROR\tdid not land: %s\n' "$out" >"$MD/$id.res"; exit 0
fi
if cmp -s "$pristine" "$dst"; then printf 'ERROR\tmutant is identical to the pristine file\n' >"$MD/$id.res"; exit 0; fi
rc=0
if [[ "$target" == "script" ]]; then
  ADG_SUT="$dst" ADG_ONLY="$pins" ADG_NO_META=1 timeout -k 5 150 bash "$SELF" >"$MD/$id.log" 2>&1 || rc=$?
else
  ADG_WF="$dst" ADG_ONLY="$pins" ADG_NO_META=1 timeout -k 5 150 bash "$SELF" >"$MD/$id.log" 2>&1 || rc=$?
fi
case "$rc" in
  1) printf 'CAUGHT\t\n' >"$MD/$id.res" ;;
  0) printf 'SURVIVED\t%s\n' "$pins" >"$MD/$id.res" ;;
  *) printf 'ERROR\tinstrument rc=%s\n' "$rc" >"$MD/$id.res" ;;
esac
JOB
  chmod +x "$MD/job.sh"
  # pristine control per distinct pin set (and per target): must pass
  declare -A seen=()
  i=0
  for m in "${MUTANTS[@]}"; do
    i=$((i + 1)); printf '%s\n' "$m" >"$MD/spec.$i"
    IFS=$'\t' read -r id target func old new pins <<<"$m"
    seen["$target|$pins"]=1
  done
  ctl_bad=0
  # pristine controls run in parallel (one child per distinct pin set); only an rc of 0 is a clean control
  : >"$MD/ctl.list"
  for k in "${!seen[@]}"; do printf '%s\n' "${k#*|}" >>"$MD/ctl.list"; done
  ci=0
  while IFS= read -r pins; do ci=$((ci + 1)); printf '%s\t%s\n' "$ci" "$pins" >"$MD/ctlspec.$ci"; done <"$MD/ctl.list"
  cat >"$MD/ctl.sh" <<'CTL'
#!/usr/bin/env bash
i="$1"; MD="$2"; SUT="$3"; WF="$4"; SELF="$5"
IFS=$'\t' read -r _ pins <"$MD/ctlspec.$i"
rc=0
ADG_SUT="$SUT" ADG_WF="$WF" ADG_ONLY="$pins" ADG_NO_META=1 timeout -k 5 150 bash "$SELF" >"$MD/ctl.$i.log" 2>&1 || rc=$?
printf '%s\t%s\n' "$rc" "$pins" >"$MD/ctl.$i.res"
CTL
  chmod +x "$MD/ctl.sh"
  seq 1 "$ci" | xargs -P 8 -I{} bash "$MD/ctl.sh" {} "$MD" "$SUT" "$WF" "$SELF"
  for ((cj = 1; cj <= ci; cj++)); do
    IFS=$'\t' read -r crc cpins <"$MD/ctl.$cj.res"
    if [[ "$crc" -ne 0 ]]; then ctl_bad=1; fail "M pristine control for pins <$cpins> failed (rc $crc): mutation results for it would be meaningless"; fi
  done
  [[ "$ctl_bad" -eq 0 ]] && pass "M every pristine control passes (${#seen[@]} pin sets)"
  eq "M the mutant table length equals MUTANT_FLOOR" "${#MUTANTS[@]}" "$MUTANT_FLOOR"
  seq 1 "${#MUTANTS[@]}" | xargs -P 8 -I{} bash "$MD/job.sh" {} "$MD" "$SUT" "$WF" "$SELF"
  caught=0
  for m in "${MUTANTS[@]}"; do
    IFS=$'\t' read -r id _ <<<"$m"
    if [[ -f "$MD/$id.res" ]]; then
      IFS=$'\t' read -r verdict detail <"$MD/$id.res"
    else
      verdict=ERROR; detail="no result"
    fi
    case "$verdict" in
      CAUGHT) pass "M $id landed and was caught"; caught=$((caught + 1)) ;;
      SURVIVED) fail "M $id SURVIVED its pins ($detail)" ;;
      *) fail "M $id instrument error: $detail" ;;
    esac
  done
  printf '[M] %s/%s mutants caught\n' "$caught" "${#MUTANTS[@]}"
  if [[ -n "${ADG_MUT_LOGS:-}" ]]; then mkdir -p "$ADG_MUT_LOGS" && cp "$MD"/*.log "$ADG_MUT_LOGS"/ 2>/dev/null; fi
  gend
fi

# ---- verdict ------------------------------------------------------------------------------------------------------------------
if [[ -n "${ADG_PRINT_COUNTS:-}" ]]; then
  for k in "${!GCOUNT[@]}"; do printf 'COUNT %s %s\n' "$k" "${GCOUNT[$k]}"; done | sort
fi
printf '\n[apply-delivery-gap-follower] %s assertions, %s passed, %s failed\n' "$ASSERTS" "$passes" "$fails"
if [[ "$fails" -gt 0 ]]; then
  printf 'FAILED:\n'; printf '  - %s\n' "${FAILED[@]}"
  exit 1
fi
if [[ "$ASSERTS" -eq 0 ]]; then printf '[FATAL] zero assertions ran\n' >&2; exit 2; fi
exit 0
