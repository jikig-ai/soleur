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
# THE AUDIT REACH (S4 index completion PR1b, #10448): the section `== audit reach (PR1b)` pins the source closure (depth, operand forms, symlinks, cycles, a fan-out lattice under a line-event cap), the
# naming walk over the selector row's code files (per row, CODE_EXT per extension, closures feeding the next level, directory suites), the canonical read order, the comment table per extension, the edge
# credit against the REAL bash `_diff_edge_hit`/`_diff_touches` (extracted by content anchors), a linear-time bound on one long `source` token and the reach-differential generator's stop line.
# THE AUDIT SCAN (S4 index completion PR1, #10448). A reference is a tracked path named at a boundary: the character before it is
# not [A-Za-z0-9_], after printf escapes (\t, \0, \x09, \u0009 ...) and an attached short option (-Iplugins/x) are blanked ONCE by
# views(); the SUT's start regex and boundary() derive from that one definition, and this file keeps independent oracles of its own. The scan walks a trie of the tracked
# paths with the per-file result memoised across suites; a directory suite is read through its bun test files; an accept row is
# keyed on the whitespace-collapsed ORIGINAL line it describes. The work bound is an operation count, never a clock, read from two
# instruments (PathIndex.ops, and an independent profile-event count that a mutant cannot under-report). The committed
# receipts/audit-differential.tsv is judged per occurrence, on its stored line text, with the SUT's own views()/boundary(); this file does
# NOT regenerate the pinned-tree receipt, so the completeness of its rows is attested by re-running receipts/audit-differential.py.
# A mutant that CRASHES (does not import, exits rc 4, prints a Traceback) is never a kill.
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
RCLOG="$SANDBOX/rc.log"; : > "$RCLOG"
run_sut() {  # run_sut <args...>; the repo is the cwd, the selector and gh are stubs; prints stdout. Every exit code is appended to $RCLOG, so a mutant that CRASHES (rc 4) is told apart from one that merely changes an answer
  local rc
  ( cd "$REPO" && env PATH="$BIN:$PATH" PR_AFFECTED_REPLAY_TEST_ALL="$BIN/sel.sh" PR_AFFECTED_REPLAY_RETRY_SLEEP=0 HOME="$FIXHOME" "${RUN_ENV[@]}" timeout 30 python3 "$SUT" "$@" ); rc=$?   # a hang (a FIFO opened blocking) is rc 124, a red row
  printf '%s\n' "$rc" >> "$RCLOG"
  return "$rc"
}
unit_field() {  # unit_field <jsonl> <sha> <jq expr>
  jq -r --arg s "$2" "select(.sha==\$s) | $3" "$1"
}
py_sut() {  # python3 "$SUT" with the exit code logged, so mutant_outcome can tell a crash (rc 4) from a changed answer
  local rc
  python3 "$SUT" "$@"; rc=$?
  printf '%s\n' "$rc" >> "$RCLOG"
  return "$rc"
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
[[ "$rc" -eq 0 ]] && grep -q 'SUBCOMMANDS' <<<"$helptxt" && grep -q 'THE PROPOSED RULE' <<<"$helptxt" && grep -q 'pinned' <<<"$helptxt" \
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
[[ -n "$ci_jobs" && "$ci_jobs" = "$py_jobs" ]] && pass "the always-run job set plus the four shard families is exactly ci.yml's job list (a new job there must be classified here)" || fail "job parity: ci-only='$(LC_ALL=C comm -23 <(echo "$ci_jobs") <(echo "$py_jobs") | tr '\n' ' ')' tool-only='$(LC_ALL=C comm -13 <(echo "$ci_jobs") <(echo "$py_jobs") | tr '\n' ' ')'"
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
# An accept row is anchor-keyed: suite, path, anchor, ordinal, reason. The anchor is the first 12 hex of the sha256 of the source
# line with its whitespace collapsed; this oracle is bash (tr, sed, sha256sum), independent of the SUT's own hashing.
anchor_of() { local n; n="$(printf '%s' "$1" | tr -s '[:space:]' ' ' | sed -E 's/^ +//; s/ +$//')"; printf '%s' "$n" | sha256sum | cut -c1-12; }
A_CI="$(anchor_of 'cat .github/workflows/ci.yml')"; A_GV="$(anchor_of 'bash scripts/guard-vacuity-floor.test.sh')"
printf 'scripts/lint-orphan-mutations\t.github/workflows/ci.yml\t%s\t1\tfalse-positive: fixture write into a scratch repo\nscripts/lint-orphan-mutations\tscripts/guard-vacuity-floor.test.sh\t%s\t1\tfalse-positive: only mentioned in a message\n' "$A_CI" "$A_GV" > "$SANDBOX/accept-ok.tsv"
printf 'scripts/lint-orphan-mutations\t.github/workflows/ci.yml\t%s\t1\n' "$A_CI" > "$SANDBOX/accept-noreason.tsv"
printf 'scripts/lint-orphan-mutations\t.github/workflows/ci.yml\t%s\t1\tbecause I said so\n' "$A_CI" > "$SANDBOX/accept-badreason.tsv"
printf 'adir\t*\t-\t-\tfalse-positive: a directory suite whose reads the index declares by prefix\n' > "$SANDBOX/accept-dir.tsv"
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
# PR1 of the S4 index completion (#9729, #10448): the audit's match is a path-component-boundary scan with per-file
# memoisation (it replaces the every-tracked-path `f in blob` scan, 53 s on 19,367 paths), directory suites are audited
# through their bun-discoverable test files, and an accept row is keyed on the line it describes. Every fixture below is a
# row that distinguishes the mutant from the real thing: a negative fixture (a mid-component mention that is NOT a read)
# always sits beside a positive control (the same shape at a boundary) that IS reported, so an empty result cannot pass.
echo "== audit scan: component-boundary match, memoisation, comment shapes, out-of-charset paths"
SREPO="$SANDBOX/srepo"
assert_fixture_dir "$SREPO"
mkf() {  # mkf <relpath> <content>: write one fixture file under the scan repo, content verbatim (no newline is added)
  assert_fixture_dir "$SREPO"; mkdir -p "$(dirname "$SREPO/$1")" && printf '%s' "$2" > "$SREPO/$1"
}
SFILES=(ab/cd.sh xy/ab/cd.sh lib/mid.txt data/p1.txt data/p2.txt data/end.txt data/esc1.txt data/esc2.txt "apps/(auth)/page.tsx" "apps/[id]/page.tsx"
  apps/@scope/x.tsx apps/+page/x.svelte "apps/with space/y.txt" docs/hd-hash.md docs/hd-plain.md docs/trail.md docs/tabc.md
  docs/crlf.md data/one.txt data/two.txt docs/acc1.md data/acc2.txt data/dup.txt docs/mixed.md docs/ws.md docs/cmt.md
  docs/guide.md data/spec.txt data/nested.txt data/under.txt docs/shonly.md docs/notes-only.md dsuite/inner.txt dsuite/notes.txt)
for f in "${SFILES[@]}"; do mkf "$f" $'t\n'; done
mkf lib1/helper.sh $'cat data/one.txt\n'
mkf lib2/helper.sh $'cat data/two.txt\n'
mkf lib1/shared.sh $'cat scripts/pa.test.sh\n'
mkf scripts/suffix.test.sh $'cat "xy/ab/cd.sh"\n'
mkf scripts/tabbed.test.sh $'true\n\tdata/p1.txt\n'
mkf scripts/mid.test.sh $'cat xlib/mid.txt\n'
mkf scripts/midok.test.sh $'cat "lib/mid.txt"\n'
mkf scripts/two.test.sh $'cat data/p1.txt data/p2.txt\n'
mkf scripts/eol.test.sh 'cat data/end.txt'
mkf scripts/esc.test.sh $'printf \'A\\tdata/esc1.txt\\nB\\ndata/esc2.txt\\n\'\n'
mkf scripts/charset.test.sh $'cat "apps/(auth)/page.tsx"\ncat "apps/[id]/page.tsx"\ncat apps/@scope/x.tsx\ncat apps/+page/x.svelte\ncat "apps/with space/y.txt"\n'
mkf scripts/shapes.test.sh $'cat <<\'EOF\'\n# docs/hd-hash.md\ncp docs/hd-plain.md x\nEOF\ntrue # docs/trail.md\n\t# docs/tabc.md\n'
mkf scripts/crlf.test.sh $'cat docs/crlf.md\r\ntrue\r\n'
mkf scripts/s1.test.sh $'source lib1/helper.sh\n'
mkf scripts/s2.test.sh $'source lib2/helper.sh\n'
mkf scripts/pa.test.sh $'source lib1/shared.sh\n'
mkf scripts/pb.test.sh $'source lib1/shared.sh\n'
mkf scripts/acc.test.sh $'cat docs/acc1.md\necho data/acc2.txt\n'
mkf scripts/dup.test.sh $'cat data/dup.txt\ncat data/dup.txt\n'
mkf scripts/mixed.test.sh $'cat docs/mixed.md\necho "see docs/mixed.md"\n'
mkf scripts/ws.test.sh $'\t\tcat   docs/ws.md\r\n'
mkf scripts/cmt.test.sh $'# cat docs/cmt.md\ntrue\n'
mkf scripts/alw.test.sh $'cat docs/acc1.md\n'
mkf dsuite/a.test.ts $'readFileSync("docs/guide.md")\n'
mkf dsuite/b.test.tsx $'readFileSync("dsuite/inner.txt")\n'
mkf dsuite/c.spec.js $'readFileSync("data/spec.txt")\n'
mkf dsuite/d.test.sh $'cat docs/shonly.md\n'
mkf dsuite/notes.md $'docs/notes-only.md\n'
mkf dsuite/sub/e.test.js $'readFileSync("data/nested.txt")\n'
mkf dsuite/f_test.ts $'readFileSync("data/under.txt")\n'
# bun's discovery over js, jsx, ts, tsx, mjs, cjs, mts, cts (a SUPERSET: bunfig pathIgnorePatterns are deliberately not applied, over-scanning is the safe
# direction); a snapshot file and a name that merely ends in "test.ts" are not tests
for ext in jsx mjs cjs mts cts; do
  mkf "data/$ext.txt" $'t\n'
done
mkf data/snap.txt $'t\n'; mkf data/latest.txt $'t\n'; mkf data/dl.txt $'t\n'
mkf dsuite/g.test.jsx $'readFileSync("data/jsx.txt")\n'
mkf dsuite/i.test.mjs $'readFileSync("data/mjs.txt")\n'
mkf dsuite/j.spec.cjs $'readFileSync("data/cjs.txt")\n'
mkf dsuite/k.test.mts $'readFileSync("data/mts.txt")\n'
mkf dsuite/l.test.cts $'readFileSync("data/cts.txt")\n'
mkf dsuite/h.test.ts.snap $'readFileSync("data/snap.txt")\n'
mkf dsuite/latest.ts $'readFileSync("data/latest.txt")\n'
# a directory suite holding a readable test and a tracked symlink to nothing (a member the audit cannot read)
mkf dlink/ok.test.ts $'readFileSync("data/dl.txt")\n'
ln -s nowhere "$SREPO/dlink/dang.test.ts"
# one boundary: the character before the path is not [A-Za-z0-9_], after printf escapes and an attached short option are blanked
for f in bx/z0.txt bx/x09.txt bx/o011.txt bx/u0009.txt bx/a.txt bx/e.txt bx/opt.txt bx/ansi.md bx/ansi2.md docs/bm.md docs/bs.md docs/be.md docs/cmt2.md docs/nbsp.md m.txt; do mkf "$f" $'t\n'; done
mkf scripts/escx.test.sh "$(cat <<'ESCX'
printf 'A\0bx/z0.txt\n'
printf 'A\x09bx/x09.txt\n'
printf 'A\011bx/o011.txt\n'
printf 'A\u0009bx/u0009.txt\n'
printf 'A\abx/a.txt\n'
printf 'A\ebx/e.txt\n'
gcc -Ibx/opt.txt
ESCX
)"$'\n'
mkf scripts/ansi.test.sh "$(cat <<'ANSI'
printf '\033[0mbx/ansi.md\n'
cat bx/ansi2.md
ANSI
)"$'\n'
mkf scripts/bnd.test.sh $'cat docs/bm.md\necho xdocs/bm.md\necho x_docs/bm.md\necho 7docs/bm.md\n'
mkf scripts/bnd0.test.sh $'docs/bs.md\n'
mkf scripts/bnde.test.sh "$(cat <<'BNDE'
printf 'A\x09docs/be.md\n'
BNDE
)"$'\n'
mkf scripts/cmt2.test.sh $'# first comment\n\n# docs/cmt2.md in a comment\ncat docs/cmt2.md\n'
mkf docs/vt.md $'t\n'; mkf docs/vt2.md $'t\n'
mkf scripts/vt.test.sh $'echo\x0b# docs/vt.md\ncat docs/vt2.md\n'
mkf scripts/hop.test.sh $'source lib1/helper.sh\nsource ./lib1/helper.sh\n'
mkf scripts/short.test.sh $'cat m.txt\n'
mkf scripts/nbsp.test.sh $'cat\xc2\xa0\xc2\xa0 docs/nbsp.md\n'
NAME_NA="docs/caf$(printf '\303\251').md"; mkf "$NAME_NA" $'t\n'
mkf scripts/nonascii.test.sh "cat $NAME_NA"$'\n'
# the table-driven preceding-character fixture: line 1 is a path at the start of a line; each keep line has ONE preceding
# character before the path (after an `a` that is not itself part of the path); the drop lines end in a word character
PC_KEEP_PRE=(' ' $'\t' '"' "'" 'a/' 'a=' 'a:' 'a(' 'a$(' 'a{' 'a<' 'a>' 'a|' 'a;' 'a,' 'a@' 'a-' 'a.' 'a`' 'a&' 'a!' 'a+' 'a[' 'a#' '${V:-')
PC_DROP_PRE=('a_' 'a7' 'ab')
PC_BODY=$'pc/k01.txt\n'; PC_WANT="pc/k01.txt"; PC_DROPS=(); n=1; mkf pc/k01.txt $'t\n'
for pre in "${PC_KEEP_PRE[@]}"; do
  n=$((n + 1)); nn="$(printf '%02d' "$n")"; mkf "pc/k$nn.txt" $'t\n'; PC_BODY+="cat ${pre}pc/k$nn.txt"$'\n'; PC_WANT+=",pc/k$nn.txt"
done
for pre in "${PC_DROP_PRE[@]}"; do
  n=$((n + 1)); nn="$(printf '%02d' "$n")"; mkf "pc/k$nn.txt" $'t\n'; PC_BODY+="cat ${pre}pc/k$nn.txt"$'\n'; PC_DROPS+=("pc/k$nn.txt")
