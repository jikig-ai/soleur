#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2015  # `A && B || C` is the row idiom; the anchors live in destroy-ask-mutants.json and are LITERAL text, never expanded
# Guard 1 and Guard 2 of the #9776 plan, mutation half (plan "Guard Contract"; ADR-282):
# anchor-asserted textual mutants of the hosted must-ask lane, applied to a COPY of the app tree, each judged by ONE
# targeted vitest file (never the full battery). The mutant table is test/fixtures/destroy-ask-mutants.json.
#
# PROPERTY. For each edit of the lane's chokepoints and narrowing predicates, the designed test turns RED on the
# case that is meant to catch it, and is GREEN on the unedited copy first. A mutant that is not killed, did not
# land, no longer parses, or was killed by something other than its designed detector is a finding. A mutant
# listed `equivalent` must SURVIVE (its reason is printed); if it is killed the table is wrong.
#
# ASSEMBLY. copy -> content-anchored edit (exact occurrence count, never a line number) -> landing proof (cmp
# differs from the pristine copy; a recursive diff names that file and no other) -> one vitest file -> verdict
# read from ANSI-stripped output. Every mutant is restored from the pristine copy with cp, never with git, and the
# restore is proved. The working tree is never edited: its tracked-file status is compared before and after.
#
# Harness rows: (a) a mutant whose anchor is missing must FAIL the harness (never skip); (b) the judge is driven
# with a canned green, a canned red and a canned unparseable log; (c) a no-op edit must read as "not landed";
# (d) the control (unedited) runs first and a red or empty control voids the battery (printf + exit 1).
#
# Usage: bash apps/web-platform/test/destroy-ask-mutation.test.sh [--only <ERE over mutant ids>] [--list]
# Exit: 0 all verdicts as designed; 1 a finding; 2 setup failure; 3 inconclusive (a mutant could not be judged).
# Time: one targeted vitest file per mutant (~2-6 s each); the budget below is a WARN, never a verdict.
set -uo pipefail

WALL_BUDGET_S=900
APP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MUTANTS="$APP/test/fixtures/destroy-ask-mutants.json"
ONLY=""
LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="${2:-}"; shift 2 ;;
    --list) LIST=1; shift ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

for t in python3 jq tar cmp diff timeout; do
  command -v "$t" >/dev/null 2>&1 || { printf 'HALT: required tool missing: %s (a skipped mutation battery reads as a pass)\n' "$t"; exit 2; }
done
VITEST="$APP/node_modules/.bin/vitest"
[ -x "$VITEST" ] || { printf 'HALT: %s is missing; run npm ci in apps/web-platform first\n' "$VITEST"; exit 2; }
[ -s "$MUTANTS" ] || { printf 'HALT: mutant table missing or empty: %s\n' "$MUTANTS"; exit 2; }

if [ "$LIST" = 1 ]; then jq -r '.[] | "\(.id)\t\(.test)\t\(if .equivalent then "equivalent" else "must-kill" end)"' "$MUTANTS"; exit 0; fi

START=$(date +%s)
CHECKED=0 PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf '[ok]   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '[FAIL] %s\n' "$1"; }
check() { # check <label> <command...>: CHECKED moves at the call site, never in ok/bad
  local label="$1"; shift
  CHECKED=$((CHECKED + 1))
  if "$@"; then ok "$label"; else bad "$label"; fi
}

# Instrument self-test: drive both helpers once and require every observable to have moved.
p0=$PASS f0=$FAIL
ok "instrument self-test (pass path)" >/dev/null
bad "instrument self-test (fail path, expected)" >/dev/null
if [ $((PASS - p0)) -ne 1 ] || [ $((FAIL - f0)) -ne 1 ]; then printf 'HALT: the pass/fail helpers did not both move\n'; exit 1; fi
PASS=$p0 FAIL=$f0

SB="$(mktemp -d "${TMPDIR:-/var/tmp}/destroy-ask-mut.XXXXXXXX")" || exit 2
cleanup() { rm -rf "$SB"; }
trap cleanup EXIT
PRISTINE="$SB/.pristine"
REPO="$(cd "$APP/../.." && pwd)"
APPCOPY="$SB/apps/web-platform"
mkdir -p "$PRISTINE" "$APPCOPY" || exit 2
# vitest.config.ts and its global setup reach ../../../plugins/soleur/test/lib/*: mirror that layout (read-only symlink; no mutant edits plugins/).
ln -s "$REPO/plugins" "$SB/plugins" || exit 2

