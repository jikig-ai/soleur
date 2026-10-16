#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016,SC2034,SC1091  # rows are dispatched indirectly; A && B || why is the assertion idiom; some programs are single-quoted on purpose
# Suite for scripts/ci-pr-affected-replay.py (S4 PR C, #9729, ADR-276): the escape-rate replay and the go/no-go arithmetic.
#
# THE SEAMS. `gh` is a PATH stub keyed on the request path (the `created=` window is collapsed, because the SUT
# stamps it with the clock) that refuses an unknown request with exit 64 and logs `STUB-MISS`; a fixture file
# named ERR_<key> makes a request fail with rc 1. The selector is PR_AFFECTED_REPLAY_TEST_ALL, a stub that prints
# AFFECTED_SELECTED rows decided by the path list. The repository is a synthesized git repo with an origin/main ref.
#
# WHAT IS PINNED. A failed READ is never "no failure" (not-evaluable, with the read named: a 5xx is retried, a 4xx is
# asked once, a hang is killed at the timeout, a truncated or empty list is a failed read); a failed suite counts
# against the rule only when the rule would have skipped it; a clearance is a CONTENT claim ((name, blob) pairs, a
# later run of the same PR, never an earlier one, never a branch that names no PR); an escape is read from attempt
# 1's jobs and logs, never inferred from run_attempt; a suite that fails in three units from three distinct PRs
# with two distinct file sets is a flake class and one that fails once is not, and a flake class never clears an
# escape; the worst-case numerator (not-evaluable included) feeds the 95% bound; the verdict function is total
# over all 256 status combinations; the audit flags the PR 9404 shape, counts an unread suite as UNAUDITED (exit
# 1), exempts always_on suites and reads the selector's own `^glob:` edge. The selector subprocess sees an
# allowlisted environment (no credential, no CI switch, no git location variable).
# MUTATION ROWS copy the SUT and apply ONE edit; the harness requires the edit to land once, the mutant to parse,
# the row to be GREEN on the pristine SUT, and the row to then FAIL on the mutant; controls prove it reports a
# survivor, an unparseable mutant, a red row and an edit that did not land. The anti-vacuity floor and the
# instrument self-test report through printf + exit, never through the pass()/fail() pair they backstop.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/git-fixture-env.sh
source "$SCRIPT_DIR/lib/git-fixture-env.sh"   # arms the git-location tripwire and gives git_fixture_env (one list, one builder)
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

git_fixture_env "$SANDBOX/repo" || { echo "[FATAL] git_fixture_env refused the sandbox" >&2; exit 1; }   # ceiling, identity, hermetic config: ONE builder
gitq() { git -c commit.gpgsign=false -c maintenance.auto=false -c gc.auto=0 -c init.defaultBranch=main "$@"; }

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
    GIT_AUTHOR_DATE="2031-01-01T00:00:00Z" GIT_COMMITTER_DATE="2031-01-01T00:00:00Z" gitq add -A \
      && GIT_AUTHOR_DATE="2031-01-01T00:00:00Z" GIT_COMMITTER_DATE="2031-01-01T00:00:00Z" gitq commit -qm seed || exit 1
    n=0
    for f in doc/a.md x.txt doc/c.md doc/d.md doc/e.md scripts/runner.sh doc/g.md; do
      n=$((n + 1)); mkdir -p "$(dirname "$REPO/$f")"; printf 'v%s\n' "$n" > "$REPO/$f"
      # one distinct committer second per commit, so the default ejection window has two different ends
      GIT_AUTHOR_DATE="2031-01-0$((n + 1))T12:00:00Z" GIT_COMMITTER_DATE="2031-01-0$((n + 1))T12:00:00Z" gitq add -A \
        && GIT_AUTHOR_DATE="2031-01-0$((n + 1))T12:00:00Z" GIT_COMMITTER_DATE="2031-01-0$((n + 1))T12:00:00Z" gitq commit -qm "c$n $f" || exit 1
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
if [ -n "${PR_AFFECTED_REPLAY_SEL_ENV_DUMP:-}" ]; then env > "$PR_AFFECTED_REPLAY_SEL_ENV_DUMP"; fi
fb=none
case ",$paths," in *,scripts/runner.sh,*) fb=runner-changed ;; esac
if [ "$fb" != none ]; then
  # a fallback runs the FULL battery and prints no per-suite rows
  printf 'AFFECTED_FALLBACK\treason=%s\n' "$fb"
  printf 'AFFECTED_SUMMARY selected=all of=all always_on=all edge=all fallback=%s\n' "$fb"
  exit 0
fi
x=0; case ",$paths," in *,x.txt,*) x=1 ;; esac
printf 'AFFECTED_SELECTED\tscripts/lib/a\t1\talways_on\t^scripts/lib/a\n'
printf 'AFFECTED_SELECTED\tscripts/suitex\t%s\tedge:declared\t^x.txt|^scripts/suitex.test.sh\n' "$x"
printf 'AFFECTED_SELECTED\tscripts/suitey\t0\tedge:derived\t^scripts/suitey.test.sh\n'
printf 'AFFECTED_SELECTED\tscripts/suitez\t0\talways_on\t^scripts/suitez.test.sh\n'
printf 'AFFECTED_SUMMARY selected=2 of=4 always_on=1 edge=0 fallback=%s\n' "$fb"
SEL
chmod +x "$BIN/sel.sh"
printf '#!/usr/bin/env bash\necho "selector exploded" >&2\nexit 3\n' > "$BIN/sel-fail.sh"; chmod +x "$BIN/sel-fail.sh"

cat > "$BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
# gh api [--allow-escape-sequences] [--paginate] <path>
[ "${1:-}" = api ] || { echo "STUB-MISS argv=$*" >> "$GH_LOG"; exit 64; }
shift
path=""; esc=0
for a in "$@"; do case "$a" in --allow-escape-sequences) esc=1 ;; --paginate) : ;; *) path="$a" ;; esac; done
key="$(printf '%s' "$path" | sed -E 's/created=[^&]*/created=X/' | tr -c 'A-Za-z0-9\n' '_')"
printf 'REQ %s\n' "$key" >> "$GH_LOG"
# a job log is fetched with --allow-escape-sequences or gh refuses it: the stub refuses it too
case "$path" in */logs) [ "$esc" = 1 ] || { echo "STUB-MISS no --allow-escape-sequences on $key" >> "$GH_LOG"; echo "gh: refusing escape sequences" >&2; exit 1; } ;; esac
if [ -f "$GH_FIX/ERR_$key" ]; then echo "gh: HTTP 502" >&2; exit 1; fi
if [ -f "$GH_FIX/ERR404_$key" ]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
if [ -f "$GH_FIX/ERR403RL_$key" ]; then echo "gh: API rate limit exceeded (HTTP 403)" >&2; exit 1; fi
if [ -f "$GH_FIX/HANG_$key" ]; then sleep 2; echo '{"total_count":0,"workflow_runs":[]}'; exit 0; fi
if [ -f "$GH_FIX/$key" ]; then cat "$GH_FIX/$key"; exit 0; fi
echo "STUB-MISS $key" >> "$GH_LOG"; exit 64
GHSTUB
chmod +x "$BIN/gh"
export GH_LOG="$GHLOG" GH_FIX="$GHFIX"

R=jikig-ai/soleur
R2=jikig-ai/other      # a second repository name: its fixtures never collide with the first scenario set
keyof() { printf '%s' "$1" | sed -E 's/created=[^&]*/created=X/' | tr -c 'A-Za-z0-9\n' '_'; }
fx() { local k; k="$(keyof "$1")"; cat > "$GHFIX/$k"; }          # fx <path> < body
fx_err() { : > "$GHFIX/ERR_$(keyof "$1")"; }
fx_err404() { : > "$GHFIX/ERR404_$(keyof "$1")"; }
fx_hang() { : > "$GHFIX/HANG_$(keyof "$1")"; }
fx_err403rl() { : > "$GHFIX/ERR403RL_$(keyof "$1")"; }
runs_path() { printf 'repos/%s/actions/workflows/ci.yml/runs?head_sha=%s&per_page=100' "${REPO_NAME:-$R}" "$1"; }
jobs_path() { printf 'repos/%s/actions/runs/%s/jobs?per_page=100&filter=latest' "${REPO_NAME:-$R}" "$1"; }
jobs1_path() { printf 'repos/%s/actions/runs/%s/attempts/1/jobs?per_page=100' "${REPO_NAME:-$R}" "$1"; }
log_path() { printf 'repos/%s/actions/jobs/%s/logs' "${REPO_NAME:-$R}" "$1"; }
runs_body() {  # runs_body <sha> then id:event:conclusion[:attempt]
  local sha="$1"; shift; local first=1 item id ev concl att
  printf '{"total_count":%s,"workflow_runs":[' "$#"
  for item in "$@"; do
    IFS=: read -r id ev concl att <<<"$item"
    [ "$first" = 1 ] || printf ','; first=0
    printf '{"id":%s,"event":"%s","conclusion":"%s","run_attempt":%s,"created_at":"2031-01-0%sT00:00:00Z","head_sha":"%s"}' "$id" "$ev" "$concl" "${att:-1}" "${id: -1}" "$sha"
  done
  printf ']}'
}
jobs_body() {  # jobs_body <runid> then id:name:conclusion   (JOBS_TOTAL pins a total_count)
  local first=1 item id name concl
  printf '{%s"jobs":[' "${JOBS_TOTAL:+\"total_count\":$JOBS_TOTAL,}"
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
runs_body "${C[1]}" "2001:push:failure" "2002:pull_request:success" | fx "$(runs_path "${C[1]}")"
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

RUN_ENV=()
run_sut() {  # run_sut <args...>; the repo is the cwd, the selector and gh are stubs; prints stdout, rc in $RC
  ( cd "$REPO" && env PATH="$BIN:$PATH" PR_AFFECTED_REPLAY_TEST_ALL="$BIN/sel.sh" PR_AFFECTED_REPLAY_RETRY_SLEEP=0 HOME="$FIXHOME" "${RUN_ENV[@]}" python3 "$SUT" "$@" )
}
unit_field() {  # unit_field <jsonl> <sha> <jq expr>
  jq -r --arg s "$2" "select(.sha==\$s) | $3" "$1"
}
reqs() { grep -c "^REQ $(keyof "$1")\$" "$GHLOG"; }   # how many times the stub saw this request

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
[[ "$(reqs "$(runs_path "${C[4]}")")" -eq 3 ]] && pass "a transient (5xx) read failure is retried: three requests for the broken runs read" || fail "transient retry count (got $(reqs "$(runs_path "${C[4]}")"))"

echo "== collect: the environment the selector and git see"
rm -rf "$OUT"; mkdir -p "$OUT"; SELDUMP="$SANDBOX/sel-env.txt"; rm -f "$SELDUMP"; mkdir -p "$SANDBOX/decoy.git"
RUN_ENV=(GH_TOKEN=ghs_notasecret CI=true GITHUB_OUTPUT=/dev/null SOLEUR_TEST_FORCE_ALL=1 PR_AFFECTED_REPLAY_SEL_ENV_DUMP="$SELDUMP" GIT_DIR="$SANDBOX/decoy.git" GIT_INDEX_FILE="$SANDBOX/decoy.index")
run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" >/dev/null 2>&1; rc=$?
RUN_ENV=()
[[ -s "$SELDUMP" ]] && ! grep -qE '^(GH_TOKEN|CI|GITHUB_OUTPUT|SOLEUR_TEST_FORCE_ALL|GIT_DIR|GIT_INDEX_FILE)=' "$SELDUMP" \
  && [[ "$(sed -n 's/^HOME=//p' "$SELDUMP")" != "$FIXHOME" && -n "$(sed -n 's/^HOME=//p' "$SELDUMP")" ]] \
  && pass "the selector subprocess sees no credential, no CI switch, no git location variable and a scratch HOME (allowlisted env)" || fail "selector env leaks: $(grep -E '^(GH_TOKEN|CI|GITHUB_OUTPUT|SOLEUR_TEST_FORCE_ALL|GIT_DIR|GIT_INDEX_FILE)=' "$SELDUMP" 2>/dev/null | cut -d= -f1 | tr '\n' ' ')"
[[ "$(wc -l < "$OUT/units-commits-1-of-1.jsonl" 2>/dev/null)" -eq 7 ]] && pass "an inherited GIT_DIR does not redirect the replay's git reads (the seven commits still resolve)" || fail "GIT_DIR redirected the replay (rc=$rc)"

echo "== collect: selection errors, the redo flag, reclassify, a torn last line"
rm -rf "$OUT"; mkdir -p "$OUT"
( cd "$REPO" && env PATH="$BIN:$PATH" PR_AFFECTED_REPLAY_TEST_ALL="$BIN/sel-fail.sh" PR_AFFECTED_REPLAY_RETRY_SLEEP=0 HOME="$FIXHOME" python3 "$SUT" collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" >/dev/null 2>&1 )
SU="$OUT/units-commits-1-of-1.jsonl"
[[ "$(unit_field "$SU" "${C[0]}" .cls)" = clean && "$(unit_field "$SU" "${C[0]}" .fallback)" = selection-error ]] \
  && pass "a selector failure on a green unit is recorded as selection-error and does not fake a clean saving" || fail "selector failure on a green unit (got $(unit_field "$SU" "${C[0]}" '.cls+" "+.fallback'))"
[[ "$(unit_field "$SU" "${C[6]}" .cls)" = not-evaluable && "$(unit_field "$SU" "${C[6]}" .reason)" == selection:* ]] \
  && pass "a selector failure on a failing unit is not-evaluable, with the selection named" || fail "selector failure on a failing unit (got $(unit_field "$SU" "${C[6]}" '.cls+" "+.reason'))"
collect_once
rm -f "$GHFIX/ERR_$(keyof "$(runs_path "${C[4]}")")"
runs_body "${C[4]}" "5001:merge_group:success" | fx "$(runs_path "${C[4]}")"
before="$(wc -l < "$OUT/units-commits-1-of-1.jsonl")"
run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" >/dev/null 2>&1
[[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[4]}" .cls)" = not-evaluable ]] && pass "without --redo-unevaluable a frozen not-evaluable row stays (resume never re-reads it)" || fail "a frozen not-evaluable row stays without the flag"
run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" --redo-unevaluable >/dev/null 2>&1
[[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[4]}" .cls)" = clean && "$(wc -l < "$OUT/units-commits-1-of-1.jsonl")" -eq "$before" ]] \
  && pass "--redo-unevaluable re-reads the healed unit once and leaves every other row alone (7 rows, no duplicate)" || fail "--redo-unevaluable (got $(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[4]}" .cls), $(wc -l < "$OUT/units-commits-1-of-1.jsonl") rows)"