done
mkf scripts/prec.test.sh "$PC_BODY"
# ---- review round 2: duplicate selector labels, top-level names with regex metacharacters, escape-adjacent heads, sourced non-regular files,
# unreadable members, control characters in names, a lone CR, symlinks that must not be read, identical lines in a suite and its library
for f in data/untr.txt data/lbl.txt data/sib.txt data/da.txt data/db.txt data/tw.txt data/idl.txt data/sy.txt data/out.txt lib/cr.txt a+b/y.txt "(tl)/z.txt" tests/foo.txt bin/x.txt ecosystem/y.txt dat1/x.txt dat2/x.txt dat3/x.txt pv/p.txt pi/p.txt; do mkf "$f" $'t\n'; done
mkf scripts/dupa.test.sh $'cat data/da.txt\n'; mkf scripts/dupb.test.sh $'cat data/db.txt\n'; mkf scripts/dupn.test.sh $'true\n'
mkf scripts/mt.test.sh $'cat a+b/y.txt\ncat (tl)/z.txt\n'
mkf scripts/escadj.test.sh "$(cat <<'ESCADJ'
cat \tests/foo.txt
cat \bin/x.txt
cat \ecosystem/y.txt
printf '\x09dat1/x.txt'
printf '\011dat2/x.txt'
printf '\033[0mdat3/x.txt'
echo ${V:-pv/p.txt}
gcc -I pi/p.txt
ESCADJ
)"$'\n'
mkdir -p "$SREPO/lib3"; ln -s nowhere "$SREPO/lib3/dangling.sh"; ln -s ../data "$SREPO/lib3/dirlink.sh"; mkf lib3/gone.sh $'cat data/one.txt\n'
mkf scripts/hopd.test.sh $'source lib3/dangling.sh\n'; mkf scripts/hopl.test.sh $'source lib3/dirlink.sh\n'; mkf scripts/hopg.test.sh $'source lib3/gone.sh\n'
mkf scripts/cr.test.sh $'cat x\r# lib/cr.txt\n'; mkf scripts/crl.test.sh $'cat data/one.txt\n'
# R3: a tracked suite file that is deleted, dangling or a directory link; an untracked hop; an alias hop; two rows of one label; control characters
mkf scripts/stdel.test.sh $'cat data/one.txt\n'; ln -s nowhere "$SREPO/scripts/stdang.test.sh"; ln -s ../data "$SREPO/scripts/stdlink.test.sh"
mkf scripts/hopu.test.sh $'source lib1/untracked.sh\n'; mkf scripts/hopa.test.sh $'source lib1/helper.sh\nsource lib1/alias.sh\n'; ln -s helper.sh "$SREPO/lib1/alias.sh"
mkf scripts/lbla.test.sh $'cat data/lbl.txt\n'; mkf scripts/lblb.test.sh $'cat data/lbl.txt\n'; mkf scripts/aoo.test.sh $'cat docs/acc1.md\n'
mkf scripts/escn.test.sh "cat xlib/e$(printf '\033')sc.txt"$'\n'
mkf scripts/twob.test.sh $'cat data/p1.txt data/p2.txt\n'
mkf scripts/bnd1.test.sh $'docs/b1.md\nxdocs/b1.md\n'; mkf docs/b1.md $'t\n'
mkf "lib/e$(printf '\033')sc.txt" $'t\n'
mkf scripts/ctl.test.sh "$(printf 'printf x lib/t\tab.txt \033[31m\n')"$'\n'
mkf scripts/idl.test.sh $'source lib1/idl.sh\ncat data/idl.txt\n'; mkf lib1/idl.sh $'cat data/idl.txt\n'
mkf scripts/tw1.test.sh $'cat data/tw.txt\n'; mkf scripts/tw2.test.sh $'cat data/tw.txt\n'
mkf "lib/$(printf 'b\nc').txt" $'t\n'; mkf $'lib/t\tab.txt' $'t\n'; mkf "lib/$(printf 'b\rc').txt" $'t\n'
mkf scripts/qq.test.sh $'cat \'lib/b\nc.txt\'\ncat lib/t\tab.txt\ncat \'lib/b\rc.txt\'\n'
printf 'readFileSync("data/out.txt")\n' > "$SANDBOX/outside.txt"
mkf dsym/ok.test.ts $'readFileSync("data/sy.txt")\n'
head -c 9437184 /dev/zero > "$SREPO/dsym/big.test.ts"   # 9 MiB, over the 8 MiB read cap
head -c 8388608 /dev/zero > "$SREPO/dsym/exact.test.ts"   # exactly the 8 MiB cap: still read
mkdir -p "$SANDBOX/srepo-evil"; printf 'readFileSync("data/sib.txt")\n' > "$SANDBOX/srepo-evil/secret.txt"   # a SIBLING that shares the root's name prefix
ln -s ../../srepo-evil/secret.txt "$SREPO/dsym/sib.test.ts"; ln -s loop.test.ts "$SREPO/dsym/loop.test.ts"; ln -s fifo.pipe "$SREPO/dsym/fifo.test.ts"
ln -s ok.test.ts "$SREPO/dsym/inner.test.ts"; ln -s /dev/zero "$SREPO/dsym/zero.test.ts"; ln -s "$SANDBOX/outside.txt" "$SREPO/dsym/out.test.ts"
PC_LINES=("pc/k01.txt"); PC_PATHS=("pc/k01.txt"); n=1
for pre in "${PC_KEEP_PRE[@]}"; do n=$((n + 1)); PC_LINES+=("cat ${pre}pc/k$(printf '%02d' "$n").txt"); PC_PATHS+=("pc/k$(printf '%02d' "$n").txt"); done
(cd "$SREPO" && gitq init -q -b main . && gitq add -A && gitq commit -qm seed) || { echo "[FATAL] scan fixture" >&2; exit 1; }
rm -f "$SREPO/lib3/gone.sh" "$SREPO/scripts/stdel.test.sh"   # tracked, deleted from the work tree
printf 'cat data/untr.txt\n' > "$SREPO/lib1/untracked.sh"   # present, NOT tracked
mkfifo "$SREPO/dsym/fifo.pipe"   # a FIFO inside the tree, reached through a tracked symlink (untracked itself)
sfix_ok=1; for f in "${SFILES[@]}" scripts/shapes.test.sh dsuite/f_test.ts dsuite/l.test.cts dsuite/h.test.ts.snap dlink/dang.test.ts scripts/escx.test.sh scripts/prec.test.sh pc/k28.txt "$NAME_NA" bx/e.txt lib3/dangling.sh lib3/dirlink.sh lib3/gone.sh dsym/zero.test.ts dsym/out.test.ts scripts/escadj.test.sh "lib/$(printf 'b\nc').txt" dsym/sib.test.ts dsym/loop.test.ts dsym/fifo.test.ts dsym/exact.test.ts scripts/stdang.test.sh scripts/stdlink.test.sh scripts/stdel.test.sh lib1/alias.sh scripts/ctl.test.sh "lib/e$(printf '\033')sc.txt"; do gitq -C "$SREPO" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || { sfix_ok=0; printf "MISSING planted path: %q\n" "$f" >&2; }; done
[[ "$sfix_ok" -eq 1 ]] && pass "the scan fixture repo tracks every planted path (a fixture that did not land would pass its negative rows vacuously)" || fail "the scan fixture repo is missing a planted path"
srow() {  # srow <label> [extra patterns, joined with |]: one selector row for scripts/<label>
  printf 'AFFECTED_SELECTED\tscripts/%s\t0\tedge:derived\t^scripts/%s.test.sh%s\n' "$1" "$1" "${2:+|$2}"
}
saudit() { RC=0; AOUT="$(run_sut audit --root "$SREPO" --list "$1" ${2:+"$2"} ${3:+"$3"} ${4:+"$4"} 2>&1)" || RC=$?; }   # saudit <rows> [--accept F | --all-refs] [..]
srow suffix > "$SANDBOX/s-suffix.rows"; srow tabbed > "$SANDBOX/s-tabbed.rows"; { srow mid; srow midok; } > "$SANDBOX/s-mid.rows"
srow two > "$SANDBOX/s-two.rows"; srow esc > "$SANDBOX/s-esc.rows"; srow eol > "$SANDBOX/s-eol.rows"; srow charset > "$SANDBOX/s-charset.rows"
srow shapes > "$SANDBOX/s-shapes.rows"; srow crlf > "$SANDBOX/s-crlf.rows"
{ srow s1 '^lib1/helper.sh'; srow s2 '^lib2/helper.sh'; } > "$SANDBOX/s-base.rows"
{ srow pa '^lib1/shared.sh'; srow pb '^lib1/shared.sh'; } > "$SANDBOX/s-poison.rows"
row_scan_suffix() { saudit "$SANDBOX/s-suffix.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/suffix\t2\tab/cd.sh,xy/ab/cd.sh' <<<"$AOUT"; }
row_scan_tab() { saudit "$SANDBOX/s-tabbed.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/tabbed\t1\tdata/p1.txt' <<<"$AOUT"; }
row_scan_mid() { saudit "$SANDBOX/s-mid.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/midok\t1\tlib/mid.txt' <<<"$AOUT" && ! grep -P -q '^gap\tscripts/mid\t' <<<"$AOUT"; }
row_scan_two() { saudit "$SANDBOX/s-two.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/two\t2\tdata/p1.txt,data/p2.txt' <<<"$AOUT"; }
row_scan_esc() { saudit "$SANDBOX/s-esc.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/esc\t2\tdata/esc1.txt,data/esc2.txt' <<<"$AOUT"; }
row_scan_eol() { saudit "$SANDBOX/s-eol.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/eol\t1\tdata/end.txt' <<<"$AOUT"; }
row_scan_charset() { saudit "$SANDBOX/s-charset.rows" --all-refs; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/charset\t5\tapps/(auth)/page.tsx,apps/+page/x.svelte,apps/@scope/x.tsx,apps/[id]/page.tsx,apps/with space/y.txt' <<<"$AOUT"; }
row_scan_shapes() { saudit "$SANDBOX/s-shapes.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/shapes\t2\tdocs/hd-plain.md,docs/trail.md' <<<"$AOUT"; }
row_scan_crlf() { saudit "$SANDBOX/s-crlf.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/crlf\t1\tdocs/crlf.md' <<<"$AOUT"; }
row_scan_basename() { saudit "$SANDBOX/s-base.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/s1\t1\tdata/one.txt' <<<"$AOUT" && grep -qxF -- $'gap\tscripts/s2\t1\tdata/two.txt' <<<"$AOUT"; }
row_scan_poison() { saudit "$SANDBOX/s-poison.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/pb\t1\tscripts/pa.test.sh' <<<"$AOUT" && ! grep -P -q '^gap\tscripts/pa\t' <<<"$AOUT"; }
row_scan_suffix && pass "a tracked path that is a suffix of a longer tracked path (ab/cd.sh in xy/ab/cd.sh) is a match at its own component boundary: both are reported" || fail "suffix-path fixture (rc=$RC): $AOUT"
row_scan_tab && pass "a path preceded by a tab is a match (must-PASS, not the canonical space or quote)" || fail "tab-preceded fixture (rc=$RC): $AOUT"
row_scan_mid && pass "a mention that starts mid-component (xlib/mid.txt) is NOT a read, while the same path at a boundary (control, same run) is reported" || fail "mid-component fixture (rc=$RC): $AOUT"
row_scan_two && pass "two paths on one line are both reported (the scan does not stop at the first member)" || fail "two-path fixture (rc=$RC): $AOUT"
row_scan_esc && pass "a path after a printf escape (the source text has 'A\\tdata/x', the program has a tab) is a boundary: the letter before it is not a word" || fail "printf escape fixture (rc=$RC): $AOUT"
row_scan_eol && pass "a path at the very end of a file with no trailing newline is reported (an end-of-text off-by-one would hide it)" || fail "no-trailing-newline fixture (rc=$RC): $AOUT"
row_scan_charset && pass "paths with ( ) [ ] @ + and a space inside a component are matched component by component (five shapes, one run)" || fail "out-of-charset fixture (rc=$RC): $AOUT"
row_scan_shapes && pass "comment shapes: a whole-line # (heredoc body or tab-indented) is stripped; a trailing comment and a plain heredoc body line keep the path" || fail "comment-shape fixture (rc=$RC): $AOUT"
row_scan_crlf && pass "a path at the end of a CRLF line is reported (the carriage return is not part of the match)" || fail "CRLF fixture (rc=$RC): $AOUT"
row_scan_basename && pass "two libraries with the same basename in different directories keep their own refs (memo keyed on the full path, not the basename)" || fail "basename-collision fixture (rc=$RC): $AOUT"
row_scan_poison && pass "a memo filled while processing suite A does not drop A's own path for suite B that sources the same library" || fail "cache-poisoning fixture (rc=$RC): $AOUT"

echo "== audit scan: ONE boundary definition (the previous character is not [A-Za-z0-9_]); printf escapes and an attached short option are blanked once"
for k in escx ansi prec nonascii short nbsp cmt2 mixed bnd bnd0 bnde vt hop; do srow "$k" > "$SANDBOX/s-$k.rows"; done
row_scan_escapes() { saudit "$SANDBOX/s-escx.rows" --all-refs; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/escx\t7\tbx/a.txt,bx/e.txt,bx/o011.txt,bx/opt.txt,bx/u0009.txt,bx/x09.txt,bx/z0.txt' <<<"$AOUT"; }
row_scan_ansi() { saudit "$SANDBOX/s-ansi.rows" --all-refs; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/ansi\t1\tbx/ansi2.md' <<<"$AOUT" && ! grep -q 'bx/ansi.md' <<<"$AOUT"; }
row_scan_prec() { saudit "$SANDBOX/s-prec.rows" --all-refs; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/prec\t'"$((${#PC_KEEP_PRE[@]} + 1))"$'\t'"$PC_WANT" <<<"$AOUT"; }
row_scan_nonascii() { saudit "$SANDBOX/s-nonascii.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/nonascii\t1\t'"$NAME_NA" <<<"$AOUT"; }
row_scan_short() { saudit "$SANDBOX/s-short.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/short\t1\tm.txt' <<<"$AOUT"; }
row_scan_escapes && pass "after a letter, each of \\0 \\x09 \\011 \\u0009 \\a \\e (and an attached -I) is a boundary: all seven paths are reported, none lost to the word character in front of the escape" || fail "escape-form fixture (rc=$RC): $AOUT"
row_scan_ansi && pass "DECLARED DROP: a path glued to an ANSI colour code (\\033[0m<path>) is display text, not a read: the leftover m is a word character, and the control path beside it is reported" || fail "ansi declared-drop fixture (rc=$RC): $AOUT"
row_scan_prec && pass "table-driven: a path is a match after a line start, space, tab, quote, slash, = : ( \$( { < > | ; , @ - . backtick & ! + [ # (26 keep lines, the last one the default of a parameter expansion, \${V:-path}), and after _, a digit or a letter it is NOT (3 drop lines)" || fail "preceding-character table (rc=$RC): $AOUT"
row_scan_nonascii && pass "NUL-separated tracked listing (-z): a tracked name with non-ASCII bytes is matched raw (the quoted form git prints without -z can never match a read)" || fail "non-ASCII tracked name (rc=$RC): $AOUT"
row_scan_short && pass "a tracked path of six characters or fewer (m.txt) is reported: there is no length filter" || fail "short tracked path (rc=$RC): $AOUT"
row_scan_nbsp() { saudit "$SANDBOX/s-nbsp.rows" --all-refs; [[ "$RC" -eq 1 ]] && grep -qxF -- $'ref\tscripts/nbsp\tdocs/nbsp.md\tscripts/nbsp.test.sh:1\t'"$(anchor_of 'cat docs/nbsp.md')"$'/1\tcat docs/nbsp.md' <<<"$AOUT"; }
row_scan_nbsp && pass "the anchor recipe is str.split(): a line holding non-breaking spaces hashes like its ASCII-collapsed text (the bash oracle is byte-wise, so every OTHER fixture line is ASCII-whitespace only)" || fail "unicode whitespace anchor (rc=$RC): $AOUT"
row_scan_refs() {
  saudit "$SANDBOX/s-cmt2.rows" --all-refs; [[ "$RC" -eq 1 ]] || return 1
  grep -qxF -- $'ref\tscripts/cmt2\tdocs/cmt2.md\tscripts/cmt2.test.sh:4\t'"$(anchor_of 'cat docs/cmt2.md')"$'/1\tcat docs/cmt2.md' <<<"$AOUT" || return 1
  saudit "$SANDBOX/s-mixed.rows" --all-refs; [[ "$RC" -eq 1 ]] || return 1
  grep -qxF -- $'ref\tscripts/mixed\tdocs/mixed.md\tscripts/mixed.test.sh:1\t'"$(anchor_of 'cat docs/mixed.md')"$'/1\tcat docs/mixed.md' <<<"$AOUT" &&
    grep -qxF -- $'ref\tscripts/mixed\tdocs/mixed.md\tscripts/mixed.test.sh:2\t'"$(anchor_of 'echo "see docs/mixed.md"')"$'/1\techo "see docs/mixed.md"' <<<"$AOUT"
}
# the boundary() twin: which lines an accept row can exempt. Each suite holds a boundary line and/or a mid-component line for the same path
A_BM="$(anchor_of 'cat docs/bm.md')"; A_BS="$(anchor_of 'docs/bs.md')"; A_BE="$(anchor_of "printf 'A\\x09docs/be.md\\n'")"
printf 'scripts/bnd\tdocs/bm.md\t%s\t1\tfalse-positive: only the boundary line is the read under test\n' "$A_BM" > "$SANDBOX/b-bnd.tsv"
printf 'scripts/bnd0\tdocs/bs.md\t%s\t1\tfalse-positive: a path at the start of a line\n' "$A_BS" > "$SANDBOX/b-bnd0.tsv"
printf 'scripts/bnde\tdocs/be.md\t%s\t1\tfalse-positive: the anchor hashes the ORIGINAL line, escape and all\n' "$A_BE" > "$SANDBOX/b-bnde.tsv"
row_bnd_mid() { saudit "$SANDBOX/s-bnd.rows" --accept "$SANDBOX/b-bnd.tsv"; [[ "$RC" -eq 0 ]] && grep -q 'gap_suites=0 gap_refs=0 accepted=1 stale=0' <<<"$AOUT"; }
row_bnd_start() { saudit "$SANDBOX/s-bnd0.rows" --accept "$SANDBOX/b-bnd0.tsv"; [[ "$RC" -eq 0 ]] && grep -q 'accepted=1 stale=0' <<<"$AOUT"; }
row_bnd_orig() { saudit "$SANDBOX/s-bnde.rows" --accept "$SANDBOX/b-bnde.tsv"; [[ "$RC" -eq 0 ]] && grep -q 'accepted=1 stale=0' <<<"$AOUT"; }
row_scan_vt() { saudit "$SANDBOX/s-vt.rows" --all-refs; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/vt\t2\tdocs/vt.md,docs/vt2.md' <<<"$AOUT" && grep -qxF -- $'ref\tscripts/vt\tdocs/vt2.md\tscripts/vt.test.sh:2\t'"$(anchor_of 'cat docs/vt2.md')"$'/1\tcat docs/vt2.md' <<<"$AOUT"; }
row_scan_vt && pass "lines are split on \\n only: a vertical tab inside a line (echo<VT># docs/vt.md) does not start a 'comment line', and the next line keeps its physical number (2)" || fail "vertical-tab fixture (rc=$RC): $AOUT"
row_scan_hop() { saudit "$SANDBOX/s-hop.rows" --all-refs; [[ "$RC" -eq 1 ]] && [[ "$(grep -c -P '^ref\tscripts/hop\tdata/one\.txt\t' <<<"$AOUT")" -eq 1 ]] && grep -qxF -- $'ref\tscripts/hop\tdata/one.txt\tlib1/helper.sh:1\t'"$(anchor_of 'cat data/one.txt')"$'/1\tcat data/one.txt' <<<"$AOUT"; }
row_scan_hop && pass "a library sourced as lib1/helper.sh and as ./lib1/helper.sh is one file (normalised path): its line is listed once, ordinal 1" || fail "normalised library path (rc=$RC): $AOUT"
row_scan_refs && pass "--all-refs prints one ref line per boundary line (suite, path, file:line, anchor/ordinal, text); a stripped comment line keeps its line number (the match is on line 4), and a library line names its own file" || fail "ref lines (rc=$RC): $AOUT"
row_bnd_mid && pass "accept rows follow the same boundary: a suite with a boundary line AND two mid-component lines (xdocs/, x_docs/, 7docs/) for one path is exempted by the boundary line's row alone" || fail "boundary twin, mid-component lines (rc=$RC): $AOUT"
row_bnd_start && pass "accept rows: a path at the very start of a line (offset 0) is a boundary line the row can describe" || fail "boundary twin, line start (rc=$RC): $AOUT"
row_bnd_orig && pass "the anchor hashes the ORIGINAL line (printf 'A\\x09docs/be.md\\n' with the escape as written), while the match uses the normalised copy" || fail "anchor over the original line (rc=$RC): $AOUT"

echo "== audit scan: the work is bounded by the text, not by the tracked-path count, the top-level width or (superlinearly) the text (three instruments: PathIndex.ops, line events, CPU time)"
# Three instruments, because each one alone has a blind spot. PathIndex.ops is self-reported. The LINE-EVENT count (sys.settrace, which
# every CPython 3.x has; sys.monitoring needs 3.12) counts the interpreter's own executed lines in every frame below scan_text, so
# call-less Python work (`for p in paths: p in text`, a loop over the top-level names or range(len(text)) per start) is seen even when ops
# is not incremented. CPU time (best of 3, bounded with 3x slack, never pinned) is the only one that sees a cost inside ONE C call, such
# as a regex alternation that grows with the number of top-level names.
row_scan_ops() {
  local out
  out="$(python3 - "$SUT" <<'PY' 2>&1
import importlib.util as u, sys, time
s = u.spec_from_file_location('m', sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
def tree(n):
    return {"d%d/s%d/f%d.txt" % (i % 200, i % 7, i) for i in range(n)}
def blob(size):
    lines, k, tot = [], 0, 0
    while tot < size:
        l = "echo step %d && cat d%d/s%d/f%d.txt >> /dev/null" % (k, (k * 7) % 200, (k * 7) % 7, k * 7)
        lines.append(l); tot += len(l) + 1; k += 1
    return "\n".join(lines), {"d%d/s%d/f%d.txt" % ((j * 7) % 200, (j * 7) % 7, j * 7) for j in range(k)}
def wide(width):
    # 40 mentioned top-level names, padded with unmentioned ones up to `width`; the TEXT is the same for every width
    lines = ["cat t%d/s/f%d.txt" % (i % 40, i) for i in range(400)]
    want = {"t%d/s/f%d.txt" % (i % 40, i) for i in range(400)}
    return "\n".join(lines), want, want | {"pad%d/x.txt" % i for i in range(width - 40)}
def traced(tracked, text):
    idx = m.PathIndex(tracked)
    ev, cap = [0], 40 * len(text) + 20000
    def local(frame, event, arg):
        if event == "line":
            ev[0] += 1
            if ev[0] > cap:
                raise OverflowError
        return local
    sys.settrace(lambda f, e, a: local)
    try:
        got = m.scan_text(idx, text)
    except OverflowError:
        got = None
    finally:
        sys.settrace(None)
    return got, idx.ops, ev[0]
def cpu(tracked, text, reps=10, give_up=None):
    idx = m.PathIndex(tracked)
    best = None
    for _ in range(3):
        t0 = time.process_time()
        for _ in range(reps):
            m.scan_text(idx, text)
        d = (time.process_time() - t0) / reps
        best = d if best is None else min(best, d)
        if give_up is not None and best > give_up:   # already far past any bound: do not spend two more runs on it
            break
    return best
def lengths(n):                                          # one directory holding file names of n distinct lengths
    return {"d/" + "a" * i for i in range(1, n + 1)}
bad = []
T = tree(20000)
per_byte = []
for size in (5000, 10000, 20000):                      # the text-length axis: events per byte may not grow with the text
    b, want = blob(size)
    got, ops, ev = traced(T, b)
    if got != (want & T):
        bad.append("wrong refs at %d bytes" % len(b))
    if not (ops > len(b) / 20 and ev > len(b) / 10):           # a FLOOR: 180 paths in 10 KB cannot be found with less
        bad.append("floor: ops=%d events=%d for %d bytes" % (ops, ev, len(b)))
    if not (ops <= len(b) / 2 and ev <= 8 * len(b)):           # the bound
        bad.append("bound: ops=%d events=%d for %d bytes" % (ops, ev, len(b)))
    per_byte.append((ops / len(b), ev / len(b)))
if per_byte[2][0] > 1.5 * per_byte[0][0] or per_byte[2][1] > 1.5 * per_byte[0][1]:
    bad.append("per-byte cost grows with the text: %s" % per_byte)
b, want = blob(10000)
g20, o20, e20 = traced(T, b); g2, o2, e2 = traced(tree(2000), b)
if g2 is None or o20 > 2 * o2 or e20 > 2 * e2:
    bad.append("paths axis (20k vs 2k): ops %d/%d events %d/%d" % (o20, o2, e20, e2))
wb, wwant, w40 = wide(40); _, _, w4k = wide(4000)
g40, o40, e40 = traced(w40, wb); g4k, o4k, e4k = traced(w4k, wb)
if g40 != wwant or g4k != wwant or o4k > 2 * o40 or e4k > 2 * e40 or e40 > 12 * len(wb):
    bad.append("width axis (4000 vs 40 names): ops %d/%d events %d/%d" % (o4k, o40, e4k, e40))
if bad:                                                  # the CPU phase is not run on an implementation the counters already condemned (it could take minutes)
    print("; ".join(bad)); sys.exit(0)
hb = "d/a " * 10000                                      # hostile for a per-length loop: every start sits in a directory with 250 name lengths
l250, l2 = lengths(250), lengths(2)
g250, o250, e250 = traced(l250, hb); g2l, o2l, e2l = traced(l2, hb)
if g250 is None or o250 > 2 * o2l or e250 > 2 * e2l:
    bad.append("name-length axis (250 vs 2 distinct lengths): ops %d/%d events %d/%d" % (o250, o2l, e250, e2l))
if bad:
    print("; ".join(bad)); sys.exit(0)
FLOOR = 0.001                                            # CPU time: best of 3, 3x slack, and a 1 ms floor under the baseline
bs, _ = blob(1000)                                       # 100k paths: an O(paths) C call per scan (a join, a find) shows against a 1 KB scan
PFLOOR = 0.0003
t2 = cpu(tree(2000), bs, reps=200)
t100k = cpu(tree(100000), bs, reps=200, give_up=30 * max(t2, PFLOOR))
tw40, tw4k = cpu(w40, wb), cpu(w4k, wb)
tl2, tl250 = cpu(l2, hb), cpu(l250, hb)
if t100k > 3 * max(t2, PFLOOR) or tw4k > 3 * max(tw40, FLOOR) or tl250 > 3 * max(tl2, FLOOR):
    bad.append("cpu: 100k/2k paths %.4f/%.4f s, 4000/40 names %.4f/%.4f s, 250/2 name lengths %.4f/%.4f s" % (t100k, t2, tw4k, tw40, tl250, tl2))
b64, _ = blob(65536); b1m, _ = blob(1048576)             # the TEXT axis in CPU time: per byte, 1 MB may cost at most 3x what 64 KB costs
c64 = cpu(T, b64, reps=6)
c1m = cpu(T, b1m, reps=1, give_up=3 * c64 * (len(b1m) / len(b64)))
if c1m / len(b1m) > 3 * max(c64, FLOOR) / len(b64):
    bad.append("cpu text axis: 64 KB %.4f s, 1 MB %.4f s (%.1fx per byte)" % (c64, c1m, (c1m / len(b1m)) / (c64 / len(b64))))
print("RATIOS paths=%.2f width=%.2f lengths=%.2f text=%.2f" % (t100k / max(t2, PFLOOR), tw4k / max(tw40, FLOOR), tl250 / max(tl2, FLOOR), (c1m / len(b1m)) / (max(c64, FLOOR) / len(b64))), file=sys.stderr)
print("; ".join(bad) or "ok")
PY
)" || { echo "$out" >&2; return 1; }
  [[ -z "${ROW_OPS_VERBOSE:-}" ]] || echo "$out" >&2
  out="${out##*$'\n'}"
  [[ "$out" = ok ]] || { echo "$out" >&2; return 1; }
}
row_scan_ops && pass "scanning 5, 10 and 20 KB against 20,000 tracked paths costs a roughly constant number of operations and line events per byte; 10x the paths or 100x the top-level names (40 vs 4,000, same text) costs no more than twice by ops and by executed lines, and no more than 3x in best-of-3 CPU time" || fail "operation-count fixture: $(row_scan_ops 2>&1 | tail -1)"

echo "== audit scan: the committed differential receipt (old scan versus new scan on the pinned tree, per occurrence) and its regenerator"
SPECS="$SCRIPT_DIR/../../../knowledge-base/project/specs"
RECEIPTS="$(find "$SPECS" -path '*/receipts/audit-differential.tsv' 2>/dev/null | sort)"   # every copy (the spec dir may later move under specs/archive/): all are judged
REGEN="$(find "$SPECS" -path '*/receipts/audit-differential.py' 2>/dev/null | sort | head -1)"
receipt_check() {  # receipt_check <file> [min_old]: judged on the STORED line text (a pinned git tree may be absent in a shallow clone, and a skip would pass vacuously)
  python3 - "$SUT" "$1" "${2:-100}" <<'PY'
import importlib.util as u, re, sys
s = u.spec_from_file_location('m', sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)   # the SUT's own m.views and m.boundary
COLOUR = re.compile(r"(?:\\0[0-7]{1,3}|\\e|\\x1[bB]|\x1b)\[[0-9;]*m$")
want = {"dropped": 0, "declared-drop": 0, "kept-escape": 0}
vanished, survives, hdr = set(), set(), {}
for n, line in enumerate(open(sys.argv[2], errors="replace"), 1):
    line = line.rstrip("\n")
    mm = re.match(r"^# old_refs=(\d+) new_refs=(\d+) dropped=(\d+) dropped_occurrences=(\d+) declared_drop=(\d+) kept_escape=(\d+)$", line)
    if mm:
        hdr = dict(zip(("old", "new", "dropped", "dropped_occurrences", "declared_drop", "kept_escape"), map(int, mm.groups())))
    if not line or line.startswith("#") or line.startswith("verdict\t"):
        continue
    f = line.split("\t")
    if len(f) != 7 or f[0] not in want or f[3] not in ("vanished", "survives") or not re.match(r"^\d+:\d+$", f[5]):
        print("%d: want verdict(dropped|declared-drop|kept-escape),suite,path,pair(vanished|survives),source,line:col,line_text" % n); sys.exit(1)
    verdict, suite, path, pair, src, loc, text = f
    path = re.sub(r"\\x([0-9a-f]{2})|\\u([0-9a-f]{4})", lambda g: chr(int(g.group(1) or g.group(2), 16)), path)   # the column is written through quote_field
    col = int(loc.split(":")[1])
    shown = "".join(" " if ord(c) < 0x20 or c == "\x7f" or m.QUOTE_U.match(c) else c for c in path)   # the stored line text has such characters flattened to a space
    if not text.startswith(shown, col):
        print("%d: the stored line does not hold the path at column %d" % (n, col)); sys.exit(1)
    full, light = m.views(text)
    at_boundary = m.boundary(full, col) or m.boundary(light, col)
    if verdict == "kept-escape":
        if not (col > 0 and re.match(r"[A-Za-z0-9_]", text[col - 1]) and at_boundary):
            print("%d: a kept-escape row whose occurrence is not made a boundary by an escape or an attached option" % n); sys.exit(1)
    else:
        if at_boundary:
            print("%d: %s starts at a component boundary in the stored line, so it is a read, not a dropped mention" % (n, path)); sys.exit(1)
        coloured = COLOUR.search(text[:col]) is not None
        if (verdict == "declared-drop") != coloured:
            print("%d: a %s row %s an ANSI colour code in front of the path" % (n, verdict, "without" if verdict == "declared-drop" else "with")); sys.exit(1)
    (vanished if pair == "vanished" else survives).add((suite, path))
    want[verdict] += 1
if not hdr:
    print("no `# old_refs=N new_refs=M dropped=D dropped_occurrences=O declared_drop=X kept_escape=K` header"); sys.exit(1)
if vanished & survives:
    print("a pair is marked both vanished and surviving: %s" % sorted(vanished & survives)[:2]); sys.exit(1)
if (len(vanished) != hdr["dropped"] or want["dropped"] != hdr["dropped_occurrences"] or want["declared-drop"] != hdr["declared_drop"]
        or want["kept-escape"] != hdr["kept_escape"] or hdr["old"] - hdr["new"] != hdr["dropped"] or hdr["old"] < int(sys.argv[3])):
    print("the header %s disagrees with the rows (vanished pairs %d, %s)" % (hdr, len(vanished), want)); sys.exit(1)
print("old_refs=%d new_refs=%d dropped=%d dropped_occurrences=%d declared_drop=%d kept_escape=%d" % tuple(hdr[k] for k in ("old", "new", "dropped", "dropped_occurrences", "declared_drop", "kept_escape")))
PY
}
rhdr() { printf '# old_refs=300 new_refs=299 dropped=1 dropped_occurrences=1 declared_drop=1 kept_escape=1\nverdict\tsuite\tpath\tpair\tsource\tloc\tline_text\n'; }
R_MID=$'dropped\tscripts/x\tlib/mid.txt\tvanished\tscripts/x.test.sh\t3:5\tcat xlib/mid.txt'
R_ESC=$'kept-escape\tscripts/y\tlib/esc.txt\tsurvives\tscripts/y.test.sh\t4:14\tprintf %s "A\\tlib/esc.txt"'
R_ANSI=$'declared-drop\tscripts/z\tlib/ansi.txt\tsurvives\tscripts/z.test.sh\t5:15\tprintf \'\\033[0mlib/ansi.txt\''
{ rhdr; printf '%s\n%s\n%s\n' "$R_MID" "$R_ESC" "$R_ANSI"; } > "$SANDBOX/receipt-good.tsv"
{ rhdr; printf '%s\n%s\n%s\n' $'dropped\tscripts/x\ttests/foo.txt\tvanished\tscripts/x.test.sh\t6:5\tcat \\tests/foo.txt' "$R_ESC" "$R_ANSI"; } > "$SANDBOX/receipt-light.tsv"
{ rhdr; printf '%s\n%s\n%s\n' $'dropped\tscripts/x\tlib/mid.txt\tvanished\tscripts/x.test.sh\t3:4\tcat lib/mid.txt' "$R_ESC" "$R_ANSI"; } > "$SANDBOX/receipt-bad.tsv"
{ rhdr; printf '%s\n%s\n%s\n' $'dropped\tscripts/x\tlib/mid.txt\tvanished\tscripts/x.test.sh\t3:14\tprintf %s "A\\tlib/mid.txt"' "$R_ESC" "$R_ANSI"; } > "$SANDBOX/receipt-esc.tsv"
{ rhdr; printf '%s\n%s\n' "$R_MID" "$R_ESC"; } > "$SANDBOX/receipt-short.tsv"
{ rhdr; printf '%s\n%s\n%s\n' "$R_MID" "$R_ESC" "${R_ANSI/declared-drop/dropped}"; } > "$SANDBOX/receipt-colour.tsv"
{ rhdr; printf '%s\n%s\n%s\n' "$R_MID" $'kept-escape\tscripts/y\tlib/esc.txt\tsurvives\tscripts/y.test.sh\t4:4\tcat lib/esc.txt' "$R_ANSI"; } > "$SANDBOX/receipt-keptbad.tsv"
{ rhdr; printf '%s\n%s\n%s\n' "$R_MID" "$R_ESC" $'declared-drop\tscripts/z\tlib/ansi.txt\tsurvives\tscripts/z.test.sh\t5:5\tcat xlib/ansi.txt'; } > "$SANDBOX/receipt-nocolour.tsv"
rc=0; receipt_check "$SANDBOX/receipt-good.tsv" 100 >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] && pass "receipt checker control: a mid-component row, a kept-escape row and an ANSI declared-drop row pass" || fail "receipt checker control: good rows (rc=$rc)"
for bad in bad esc short colour keptbad nocolour light; do
  rc=0; receipt_check "$SANDBOX/receipt-$bad.tsv" 100 >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 1 ]] && pass "receipt checker control ($bad): a row or header that contradicts the stored line is refused" || fail "receipt checker control ($bad) accepted (rc=$rc)"
done
nrec=0; recfail=""
for r in $RECEIPTS; do nrec=$((nrec + 1)); rc=0; rout="$(receipt_check "$r" 2>&1)" || rc=$?; [[ "$rc" -eq 0 ]] || recfail+=" $r:$rout"; done
[[ "$nrec" -ge 1 && -z "$recfail" ]] && pass "every committed differential receipt ($nrec found) lists each dropped occurrence with its source line (each starts mid-component), each ANSI declared drop and each printf-escape mention the rule keeps ($rout)" || fail "committed differential receipt (found $nrec):$recfail"
# the regenerator: run on the scan repo it must reproduce a receipt the checker accepts, with one row of each verdict
{ srow mid; srow midok; srow escx; srow ansi; srow bnd; srow escn; srow qq; } > "$SANDBOX/regen.rows"
row_regen() {
  [[ -n "$REGEN" && -f "$REGEN" ]] || return 1
  python3 "$REGEN" "$SREPO" "$SANDBOX/regen.rows" --sut "$SUT" --out "$SANDBOX/regen.tsv" >/dev/null 2>&1 || return 1
  receipt_check "$SANDBOX/regen.tsv" 1 >/dev/null 2>&1 &&
    grep -P -q '^declared-drop\tscripts/ansi\tbx/ansi\.md\tvanished\t' "$SANDBOX/regen.tsv" &&
    grep -P -q '^dropped\tscripts/mid\tlib/mid\.txt\tvanished\t' "$SANDBOX/regen.tsv" &&
    grep -P -q '^dropped\tscripts/bnd\tdocs/bm\.md\tsurvives\t' "$SANDBOX/regen.tsv" &&
    grep -P -q '^kept-escape\tscripts/escx\tbx/x09\.txt\tsurvives\t' "$SANDBOX/regen.tsv" &&
    grep -P -q '^dropped\tscripts/escn\tlib/e\\x1bsc\.txt\tvanished\t' "$SANDBOX/regen.tsv" &&
    ! LC_ALL=C grep -q -P '[\x00-\x08\x0b-\x1f\x7f]' "$SANDBOX/regen.tsv" &&
    grep -q '^# tree ' "$SANDBOX/regen.tsv"
}
row_regen && pass "the committed regenerator (receipts/audit-differential.py) reproduces a checker-valid receipt on the scan repo: a vanished mid-component pair, a surviving pair with a dropped occurrence, an ANSI declared drop and a kept escape each get their row" || fail "receipt regenerator (path='${REGEN:-none}')"

row_regen_planted() {   # a SUT that loses a pair WITHOUT a dropped occurrence (scan and boundary disagree): the regenerator must say so
  local m="$SANDBOX/mut-regen.py" rc=0 out
  cp "$REAL_SUT" "$m" && python3 - "$m" <<'PY' || return 1
import sys
p = sys.argv[1]; s = open(p).read()
old = "r = index.refs[got[0]] = scan_views(index, got[1], got[2])"
assert s.count(old) == 1
open(p, "w").write(s.replace(old, "r = index.refs[got[0]] = scan_views(index, got[1][:-1], got[2][:-1])"))
PY
  python3 "$REGEN" "$SREPO" "$SANDBOX/s-eol.rows" --sut "$REAL_SUT" --out "$SANDBOX/regen-ctl.tsv" >/dev/null 2>&1 || return 1   # control: the real SUT is fine
  out="$(python3 "$REGEN" "$SREPO" "$SANDBOX/s-eol.rows" --sut "$m" --out "$SANDBOX/regen-bad.tsv" 2>&1)" || rc=$?
  [[ "$rc" -eq 1 ]] && grep -q 'VANISHED PAIR WITHOUT A ROW' <<<"$out"
}
row_regen_planted && pass "the regenerator FAILS (exit 1, VANISHED PAIR WITHOUT A ROW) when a pair leaves the new refs with no dropped occurrence, and passes on the real SUT (the check is computed from old minus new, not from the rows it looks for)" || fail "regenerator planted vanish"

regen_with() {  # regen_with <regenerator> <sut> <rows>: sets RGRC and RGOUT
  RGRC=0; RGOUT="$(python3 "$1" "$SREPO" "$3" --sut "$2" --out "$SANDBOX/regen-x.tsv" 2>&1)" || RGRC=$?
}
edit_copy() {  # edit_copy <src> <dst> <old> <new>: one edit that must land exactly once
  cp "$1" "$2" && python3 - "$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
assert s.count(old) == 1, "count=%d" % s.count(old)
open(p, "w").write(s.replace(old, new))
PY
}
row_regen_subset() {   # the check that the new refs are a subset of the old refs is what fails a SUT that names more than the brute-force scan
  edit_copy "$REAL_SUT" "$SANDBOX/sut-extra.py" '        named |= refs_of(index, got)' '        named |= refs_of(index, got) | {"m.txt"}' || return 1
  regen_with "$REGEN" "$REAL_SUT" "$SANDBOX/s-eol.rows"; [[ "$RGRC" -eq 0 ]] || return 1                                       # control: the real SUT is fine
  regen_with "$REGEN" "$SANDBOX/sut-extra.py" "$SANDBOX/s-eol.rows"; [[ "$RGRC" -eq 1 ]] && grep -q 'NEW SCAN FOUND WHAT THE OLD ONE DID NOT' <<<"$RGOUT" || return 1
  edit_copy "$REGEN" "$SANDBOX/regen-nosubset.py" '[q(x) for x in sorted(extra)[:5]]))
            bad += 1' '[q(x) for x in sorted(extra)[:5]]))' || return 1
  regen_with "$SANDBOX/regen-nosubset.py" "$SANDBOX/sut-extra.py" "$SANDBOX/s-eol.rows"; [[ "$RGRC" -eq 0 ]]                    # the mutant regenerator misses it
}
row_regen_oldview() {  # the old side is built from the text AS WRITTEN: from the full view it would lose \tests/ and report the new scan's find as an error
  srow escadj > "$SANDBOX/s-escadj-regen.rows"
  regen_with "$REGEN" "$REAL_SUT" "$SANDBOX/s-escadj-regen.rows"; [[ "$RGRC" -eq 0 ]] || return 1
  edit_copy "$REGEN" "$SANDBOX/regen-fullold.py" 'blob = "\n".join(tr for _, _, _, tr in texts)' 'blob = "\n".join(tn for _, tn, _, _ in texts)' || return 1
  regen_with "$SANDBOX/regen-fullold.py" "$REAL_SUT" "$SANDBOX/s-escadj-regen.rows"; [[ "$RGRC" -eq 1 ]]
}
row_regen_subset && pass "regenerator: a SUT that names a path the brute-force old scan cannot is refused (NEW SCAN FOUND WHAT THE OLD ONE DID NOT, exit 1); the regenerator with that check removed accepts it" || fail "regenerator subset check"
row_regen_oldview && pass "regenerator: the old side is built from the text as written (the real SUT passes on \\tests/); built from the full view it reports a false error" || fail "regenerator old side"

echo "== audit: directory suites are audited through their bun-discoverable test files"
printf 'AFFECTED_SELECTED\tdsuite\t0\tedge:declared\t^dsuite/\n' > "$SANDBOX/s-dir.rows"
printf 'AFFECTED_SELECTED\tdsuite/sub\t0\tedge:declared\t^dsuite/sub/\n' > "$SANDBOX/s-dirsub.rows"
row_dir_scan() { saudit "$SANDBOX/s-dir.rows" --all-refs; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tdsuite\t9\tdata/cjs.txt,data/cts.txt,data/jsx.txt,data/mjs.txt,data/mts.txt,data/nested.txt,data/spec.txt,data/under.txt,docs/guide.md' <<<"$AOUT" && grep -q 'audited=1 unaudited=0' <<<"$AOUT"; }
row_dir_nested() { saudit "$SANDBOX/s-dirsub.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tdsuite/sub\t1\tdata/nested.txt' <<<"$AOUT" && grep -q 'audited=1 unaudited=0' <<<"$AOUT"; }
row_dir_scan && pass "a directory suite unions the refs of its *.test.{ts,tsx,jsx,mjs,mts,cts}, *.spec.{js,cjs} and *_test.ts files; a .test.sh, a .test.ts.snap, latest.ts, a notes file and a path inside the directory are not gaps" || fail "directory-suite scan (rc=$RC): $AOUT"
row_dir_nested && pass "a nested directory prefix (^dsuite/sub/) scans only the test files under it" || fail "nested directory suite (rc=$RC): $AOUT"
RC=0; AOUT="$(run_sut audit --root "$AREPO" --list "$SANDBOX/audit-dir.rows" 2>&1)" || RC=$?
[[ "$RC" -eq 1 ]] && grep -q 'audited=0 unaudited=1' <<<"$AOUT" && pass "control: a directory with no bun-discoverable test file (adir holds only data.txt) stays unaudited" || fail "directory without tests (rc=$RC): $AOUT"
# An unreadable tracked member of a directory suite: the suite is `unaudited ... unreadable:<relpath>`, its readable members are still scanned,
# the audit exits 1 (not the rc 3 of a git or selector failure), and a `*` row cannot accept it.
printf 'AFFECTED_SELECTED\tdlink\t0\tedge:declared\t^dlink/\n' > "$SANDBOX/s-dlink.rows"
printf 'dlink\t*\t-\t-\tfalse-positive: would hide every test file in the directory\n' > "$SANDBOX/s-dlink-star.tsv"
row_dir_dangling() { saudit "$SANDBOX/s-dlink.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'unaudited\tdlink\tunreadable:dlink/dang.test.ts' <<<"$AOUT" && grep -qxF -- $'gap\tdlink\t1\tdata/dl.txt' <<<"$AOUT" && grep -q 'audited=0 unaudited=1 gap_suites=1 gap_refs=1' <<<"$AOUT"; }
row_dir_dangling_star() { saudit "$SANDBOX/s-dlink.rows" --accept "$SANDBOX/s-dlink-star.tsv"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'unaudited\tdlink\tunreadable:dlink/dang.test.ts' <<<"$AOUT" && grep -P -q '^stale\tdlink\t\*\t-/-\tstar-row-unreadable-members$' <<<"$AOUT" && grep -q 'accepted=0 stale=1' <<<"$AOUT"; }
row_dir_dangling && pass "a dangling tracked symlink among a directory suite's test files makes the suite unaudited (unreadable:<relpath>), exit 1, while the readable test is still scanned" || fail "dangling tracked member (rc=$RC): $AOUT"
row_dir_dangling_star && pass "a '*' accept row cannot accept an unreadable member: the suite stays unaudited and the row is STALE" || fail "star row over an unreadable member (rc=$RC): $AOUT"

echo "== audit: accept rows are keyed on the line they describe"
A_ACC1="$(anchor_of 'cat docs/acc1.md')"; A_ACC2="$(anchor_of 'echo data/acc2.txt')"; A_DUP="$(anchor_of 'cat data/dup.txt')"
A_MX1="$(anchor_of 'cat docs/mixed.md')"; A_MX2="$(anchor_of 'echo "see docs/mixed.md"')"; A_WS="$(anchor_of 'cat docs/ws.md')"; A_CMT="$(anchor_of 'cat docs/cmt.md')"
FPR='false-positive: a message string, not a read'
arow() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "${5:-$FPR}"; }   # arow <suite> <path> <anchor> <ordinal> [reason]
srow acc > "$SANDBOX/a-acc.rows"; srow dup > "$SANDBOX/a-dup.rows"; srow mixed > "$SANDBOX/a-mixed.rows"; srow ws > "$SANDBOX/a-ws.rows"; srow cmt > "$SANDBOX/a-cmt.rows"
{ srow acc; printf 'AFFECTED_SELECTED\tscripts/alw\t1\talways_on\t^scripts/alw.test.sh\n'; } > "$SANDBOX/a-alw.rows"
{ arow scripts/acc docs/acc1.md "$A_ACC1" 1; arow scripts/acc data/acc2.txt "$A_ACC2" 1; } > "$SANDBOX/a-ok.tsv"
row_acc_ok() { saudit "$SANDBOX/a-acc.rows" --accept "$SANDBOX/a-ok.tsv"; [[ "$RC" -eq 0 ]] && grep -q 'gap_suites=0 gap_refs=0 accepted=2 stale=0' <<<"$AOUT"; }
row_acc_ok && pass "pristine control: two anchor-keyed rows that match live lines exempt exactly their two pairs (accepted=2 stale=0)" || fail "anchor-keyed accept (rc=$RC): $AOUT"
{ arow scripts/acc docs/acc1.md 000000000000 1; arow scripts/acc data/acc2.txt "$A_ACC2" 1; } > "$SANDBOX/a-anchor.tsv"
row_acc_anchor() { saudit "$SANDBOX/a-acc.rows" --accept "$SANDBOX/a-anchor.tsv"; [[ "$RC" -eq 1 ]] && grep -P -q '^stale\tscripts/acc\tdocs/acc1.md\t000000000000/1\tanchor-not-live$' <<<"$AOUT" && grep -qxF -- $'gap\tscripts/acc\t1\tdocs/acc1.md' <<<"$AOUT" && grep -q 'accepted=1 stale=1' <<<"$AOUT"; }
row_acc_anchor && pass "a row whose anchor matches no live line is STALE: reported, exit 1, and it exempts nothing" || fail "anchor mismatch (rc=$RC): $AOUT"
{ arow scripts/acc docs/acc1.md "$A_ACC1" 1; arow scripts/acc data/acc2.txt "$A_ACC2" 1; arow scripts/acc docs/nowhere.md "$A_ACC1" 1; } > "$SANDBOX/a-untracked.tsv"
row_acc_untracked() { saudit "$SANDBOX/a-acc.rows" --accept "$SANDBOX/a-untracked.tsv"; [[ "$RC" -eq 1 ]] && grep -P -q '^stale\tscripts/acc\tdocs/nowhere.md\t[0-9a-f]{12}/1\tpath-untracked$' <<<"$AOUT" && grep -q 'gap_suites=0 gap_refs=0 accepted=2 stale=1' <<<"$AOUT"; }
row_acc_untracked && pass "a row naming an untracked path is STALE (the live rows still exempt their pairs)" || fail "untracked path (rc=$RC): $AOUT"
{ arow scripts/acc docs/acc1.md "$A_ACC1" 1; arow scripts/acc data/acc2.txt "$A_ACC2" 1; arow scripts/phantom docs/acc1.md "$A_ACC1" 1; } > "$SANDBOX/a-phantom.tsv"
row_acc_phantom() { saudit "$SANDBOX/a-acc.rows" --accept "$SANDBOX/a-phantom.tsv"; [[ "$RC" -eq 1 ]] && grep -P -q '^stale\tscripts/phantom\tdocs/acc1.md\t[0-9a-f]{12}/1\tsuite-unregistered$' <<<"$AOUT"; }
row_acc_phantom && pass "a row for a suite the selector does not register is STALE" || fail "unregistered suite (rc=$RC): $AOUT"
{ arow scripts/acc docs/acc1.md "$A_ACC1" 1; arow scripts/acc docs/acc1.md "$A_ACC1" 2; arow scripts/acc data/acc2.txt "$A_ACC2" 1; } > "$SANDBOX/a-ord2.tsv"
row_acc_ord2() { saudit "$SANDBOX/a-acc.rows" --accept "$SANDBOX/a-ord2.tsv"; [[ "$RC" -eq 1 ]] && grep -P -q "^stale\tscripts/acc\tdocs/acc1.md\t$A_ACC1/2\tanchor-not-live\$" <<<"$AOUT"; }
row_acc_ord2 && pass "ordinal 2 for a line that occurs once is STALE (the ordinal names the Nth identical line)" || fail "ordinal beyond the last identical line (rc=$RC): $AOUT"
{ arow scripts/dup data/dup.txt "$A_DUP" 1; } > "$SANDBOX/a-dup1.tsv"; { arow scripts/dup data/dup.txt "$A_DUP" 1; arow scripts/dup data/dup.txt "$A_DUP" 2; } > "$SANDBOX/a-dup2.tsv"
row_acc_dup1() { saudit "$SANDBOX/a-dup.rows" --accept "$SANDBOX/a-dup1.tsv"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/dup\t1\tdata/dup.txt' <<<"$AOUT"; }
row_acc_dup2() { saudit "$SANDBOX/a-dup.rows" --accept "$SANDBOX/a-dup2.tsv"; [[ "$RC" -eq 0 ]] && grep -q 'accepted=1 stale=0' <<<"$AOUT"; }
row_acc_dup1 && pass "two identical reading lines with only ordinal 1 accepted: the pair stays a gap (every boundary-match line must be accepted)" || fail "partial ordinals (rc=$RC): $AOUT"
row_acc_dup2 && pass "control: ordinals 1 and 2 together accept both identical lines (one pair, accepted=1)" || fail "both ordinals (rc=$RC): $AOUT"
{ arow scripts/mixed docs/mixed.md "$A_MX1" 1; } > "$SANDBOX/a-mx1.tsv"; { arow scripts/mixed docs/mixed.md "$A_MX1" 1; arow scripts/mixed docs/mixed.md "$A_MX2" 1; } > "$SANDBOX/a-mx2.tsv"
row_acc_mixed1() { saudit "$SANDBOX/a-mixed.rows" --accept "$SANDBOX/a-mx1.tsv"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/mixed\t1\tdocs/mixed.md' <<<"$AOUT"; }
row_acc_mixed2() { saudit "$SANDBOX/a-mixed.rows" --accept "$SANDBOX/a-mx2.tsv"; [[ "$RC" -eq 0 ]] && grep -q 'accepted=1 stale=0' <<<"$AOUT"; }
row_acc_mixed1 && pass "a second DIFFERENT line naming the same path is a new gap until it is accepted too" || fail "second reading line (rc=$RC): $AOUT"
row_acc_mixed2 && pass "control: both different lines accepted exempt the pair" || fail "both lines accepted (rc=$RC): $AOUT"
{ arow scripts/ws docs/ws.md "$A_WS" 1; } > "$SANDBOX/a-ws.tsv"
row_acc_ws() { saudit "$SANDBOX/a-ws.rows" --accept "$SANDBOX/a-ws.tsv"; [[ "$RC" -eq 0 ]] && grep -q 'accepted=1 stale=0' <<<"$AOUT"; }
row_acc_ws && pass "the anchor ignores indentation, runs of spaces and CRLF (a tab-indented, CRLF line matches the anchor of its collapsed text)" || fail "whitespace-normalised anchor (rc=$RC): $AOUT"
{ arow scripts/cmt docs/cmt.md "$A_CMT" 1; } > "$SANDBOX/a-cmt.tsv"
row_acc_cmt() { saudit "$SANDBOX/a-cmt.rows" --accept "$SANDBOX/a-cmt.tsv"; [[ "$RC" -eq 1 ]] && grep -P -q "^stale\tscripts/cmt\tdocs/cmt.md\t$A_CMT/1\tnot-a-gap\$" <<<"$AOUT"; }
row_acc_cmt && pass "commenting out an accepted line makes its row STALE (the path is no longer named by the comment-stripped text, so the pair is not a gap)" || fail "commented-out accepted line (rc=$RC): $AOUT"
row_acc_missing() { saudit "$SANDBOX/a-acc.rows" --accept "$SANDBOX/no-such-accept.tsv"; [[ "$RC" -eq 1 ]] && grep -q 'gap_suites=1 gap_refs=2 accepted=0 stale=0' <<<"$AOUT" && grep -q 'no-such-accept.tsv does not exist: no exemptions' <<<"$AOUT"; }
row_acc_missing && pass "a missing accept file means no exemptions (not an error): both pairs stay gaps, exit 1, and one stderr line says the file does not exist" || fail "missing accept file (rc=$RC): $AOUT"
{ arow scripts/acc '*' - -; } > "$SANDBOX/a-star.tsv"
row_acc_star() { saudit "$SANDBOX/a-acc.rows" --accept "$SANDBOX/a-star.tsv"; [[ "$RC" -eq 1 ]] && grep -P -q '^stale\tscripts/acc\t\*\t-/-\tstar-row-readable-suite$' <<<"$AOUT" && grep -q 'gap_suites=1' <<<"$AOUT"; }
row_acc_star && pass "a '*' row naming a READABLE suite is rejected and exempts nothing (control: the '*' row for the unreadable directory suite above is still accepted)" || fail "star row for a readable suite (rc=$RC): $AOUT"
{ arow scripts/alw docs/acc1.md "$A_ACC1" 1; arow scripts/acc docs/acc1.md "$A_ACC1" 1; arow scripts/acc data/acc2.txt "$A_ACC2" 1; } > "$SANDBOX/a-alw.tsv"
row_acc_alw() { saudit "$SANDBOX/a-alw.rows" --accept "$SANDBOX/a-alw.tsv"; [[ "$RC" -eq 1 ]] && grep -P -q '^stale\tscripts/alw\tdocs/acc1.md\t[0-9a-f]{12}/1\tsuite-always-on$' <<<"$AOUT"; }
row_acc_alw && pass "a row for an always_on suite is STALE (its reads are not audited, so nothing can be accepted)" || fail "always_on suite row (rc=$RC): $AOUT"
printf '%s\t%s\t%s\t%s\n' scripts/acc docs/acc1.md "$A_ACC1" 1 > "$SANDBOX/a-four.tsv"
printf '%s\t%s\tnot-hex\t1\t%s\n' scripts/acc docs/acc1.md "$FPR" > "$SANDBOX/a-nothex.tsv"
printf '%s\t%s\t%s\t0\t%s\n' scripts/acc docs/acc1.md "$A_ACC1" "$FPR" > "$SANDBOX/a-ord0.tsv"
printf '%s\t%s\t%s\tx\t%s\n' scripts/acc docs/acc1.md "$A_ACC1" "$FPR" > "$SANDBOX/a-ordx.tsv"
printf '%s\t%s\t%s\t1\t%s\n%s\t%s\t%s\t1\t%s\n' scripts/acc docs/acc1.md "$A_ACC1" "$FPR" scripts/acc docs/acc1.md "$A_ACC1" "$FPR" > "$SANDBOX/a-dupe.tsv"
printf '%s\t*\t%s\t1\t%s\n' scripts/acc "$A_ACC1" "$FPR" > "$SANDBOX/a-starkey.tsv"
row_acc_bad() { saudit "$SANDBOX/a-acc.rows" --accept "$SANDBOX/a-$1.tsv"; [[ "$RC" -eq 2 ]] && grep -qF -- "$2" <<<"$AOUT"; }   # row_acc_bad <name> <needle>: refused as a value error whose message names the failing field
printf '%s\t%s\t%s\t1\tfalse-positive:\n' scripts/acc docs/acc1.md "$A_ACC1" > "$SANDBOX/a-emptyreason.tsv"
printf '%s\t%s\t%s\t1\tfalse-positive: \n' scripts/acc docs/acc1.md "$A_ACC1" > "$SANDBOX/a-trailing.tsv"
printf '%s\t%s\tfalse-positive: a message string\n' scripts/acc docs/acc1.md > "$SANDBOX/a-three.tsv"
printf '%s\t%s\t%s\t1\t%s\n%s\t%s\t%s\t1\tfalse-positive: a different reason, the same key\n' scripts/acc docs/acc1.md "$A_ACC1" "$FPR" scripts/acc docs/acc1.md "$A_ACC1" > "$SANDBOX/a-dupe2.tsv"
printf '%s\t%s\t%s\t1\t%s\textra\n' scripts/acc docs/acc1.md "$A_ACC1" "$FPR" > "$SANDBOX/a-six.tsv"
for spec in "six|6 column(s)" "four|4 column(s)" "nothex|col 3 (anchor)" "ord0|col 4 (ordinal)" "ordx|col 4 (ordinal)" "dupe|duplicate accept row" "dupe2|duplicate accept row" "starkey|a \`*\` row" \
            "emptyreason|col 5 (reason)" "trailing|col 5 (reason)" "three|3-column form" "three|retired"; do
  t="${spec%%|*}"; needle="${spec#*|}"
  row_acc_bad "$t" "$needle" && pass "a malformed accept row ($t) is a value error, rc 2, and the message says: $needle" || fail "malformed accept row $t (rc=$RC, wanted '$needle'): $AOUT"
done
{ printf '# an accept file with comments\n\n'; arow scripts/acc docs/acc1.md "$A_ACC1" 1; printf '   \n# between rows\n'; arow scripts/acc data/acc2.txt "$A_ACC2" 1; printf '# last line\n'; } > "$SANDBOX/a-comments.tsv"
row_acc_comments() { saudit "$SANDBOX/a-acc.rows" --accept "$SANDBOX/a-comments.tsv"; [[ "$RC" -eq 0 ]] && grep -q 'accepted=2 stale=0' <<<"$AOUT"; }
row_acc_comments && pass "comment and blank lines in the accept file are skipped (a '#' line is not a malformed row)" || fail "accept-file comment lines (rc=$RC): $AOUT"
srow acc '^docs/acc1.md' > "$SANDBOX/a-declared.rows"
row_acc_declared() { saudit "$SANDBOX/a-declared.rows" --accept "$SANDBOX/a-ok.tsv"; [[ "$RC" -eq 1 ]] && grep -P -q "^stale\tscripts/acc\tdocs/acc1.md\t$A_ACC1/1\tnot-a-gap\$" <<<"$AOUT" && grep -q 'gap_suites=0 gap_refs=0 accepted=1 stale=1' <<<"$AOUT"; }
row_acc_declared && pass "a row whose pair an edge now declares is STALE (not-a-gap): it would silently re-exempt the read if the edge were ever removed" || fail "accept row for a declared pair (rc=$RC): $AOUT"
printf 'AFFECTED_SELECTED\tscripts/nosuch\t0\tedge:derived\t^scripts/nosuch.test.sh\n' > "$SANDBOX/a-nosuch.rows"
arow scripts/nosuch docs/acc1.md "$A_ACC1" 1 > "$SANDBOX/a-nosuch.tsv"
row_acc_unaudited() { saudit "$SANDBOX/a-nosuch.rows" --accept "$SANDBOX/a-nosuch.tsv"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'unaudited\tscripts/nosuch\t^scripts/nosuch.test.sh' <<<"$AOUT" && grep -P -q "^stale\tscripts/nosuch\tdocs/acc1.md\t$A_ACC1/1\tsuite-unaudited\$" <<<"$AOUT"; }
row_acc_unaudited && pass "a path row for a suite the audit could not read is STALE (suite-unaudited): only a '*' row may accept an unread suite" || fail "accept row for an unaudited suite (rc=$RC): $AOUT"
{ arow scripts/acc docs/zzz.md 000000000000 1; arow scripts/acc docs/aaa.md 000000000000 1; arow scripts/acc docs/acc1.md "$A_ACC1" 1; arow scripts/acc data/acc2.txt "$A_ACC2" 1; } > "$SANDBOX/a-order.tsv"
row_acc_order() { saudit "$SANDBOX/a-acc.rows" --accept "$SANDBOX/a-order.tsv"; [[ "$RC" -eq 1 && "$(grep -c '^stale' <<<"$AOUT")" -eq 2 ]] && LC_ALL=C sort -c < <(grep '^stale' <<<"$AOUT") 2>/dev/null; }
row_acc_order && pass "stale lines are printed sorted (the accept file's row order does not decide the output)" || fail "stale line order (rc=$RC): $AOUT"
row_acc_isdir() { saudit "$SANDBOX/a-acc.rows" --accept "$SANDBOX"; [[ "$RC" -eq 3 ]]; }
row_acc_four() { row_acc_bad four '4 column(s)'; }; row_acc_nothex() { row_acc_bad nothex 'col 3 (anchor)'; }; row_acc_ord0() { row_acc_bad ord0 'col 4 (ordinal)'; }
row_acc_dupe() { row_acc_bad dupe 'duplicate accept row'; }; row_acc_starkey() { row_acc_bad starkey 'a `*` row'; }; row_acc_emptyreason() { row_acc_bad emptyreason 'col 5 (reason)'; }
row_acc_trailing() { row_acc_bad trailing 'col 5 (reason)'; }; row_acc_dupe2() { row_acc_bad dupe2 'duplicate accept row'; }; row_acc_three() { row_acc_bad three 'retired'; }; row_acc_six() { row_acc_bad six '6 column(s)'; }
row_acc_isdir && pass "an --accept path that is a directory is a failed READ (rc 3), not an internal error (rc 4)" || fail "accept path is a directory (rc=$RC): $AOUT"

echo "== audit round 2: duplicate labels, escape-adjacent heads, non-regular files, partial suites, quoting, CR, symlinks, ordinals across files and suites"
for k in mt escadj hopd hopl hopg cr idl tw1 tw2 qq; do srow "$k" > "$SANDBOX/s-$k.rows"; done
{ printf 'AFFECTED_SELECTED\tscripts/dup\t0\tedge:derived\t^scripts/dupa.test.sh\n'; printf 'AFFECTED_SELECTED\tscripts/dup\t0\tedge:derived\t^scripts/dupb.test.sh\n'; } > "$SANDBOX/s-dupab.rows"
{ printf 'AFFECTED_SELECTED\tscripts/dup2\t0\tedge:derived\t^scripts/dupa.test.sh\n'; printf 'AFFECTED_SELECTED\tscripts/dup2\t0\tedge:derived\t^scripts/dupn.test.sh\n'; } > "$SANDBOX/s-dupan.rows"
{ printf 'AFFECTED_SELECTED\tscripts/dup2\t0\tedge:derived\t^scripts/dupn.test.sh\n'; printf 'AFFECTED_SELECTED\tscripts/dup2\t0\tedge:derived\t^scripts/dupa.test.sh\n'; } > "$SANDBOX/s-dupna.rows"
arow scripts/dup data/da.txt "$(anchor_of 'cat data/da.txt')" 1 > "$SANDBOX/a-dup.tsv"
row_dup_labels() { saudit "$SANDBOX/s-dupab.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/dup\t2\tdata/da.txt,data/db.txt' <<<"$AOUT" && grep -q 'gap_suites=1 gap_refs=2' <<<"$AOUT"; }
row_dup_one_empty() {
  saudit "$SANDBOX/s-dupan.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/dup2\t1\tdata/da.txt' <<<"$AOUT" && grep -q 'gap_suites=1 gap_refs=1' <<<"$AOUT" || return 1
  saudit "$SANDBOX/s-dupna.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/dup2\t1\tdata/da.txt' <<<"$AOUT" && grep -q 'gap_suites=1 gap_refs=1' <<<"$AOUT"
}
row_dup_accept() { saudit "$SANDBOX/s-dupab.rows" --accept "$SANDBOX/a-dup.tsv"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/dup\t1\tdata/db.txt' <<<"$AOUT" && grep -q 'accepted=1 stale=0' <<<"$AOUT"; }
row_dup_labels && pass "two selector rows with ONE label are one suite: both rows' gaps are kept (gap_suites counts the label once, gap_refs both paths), not overwritten by the later row" || fail "duplicate labels, both with a gap (rc=$RC): $AOUT"
row_dup_one_empty && pass "duplicate labels where one row has a gap and the other none: the gap survives in either order" || fail "duplicate labels, one empty (rc=$RC): $AOUT"
row_dup_accept && pass "an accept row is judged once against the merged suite: it exempts the pair from the first row and is not stale for the second" || fail "duplicate labels with an accept row (rc=$RC): $AOUT"
row_mt() { saudit "$SANDBOX/s-mt.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/mt\t2\t(tl)/z.txt,a+b/y.txt' <<<"$AOUT"; }
row_mt && pass "top-level names holding regex metacharacters ((tl), a+b) start a match (the prefix-trie regex escapes every character; lib, lib1 and lib2 show a name that is a prefix of another)" || fail "metacharacter top-level names (rc=$RC): $AOUT"
row_adj() { saudit "$SANDBOX/s-escadj.rows" --all-refs; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/escadj\t7\tbin/x.txt,dat1/x.txt,dat2/x.txt,ecosystem/y.txt,pi/p.txt,pv/p.txt,tests/foo.txt' <<<"$AOUT" && ! grep -q 'dat3/x.txt' <<<"$AOUT"; }
row_adj && pass "escape-adjacent paths keep their head (\\tests/, \\bin/, \\ecosystem/ in the light view; \\x09, \\011 in the full view; \${V:-p}, -I p); \\033[0m<path> stays a declared drop in BOTH views" || fail "escape-adjacent fixture (rc=$RC): $AOUT"
ADJ_LINES=('cat \tests/foo.txt' 'cat \bin/x.txt' 'cat \ecosystem/y.txt' "printf '\\x09dat1/x.txt'" "printf '\\011dat2/x.txt'" 'echo ${V:-pv/p.txt}' 'gcc -I pi/p.txt')
ADJ_PATHS=(tests/foo.txt bin/x.txt ecosystem/y.txt dat1/x.txt dat2/x.txt pv/p.txt pi/p.txt)
for i in "${!ADJ_PATHS[@]}"; do arow scripts/escadj "${ADJ_PATHS[$i]}" "$(anchor_of "${ADJ_LINES[$i]}")" 1; done > "$SANDBOX/a-escadj.tsv"
row_adj_accept() { saudit "$SANDBOX/s-escadj.rows" --accept "$SANDBOX/a-escadj.tsv"; [[ "$RC" -eq 0 ]] && grep -q 'gap_refs=0 accepted=7 stale=0' <<<"$AOUT"; }
row_adj_accept && pass "scan and anchors agree on every escape shape: one accept row per line exempts all seven pairs (each line is a boundary line in the same view that found its path)" || fail "escape shapes, accept rows (rc=$RC): $AOUT"
row_hop() { saudit "$SANDBOX/s-$1.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'unaudited\tscripts/'"$1"$'\tunreadable:'"$2" <<<"$AOUT" && grep -q 'unaudited=1' <<<"$AOUT"; }
row_hopd() { row_hop hopd lib3/dangling.sh; }; row_hopl() { row_hop hopl lib3/dirlink.sh; }; row_hopg() { row_hop hopg lib3/gone.sh; }
row_hopd && pass "a sourced library that is a dangling tracked symlink makes the suite unaudited (unreadable:lib3/dangling.sh), like an unreadable member" || fail "dangling sourced library (rc=$RC): $AOUT"
row_hopl && pass "a sourced library that is a tracked symlink to a directory is unreadable:lib3/dirlink.sh" || fail "directory sourced library (rc=$RC): $AOUT"
row_hopg && pass "a sourced library that is tracked but deleted from the work tree is unreadable:lib3/gone.sh" || fail "deleted sourced library (rc=$RC): $AOUT"
printf 'AFFECTED_SELECTED\tscripts/shortx\t0\tedge:declared\n' > "$SANDBOX/s-shortx.rows"
arow scripts/shortx docs/acc1.md "$A_ACC1" 1 > "$SANDBOX/a-shortx.tsv"
{ arow dlink data/dl.txt "$(anchor_of 'readFileSync("data/dl.txt")')" 1; arow dlink data/dl.txt 000000000000 1; arow dlink data/nowhere.txt 000000000000 1; } > "$SANDBOX/a-partial.tsv"
row_partial() { saudit "$SANDBOX/s-dlink.rows" --accept "$SANDBOX/a-partial.tsv"; [[ "$RC" -eq 1 && "$(grep -c '^stale' <<<"$AOUT")" -eq 1 ]] && grep -P -q '^stale\tdlink\tdata/nowhere.txt\t000000000000/1\tpath-untracked$' <<<"$AOUT" && grep -q '^unaudited.dlink.unreadable:' <<<"$AOUT" && grep -q 'accepted=0 stale=1' <<<"$AOUT"; }
row_shortx() { saudit "$SANDBOX/s-shortx.rows" --accept "$SANDBOX/a-shortx.tsv"; [[ "$RC" -eq 1 ]] && grep -P -q "^stale\tscripts/shortx\tdocs/acc1.md\t$A_ACC1/1\tsuite-unaudited\$" <<<"$AOUT"; }
row_partial && pass "while a suite has an unreadable member its accept rows are not judged by the partial text (no not-a-gap or anchor-not-live to delete); an untracked path is still stale and nothing is accepted" || fail "partial suite accept rows (rc=$RC): $AOUT"
row_shortx && pass "a row for a short-row suite is labelled suite-unaudited, not suite-unregistered" || fail "short-row suite label (rc=$RC): $AOUT"
row_quote() {
  saudit "$SANDBOX/s-qq.rows" --all-refs; [[ "$RC" -eq 1 && "$(grep -c '^gap' <<<"$AOUT")" -eq 1 ]] && grep -qxF -- $'gap\tscripts/qq\t3\tlib/b\\x0ac.txt,lib/b\\x0dc.txt,lib/t\\x09ab.txt' <<<"$AOUT" || return 1
  python3 - "$SUT" <<'PYQ'
import importlib.util as u, sys
s = u.spec_from_file_location('m', sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
q = m.quote_field
ok = (q("a\nb\tc\rd\x1b\x7f\\e") == "a\\x0ab\\x09c\\x0dd\\x1b\\x7f\\x5ce" and q("x,y") == "x,y" and q("x,y", True) == "x\\x2cy" and q("plain/path.sh") == "plain/path.sh"
      and q("caf\u00e9") == "caf\u00e9")
for ch in ("\u0085", "\u009b", "\u2028", "\u2029", "\u202e", "\u2066", "\u200b", "\ufeff", "\u00ad", "\u061c", "\u180e", "\u2060", "\u2064"):   # C1, NEL/CSI, separators, bidi, zero-width
    ok = ok and q("a" + ch + "b") == "a\\u%04xb" % ord(ch)
sys.exit(0 if ok else 1)
PYQ
}
row_quote && pass "a tracked name holding a newline or a tab cannot add a line or a column: every printed path has control characters, backslashes (and commas in a list) written as \\xHH" || fail "output quoting (rc=$RC): $AOUT"
row_cr() { saudit "$SANDBOX/s-cr.rows"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/cr\t1\tlib/cr.txt' <<<"$AOUT"; }
printf 'AFFECTED_SELECTED\tscripts/crl\t0\tedge:derived\t^scripts/crl.test.sh|^data/one.txt\r\n' > "$SANDBOX/s-crl.rows"
row_crl() { saudit "$SANDBOX/s-crl.rows"; [[ "$RC" -eq 0 ]] && grep -q 'gap_suites=0' <<<"$AOUT"; }
row_cr && pass "a lone carriage return is an ordinary character (bash does not split on it): 'cat x<CR># lib/cr.txt' is one line and the path is read" || fail "lone CR fixture (rc=$RC): $AOUT"
row_crl && pass "a CRLF --list file: the last edge of each row still hits (the trailing CR is dropped from the row)" || fail "CRLF rows file (rc=$RC): $AOUT"
printf 'AFFECTED_SELECTED\tdsym\t0\tedge:declared\t^dsym/\n' > "$SANDBOX/s-dsym.rows"
row_sym() (
  ulimit -v 1500000 2>/dev/null || true   # a reader that follows /dev/zero dies of MemoryError here instead of taking the machine
  saudit "$SANDBOX/s-dsym.rows"
  [[ "$RC" -eq 1 ]] && grep -qxF -- $'unaudited\tdsym\tunreadable:dsym/big.test.ts,dsym/fifo.test.ts,dsym/loop.test.ts,dsym/out.test.ts,dsym/sib.test.ts,dsym/zero.test.ts' <<<"$AOUT" && grep -qxF -- $'gap\tdsym\t1\tdata/sy.txt' <<<"$AOUT" && ! grep -q 'data/out.txt\|data/sib.txt' <<<"$AOUT" || { printf 'rc=%s %s\n' "$RC" "$AOUT" >&2; return 1; }
)
row_sym && pass "only regular files inside the tree are read: a tracked symlink to /dev/zero, to a file outside the tree, to a SIBLING directory sharing the root's name prefix, to a FIFO inside the tree (no hang) and to itself, and a file over the 8 MiB cap are unreadable (no MemoryError), while a file of exactly 8 MiB is read and a symlink to a regular file inside the tree is followed" || fail "symlink fixture: $(row_sym 2>&1 | tail -3)"
A_IDL="$(anchor_of 'cat data/idl.txt')"
arow scripts/idl data/idl.txt "$A_IDL" 1 > "$SANDBOX/a-idl1.tsv"; { arow scripts/idl data/idl.txt "$A_IDL" 1; arow scripts/idl data/idl.txt "$A_IDL" 2; } > "$SANDBOX/a-idl2.tsv"
row_idl1() { saudit "$SANDBOX/s-idl.rows" --accept "$SANDBOX/a-idl1.tsv"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/idl\t2\tdata/idl.txt,lib1/idl.sh' <<<"$AOUT"; }
row_idl2() { saudit "$SANDBOX/s-idl.rows" --accept "$SANDBOX/a-idl2.tsv"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/idl\t1\tlib1/idl.sh' <<<"$AOUT" && grep -q 'accepted=1 stale=0' <<<"$AOUT"; }
row_idl1 && pass "an identical line in the suite and in its sourced library is two occurrences: one accept row (anchor,1) leaves the pair a gap (the ordinal runs across the files)" || fail "identical line in suite and library, one row (rc=$RC): $AOUT"
row_idl2 && pass "control: rows (anchor,1) and (anchor,2) exempt both occurrences" || fail "identical line in suite and library, two rows (rc=$RC): $AOUT"
{ srow tw1; srow tw2; } > "$SANDBOX/s-tw.rows"; arow scripts/tw1 data/tw.txt "$(anchor_of 'cat data/tw.txt')" 1 > "$SANDBOX/a-tw.tsv"
row_tw() { saudit "$SANDBOX/s-tw.rows" --accept "$SANDBOX/a-tw.tsv"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/tw2\t1\tdata/tw.txt' <<<"$AOUT" && ! grep -q '^gap.scripts/tw1' <<<"$AOUT" && grep -q 'accepted=1 stale=0' <<<"$AOUT"; }
row_tw && pass "an accept row names ONE suite: two suites with the identical line, a row for the first exempts only the first" || fail "two suites, identical lines (rc=$RC): $AOUT"
for i in "${!PC_PATHS[@]}"; do arow scripts/prec "${PC_PATHS[$i]}" "$(anchor_of "${PC_LINES[$i]}")" 1; done > "$SANDBOX/a-prec.tsv"
row_prec_accept() { saudit "$SANDBOX/s-prec.rows" --accept "$SANDBOX/a-prec.tsv"; [[ "$RC" -eq 0 ]] && grep -q "gap_refs=0 accepted=$((${#PC_KEEP_PRE[@]} + 1)) stale=0" <<<"$AOUT"; }
row_prec_accept && pass "the anchors follow the same table: a line behind each of the 26 keep prefixes (and the line start) gets an anchor, so one accept row per line exempts all 26 pairs (a boundary() that refused any one prefix leaves its pair a gap)" || fail "preceding-character table, accept rows (rc=$RC): $AOUT"
{ srow two; srow twob '^data/p1.txt'; } > "$SANDBOX/s-marker.rows"
row_marker() { saudit "$SANDBOX/s-marker.rows"; [[ "$RC" -eq 1 ]] && grep -q 'suites=2 always_on=0 audited=2 unaudited=0 gap_suites=2 gap_refs=3 accepted=0 stale=0 refs=4 files_read=2$' <<<"$AOUT"; }
row_marker && pass "the summary line: two suites, one with a declared edge over one of its two refs: refs=4 counts the pairs BEFORE the edge (gap_refs=3 after it) and files_read=2 the distinct files read" || fail "summary reach counters (rc=$RC): $AOUT"

echo "== audit round 3: tracked suites a * row cannot accept, untracked and aliased hops, one verdict per label, control characters"
for k in stdel stdang stdlink; do
  srow "$k" > "$SANDBOX/s-$k.rows"; printf 'scripts/%s\t*\t-\t-\tfalse-positive: a tracked suite is not a suite with no inputs\n' "$k" > "$SANDBOX/a-star-$k.tsv"
done
row_star_tracked() {
  local k
  for k in stdel stdang stdlink; do
    saudit "$SANDBOX/s-$k.rows" --accept "$SANDBOX/a-star-$k.tsv"
    [[ "$RC" -eq 1 ]] && grep -qxF -- $'unaudited\tscripts/'"$k"$'\t^scripts/'"$k.test.sh" <<<"$AOUT" && grep -P -q "^stale\tscripts/$k\t\*\t-/-\tstar-row-tracked-suite\$" <<<"$AOUT" && grep -q 'accepted=0 stale=1' <<<"$AOUT" || { echo "$k: rc=$RC $AOUT" >&2; return 1; }
  done
}
row_star_tracked && pass "a '*' accept row is refused (stale star-row-tracked-suite) for a suite whose file git tracks but the work tree lost: deleted, a dangling symlink, a link to a directory; the suite stays unaudited (a directory with no tracked bun test file is still accepted: see the adir row)" || fail "star row over a tracked suite: $(row_star_tracked 2>&1 | tail -2)"
srow hopu > "$SANDBOX/s-hopu.rows"; srow hopa > "$SANDBOX/s-hopa.rows"
row_hop_untracked() { saudit "$SANDBOX/s-hopu.rows"; [[ "$RC" -eq 0 ]] && grep -q 'gap_suites=0 gap_refs=0 accepted=0 stale=0 refs=0 files_read=1$' <<<"$AOUT"; }
row_hop_alias() { saudit "$SANDBOX/s-hopa.rows" --all-refs; [[ "$RC" -eq 1 && "$(grep -c -P '^ref\tscripts/hopa\tdata/one\.txt\t' <<<"$AOUT")" -eq 1 ]] && grep -P -q '^ref\tscripts/hopa\tdata/one\.txt\tlib1/helper\.sh:1\t[0-9a-f]{12}/1\t' <<<"$AOUT" && grep -q 'files_read=2$' <<<"$AOUT"; }
row_hop_untracked && pass "a sourced file that is present but NOT tracked is not read (the counters do not depend on untracked files): no gap, files_read=1" || fail "untracked sourced file (rc=$RC): $AOUT"
row_hop_alias && pass "two names for one library (lib1/helper.sh and a tracked symlink lib1/alias.sh to it) are one read: the line has ordinal 1, files_read=2" || fail "aliased sourced file (rc=$RC): $AOUT"
{ printf 'AFFECTED_SELECTED\tscripts/lbl\t0\tedge:derived\t^scripts/lbla.test.sh\n'; printf 'AFFECTED_SELECTED\tscripts/lbl\t0\tedge:derived\t^scripts/lblb.test.sh|^data/lbl.txt\n'; } > "$SANDBOX/s-lbl.rows"
arow scripts/lbl data/lbl.txt "$(anchor_of 'cat data/lbl.txt')" 1 > "$SANDBOX/a-lbl.tsv"
{ printf 'AFFECTED_SELECTED\tscripts/lbl\t0\tedge:derived\t^scripts/lbla.test.sh\n'; printf 'AFFECTED_SELECTED\tscripts/lbl\t0\tedge:derived\t^scripts/lblb.test.sh\n'; } > "$SANDBOX/s-lbl2.rows"
row_label_rows() {
  saudit "$SANDBOX/s-lbl.rows" --all-refs; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/lbl\t1\tdata/lbl.txt' <<<"$AOUT" && [[ "$(grep -c '^ref' <<<"$AOUT")" -eq 1 ]] && grep -P -q '^ref\tscripts/lbl\tdata/lbl\.txt\tscripts/lbla\.test\.sh:1\t' <<<"$AOUT" \
    && grep -q 'suites=2 always_on=0 audited=1 unaudited=0 gap_suites=1 gap_refs=1 accepted=0 stale=0 refs=1 files_read=2$' <<<"$AOUT" || return 1
  saudit "$SANDBOX/s-lbl.rows" --accept "$SANDBOX/a-lbl.tsv"; [[ "$RC" -eq 0 ]] && grep -q 'gap_suites=0 gap_refs=0 accepted=1 stale=0' <<<"$AOUT" || return 1
  saudit "$SANDBOX/s-lbl2.rows" --all-refs; [[ "$RC" -eq 1 && "$(grep -c -P '^ref\tscripts/lbl\tdata/lbl\.txt\t' <<<"$AOUT")" -eq 2 ]] && grep -q -P '/2\tcat data/lbl.txt$' <<<"$AOUT" || return 1   # both rows miss it: both lines count (ordinals 1 and 2)
  saudit "$SANDBOX/s-lbl2.rows" --accept "$SANDBOX/a-lbl.tsv"; [[ "$RC" -eq 1 ]] && grep -qxF -- $'gap\tscripts/lbl\t1\tdata/lbl.txt' <<<"$AOUT"
}
row_label_rows && pass "two rows of ONE label with different edges: the pair is a gap of the row whose edges miss it, its ref line and anchor come from THAT row's text only (one accept row exempts it), and the counters are per label (suites=2 rows, audited=1, refs=1 pair)" || fail "two rows, one label (rc=$RC): $AOUT"
{ printf 'AFFECTED_SELECTED\tscripts/aoo\t0\tedge:derived\t^scripts/aoo.test.sh\n'; printf 'AFFECTED_SELECTED\tscripts/aoo\t1\talways_on\t^scripts/aoo.test.sh\n'; } > "$SANDBOX/s-aoo1.rows"
{ printf 'AFFECTED_SELECTED\tscripts/aoo\t1\talways_on\t^scripts/aoo.test.sh\n'; printf 'AFFECTED_SELECTED\tscripts/aoo\t0\tedge:derived\t^scripts/aoo.test.sh\n'; } > "$SANDBOX/s-aoo2.rows"
arow scripts/aoo docs/acc1.md "$A_ACC1" 1 > "$SANDBOX/a-aoo.tsv"
row_always_on_order() {
  local o1 o2 r1 r2
  saudit "$SANDBOX/s-aoo1.rows" --accept "$SANDBOX/a-aoo.tsv"; o1="$AOUT"; r1=$RC
  saudit "$SANDBOX/s-aoo2.rows" --accept "$SANDBOX/a-aoo.tsv"; o2="$AOUT"; r2=$RC
  [[ "$r1" -eq 1 && "$r1" = "$r2" && "$o1" = "$o2" ]] && grep -P -q "^stale\tscripts/aoo\tdocs/acc1.md\t$A_ACC1/1\tsuite-always-on\$" <<<"$o1" && grep -q 'suites=2 always_on=1 audited=0 unaudited=0' <<<"$o1"
}
row_always_on_order && pass "a label is always_on if ANY of its rows is: both orders of an always_on row and a normal row of one label print the same lines (the accept row is stale suite-always-on either way)" || fail "always_on order dependence"
{ srow acc; printf 'AFFECTED_SELECTED\tscripts/acc\t0\tedge:derived\t^scripts/nosuch2.test.sh\n'; } > "$SANDBOX/s-sib.rows"
row_dead_sibling() { saudit "$SANDBOX/s-sib.rows" --accept "$SANDBOX/a-ok.tsv"; [[ "$RC" -eq 1 && "$(grep -c '^stale' <<<"$AOUT")" -eq 0 ]] && grep -qxF -- $'unaudited\tscripts/acc\t^scripts/nosuch2.test.sh' <<<"$AOUT" && grep -q 'gap_suites=0 gap_refs=0 accepted=2 stale=0' <<<"$AOUT"; }
row_dead_sibling && pass "a sibling row of the label with nothing to read is reported unaudited, but it does not turn the live accept rows (judged against the readable row) into suite-unaudited" || fail "unreadable sibling row (rc=$RC): $AOUT"
CTL_L=$'scripts/c\x07tl'
{ printf 'AFFECTED_SELECTED\t%s\t0\tedge:derived\t^scripts/ctl.test.sh\n' "$CTL_L"; printf 'AFFECTED_SELECTED\t%s\t0\tedge:derived\t^scripts/nosuch\x1b.test.sh\n' $'scripts/cu\x07'; } > "$SANDBOX/s-ctl.rows"
printf '%s\t%s\t000000000000\t1\tfalse-positive: x\n' "$CTL_L" $'lib/n\x1bo.txt' > "$SANDBOX/a-ctl.tsv"
row_ctl_bytes() {
  saudit "$SANDBOX/s-ctl.rows" --all-refs --accept "$SANDBOX/a-ctl.tsv"; [[ "$RC" -eq 1 ]] || return 1
  ! LC_ALL=C grep -q -P '[\x00-\x08\x0b-\x1f\x7f]' <<<"$AOUT" || return 1   # no raw control byte (TAB and LF are the separators)
  grep -qxF -- $'gap\tscripts/c\\x07tl\t1\tlib/t\\x09ab.txt' <<<"$AOUT" && grep -F -q $'ref\tscripts/c\\x07tl\tlib/t\\x09ab.txt\tscripts/ctl.test.sh:1\t' <<<"$AOUT" && grep -F -q 'ab.txt \x1b[31m' <<<"$AOUT" \
    && grep -qxF -- $'stale\tscripts/c\\x07tl\tlib/n\\x1bo.txt\t000000000000/1\tpath-untracked' <<<"$AOUT" && grep -qxF -- $'unaudited\tscripts/cu\\x07\t^scripts/nosuch\\x1b.test.sh' <<<"$AOUT"
}
row_ctl_bytes && pass "no raw control byte reaches the gap, ref, stale and unaudited lines: a label with BEL, a path with ESC, a source line with ESC and a name with TAB are all written as \\xHH" || fail "control bytes in output (rc=$RC): $(cat -v <<<"$AOUT" | head -6)"
srow bnd1 > "$SANDBOX/s-bnd1.rows"; arow scripts/bnd1 docs/b1.md "$(anchor_of 'docs/b1.md')" 1 > "$SANDBOX/a-bnd1.tsv"
row_bnd_two() { saudit "$SANDBOX/s-bnd1.rows" --accept "$SANDBOX/a-bnd1.tsv"; [[ "$RC" -eq 0 ]] && grep -q 'accepted=1 stale=0' <<<"$AOUT"; }
row_bnd_two && pass "a path at the FIRST character of a line is a boundary line, the same path at the SECOND character (xdocs/b1.md: behind a word character) is not: one accept row for the first exempts the pair" || fail "offset 0 versus offset 1 (rc=$RC): $AOUT"
{ printf 'AFFECTED_SELECTED\tscripts/neg\t0\tedge:derived\n'; printf 'AFFECTED_SELECTED\tscripts/neg\t1\talways_on\t^scripts/neg.test.sh\n'; } > "$SANDBOX/s-neg.rows"
row_audited_floor() { saudit "$SANDBOX/s-neg.rows"; [[ "$RC" -eq 1 ]] && grep -q 'suites=2 always_on=1 audited=0 unaudited=1 ' <<<"$AOUT"; }
row_audited_floor && pass "audited= is never negative: one label that is both unaudited (a short row) and always_on is subtracted once (audited=0)" || fail "audited for a label in two states (rc=$RC): $AOUT"
row_help_text() {
  local top sub
  top="$(python3 "$SUT" --help 2>&1)"; sub="$(python3 "$SUT" audit --help 2>&1)"
  grep -q 'UNITS: `suites` counts selector ROWS' <<<"$top" && grep -q 'DECLARED LIMITS' <<<"$top" && grep -q 'ACCEPT FILE (--accept FILE' <<<"$top" && grep -q 'top-level --help' <<<"$sub" && ! grep -q 'section above' <<<"$sub"
}
row_help_text && pass "--help documents the units of every counter and the declared limits, and audit --help points at the top-level --help (which holds the ACCEPT FILE section), not at a section 'above'" || fail "help text"

echo "== audit scan: a library read once is scanned once, however many suites source it"
MEMODIR="$SANDBOX/memo"; assert_fixture_dir "$MEMODIR"; mkdir -p "$MEMODIR"
row_scan_memo() {
  python3 - "$SUT" "$MEMODIR" <<'PYMEMO'
import importlib.util as u, os, sys
s = u.spec_from_file_location('m', sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
root = sys.argv[2]
tracked = {"dd%d/ff%d.txt" % (i % 50, i) for i in range(2000)} | {"lib.sh", "a.test.sh", "b.test.sh"}   # a sourced library is read only when it is tracked
lib = "\n".join("cat dd%d/ff%d.txt" % (i % 50, i) for i in range(0, 2000, 3)) + "\n"
for name, body in (("lib.sh", lib), ("a.test.sh", "source lib.sh\n"), ("b.test.sh", "source lib.sh\n")):
    with open(os.path.join(root, name), "w") as fh:
        fh.write(body)
alone = m.PathIndex(tracked); m.scan_text(alone, lib); once = alone.ops
idx = m.PathIndex(tracked)
ra = m.suite_refs(root, "a", [os.path.join(root, "a.test.sh")], idx); after_a = idx.ops
rb = m.suite_refs(root, "b", [os.path.join(root, "b.test.sh")], idx); extra = idx.ops - after_a
ok = ra == rb and len(ra) == len(range(0, 2000, 3)) + 1 and once > 1000 and after_a >= once and extra * 10 < once
print("memo once=%d first=%d second=%d refs=%d" % (once, after_a, extra, len(ra)), file=sys.stderr)
sys.exit(0 if ok else 1)
PYMEMO
}
row_scan_memo 2>/dev/null && pass "the second suite that sources the same library costs a tenth of one scan of it or less (per-file memoisation across suites)" || fail "memoisation fixture: $(row_scan_memo 2>&1 | tail -2)"

echo "== audit scan: an old-scan ORACLE (brute-force 'p in text') against the new scan, escape forms included"
ORADIR="$SANDBOX/oracle"; assert_fixture_dir "$ORADIR"; mkdir -p "$ORADIR"
row_scan_oracle() {
  python3 - "$SUT" "$ORADIR" <<'PYORA'
import importlib.util as u, os, re, sys
s = u.spec_from_file_location('m', sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
root = sys.argv[2]
# one line per context; the line is `cat ` + context + a tracked path that appears nowhere else
ctx = ["", " ", "\t", '"', "'", "/", "=", ":", "(", "$(", "{", "<", ">", "|", ";", ",", "@", "x-", ".", "`", "&", "!", "+", "[", "#", "${V:-",
       "\\t", "\\n", "\\r", "\\f", "\\v", "\\a", "\\b", "\\e", "\\0", "\\011", "\\x09", "\\x9", "\\u0009", "\\033", "-I",
       "x", "7", "_", "\\033[0m", "ab", "\\xz", "\\d", "x-I", "\\u00", "\\8", "-"]
paths = ["o/p%02d.txt" % i for i in range(len(ctx))]
lines = [(c if c == "" else "cat " + c) + p for c, p in zip(ctx, paths)]   # a "" context is a path at the start of a line
# a path whose FIRST letter is also an escape letter, behind a lone backslash (`\tests/x`, `\bin/x`): the escape-looking head must not be eaten
for L in "abefnrtv":
    ctx.append("\\"); paths.append("%s/q.txt" % L); lines.append("cat \\" + paths[-1])
text = "\n".join(lines) + "\n"
with open(os.path.join(root, "oracle.test.sh"), "w") as fh:
    fh.write(text)
# the oracle, written independently of the SUT: a context is a boundary when nothing is in front of it, the previous character is
# not a word character, a printf escape ends the context, or the context ends in an attached short option (a `-` that is not
# itself inside a word, plus one letter)
ESC_TAIL = re.compile(r"\\(?:[abefnrtv]|0[0-7]{0,3}|x[0-9A-Fa-f]{1,2}|u[0-9A-Fa-f]{4})$")
OPT_TAIL = re.compile(r"""(?:^|[\s"'])-[A-Za-z]$""")
def oracle_boundary(prefix, first):
    return prefix == "" or re.match(r"[A-Za-z0-9_]", prefix[-1]) is None or ESC_TAIL.search(prefix) is not None or OPT_TAIL.search(prefix) is not None
tracked = set(paths)
old = {p for p in tracked if p in text}                      # the old scan: every tracked path that occurs anywhere in the text
idx = m.PathIndex(tracked)
new = set(m.suite_refs(root, "none", [os.path.join(root, "oracle.test.sh")], idx))
want = {p for l, p in zip(lines, paths) if oracle_boundary(l[:len(l) - len(p)], p[0])}
bad = []
if not new <= old:
    bad.append("new has refs old lacks: %s" % sorted(new - old)[:3])
if new != want:
    bad.append("new != oracle: missing %s extra %s" % (sorted(want - new)[:4], sorted(new - want)[:4]))
for p in old - new:                                          # every dropped ref starts mid-component at EVERY occurrence
    for l in lines:
        i = l.find(p)
        if i >= 0 and oracle_boundary(l[:i], p[0]):
            bad.append("dropped %s although it starts at a boundary" % p)
if len(old) != len(ctx) or len(want) != 50 or len(old - new) != 10:
    bad.append("the table is not exercising both sides: old=%d boundary=%d dropped=%d" % (len(old), len(want), len(old - new)))
print("; ".join(bad) or "ok old=%d new=%d dropped=%d" % (len(old), len(new), len(old - new)), file=sys.stderr)
sys.exit(1 if bad else 0)
PYORA
}
row_scan_oracle 2>/dev/null && pass "against a brute-force 'p in text' oracle on 52 preceding contexts and 8 escape-letter heads (every escape form, an attached -I, word characters): new refs are a subset of old refs, equal the independent boundary oracle, and every dropped ref starts mid-component" || fail "old-scan oracle fixture: $(row_scan_oracle 2>&1 | tail -1)"
row_census() {
  python3 - "$SUT" "$SREPO" "$SANDBOX/s-two.rows" <<'PYCEN'
import importlib.util as u, sys
s = u.spec_from_file_location('m', sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
rows = open(sys.argv[3]).read().split("\n") + ["AFFECTED_SUMMARY selected=0 of=1 always_on=0 edge=0 fallback=none", "AFFECTED_FALLBACK\treason=none"]
c = m.audit_census(sys.argv[2], rows, {})
ok = (c.gaps == {"scripts/two": ["data/p1.txt", "data/p2.txt"]} and c.unaudited == [] and c.stale == [] and c.suites == 1 and c.gap_refs == 2
      and "AFFECTED_SUMMARY selected=0 of=1 always_on=0 edge=0 fallback=none" in c.extra and "AFFECTED_FALLBACK\treason=none" in c.extra)
sys.exit(0 if ok else 1)
PYCEN
}
row_census && pass "audit_census(root, rows, accept) returns the gaps by suite, the unaudited and stale lists and the counters, and keeps the AFFECTED_SUMMARY and AFFECTED_FALLBACK lines for a later consumer (cmd_audit only formats)" || fail "census object"

# ---------------------------------------------------------------------------------------------------------------------
# PR1b of the S4 index completion (#10448, Ref #9729): the audit's REACH. A suite's reads are its own file, the `source` closure of it (to depth
# 8, operands resolved against the INCLUDING file), and the code files its selector row lists that an already-read text names (the naming walk,
# to depth 8); a path named in a comment of the file's OWN language is a mention; an edge is credited exactly when the selector would select the
# suite. Fixtures live in their own repo ($RREPO, never $SREPO/$AREPO: new tracked files would change the populations the PR1 rows and the
# 20,000-path fixture depend on). Every negative sits beside a positive control that IS reported, so an empty result cannot pass.
echo "== audit reach (PR1b): source closure, naming walk, comment table, edge parity, canonical order, cost"
RREPO="$SANDBOX/rrepo"
assert_fixture_dir "$RREPO"
rmk() {  # rmk <relpath> <content>: write one fixture file under the reach repo, content verbatim
  assert_fixture_dir "$RREPO"; mkdir -p "$(dirname "$RREPO/$1")" && printf '%s' "$2" > "$RREPO/$1"
}
RDATA=(deep first second cyc inner decoy untr prose commented ctl w1 w1b w2 w3 w4 w5 w6 g1 dd1 h cls_sh cls_py cls_ts ord ord2 unr2 cm_own cm_other cm_live cm_quote cm_dollar wsrc sa sb g2)
for n in d1 d2 d3 d4 d5 d6 d7 d8 d9 n1 n2 n3 n4 n5 n6 n7 n8 n9 op1 op2 op3 op4 op5 op6 op7 op8 op9 op10 op11 op12 op13 op14 op15 op16 op17 op18 tie wcl lvl lcl dsw; do RDATA+=("$n"); done
for n in "${RDATA[@]}"; do rmk "data/$n.txt" $'t\n'; done
rmk zz/only-from-trigger.txt $'t\n'

# --- the source closure
rmk scripts/chain3.test.sh $'source libA/l1.sh\n'; rmk libA/l1.sh $'source libA/l2.sh\n'; rmk libA/l2.sh $'source libA/l3.sh\n'; rmk libA/l3.sh $'cat data/deep.txt\n'
rmk scripts/depth9.test.sh $'source libB/l1.sh\n'
for k in 1 2 3 4 5 6 7 8; do rmk "libB/l$k.sh" "source libB/l$((k + 1)).sh"$'\n'"cat data/d$k.txt"$'\n'; done
rmk libB/l9.sh $'cat data/d9.txt\n'
rmk scripts/twosrc.test.sh $'source libC/first.sh\nsource "$SCRIPT_DIR/second.sh"\n'; rmk libC/first.sh $'cat data/first.txt\n'; rmk scripts/second.sh $'cat data/second.txt\n'
rmk scripts/cyc.test.sh $'source libD/a.sh\n'; rmk libD/a.sh $'source libD/b.sh\ncat data/cyc.txt\n'; rmk libD/b.sh $'source libD/a.sh\n'
# operand forms: every form sits in an OUTER library under libG/ (the suite sources libG/outerN.sh), so a form that resolves against the including
# file lands in libG/ while the same form resolved against the suite's directory (scripts/) or the repo root finds nothing; a root form lands in libH/
OPF=('source "$(dirname "$0")/oplib1.sh"|libG/oplib1.sh' 'source "$(dirname "${BASH_SOURCE[0]}")/oplib2.sh"|libG/oplib2.sh'
     'source "$SCRIPT_DIR/oplib3.sh"|libG/oplib3.sh' 'source "${SCRIPT_DIR}/oplib4.sh"|libG/oplib4.sh' 'source "$HERE/oplib5.sh"|libG/oplib5.sh'
     'source "${HERE}/oplib6.sh"|libG/oplib6.sh' 'source "$DIR/oplib7.sh"|libG/oplib7.sh' 'source "${DIR}/oplib8.sh"|libG/oplib8.sh'
     'source "$REPO_ROOT/libH/oplib9.sh"|libH/oplib9.sh' 'source "${REPO_ROOT}/libH/oplib10.sh"|libH/oplib10.sh'
     'source "$ROOT_DIR/libH/oplib11.sh"|libH/oplib11.sh' 'source ./libH/oplib12.sh|libH/oplib12.sh' 'source "$X/libH/oplib13.sh"|libH/oplib13.sh'
     '. libH/oplib14.sh|libH/oplib14.sh'
     'source "$SCRIPT_DIR/../libH/oplib15.sh"|libH/oplib15.sh' "source '\$SCRIPT_DIR/oplib16.sh'|libG/oplib16.sh"
     'source "$SCRIPT_DIR/oplib17.bash"|libG/oplib17.bash' $'source\t"$SCRIPT_DIR/oplib18.sh"|libG/oplib18.sh')
i=0; for e in "${OPF[@]}"; do
  i=$((i + 1)); rmk "scripts/op$i.test.sh" "source libG/outer$i.sh"$'\n'; rmk "libG/outer$i.sh" "${e%%|*}"$'\n'; rmk "${e##*|}" "cat data/op$i.txt"$'\n'
done
# a decoy for the two-hop reading: scripts/oplib3.sh would be the target if the form were resolved against the SUITE's directory
rmk scripts/oplib3.sh $'cat data/decoy.txt\n'
# negatives: an untracked target, a runner trigger, a prose "see. lib/x.sh", a commented source line; negctl sources the same libraries for real
rmk scripts/negu.test.sh $'source libN/untracked.sh\n'
rmk scripts/negt.test.sh $'source scripts/test-all.sh\n'; rmk scripts/test-all.sh $'cat zz/only-from-trigger.txt\n'
rmk scripts/negp.test.sh $'echo see. libN/prose.sh\n'; rmk scripts/negc.test.sh $'# source libN/commented.sh\ntrue\n'
rmk scripts/negctl.test.sh $'source libN/prose.sh\nsource libN/commented.sh\n'; rmk libN/prose.sh $'cat data/prose.txt\n'; rmk libN/commented.sh $'cat data/commented.txt\n'
# unreadable reach: a dangling symlink at depth 3 of a closure, and a dangling code file in `pats`; a neighbour that must still be scanned
rmk scripts/unr.test.sh $'source libU/u1.sh\n'; rmk libU/u1.sh $'source libU/u2.sh\n'; rmk libU/u2.sh $'source libU/dang.sh\n'; ln -s no-such-target.sh "$RREPO/libU/dang.sh"
rmk scripts/unr2.test.sh $'cat data/unr2.txt\n'
rmk scripts/unrw.test.sh $'bash walk/dangcode.sh\n'; mkdir -p "$RREPO/walk" && ln -s no-such-code.sh "$RREPO/walk/dangcode.sh"

# --- the naming walk
rmk scripts/wk.test.sh $'bash walk/code1.sh\ncat walk/notlisted.sh\ncat walk/doc.md walk/cfg.yml walk/tab.tsv\n'
rmk walk/code1.sh $'cat data/w1.txt\n'; rmk walk/notlisted.sh $'cat data/w2.txt\n'; rmk walk/unnamed.sh $'cat data/w3.txt\n'
rmk walk/doc.md $'cat data/w4.txt\n'; rmk walk/cfg.yml $'cat data/w5.txt\n'; rmk walk/tab.tsv $'cat data/w6.txt\n'
rmk scripts/wchain.test.sh $'bash walk/n1.sh\n'
for k in 1 2 3 4 5 6 7 8; do rmk "walk/n$k.sh" "cat walk/n$((k + 1)).sh"$'\n'"cat data/n$k.txt"$'\n'; done
rmk walk/n9.sh $'cat data/n9.txt\n'
rmk scripts/wtrig.test.sh $'bash scripts/test-all.sh\nbash walk/ok.sh\n'; rmk walk/ok.sh $'cat data/w1b.txt\n'
rmk scripts/wgl.test.sh $'bash walk/g1.sh\nbash walk/dir/d1.sh\nbash walk/ok.sh\ncat "glob:walk/*.sh"\n'; rmk walk/g1.sh $'cat data/g1.txt\n'; rmk 'glob:walk/*.sh' $'cat data/g2.txt\n'; rmk walk/dir/d1.sh $'cat data/dd1.txt\n'
rmk scripts/lab.test.sh $'bash walk/helper.sh\n'; rmk scripts/lab2.test.sh $'bash walk/helper.sh\n'; rmk walk/helper.sh $'cat data/h.txt\n'
rmk scripts/wsrc.test.sh $'bash walk/wsrc.sh\n'; rmk walk/wsrc.sh $'source libW/w.sh\n'; rmk libW/w.sh $'cat data/wsrc.txt\n'
# a symlinked library: the selector resolves $SCRIPT_DIR against the file's LOGICAL directory (libS/a), not the directory of its target (libS/b)
mkdir -p "$RREPO/libS/a" "$RREPO/libS/b"
rmk libS/a/sib.sh $'cat data/sa.txt\n'; rmk libS/b/sib.sh $'cat data/sb.txt\n'; rmk libS/b/real.sh $'source "$SCRIPT_DIR/sib.sh"\n'; ln -s ../b/real.sh "$RREPO/libS/a/link.sh"
rmk scripts/symlnk.test.sh $'source libS/a/link.sh\n'; rmk scripts/symreal.test.sh $'source libS/b/real.sh\n'
rmk scripts/cls.test.sh $'bash walk/cls.sh\npython3 walk/cls.py\nbun walk/cls.ts\n'
rmk walk/cls.sh $'cat data/cls_sh.txt\n'; rmk walk/cls.py $'print(open("data/cls_py.txt"))\n'; rmk walk/cls.ts $'readFileSync("data/cls_ts.txt")\n'
# canonical order: identical reading lines in the suite, a closure library and a walk file
rmk scripts/ord.test.sh $'cat data/ord.txt\nsource libO/lib.sh\nbash walk/ordw.sh\n'; rmk libO/lib.sh $'cat data/ord.txt\n'; rmk walk/ordw.sh $'cat data/ord.txt\n'
rmk scripts/ord2a.test.sh $'cat data/ord2.txt\n'; rmk scripts/ord2b.test.sh $'cat data/ord2.txt\n'
# row-order ties: two rows of ONE label share their first pattern and differ after it (and their LAST patterns order them the other way round)
rmk scripts/tie.test.sh $'cat data/tie.txt\nbash walk/tiea.sh\nbash walk/tieb.sh\n'; rmk walk/tiea.sh $'cat data/tie.txt\n'; rmk walk/tieb.sh $'cat data/tie.txt\n'
# a walk file's source closure feeds the naming of the next level
rmk scripts/wcl.test.sh $'bash walk/wc1.sh\n'; rmk walk/wc1.sh $'source libX/wc.sh\n'; rmk libX/wc.sh $'bash walk/wc2.sh\n'; rmk walk/wc2.sh $'cat data/wcl.txt\n'
# two walk files of ONE level with identical lines (read in sorted order, named in the opposite order), and their closures (read in walk order)
rmk scripts/lvl.test.sh $'bash walk/lvb.sh\nbash walk/lva.sh\n'; rmk walk/lva.sh $'cat data/lvl.txt\n'; rmk walk/lvb.sh $'cat data/lvl.txt\n'
rmk scripts/lcl.test.sh $'bash walk/lcb.sh\nbash walk/lca.sh\n'; rmk walk/lca.sh $'source libY/ya.sh\n'; rmk walk/lcb.sh $'source libY/yb.sh\n'
rmk libY/ya.sh $'cat data/lcl.txt\n'; rmk libY/yb.sh $'cat data/lcl.txt\n'
# a directory suite whose SECOND test file is the only one that names the walk file
rmk dsw/a.test.ts $'export {}\n'; rmk dsw/b.test.ts $'readFileSync("walk/dsw.sh")\n'; rmk walk/dsw.sh $'cat data/dsw.txt\n'
# one walk file per CODE_EXT member
CE_EXT=(sh bash py ts tsx jsx js mjs cjs mts cts rb)
ce_lines=""; for x in "${CE_EXT[@]}"; do ce_lines+="bash walk/ce.$x"$'\n'; rmk "walk/ce.$x" "cat data/ce_$x.txt"$'\n'; rmk "data/ce_$x.txt" $'t\n'; done
rmk scripts/ce.test.sh "$ce_lines"

# --- the comment table: one file per extension, each with a line comment in its own language, one in the OTHER language and a live line
CM_HASH=(sh bash py rb yml yaml); CM_SLASH=(ts tsx js jsx mjs cjs mts cts); CM_NONE=(md tsv txt)
mkdir -p "$RREPO/cm"
for x in "${CM_HASH[@]}"; do rmk "cm/c.$x" $'# data/cm_own.txt\n// data/cm_other.txt\ncat data/cm_live.txt\n'; done
for x in "${CM_SLASH[@]}"; do rmk "cm/c.$x" $'// data/cm_own.txt\n# data/cm_other.txt\ncat data/cm_live.txt\n'; done
for x in "${CM_NONE[@]}"; do rmk "cm/c.$x" $'# data/cm_own.txt\n// data/cm_other.txt\ncat data/cm_live.txt\n'; done
rmk cm/noext $'# data/cm_own.txt\n// data/cm_other.txt\ncat data/cm_live.txt\n'; rmk cm/.hidden $'# data/cm_own.txt\n// data/cm_other.txt\ncat data/cm_live.txt\n'
rmk cm/x.test.ts $'// data/cm_own.txt\ncat data/cm_live.txt\n'; rmk cm/x.ts.snap $'// data/cm_own.txt\ncat data/cm_live.txt\n'
ln -s c.sh "$RREPO/cm/link.txt"
rmk cm/tab.py $'\t# data/cm_own.txt\ncat data/cm_live.txt\n'; rmk cm/crlf.ts $'// data/cm_own.txt\r\ncat data/cm_live.txt\r\n'
rmk cm/q.sh $'echo "# data/cm_quote.txt"\necho ${#x} $# data/cm_dollar.txt\n'; rmk cm/ln.sh $'# one\n# two\ncat data/cm_live.txt\n'
( cd "$RREPO" && gitq init -q -b main . && gitq add -A && gitq commit -qm seed ) || { echo "[FATAL] reach fixture" >&2; exit 1; }
printf 'cat data/untr.txt\n' > "$RREPO/libN/untracked.sh"   # present, NOT tracked
rfix_ok=1
for f in chain3.test.sh second.sh oplib3.sh test-all.sh negu.test.sh wk.test.sh; do gitq -C "$RREPO" ls-files --error-unmatch -- "scripts/$f" >/dev/null 2>&1 || { rfix_ok=0; echo "MISSING planted path: scripts/$f" >&2; }; done
for f in dsw/b.test.ts walk/ce.rb libY/yb.sh walk/lcb.sh libG/oplib18.sh libH/oplib15.sh 'glob:walk/*.sh' libS/a/link.sh libW/w.sh walk/wsrc.sh libU/dang.sh walk/dangcode.sh cm/link.txt cm/.hidden cm/c.cts cm/noext walk/n9.sh libB/l9.sh libH/oplib14.sh libG/outer14.sh data/op14.txt; do gitq -C "$RREPO" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || { rfix_ok=0; echo "MISSING planted path: $f" >&2; }; done
gitq -C "$RREPO" ls-files --error-unmatch -- libN/untracked.sh >/dev/null 2>&1 && { rfix_ok=0; echo "libN/untracked.sh must NOT be tracked" >&2; }
[[ "$rfix_ok" -eq 1 ]] && pass "the reach fixture repo tracks every planted path and leaves libN/untracked.sh untracked (a fixture that did not land would pass its negative rows vacuously)" || fail "the reach fixture repo is wrong"

rrow() {  # rrow <label> [extra patterns, joined with |]: one selector row for scripts/<label>
  printf 'AFFECTED_SELECTED\tscripts/%s\t0\tedge:derived\t^scripts/%s.test.sh%s\n' "$1" "$1" "${2:+|$2}"
}
raudit() { RC=0; AOUT="$(run_sut audit --root "$RREPO" --list "$1" ${2:+"$2"} ${3:+"$3"} 2>&1)" || RC=$?; }   # raudit <rows> [--all-refs | --accept F] [..]
has_ref() { grep -qF -- "$(printf 'ref\t%s\t%s\t' "$2" "$3")" <<<"$1"; }   # has_ref <output> <suite> <path>: a ref line names the path for the suite
chk() { local name="$1"; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }   # chk <name> <cmd...>
# instrument self-test for chk: it must record a pass for a true predicate and a failure for a false one (the assertions below ride on it)
_c_p=$passes; _c_f=$fails; _c_n=${#FAILED[@]}
{ chk "instrument: a true predicate" true; chk "instrument: a false predicate" false; } >/dev/null 2>&1
if [[ "$passes" -ne $((_c_p + 1)) || "$fails" -ne $((_c_f + 1)) || "${#FAILED[@]}" -ne $((_c_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: chk did not record both a pass and a failure\n' >&2; exit 1
fi
passes=$_c_p; fails=$_c_f; if (( _c_n == 0 )); then FAILED=(); else FAILED=("${FAILED[@]:0:_c_n}"); fi

# ---- hop closure
{ rrow chain3; rrow depth9; rrow twosrc; rrow cyc; rrow symlnk '^libS/a/link.sh'; rrow symreal '^libS/b/real.sh'; } > "$SANDBOX/r-hop.rows"
{ i=0; for e in "${OPF[@]}"; do i=$((i + 1)); rrow "op$i" "^libG/outer$i.sh"; done; } > "$SANDBOX/r-ops.rows"
{ rrow negu; rrow negt; rrow negp; rrow negc; rrow negctl '^libN/prose.sh|^libN/commented.sh'; rrow unr; rrow unr2; } > "$SANDBOX/r-neg.rows"
raudit "$SANDBOX/r-hop.rows" --all-refs; RO_HOP="$AOUT"; RC_HOP=$RC
chk "closure: a path named only in the THIRD library of a chain suite -> l1 -> l2 -> l3 is a gap (PR1 read one hop)" has_ref "$RO_HOP" scripts/chain3 data/deep.txt
chk "closure depth: the path named in the 8th library of a 9-library chain is reported" has_ref "$RO_HOP" scripts/depth9 data/d8.txt
chk "closure depth: the path named in the 9th library is NOT reported (the closure stops at depth 8)" bash -c '! grep -qF -- "$(printf "ref\t%s\t%s\t" scripts/depth9 data/d9.txt)" <<<"$1"' _ "$RO_HOP"
chk "closure depth: control, the paths of libraries 1 through 7 are all reported" bash -c 'for k in 1 2 3 4 5 6 7; do grep -qF -- "$(printf "ref\t%s\t%s\t" scripts/depth9 "data/d$k.txt")" <<<"$1" || exit 1; done' _ "$RO_HOP"
chk "closure: a file with two source lines whose SECOND uses \$SCRIPT_DIR/ yields both libraries (no first-member stop)" bash -c 'grep -qF -- "$(printf "ref\t%s\t%s\t" scripts/twosrc data/first.txt)" <<<"$1" && grep -qF -- "$(printf "ref\t%s\t%s\t" scripts/twosrc data/second.txt)" <<<"$1"' _ "$RO_HOP"
chk "closure: a cycle (a sources b sources a) terminates and lists the line of a once" bash -c '[[ "$(grep -c -P "^ref\tscripts/cyc\tdata/cyc\.txt\t" <<<"$1")" -eq 1 ]]' _ "$RO_HOP"
chk "closure: a cycle's library line is listed once, in the first library" bash -c 'grep -qF -- "$(printf "ref\t%s\t%s\t%s" scripts/cyc data/cyc.txt libD/a.sh:2)" <<<"$1"' _ "$RO_HOP"
raudit "$SANDBOX/r-ops.rows" --all-refs; RO_OPS="$AOUT"
i=0; for e in "${OPF[@]}"; do
  i=$((i + 1)); chk "operand form $i resolves to ${e##*|}: ${e%%|*}" has_ref "$RO_OPS" "scripts/op$i" "data/op$i.txt"
done
chk "closure: a symlinked library resolves \$SCRIPT_DIR against its LOGICAL directory (libS/a), never the directory of its target (libS/b)" bash -c 'grep -qF -- "$(printf "ref\t%s\t%s\t" scripts/symlnk data/sa.txt)" <<<"$1" && ! grep -qF -- "$(printf "ref\t%s\t%s\t" scripts/symlnk data/sb.txt)" <<<"$1"' _ "$RO_HOP"
chk "closure: control, the same library reached by its REAL name resolves \$SCRIPT_DIR against libS/b (the memo does not keep the first resolution)" bash -c 'grep -qF -- "$(printf "ref\t%s\t%s\t" scripts/symreal data/sb.txt)" <<<"$1"' _ "$RO_HOP"
[[ "${#OPF[@]}" -ge 18 ]] && pass "operand table floor: at least 18 forms ran (${#OPF[@]})" || fail "operand table shrank to ${#OPF[@]} forms"
raudit "$SANDBOX/r-neg.rows" --all-refs; RO_NEG="$AOUT"; RC_NEG=$RC
chk "operand decoy: \$SCRIPT_DIR in a library under libG/ is the LIBRARY's directory, not the suite's (scripts/oplib3.sh is never read)" bash -c '! grep -qF -- "$(printf "ref\t%s\t%s\t" scripts/op3 data/decoy.txt)" <<<"$1"' _ "$RO_OPS"
chk "negative: an untracked library is not read" bash -c '! grep -qF -- "$(printf "ref\t%s\t%s\t" scripts/negu data/untr.txt)" <<<"$1"' _ "$RO_NEG"
chk "negative: a runner trigger is never read as a hop target" bash -c '! grep -qF -- "zz/only-from-trigger.txt" <<<"$1"' _ "$RO_NEG"
chk "negative: a prose 'see. lib/x.sh' is not a hop" bash -c '! grep -qF -- "$(printf "ref\t%s\t%s\t" scripts/negp data/prose.txt)" <<<"$1"' _ "$RO_NEG"
chk "negative: a commented source line is not a hop" bash -c '! grep -qF -- "$(printf "ref\t%s\t%s\t" scripts/negc data/commented.txt)" <<<"$1"' _ "$RO_NEG"
chk "control: the same two libraries sourced for real are read (their paths are reported)" bash -c 'grep -qF -- "$(printf "ref\t%s\t%s\t" scripts/negctl data/prose.txt)" <<<"$1" && grep -qF -- "$(printf "ref\t%s\t%s\t" scripts/negctl data/commented.txt)" <<<"$1"' _ "$RO_NEG"
chk "unreadable reach: a dangling symlink at depth 3 of a closure makes ONLY that suite unaudited (unreadable:<rel>), exit 1" bash -c 'grep -qxF -- "$(printf "unaudited\tscripts/unr\tunreadable:libU/dang.sh")" <<<"$1" && [[ "$2" -eq 1 ]]' _ "$RO_NEG" "$RC_NEG"
chk "unreadable reach: the neighbouring suite is still scanned (its gap is reported)" has_ref "$RO_NEG" scripts/unr2 data/unr2.txt

# ---- naming walk
{ rrow wk '^walk/code1.sh|^walk/unnamed.sh|^walk/doc.md|^walk/cfg.yml|^walk/tab.tsv'
  rrow wchain "$(for k in 1 2 3 4 5 6 7 8 9; do printf '^walk/n%s.sh|' "$k"; done | sed 's/|$//')"
  rrow wtrig '^scripts/test-all.sh|^walk/ok.sh'; rrow wgl '^glob:walk/*.sh|^walk/dir/|^walk/ok.sh'
  rrow cls '^walk/cls.sh|^walk/cls.py|^walk/cls.ts'; rrow unrw '^walk/dangcode.sh'; rrow wsrc '^walk/wsrc.sh'; } > "$SANDBOX/r-walk.rows"
raudit "$SANDBOX/r-walk.rows" --all-refs; RO_WALK="$AOUT"; RC_WALK=$RC
chk "walk: a code file listed in pats and named by the suite is read (its path is reported)" has_ref "$RO_WALK" scripts/wk data/w1.txt
chk "walk: a code file named but NOT listed in pats is not read" bash -c '! grep -qF -- "$(printf "ref\t%s\t%s\t" scripts/wk data/w2.txt)" <<<"$1"' _ "$RO_WALK"
chk "walk: a code file listed in pats but named by nothing is not read" bash -c '! grep -qF -- "data/w3.txt" <<<"$1"' _ "$RO_WALK"
chk "walk: a .md, a .yml and a .tsv file listed in pats and named by the suite are NOT read (a declared limit)" bash -c '! grep -qE "data/w(4|5|6)\.txt" <<<"$1"' _ "$RO_WALK"
chk "walk depth: the path named in the 8th file of a 9-level naming chain is reported" has_ref "$RO_WALK" scripts/wchain data/n8.txt
chk "walk depth: the path named in the 9th file is NOT reported" bash -c '! grep -qF -- "data/n9.txt" <<<"$1"' _ "$RO_WALK"
chk "walk depth: control, the paths of files 1 through 7 are reported" bash -c 'for k in 1 2 3 4 5 6 7; do grep -qF -- "$(printf "ref\t%s\t%s\t" scripts/wchain "data/n$k.txt")" <<<"$1" || exit 1; done' _ "$RO_WALK"
chk "walk: a runner trigger listed in pats and named by the suite is never read (the path only it names is absent)" bash -c '! grep -qF -- "zz/only-from-trigger.txt" <<<"$1"' _ "$RO_WALK"
chk "walk: control, the exact-listed neighbour in the same row is read" has_ref "$RO_WALK" scripts/wtrig data/w1b.txt
chk "walk: a glob: entry and a dir/ entry are never nodes (their files are named and covered, and not read)" bash -c '! grep -qE "data/(g1|dd1|g2)\.txt" <<<"$1"' _ "$RO_WALK"
chk "walk: control, the exact-listed file of the same row is read" has_ref "$RO_WALK" scripts/wgl data/w1b.txt
chk "walk: a dangling code file listed in pats makes that suite unaudited (unreadable:<rel>)" bash -c 'grep -qxF -- "$(printf "unaudited\tscripts/unrw\tunreadable:walk/dangcode.sh")" <<<"$1" && [[ "$2" -eq 1 ]]' _ "$RO_WALK" "$RC_WALK"
chk "walk: a code file read through the walk brings its own source closure (walk/wsrc.sh sources libW/w.sh)" has_ref "$RO_WALK" scripts/wsrc data/wsrc.txt
chk "per-class: a .sh, a .py and a .ts file reached through the walk are each read (a class that scans zero files cannot pass)" bash -c 'for p in data/cls_sh.txt data/cls_py.txt data/cls_ts.txt; do grep -qF -- "$(printf "ref\t%s\t%s\t" scripts/cls "$p")" <<<"$1" || exit 1; done' _ "$RO_WALK"
# per-row walk state: row A lists helper.sh and declares the path it names; row B names helper.sh, covers it by a dir/ entry and does not list it
printf 'AFFECTED_SELECTED\tscripts/lab\t0\tedge:derived\t^scripts/lab.test.sh|^walk/helper.sh|^data/h.txt\nAFFECTED_SELECTED\tscripts/lab\t0\tedge:derived\t^scripts/lab2.test.sh|^walk/\n' > "$SANDBOX/r-lab-ab.rows"
printf 'AFFECTED_SELECTED\tscripts/lab\t0\tedge:derived\t^scripts/lab2.test.sh|^walk/\nAFFECTED_SELECTED\tscripts/lab\t0\tedge:derived\t^scripts/lab.test.sh|^walk/helper.sh|^data/h.txt\n' > "$SANDBOX/r-lab-ba.rows"
row_lab() { local f; for f in r-lab-ab r-lab-ba; do raudit "$SANDBOX/$f.rows"; [[ "$RC" -eq 0 ]] && grep -q 'gap_suites=0 gap_refs=0' <<<"$AOUT" || return 1; done; }
chk "walk state is per row: row B (no helper.sh in its pats) does not read what row A listed, in either row order (no gap)" row_lab
# a second label: row B LISTS helper.sh and does not declare data/h.txt; it must read the file row A read, in either order
printf 'AFFECTED_SELECTED\tscripts/seen\t0\tedge:derived\t^scripts/lab.test.sh|^walk/helper.sh|^data/h.txt\nAFFECTED_SELECTED\tscripts/seen\t0\tedge:derived\t^scripts/lab2.test.sh|^walk/helper.sh\n' > "$SANDBOX/r-seen-ab.rows"
printf 'AFFECTED_SELECTED\tscripts/seen\t0\tedge:derived\t^scripts/lab2.test.sh|^walk/helper.sh\nAFFECTED_SELECTED\tscripts/seen\t0\tedge:derived\t^scripts/lab.test.sh|^walk/helper.sh|^data/h.txt\n' > "$SANDBOX/r-seen-ba.rows"
row_seen() { local f; for f in r-seen-ab r-seen-ba; do raudit "$SANDBOX/$f.rows" --all-refs; has_ref "$AOUT" scripts/seen data/h.txt || return 1; done; }
chk "walk state is per row: row B (it LISTS helper.sh) still reads the file row A read, in either row order (the gap is reported)" row_seen

# ---- canonical order
{ rrow ord '^libO/lib.sh|^walk/ordw.sh'; } > "$SANDBOX/r-ord.rows"
raudit "$SANDBOX/r-ord.rows" --all-refs; RO_ORD="$AOUT"; A_ORD="$(anchor_of 'cat data/ord.txt')"
chk "order: identical reading lines in the suite, a closure library and a walk file are ordinals 1, 2, 3 (asserted through the FILE column)" bash -c 'grep -qF -- "$(printf "ref\tscripts/ord\tdata/ord.txt\tscripts/ord.test.sh:1\t$2/1\t")" <<<"$1" && grep -qF -- "$(printf "ref\tscripts/ord\tdata/ord.txt\tlibO/lib.sh:1\t$2/2\t")" <<<"$1" && grep -qF -- "$(printf "ref\tscripts/ord\tdata/ord.txt\twalk/ordw.sh:1\t$2/3\t")" <<<"$1"' _ "$RO_ORD" "$A_ORD"
printf 'AFFECTED_SELECTED\tscripts/ord2\t0\tedge:derived\t^scripts/ord2a.test.sh\nAFFECTED_SELECTED\tscripts/ord2\t0\tedge:derived\t^scripts/ord2b.test.sh\n' > "$SANDBOX/r-ord2-ab.rows"
printf 'AFFECTED_SELECTED\tscripts/ord2\t0\tedge:derived\t^scripts/ord2b.test.sh\nAFFECTED_SELECTED\tscripts/ord2\t0\tedge:derived\t^scripts/ord2a.test.sh\n' > "$SANDBOX/r-ord2-ba.rows"
row_order_stable() {
  local a b
  raudit "$SANDBOX/r-ord2-ab.rows" --all-refs; a="$(grep '^ref' <<<"$AOUT")"
  raudit "$SANDBOX/r-ord2-ba.rows" --all-refs; b="$(grep '^ref' <<<"$AOUT")"
  [[ -n "$a" && "$a" == "$b" ]] && grep -qF -- "$(printf 'scripts/ord2a.test.sh:1\t%s/1' "$(anchor_of 'cat data/ord2.txt')")" <<<"$a" && grep -qF -- "$(printf 'scripts/ord2b.test.sh:1\t%s/2' "$(anchor_of 'cat data/ord2.txt')")" <<<"$a"
}
chk "order: the same two rows of one label presented in both orders print identical ref lines (rows ordered by their first pattern)" row_order_stable

# row-order ties
printf 'AFFECTED_SELECTED\tscripts/tie\t0\tedge:derived\t^scripts/tie.test.sh|^walk/tiea.sh|^data/zlast.txt\nAFFECTED_SELECTED\tscripts/tie\t0\tedge:derived\t^scripts/tie.test.sh|^walk/tieb.sh|^data/alast.txt\n' > "$SANDBOX/r-tie-ab.rows"
printf 'AFFECTED_SELECTED\tscripts/tie\t0\tedge:derived\t^scripts/tie.test.sh|^walk/tieb.sh|^data/alast.txt\nAFFECTED_SELECTED\tscripts/tie\t0\tedge:derived\t^scripts/tie.test.sh|^walk/tiea.sh|^data/zlast.txt\n' > "$SANDBOX/r-tie-ba.rows"
row_ties() {
  local a b t; t="$(anchor_of 'cat data/tie.txt')"
  raudit "$SANDBOX/r-tie-ab.rows" --all-refs; a="$(grep '^ref' <<<"$AOUT")"
  raudit "$SANDBOX/r-tie-ba.rows" --all-refs; b="$(grep '^ref' <<<"$AOUT")"
  [[ -n "$a" && "$a" == "$b" ]] && grep -qF -- "$(printf 'walk/tiea.sh:1\t%s/2' "$t")" <<<"$a" && grep -qF -- "$(printf 'walk/tieb.sh:1\t%s/3' "$t")" <<<"$a"
}
chk "order: two rows of one label that share their first pattern and differ after it print identical ref lines in both row orders (the whole pattern list is the sort key; the walk files are ordinals 2 and 3)" row_ties
# walk-file closures, level order, directory suites, one walk file per extension, a runner trigger as a first pattern
{ rrow wcl '^walk/wc1.sh|^walk/wc2.sh'; rrow lvl '^walk/lva.sh|^walk/lvb.sh'; rrow lcl '^walk/lca.sh|^walk/lcb.sh'
  rrow ce "$(for x in "${CE_EXT[@]}"; do printf '^walk/ce.%s|' "$x"; done | sed 's/|$//')"
  printf 'AFFECTED_SELECTED\tdsw\t0\tedge:declared\t^dsw/|^walk/dsw.sh\n'
  printf 'AFFECTED_SELECTED\tscripts/rt\t0\tedge:derived\t^scripts/test-all.sh\n'; } > "$SANDBOX/r-reach2.rows"
raudit "$SANDBOX/r-reach2.rows" --all-refs; RO_R2="$AOUT"; A_LVL="$(anchor_of 'cat data/lvl.txt')"; A_LCL="$(anchor_of 'cat data/lcl.txt')"
chk "walk: a code pat named only by a library that a walk file sources is read (the closure of a walk file feeds the next level's naming)" has_ref "$RO_R2" scripts/wcl data/wcl.txt
chk "order: two walk files of one level are read in sorted path order, whatever order the suite names them (ordinals 1, 2 through the FILE column)" bash -c 'grep -qF -- "$(printf "ref\tscripts/lvl\tdata/lvl.txt\twalk/lva.sh:1\t$2/1\t")" <<<"$1" && grep -qF -- "$(printf "ref\tscripts/lvl\tdata/lvl.txt\twalk/lvb.sh:1\t$2/2\t")" <<<"$1"' _ "$RO_R2" "$A_LVL"
chk "order: the source closures of the walk files follow them in walk order (ya.sh is ordinal 1, yb.sh ordinal 2)" bash -c 'grep -qF -- "$(printf "ref\tscripts/lcl\tdata/lcl.txt\tlibY/ya.sh:1\t$2/1\t")" <<<"$1" && grep -qF -- "$(printf "ref\tscripts/lcl\tdata/lcl.txt\tlibY/yb.sh:1\t$2/2\t")" <<<"$1"' _ "$RO_R2" "$A_LCL"
chk "walk: every test file of a directory suite feeds the naming walk (only the SECOND file names walk/dsw.sh)" has_ref "$RO_R2" dsw data/dsw.txt
chk "walk: one walk file per CODE_EXT member is read (12 extensions, 12 paths reported)" bash -c 'for x in $2; do grep -qF -- "$(printf "ref\tscripts/ce\tdata/ce_%s.txt\t" "$x")" <<<"$1" || exit 1; done' _ "$RO_R2" "${CE_EXT[*]}"
chk "suite file: a runner trigger as a row's first pattern is not read as the suite (it is unaudited, with the pattern as the reason)" bash -c 'grep -qxF -- "$(printf "unaudited\tscripts/rt\t^scripts/test-all.sh")" <<<"$1"' _ "$RO_R2"
chk "tables: CODE_EXT is the 12 extensions the fixtures cover, and COMMENT_PREFIX holds exactly the comment-table extensions" python3 - "$SUT" "${CE_EXT[*]}" "${CM_HASH[*]} ${CM_SLASH[*]}" <<'PYTAB'
import importlib.util as u, sys
s = u.spec_from_file_location('m', sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
ok = sorted(m.CODE_EXT) == sorted("." + x for x in sys.argv[2].split()) and sorted(m.COMMENT_PREFIX) == sorted("." + x for x in sys.argv[3].split())
sys.exit(0 if ok else 1)
PYTAB

# ---- comment table
{ for x in "${CM_HASH[@]}" "${CM_SLASH[@]}" "${CM_NONE[@]}"; do printf 'AFFECTED_SELECTED\tcm/c.%s\t0\tedge:derived\t^cm/c.%s\n' "$x" "$x"; done
  for f in noext .hidden x.test.ts x.ts.snap link.txt tab.py crlf.ts q.sh ln.sh; do printf 'AFFECTED_SELECTED\tcm/%s\t0\tedge:derived\t^cm/%s\n' "$f" "$f"; done; } > "$SANDBOX/r-cm.rows"
raudit "$SANDBOX/r-cm.rows" --all-refs; RO_CM="$AOUT"
for x in "${CM_HASH[@]}"; do
  chk "comment table: .$x blanks its own # comment and keeps both the // line of the other language and the live line" bash -c '! grep -qF -- "$(printf "ref\t%s\t%s\t" "cm/c.$2" data/cm_own.txt)" <<<"$1" && grep -qF -- "$(printf "ref\t%s\t%s\t" "cm/c.$2" data/cm_other.txt)" <<<"$1" && grep -qF -- "$(printf "ref\t%s\t%s\t" "cm/c.$2" data/cm_live.txt)" <<<"$1"' _ "$RO_CM" "$x"
done
for x in "${CM_SLASH[@]}"; do
  chk "comment table: .$x blanks its own // comment and keeps both the # line of the other language and the live line" bash -c '! grep -qF -- "$(printf "ref\t%s\t%s\t" "cm/c.$2" data/cm_own.txt)" <<<"$1" && grep -qF -- "$(printf "ref\t%s\t%s\t" "cm/c.$2" data/cm_other.txt)" <<<"$1" && grep -qF -- "$(printf "ref\t%s\t%s\t" "cm/c.$2" data/cm_live.txt)" <<<"$1"' _ "$RO_CM" "$x"
done
for x in "${CM_NONE[@]}"; do
  chk "comment table: .$x strips nothing (its # and // lines are both reported)" bash -c 'grep -qF -- "$(printf "ref\t%s\t%s\t" "cm/c.$2" data/cm_own.txt)" <<<"$1" && grep -qF -- "$(printf "ref\t%s\t%s\t" "cm/c.$2" data/cm_other.txt)" <<<"$1"' _ "$RO_CM" "$x"
done
chk "comment table: an extensionless file and a dotfile strip nothing" bash -c 'for f in cm/noext cm/.hidden; do grep -qF -- "$(printf "ref\t%s\t%s\t" "$f" data/cm_own.txt)" <<<"$1" || exit 1; done' _ "$RO_CM"
chk "comment table: x.test.ts is a .ts file (its // comment is blanked), x.ts.snap is a .snap file (its // comment is kept)" bash -c '! grep -qF -- "$(printf "ref\t%s\t%s\t" cm/x.test.ts data/cm_own.txt)" <<<"$1" && grep -qF -- "$(printf "ref\t%s\t%s\t" cm/x.ts.snap data/cm_own.txt)" <<<"$1"' _ "$RO_CM"
chk "comment table: a symlink is read as its target (cm/link.txt -> c.sh: the # comment is blanked, the live line is reported)" bash -c '! grep -qF -- "$(printf "ref\t%s\t%s\t" cm/link.txt data/cm_own.txt)" <<<"$1" && grep -qF -- "$(printf "ref\t%s\t%s\t" cm/link.txt data/cm_live.txt)" <<<"$1"' _ "$RO_CM"
chk "comment table: a tab-indented # comment in a .py and a CRLF // comment in a .ts are blanked, the live line is kept" bash -c '! grep -qF -- "data/cm_own.txt" <<<"$(grep -P "^ref\tcm/(tab\.py|crlf\.ts)\t" <<<"$1")" && grep -qF -- "$(printf "ref\t%s\t%s\t" cm/tab.py data/cm_live.txt)" <<<"$1" && grep -qF -- "$(printf "ref\t%s\t%s\t" cm/crlf.ts data/cm_live.txt)" <<<"$1"' _ "$RO_CM"
chk "comment table: a # inside quotes and a \$# or \${#x} are not comments" bash -c 'grep -qF -- "$(printf "ref\t%s\t%s\t" cm/q.sh data/cm_quote.txt)" <<<"$1" && grep -qF -- "$(printf "ref\t%s\t%s\t" cm/q.sh data/cm_dollar.txt)" <<<"$1"' _ "$RO_CM"
chk "comment table: a blanked comment keeps its line number (the live line after two comments is cm/ln.sh:3)" bash -c 'grep -qF -- "$(printf "ref\t%s\t%s\tcm/ln.sh:3\t" cm/ln.sh data/cm_live.txt)" <<<"$1"' _ "$RO_CM"
[[ $(( ${#CM_HASH[@]} + ${#CM_SLASH[@]} + ${#CM_NONE[@]} )) -ge 17 ]] && pass "comment table floor: at least 17 extension rows ran" || fail "comment table shrank"

# ---- marker
raudit "$SANDBOX/r-walk.rows"
row_marker_fields() { grep -qE '^SOLEUR_PR_AFFECTED_AUDIT suites=[0-9]+ always_on=[0-9]+ audited=[0-9]+ unaudited=[0-9]+ gap_suites=[0-9]+ gap_refs=[0-9]+ accepted=[0-9]+ stale=[0-9]+ refs=[0-9]+ files_read=[0-9]+$' <<<"$AOUT"; }
chk "marker: the SOLEUR_PR_AFFECTED_AUDIT line keeps exactly its field list" row_marker_fields
{ rrow chain3; } > "$SANDBOX/r-chain-only.rows"; raudit "$SANDBOX/r-chain-only.rows"
chk "marker: files_read counts the closure (the suite and three libraries are 4 files, and no data file is read)" bash -c 'grep -q "files_read=4\$" <<<"$1"' _ "$AOUT"
{ rrow cls '^walk/cls.sh|^walk/cls.py|^walk/cls.ts'; } > "$SANDBOX/r-cls-only.rows"; raudit "$SANDBOX/r-cls-only.rows"
chk "marker: files_read counts the walk (the suite and the .sh, .py and .ts files reached through it are 4 files)" bash -c 'grep -q "files_read=4\$" <<<"$1"' _ "$AOUT"

# ---- edge credit parity with the selector's own functions
# The oracle is the REAL _NL line, _DEH_SRC/_DEH_N initialisers, _diff_edge_hit and _diff_touches of scripts/test-all.sh, cut out by content anchors
# and run under LC_ALL=C with the early-return controls (CI, SOLEUR_TEST_FORCE_ALL, --full, --enumerate, the fail-safe arms) neutralised. It is
# computed ONCE here; a mutant run re-runs only the python side. A renamed function FAILS the suite with a named reason, it never skips.
EDGE_ROWS=()
er() { EDGE_ROWS+=("$1"$'\t'"$2"$'\t'"$3"); }   # er <edge> <path> <name>; the empty entry is spelled <empty> (a tab is IFS whitespace and would collapse it)
er '^glob:docs-tree/**.sh' 'docs-tree/a/b/c.sh' 'wf-cross'          # * crosses /
er '^glob:docs-tree/**.sh' 'docs-tree/a/b/c.txt' 'wf-tail-rejects'
er '^glob:docs-tree/**.sh' 'other/a.sh' 'wf-head-rejects'
er '^glob:scripts/*.sh' 'scripts/x.sh' 'wf-plain'
er '^glob:scripts/*.sh' 'scripts/x.txt' 'wf-plain-rejects'
er '^glob:scripts/*.sh' 'scripts/x.sh.bak' 'wf-suffix-rejected'
er '^glob:scripts/*.txt' 'scripts/a.txt' 'wf-same-head-other-tail'
er '^glob:scripts/*.sh' 'scripts/b.sh' 'wf-same-head-first-tail-again'
er '^scripts/' 'scripts/a.sh' 'dir-prefix'
er '^scripts/' 'x/scripts/a.sh' 'dir-not-infix'
er '^scripts/a.sh' 'scripts/a.sh' 'exact'
er '^scripts/a.sh' 'scripts/a.sh.bak' 'exact-not-prefix'
er '^scripts/a.sh' 'x/scripts/a.sh' 'exact-not-suffix'
er '^scripts' 'scripts/a.sh' 'exact-no-slash-is-exact'
er '^apps/(auth)/p.tsx' 'apps/(auth)/p.tsx' 'exact-metachars'
er '^apps/(auth)/p.tsx' 'apps/auth/p.tsx' 'exact-metachars-not-a-regex'
er '^glob:scripts/**' 'scripts/a/b.sh' 'wf-star-tail-only'
er '^glob:scripts/*/lib/*.sh' 'scripts/x/lib/y.sh' 'wf-two-stars'
er '^glob:scripts/*/lib/*.sh' 'scripts/x/lib/y.txt' 'wf-two-stars-rejects'
er '^glob:scripts/*/a-b_c.sh' 'scripts/x/a-b_c.sh' 'wf-charset-allowed'
er '^glob:scripts/*.sh' 'scripts/a/b.sh' 'wf-star-crosses-in-a-plain-tail'
er '^scripts/' 'scripts/' 'dir-equals-itself'
er '^scripts/lib/' 'scripts/lib2/a.sh' 'dir-not-a-name-prefix'
er '^glob:scripts/*/a?.sh' 'scripts/x/zz.sh' 'mal-charset-question'
er '^glob:scripts/*/a[b].sh' 'scripts/x/zz.sh' 'mal-charset-bracket'
er '^glob:scripts/*/a b.sh' 'scripts/x/zz.sh' 'mal-charset-space'
er '^glob:scripts/*/a+.sh' 'scripts/x/zz.sh' 'mal-charset-plus'
er '^glob:/*/x.sh' 'lib/z.sh' 'mal-head-absolute'
er '^glob:./*/x.sh' 'lib/z.sh' 'mal-head-curdir'
er '^glob:../*/x.sh' 'lib/z.sh' 'mal-head-parent'
er '^glob:a//*/x.sh' 'lib/z.sh' 'mal-head-doubleslash'
er '^glob:a/./*/x.sh' 'lib/z.sh' 'mal-head-slashdotslash'
er '^glob:a/../*/x.sh' 'lib/z.sh' 'mal-head-slashdotdotslash'
er '^glob:scripts/a*/x.sh' 'lib/z.sh' 'mal-head-not-slash'
er '^glob:*.sh' 'lib/z.txt' 'mal-head-not-slash-empty'
er '^glob:' 'lib/z.sh' 'mal-head-not-slash-bare'
er '^glob:scripts/*/' 'lib/z.sh' 'mal-tail-slash'
er '^glob:scripts/' 'lib/z.sh' 'mal-tail-no-star'
er 'lib/x' 'a/lib/x.sh' 'noncaret-substring'
er 'lib/x' 'a/other/y.sh' 'noncaret-substring-rejects'
er 'scripts/a.sh' 'x/scripts/a.sh.bak' 'noncaret-is-a-substring-not-an-exact-name'
er 'glob:scripts/*.sh' 'scripts/a.sh' 'noncaret-glob-is-dead'
er '<empty>' 'scripts/a.sh' 'noncaret-empty-matches-all'
er '^' 'scripts/a.sh' 'caret-bare-matches-nothing'
printf '%s\n' "${EDGE_ROWS[@]}" > "$SANDBOX/edge.table"
extract_oracle() {  # extract_oracle <test-all.sh> <out>: the pieces by content anchors; non-zero with a named reason when one is missing
  local src="$1" out="$2" fn pat
  assert_fixture_dir "${out%/*}"
  : > "$out" || return 2
  for pat in "_NL=\$'\\n'" '_DEH_SRC=""' '_DEH_N=""'; do
    grep -m1 -xF -- "$pat" "$src" >> "$out" || { echo "oracle: the line $pat is not in $src" >&2; return 1; }
  done
  for fn in _diff_edge_hit _diff_touches; do
    awk -v fn="$fn" '$0 == fn "() {" { on = 1 } on { print } on && $0 == "}" { exit }' "$src" > "$out.fn"
    [[ -s "$out.fn" && "$(tail -n 1 "$out.fn")" == "}" ]] || { echo "oracle: the function $fn is not in $src" >&2; return 1; }
    cat "$out.fn" >> "$out"
  done
}
cat > "$SANDBOX/edge-run.sh" <<'EOS'
LC_ALL=C; export LC_ALL
unset CI SOLEUR_TEST_FORCE_ALL
source "$1"
_FULL_GATE=0; _ENUMERATE=0; _diff_detect_ok=1; _diff_head_ok=1; _pr_gate_canary_failed=0
i=0
while IFS=$'\t' read -r e p n; do
  i=$((i + 1)); [[ "$e" == "<empty>" ]] && e=""
  _diff_names="$p"
  if _diff_touches "$e"; then echo "$i 1"; else echo "$i 0"; fi
done < "$2"
EOS
EDGE_SRC="$SCRIPT_DIR/../../../scripts/test-all.sh"
extract_oracle "$EDGE_SRC" "$SANDBOX/edge-oracle.sh" && bash "$SANDBOX/edge-run.sh" "$SANDBOX/edge-oracle.sh" "$SANDBOX/edge.table" > "$SANDBOX/edge.oracle" 2>/dev/null
[[ "$(wc -l < "$SANDBOX/edge.oracle")" -eq "${#EDGE_ROWS[@]}" ]] && pass "edge oracle: the real _diff_touches answered all ${#EDGE_ROWS[@]} rows" || fail "edge oracle did not answer every row"
edge_py() {  # the python side: edge_hit of the SUT under test, one '<row> <0|1>' line per table row
  python3 - "$SUT" "$SANDBOX/edge.table" <<'PY'
import importlib.util as u, sys
s = u.spec_from_file_location('m', sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
for i, line in enumerate(open(sys.argv[2], encoding="utf-8").read().split("\n"), 1):
    if not line:
        continue
    e, p, n = line.split("\t")
    print(i, 1 if m.edge_hit("" if e == "<empty>" else e, p) else 0)
PY
}
row_edge() {  # row_edge <name prefix>: every table row whose name starts with the prefix agrees with the oracle, and at least one such row exists
  local i=0 n=0 line name got want out
  out="$(edge_py)" || return 1
  for line in "${EDGE_ROWS[@]}"; do
    i=$((i + 1)); name="${line##*$'\t'}"
    [[ "$name" == "$1"* ]] || continue
    n=$((n + 1)); got="$(sed -n "${i}p" <<<"$out")"; want="$(sed -n "${i}p" "$SANDBOX/edge.oracle")"
    [[ -n "$want" && "$got" == "$want" ]] || return 1
  done
  [[ "$n" -ge 1 ]]
}
EDGE_OUT="$(edge_py)"
i=0; for line in "${EDGE_ROWS[@]}"; do
  i=$((i + 1)); name="${line##*$'\t'}"
  chk "edge parity: row $name (edge ${line%%$'\t'*}) agrees with the selector's own _diff_touches" test "$(sed -n "${i}p" <<<"$EDGE_OUT")" = "$(sed -n "${i}p" "$SANDBOX/edge.oracle")"
done
[[ "${#EDGE_ROWS[@]}" -ge 44 ]] && pass "edge table floor: at least 44 rows ran" || fail "the edge table shrank to ${#EDGE_ROWS[@]} rows"
row_edge_charset() { row_edge mal-charset; }; row_edge_head_abs() { row_edge mal-head-absolute; }; row_edge_head_dot() { row_edge mal-head-curdir; }
row_edge_head_dotdot() { row_edge mal-head-parent; }; row_edge_head_dslash() { row_edge mal-head-doubleslash; }; row_edge_head_sds() { row_edge mal-head-slashdotslash; }
row_edge_head_sddsl() { row_edge mal-head-slashdotdotslash; }; row_edge_head_notslash() { row_edge mal-head-not-slash; }; row_edge_tail_slash() { row_edge mal-tail-slash; }
row_edge_tail_nostar() { row_edge mal-tail-no-star; }; row_edge_noncaret() { row_edge noncaret-; }; row_edge_cross() { row_edge wf-; }
row_edge_exact() { row_edge exact; }; row_edge_dir() { row_edge dir-; }
edge_oracle_missing_fn() {   # the harness row: an oracle extractor pointed at a copy whose _diff_edge_hit was renamed must FAIL with a named reason, never skip
  sed 's/^_diff_edge_hit() {/_diff_edge_hit_renamed() {/' "$EDGE_SRC" > "$SANDBOX/test-all-renamed.sh"
  local msg; msg="$(extract_oracle "$SANDBOX/test-all-renamed.sh" "$SANDBOX/edge-oracle-bad.sh" 2>&1)" && return 1
  grep -q 'oracle: the function _diff_edge_hit is not in' <<<"$msg"
}
chk "edge oracle: a copy of test-all.sh whose _diff_edge_hit was renamed FAILS the extraction with a named reason (it never skips)" edge_oracle_missing_fn
chk "edge credit has ONE function and ONE call site in the audit (a second implementation could drift from the differential)" bash -c '[[ "$(grep -cE "(^|[^_])edge_hit\(" "$1")" -eq 2 ]]' _ "$REAL_SUT"

# ---- cost: line events, never a clock (the cap raises OverflowError, so a mutant that loses a bound fails fast instead of hanging)
row_reach_cost() {
  python3 - "$SUT" "$SANDBOX" <<'PY' 2>&1
import importlib.util as u, os, sys, shutil, tempfile
s = u.spec_from_file_location('m', sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
base = tempfile.mkdtemp(prefix="reach-cost.", dir=sys.argv[2])
def put(root, rel, text):
    p = os.path.join(root, rel); os.makedirs(os.path.dirname(p) or root, exist_ok=True); open(p, "w").write(text)
def events(fn, cap):
    ev = [0]
    def local(frame, event, arg):
        if event == "line":
            ev[0] += 1
            if ev[0] > cap:
                raise OverflowError
        return local
    sys.settrace(lambda f, e, a: local)
    try:
        fn(); ok = True
    except OverflowError:
        ok = False
    finally:
        sys.settrace(None)
    return ok, ev[0]
def reach(root, tracked, pats, inputs):
    idx = m.PathIndex(tracked)
    return lambda: m.reach_texts(root, inputs, pats, idx, [])
def flat(name, n_named, width):
    root = os.path.join(base, name); os.makedirs(root)
    names = ["walk/w%d.sh" % i for i in range(n_named)]
    put(root, "s.sh", "".join("bash %s\n" % x for x in names))
    for x in names:
        put(root, x, "true\n")
    pats = ["^s.sh"] + ["^" + x for x in names] + ["^walk/pad%d.sh" % i for i in range(width - n_named)]
    return reach(root, set(names) | {"s.sh"} | {"walk/pad%d.sh" % i for i in range(width - n_named)}, pats, [os.path.join(root, "s.sh")])
def chain(name, n):
    root = os.path.join(base, name); os.makedirs(root)
    names = ["walk/c%d.sh" % i for i in range(n)]
    put(root, "s.sh", "bash %s\n" % names[0])
    for i, x in enumerate(names):
        put(root, x, ("bash %s\n" % names[i + 1]) if i + 1 < n else "true\n")
    return reach(root, set(names) | {"s.sh"}, ["^s.sh"] + ["^" + x for x in names], [os.path.join(root, "s.sh")])
bad = []
CAP = 2000000
ok4, e400 = events(flat("w400", 20, 400), CAP); ok40, e4000 = events(flat("w4000", 20, 4000), CAP)
if not (ok4 and ok40) or e4000 > 12 * e400:
    bad.append("width of pats (400 vs 4000 entries, 20 named): events %d -> %d (ok=%s/%s)" % (e400, e4000, ok4, ok40))
oka, e20 = events(flat("f20", 20, 20), CAP); okb, e200 = events(flat("f200", 200, 200), CAP)
if not (oka and okb) or e200 > 14 * e20:
    bad.append("files at one level (20 vs 200): events %d -> %d" % (e20, e200))
okc, ech = events(chain("c8", 8), CAP); okf, efl = events(flat("f8", 8, 8), CAP)
if not (okc and okf) or ech > 3 * efl:
    bad.append("levels (an 8-file chain vs 8 files at one level): events %d vs %d" % (ech, efl))
# the fan-out lattice: k libraries that each source every other one; a dropped visited set expands 5^8 paths and trips the cap
root = os.path.join(base, "lat"); os.makedirs(root); k = 6
for i in range(k):
    put(root, "lib/n%d.sh" % i, "".join("source lib/n%d.sh\n" % j for j in range(k) if j != i))
put(root, "s.sh", "source lib/n0.sh\n")
tracked = {"s.sh"} | {"lib/n%d.sh" % i for i in range(k)}
idx = m.PathIndex(tracked)
okl, el = events(lambda: m.suite_texts(root, [os.path.join(root, "s.sh")], idx, []), 60000)   # measured 9,081 events with the visited set; without it the same walk passes 3,000,000
if not okl:
    bad.append("fan-out lattice (k=6): the closure exceeded the line-event cap (%d events): the visited set is gone" % el)
shutil.rmtree(base, ignore_errors=True)
print("; ".join(bad))
sys.exit(1 if bad else 0)
PY
}
chk "cost: reach_texts is linear in the width of pats and does not multiply by files or levels, and the fan-out lattice stays under the line-event cap" row_reach_cost

# ---- the reach-differential generator: a fixture old SUT, the four boundaries, B=0, and no file written at the stop line
RDIFF="$(find "$SPECS" -path '*/receipts/reach-differential.py' 2>/dev/null | sort | head -1)"
row_rdiff_gen() {
  [[ -n "$RDIFF" && -f "$RDIFF" ]] || { echo "reach-differential.py not found under $SPECS" >&2; return 1; }
  local d="$SANDBOX/rdiff" b added gone resplit want out rc ncode nnon
  mkdir -p "$d" && printf 'AFFECTED_SELECTED\ts\t0\tedge:derived\t^s\n' > "$d/rows.txt"
  cat > "$d/stub.py" <<'PY'
import os
class C:
    def __init__(self, gaps, n): self.gaps, self.unaudited = gaps, ["u"] * n
    def ref_lines(self, label, path): return [("a", 1, "f.sh", 3, "t")]
def quote_field(s, comma=False): return s
CODE_EXT = frozenset((".sh",))
def load_rows(path, root): return open(path).read().split("\n")
def audit_census(root, rows, accept):
    n, extra, gone = int(os.environ["RD_B"]), int(os.environ["RD_ADDED"]), int(os.environ["RD_REMOVED"])
    base = ["p%d.sh" % i for i in range(n)]
    if SIDE == "old":
        return C({"s": base}, int(os.environ["RD_UNAUD_OLD"]))
    return C({"s": base[gone:] + ["x%d.%s" % (i, "sh" if i % 2 == 0 else "md") for i in range(extra)]}, int(os.environ["RD_UNAUD_NEW"]))
PY
  { printf 'SIDE = "old"\n'; cat "$d/stub.py"; } > "$d/old.py"
  { printf 'SIDE = "new"\n'; cat "$d/stub.py"; } > "$d/new.py"
  for b in 0 11; do
    for added in 0 5 6 10 11; do
      [[ "$b" -eq 0 && "$added" -gt 0 ]] && continue
      gone=0; [[ "$b" -eq 11 ]] && gone=3
      printf 'STALE\n' > "$d/out.tsv"; rc=0
      out="$(RD_B=$b RD_ADDED=$added RD_REMOVED=$gone RD_UNAUD_OLD=0 RD_UNAUD_NEW=0 python3 "$RDIFF" "$d" "$d/rows.txt" --old-sut "$d/old.py" --sut "$d/new.py" --out "$d/out.tsv" 2>&1)" || rc=$?
      resplit=$(( (b + 1) / 2 ))
      if (( added >= b )); then want=1; else want=0; fi
      [[ "$rc" -eq "$want" ]] || { echo "B=$b added=$added: rc=$rc, wanted $want" >&2; return 1; }
      if (( want == 1 )); then [[ ! -e "$d/out.tsv" && ! -e "$d/out.tsv.part" ]] || { echo "B=$b added=$added: a file (or the stale one) is left at the stop line" >&2; return 1; }; continue; fi
      if grep -q STALE "$d/out.tsv"; then echo "B=$b added=$added: the stale file was not replaced" >&2; return 1; fi
      head -n 1 "$d/out.tsv" | grep -qE "^# old_sut=[0-9a-f]+ tree=[^ ]+ rows_sha256=[0-9a-f]{64} base_pairs=$b new_pairs=$((b - gone + added)) added=$added removed=$gone\$" || { echo "B=$b added=$added: bad header" >&2; return 1; }
      [[ "$(sed -n '/^# added/,/^# removed/p' "$d/out.tsv" | grep -vc '^#')" -eq "$added" ]] || { echo "B=$b added=$added: the added section differs from the header" >&2; return 1; }
      [[ "$(sed -n '/^# removed/,$p' "$d/out.tsv" | grep -vc '^#')" -eq "$gone" ]] || { echo "B=$b added=$added: the removed section differs from the header" >&2; return 1; }
      ncode="$(awk -F'\t' '/^#/ {next} $3 == "code"' "$d/out.tsv" | wc -l)"; nnon="$(awk -F'\t' '/^#/ {next} $3 == "non-code"' "$d/out.tsv" | wc -l)"
      [[ "$ncode" -eq $(( (added + 1) / 2 + gone )) && "$nnon" -eq $(( added / 2 )) ]] || { echo "B=$b added=$added: path classes code=$ncode non-code=$nnon" >&2; return 1; }
      [[ "$(awk -F'\t' '/^#/ {next} $4 != "f.sh:3"' "$d/out.tsv" | wc -l)" -eq 0 && "$(awk -F'\t' '/^#/ {next} NF != 4' "$d/out.tsv" | wc -l)" -eq 0 ]] || { echo "B=$b added=$added: a data row has the wrong via or column count" >&2; return 1; }
      if (( added >= resplit )); then grep -q 'RE-SPLIT' <<<"$out" || { echo "B=$b added=$added: no re-split note" >&2; return 1; }
      else ! grep -q 'RE-SPLIT' <<<"$out" || { echo "B=$b added=$added: a re-split note below the line" >&2; return 1; }; fi
    done
  done
  printf 'STALE\n' > "$d/out.tsv"; rc=0   # a new audit with more unaudited suites than the old one stops; one with fewer does not
  RD_B=11 RD_ADDED=0 RD_REMOVED=3 RD_UNAUD_OLD=0 RD_UNAUD_NEW=1 python3 "$RDIFF" "$d" "$d/rows.txt" --old-sut "$d/old.py" --sut "$d/new.py" --out "$d/out.tsv" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 1 && ! -e "$d/out.tsv" ]] || { echo "more unaudited suites: rc=$rc or the file survived" >&2; return 1; }
  rc=0; RD_B=11 RD_ADDED=0 RD_REMOVED=3 RD_UNAUD_OLD=1 RD_UNAUD_NEW=0 python3 "$RDIFF" "$d" "$d/rows.txt" --old-sut "$d/old.py" --sut "$d/new.py" --out "$d/out.tsv" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 0 && -s "$d/out.tsv" ]] || { echo "fewer unaudited suites: rc=$rc or no file" >&2; return 1; }
}
chk "reach-differential: B=0 and the boundaries of B=11 (re-split line 6, stop line 11: nothing written and the stale file removed at the stop), header counts, the added and removed sections, the code and non-code split, the via column, and the unaudited guard" row_rdiff_gen
# ---- rows for the mutation harness: each re-runs the audit with $SUT and judges ONE property (a pristine run must be GREEN)
no_ref() { ! has_ref "$@"; }
row_rc_closure() { raudit "$SANDBOX/r-hop.rows" --all-refs; has_ref "$AOUT" scripts/chain3 data/deep.txt; }
row_rc_depth() { raudit "$SANDBOX/r-hop.rows" --all-refs; has_ref "$AOUT" scripts/depth9 data/d8.txt && no_ref "$AOUT" scripts/depth9 data/d9.txt; }
row_rc_twosrc() { raudit "$SANDBOX/r-hop.rows" --all-refs; has_ref "$AOUT" scripts/twosrc data/first.txt && has_ref "$AOUT" scripts/twosrc data/second.txt; }
row_rc_symlink() { raudit "$SANDBOX/r-hop.rows" --all-refs; has_ref "$AOUT" scripts/symlnk data/sa.txt && no_ref "$AOUT" scripts/symlnk data/sb.txt && has_ref "$AOUT" scripts/symreal data/sb.txt; }
row_rc_ops() { local i; raudit "$SANDBOX/r-ops.rows" --all-refs; for i in $(seq 1 "${#OPF[@]}"); do has_ref "$AOUT" "scripts/op$i" "data/op$i.txt" || return 1; done; no_ref "$AOUT" scripts/op3 data/decoy.txt; }
row_rc_neg_trigger() { raudit "$SANDBOX/r-neg.rows" --all-refs; ! grep -qF -- "zz/only-from-trigger.txt" <<<"$AOUT" && has_ref "$AOUT" scripts/negctl data/prose.txt; }
row_rc_neg_untracked() { raudit "$SANDBOX/r-neg.rows" --all-refs; no_ref "$AOUT" scripts/negu data/untr.txt && has_ref "$AOUT" scripts/negctl data/prose.txt; }
row_rc_neg_prose() { raudit "$SANDBOX/r-neg.rows" --all-refs; no_ref "$AOUT" scripts/negp data/prose.txt && no_ref "$AOUT" scripts/negc data/commented.txt && has_ref "$AOUT" scripts/negctl data/commented.txt; }
row_rc_unreadable() { raudit "$SANDBOX/r-neg.rows" --all-refs; [[ "$RC" -eq 1 ]] && grep -qxF -- "$(printf 'unaudited\tscripts/unr\tunreadable:libU/dang.sh')" <<<"$AOUT" && has_ref "$AOUT" scripts/unr2 data/unr2.txt; }
row_rc_unreadable_walk() { raudit "$SANDBOX/r-walk.rows" --all-refs; [[ "$RC" -eq 1 ]] && grep -qxF -- "$(printf 'unaudited\tscripts/unrw\tunreadable:walk/dangcode.sh')" <<<"$AOUT"; }
row_rc_walk_listed() { raudit "$SANDBOX/r-walk.rows" --all-refs; has_ref "$AOUT" scripts/wk data/w1.txt && no_ref "$AOUT" scripts/wk data/w2.txt && ! grep -qF -- "data/w3.txt" <<<"$AOUT"; }
row_rc_walk_data() { raudit "$SANDBOX/r-walk.rows" --all-refs; has_ref "$AOUT" scripts/wk data/w1.txt && ! grep -qE "data/w(4|5|6)\.txt" <<<"$AOUT"; }
row_rc_walk_depth() { raudit "$SANDBOX/r-walk.rows" --all-refs; has_ref "$AOUT" scripts/wchain data/n8.txt && ! grep -qF -- "data/n9.txt" <<<"$AOUT"; }
row_rc_walk_trigger() { raudit "$SANDBOX/r-walk.rows" --all-refs; has_ref "$AOUT" scripts/wtrig data/w1b.txt && ! grep -qF -- "zz/only-from-trigger.txt" <<<"$AOUT"; }
row_rc_walk_nodes() { raudit "$SANDBOX/r-walk.rows" --all-refs; has_ref "$AOUT" scripts/wgl data/w1b.txt && ! grep -qE "data/(g1|dd1|g2)\.txt" <<<"$AOUT"; }
row_rc_cls() { raudit "$SANDBOX/r-walk.rows" --all-refs; local p; for p in data/cls_sh.txt data/cls_py.txt data/cls_ts.txt; do has_ref "$AOUT" scripts/cls "$p" || return 1; done; }
row_rc_walk_closure() { raudit "$SANDBOX/r-walk.rows" --all-refs; has_ref "$AOUT" scripts/wsrc data/wsrc.txt; }
row_rc_order() {
  local a; raudit "$SANDBOX/r-ord.rows" --all-refs; a="$(anchor_of 'cat data/ord.txt')"
  grep -qF -- "$(printf 'ref\tscripts/ord\tdata/ord.txt\tscripts/ord.test.sh:1\t%s/1\t' "$a")" <<<"$AOUT" && grep -qF -- "$(printf 'ref\tscripts/ord\tdata/ord.txt\tlibO/lib.sh:1\t%s/2\t' "$a")" <<<"$AOUT" && grep -qF -- "$(printf 'ref\tscripts/ord\tdata/ord.txt\twalk/ordw.sh:1\t%s/3\t' "$a")" <<<"$AOUT"
}
row_rc_order_rows() { row_order_stable; }
row_rc_lab() { row_lab; }
row_rc_seen() { row_seen; }
row_cm_hash() { local x; raudit "$SANDBOX/r-cm.rows" --all-refs; for x in "${CM_HASH[@]}"; do no_ref "$AOUT" "cm/c.$x" data/cm_own.txt && has_ref "$AOUT" "cm/c.$x" data/cm_other.txt && has_ref "$AOUT" "cm/c.$x" data/cm_live.txt || return 1; done; }
row_cm_slash() { local x; raudit "$SANDBOX/r-cm.rows" --all-refs; for x in "${CM_SLASH[@]}"; do no_ref "$AOUT" "cm/c.$x" data/cm_own.txt && has_ref "$AOUT" "cm/c.$x" data/cm_other.txt && has_ref "$AOUT" "cm/c.$x" data/cm_live.txt || return 1; done; }
row_cm_none() { local x; raudit "$SANDBOX/r-cm.rows" --all-refs; for x in "${CM_NONE[@]}"; do has_ref "$AOUT" "cm/c.$x" data/cm_own.txt && has_ref "$AOUT" "cm/c.$x" data/cm_other.txt || return 1; done; has_ref "$AOUT" cm/noext data/cm_own.txt && has_ref "$AOUT" cm/.hidden data/cm_own.txt; }
row_cm_names() { raudit "$SANDBOX/r-cm.rows" --all-refs; no_ref "$AOUT" cm/x.test.ts data/cm_own.txt && has_ref "$AOUT" cm/x.ts.snap data/cm_own.txt && no_ref "$AOUT" cm/link.txt data/cm_own.txt && has_ref "$AOUT" cm/link.txt data/cm_live.txt; }
row_cm_shapes() { raudit "$SANDBOX/r-cm.rows" --all-refs; no_ref "$AOUT" cm/tab.py data/cm_own.txt && no_ref "$AOUT" cm/crlf.ts data/cm_own.txt && has_ref "$AOUT" cm/q.sh data/cm_quote.txt && has_ref "$AOUT" cm/q.sh data/cm_dollar.txt && grep -qF -- "$(printf 'ref\tcm/ln.sh\tdata/cm_live.txt\tcm/ln.sh:3\t')" <<<"$AOUT"; }
row_hop_redos() {   # one long identifier-like token after a source keyword must stay linear: a quadratic match runs for minutes, so it is killed at 8 s
  timeout -k 2 8 python3 - "$SUT" <<'PYRE' 2>&1
import importlib.util as u, sys
s = u.spec_from_file_location('m', sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
for lead in ("source $", "source ${", ". $", 'source "$'):
    m.SOURCE_HOP.search(lead + "A" * 100000)
hit = m.SOURCE_HOP.search('source "$SCRIPT_DIR/x.sh"')
sys.exit(0 if hit and hit.group(1) == "$SCRIPT_DIR" and hit.group(2) == "/x.sh" else 1)
PYRE
}
chk "cost: one 100,000-character token after a source keyword matches in linear time (and a real operand still parses)" row_hop_redos
row_rc_ties() { row_ties; }
row_rc_wcl() { raudit "$SANDBOX/r-reach2.rows" --all-refs; has_ref "$AOUT" scripts/wcl data/wcl.txt; }
row_rc_lvl() { local a; a="$(anchor_of 'cat data/lvl.txt')"; raudit "$SANDBOX/r-reach2.rows" --all-refs
  grep -qF -- "$(printf 'ref\tscripts/lvl\tdata/lvl.txt\twalk/lva.sh:1\t%s/1\t' "$a")" <<<"$AOUT" && grep -qF -- "$(printf 'ref\tscripts/lvl\tdata/lvl.txt\twalk/lvb.sh:1\t%s/2\t' "$a")" <<<"$AOUT"; }
row_rc_lcl() { local a; a="$(anchor_of 'cat data/lcl.txt')"; raudit "$SANDBOX/r-reach2.rows" --all-refs
  grep -qF -- "$(printf 'ref\tscripts/lcl\tdata/lcl.txt\tlibY/ya.sh:1\t%s/1\t' "$a")" <<<"$AOUT" && grep -qF -- "$(printf 'ref\tscripts/lcl\tdata/lcl.txt\tlibY/yb.sh:1\t%s/2\t' "$a")" <<<"$AOUT"; }
row_rc_dsw() { raudit "$SANDBOX/r-reach2.rows" --all-refs; has_ref "$AOUT" dsw data/dsw.txt; }
row_rc_ce() { local x; raudit "$SANDBOX/r-reach2.rows" --all-refs; for x in "${CE_EXT[@]}"; do has_ref "$AOUT" scripts/ce "data/ce_$x.txt" || return 1; done; }
row_rc_rt() { raudit "$SANDBOX/r-reach2.rows"; grep -qxF -- "$(printf 'unaudited\tscripts/rt\t^scripts/test-all.sh')" <<<"$AOUT"; }
# --- end of the reach rows; the mutation rows for them are at the end of the mutation section
# ---------------------------------------------------------------------------------------------------------------------
echo "== mutation rows (each edit lands once, leaves valid python, leaves the row GREEN on the pristine SUT, and the named row must then FAIL)"
MUT_RUN=0; MUT_KILLED=0
declare -A PRISTINE_OK=() PRISTINE_RC4=()
CRASH_IS_THE_POINT=" row_acc_isdir:accept-os-error-unmapped row_cp_big:cp-overflow row_sym:read-oserror-unmapped "   # row:mutant pairs whose property IS "does not crash": an unmapped OSError is rc 4 instead of rc 3; the float-product cp_upper overflows
crash_seen() {  # crash_seen <row output file>: rc 4 was logged, a Traceback printed, or main() reported an internal error
  grep -qx 4 "$RCLOG" || grep -q 'Traceback (most recent call last)\|replay: internal error' "$1"
}
MUT_RESULT=""
mutant_outcome() {  # mutant_outcome <name> <old> <new> <row>: sets MUT_RESULT = killed | survived | invalid | crashed | row-red-on-pristine | edit-failed
  # killed = the row went RED on a mutant that still imports and still answers; a mutant that CRASHES (does not import, or a run
  # exits rc 4 / prints a Traceback where the pristine run did not) is `crashed`, never a kill: a crash fails every row, so it proves nothing
  local name="$1" old="$2" new="$3" row="$4" m="$SANDBOX/mut-$1.py" got mout="$SANDBOX/mut-out.txt"
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
    : > "$RCLOG"; SUT="$REAL_SUT"; "$row" >"$mout" 2>&1 || { MUT_RESULT="row-red-on-pristine"; return 0; }
    PRISTINE_OK[$row]=1; if crash_seen "$mout"; then PRISTINE_RC4[$row]=1; fi
  fi
  python3 -c 'import importlib.util as u,sys; s=u.spec_from_file_location("m",sys.argv[1]); mod=u.module_from_spec(s); s.loader.exec_module(mod)' "$m" >/dev/null 2>&1 || { MUT_RESULT=crashed; return 0; }   # does not import
  : > "$RCLOG"; SUT="$m"; "$row" >"$mout" 2>&1; got=$?; SUT="$REAL_SUT"
  if [[ "$got" -eq 0 ]]; then MUT_RESULT=survived
  elif [[ -z "${PRISTINE_RC4[$row]:-}" && "$CRASH_IS_THE_POINT" != *" $row:$name "* ]] && crash_seen "$mout"; then MUT_RESULT=crashed
  else MUT_RESULT=killed; fi
}
declare -A MUT_SIGS=()
mutate() {  # mutate <name> <old> <new> <row>
  local sig
  mutant_outcome "$@"
  MUT_RUN=$((MUT_RUN + 1))
  if [[ "$MUT_RESULT" = killed || "$MUT_RESULT" = survived ]]; then   # the identity of a mutant is the MUTATED FILE it produced (and the row), not the spelling of its edit
    sig="$(sha256sum "$SANDBOX/mut-$1.py" | cut -c1-64)/$4"
    if [[ -n "${MUT_SIGS[$sig]:-}" ]]; then fail "mutant $1 repeats mutant ${MUT_SIGS[$sig]} (same mutated file, same row): a renamed duplicate adds no kill"; return 0; fi
    MUT_SIGS[$sig]="$1"
  fi
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
row_worst_bound() { collect_once; local o; o="$(run_sut aggregate "$OUT" --commits-only 2>&1)"; grep -q "cp95_upper_on_worst_case=$(python3 -c "print('%.2f'%(100*$(python3 "$REAL_SUT" cp-upper 3 7)))")%" <<<"$o"; }
row_flake_same_files() { local o; o="$(run_sut aggregate "$FC" 2>&1)"; grep -q '"unverified": 3' <<<"$o"; }
row_flake_same_pr() { local o; o="$(run_sut aggregate "$FA" 2>&1)"; grep -q '"unverified": 3' <<<"$o"; }
row_flake_escape() { local o; o="$(run_sut aggregate "$FB" 2>&1)"; grep -q 'attributable=1/4' <<<"$o"; }
row_verdict_fail() { [[ "$(py_sut verdict --a pass --b fail --c pass --d pass)" == "computed=NO-GO "* ]]; }
row_unmeasured() { [[ "$(py_sut verdict --a pass --b pass --c unmeasured --d pass)" == "computed=UNDECIDED reason=incomplete" ]]; }
row_band_b() { py_sut verdict --a pass --b within-10% --c pass --d pass >/dev/null 2>&1; [[ $? -eq 2 ]]; }
row_selftest_line() { collect_once; [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[2]}" '.failing[0].suites|join(",")')" = scripts/suitey ]]; }
row_sel_error() { rm -rf "$OUT"; mkdir -p "$OUT"; RUN_ENV=(PR_AFFECTED_REPLAY_TEST_ALL="$BIN/sel-fail.sh"); run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" >/dev/null 2>&1; RUN_ENV=(); [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[6]}" .reason)" == selection:* ]]; }   # through run_sut: a crash is logged
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
row_hang() { REPO_NAME="$R2"; rm -rf "$OUT"; mkdir -p "$OUT"; RUN_ENV=(PR_AFFECTED_REPLAY_GH_TIMEOUT=1); run_sut collect --out "$OUT" --commits 2 --chunk 1/1 --repo "$R2" >/dev/null 2>&1; RUN_ENV=(); REPO_NAME=""; [[ "$(unit_field "$OUT/units-commits-1-of-1.jsonl" "${C[5]}" .reason)" == *"timed out"* ]]; }
row_torn() { collect_once; printf '{"kind": "commit", "sha": "torn' >> "$OUT/units-commits-1-of-1.jsonl"; run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" >/dev/null 2>&1; jq -c . "$OUT/units-commits-1-of-1.jsonl" >/dev/null 2>&1 && [[ "$(jq -s length "$OUT/units-commits-1-of-1.jsonl")" -eq 7 ]]; }
row_reclassify() { collect_once; : > "$GHLOG"; run_sut collect --out "$OUT" --commits 7 --chunk 1/1 --repo "$R" --reclassify >/dev/null 2>&1; [[ "$(reqs "$(runs_path "${C[0]}")")" -eq 0 && "$(reqs "$(runs_path "${C[2]}")")" -ge 1 ]]; }
row_cp_big() { local v; v="$(py_sut cp-upper 300 2000 2>&1)" || return 1; awk -v v="$v" 'BEGIN{exit !(v>0.16 && v<0.18)}'; }
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
row_window() { local o; o="$(run_sut ejections --out "$SANDBOX/ej-win" --commits 7 --repo "$R" 2>&1)"; grep -q 'window 2031-01-02T12:00:00Z\.\.2031-01-08T12:00:00Z' <<<"$o"; }
row_rate_limit() { REPO_NAME="$R3"; rm -rf "$OUT"; mkdir -p "$OUT"; : > "$GHLOG"; run_sut collect --out "$OUT" --commits 1 --chunk 1/1 --repo "$R3" >/dev/null 2>&1; local n; n="$(grep -c "^REQ $(keyof "$(runs_path "${C[6]}")")\$" "$GHLOG")"; REPO_NAME=""; [[ "$n" -eq 3 ]]; }
row_agg_no_ejections() { run_sut aggregate "$FE" >/dev/null 2>&1; [[ $? -eq 2 ]]; }
row_agg_gap() { run_sut aggregate "$FG" >/dev/null 2>&1; [[ $? -eq 2 ]]; }
row_agg_dup() { run_sut aggregate "$FH" >/dev/null 2>&1; [[ $? -eq 2 ]]; }
row_agg_expect() { run_sut aggregate "$FD" --expect-commits 4 >/dev/null 2>&1; [[ $? -eq 2 ]]; }
row_agg_arith() { local o; o="$(run_sut aggregate "$FD" 2>&1)"; grep -q 'mean_skipped_suite_min=20.00 se=5.77 selector_min=1.29 net_mean=18.71 net_mean_plus_2se=30.26' <<<"$o"; }
row_agg_point() { local o; o="$(run_sut aggregate "$FD" 2>&1)"; grep -q 'unverified_as_escape=1/4 (point 25.00%)' <<<"$o"; }
row_tsv() { run_sut aggregate "$FT" --out "$SANDBOX/tsv.txt" >/dev/null 2>&1; [[ "$(awk -F'\t' 'NF != 9 { bad++ } END { print bad + 0 }' "$SANDBOX/tsv.txt.tsv")" = 0 ]]; }
row_internal() { local e rc; e="$(run_sut aggregate "$FI" 2>&1 >/dev/null)"; rc=$?; [[ "$rc" -eq 4 ]] && grep -q 'internal error' <<<"$e"; }
row_two_prs() { local o; o="$(run_sut aggregate "$FP" 2>&1)"; grep -q '"unverified": 3' <<<"$o"; }
row_audit_parens() { audit "$SANDBOX/audit-parens.rows"; [[ "$RC" -eq 0 ]]; }
row_audit_exact() { audit "$SANDBOX/audit-exact.rows"; [[ "$RC" -eq 1 ]] && grep -q 'scripts/x.sh.bak' <<<"$AOUT"; }
row_audit_many() { audit "$SANDBOX/audit-many.rows" --all-refs; grep -P -q '^gap\tscripts/many\t8\t([^,]+,){7}[^,]+$' <<<"$AOUT"; }
row_audit_short() { audit "$SANDBOX/audit-short.rows"; [[ "$RC" -eq 1 ]] && grep -q 'short-row' <<<"$AOUT"; }
row_audit_sel_fail() { RUN_ENV=(PR_AFFECTED_REPLAY_TEST_ALL="$BIN/sel-partial.sh"); run_sut audit --root "$AREPO" >/dev/null 2>&1; local rc=$?; RUN_ENV=(); [[ "$rc" -eq 3 ]]; }
row_bad_env() { PR_AFFECTED_REPLAY_GH_TIMEOUT=abc py_sut cp-upper 0 10 >/dev/null 2>&1; [[ $? -eq 2 ]]; }
row_cp_edge() { [[ "$(py_sut cp-upper 7 7)" = 1.000000 ]]; }
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
mutate audit-comments-counted '    return "\n".join("" if line.lstrip().startswith(prefix) else line for line in lines)' '    return "\n".join(lines)' row_audit_comment
mutate audit-runner-not-excused 'f != suite and f not in own and f not in RUNNER_TRIGGERS)' 'f != suite and f not in own)' row_audit_runner
mutate audit-gap-blind 'if not any(edge_hit(pt, r) for pt in pats)]' 'if False]' row_audit_bad
mutate audit-zero-suites 'if c.suites == 0:' 'if False:' row_audit_zero
mutate audit-unread-suite-clean '            else:
                for d in dead:
                    c.add_unaudited(label, d)' '            else:
                pass' row_audit_ghost
mutate audit-always-on-audited '        if g["always_on"]:' '        if False:' row_audit_always
mutate audit-edge-as-regex '    if e.endswith("/"):
        return path.startswith(e)
    return path == e' '    return re.search(e, path) is not None' row_audit_parens
mutate audit-edge-as-regex-exact '    if e.endswith("/"):
        return path.startswith(e)
    return path == e' '    return re.search(e, path) is not None' row_audit_exact
mutate audit-glob-not-a-glob '    if e.startswith("glob:"):' '    if False:' row_audit_glob
mutate audit-all-refs-ignored '(found if a.all_refs else found[:6])' '(found[:6])' row_audit_many
mutate audit-short-row-skipped '            c.add_unaudited(label, "short-row")' '            pass' row_audit_short
mutate audit-selector-rc-ignored '    if sp.returncode != 0:' '    if False:' row_audit_sel_fail
mutate bad-timeout-env-traceback 'except ValueError as _e:' 'except KeyError as _e:' row_bad_env
mutate ejections-manifest-optional '        if not os.path.exists(meta_path):' '        if not os.path.exists(meta_path):
            return
        if False:' row_agg_no_meta
mutate ejections-count-unchecked '        if have != meta["refused"]:' '        if False:' row_agg_short
mutate accepted-unread-counted-audited 'return len(self.labels - self.always_on_labels - {u[0] for u in self.unaudited} - self.accepted_unread_labels)' 'return len(self.labels - self.always_on_labels - {u[0] for u in self.unaudited})' row_accept_dir
mutate accept-ignored '        if lines and all((a[0], a[1]) in want for a in lines):' '        if False:' row_accept_ok
mutate accept-without-reason '        if not re.match(r"^false-positive: \S", f[4]):' '        if False:' row_accept_badreason
mutate cleared-by-failed-run 'if o["created_at"] > r["created_at"] and o["conclusion"] == "success":' 'if o["created_at"] > r["created_at"]:' row_cleared_by_failed
mutate cleared-read-error-as-cleared '                        except ReadError:
                            return False' '                        except ReadError:
                            return True' row_cleared_read_error
mutate suite-job-narrowed 'SUITE_JOB = re.compile(r"^test-(scripts|webplat|bun)( \(|$)|^test-scripts-heavy( \(|$)")' 'SUITE_JOB = re.compile(r"^test-scripts( \(|$)")' row_shard_families
mutate pull-request-event-counted 'FULL_EVENTS = ("merge_group", "push")' 'FULL_EVENTS = ("merge_group", "push", "pull_request")' row_full_events
mutate commit-files-first-page-only '    files = []
    for d in docs:' '    files = []
    for d in docs[:1]:' row_two_page
mutate commit-file-cap-ignored '    if len(files) >= COMMIT_FILES_CAP:' '    if False:' row_file_cap
mutate timed-out-not-a-unit 'r["conclusion"] != "success"' 'r["conclusion"] == "failure"' row_timed_out
mutate blob-sha-optional '            if not x.get("sha"):' '            x.setdefault("sha", "")
            if False:' row_no_sha
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

# PR1: the component-boundary scan, memoisation, directory suites and the anchor-keyed accept rows
mutate scan-drops-last-char 'r = index.refs[got[0]] = scan_views(index, got[1], got[2])' 'r = index.refs[got[0]] = scan_views(index, got[1][:-1], got[2][:-1])' row_scan_eol
mutate scan-stops-at-first-member '                    out.add(leaf)' '                    out.add(leaf)
                    return out' row_scan_two
mutate scan-component-charset-limited '                    nxt = t.get("")
                    break
                t = t.get(ch)' '                    nxt = t.get("")
                    break
                t = t.get(ch) if ch.isalnum() or ch in "._-" else None' row_scan_charset
mutate scan-boundary-ignored 'WORD_CHARS = "A-Za-z0-9_"' 'WORD_CHARS = "\x00"' row_scan_mid
mutate scan-boundary-rejects-after-slash 'WORD_CHARS = "A-Za-z0-9_"' 'WORD_CHARS = "A-Za-z0-9_/"' row_scan_suffix
mutate scan-boundary-rejects-after-tab 'WORD_CHARS = "A-Za-z0-9_"' 'WORD_CHARS = "A-Za-z0-9_\t"' row_scan_tab
mutate scan-escape-not-a-boundary 'ESCAPE = re.compile(r"\\(?:[abefnrtv]|' 'ESCAPE = re.compile(r"\\(?:[ABEFNRTV]|' row_scan_esc
mutate scan-memo-keyed-on-basename '    r = index.refs.get(got[0])
    if r is None:
        r = index.refs[got[0]] = scan_views(index, got[1], got[2])' '    r = index.refs.get(os.path.basename(got[0]))
    if r is None:
        r = index.refs[os.path.basename(got[0])] = scan_views(index, got[1], got[2])' row_scan_basename
mutate scan-memo-poisoned-by-own-path '        named |= refs_of(index, got)' '        named |= refs_of(index, got)
        index.refs[got[0]] = index.refs[got[0]] - {os.path.relpath(p, root) for p in inputs}' row_scan_poison
mutate scan-library-hop-dropped 'for m in SOURCE_HOP.finditer(index.raws[real])]' 'for m in []]' row_rc_closure   # re-aimed: row_scan_basename lists its libraries in pats, so the naming walk reads them even when no hop is followed
mutate scan-memo-bypassed '    r = index.refs.get(got[0])' '    r = None' row_scan_memo
mutate scan-every-offset 'for m in index.start.finditer(text):' 'for m in re.finditer("", text):' row_scan_ops
mutate scan-brute-force-find '    for m in index.start.finditer(text):' '    for p in index.paths:
        if text.find(p) >= 0:
            out.add(p)
    index.ops += len(text) // 4
    for m in []:' row_scan_ops
mutate scan-brute-force-membership '    for m in index.start.finditer(text):' '    return {p for p in index.paths if p in text}
    for m in index.start.finditer(text):' row_scan_ops
mutate scan-hidden-quadratic-in-paths '        cur, node = m.start(), index.root' '        for _p in index.paths:
            _p.startswith("zz")
        cur, node = m.start(), index.root' row_scan_ops
mutate scan-hidden-quadratic-in-width '    for m in index.start.finditer(text):' '    _tl = sorted({x.split("/")[0] for x in index.paths})
    for m in index.start.finditer(text):
        for _n in _tl:
            _n.startswith("zz")' row_scan_ops
mutate comment-trailing-stripped '    return "\n".join("" if line.lstrip().startswith(prefix) else line for line in lines)' '    return "\n".join("" if line.lstrip().startswith(prefix) else re.sub(r"\s#.*$", "", line) for line in lines)' row_scan_shapes
mutate comment-tab-indent-kept 'line.lstrip().startswith(prefix)' 'line.startswith(prefix)' row_scan_shapes
mutate comment-line-deleted '    return "\n".join("" if line.lstrip().startswith(prefix) else line for line in lines)' '    return "\n".join(line for line in lines if not line.lstrip().startswith(prefix))' row_scan_refs
mutate comment-split-on-any-line-break 'lines = text.replace("\r\n", "\n").split("\n")' 'lines = text.replace("\r\n", "\n").splitlines()' row_scan_vt
mutate dir-suite-unaudited '    return files or None' '    return None' row_dir_scan
mutate dir-suite-no-underscore-tests 'BUN_TEST = re.compile(r"[._](?:test|spec)' 'BUN_TEST = re.compile(r"[.](?:test|spec)' row_dir_scan
mutate dir-suite-no-spec-files 'BUN_TEST = re.compile(r"[._](?:test|spec)' 'BUN_TEST = re.compile(r"[._](?:test)' row_dir_scan
mutate dir-suite-prefix-ignored 'index.under(d) if BUN_TEST.search(f)' 'index.under("") if BUN_TEST.search(f)' row_dir_nested
mutate dir-suite-no-jsx '(?:js|jsx|ts|tsx|mjs|cjs|mts|cts)$' '(?:js|ts|tsx|mjs|cjs|mts|cts)$' row_dir_scan
mutate dir-suite-no-mjs '(?:js|jsx|ts|tsx|mjs|cjs|mts|cts)$' '(?:js|jsx|ts|tsx|cjs|mts|cts)$' row_dir_scan
mutate dir-suite-no-cjs '(?:js|jsx|ts|tsx|mjs|cjs|mts|cts)$' '(?:js|jsx|ts|tsx|mjs|mts|cts)$' row_dir_scan
mutate dir-suite-no-mts '(?:js|jsx|ts|tsx|mjs|cjs|mts|cts)$' '(?:js|jsx|ts|tsx|mjs|cjs|cts)$' row_dir_scan
mutate dir-suite-no-cts '(?:js|jsx|ts|tsx|mjs|cjs|mts|cts)$' '(?:js|jsx|ts|tsx|mjs|cjs|mts)$' row_dir_scan
mutate dir-suite-snapshot-scanned '|mts|cts)$")' '|mts|cts)")' row_dir_scan
mutate dir-suite-any-name-ending-in-test 'BUN_TEST = re.compile(r"[._](?:test|spec)' 'BUN_TEST = re.compile(r"(?:test|spec)' row_dir_scan
mutate dir-suite-unreadable-member-unreported '            c.add_unaudited(label, "unreadable:" + ",".join(sorted(quote_field(os.path.relpath(b, root), True) for b in bad)), True)' '            pass' row_dir_dangling
mutate dir-suite-unreadable-member-aborts '        if path not in bad:
            bad.append(path)' '        raise' row_dir_dangling
mutate dir-suite-star-row-accepts-unreadable '"star-row-unreadable-members" if bad else "star-row-readable-suite"' '"star-row-readable-suite"' row_dir_dangling_star
mutate tracked-listing-not-nul-separated '["git", "ls-files", "-z"]' '["git", "ls-files"]' row_scan_nonascii
mutate tracked-length-filter-restored 'f not in own and f not in RUNNER_TRIGGERS)' 'f not in own and f not in RUNNER_TRIGGERS and len(f) > 6)' row_scan_short
mutate normalise-drops-octal-escapes '|0[0-7]{0,3}|x[0-9A-Fa-f]{1,2}|' '|x[0-9A-Fa-f]{1,2}|' row_scan_escapes
mutate normalise-drops-hex-escapes '|x[0-9A-Fa-f]{1,2}|u[0-9A-Fa-f]{4})' '|u[0-9A-Fa-f]{4})' row_scan_escapes
mutate normalise-drops-unicode-escapes '|u[0-9A-Fa-f]{4})")' ')")' row_scan_escapes
mutate normalise-drops-bell '(?:[abefnrtv]|' '(?:[befnrtv]|' row_scan_escapes
mutate normalise-drops-escape-letter '(?:[abefnrtv]|' '(?:[abfnrtv]|' row_scan_escapes
mutate normalise-drops-return-escape '(?:[abefnrtv]|' '(?:[abefntv]|' row_scan_oracle
mutate normalise-drops-short-options 'full = SHORT_OPTION.sub(lambda m: " " * len(m.group(0)), ESCAPE.sub(lambda m: " " * len(m.group(0)), text))' 'full = ESCAPE.sub(lambda m: " " * len(m.group(0)), text)' row_scan_escapes
mutate scan-light-view-dropped '    return (text, text) if full == text else (full, text)' '    return (text, text) if full == text else (full, full)' row_adj
mutate word-without-underscore 'WORD_CHARS = "A-Za-z0-9_"' 'WORD_CHARS = "A-Za-z0-9"' row_scan_prec
mutate word-without-digits 'WORD_CHARS = "A-Za-z0-9_"' 'WORD_CHARS = "A-Za-z_"' row_scan_prec
mutate word-with-hyphen 'WORD_CHARS = "A-Za-z0-9_"' 'WORD_CHARS = "A-Za-z0-9_-"' row_scan_prec
mutate word-without-underscore-in-boundary-only '    return i == 0 or WORD.match(text[i - 1]) is None' '    return i == 0 or re.match("[A-Za-z0-9]", text[i - 1]) is None' row_bnd_mid
mutate boundary-always-true '    return i == 0 or WORD.match(text[i - 1]) is None' '    return True' row_bnd_mid
mutate boundary-no-line-start-case '    return i == 0 or WORD.match(text[i - 1]) is None' '    return WORD.match(text[i - 1]) is None' row_bnd_start
mutate boundary-start-only '    return i == 0 or WORD.match(text[i - 1]) is None' '    return i == 0' row_bnd_orig
mutate anchor-hashes-the-normalised-line '                    out.append((q, no, wl[no - 1]))' '                    out.append((q, no, fl[no - 1]))' row_bnd_orig
mutate ref-line-number-off-by-one 'out.append((a, count[a], q, no, text))' 'out.append((a, count[a], q, no + 1, text))' row_scan_refs
mutate census-drops-the-selector-summary '                c.extra.append(line)' '                pass' row_census
mutate accept-any-line-suffices '        if lines and all((a[0], a[1]) in want for a in lines):' '        if lines and any((a[0], a[1]) in want for a in lines):' row_acc_dup1
mutate accept-ordinal-ignored 'out.append((a, count[a], q, no, text))' 'out.append((a, 1, q, no, text))' row_acc_dup1
mutate accept-whitespace-significant 'text = " ".join(written.split())' 'text = written.strip()' row_acc_ws
mutate accept-stale-anchor-tolerated 'stale += stale_entries(suite, path, [e for e in entries if (e[0], e[1]) not in live], "anchor-not-live")' 'pass' row_acc_anchor
mutate accept-untracked-path-tolerated '        elif path not in tracked:' '        elif False:' row_acc_untracked
mutate accept-not-a-gap-tolerated '        elif path not in miss_set:' '        elif False:' row_acc_declared
mutate accept-unregistered-suite-tolerated '            why = "suite-unregistered"' '            continue' row_acc_phantom
mutate accept-always-on-suite-tolerated '        elif c.registered[suite] == "always_on":' '        elif False:' row_acc_alw
mutate accept-unaudited-suite-tolerated 'c.stale += stale_entries(label, path, entries, "suite-unaudited")' 'pass' row_acc_unaudited
mutate accept-star-row-for-readable-suite 'stale += stale_entries(suite, path, entries, star_why)' 'pass' row_acc_star
mutate accept-stale-lines-unsorted 'c.stale = sorted(set(c.stale))' 'c.stale = list(dict.fromkeys(c.stale))' row_acc_order
mutate accept-missing-file-is-an-error '    if not os.path.exists(path):' '    if False:' row_acc_missing
mutate accept-missing-file-silent '        print("replay: --accept %s does not exist: no exemptions" % path, file=sys.stderr)' '        pass' row_acc_missing
mutate accept-os-error-unmapped '        raise ReadError("cannot read the accept file %s: %s" % (path, e.strerror or e))' '        raise' row_acc_isdir
mutate accept-comment-lines-are-rows '        if not line.strip() or line.startswith("#"):' '        if not line.strip():' row_acc_comments
mutate accept-duplicate-row-tolerated '        if tuple(f[:4]) in seen:' '        if False:' row_acc_dupe
mutate accept-duplicate-key-needs-the-same-reason '        if tuple(f[:4]) in seen:' '        if tuple(f[:5]) in seen:' row_acc_dupe2
mutate accept-ordinal-zero-tolerated 're.match(r"^[1-9][0-9]*$", f[3])' 're.match(r"^[0-9]+$", f[3])' row_acc_ord0
mutate accept-anchor-not-hex 're.match(r"^[0-9a-f]{12}$", f[2])' 'f[2]' row_acc_nothex
mutate accept-star-needs-no-dashes '            if f[2:4] != ["-", "-"]:' '            if False:' row_acc_starkey
mutate accept-extra-columns-tolerated '        if len(f) != 5:' '        if len(f) < 5:' row_acc_six
mutate accept-empty-reason-tolerated 'if not re.match(r"^false-positive: \S", f[4]):' 'if not re.match(r"^false-positive:", f[4]):' row_acc_emptyreason
mutate accept-blank-reason-tolerated 'if not re.match(r"^false-positive: \S", f[4]):' 'if not re.match(r"^false-positive: ", f[4]):' row_acc_trailing

# review round 2
mutate census-gaps-of-earlier-rows-dropped '        for texts, m in ok:' '        for texts, m in ok[-1:]:' row_dup_labels
mutate census-texts-overwritten-by-a-later-row-of-the-label 'texts_of[path].extend(t for t in texts if t[0] not in have)' 'texts_of[path] = list(texts)' row_label_rows
mutate accept-rules-flattened-across-suites '        rules = accept.get(label, {})' '        rules = {k: v for d in accept.values() for k, v in d.items()}' row_tw
mutate accept-ordinal-counted-per-file '        count[a] = count.get(a, 0) + 1
        out.append((a, count[a], q, no, text))' '        count[(q, a)] = count.get((q, a), 0) + 1
        out.append((a, count[(q, a)], q, no, text))' row_idl1
mutate accept-anchors-from-the-first-file-only '    for q, full, light, written in texts:
        if path not in full' '    for q, full, light, written in texts[:1]:
        if path not in full' row_idl2
mutate start-regex-flat-alternation 'WORD_CHARS, name_regex(names))) if names else None' 'WORD_CHARS, "|".join(re.escape(n) for n in names))) if names else None' row_scan_ops
mutate start-regex-unescaped 'alts = [re.escape(ch) + emit(node[ch]) for ch in sorted(node)]' 'alts = [(ch if ch != "+" else "\\+") + emit(node[ch]) for ch in sorted(node)]' row_mt
mutate start-regex-prefix-name-never-starts '        if "" in node:
            return ""' '        if "" in node:
            return "(?!)"' row_scan_mid
mutate scan-light-view-ignored-by-the-anchors '        ll = fl if light is full else light.split("\n")' '        ll = fl' row_adj_accept
mutate sourced-library-not-regular-file-skipped '                h = try_read(index, path, bad, root)' '                h = try_read(index, path, bad, root) if os.path.isfile(path) else None' row_hopd
mutate sourced-library-deleted-file-skipped '                h = try_read(index, path, bad, root)' '                h = try_read(index, path, bad, root) if os.path.isfile(path) else None' row_hopg
mutate sourced-library-directory-link-skipped '                h = try_read(index, path, bad, root)' '                h = try_read(index, path, bad, root) if os.path.isfile(path) else None' row_hopl
mutate partial-suite-rows-judged-by-partial-text '        elif partial:' '        elif False:' row_partial
mutate short-row-suite-labelled-unregistered '        if suite in c.short_rows and suite not in c.registered:' '        if False:' row_shortx
mutate output-quoting-helper-removed '    return "".join("\\x%02x" % ord(c)' '    return s
    return "".join("\\x%02x" % ord(c)' row_quote
mutate output-quoting-comma-kept 'or (comma and c == ",")' 'or False' row_quote
mutate output-gap-line-unquoted 'quote_field(p, True) for p in (found if a.all_refs else found[:6])' 'p for p in (found if a.all_refs else found[:6])' row_quote
mutate lone-carriage-return-becomes-a-line-break 'lines = text.replace("\r\n", "\n").split("\n")' 'lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")' row_cr
mutate rows-file-trailing-carriage-return-kept 'return [line.rstrip("\r") for line in fh.read().split("\n")]' 'return fh.read().split("\n")' row_crl
mutate read-follows-links-outside-the-tree '        if real != top and not real.startswith(top.rstrip(os.sep) + os.sep):' '        if False:' row_sym
mutate read-has-no-size-cap '            if size > MAX_READ:' '            if False:' row_sym
mutate summary-refs-counter-dropped 'c.refs += len(found)' 'pass' row_marker
mutate summary-files-read-counter-dropped '        return len(self.index.raws)' '        return 0' row_marker
mutate scan-call-less-quadratic-in-paths '        cur, node = m.start(), index.root' '        for _p in index.paths:
            _p in text
        cur, node = m.start(), index.root' row_scan_ops
mutate scan-call-less-prefilter-over-all-paths '    for m in index.start.finditer(text):' '    for _p in index.paths:
        _p in text
    for m in index.start.finditer(text):' row_scan_ops
mutate scan-call-less-quadratic-in-width '    for m in index.start.finditer(text):' '    _tl = sorted({x.split("/")[0] for x in index.paths})
    for m in index.start.finditer(text):
        for _n in _tl:
            _n == text' row_scan_ops
mutate scan-call-less-quadratic-in-text '        cur, node = m.start(), index.root' '        for _i in range(len(text)):
            pass
        cur, node = m.start(), index.root' row_scan_ops
mutate boundary-twin-rejects-after-tab '    return i == 0 or WORD.match(text[i - 1]) is None' '    return i == 0 or re.match(r"[A-Za-z0-9_\t]", text[i - 1]) is None' row_prec_accept
mutate boundary-twin-rejects-after-slash '    return i == 0 or WORD.match(text[i - 1]) is None' '    return i == 0 or re.match(r"[A-Za-z0-9_/]", text[i - 1]) is None' row_prec_accept
mutate boundary-twin-rejects-after-double-quote '    return i == 0 or WORD.match(text[i - 1]) is None' '    return i == 0 or re.match(r"[A-Za-z0-9_\"]", text[i - 1]) is None' row_prec_accept
mutate boundary-twin-rejects-after-equals '    return i == 0 or WORD.match(text[i - 1]) is None' '    return i == 0 or re.match(r"[A-Za-z0-9_=]", text[i - 1]) is None' row_prec_accept
mutate boundary-twin-rejects-after-colon '    return i == 0 or WORD.match(text[i - 1]) is None' '    return i == 0 or re.match(r"[A-Za-z0-9_:]", text[i - 1]) is None' row_prec_accept
mutate boundary-twin-rejects-after-hyphen '    return i == 0 or WORD.match(text[i - 1]) is None' '    return i == 0 or re.match(r"[A-Za-z0-9_-]", text[i - 1]) is None' row_prec_accept
mutate boundary-twin-rejects-after-pipe '    return i == 0 or WORD.match(text[i - 1]) is None' '    return i == 0 or re.match(r"[A-Za-z0-9_|]", text[i - 1]) is None' row_prec_accept
mutate boundary-twin-rejects-after-semicolon '    return i == 0 or WORD.match(text[i - 1]) is None' '    return i == 0 or re.match(r"[A-Za-z0-9_;]", text[i - 1]) is None' row_prec_accept
mutate boundary-twin-rejects-after-open-paren '    return i == 0 or WORD.match(text[i - 1]) is None' '    return i == 0 or re.match(r"[A-Za-z0-9_(]", text[i - 1]) is None' row_prec_accept
mutate boundary-twin-rejects-after-single-quote '    return i == 0 or WORD.match(text[i - 1]) is None' '    return i == 0 or re.match(r"[A-Za-z0-9_\x27]", text[i - 1]) is None' row_prec_accept
mutate boundary-twin-ignores-digits '    return i == 0 or WORD.match(text[i - 1]) is None' '    return i == 0 or re.match(r"[A-Za-z_]", text[i - 1]) is None' row_bnd_mid

# review round 3
mutate audited-subtracts-each-state-separately 'return len(self.labels - self.always_on_labels - {u[0] for u in self.unaudited} - self.accepted_unread_labels)' 'return len(self.labels) - len(self.always_on_labels) - self.unaudited_labels - len(self.accepted_unread_labels)' row_audited_floor
mutate boundary-twin-offset-one-is-a-start '    return i == 0 or WORD.match(text[i - 1]) is None' '    return i <= 1 or WORD.match(text[i - 1]) is None' row_bnd_two
mutate star-row-accepts-a-tracked-suite '            tracked_suite = any(has_tracked_input(index, d) for d in dead)' '            tracked_suite = False' row_star_tracked
mutate sourced-untracked-file-is-read '        if q in tracked and q not in RUNNER_TRIGGERS and q not in out:' '        if q not in RUNNER_TRIGGERS and q not in out:' row_hop_untracked
# sourced-alias-is-read-twice (try_read keyed on the logical path) SURVIVES BY DESIGN since PR1b and is EQUIVALENT: the closure's visited set (keyed on
# the real path) never offers the alias to try_read, and suite_texts' seen set would drop it again. Three layers, none individually observable.
mutate label-gap-anchored-in-every-row 'texts_of[path].extend(t for t in texts if t[0] not in have)' 'texts_of[path].extend(t for tt, _ in ok for t in tt if t[0] not in have)' row_label_rows
mutate label-always-on-last-row-wins '        if f[3] == "always_on":
            g["always_on"] = True' '        g["always_on"] = f[3] == "always_on"' row_always_on_order
mutate label-dead-sibling-judges-the-rows-unaudited '        if not ok:   # no row has an input to read' '        if not ok or dead:' row_dead_sibling
mutate counter-refs-assigned-not-added 'c.refs += len(found)' 'c.refs = len(found)' row_marker
mutate counter-refs-after-the-edges 'c.refs += len(found)' 'c.refs += sum(len(m) for _, m in ok)' row_marker
mutate output-ref-text-unquoted ', quote_field(text)))' ', text))' row_ctl_bytes
mutate output-gap-suite-unquoted 'print("gap\t%s\t%d\t%s" % (quote_field(suite), len(found)' 'print("gap\t%s\t%d\t%s" % (suite, len(found)' row_ctl_bytes
mutate output-stale-suite-unquoted '(quote_field(suite), quote_field(p), key, why)' '(suite, quote_field(p), key, why)' row_ctl_bytes
mutate output-stale-path-unquoted '(quote_field(suite), quote_field(p), key, why)' '(quote_field(suite), p, key, why)' row_ctl_bytes
mutate output-unaudited-suite-unquoted 'print("unaudited\t%s\t%s" % (quote_field(suite),' 'print("unaudited\t%s\t%s" % (suite,' row_ctl_bytes
mutate output-unaudited-reason-flag-ignored 'why if quoted else quote_field(why)' 'why' row_ctl_bytes
mutate quote-c1-controls-raw 'QUOTE_U = re.compile("[\u0080-\u009f' 'QUOTE_U = re.compile("[' row_quote
mutate quote-zero-width-raw '\u200b-\u200f' '' row_quote
mutate quote-separators-raw '\u2028-\u202e' '' row_quote
mutate quote-bidi-isolates-raw '\u2066-\u2069' '' row_quote
mutate quote-bom-raw '\ufeff]")' ']")' row_quote
mutate quote-soft-hyphen-raw '\u00ad' '' row_quote
mutate quote-arabic-letter-mark-raw '\u061c' '' row_quote
mutate quote-mongolian-vowel-separator-raw '\u180e' '' row_quote
mutate quote-word-joiners-raw '\u2060-\u2064' '' row_quote
mutate tracked-names-carriage-return-folded 'return {f.decode("utf-8", errors="replace")' 'return {f.decode("utf-8", errors="replace").replace("\r", "\n")' row_quote
mutate scan-per-length-loop-restored '    for m in index.start.finditer(text):' '    _lens = sorted({len(x) for x in index.paths})
    for m in index.start.finditer(text):
        for _l in _lens:
            text[m.start():m.start() + _l]' row_scan_ops
mutate scan-hidden-copy-and-encode-per-start '        cur, node = m.start(), index.root' '        text[m.start():].encode()
        cur, node = m.start(), index.root' row_scan_ops
mutate scan-hidden-count-per-start '        cur, node = m.start(), index.root' '        text.count("x", m.start())
        cur, node = m.start(), index.root' row_scan_ops
mutate scan-hidden-regex-search-on-a-slice-per-start '        cur, node = m.start(), index.root' '        re.search("zzz", text[m.start():])
        cur, node = m.start(), index.root' row_scan_ops
mutate scan-hidden-replace-per-start '        cur, node = m.start(), index.root' '        text.replace("zz", "y")
        cur, node = m.start(), index.root' row_scan_ops
mutate scan-hidden-join-and-find-per-scan '    for m in index.start.finditer(text):' '    "\n".join(index.paths).find("zz")
    for m in index.start.finditer(text):' row_scan_ops
mutate read-containment-without-the-separator '        if real != top and not real.startswith(top.rstrip(os.sep) + os.sep):' '        if real != top and not real.startswith(top):' row_sym
mutate read-opens-blocking 'os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0)' 'os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)' row_sym
mutate read-oserror-unmapped '        raise ReadError("cannot read %s: %s" % (path, e.strerror or e))
    try:
        if not stat' '        raise
    try:
        if not stat' row_sym
mutate read-cap-is-exclusive 'if size > MAX_READ:' 'if size >= MAX_READ:' row_sym

# --- PR1b reach: one mutant per property failure (the matrices of the plan's Guard Contract); every row above is GREEN on the pristine SUT first
mutate reach-closure-stops-after-one-hop '    for _ in range(HOP_DEPTH):' '    for _ in range(1):' row_rc_closure
mutate reach-walk-disabled '    code = set(code_pats_of(pats, index))' '    code = set()' row_rc_cls
mutate reach-hop-depth-seven 'HOP_DEPTH = 8 ' 'HOP_DEPTH = 7 ' row_rc_depth
mutate reach-hop-depth-unbounded 'HOP_DEPTH = 8 ' 'HOP_DEPTH = 99 ' row_rc_depth
mutate reach-walk-depth-seven 'WALK_DEPTH = 8 ' 'WALK_DEPTH = 7 ' row_rc_walk_depth
mutate reach-walk-depth-unbounded 'WALK_DEPTH = 8 ' 'WALK_DEPTH = 99 ' row_rc_walk_depth
mutate reach-hop-first-member-stops '        if q in tracked and q not in RUNNER_TRIGGERS and q not in out:
            out.append(q)
' '        if q in tracked and q not in RUNNER_TRIGGERS and q not in out:
            out.append(q)
            break
' row_rc_twosrc
mutate reach-dir-operands-against-the-repo-root '            home = os.path.dirname(rel) if pre.startswith("$(dirname") or pre.strip("${}") in HOP_DIR_VARS else ""' '            home = ""' row_rc_ops
mutate reach-dir-operands-against-the-suite-directory '                    nxt.append((h, q))' '                    nxt.append((h, rel))' row_rc_ops
mutate reach-hop-memo-resolved-against-the-real-path '            for q in hops_of(index, g[0], r):' '            for q in hops_of(index, g[0], os.path.relpath(g[0], os.path.realpath(root))):' row_rc_symlink
mutate reach-walk-ignores-pats '    code = set(code_pats_of(pats, index))' '    code = set(index.tracked)' row_rc_walk_listed
mutate reach-walk-reads-data-files '".mts", ".cts", ".rb"))' '".mts", ".cts", ".rb", ".md", ".yml", ".tsv"))' row_rc_walk_data
mutate reach-walk-reads-a-runner-trigger 'and e not in RUNNER_TRIGGERS
                and os.path.splitext(e)[1] in CODE_EXT' '
                and os.path.splitext(e)[1] in CODE_EXT' row_rc_walk_trigger
mutate reach-hop-reads-a-runner-trigger '        if q in tracked and q not in RUNNER_TRIGGERS and q not in out:' '        if q in tracked and q not in out:' row_rc_neg_trigger
mutate reach-hop-keyword-glued-to-a-word '    r"""(?<![\w.])(?:source|\.)[ \t]+["'\'']?"""' '    r"""(?:source|\.)[ \t]+["'\'']?"""' row_rc_neg_prose
mutate reach-walk-nodes-include-globs '        if (pt.startswith("^") and e and not e.startswith("glob:") and not e.endswith("/")' '        if (pt.startswith("^") and e and not e.endswith("/")' row_rc_walk_nodes
# reach-walk-nodes-include-dirs (a dir/ entry allowed as a walk node) SURVIVES BY DESIGN and is EQUIVALENT: the entry ends in a slash and no tracked path does,
# so the `e in index.tracked` test excludes it whatever the dir check says. (The glob: twin is observable: the fixture tracks a file NAMED glob:walk/*.sh, the very text of the wgl row's glob entry.)
mutate reach-unreadable-hop-skipped-silently '                h = try_read(index, path, bad, root)' '                h = try_read(index, path, [], root)' row_rc_unreadable
mutate reach-unreadable-walk-file-skipped-silently '            tried.add(path)
            got = try_read(index, path, bad, root)' '            tried.add(path)
            got = try_read(index, path, [], root)' row_rc_unreadable_walk
mutate reach-walk-files-bring-no-closure '            for g in source_closure(root, got, q, index, bad)[1:]:' '            for g in []:' row_rc_walk_closure
mutate reach-walk-before-closure '                out.append(got)
                level.append((got, q))' '                out.insert(0, got)
                level.append((got, q))' row_rc_order
mutate reach-rows-of-a-label-in-selector-order 'g["rows"].sort()' 'pass' row_rc_order_rows
mutate reach-rows-sorted-by-the-first-pattern-only 'g["rows"].sort()' 'g["rows"].sort(key=lambda pats: pats[0])' row_rc_ties
mutate reach-rows-sorted-by-the-last-pattern 'g["rows"].sort()' 'g["rows"].sort(key=lambda pats: pats[-1])' row_rc_ties
mutate reach-walk-closure-does-not-feed-the-walk '                    out.append(g)
                    frontier.append(g)' '                    out.append(g)
                    pass' row_rc_wcl
mutate reach-walk-level-in-reverse-order 'for q in sorted(named):' 'for q in sorted(named, reverse=True):' row_rc_lvl
mutate reach-walk-closures-in-reverse-walk-order '        for got, q in level:
            for g in source_closure(root, got, q, index, bad)[1:]:' '        for got, q in reversed(level):
            for g in source_closure(root, got, q, index, bad)[1:]:' row_rc_lcl
mutate reach-walk-seeded-by-the-first-input-only 'seen, tried, frontier = {t[0] for t in out}, set(), list(out)' 'seen, tried, frontier = {t[0] for t in out}, set(), list(out)[:1]' row_rc_dsw
mutate reach-hop-operand-not-normalised 'q = os.path.normpath(os.path.join(home, rest.lstrip("/")))' 'q = os.path.join(home, rest.lstrip("/"))' row_rc_ops
mutate reach-hop-bash-targets-dropped '([A-Za-z0-9_./-]+\.(?:sh|bash))"""' '([A-Za-z0-9_./-]+\.(?:sh))"""' row_rc_ops
mutate reach-hop-single-quote-dropped '(?:source|\.)[ \t]+["'\'']?"""' '(?:source|\.)[ \t]+"?"""' row_rc_ops
mutate reach-hop-tab-blank-dropped '(?:source|\.)[ \t]+' '(?:source|\.) +' row_rc_ops
mutate reach-hop-prefix-without-the-slash-lookahead '\)(?=/)|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?(?=/))?"""' '\)|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?)?"""' row_hop_redos
mutate reach-code-ext-drops-bash 'CODE_EXT = frozenset((".sh", ".bash", ' 'CODE_EXT = frozenset((".sh", ' row_rc_ce
mutate reach-code-ext-drops-jsx '".tsx", ".jsx", ".js"' '".tsx", ".js"' row_rc_ce
mutate reach-code-ext-drops-the-module-flavours '".mjs", ".cjs", ".mts", ".cts", ".rb"))' '".rb"))' row_rc_ce
mutate suite-file-reads-a-runner-trigger 'path and path not in RUNNER_TRIGGERS and not path.endswith("/")' 'path and not path.endswith("/")' row_rc_rt
mutate comment-prefix-matched-anywhere-in-the-line '"" if line.lstrip().startswith(prefix) else line for line in lines' '"" if prefix in line else line for line in lines' row_cm_shapes
mutate edge-glob-cache-keyed-on-the-head '        rx = glob_regexes.get(g)
        if rx is None:
            rx = glob_regexes[g] = re.compile(' '        rx = glob_regexes.get(head)
        if rx is None:
            rx = glob_regexes[head] = re.compile(' row_edge_cross
mutate edge-glob-prefix-match-only 'rx.fullmatch(path)' 'rx.match(path)' row_edge_cross
mutate reach-walk-pats-unioned-across-rows '            texts = reach_texts(root, inputs, pats, index, bad)' '            texts = reach_texts(root, inputs, [x for r in g["rows"] for x in r], index, bad)' row_rc_lab
mutate reach-walk-seen-set-lives-in-the-index 'if path in tried or os.path.realpath(path) in seen:' 'if path in tried or os.path.realpath(path) in index.raws:' row_rc_seen
mutate reach-visited-set-dropped '                if real in visited:
                    continue
' '                if False:
                    continue
' row_reach_cost
mutate reach-walk-loops-pats-per-node '        for g in frontier:
            named |= refs_of(index, g) & code
' '        for g in frontier:
            for c in code:
                if c in refs_of(index, g):
                    named.add(c)
' row_reach_cost
mutate edge-question-mark-allowed-in-a-glob 'GLOB_CHARSET = re.compile(r"[^A-Za-z0-9_./*-]")' 'GLOB_CHARSET = re.compile(r"[^A-Za-z0-9_./*?-]")' row_edge_charset
mutate edge-charset-arm-returns-false '        if GLOB_CHARSET.search(g):
            return True' '        if GLOB_CHARSET.search(g):
            return False' row_edge_charset
mutate edge-head-absolute-arm-dropped 'if head.startswith("/"):' 'if False:' row_edge_head_abs
mutate edge-head-curdir-arm-dropped 'if head.startswith("./"):' 'if False:' row_edge_head_dot
mutate edge-head-parent-arm-dropped 'if head.startswith("../"):' 'if False:' row_edge_head_dotdot
mutate edge-head-doubleslash-arm-dropped 'if "//" in head:' 'if False:' row_edge_head_dslash
mutate edge-head-slashdotslash-arm-dropped 'if "/./" in head:' 'if False:' row_edge_head_sds
mutate edge-head-slashdotdotslash-arm-dropped 'if "/../" in head:' 'if False:' row_edge_head_sddsl
mutate edge-head-not-slash-terminated-arm-dropped 'if not head.endswith("/"):' 'if False:' row_edge_head_notslash
mutate edge-tail-slash-arm-dropped 'if tail.endswith("/"):' 'if False:' row_edge_tail_slash
mutate edge-tail-without-star-arm-dropped 'if "*" not in tail:' 'if False:' row_edge_tail_nostar
mutate edge-noncaret-compared-by-equality '        return pt in path' '        return pt == path' row_edge_noncaret
mutate edge-noncaret-glob-is-live '    if not pt.startswith("^"):
        return pt in path
    e = pt[1:]
' '    if not pt.startswith("^") and not pt.startswith("glob:"):
        return pt in path
    e = pt[1:] if pt.startswith("^") else pt
' row_edge_noncaret
mutate edge-star-does-not-cross-a-slash 'for c in re.sub(r"\*+", "*", g)), re.S)' 'for c in re.sub(r"\*+", "*", g)).replace(".*", "[^/]*"), re.S)' row_edge_cross
mutate edge-exact-as-substring '    return path == e
' '    return e in path
' row_edge_exact
mutate edge-dir-as-infix '        return path.startswith(e)
    return path == e' '        return e in path
    return path == e' row_edge_dir
mutate comment-both-languages-stripped 'line.lstrip().startswith(prefix) else line for line in lines' 'line.lstrip().startswith(("#", "//")) else line for line in lines' row_cm_hash
mutate comment-unknown-extension-strips-hash 'return COMMENT_PREFIX.get(os.path.splitext(path)[1], "")' 'return COMMENT_PREFIX.get(os.path.splitext(path)[1], "#")' row_cm_none
mutate comment-table-drops-tsx '".tsx": "//", ' '' row_cm_slash
mutate comment-table-drops-rb '".rb": "#", ' '' row_cm_hash
mutate comment-extension-from-the-logical-name 'comment_prefix(path))' 'comment_prefix(os.path.basename(path).split(".")[0]))' row_cm_names

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
# A CRASH is not a kill: a mutant that does not import, one whose run exits rc 4 and one that prints a Traceback where the pristine run did not
mutant_outcome ctl-import-crash 'import argparse' 'import argparse_does_not_exist' row_scan_eol
[[ "$MUT_RESULT" = crashed ]] && pass "control: a mutant that does not import is CRASHED, not killed" || fail "control: import crash scored as '$MUT_RESULT'"
mutant_outcome ctl-scan-raises '    for m in index.start.finditer(text):' '    raise RuntimeError("boom")
    for m in index.start.finditer(text):' row_scan_eol
[[ "$MUT_RESULT" = crashed ]] && pass "control: a scan_text that raises (the audit exits rc 4) is CRASHED, not killed" || fail "control: scan_text crash scored as '$MUT_RESULT'"
mutant_outcome ctl-boundary-raises '    return i == 0 or WORD.match(text[i - 1]) is None' '    raise RuntimeError("boom")' row_bnd_mid
[[ "$MUT_RESULT" = crashed ]] && pass "control: a boundary() that raises is CRASHED, not killed" || fail "control: boundary() crash scored as '$MUT_RESULT'"
mutant_outcome ctl-ops-traceback '    for m in index.start.finditer(text):' '    raise RuntimeError("boom")
    for m in index.start.finditer(text):' row_scan_ops
[[ "$MUT_RESULT" = crashed ]] && pass "control: a mutant that makes the python row print a Traceback is CRASHED, not killed" || fail "control: traceback scored as '$MUT_RESULT'"
mutant_outcome ctl-verdict-crash 'def verdict(a_, b_, c_, d_):' 'def verdict(a_, b_, c_, d_):
    raise NameError("boom")' row_verdict_fail
[[ "$MUT_RESULT" = crashed ]] && pass "control: a verdict() that raises (a direct python3 row: main reports an internal error, rc 4) is CRASHED, not killed" || fail "control: verdict crash scored as '$MUT_RESULT'"
mutant_outcome ctl-cp-crash 'def cp_upper(k, n, conf=0.95):' 'def cp_upper(k, n, conf=0.95):
    raise NameError("boom")' row_cp_edge
[[ "$MUT_RESULT" = crashed ]] && pass "control: a cp_upper() that raises is CRASHED, not killed" || fail "control: cp_upper crash scored as '$MUT_RESULT'"
mutant_outcome ctl-ambiguous-old 'import ' 'import  ' row_verdict_fail
[[ "$MUT_RESULT" = edit-failed ]] && pass "control: an edit whose 'old' text occurs more than once does not land (edit-failed), it is never applied to the first occurrence" || fail "control: ambiguous edit scored as '$MUT_RESULT'"
mutant_outcome ctl-load-accept-nameerror 'def load_accept(path):' 'def load_accept(path):
    raise NameError("boom")' row_acc_isdir
[[ "$MUT_RESULT" = crashed ]] && pass "control: a NameError in load_accept is CRASHED, not killed (row_acc_isdir only allows the one unmapped-OSError mutant to crash)" || fail "control: load_accept NameError scored as '$MUT_RESULT'"
mutant_outcome ctl-cp-nameerror 'def cp_upper(k, n, conf=0.95):' 'def cp_upper(k, n, conf=0.95):
    raise NameError("boom")' row_cp_big
[[ "$MUT_RESULT" = crashed ]] && pass "control: a NameError in cp_upper is CRASHED, not killed (row_cp_big only allows the overflow mutant to crash)" || fail "control: cp_upper NameError scored as '$MUT_RESULT'"
mutant_outcome ctl-sel-error-nameerror 'def run_selector(root, args):' 'def run_selector(root, args):
    raise NameError("boom")' row_sel_error
[[ "$MUT_RESULT" = crashed ]] && pass "control: a NameError on the selector path (row_sel_error, now run through run_sut) is CRASHED, not killed" || fail "control: selector NameError scored as '$MUT_RESULT'"
mutant_outcome ctl-real-kill 'r = index.refs[got[0]] = scan_views(index, got[1], got[2])' 'r = index.refs[got[0]] = scan_views(index, got[1][:-1], got[2][:-1])' row_scan_eol
[[ "$MUT_RESULT" = killed ]] && pass "control: a mutant that still runs and returns the wrong answer is KILLED" || fail "control: a real kill scored as '$MUT_RESULT'"
ctl_mutate_records() {  # drive mutate() with a survivor: it must record a FAILURE, then unwind
  local p0=$passes f0=$fails n0=${#FAILED[@]} m0=$MUT_RUN k0=$MUT_KILLED f1
  mutate ctl-survive-through-mutate 'READ-ONLY. It never writes' 'READ-ONLY (edited). It never writes' row_verdict_fail >/dev/null 2>&1
  f1=$fails
  passes=$p0; fails=$f0; MUT_RUN=$m0; MUT_KILLED=$k0
  if (( n0 == 0 )); then FAILED=(); else FAILED=("${FAILED[@]:0:n0}"); fi
  [[ $((f1 - f0)) -eq 1 ]]
}
ctl_mutate_records && pass "control: mutate() records a survivor as a failure" || fail "control: mutate() did not record a survivor as a failure"
ctl_duplicate_refused() {  # a renamed duplicate of an earlier mutant (same edit, same row) must be REFUSED, not counted as one more kill
  local p0=$passes f0=$fails n0=${#FAILED[@]} m0=$MUT_RUN k0=$MUT_KILLED last
  mutate ctl-dup-a 'import argparse' 'import argparse  # dup' row_verdict_fail >/dev/null 2>&1
  mutate ctl-dup-b 'import argparse
import hashlib' 'import argparse  # dup
import hashlib' row_verdict_fail >/dev/null 2>&1   # spelled differently, the same mutated file
  last="${FAILED[${#FAILED[@]}-1]}"
  passes=$p0; fails=$f0; MUT_RUN=$m0; MUT_KILLED=$k0
  if (( n0 == 0 )); then FAILED=(); else FAILED=("${FAILED[@]:0:n0}"); fi
  [[ "$last" == *"repeats mutant ctl-dup-a"* ]]
}
ctl_duplicate_refused && pass "control: a mutant that repeats an earlier one (same edit, same row) is refused by name, so a renamed duplicate cannot hold a floor" || fail "control: a renamed duplicate mutant was not refused"
if [[ "$MUT_KILLED" -eq "$MUT_RUN" ]]; then pass "every mutant was killed ($MUT_KILLED of $MUT_RUN)"; else fail "mutants killed $MUT_KILLED of $MUT_RUN"; fi

# Anti-vacuity floors, reported through printf + exit so they never ride on the helpers they guard. Each floor is a literal (raised IN THE
# SAME EDIT that adds rows: base + added, so a deleted row cannot hide behind a new one) AND a count taken from this file (every `mutate`
# line and every `pass "` call site must have run at least once, whatever else changes). mutate() itself refuses a mutant that repeats an
# earlier one (same edit, same row), so a renamed duplicate adds no kill.
SELF="${BASH_SOURCE[0]}"
SITES_MUTATE="$(grep -c '^mutate ' "$SELF")"
FLOOR_ASSERTIONS=687   # base 483 (PR1) + 204 added by PR1b incl. review round 1 (measured: 687 passed, 0 failed)
total=$((passes + fails))
if [[ "$total" -lt "$FLOOR_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$total" "$FLOOR_ASSERTIONS" >&2; exit 1
fi
FLOOR_MUTANTS=288   # base 225 (PR1) - 1 (sourced-alias-is-read-twice, equivalent since PR1b) + 64 added by PR1b incl. review round 1 (measured: 288 mutants, all killed)
if [[ "$MUT_RUN" -lt "$FLOOR_MUTANTS" ]]; then
  printf '[FATAL] mutation floor: only %s mutants ran, floor is %s\n' "$MUT_RUN" "$FLOOR_MUTANTS" >&2; exit 1
fi
# the counted floors (not `if` openers: they need the grep counts above, which a mutant of the literal floors above cannot carry)
# every `mutate` line must have run (an exact reconciliation: a skipped or conditional line is a missing mutant)
[[ "$MUT_RUN" -ge "$SITES_MUTATE" ]] || { printf '[FATAL] mutation floor: %s mutants ran but this file has %s mutate lines\n' "$MUT_RUN" "$SITES_MUTATE" >&2; exit 1; }
echo "ci-pr-affected-replay.test.sh: $passes passed, $fails failed, $total assertions, $MUT_RUN mutants"
[[ "$fails" -eq 0 ]] && exit 0
printf 'FAILED: %s\n' "${FAILED[@]}" >&2
exit 1
