#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016,SC2034  # rows are dispatched indirectly; A && B || why is the assertion idiom; some programs are single-quoted on purpose
# Suite for scripts/ci-pr-affected-replay.py (S4 PR C, #9729, ADR-276): the escape-rate replay and the go/no-go arithmetic.
#
# THE SEAMS. `gh` is a PATH stub keyed on the request path (the `created=` window is collapsed, because the SUT
# stamps it with the clock) that refuses an unknown request with exit 64 and logs `STUB-MISS`; a fixture file
# named ERR_<key> makes a request fail with rc 1. The selector is PR_AFFECTED_REPLAY_TEST_ALL, a stub that prints
# AFFECTED_SELECTED rows decided by the path list. The repository is a synthesized git repo with an origin/main ref.
#
# WHAT IS PINNED. A failed READ is never "no failure" (not-evaluable, with the read named); a failed suite counts
# against the rule only when the rule would have skipped it; a same-tree green clears it; a suite that fails in
# three units with two distinct file sets is a flake class and one that fails once is not; the worst-case
# numerator (not-evaluable included) feeds the 95% bound; the verdict function is total over all 256 status
# combinations; the audit flags the PR 9404 shape. MUTATION ROWS copy the SUT, apply ONE edit (asserted to have
# landed), and require the named row to FAIL against the mutant. The anti-vacuity floor and the instrument
# self-test report through printf + exit, never through the pass()/fail() pair they backstop.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_SUT="$SCRIPT_DIR/../../../scripts/ci-pr-affected-replay.py"
SUT="$REAL_SUT"

passes=0; fails=0; FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; FAILED=()

[[ -f "$REAL_SUT" ]] || { echo "[FATAL] SUT not found at $REAL_SUT" >&2; exit 1; }
for tool in python3 git jq; do
  command -v "$tool" >/dev/null || { echo "[FATAL] $tool required" >&2; exit 1; }
done

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

SANDBOX="$(mktemp -d "$TMPDIR/ci-pr-affected-replay.XXXXXXXX")" || { echo "[FATAL] mktemp failed" >&2; exit 1; }
case "$SANDBOX" in /*) : ;; *) echo "[FATAL] sandbox is not absolute" >&2; exit 1 ;; esac
trap 'rm -rf "$SANDBOX"' EXIT
export TMPDIR="$SANDBOX"

GIT_SCRUB=(-u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY
           -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_NAMESPACE -u GIT_TEMPLATE_DIR -u GIT_EXEC_PATH)
gitq() { env "${GIT_SCRUB[@]}" git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

REPO="$SANDBOX/repo"
GHFIX="$SANDBOX/ghfix"
BIN="$SANDBOX/bin"
GHLOG="$SANDBOX/gh.log"
FIXHOME="$SANDBOX/fixhome"

# ---- the fake repository: seven first-parent commits --------------------------------------------------------------
build_repo() {
  assert_fixture_dir "$REPO"
  mkdir -p "$REPO/scripts" "$REPO/doc" || return 1
  (
    cd "$REPO" || exit 1
    gitq init -q -b main . || exit 1
    printf 'scripts/lib/a\t60000\tmeasured\nscripts/suitex\t120000\tmeasured\nscripts/suitey\t30000\tmeasured\n' > "$REPO/scripts/suite-durations.tsv"
    : > "$REPO/scripts/suite-durations-heavy.tsv"
    printf 'seed\n' > "$REPO/README.md"
    gitq add -A && gitq commit -qm seed || exit 1
    n=0
    for f in doc/a.md x.txt doc/c.md doc/d.md doc/e.md scripts/runner.sh doc/g.md; do
      n=$((n + 1)); mkdir -p "$(dirname "$REPO/$f")"; printf 'v%s\n' "$n" > "$REPO/$f"
      gitq add -A && gitq commit -qm "c$n $f" || exit 1
    done
    gitq update-ref refs/remotes/origin/main HEAD
  ) || return 1
}
build_repo || { echo "[FATAL] could not build the fixture repo" >&2; exit 1; }
C=()   # C[1]..C[7], oldest first
while read -r sha; do C+=("$sha"); done < <(gitq -C "$REPO" rev-list --first-parent --reverse -n 7 origin/main)
[[ "${#C[@]}" -eq 7 ]] || { echo "[FATAL] expected 7 commits, got ${#C[@]}" >&2; exit 1; }

# ---- the selector stub ----------------------------------------------------------------------------------------------
mkdir -p "$BIN" "$GHFIX" "$FIXHOME"
cat > "$BIN/sel.sh" <<'SEL'
#!/usr/bin/env bash
# args: --print-selection --paths=<csv>
paths=""
for a in "$@"; do case "$a" in --paths=*) paths="${a#--paths=}" ;; esac; done
[ -n "$paths" ] || { echo "sel-stub: no --paths" >&2; exit 64; }
fb=none
case ",$paths," in *,scripts/runner.sh,*) fb=runner-changed ;; esac
x=0; case ",$paths," in *,x.txt,*) x=1 ;; esac
printf 'AFFECTED_SELECTED\tscripts/lib/a\t1\talways_on\t^scripts/lib/a\n'
printf 'AFFECTED_SELECTED\tscripts/suitex\t%s\tedge:declared\t^x.txt|^scripts/suitex.test.sh\n' "$x"
printf 'AFFECTED_SELECTED\tscripts/suitey\t0\tedge:derived\t^scripts/suitey.test.sh\n'
printf 'AFFECTED_SELECTED\tscripts/suitez\t0\talways_on\t^scripts/suitez.test.sh\n'
printf 'AFFECTED_SUMMARY selected=2 of=4 always_on=1 edge=0 fallback=%s\n' "$fb"
SEL
chmod +x "$BIN/sel.sh"

cat > "$BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
# gh api [--allow-escape-sequences] [--paginate] <path>
[ "${1:-}" = api ] || { echo "STUB-MISS argv=$*" >> "$GH_LOG"; exit 64; }
shift
path=""
for a in "$@"; do case "$a" in --allow-escape-sequences|--paginate) : ;; *) path="$a" ;; esac; done
key="$(printf '%s' "$path" | sed -E 's/created=[^&]*/created=X/' | tr -c 'A-Za-z0-9\n' '_')"
printf 'REQ %s\n' "$key" >> "$GH_LOG"
if [ -f "$GH_FIX/ERR_$key" ]; then echo "gh: HTTP 502" >&2; exit 1; fi
if [ -f "$GH_FIX/$key" ]; then cat "$GH_FIX/$key"; exit 0; fi
echo "STUB-MISS $key" >> "$GH_LOG"; exit 64
GHSTUB
chmod +x "$BIN/gh"
export GH_LOG="$GHLOG" GH_FIX="$GHFIX"