: > "$GHLOG"
run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" --reclassify >/dev/null 2>&1
[[ "$(reqs "$(runs_path "${C[0]}")")" -eq 0 && "$(reqs "$(runs_path "${C[2]}")")" -ge 1 && "$(wc -l < "$OUT/units-commits-1-of-1.jsonl")" -eq "$before" ]] \
  && pass "--reclassify re-reads every non-clean unit and leaves the clean ones unread (7 rows, no duplicate)" || fail "--reclassify (clean reads $(reqs "$(runs_path "${C[0]}")"), unverified reads $(reqs "$(runs_path "${C[2]}")"))"
fx_err "$(runs_path "${C[4]}")"   # re-break c5's runs read: every later section expects the original fixture
printf '{"kind": "commit", "sha": "torn' >> "$OUT/units-commits-1-of-1.jsonl"
run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" >/dev/null 2>&1
jq -c . "$OUT/units-commits-1-of-1.jsonl" >/dev/null 2>&1 && [[ "$(jq -s length "$OUT/units-commits-1-of-1.jsonl")" -eq 7 ]] \
  && pass "a torn last line (a write cut off by a kill) is dropped and the file stays valid JSON lines" || fail "a torn last line corrupted the units file"

echo "== collect: resumability and chunking"
before="$(wc -l < "$U")"
run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" >/dev/null 2>&1
collect_once; U="$OUT/units-commits-1-of-1.jsonl"; before="$(wc -l < "$U")"
run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" >/dev/null 2>&1
[[ "$(wc -l < "$U")" -eq "$before" ]] && pass "a second run appends nothing (resumable per unit)" || fail "a second run appends nothing"
rm -rf "$OUT"; mkdir -p "$OUT"
run_sut collect --out "$OUT" --commits 7 --chunk 2/3 --repo "$R" >/dev/null 2>&1
[[ "$(wc -l < "$OUT/units-commits-2-of-3.jsonl")" -eq 2 ]] && pass "chunk 2/3 of 7 holds two units (indices 1 and 4)" || fail "chunk 2/3 of 7 holds two units"
run_sut collect --out "$OUT" --chunk 0/3 --repo "$R" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "a malformed --chunk is refused with rc 2" || fail "a malformed --chunk is refused with rc 2 (rc=$rc)"

echo "== read failures: a 404 is not retried, a rate limit is, a hang is bounded"
R3=jikig-ai/third
REPO_NAME="$R2"; rm -rf "$OUT"; mkdir -p "$OUT"; : > "$GHLOG"
fx_err404 "$(runs_path "${C[6]}")"
( cd "$REPO" && env PATH="$BIN:$PATH" PR_AFFECTED_REPLAY_TEST_ALL="$BIN/sel.sh" PR_AFFECTED_REPLAY_RETRY_SLEEP=0 HOME="$FIXHOME" python3 "$SUT" collect --out "$OUT" --commits 1 --chunk 1/1 --repo "$R2" >/dev/null 2>&1 )
HU="$OUT/units-commits-1-of-1.jsonl"
[[ "$(reqs "$(runs_path "${C[6]}")")" -eq 1 && "$(unit_field "$HU" "${C[6]}" .cls)" = not-evaluable ]] \
  && pass "a 404 is asked once, not three times, and the unit is not-evaluable" || fail "404 retried or unit not not-evaluable (reqs $(reqs "$(runs_path "${C[6]}")"))"
REPO_NAME="$R3"; rm -rf "$OUT"; mkdir -p "$OUT"; : > "$GHLOG"
fx_err403rl "$(runs_path "${C[6]}")"
( cd "$REPO" && env PATH="$BIN:$PATH" PR_AFFECTED_REPLAY_TEST_ALL="$BIN/sel.sh" PR_AFFECTED_REPLAY_RETRY_SLEEP=0 HOME="$FIXHOME" python3 "$SUT" collect --out "$OUT" --commits 1 --chunk 1/1 --repo "$R3" >/dev/null 2>&1 )
[[ "$(reqs "$(runs_path "${C[6]}")")" -eq 3 ]] && pass "a 403 that says rate limit is retried (three requests): it is the one 4xx that clears" || fail "rate-limit retry count (got $(reqs "$(runs_path "${C[6]}")"))"
REPO_NAME="$R2"; rm -rf "$OUT"; mkdir -p "$OUT"; : > "$GHLOG"
fx_hang "$(runs_path "${C[5]}")"   # the second newest first-parent commit, in the second repository
fx_err404 "$(runs_path "${C[6]}")"
( cd "$REPO" && env PATH="$BIN:$PATH" PR_AFFECTED_REPLAY_TEST_ALL="$BIN/sel.sh" PR_AFFECTED_REPLAY_RETRY_SLEEP=0 PR_AFFECTED_REPLAY_GH_TIMEOUT=1 HOME="$FIXHOME" python3 "$SUT" collect --out "$OUT" --commits 2 --chunk 1/1 --repo "$R2" >/dev/null 2>&1 )
HU="$OUT/units-commits-1-of-1.jsonl"
[[ "$(unit_field "$HU" "${C[5]}" .cls)" = not-evaluable && "$(unit_field "$HU" "${C[5]}" .reason)" == *"timed out"* ]] \
  && pass "a gh call that hangs is killed at the timeout and the unit is not-evaluable with the timeout named" || fail "hang not bounded (got $(unit_field "$HU" "${C[5]}" '.cls+" "+.reason'))"
REPO_NAME=""

echo "== aggregate: rates, the worst-case bound, the saving, the routes"
collect_once
run_sut aggregate "$OUT" --commits-only --out "$SANDBOX/agg.txt" > "$SANDBOX/agg.out" 2>&1; rc=$?
[[ "$rc" -eq 0 ]] && pass "aggregate exits 0" || fail "aggregate exits 0 (rc=$rc)"
grep -q "attributable=0/7 unverified_as_escape=1/7" "$SANDBOX/agg.out" && pass "one unverified unit counts as an escape for the gating point estimate" || fail "unverified counts as escape: $(grep attributable "$SANDBOX/agg.out" | head -1)"
grep -q "worst_case=3/7" "$SANDBOX/agg.out" && pass "the worst case adds the two not-evaluable units (3 of 7)" || fail "worst case 3/7: $(grep attributable "$SANDBOX/agg.out" | head -1)"
bound="$(python3 "$SUT" cp-upper 3 7)"
grep -q "cp95_upper_on_worst_case=$(python3 -c "print('%.2f'%(100*$bound))")%" "$SANDBOX/agg.out" && pass "the bound is computed on the WORST-CASE numerator" || fail "the bound is computed on the worst-case numerator"
grep -q "^saving commits=7 evaluable=6 mean_skipped_suite_min=1.86 " "$SANDBOX/agg.out" && pass "mean saving is 13 skipped minutes over 7 commits, the runner-changed commit counted as zero and not as evaluable (6 of 7)" || fail "mean saving: $(grep '^saving' "$SANDBOX/agg.out")"
grep -q "selector_min=1.29 net_mean=0.57 net_mean_plus_2se=" "$SANDBOX/agg.out" && grep -q "baseline_min=99.80 bar_min=19.96" "$SANDBOX/agg.out" && pass "the net mean (saving minus the selector minutes) and the 20% bar are printed" || fail "net_mean / bar_min: $(grep '^saving' "$SANDBOX/agg.out")"
grep -q '  routes={' "$SANDBOX/agg.out" && grep -q '"clean:-": 2' "$SANDBOX/agg.out" && pass "each population prints how many units each route cleared or classed (routes=)" || fail "routes line: $(grep routes "$SANDBOX/agg.out" | head -1)"
grep -q '^attributable means: ' "$SANDBOX/agg.out" && pass "the receipt defines attributable (deterministic, uncleared) beside the count" || fail "attributable definition missing"
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
cfile() { printf '{"filename":"%s","sha":"%s"}' "$1" "${2:-b0b0b0}"; }
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
  && pass "a later queue run of the same PR with the identical (name, blob) set clears the failure" || fail "identical-tree clearance (got $(unit_field "$EU" "$SH1" .cls))"
[[ "$(unit_field "$EU" "$SH6" .cls)" = rule-irrelevant ]] && pass "a failure in a suite the rule would RUN is rule-irrelevant" || fail "selected-suite ejection is rule-irrelevant (got $(unit_field "$EU" "$SH6" .cls))"
[[ "$(unit_field "$EU" "$SH3" .cls)" = unverified ]] && pass "an uncleared would-skip failure starts as unverified" || fail "uncleared would-skip failure is unverified"
! grep -q STUB-MISS "$GHLOG" && pass "ejections made no unknown request" || fail "ejections made an unknown request: $(grep STUB-MISS "$GHLOG" | head -2)"
run_sut aggregate "$OUT" > "$SANDBOX/ej-agg.out" 2>&1
grep -q "multi_unit_flake_suites=scripts/suitey" "$SANDBOX/ej-agg.out" && pass "a suite failing in 3 units from 3 distinct PRs with 3 distinct file sets is a flake class" || fail "multi-unit flake class: $(grep multi "$SANDBOX/ej-agg.out")"
grep -q '"flake-cleared": 4' "$SANDBOX/ej-agg.out" && pass "the flake class reclassifies its units (1 identical-tree + 3 multi-unit)" || fail "flake reclassification: $(grep population "$SANDBOX/ej-agg.out" | head -1)"
grep -q '"unverified": 2' "$SANDBOX/ej-agg.out" && pass "a suite that fails in only two units stays unverified (below the flake threshold)" || fail "two-unit failure stays unverified: $(grep population "$SANDBOX/ej-agg.out" | head -1)"
run_sut ejections --out "$SANDBOX/ej-off" --since "2031-01-01T00:00:00+02:00" --repo "$R" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "--since with a UTC offset is refused (GitHub's created= filter would silently match nothing)" || fail "--since offset (rc=$rc)"
run_sut ejections --out "$SANDBOX/ej-off" --since "$since" --until "2031-01-09T00:00:00+02:00" --repo "$R" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "--until with a UTC offset is refused for the same reason" || fail "--until offset (rc=$rc)"
run_sut ejections --out "$SANDBOX/ej-win" --commits 7 --repo "$R" > "$SANDBOX/ej-win.out" 2>&1
grep -q 'window 2031-01-02T12:00:00Z\.\.2031-01-08T12:00:00Z' "$SANDBOX/ej-win.out" && pass "with no --since/--until the window is the commit window: oldest committer second to newest, both ends printed" || fail "default window line: $(tail -2 "$SANDBOX/ej-win.out" | head -1)"
grep -q 'conclusions {' "$SANDBOX/ej-win.out" && pass "the ejections run prints the conclusion histogram of every run in the window" || fail "conclusion histogram: $(tail -2 "$SANDBOX/ej-win.out")"
printf '{"total_count":0,"workflow_runs":[]}' | fx "repos/$R2/actions/workflows/ci.yml/runs?event=merge_group&created=X&per_page=100"
run_sut ejections --out "$SANDBOX/ej-zero" --since "$since" --repo "$R2" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 3 ]] && pass "a window with zero merge_group runs is a failed read (rc 3), not a clean population" || fail "empty window (rc=$rc)"
mg_runs "$(mgrun 8101 failure 1 "$SH1" 11)" 5 | fx "repos/$R2/actions/workflows/ci.yml/runs?event=merge_group&created=X&per_page=100"
run_sut ejections --out "$SANDBOX/ej-trunc" --since "$since" --repo "$R2" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 3 ]] && pass "a run list whose total_count exceeds what was read is truncated (rc 3)" || fail "truncated run list (rc=$rc)"
mg_runs "$(mgrun 8101 failure 1 "$SH1" 11)" 1000 | fx "repos/$R2/actions/workflows/ci.yml/runs?event=merge_group&created=X&per_page=100"
run_sut ejections --out "$SANDBOX/ej-cap" --since "$since" --repo "$R2" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 3 ]] && pass "a window at the API's 1000-result cap is refused (rc 3): narrow --since" || fail "result cap (rc=$rc)"

