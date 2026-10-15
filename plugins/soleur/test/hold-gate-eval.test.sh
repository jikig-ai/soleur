#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2329  # A && B || C is the assertion idiom; sed/jq programs are single-quoted on purpose; setup functions are dispatched indirectly
# Suite for plugins/soleur/skills/ship/scripts/hold-gate-eval.sh -- Guard 4 of the plan's Guard Contract.
#
# THE SEAM: `gh` is a PATH stub answering only the exact argv shapes the SUT is expected to use (delegation
# reads, `pr view`, `run list`), refusing every other argv with exit 64 after logging STUB-MISS. `git` is real,
# against local bare "origin" repositories and clones, so byte-identity with origin/main is measured, not stubbed.
# Fixtures are synthesized (cq-test-fixtures-synthesized-only) under test/fixtures/standing-delegation/.
#
# ARMS: control, gate kinds, parse shapes, sections, delegation, restrictions on the `command` kind, stale
# origin, envelope mode, jargon over the human lines, zero-write audit of the stub log, mutations
# (`# mut:<name>` markers in the script), floor.

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

( assert_eq a b "control" >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: assert_eq cannot fail -- dispatch is neutered\n' >&2; exit 2; }

[[ -f "$SUT_REAL" ]] || { echo "  FAIL: evaluator missing: $SUT_REAL"; FAIL=$((FAIL + 1)); print_results 1; exit 1; }
command -v jq >/dev/null || { echo "FATAL: jq required" >&2; exit 2; }
for f in delegation-valid.md envelope-valid.md envelope-two-sections.md holds-mixed.md holds-prose.md holds-none.md; do
  [[ -s "$FX/$f" ]] || { echo "FATAL: fixture missing: $FX/$f" >&2; exit 2; }
done

addd() { jq -rn --arg d "$1" --argjson n "$2" '($d + "T00:00:00Z" | fromdateiso8601) + ($n * 86400) | strftime("%Y-%m-%d")'; }
TODAY="$(date -u +%Y-%m-%d)"; NOW_ISO="${TODAY}T00:00:00Z"; EXP10="$(addd "$TODAY" 10)"

# --- the gh stub ----------------------------------------------------------------------------------
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
d="${STUB_DIR:?}"
echo "$*" >> "$d/calls.log"
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
  if [ "$#" -eq 10 ] && [ "$3" = "--workflow" ] && [ "$5" = "--status" ] && [ "$7" = "--limit" ] && [ "$8" = "5" ] && [ "$9" = "--json" ] && [ "${10}" = "databaseId" ]; then
    fail_mode mode-run; f="$d/runs-$4-$6.json"; if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi; exit 0
  fi
  if [ "$#" -eq 10 ] && [ "$3" = "--workflow" ] && [ "$5" = "--commit" ] && [ "$7" = "--limit" ] && [ "$8" = "5" ] && [ "$9" = "--json" ] && [ "${10}" = "status,conclusion" ]; then
    fail_mode mode-run; f="$d/green-$4-$6.json"; if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi; exit 0
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

# --- the repositories ------------------------------------------------------------------------------
# W: main clone (pushed history A, B, C; then local-only D, E; a dirty file; an untracked file)
# W4: an independent clone whose origin/main is made STALE after a second clone pushes a change to origin2
URL="https://github.com/example-org/example-repo/issues/77#issuecomment-1001"
O="$TMP/origin.git"; W="$TMP/work"; O2="$TMP/origin2.git"; W4="$TMP/work4"; W5="$TMP/work5"
(
  git_fixture_env "$O" || exit 1
  git init -q --bare "$O" && git -C "$O" symbolic-ref HEAD refs/heads/main
  git clone -q "$O" "$W" 2>/dev/null
  git -C "$W" checkout -q -b main
  mkdir -p "$W/scripts"
  printf '#!/usr/bin/env bash\necho READY\n' > "$W/scripts/probe-ok.sh"
  printf '#!/usr/bin/env bash\necho NOTREADY\n' > "$W/scripts/probe-bad.sh"
  printf '#!/usr/bin/env bash\nssh example.invalid true\necho READY\n' > "$W/scripts/probe-ssh.sh"
  printf '#!/usr/bin/env bash\n. ./scripts/lib.sh\necho READY\n' > "$W/scripts/probe-source.sh"
  printf '#!/usr/bin/env bash\nexit 3\n' > "$W/scripts/probe-fail.sh"
  printf '#!/usr/bin/env bash\necho "a => b"\n' > "$W/scripts/probe-arrow.sh"
  printf '#!/usr/bin/env bash\necho "$1"\n' > "$W/scripts/probe-echo.sh"
  ln -s /bin/true "$W/scripts/probe-link.sh"
  sed -e "s|@URL@|$URL|g" "$FX/envelope-valid.md" > "$W/env-valid.md"
  sed -e "s|@URL@|$URL|g" "$FX/envelope-two-sections.md" > "$W/env-two.md"
  git -C "$W" add -A && git -C "$W" commit -q -m "base" && git -C "$W" push -q origin main
  git -C "$W" rev-parse HEAD > "$TMP/sha-merged"
  git -C "$W" checkout -q -b side && printf 'x\n' > "$W/side.txt" && git -C "$W" add side.txt && git -C "$W" commit -q -m "side"
  git -C "$W" rev-parse HEAD > "$TMP/sha-side"
  git -C "$W" checkout -q main
  cp "$W/scripts/probe-ok.sh" "$W/scripts/probe-edited.sh"; cp "$W/scripts/probe-ok.sh" "$W/scripts/probe-restored.sh"; git -C "$W" add scripts/probe-edited.sh scripts/probe-restored.sh; git -C "$W" commit -q -m "edited base"
  printf '#!/usr/bin/env bash\necho EDITED2\n' > "$W/scripts/probe-dirty.sh"; git -C "$W" add scripts/probe-dirty.sh; git -C "$W" commit -q -m "dirty base"
  git -C "$W" push -q origin main
  printf '#!/usr/bin/env bash\necho EDITED\n' > "$W/scripts/probe-edited.sh"; printf '#!/usr/bin/env bash\necho LOCAL\n' > "$W/scripts/probe-restored.sh"; git -C "$W" commit -q -am "edited locally"
  printf '#!/usr/bin/env bash\necho READY\n' > "$W/scripts/probe-unpushed.sh"; git -C "$W" add scripts/probe-unpushed.sh; git -C "$W" commit -q -m "unpushed probe"
  git -C "$W" fetch -q origin main
) >/dev/null 2>&1 || { echo "FATAL: fixture repositories not built" >&2; exit 2; }
printf '#!/usr/bin/env bash\necho READY\n' > "$W/scripts/probe-untracked.sh"
printf '#!/usr/bin/env bash\necho EDITED3\n' > "$W/scripts/probe-dirty.sh"
( git_fixture_env "$W" && git -C "$W" show origin/main:scripts/probe-restored.sh > "$W/scripts/probe-restored.sh" )   # bytes equal origin/main, but HEAD holds another version
SHA_MERGED="$(cat "$TMP/sha-merged")"; SHA_SIDE="$(cat "$TMP/sha-side")"
[[ -n "$SHA_MERGED" && -n "$SHA_SIDE" ]] || { echo "FATAL: fixture shas not resolved" >&2; exit 2; }
(
  git_fixture_env "$O2" || exit 1
  git init -q --bare "$O2" && git -C "$O2" symbolic-ref HEAD refs/heads/main
  git clone -q "$O2" "$W4" 2>/dev/null; git -C "$W4" checkout -q -b main; mkdir -p "$W4/scripts"
  printf '#!/usr/bin/env bash\necho READY\n' > "$W4/scripts/probe-ok.sh"
  sed -e "s|@URL@|$URL|g" "$FX/envelope-valid.md" > "$W4/env-valid.md"
  git -C "$W4" add -A && git -C "$W4" commit -q -m base && git -C "$W4" push -q origin main
  git -C "$W4" rev-parse origin/main > "$TMP/old4"
  git clone -q "$O2" "$W5" 2>/dev/null; git -C "$W5" checkout -q main 2>/dev/null
  printf '#!/usr/bin/env bash\necho MOVED\n' > "$W5/scripts/probe-ok.sh"; git -C "$W5" commit -q -am "origin moves"; git -C "$W5" push -q origin main
) >/dev/null 2>&1 || { echo "FATAL: stale-origin fixture not built" >&2; exit 2; }
OLD4="$(cat "$TMP/old4")"
stale4() { ( git_fixture_env "$W4" && git -C "$W4" update-ref refs/remotes/origin/main "$OLD4" ) >/dev/null 2>&1; }

# --- scenario builders ------------------------------------------------------------------------------
SC=0
mk_comment() { # <id> <bodyfile>
  jq -n --rawfile body "$2" --arg c "$NOW_ISO" --arg iu "https://api.github.com/repos/example-org/example-repo/issues/77" --argjson id "$1" \
    '{id:$id, body:$body, user:{login:"owner-user", type:"User"}, author_association:"MEMBER", created_at:$c, updated_at:$c, issue_url:$iu}' > "$STUB_DIR/comment-$1.json"
}
scn() {
  SC=$((SC + 1)); STUB_DIR="$TMP/scn$SC"; rm -rf "$STUB_DIR"; mkdir -p "$STUB_DIR"; export STUB_DIR
  echo "example-org/example-repo" > "$STUB_DIR/repo.txt"
  sed -e "s/@EXPIRY@/$EXP10/" -e "s/@DATE@/$TODAY/" "$FX/delegation-valid.md" > "$STUB_DIR/body.md"
  mk_comment 1001 "$STUB_DIR/body.md"
  echo '{"permission":"admin"}' > "$STUB_DIR/perm-owner-user.json"
  echo '{"number":77,"state":"open"}' > "$STUB_DIR/issue-77.json"
  jq -n --arg s "$SHA_MERGED" '{state:"MERGED", mergeCommit:{oid:$s}, baseRefName:"main"}' > "$STUB_DIR/pr-55.json"
  jq -n --arg s "$SHA_MERGED" '{state:"MERGED", mergeCommit:{oid:$s}, baseRefName:"main"}' > "$STUB_DIR/pr-120.json"
}
mkplan() { # <name> [sed -E expr]: a plan in $TMP/plans/<name>.md derived from holds-mixed.md
  mkdir -p "$TMP/plans"
  sed -E -e "s|@URL@|$URL|g" -e "${2:-s/zzz-never-zzz/x/}" "$FX/holds-mixed.md" > "$TMP/plans/$1.md"
  PLAN="$TMP/plans/$1.md"
}
run_h() { # <args...> ; runs in the main clone
  ( cd "$W" && git_fixture_env "$W" && PATH="$BIN:$PATH" bash "$SUT" "$@" ) >"$TMP/o" 2>"$TMP/e"
  rc=$?; echo "$rc" > "$TMP/rc"
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

echo "=== Control: three holds, one verified delegation, every gate true ==="
scn; mkplan mixed; run_h --plan "$PLAN"
expect "all discharged" 0 "holds: 3 discharged: 3 standing: 0"
assert_eq "3" "$(grep -c '^Done: ' "$TMP/o")" "each discharged hold prints a Done line"
for s in queued in_progress waiting; do
  assert_eq "1" "$(grep -c "^run list --workflow example-release.yml --status $s --limit 5 --json databaseId$" "$STUB_DIR/calls.log")" "no-inflight-run asked for the $s list separately"
done

echo "=== Arm 1: pr-merged ==="
scn; echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-55.json"; mkplan mixed; run_h --plan "$PLAN"
expect "open change stands" 1 "holds: 3 discharged: 2 standing: 1"
scn; jq -n --arg s "$SHA_SIDE" '{state:"MERGED", mergeCommit:{oid:$s}, baseRefName:"main"}' > "$STUB_DIR/pr-55.json"; mkplan mixed; run_h --plan "$PLAN"
expect "merged but not contained in HEAD stands" 1 "holds: 3 discharged: 2 standing: 1"
scn; jq -n --arg s "$SHA_MERGED" '{state:"MERGED", mergeCommit:{oid:$s}, baseRefName:"release"}' > "$STUB_DIR/pr-55.json"; mkplan mixed; run_h --plan "$PLAN"
expect "merged into another base stands" 1 "holds: 3 discharged: 2 standing: 1"
scn; echo net > "$STUB_DIR/mode-pr"; mkplan mixed; run_h --plan "$PLAN"
expect "unreadable probe is exit 2" 2 "holds: 3 discharged: 2 standing: 1"
scn; mkplan mixed 's/pr-merged 55/pr-merged 55x/'; run_h --plan "$PLAN"
expect "malformed number is not evaluated (exit 2)" 2 "holds: 3 discharged: 2 standing: 1"

echo "=== Arm 2: no-inflight-run (all three lists must be empty) ==="
for s in queued in_progress waiting; do
  scn; echo '[{"databaseId":1}]' > "$STUB_DIR/runs-example-release.yml-$s.json"; mkplan mixed; run_h --plan "$PLAN"
  expect "a $s run keeps the hold" 1 "holds: 3 discharged: 2 standing: 1"
done
scn; echo net > "$STUB_DIR/mode-run"; mkplan mixed; run_h --plan "$PLAN"
expect "a failed run list is exit 2" 2 "holds: 3 discharged: 2 standing: 1"
scn; echo '{"not":"an array"}' > "$STUB_DIR/runs-example-release.yml-queued.json"; mkplan mixed; run_h --plan "$PLAN"
expect "a non-array answer is exit 2" 2 "holds: 3 discharged: 2 standing: 1"
echo "=== Arm 2b: the re-check right before arming sees a new run ==="
scn; mkplan mixed; run_h --plan "$PLAN"; assert_eq "0" "$(last_rc)" "first look at the draft exit: clear"
echo '[{"databaseId":9}]' > "$STUB_DIR/runs-example-release.yml-in_progress.json"; run_h --plan "$PLAN"
assert_eq "1" "$(last_rc)" "second look immediately before arming: a run started in between, the hold stands again"

echo "=== Arm 3: run-green ==="
scn; mkplan green 's|  Gate: no-inflight-run example-release.yml|  Gate: run-green example-release.yml abc1234|'
echo '[{"status":"completed","conclusion":"success"}]' > "$STUB_DIR/green-example-release.yml-abc1234.json"; run_h --plan "$PLAN"
expect "latest run for the sha is green" 0 "holds: 3 discharged: 3 standing: 0"
echo '[{"status":"completed","conclusion":"failure"}]' > "$STUB_DIR/green-example-release.yml-abc1234.json"; run_h --plan "$PLAN"
expect "latest run failed" 1 "holds: 3 discharged: 2 standing: 1"
echo '[]' > "$STUB_DIR/green-example-release.yml-abc1234.json"; run_h --plan "$PLAN"
expect "no run for the sha yet" 1 "holds: 3 discharged: 2 standing: 1"
echo '[{"status":"in_progress","conclusion":null}]' > "$STUB_DIR/green-example-release.yml-abc1234.json"; run_h --plan "$PLAN"
expect "run still going" 1 "holds: 3 discharged: 2 standing: 1"

echo "=== Arm 4: unknown kind, no gate, partial gates, parse shapes ==="
s_unknown() { mkplan unk 's/  Gate: pr-merged 55/  Gate: frobnicate 55/'; }
scn; s_unknown; run_h --plan "$PLAN"
expect "unknown kind never discharges (exit 2)" 2 "holds: 3 discharged: 2 standing: 1"
s_nogate() { mkplan nogate '/  Gate: pr-merged 55/d'; }
scn; s_nogate; run_h --plan "$PLAN"
expect "a hold with no Gate line needs a person" 1 "holds: 3 discharged: 2 standing: 1"
assert_eq "1" "$(grep -c '^Needs a person: ' "$TMP/o")" "the needs-a-person line is printed"
s_twogates() { echo '{"state":"OPEN","mergeCommit":null,"baseRefName":"main"}' > "$STUB_DIR/pr-9999.json"; mkplan twogates 's/^  Gate: no-inflight-run example-release.yml$/  Gate: no-inflight-run example-release.yml\n  Gate: pr-merged 9999/'; }
scn; s_twogates; run_h --plan "$PLAN"
expect "two gates, first true, second false: the hold stands" 1 "holds: 3 discharged: 2 standing: 1"
scn; mkplan orphan 's/^- Hold: do not ship until/  Gate: pr-merged 55\n- Hold: do not ship until/'; run_h --plan "$PLAN"
assert_eq "2" "$(last_rc)" "a Gate line before any Hold is exit 2"
scn; mkplan crlf 's/$/\r/'; run_h --plan "$PLAN"
expect "a CRLF plan still evaluates" 0 "holds: 3 discharged: 3 standing: 0"
scn
cat > "$TMP/plans/reordered.md" <<EOF
# Plan (synthesized, different order and count)

## Operator Holds

- Hold: wait until the live check reads ready.
  Gate: command scripts/probe-ok.sh => READY
- Hold: do not ship while a release is running.
  Gate: no-inflight-run example-release.yml
Delegation: $URL

## Next
EOF
run_h --plan "$TMP/plans/reordered.md"
expect "H2: two holds in a different order, Delegation line after the holds" 0 "holds: 2 discharged: 2 standing: 0"

echo "=== Arm 5: sections ==="
scn; run_h --plan "$FX/holds-none.md"
expect "no Operator Holds section is a no-op" 0 "holds: 0 discharged: 0 standing: 0"
scn; printf '# Plan\n\n## Operator Holds\n\n## Next\n' > "$TMP/plans/empty.md"; run_h --plan "$TMP/plans/empty.md"
expect "an empty section is a no-op" 0 "holds: 0 discharged: 0 standing: 0"
s_prose() { :; }
scn; run_h --plan "$FX/holds-prose.md"
assert_eq "2" "$(last_rc)" "a non-blank section with zero parsed holds is exit 2"
assert_eq "0" "$(grep -c '^holds: 0 discharged: 0' "$TMP/o")" "it does not print the all-clear line"

echo "=== Arm 6: delegation ==="
s_nodeleg() { mkplan nodeleg '/^Delegation: /d'; }
scn; s_nodeleg; run_h --plan "$PLAN"
assert_eq "3" "$(last_rc)" "no delegation recorded is exit 3 (the caller keeps its prose evaluation)"
assert_eq "0" "$(cat "$STUB_DIR/calls.log" 2>/dev/null | grep -c 'run list\|pr view')" "nothing was probed when no delegation is recorded"
s_edited() { jq --arg u "${TODAY}T01:00:00Z" '.updated_at = $u' "$STUB_DIR/comment-1001.json" > "$STUB_DIR/c.tmp" && cat "$STUB_DIR/c.tmp" > "$STUB_DIR/comment-1001.json"; mkplan mixed; }
scn; s_edited; run_h --plan "$PLAN"
expect "an edited delegation leaves every hold standing" 1 "holds: 3 discharged: 0 standing: 3"
assert_eq "0" "$(cat "$STUB_DIR/calls.log" 2>/dev/null | grep -c 'run list\|pr view')" "no gate is probed under an invalid delegation"
scn; echo net > "$STUB_DIR/mode-comment-1001"; mkplan mixed; run_h --plan "$PLAN"
expect "an unreadable delegation is exit 2 and every hold stands" 2 "holds: 3 discharged: 0 standing: 3"
scn; echo 404 > "$STUB_DIR/mode-comment-1001"; mkplan mixed; run_h --plan "$PLAN"
expect "a deleted (revoked) delegation is exit 2 and every hold stands" 2 "holds: 3 discharged: 0 standing: 3"
scn; mkplan mixed; mkdir -p "$TMP/lonely/skills/ship/scripts"; cp "$SUT_REAL" "$TMP/lonely/skills/ship/scripts/hold-gate-eval.sh"
SUT="$TMP/lonely/skills/ship/scripts/hold-gate-eval.sh"; run_h --plan "$PLAN"; SUT="$SUT_REAL"
assert_eq "2" "$(last_rc)" "a missing verifier is exit 2, never a pass"
scn; mkplan wrongenv 's|^Envelope: env-valid.md|Envelope: missing.md|'; run_h --plan "$PLAN"
expect "an envelope that does not verify leaves every hold standing" 1 "holds: 3 discharged: 0 standing: 3"

echo "=== Arm 7: the command kind is restricted ==="
cmdplan() { # <gate text after 'Gate: '>
  scn; mkplan cmdp "s|^  Gate: command scripts/probe-ok.sh => READY|  Gate: $1|"; run_h --plan "$PLAN"
}
cmdplan 'command scripts/probe-ok.sh => READY';                    expect "tracked, pushed, identical probe" 0 "holds: 3 discharged: 3 standing: 0"
cmdplan 'command scripts/probe-bad.sh => READY';                   expect "output differs from the expectation" 1 "holds: 3 discharged: 2 standing: 1"
cmdplan 'command scripts/probe-ok.sh => ready';                    expect "the compare is exact (case)" 1 "holds: 3 discharged: 2 standing: 1"
cmdplan 'command scripts/probe-arrow.sh => a => b';                expect "split at the FIRST arrow only" 0 "holds: 3 discharged: 3 standing: 0"
cmdplan 'command scripts/probe-echo.sh hello => hello';            expect "arguments from the allowed charset are passed" 0 "holds: 3 discharged: 3 standing: 0"
cmdplan 'command scripts/probe-echo.sh a;b => a';                  expect "a shell metacharacter in an argument is refused" 2 "holds: 3 discharged: 2 standing: 1"
cmdplan 'command ../outside.sh => READY';                          expect "a .. path is refused" 2 "holds: 3 discharged: 2 standing: 1"
cmdplan 'command /bin/true => ';                                   expect "an absolute path is refused" 2 "holds: 3 discharged: 2 standing: 1"
cmdplan 'command scripts/probe-link.sh => ';                       expect "a symlink probe is refused" 2 "holds: 3 discharged: 2 standing: 1"
cmdplan 'command scripts/probe-ssh.sh => READY';                   expect "a probe that uses ssh is refused" 2 "holds: 3 discharged: 2 standing: 1"
cmdplan 'command scripts/probe-source.sh => READY';                expect "a probe that sources another file is refused" 2 "holds: 3 discharged: 2 standing: 1"
cmdplan 'command scripts/probe-fail.sh => READY';                  expect "a probe that exits non-zero is exit 2" 2 "holds: 3 discharged: 2 standing: 1"
cmdplan 'command scripts/probe-untracked.sh => READY';             expect "an untracked probe is refused" 2 "holds: 3 discharged: 2 standing: 1"
cmdplan 'command scripts/probe-dirty.sh => EDITED3';               expect "a probe modified in the working tree is refused" 2 "holds: 3 discharged: 2 standing: 1"
cmdplan 'command scripts/probe-edited.sh => EDITED';               expect "a probe edited in a local commit (differs from origin/main) is refused" 2 "holds: 3 discharged: 2 standing: 1"
cmdplan 'command scripts/probe-restored.sh => READY';              expect "a probe equal to origin/main but modified against HEAD is refused" 2 "holds: 3 discharged: 2 standing: 1"
cmdplan 'command scripts/probe-unpushed.sh => READY';              expect "a probe not on origin/main yet is refused" 2 "holds: 3 discharged: 2 standing: 1"
cmdplan 'command scripts/missing.sh => READY';                     expect "a missing probe is refused" 2 "holds: 3 discharged: 2 standing: 1"
cmdplan 'command';                                                 expect "a command gate with no script is refused" 2 "holds: 3 discharged: 2 standing: 1"
cmdplan 'command scripts/probe-ok.sh READY';                       expect "a command gate with no arrow is refused" 2 "holds: 3 discharged: 2 standing: 1"

echo "=== Arm 8: origin/main moved after the last fetch (a fresh fetch is part of the check) ==="
mkdir -p "$TMP/plans"
cat > "$TMP/plans/stale.md" <<EOF
# Plan (synthesized)

## Operator Holds

Delegation: $URL
Envelope: env-valid.md

- Hold: wait until the live check reads ready.
  Gate: command scripts/probe-ok.sh => READY
EOF
stale_run() { stale4; ( cd "$W4" && git_fixture_env "$W4" && PATH="$BIN:$PATH" bash "$SUT" --plan "$TMP/plans/stale.md" ) >"$TMP/o" 2>"$TMP/e"; rc=$?; echo "$rc" > "$TMP/rc"; }
scn; stale_run
expect "the local probe differs from the freshly fetched origin/main" 2 "holds: 1 discharged: 0 standing: 1"

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
scn; run_h --file env-two.md --section "nonesuch"
assert_eq "2" "$(last_rc)" "a section that does not exist is exit 2"
scn; sed '/^- Gate:/d' "$W/env-valid.md" > "$TMP/plans/nogate-env.md"; run_h --file "$TMP/plans/nogate-env.md" --section "Production Envelope"
assert_eq "2" "$(last_rc)" "an envelope with no gate is exit 2"
assert_eq "0" "$(cat "$STUB_DIR/calls.log" 2>/dev/null | grep -c 'repos/.*comments')" "envelope mode does not re-verify the delegation (the caller just did)"

echo "=== Arm 10: usage ==="
scn; run_h;                                   assert_eq "2" "$(last_rc)" "no arguments is exit 2"
scn; run_h --plan "$FX/holds-none.md" --file "$W/env-valid.md" --section x; assert_eq "2" "$(last_rc)" "--plan with --file is exit 2"
scn; run_h --plan "$TMP/no-such-plan.md";     assert_eq "2" "$(last_rc)" "a missing plan file is exit 2 (not an all-clear)"
scn; run_h --bogus;                           assert_eq "2" "$(last_rc)" "an unknown flag is exit 2"
scn; run_h --file env-valid.md;               assert_eq "2" "$(last_rc)" "--file without --section is exit 2"

echo "=== Arm 11: the human lines carry no jargon ==="
jargon_hits() { # <outfile>: count lines (other than the machine line) with a denylisted word
  grep -v '^holds: ' "$1" | grep -E -c '(^|[^A-Za-z])(SHA|HEAD|PR)([^A-Za-z]|$)|#[0-9]+' || true
}
jargon_hits_ci() {
  grep -v '^holds: ' "$1" | grep -i -E -c '(^|[^a-z])(patch-id|rebase|merge-base|stdout|diff|commit|draft|pull request|branch|unarmed)([^a-z]|$)' || true
}
for variant in mixed nogate unk; do
  scn; case "$variant" in mixed) mkplan v ;; nogate) s_nogate ;; unk) s_unknown ;; esac
  run_h --plan "$PLAN"
  cp "$TMP/o" "$TMP/human-$variant.txt"
  assert_eq "0" "$(jargon_hits "$TMP/human-$variant.txt")" "no uppercase jargon or number token in the $variant output"
  assert_eq "0" "$(jargon_hits_ci "$TMP/human-$variant.txt")" "no denylisted word in the $variant output"