R=jikig-ai/soleur
keyof() { printf '%s' "$1" | sed -E 's/created=[^&]*/created=X/' | tr -c 'A-Za-z0-9\n' '_'; }
fx() { local k; k="$(keyof "$1")"; cat > "$GHFIX/$k"; }          # fx <path> < body
fx_err() { : > "$GHFIX/ERR_$(keyof "$1")"; }
runs_path() { printf 'repos/%s/actions/workflows/ci.yml/runs?head_sha=%s&per_page=100' "$R" "$1"; }
jobs_path() { printf 'repos/%s/actions/runs/%s/jobs?per_page=100&filter=latest' "$R" "$1"; }
log_path() { printf 'repos/%s/actions/jobs/%s/logs' "$R" "$1"; }
runs_body() {  # runs_body <sha> then triples id:event:conclusion
  local sha="$1"; shift; local first=1 item id ev concl
  printf '{"total_count":%s,"workflow_runs":[' "$#"
  for item in "$@"; do
    IFS=: read -r id ev concl <<<"$item"
    [ "$first" = 1 ] || printf ','; first=0
    printf '{"id":%s,"event":"%s","conclusion":"%s","run_attempt":1,"created_at":"2031-01-0%sT00:00:00Z","head_sha":"%s"}' "$id" "$ev" "$concl" "${id: -1}" "$sha"
  done
  printf ']}'
}
jobs_body() {  # jobs_body <runid> then id:name:conclusion
  local first=1 item id name concl
  printf '{"jobs":['
  shift
  for item in "$@"; do
    IFS=: read -r id name concl <<<"$item"
    [ "$first" = 1 ] || printf ','; first=0
    printf '{"id":%s,"name":"%s","conclusion":"%s"}' "$id" "$name" "$concl"
  done
  printf ']}'
}