git_status() { git -C "$APP" status --porcelain -- . 2>/dev/null | sort; }
STATUS_BEFORE="$(git_status)"

tar -C "$APP" --exclude=./node_modules --exclude=./.next --exclude=./e2e --exclude=./public --exclude=./docs -cf - . | tar -C "$APPCOPY" -xf -
rc=$?; [ "$rc" = 0 ] || { printf 'HALT: could not copy the app tree (rc=%s)\n' "$rc"; exit 2; }
ln -s "$APP/node_modules" "$APPCOPY/node_modules" || exit 2
# Pristine copies of every file any mutant edits.
while IFS= read -r f; do
  mkdir -p "$PRISTINE/$(dirname "$f")" && cp "$APP/$f" "$PRISTINE/$f" || { printf 'HALT: cannot snapshot %s\n' "$f"; exit 2; }
done < <(jq -r '.[].file' "$MUTANTS" | sort -u)

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[mGKHF]//g' "$1"; }

# vitest summary readers (from ANSI-stripped text). A missing "Tests" line reads as "no summary", never as zero failures.
summary_line() { grep -E '^ *Tests ' "$1.clean" | tail -1; }
count_of() { # count_of <log> <word>
  summary_line "$1" | grep -oE "[0-9]+ $2" | head -1 | grep -oE '[0-9]+'
}

run_test() { # run_test <testfile> <log> -> exit status of vitest in $RUN_RC
  ( cd "$APPCOPY" && timeout -k 5 180 "$VITEST" run "$1" ) > "$2" 2>&1
  RUN_RC=$?
  strip_ansi "$2" > "$2.clean"
}

# Judge: prints one of KILLED, SURVIVED, BROKEN, UNRESOLVED. BROKEN = the mutant does not parse or collect (killed by
# the parser, not by the designed row); UNRESOLVED = no readable summary.
judge() { # judge <log> <rc>
  local log="$1" rc="$2" failed
  failed="$(count_of "$log" failed)"
  if grep -qE 'SyntaxError|Transform failed|Failed to parse|Unexpected token|Cannot find module|Failed to resolve import|is not defined' "$log.clean" && [ -z "$(summary_line "$log")" ]; then echo BROKEN; return; fi
  if [ -z "$(summary_line "$log")" ]; then echo UNRESOLVED; return; fi
  if [ "$rc" = 1 ] && [ -n "$failed" ] && [ "$failed" -ge 1 ]; then echo KILLED; return; fi
  if [ "$rc" = 0 ] && [ -z "$failed" ]; then echo SURVIVED; return; fi
  echo UNRESOLVED
}

# --- Harness row (b): the judge itself, driven with canned logs.
canned() { printf '%s\n' "$2" > "$1"; cp "$1" "$1.clean"; }
canned "$SB/c-green" " Tests  40 passed (40)"
canned "$SB/c-red"   " Tests  2 failed | 38 passed (40)"
canned "$SB/c-parse" " Error: Transform failed with 1 error
SyntaxError: Unexpected token"
check "judge: canned green reads SURVIVED" test "$(judge "$SB/c-green" 0)" = SURVIVED
check "judge: canned red reads KILLED" test "$(judge "$SB/c-red" 1)" = KILLED
check "judge: canned unparseable log reads BROKEN, never KILLED" test "$(judge "$SB/c-parse" 1)" = BROKEN
check "judge: a red log with exit 0 is UNRESOLVED" test "$(judge "$SB/c-red" 0)" = UNRESOLVED

# --- Edit driver (python): replaces a literal anchor, asserts the exact occurrence count, optional nth occurrence.
apply_mutant() { # apply_mutant <index> -> 0 landed, 3 anchor mismatch
  python3 - "$MUTANTS" "$1" "$APPCOPY" <<'PY'
import json, sys
mutants, idx, root = sys.argv[1], int(sys.argv[2]), sys.argv[3]
m = json.load(open(mutants))[idx]
path = root + "/" + m["file"]
s = open(path, encoding="utf-8").read()
n = s.count(m["anchor"])
if n != m["count"]:
    print("ANCHOR MISMATCH for %s: found %d, expected %d" % (m["id"], n, m["count"]))
    sys.exit(3)
nth = m.get("nth")
if nth is None:
    out = s.replace(m["anchor"], m["replace"])
else:
    parts = s.split(m["anchor"])
    out = parts[0]
    for i, p in enumerate(parts[1:], start=1):
        out += (m["replace"] if i == nth else m["anchor"]) + p
open(path, "w", encoding="utf-8").write(out)
PY
}

