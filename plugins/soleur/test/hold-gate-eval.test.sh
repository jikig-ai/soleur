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
# GRAMMAR UNDER TEST (CTO ruling R1): `pr-merged <N>` and `no-inflight-run <workflow-file>` only. `command` and
# `run-green` are deferred; their lines are an unknown kind, which exits 2 and leaves the hold standing.
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
[[ -s "$FXH/plan-three-holds.md" ]] || { echo "FATAL: fixture missing: $FXH/plan-three-holds.md" >&2; exit 2; }

addd() { jq -rn --arg d "$1" --argjson n "$2" '($d + "T00:00:00Z" | fromdateiso8601) + ($n * 86400) | strftime("%Y-%m-%d")'; }
TODAY="$(date -u +%Y-%m-%d)"; NOW_ISO="${TODAY}T00:00:00Z"; EXP10="$(addd "$TODAY" 10)"

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
  git -C "$W" add -A && git -C "$W" commit -q -m "base" && git -C "$W" push -q origin main
  git -C "$W" rev-parse HEAD > "$TMP/sha-merged"
  git -C "$W" checkout -q -b side && printf 'x\n' > "$W/side.txt" && git -C "$W" add side.txt && git -C "$W" commit -q -m "side"
  git -C "$W" rev-parse HEAD > "$TMP/sha-side"
  git -C "$W" checkout -q main
  printf 'y\n' > "$W/second.txt"; git -C "$W" add second.txt; git -C "$W" commit -q -m "second"; git -C "$W" push -q origin main
  printf 'z\n' > "$W/local.txt"; git -C "$W" add local.txt; git -C "$W" commit -q -m "local only"
  git -C "$W" fetch -q origin main
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
( cd "$W7" && git remote add origin "$O" && git fetch -q origin && git remote set-head origin -a ) >/dev/null 2>&1

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
assert_eq "1" "$(grep -c 'runbook' "$TMP/o")" "XE1e: the stall names the missing runbook in plain words"
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
  local d="$1" t o p; shift; rm -rf "$d"; mkdir -p "$d"
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
  grep -v '^\(holds\|delegation\): ' "$1" | grep -i -E -c '(^|[^a-z])(patch-id|rebase|merge-base|stdout|diff|commit|draft|pull request|branch|unarmed)([^a-z]|$)' || true
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
printf 'holds: 3 discharged: 0 standing: 3\ndelegation: invalid reason=rebase\n' > "$TMP/jargon-control-m.txt"
assert_eq "0" "$(( $(jargon_hits "$TMP/jargon-control-m.txt") + $(jargon_hits_ci "$TMP/jargon-control-m.txt") ))" "instrument: the machine lines are excluded from the jargon check"

echo "=== Arm 11b: control characters and bidi marks in a hold's words do not reach the output ==="
scn; mkdir -p "$TMP/plans"
{ printf '# Plan\n\n## Operator Holds\n\nDelegation: %s\nEnvelope: env-valid.md\n\n' "$URL"; printf -- '- Hold: do not ship \033[31mred\007 text \342\200\256evil\342\200\250 here\n  Gate: no-inflight-run example-release.yml\n' ; } > "$TMP/plans/ctl.md"
run_h --plan "$TMP/plans/ctl.md"
expect "HX6: a hold with control characters still evaluates" 0 "holds: 1 discharged: 1 standing: 0"
assert_eq "0" "$(LC_ALL=C grep -c "$(printf '\033')" "$TMP/o")" "HX6b: no escape character reaches the output"
assert_eq "0" "$(LC_ALL=C grep -c "$(printf '\007')" "$TMP/o")" "HX6c: no bell character reaches the output"
assert_eq "0" "$(LC_ALL=C grep -c "$(printf '\342\200\256')" "$TMP/o")" "HX6d: no bidi override reaches the output"
assert_eq "0" "$(LC_ALL=C grep -c "$(printf '\342\200\250')" "$TMP/o")" "HX6e: no line-separator mark reaches the output"

echo "=== Arm 12: every gh call was a read ==="
bad=0
for f in "$TMP"/scn*/calls.log; do
  [[ -f "$f" ]] || continue
  n="$(grep -vcE '^(api repos/[A-Za-z0-9_./-]+|repo view --json nameWithOwner --jq \.nameWithOwner|pr view [0-9]+ --json state,mergeCommit,baseRefName|run list --workflow [A-Za-z0-9._-]+ --limit 100 --json status)$' "$f")"
  bad=$((bad + n))
done
assert_eq "0" "$bad" "no gh call outside the read-only shapes across all scenarios"
assert_eq "0" "$(cat "$TMP"/scn*/calls.log | grep -cE ' (-X|--method|-f|-F|--field|--input) |^(issue|pr) (comment|edit|close|merge)|^workflow run')" "no write verb reached gh"

echo "=== Arm 13: mutations (the pristine control first) ==="
MUT="$TMP/mut"; mkdir -p "$MUT"; PRISTINE_DIR="$TMP/pristine/skills/ship/scripts"; mkdir -p "$PRISTINE_DIR"
# The evaluator resolves the verifier relative to itself, so mutants live in a tree that mirrors the plugin layout.
mkdir -p "$TMP/pristine/scripts"; cp "$REPO_ROOT/plugins/soleur/scripts/delegation-verify.sh" "$TMP/pristine/scripts/"
PRISTINE="$PRISTINE_DIR/hold-gate-eval.sh"; cp "$SUT_REAL" "$PRISTINE"
cp "$TMP/pristine/scripts/delegation-verify.sh" "$TMP/real-verifier.sh"
mutate() { # <name> <sed -E expr>: write a mutant inside a mirrored tree and prove the mutation LANDED
  local d="$TMP/mutants/$1"; mkdir -p "$d/skills/ship/scripts" "$d/scripts"
  cp "$REPO_ROOT/plugins/soleur/scripts/delegation-verify.sh" "$d/scripts/"
  sed -E "$2" "$PRISTINE" > "$d/skills/ship/scripts/hold-gate-eval.sh"
  if cmp -s "$PRISTINE" "$d/skills/ship/scripts/hold-gate-eval.sh"; then echo "  FAIL: mutation $1 did not land"; FAIL=$((FAIL + 1)); return 1; fi
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
s_ctl() { mkholds mctl "$(printf -- '- Hold: do not ship \033[31mred\007 text\n  Gate: no-inflight-run example-release.yml')"; }
r_ctl() { run_h --plan "$PLAN"; echo "holds: x esc=$(grep -c "$(printf '\033')" "$TMP/o")" >> "$TMP/o"; }
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
  || { printf 'FATAL: killed cannot report a survivor\n' >&2; exit 2; }
( b=$FAIL; mutate ctrl 's/zz-no-such-text-zz/y/' >/dev/null; [[ $FAIL -gt $b ]] ) \
  || { printf 'FATAL: mutate cannot report a mutation that did not land\n' >&2; exit 2; }
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
mutate file-title "$(noop file-title)" && killed file-title "0|holds: 1 discharged: 1 standing: 0" s_filepath r_file_title

echo "=== Floor: the SUT answered every row ==="
n_calls="$(cat "$TMP"/scn*/calls.log 2>/dev/null | wc -l | tr -d ' ')"
# Zero-slack floors, committed from a green run: re-measure and raise them when rows are added; a lower number is a deleted row.
if (( n_calls >= 911 )); then echo "  PASS: gh stub calls $n_calls >= 911"; PASS=$((PASS + 1))
else echo "  FAIL: gh stub calls $n_calls < 911 -- the rows did not drive the script"; FAIL=$((FAIL + 1)); fi

print_results 537