# c1 clean merge_group; c2 failing selected suite; c3 failing would-skip suite (unverified); c4 e2e failure;
# c5 runs read fails; c6 merge_group success beside a push failure on the runner-changed commit; c7 failed shard without a FAIL line
runs_body "${C[0]}" "1001:merge_group:success" | fx "$(runs_path "${C[0]}")"
runs_body "${C[1]}" "2001:push:failure" | fx "$(runs_path "${C[1]}")"
jobs_body 2001 "9201:test-scripts (1/8):failure" "9202:test:failure" "9203:lint:success" | fx "$(jobs_path 2001)"
printf '2031-01-01T00:00:00.1Z [FAIL] scripts/suitex (120ms) log=/l/x.log\n2031-01-01T00:00:00.2Z === 5/6 suites passed ===\n' | fx "$(log_path 9201)"
runs_body "${C[2]}" "3001:push:failure" | fx "$(runs_path "${C[2]}")"
jobs_body 3001 "9301:test-scripts (2/8):failure" "9302:test:failure" | fx "$(jobs_path 3001)"
printf '[FAIL] instrument self-test: the FAIL arm records (EXPECTED — subtracted)\n[FAIL] scripts/suitey (90ms) log=/l/y.log\n' | fx "$(log_path 9301)"
runs_body "${C[3]}" "4001:push:failure" | fx "$(runs_path "${C[3]}")"
jobs_body 4001 "9401:e2e:failure" "9402:test:failure" | fx "$(jobs_path 4001)"
fx_err "$(runs_path "${C[4]}")"
runs_body "${C[5]}" "6001:push:failure" "6002:merge_group:success" | fx "$(runs_path "${C[5]}")"
runs_body "${C[6]}" "7001:push:failure" | fx "$(runs_path "${C[6]}")"
jobs_body 7001 "9701:test-scripts (3/8):failure" "9702:test:failure" | fx "$(jobs_path 7001)"
printf '[FAIL] instrument self-test: the FAIL arm records (EXPECTED — subtracted)\nsome other line\n' | fx "$(log_path 9701)"

run_sut() {  # run_sut <args...>; the repo is the cwd, the selector and gh are stubs; prints stdout, rc in $RC
  ( cd "$REPO" && env PATH="$BIN:$PATH" PR_AFFECTED_REPLAY_TEST_ALL="$BIN/sel.sh" HOME="$FIXHOME" python3 "$SUT" "$@" )
}
unit_field() {  # unit_field <jsonl> <sha> <jq expr>
  jq -r --arg s "$2" "select(.sha==\$s) | $3" "$1"
}

OUT="$SANDBOX/out"
collect_once() {
  rm -rf "$OUT"; mkdir -p "$OUT"
  : > "$GHLOG"
  run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" > "$SANDBOX/collect.out" 2>&1
  RC=$?
}

# ---------------------------------------------------------------------------------------------------------------------
echo "== collect: classification of seven commits"
collect_once
U="$OUT/units-commits-1-of-1.jsonl"
[[ "$RC" -eq 0 && -s "$U" ]] && pass "collect exits 0 and writes units" || fail "collect exits 0 and writes units (rc=$RC)"
[[ "$(wc -l < "$U" 2>/dev/null)" -eq 7 ]] && pass "seven units, one per commit" || fail "seven units, one per commit"
[[ "$(unit_field "$U" "${C[0]}" .cls)" = clean ]] && pass "c1 green merge_group run is clean" || fail "c1 green merge_group run is clean"
[[ "$(unit_field "$U" "${C[0]}" '.skipped_suites|join(",")')" = "scripts/suitex,scripts/suitey" ]] \
  && pass "c1 skips exactly the sel=0 non-always_on suites" || fail "c1 skips exactly the sel=0 non-always_on suites"
[[ "$(unit_field "$U" "${C[0]}" .skipped_min)" = 2.5 ]] && pass "c1 skipped minutes are read from the durations file (2 + 0.5)" || fail "c1 skipped minutes (got $(unit_field "$U" "${C[0]}" .skipped_min))"
[[ "$(unit_field "$U" "${C[1]}" .cls)" = rule-irrelevant ]] && pass "c2 a failure in a SELECTED suite is rule-irrelevant" || fail "c2 a failure in a SELECTED suite is rule-irrelevant"
[[ "$(unit_field "$U" "${C[2]}" .cls)" = unverified ]] && pass "c3 a failure in a would-skip suite with no clearance is unverified" || fail "c3 would-skip failure is unverified (got $(unit_field "$U" "${C[2]}" .cls))"
[[ "$(unit_field "$U" "${C[2]}" '.would_skip_failures|join(",")')" = scripts/suitey && "$(unit_field "$U" "${C[2]}" '.failing[0].suites|join(",")')" = scripts/suitey ]] && pass "c3 names the would-skip suite and ignores the self-test line" || fail "c3 names the would-skip suite"
[[ "$(unit_field "$U" "${C[3]}" .cls)" = rule-irrelevant ]] && pass "c4 an e2e job failure is rule-irrelevant (the rule never skips it)" || fail "c4 an e2e job failure is rule-irrelevant"
[[ "$(unit_field "$U" "${C[4]}" .cls)" = not-evaluable ]] && pass "c5 a failed runs read is not-evaluable" || fail "c5 a failed runs read is not-evaluable"
[[ "$(unit_field "$U" "${C[4]}" .reason)" == runs-read* ]] && pass "c5 names the failed read" || fail "c5 names the failed read (got $(unit_field "$U" "${C[4]}" .reason))"
[[ "$(unit_field "$U" "${C[5]}" .cls)" = clean ]] && pass "c6 a same-tree green merge_group run clears a push failure" || fail "c6 a same-tree green run clears a push failure"
[[ "$(unit_field "$U" "${C[5]}" .fallback)" = runner-changed && "$(unit_field "$U" "${C[5]}" '.skipped_min == 0')" = true ]] \
  && pass "c6 a runner-changed fallback skips nothing" || fail "c6 a runner-changed fallback skips nothing"
