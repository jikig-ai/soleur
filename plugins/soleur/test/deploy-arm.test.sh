#!/usr/bin/env bash
# Test: plugins/soleur/scripts/deploy-arm.sh (#8492)
#
# The deploy arm is identified by the SHA its resolve-target job checked out, never by
# the run's head_sha (a workflow_run run's head_sha is main's tip when it FIRED). This
# suite pins that predicate end to end:
#   - real git: a bare `origin` reached through file:// plus a clone, rebuilt per
#     scenario (A -> M -> D on main, X on an unrelated branch), so ancestry and the
#     fetch-after-listing order are exercised for real;
#   - a stub `gh` on PATH that runs the script's OWN --jq with real jq, models
#     --paginate (page 2 only with it), serves job logs only with
#     --allow-escape-sequences (without it: rc 1, zero bytes — the measured behaviour),
#     returns a 404 as JSON on stdout + rc 1, records argv, and exits 64 on anything
#     it was not told about;
#   - static rows over the two SKILL.md consumers and the workflow lines the script
#     keys on.
# Mutation driver (hand-run): plugins/soleur/test/deploy-arm-mutations.sh.

# shellcheck disable=SC2016  # the rows are literal source text, not expansions
set -uo pipefail
export LC_ALL=C
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SUT="${DEPLOY_ARM_SUT:-$REPO_ROOT/plugins/soleur/scripts/deploy-arm.sh}"
POSTMERGE="$REPO_ROOT/plugins/soleur/skills/postmerge/SKILL.md"
SHIP="$REPO_ROOT/plugins/soleur/skills/ship/SKILL.md"
RELEASE_WF="$REPO_ROOT/.github/workflows/web-platform-release.yml"

# shellcheck source=lib/git-fixture-env.sh
source "$SCRIPT_DIR/lib/git-fixture-env.sh"

fails=0
passes=0
cases=0
pass() { printf '  ok   %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

# Instrument self-test: both helpers must move their OWN counter (ADR-193).
_p0=$passes; _f0=$fails
pass "self-test" >/dev/null
fail "self-test (EXPECTED)" >/dev/null
if [[ $((passes - _p0)) -ne 1 || $((fails - _f0)) -ne 1 ]]; then
  printf '[FATAL] verdict helpers are neutered; refusing to report a result.\n' >&2
  exit 1
fi
passes=$_p0; fails=$_f0

[[ -r "$SUT" ]] || { printf 'FAIL: script missing: %s\n' "$SUT" >&2; exit 1; }

WORK="$(mktemp -d -t deploy-arm-test.XXXXXXXX)"
trap 'rm -rf "$WORK"' EXIT
git_fixture_env "$WORK" || { printf 'FAIL: git_fixture_env refused %s\n' "$WORK" >&2; exit 1; }

NOW=2000000000
iso() { jq -rn --argjson t "$1" '$t | todate'; }

# ---------------------------------------------------------------------------
# Stub gh + curl.
# ---------------------------------------------------------------------------
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Fixture dir: $STUB_FX. Call log: $STUB_FX/calls.
printf '%s\n' "$*" >> "$STUB_FX/calls"
[[ "${1:-}" == "api" ]] || exit 64
shift
paginate=0; escapes=0; jqexpr=""; ep=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --paginate) paginate=1 ;;
    --allow-escape-sequences) escapes=1 ;;
    --jq) jqexpr="$2"; shift ;;
    -*) exit 64 ;;
    *) ep="$1" ;;
  esac
  shift
done
out() { # out <file...> — apply --jq per page, like real gh
  local f
  for f in "$@"; do
    if [[ -n "$jqexpr" ]]; then jq -r "$jqexpr" "$f" || exit 1; else cat "$f"; fi
  done
}
nf() { printf '{"message":"Not Found","documentation_url":"x","status":"404"}\n'; exit 1; }
case "$ep" in
  *actions/workflows/ci.yml/runs\?head_sha=*event=push*)
    [[ -f "$STUB_FX/ci.rc" ]] && exit "$(cat "$STUB_FX/ci.rc")"
    if [[ -f "$STUB_FX/ci.seq" ]]; then
      n=$(( $(cat "$STUB_FX/ci.seq") + 1 )); echo "$n" > "$STUB_FX/ci.seq"
      f="$STUB_FX/ci.$n.json"; [[ -f "$f" ]] || f="$STUB_FX/ci.last.json"
      out "$f"
    else
      out "$STUB_FX/ci.json"
    fi ;;
  *actions/runs\?head_sha=*event=workflow_run*)
    out "$STUB_FX/fg.json" ;;
  *actions/workflows/web-platform-release.yml/runs\?event=workflow_run\&created=*)
    [[ -x "$STUB_FX/win.hook" ]] && "$STUB_FX/win.hook" >/dev/null 2>&1
    if [[ "$paginate" == 1 && -f "$STUB_FX/win.p2.json" ]]; then
      out "$STUB_FX/win.p1.json" "$STUB_FX/win.p2.json"
    else
      out "$STUB_FX/win.p1.json"
    fi ;;
  *actions/runs/*/jobs*)
    id="${ep#*actions/runs/}"; id="${id%%/*}"
    [[ -f "$STUB_FX/jobs.$id.json" ]] || nf
    out "$STUB_FX/jobs.$id.json" ;;
  *actions/jobs/*/logs)
    id="${ep#*actions/jobs/}"; id="${id%%/*}"
    [[ "$escapes" == 1 || -n "${STUB_LAX_ESCAPES:-}" ]] || exit 1
    [[ -f "$STUB_FX/log.$id.404" ]] && nf
    [[ -f "$STUB_FX/log.$id" ]] || nf
    cat "$STUB_FX/log.$id" ;;
  *) exit 64 ;;
