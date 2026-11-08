#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2329  # A && B || C is the assertion idiom; sed/jq programs are single-quoted on purpose; setup functions are dispatched indirectly
# Suite for plugins/soleur/skills/ship/scripts/hold-gate-eval.sh -- Guard 4 of the plan's Guard Contract.
#
# THE SEAM: `gh` is a PATH stub answering only the exact argv shapes the SUT is expected to use (delegation
# reads, `pr view`, one `run list`), refusing every other argv with exit 64 after logging STUB-MISS. `git` is real,
# against local bare "origin" repositories and clones, so the default branch and the fetch are measured, not stubbed.
# Fixtures are synthesized (cq-test-fixtures-synthesized-only) under test/fixtures/standing-delegation/ (shared with
# the verifier suite, read-only here) and test/fixtures/hold-gate-eval/ (this suite's own plans).
#
# GRAMMAR UNDER TEST (CTO ruling R1): `pr-merged <N>`, `no-inflight-run <workflow-file>` and `web-acceptance <key> <hash>`.
# `command` and `run-green` are deferred; their lines are an unknown kind, which exits 2 and leaves the hold standing.
# Arm 14 drives web-acceptance (Guard 1 of the PR-D plan): `doppler` and `curl` are PATH stubs that refuse any argv they do
# not know with exit 64, the PATH for those runs is a hermetic directory with NO real curl and NO real doppler, and the
# committed texts live in the fixture repository (HEAD blobs). The token must reach no output and no argv log.
#
# ARMS: control, gate kinds, parse shapes, sections and headings, the no-delegation exit 3, delegation and envelope,
# default branch and fetch, stdin hygiene, no time-limit tool, envelope mode, jargon over the human lines, zero-write
# audit of the stub log, mutations (`# mut:<name>` markers in the script), floor.

set -uo pipefail
export LC_ALL=C

TMP="$(mktemp -d -t hge-suite.XXXXXXXX)"
trap 'rm -rf "$TMP"' EXIT

SUITE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./test-helpers.sh
source "$SUITE_DIR/test-helpers.sh"
set +e
assert_fixture_dir "$TMP"

REPO_ROOT="$(cd -P "$SUITE_DIR/../../.." && pwd -P)"
SUT_REAL="$REPO_ROOT/plugins/soleur/skills/ship/scripts/hold-gate-eval.sh"
SUT="$SUT_REAL"
FX="$SUITE_DIR/fixtures/standing-delegation"
FXH="$SUITE_DIR/fixtures/hold-gate-eval"
BASH_BIN="$(command -v bash)"

( assert_eq a b "control" >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: assert_eq cannot fail -- dispatch is neutered\n' >&2; exit 2; }

[[ -f "$SUT_REAL" ]] || { echo "  FAIL: evaluator missing: $SUT_REAL"; FAIL=$((FAIL + 1)); print_results 1; exit 1; }
command -v jq >/dev/null || { echo "FATAL: jq required" >&2; exit 2; }
command -v timeout >/dev/null || { echo "FATAL: this suite needs timeout (the SUT stands without one)" >&2; exit 2; }
for f in delegation-valid.md envelope-valid.md envelope-two-sections.md holds-prose.md holds-none.md; do
  [[ -s "$FX/$f" ]] || { echo "FATAL: fixture missing: $FX/$f" >&2; exit 2; }
done
for f in plan-three-holds.md plan-web-acceptance-only.md plan-web-acceptance-mixed.md plan-reserved-only.md web-acceptance-text.md; do
  [[ -s "$FXH/$f" ]] || { echo "FATAL: fixture missing: $FXH/$f" >&2; exit 2; }
done

addd() { jq -rn --arg d "$1" --argjson n "$2" '($d + "T00:00:00Z" | fromdateiso8601) + ($n * 86400) | strftime("%Y-%m-%d")'; }
TODAY="$(date -u +%Y-%m-%d)"; NOW_ISO="${TODAY}T00:00:00Z"; EXP10="$(addd "$TODAY" 10)"; YEST="$(addd "$TODAY" -1)"
[[ "$YEST" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && "$YEST" < "$TODAY" ]] || { echo "FATAL: yesterday not computed" >&2; exit 2; }
# TODAY is fixed here and the suite runs for minutes: a valid_until row that depends on it is skipped, with a visible note, when UTC midnight has passed.
day_stable() { [[ "$(date -u +%Y-%m-%d)" == "$TODAY" ]]; }
day_skip() { echo "  SKIP: $1: UTC midnight passed during the suite, so the rows that depend on today's date are not trusted"; SKIPPED=$((SKIPPED + 1)); }
# Per-arm assertion counts: deleting one arm of rows must trip its own minimum even when the total floor still holds.
arm_begin() { eval "ARM_S_$1=$((PASS + FAIL + SKIPPED))"; }
arm_end() { local st; eval "st=\${ARM_S_$1:-}"; if [[ -n "$st" ]]; then eval "ARM_N_$1=$((PASS + FAIL + SKIPPED - st))"; else eval "ARM_N_$1=0"; fi; }
arm_floor() { # <id> <minimum> <what>
  local v; eval "v=\${ARM_N_$1:-0}"
  # Written without a leading `if (( .. ))` on a counter line: scripts/guard-vacuity-floor.test.sh would read that as a whole-suite floor it cannot rebuild.
  (( v >= $2 )) && { echo "  PASS: arm $1 ($3): $v assertions >= $2"; PASS=$((PASS + 1)); return 0; }
  echo "  FAIL: arm $1 ($3): $v assertions < $2 -- a block of rows is missing"; FAIL=$((FAIL + 1))
}

# --- the gh stub ----------------------------------------------------------------------------------
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
d="${STUB_DIR:?}"
echo "$*" >> "$d/calls.log"
# stdin hygiene probe: when `eat-stdin` exists the stub drains whatever stdin it inherited and records the byte count
if [ -f "$d/eat-stdin" ]; then n="$(cat | wc -c | tr -d ' ')"; echo "$n" >> "$d/stdin-bytes"; fi
miss() { echo "STUB-MISS $*" >> "$d/calls.log"; echo "gh stub: unsupported argv: $*" >&2; exit 64; }
fail_mode() {
  case "$(cat "$d/$1" 2>/dev/null)" in
    404) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
    net) echo "error connecting to api.github.com" >&2; exit 1 ;;
  esac
}
if [ "$*" = "repo view --json nameWithOwner --jq .nameWithOwner" ]; then fail_mode mode-repo; cat "$d/repo.txt"; exit 0; fi
if [ "${1:-} ${2:-}" = "pr view" ]; then
  [ "$#" -eq 5 ] && [ "$4" = "--json" ] && [ "$5" = "state,mergeCommit,baseRefName" ] || miss "$@"
  fail_mode mode-pr; [ -f "$d/pr-$3.json" ] || { echo "no pull request found" >&2; exit 1; }; cat "$d/pr-$3.json"; exit 0
fi
if [ "${1:-} ${2:-}" = "run list" ]; then
  if [ "$#" -eq 8 ] && [ "$3" = "--workflow" ] && [ "$5" = "--limit" ] && [ "$6" = "100" ] && [ "$7" = "--json" ] && [ "${8}" = "status" ]; then
    fail_mode mode-run; f="$d/runs-$4.json"; if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi; exit 0
  fi
  miss "$@"
fi
[ "$#" -eq 2 ] && [ "$1" = api ] || miss "$@"
p="$2"
case "$p" in
  repos/*/*/issues/comments/*)
    id="${p##*/}"; fail_mode "mode-comment-$id"
    [ -f "$d/comment-$id.json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }; cat "$d/comment-$id.json" ;;
  repos/*/*/collaborators/*/permission)
    l="${p%/permission}"; l="${l##*/}"; fail_mode mode-perm
    [ -f "$d/perm-$l.json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }; cat "$d/perm-$l.json" ;;
  repos/*/*/issues/*)
    n="${p##*/}"; fail_mode mode-issue
    [ -f "$d/issue-$n.json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }; cat "$d/issue-$n.json" ;;
  *) miss "$@" ;;
esac
STUB
chmod +x "$BIN/gh"
( STUB_DIR="$TMP" PATH="$BIN:$PATH" gh bogus argv >/dev/null 2>&1 ); h1=$?
assert_eq "64" "$h1" "H1: the gh stub refuses an argv it does not know (exit 64)"
( STUB_DIR="$TMP" PATH="$BIN:$PATH" gh run list --workflow w.yml --status queued --limit 5 --json databaseId >/dev/null 2>&1 ); h1b=$?
assert_eq "64" "$h1b" "H1b: the gh stub refuses the retired per-status run list (exit 64)"