echo "== ejections: the classifier's hard cases (second repository, one window)"
SHA() { printf '%040d' "$1"; }
mgr2() { printf '{"id":%s,"event":"merge_group","conclusion":"%s","run_attempt":%s,"created_at":"2031-01-0%sT00:00:00Z","head_sha":"%s","head_branch":"%s"}' "$1" "$2" "$5" "$3" "$4" "$6"; }
qb() { printf 'gh-readonly-queue/main/pr-%s-base' "$1"; }
REPO_NAME="$R2"
RUNS2="$(mgr2 8101 failure 1 "$(SHA 101)" 2 "$(qb 21)"),$(mgr2 8102 failure 1 "$(SHA 102)" 2 "$(qb 22)"),$(mgr2 8103 failure 1 "$(SHA 103)" 2 "$(qb 23)"),$(mgr2 8104 failure 1 "$(SHA 104)" 1 "$(qb 24)"),$(mgr2 8105 success 2 "$(SHA 105)" 1 "$(qb 24)"),$(mgr2 8106 failure 1 "$(SHA 106)" 1 "$(qb 25)"),$(mgr2 8107 success 2 "$(SHA 107)" 1 "$(qb 25)"),$(mgr2 8108 success 1 "$(SHA 108)" 1 "$(qb 26)"),$(mgr2 8109 failure 2 "$(SHA 109)" 1 "$(qb 26)"),$(mgr2 8110 failure 3 "$(SHA 110)" 1 gh-readonly-queue/main/weird),$(mgr2 8111 success 4 "$(SHA 111)" 1 gh-readonly-queue/main/weird2),$(mgr2 8112 failure 1 "$(SHA 112)" 1 "$(qb 27)"),$(mgr2 8113 failure 1 "$(SHA 113)" 1 "$(qb 28)"),$(mgr2 8114 failure 1 "$(SHA 114)" 1 "$(qb 29)"),$(mgr2 8115 failure 1 "$(SHA 115)" 1 "$(qb 31)"),$(mgr2 8116 failure 1 "$(SHA 116)" 1 "$(qb 32)"),$(mgr2 8117 failure 1 "$(SHA 117)" 1 "$(qb 33)"),$(mgr2 8118 failure 1 "$(SHA 118)" 1 "$(qb 34)"),$(mgr2 8119 failure 1 "$(SHA 119)" 1 "$(qb 35)"),$(mgr2 8120 failure 2 "$(SHA 120)" 1 "$(qb 35)"),$(mgr2 8121 failure 1 "$(SHA 121)" 1 "$(qb 36)"),$(mgr2 8122 success 2 "$(SHA 122)" 1 "$(qb 36)"),$(mgr2 8123 failure 1 "$(SHA 123)" 1 "$(qb 37)"),$(mgr2 8124 failure 1 "$(SHA 124)" 1 "$(qb 38)"),$(mgr2 8125 failure 1 "$(SHA 125)" 1 "$(qb 39)"),$(mgr2 8127 timed_out 1 "$(SHA 127)" 1 "$(qb 42)"),$(mgr2 8128 cancelled 1 "$(SHA 128)" 1 "$(qb 43)"),$(mgr2 8129 failure 1 "$(SHA 129)" 1 "$(qb 40)"),$(mgr2 8130 failure 1 "$(SHA 130)" 1 "$(qb 41)"),$(mgr2 8131 failure 1 "$(SHA 131)" 1 "$(qb 44)"),$(mgr2 8132 failure 1 "$(SHA 132)" 1 "$(qb 45)")"
mg_runs "$RUNS2" 31 | fx "repos/$R2/actions/workflows/ci.yml/runs?event=merge_group&created=X&per_page=100"
f2() { cfiles "$(cfile "$2" "$3")" | fx "repos/$R2/commits/$(SHA "$1")?per_page=100"; }   # f2 <n> <path> <blob>
suitey_fail() { jobs_body "$1" "$2:test-scripts (1/8):failure" "$3:test:failure" | fx "$(jobs_path "$1")"; printf '[FAIL] scripts/suitey (90ms) log=/l/y.log\n' | fx "$(log_path "$2")"; }
f2 101 doc/q1.md aaa111; suitey_fail 8101 95101 95102
jobs_body 8101 "95111:test-scripts (1/8):failure" | fx "$(jobs1_path 8101)"; printf '[FAIL] scripts/suitey (90ms) log=/l/y.log\n' | fx "$(log_path 95111)"
f2 102 doc/q2.md aaa222; suitey_fail 8102 95121 95122
jobs_body 8102 "95131:test-scripts (1/8):failure" | fx "$(jobs1_path 8102)"; printf '[FAIL] scripts/lib/a (90ms) log=/l/a.log\n' | fx "$(log_path 95131)"
f2 103 doc/q3.md aaa333; suitey_fail 8103 95141 95142
fx_err "$(jobs1_path 8103)"
f2 104 doc/c.md blobAAA; suitey_fail 8104 95151 95152
f2 105 doc/c.md blobBBB
f2 106 doc/d.md blobCCC; suitey_fail 8106 95161 95162
f2 107 doc/d.md blobCCC
f2 108 doc/e.md blobE1
f2 109 doc/e.md blobE1; suitey_fail 8109 95171 95172
f2 110 doc/n.md blobN1; suitey_fail 8110 95181 95182
f2 111 doc/n.md blobN1
f2 112 doc/u.md blobU1; jobs_body 8112 "95191:e2e:failure" "95192:test-bun (1/2):cancelled" | fx "$(jobs_path 8112)"
f2 113 doc/t1.md blobT1; JOBS_TOTAL=5 jobs_body 8113 "95201:test-scripts (1/8):failure" "95202:test:failure" | fx "$(jobs_path 8113)"
printf '[FAIL] scripts/suitey (90ms) log=/l/y.log\n' | fx "$(log_path 95201)"
cfiles "" | fx "repos/$R2/commits/$(SHA 114)?per_page=100"; suitey_fail 8114 95211 95212
f2 115 doc/k.md blobK1; jobs_body 8115 "95221:test-scripts (1/8):failure" | fx "$(jobs_path 8115)"
printf '[KILLED] scripts/suitey (exit=137, signal-shaped 128+9 = SIGKILL, 1200000ms) — UNRESOLVED, not a failure\n' | fx "$(log_path 95221)"
f2 116 'doc/a,b.md' blobM1; suitey_fail 8116 95231 95232
BIGNAME="doc/$(python3 -c "print('a'*120000)").md"; f2 117 "$BIGNAME" blobG1; suitey_fail 8117 95241 95242
# a changed-file list that spans two --paginate pages: page 2 holds x.txt, which SELECTS scripts/suitex
printf '{"files":[{"filename":"doc/p1.md","sha":"p1"}]}\n{"files":[{"filename":"x.txt","sha":"p2"}]}\n' | fx "repos/$R2/commits/$(SHA 118)?per_page=100"
jobs_body 8118 "95251:test-scripts (1/8):failure" | fx "$(jobs_path 8118)"; printf '[FAIL] scripts/suitex (90ms) log=/l/x.log\n' | fx "$(log_path 95251)"
# a LATER FAILED run of the same PR with the identical blobs must not clear the earlier failure
f2 119 doc/f.md blobF1; suitey_fail 8119 95261 95262
f2 120 doc/f.md blobF1; suitey_fail 8120 95271 95272
# the later success's file list cannot be read: that is a failed read, not a clearance
f2 121 doc/g.md blobG2; suitey_fail 8121 95281 95282
cfiles "" | fx "repos/$R2/commits/$(SHA 122)?per_page=100"; fx_err "repos/$R2/commits/$(SHA 122)?per_page=100"
# the other three skippable shard families fail a would-skip suite
f2 123 doc/w.md blobW1; jobs_body 8123 "95291:test-webplat (1/2):failure" | fx "$(jobs_path 8123)"; printf '[FAIL] scripts/suitey (90ms) log=/l/y.log\n' | fx "$(log_path 95291)"
f2 124 doc/b.md blobB1; jobs_body 8124 "95301:test-bun (1/2):failure" | fx "$(jobs_path 8124)"; printf '[FAIL] scripts/suitey (90ms) log=/l/y.log\n' | fx "$(log_path 95301)"
f2 125 doc/h.md blobH1; jobs_body 8125 "95311:test-scripts-heavy (1/3):failure" | fx "$(jobs_path 8125)"; printf '[FAIL] scripts/suitey (90ms) log=/l/y.log\n' | fx "$(log_path 95311)"
# a timed_out queue run is an unfinished refusal and is classed; so is a cancelled one (a cancelled shard fails the aggregate)
f2 127 doc/to.md blobT2; jobs_body 8127 "95321:e2e:failure" | fx "$(jobs_path 8127)"
f2 128 doc/ca.md blobC2; jobs_body 8128 "95322:test-webplat (1/2):cancelled" "95323:test:failure" | fx "$(jobs_path 8128)"
# a commit file entry with no blob sha cannot support an identical-content claim
printf '{"files":[{"filename":"doc/nosha.md"}]}\n' | fx "repos/$R2/commits/$(SHA 132)?per_page=100"
# a log whose suite label carries a terminal escape (OSC, which the ANSI strip does not touch) is not a [FAIL] line
f2 129 doc/o.md blobO1; jobs_body 8129 "95331:test-scripts (1/8):failure" | fx "$(jobs_path 8129)"
printf '[FAIL] bad\033]0;title\007label (90ms) log=/l/z.log\n' | fx "$(log_path 95331)"
# the commits API stops listing at 3000 files without saying so: a list AT the cap is a truncated list
python3 -c "
import json
print(json.dumps({'files': [{'filename': 'big/f%d.md' % i, 'sha': 's%d' % i} for i in range(3000)]}))" | fx "repos/$R2/commits/$(SHA 131)?per_page=100"
# a failing job this tool has not classified (in neither the shard family nor ci.yml's job list)
f2 130 doc/m.md blobM2; jobs_body 8130 "95341:mystery-job:failure" | fx "$(jobs_path 8130)"
rm -rf "$OUT"; mkdir -p "$OUT"; : > "$GHLOG"
run_sut ejections --out "$OUT" --since "$since" --repo "$R2" > "$SANDBOX/ej2.out" 2>&1; rc=$?
E2="$OUT/units-ejections.jsonl"
cls_of() { unit_field "$E2" "$(SHA "$1")" '.cls+" "+.reason'; }
[[ "$rc" -eq 0 && "$(wc -l < "$E2")" -eq 26 ]] && pass "twenty-six non-success queue runs (failure, timed_out and cancelled) become twenty-six units" || fail "second window (rc=$rc, lines=$(wc -l < "$E2" 2>/dev/null)): $(tail -3 "$SANDBOX/ej2.out")"
[[ "$(cls_of 101)" = "escape deterministic" ]] && pass "ESC: the would-skip suite failed in attempt 2 AND attempt 1 (read from attempt 1's jobs and log) is a deterministic escape" || fail "ESC: $(cls_of 101)"
[[ "$(cls_of 102 | cut -d' ' -f1)" = unverified ]] && pass "attempt 1 failed a DIFFERENT suite: run_attempt is a counter, not evidence, so the unit is unverified" || fail "attempt-1 different suite: $(cls_of 102)"
[[ "$(cls_of 103 | cut -d' ' -f1)" = unverified ]] && pass "attempt 1's jobs could not be read: the unit is unverified, never an escape and never cleared" || fail "attempt-1 unread: $(cls_of 103)"
[[ "$(cls_of 104 | cut -d' ' -f1)" = unverified ]] && pass "a later success of the same PR with the same file NAMES but a different blob does not clear the failure" || fail "blob differs: $(cls_of 104)"
[[ "$(cls_of 106)" = "flake-cleared identical-tree-green" ]] && pass "a later success of the same PR with the identical (name, blob) set clears the failure" || fail "same blob: $(cls_of 106)"
[[ "$(cls_of 109 | cut -d' ' -f1)" = unverified ]] && pass "an EARLIER success of the same PR never clears a later failure" || fail "earlier success: $(cls_of 109)"
[[ "$(cls_of 110 | cut -d' ' -f1)" = unverified ]] && pass "a run whose branch names no PR is tied to nothing: a later success with the same files does not clear it" || fail "no-PR branch: $(cls_of 110)"
[[ "$(cls_of 112 | cut -d' ' -f1)" = not-evaluable && "$(cls_of 112)" == *"unsettled-jobs: test-bun (1/2)"* ]] && pass "a cancelled job beside a failed always-run job leaves the run not-evaluable (it never said whether it failed)" || fail "unsettled: $(cls_of 112)"
[[ "$(cls_of 113 | cut -d' ' -f1)" = not-evaluable && "$(cls_of 113)" == *"truncated jobs list"* ]] && pass "a jobs list shorter than its total_count is a failed read, not a shorter list" || fail "truncated jobs: $(cls_of 113)"
[[ "$(cls_of 114)" = "not-evaluable empty-diff" ]] && pass "an empty changed-file list on a failed run is not-evaluable (a failed diff read), not rule-irrelevant" || fail "empty diff: $(cls_of 114)"
[[ "$(unit_field "$E2" "$(SHA 115)" '.cls+" "+(.would_skip_failures|join(","))')" = "unverified scripts/suitey" ]] && pass "a [KILLED] line is a suite that did not finish: it names the would-skip suite like a [FAIL] line" || fail "[KILLED]: $(cls_of 115)"
[[ "$(unit_field "$E2" "$(SHA 116)" '.fallback+" "+(.skipped_suites|length|tostring)')" = "not-evaluable 0" ]] && pass "a changed path with a comma is not evaluable and skips nothing" || fail "comma path: $(unit_field "$E2" "$(SHA 116)" '.fallback')"
[[ "$(unit_field "$E2" "$(SHA 117)" '.fallback+" "+(.skipped_suites|length|tostring)')" = "not-evaluable 0" ]] && pass "a changed-file list over 100000 bytes is not evaluable and skips nothing" || fail "oversize list: $(unit_field "$E2" "$(SHA 117)" '.fallback')"
[[ "$(cls_of 118 | cut -d' ' -f1)" = rule-irrelevant ]] && pass "a changed-file list on TWO pages is read whole: page 2's x.txt selects the failing suite, so the failure is rule-irrelevant" || fail "two-page file list: $(cls_of 118)"
[[ "$(cls_of 119 | cut -d' ' -f1)" = unverified ]] && pass "a later FAILED run of the same PR with the identical blobs does not clear the earlier failure" || fail "later failed run: $(cls_of 119)"
[[ "$(cls_of 121 | cut -d' ' -f1)" = unverified ]] && pass "a later success whose file list cannot be read does not clear the failure (an unread list is not 'identical')" || fail "unread later list: $(cls_of 121)"
for n in 123 124 125; do
  [[ "$(cls_of $n | cut -d' ' -f1)" = unverified ]] && pass "unit $n: a would-skip suite failing in a test-webplat / test-bun / test-scripts-heavy shard is read, not waved through" || fail "shard family $n: $(cls_of $n)"