[[ "$(unit_field "$U" "${C[6]}" .cls)" = not-evaluable && "$(unit_field "$U" "${C[6]}" .reason)" = failed-job-without-fail-line ]] \
  && pass "c7 a failed shard with no FAIL line is not-evaluable" || fail "c7 a failed shard with no FAIL line is not-evaluable"
! grep -q STUB-MISS "$GHLOG" && pass "collect made no request the stub does not know" || fail "collect made an unknown request: $(grep STUB-MISS "$GHLOG" | head -2)"

echo "== collect: resumability and chunking"
before="$(wc -l < "$U")"
run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" >/dev/null 2>&1
[[ "$(wc -l < "$U")" -eq "$before" ]] && pass "a second run appends nothing (resumable per unit)" || fail "a second run appends nothing"
rm -rf "$OUT"; mkdir -p "$OUT"
run_sut collect --out "$OUT" --commits 7 --chunk 2/3 --repo "$R" >/dev/null 2>&1
[[ "$(wc -l < "$OUT/units-commits-2-of-3.jsonl")" -eq 2 ]] && pass "chunk 2/3 of 7 holds two units (indices 1 and 4)" || fail "chunk 2/3 of 7 holds two units"
run_sut collect --out "$OUT" --chunk 0/3 --repo "$R" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "a malformed --chunk is refused with rc 2" || fail "a malformed --chunk is refused with rc 2 (rc=$rc)"

echo "== aggregate: rates, the worst-case bound, the saving"
collect_once
run_sut aggregate "$OUT" --out "$SANDBOX/agg.txt" > "$SANDBOX/agg.out" 2>&1; rc=$?
[[ "$rc" -eq 0 ]] && pass "aggregate exits 0" || fail "aggregate exits 0 (rc=$rc)"
grep -q "attributable=0/7 unverified_as_escape=1/7" "$SANDBOX/agg.out" && pass "one unverified unit counts as an escape for the gating point estimate" || fail "unverified counts as escape: $(grep attributable "$SANDBOX/agg.out" | head -1)"
grep -q "worst_case=3/7" "$SANDBOX/agg.out" && pass "the worst case adds the two not-evaluable units (3 of 7)" || fail "worst case 3/7: $(grep attributable "$SANDBOX/agg.out" | head -1)"
bound="$(python3 "$SUT" cp-upper 3 7)"
grep -q "cp95_upper_on_worst_case=$(python3 -c "print('%.2f'%(100*$bound))")%" "$SANDBOX/agg.out" && pass "the bound is computed on the WORST-CASE numerator" || fail "the bound is computed on the worst-case numerator"
grep -q "^saving commits=7 .*mean_skipped_suite_min=1.86 " "$SANDBOX/agg.out" && pass "mean saving is 13 skipped minutes over 7 commits, with the runner-changed commit counted as zero" || fail "mean saving: $(grep '^saving' "$SANDBOX/agg.out")"
grep -q "rule_sha256=$(printf '%s' "$(python3 -c "import importlib.util as u;s=u.spec_from_file_location('m','$SUT');m=u.module_from_spec(s);s.loader.exec_module(m);print(m.RULE_TEXT)")" | sha256sum | cut -d' ' -f1)" "$SANDBOX/agg.out" && pass "the receipt carries the rule text hash" || fail "the receipt carries the rule text hash"
[[ -s "$SANDBOX/agg.txt.tsv" ]] && pass "aggregate writes the per-unit tsv beside the summary" || fail "aggregate writes the per-unit tsv"