done
scn; s_edited; run_h --plan "$PLAN"; cp "$TMP/o" "$TMP/human-edited.txt"
assert_eq "0" "$(( $(jargon_hits "$TMP/human-edited.txt") + $(jargon_hits_ci "$TMP/human-edited.txt") ))" "no jargon in the invalid-delegation output"
printf 'see the PR for the SHA\n' > "$TMP/jargon-control.txt"
assert_eq "1" "$(jargon_hits "$TMP/jargon-control.txt")" "instrument: the jargon check can fail"

echo "=== Arm 12: every gh call was a read ==="
bad=0
for f in "$TMP"/scn*/calls.log; do
  [[ -f "$f" ]] || continue
  n="$(grep -vcE '^(api repos/[A-Za-z0-9_./-]+|repo view --json nameWithOwner --jq \.nameWithOwner|pr view [0-9]+ --json state,mergeCommit,baseRefName|run list --workflow [A-Za-z0-9._-]+ --(status [a-z_]+|commit [0-9a-f]+) --limit 5 --json (databaseId|status,conclusion))$' "$f")"
  bad=$((bad + n))
done
assert_eq "0" "$bad" "no gh call outside the read-only shapes across all scenarios"
assert_eq "0" "$(cat "$TMP"/scn*/calls.log | grep -cE ' (-X|--method|-f|-F|--field|--input) |^(issue|pr) (comment|edit|close|merge)|^workflow run')" "no write verb reached gh"