done
[[ -n "$(unit_field "$E2" "$(SHA 127)" .cls)" && "$(cls_of 128)" == "not-evaluable unsettled-jobs: test-webplat (1/2)" ]] && pass "a timed_out run is a unit, and so is a cancelled one: its cancelled shard is unsettled, so not-evaluable (never dropped as 'no verdict')" || fail "timed_out/cancelled: 127='$(cls_of 127)' 128='$(cls_of 128)'"
[[ "$(cls_of 132)" == "not-evaluable files: "* ]] && pass "a commit file entry without a blob sha is a failed read: a name-only comparison is not an identical-content claim" || fail "no blob sha: $(cls_of 132)"
[[ "$(cls_of 129 | cut -d' ' -f1)" = not-evaluable ]] && pass "a log line whose label carries a control byte is not a [FAIL] line: the shard has no fail line, so not-evaluable" || fail "control byte in label: $(cls_of 129)"
[[ "$(cls_of 130)" == "not-evaluable unclassified-job: mystery-job" ]] && pass "a failing job in neither the shard family nor ci.yml's job list is unclassified, so the unit is not-evaluable" || fail "unclassified job: $(cls_of 130)"
[[ "$(cls_of 131)" == "not-evaluable files: "* ]] && pass "a changed-file list of exactly 3000 files is the API's cap: truncated, so the unit is not-evaluable (never a shortened selector input)" || fail "3000-file cap: $(cls_of 131)"
! grep -q STUB-MISS "$GHLOG" && pass "the second window made no request the stub does not know" || fail "second window unknown request: $(grep STUB-MISS "$GHLOG" | head -2)"
REPO_NAME=""

echo "== the flake class and the escape, aggregated from hand-built units"
mkmeta() {  # mkmeta <dir> <refused>: the ejections-window.json the `ejections` command writes
  printf '{"since":"2031-01-01T00:00:00Z","until":"2031-01-09T00:00:00Z","runs":10,"refused":%s,"conclusions":{"failure":%s,"success":%s}}\n' "$2" "$2" "$((10 - $2))" > "$1/ejections-window.json"
}
mkunit() {  # mkunit <idx> <sha> <pr> <cls> <reason> <files_hash>
  printf '{"kind":"ejection","idx":%s,"sha":"%s","pr":"%s","cls":"%s","reason":"%s","files_hash":"%s","files_n":1,"fallback":"none","skipped_min":2.5,"would_skip_failures":["scripts/suitey"],"run":{"id":%s}}\n' "$1" "$2" "$3" "$4" "$5" "$6" "$1"
}
FA="$SANDBOX/flake-same-pr"; mkdir -p "$FA"
{ mkunit 1 s1 7 unverified would-skip-suite-failed h1; mkunit 2 s2 7 unverified would-skip-suite-failed h2; mkunit 3 s3 7 unverified would-skip-suite-failed h3; } > "$FA/units-ejections.jsonl"; mkmeta "$FA" 3
run_sut aggregate "$FA" > "$SANDBOX/fa.out" 2>&1
grep -q "multi_unit_flake_suites=none" "$SANDBOX/fa.out" && grep -q '"unverified": 3' "$SANDBOX/fa.out" && pass "three failures of one suite from ONE PR are not a flake class (the class needs 3 distinct PRs)" || fail "same-PR flake: $(grep -E 'multi|population' "$SANDBOX/fa.out" | head -2)"
FC="$SANDBOX/flake-same-files"; mkdir -p "$FC"
{ mkunit 1 s1 7 unverified would-skip-suite-failed h1; mkunit 2 s2 8 unverified would-skip-suite-failed h1; mkunit 3 s3 9 unverified would-skip-suite-failed h1; } > "$FC/units-ejections.jsonl"; mkmeta "$FC" 3
run_sut aggregate "$FC" > "$SANDBOX/fc.out" 2>&1
grep -q "multi_unit_flake_suites=none" "$SANDBOX/fc.out" && pass "three PRs failing one suite on the SAME file set are not a flake class (the class needs 2 distinct file sets)" || fail "same-files flake: $(grep -E 'multi' "$SANDBOX/fc.out" | head -1)"
FB="$SANDBOX/flake-esc"; mkdir -p "$FB"
{ mkunit 1 s1 7 escape deterministic h0; mkunit 2 s2 8 unverified would-skip-suite-failed h2; mkunit 3 s3 9 unverified would-skip-suite-failed h3; mkunit 4 s4 10 unverified would-skip-suite-failed h4; } > "$FB/units-ejections.jsonl"; mkmeta "$FB" 4
run_sut aggregate "$FB" > "$SANDBOX/fb.out" 2>&1
grep -q "multi_unit_flake_suites=scripts/suitey" "$SANDBOX/fb.out" && grep -q "attributable=1/4" "$SANDBOX/fb.out" && grep -q '"escape": 1' "$SANDBOX/fb.out" && pass "a flake class clears its UNVERIFIED units and never an escape (attributable stays 1 of 4)" || fail "escape under flake class: $(grep -E 'multi|attributable|population' "$SANDBOX/fb.out" | head -3)"

FD="$SANDBOX/arith"; mkdir -p "$FD"
mkcommit() {  # mkcommit <idx> <sha> <skipped_min>
  printf '{"kind":"commit","idx":%s,"sha":"%s","cls":"clean","reason":"","files_hash":"h%s","files_n":1,"fallback":"none","skipped_min":%s,"run":{"id":%s}}\n' "$1" "$2" "$1" "$3" "$1"
}
{ mkcommit 0 c0 10; mkcommit 1 c1 20; mkcommit 2 c2 30; } > "$FD/units-commits-1-of-1.jsonl"
mkunit 1 e1 9 unverified would-skip-suite-failed h9 > "$FD/units-ejections.jsonl"; mkmeta "$FD" 1
run_sut aggregate "$FD" > "$SANDBOX/fd.out" 2>&1; rc=$?
[[ "$rc" -eq 0 ]] && grep -q 'mean_skipped_suite_min=20.00 se=5.77 selector_min=1.29 net_mean=18.71 net_mean_plus_2se=30.26' "$SANDBOX/fd.out" \
  && pass "the saving arithmetic is exact on known values (mean 20, se 5.77, net 18.71, net plus 2 se 30.26)" || fail "saving arithmetic: $(grep '^saving' "$SANDBOX/fd.out")"
grep -q 'attributable=0/4 unverified_as_escape=1/4 (point 25.00%)' "$SANDBOX/fd.out" && pass "the gating point estimate counts an unverified unit as an escape (1 of 4 is 25.00%)" || fail "point estimate: $(grep 'population=commits+' -A2 "$SANDBOX/fd.out" | tail -2)"
grep -q 'ejection_units=1 commit_units=3' "$SANDBOX/fd.out" && pass "the receipt names how many units of each population it read" || fail "population counts: $(sed -n 3p "$SANDBOX/fd.out")"
FE="$SANDBOX/no-ejections"; mkdir -p "$FE"; { mkcommit 0 c0 1; mkcommit 1 c1 1; } > "$FE/units-commits-1-of-1.jsonl"; mkmeta "$FE" 0
run_sut aggregate "$FE" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "aggregate refuses a directory with no ejections file (the commits-only population is near-vacuous by construction)" || fail "no ejections file (rc=$rc)"
run_sut aggregate "$FE" --commits-only >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 ]] && pass "--commits-only says that is intended, and aggregate then reads the commits alone" || fail "--commits-only (rc=$rc)"
FG="$SANDBOX/gap-chunk"; mkdir -p "$FG"; { mkcommit 0 c0 1; mkcommit 2 c2 1; } > "$FG/units-commits-1-of-2.jsonl"; : > "$FG/units-ejections.jsonl"; mkmeta "$FG" 0
run_sut aggregate "$FG" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "aggregate refuses commit units whose indices are not contiguous (a chunk is missing)" || fail "missing chunk (rc=$rc)"
FH="$SANDBOX/dup-layout"; mkdir -p "$FH"; { mkcommit 0 c0 1; mkcommit 1 c1 1; } > "$FH/units-commits-1-of-1.jsonl"; { mkcommit 2 c0 1; } > "$FH/units-commits-1-of-2.jsonl"; : > "$FH/units-ejections.jsonl"; mkmeta "$FH" 0
run_sut aggregate "$FH" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "aggregate refuses a unit that appears in two chunk layouts (it would count twice and tighten the bound)" || fail "duplicate layout (rc=$rc)"
run_sut aggregate "$FD" --expect-commits 4 >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "--expect-commits N refuses a directory holding another number of commit units" || fail "--expect-commits (rc=$rc)"
run_sut aggregate "$FD" --expect-commits 3 >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 ]] && pass "--expect-commits N accepts exactly N" || fail "--expect-commits exact (rc=$rc)"
FT="$SANDBOX/tsv"; mkdir -p "$FT"; { mkcommit 0 c0 1; } > "$FT/units-commits-1-of-1.jsonl"
printf '{"kind":"ejection","idx":0,"sha":"e0","pr":"1","cls":"not-evaluable","reason":"gh said:\\tfirst\\nsecond","files_hash":"h","files_n":1,"fallback":"none","skipped_min":0,"run":{"id":1}}\n' > "$FT/units-ejections.jsonl"; mkmeta "$FT" 1
run_sut aggregate "$FT" --out "$SANDBOX/tsv.txt" >/dev/null 2>&1
[[ "$(awk -F'\t' 'NF != 9 { bad++ } END { print bad + 0 }' "$SANDBOX/tsv.txt.tsv")" = 0 && "$(wc -l < "$SANDBOX/tsv.txt.tsv")" -eq 3 ]] && pass "a reason holding a tab or a newline cannot split a row of the per-unit TSV" || fail "tsv rows: $(awk -F'\t' '{print NF}' "$SANDBOX/tsv.txt.tsv" | tr '\n' ' ')"
FI="$SANDBOX/internal"; mkdir -p "$FI"; printf '{"kind":"commit","sha":"x"}\n' > "$FI/units-commits-1-of-1.jsonl"; : > "$FI/units-ejections.jsonl"; mkmeta "$FI" 0
ierr="$(run_sut aggregate "$FI" 2>&1 >/dev/null)"; rc=$?
[[ "$rc" -eq 4 ]] && grep -q 'internal error' <<<"$ierr" && pass "an uncaught Python error exits 4 and says so, never 1 (which is the audit's 'gaps found')" || fail "internal error exit (rc=$rc: $ierr)"
FM="$SANDBOX/no-meta"; mkdir -p "$FM"; { mkcommit 0 c0 1; } > "$FM/units-commits-1-of-1.jsonl"; mkunit 1 e1 9 unverified would-skip-suite-failed h9 > "$FM/units-ejections.jsonl"
run_sut aggregate "$FM" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "aggregate refuses ejection units with no ejections-window.json (nothing says how many refused runs the window held)" || fail "no window manifest (rc=$rc)"
FN="$SANDBOX/short-ejections"; mkdir -p "$FN"; { mkcommit 0 c0 1; } > "$FN/units-commits-1-of-1.jsonl"; mkunit 1 e1 9 unverified would-skip-suite-failed h9 > "$FN/units-ejections.jsonl"; mkmeta "$FN" 5
run_sut aggregate "$FN" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "aggregate refuses a short ejection population: 1 unit against a window that held 5 refused runs" || fail "short ejections (rc=$rc)"
grep -q 'ejection_window=2031-01-01T00:00:00Z..2031-01-09T00:00:00Z runs=10 refused=1' "$SANDBOX/fd.out" && pass "the receipt prints the ejection window, how many runs it held and how many were refused" || fail "ejection_window line: $(grep ejection_window "$SANDBOX/fd.out")"
FP="$SANDBOX/flake-two-prs"; mkdir -p "$FP"
{ mkunit 1 s1 7 unverified would-skip-suite-failed h1; mkunit 2 s2 8 unverified would-skip-suite-failed h2; mkunit 3 s3 8 unverified would-skip-suite-failed h3; } > "$FP/units-ejections.jsonl"; mkmeta "$FP" 3
run_sut aggregate "$FP" > "$SANDBOX/fp.out" 2>&1
grep -q "multi_unit_flake_suites=none" "$SANDBOX/fp.out" && grep -q '"unverified": 3' "$SANDBOX/fp.out" && pass "three failures of one suite from only TWO PRs are not a flake class (the class needs 3 distinct PRs)" || fail "two-PR flake: $(grep -E 'multi' "$SANDBOX/fp.out")"