echo "== ejections: clearance and the multi-unit flake class"
since="2031-01-01T00:00:00Z"
mg_runs() { printf '{"total_count":%s,"workflow_runs":[%s]}' "$2" "$1"; }
mgrun() { printf '{"id":%s,"event":"merge_group","conclusion":"%s","run_attempt":1,"created_at":"2031-01-0%sT00:00:00Z","head_sha":"%s","head_branch":"gh-readonly-queue/main/pr-%s-base"}' "$1" "$2" "$3" "$4" "$5"; }
EJ="$SANDBOX/ej"; mkdir -p "$EJ"
SH1=1111111111111111111111111111111111111111; SH2=2222222222222222222222222222222222222222
SH3=3333333333333333333333333333333333333333; SH4=4444444444444444444444444444444444444444
SH5=5555555555555555555555555555555555555555; SH6=6666666666666666666666666666666666666666
SH7=7777777777777777777777777777777777777777; SH8=8888888888888888888888888888888888888888
mg_runs "$(mgrun 8001 failure 1 $SH1 11),$(mgrun 8002 success 2 $SH2 11),$(mgrun 8003 failure 3 $SH3 12),$(mgrun 8004 failure 4 $SH4 13),$(mgrun 8005 failure 5 $SH5 14),$(mgrun 8006 failure 6 $SH6 15),$(mgrun 8007 failure 7 $SH7 16),$(mgrun 8008 failure 8 $SH8 17)" 8 \
  | fx "repos/$R/actions/workflows/ci.yml/runs?event=merge_group&created=$since..NOW&per_page=100"
cfiles() { printf '{"files":[%s]}' "$1"; }
cfile() { printf '{"filename":"%s"}' "$1"; }
cfiles "$(cfile doc/q.md)" | fx "repos/$R/commits/$SH1?per_page=100"
cfiles "$(cfile doc/q.md)" | fx "repos/$R/commits/$SH2?per_page=100"
cfiles "$(cfile doc/r.md)" | fx "repos/$R/commits/$SH3?per_page=100"
cfiles "$(cfile doc/s.md)" | fx "repos/$R/commits/$SH4?per_page=100"
cfiles "$(cfile doc/t.md)" | fx "repos/$R/commits/$SH5?per_page=100"
cfiles "$(cfile x.txt)" | fx "repos/$R/commits/$SH6?per_page=100"
cfiles "$(cfile doc/v.md)" | fx "repos/$R/commits/$SH7?per_page=100"
cfiles "$(cfile doc/w.md)" | fx "repos/$R/commits/$SH8?per_page=100"
for rid in 8001 8003 8004 8005; do
  jobs_body "$rid" "95${rid}1:test-scripts (1/8):failure" "95${rid}2:test:failure" | fx "$(jobs_path "$rid")"
  printf '[FAIL] scripts/suitey (90ms) log=/l/y.log\n' | fx "$(log_path "95${rid}1")"
done
for rid in 8006 8007 8008; do
  jobs_body "$rid" "95${rid}1:test-scripts (1/8):failure" | fx "$(jobs_path "$rid")"
  printf '[FAIL] scripts/suitex (90ms) log=/l/x.log\n' | fx "$(log_path "95${rid}1")"
done
rm -rf "$OUT"; mkdir -p "$OUT"
: > "$GHLOG"
run_sut ejections --out "$OUT" --since "$since" --repo "$R" > "$SANDBOX/ej.out" 2>&1; rc=$?
EU="$OUT/units-ejections.jsonl"
[[ "$rc" -eq 0 && "$(wc -l < "$EU")" -eq 7 ]] && pass "ejections: seven failed queue runs become seven units" || fail "ejections: seven failed queue runs (rc=$rc, lines=$(wc -l < "$EU" 2>/dev/null)) $(tail -2 "$SANDBOX/ej.out")"
[[ "$(unit_field "$EU" "$SH1" .cls)" = flake-cleared && "$(unit_field "$EU" "$SH1" .reason)" = identical-tree-green ]] \
  && pass "a later queue run of the same PR with the identical file set clears the failure" || fail "identical-tree clearance (got $(unit_field "$EU" "$SH1" .cls))"
[[ "$(unit_field "$EU" "$SH6" .cls)" = rule-irrelevant ]] && pass "a failure in a suite the rule would RUN is rule-irrelevant" || fail "selected-suite ejection is rule-irrelevant (got $(unit_field "$EU" "$SH6" .cls))"
[[ "$(unit_field "$EU" "$SH3" .cls)" = unverified ]] && pass "an uncleared would-skip failure starts as unverified" || fail "uncleared would-skip failure is unverified"
! grep -q STUB-MISS "$GHLOG" && pass "ejections made no unknown request" || fail "ejections made an unknown request: $(grep STUB-MISS "$GHLOG" | head -2)"
run_sut aggregate "$OUT" > "$SANDBOX/ej-agg.out" 2>&1
grep -q "multi_unit_flake_suites=scripts/suitey" "$SANDBOX/ej-agg.out" && pass "a suite failing in 3 units with 3 distinct file sets is a flake class" || fail "multi-unit flake class: $(grep multi "$SANDBOX/ej-agg.out")"
grep -q '"flake-cleared": 4' "$SANDBOX/ej-agg.out" && pass "the flake class reclassifies its units (1 identical-tree + 3 multi-unit)" || fail "flake reclassification: $(grep population "$SANDBOX/ej-agg.out" | head -1)"
grep -q '"unverified": 2' "$SANDBOX/ej-agg.out" && pass "a suite that fails in only two units stays unverified (below the flake threshold)" || fail "two-unit failure stays unverified: $(grep population "$SANDBOX/ej-agg.out" | head -1)"