MIN_MUTANTS=88
TOTAL="$(jq 'length' "$MUTANTS")"
if [ "$TOTAL" -lt "$MIN_MUTANTS" ]; then printf 'HALT: mutant table has %s rows, floor %s: a truncated table is vacuous\n' "$TOTAL" "$MIN_MUTANTS"; exit 1; fi

# --- Harness row (a): a missing anchor must fail the apply step.
BOGUS="$SB/bogus.json"
jq -n '[{id:"bogus",file:"server/destroy-ask-classifier.ts",anchor:"@@no such anchor@@",replace:"x",count:1,nth:null,test:"x",detect:"x",equivalent:null}]' > "$BOGUS"
python3 - "$BOGUS" 0 "$APPCOPY" > /dev/null 2>&1 <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))[0]
s = open(sys.argv[3] + "/" + m["file"], encoding="utf-8").read()
sys.exit(0 if s.count(m["anchor"]) == m["count"] else 3)
PY
rc=$?
check "harness row (a): a mutant whose anchor is missing fails the apply step (rc 3, never a skip)" test "$rc" = 3

# --- Control: the unedited copy, on every distinct test file, must be GREEN with a literal floor of tests.
declare -A FLOOR=( ["test/destroy-ask-classifier.test.ts"]=200 ["test/permission-callback-destroy-ask.test.ts"]=35 ["test/resolve-protected-branches.test.ts"]=20 ["test/components/chat/autonomous-disclosure-banner.test.tsx"]=6 ["test/components/settings/bash-autonomous-toggle.test.tsx"]=8 )
for tf in $(jq -r '.[].test' "$MUTANTS" | sort -u); do
  floor="${FLOOR[$tf]:-}"
  [ -n "$floor" ] || { printf 'HALT: no control floor for test file %s\n' "$tf"; exit 1; }
  run_test "$tf" "$SB/control.$(basename "$tf").log"
  passed="$(count_of "$SB/control.$(basename "$tf").log" passed)"
  failed="$(count_of "$SB/control.$(basename "$tf").log" failed)"
  if [ "$RUN_RC" != 0 ] || [ -n "$failed" ] || [ -z "$passed" ] || [ "$passed" -lt "$floor" ]; then
    printf 'HALT: the CONTROL run of %s is not green with at least %s tests (rc=%s, passed=%s, failed=%s): the battery is void\n' "$tf" "$floor" "$RUN_RC" "${passed:-?}" "${failed:-0}"
    tail -30 "$SB/control.$(basename "$tf").log.clean"
    exit 1
  fi
  CHECKED=$((CHECKED + 1))
  ok "control: $tf is green ($passed tests)"
done