echo "== cp-upper, verdict, usage"
v="$(python3 "$SUT" cp-upper 6 300)"
awk -v v="$v" 'BEGIN{exit !(v>0.0385 && v<0.0397)}' && pass "cp-upper 6/300 is about 3.9% (the plan's figure)" || fail "cp-upper 6/300 (got $v)"
v="$(python3 "$SUT" cp-upper 0 300)"
awk -v v="$v" 'BEGIN{exit !(v>0.0098 && v<0.0101)}' && pass "cp-upper 0/300 is about 0.99%" || fail "cp-upper 0/300 (got $v)"
[[ "$(python3 "$SUT" cp-upper 7 7)" = 1.000000 && "$(python3 "$SUT" cp-upper 0 0)" = 1.000000 ]] && pass "cp-upper k>=n and n=0 are 1" || fail "cp-upper edge cases"
v="$(python3 "$SUT" cp-upper 0 100000 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && awk -v v="$v" 'BEGIN{exit !(v>0.00002 && v<0.00004)}' && pass "cp-upper 0/100000 is about 3e-5 (no overflow on a large n)" || fail "cp-upper 0/100000 (rc=$rc, got $v)"
v="$(python3 "$SUT" cp-upper 300 2000 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && awk -v v="$v" 'BEGIN{exit !(v>0.16 && v<0.18)}' && pass "cp-upper 300/2000 is about 17% (binomial terms large enough that a naive float product overflows)" || fail "cp-upper 300/2000 (rc=$rc, got $v)"
vt="$(python3 - "$SUT" <<'PY'
import importlib.util, itertools, sys
sp = importlib.util.spec_from_file_location('m', sys.argv[1]); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
ST = ("pass", "fail", "within-10%", "unmeasured")
seen = bad = 0
for a, b, c, d in itertools.product(ST, repeat=4):
    seen += 1
    if b == "within-10%" or d == "within-10%":
        # criteria b (index completeness) and d (census) are yes/no: a tolerance band is refused
        try:
            m.verdict(a, b, c, d); bad += 1
        except ValueError:
            pass
        continue
    got = m.verdict(a, b, c, d)[0]
    xs = [a, b, c, d]
    want = "NO-GO" if "fail" in xs else ("UNDECIDED" if ("unmeasured" in xs or "within-10%" in xs) else "GO")
    if got != want:
        bad += 1
print(seen, bad)
PY
)"
[[ "$vt" = "256 0" ]] && pass "the verdict function is total over 256 combinations and matches the independent oracle (a band on b or d is refused)" || fail "verdict table ($vt)"
python3 "$SUT" verdict --a pass --b pass --c nope --d pass >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "an unknown criterion status is refused with rc 2" || fail "an unknown criterion status is refused (rc=$rc)"
[[ "$(python3 "$SUT" verdict --a pass --b fail --c unmeasured --d pass)" = "computed=NO-GO reason=criterion-failed" ]] && pass "the PR C verdict (b fail, c unmeasured) computes NO-GO" || fail "PR C verdict arithmetic"
helptxt="$(python3 "$SUT" --help 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && printf '%s\n' "$helptxt" | grep -q 'SUBCOMMANDS' && printf '%s\n' "$helptxt" | grep -q 'THE PROPOSED RULE' && printf '%s\n' "$helptxt" | grep -q 'pinned' \
  && pass "--help carries the rule, the subcommands and the pinned-tree instruction" || fail "--help (rc=$rc)"

ci_jobs="$(python3 - "$SCRIPT_DIR/../../../.github/workflows/ci.yml" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"^jobs:\n(.*)", t, re.S | re.M).group(1)
print("\n".join(sorted(re.findall(r"^  ([a-zA-Z0-9_-]+):\s*$", m, re.M))))
PY
)"
py_jobs="$(python3 - "$SUT" <<'PY'
import importlib.util, sys
sp = importlib.util.spec_from_file_location('m', sys.argv[1]); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
print("\n".join(sorted(m.ALWAYS_RUN_JOBS | {"test-webplat", "test-bun", "test-scripts", "test-scripts-heavy"})))
PY
)"
[[ -n "$ci_jobs" && "$ci_jobs" = "$py_jobs" ]] && pass "the always-run job set plus the four shard families is exactly ci.yml's job list (a new job there must be classified here)" || fail "job parity: ci-only='$(comm -23 <(echo "$ci_jobs") <(echo "$py_jobs") | tr '\n' ' ')' tool-only='$(comm -13 <(echo "$ci_jobs") <(echo "$py_jobs") | tr '\n' ' ')'"
gate_git="$(awk '/^git_ro\(\)/,/^}/' "$SCRIPT_DIR/../../../scripts/ci-pr-affected-preactivation.sh" | grep -o 'GIT_[A-Z_]*' | sort -u)"
lib_git="$(printf '%s\n' "${GIT_LOCATION_VARS[@]}" | sort -u)"
py_git="$(python3 - "$SUT" <<'PY'
import importlib.util, sys
sp = importlib.util.spec_from_file_location('m', sys.argv[1]); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
print("\n".join(sorted(m.GIT_LOCATION_VARS)))
PY
)"
[[ -n "$gate_git" && "$gate_git" = "$lib_git" && "$py_git" = "$lib_git" ]] && pass "the replay tool's GIT_LOCATION_VARS, the gate's git_ro and the fixture lib's list are the same nine names" || fail "git location list parity: gate='${gate_git//$'\n'/ }' lib='${lib_git//$'\n'/ }' py='${py_git//$'\n'/ }'"
echo "== git: a non-ASCII path is read raw, not as a quoted ASCII string"
NREPO="$SANDBOX/nrepo"; assert_fixture_dir "$NREPO"; mkdir -p "$NREPO"
( cd "$NREPO" && gitq init -q -b main . && printf 'x\n' > seed && gitq add -A && gitq commit -qm seed && printf 'y\n' > "caf$(printf '\303\251').txt" && gitq add -A && gitq commit -qm accent ) || { echo "[FATAL] nrepo" >&2; exit 1; }
NSHA="$(gitq -C "$NREPO" rev-parse HEAD)"
row_nonascii() { [[ "$(python3 -c "
import importlib.util as u, sys
s = u.spec_from_file_location('m', '$SUT'); m = u.module_from_spec(s); s.loader.exec_module(m)
f = m.commit_files('$NREPO', '$NSHA')
print(f == ['café.txt'], m.evaluable(f))
")" = "True (False, 'non-printable-path')" ]]; }
row_nonascii && pass "git diff-tree -z yields the raw path (cafe-acute), which is flagged non-printable and so not evaluable" || fail "non-ASCII path handling"