echo "== cp-upper and verdict"
v="$(python3 "$SUT" cp-upper 6 300)"
awk -v v="$v" 'BEGIN{exit !(v>0.0385 && v<0.0397)}' && pass "cp-upper 6/300 is about 3.9% (the plan's figure)" || fail "cp-upper 6/300 (got $v)"
v="$(python3 "$SUT" cp-upper 0 300)"
awk -v v="$v" 'BEGIN{exit !(v>0.0098 && v<0.0101)}' && pass "cp-upper 0/300 is about 0.99%" || fail "cp-upper 0/300 (got $v)"
[[ "$(python3 "$SUT" cp-upper 7 7)" = 1.000000 && "$(python3 "$SUT" cp-upper 0 0)" = 1.000000 ]] && pass "cp-upper k>=n and n=0 are 1" || fail "cp-upper edge cases"
ST=(pass fail within-10% unmeasured)
bad=0; seen=0
for a in "${ST[@]}"; do for b in "${ST[@]}"; do for c in "${ST[@]}"; do for d in "${ST[@]}"; do
  got="$(python3 "$SUT" verdict --a "$a" --b "$b" --c "$c" --d "$d")"
  nf=0; nu=0; nw=0
  for x in "$a" "$b" "$c" "$d"; do case "$x" in fail) nf=$((nf+1));; unmeasured) nu=$((nu+1));; within-10%) nw=$((nw+1));; esac; done
  if [[ $nf -gt 0 ]]; then want="NO-GO"; elif [[ $((nu + nw)) -gt 0 ]]; then want="UNDECIDED"; else want="GO"; fi
  seen=$((seen+1))
  [[ "$got" == "computed=$want "* ]] || { bad=$((bad+1)); echo "  verdict $a $b $c $d: got '$got' want $want" >&2; }
done; done; done; done
[[ "$seen" -eq 256 && "$bad" -eq 0 ]] && pass "the verdict function is total over 256 combinations and matches the independent oracle" || fail "verdict table ($bad bad of $seen)"
python3 "$SUT" verdict --a pass --b pass --c nope --d pass >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "an unknown criterion status is refused with rc 2" || fail "an unknown criterion status is refused (rc=$rc)"