echo "=== Arm 13: mutations (the pristine control first) ==="
MUT="$TMP/mut"; mkdir -p "$MUT"; PRISTINE_DIR="$TMP/pristine/skills/ship/scripts"; mkdir -p "$PRISTINE_DIR"
# The evaluator resolves the verifier relative to itself, so mutants live in a tree that mirrors the plugin layout.
mkdir -p "$TMP/pristine/scripts"; cp "$REPO_ROOT/plugins/soleur/scripts/delegation-verify.sh" "$TMP/pristine/scripts/"
PRISTINE="$PRISTINE_DIR/hold-gate-eval.sh"; cp "$SUT_REAL" "$PRISTINE"
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
s_restored() { mkplan cmdp 's|^  Gate: command scripts/probe-ok.sh => READY|  Gate: command scripts/probe-restored.sh => READY|'; }
s_unpushed() { mkplan cmdp 's|^  Gate: command scripts/probe-ok.sh => READY|  Gate: command scripts/probe-unpushed.sh => READY|'; }
s_prose2() { PLAN="$FX/holds-prose.md"; }
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

# 1 an unknown kind must not pass
mutate unknown-kind 's/GRES=UNEVAL; return; \}( # mut:unknown-kind)/GRES=TRUE; return; }\1/' && killed unknown-kind "2|holds: 3 discharged: 2 standing: 1" s_unknown r_plan
# 2 a hold with no gate must stand
mutate zero-gates "$(noop zero-gates)" && killed zero-gates "1|holds: 3 discharged: 2 standing: 1" s_nogate r_plan
# 3 stopping at the first gate is the defect
mutate all-gates 's/esac # mut:all-gates/esac; break # mut:all-gates/' && killed all-gates "1|holds: 3 discharged: 2 standing: 1" s_twogates r_plan
# 4 byte-identity with origin/main and tracked-at-HEAD
mutate cmd-identical "$(noop cmd-identical)" && killed cmd-identical "2|holds: 3 discharged: 2 standing: 1" s_unpushed r_plan
mutate cmd-tracked "$(noop cmd-tracked)" && killed cmd-tracked "2|holds: 3 discharged: 2 standing: 1" s_restored r_plan
# 5 an invalid delegation leaves every hold standing
mutate deleg-valid "$(noop deleg-valid)" && killed deleg-valid "1|holds: 3 discharged: 0 standing: 3" s_edited r_plan
# 6 no delegation recorded is exit 3
mutate no-deleg "$(noop no-deleg)" && killed no-deleg "3|holds: 3 discharged: 0 standing: 3" s_nodeleg r_plan
# 7 a non-blank section that parses to zero holds is exit 2
mutate zero-holds "$(noop zero-holds)" && killed zero-holds "2|" s_prose2 r_plan
# 8 a stale origin/main
mutate fetch "$(noop fetch)" && killed fetch "2|holds: 1 discharged: 0 standing: 1" s_mixed r_stale

echo "=== Floor: the SUT answered every row ==="
n_calls="$(cat "$TMP"/scn*/calls.log 2>/dev/null | wc -l | tr -d ' ')"
if (( n_calls >= 300 )); then echo "  PASS: gh stub calls $n_calls >= 300"; PASS=$((PASS + 1))
else echo "  FAIL: gh stub calls $n_calls < 300 -- the rows did not drive the script"; FAIL=$((FAIL + 1)); fi

print_results 190