echo "== audit: the PR 9404 shape, the unread suite, the glob edge"
AREPO="$SANDBOX/arepo"
assert_fixture_dir "$AREPO"
mkdir -p "$AREPO/scripts" "$AREPO/.github/workflows" "$AREPO/adir"
printf 'name: ci\n' > "$AREPO/.github/workflows/ci.yml"
printf '#!/usr/bin/env bash\ncat .github/workflows/ci.yml\nbash scripts/guard-vacuity-floor.test.sh\n' > "$AREPO/scripts/lint-orphan-mutations.test.sh"
printf '#!/usr/bin/env bash\n# reads nothing tracked but itself\n' > "$AREPO/scripts/guard-vacuity-floor.test.sh"
printf '#!/usr/bin/env bash\ncat .github/workflows/ci.yml\n' > "$AREPO/scripts/declared-complete.test.sh"
printf '#!/usr/bin/env bash\n# mentions .github/workflows/ci.yml only in a comment\ntrue\n' > "$AREPO/scripts/comment-only.test.sh"
printf '#!/usr/bin/env bash\ngrep -q x scripts/test-all.sh\n' > "$AREPO/scripts/names-the-runner.test.sh"
printf '#!/usr/bin/env bash\ncat adir/data.txt\n' > "$AREPO/scripts/globbed.test.sh"
printf 'd\n' > "$AREPO/adir/data.txt"
mkdir -p "$AREPO/apps/(auth)" "$AREPO/data"
printf 'p\n' > "$AREPO/apps/(auth)/page.tsx"; printf 'x\n' > "$AREPO/scripts/x.sh"; printf 'x\n' > "$AREPO/scripts/x.sh.bak"
for i in 1 2 3 4 5 6 7 8; do printf 'f\n' > "$AREPO/data/f$i.txt"; done
printf '#!/usr/bin/env bash\ncat "apps/(auth)/page.tsx"\n' > "$AREPO/scripts/parens.test.sh"
printf '#!/usr/bin/env bash\ncat scripts/x.sh.bak\n' > "$AREPO/scripts/exact.test.sh"
printf '#!/usr/bin/env bash\ncat data/f1.txt data/f2.txt data/f3.txt data/f4.txt data/f5.txt data/f6.txt data/f7.txt data/f8.txt\n' > "$AREPO/scripts/many.test.sh"
printf '#!/usr/bin/env bash\n' > "$AREPO/scripts/test-all.sh"
(cd "$AREPO" && gitq init -q -b main . && gitq add -A && gitq commit -qm seed) || { echo "[FATAL] audit fixture" >&2; exit 1; }
printf 'AFFECTED_SELECTED\tscripts/lint-orphan-mutations\t0\tedge:declared\t^scripts/lint-orphan-mutations.test.sh\n' > "$SANDBOX/audit-bad.rows"
printf 'AFFECTED_SELECTED\tscripts/declared-complete\t0\tedge:declared\t^scripts/declared-complete.test.sh|^.github/workflows/ci.yml\n' > "$SANDBOX/audit-good.rows"
printf 'AFFECTED_SELECTED\tscripts/comment-only\t0\tedge:derived\t^scripts/comment-only.test.sh\n' > "$SANDBOX/audit-comment.rows"
printf 'AFFECTED_SELECTED\tscripts/names-the-runner\t0\tedge:derived\t^scripts/names-the-runner.test.sh\n' > "$SANDBOX/audit-runner.rows"
printf 'AFFECTED_SELECTED\tscripts/ghost\t0\tedge:derived\t^scripts/ghost.test.sh\n' > "$SANDBOX/audit-ghost.rows"
printf 'AFFECTED_SELECTED\tscripts/always\t1\talways_on\t\n' > "$SANDBOX/audit-always.rows"
printf 'AFFECTED_SELECTED\tscripts/globbed\t0\tedge:declared\t^scripts/globbed.test.sh|^glob:adir/**.txt\n' > "$SANDBOX/audit-glob.rows"
printf 'AFFECTED_SELECTED\tadir\t0\tedge:declared\t^adir/\n' > "$SANDBOX/audit-dir.rows"
printf 'AFFECTED_SELECTED\tscripts/parens\t0\tedge:declared\t^scripts/parens.test.sh|^apps/(auth)/page.tsx\n' > "$SANDBOX/audit-parens.rows"
printf 'AFFECTED_SELECTED\tscripts/exact\t0\tedge:declared\t^scripts/exact.test.sh|^scripts/x.sh\n' > "$SANDBOX/audit-exact.rows"
printf 'AFFECTED_SELECTED\tscripts/many\t0\tedge:declared\t^scripts/many.test.sh\n' > "$SANDBOX/audit-many.rows"
printf 'AFFECTED_SELECTED\tscripts/short\t0\tedge:declared\n' > "$SANDBOX/audit-short.rows"
printf 'scripts/lint-orphan-mutations\t.github/workflows/ci.yml\tfalse-positive: fixture write into a scratch repo\nscripts/lint-orphan-mutations\tscripts/guard-vacuity-floor.test.sh\tfalse-positive: only mentioned in a message\n' > "$SANDBOX/accept-ok.tsv"
printf 'scripts/lint-orphan-mutations\t.github/workflows/ci.yml\n' > "$SANDBOX/accept-noreason.tsv"
printf 'scripts/lint-orphan-mutations\t.github/workflows/ci.yml\tbecause I said so\n' > "$SANDBOX/accept-badreason.tsv"
printf 'adir\t*\tfalse-positive: a directory suite whose reads the index declares by prefix\n' > "$SANDBOX/accept-dir.tsv"
audit() { RC=0; AOUT="$(run_sut audit --root "$AREPO" --list "$1" ${2:+"$2"} ${3:+"$3"} 2>&1)" || RC=$?; }
audit "$SANDBOX/audit-bad.rows"
[[ "$RC" -eq 1 ]] && grep -q 'gap_suites=1' <<<"$AOUT" && grep -q 'unaudited=0' <<<"$AOUT" && pass "a -mutations sibling that reads ci.yml and a sibling suite but declares only its own file is flagged" || fail "the PR 9404 shape is flagged (rc=$RC: $(tail -2 <<<"$AOUT"))"
grep -q 'ci.yml' <<<"$AOUT" && grep -q 'guard-vacuity-floor.test.sh' <<<"$AOUT" && pass "the gap line names both undeclared inputs" || fail "the gap line names both undeclared inputs"
audit "$SANDBOX/audit-good.rows"
[[ "$RC" -eq 0 ]] && grep -q 'gap_suites=0 gap_refs=0' <<<"$AOUT" && grep -q 'audited=1 unaudited=0' <<<"$AOUT" && pass "a suite whose reads are all declared has no gap (must-pass control)" || fail "a fully declared suite has no gap (rc=$RC)"
audit "$SANDBOX/audit-comment.rows"
[[ "$RC" -eq 0 ]] && grep -q 'gap_suites=0' <<<"$AOUT" && pass "a path named only in a comment is a mention, not a read (no gap)" || fail "comment-only mention is not a gap (rc=$RC)"
audit "$SANDBOX/audit-runner.rows"
[[ "$RC" -eq 0 ]] && grep -q 'gap_suites=0' <<<"$AOUT" && pass "a suite that names the runner is covered by the runner-changed trigger (no gap)" || fail "runner path is covered by the trigger list (rc=$RC)"
audit "$SANDBOX/audit-ghost.rows"
[[ "$RC" -eq 1 ]] && grep -q 'unaudited=1' <<<"$AOUT" && grep -q '^unaudited.scripts/ghost' <<<"$AOUT" && grep -q 'gap_suites=0' <<<"$AOUT" && pass "a suite whose file the audit cannot read is UNAUDITED and the audit exits 1 (gap_suites=0 alone no longer reads clean)" || fail "unread suite (rc=$RC): $AOUT"
audit "$SANDBOX/audit-always.rows"
[[ "$RC" -eq 0 ]] && grep -q 'always_on=1 audited=0 unaudited=0' <<<"$AOUT" && pass "an always_on suite runs on every diff, so its index is exempt and counted as such" || fail "always_on exemption (rc=$RC): $AOUT"
audit "$SANDBOX/audit-glob.rows"
[[ "$RC" -eq 0 ]] && grep -q 'gap_suites=0 gap_refs=0' <<<"$AOUT" && pass "a ^glob: edge covers the files it names (the selector's own glob grammar, not a regex)" || fail "glob edge (rc=$RC): $AOUT"
audit "$SANDBOX/audit-dir.rows"
[[ "$RC" -eq 1 ]] && grep -q 'unaudited=1' <<<"$AOUT" && pass "a directory suite (first pattern is a directory) is unaudited, not silently clean" || fail "directory suite (rc=$RC): $AOUT"
audit "$SANDBOX/audit-parens.rows"
[[ "$RC" -eq 0 ]] && grep -q 'gap_suites=0 gap_refs=0' <<<"$AOUT" && pass "a path holding ( ) matches itself: edges are literal paths, not regexes" || fail "parenthesised path (rc=$RC): $AOUT"
audit "$SANDBOX/audit-exact.rows"
[[ "$RC" -eq 1 ]] && grep -q 'gap_suites=1' <<<"$AOUT" && grep -q 'scripts/x.sh.bak' <<<"$AOUT" && pass "an edge naming scripts/x.sh does not cover scripts/x.sh.bak: a file edge is exact equality, not a prefix" || fail "exact edge (rc=$RC): $AOUT"
audit "$SANDBOX/audit-many.rows"
[[ "$RC" -eq 1 ]] && grep -P -q '^gap\tscripts/many\t8\t([^,]+,){5}[^,]+$' <<<"$AOUT" && pass "a gap line prints the first six undeclared paths by default" || fail "default gap line: $(grep '^gap' <<<"$AOUT")"
audit "$SANDBOX/audit-many.rows" --all-refs
[[ "$RC" -eq 1 ]] && grep -P -q '^gap\tscripts/many\t8\t([^,]+,){7}[^,]+$' <<<"$AOUT" && pass "--all-refs prints every undeclared path (the receipt's frequency table is reproducible from it)" || fail "--all-refs gap line: $(grep '^gap' <<<"$AOUT")"
audit "$SANDBOX/audit-short.rows"
[[ "$RC" -eq 1 ]] && grep -q 'unaudited=1' <<<"$AOUT" && grep -q 'short-row' <<<"$AOUT" && pass "a selector row too short to name its edges is unaudited, not skipped" || fail "short row (rc=$RC): $AOUT"
printf '#!/usr/bin/env bash\nprintf "AFFECTED_SELECTED\\tscripts/declared-complete\\t0\\tedge:declared\\t^scripts/declared-complete.test.sh|^.github/workflows/ci.yml\\n"\nexit 7\n' > "$BIN/sel-partial.sh"; chmod +x "$BIN/sel-partial.sh"
RUN_ENV=(PR_AFFECTED_REPLAY_TEST_ALL="$BIN/sel-partial.sh"); run_sut audit --root "$AREPO" >/dev/null 2>&1; rc=$?; RUN_ENV=()
[[ "$rc" -eq 3 ]] && pass "an audit whose selector prints rows and then fails is a failed read (rc 3), never a pass over the rows it got" || fail "selector failing after rows (rc=$rc)"
PR_AFFECTED_REPLAY_GH_TIMEOUT=abc python3 "$SUT" cp-upper 0 10 >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "a non-numeric PR_AFFECTED_REPLAY_GH_TIMEOUT is a usage error (rc 2), never the audit's rc 1" || fail "bad timeout env (rc=$rc)"
audit "$SANDBOX/audit-bad.rows" --accept "$SANDBOX/accept-ok.tsv"
[[ "$RC" -eq 0 ]] && grep -q 'gap_suites=0 gap_refs=0 accepted=2' <<<"$AOUT" && pass "--accept removes exactly the gaps a human wrote a false-positive reason for, and counts them" || fail "--accept (rc=$RC): $AOUT"
audit "$SANDBOX/audit-bad.rows" --accept "$SANDBOX/accept-noreason.tsv"
[[ "$RC" -eq 2 ]] && pass "an --accept row with no reason is refused (rc 2): a gap cannot be waved off by a bare name" || fail "accept without reason (rc=$RC)"
audit "$SANDBOX/audit-bad.rows" --accept "$SANDBOX/accept-badreason.tsv"
[[ "$RC" -eq 2 ]] && pass "an --accept reason that does not start with 'false-positive:' is refused (rc 2)" || fail "accept with another reason (rc=$RC)"
audit "$SANDBOX/audit-dir.rows" --accept "$SANDBOX/accept-dir.tsv"
[[ "$RC" -eq 0 ]] && grep -q 'audited=0 unaudited=0' <<<"$AOUT" && grep -q 'accepted=1' <<<"$AOUT" && pass "an unaudited directory suite is accepted only by a '*' row carrying a false-positive reason" || fail "accepted directory suite (rc=$RC): $AOUT"
: > "$SANDBOX/audit-empty.rows"
run_sut audit --root "$AREPO" --list "$SANDBOX/audit-empty.rows" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "an audit that examined zero suites exits non-zero (anti-vacuity)" || fail "an audit that examined zero suites exits non-zero (rc=$rc)"

# ---------------------------------------------------------------------------------------------------------------------
echo "== mutation rows (each edit lands once, leaves valid python, leaves the row GREEN on the pristine SUT, and the named row must then FAIL)"
MUT_RUN=0; MUT_KILLED=0
declare -A PRISTINE_OK=()
MUT_RESULT=""
mutant_outcome() {  # mutant_outcome <name> <old> <new> <row>: sets MUT_RESULT = killed | survived | invalid | row-red-on-pristine | edit-failed
  local name="$1" old="$2" new="$3" row="$4" m="$SANDBOX/mut-$1.py" got
  cp "$REAL_SUT" "$m" || { MUT_RESULT=edit-failed; return 0; }
  python3 - "$m" "$old" "$new" 2>/dev/null <<'PY' || { MUT_RESULT=edit-failed; return 0; }
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
assert s.count(old) == 1, "count=%d" % s.count(old)
open(p, "w").write(s.replace(old, new))
PY
  cmp -s "$m" "$REAL_SUT" && { MUT_RESULT=edit-failed; return 0; }
  python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$m" 2>/dev/null || { MUT_RESULT=invalid; return 0; }   # a mutant that does not parse crashes every row: not a kill
  if [[ -z "${PRISTINE_OK[$row]:-}" ]]; then   # a row that is red on the real script would "kill" anything; checked once per row
    SUT="$REAL_SUT"; "$row" >/dev/null 2>&1 || { MUT_RESULT="row-red-on-pristine"; return 0; }
    PRISTINE_OK[$row]=1
  fi
  SUT="$m"; "$row" >/dev/null 2>&1; got=$?; SUT="$REAL_SUT"
  if [[ "$got" -ne 0 ]]; then MUT_RESULT=killed; else MUT_RESULT=survived; fi
}
mutate() {  # mutate <name> <old> <new> <row>
  mutant_outcome "$@"
  MUT_RUN=$((MUT_RUN + 1))
  if [[ "$MUT_RESULT" = killed ]]; then MUT_KILLED=$((MUT_KILLED + 1)); pass "mutant $1 is killed by $4"; else fail "mutant $1: $MUT_RESULT (row $4)"; fi
}
ej2_run() {  # re-run the second ejection window into a fresh dir with the SUT under test; sets E2
  REPO_NAME="$R2"; rm -rf "$OUT"; mkdir -p "$OUT"; : > "$GHLOG"
  mg_runs "$RUNS2" 31 | fx "repos/$R2/actions/workflows/ci.yml/runs?event=merge_group&created=X&per_page=100"
  run_sut ejections --out "$OUT" --since "$since" --repo "$R2" >/dev/null 2>&1; E2="$OUT/units-ejections.jsonl"; REPO_NAME=""
}
row_always_on() { collect_once; [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[0]}" '.skipped_suites|join(",")')" = "scripts/suitex,scripts/suitey" ]]; }
row_fallback() { collect_once; [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[5]}" '.skipped_min == 0')" = true ]]; }
row_read_error() { collect_once; [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[4]}" .reason)" == runs-read* ]]; }
row_worst_bound() { collect_once; run_sut aggregate "$OUT" --commits-only 2>&1 | grep -q "cp95_upper_on_worst_case=$(python3 -c "print('%.2f'%(100*$(python3 "$REAL_SUT" cp-upper 3 7)))")%"; }
row_flake_same_files() { local o; o="$(run_sut aggregate "$FC" 2>&1)"; grep -q '"unverified": 3' <<<"$o"; }
row_flake_same_pr() { local o; o="$(run_sut aggregate "$FA" 2>&1)"; grep -q '"unverified": 3' <<<"$o"; }
row_flake_escape() { local o; o="$(run_sut aggregate "$FB" 2>&1)"; grep -q 'attributable=1/4' <<<"$o"; }
row_verdict_fail() { [[ "$(python3 "$SUT" verdict --a pass --b fail --c pass --d pass)" == "computed=NO-GO "* ]]; }
row_unmeasured() { [[ "$(python3 "$SUT" verdict --a pass --b pass --c unmeasured --d pass)" == "computed=UNDECIDED reason=incomplete" ]]; }
row_band_b() { python3 "$SUT" verdict --a pass --b within-10% --c pass --d pass >/dev/null 2>&1; [[ $? -eq 2 ]]; }
row_selftest_line() { collect_once; [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[2]}" '.failing[0].suites|join(",")')" = scripts/suitey ]]; }
row_sel_error() { rm -rf "$OUT"; mkdir -p "$OUT"; ( cd "$REPO" && env PATH="$BIN:$PATH" PR_AFFECTED_REPLAY_TEST_ALL="$BIN/sel-fail.sh" PR_AFFECTED_REPLAY_RETRY_SLEEP=0 HOME="$FIXHOME" python3 "$SUT" collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" >/dev/null 2>&1 ); [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[6]}" .reason)" == selection:* ]]; }
row_fallback_rows() { collect_once; [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[5]}" .fallback)" = runner-changed ]]; }
row_redo() { fx_err "$(runs_path "${C[4]}")"; collect_once; rm -f "$GHFIX/ERR_$(keyof "$(runs_path "${C[4]}")")"; runs_body "${C[4]}" "5001:merge_group:success" | fx "$(runs_path "${C[4]}")"; run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" --redo-unevaluable >/dev/null 2>&1; local ok=0; [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[4]}" .cls)" = clean ]] && ok=1; fx_err "$(runs_path "${C[4]}")"; [[ "$ok" -eq 1 ]]; }
row_clear() { collect_once; [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[5]}" .cls)" = clean ]]; }
row_escape_unread() { ej2_run; [[ "$(unit_field "$E2" "$(SHA 103)" .cls)" = unverified ]]; }
row_escape_other_suite() { ej2_run; [[ "$(unit_field "$E2" "$(SHA 102)" .cls)" = unverified && "$(unit_field "$E2" "$(SHA 101)" .cls)" = escape ]]; }
row_blob() { ej2_run; [[ "$(unit_field "$E2" "$(SHA 104)" .cls)" = unverified && "$(unit_field "$E2" "$(SHA 106)" .cls)" = flake-cleared ]]; }
row_earlier() { ej2_run; [[ "$(unit_field "$E2" "$(SHA 109)" .cls)" = unverified ]]; }
row_nopr() { ej2_run; [[ "$(unit_field "$E2" "$(SHA 110)" .cls)" = unverified ]]; }
row_unsettled() { ej2_run; [[ "$(unit_field "$E2" "$(SHA 112)" .cls)" = not-evaluable ]]; }
row_trunc_jobs() { ej2_run; [[ "$(unit_field "$E2" "$(SHA 113)" .cls)" = not-evaluable ]]; }
row_empty_diff() { ej2_run; [[ "$(unit_field "$E2" "$(SHA 114)" .reason)" = empty-diff ]]; }
row_killed_line() { ej2_run; [[ "$(unit_field "$E2" "$(SHA 115)" .cls)" = unverified ]]; }
row_since_offset() { run_sut ejections --out "$SANDBOX/ej-off" --since "2031-01-01T00:00:00+02:00" --repo "$R" >/dev/null 2>&1; [[ $? -eq 2 ]] || return 1
  run_sut ejections --out "$SANDBOX/ej-off" --since "$since" --until "2031-01-09T00:00:00+02:00" --repo "$R" >/dev/null 2>&1; [[ $? -eq 2 ]]; }