echo "== audit: the PR 9404 shape"
AREPO="$SANDBOX/arepo"
assert_fixture_dir "$AREPO"
mkdir -p "$AREPO/scripts" "$AREPO/.github/workflows"
printf 'name: ci\n' > "$AREPO/.github/workflows/ci.yml"
printf '#!/usr/bin/env bash\ncat .github/workflows/ci.yml\nbash scripts/guard-vacuity-floor.test.sh\n' > "$AREPO/scripts/lint-orphan-mutations.test.sh"
printf '#!/usr/bin/env bash\n# reads nothing tracked but itself\n' > "$AREPO/scripts/guard-vacuity-floor.test.sh"
printf '#!/usr/bin/env bash\ncat .github/workflows/ci.yml\n' > "$AREPO/scripts/declared-complete.test.sh"
printf '#!/usr/bin/env bash\n# mentions .github/workflows/ci.yml only in a comment\ntrue\n' > "$AREPO/scripts/comment-only.test.sh"
printf '#!/usr/bin/env bash\ngrep -q x scripts/test-all.sh\n' > "$AREPO/scripts/names-the-runner.test.sh"
printf '#!/usr/bin/env bash\n' > "$AREPO/scripts/test-all.sh"
(cd "$AREPO" && gitq init -q -b main . && gitq add -A && gitq commit -qm seed) || { echo "[FATAL] audit fixture" >&2; exit 1; }
printf 'AFFECTED_SELECTED\tscripts/lint-orphan-mutations\t0\tedge:declared\t^scripts/lint-orphan-mutations.test.sh\n' > "$SANDBOX/audit-bad.rows"
printf 'AFFECTED_SELECTED\tscripts/declared-complete\t0\tedge:declared\t^scripts/declared-complete.test.sh|^.github/workflows/ci.yml\n' > "$SANDBOX/audit-good.rows"
printf 'AFFECTED_SELECTED\tscripts/comment-only\t0\tedge:derived\t^scripts/comment-only.test.sh\n' > "$SANDBOX/audit-comment.rows"
printf 'AFFECTED_SELECTED\tscripts/names-the-runner\t0\tedge:derived\t^scripts/names-the-runner.test.sh\n' > "$SANDBOX/audit-runner.rows"
run_sut audit --root "$AREPO" --list "$SANDBOX/audit-bad.rows" > "$SANDBOX/audit-bad.out" 2>&1; rc=$?
[[ "$rc" -eq 1 ]] && grep -q 'gap_suites=1' "$SANDBOX/audit-bad.out" && pass "a -mutations sibling that reads ci.yml and a sibling suite but declares only its own file is flagged" || fail "the PR 9404 shape is flagged (rc=$rc: $(tail -2 "$SANDBOX/audit-bad.out"))"
grep -q 'ci.yml' "$SANDBOX/audit-bad.out" && grep -q 'guard-vacuity-floor.test.sh' "$SANDBOX/audit-bad.out" && pass "the gap line names both undeclared inputs" || fail "the gap line names both undeclared inputs"
run_sut audit --root "$AREPO" --list "$SANDBOX/audit-good.rows" > "$SANDBOX/audit-good.out" 2>&1; rc=$?
[[ "$rc" -eq 0 ]] && grep -q 'gap_suites=0' "$SANDBOX/audit-good.out" && pass "a suite whose reads are all declared has no gap (must-pass control)" || fail "a fully declared suite has no gap (rc=$rc)"
run_sut audit --root "$AREPO" --list "$SANDBOX/audit-comment.rows" > "$SANDBOX/audit-comment.out" 2>&1; rc=$?
[[ "$rc" -eq 0 ]] && grep -q 'gap_suites=0' "$SANDBOX/audit-comment.out" && pass "a path named only in a comment is a mention, not a read (no gap)" || fail "comment-only mention is not a gap (rc=$rc)"
run_sut audit --root "$AREPO" --list "$SANDBOX/audit-runner.rows" > "$SANDBOX/audit-runner.out" 2>&1; rc=$?
[[ "$rc" -eq 0 ]] && grep -q 'gap_suites=0' "$SANDBOX/audit-runner.out" && pass "a suite that names the runner is covered by the runner-changed trigger (no gap)" || fail "runner path is covered by the trigger list (rc=$rc)"
: > "$SANDBOX/audit-empty.rows"
run_sut audit --root "$AREPO" --list "$SANDBOX/audit-empty.rows" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "an audit that examined zero suites exits non-zero (anti-vacuity)" || fail "an audit that examined zero suites exits non-zero (rc=$rc)"

# ---------------------------------------------------------------------------------------------------------------------
echo "== mutation rows (each edit must land and the named row must fail)"
MUT_RUN=0; MUT_KILLED=0
mutate() {  # mutate <name> <old> <new> <row-function>
  local name="$1" old="$2" new="$3" row="$4" m="$SANDBOX/mut-$1.py" got
  cp "$REAL_SUT" "$m" || { fail "mutant $name: copy"; return; }
  python3 - "$m" "$old" "$new" <<'PY' || { fail "mutant $name: the edit did not land exactly once"; return; }
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
assert s.count(old) == 1, "count=%d" % s.count(old)
open(p, "w").write(s.replace(old, new))
PY
  cmp -s "$m" "$REAL_SUT" && { fail "mutant $name: the mutation did not change the file"; return; }
  MUT_RUN=$((MUT_RUN + 1))
  SUT="$m"; "$row" >/dev/null 2>&1; got=$?; SUT="$REAL_SUT"
  if [[ "$got" -ne 0 ]]; then MUT_KILLED=$((MUT_KILLED + 1)); pass "mutant $name is killed by $row"; else fail "mutant $name SURVIVED $row"; fi
}
row_always_on() { collect_once; [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[0]}" '.skipped_suites|join(",")')" = "scripts/suitex,scripts/suitey" ]]; }
row_fallback() { collect_once; [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[5]}" .skipped_min)" = 0 ]]; }
row_read_error() { collect_once; [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[4]}" .reason)" == runs-read* ]]; }
row_worst_bound() { collect_once; run_sut aggregate "$OUT" 2>&1 | grep -q "cp95_upper_on_worst_case=$(python3 -c "print('%.2f'%(100*$(python3 "$REAL_SUT" cp-upper 3 7)))")%"; }
row_flake_threshold() { rm -rf "$OUT"; mkdir -p "$OUT"; run_sut ejections --out "$OUT" --since "$since" --repo "$R" >/dev/null 2>&1; run_sut aggregate "$OUT" 2>&1 | grep -q '"unverified": 2'; }
row_verdict_fail() { [[ "$(python3 "$SUT" verdict --a pass --b fail --c pass --d pass)" == "computed=NO-GO "* ]]; }
row_unmeasured() { [[ "$(python3 "$SUT" verdict --a pass --b pass --c unmeasured --d pass)" == "computed=UNDECIDED reason=incomplete" ]]; }
row_selftest_line() { collect_once; [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[2]}" '.failing[0].suites|join(",")')" = scripts/suitey ]]; }
row_clear() { collect_once; [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[5]}" .cls)" = clean ]]; }
row_audit_comment() { run_sut audit --root "$AREPO" --list "$SANDBOX/audit-comment.rows" 2>&1 | grep -q 'gap_suites=0'; }
row_audit_runner() { run_sut audit --root "$AREPO" --list "$SANDBOX/audit-runner.rows" 2>&1 | grep -q 'gap_suites=0'; }
row_audit_bad() { run_sut audit --root "$AREPO" --list "$SANDBOX/audit-bad.rows" 2>&1 | grep -q 'gap_suites=1'; }
row_audit_zero() { run_sut audit --root "$AREPO" --list "$SANDBOX/audit-empty.rows" >/dev/null 2>&1; [[ $? -eq 2 ]]; }
mutate always-on-skippable 'elif f[2] == "0" and f[3] != "always_on":' 'elif f[2] == "0":' row_always_on
mutate fallback-ignored '    if fb == "none":
        u["skipped_suites"] = skipped' '    if True:
        u["skipped_suites"] = skipped' row_fallback