# --- the repositories ------------------------------------------------------------------------------
# W: main clone (pushed history A, B; then a local-only commit). W7: a clone of the pushed origin (origin/HEAD is set).
# W6: a repository whose default branch is `trunk`. W4: a clone whose origin moves after it was taken (stale origin/main).
URL="https://github.com/example-org/example-repo/issues/77#issuecomment-1001"
K62="a$(printf 'b%.0s' $(seq 1 61))"; K63="a$(printf 'b%.0s' $(seq 1 62))"; K64="a$(printf 'b%.0s' $(seq 1 63))"
[[ ${#K62} -eq 62 && ${#K63} -eq 63 && ${#K64} -eq 64 ]] || { echo "FATAL: key lengths wrong" >&2; exit 2; }
O="$TMP/origin.git"; W="$TMP/work"; W7="$TMP/work7"; O2="$TMP/origin2.git"; W4="$TMP/work4"; W4TPL="$TMP/work4tpl"; W5="$TMP/work5"
O3="$TMP/origin3.git"; W6="$TMP/work6"
(
  git_fixture_env "$O" || exit 1
  git init -q --bare "$O" && git -C "$O" symbolic-ref HEAD refs/heads/main
  git clone -q "$O" "$W" 2>/dev/null
  git -C "$W" checkout -q -b main
  sed -e "s|@URL@|$URL|g" "$FX/envelope-valid.md" > "$W/env-valid.md"
  sed -e "s|@URL@|$URL|g" "$FX/envelope-two-sections.md" > "$W/env-two.md"
  sed '/^- Gate:/d' "$W/env-valid.md" > "$W/env-nogate.md"
  sed 's/^## Production Envelope/### production envelope/' "$W/env-valid.md" > "$W/env-lvl3.md"
  sed 's/^- Gate: pr-merged 120$/- Gate: command scripts\/x.sh => y/' "$W/env-valid.md" > "$W/env-cmd.md"
  ln -s env-valid.md "$W/env-link.md"
  WAT="$W/apps/web-platform/server/legal-acceptance/texts"; mkdir -p "$WAT/up"
  cp "$FXH/web-acceptance-text.md" "$WAT/wa-key.md"; cp "$FXH/web-acceptance-text.md" "$WAT/$K62.md"; cp "$FXH/web-acceptance-text.md" "$WAT/$K63.md"
  cp "$FXH/web-acceptance-text.md" "$WAT/$K64.md"; cp "$FXH/web-acceptance-text.md" "$WAT/dot.key.md"; cp "$FXH/web-acceptance-text.md" "$WAT/up/key.md"
  sed 's/$/\r/' "$FXH/web-acceptance-text.md" > "$WAT/wa-cr.md"
  sed 's/^valid_until: .*/valid_until: 2000-01-01/' "$FXH/web-acceptance-text.md" > "$WAT/wa-exp.md"
  sed "s/^valid_until: .*/valid_until: $TODAY/" "$FXH/web-acceptance-text.md" > "$WAT/wa-today.md"
  sed 's/^valid_until: .*/valid_until: soon/' "$FXH/web-acceptance-text.md" > "$WAT/wa-badvu.md"
  sed 's/^valid_until: .*/valid_until: 2099-1-1/' "$FXH/web-acceptance-text.md" > "$WAT/wa-badvu2.md"
  sed '/^valid_until: /d' "$FXH/web-acceptance-text.md" > "$WAT/wa-novu.md"
  sed "s/^valid_until: .*/valid_until: $YEST/" "$FXH/web-acceptance-text.md" > "$WAT/wa-yest.md"
  sed 's/^valid_until: .*/valid_until: 2000-01-01\nvalid_until: 2099-12-31/' "$FXH/web-acceptance-text.md" > "$WAT/wa-dup.md"
  sed 's/^valid_until: .*/valid_until: 2099-12-31\nvalid_until: 2000-01-01/' "$FXH/web-acceptance-text.md" > "$WAT/wa-dup2.md"
  sed -e '/^valid_until: /d' -e '$a valid_until: 2000-01-01' "$FXH/web-acceptance-text.md" > "$WAT/wa-bodyvu.md"
  sed 's/^valid_until: .*/valid_until: 2026-13-01/' "$FXH/web-acceptance-text.md" > "$WAT/wa-badvu3.md"
  sed 's/^valid_until: .*/valid_until: 2099-99-99/' "$FXH/web-acceptance-text.md" > "$WAT/wa-badvu4.md"
  sed 's/^valid_until: .*/valid_until: 2026-02-30/' "$FXH/web-acceptance-text.md" > "$WAT/wa-badvu5.md"
  sed 's/^valid_until: .*/valid_until:/' "$FXH/web-acceptance-text.md" > "$WAT/wa-badvu6.md"
  sed '1,4d' "$FXH/web-acceptance-text.md" > "$WAT/wa-nofm.md"
  printf '# Example envelope (synthesized fixture)\n\n## Production Envelope - web\n\nPreconditions:\n- Gate: web-acceptance wa-key %s\n' "$(sha256sum < "$FXH/web-acceptance-text.md" | cut -c1-64)" > "$W/env-wa.md"
  ln -s wa-key.md "$WAT/wa-link.md"
  # the acknowledgement key and its look-alikes have a committed text too (arm nt): the only thing that can then refuse the key is its KIND
  for nk in founder-acceptance-record founder-acceptance-record-two founder-acceptance acceptance-record; do cp "$FXH/web-acceptance-text.md" "$WAT/$nk.md"; done
  git -C "$W" add -A && git -C "$W" commit -q -m "base" && git -C "$W" push -q origin main
  git -C "$W" rev-parse HEAD > "$TMP/sha-merged"
  git -C "$W" checkout -q -b side && printf 'x\n' > "$W/side.txt" && git -C "$W" add side.txt && git -C "$W" commit -q -m "side"
  git -C "$W" rev-parse HEAD > "$TMP/sha-side"
  git -C "$W" checkout -q main
  printf 'y\n' > "$W/second.txt"; git -C "$W" add second.txt; git -C "$W" commit -q -m "second"; git -C "$W" push -q origin main
  printf 'z\n' > "$W/local.txt"; git -C "$W" add local.txt; git -C "$W" commit -q -m "local only"
  git -C "$W" fetch --no-tags -q origin main
  git clone -q "$O" "$W7" 2>/dev/null
) >/dev/null 2>&1 || { echo "FATAL: fixture repositories not built" >&2; exit 2; }
SHA_MERGED="$(cat "$TMP/sha-merged")"; SHA_SIDE="$(cat "$TMP/sha-side")"
[[ -n "$SHA_MERGED" && -n "$SHA_SIDE" ]] || { echo "FATAL: fixture shas not resolved" >&2; exit 2; }
SHA_ABSENT="0123456789abcdef0123456789abcdef01234567"
(
  git_fixture_env "$O3" || exit 1
  git init -q --bare "$O3" && git -C "$O3" symbolic-ref HEAD refs/heads/trunk
  git clone -q "$O3" "$W6" 2>/dev/null; git -C "$W6" checkout -q -b trunk
  sed -e "s|@URL@|$URL|g" "$FX/envelope-valid.md" > "$W6/env-valid.md"
  git -C "$W6" add -A && git -C "$W6" commit -q -m base && git -C "$W6" push -q origin trunk
  git -C "$W6" rev-parse HEAD > "$TMP/sha-trunk"
) >/dev/null 2>&1 || { echo "FATAL: trunk fixture not built" >&2; exit 2; }
SHA_TRUNK="$(cat "$TMP/sha-trunk")"
(
  git_fixture_env "$O2" || exit 1
  git init -q --bare "$O2" && git -C "$O2" symbolic-ref HEAD refs/heads/main
  git clone -q "$O2" "$W4" 2>/dev/null; git -C "$W4" checkout -q -b main
  sed -e "s|@URL@|$URL|g" "$FX/envelope-valid.md" > "$W4/env-valid.md"
  git -C "$W4" add -A && git -C "$W4" commit -q -m base && git -C "$W4" push -q origin main
  cp -a "$W4" "$W4TPL"
  git clone -q "$O2" "$W5" 2>/dev/null; git -C "$W5" checkout -q main 2>/dev/null
  printf 'moved\n' > "$W5/moved.txt"; git -C "$W5" add moved.txt; git -C "$W5" commit -q -m "origin moves"; git -C "$W5" push -q origin main
  git -C "$W5" rev-parse HEAD > "$TMP/sha-moved"
) >/dev/null 2>&1 || { echo "FATAL: stale-origin fixture not built" >&2; exit 2; }
SHA_MOVED="$(cat "$TMP/sha-moved")"

# --- scenario builders ------------------------------------------------------------------------------
SC=0
RUN_PATH="$BIN:$PATH"; RUN_REPO=""; RUN_STDIN=/dev/null
mk_comment() { # <id> <bodyfile>
  jq -n --rawfile body "$2" --arg c "$NOW_ISO" --arg iu "https://api.github.com/repos/example-org/example-repo/issues/77" --argjson id "$1" \
    '{id:$id, body:$body, user:{login:"owner-user", type:"User"}, author_association:"MEMBER", created_at:$c, updated_at:$c, issue_url:$iu}' > "$STUB_DIR/comment-$1.json"
}
scn() {
  SC=$((SC + 1)); STUB_DIR="$TMP/scn$SC"; rm -rf "$STUB_DIR"; mkdir -p "$STUB_DIR"; export STUB_DIR
  RUN_PATH="$BIN:$PATH"; RUN_REPO=""; RUN_STDIN=/dev/null
  echo "example-org/example-repo" > "$STUB_DIR/repo.txt"
  sed -e "s/@EXPIRY@/$EXP10/" -e "s/@DATE@/$TODAY/" "$FX/delegation-valid.md" > "$STUB_DIR/body.md"
  mk_comment 1001 "$STUB_DIR/body.md"
  echo '{"permission":"admin"}' > "$STUB_DIR/perm-owner-user.json"
  echo '{"number":77,"state":"open"}' > "$STUB_DIR/issue-77.json"
  jq -n --arg s "$SHA_MERGED" '{state:"MERGED", mergeCommit:{oid:$s}, baseRefName:"main"}' > "$STUB_DIR/pr-55.json"
  jq -n --arg s "$SHA_MERGED" '{state:"MERGED", mergeCommit:{oid:$s}, baseRefName:"main"}' > "$STUB_DIR/pr-120.json"
}
mkplan() { # <name> [sed -E expr]: a plan in $TMP/plans/<name>.md derived from plan-three-holds.md
  mkdir -p "$TMP/plans"
  sed -E -e "s|@URL@|$URL|g" -e "${2:-s/zzz-never-zzz/x/}" "$FXH/plan-three-holds.md" > "$TMP/plans/$1.md"
  PLAN="$TMP/plans/$1.md"
}
mkholds() { # <name> <text>: a plan whose Operator Holds section carries the standard Delegation and Envelope lines, then <text>
  mkdir -p "$TMP/plans"; PLAN="$TMP/plans/$1.md"
  { printf '# Plan (synthesized)\n\n## Operator Holds\n\nDelegation: %s\nEnvelope: env-valid.md\n\n' "$URL"; printf '%s\n' "$2"; printf '\n## Next\n'; } > "$PLAN"
}
run_h() { # <args...> ; runs in $RUN_REPO (default: the main clone) with $RUN_PATH and stdin from $RUN_STDIN
  local repo="${RUN_REPO:-$W}"
  ( cd "$repo" && git_fixture_env "$repo" && PATH="$RUN_PATH" "$BASH_BIN" "$SUT" "$@" ) <"$RUN_STDIN" >"$TMP/o" 2>"$TMP/e"
  rc=$?
  echo "$rc" > "$TMP/rc"
}
last_rc() { cat "$TMP/rc"; }
has_line() { grep -cF -- "$1" "$TMP/o"; }
machine() { grep '^holds: ' "$TMP/o" | tail -1; }
no_stub_miss() { ! grep -q 'STUB-MISS' "$STUB_DIR/calls.log" 2>/dev/null; }
expect() { # <name> <rc> <machine line>
  assert_eq "$2" "$(last_rc)" "$1: rc"
  assert_eq "$3" "$(machine)" "$1: machine line"
  no_stub_miss && { echo "  PASS: $1: no stub miss"; PASS=$((PASS + 1)); } || { echo "  FAIL: $1: gh stub refused an argv"; FAIL=$((FAIL + 1)); }
}
( b=$FAIL; : > "$TMP/o"; echo 0 > "$TMP/rc"; STUB_DIR="$TMP"; expect ctrl 1 "x" >/dev/null; [[ $FAIL -ge $((b + 2)) ]] ) \
  || { printf 'FATAL: expect cannot fail -- dispatch is neutered\n' >&2; exit 2; }
calls() { { cat "$STUB_DIR/calls.log" 2>/dev/null || true; } | grep -c -e "$1" || true; }
probed() { { cat "$STUB_DIR/calls.log" 2>/dev/null || true; } | grep -c '^pr view\|^run list' || true; }
# F4/N9: the helpers that COUNT are under controls too. no_stub_miss must see a STUB-MISS line; probed must count gate probes.
mkdir -p "$TMP/ctl-miss" "$TMP/ctl-probed"
printf 'STUB-MISS api bogus\n' > "$TMP/ctl-miss/calls.log"
( b=$FAIL; STUB_DIR="$TMP/ctl-miss"; : > "$TMP/o"; echo 0 > "$TMP/rc"; printf 'holds: x\n' > "$TMP/o"; expect ctrl 0 "holds: x" >/dev/null; [[ $FAIL -eq $((b + 1)) ]] ) \
  || { printf 'FATAL: no_stub_miss cannot see a STUB-MISS line -- a refused argv would pass\n' >&2; exit 2; }
printf 'pr view 1 --json state,mergeCommit,baseRefName\nrun list --workflow w.yml --limit 100 --json status\napi repos/o/r/issues/1\npr view 2 --json state,mergeCommit,baseRefName\n' > "$TMP/ctl-probed/calls.log"
( STUB_DIR="$TMP/ctl-probed"; [[ "$(probed)" == 3 && "$(calls 'api repos')" == 1 ]] ) \
  || { printf 'FATAL: probed/calls cannot count -- every "nothing was probed" row would pass\n' >&2; exit 2; }

echo "=== Control: three holds, one verified delegation, every gate true ==="
scn; mkplan mixed; run_h --plan "$PLAN"
expect "all discharged" 0 "holds: 3 discharged: 3 standing: 0"
assert_eq "3" "$(grep -c '^Done: ' "$TMP/o")" "each discharged hold prints a Done line"
assert_eq "1" "$(grep -c '^Done: do not ship until the earlier change has gone live. - checked: pr-merged 55$' "$TMP/o")" "XD2: a Done line prints the gate text that was true"
assert_eq "1" "$(grep -c '^Done: do not ship while a release is running. - checked: no-inflight-run example-release.yml$' "$TMP/o")" "XD2b: the no-inflight-run gate text is printed too"
assert_eq "1" "$(calls '^run list --workflow example-release.yml --limit 100 --json status$')" "no-inflight-run asks ONE run list for every state"
assert_eq "valid" "$(head -1 "$TMP/o" | sed -n 's/^delegation: \(valid\) reason=ok$/\1/p')" "the first line is the delegation verdict"
assert_eq "1" "$([ "$(probed)" -ge 3 ] && echo 1 || echo 0)" "N9: the control run probed at least three gates (so a probed count of 0 elsewhere is meaningful)"

echo "=== Arm 1: pr-merged ==="
scn; echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-55.json"; mkplan mixed; run_h --plan "$PLAN"
expect "open change stands" 1 "holds: 3 discharged: 2 standing: 1"
scn; jq -n --arg s "$SHA_SIDE" '{state:"MERGED", mergeCommit:{oid:$s}, baseRefName:"main"}' > "$STUB_DIR/pr-55.json"; mkplan mixed; run_h --plan "$PLAN"
expect "merged but not contained in HEAD stands" 1 "holds: 3 discharged: 2 standing: 1"
assert_eq "1" "$(grep -c 'live, but this work has not been brought up to date with it' "$TMP/o")" "XM1: a merged change not yet in this work says so in plain words"
scn; jq -n --arg s "$SHA_MERGED" '{state:"MERGED", mergeCommit:{oid:$s}, baseRefName:"release"}' > "$STUB_DIR/pr-55.json"; mkplan mixed; run_h --plan "$PLAN"
expect "merged into another base stands" 1 "holds: 3 discharged: 2 standing: 1"
scn; echo net > "$STUB_DIR/mode-pr"; mkplan mixed; run_h --plan "$PLAN"
expect "unreadable probe is exit 2" 2 "holds: 3 discharged: 1 standing: 2"
scn; mkplan mixed 's/pr-merged 55/pr-merged 55x/'; run_h --plan "$PLAN"
expect "malformed number is not evaluated (exit 2)" 2 "holds: 3 discharged: 2 standing: 1"
scn; jq -n --arg s "$SHA_ABSENT" '{state:"MERGED", mergeCommit:{oid:$s}, baseRefName:"main"}' > "$STUB_DIR/pr-55.json"; mkplan mixed; run_h --plan "$PLAN"
expect "HX4: a merge commit this clone does not know is exit 2, never a pass" 2 "holds: 3 discharged: 2 standing: 1"
scn; echo '{"state":"MERGED","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-55.json"; mkplan mixed; run_h --plan "$PLAN"
expect "HX10: a merged change with no merge commit recorded stands (exit 1), it is not an unreadable probe" 1 "holds: 3 discharged: 2 standing: 1"
assert_eq "1" "$(grep -c 'cannot see which version of the work' "$TMP/o")" "HX10b: and the reason is stated in plain words"
scn; X300="$(printf 'x%.0s' $(seq 1 300))"; mkholds long "- Hold: $X300
  Gate: no-inflight-run example-release.yml"; run_h --plan "$PLAN"
assert_eq "0" "$(grep -c 'x\{161\}' "$TMP/o")" "HX11: a 300-character hold is capped at 160 (no 161st character)"
assert_eq "1" "$(grep -c 'x\{160\}' "$TMP/o")" "HX11b: and exactly 160 are printed"
echo "=== Arm 1b: the default branch is resolved, not assumed (trunk, and origin/HEAD set) ==="
scn; jq -n --arg s "$SHA_TRUNK" '{state:"MERGED", mergeCommit:{oid:$s}, baseRefName:"trunk"}' > "$STUB_DIR/pr-55.json"; cp "$STUB_DIR/pr-55.json" "$STUB_DIR/pr-120.json"; mkplan mixed; RUN_REPO="$W6"; run_h --plan "$PLAN"
expect "XB1: a change merged into the repository's own default branch (trunk) counts" 0 "holds: 3 discharged: 3 standing: 0"
scn; jq -n --arg s "$SHA_TRUNK" '{state:"MERGED", mergeCommit:{oid:$s}, baseRefName:"main"}' > "$STUB_DIR/pr-55.json"; mkplan mixed; RUN_REPO="$W6"; run_h --plan "$PLAN"
expect "XB2: a change merged into a branch that is not the default one stands (a repository whose default is trunk)" 1 "holds: 3 discharged: 1 standing: 2"
scn; mkplan mixed; RUN_REPO="$W7"; run_h --plan "$PLAN"
expect "XB3: a clone whose origin/HEAD is set resolves the default branch locally" 0 "holds: 3 discharged: 3 standing: 0"
scn; mkplan mixed; RUN_REPO="$W7"; ( cd "$W7" && git remote remove origin ) >/dev/null 2>&1; run_h --plan "$PLAN"
expect "XB4: a repository with no origin cannot name its default branch, so the hold stands (exit 2)" 2 "holds: 3 discharged: 1 standing: 2"
( cd "$W7" && git remote add origin "$O" && git fetch --no-tags -q origin && git remote set-head origin -a ) >/dev/null 2>&1

echo "=== Arm 1c: origin moved after the clone was taken (the fetch is part of the check) ==="
mkdir -p "$TMP/plans"
cat > "$TMP/plans/stale.md" <<EOF
# Plan (synthesized)

## Operator Holds

Delegation: $URL
Envelope: env-valid.md

- Hold: wait until the earlier change has gone live.
  Gate: pr-merged 55
EOF
stale_run() { rm -rf "$W4"; cp -a "$W4TPL" "$W4"; RUN_REPO="$W4"; run_h --plan "$TMP/plans/stale.md"; }
scn; jq -n --arg s "$SHA_MOVED" '{state:"MERGED", mergeCommit:{oid:$s}, baseRefName:"main"}' > "$STUB_DIR/pr-55.json"; stale_run
expect "a merge commit that exists only after a fresh fetch is looked up (not in HEAD yet: the hold stands, exit 1)" 1 "holds: 1 discharged: 0 standing: 1"

echo "=== Arm 2: no-inflight-run (one list; queued, in_progress, waiting, requested and pending all keep the hold) ==="
for s in queued in_progress waiting requested pending; do
  scn; echo "[{\"status\":\"$s\"}]" > "$STUB_DIR/runs-example-release.yml.json"; mkplan mixed; run_h --plan "$PLAN"
  expect "a $s run keeps the hold" 1 "holds: 3 discharged: 2 standing: 1"
done
scn; echo '[{"status":"completed"},{"status":"completed"},{"status":"completed"}]' > "$STUB_DIR/runs-example-release.yml.json"; mkplan mixed; run_h --plan "$PLAN"
expect "XS1: finished runs do not hold anything back" 0 "holds: 3 discharged: 3 standing: 0"
scn; echo '[{"status":"completed"},{"status":"completed"},{"status":"in_progress"}]' > "$STUB_DIR/runs-example-release.yml.json"; mkplan mixed; run_h --plan "$PLAN"
expect "XS2: a live run among finished ones keeps the hold" 1 "holds: 3 discharged: 2 standing: 1"
scn; echo '[{"status":"completed"},{"status":"frobnicated"}]' > "$STUB_DIR/runs-example-release.yml.json"; mkplan mixed; run_h --plan "$PLAN"
expect "XS3: a run state this check does not know is exit 2, never read as finished" 2 "holds: 3 discharged: 2 standing: 1"
scn; echo net > "$STUB_DIR/mode-run"; mkplan mixed; run_h --plan "$PLAN"
expect "a failed run list is exit 2" 2 "holds: 3 discharged: 2 standing: 1"
scn; echo '{"not":"an array"}' > "$STUB_DIR/runs-example-release.yml.json"; mkplan mixed; run_h --plan "$PLAN"
expect "a non-array answer is exit 2" 2 "holds: 3 discharged: 2 standing: 1"
scn; echo '["not-an-object"]' > "$STUB_DIR/runs-example-release.yml.json"; mkplan mixed; run_h --plan "$PLAN"
expect "a list of non-objects is exit 2" 2 "holds: 3 discharged: 2 standing: 1"
scn; mkplan mixed 's/no-inflight-run example-release.yml/no-inflight-run ..\/evil.yml/'; run_h --plan "$PLAN"
expect "a workflow name with a path is exit 2" 2 "holds: 3 discharged: 2 standing: 1"
echo "=== Arm 2b: the re-check right before arming sees a new run ==="
scn; mkplan mixed; run_h --plan "$PLAN"; assert_eq "0" "$(last_rc)" "first look at the draft exit: clear"
echo '[{"status":"in_progress"}]' > "$STUB_DIR/runs-example-release.yml.json"; run_h --plan "$PLAN"
assert_eq "1" "$(last_rc)" "second look immediately before arming: a run started in between, the hold stands again"

echo "=== Arm 4: unknown and retired kinds, no gate, partial gates, parse shapes ==="
s_unknown() { mkplan unk 's/  Gate: pr-merged 55/  Gate: frobnicate 55/'; }
scn; s_unknown; run_h --plan "$PLAN"
expect "unknown kind never discharges (exit 2)" 2 "holds: 3 discharged: 2 standing: 1"
scn; mkplan kcase 's/  Gate: pr-merged 55/  Gate: PR-Merged 55/'; run_h --plan "$PLAN"
expect "XK1: a kind spelled in another case is an unknown kind (exit 2)" 2 "holds: 3 discharged: 2 standing: 1"
scn; mkplan cmd 's|  Gate: pr-merged 55|  Gate: command scripts/probe-ok.sh => READY|'; run_h --plan "$PLAN"
expect "XK2: the retired command kind is an unknown kind: the hold stands (exit 2)" 2 "holds: 3 discharged: 2 standing: 1"
assert_eq "0" "$(calls 'STUB-MISS')" "XK2b: no probe was attempted for the retired command kind"
scn; mkplan rg 's|  Gate: pr-merged 55|  Gate: run-green example-release.yml abc1234|'; run_h --plan "$PLAN"
expect "XK3: the retired run-green kind is an unknown kind: the hold stands (exit 2)" 2 "holds: 3 discharged: 2 standing: 1"
assert_eq "0" "$(calls ' --commit ')" "XK3b: no run list by commit was attempted"
assert_eq "1" "$(grep -c '^Could not check: do not ship until the earlier change has gone live. - ' "$TMP/o")" "XK3c: the unreadable condition is named in plain words"
s_nogate() { mkplan nogate '/  Gate: pr-merged 55/d'; }
scn; s_nogate; run_h --plan "$PLAN"
expect "a hold with no Gate line needs a person" 1 "holds: 3 discharged: 2 standing: 1"
assert_eq "1" "$(grep -c '^Needs a person: ' "$TMP/o")" "the needs-a-person line is printed"
s_twogates() { echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-9999.json"; mkplan twogates 's/^  Gate: no-inflight-run example-release.yml$/  Gate: no-inflight-run example-release.yml\n  Gate: pr-merged 9999/'; }
scn; s_twogates; run_h --plan "$PLAN"
expect "two gates, first true, second false: the hold stands" 1 "holds: 3 discharged: 2 standing: 1"
s_falsefirst() { echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-9999.json"; mkholds falsefirst $'- Hold: ship only when both are true.\n  Gate: pr-merged 9999\n  Gate: no-inflight-run example-release.yml'; }
scn; s_falsefirst; run_h --plan "$PLAN"
expect "HX2: a false gate then a true one: the later gate never wins the hold back" 1 "holds: 1 discharged: 0 standing: 1"
s_unkfirst() { mkholds unkfirst $'- Hold: ship only when both are true.\n  Gate: frobnicate 1\n  Gate: no-inflight-run example-release.yml'; }
scn; s_unkfirst; run_h --plan "$PLAN"
expect "HX3: an unknown gate then a true one: still exit 2, still standing" 2 "holds: 1 discharged: 0 standing: 1"
scn; mkplan orphan 's/^- Hold: do not ship until/  Gate: pr-merged 55\n- Hold: do not ship until/'; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "a Gate line before any Hold (with a delegation recorded) is exit 2"
assert_eq "1" "$(grep -c 'outside any hold' "$TMP/o")" "XO1: the orphan stall says so in plain words"
scn; mkplan crlf 's/$/\r/'; run_h --plan "$PLAN"
expect "a CRLF plan still evaluates" 0 "holds: 3 discharged: 3 standing: 0"
scn
cat > "$TMP/plans/reordered.md" <<EOF
# Plan (synthesized, different order and count)

## Operator Holds

- Hold: wait until the earlier change has gone live.
  Gate: pr-merged 55
- Hold: do not ship while a release is running.
  Gate: no-inflight-run example-release.yml
Delegation: $URL
Envelope: env-valid.md

## Next
EOF
run_h --plan "$TMP/plans/reordered.md"
expect "H2: two holds in a different order, Delegation and Envelope lines after the holds" 0 "holds: 2 discharged: 2 standing: 0"
scn; mkholds lcase $'- Hold: ship only when both are true.\n  Gate: no-inflight-run example-release.yml\n  gate: pr-merged 9999'; echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-9999.json"; run_h --plan "$PLAN"
expect "XG1: a lowercase gate: line after a true gate still counts (the hold stands)" 1 "holds: 1 discharged: 0 standing: 1"
scn; mkholds spaced $'- Hold: ship only when both are true.\n  Gate: no-inflight-run example-release.yml\n  Gate : pr-merged 9999'; echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-9999.json"; run_h --plan "$PLAN"
expect "XG2: a 'Gate :' line (space before the colon) still counts" 1 "holds: 1 discharged: 0 standing: 1"
scn; mkholds dashed $'- hold: ship only when both are true.\n  - gate: no-inflight-run example-release.yml\n  - Gate: pr-merged 9999'; echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-9999.json"; run_h --plan "$PLAN"
expect "XG3: a lowercase - hold: item with dashed gates is read" 1 "holds: 1 discharged: 0 standing: 1"
scn; mkholds emptygate $'- Hold: ship only when it is true.\n  Gate:'; run_h --plan "$PLAN"
expect "XG4: an empty Gate: line is a condition nobody can check (exit 2)" 2 "holds: 1 discharged: 0 standing: 1"
scn; mkholds bare $'Hold: ship only when it is true.\n  Gate: no-inflight-run example-release.yml'; run_h --plan "$PLAN"
expect "XG5: a Hold: line without the dash is still a hold" 0 "holds: 1 discharged: 1 standing: 0"
echo "=== Arm 4b: fences hide examples, and only a fence of the same character closes one ==="
scn; mkholds fenced $'- Hold: do not ship while a release is running.\n  Gate: no-inflight-run example-release.yml\n\nExample of the format:\n\n```text\n- Hold: example only\n  Gate: pr-merged 9999\nDelegation: https://github.com/example-org/example-repo/issues/1#issuecomment-9\n```'
run_h --plan "$PLAN"
expect "HX8: a fenced example hold, gate and Delegation inside the section are ignored" 0 "holds: 1 discharged: 1 standing: 0"
scn; mkholds fchar $'- Hold: do not ship while a release is running.\n  Gate: no-inflight-run example-release.yml\n\n```text\n~~~\n- Hold: still inside the backtick fence\n  Gate: pr-merged 9999\n```'
run_h --plan "$PLAN"
expect "XF1: a tilde line inside a backtick fence does not close it (one hold, not two)" 0 "holds: 1 discharged: 1 standing: 0"
scn; mkholds ftilde $'- Hold: do not ship while a release is running.\n  Gate: no-inflight-run example-release.yml\n\n~~~text\n- Hold: still inside the tilde fence\n  Gate: pr-merged 9999\n```\n- Hold: also inside\n  Gate: pr-merged 9999\n~~~'
run_h --plan "$PLAN"
expect "XF2: a backtick line inside a tilde fence does not close it" 0 "holds: 1 discharged: 1 standing: 0"
scn; mkholds fafter $'```text\n- Hold: example\n```\n- Hold: do not ship while a release is running.\n  Gate: no-inflight-run example-release.yml'
run_h --plan "$PLAN"
expect "XF3: a real hold after a closed fence is read" 0 "holds: 1 discharged: 1 standing: 0"

echo "=== Arm 4c: Operator-reserved holds are never discharged by a gate (security F7) ==="
scn; mkplan reserved 's/^- Hold: do not ship while a release is running\./- Hold: Operator-reserved: approve the new pricing page copy./'; run_h --plan "$PLAN"
expect "OR1: an Operator-reserved hold stands even though its gate is true (exit 2)" 2 "holds: 3 discharged: 2 standing: 1"
assert_eq "1" "$(grep -c '^Reserved for you: Operator-reserved: approve the new pricing page copy. - only you can clear this$' "$TMP/o")" "OR1b: it is printed as reserved, with 'only you can clear this'"
assert_eq "0" "$(calls '^run list')" "OR1c: its gate was not even probed"
scn; mkplan reserved2 's/^- Hold: do not ship while a release is running\./- Hold: OPERATOR-RESERVED: spend above the budget/'; run_h --plan "$PLAN"
expect "OR2: the prefix is read in any case" 2 "holds: 3 discharged: 2 standing: 1"
scn; mkplan reserved3 's/^- Hold: do not ship while a release is running\./- Hold: ask first, this is Operator-reserved: nothing special/'; run_h --plan "$PLAN"
expect "OR3: the words in the middle of a hold do not reserve it (it must BEGIN with the prefix)" 0 "holds: 3 discharged: 3 standing: 0"
scn; mkplan reserved4 's/^- Hold: do not ship while a release is running\./- Hold: Operator-reserved: brand copy/;/^  Gate: no-inflight-run/d'; run_h --plan "$PLAN"
expect "OR4: a reserved hold with no gate at all is reserved, not 'needs a person' by accident" 2 "holds: 3 discharged: 2 standing: 1"
assert_eq "1" "$(grep -c '^Reserved for you: ' "$TMP/o")" "OR4b: it is the reserved line"

echo "=== Arm 4d: every spelling of a hold or gate marker is read, or the run exits 2 (verification V4) ==="
NB=$'\xc2\xa0'; FW=$'\xef\xbc\x9a'; ZW=$'\xe2\x80\x8b'; SH=$'\xc2\xad'; NH=$'\xe2\x80\x91'
FIRST='- Hold: do not ship while a release is running.
  Gate: no-inflight-run example-release.yml'
spell() { # <name> <hold marker line> <gate marker line>: a second hold, spelled oddly, must be PARSED (two holds, both discharged)
  scn; mkholds "$1" "$FIRST
$2
$3"; run_h --plan "$PLAN"
  expect "V4 $1: the hold and its gate are read" 0 "holds: 2 discharged: 2 standing: 0"
}
spell star       '* Hold: wait for the earlier change.'          '  Gate: pr-merged 55'
spell numbered   '1. Hold: wait for the earlier change.'         '  Gate: pr-merged 55'
spell paren      '2) Hold: wait for the earlier change.'         '  Gate: pr-merged 55'
spell quote      '> Hold: wait for the earlier change.'          '> Gate: pr-merged 55'
spell bold       '- **Hold:** wait for the earlier change.'      '  - **Gate:** pr-merged 55'
spell boldcolon  '- **Hold**: wait for the earlier change.'      '  **Gate**: pr-merged 55'
spell underscore '- __Hold__: wait for the earlier change.'      '  __Gate__: pr-merged 55'
spell plus       '+ Hold: wait for the earlier change.'          '  + Gate: pr-merged 55'
spell fullwidth  "- Hold$FW wait for the earlier change."        "  Gate$FW pr-merged 55"
spell nbsp       "Hold$NB: wait for the earlier change."         "  Gate$NB: pr-merged 55"
spell spaced     '- hold : wait for the earlier change.'         '  gate : pr-merged 55'
spell zerowidth  "- Ho${ZW}ld: wait for the earlier change."     "  Ga${SH}te: pr-merged 55"
scn; mkholds oddprefix "$FIRST"; printf '\n## Notes\n\n* Hold: a hold hiding under another heading.\n  Gate: pr-merged 9999\n' >> "$PLAN"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "V4b: an oddly spelt hold OUTSIDE the section is counted too: exit 2, not silently dropped"
scn; mkholds oddprefix2 "$FIRST"; printf '\n## Notes\n\n1. Gate: pr-merged 9999\n' >> "$PLAN"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "V4c: so is an oddly spelt gate outside the section"

echo "=== Arm 4e: Operator-reserved is recognised however it is spelt (verification V5) ==="
resv() { # <name> <hold words>
  scn; mkholds "$1" "$FIRST
- Hold: $2
  Gate: pr-merged 55"; run_h --plan "$PLAN"
  expect "V5 $1: stands as reserved" 2 "holds: 2 discharged: 1 standing: 1"
  assert_eq "1" "$(grep -c '^Reserved for you: ' "$TMP/o")" "V5 $1: it is printed as reserved"
}
resv space       'Operator reserved: approve the pricing copy'
resv spaced      'operator-reserved : approve the pricing copy'
resv bold        '**Operator-reserved:** approve the pricing copy'
resv nbhyphen    "Operator${NH}reserved: approve the pricing copy"
resv underscore  'Operator_reserved: approve the pricing copy'
resv fwcolon     "Operator-reserved$FW approve the pricing copy"
resv quoted      '"Operator-reserved: approve the pricing copy"'
resv leadzw      "${ZW}Operator-reserved: approve the pricing copy"
resv innerzw     "Opera${ZW}tor-reser${SH}ved: approve the pricing copy"
resv leadnb      "${NB}Operator-reserved: approve the pricing copy"
resv dashed      '- Operator-reserved: approve the pricing copy'

echo "=== Arm 5: sections and headings ==="
scn; run_h --plan "$FX/holds-none.md"
expect "no Operator Holds section is a no-op" 0 "holds: 0 discharged: 0 standing: 0"
scn; printf '# Plan\n\n## Operator Holds\n\n## Next\n' > "$TMP/plans/empty.md"; run_h --plan "$TMP/plans/empty.md"
expect "an empty section is a no-op" 0 "holds: 0 discharged: 0 standing: 0"
scn; run_h --plan "$FX/holds-prose.md"
assert_eq "3" "$(last_rc)" "R: legacy prose holds (no Delegation line) are exit 3, the caller keeps its prose evaluation"
assert_eq "0" "$(grep -c '^holds: 0 discharged: 0' "$TMP/o")" "R: the prose plan does not print the all-clear line"
assert_eq "0" "$(probed)" "R: nothing was probed for a prose plan"
scn; printf '# Plan\n\n## Operator Holds\n\n- Wait for the earlier change.\n  Gate: pr-merged 55\n\n## Operator Holds\n\n- Second prose section.\n' > "$TMP/plans/prose2.md"; run_h --plan "$TMP/plans/prose2.md"
assert_eq "3" "$(last_rc)" "R2: two hold sections and an orphan Gate, but no Delegation: still exit 3 (before the orphan and multi-section checks)"
scn; printf '# Plan\n\n## Operator Holds\n\nDelegation: %s\nEnvelope: env-valid.md\n\n- Wait for the earlier change.\n\nPlain prose with no Hold items.\n' "$URL" > "$TMP/plans/zerohold.md"; run_h --plan "$TMP/plans/zerohold.md"
assert_eq "2" "$(last_rc)" "R3: a Delegation line but zero parsed holds is exit 2"
assert_eq "0" "$(grep -c '^holds: 0 discharged: 0 standing: 0$' "$TMP/o")" "R3b: it does not print the all-clear line"
scn; mkplan hx5 ''; printf '\n## Operator Holds\n\n- Hold: a second section.\n  Gate: no-inflight-run example-release.yml\n' >> "$PLAN"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "HX5: two Operator Holds sections with a delegation recorded is exit 2"
assert_eq "0" "$(probed)" "HX5b: nothing was probed"
scn; printf '# Plan\n\n```text\n## Operator Holds\n\n- Hold: an example in a fence\n  Gate: pr-merged 9999\n```\n\n## Operator Holds\n\nDelegation: %s\nEnvelope: env-valid.md\n\n- Hold: do not ship while a release is running.\n  Gate: no-inflight-run example-release.yml\n' "$URL" > "$TMP/plans/hx9.md"; run_h --plan "$TMP/plans/hx9.md"
expect "HX9: a fenced Operator Holds example before the real section is not a section" 0 "holds: 1 discharged: 1 standing: 0"
for h in '## Operator holds' '### Operator Holds' '#### OPERATOR HOLDS' '##  Operator Holds' '## Operator Holds (draft)' '## Operator Holds:'; do
  scn; mkplan hd "s/^## Operator Holds\$/$h/"; run_h --plan "$PLAN"
  expect "XH: the heading '$h' is a hold section" 0 "holds: 3 discharged: 3 standing: 0"
done
for h in '# Operator Holds' '##### Operator Holds' '## Operator Hold' '## Holds' '## Operator  Holdsy'; do
  scn; mkplan hd "s/^## Operator Holds\$/$h/"; run_h --plan "$PLAN"
  assert_eq "2" "$(last_rc)" "XH2: '$h' is not a hold section but the file carries holds: exit 2, never the all-clear"
  assert_eq "0" "$(grep -c '^holds: 0 discharged: 0 standing: 0$' "$TMP/o")" "XH2b: '$h' does not print the all-clear line"
done
scn; printf '# Plan\n\nGate: pr-merged 55\n' > "$TMP/plans/gateonly.md"; run_h --plan "$TMP/plans/gateonly.md"
assert_eq "2" "$(last_rc)" "XH3: a Gate line with no hold section anywhere is exit 2"
scn; printf '# Plan\n\n```text\n- Hold: an example\n  Gate: pr-merged 9999\n```\n' > "$TMP/plans/fenceonly.md"; run_h --plan "$TMP/plans/fenceonly.md"
assert_eq "0" "$(last_rc)" "XH4: a hold and a gate that exist only inside a fence are an example, not a hold (exit 0)"
scn; mkplan sub 's/^- Hold: wait until the second earlier change has gone live./### Notes\n\nA sub-heading inside the section.\n\n- Hold: wait until the second earlier change has gone live./'; run_h --plan "$PLAN"
expect "XH5: a deeper heading inside the section does not end it" 0 "holds: 3 discharged: 3 standing: 0"
scn; mkplan after 's/^## Acceptance Criteria$/## Acceptance Criteria\n\n- Hold: not part of the section.\n  Gate: pr-merged 9999/'; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "XH6: holds after the next same-level heading are outside the section: exit 2, never silently dropped (security N2)"
assert_eq "0" "$(calls 'repos/')" "XH6b: and nothing was verified or probed"
scn; mkplan misspelt ''; printf '\n## Operator Hold (misspelt, second)\n\n- Hold: Do not merge until Dana has signed off the copy.\n  Gate: pr-merged 9999\n' >> "$PLAN"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "XN2a: a good hold section plus a hold under a misspelt second heading is exit 2 (the hidden hold stands)"
assert_eq "1" "$(grep -c 'not inside a hold section I can read' "$TMP/o")" "XN2b: and says so in plain words"
assert_eq "0" "$(grep -c '^Done: ' "$TMP/o")" "XN2c: nothing is discharged"
scn; printf '# Plan\n\n## Operator Holds\n\n## Operator Hold (misspelt)\n\n- Hold: x\n  Gate: pr-merged 9999\n' > "$TMP/plans/emptyplusmisspelt.md"; run_h --plan "$TMP/plans/emptyplusmisspelt.md"
assert_eq "2" "$(last_rc)" "XN2f: an EMPTY hold section plus holds under a misspelt heading is exit 2, not the all-clear"
scn; mkplan fencedextra ''; printf '\nExample, not a hold:\n\n```text\n- Hold: an example\n  Gate: pr-merged 9999\n```\n' >> "$PLAN"; run_h --plan "$PLAN"
expect "XN2d: a fenced example outside the section is not a hold" 0 "holds: 3 discharged: 3 standing: 0"
scn; printf '# Plan\n\n## Operator Holds\n\n- Wait for the earlier change.\n\n## Operator Hold (misspelt)\n\n- Hold: x\n  Gate: pr-merged 9999\n' > "$TMP/plans/prose-misspelt.md"; run_h --plan "$TMP/plans/prose-misspelt.md"
assert_eq "3" "$(last_rc)" "XN2e: with no Delegation line the prose path (exit 3) still comes first"

echo "=== Arm 6: delegation and envelope ==="
s_nodeleg() { mkplan nodeleg '/^Delegation: /d'; }
scn; s_nodeleg; run_h --plan "$PLAN"
assert_eq "3" "$(last_rc)" "no delegation recorded is exit 3 (the caller keeps its prose evaluation)"
assert_eq "3" "$(sed -n 's/^holds: 3 discharged: 0 standing: 3$/3/p' "$TMP/o")" "no delegation: the holds are counted but none discharged"
assert_eq "0" "$(probed)" "nothing was probed when no delegation is recorded"
assert_eq "0" "$(calls 'repos/')" "nothing was verified when no delegation is recorded"
scn; printf '# Plan\n\n## Operator Holds\n\n- Hold: do not ship while a release is running.\n  Gate: no-inflight-run example-release.yml\n\n```text\nDelegation: %s\n```\n' "$URL" > "$TMP/plans/fdeleg.md"
run_h --plan "$TMP/plans/fdeleg.md"
assert_eq "3" "$(last_rc)" "XD3: a Delegation line that exists only inside a fence is no delegation (exit 3)"
scn; mkholds two $'- Hold: do not ship while a release is running.\n  Gate: no-inflight-run example-release.yml\nDelegation: https://github.com/example-org/example-repo/issues/77#issuecomment-1002'; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "HX7: two Delegation lines are exit 2 (the second may be the one that is not valid)"
assert_eq "0" "$(probed)" "HX7b: no gate was probed"
assert_eq "0" "$(calls 'repos/')" "HX7c: nothing was verified"
scn; mkplan noenv '/^Envelope: /d'; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "XE1: a Delegation line without an Envelope line is exit 2: the hold stands"
assert_eq "0" "$(probed)" "XE1b: no gate was probed"
assert_eq "0" "$(calls 'repos/')" "XE1c: the delegation was not verified without an envelope"
assert_eq "3" "$(grep -c '^Could not check: ' "$TMP/o")" "XE1d: each hold says it could not be checked"
assert_eq "1" "$(grep -c 'written procedure' "$TMP/o")" "XE1e: the stall names the missing written procedure in plain words"
scn; mkplan twoenv 's|^Envelope: env-valid.md|Envelope: env-valid.md\nEnvelope: env-two.md|'; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "XE2: two Envelope lines are exit 2"
s_edited() { jq --arg u "${TODAY}T01:00:00Z" '.updated_at = $u' "$STUB_DIR/comment-1001.json" > "$STUB_DIR/c.tmp" && cat "$STUB_DIR/c.tmp" > "$STUB_DIR/comment-1001.json"; mkplan mixed; }
scn; s_edited; run_h --plan "$PLAN"
expect "an edited delegation leaves every hold standing" 1 "holds: 3 discharged: 0 standing: 3"
assert_eq "delegation: invalid reason=edited" "$(head -1 "$TMP/o")" "XD4: the FIRST line says why: the verifier's state and reason"
assert_eq "0" "$(probed)" "no gate is probed under an invalid delegation"
scn; echo net > "$STUB_DIR/mode-comment-1001"; mkplan mixed; run_h --plan "$PLAN"
expect "an unreadable delegation is exit 2 and every hold stands" 2 "holds: 3 discharged: 0 standing: 3"
assert_eq "1" "$(head -1 "$TMP/o" | grep -cE '^delegation: unverifiable reason=[a-z0-9-]+$')" "XD5: the first line is the verifier's unverifiable verdict with a reason token"
scn; echo 404 > "$STUB_DIR/mode-comment-1001"; mkplan mixed; run_h --plan "$PLAN"
expect "a deleted (revoked) delegation is exit 2 and every hold stands" 2 "holds: 3 discharged: 0 standing: 3"
scn; mkplan mixed; mkdir -p "$TMP/lonely/skills/ship/scripts"; cp "$SUT_REAL" "$TMP/lonely/skills/ship/scripts/hold-gate-eval.sh"
SUT="$TMP/lonely/skills/ship/scripts/hold-gate-eval.sh"; run_h --plan "$PLAN"; SUT="$SUT_REAL"
assert_eq "2" "$(last_rc)" "a missing verifier is exit 2, never a pass"
scn; mkplan wrongenv 's|^Envelope: env-valid.md|Envelope: missing.md|'; run_h --plan "$PLAN"
expect "an envelope that does not verify leaves every hold standing" 1 "holds: 3 discharged: 0 standing: 3"
echo "--- the verifier's rc AND first line must both say valid (a fake verifier in a mirrored tree) ---"
FAKE="$TMP/fakev"; mkdir -p "$FAKE/skills/ship/scripts" "$FAKE/scripts"; cp "$SUT_REAL" "$FAKE/skills/ship/scripts/hold-gate-eval.sh"
cat > "$FAKE/scripts/delegation-verify.sh" <<'FAKEV'
#!/usr/bin/env bash
# fake verifier: prints $FAKE_V_OUT (printf %b), exits $FAKE_V_RC, and records how many stdin bytes it was handed
n="$(cat | wc -c | tr -d ' ')"; echo "$n" >> "${STUB_DIR:?}/v-stdin-bytes"
[ -z "${FAKE_V_SLEEP-}" ] || exec sleep "$FAKE_V_SLEEP"
[ -z "${FAKE_V_OUT-}" ] || printf '%b' "$FAKE_V_OUT"
exit "${FAKE_V_RC:-0}"
FAKEV
fakev() { # <out> <rc>
  scn; mkplan mixed; export FAKE_V_OUT="$1" FAKE_V_RC="$2"
  SUT="$FAKE/skills/ship/scripts/hold-gate-eval.sh"; run_h --plan "$PLAN"; SUT="$SUT_REAL"
}
fakev 'delegation: valid reason=ok\n' 0
expect "FV1: rc 0 and a valid first line discharge" 0 "holds: 3 discharged: 3 standing: 0"
fakev 'delegation: valid reason=ok\n' 7
assert_eq "2" "$(last_rc)" "FV2: a valid line with a non-zero rc is exit 2 (the rc is checked too)"
assert_eq "1" "$(head -1 "$TMP/o" | grep -cE '^delegation: ')" "FV2b: the first line is still a delegation verdict"
fakev 'delegation: invalid reason=expired\n' 0
assert_eq "2" "$(last_rc)" "FV3: an invalid line with rc 0 is a contradiction: exit 2"
fakev 'delegation: invalid reason=expired\n' 1
assert_eq "1" "$(last_rc)" "FV4: rc 1 with an invalid line is exit 1"
assert_eq "delegation: invalid reason=expired" "$(head -1 "$TMP/o")" "FV4b: the reason is copied to the first line"
fakev '' 0
assert_eq "2" "$(last_rc)" "FV5: a verifier that prints nothing is exit 2"
assert_eq "delegation: unverifiable reason=no-answer" "$(head -1 "$TMP/o")" "FV5b: and says it gave no answer"
fakev 'garbage\n' 1
assert_eq "2" "$(last_rc)" "FV6: an unreadable first line is exit 2 even with rc 1"
fakev 'delegation: unverifiable reason=api-error\n' 2
assert_eq "2" "$(last_rc)" "FV7: unverifiable with rc 2 is exit 2"
fakev 'delegation: invalid reason=has;shell$(x)\n' 1
assert_eq "2" "$(last_rc)" "FV8: a reason token with shell characters is not trusted: exit 2"
assert_eq "0" "$(grep -c 'shell' "$TMP/o")" "FV8b: and is not echoed"
scn; mkplan mixed; export FAKE_V_OUT='delegation: valid reason=ok\n' FAKE_V_RC=0; printf 'ten bytes!' > "$TMP/stdin-ten"; RUN_STDIN="$TMP/stdin-ten"
SUT="$FAKE/skills/ship/scripts/hold-gate-eval.sh"; run_h --plan "$PLAN"; SUT="$SUT_REAL"
assert_eq "0" "$(sort -u "$STUB_DIR/v-stdin-bytes" | tr '\n' ' ' | tr -d ' ')" "XI1: the verifier is handed no stdin"
unset FAKE_V_OUT FAKE_V_RC

echo "--- a verifier that hangs is cut off at the (test-shortened) time limit and the holds stand (testdesign N15) ---"
scn; mkplan mixed; export FAKE_V_OUT='delegation: valid reason=ok\n' FAKE_V_RC=0 FAKE_V_SLEEP=8 HGE_VERIFY_TIMEOUT=2
t0=$SECONDS; SUT="$FAKE/skills/ship/scripts/hold-gate-eval.sh"; run_h --plan "$PLAN"; SUT="$SUT_REAL"; el=$((SECONDS - t0)); unset FAKE_V_OUT FAKE_V_RC FAKE_V_SLEEP HGE_VERIFY_TIMEOUT
assert_eq "2" "$(last_rc)" "VT1: a verifier that never answers leaves every hold standing (exit 2)"
assert_eq "delegation: unverifiable reason=no-answer" "$(head -1 "$TMP/o")" "VT1b: and says it got no answer"
assert_eq "1" "$([ "$el" -lt 6 ] && echo 1 || echo 0)" "VT1c: it was cut off at the shortened limit (took ${el}s, not the 8s the fake sleeps)"
scn; mkplan mixed; export FAKE_V_OUT='delegation: valid reason=ok\n' FAKE_V_RC=0 HGE_VERIFY_TIMEOUT=900
SUT="$FAKE/skills/ship/scripts/hold-gate-eval.sh"; run_h --plan "$PLAN"; SUT="$SUT_REAL"; unset FAKE_V_OUT FAKE_V_RC HGE_VERIFY_TIMEOUT
assert_eq "0" "$(last_rc)" "VT2: a limit above 60 is ignored (the knob can only shorten) and a quick verifier still passes"

echo "=== Arm 6b: stdin hygiene (a gh call that drains stdin must not swallow the remaining gates or holds) ==="
scn; touch "$STUB_DIR/eat-stdin"; echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-9999.json"; mkplan eat 's/^  Gate: no-inflight-run example-release.yml$/  Gate: no-inflight-run example-release.yml\n  Gate: pr-merged 9999/'; run_h --plan "$PLAN"
expect "XI2: a gh that drains stdin does not hide the second gate of a hold" 1 "holds: 3 discharged: 2 standing: 1"
scn; touch "$STUB_DIR/eat-stdin"; echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-120.json"; mkplan eat2; run_h --plan "$PLAN"
expect "XI3: a gh that drains stdin does not hide a later hold" 1 "holds: 3 discharged: 2 standing: 1"
scn; touch "$STUB_DIR/eat-stdin"; mkplan eat3; RUN_STDIN="$TMP/stdin-ten"; run_h --plan "$PLAN"
assert_eq "0" "$(grep -vcx 0 "$STUB_DIR/stdin-bytes")" "XI4: every gh call, the verifier's included, saw an empty stdin"
assert_eq "1" "$([ "$(wc -l < "$STUB_DIR/stdin-bytes" | tr -d ' ')" -ge 6 ] && echo 1 || echo 0)" "XI4b: and there were gh calls to see it"

echo "=== Arm 6c: no time-limit tool, and tools missing before and after the no-delegation exit ==="
mkbin() { # <dir> <tools to leave out...>: a PATH with the usual tools (symlinks) and the gh stub
  local d="$1" t o p; shift; assert_fixture_dir "$d"; rm -rf "$d"; mkdir -p "$d"
  for t in bash git jq awk sed tr cut grep cat head tail wc mktemp rm dirname basename cmp date sort uniq env sleep timeout gtimeout expr tee touch mkdir ln cp mv ls id uname xargs true false find stat sha256sum shasum openssl od readlink realpath; do
    for o in "$@"; do [[ "$t" == "$o" ]] && continue 2; done
    p="$(command -v "$t" 2>/dev/null)"; [[ "$p" == /* && -x "$p" ]] && ln -sf "$p" "$d/$t"
  done
  cp "$BIN/gh" "$d/gh"
}
mkbin "$TMP/nobin-timeout" timeout gtimeout
mkbin "$TMP/nobin-jq" jq
mkbin "$TMP/nobin-ok"
scn; mkplan mixed; RUN_PATH="$TMP/nobin-ok"; run_h --plan "$PLAN"
expect "XT0: the reduced PATH itself still evaluates (instrument control)" 0 "holds: 3 discharged: 3 standing: 0"
scn; mkplan mixed; RUN_PATH="$TMP/nobin-timeout"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "XT1: no timeout tool: exit 2, the holds stand"
assert_eq "1" "$(cat "$TMP/o" "$TMP/e" | grep -c 'time limit')" "XT1b: and the reason is named in plain words"
assert_eq "0" "$(calls 'repos/')" "XT1c: nothing was verified without a time limit"
scn; run_h_prose() { RUN_PATH="$1"; run_h --plan "$FX/holds-prose.md"; }
scn; run_h_prose "$TMP/nobin-timeout"
assert_eq "3" "$(last_rc)" "XT2: legacy prose holds with no timeout tool are still exit 3 (the tool check comes after the no-delegation exit)"
scn; run_h_prose "$TMP/nobin-jq"
assert_eq "3" "$(last_rc)" "XT3: legacy prose holds with no jq are still exit 3"
scn; RUN_PATH="$TMP/nobin-timeout"; run_h --plan "$FX/holds-none.md"
assert_eq "0" "$(last_rc)" "XT4: no hold section with no timeout tool is still a no-op (exit 0)"
scn; mkplan mixed; RUN_PATH="$TMP/nobin-jq"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "XT5: a recorded delegation with no jq is exit 2"

echo "=== Arm 7: retired grammar is gone from the script ==="
assert_eq "0" "$(grep -c 'gate_command\|gate_run_green' "$SUT_REAL")" "R1: no command or run-green evaluator remains in the script"
assert_eq "1" "$(grep -c 'are deferred' "$SUT_REAL")" "R1b: the header says command and run-green are deferred"
assert_eq "1" "$(grep -c 'plan mode verifies' "$SUT_REAL")" "XHD1: the header says plan mode verifies the delegation"
assert_eq "1" "$(grep -c -- '--file mode does not' "$SUT_REAL")" "XHD2: and that --file mode does not"

echo "=== Arm 9: envelope mode ==="
scn; run_h --file env-valid.md --section "Production Envelope"
expect "envelope preconditions all true" 0 "holds: 1 discharged: 1 standing: 0"
scn; echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-120.json"; run_h --file env-valid.md --section "Production Envelope"
expect "one precondition false" 1 "holds: 1 discharged: 0 standing: 1"
scn; run_h --file env-two.md --section "Production Envelope"
assert_eq "2" "$(last_rc)" "two matching sections is exit 2 (name the one)"
scn; run_h --file env-two.md --section "alpha merge"
expect "H2: second section chosen by title (alpha)" 0 "holds: 1 discharged: 1 standing: 0"
scn; run_h --file env-two.md --section "beta dispatch"
expect "H2: second section chosen by title (beta)" 0 "holds: 1 discharged: 1 standing: 0"
scn; run_h --file env-two.md --section "BETA Dispatch"
expect "XP1: the title is matched without regard to case" 0 "holds: 1 discharged: 1 standing: 0"
scn; run_h --file "env-two.md#beta dispatch"
expect "XP2: --file accepts path#title (the verifier's own address)" 0 "holds: 1 discharged: 1 standing: 0"
scn; run_h --file "env-two.md#Production Envelope - alpha merge"
expect "XP3: path#title with the full heading text" 0 "holds: 1 discharged: 1 standing: 0"
scn; run_h --file "env-two.md#nonesuch"
assert_eq "2" "$(last_rc)" "XP4: path#title naming no section is exit 2"
scn; run_h --file "env-two.md#alpha merge" --section "alpha merge"
assert_eq "2" "$(last_rc)" "XP5: the title named twice (#title and --section) is a usage error, exit 2"
scn; run_h --file "env-valid.md#"
assert_eq "2" "$(last_rc)" "XP6: path# with an empty title is exit 2"
scn; run_h --file env-two.md --section "nonesuch"
assert_eq "2" "$(last_rc)" "a section that does not exist is exit 2"
scn; run_h --file env-nogate.md --section "Production Envelope"
assert_eq "2" "$(last_rc)" "an envelope with no gate is exit 2"
assert_eq "0" "$(calls 'repos/.*comments')" "envelope mode does not re-verify the delegation (the caller just did)"
scn; run_h --file env-lvl3.md --section "Production Envelope"
expect "XP7: a level-3 mixed-case envelope heading is found" 0 "holds: 1 discharged: 1 standing: 0"
scn; run_h --file env-cmd.md --section "Production Envelope"
expect "XP8: a retired command precondition in an envelope stands (exit 2)" 2 "holds: 1 discharged: 0 standing: 1"
echo "--- --file reads the committed blob (HEAD), never the working tree (security N4) ---"
scn; echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-120.json"
sed -i.bak '/^- Gate: pr-merged 120$/d' "$W/env-valid.md"; rm -f "$W/env-valid.md.bak"; run_h --file env-valid.md --section "Production Envelope"; git -C "$W" checkout -q -- env-valid.md
expect "XN4a: deleting the false precondition in the working tree does not change the answer (HEAD still has it)" 1 "holds: 1 discharged: 0 standing: 1"
scn; sed -i.bak 's/^- Gate: pr-merged 120$/- Gate: pr-merged 9999/' "$W/env-valid.md"; rm -f "$W/env-valid.md.bak"; run_h --file env-valid.md --section "Production Envelope"; git -C "$W" checkout -q -- env-valid.md
expect "XN4b: making a precondition false in the working tree does not change the answer either" 0 "holds: 1 discharged: 1 standing: 0"
scn; cp "$W/env-valid.md" "$W/env-untracked.md"; run_h --file env-untracked.md --section "Production Envelope"; rm -f "$W/env-untracked.md"
assert_eq "2" "$(last_rc)" "XN4c: an envelope file that is not committed is exit 2"
assert_eq "0" "$(probed)" "XN4d: and nothing was probed for it"
scn; run_h --file env-link.md --section "Production Envelope"
assert_eq "2" "$(last_rc)" "XN4e: a committed symlink is not a regular file: exit 2"
scn; run_h --file /etc/hostname --section x;                 assert_eq "2" "$(last_rc)" "XN4f: an absolute path is exit 2"
scn; run_h --file ../env-valid.md --section "Production Envelope"; assert_eq "2" "$(last_rc)" "XN4g: a path with .. is exit 2"
scn; run_h --file 'env-*.md' --section "Production Envelope"; assert_eq "2" "$(last_rc)" "XN4h: a glob is exit 2"

echo "=== Arm 10: usage ==="
scn; run_h;                                   assert_eq "2" "$(last_rc)" "no arguments is exit 2"
scn; run_h --plan "$FX/holds-none.md" --file "$W/env-valid.md" --section x; assert_eq "2" "$(last_rc)" "--plan with --file is exit 2"
scn; run_h --plan "$TMP/no-such-plan.md";     assert_eq "2" "$(last_rc)" "a missing plan file is exit 2 (not an all-clear)"
scn; run_h --bogus;                           assert_eq "2" "$(last_rc)" "an unknown flag is exit 2"
scn; run_h --file env-valid.md;               assert_eq "2" "$(last_rc)" "--file without --section or #title is exit 2"

echo "=== Arm 11: the human lines carry no jargon ==="
jargon_hits() { # <outfile>: count lines (other than the machine lines) with a denylisted word
  grep -v '^\(holds\|delegation\): ' "$1" | grep -E -c '(^|[^A-Za-z])(SHA|HEAD|PR)([^A-Za-z]|$)|#[0-9]+' || true
}
jargon_hits_ci() {
  grep -v '^\(holds\|delegation\): ' "$1" | grep -i -E -c '(^|[^a-z])(patch-id|rebase|merge-base|stdout|diff|commit|draft|pull request|branch|unarmed|hash|token|endpoint|registry|runbook)([^a-z]|$)' || true
}
for variant in mixed nogate unk uptodate edited noenv nodeleg-tools reserved nullmerge; do
  scn
  case "$variant" in
    mixed) mkplan v ;; nogate) s_nogate ;; unk) s_unknown ;;
    uptodate) jq -n --arg s "$SHA_SIDE" '{state:"MERGED", mergeCommit:{oid:$s}, baseRefName:"main"}' > "$STUB_DIR/pr-55.json"; mkplan v ;;
    edited) s_edited ;;
    noenv) mkplan noenv '/^Envelope: /d' ;;
    nodeleg-tools) mkplan v; RUN_PATH="$TMP/nobin-timeout" ;;
    reserved) mkplan v 's/^- Hold: do not ship while a release is running\./- Hold: Operator-reserved: approve the new pricing copy./' ;;
    nullmerge) echo '{"state":"MERGED","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-55.json"; mkplan v ;;
  esac
  run_h --plan "$PLAN"
  cp "$TMP/o" "$TMP/human-$variant.txt"; cat "$TMP/e" >> "$TMP/human-$variant.txt"
  assert_eq "1" "$([[ -s "$TMP/human-$variant.txt" ]] && echo 1 || echo 0)" "the $variant output is not empty (a jargon count of 0 on nothing proves nothing)"
  assert_eq "0" "$(jargon_hits "$TMP/human-$variant.txt")" "no uppercase jargon or number token in the $variant output"
  assert_eq "0" "$(jargon_hits_ci "$TMP/human-$variant.txt")" "no denylisted word in the $variant output"
done
printf 'see the PR for the SHA\n' > "$TMP/jargon-control.txt"
assert_eq "1" "$(jargon_hits "$TMP/jargon-control.txt")" "instrument: the uppercase jargon check can fail"
printf 'rebase the draft first\nplain line\n' > "$TMP/jargon-control-ci.txt"
assert_eq "1" "$(jargon_hits_ci "$TMP/jargon-control-ci.txt")" "instrument: the lowercase jargon check can fail (HG jargon_hits_ci)"
for jw in hash token endpoint registry runbook; do
  printf 'the %s was refused\nplain line\n' "$jw" > "$TMP/jargon-control-$jw.txt"
  assert_eq "1" "$(jargon_hits_ci "$TMP/jargon-control-$jw.txt")" "instrument: the denylist catches '$jw'"
done
printf 'see knowledge-base/engineering/operations/runbooks/x.md\n' > "$TMP/jargon-control-path.txt"
assert_eq "0" "$(jargon_hits_ci "$TMP/jargon-control-path.txt")" "instrument: a path through a runbooks folder is not the word runbook"
printf 'holds: 3 discharged: 0 standing: 3\ndelegation: invalid reason=rebase\n' > "$TMP/jargon-control-m.txt"
assert_eq "0" "$(( $(jargon_hits "$TMP/jargon-control-m.txt") + $(jargon_hits_ci "$TMP/jargon-control-m.txt") ))" "instrument: the machine lines are excluded from the jargon check"

echo "=== Arm 11b: control characters and bidi marks in a hold's words do not reach the output ==="
scn; mkdir -p "$TMP/plans"
{ printf '# Plan\n\n## Operator Holds\n\nDelegation: %s\nEnvelope: env-valid.md\n\n' "$URL"; printf -- '- Hold: do not ship \302\205red text \342\200\256evil\342\200\250 here\n  Gate: no-inflight-run example-release.yml\n' ; } > "$TMP/plans/ctl.md"
run_h --plan "$TMP/plans/ctl.md"
expect "HX6: a hold with C1 controls and bidi marks still evaluates" 0 "holds: 1 discharged: 1 standing: 0"
assert_eq "0" "$(LC_ALL=C grep -c "$(printf '\302\205')" "$TMP/o")" "HX6b: no C1 control character reaches the output"
assert_eq "0" "$(LC_ALL=C grep -c "$(printf '\342\200\256')" "$TMP/o")" "HX6d: no bidi override reaches the output"
assert_eq "0" "$(LC_ALL=C grep -c "$(printf '\342\200\250')" "$TMP/o")" "HX6e: no line-separator mark reaches the output"
echo "--- a NUL, or any C0 control byte but tab, CR and LF, anywhere in the file is exit 2 before anything is read (FR-SEC) ---"
for cb in '\033' '\007' '\000' '\001' '\010' '\013' '\014' '\016' '\037'; do
  scn; { printf '# Plan\n\n## Operator Holds\n\nDelegation: %s\nEnvelope: env-valid.md\n\n' "$URL"; printf -- "- Hold: do not ship while a release is running.$cb\n  Gate: no-inflight-run example-release.yml\n"; } > "$TMP/plans/cb.md"; run_h --plan "$TMP/plans/cb.md"
  assert_eq "2" "$(last_rc)" "HX6f: the control byte $cb in the plan is exit 2"
  assert_eq "1" "$(has_line "The file holds a control character I cannot read safely")" "HX6g: and says so in plain words ($cb)"
  assert_eq "0" "$(grep -c '^Done: ' "$TMP/o")" "HX6h: nothing is discharged ($cb)"
  assert_eq "0" "$(probed)" "HX6i: nothing was probed ($cb)"
done
scn; { printf '# Plan\n\n## Operator Holds\n\nDelegation: %s\nEnvelope: env-valid.md\n\n' "$URL"; printf -- "- Hold: do not ship while a release is running.\n  Gate: no-inflight-run example-release.yml\t\r\n"; } > "$TMP/plans/cb2.md"; run_h --plan "$TMP/plans/cb2.md"
expect "HX6j: instrument: a tab and a carriage return are fine" 0 "holds: 1 discharged: 1 standing: 0"
scn; { printf '# Plan\n\n## Operator Holds\n\n- Wait for the earlier change.\n  Gate: pr-merged 55 \000\n'; } > "$TMP/plans/cb3.md"; run_h --plan "$TMP/plans/cb3.md"
assert_eq "2" "$(last_rc)" "HX6k: a NUL in a legacy prose plan is exit 2 too (fail closed, before the no-delegation exit)"
scn; run_h --file env-valid.md --section "Production Envelope"; assert_eq "0" "$(last_rc)" "HX6l: instrument: the envelope file itself has no control byte"

echo "=== Arm 12: every gh call was a read ==="
bad=0
for f in "$TMP"/scn*/calls.log; do
  [[ -f "$f" ]] || continue
  n="$(grep -vcE '^(api repos/[A-Za-z0-9_./-]+|repo view --json nameWithOwner --jq \.nameWithOwner|pr view [0-9]+ --json state,mergeCommit,baseRefName|run list --workflow [A-Za-z0-9._-]+ --limit 100 --json status)$' "$f")"
  bad=$((bad + n))
done
assert_eq "0" "$bad" "no gh call outside the read-only shapes across all scenarios"
assert_eq "0" "$(cat "$TMP"/scn*/calls.log | grep -cE ' (-X|--method|-f|-F|--field|--input) |^(issue|pr) (comment|edit|close|merge)|^workflow run')" "no write verb reached gh"

arm_begin wa
echo "=== Arm 14: web-acceptance (the hold backed by a founder's recorded decision) ==="
# THE SEAM: `doppler` and `curl` are PATH stubs that answer only the exact argv shapes the evaluator is expected to use and
# refuse every other argv with exit 64. The PATH for these runs is a hermetic directory of symlinks that holds NEITHER a real
# curl NOR a real doppler, so a missing stub can never become a network call. The committed text is read from repository $W.
WSTUB="$TMP/wastubs"; mkdir -p "$WSTUB"
cat > "$WSTUB/doppler" <<'STUB'
#!/usr/bin/env bash
d="${STUB_DIR:?}"
echo "doppler $*" >> "$d/doppler-argv.log"
if [ -f "$d/eat-stdin" ]; then n="$(cat | wc -c | tr -d ' ')"; echo "$n" >> "$d/stdin-bytes"; fi
[ "$*" = "secrets get LEGAL_ACCEPTANCE_VERIFY_TOKEN --plain --project soleur --config prd" ] \
  || { echo "STUB-MISS $*" >> "$d/doppler-argv.log"; echo "doppler stub: unsupported argv" >&2; exit 64; }
[ ! -f "$d/doppler-fail" ] || { echo "Doppler Error: could not read the secret" >&2; exit 1; }
cat "$d/doppler-token"
STUB
cat > "$WSTUB/curl" <<'STUB'
#!/usr/bin/env bash
d="${STUB_DIR:?}"
{ printf 'curl'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; } >> "$d/curl-argv.log"
tls="${SSLKEYLOGFILE+x}${CURL_CA_BUNDLE+x}${SSL_CERT_FILE+x}${SSL_CERT_DIR+x}${CURL_HOME+x}${HOSTALIASES+x}${LOCALDOMAIN+x}${RES_OPTIONS+x}${OPENSSL_CONF+x}${OPENSSL_MODULES+x}${LD_PRELOAD+x}${LD_AUDIT+x}${LD_LIBRARY_PATH+x}"
if [ -f "$d/eat-stdin" ]; then n="$(cat | wc -c | tr -d ' ')"; echo "$n" >> "$d/stdin-bytes"; fi
miss() { echo "STUB-MISS $*" >> "$d/curl-argv.log"; echo "curl stub: unsupported argv: $1" >&2; exit 64; }
[ -z "$tls" ] || miss "tls environment visible"
[ "$#" -eq 21 ] || miss "count"
[ "$1" = "--disable" ] && [ "$2" = "--noproxy" ] && [ "$3" = "*" ] && [ "$4" = "--proto" ] && [ "$5" = "=https" ] \
  && [ "$6" = "--max-redirs" ] && [ "$7" = "0" ] && [ "${8}" = "--connect-timeout" ] && [ "${9}" = "5" ] \
  && [ "${10}" = "--max-time" ] && [ "${11}" = "15" ] && [ "${12}" = "--max-filesize" ] && [ "${13}" = "4096" ] \
  && [ "${14}" = "-sS" ] && [ "${15}" = "-o" ] && [ "${17}" = "-w" ] && [ "${18}" = '%{http_code}' ] && [ "${19}" = "--config" ] || miss "flags"
out="${16}"; cfg="${20}"; url="${21}"
[[ "$url" =~ ^https://app\.soleur\.ai/api/internal/legal-acceptance/[a-z0-9][a-z0-9-]{0,62}\?hash=[0-9a-f]{64}$ ]] || miss "url"
echo "$url" >> "$d/curl-url.log"
[ -f "$cfg" ] || miss "no config"
[ -n "$(find "$cfg" -perm 600 -print 2>/dev/null)" ] || miss "config mode"
rc=0; [ ! -f "$d/curl-rc" ] || rc="$(cat "$d/curl-rc")"
[ "$rc" = 0 ] || { printf '000'; exit "$rc"; }
st=200; [ ! -f "$d/curl-status" ] || st="$(cat "$d/curl-status")"
want="header = \"Authorization: Bearer $(cat "$d/doppler-token")\""
[ "$(cat "$cfg")" = "$want" ] || st=401
: > "$out"
[ ! -f "$d/curl-body" ] || cat "$d/curl-body" > "$out"
printf '%s' "$st"
STUB
chmod +x "$WSTUB/doppler" "$WSTUB/curl"
mkwabin() { # <dir> <omit...>: the usual tools + the gh stub + the doppler and curl stubs, minus what is named
  local d="$1"; shift; mkbin "$d" "$@"; cp "$BIN/gh" "$d/gh"
  case " $* " in *" doppler "*) ;; *) cp "$WSTUB/doppler" "$d/doppler" ;; esac
  case " $* " in *" curl "*) ;; *) cp "$WSTUB/curl" "$d/curl" ;; esac
}
WABIN="$TMP/wabin"; mkwabin "$WABIN"
mkwabin "$TMP/wabin-nocurl" curl
mkwabin "$TMP/wabin-nodoppler" doppler
mkwabin "$TMP/wabin-nohash" sha256sum shasum
mkwabin "$TMP/wabin-shaonly" sha256sum
( cd "$TMP" && env -i PATH="$WABIN" STUB_DIR="$TMP" "$BASH_BIN" -c 'doppler bogus' ) >/dev/null 2>&1; w1=$?
assert_eq "64" "$w1" "WH1: the doppler stub refuses an argv it does not know (exit 64)"
( cd "$TMP" && env -i PATH="$WABIN" STUB_DIR="$TMP" "$BASH_BIN" -c 'curl --bogus' ) >/dev/null 2>&1; w2=$?
assert_eq "64" "$w2" "WH2: the curl stub refuses an argv it does not know (exit 64)"
( cd "$TMP" && env -i PATH="$WABIN" "$BASH_BIN" -c 'command -v curl >/dev/null && command -v doppler >/dev/null' ) >/dev/null 2>&1; w3=$?
assert_eq "0" "$w3" "WH3: instrument: the hermetic PATH carries both stubs"
( cd "$TMP" && env -i PATH="$TMP/wabin-nocurl" "$BASH_BIN" -c 'command -v curl' ) >/dev/null 2>&1; w4=$?
assert_eq "1" "$w4" "WH4: the no-curl PATH has no curl at all (no real network tool is reachable by accident)"
( cd "$TMP" && env -i PATH="$TMP/wabin-nodoppler" "$BASH_BIN" -c 'command -v doppler' ) >/dev/null 2>&1; w5=$?
assert_eq "1" "$w5" "WH5: the no-doppler PATH has no doppler at all"

WA_H="0a711a0e425567eccd9050ae62564317493a22f564f6f862c7b24d89b9956c76"   # sha256 of fixtures/hold-gate-eval/web-acceptance-text.md, pinned
WA_H2="$(printf 'f%.0s' $(seq 1 64))"
WA_TOK='SYNTHtok0123456789abcdefghijklmnopqrstuvwxyzQ9x3'
WA_DATE_JSON='"2026-11-05T10:15:30.123456+00:00"'
assert_eq "$WA_H" "$(sha256sum "$FXH/web-acceptance-text.md" | cut -c1-64)" "WF1: the pinned hash is the sha256 of the fixture text (sha256sum)"
assert_eq "$WA_H" "$(shasum -a 256 < "$FXH/web-acceptance-text.md" | cut -c1-64)" "WF1b: and of shasum -a 256 (the two tools agree)"
assert_eq "$WA_H" "$(git -C "$W" cat-file blob "HEAD:apps/web-platform/server/legal-acceptance/texts/wa-key.md" | sha256sum | cut -c1-64)" "WF1c: and of the committed blob the evaluator reads"
assert_eq "1" "$(grep -c '|' "$FXH/web-acceptance-text.md")" "WF2: the fixture text contains a pipe"
assert_eq "1" "$(grep -c '"' "$FXH/web-acceptance-text.md")" "WF2b: a double quote"
assert_eq "1" "$(LC_ALL=C grep -c "$(printf '\303\251')" "$FXH/web-acceptance-text.md")" "WF2c: a multibyte character"
assert_eq "0a" "$(tail -c1 "$FXH/web-acceptance-text.md" | od -An -tx1 | tr -d ' \n')" "WF2d: and a trailing newline"
assert_eq "0" "$(LC_ALL=C grep -c "$(printf '\r')" "$FXH/web-acceptance-text.md")" "WF2e: and no CR byte"

wabody() { # <status> <hash> <decided_at json> <row_ok json>
  jq -n --arg s "$1" --arg h "$2" --argjson d "$3" --argjson r "$4" '{status:$s,text_hash:$h,decided_at:$d,row_ok:$r}' > "$STUB_DIR/curl-body"
}
mkwa() { # <name> [sed -E expr]: a no-delegation plan with one web-acceptance hold on the committed fixture text
  mkdir -p "$TMP/plans"
  sed -E -e "s|@KEY@|${WA_KEY:-wa-key}|g" -e "s|@HASH@|${WA_HASH:-$WA_H}|g" -e "${2:-s/zzz-never-zzz/x/}" "$FXH/plan-web-acceptance-only.md" > "$TMP/plans/$1.md"
  PLAN="$TMP/plans/$1.md"
}
blobhash() { git -C "$W" cat-file blob "HEAD:apps/web-platform/server/legal-acceptance/texts/$1.md" | sha256sum | cut -c1-64; }
mkhold1() { # <name> <the hold's words> [key] [hash]: a no-delegation plan with ONE hold and ONE web-acceptance gate (the hold's words are the caller's)
  mkdir -p "$TMP/plans"; PLAN="$TMP/plans/$1.md"
  printf '# Plan (synthesized)\n\n## Operator Holds\n\n- Hold: %s\n  Gate: web-acceptance %s %s\n\n## Next\n' "$2" "${3:-wa-key}" "${4:-$WA_H}" > "$PLAN"
}
mkholdg() { # <name> <the hold's words> <gate text after the kind>: the same, with the whole gate text given
  mkdir -p "$TMP/plans"; PLAN="$TMP/plans/$1.md"
  printf '# Plan (synthesized)\n\n## Operator Holds\n\n- Hold: %s\n  Gate: web-acceptance %s\n\n## Next\n' "$2" "$3" > "$PLAN"
}
jbody() { # <status json> <decided_at json> <row_ok json> [hash]: an answer written by hand, so a string can carry an escape or a key can repeat
  printf '{"status":%s,"text_hash":"%s","decided_at":%s,"row_ok":%s}\n' "$1" "${4:-$WA_H}" "$2" "$3" > "$STUB_DIR/curl-body"
}
wa_init() { # after scn: the stubs, the token, a strict URL check and an accepted answer for the canonical key and hash
  RUN_PATH="$WABIN"; RUN_REPO=""
  printf '%s\n' "$WA_TOK" > "$STUB_DIR/doppler-token"
  wabody accepted "$WA_H" "$WA_DATE_JSON" true
  mkwa wa
}
wa_calls() { { cat "$STUB_DIR/$1" 2>/dev/null || true; } | grep -c "^$2" || true; }
no_wa_miss() { ! grep -q 'STUB-MISS' < <({ cat "$STUB_DIR/curl-argv.log" "$STUB_DIR/doppler-argv.log" 2>/dev/null || true; }); }
no_secret_out() { # the canonical token AND the one this scenario put in the secret store (a refused token must not be printed either)
  local h="$TMP/.hay" t2=""
  { cat "$TMP/o" "$TMP/e" "$STUB_DIR/curl-argv.log" "$STUB_DIR/curl-url.log" "$STUB_DIR/doppler-argv.log" 2>/dev/null || true; } > "$h"
  ! grep -qF -- "$WA_TOK" "$h" || return 1
  t2="$(head -1 "$STUB_DIR/doppler-token" 2>/dev/null)"
  [ "${#t2}" -lt 8 ] || ! grep -qF -- "$t2" "$h"
}
# T2: the two detectors are under controls. A known leak must be FLAGGED, or every "the token is in no output" row below proves nothing.
mkdir -p "$TMP/ctl-leak"
( TMP="$TMP/ctl-leak"; STUB_DIR="$TMP"; : > "$TMP/o"; : > "$TMP/e"; no_secret_out && no_wa_miss ) \
  || { printf 'FATAL: the leak detectors flag a clean run\n' >&2; exit 2; }
( TMP="$TMP/ctl-leak"; STUB_DIR="$TMP"; printf 'out %s\n' "$WA_TOK" > "$TMP/o"; : > "$TMP/e"; rm -f "$STUB_DIR"/*.log; ! no_secret_out ) \
  || { printf 'FATAL: no_secret_out cannot see a token in the output\n' >&2; exit 2; }
( TMP="$TMP/ctl-leak"; STUB_DIR="$TMP"; : > "$TMP/o"; printf 'x %s\n' "$WA_TOK" > "$TMP/e"; rm -f "$STUB_DIR"/*.log; ! no_secret_out ) \
  || { printf 'FATAL: no_secret_out cannot see a token in stderr\n' >&2; exit 2; }
( TMP="$TMP/ctl-leak"; STUB_DIR="$TMP"; : > "$TMP/o"; : > "$TMP/e"; printf 'curl [-H] [Bearer %s]\n' "$WA_TOK" > "$STUB_DIR/curl-argv.log"; ! no_secret_out ) \
  || { printf 'FATAL: no_secret_out cannot see a token on a curl argv\n' >&2; exit 2; }
( TMP="$TMP/ctl-leak"; STUB_DIR="$TMP"; : > "$TMP/o"; : > "$TMP/e"; rm -f "$STUB_DIR"/*.log; printf 'STUB-MISS x\n' > "$STUB_DIR/doppler-argv.log"; ! no_wa_miss ) \
  || { printf 'FATAL: no_wa_miss cannot see a stub miss on doppler\n' >&2; exit 2; }
( TMP="$TMP/ctl-leak"; STUB_DIR="$TMP"; rm -f "$STUB_DIR"/*.log; printf 'STUB-MISS x\n' > "$STUB_DIR/curl-argv.log"; ! no_wa_miss ) \
  || { printf 'FATAL: no_wa_miss cannot see a stub miss on curl\n' >&2; exit 2; }
wexpect() { # <name> <rc> <machine line>: expect + no doppler/curl stub miss + the token in no output
  expect "$1" "$2" "$3"
  no_wa_miss && { echo "  PASS: $1: no doppler or curl stub miss"; PASS=$((PASS + 1)); } || { echo "  FAIL: $1: a doppler or curl stub refused an argv"; FAIL=$((FAIL + 1)); }
  no_secret_out && { echo "  PASS: $1: the token is in no output and no argv log"; PASS=$((PASS + 1)); } || { echo "  FAIL: $1: the token leaked"; FAIL=$((FAIL + 1)); }
}

( TMP="$TMP/ctl-leak"; STUB_DIR="$TMP"; : > "$TMP/o"; : > "$TMP/e"; rm -f "$STUB_DIR"/*.log; printf '%s\n' 'SYNTHrefused0123456789abcdef"x' > "$STUB_DIR/doppler-token"; printf 'x SYNTHrefused0123456789abcdef"x y\n' > "$TMP/e"; ! no_secret_out ) \
  || { printf 'FATAL: no_secret_out cannot see a refused (non-canonical) token the scenario configured\n' >&2; exit 2; }
( TMP="$TMP/ctl-leak"; STUB_DIR="$TMP"; : > "$TMP/o"; : > "$TMP/e"; rm -f "$STUB_DIR"/*.log; printf '%s\n' 'SYNTHrefused0123456789abcdef"x' > "$STUB_DIR/doppler-token"; no_secret_out ) \
  || { printf 'FATAL: no_secret_out flags a clean run that has a non-canonical token configured\n' >&2; exit 2; }
# T2: wexpect, has_line and wa_calls are under controls as well (a known leak and a known stub miss must raise FAIL; the counters must count).
( b=$FAIL; TMP="$TMP/ctl-leak"; STUB_DIR="$TMP"; rm -f "$STUB_DIR"/*.log; echo 0 > "$TMP/rc"; printf 'holds: 1 discharged: 1 standing: 0\n%s\n' "$WA_TOK" > "$TMP/o"; : > "$TMP/e"; wexpect ctl 0 "holds: 1 discharged: 1 standing: 0" >/dev/null; [[ $FAIL -eq $((b + 1)) ]] ) \
  || { printf 'FATAL: wexpect does not fail on a run that printed the token\n' >&2; exit 2; }
( b=$FAIL; TMP="$TMP/ctl-leak"; STUB_DIR="$TMP"; rm -f "$STUB_DIR"/*.log; echo 0 > "$TMP/rc"; printf 'holds: 1 discharged: 1 standing: 0\n' > "$TMP/o"; : > "$TMP/e"; printf 'STUB-MISS x\n' > "$STUB_DIR/curl-argv.log"; wexpect ctl 0 "holds: 1 discharged: 1 standing: 0" >/dev/null; [[ $FAIL -eq $((b + 1)) ]] ) \
  || { printf 'FATAL: wexpect does not fail on a run in which a stub refused an argv\n' >&2; exit 2; }
( b=$FAIL; TMP="$TMP/ctl-leak"; STUB_DIR="$TMP"; rm -f "$STUB_DIR"/*.log; echo 0 > "$TMP/rc"; printf 'holds: 1 discharged: 1 standing: 0\n' > "$TMP/o"; : > "$TMP/e"; wexpect ctl 0 "holds: 1 discharged: 1 standing: 0" >/dev/null; [[ $FAIL -eq $b ]] ) \
  || { printf 'FATAL: wexpect fails on a clean run\n' >&2; exit 2; }
( b=$FAIL; TMP="$TMP/ctl-leak"; STUB_DIR="$TMP"; rm -f "$STUB_DIR"/*.log; echo 2 > "$TMP/rc"; printf 'holds: 1 discharged: 1 standing: 0\n' > "$TMP/o"; : > "$TMP/e"; wexpect ctl 0 "holds: 1 discharged: 1 standing: 0" >/dev/null; [[ $FAIL -gt $b ]] ) \
  || { printf 'FATAL: wexpect does not fail on a wrong exit code\n' >&2; exit 2; }
( TMP="$TMP/ctl-leak"; printf 'a line\nsecond line\na line again\n' > "$TMP/o"; [[ "$(has_line 'a line')" == 2 && "$(has_line 'second')" == 1 && "$(has_line 'nothing like it')" == 0 ]] ) \
  || { printf 'FATAL: has_line does not count the lines that contain its text\n' >&2; exit 2; }
( TMP="$TMP/ctl-leak"; STUB_DIR="$TMP"; printf 'curl [a]\ncurl [b]\ndoppler x\n' > "$STUB_DIR/c.log"; rm -f "$STUB_DIR/none.log"; [[ "$(wa_calls c.log curl)" == 2 && "$(wa_calls c.log doppler)" == 1 && "$(wa_calls c.log zzz)" == 0 && "$(wa_calls none.log curl)" == 0 ]] ) \
  || { printf 'FATAL: wa_calls does not count what it matches\n' >&2; exit 2; }
why_of() { grep -E '^(Done|Still waiting|Needs a person|Could not check|Reserved for you):' "$TMP/o" | head -1 | sed -e 's/.* - //' -e 's/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}/DATE/' | cut -c1-220; }
CARD="Needs a person: do not ship the feature until the founder has accepted the synthetic text wa-key. - only a person can settle this"
WAIT="Still waiting: do not ship the feature until the founder has accepted the synthetic text wa-key. - "
COULD="Could not check: do not ship the feature until the founder has accepted the synthetic text wa-key. - "
RUNBOOK="knowledge-base/engineering/operations/runbooks/legal-acceptance-note-read.md"
NEEDSYOU="Needs you: the founder asked for changes. You read the note yourself, not an agent session: $RUNBOOK"
wa_case() { # <name> <rc> <machine> <reason line prefix+text>: run the canonical plan; expect rc, machine line and ONE printed line
  run_h --plan "$PLAN"
  wexpect "$1" "$2" "$3"
  assert_eq "1" "$(has_line "$4")" "$1: the printed line is exactly the closed-table wording"
}

echo "--- Control: accepted, row ok, hash equal to the committed text: discharged without a delegation ---"
scn; wa_init; run_h --plan "$PLAN"
wexpect "WA1: an accepted decision for the committed text discharges (no Delegation: line)" 0 "holds: 1 discharged: 1 standing: 0"
assert_eq "1" "$(has_line "Done: do not ship the feature until the founder has accepted the synthetic text wa-key. - checked: web-acceptance wa-key $WA_H (decided 2026-11-05)")" "WA1b: the Done line carries the gate that was true and the UTC date"
assert_eq "0" "$(head -1 "$TMP/o" | grep -c '^delegation: ')" "WA1c: no delegation verdict line is printed (none was checked)"
assert_eq "1" "$(wa_calls curl-argv.log curl)" "WA1d: exactly one request"
assert_eq "1" "$(wa_calls curl-url.log "https://app.soleur.ai/api/internal/legal-acceptance/wa-key?hash=$WA_H\$")" "WA1e: to the literal route with the key and the hash"
assert_eq "1" "$(wa_calls doppler-argv.log 'doppler secrets get LEGAL_ACCEPTANCE_VERIFY_TOKEN --plain --project soleur --config prd$')" "WA1f: the token is read with the fixed project and config"
assert_eq "0" "$(probed)" "WA1g: nothing on the GitHub side was probed"
scn; wa_init; WA_KEY="$K63" mkwa wa63; run_h --plan "$PLAN"
wexpect "WA2: a key at the 63-character limit is accepted by the gate" 0 "holds: 1 discharged: 1 standing: 0"
scn; wa_init; WA_KEY="$K62" mkwa wa62; run_h --plan "$PLAN"
wexpect "WA2b: and one at 62" 0 "holds: 1 discharged: 1 standing: 0"
scn; wa_init; for z in '+00:00' 'Z' '+0000' '+00'; do wabody accepted "$WA_H" "\"2026-11-06T00:00:01$z\"" true; run_h --plan "$PLAN"; assert_eq "0" "$(last_rc)" "WA2c: a UTC timestamp spelt with $z is understood"; done

echo "--- The closed table: every answer, the verdict, the printed reason ---"
scn; wa_init; WA_HASH="$WA_H2" mkwa wamm; run_h --plan "$PLAN"
wexpect "T1: the committed text hash differs from the gate hash: the hold stands" 1 "holds: 1 discharged: 0 standing: 1"
assert_eq "1" "$(has_line "${WAIT}the text was changed after this check was written")" "T1b: the reason is 'hash mismatch'"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "T1c: and no request was made (the answer cannot help)"
assert_eq "0" "$(wa_calls doppler-argv.log doppler)" "T1d: and no token was read"
scn; wa_init; wabody none "$WA_H" null null; wa_case "T2: none" 1 "holds: 1 discharged: 0 standing: 1" "${WAIT}no decision recorded for this text version"
scn; wa_init; wabody declined "$WA_H" "$WA_DATE_JSON" true; wa_case "T3: declined" 1 "holds: 1 discharged: 0 standing: 1" "${CARD} (declined; a revised text is needed)"
scn; wa_init; wabody changes_requested "$WA_H" "$WA_DATE_JSON" true; wa_case "T4: changes requested" 1 "holds: 1 discharged: 0 standing: 1" "${CARD}"
assert_eq "1" "$(has_line "$NEEDSYOU")" "T4b: and the founder-asked-for-changes line names who reads the note and where"
assert_eq "1" "$(grep -c '^Needs you: ' "$TMP/o")" "T4c: exactly one such line"
scn; wa_init; wabody invalid "$WA_H" "$WA_DATE_JSON" false; wa_case "T5: invalid (the checksum failed)" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}the saved decision looks damaged"
scn; wa_init; wabody invalid "$WA_H" null false; wa_case "T5b: invalid with no timestamp" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}the saved decision looks damaged"
for pair in "503|the check is not available right now (not switched on, or temporarily down)" "401|the check did not accept my sign-in" "404|the live app does not know this text yet" "400|answer not understood" "502|answer not understood" "500|I could not reach the check (HTTP 500, curl rc 0)" "429|I could not reach the check (HTTP 429, curl rc 0)" "302|I could not reach the check (HTTP 302, curl rc 0)" "307|I could not reach the check (HTTP 307, curl rc 0)" "204|I could not reach the check (HTTP 204, curl rc 0)" "000|I could not reach the check (HTTP 000, curl rc 0)"; do
  st="${pair%%|*}"; why="${pair#*|}"
  scn; wa_init; echo "$st" > "$STUB_DIR/curl-status"; wa_case "T6: HTTP $st" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$why"
done
scn; wa_init; echo 307 > "$STUB_DIR/curl-status"; wa_case "T6b: a redirect that carries an accepted body is still not an answer" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}I could not reach the check (HTTP 307, curl rc 0)"
scn; wa_init; echo 200 > "$STUB_DIR/curl-status"; : > "$STUB_DIR/doppler-fail"; wa_case "T7: the secret store fails" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}no saved sign-in value was found"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "T7b: no request without a token"
scn; wa_init; printf '%s\n' 'SYNTHbad0123456789abcdefghijklmnopqrstuvwx"yz9' > "$STUB_DIR/doppler-token"; wa_case "T7c: a token that fails the shape guard (a quote in it)" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}the saved sign-in value looks wrong (too short or odd characters)"
scn; wa_init; printf '%s\n' 'SYNTHshort0123' > "$STUB_DIR/doppler-token"; wa_case "T7e: a token that is too short" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}the saved sign-in value looks wrong (too short or odd characters)"
scn; wa_init; : > "$STUB_DIR/doppler-token"; wa_case "T7f: an empty secret is missing, not malformed" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}no saved sign-in value was found"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "T7d: a refused token makes zero requests"
scn; wa_init; RUN_PATH="$TMP/wabin-nodoppler"; wa_case "T8: no doppler on this machine" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}no saved sign-in value was found"
scn; wa_init; RUN_PATH="$TMP/wabin-nohash"; wa_case "T9: neither sha256sum nor shasum" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}I have no tool here to check that the text is unchanged"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "T9b: and no request"
scn; wa_init; RUN_PATH="$TMP/wabin-shaonly"; wa_case "T9c: only shasum -a 256 is available: it is used" 0 "holds: 1 discharged: 1 standing: 0" "Done: do not ship the feature until the founder has accepted the synthetic text wa-key. - checked: web-acceptance wa-key $WA_H (decided 2026-11-05)"
for crc in 28 6 7 35 63; do
  scn; wa_init; echo "$crc" > "$STUB_DIR/curl-rc"; wa_case "T10: curl exit $crc (timeout, DNS, connect, TLS, oversize)" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}I could not reach the check (HTTP 000, curl rc $crc)"
done
scn; wa_init; RUN_PATH="$TMP/wabin-nocurl"; wa_case "T10b: no curl on this machine" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}I could not reach the check (HTTP 000, curl rc 127)"

arm_begin nser
echo "--- Answers that cannot be understood are exit 2, never a pass ---"
scn; wa_init; : > "$STUB_DIR/curl-body"; wa_case "N1: an empty body" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}answer not understood"
scn; wa_init; echo 'not json at all' > "$STUB_DIR/curl-body"; wa_case "N2: a non-JSON body" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}answer not understood"
scn; wa_init; echo '[]' > "$STUB_DIR/curl-body"; wa_case "N3: a JSON array" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}answer not understood"
scn; wa_init; jq -n --arg h "$WA_H" '{status:"accepted",text_hash:$h,decided_at:"2026-11-05T10:15:30Z",row_ok:true,requested_edit:"x"}' > "$STUB_DIR/curl-body"; wa_case "N4: a fifth key (the note must never be in the answer)" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}answer not understood"
scn; wa_init; jq -n --arg h "$WA_H" '{status:"accepted",text_hash:$h,decided_at:"2026-11-05T10:15:30Z"}' > "$STUB_DIR/curl-body"; wa_case "N5: a missing key" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}answer not understood"
for s in approved ACCEPTED Accepted "" "accepted " null 1 true; do
  scn; wa_init; if [[ "$s" == null || "$s" == 1 || "$s" == true ]]; then jq -n --arg h "$WA_H" --argjson s "$s" '{status:$s,text_hash:$h,decided_at:"2026-11-05T10:15:30Z",row_ok:true}' > "$STUB_DIR/curl-body"; else wabody "$s" "$WA_H" "$WA_DATE_JSON" true; fi
  wa_case "N6: a status outside the closed set ('$s')" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}answer not understood"
done
scn; wa_init; wabody accepted "$WA_H2" "$WA_DATE_JSON" true; wa_case "N7: an echoed hash that differs from the gate hash" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}answer not understood"
scn; wa_init; jq -n '{status:"accepted",text_hash:null,decided_at:"2026-11-05T10:15:30Z",row_ok:true}' > "$STUB_DIR/curl-body"; wa_case "N7b: an echoed hash that is null" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}answer not understood"
scn; wa_init; wabody accepted "$(printf '%s' "$WA_H" | tr 'a-f' 'A-F')" "$WA_DATE_JSON" true; wa_case "N7c: an echoed hash in uppercase" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}answer not understood"
for ro in false '"true"' '"false"' '"yes"' 1 0 null '[]' '{}'; do
  scn; wa_init; wabody accepted "$WA_H" "$WA_DATE_JSON" "$ro"; wa_case "N8: accepted with row_ok $ro is not a pass" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}answer not understood"
done
scn; wa_init; wabody accepted "$WA_H" null true; wa_case "N9: accepted with no timestamp" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}answer not understood"
for ts in '"yesterday"' '"2026-11-05"' '"2026-11-05T10:15:30+02:00"' '"2026-11-05T10:15:30.123456-05:00"' '""' 5 '"2026-11-05T10:15:30Z; rm -rf"'; do
  scn; wa_init; wabody accepted "$WA_H" "$ts" true; wa_case "N10: a timestamp that is not plain UTC ($ts)" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}answer not understood"
done
scn; wa_init; wabody declined "$WA_H" "$WA_DATE_JSON" false; wa_case "N11: declined with row_ok false is a contradiction" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}answer not understood"
scn; wa_init; wabody none "$WA_H" "$WA_DATE_JSON" null; wa_case "N12: none with a timestamp is a contradiction" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}answer not understood"
scn; wa_init; wabody none "$WA_H" null true; wa_case "N13: none with row_ok true is a contradiction" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}answer not understood"
scn; wa_init; wabody invalid "$WA_H" "$WA_DATE_JSON" true; wa_case "N14: invalid with row_ok true is a contradiction" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}answer not understood"
scn; wa_init; wabody invalid "$WA_H2" "$WA_DATE_JSON" false; wa_case "N15: invalid for another hash" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}answer not understood"

echo "--- Escapes, repeats and impossible dates are not a pass (F5) ---"
NU='answer not understood'
scn; wa_init; jbody '"accepted\n"' '"2026-11-05T10:15:30Z"' true; wa_case "N16: a status that is 'accepted' plus a newline" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$NU"
scn; wa_init; jbody '"accepted\u0000"' '"2026-11-05T10:15:30Z"' true; wa_case "N16b: a status that is 'accepted' plus a NUL" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$NU"
scn; wa_init; jbody '"accepted\r"' '"2026-11-05T10:15:30Z"' true; wa_case "N16c: a status that is 'accepted' plus a carriage return" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$NU"
scn; wa_init; jbody '"\naccepted"' '"2026-11-05T10:15:30Z"' true; wa_case "N16d: a status with a newline in front" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$NU"
scn; wa_init; printf '{"status":"none","status":"accepted","text_hash":"%s","decided_at":"2026-11-05T10:15:30Z","row_ok":true}\n' "$WA_H" > "$STUB_DIR/curl-body"; wa_case "N17: the status repeated, none first and accepted last" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$NU"
scn; wa_init; printf '{"status":"accepted","status":"none","text_hash":"%s","decided_at":null,"row_ok":null}\n' "$WA_H" > "$STUB_DIR/curl-body"; wa_case "N17b: the status repeated, accepted first and none last" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$NU"
scn; wa_init; printf '{"status":"accepted","text_hash":"%s","decided_at":"2026-11-05T10:15:30Z","row_ok":false,"row_ok":true}\n' "$WA_H" > "$STUB_DIR/curl-body"; wa_case "N18: row_ok repeated, false first and true last" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$NU"
scn; wa_init; printf '{"status":"accepted","text_hash":"%s","decided_at":"2026-11-05T10:15:30Z","row_ok":{"a":1},"row_ok":true}\n' "$WA_H" > "$STUB_DIR/curl-body"; wa_case "N18b: row_ok repeated, an object first and true last" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$NU"
scn; wa_init; printf '{"status":"accepted","text_hash":"%s","text_hash":"%s","decided_at":"2026-11-05T10:15:30Z","row_ok":true}\n' "$WA_H2" "$WA_H" > "$STUB_DIR/curl-body"; wa_case "N18c: the echoed hash repeated, a wrong one first" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$NU"
scn; wa_init; printf '{"status":"accepted","text_hash":"%s","decided_at":null,"decided_at":"2026-11-05T10:15:30Z","row_ok":true}\n' "$WA_H" > "$STUB_DIR/curl-body"; wa_case "N18d: decided_at repeated, null first" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$NU"
scn; wa_init; wabody accepted "$WA_H" "$WA_DATE_JSON" true; cp "$STUB_DIR/curl-body" "$STUB_DIR/one"; cat "$STUB_DIR/one" "$STUB_DIR/one" > "$STUB_DIR/curl-body"; wa_case "N19: two answers in one body" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$NU"
scn; wa_init; wabody none "$WA_H" null null; cp "$STUB_DIR/curl-body" "$STUB_DIR/one"; wabody accepted "$WA_H" "$WA_DATE_JSON" true; cat "$STUB_DIR/one" "$STUB_DIR/curl-body" > "$STUB_DIR/two"; cp "$STUB_DIR/two" "$STUB_DIR/curl-body"; wa_case "N19b: a refusing answer first and an accepting one after it" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$NU"
for dt in 2026-13-99T99:99:99Z 0000-00-00T00:00:00Z 9999-12-31T23:59:59Z 1999-12-31T23:59:59Z 2100-01-01T00:00:00Z 2026-00-10T00:00:00Z 2026-11-00T00:00:00Z 2026-11-32T00:00:00Z 2026-02-30T10:00:00Z 2026-11-05T24:00:00Z 2026-11-05T10:60:00Z 2026-11-05T10:15:60Z 2026-04-31T10:15:30Z; do
  scn; wa_init; jbody '"accepted"' "\"$dt\"" true; wa_case "N20: an impossible or absurd date ($dt)" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$NU"
done
scn; wa_init; jbody '"accepted"' '"2026-11-05T10:15:30Z\n"' true; wa_case "N21: a timestamp with a trailing newline" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$NU"
scn; wa_init; jbody '"accepted"' '"2026-11-05T10:15:30Z\u0000"' true; wa_case "N21b: a timestamp with a trailing NUL" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$NU"
scn; wa_init; jbody '"accepted"' '"\n2026-11-05T10:15:30Z"' true; wa_case "N21c: a timestamp with a newline in front" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$NU"
scn; wa_init; jbody '"declined"' '"2026-13-99T99:99:99Z"' true; wa_case "N22: a declined answer with an impossible date is not understood either" 2 "holds: 1 discharged: 0 standing: 1" "${COULD}$NU"
scn; wa_init; jbody '"accepted"' '"2028-02-29T10:15:30Z"' true; wa_case "N23: instrument: a real leap day is understood" 0 "holds: 1 discharged: 1 standing: 0" "Done: do not ship the feature until the founder has accepted the synthetic text wa-key. - checked: web-acceptance wa-key $WA_H (decided 2028-02-29)"

arm_end nser
echo "--- The gate is validated before any request: every malformed spelling is exit 2 with zero requests ---"
SHAPE="the web acceptance is not written as a plain text name and fingerprint"
bad_gate() { # <name> <key token(s) text after the kind> 
  scn; wa_init; mkdir -p "$TMP/plans"; sed -E -e "s|@KEY@|wa-key|g" -e "s|^  Gate: .*|  Gate: web-acceptance $2|" "$FXH/plan-web-acceptance-only.md" > "$TMP/plans/bad.md"; PLAN="$TMP/plans/bad.md"
  run_h --plan "$PLAN"
  wexpect "$1" 2 "holds: 1 discharged: 0 standing: 1"
  assert_eq "1" "$(has_line "${COULD}${SHAPE}")" "$1: says why"
  assert_eq "0" "$(wa_calls curl-argv.log curl)" "$1: zero requests"
  assert_eq "0" "$(wa_calls doppler-argv.log doppler)" "$1: no token read"
}
bad_gate "G1: a path separator in the key" "up/key $WA_H"
bad_gate "G2: a dot in the key" "dot.key $WA_H"
bad_gate "G3: a 64-character key (the database refuses it)" "$K64 $WA_H"
bad_gate "G4: an uppercase hex hash" "wa-key $(printf '%s' "$WA_H" | tr 'a-f' 'A-F')"
bad_gate "G5: a 63-character hash" "wa-key ${WA_H%?}"
bad_gate "G5b: a 65-character hash" "wa-key ${WA_H}0"
bad_gate "G6: a missing hash" "wa-key"
bad_gate "G7: a missing key and hash" ""
bad_gate "G8: an extra token" "wa-key $WA_H extra"
bad_gate "G9: a tab, then more words, after the hash (E3)" "wa-key $WA_H"$'\t'"AND pr-merged 999999"
bad_gate "G9b: a tab in front of more words after the key" "wa-key"$'\t'"AND pr-merged 999999 $WA_H"
bad_gate "G10: a non-breaking space inside the key" "wa"$'\xc2\xa0'"-key $WA_H"
bad_gate "G10b: a non-breaking space inside the hash" "wa-key ${WA_H:0:32}"$'\xc2\xa0'"${WA_H:32}"
bad_gate "G11: a leading hyphen in the key" "-wa-key $WA_H"
bad_gate "G12: an uppercase key" "WA-KEY $WA_H"
bad_gate "G13: a key with an underscore" "wa_key $WA_H"
bad_gate "G14: a key with a glob character" "wa-* $WA_H"
bad_gate "G15: a key with a colon (a revision spec)" "HEAD:wa-key $WA_H"
bad_gate "G16: two spaces between the tokens" "wa-key  $WA_H"
bad_gate "G17: a hash with a trailing quote" "wa-key $WA_H\""
bad_gate "G18: a url-ish key" "wa-key?x=1 $WA_H"
scn; wa_init; sed -E -e "s|^  Gate: .*|  Gate: Web-Acceptance wa-key $WA_H|" "$FXH/plan-web-acceptance-only.md" > "$TMP/plans/kc.md"; run_h --plan "$TMP/plans/kc.md"
assert_eq "3" "$(last_rc)" "G19: a kind spelled in another case is an unknown kind: with no delegation the plan keeps the prose path (exit 3)"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "G19b: and nothing was requested"

echo "--- The committed text: a missing, symlinked or CR-bearing blob is exit 2 ---"
CANT="${COULD}the saved text is not in the project"
cant_for() { printf '%s' "${COULD/synthetic text wa-key./synthetic text $1.}the saved text is not in the project"; }
dmg_for() { printf '%s' "${COULD/synthetic text wa-key./synthetic text $1.}the saved text is damaged"; }
scn; wa_init; WA_KEY=nowhere mkwa nowhere; wa_case "B1: no committed text for the key" 2 "holds: 1 discharged: 0 standing: 1" "$(cant_for nowhere)"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "B1b: no request"
scn; wa_init; WA_KEY=wa-cr WA_HASH="$(git -C "$W" cat-file blob HEAD:apps/web-platform/server/legal-acceptance/texts/wa-cr.md | sha256sum | cut -c1-64)" mkwa cr; wabody accepted "$(git -C "$W" cat-file blob HEAD:apps/web-platform/server/legal-acceptance/texts/wa-cr.md | sha256sum | cut -c1-64)" "$WA_DATE_JSON" true
wa_case "B2: a committed text with a CR byte (the web app refuses it too)" 2 "holds: 1 discharged: 0 standing: 1" "$(dmg_for wa-cr)"
scn; wa_init; WA_KEY=wa-link WA_HASH="$(printf 'wa-key.md' | sha256sum | cut -c1-64)" mkwa link; wabody accepted "$(printf 'wa-key.md' | sha256sum | cut -c1-64)" "$WA_DATE_JSON" true
wa_case "B3: a committed symlink is not a regular text" 2 "holds: 1 discharged: 0 standing: 1" "$(cant_for wa-link)"
scn; wa_init; RUN_REPO="$W6"; wa_case "B4: a repository that has no texts folder at all" 2 "holds: 1 discharged: 0 standing: 1" "$CANT"
scn; wa_init; ( cd "$W/apps/web-platform/server/legal-acceptance/texts" && printf 'changed\n' > wa-key.md ); run_h --plan "$PLAN"; git -C "$W" checkout -q -- apps/web-platform/server/legal-acceptance/texts/wa-key.md
wexpect "B5: a dirty working-tree copy does not change the answer (the committed blob is read)" 0 "holds: 1 discharged: 1 standing: 0"
scn; wa_init; ( cd "$W/apps/web-platform/server/legal-acceptance/texts" && printf 'changed\n' > wa-key.md && git add wa-key.md ); run_h --plan "$PLAN"; git -C "$W" reset -q HEAD -- apps/web-platform/server/legal-acceptance/texts/wa-key.md; git -C "$W" checkout -q -- apps/web-platform/server/legal-acceptance/texts/wa-key.md
wexpect "B5b: nor does a staged one" 0 "holds: 1 discharged: 1 standing: 0"
scn; wa_init
( cd "$W/apps" && git_fixture_env "$W" && PATH="$RUN_PATH" "$BASH_BIN" "$SUT" --plan "$PLAN" ) </dev/null >"$TMP/o" 2>"$TMP/e"; echo $? > "$TMP/rc"
wexpect "B6: the blob is found from a subdirectory of the repository too" 0 "holds: 1 discharged: 1 standing: 0"

echo "--- Request hygiene ---"
scn; wa_init; : > "$STUB_DIR/eat-stdin"; printf 'ten bytes!' > "$TMP/stdin-ten"; RUN_STDIN="$TMP/stdin-ten"
{ printf '# Plan (synthesized)\n\n## Operator Holds\n\n- Hold: first web acceptance wa-key.\n  Gate: web-acceptance wa-key %s\n  Gate: web-acceptance wa-key %s\n- Hold: second web acceptance wa-key.\n  Gate: web-acceptance wa-key %s\n  Gate: web-acceptance wa-key %s\n\n## Next\n' "$WA_H" "$WA_H" "$WA_H" "$WA_H"; } > "$TMP/plans/two.md"; PLAN="$TMP/plans/two.md"
run_h --plan "$PLAN"
wexpect "Q1: a doppler or curl that drains stdin does not swallow the second gate or hold" 0 "holds: 2 discharged: 2 standing: 0"
assert_eq "0" "$(grep -vcx 0 "$STUB_DIR/stdin-bytes")" "Q1b: every doppler and curl call saw an empty stdin"
assert_eq "8" "$(wc -l < "$STUB_DIR/stdin-bytes" | tr -d ' ')" "Q1c: and there were eight calls to see it (four token reads, four requests)"
scn; wa_init; ( cd "$W" && git_fixture_env "$W" && PATH="$RUN_PATH" TERM=dumb "$BASH_BIN" -x "$SUT" --plan "$PLAN" ) </dev/null >"$TMP/o" 2>"$TMP/e"; echo $? > "$TMP/rc"
assert_eq "2" "$(last_rc)" "Q2: run under xtrace the gate refuses to read the token: exit 2"
assert_eq "0" "$(wa_calls doppler-argv.log doppler)" "Q2b: the secret was never read"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "Q2c: and nothing was requested"
no_secret_out && { echo "  PASS: Q2d: the traced run carries no token"; PASS=$((PASS + 1)); } || { echo "  FAIL: Q2d: the token leaked under xtrace"; FAIL=$((FAIL + 1)); }
assert_eq "1" "$(has_line "${COULD}I will not read the sign-in value while commands are being traced")" "Q2e: and says so"
scn; wa_init
( cd "$W" && git_fixture_env "$W" && SSLKEYLOGFILE=/x CURL_CA_BUNDLE=/x SSL_CERT_FILE=/x SSL_CERT_DIR=/x CURL_HOME=/x HOSTALIASES=/x LOCALDOMAIN=x RES_OPTIONS=x OPENSSL_CONF=/x OPENSSL_MODULES=/x LD_PRELOAD=/nonexistent/x.so LD_AUDIT=/nonexistent/x.so LD_LIBRARY_PATH=/nonexistent PATH="$RUN_PATH" "$BASH_BIN" "$SUT" --plan "$PLAN" ) </dev/null >"$TMP/o" 2>"$TMP/e"; echo $? > "$TMP/rc"
wexpect "Q3: TLS and resolver variables in the environment are hidden from curl (the stub refuses if it sees one)" 0 "holds: 1 discharged: 1 standing: 0"
scn; wa_init; HGE_WA_BASE='https://evil.example.test/api' HGE_BASE_URL='https://evil.example.test' APP_URL='https://evil.example.test' BASE_URL='https://evil.example.test' NEXT_PUBLIC_APP_URL='https://evil.example.test' run_h --plan "$PLAN"
wexpect "Q4: no environment variable can change the base URL (the stub refuses any other host)" 0 "holds: 1 discharged: 1 standing: 0"
assert_eq "0" "$(wa_calls curl-argv.log '.*evil')" "Q4b: and no request names another host"

echo "--- Plans: web-acceptance holds beside other holds, with and without a standing delegation ---"
mkplan2() { # <name> <text after the section's Delegation/Envelope lines>
  mkdir -p "$TMP/plans"; PLAN="$TMP/plans/$1.md"
  { printf '# Plan (synthesized)\n\n## Operator Holds\n\nDelegation: %s\nEnvelope: env-valid.md\n\n' "$URL"; printf '%s\n' "$2"; printf '\n## Next\n'; } > "$PLAN"
}
scn; wa_init; mkplan2 d1 "- Hold: do not ship while a release is running.
  Gate: no-inflight-run example-release.yml
- Hold: do not ship the feature until the founder has accepted the synthetic text wa-key.
  Gate: web-acceptance wa-key $WA_H"
RUN_PATH="$WABIN"; run_h --plan "$PLAN"
wexpect "P1: with a valid delegation, a plan with two holds where only the second is a web acceptance" 0 "holds: 2 discharged: 2 standing: 0"
assert_eq "valid" "$(head -1 "$TMP/o" | sed -n 's/^delegation: \(valid\) reason=ok$/\1/p')" "P1b: the delegation verdict is the first line"
scn; wa_init; mkplan2 d2 "- Hold: ship only when both are true (wa-key).
  Gate: pr-merged 55
  Gate: web-acceptance wa-key $WA_H"
RUN_PATH="$WABIN"; run_h --plan "$PLAN"
wexpect "P2: with a valid delegation, a web acceptance beside a pr-merged gate in one hold" 0 "holds: 1 discharged: 1 standing: 0"
assert_eq "1" "$(has_line "Done: ship only when both are true (wa-key). - checked: pr-merged 55; web-acceptance wa-key $WA_H (decided 2026-11-05)")" "P2b: both gates are named in the Done line"
scn; wa_init; wabody declined "$WA_H" "$WA_DATE_JSON" true; mkplan2 d3 "- Hold: ship only when both are true (wa-key).
  Gate: web-acceptance wa-key $WA_H
  Gate: pr-merged 55"
RUN_PATH="$WABIN"; run_h --plan "$PLAN"
wexpect "P3: a declined web acceptance beside a true pr-merged gate: the hold stands as a person's decision" 1 "holds: 1 discharged: 0 standing: 1"
assert_eq "1" "$(has_line "Needs a person: ship only when both are true (wa-key). - only a person can settle this (declined; a revised text is needed)")" "P3b: with its reason"
scn; wa_init; wabody declined "$WA_H" "$WA_DATE_JSON" true; echo net > "$STUB_DIR/mode-pr"; mkplan2 d4 "- Hold: ship only when both are true (wa-key).
  Gate: web-acceptance wa-key $WA_H
  Gate: pr-merged 55"
RUN_PATH="$WABIN"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "P4: a person's decision followed by an unreadable gate is exit 2 (the unreadable one wins)"
scn; wa_init; echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-55.json"; mkplan2 d5 "- Hold: ship only when both are true (wa-key).
  Gate: pr-merged 55
  Gate: web-acceptance wa-key $WA_H"
RUN_PATH="$WABIN"; run_h --plan "$PLAN"
wexpect "P5: a false pr-merged gate then a true web acceptance: the later gate never wins the hold back" 1 "holds: 1 discharged: 0 standing: 1"
scn; wa_init; mkplan2 d6 "- Hold: Operator-reserved: approve the wording.
  Gate: web-acceptance wa-key $WA_H
- Hold: do not ship the feature until the founder has accepted the synthetic text wa-key.
  Gate: web-acceptance wa-key $WA_H"
RUN_PATH="$WABIN"; run_h --plan "$PLAN"
wexpect "P6: an Operator-reserved hold beside a web acceptance: the reserved one stands, the other discharges" 2 "holds: 2 discharged: 1 standing: 1"
assert_eq "1" "$(grep -c '^Reserved for you: ' "$TMP/o")" "P6b: the reserved hold is printed as reserved"
assert_eq "1" "$(wa_calls curl-argv.log curl)" "P6c: its web-acceptance gate was not even probed (one request, for the other hold)"
scn; wa_init; mkplan2 d7 "- Hold: do not ship the feature until the founder has accepted the synthetic text wa-key.
  Gate: web-acceptance wa-key $WA_H
- Hold: do not ship the feature until the founder has accepted the synthetic text again $K63.
  Gate: web-acceptance $K63 $WA_H"
RUN_PATH="$WABIN"; run_h --plan "$PLAN"
wexpect "P7: two web acceptances, the second on a key with no stored answer for it: one request each" 0 "holds: 2 discharged: 2 standing: 0"
assert_eq "2" "$(wa_calls curl-argv.log curl)" "P7b: two requests"

echo "--- No Delegation: line (CTO ruling F3) ---"
scn; wa_init; run_h --plan "$FXH/plan-web-acceptance-only.md"
assert_eq "2" "$(last_rc)" "ND0: the fixture with its placeholders unreplaced is a malformed gate: exit 2, never 3"
scn; wa_init; mkwa nd1; run_h --plan "$PLAN"
wexpect "ND1: only web-acceptance gates and no delegation: evaluated, discharged" 0 "holds: 1 discharged: 1 standing: 0"
scn; wa_init; wabody declined "$WA_H" "$WA_DATE_JSON" true; mkwa nd1b; run_h --plan "$PLAN"
assert_eq "1" "$(last_rc)" "ND1b: and a declined one is exit 1 (never the exit 3 prose path)"
sed -E -e "s|@KEY@|wa-key|g" -e "s|@HASH@|$WA_H|g" "$FXH/plan-web-acceptance-mixed.md" > "$TMP/plans/mixed.md"
scn; wa_init; PLAN="$TMP/plans/mixed.md"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "ND2: a web acceptance mixed with pr-merged and no delegation is exit 2 (not 3, never 0 or 1)"
assert_eq "1" "$(machine | grep -c '^holds: 2 discharged: 0 standing: 2$')" "ND2b: both holds stand and none is discharged"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "ND2c: no request was made for the mixed plan"
assert_eq "0" "$(probed)" "ND2d: and nothing on the GitHub side was probed"
assert_eq "2" "$(grep -c '^Could not check: ' "$TMP/o")" "ND2e: each hold says it could not be checked"
sed -E -e "s|@KEY@|wa-key|g" -e "s|@HASH@|$WA_H|g" "$FXH/plan-reserved-only.md" > "$TMP/plans/resonly.md"
scn; wa_init; PLAN="$TMP/plans/resonly.md"; run_h --plan "$PLAN"
assert_eq "3" "$(last_rc)" "ND3: a plan with only an Operator-reserved hold and no delegation keeps the prose path (exit 3), even when the reserved hold carries a web-acceptance gate"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "ND3b: and nothing was requested"
scn; wa_init; mkdir -p "$TMP/plans"; printf '# Plan\n\n## Operator Holds\n\n- Hold: wait for the founder to read it.\n' > "$TMP/plans/gateless.md"; PLAN="$TMP/plans/gateless.md"; run_h --plan "$PLAN"
assert_eq "3" "$(last_rc)" "ND4: a plan whose holds have no gate and no delegation keeps the prose path (exit 3)"
scn; wa_init; printf '# Plan\n\n## Operator Holds\n\n- Hold: Operator-reserved: approve the wording.\n- Hold: wait for the founder to read it.\n' > "$TMP/plans/gateless2.md"; PLAN="$TMP/plans/gateless2.md"; run_h --plan "$PLAN"
assert_eq "3" "$(last_rc)" "ND4b: reserved and gate-less holds together: exit 3"
scn; wa_init
{ printf '# Plan\n\n## Operator Holds\n\n- Hold: first wa-key.\n  Gate: web-acceptance wa-key %s\n- Hold: wait for the founder to read it as well.\n\n## Next\n' "$WA_H"; } > "$TMP/plans/nd5.md"; PLAN="$TMP/plans/nd5.md"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "ND5: a web acceptance beside a gate-less hold and no delegation is exit 2 (the prose hold cannot ride along)"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "ND5b: nothing was requested"
scn; wa_init; { printf '# Plan\n\n## Operator Holds\n\n- Hold: Operator-reserved: approve the wording.\n  Gate: pr-merged 55\n- Hold: first wa-key.\n  Gate: web-acceptance wa-key %s\n\n## Next\n' "$WA_H"; } > "$TMP/plans/nd6.md"; PLAN="$TMP/plans/nd6.md"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "ND6: an Operator-reserved hold beside a web acceptance and no delegation: the web acceptance is evaluated, the reserved one stands (exit 2)"
assert_eq "1" "$(machine | grep -c '^holds: 2 discharged: 1 standing: 1$')" "ND6b: one discharged, one standing"
assert_eq "0" "$(probed)" "ND6c: the reserved hold's pr-merged gate is not probed"
scn; wa_init; { printf '# Plan\n\n## Operator Holds\n\n- Hold: first wa-key.\n  Gate: web-acceptance wa-key %s\n\n## Operator Holds\n\n- Hold: second wa-key.\n  Gate: web-acceptance wa-key %s\n\n## Next\n' "$WA_H" "$WA_H"; } > "$TMP/plans/nd7.md"; PLAN="$TMP/plans/nd7.md"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "ND7: two hold sections with web acceptances and no delegation is exit 2 (same structural checks as today)"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "ND7b: nothing was requested"
scn; wa_init; mkwa nd8; printf '\n## Notes\n\n* Hold: a hold hiding under another heading.\n  Gate: pr-merged 9999\n' >> "$PLAN"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "ND8: a hold outside the section beside a web acceptance and no delegation is exit 2 (the stray-marker count still applies)"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "ND8b: nothing was requested"
scn; wa_init; { printf '# Plan\n\n## Operator Holds\n\nEnvelope: env-valid.md\n\n- Hold: first wa-key.\n  Gate: web-acceptance wa-key %s\n\n## Next\n' "$WA_H"; } > "$TMP/plans/nd9.md"; PLAN="$TMP/plans/nd9.md"; run_h --plan "$PLAN"
wexpect "ND9: an Envelope line without a Delegation line does not stop a web-acceptance-only plan" 0 "holds: 1 discharged: 1 standing: 0"
scn; wa_init; { printf '# Plan\n\n## Operator Holds\n\n- Hold: first wa-key.\n  Gate: web-acceptance wa-key %s\n  Gate: frobnicate 1\n\n## Next\n' "$WA_H"; } > "$TMP/plans/nd10.md"; PLAN="$TMP/plans/nd10.md"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "ND10: a web acceptance beside an unknown kind and no delegation is exit 2"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "ND10b: nothing was requested"
scn; wa_init; { printf '# Plan\n\n## Operator Holds\n\n  Gate: web-acceptance wa-key %s\n- Hold: first wa-key.\n  Gate: web-acceptance wa-key %s\n\n## Next\n' "$WA_H" "$WA_H"; } > "$TMP/plans/nd11.md"; PLAN="$TMP/plans/nd11.md"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "ND11: a web-acceptance gate written outside any hold (an orphan) is exit 2"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "ND11b: nothing was requested"

arm_begin bind
echo "--- The hold must name the text its gate decides (CTO ruling D1) ---"
bindwhy_for() { printf '%s' "this wait does not name the legal text it is about; ask the plan's author to put the text name $1 in the hold's words"; }
BINDWHY="$(bindwhy_for wa-key)"
scn; wa_init; mkhold1 bind1 "Deploy the payments migration to production"; run_h --plan "$PLAN"
wexpect "BIND1: an accepted text cannot clear a wait about something else (the payments migration case)" 2 "holds: 1 discharged: 0 standing: 1"
assert_eq "1" "$(has_line "Could not check: Deploy the payments migration to production - $BINDWHY")" "BIND1b: and says why in plain words"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "BIND1c: nothing was requested"
assert_eq "0" "$(wa_calls doppler-argv.log doppler)" "BIND1d: and no token was read"
scn; wa_init; mkplan2 bind2 "- Hold: Deploy the payments migration to production
  Gate: web-acceptance wa-key $WA_H"; RUN_PATH="$WABIN"; run_h --plan "$PLAN"
wexpect "BIND2: the same with a valid standing delegation recorded" 2 "holds: 1 discharged: 0 standing: 1"
assert_eq "1" "$(has_line "Could not check: Deploy the payments migration to production - $BINDWHY")" "BIND2b: the same words"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "BIND2c: nothing was requested"
for words in "wa-key must be accepted" "accepted: wa-key" "The founder accepts \"wa-key\", then ship." "Wait for WA-KEY" "(wa-key)" "wa-key."; do
  scn; wa_init; mkhold1 bind3 "$words"; run_h --plan "$PLAN"
  wexpect "BIND3: a hold that names the key as a whole word ($words) is cleared by its decision" 0 "holds: 1 discharged: 1 standing: 0"
done
for words in "Wait for wa-key-two" "Wait for xwa-key" "Wait for wa-keys" "Wait for 2wa-key" "Wait for wa-key2" "Wait for wa key" "Wait for wa-ke" "Wait for the legal text" "Wait for a-key" "Wait for wa-key_x" "Wait for _wa-key" "Wait for x_wa-key_"; do
  scn; wa_init; mkhold1 bind4 "$words"; run_h --plan "$PLAN"
  wexpect "BIND4: a hold that only contains part of the key ($words) is not cleared" 2 "holds: 1 discharged: 0 standing: 1"
  assert_eq "1" "$(has_line "Could not check: $words - $BINDWHY")" "BIND4b: says why ($words)"
  assert_eq "0" "$(wa_calls curl-argv.log curl)" "BIND4c: nothing was requested ($words)"
done
scn; wa_init; mkhold1 bind5 "Wait for wa-key to be accepted" "$K63" "$WA_H"; run_h --plan "$PLAN"
wexpect "BIND5: the hold names one key and the gate decides another: not cleared" 2 "holds: 1 discharged: 0 standing: 1"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "BIND5b: nothing was requested"
scn; wa_init; mkdir -p "$TMP/plans"; PLAN="$TMP/plans/bind6.md"; printf '# Plan\n\n## Operator Holds\n\n- Hold: Wait for wa-key to be accepted\n  Gate: web-acceptance wa-key %s\n  Gate: web-acceptance %s %s\n\n## Next\n' "$WA_H" "$K63" "$WA_H" > "$PLAN"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "BIND6: every web-acceptance gate on a hold needs its own key named: the second does not, so exit 2"
assert_eq "1" "$(has_line "Could not check: Wait for wa-key to be accepted - $(bindwhy_for "$K63")")" "BIND6b: says why (it names the key that is missing)"
scn; wa_init; run_h --file env-wa.md --section "Production Envelope"
wexpect "BIND7: a web acceptance in an envelope (--file mode) is never evaluated" 2 "holds: 1 discharged: 0 standing: 1"
assert_eq "1" "$(has_line "a recorded decision on a legal text cannot back a production step")" "BIND7b: and says why"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "BIND7c: nothing was requested"
assert_eq "0" "$(wa_calls doppler-argv.log doppler)" "BIND7d: and no token was read"

arm_end bind
arm_begin nt
echo "--- An acknowledgement key cannot back a production step (CTO ruling T3, review round 1) ---"
NTWHY="this key is an acknowledgement; its decision cannot back a production step"
scn; wa_init; mkhold1 nt1 "Wait for founder-acceptance-record to be accepted" "founder-acceptance-record" "$WA_H"; run_h --plan "$PLAN"
wexpect "NT1: a web-acceptance gate on the acknowledgement key is refused (exit 2), even though the hold names it and the answer would be accepted" 2 "holds: 1 discharged: 0 standing: 1"
assert_eq "1" "$(has_line "Could not check: Wait for founder-acceptance-record to be accepted - $NTWHY")" "NT1b: and says why in plain words"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "NT1c: nothing was requested"
assert_eq "0" "$(wa_calls doppler-argv.log doppler)" "NT1d: and no token was read"
scn; wa_init; mkhold1 nt2 "Wait for wa-key to be accepted"; run_h --plan "$PLAN"
wexpect "NT2: control, an ordinary key is still cleared by its decision (the refusal is the key, not the gate)" 0 "holds: 1 discharged: 1 standing: 0"
scn; wa_init; mkhold1 nt3 "Wait for founder-acceptance-record-two to be accepted" "founder-acceptance-record-two" "$WA_H"; run_h --plan "$PLAN"
wexpect "NT3: a key that merely CONTAINS the listed key is not refused as an acknowledgement (whole-word match); with its text committed it is cleared by its decision" 0 "holds: 1 discharged: 1 standing: 0"
assert_eq "0" "$(has_line "$NTWHY")" "NT3b: and the refusal words are not printed"
scn; wa_init; mkhold1 nt4 "Wait for acceptance-record to be accepted" "acceptance-record" "$WA_H"; run_h --plan "$PLAN"
wexpect "NT4: a key that is a SUFFIX of the listed key (acceptance-record) is not refused; it is cleared by its decision" 0 "holds: 1 discharged: 1 standing: 0"
scn; wa_init; mkhold1 nt5 "Wait for founder-acceptance to be accepted" "founder-acceptance" "$WA_H"; run_h --plan "$PLAN"
wexpect "NT5: a key that is a PREFIX of the listed key (founder-acceptance) is not refused; it is cleared by its decision" 0 "holds: 1 discharged: 1 standing: 0"
scn; wa_init; mkhold1 nt1d "Wait for founder-acceptance-record to be accepted" "founder-acceptance-record" "$WA_H"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "NT6: instrument: the acknowledgement key HAS a committed text and an accepted answer in this fixture, so the refusal in NT1 is its kind and not a missing text"
assert_eq "1" "$(git -C "$W" cat-file -e "HEAD:apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md" 2>/dev/null && echo 1 || echo 0)" "NT6b: the text is committed in the fixture repo"
arm_end nt
arm_begin tab
echo "--- A tab inside a Gate line cannot split the record (E3) ---"
TABGATE="wa-key $WA_H"$'\t'"AND pr-merged 999999"
scn; wa_init; mkholdg tab1 "Wait for wa-key to be accepted" "$TABGATE"; run_h --plan "$PLAN"
wexpect "TAB1: a tab after the hash and more conditions: the whole line is read, it is not a plain key and hash, exit 2" 2 "holds: 1 discharged: 0 standing: 1"
assert_eq "1" "$(has_line "Could not check: Wait for wa-key to be accepted - $SHAPE")" "TAB1c: says the gate is not a plain key and hash"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "TAB1d: nothing was requested"
scn; wa_init; echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-999999.json"; mkplan2 tab2 "- Hold: Wait for wa-key to be accepted
  Gate: web-acceptance $TABGATE"; RUN_PATH="$WABIN"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "TAB2: the same under a valid standing delegation is exit 2, never a discharge"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "TAB2b: nothing was requested"
scn; wa_init; mkholdg tab3 "Wait for wa-key to be accepted" "wa-key"$'\t'"$WA_H"; run_h --plan "$PLAN"
assert_eq "0" "$(last_rc)" "TAB3: a tab between the key and the hash is read as one space (a plain gate)"
scn; wa_init; mkhold1 tab4 "Wait"$'\t'"for wa-key"; run_h --plan "$PLAN"
assert_eq "0" "$(last_rc)" "TAB4: a tab inside the hold's words is read as a space too (the key is still named)"

arm_end tab
arm_begin vu
echo "--- valid_until (CTO ruling D6) ---"
wa_vu() { # <key> <name>: a no-delegation plan on the committed text <key>, and an accepted answer for ITS hash
  scn; wa_init; local h; h="$(blobhash "$1")"; WA_KEY="$1" WA_HASH="$h" mkwa "$2"; wabody accepted "$h" "$WA_DATE_JSON" true; run_h --plan "$PLAN"
}
wa_vu wa-exp vu1
wexpect "VU1: a text whose last day is past stands as a person's matter (exit 1), whatever the founder recorded" 1 "holds: 1 discharged: 0 standing: 1"
assert_eq "1" "$(has_line "Needs a person: do not ship the feature until the founder has accepted the synthetic text wa-exp. - only a person can settle this (the accepted text has passed its last valid day; a revised text is needed)")" "VU1b: with its reason"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "VU1c: nothing was requested"
assert_eq "0" "$(wa_calls doppler-argv.log doppler)" "VU1d: and no token was read"
wa_vu wa-today vu2
if day_stable; then wexpect "VU2: a text whose last day is today is still valid" 0 "holds: 1 discharged: 1 standing: 0"; else day_skip VU2; fi
wa_vu wa-badvu vu3
wexpect "VU3: a last day that is not a date (soon) cannot be used: exit 2" 2 "holds: 1 discharged: 0 standing: 1"
assert_eq "1" "$(has_line "${COULD/synthetic text wa-key./synthetic text wa-badvu.}the saved text is damaged")" "VU3b: with the closed wording"
assert_eq "0" "$(wa_calls curl-argv.log curl)" "VU3c: nothing was requested"
wa_vu wa-badvu2 vu4
wexpect "VU4: a last day written without leading zeros (2099-1-1) cannot be used: exit 2" 2 "holds: 1 discharged: 0 standing: 1"
wa_vu wa-novu vu5
wexpect "VU5: front matter with no valid_until line is no expiry" 0 "holds: 1 discharged: 1 standing: 0"
wa_vu wa-nofm vu6
wexpect "VU6: a text with no front matter at all is no expiry" 0 "holds: 1 discharged: 1 standing: 0"
scn; wa_init; run_h --plan "$PLAN"
wexpect "VU7: instrument: the canonical text (valid_until 2099-12-31) is valid" 0 "holds: 1 discharged: 1 standing: 0"

arm_end vu
arm_begin bind2
echo "--- The binding reads the words the operator reads, and nothing accumulates between holds (FR-SEC, FR-PAT) ---"
scn; wa_init; mkhold1 bindlong "$(printf 'x%.0s' $(seq 1 200)) wa-key"; run_h --plan "$PLAN"
wexpect "BIND9: a key named after the 160th character is still named (the words are matched whole, only the printed line is cut)" 0 "holds: 1 discharged: 1 standing: 0"
scn; wa_init; mkhold1 bindc1 "Wait for wa-ke"$'\xc2\x85'"y to be accepted"; run_h --plan "$PLAN"
wexpect "BIND10: a control character inside the key is removed before the match, as it is before the operator sees it" 0 "holds: 1 discharged: 1 standing: 0"
scn; wa_init; mkdir -p "$TMP/plans"; PLAN="$TMP/plans/bind11.md"
printf '# Plan\n\n## Operator Holds\n\n- Hold: Wait for wa-key to be accepted\n  Gate: web-acceptance wa-key %s\n- Hold: Deploy the payments migration to production\n  Gate: web-acceptance wa-key %s\n\n## Next\n' "$WA_H" "$WA_H" > "$PLAN"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "BIND11: a second hold that omits the key beside a first that names it is not cleared (the first hold's words do not carry over)"
assert_eq "1" "$(machine | grep -c '^holds: 2 discharged: 1 standing: 1$')" "BIND11b: one discharged, one standing"
assert_eq "1" "$(has_line "Could not check: Deploy the payments migration to production - $BINDWHY")" "BIND11c: and the second says why"

arm_end bind2
arm_begin chg
echo "--- Whoever reads the note is told, whatever order the gates come in (FR-UI) ---"
chg_setup() { # <name> <gate lines...>: a plan with a valid delegation, an open earlier change and ONE hold whose gates are given
  scn; wa_init; wabody changes_requested "$WA_H" "$WA_DATE_JSON" true; echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-55.json"
  mkplan2 "$1" "- Hold: ship only when both are true (wa-key).
$2"; RUN_PATH="$WABIN"
}
chg() { chg_setup "$@"; run_h --plan "$PLAN"; }
chg chg1 "  Gate: pr-merged 55
  Gate: web-acceptance wa-key $WA_H"
wexpect "CHG1: an open earlier change first, changes requested second: the hold waits" 1 "holds: 1 discharged: 0 standing: 1"
assert_eq "1" "$(has_line "$NEEDSYOU")" "CHG1b: and the founder's request for changes is still said, with who reads the note"
assert_eq "1" "$(grep -c '^Still waiting: ' "$TMP/o")" "CHG1c: the waiting line is the hold's own line"
chg chg2 "  Gate: web-acceptance wa-key $WA_H
  Gate: pr-merged 55"
wexpect "CHG2: changes requested first, an open earlier change second" 1 "holds: 1 discharged: 0 standing: 1"
assert_eq "1" "$(has_line "$NEEDSYOU")" "CHG2b: the line is said"
chg chg3 "  Gate: web-acceptance wa-key $WA_H"
wexpect "CHG3: changes requested alone" 1 "holds: 1 discharged: 0 standing: 1"
assert_eq "1" "$(has_line "$NEEDSYOU")" "CHG3b: the line is said once"
assert_eq "1" "$(grep -c '^Needs you: ' "$TMP/o")" "CHG3c: exactly once"
scn; wa_init; run_h --plan "$PLAN"
wexpect "CHG4: instrument: the canonical accepted answer says nothing about changes" 0 "holds: 1 discharged: 1 standing: 0"
assert_eq "0" "$(grep -c '^Needs you: ' "$TMP/o")" "CHG4b: no such line"

arm_end chg
w_tz() { wa_init; local h; h="$(blobhash wa-today)"; WA_KEY=wa-yest WA_HASH="$(blobhash wa-yest)" mkwa mtzB; PLANB="$PLAN"; WA_KEY=wa-today WA_HASH="$h" mkwa mtzA; PLANA="$PLAN"; wabody accepted "$h" "$WA_DATE_JSON" true; }
r_tz() { # a text valid through today (UTC) under the zone furthest AHEAD of UTC, a text that ended yesterday under the zone furthest BEHIND: a gate reading the local date fails one of them at every hour
  local rcs=""; TZ=Pacific/Kiritimati run_h --plan "$PLANA"; rcs="$(last_rc)"; TZ=Etc/GMT+12 run_h --plan "$PLANB"; rcs="$rcs $(last_rc)"; echo "holds: x rcs=$rcs" >> "$TMP/o"; echo 0 > "$TMP/rc"; }
arm_begin vu2
echo "--- valid_until: the day before today, the front matter only, the last repeated line, a real calendar day, UTC (FR-SEC, test design) ---"
wa_vu wa-yest vu8
if day_stable; then
  wexpect "VU8: a text whose last day was yesterday is expired" 1 "holds: 1 discharged: 0 standing: 1"
  assert_eq "1" "$(has_line "(the accepted text has passed its last valid day; a revised text is needed)")" "VU8b: with its reason"
  assert_eq "0" "$(wa_calls curl-argv.log curl)" "VU8c: nothing was requested"
else day_skip VU8; fi
wa_vu wa-dup vu9
wexpect "VU9: a repeated valid_until keeps the LAST value (old first, far future last): still valid" 0 "holds: 1 discharged: 1 standing: 0"
wa_vu wa-dup2 vu10
wexpect "VU10: a repeated valid_until keeps the LAST value (far future first, old last): expired" 1 "holds: 1 discharged: 0 standing: 1"
wa_vu wa-bodyvu vu11
wexpect "VU11: a valid_until line in the body, outside the front matter, is ignored" 0 "holds: 1 discharged: 1 standing: 0"
for vk in wa-badvu3 wa-badvu4 wa-badvu5 wa-badvu6; do
  wa_vu "$vk" vu12
  wexpect "VU12: $vk: a valid_until that is not a real calendar day is damaged" 2 "holds: 1 discharged: 0 standing: 1"
  assert_eq "1" "$(has_line "${COULD/synthetic text wa-key./synthetic text $vk.}the saved text is damaged")" "VU12b: $vk: with the closed wording"
  assert_eq "0" "$(wa_calls curl-argv.log curl)" "VU12c: $vk: nothing was requested"
done
scn; w_tz; r_tz
if day_stable; then assert_eq "rcs=0 1" "$(grep -o 'rcs=.*' "$TMP/o")" "VU13: a text valid through today (UTC) is valid under the zone furthest ahead of UTC, and one that ended yesterday is expired under the zone furthest behind (the date is read in UTC)"; else day_skip VU13; fi

arm_end vu2
echo "--- Harness rows: the stubs are load-bearing (removing one must fail the discharge rows, not pass them as held) ---"
scn; wa_init; RUN_PATH="$TMP/wabin-nocurl"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "HR1: with the curl stub removed the canonical discharge is NOT a discharge (the discharge rows above would fail)"
assert_eq "1" "$(has_line "${COULD}I could not reach the check (HTTP 000, curl rc 127)")" "HR1b: it reads as unreachable, with the numbers only"
scn; wa_init; RUN_PATH="$TMP/wabin-nodoppler"; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "HR2: with the doppler stub removed the canonical discharge is NOT a discharge"
assert_eq "1" "$(has_line "${COULD}no saved sign-in value was found")" "HR2b: it reads as no saved sign-in value"
echo "--- Human lines carry no jargon (web-acceptance outputs) ---"
for variant in "done" declined changes none invalid unreachable mismatch expired nobind notavail refused unknown badanswer badgate; do
  scn; wa_init
  case "$variant" in
    declined) wabody declined "$WA_H" "$WA_DATE_JSON" true ;;
    changes) wabody changes_requested "$WA_H" "$WA_DATE_JSON" true ;;
    none) wabody none "$WA_H" null null ;;
    invalid) wabody invalid "$WA_H" "$WA_DATE_JSON" false ;;
    unreachable) echo 28 > "$STUB_DIR/curl-rc" ;;
    mismatch) WA_HASH="$WA_H2" mkwa jm ;;
    expired) WA_KEY=wa-exp WA_HASH="$(blobhash wa-exp)" mkwa jx; wabody accepted "$(blobhash wa-exp)" "$WA_DATE_JSON" true ;;
    nobind) mkhold1 jb "Deploy the payments migration to production" ;;
    notavail) echo 503 > "$STUB_DIR/curl-status" ;;
    refused) echo 401 > "$STUB_DIR/curl-status" ;;
    unknown) echo 404 > "$STUB_DIR/curl-status" ;;
    badanswer) : > "$STUB_DIR/curl-body" ;;
    badgate) mkholdg jg "Wait for wa-key" "wa-key" ;;
  esac
  run_h --plan "$PLAN"; cp "$TMP/o" "$TMP/human-wa-$variant.txt"; cat "$TMP/e" >> "$TMP/human-wa-$variant.txt"
  assert_eq "1" "$([[ -s "$TMP/human-wa-$variant.txt" ]] && echo 1 || echo 0)" "the web-acceptance $variant output is not empty"
  assert_eq "0" "$(jargon_hits "$TMP/human-wa-$variant.txt")" "no uppercase jargon or number token in the web-acceptance $variant output"
  assert_eq "0" "$(jargon_hits_ci "$TMP/human-wa-$variant.txt")" "no denylisted word in the web-acceptance $variant output"
done
echo "--- No stub refused an argv anywhere in the web-acceptance scenarios so far ---"
miss_n=0; for f in "$TMP"/scn*/curl-argv.log "$TMP"/scn*/doppler-argv.log; do [[ -f "$f" ]] && miss_n=$((miss_n + $(grep -c 'STUB-MISS' "$f" || true))); done
assert_eq "0" "$miss_n" "no curl or doppler stub miss across all web-acceptance scenarios (the rows that expected a miss, T7/T8, never reach a stub with a wrong argv)"

arm_end wa
echo "=== Arm 13: mutations (the pristine control first) ==="
MUT="$TMP/mut"; mkdir -p "$MUT"; PRISTINE_DIR="$TMP/pristine/skills/ship/scripts"; mkdir -p "$PRISTINE_DIR"
# The evaluator resolves the verifier relative to itself, so mutants live in a tree that mirrors the plugin layout.
mkdir -p "$TMP/pristine/scripts/lib"; cp "$REPO_ROOT/plugins/soleur/scripts/delegation-verify.sh" "$TMP/pristine/scripts/"
# The plugin helper (NOT the repository-root helper of the same file name); built from a directory so no path in this suite is a tail match for the root helper.
PLUGIN_LIB_DIR="$REPO_ROOT/plugins/soleur/scripts/lib"
cp "$PLUGIN_LIB_DIR/bearer-fetch.sh" "$TMP/pristine/scripts/lib/"
PRISTINE="$PRISTINE_DIR/hold-gate-eval.sh"; cp "$SUT_REAL" "$PRISTINE"
cp "$TMP/pristine/scripts/delegation-verify.sh" "$TMP/real-verifier.sh"
mutate() { # <name> <sed -E expr>: write a mutant inside a mirrored tree and prove the mutation LANDED
  local d="$TMP/mutants/$1"; mkdir -p "$d/skills/ship/scripts" "$d/scripts/lib"
  cp "$REPO_ROOT/plugins/soleur/scripts/delegation-verify.sh" "$d/scripts/"; cp "$PLUGIN_LIB_DIR/bearer-fetch.sh" "$d/scripts/lib/"
  sed -E "$2" "$PRISTINE" > "$d/skills/ship/scripts/hold-gate-eval.sh"
  if cmp -s "$PRISTINE" "$d/skills/ship/scripts/hold-gate-eval.sh"; then echo "  FAIL: mutation $1 did not land"; FAIL=$((FAIL + 1)); return 1; fi
  echo "  PASS: mutation $1 landed"; PASS=$((PASS + 1))
}
mutate_lib() { # <name> <sed -E expr>: the evaluator is unchanged, the shared helper beside it is edited
  local d="$TMP/mutants/$1" lib="$PLUGIN_LIB_DIR/bearer-fetch.sh"; mkdir -p "$d/skills/ship/scripts" "$d/scripts/lib"
  cp "$REPO_ROOT/plugins/soleur/scripts/delegation-verify.sh" "$d/scripts/"; cp "$PRISTINE" "$d/skills/ship/scripts/hold-gate-eval.sh"
  local mlib="$d/scripts/lib"; sed -E "$2" "$lib" > "$mlib/bearer-fetch.sh"
  if cmp -s "$lib" "$mlib/bearer-fetch.sh"; then echo "  FAIL: mutation $1 did not land"; FAIL=$((FAIL + 1)); return 1; fi
  echo "  PASS: mutation $1 landed"; PASS=$((PASS + 1))
}
noop() { echo "s/^.*# mut:$1\$/: # mut:$1/"; }
probe() { # <setup-fn> <runner> -> PROBE_OUT="rc|machine line"
  local fn="$1" runner="$2"
  scn; "$fn"; "$runner"
  PROBE_OUT="$(last_rc)|$(machine)"
}
r_plan() { run_h --plan "$PLAN"; }
r_stale() { stale_run; }
s_mixed() { mkplan mixed; }
s_stale() { jq -n --arg s "$SHA_MOVED" '{state:"MERGED", mergeCommit:{oid:$s}, baseRefName:"main"}' > "$STUB_DIR/pr-55.json"; }
s_trunk() { jq -n --arg s "$SHA_TRUNK" '{state:"MERGED", mergeCommit:{oid:$s}, baseRefName:"trunk"}' > "$STUB_DIR/pr-55.json"; cp "$STUB_DIR/pr-55.json" "$STUB_DIR/pr-120.json"; mkplan mixed; RUN_REPO="$W6"; }
s_vstdin() { mkplan mvs; RUN_STDIN="$TMP/stdin-ten"; export FAKE_V_OUT='delegation: valid reason=ok\n' FAKE_V_RC=0; cp "$FAKE/scripts/delegation-verify.sh" "$TMP/pristine/scripts/delegation-verify.sh"; cp "$FAKE/scripts/delegation-verify.sh" "$TMP/mutants/stdin-verify/scripts/delegation-verify.sh"; }
r_vstdin() { run_h --plan "$PLAN"; echo "holds: x vstdin=$(tr -d ' \n' < "$STUB_DIR/v-stdin-bytes")" >> "$TMP/o"; unset FAKE_V_OUT FAKE_V_RC; cp "$TMP/real-verifier.sh" "$TMP/pristine/scripts/delegation-verify.sh"; }
s_star() { mkholds mstar "- Hold: do not ship while a release is running.
  Gate: no-inflight-run example-release.yml
- Hold$FW wait for the earlier change.
  Gate$FW pr-merged 55"; }
s_resv() { mkholds mresv '- Hold: do not ship while a release is running.
  Gate: no-inflight-run example-release.yml
- Hold: **Operator-reserved:** approve the pricing copy
  Gate: pr-merged 55'; }
s_hidden() { mkplan mhid ''; printf '\n## Operator Hold (misspelt, second)\n\n- Hold: Do not merge until Dana has signed off the copy.\n  Gate: pr-merged 9999\n' >> "$PLAN"; }
s_dirty() { echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-120.json"; sed -i.bak '/^- Gate: pr-merged 120$/d' "$W/env-valid.md"; rm -f "$W/env-valid.md.bak"; }
r_dirty() { run_h --file env-valid.md --section "Production Envelope"; git -C "$W" checkout -q -- env-valid.md; }
s_reserved() { mkplan mres 's/^- Hold: do not ship while a release is running\./- Hold: Operator-reserved: approve the new pricing page copy./'; }
s_prose2() { PLAN="$FX/holds-prose.md"; }
s_status() { echo "[{\"status\":\"$STATUS_PROBE\"}]" > "$STUB_DIR/runs-example-release.yml.json"; mkplan mixed; }
s_eat() { touch "$STUB_DIR/eat-stdin"; echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-9999.json"; mkplan eat 's/^  Gate: no-inflight-run example-release.yml$/  Gate: no-inflight-run example-release.yml\n  Gate: pr-merged 9999/'; }
s_hx9() { printf '# Plan\n\n```text\n## Operator Holds\n\n- Hold: an example in a fence\n  Gate: pr-merged 9999\n```\n\n## Operator Holds\n\nDelegation: %s\nEnvelope: env-valid.md\n\n- Hold: do not ship while a release is running.\n  Gate: no-inflight-run example-release.yml\n' "$URL" > "$TMP/plans/mhx9.md"; PLAN="$TMP/plans/mhx9.md"; }
s_heading() { mkplan mhd 's/^## Operator Holds$/### Operator holds/'; }
s_fchar() { mkholds mfchar $'- Hold: do not ship while a release is running.\n  Gate: no-inflight-run example-release.yml\n\n```text\n~~~\n- Hold: still inside the backtick fence\n  Gate: pr-merged 9999\n```'; }
s_stray() { printf '# Plan\n\nGate: pr-merged 55\n' > "$TMP/plans/mstray.md"; PLAN="$TMP/plans/mstray.md"; }
s_twodeleg() { mkholds mtwo $'- Hold: do not ship while a release is running.\n  Gate: no-inflight-run example-release.yml\nDelegation: https://github.com/example-org/example-repo/issues/77#issuecomment-1002'; }
s_noenv() { mkplan mnoenv '/^Envelope: /d'; }
s_lastwins() { echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-9999.json"; mkholds mlast $'- Hold: ship only when both are true.\n  Gate: pr-merged 9999\n  Gate: no-inflight-run example-release.yml'; }
s_doneg() { mkplan mdone; }
r_checked() { run_h --plan "$PLAN"; echo "holds: x checked=$(grep -c ' - checked: ' "$TMP/o")" >> "$TMP/o"; }
s_zerohold() { printf '# Plan\n\n## Operator Holds\n\nDelegation: %s\nEnvelope: env-valid.md\n\n- Wait for the earlier change.\n\nPlain prose with no Hold items.\n' "$URL" > "$TMP/plans/mzero.md"; PLAN="$TMP/plans/mzero.md"; }
s_lcgate() { mkholds mlc $'- Hold: ship only when both are true.\n  Gate: no-inflight-run example-release.yml\n  gate: pr-merged 9999'; echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-9999.json"; }
s_notimeout() { mkplan mnt; RUN_PATH="$TMP/nobin-timeout"; }
s_nojq3() { RUN_PATH="$TMP/nobin-jq"; PLAN="$FX/holds-prose.md"; }
s_ctl() { mkholds mctl "$(printf -- '- Hold: do not ship \302\205red text\n  Gate: no-inflight-run example-release.yml')"; }
r_ctl() { run_h --plan "$PLAN"; echo "holds: x esc=$(LC_ALL=C grep -c "$(printf '\302\205')" "$TMP/o")" >> "$TMP/o"; }
s_cb() { { printf '# Plan\n\n## Operator Holds\n\nDelegation: %s\nEnvelope: env-valid.md\n\n' "$URL"; printf -- '- Hold: do not ship while a release is running.\033\n  Gate: no-inflight-run example-release.yml\n'; } > "$TMP/plans/mcb.md"; PLAN="$TMP/plans/mcb.md"; }
s_filepath() { :; }
r_file_title() { run_h --file "env-two.md#beta dispatch"; }
s_unkstatus() { echo '[{"status":"frobnicated"}]' > "$STUB_DIR/runs-example-release.yml.json"; mkplan munk; }
crashed() { [[ "$(last_rc)" == 127 ]] || grep -qE 'unbound variable|syntax error|command not found' "$TMP/e"; }
killed() { # <name> <pinned> <setup-fn> <runner>
  local name="$1" pinned="$2"
  SUT="$PRISTINE"; probe "$3" "$4"
  if [[ "$PROBE_OUT" != "$pinned" ]]; then echo "  FAIL: $name: the pristine script gives '$PROBE_OUT', not the pinned '$pinned'"; FAIL=$((FAIL + 1)); SUT="$SUT_REAL"; return; fi
  SUT="$TMP/mutants/$name/skills/ship/scripts/hold-gate-eval.sh"; probe "$3" "$4"
  if crashed; then echo "  FAIL: mutant $name CRASHED; a crash is not a kill"; FAIL=$((FAIL + 1))
  elif [[ "$PROBE_OUT" != "$pinned" ]]; then echo "  PASS: mutant $name killed ('$PROBE_OUT')"; PASS=$((PASS + 1))
  else echo "  FAIL: mutant $name SURVIVED ('$PROBE_OUT')"; FAIL=$((FAIL + 1)); fi
  SUT="$SUT_REAL"
}
SUT="$PRISTINE"; probe s_mixed r_plan; assert_eq "0|holds: 3 discharged: 3 standing: 0" "$PROBE_OUT" "mutation control: the pristine copy is green"; SUT="$SUT_REAL"
( b=$FAIL; killed ctrl "9|never" s_mixed r_plan >/dev/null; [[ $FAIL -gt $b ]] ) \
  || { printf 'FATAL: killed cannot report a pristine that differs from its pin\n' >&2; exit 2; }
( b=$FAIL; mutate ctrl 's/zz-no-such-text-zz/y/' >/dev/null; [[ $FAIL -gt $b ]] ) \
  || { printf 'FATAL: mutate cannot report a mutation that did not land\n' >&2; exit 2; }
# T6: the SURVIVED branch has a positive control. mutants/ctrl is now a byte-identical copy of the pristine script (an equivalent mutation),
# so killed with the pristine's own answer as the pin MUST report it SURVIVED and count a failure; a killed that always said "killed" would pass nothing.
( out="$(killed ctrl "0|holds: 3 discharged: 3 standing: 0" s_mixed r_plan)"; [[ "$out" == *"SURVIVED"* && "$out" != *"killed"* ]] ) \
  || { printf 'FATAL: killed cannot report an equivalent mutation as SURVIVED\n' >&2; exit 2; }
( b=$FAIL; killed ctrl "0|holds: 3 discharged: 3 standing: 0" s_mixed r_plan >/dev/null; [[ $FAIL -eq $((b + 1)) ]] ) \
  || { printf 'FATAL: a SURVIVED mutant is not counted as a failure\n' >&2; exit 2; }
# F4: the crash detector itself is under a control: a mutant that is a deliberate syntax error must be reported as CRASHED, not killed
mutate crashctl 's/^set -uo pipefail$/set -uo pipefail; if then/' >/dev/null
( out="$(killed crashctl "0|holds: 3 discharged: 3 standing: 0" s_mixed r_plan)"; [[ "$out" == *"CRASHED"* ]] ) \
  || { printf 'FATAL: crashed cannot detect a crashing mutant -- a crash would be graded as a kill\n' >&2; exit 2; }

# 1 an unknown kind must not pass
mutate unknown-kind 's/GRES=UNEVAL; return; \}( # mut:unknown-kind)/GRES=TRUE; return; }\1/' && killed unknown-kind "2|holds: 3 discharged: 2 standing: 1" s_unknown r_plan
# 2 a hold with no gate must stand
mutate zero-gates "$(noop zero-gates)" && killed zero-gates "1|holds: 3 discharged: 2 standing: 1" s_nogate r_plan
# 3 stopping at the first gate is the defect; the last gate winning is the same defect from the other side
mutate all-gates 's/esac # mut:all-gates/esac; break # mut:all-gates/' && killed all-gates "1|holds: 3 discharged: 2 standing: 1" s_twogates r_plan
mutate last-wins 's/case "\$GRES" in TRUE\) ;;/case "$GRES" in TRUE) HV=OK ;;/' && killed last-wins "1|holds: 1 discharged: 0 standing: 1" s_lastwins r_plan
# 4 an invalid delegation leaves every hold standing; the verifier's rc counts too
mutate deleg-valid "$(noop deleg-valid)" && killed deleg-valid "1|holds: 3 discharged: 0 standing: 3" s_edited r_plan
# 5 no delegation recorded is exit 3, and it comes before the other structure checks
mutate no-deleg "$(noop no-deleg)" && killed no-deleg "3|holds: 3 discharged: 0 standing: 3" s_nodeleg r_plan
# 6 a delegation but zero holds is exit 2
mutate zero-holds "$(noop zero-holds)" && killed zero-holds "2|" s_zerohold r_plan
# 7 a stale origin
mutate fetch "$(noop fetch)" && killed fetch "1|holds: 1 discharged: 0 standing: 1" s_stale r_stale
# 8 the default branch is resolved, not assumed
mutate defbr "$(noop defbr)" && killed defbr "0|holds: 3 discharged: 3 standing: 0" s_trunk r_plan
# 9 the in-flight state set
STATUS_PROBE=requested
mutate status-requested 's/ or \$s == "requested"//' && killed status-requested "1|holds: 3 discharged: 2 standing: 1" s_status r_plan
STATUS_PROBE=pending
mutate status-pending 's/ or \$s == "pending"//' && killed status-pending "1|holds: 3 discharged: 2 standing: 1" s_status r_plan
STATUS_PROBE=waiting
mutate status-waiting 's/ or \$s == "waiting"//' && killed status-waiting "1|holds: 3 discharged: 2 standing: 1" s_status r_plan
mutate status-unknown "$(noop status-unknown)" && killed status-unknown "2|holds: 3 discharged: 2 standing: 1" s_unkstatus r_plan
# 10 stdin hygiene
mutate stdin-gh 's# </dev/null( \|\| return 1 \# mut:stdin-gh)#\1#' && killed stdin-gh "1|holds: 3 discharged: 2 standing: 1" s_eat r_plan
mutate stdin-verify 's# </dev/null (> "\$WORK/verdict")# \1#' && killed stdin-verify "0|holds: x vstdin=0" s_vstdin r_vstdin
# the verifier's rc counts as well as its first line (a fake verifier stands in for the real one in both trees)
mutate deleg-rc 's/ && \[ "\$VRC" -eq 0 \]//' && {
  cp "$FAKE/scripts/delegation-verify.sh" "$TMP/pristine/scripts/delegation-verify.sh"; cp "$FAKE/scripts/delegation-verify.sh" "$TMP/mutants/deleg-rc/scripts/delegation-verify.sh"
  export FAKE_V_OUT='delegation: valid reason=ok\n' FAKE_V_RC=7
  killed deleg-rc "2|holds: 3 discharged: 0 standing: 3" s_mixed r_plan
  unset FAKE_V_OUT FAKE_V_RC; cp "$TMP/real-verifier.sh" "$TMP/pristine/scripts/delegation-verify.sh"
}
mutate stray-all "$(noop stray-all)" && killed stray-all "2|holds: 3 discharged: 0 standing: 3" s_hidden r_plan
mutate marker-norm 's/nt = norm\(t\) # mut:marker-norm/nt = t # mut:marker-norm/' && killed marker-norm "0|holds: 2 discharged: 2 standing: 0" s_star r_plan
mutate reserved-norm 's/^.*# mut:reserved-norm$/  rn="" # mut:reserved-norm/' && killed reserved-norm "2|holds: 2 discharged: 1 standing: 1" s_resv r_plan
mutate file-head "$(noop file-head)" && killed file-head "1|holds: 1 discharged: 0 standing: 1" s_dirty r_dirty
mutate reserved "$(noop reserved)" && killed reserved "2|holds: 3 discharged: 2 standing: 1" s_reserved r_plan
# 11 structure
mutate heading-ci 's/(rest = )tolower\(([^#]*)\) # mut:heading-ci/\1\2 # mut:heading-ci/' && killed heading-ci "0|holds: 3 discharged: 3 standing: 0" s_heading r_plan
mutate fence-char 's/c == fc && n >= fn && //g' && killed fence-char "0|holds: 1 discharged: 1 standing: 0" s_fchar r_plan
mutate fence-split 's/\{ fence\(\) \} # mut:fence-split/{ } # mut:fence-split/' && killed fence-split "0|holds: 1 discharged: 1 standing: 0" s_hx9 r_plan
mutate stray "$(noop stray)" && killed stray "2|" s_stray r_plan
mutate deleg-multi "$(noop deleg-multi)" && killed deleg-multi "2|holds: 1 discharged: 0 standing: 1" s_twodeleg r_plan
mutate envelope-req "$(noop envelope-req)" && killed envelope-req "2|holds: 3 discharged: 0 standing: 3" s_noenv r_plan
mutate ci-markers 's/lt = tolower\(st\) # mut:ci-markers/lt = st # mut:ci-markers/' && killed ci-markers "1|holds: 1 discharged: 0 standing: 1" s_lcgate r_plan
mutate done-gates "$(noop done-gates)" && killed done-gates "0|holds: x checked=3" s_doneg r_checked
# 12 tools, sanitising, the --file address
mutate need-timeout "$(noop need-timeout)" && killed need-timeout "2|" s_notimeout r_plan
mutate clean-text "s/^clean_text\\(\\) .*# mut:clean-text\$/clean_text() { printf '%s' \"\\\$1\"; } # mut:clean-text/" && killed clean-text "0|holds: x esc=0" s_ctl r_ctl
mutate clean-uncut "s/^clean_uncut\\(\\) .*# mut:clean-uncut\$/clean_uncut() { printf '%s' \"\\\$1\"; } # mut:clean-uncut/" && killed clean-uncut "0|holds: x esc=0" s_ctl r_ctl
mutate ctl-bytes "$(noop ctl-bytes)" && killed ctl-bytes "2|" s_cb r_plan
mutate file-title "$(noop file-title)" && killed file-title "0|holds: 1 discharged: 1 standing: 0" s_filepath r_file_title

# --- web-acceptance (Guard 1 mutation rows 1 to 11 and the harness rows) ------------------------------------------------
# r_wa runs the plan and appends ONE line carrying the machine counts and the first printed reason (dates masked), so a mutant
# that keeps the exit code but changes the verdict wording is still caught.
r_wa() { run_h --plan "$PLAN"; echo "holds: x $(machine | sed 's/^holds: //') why=$(why_of)" >> "$TMP/o"; }
r_wa_needs() { run_h --plan "$PLAN"; echo "holds: x $(machine | sed 's/^holds: //') needs=$(grep -c '^Needs you: ' "$TMP/o")" >> "$TMP/o"; }
r_wafile() { run_h --file env-wa.md --section "Production Envelope"; echo "holds: x $(machine | sed 's/^holds: //') why=$(why_of)" >> "$TMP/o"; }
r_wa_in() { run_h --plan "$PLAN"; echo "holds: x $(machine | sed 's/^holds: //') stdin-calls=$(grep -vcx 0 "$STUB_DIR/stdin-bytes" 2>/dev/null)" >> "$TMP/o"; }
r_envbase() { HGE_WA_BASE='https://evil.example.test/api' r_wa; }
PU="2|holds: x 1 discharged: 0 standing: 1 why=I could not reach the check (HTTP 000, curl rc 28)"
PU500="2|holds: x 1 discharged: 0 standing: 1 why=I could not reach the check (HTTP 500, curl rc 0)"
PU307="2|holds: x 1 discharged: 0 standing: 1 why=I could not reach the check (HTTP 307, curl rc 0)"
PNU="2|holds: x 1 discharged: 0 standing: 1 why=answer not understood"
P_OK="0|holds: x 1 discharged: 1 standing: 0 why=checked: web-acceptance wa-key $WA_H (decided DATE)"
PSHAPE="2|holds: x 1 discharged: 0 standing: 1 why=the web acceptance is not written as a plain text name and fingerprint"
PCANT="2|holds: x 1 discharged: 0 standing: 1 why=the saved text is damaged"
PNOTIN="2|holds: x 1 discharged: 0 standing: 1 why=the saved text is not in the project"
PBIND="2|holds: x 1 discharged: 0 standing: 1 why=$BINDWHY"
w_ok() { wa_init; }
w_declined() { wa_init; wabody declined "$WA_H" "$WA_DATE_JSON" true; }
w_changes() { wa_init; wabody changes_requested "$WA_H" "$WA_DATE_JSON" true; }
w_none() { wa_init; wabody none "$WA_H" null null; }
w_invalid() { wa_init; wabody invalid "$WA_H" "$WA_DATE_JSON" false; }
w_rc28() { wa_init; echo 28 > "$STUB_DIR/curl-rc"; }
w_500() { wa_init; echo 500 > "$STUB_DIR/curl-status"; }
w_307() { wa_init; echo 307 > "$STUB_DIR/curl-status"; }
w_emptybody() { wa_init; : > "$STUB_DIR/curl-body"; }
w_mismatch() { wa_init; WA_HASH="$WA_H2" mkwa mmut; }
w_echo() { wa_init; wabody accepted "$WA_H2" "$WA_DATE_JSON" true; }
w_badstatus() { wa_init; wabody approved "$WA_H" "$WA_DATE_JSON" true; }
w_rowfalse() { wa_init; wabody accepted "$WA_H" "$WA_DATE_JSON" false; }
w_rowstr() { wa_init; wabody accepted "$WA_H" "$WA_DATE_JSON" '"yes"'; }
w_rowone() { wa_init; wabody accepted "$WA_H" "$WA_DATE_JSON" 1; }
w_badgate() { wa_init; sed -E -e "s|@KEY@|wa-key|g" -e "s|^  Gate: .*|  Gate: web-acceptance $BADGATE|" "$FXH/plan-web-acceptance-only.md" > "$TMP/plans/mbad.md"; PLAN="$TMP/plans/mbad.md"; }
w_cr() { wa_init; CRH="$(git -C "$W" cat-file blob HEAD:apps/web-platform/server/legal-acceptance/texts/wa-cr.md | sha256sum | cut -c1-64)"; WA_KEY=wa-cr WA_HASH="$CRH" mkwa mcr; wabody accepted "$CRH" "$WA_DATE_JSON" true; }
w_link() { wa_init; LNH="$(printf 'wa-key.md' | sha256sum | cut -c1-64)"; WA_KEY=wa-link WA_HASH="$LNH" mkwa mlink; wabody accepted "$LNH" "$WA_DATE_JSON" true; }
w_payments() { wa_init; mkhold1 mpay "Deploy the payments migration to production"; }
w_bindlong() { wa_init; mkhold1 mbl "Wait for wa-key-two"; }
w_bindcase() { wa_init; mkhold1 mbc "Wait for WA-KEY"; }
w_tab() { wa_init; mkholdg mtab "Wait for wa-key to be accepted" "$TABGATE"; }
w_expired() { wa_init; local h; h="$(blobhash wa-exp)"; WA_KEY=wa-exp WA_HASH="$h" mkwa mexp; wabody accepted "$h" "$WA_DATE_JSON" true; }
w_badvu() { wa_init; local h; h="$(blobhash wa-badvu)"; WA_KEY=wa-badvu WA_HASH="$h" mkwa mbvu; wabody accepted "$h" "$WA_DATE_JSON" true; }
w_dup() { wa_init; local h; h="$(blobhash wa-dup)"; WA_KEY=wa-dup WA_HASH="$h" mkwa mdup; wabody accepted "$h" "$WA_DATE_JSON" true; }
w_dup2() { wa_init; local h; h="$(blobhash wa-dup2)"; WA_KEY=wa-dup2 WA_HASH="$h" mkwa mdup2; wabody accepted "$h" "$WA_DATE_JSON" true; }
w_bodyvu() { wa_init; local h; h="$(blobhash wa-bodyvu)"; WA_KEY=wa-bodyvu WA_HASH="$h" mkwa mbodyvu; wabody accepted "$h" "$WA_DATE_JSON" true; }
w_badvu3() { wa_init; local h; h="$(blobhash wa-badvu3)"; WA_KEY=wa-badvu3 WA_HASH="$h" mkwa mbvu3; wabody accepted "$h" "$WA_DATE_JSON" true; }
w_badvu4() { wa_init; local h; h="$(blobhash wa-badvu4)"; WA_KEY=wa-badvu4 WA_HASH="$h" mkwa mbvu4; wabody accepted "$h" "$WA_DATE_JSON" true; }
w_badvu5() { wa_init; local h; h="$(blobhash wa-badvu5)"; WA_KEY=wa-badvu5 WA_HASH="$h" mkwa mbvu5; wabody accepted "$h" "$WA_DATE_JSON" true; }
w_badvu6() { wa_init; local h; h="$(blobhash wa-badvu6)"; WA_KEY=wa-badvu6 WA_HASH="$h" mkwa mbvu6; wabody accepted "$h" "$WA_DATE_JSON" true; }
w_bindus() { wa_init; mkhold1 mbus "Wait for wa-key_x"; }
w_ntkey() { wa_init; mkhold1 mnt1 "Wait for founder-acceptance-record to be accepted" "founder-acceptance-record" "$WA_H"; }
w_ntsuf() { wa_init; mkhold1 mnt2 "Wait for acceptance-record to be accepted" "acceptance-record" "$WA_H"; }
w_ntpre() { wa_init; mkhold1 mnt3 "Wait for founder-acceptance to be accepted" "founder-acceptance" "$WA_H"; }
w_ntord() { wa_init; mkhold1 mnt4 "Wait for wa-key to be accepted"; }
w_bindc1() { wa_init; mkhold1 mbc1 "Wait for wa-ke"$'\xc2\x85'"y to be accepted"; }
w_bind200() { wa_init; mkhold1 mb200 "$(printf 'x%.0s' $(seq 1 200)) wa-key"; }
w_bind2() { wa_init; PLAN="$TMP/plans/mb2.md"; mkdir -p "$TMP/plans"; printf '# Plan\n\n## Operator Holds\n\n- Hold: Wait for wa-key to be accepted\n  Gate: web-acceptance wa-key %s\n- Hold: Deploy the payments migration to production\n  Gate: web-acceptance wa-key %s\n\n## Next\n' "$WA_H" "$WA_H" > "$PLAN"; }
w_chg1() { chg_setup mchg1 "  Gate: pr-merged 55
  Gate: web-acceptance wa-key $WA_H"; }
w_shapetok() { wa_init; printf '%s\n' 'SYNTHshort0123' > "$STUB_DIR/doppler-token"; }
w_badvu2() { wa_init; local h; h="$(blobhash wa-badvu2)"; WA_KEY=wa-badvu2 WA_HASH="$h" mkwa mbvu2; wabody accepted "$h" "$WA_DATE_JSON" true; }
w_statusnl() { wa_init; jbody '"accepted\n"' '"2026-11-05T10:15:30Z"' true; }
w_statusnul() { wa_init; jbody '"accepted\u0000"' '"2026-11-05T10:15:30Z"' true; }
w_dupstatus() { wa_init; printf '{"status":"none","status":"accepted","text_hash":"%s","decided_at":"2026-11-05T10:15:30Z","row_ok":true}\n' "$WA_H" > "$STUB_DIR/curl-body"; }
w_duprowok() { wa_init; printf '{"status":"accepted","text_hash":"%s","decided_at":"2026-11-05T10:15:30Z","row_ok":false,"row_ok":true}\n' "$WA_H" > "$STUB_DIR/curl-body"; }
w_duprowok2() { wa_init; printf '{"status":"accepted","text_hash":"%s","decided_at":"2026-11-05T10:15:30Z","row_ok":{"a":1},"row_ok":true}\n' "$WA_H" > "$STUB_DIR/curl-body"; }
w_date() { wa_init; jbody '"accepted"' "\"$DATEPROBE\"" true; }
w_datenl() { wa_init; jbody '"accepted"' '"2026-11-05T10:15:30Z\n"' true; }
w_renamed() { wa_init; printf '{"status":"none","text_hash":"%s","decided_at":null,"rowok":null}\n' "$WA_H" > "$STUB_DIR/curl-body"; }
w_two() { wa_init; : > "$STUB_DIR/eat-stdin"; printf 'ten bytes!' > "$TMP/stdin-ten"; RUN_STDIN="$TMP/stdin-ten"; { printf '# Plan (synthesized)\n\n## Operator Holds\n\n- Hold: first web acceptance wa-key.\n  Gate: web-acceptance wa-key %s\n  Gate: web-acceptance wa-key %s\n- Hold: second web acceptance wa-key.\n  Gate: web-acceptance wa-key %s\n  Gate: web-acceptance wa-key %s\n\n## Next\n' "$WA_H" "$WA_H" "$WA_H" "$WA_H"; } > "$TMP/plans/mtwo.md"; PLAN="$TMP/plans/mtwo.md"; }
w_mixed() { wa_init; sed -E -e "s|@KEY@|wa-key|g" -e "s|@HASH@|$WA_H|g" "$FXH/plan-web-acceptance-mixed.md" > "$TMP/plans/mmixed.md"; PLAN="$TMP/plans/mmixed.md"; }
w_mixed_open() { w_mixed; echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-55.json"; }
w_resonly() { wa_init; sed -E -e "s|@KEY@|wa-key|g" -e "s|@HASH@|$WA_H|g" "$FXH/plan-reserved-only.md" > "$TMP/plans/mres.md"; PLAN="$TMP/plans/mres.md"; }
w_gateless() { wa_init; printf '# Plan\n\n## Operator Holds\n\n- Hold: wait for the founder to read it.\n' > "$TMP/plans/mgl.md"; PLAN="$TMP/plans/mgl.md"; }
w_wa_gateless() { wa_init; { printf '# Plan\n\n## Operator Holds\n\n- Hold: first wa-key.\n  Gate: web-acceptance wa-key %s\n- Hold: wait for the founder to read it as well.\n\n## Next\n' "$WA_H"; } > "$TMP/plans/mwg.md"; PLAN="$TMP/plans/mwg.md"; }
# 1 unreadable must hold: a timeout, a 5xx, a redirect, an empty body
mutate curl-fail 's/(GRES=)UNEVAL; GWHY="[^"]*"; return; \} # mut:curl-fail/\1TRUE; GWHY=""; return; } # mut:curl-fail/' && killed curl-fail "$PU" w_rc28 r_wa
mutate status-default 's/\*\) GRES=UNEVAL; GWHY="[^"]*"; return ;; # mut:status-default/*) GRES=TRUE; GWHY=""; return ;; # mut:status-default/' && {
  killed status-default "$PU500" w_500 r_wa; killed status-default "$PU307" w_307 r_wa; }
mutate empty-body 's/^wa_jq\(\) \{ .*$/wa_jq() { return 0; }/;s/^.*# mut:body-dupkeys$/: # mut:body-dupkeys/;s/\*\) wa_notu; return ;; # mut:body-status/*) GRES=TRUE; GWHY=""; return ;; # mut:body-status/' && killed empty-body "$PNU" w_emptybody r_wa
# 2 only accepted discharges; invalid is UNEVAL with its own words
mutate st-declined 's/declined\) GRES=PERSON; GWHY="[^"]*" ;; # mut:st-declined/declined) GRES=TRUE; GWHY="" ;; # mut:st-declined/' && killed st-declined "1|holds: x 1 discharged: 0 standing: 1 why=only a person can settle this (declined; a revised text is needed)" w_declined r_wa
mutate st-changes 's/changes_requested\) GRES=PERSON; /changes_requested) GRES=TRUE; /' && killed st-changes "1|holds: x 1 discharged: 0 standing: 1 why=only a person can settle this" w_changes r_wa
mutate st-changes-line 's/GLINE="[^"]*" ;; # mut:st-changes/GLINE="" ;; # mut:st-changes/' && killed st-changes-line "1|holds: x 1 discharged: 0 standing: 1 needs=1" w_changes r_wa_needs
mutate st-none 's/none\) GRES=FALSE; GWHY="[^"]*" ;; # mut:st-none/none) GRES=TRUE; GWHY="" ;; # mut:st-none/' && killed st-none "1|holds: x 1 discharged: 0 standing: 1 why=no decision recorded for this text version" w_none r_wa
mutate st-invalid-true 's/invalid\) GRES=UNEVAL; GWHY="[^"]*" ;; # mut:st-invalid/invalid) GRES=TRUE; GWHY="" ;; # mut:st-invalid/' && killed st-invalid-true "2|holds: x 1 discharged: 0 standing: 1 why=the saved decision looks damaged" w_invalid r_wa
mutate st-invalid-false 's/invalid\) GRES=UNEVAL; GWHY=/invalid) GRES=FALSE; GWHY=/' && killed st-invalid-false "2|holds: x 1 discharged: 0 standing: 1 why=the saved decision looks damaged" w_invalid r_wa
mutate st-invalid-none 's/invalid\) GRES=UNEVAL; GWHY="[^"]*" ;; # mut:st-invalid/invalid) GRES=FALSE; GWHY="no decision recorded for this text version" ;; # mut:st-invalid/' && killed st-invalid-none "2|holds: x 1 discharged: 0 standing: 1 why=the saved decision looks damaged" w_invalid r_wa
mutate body-status 's/\*\) wa_notu; return ;; # mut:body-status/*) GRES=TRUE; GWHY=""; return ;; # mut:body-status/' && killed body-status "$PNU" w_badstatus r_wa
# 3 the committed text hash is compared; 4 the echoed hash is compared; 5 the case is wired; the body keys are exact
mutate local-hash "$(noop local-hash)" && killed local-hash "1|holds: x 1 discharged: 0 standing: 1 why=the text was changed after this check was written" w_mismatch r_wa
mutate echo-hash "$(noop echo-hash)" && killed echo-hash "$PNU" w_echo r_wa
mutate wa-case 's/gate_web_acceptance "\$rest" ;; # mut:wa-case/: ;; # mut:wa-case/' && killed wa-case "$P_OK" w_ok r_wa
mutate body-keys "$(noop body-keys)" && killed body-keys "$PNU" w_renamed r_wa
mutate wa-blob "$(noop wa-blob)" && killed wa-blob "$PNOTIN" w_link r_wa
mutate wa-cr "$(noop wa-cr)" && killed wa-cr "$PCANT" w_cr r_wa
# 6 a malformed gate is refused before any request (every spelling, against the neutered check and each narrowed regex)
mutate wa-shape 's/if \[\[ "\$rest" != \*" "\* \]\] \|\| ! \[\[ "\$key" =~ \$WA_KEY_RE \]\] \|\| ! \[\[ "\$hash" =~ \$WA_HASH_RE \]\]; then/if false; then/' && {
  for BADGATE in "up/key $WA_H" "dot.key $WA_H" "$K64 $WA_H" "wa-key $(printf '%s' "$WA_H" | tr 'a-f' 'A-F')" "wa-key" "wa-key $WA_H extra" "wa-key $WA_H"$'\t'"AND pr-merged 999999" "wa"$'\xc2\xa0'"-key $WA_H" "-wa-key $WA_H"; do
    killed wa-shape "$PSHAPE" w_badgate r_wa
  done; }
mutate wa-key-len 's/(WA_KEY_RE=.*)\{0,62\}/\1{0,63}/' && { BADGATE="$K64 $WA_H"; killed wa-key-len "$PSHAPE" w_badgate r_wa; }
mutate wa-hash-case 's/(WA_HASH_RE=[^\[]*\[0-9a)-f\]/\1-fA-F]/' && { BADGATE="wa-key $(printf '%s' "$WA_H" | tr 'a-f' 'A-F')"; killed wa-hash-case "$PSHAPE" w_badgate r_wa; }
mutate wa-key-lead 's/(WA_KEY_RE=[^\[]*\[)a-z0-9\]/\1a-z0-9-]/' && { BADGATE="-wa-key $WA_H"; killed wa-key-lead "$PSHAPE" w_badgate r_wa; }
# 7 no redirect, no environment base URL
mutate_lib redirs 's/ --max-redirs 0//' && killed redirs "$P_OK" w_ok r_wa
mutate base-url 's|^WA_BASE=.https://app.soleur.ai[^ ]*. # mut:base-url$|WA_BASE="${HGE_WA_BASE:-https://app.soleur.ai/api/internal/legal-acceptance}" # mut:base-url|' && killed base-url "$P_OK" w_ok r_envbase
# 8 no delegation: web-acceptance-only is evaluated (never exit 3); mixed with another kind is exit 2, never 0 or 1
mutate wa-eval 's/NODELEG=1 # mut:wa-eval/NODELEG=0 # mut:wa-eval/' && killed wa-eval "$P_OK" w_ok r_wa
mutate wa-mixed "$(noop wa-mixed)" && { killed wa-mixed "2|holds: 2 discharged: 0 standing: 2" w_mixed r_plan; killed wa-mixed "2|holds: 2 discharged: 0 standing: 2" w_mixed_open r_plan; }
# 9 the converse: reserved-only and gate-less no-delegation plans keep exit 3
mutate wa-none 's/\[ "\$wa" -gt 0 \] \|\| return 0 # mut:wa-none/[ "$wa" -ge 0 ] || return 0 # mut:wa-none/' && killed wa-none "3|holds: 1 discharged: 0 standing: 1" w_gateless r_plan
mutate wa-reserved-skip "$(noop wa-reserved-skip)" && killed wa-reserved-skip "3|holds: 1 discharged: 0 standing: 1" w_resonly r_plan
mutate wa-gateless "$(noop wa-gateless)" && killed wa-gateless "2|holds: 2 discharged: 0 standing: 2" w_wa_gateless r_plan
# 10 row_ok is checked with an explicit type predicate, never `//` or truthiness
mutate row-ok-coalesce 's|\.row_ok == true and|(.row_ok // true) == true and|' && killed row-ok-coalesce "$PNU" w_rowfalse r_wa
mutate row-ok-truthy 's,\(\.row_ok \| type\) == "boolean" and \.row_ok == true and,.row_ok and,' && { killed row-ok-truthy "$PNU" w_rowstr r_wa; killed row-ok-truthy "$PNU" w_rowone r_wa; }
# 11 the bearer reaches curl through a 0600 config only: not on argv, not in a world-readable file
mutate_lib argv-token 's/--config "\$cfg"/-H "Authorization: Bearer $BC_TOKEN"/' && killed argv-token "$P_OK" w_ok r_wa
mutate_lib cfg-mode 's/umask 077/umask 022/' && killed cfg-mode "$P_OK" w_ok r_wa
# the hold names its text (D1), a tab cannot split a gate (E3), valid_until (D6), the answer parser (F5)
mutate wa-bind "$(noop wa-bind)" && { killed wa-bind "$PBIND" w_payments r_wa; }
mutate wa-bind-edge '/mut:wa-bind$/ s/\[\^a-z0-9_-\]/[^a-z0-9_]/g' && killed wa-bind-edge "$PBIND" w_bindlong r_wa
mutate wa-bind-underscore '/mut:wa-bind$/ s/\[\^a-z0-9_-\]/[^a-z0-9-]/g' && killed wa-bind-underscore "$PBIND" w_bindus r_wa
mutate wa-bind-raw '/mut:wa-bind$/ s/clean_uncut "\$WA_HOLD_TEXT"/printf "%s" "$WA_HOLD_TEXT"/' && killed wa-bind-raw "$P_OK" w_bindc1 r_wa
mutate wa-bind-cut '/mut:wa-bind$/ s/clean_uncut "\$WA_HOLD_TEXT"/clean_text "$WA_HOLD_TEXT"/' && killed wa-bind-cut "$P_OK" w_bind200 r_wa
mutate wa-bind-accum 's/^  WA_HOLD_TEXT="\$text"$/  WA_HOLD_TEXT="$WA_HOLD_TEXT $text"/' && killed wa-bind-accum "2|holds: 2 discharged: 1 standing: 1" w_bind2 r_plan
mutate hline-any "$(noop hline-any)" && killed hline-any "1|holds: x 1 discharged: 0 standing: 1 needs=1" w_chg1 r_wa_needs
mutate wa-err-shape 's/^      shape\) GWHY=/      nomatch) GWHY=/' && killed wa-err-shape "2|holds: x 1 discharged: 0 standing: 1 why=the saved sign-in value looks wrong (too short or odd characters)" w_shapetok r_wa
mutate_lib err-shape "$(noop err-shape)" && killed err-shape "2|holds: x 1 discharged: 0 standing: 1 why=the saved sign-in value looks wrong (too short or odd characters)" w_shapetok r_wa
mutate wa-valid-day "$(noop wa-valid-day)" && { killed wa-valid-day "$PCANT" w_badvu3 r_wa; killed wa-valid-day "$PCANT" w_badvu4 r_wa; killed wa-valid-day "$PCANT" w_badvu5 r_wa; }
mutate wa-valid-last 's/got = 1; last = v/last = (got ? last : v); got = 1/' && { killed wa-valid-last "0|holds: x 1 discharged: 1 standing: 0 why=checked: web-acceptance wa-dup $(blobhash wa-dup) (decided DATE)" w_dup r_wa; killed wa-valid-last "1|holds: x 1 discharged: 0 standing: 1 why=only a person can settle this (the accepted text has passed its last valid day; a revised text is needed)" w_dup2 r_wa; }
mutate wa-valid-fm 's/NR == 1 \{ if \(\$0 == "---"\) \{ f = 1; next \} else exit \} f && \$0 == "---" \{ exit \} f && //' && killed wa-valid-fm "0|holds: x 1 discharged: 1 standing: 0 why=checked: web-acceptance wa-bodyvu $(blobhash wa-bodyvu) (decided DATE)" w_bodyvu r_wa
if day_stable; then mutate wa-today-utc 's/date -u \+%F/date +%F/' && killed wa-today-utc "0|holds: x rcs=0 1" w_tz r_tz; else day_skip wa-today-utc; fi
mutate wa-kind "$(noop wa-kind)" && killed wa-kind "2|holds: x 1 discharged: 0 standing: 1 why=$NTWHY" w_ntkey r_wa
mutate wa-kind-substr '/# mut:wa-kind$/ s/ \$key / *\$key* /' && killed wa-kind-substr "2|holds: x 1 discharged: 0 standing: 1 why=$NTWHY" w_ntkey r_wa
mutate wa-kind-lead '/# mut:wa-kind$/ s/\*" \$key "\*/*"\$key "*/' && killed wa-kind-lead "0|holds: x 1 discharged: 1 standing: 0 why=checked: web-acceptance acceptance-record $(blobhash acceptance-record) (decided DATE)" w_ntsuf r_wa
mutate wa-kind-trail '/# mut:wa-kind$/ s/\*" \$key "\*/*" \$key"*/' && killed wa-kind-trail "0|holds: x 1 discharged: 1 standing: 0 why=checked: web-acceptance founder-acceptance $(blobhash founder-acceptance) (decided DATE)" w_ntpre r_wa
# the refusal list is a VARIABLE the case consumes: widen it by one key and an ordinary key must be refused (a literal pasted into the case would not notice)
mutate wa-kind-var "s/^WA_NON_TERMS_KEYS=.*/WA_NON_TERMS_KEYS='founder-acceptance-record wa-key'/" && killed wa-kind-var "0|holds: x 1 discharged: 1 standing: 0 why=checked: web-acceptance wa-key $(blobhash wa-key) (decided DATE)" w_ntord r_wa
mutate wa-bind-case '/# mut:wa-bind$/ s/ \| tr .A-Z. .a-z.//' && killed wa-bind-case "$P_OK" w_bindcase r_wa
mutate wa-file "$(noop wa-file)" && killed wa-file "2|holds: x 1 discharged: 0 standing: 1 why=a recorded decision on a legal text cannot back a production step" s_filepath r_wafile
mutate tab-val 's~gsub\(/\\t/, " ", s\); ~~' && killed tab-val "$PSHAPE" w_tab r_wa
mutate wa-expired "$(noop wa-expired)" && killed wa-expired "1|holds: x 1 discharged: 0 standing: 1 why=only a person can settle this (the accepted text has passed its last valid day; a revised text is needed)" w_expired r_wa
mutate wa-valid-shape "$(noop wa-valid-shape)" && { killed wa-valid-shape "$PCANT" w_badvu6 r_wa; }
mutate st-allow 's~\.status as \$s [^'"'"']*~.status | if type == "string" then . else "-" end~' && { killed st-allow "$PNU" w_statusnl r_wa; killed st-allow "$PNU" w_statusnul r_wa; }
mutate body-dupkeys "$(noop body-dupkeys)" && { killed body-dupkeys "$PNU" w_dupstatus r_wa; killed body-dupkeys "$PNU" w_duprowok r_wa; killed body-dupkeys "$PNU" w_duprowok2 r_wa; }
mutate ts-wired 's~\(\.decided_at \| okts\)~(.decided_at | type) == "string"~' && { DATEPROBE=2026-13-99T99:99:99Z; killed ts-wired "$PNU" w_date r_wa; }
mutate ts-end 's~\\\\z~$~' && killed ts-end "$PNU" w_datenl r_wa
mutate ts-year 's~\.y >= "2000" and \.y <= "2099" and ~~' && { DATEPROBE=1999-12-31T23:59:59Z; killed ts-year "$PNU" w_date r_wa; DATEPROBE=9999-12-31T23:59:59Z; killed ts-year "$PNU" w_date r_wa; }
mutate ts-calendar 's~catch ""\) == \$t~catch "") == $t or true~;s~ and \.mo >= "01" and \.mo <= "12" and \.d >= "01" and \.d <= "31" and \.h <= "23" and \.mi <= "59" and \.s <= "59"~~' && { DATEPROBE=2026-02-30T10:00:00Z; killed ts-calendar "$PNU" w_date r_wa; DATEPROBE=2026-13-99T99:99:99Z; killed ts-calendar "$PNU" w_date r_wa; DATEPROBE=2026-11-05T24:00:00Z; killed ts-calendar "$PNU" w_date r_wa; }
mutate ts-roundtrip 's~catch ""\) == \$t~catch "") == $t or true~' && { DATEPROBE=2026-02-30T10:00:00Z; killed ts-roundtrip "$PNU" w_date r_wa; }
# stdin hygiene of the new calls
mutate_lib stdin-curl 's# 2>/dev/null </dev/null\)"; BC_RC=# 2>/dev/null)"; BC_RC=#' && killed stdin-curl "0|holds: x 2 discharged: 2 standing: 0 stdin-calls=0" w_two r_wa_in
mutate_lib stdin-doppler 's# 2>/dev/null </dev/null\)" \|\| return 1# 2>/dev/null)" || return 1#' && killed stdin-doppler "0|holds: x 2 discharged: 2 standing: 0 stdin-calls=0" w_two r_wa_in

echo "=== Floor: the SUT answered every row ==="
n_calls="$(cat "$TMP"/scn*/calls.log 2>/dev/null | wc -l | tr -d ' ')"
# Floors, committed from a green run (2051 assertions after fix round 1; 2028 after review round 1; 2009 before, 1000 gh stub calls, per-arm counts below) within 0.5%: a FLOOR, never equality. Re-measure and raise them when rows are added; a lower number is a deleted row.
if (( n_calls >= 995 )); then
  echo "  PASS: gh stub calls $n_calls >= 995"; PASS=$((PASS + 1))
else
  echo "  FAIL: gh stub calls $n_calls < 995 -- the rows did not drive the script"; FAIL=$((FAIL + 1))
fi

for armrow in "wa:1270:the whole of Arm 14" "nser:405:answers that cannot be understood, escapes, repeats and dates" "bind:145:the hold must name its text" "tab:11:a tab cannot split a gate" "vu:40:valid_until" "bind2:13:what the binding reads" "chg:26:who reads the note" "vu2:51:valid_until, the day before, zones, calendar" "nt:30:an acknowledgement key cannot back a production step"; do
  arm_floor "${armrow%%:*}" "$(printf '%s' "$armrow" | cut -d: -f2)" "${armrow#*:*:}"
done

print_results 2045