row_zero_window() { printf '{"total_count":0,"workflow_runs":[]}' | fx "repos/$R2/actions/workflows/ci.yml/runs?event=merge_group&created=X&per_page=100"; run_sut ejections --out "$SANDBOX/ej-zero" --since "$since" --repo "$R2" >/dev/null 2>&1; [[ $? -eq 3 ]]; }
row_trunc_runs() { mg_runs "$(mgrun 8101 failure 1 "$SH1" 11)" 5 | fx "repos/$R2/actions/workflows/ci.yml/runs?event=merge_group&created=X&per_page=100"; run_sut ejections --out "$SANDBOX/ej-trunc" --since "$since" --repo "$R2" >/dev/null 2>&1; [[ $? -eq 3 ]]; }
row_env() { rm -rf "$OUT"; mkdir -p "$OUT"; rm -f "$SELDUMP"; RUN_ENV=(GH_TOKEN=ghs_notasecret PR_AFFECTED_REPLAY_SEL_ENV_DUMP="$SELDUMP"); run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" >/dev/null 2>&1; RUN_ENV=(); [[ -s "$SELDUMP" ]] && ! grep -q '^GH_TOKEN=' "$SELDUMP"; }
row_home() { rm -rf "$OUT"; mkdir -p "$OUT"; rm -f "$SELDUMP"; RUN_ENV=(PR_AFFECTED_REPLAY_SEL_ENV_DUMP="$SELDUMP"); run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" >/dev/null 2>&1; RUN_ENV=(); [[ -s "$SELDUMP" && "$(sed -n 's/^HOME=//p' "$SELDUMP")" != "$FIXHOME" && -n "$(sed -n 's/^HOME=//p' "$SELDUMP")" ]]; }
row_git_env() { rm -rf "$OUT"; mkdir -p "$OUT"; RUN_ENV=(GIT_DIR="$SANDBOX/decoy.git"); run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" >/dev/null 2>&1; RUN_ENV=(); [[ "$(wc -l < "$OUT/units-commits-1-of-1.jsonl" 2>/dev/null)" -eq 7 ]]; }
row_404() { REPO_NAME="$R2"; rm -rf "$OUT"; mkdir -p "$OUT"; : > "$GHLOG"; run_sut collect --out "$OUT" --commits 1 --chunk 1/1 --repo "$R2" >/dev/null 2>&1; local n; n="$(grep -c "^REQ $(keyof "$(runs_path "${C[6]}")")\$" "$GHLOG")"; REPO_NAME=""; [[ "$n" -eq 1 ]]; }
row_hang() { REPO_NAME="$R2"; rm -rf "$OUT"; mkdir -p "$OUT"; ( cd "$REPO" && env PATH="$BIN:$PATH" PR_AFFECTED_REPLAY_TEST_ALL="$BIN/sel.sh" PR_AFFECTED_REPLAY_RETRY_SLEEP=0 PR_AFFECTED_REPLAY_GH_TIMEOUT=1 HOME="$FIXHOME" python3 "$SUT" collect --out "$OUT" --commits 2 --chunk 1/1 --repo "$R2" >/dev/null 2>&1 ); REPO_NAME=""; [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[5]}" .reason)" == *"timed out"* ]]; }
row_torn() { collect_once; printf '{"kind": "commit", "sha": "torn' >> "$OUT/units-commits-1-of-1.jsonl"; run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" >/dev/null 2>&1; jq -c . "$OUT/units-commits-1-of-1.jsonl" >/dev/null 2>&1 && [[ "$(jq -s length "$OUT/units-commits-1-of-1.jsonl")" -eq 7 ]]; }
row_reclassify() { collect_once; : > "$GHLOG"; run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" --reclassify >/dev/null 2>&1; [[ "$(reqs "$(runs_path "${C[0]}")")" -eq 0 && "$(reqs "$(runs_path "${C[2]}")")" -ge 1 ]]; }
row_cp_big() { local v; v="$(python3 "$SUT" cp-upper 300 2000 2>&1)" || return 1; awk -v v="$v" 'BEGIN{exit !(v>0.16 && v<0.18)}'; }
row_audit_comment() { audit "$SANDBOX/audit-comment.rows"; grep -q 'gap_suites=0' <<<"$AOUT"; }
row_audit_runner() { audit "$SANDBOX/audit-runner.rows"; grep -q 'gap_suites=0' <<<"$AOUT"; }
row_audit_bad() { audit "$SANDBOX/audit-bad.rows"; grep -q 'gap_suites=1' <<<"$AOUT"; }
row_audit_zero() { run_sut audit --root "$AREPO" --list "$SANDBOX/audit-empty.rows" >/dev/null 2>&1; [[ $? -eq 2 ]]; }
row_audit_ghost() { audit "$SANDBOX/audit-ghost.rows"; [[ "$RC" -eq 1 ]] && grep -q 'unaudited=1' <<<"$AOUT"; }
row_audit_always() { audit "$SANDBOX/audit-always.rows"; [[ "$RC" -eq 0 ]] && grep -q 'always_on=1' <<<"$AOUT"; }
row_audit_glob() { audit "$SANDBOX/audit-glob.rows"; [[ "$RC" -eq 0 ]] && grep -q 'gap_suites=0 gap_refs=0' <<<"$AOUT"; }
row_cleared_by_failed() { ej2_run; [[ "$(unit_field "$E2" "$(SHA 119)" .cls)" = unverified ]]; }
row_cleared_read_error() { ej2_run; [[ "$(unit_field "$E2" "$(SHA 121)" .cls)" = unverified ]]; }
row_shard_families() { ej2_run; local n; for n in 123 124 125; do [[ "$(unit_field "$E2" "$(SHA "$n")" .cls)" = unverified ]] || return 1; done; }
row_two_page() { ej2_run; [[ "$(unit_field "$E2" "$(SHA 118)" .cls)" = rule-irrelevant ]]; }
row_timed_out() { ej2_run; [[ -n "$(unit_field "$E2" "$(SHA 127)" .cls)" && "$(unit_field "$E2" "$(SHA 128)" .cls)" = not-evaluable ]]; }
row_no_sha() { ej2_run; [[ "$(unit_field "$E2" "$(SHA 132)" .reason)" == files:* ]]; }
row_ctrl_label() { ej2_run; [[ "$(unit_field "$E2" "$(SHA 129)" .cls)" = not-evaluable ]]; }
row_unclassified() { ej2_run; [[ "$(unit_field "$E2" "$(SHA 130)" .reason)" == "unclassified-job: mystery-job" ]]; }
row_file_cap() { ej2_run; [[ "$(unit_field "$E2" "$(SHA 131)" .reason)" == files:* ]]; }
row_full_events() { collect_once; [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[1]}" .cls)" = rule-irrelevant ]]; }
row_window() { run_sut ejections --out "$SANDBOX/ej-win" --commits 7 --repo "$R" 2>&1 | grep -q 'window 2031-01-02T12:00:00Z\.\.2031-01-08T12:00:00Z'; }
row_rate_limit() { REPO_NAME="$R3"; rm -rf "$OUT"; mkdir -p "$OUT"; : > "$GHLOG"; run_sut collect --out "$OUT" --commits 1 --chunk 1/1 --repo "$R3" >/dev/null 2>&1; local n; n="$(grep -c "^REQ $(keyof "$(runs_path "${C[6]}")")\$" "$GHLOG")"; REPO_NAME=""; [[ "$n" -eq 3 ]]; }
row_agg_no_ejections() { run_sut aggregate "$FE" >/dev/null 2>&1; [[ $? -eq 2 ]]; }
row_agg_gap() { run_sut aggregate "$FG" >/dev/null 2>&1; [[ $? -eq 2 ]]; }
row_agg_dup() { run_sut aggregate "$FH" >/dev/null 2>&1; [[ $? -eq 2 ]]; }
row_agg_expect() { run_sut aggregate "$FD" --expect-commits 4 >/dev/null 2>&1; [[ $? -eq 2 ]]; }
row_agg_arith() { run_sut aggregate "$FD" 2>&1 | grep -q 'mean_skipped_suite_min=20.00 se=5.77 selector_min=1.29 net_mean=18.71 net_mean_plus_2se=30.26'; }
row_agg_point() { run_sut aggregate "$FD" 2>&1 | grep -q 'unverified_as_escape=1/4 (point 25.00%)'; }
row_tsv() { run_sut aggregate "$FT" --out "$SANDBOX/tsv.txt" >/dev/null 2>&1; [[ "$(awk -F'\t' 'NF != 9 { bad++ } END { print bad + 0 }' "$SANDBOX/tsv.txt.tsv")" = 0 ]]; }
row_internal() { local e rc; e="$(run_sut aggregate "$FI" 2>&1 >/dev/null)"; rc=$?; [[ "$rc" -eq 4 ]] && grep -q 'internal error' <<<"$e"; }
row_two_prs() { local o; o="$(run_sut aggregate "$FP" 2>&1)"; grep -q '"unverified": 3' <<<"$o"; }
row_audit_parens() { audit "$SANDBOX/audit-parens.rows"; [[ "$RC" -eq 0 ]]; }
row_audit_exact() { audit "$SANDBOX/audit-exact.rows"; [[ "$RC" -eq 1 ]] && grep -q 'scripts/x.sh.bak' <<<"$AOUT"; }
row_audit_many() { audit "$SANDBOX/audit-many.rows" --all-refs; grep -P -q '^gap\tscripts/many\t8\t([^,]+,){7}[^,]+$' <<<"$AOUT"; }
row_audit_short() { audit "$SANDBOX/audit-short.rows"; [[ "$RC" -eq 1 ]] && grep -q 'short-row' <<<"$AOUT"; }
row_audit_sel_fail() { RUN_ENV=(PR_AFFECTED_REPLAY_TEST_ALL="$BIN/sel-partial.sh"); run_sut audit --root "$AREPO" >/dev/null 2>&1; local rc=$?; RUN_ENV=(); [[ "$rc" -eq 3 ]]; }
row_bad_env() { PR_AFFECTED_REPLAY_GH_TIMEOUT=abc python3 "$SUT" cp-upper 0 10 >/dev/null 2>&1; [[ $? -eq 2 ]]; }
row_agg_no_meta() { run_sut aggregate "$FM" >/dev/null 2>&1; [[ $? -eq 2 ]]; }
row_agg_short() { run_sut aggregate "$FN" >/dev/null 2>&1; [[ $? -eq 2 ]]; }
row_accept_dir() { audit "$SANDBOX/audit-dir.rows" --accept "$SANDBOX/accept-dir.tsv"; [[ "$RC" -eq 0 ]] && grep -q 'audited=0 unaudited=0' <<<"$AOUT"; }
row_accept_ok() { audit "$SANDBOX/audit-bad.rows" --accept "$SANDBOX/accept-ok.tsv"; [[ "$RC" -eq 0 ]] && grep -q 'accepted=2' <<<"$AOUT"; }
row_accept_badreason() { audit "$SANDBOX/audit-bad.rows" --accept "$SANDBOX/accept-badreason.tsv"; [[ "$RC" -eq 2 ]]; }
mutate always-on-skippable 'elif f[2] == "0" and f[3] != "always_on":' 'elif f[2] == "0":' row_always_on
mutate read-error-as-no-run 'runs, u["reason"] = None, "runs-read: %s" % e' 'runs, u["reason"] = [], ""' row_read_error
mutate bound-on-point-numerator 'cp_upper(attributable + unverified + ne, n)' 'cp_upper(attributable + unverified, n)' row_worst_bound
mutate flake-needs-two-file-sets 'len({x["files_hash"] for x in us}) >= 2' 'len({x["files_hash"] for x in us}) >= 1' row_flake_same_files
mutate flake-distinct-prs-dropped 'and len({x.get("pr") or x["sha"] for x in us}) >= 3}' 'and True}' row_flake_same_pr
mutate verdict-fail-dropped 'if "fail" in s:' 'if False:' row_verdict_fail
mutate unmeasured-as-pass 'if "unmeasured" in s:' 'if False:' row_unmeasured
mutate band-on-census-accepted 'if x == "within-10%":' 'if False:' row_band_b
mutate fail-regex-loosened 'FAIL_LINE = re.compile(r"^\[(?:FAIL|KILLED)\] ([A-Za-z0-9._/+-]+) \((?:\d+ms|exit=)")' 'FAIL_LINE = re.compile(r"^\[(?:FAIL|KILLED)\] ([A-Za-z0-9._/+-]+)")' row_selftest_line
mutate control-byte-label-accepted 'FAIL_LINE = re.compile(r"^\[(?:FAIL|KILLED)\] ([A-Za-z0-9._/+-]+) \(' 'FAIL_LINE = re.compile(r"^\[(?:FAIL|KILLED)\] (\S+) \(' row_ctrl_label
mutate killed-line-ignored 'FAIL_LINE = re.compile(r"^\[(?:FAIL|KILLED)\]' 'FAIL_LINE = re.compile(r"^\[(?:FAIL)\]' row_killed_line
mutate same-tree-ignored 'pick = ok[0] if ok else sorted(runs, key=lambda r: r["created_at"])[-1]' 'pick = sorted(runs, key=lambda r: r["created_at"])[0]' row_clear
mutate escape-from-attempt-counter 'elif unit.get("attempts_failed", 1) >= 2 and escape_confirmed(unit, repo, cache_dir, would_skip_hit):' 'elif unit.get("attempts_failed", 1) >= 2:' row_escape_unread
mutate escape-any-attempt-1-suite 'return bool(s1 & set(hit))' 'return True' row_escape_other_suite
mutate clearance-by-name 'hashlib.sha256("\n".join("%s %s" % (n, b) for n, b in pairs).encode())' 'hashlib.sha256("\n".join("%s" % n for n, b in pairs).encode())' row_blob
mutate clearance-earlier-success 'if o["created_at"] > r["created_at"] and o["conclusion"] == "success":' 'if o["created_at"] != r["created_at"] and o["conclusion"] == "success":' row_earlier
mutate clearance-without-pr 'if not pr or not unit.get("content_key"):' 'if not unit.get("content_key"):' row_nopr
mutate unsettled-jobs-ignored '[j["name"] for j in jobs if j.get("conclusion") not in SETTLED and j["name"] != "test"])' '[])' row_unsettled
mutate truncated-jobs-ignored 'if docs and docs[0].get("total_count") is not None and docs[0]["total_count"] != len(jobs):' 'if False:' row_trunc_jobs
mutate empty-diff-irrelevant 'if unit.get("fallback") == "not-evaluable" and unit.get("reason") == "empty-diff":' 'if False:' row_empty_diff
mutate window-offset-accepted 'if val and not ISO_UTC.match(val):' 'if False:' row_since_offset
mutate zero-window-clean '    if not runs:' '    if False:' row_zero_window
mutate truncated-runs-ignored 'if total is None or total != len(runs) or total >= SEARCH_CAP:' 'if False:' row_trunc_runs
mutate selector-env-open 'SELECT_ENV_KEEP = ("PATH", "LANG", "TMPDIR", "TZ", "USER", "SHELL")' 'SELECT_ENV_KEEP = ("PATH", "LANG", "TMPDIR", "TZ", "USER", "SHELL", "GH_TOKEN")' row_env
mutate git-location-inherited 'env = {k: v for k, v in os.environ.items() if k not in GIT_LOCATION_VARS}' 'env = None' row_git_env
mutate client-error-retried 'return not (m and m.group(1).startswith("4") and m.group(1) != "429")' 'return True' row_404
mutate timeout-dropped 'errors="replace", timeout=timeout)' 'errors="replace")' row_hang
mutate torn-line-kept 'except ValueError:
                dirty = True' 'except ValueError:
                dirty = False' row_torn
mutate reclassify-inert '(reclassify and u.get("cls") != "clean")' '(False and u.get("cls") != "clean")' row_reclassify
mutate sel-error-ignored '    if unit.get("sel_error"):
        unit["cls"], unit["reason"] = "not-evaluable", "selection: %s" % unit["sel_error"]
        return' '    if False:
        return' row_sel_error
mutate fallback-needs-rows '    if fb != "none":
        # a fallback (runner-changed, undecidable diff) runs the FULL battery and prints no per-suite rows: nothing is skipped
        return fb, [], 0, 0' '    if False:
        return fb, [], 0, 0' row_fallback_rows
mutate redo-flag-inert '(redo and (u.get("cls") == "not-evaluable" or not u.get("fallback")))' '(False and (u.get("cls") == "not-evaluable" or not u.get("fallback")))' row_redo
mutate nonascii-quoted '"--first-parent", "-z", sha]' '"--first-parent", sha]' row_nonascii
mutate cp-overflow 'math.exp(math.lgamma(n + 1) - math.lgamma(i + 1) - math.lgamma(n - i + 1)
                           + i * math.log(mid) + (n - i) * math.log1p(-mid))' 'math.comb(n, i) * mid ** i * (1 - mid) ** (n - i)' row_cp_big