mutate read-error-as-no-run 'runs, u["reason"] = None, "runs-read: %s" % e' 'runs, u["reason"] = [], ""' row_read_error
mutate bound-on-point-numerator 'cp_upper(attributable + unverified + ne, n)' 'cp_upper(attributable + unverified, n)' row_worst_bound
mutate flake-threshold-one 'len(us) >= 3 and len' 'len(us) >= 1 and len' row_flake_threshold
mutate verdict-fail-dropped 'if "fail" in s:' 'if False:' row_verdict_fail
mutate unmeasured-as-pass 'if "unmeasured" in s:' 'if False:' row_unmeasured
mutate fail-regex-loosened 'FAIL_LINE = re.compile(r"^\[FAIL\] (\S+) \((\d+)ms\) log=")' 'FAIL_LINE = re.compile(r"^\[FAIL\] (\S+)")' row_selftest_line
mutate same-tree-ignored 'pick = ok[0] if ok else sorted(runs, key=lambda r: r["created_at"])[-1]' 'pick = sorted(runs, key=lambda r: r["created_at"])[0]' row_clear
mutate audit-comments-counted '        if t.startswith("#") or t.startswith("//"):
            continue' '        if False:
            continue' row_audit_comment
mutate audit-runner-not-excused 'f not in (suite,) and f not in RUNNER_TRIGGERS and len(f) > 6' 'f not in (suite,) and len(f) > 6' row_audit_runner
mutate audit-gap-blind 'miss = [r for r in refs if not any(rg.search(r) for rg in regs)]' 'miss = [r for r in refs if False]' row_audit_bad
mutate audit-zero-suites 'if suites == 0:' 'if False:' row_audit_zero

# ---------------------------------------------------------------------------------------------------------------------
echo "== controls: a survivor and a crash are both reportable"
if [[ "$MUT_KILLED" -eq "$MUT_RUN" ]]; then pass "every mutant was killed ($MUT_KILLED of $MUT_RUN)"; else fail "mutants killed $MUT_KILLED of $MUT_RUN"; fi

# Anti-vacuity floors, reported through printf + exit so they never ride on the helpers they guard.
FLOOR_ASSERTIONS=58
total=$((passes + fails))
if [[ "$total" -lt "$FLOOR_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$total" "$FLOOR_ASSERTIONS" >&2; exit 1
fi
FLOOR_MUTANTS=13
if [[ "$MUT_RUN" -lt "$FLOOR_MUTANTS" ]]; then
  printf '[FATAL] mutation floor: only %s mutants ran, floor is %s\n' "$MUT_RUN" "$FLOOR_MUTANTS" >&2; exit 1
fi
echo "ci-pr-affected-replay.test.sh: $passes passed, $fails failed, $total assertions, $MUT_RUN mutants"
[[ "$fails" -eq 0 ]] && exit 0
printf 'FAILED: %s\n' "${FAILED[@]}" >&2
exit 1