# --- Mutants.
KILLED=0 SURVIVED_EQ=0 UNRESOLVED=0 SELECTED=0
for ((i = 0; i < TOTAL; i++)); do
  id="$(jq -r ".[$i].id" "$MUTANTS")"
  if [ -n "$ONLY" ] && ! [[ "$id" =~ $ONLY ]]; then continue; fi
  SELECTED=$((SELECTED + 1))
  file="$(jq -r ".[$i].file" "$MUTANTS")"
  tf="$(jq -r ".[$i].test" "$MUTANTS")"
  detect="$(jq -r ".[$i].detect // empty" "$MUTANTS")"
  equiv="$(jq -r ".[$i].equivalent // empty" "$MUTANTS")"

  apply_mutant "$i" > "$SB/apply.log" 2>&1
  arc=$?
  if [ "$arc" != 0 ]; then CHECKED=$((CHECKED + 1)); bad "$id: the edit did not apply (rc=$arc): $(cat "$SB/apply.log")"; cp "$PRISTINE/$file" "$APPCOPY/$file"; continue; fi

  # Landing proof: the edited file differs from the pristine copy, and it is the ONLY file that differs from the tree.
  if cmp -s "$APPCOPY/$file" "$PRISTINE/$file"; then CHECKED=$((CHECKED + 1)); bad "$id: the mutation did NOT land (file identical to pristine)"; continue; fi
  differing="$(diff -rq "$APP/$(dirname "$file")" "$APPCOPY/$(dirname "$file")" 2>/dev/null | grep -c 'differ')"
  if [ "$differing" != 1 ]; then CHECKED=$((CHECKED + 1)); bad "$id: expected exactly one differing file in $(dirname "$file"), found $differing"; cp "$PRISTINE/$file" "$APPCOPY/$file"; continue; fi

  run_test "$tf" "$SB/mut.$i.log"
  verdict="$(judge "$SB/mut.$i.log" "$RUN_RC")"
  cp "$PRISTINE/$file" "$APPCOPY/$file"
  if ! cmp -s "$APPCOPY/$file" "$PRISTINE/$file"; then printf 'HALT: restore of %s failed\n' "$file"; exit 2; fi

  CHECKED=$((CHECKED + 1))
  if [ -n "$equiv" ]; then
    if [ "$verdict" = SURVIVED ]; then ok "$id: equivalent, survives as documented ($equiv)"; SURVIVED_EQ=$((SURVIVED_EQ + 1)); else bad "$id: listed equivalent but the verdict is $verdict"; fi
    continue
  fi
  case "$verdict" in
    KILLED)
      escaped="$(jq -rn --arg d "$detect" '$d | @json | .[1:-1]')"
      if [ -n "$detect" ] && ! grep -qF -e "$detect" -e "$escaped" "$SB/mut.$i.log.clean"; then
        bad "$id: killed, but not by its designed detector ('$detect' is absent from the failure output)"
      else
        ok "$id: killed by '$detect'"; KILLED=$((KILLED + 1))
      fi ;;
    SURVIVED) bad "$id: SURVIVED: the fixtures do not exercise this property (fix the fixtures, not the guard)" ;;
    BROKEN)   bad "$id: BROKEN: the mutant does not parse or collect, so it was killed by the parser, not by its row" ;;
    *)        UNRESOLVED=$((UNRESOLVED + 1)); bad "$id: UNRESOLVED: no readable verdict" ;;
  esac
done

# --- Harness row (c): a no-op edit reads as "not landed".
NOOP="$SB/noop.json"
jq -n '[{id:"noop",file:"server/destroy-ask-classifier.ts",anchor:"export const DESTROY_RULE_PREFIX",replace:"export const DESTROY_RULE_PREFIX",count:1,nth:null,test:"x",detect:"x",equivalent:null}]' > "$NOOP"
python3 - "$NOOP" 0 "$APPCOPY" <<'PY' > /dev/null 2>&1
import json, sys
m = json.load(open(sys.argv[1]))[0]
p = sys.argv[3] + "/" + m["file"]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(s.replace(m["anchor"], m["replace"]))
PY
check "harness row (c): a no-op edit reads as not landed" cmp -s "$APPCOPY/server/destroy-ask-classifier.ts" "$PRISTINE/server/destroy-ask-classifier.ts"

# --- The working tree was never edited.
STATUS_AFTER="$(git_status)"
check "the working tree's tracked-file status is unchanged by the battery" test "$STATUS_BEFORE" = "$STATUS_AFTER"

ELAPSED=$(( $(date +%s) - START ))
[ "$ELAPSED" -le "$WALL_BUDGET_S" ] || printf '[WARN] wall time %ss exceeds the %ss budget (a slow runner is not a defect)\n' "$ELAPSED" "$WALL_BUDGET_S"
printf '\nmutants selected=%s killed=%s equivalent-survivors=%s unresolved=%s; checks=%s pass=%s fail=%s; %ss\n' "$SELECTED" "$KILLED" "$SURVIVED_EQ" "$UNRESOLVED" "$CHECKED" "$PASS" "$FAIL" "$ELAPSED"

# Anti-vacuity: the floor is a literal directly above its `if`, and reported by printf + exit, never through ok/bad.
MIN_CHECKS=95
if [ -z "$ONLY" ] && [ "$CHECKED" -lt "$MIN_CHECKS" ]; then printf 'HALT: only %s checks ran, floor %s: the battery is vacuous\n' "$CHECKED" "$MIN_CHECKS"; exit 1; fi
if [ $((PASS + FAIL)) -lt "$CHECKED" ]; then printf 'HALT: pass+fail (%s) is below the checks counted (%s)\n' "$((PASS + FAIL))" "$CHECKED"; exit 1; fi
if [ "$UNRESOLVED" -gt 0 ]; then exit 3; fi
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