mutate audit-comments-counted '        if t.startswith("#") or t.startswith("//"):
            continue' '        if False:
            continue' row_audit_comment
mutate audit-runner-not-excused 'f not in (suite, own) and f not in RUNNER_TRIGGERS and len(f) > 6' 'f not in (suite, own) and len(f) > 6' row_audit_runner
mutate audit-gap-blind 'miss = [r for r in suite_refs(root, suite, path, tracked) if not any(edge_hit(pt, r) for pt in pats)]' 'miss = [r for r in suite_refs(root, suite, path, tracked) if False]' row_audit_bad
mutate audit-zero-suites 'if suites == 0:' 'if False:' row_audit_zero
mutate audit-unread-suite-clean '                unaudited.append((suite, pats[0]))' '                pass' row_audit_ghost
mutate audit-always-on-audited '        if reason == "always_on":' '        if False:' row_audit_always
mutate audit-edge-as-regex '    if e.endswith("/"):
        return path.startswith(e)
    return path == e' '    return re.search(e, path) is not None' row_audit_parens
mutate audit-edge-as-regex-exact '    if e.endswith("/"):
        return path.startswith(e)
    return path == e' '    return re.search(e, path) is not None' row_audit_exact
mutate audit-glob-not-a-glob '    if e.startswith("glob:"):' '    if False:' row_audit_glob
mutate audit-all-refs-ignored '",".join(miss if a.all_refs else miss[:6])' '",".join(miss[:6])' row_audit_many
mutate audit-short-row-skipped '        if len(f) < 5:
            unaudited.append((f[1] if len(f) > 1 else "?", "short-row"))
            continue' '        if len(f) < 5:
            continue' row_audit_short
mutate audit-selector-rc-ignored '        if sp.returncode != 0:' '        if False:' row_audit_sel_fail
mutate bad-timeout-env-traceback 'except ValueError as _e:' 'except KeyError as _e:' row_bad_env
mutate ejections-manifest-optional '        if not os.path.exists(meta_path):' '        if False:' row_agg_no_meta
mutate ejections-count-unchecked '        if have != meta["refused"]:' '        if False:' row_agg_short
mutate accepted-unread-counted-audited 'suites - always_on - len(unaudited) - accepted_unread' 'suites - always_on - len(unaudited)' row_accept_dir
mutate accept-ignored '        kept = [r for r in miss if r not in ok]' '        kept = miss' row_accept_ok
mutate accept-without-reason 'or not re.match(r"^false-positive: \S", f[2])' 'or False' row_accept_badreason
mutate cleared-by-failed-run 'if o["created_at"] > r["created_at"] and o["conclusion"] == "success":' 'if o["created_at"] > r["created_at"]:' row_cleared_by_failed
mutate cleared-read-error-as-cleared '                    except ReadError:
                        return False' '                    except ReadError:
                        return True' row_cleared_read_error
mutate suite-job-narrowed 'SUITE_JOB = re.compile(r"^test-(scripts|webplat|bun)( \(|$)|^test-scripts-heavy( \(|$)")' 'SUITE_JOB = re.compile(r"^test-scripts( \(|$)")' row_shard_families
mutate pull-request-event-counted 'FULL_EVENTS = ("merge_group", "push")' 'FULL_EVENTS = ("merge_group", "push", "pull_request")' row_full_events
mutate commit-files-first-page-only '    files = []
    for d in docs:' '    files = []
    for d in docs[:1]:' row_two_page
mutate commit-file-cap-ignored '    if len(files) >= COMMIT_FILES_CAP:' '    if False:' row_file_cap
mutate timed-out-not-a-unit 'r["conclusion"] != "success"' 'r["conclusion"] == "failure"' row_timed_out
mutate blob-sha-optional '            if not x.get("sha"):' '            if False:' row_no_sha
mutate unclassified-job-reassuring '            if name.split(" (")[0] in ALWAYS_RUN_JOBS:' '            if True:' row_unclassified
mutate window-ends-swapped '        since = since or iso(shas[-1])
        until = until or iso(shas[0])' '        since = since or iso(shas[0])
        until = until or iso(shas[-1])' row_window
mutate window-ends-at-now '        until = until or iso(shas[0])' '        until = until or time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())' row_window
mutate rate-limit-not-retried '    return bool(m and m.group(1) == "403" and "rate limit" in (stderr or "").lower())' '    return False' row_rate_limit
mutate home-not-scratch '    env["HOME"] = home' '    env["HOME"] = os.environ.get("HOME", home)' row_home
mutate no-ejections-file-ok '    if not commits_only and not os.path.exists(os.path.join(d, "units-ejections.jsonl")):' '    if False:' row_agg_no_ejections
mutate commit-gap-ignored '    if commits and idxs != list(range(len(idxs))):' '    if False:' row_agg_gap
mutate duplicate-unit-ignored '                    if key in seen:' '                    if False:' row_agg_dup
mutate expect-commits-ignored '    if expect_commits is not None and len(commits) != expect_commits:' '    if False:' row_agg_expect
mutate se-sign-flipped 'net + 2 * se' 'net - 2 * se' row_agg_arith
mutate point-drops-unverified '"point": (attributable + unverified) / n if n else 0.0,' '"point": attributable / n if n else 0.0,' row_agg_point
mutate tsv-reason-unsanitised 're.sub(r"[\t\r\n]", " ", u["reason"])' 'u["reason"]' row_tsv
mutate internal-error-handler-dropped '    except Exception as e:  # an internal error must not exit 1, which is the audit'"'"'s "gaps found"
        print("replay: internal error: %s: %s" % (type(e).__name__, e), file=sys.stderr)
        return 4' '    except ZeroDivisionError:
        return 4' row_internal
mutate flake-pr-threshold-lowered 'len({x.get("pr") or x["sha"] for x in us}) >= 3}' 'len({x.get("pr") or x["sha"] for x in us}) >= 2}' row_two_prs

# ---------------------------------------------------------------------------------------------------------------------
echo "== controls: the harness reports a survivor, an unparseable mutant, a red row and an edit that did not land"
row_always_red() { false; }
mutant_outcome ctl-survive 'READ-ONLY. It never writes' 'READ-ONLY (edited). It never writes' row_verdict_fail
[[ "$MUT_RESULT" = survived ]] && pass "control: an edit outside the logic is reported as a SURVIVOR" || fail "control: survivor not reported ($MUT_RESULT)"
mutant_outcome ctl-invalid 'import argparse' 'import argparse )(' row_verdict_fail
[[ "$MUT_RESULT" = invalid ]] && pass "control: a mutant that does not parse is INVALID, not killed" || fail "control: invalid mutant not reported ($MUT_RESULT)"
mutant_outcome ctl-nochange 'import argparse' 'import argparse' row_always_red
[[ "$MUT_RESULT" = edit-failed ]] && pass "control: an edit that changes nothing is reported, not counted" || fail "control: no-change edit not reported ($MUT_RESULT)"
mutant_outcome ctl-red2 'READ-ONLY. It never writes' 'READ-ONLY (edited). It never writes' row_always_red
[[ "$MUT_RESULT" = row-red-on-pristine ]] && pass "control: a row that is red on the pristine SUT is reported, not counted as a kill" || fail "control: red row not reported ($MUT_RESULT)"
mutant_outcome ctl-nolanding 'THIS TEXT IS NOT IN THE SCRIPT' 'x' row_verdict_fail
[[ "$MUT_RESULT" = edit-failed ]] && pass "control: an edit that does not land is reported" || fail "control: edit-failed not reported ($MUT_RESULT)"
ctl_mutate_records() {  # drive mutate() with a survivor: it must record a FAILURE, then unwind
  local p0=$passes f0=$fails n0=${#FAILED[@]} m0=$MUT_RUN k0=$MUT_KILLED f1
  mutate ctl-survive-through-mutate 'READ-ONLY. It never writes' 'READ-ONLY (edited). It never writes' row_verdict_fail >/dev/null 2>&1
  f1=$fails
  passes=$p0; fails=$f0; MUT_RUN=$m0; MUT_KILLED=$k0
  if (( n0 == 0 )); then FAILED=(); else FAILED=("${FAILED[@]:0:n0}"); fi
  [[ $((f1 - f0)) -eq 1 ]]
}
ctl_mutate_records && pass "control: mutate() records a survivor as a failure" || fail "control: mutate() did not record a survivor as a failure"
if [[ "$MUT_KILLED" -eq "$MUT_RUN" ]]; then pass "every mutant was killed ($MUT_KILLED of $MUT_RUN)"; else fail "mutants killed $MUT_KILLED of $MUT_RUN"; fi

# Anti-vacuity floors, reported through printf + exit so they never ride on the helpers they guard.
FLOOR_ASSERTIONS=213
total=$((passes + fails))
if [[ "$total" -lt "$FLOOR_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$total" "$FLOOR_ASSERTIONS" >&2; exit 1
fi
FLOOR_MUTANTS=74
if [[ "$MUT_RUN" -lt "$FLOOR_MUTANTS" ]]; then
  printf '[FATAL] mutation floor: only %s mutants ran, floor is %s\n' "$MUT_RUN" "$FLOOR_MUTANTS" >&2; exit 1
fi
echo "ci-pr-affected-replay.test.sh: $passes passed, $fails failed, $total assertions, $MUT_RUN mutants"
[[ "$fails" -eq 0 ]] && exit 0
printf 'FAILED: %s\n' "${FAILED[@]}" >&2
exit 1