esac
STUB
cat > "$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_FX/curl.calls"
n=$(( $(cat "$STUB_FX/curl.seq" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB_FX/curl.seq"
f="$STUB_FX/health.$n"; [[ -f "$f" ]] || f="$STUB_FX/health"
[[ -f "$f" ]] && cat "$f"
exit 0
STUB
chmod +x "$WORK/bin/gh" "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH"

# ---------------------------------------------------------------------------
# Fixture builder. new_fx [M_AGE_S] -> S, CLONE, STUB_FX, A M D X
# ---------------------------------------------------------------------------
SEQ=0
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
commit() { # commit <repo> <msg> <epoch>
  assert_fixture_dir "$1"
  GIT_COMMITTER_DATE="@$3 +0000" GIT_AUTHOR_DATE="@$3 +0000" \
    git -C "$1" commit -q --allow-empty -m "$2"
  git -C "$1" rev-parse HEAD
}
new_fx() {
  local m_age="${1:-3600}"
  SEQ=$((SEQ + 1))
  S="$WORK/s$SEQ"; mkdir -p "$S/fx" "$S/seed"
  export STUB_FX="$S/fx"; : > "$STUB_FX/calls"
  git init -q -b main "$S/seed"
  mkdir -p "$S/seed/.github/workflows"
  printf 'name: stub\n' > "$S/seed/.github/workflows/web-platform-release.yml"
  git -C "$S/seed" add -A
  GIT_COMMITTER_DATE="@$((NOW - 7200)) +0000" git -C "$S/seed" commit -q -m base
  A="$(commit "$S/seed" A $((NOW - 5000)))"
  M="$(commit "$S/seed" M $((NOW - m_age)))"
  D="$(commit "$S/seed" D $((NOW - 50)))"
  git -C "$S/seed" checkout -q -b other "$A"
  X="$(commit "$S/seed" X $((NOW - 40)))"
  git -C "$S/seed" checkout -q main
  git init -q --bare -b main "$S/origin.git"
  git -C "$S/seed" push -q "file://$S/origin.git" main other
  git clone -q "file://$S/origin.git" "$S/clone"
  CLONE="$S/clone"
  printf '{"workflow_runs":[]}\n' > "$STUB_FX/fg.json"
  printf '{"workflow_runs":[]}\n' > "$STUB_FX/win.p1.json"
  ci completed success $((NOW - 3000)) $((NOW - 3000)) $((NOW - 2400)) 1
}
ci() { # ci <status> <conclusion|null> <created> <started> <updated> <attempt> [file]
  local c="null"; [[ "$2" != "null" ]] && c="\"$2\""
  jq -n --arg s "$1" --argjson c "$c" --arg cr "$(iso "$3")" --arg st "$(iso "$4")" \
    --arg up "$(iso "$5")" --argjson a "$6" \
    '{workflow_runs:[{status:$s, conclusion:$c, created_at:$cr, run_started_at:$st, updated_at:$up, run_attempt:$a}]}' \
    > "${7:-$STUB_FX/ci.json}"
}
no_ci() { printf '{"workflow_runs":[]}\n' > "$STUB_FX/ci.json"; }
runs_add() { # runs_add <file> <id> <created> <status> <conclusion|null>
  local c="null"; [[ "$5" != "null" ]] && c="\"$5\""
  jq --argjson id "$2" --arg cr "$(iso "$3")" --arg s "$4" --argjson c "$c" \
    '.workflow_runs += [{id:$id, path:".github/workflows/web-platform-release.yml", event:"workflow_run", created_at:$cr, status:$s, conclusion:$c}]' \
    "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
jobs() { # jobs <runid> <name:status:conclusion:completed_epoch[:webhook_step_conclusion]>...
  local id="$1"; shift
  local spec arr="[]" n st c t sc jid
  jid=$((id * 10))
  for spec in "$@"; do
    IFS=: read -r n st c t sc <<< "$spec"
    jid=$((jid + 1))
    arr="$(jq --arg n "$n" --argjson id "$jid" --arg s "$st" --arg c "$c" --arg t "$t" --arg sc "${sc:-}" \
      '. += [{name:$n, id:$id, status:$s, conclusion:(if $c == "-" then null else $c end), completed_at:(if $t == "-" then null else ($t|tonumber|todate) end), steps:(if $sc == "" then [] else [{name:"Deploy via webhook", conclusion:$sc}] end)}]' <<< "$arr")"
  done
  jq -n --argjson j "$arr" '{total_count:($j|length), jobs:$j}' > "$STUB_FX/jobs.$id.json"
}
# arm <file> <runid> <created> <logsha|-> [deploy_conclusion] — a completed arm whose
# resolve-target (job id runid*10+1) completed 60 s after creation.
arm() {
  local f="$1" id="$2" cr="$3" sha="$4" dc="${5:-success}"
  runs_add "$f" "$id" "$cr" completed success
  jobs "$id" "resolve-target:completed:success:$((cr + 60))" "deploy:completed:$dc:$((cr + 600))"
  [[ "$sha" == "-" ]] || printf '2026-09-21T08:44:53Z [command]/usr/bin/git -c protocol.version=2 fetch --no-tags --prune --depth=1 origin %s\n' "$sha" > "$STUB_FX/log.$((id * 10 + 1))"
}
FG() { printf '%s' "$STUB_FX/fg.json"; }
WIN() { printf '%s' "$STUB_FX/win.p1.json"; }

# run_find <expected line> <expected rc> <label> [args...] — asserts rc, exactly one stdout line, the line.
LAST_OUT=""; LAST_ERR=""
run_sut() { # run_sut <dir> args... -> RC, OUT, ERR files
  LAST_OUT="$S/out"; LAST_ERR="$S/err"
  RC=0
  ( cd "$1" && shift && DEPLOY_ARM_NOW=$NOW DEPLOY_ARM_SLEEP=0 bash "$SUT" "$@" ) > "$LAST_OUT" 2> "$LAST_ERR" || RC=$?
}
expect() { # expect <label> <want line> <want rc>
  local lines got
  cases=$((cases + 1))
  lines="$(grep -c '' "$LAST_OUT" || true)"
  got="$(cat "$LAST_OUT")"
  if [[ "$RC" == "$3" && "$lines" == 1 && "$got" == "$2" ]]; then
    pass "$1"
  else
    fail "$1: rc=$RC (want $3) lines=$lines got=[$got] want=[$2] stderr=[$(tail -3 "$LAST_ERR" | tr '\n' '|')]"
  fi
}
find_in_clone() { run_sut "$CLONE" find "$@"; }

echo "== find"

# S1 (+H2): fast path, 4 calls, an unrelated 40-hex precedes the key line.
new_fx
arm "$(FG)" 1001 $((NOW - 2300)) "$M"
printf 'noise %s\n%s' "$X" "$(cat "$STUB_FX/log.10011")" > "$STUB_FX/log.10011"
cp "$(FG)" "$(WIN)"
find_in_clone "$M"
expect "S1 fast path exact" "ARM=1001 DEPLOYED_SHA=$M MATCH=exact DEPLOY=success CI=success" 0
cases=$((cases + 1))
_calls="$(grep -c '' "$STUB_FX/calls")"
if [[ "$_calls" == 4 ]] && ! grep -q 'created=' "$STUB_FX/calls"; then pass "S1 fast path makes 4 calls, no window call"
else fail "S1 fast path: $_calls calls: $(tr '\n' '|' < "$STUB_FX/calls")"; fi

# S2 (#8391): the API lists the previous merge's arm first.
new_fx
arm "$(FG)" 1001 $((NOW - 2300)) "$A"
arm "$(FG)" 1002 $((NOW - 2200)) "$M"
cp "$(FG)" "$(WIN)"
find_in_clone "$M"
expect "S2 previous merge's arm listed first is rejected" "ARM=1002 DEPLOYED_SHA=$M MATCH=exact DEPLOY=success CI=success" 0

# S3 (#8297): first guess empty; the real arm is stamped with a later SHA.
new_fx
arm "$(WIN)" 1003 $((NOW - 2300)) "$M"
find_in_clone "$M"
expect "S3 arm found through the window" "ARM=1003 DEPLOYED_SHA=$M MATCH=exact DEPLOY=success CI=success" 0

# S4: descendant deploy.
new_fx
arm "$(WIN)" 1004 $((NOW - 2300)) "$D"
find_in_clone "$M"
expect "S4 descendant" "ARM=1004 DEPLOYED_SHA=$D MATCH=descendant DEPLOY=success CI=success" 0

# S5: CI in progress.
new_fx
ci in_progress null $((NOW - 300)) $((NOW - 300)) $((NOW - 100)) 1
arm "$(WIN)" 1005 $((NOW - 2300)) "$A"
find_in_clone "$M"
expect "S5 ci_pending" "ARM=none REASON=ci_pending" 4

# S6: only the previous merge's arm.
new_fx
arm "$(WIN)" 1006 $((NOW - 2300)) "$A"
find_in_clone "$M"
expect "S6 ancestor is rejected" "ARM=none REASON=no_candidate" 3

# S7: log unreadable past the grace window.
new_fx
arm "$(WIN)" 1007 $((NOW - 660)) "$M"
touch "$STUB_FX/log.10071.404"
find_in_clone "$M"
expect "S7 unreadable log is unresolved, never a mismatch" "ARM=none REASON=unresolved CAUSE=log_read_failed" 3

# S8: the window call pushes L (descendant) to origin; fetch-after-listing sees it.
new_fx
git -C "$S/seed" checkout -q main
L="$(commit "$S/seed" L $((NOW - 30)))"
printf '#!/usr/bin/env bash\ngit -C "%s" push -q "file://%s" main\n' "$S/seed" "$S/origin.git" > "$STUB_FX/win.hook"
chmod +x "$STUB_FX/win.hook"
arm "$(WIN)" 1008 $((NOW - 2300)) "$L"
find_in_clone "$M"
expect "S8 fetch after listing" "ARM=1008 DEPLOYED_SHA=$L MATCH=descendant DEPLOY=success CI=success" 0

# S9: short SHA.
new_fx
find_in_clone "${M:0:7}"
expect "S9 short sha" "ARM=none REASON=error CAUSE=bad_input" 2

# S10: unrelated branch.
new_fx
arm "$(WIN)" 1010 $((NOW - 2300)) "$X"
find_in_clone "$M"
expect "S10 unrelated sha" "ARM=none REASON=no_candidate" 3

# S12: CI re-run; attempt-1 arm is older than run_started_at.
new_fx
ci completed success $((NOW - 3000)) $((NOW - 1500)) $((NOW - 1450)) 2
arm "$(WIN)" 1012 $((NOW - 2300)) "$M" failure
arm "$(WIN)" 1013 $((NOW - 1400)) "$M"
find_in_clone "$M"
expect "S12 attempt-2 arm replaces attempt 1's" "ARM=1013 DEPLOYED_SHA=$M MATCH=exact DEPLOY=success CI=success" 0

# S13: an earlier candidate is still resolving.
new_fx
runs_add "$(WIN)" 1014 $((NOW - 2300)) in_progress null
jobs 1014 "resolve-target:in_progress:-:-"
arm "$(WIN)" 1015 $((NOW - 2200)) "$D"
find_in_clone "$M"
expect "S13 pending earlier candidate blocks a descendant" "ARM=none REASON=arm_pending" 4

# S14: CI red -> exact arm clean-skipped; a later arm delivers D.
new_fx
ci completed failure $((NOW - 3000)) $((NOW - 3000)) $((NOW - 2400)) 1
arm "$(WIN)" 1016 $((NOW - 2300)) "$M" skipped
arm "$(WIN)" 1017 $((NOW - 1300)) "$D"
find_in_clone "$M"
expect "S14 descendant delivers a ci_not_green merge" "ARM=1017 DEPLOYED_SHA=$D MATCH=descendant DEPLOY=success CI=failure" 0

# S15: 1.5 MB log.
new_fx
arm "$(WIN)" 1018 $((NOW - 2300)) "$M"
{ cat "$STUB_FX/log.10181"; head -c 1500000 /dev/zero | tr '\0' 'x' | fold -w 200; echo; } > "$STUB_FX/log.big"
mv "$STUB_FX/log.big" "$STUB_FX/log.10181"
find_in_clone "$M"
expect "S15 large log" "ARM=1018 DEPLOYED_SHA=$M MATCH=exact DEPLOY=success CI=success" 0

# S16: a cancelled run with no resolve-target is dropped.
new_fx
runs_add "$(WIN)" 1019 $((NOW - 2300)) completed cancelled
jobs 1019 "release:completed:skipped:$((NOW - 2290))"
arm "$(WIN)" 1020 $((NOW - 2200)) "$D"
find_in_clone "$M"
expect "S16 cancelled run dropped" "ARM=1020 DEPLOYED_SHA=$D MATCH=descendant DEPLOY=success CI=success" 0

# S17: two pages newest-first; the earliest descendant is on page 2.
new_fx
arm "$(WIN)" 1022 $((NOW - 1000)) "$D"
printf '{"workflow_runs":[]}\n' > "$STUB_FX/win.p2.json"
arm "$STUB_FX/win.p2.json" 1021 $((NOW - 2300)) "$D"
find_in_clone "$M"
expect "S17 global sort across pages" "ARM=1021 DEPLOYED_SHA=$D MATCH=descendant DEPLOY=success CI=success" 0

# S18: log 404 inside / outside the 3-minute grace.
for age in 60 170 190; do
  new_fx
  runs_add "$(WIN)" 1023 $((NOW - 2300)) completed success
  jobs 1023 "resolve-target:completed:success:$((NOW - age))" "deploy:completed:success:$((NOW - 10))"
  touch "$STUB_FX/log.10231.404"
  find_in_clone "$M"
  if [[ "$age" == 190 ]]; then
    expect "S18 log 404 at NOW-$age -> unresolved" "ARM=none REASON=unresolved CAUSE=log_read_failed" 3
  else
    expect "S18 log 404 at NOW-$age -> grace" "ARM=none REASON=arm_pending" 4
  fi
done

# S19 / S20: no CI run for the merge.
new_fx 900; no_ci
find_in_clone "$M"
expect "S19 ci_absent" "ARM=none REASON=ci_absent" 3
new_fx 60; no_ci
find_in_clone "$M"
expect "S20 fresh merge without CI is ci_pending" "ARM=none REASON=ci_pending" 4

# S21: deploy skipped behind a failed verify job -> blocked.
new_fx
runs_add "$(WIN)" 1024 $((NOW - 2300)) completed failure
jobs 1024 "resolve-target:completed:success:$((NOW - 2240))" "verify-doppler-secrets:completed:failure:$((NOW - 2200))" "deploy:completed:skipped:$((NOW - 2200))"
printf '2026-09-21T08:44:53Z [command]/usr/bin/git fetch --depth=1 origin %s\n' "$M" > "$STUB_FX/log.10241"
find_in_clone "$M"
expect "S21 blocked, not skipped" "ARM=1024 DEPLOYED_SHA=$M MATCH=exact DEPLOY=blocked CI=success" 0

# S22: exact arm's deploy cancelled by the swap lock; a later arm delivers.
new_fx
arm "$(WIN)" 1025 $((NOW - 2300)) "$M" cancelled
arm "$(WIN)" 1026 $((NOW - 1300)) "$D"
find_in_clone "$M"
expect "S22 superseded exact arm hands off to the descendant" "ARM=1026 DEPLOYED_SHA=$D MATCH=descendant DEPLOY=success CI=success" 0

# S24: docs-only clean skip.
new_fx
arm "$(WIN)" 1027 $((NOW - 2300)) "$M" skipped
find_in_clone "$M"
expect "S24 designed clean skip" "ARM=1027 DEPLOYED_SHA=$M MATCH=exact DEPLOY=skipped CI=success" 0

# S25: fallback key line.
new_fx
arm "$(WIN)" 1028 $((NOW - 2300)) -
printf '2026 resolving deploy target for %s\n' "$M" > "$STUB_FX/log.10281"
find_in_clone "$M"
expect "S25 fallback line" "ARM=1028 DEPLOYED_SHA=$M MATCH=exact DEPLOY=success CI=success" 0

# S26: neither key line.
new_fx
arm "$(WIN)" 1029 $((NOW - 2300)) -
printf 'checkout done\n' > "$STUB_FX/log.10291"
find_in_clone "$M"
expect "S26 log_line_absent" "ARM=none REASON=unresolved CAUSE=log_line_absent" 3

# S27: more candidates than the cap.
new_fx
for k in $(seq 1 31); do arm "$(WIN)" $((1100 + k)) $((NOW - 2400 + k)) "$A"; done
find_in_clone "$M"
expect "S27 cap_hit" "ARM=none REASON=unresolved CAUSE=cap_hit" 3

# S28: CI re-run, a pending candidate created after the exact arm.
new_fx
ci completed success $((NOW - 3000)) $((NOW - 1500)) $((NOW - 1450)) 2
arm "$(WIN)" 1030 $((NOW - 1400)) "$M"
runs_add "$(WIN)" 1031 $((NOW - 1300)) queued null
jobs 1031 "resolve-target:queued:-:-"
find_in_clone "$M"
expect "S28 re-run with a later pending candidate" "ARM=none REASON=arm_pending" 4

# S29: the ci.yml call fails.
new_fx
echo 1 > "$STUB_FX/ci.rc"
find_in_clone "$M"
expect "S29 gh_failed" "ARM=none REASON=error CAUSE=gh_failed" 2

# S30: not this repo.
new_fx
mkdir -p "$S/elsewhere"; git init -q "$S/elsewhere"
run_sut "$S/elsewhere" find "$M"
expect "S30 not_applicable" "ARM=none REASON=not_applicable" 3

# S31: --wait polls through ci_pending to S1's verdict.
new_fx
arm "$(FG)" 1001 $((NOW - 2300)) "$M"
cp "$(FG)" "$(WIN)"
ci in_progress null $((NOW - 3000)) $((NOW - 3000)) $((NOW - 2400)) 1 "$STUB_FX/ci.1.json"
cp "$STUB_FX/ci.json" "$STUB_FX/ci.last.json"
echo 0 > "$STUB_FX/ci.seq"
find_in_clone --wait 2 "$M"
expect "S31 --wait" "ARM=1001 DEPLOYED_SHA=$M MATCH=exact DEPLOY=success CI=success" 0
cases=$((cases + 1))
if [[ "$(grep -c '^deploy-arm: waiting' "$LAST_ERR" || true)" == 1 ]]; then pass "S31 one progress line"
else fail "S31 progress lines: $(grep -c '^deploy-arm: waiting' "$LAST_ERR" || true)"; fi


echo "== find: review additions"
LOGL() { printf '2026-09-21T08:44:53Z [command]/usr/bin/git -c protocol.version=2 fetch --no-tags --depth=1 origin %s\n' "$1"; }

# P1 pending deploy: the exact arm's deploy is still running -> rc 4 with the arm line.
new_fx
runs_add "$(WIN)" 2001 $((NOW - 2300)) in_progress null
jobs 2001 "resolve-target:completed:success:$((NOW - 2240))" "deploy:in_progress:-:-"
LOGL "$M" > "$STUB_FX/log.20011"
find_in_clone "$M"
expect "pending deploy -> rc 4 arm line" "ARM=2001 DEPLOYED_SHA=$M MATCH=exact DEPLOY=pending CI=success" 4
arm "$(WIN)" 2002 $((NOW - 1000)) "$D"
find_in_clone "$M"
expect "pending exact arm outranks a later delivered descendant" "ARM=2001 DEPLOYED_SHA=$M MATCH=exact DEPLOY=pending CI=success" 4

# The merge's own arm is created AFTER a descendant's (D's CI finished first) and is
# still resolving -> never settle on the descendant.
new_fx
arm "$(WIN)" 2003 $((NOW - 2300)) "$D"
runs_add "$(WIN)" 2004 $((NOW - 1000)) queued null
jobs 2004 "resolve-target:queued:-:-"
find_in_clone "$M"
expect "later pending candidate blocks a descendant verdict" "ARM=none REASON=arm_pending" 4

# A fork-shaped arm (sha not on main, unknown locally after a good fetch) is rejected.
new_fx
FORK="$(printf '%040d' 3 | tr 0 b)"
arm "$(WIN)" 2005 $((NOW - 2300)) "$FORK"
arm "$(WIN)" 2006 $((NOW - 1000)) "$D"
find_in_clone "$M"
expect "fork sha rejected, later descendant selected" "ARM=2006 DEPLOYED_SHA=$D MATCH=descendant DEPLOY=success CI=success" 0
# ... and with an unreachable origin it is could-not-measure.
git -C "$CLONE" remote set-url origin "file://$S/nonexistent.git"
find_in_clone "$M"
expect "unknown sha without a fetch -> unresolved ancestry_128" "ARM=none REASON=unresolved CAUSE=ancestry_128" 3

# A commit on another branch that a local clone happens to hold is rejected too.
new_fx
arm "$(WIN)" 2007 $((NOW - 2300)) "$X"
arm "$(WIN)" 2008 $((NOW - 1000)) "$D"
find_in_clone "$M"
expect "off-main sha rejected" "ARM=2008 DEPLOYED_SHA=$D MATCH=descendant DEPLOY=success CI=success" 0

# --wait timeout paths.
new_fx
ci in_progress null $((NOW - 300)) $((NOW - 300)) $((NOW - 100)) 1
find_in_clone --wait 2 "$M"
expect "--wait timeout while CI pending" "ARM=none REASON=timeout LAST=ci_pending" 3
new_fx
runs_add "$(WIN)" 2009 $((NOW - 2300)) in_progress null
jobs 2009 "resolve-target:completed:success:$((NOW - 2240))" "deploy:in_progress:-:-"
LOGL "$M" > "$STUB_FX/log.20091"
find_in_clone --wait 2 "$M"
expect "--wait timeout while deploy pending keeps the arm id" "ARM=none REASON=timeout LAST=deploy_pending ARM=2009" 3
new_fx
echo 1 > "$STUB_FX/ci.rc"
find_in_clone --wait 2 "$M"
expect "--wait polls through gh failures" "ARM=none REASON=timeout LAST=error CAUSE=gh_failed" 3

# Fast path: newest exact arm first.
new_fx
arm "$(FG)" 2010 $((NOW - 2300)) "$M" failure
arm "$(FG)" 2011 $((NOW - 2000)) "$M"
cp "$(FG)" "$(WIN)"
find_in_clone "$M"
expect "fast path takes the newest exact arm" "ARM=2011 DEPLOYED_SHA=$M MATCH=exact DEPLOY=success CI=success" 0

# CI absent, delivered by a descendant.
new_fx 900; no_ci
arm "$(WIN)" 2012 $((NOW - 800)) "$D"
find_in_clone "$M"
expect "CI=absent on a descendant verdict" "ARM=2012 DEPLOYED_SHA=$D MATCH=descendant DEPLOY=success CI=absent" 0

# The queries carry the merge sha and the window's lower bound.
new_fx
arm "$(WIN)" 2013 $((NOW - 2300)) "$M"
find_in_clone "$M"
for q in "actions/workflows/ci.yml/runs?head_sha=$M&event=push" "actions/runs?head_sha=$M&event=workflow_run" \
         "created=%3E%3D$(iso $((NOW - 3000)))&"; do
  cases=$((cases + 1))
  if grep -qF -- "$q" "$STUB_FX/calls"; then pass "query carries ${q:0:40}"; else fail "query missing: $q"; fi
done

# Post-CI grace: CI just completed, the merge's own arm not created yet.
new_fx
ci completed success $((NOW - 3000)) $((NOW - 3000)) $((NOW - 60)) 1
arm "$(WIN)" 2014 $((NOW - 2300)) "$A"
find_in_clone "$M"
expect "arm not created yet after a fresh CI completion" "ARM=none REASON=arm_pending" 4

# CI re-run: attempt 1's exact arm is stale; wait for attempt 2's.
new_fx
ci completed success $((NOW - 3000)) $((NOW - 1500)) $((NOW - 1450)) 2
arm "$(WIN)" 2015 $((NOW - 2300)) "$M"
find_in_clone "$M"
expect "re-run: attempt-1 arm is never the answer" "ARM=none REASON=arm_pending" 4

# A cancelled resolve-target is dropped, not a blocker.
new_fx
runs_add "$(WIN)" 2016 $((NOW - 2300)) completed cancelled
jobs 2016 "resolve-target:completed:cancelled:$((NOW - 2290))"
arm "$(WIN)" 2017 $((NOW - 1000)) "$D"
find_in_clone "$M"
expect "cancelled resolve-target dropped" "ARM=2017 DEPLOYED_SHA=$D MATCH=descendant DEPLOY=success CI=success" 0

# A commit subject echoed in the log cannot supply the fallback key line.
new_fx
arm "$(WIN)" 2018 $((NOW - 2300)) -
printf '2026-09-21T08:44:55Z HEAD is now at 1234567 resolving deploy target for %s\n2026-09-21T08:45:02Z resolving deploy target for %s\n' "$A" "$M" > "$STUB_FX/log.20181"
find_in_clone "$M"
expect "forged subject line ignored" "ARM=2018 DEPLOYED_SHA=$M MATCH=exact DEPLOY=success CI=success" 0

# Descendants: a later successful deploy wins over an earlier failed one.
new_fx
arm "$(WIN)" 2019 $((NOW - 2300)) "$D" failure
arm "$(WIN)" 2020 $((NOW - 1000)) "$D"
find_in_clone "$M"
expect "successful descendant preferred" "ARM=2020 DEPLOYED_SHA=$D MATCH=descendant DEPLOY=success CI=success" 0

# deploy concluded success but the ordering guard skipped the webhook -> superseded.
new_fx
runs_add "$(WIN)" 2021 $((NOW - 2300)) completed success
jobs 2021 "resolve-target:completed:success:$((NOW - 2240))" "deploy:completed:success:$((NOW - 2200)):skipped"
LOGL "$M" > "$STUB_FX/log.20211"
find_in_clone "$M"
expect "ordering-guard skip is superseded, not success" "ARM=2021 DEPLOYED_SHA=$M MATCH=exact DEPLOY=superseded CI=success" 0

# Gate-job outcomes behind a skipped deploy.
for pair in "timed_out:blocked" "cancelled:superseded"; do
  IFS=: read -r mc want <<< "$pair"
  new_fx
  runs_add "$(WIN)" 2022 $((NOW - 2300)) completed failure
  jobs 2022 "resolve-target:completed:success:$((NOW - 2240))" "migrate:completed:$mc:$((NOW - 2200))" "deploy:completed:skipped:$((NOW - 2200))"
  LOGL "$M" > "$STUB_FX/log.20221"
  find_in_clone "$M"
  expect "migrate $mc -> DEPLOY=$want" "ARM=2022 DEPLOYED_SHA=$M MATCH=exact DEPLOY=$want CI=success" 0
done

echo "== contains / served"
new_fx
UNKNOWN="$(printf '%040d' 7 | tr 0 a)"
for pair in "$M:CONTAINS:0" "$D:CONTAINS:0" "$A:NOT_CONTAINED:1" ":UNRESOLVED:3" "dev:UNRESOLVED:3" "$UNKNOWN:UNRESOLVED:3"; do
  IFS=: read -r b want wrc <<< "$pair"
  run_sut "$CLONE" contains "$M" "$b"
  expect "S11 contains build=[${b:0:7}]" "$want" "$wrc"
done
git -C "$CLONE" remote set-url origin "file://$S/nonexistent.git"
run_sut "$CLONE" contains "$M" "$UNKNOWN"
expect "S11 unreachable origin: unknown -> UNRESOLVED" "UNRESOLVED" 3
run_sut "$CLONE" contains "$M" "$D"
expect "S11 unreachable origin: D -> CONTAINS" "CONTAINS" 0

new_fx
: > "$STUB_FX/health.1"; : > "$STUB_FX/health.2"; : > "$STUB_FX/health.3"
run_sut "$CLONE" served "$M"
expect "S23 empty body" "UNRESOLVED BUILD_SHA=-" 3
new_fx
printf '<html>nope</html>' > "$STUB_FX/health"
run_sut "$CLONE" served "$M"
expect "S23 non-JSON body" "UNRESOLVED BUILD_SHA=-" 3
new_fx
printf '{"status":"ok","build_sha":"%s"}' "$D" > "$STUB_FX/health"
run_sut "$CLONE" served "$M"
expect "S23 descendant build" "CONTAINS BUILD_SHA=$D" 0


new_fx
run_sut "$CLONE" contains "${M:0:7}" "$D"
expect "contains short merge sha" "ERROR CAUSE=bad_input" 2
run_sut "$CLONE" contains "$M"
expect "contains with one argument" "ERROR CAUSE=bad_input" 2
run_sut "$CLONE" served "$M" http://example.test/health
expect "served refuses a non-https url" "ERROR CAUSE=bad_input BUILD_SHA=-" 2
new_fx
: > "$STUB_FX/health.1"
printf '{"build_sha":"%s"}' "$M" > "$STUB_FX/health.2"
run_sut "$CLONE" served "$M" https://example.test/health
expect "served retries an empty body" "CONTAINS BUILD_SHA=$M" 0
cases=$((cases + 1))
if grep -qF -- '--url https://example.test/health' "$STUB_FX/curl.calls"; then pass "served passes its url to curl"
else fail "served url not passed: $(tr '\n' '|' < "$STUB_FX/curl.calls")"; fi
new_fx
printf '{"build_sha":"%s"}' "$A" > "$STUB_FX/health"
run_sut "$CLONE" served "$M"
expect "served NOT_CONTAINED" "NOT_CONTAINED BUILD_SHA=$A" 1

# The verdict-owning helper must be able to REJECT (a neutered expect() would pass all).
_p1=$passes; _f1=$fails; _c1=$cases
expect "expect() control (EXPECTED to fail)" "CONTAINS BUILD_SHA=never" 0 >/dev/null
if [[ $((fails - _f1)) -ne 1 || $((passes - _p1)) -ne 0 ]]; then
  printf '[FATAL] expect() cannot reject: passes moved %d, fails moved %d\n' "$((passes - _p1))" "$((fails - _f1))"; exit 1
fi
passes=$_p1; fails=$_f1; cases=$_c1

# ---------------------------------------------------------------------------
# Static rows — scoped to the named files only, comment lines stripped.
# ---------------------------------------------------------------------------
echo "== static"
FORBID_RE='head_sha=[^ "]*&[^ "]*event=workflow_run|event=workflow_run&[^ "]*head_sha=|-f head_sha=.*event=workflow_run|gh run list[^`|]*--event workflow_run[^`|]*--commit|gh run list[^`|]*--commit[^`|]*--event workflow_run|expected `build_sha`|build_sha == merge sha|"\$BUILD_SHA" = "\$MERGE_SHA"'
# Self-test the regex before trusting it.
cases=$((cases + 1))
if grep -qE "$FORBID_RE" <<< 'actions/runs?head_sha=${MERGE_SHA}&event=workflow_run' \
  && grep -qE "$FORBID_RE" <<< 'require `/health` `build_sha == merge sha` before' \
  && grep -qE "$FORBID_RE" <<< 'runs?event=workflow_run&per_page=5&head_sha=X' \
  && grep -qE "$FORBID_RE" <<< 'runs?head_sha=X&per_page=5&event=workflow_run' \
  && grep -qE "$FORBID_RE" <<< 'gh api runs -f head_sha=X -f event=workflow_run' \
  && grep -qE "$FORBID_RE" <<< 'gh run list --commit X --event workflow_run' \
  && grep -qE "$FORBID_RE" <<< 'test "$BUILD_SHA" = "$MERGE_SHA"' \
  && ! grep -qE "$FORBID_RE" <<< 'ci.yml/runs?head_sha=X&event=push' \
  && ! grep -qE "$FORBID_RE" <<< '`gh run list --commit <sha>` returns; filter by `--event push` / `--event workflow_run`' \
  && ! grep -qE "$FORBID_RE" <<< 'never a `head_sha=` query; `event=workflow_run` is the deploy arm' \
  && ! grep -qE "$FORBID_RE" <<< 'bash plugins/soleur/scripts/deploy-arm.sh find --wait X'; then
  pass "forbidden-selector regex self-test"
else fail "forbidden-selector regex self-test"; fi

for f in "$POSTMERGE" "$SHIP"; do
  b="${f#"$REPO_ROOT"/}"
  cases=$((cases + 1))
  if [[ -s "$f" ]] && grep -qE 'deploy-arm\.sh (find|served)' "$f"; then pass "$b calls deploy-arm.sh"
  else fail "$b does not call deploy-arm.sh (or is missing)"; fi
  cases=$((cases + 1))
  if [[ -s "$f" ]] && ! grep -nE "$FORBID_RE" "$f" >/dev/null; then pass "$b carries no head_sha arm selector / string build_sha check"
  else fail "$b still selects by head_sha or compares build_sha: $(grep -nE "$FORBID_RE" "$f" | cut -c1-160 | head -3 | tr '\n' '|')"; fi
done
cases=$((cases + 1))
if [[ -s "$POSTMERGE" ]] && grep -qE "^gh pr diff <number> --name-only \| grep -qE '[^']*plugins/soleur/scripts/deploy-arm\\\\\.sh'" "$POSTMERGE"; then pass "postmerge 3.7 gate regex watches deploy-arm.sh"
else fail "postmerge 3.7 gate regex does not include deploy-arm"; fi

# The workflow lines the script keys on.
cases=$((cases + 1))
if [[ -s "$RELEASE_WF" ]]; then
  _blk="$(awk '/^  resolve-target:/{f=1; print; next} f && /^  [a-z][a-z0-9-]*:/{exit} f' "$RELEASE_WF" | grep -v '^[[:space:]]*#')"
  _co="$(grep -n 'uses: actions/checkout@' <<< "$_blk" | head -1 | cut -d: -f1)"
  _ref="$(grep -nE '^ +ref: \$\{\{ github\.event\.workflow_run\.head_sha \|\| github\.sha \}\}$' <<< "$_blk" | head -1 | cut -d: -f1)"
  _res="$(grep -n 'id: resolve$' <<< "$_blk" | head -1 | cut -d: -f1)"
  if [[ -n "$_blk" ]] && ! grep -qE '^    name:' <<< "$_blk" && [[ -n "$_co" && -n "$_ref" && -n "$_res" ]] && (( _co < _ref && _ref < _res )) \
     && grep -qE '^ +echo "resolving deploy target for \$WR_HEAD_SHA"$' <<< "$_blk"; then
    pass "resolve-target: no name override, pinned checkout before resolve, echo present"
  else
    fail "resolve-target keying lines drifted (block=${#_blk}B ref=$_ref resolve=$_res)"
  fi
else fail "web-platform-release.yml missing"; fi

# ---------------------------------------------------------------------------
# Accounting.
# ---------------------------------------------------------------------------
MIN_CASES=79
echo
printf '%d passed, %d failed, %d cases\n' "$passes" "$fails" "$cases"
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf '[FATAL] accounting: passes+fails=%d != cases=%d\n' "$((passes + fails))" "$cases"; exit 1
fi
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf '[FATAL] only %d assertions ran (floor %d)\n' "$cases" "$MIN_CASES"; exit 1
fi
[[ "$fails" -eq 0 ]]
