#!/usr/bin/env bash
# Suite for scripts/monitor-streak-state.sh and its wiring in
# .github/workflows/scheduled-rehearsal-skip-monitor.yml (the streak lives in a workflow artifact;
# ADR-296 has the cause and the alternatives).
#
# A store swap is only as good as its failure behaviour: an unreadable store, an empty store and a
# poisoned store must be three different outcomes, and a run that cannot prove it restored a numeric
# prior streak must go red.
#
# SECTION A drives the script with a fake `gh` on PATH (numeric JSON ids, as GitHub returns them) and
# the real `unzip` and `jq`. The fake REFUSES (exit 64) any request it did not expect, so a fetch that
# reaches for a repo-wide listing, or drops --paginate, fails instead of passing.
# SECTION B parses the workflow with PyYAML (the bare key `on` loads as boolean True) and asserts the
# step skeleton by EXACT equality, never by substring; each mutation row edits the PARSED structure and
# must turn the property that guards it RED. A mutant that does not differ from the pristine structure
# aborts the row.
#
# Reading of the plan: its outcome table (the contract) says a BOOTSTRAP run discards a corrupt NEWEST
# artifact so a poisoned artifact cannot wedge the monitor; a failed LISTING or DOWNLOAD is never masked.
# shellcheck disable=SC2016  # jq programs and workflow expressions are literal text
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

passes=0
fails=0
# APPEND-ONLY FAILURE LEDGER: the exit status reads this, not `fails == 0` alone.
FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }

# Instrument self-test: both verdict helpers must move their counters, or nothing below means anything.
_p0=$passes; _f0=$fails; _n0=${#FAILURES[@]}
{ pass; fail "self-test"; } 2>/dev/null
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ] || [ "${#FAILURES[@]}" -ne $((_n0 + 1)) ]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2
  exit 2
fi
passes=0; fails=0; FAILURES=()

eq() { # name actual expected
  if [ "$2" = "$3" ]; then pass; else fail "$1: got '$2', expected '$3'"; fi
}
has() { # name file fixed-string
  if grep -qF -- "$3" "$2"; then pass; else fail "$1: '$3' not found in $2"; fi
}
lacks() { # name file fixed-string
  if grep -qF -- "$3" "$2"; then fail "$1: '$3' unexpectedly present in $2"; else pass; fi
}

# The repo-wide path guard (byte-identical to every tracked copy): fixture roots are absolute or we stop.
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

# Verdict-owning helpers each get a control: called with an input that MUST fail, the failure counter
# has to move. The counters are unwound so the assertion floor stays exact.
ctl() { # helper args...
  local f0=$fails n0=${#FAILURES[@]}
  "$@" 2>/dev/null
  if [ "$fails" -ne $((f0 + 1)) ] || [ "${#FAILURES[@]}" -ne $((n0 + 1)) ]; then
    printf '[FATAL] instrument control: %s did not record a failure on a must-fail input\n' "$1" >&2
    exit 2
  fi
  fails=$f0
  FAILURES=("${FAILURES[@]:0:$n0}")
}
ctl eq ctl-eq a b
ctl has ctl-has /nonexistent/path/for/the/control x
ctl lacks ctl-lacks "${BASH_SOURCE[0]}" "set -uo pipefail"

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SUT="$REPO_ROOT/scripts/monitor-streak-state.sh"
PROBE="$REPO_ROOT/scripts/followthroughs/t5-skip-persistence-bound-7510.sh"
WF="$REPO_ROOT/.github/workflows/scheduled-rehearsal-skip-monitor.yml"

for tool in jq unzip python3 timeout; do
  command -v "$tool" >/dev/null 2>&1 || { printf '[FATAL] %s not found\n' "$tool" >&2; exit 2; }
done
python3 -c 'import yaml' 2>/dev/null || { echo "[FATAL] python3 has no PyYAML module" >&2; exit 2; }
[ -x "$SUT" ] || { printf '[FATAL] %s is missing or not executable\n' "$SUT" >&2; exit 2; }
[ -r "$PROBE" ] || { printf '[FATAL] probe not readable at %s\n' "$PROBE" >&2; exit 2; }
[ -r "$WF" ] || { printf '[FATAL] workflow not readable at %s\n' "$WF" >&2; exit 2; }

SANDBOX=$(mktemp -d -t streakstate.XXXXXXXX) || { echo "[FATAL] could not create sandbox" >&2; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT

# ─────────────────────────────────────────────────────────────────────────────
# SECTION A — the script
# ─────────────────────────────────────────────────────────────────────────────

# fake gh: REFUSES anything it did not expect (exit 64); records argv.
FAKEGH="$SANDBOX/fake-gh"
cat > "$FAKEGH" <<'FAKE'
#!/usr/bin/env bash
d="${FAKE_GH_DIR:?}"
printf '%s\n' "$*" >> "$d/argv.log"
[ "${1:-}" = "api" ] || { echo "fake gh: only 'api' is served ($1)" >&2; exit 1; }
ep="${*: -1}"
case "$ep" in
  repos/o/r/actions/artifacts/[0-9]*/zip)
    id="${ep%/zip}"; id="${id##*/}"
    if [ -f "$d/dl.rc" ] && [ "$(cat "$d/dl.rc")" != 0 ]; then echo "download refused" >&2; exit "$(cat "$d/dl.rc")"; fi
    [ -f "$d/zip.$id" ] || { echo "fake gh: no zip for $id" >&2; exit 64; }
    cat "$d/zip.$id" ;;
  "repos/o/r/actions/artifacts?name=rehearsal-skip-monitor-streak&per_page=100")
    case " $* " in *" --paginate "*) ;; *) echo "fake gh: list without --paginate" >&2; exit 64 ;; esac
    if [ -n "${FAKE_LIST_SLEEP:-}" ]; then sleep "$FAKE_LIST_SLEEP"; fi
    cat "$d/list.body"
    exit "$(cat "$d/list.rc" 2>/dev/null || echo 0)" ;;
  *) echo "fake gh: unexpected endpoint: $ep" >&2; exit 64 ;;
esac
FAKE
chmod +x "$FAKEGH"

# member/content pairs; content may be `hex:<bytes>` or `bomb:<n>` (an n-byte bzip2 member).
cat > "$SANDBOX/mkzip.py" <<'PY'
import sys, zipfile
out, pairs = sys.argv[1], sys.argv[2:]
with zipfile.ZipFile(out, "w") as z:
    for i in range(0, len(pairs), 2):
        name, content = pairs[i], pairs[i + 1]
        comp = zipfile.ZIP_STORED
        if content.startswith("hex:"):
            data = bytes.fromhex(content[4:])
        elif content.startswith("bomb:"):
            data = b"0" * int(content[5:])
            comp = zipfile.ZIP_BZIP2
        else:
            data = content.encode()
        zi = zipfile.ZipInfo(name)
        zi.compress_type = comp
        z.writestr(zi, data)
PY
mkzip() { python3 -I "$SANDBOX/mkzip.py" "$@"; } # out member content [member content ...]

# art id run_id branch head_repo_id repo_id size expired created_at
art() {
  jq -nc --argjson id "$1" --argjson run "$2" --arg br "$3" --argjson hr "$4" --argjson r "$5" \
     --argjson sz "$6" --argjson ex "$7" --arg cr "$8" \
     '{id:$id,node_id:"x",name:"rehearsal-skip-monitor-streak",size_in_bytes:$sz,url:"u",expired:$ex,created_at:$cr,
       workflow_run:{id:$run,repository_id:$r,head_repository_id:$hr,head_branch:$br}}'
}
good() { art "$1" "$2" main 1000 1000 8 false "${3:-2026-10-20T06:00:00Z}"; } # id run_id [created_at]
setlist() { assert_fixture_dir "$C"; printf '{"total_count":%s,"artifacts":[%s]}\n' "$#" "$(IFS=,; echo "$*")" > "$C/list.body"; }
setpages() { # one JSON array of artifacts per argument => one listing document per page, concatenated
  assert_fixture_dir "$C"
  : > "$C/list.body"
  local page
  for page in "$@"; do jq -nc --argjson a "$page" '{total_count:($a|length),artifacts:$a}' >> "$C/list.body"; done
}

n=0
newcase() {
  n=$((n + 1)); C="$SANDBOX/case$n"
  mkdir -p "$C/bin" "$C/state"
  cp "$FAKEGH" "$C/bin/gh"
  : > "$C/argv.log"
  printf '0' > "$C/list.rc"
}

ULIM=unlimited
# runsut <subcommand> [VAR=value ...]  -- RC, $C/log, $C/gho
runsut() {
  local sub="$1"; shift
  : > "$C/gho"; rm -rf "$C/state"; mkdir -p "$C/state"
  ( ulimit -f "$ULIM" 2>/dev/null
    cd "$C" && env -i PATH="$C/bin:$PATH" HOME="$C" FAKE_GH_DIR="$C" \
      GH_TOKEN=fake GITHUB_REPOSITORY=o/r GITHUB_REPOSITORY_ID=1000 GITHUB_RUN_ID=5000 \
      GITHUB_ACTOR=tester STREAK_ARTIFACT_NAME=rehearsal-skip-monitor-streak \
      STREAK_BRANCH=main STREAK_FILE="$C/state/dir/streak" GITHUB_OUTPUT="$C/gho" \
      "$@" bash "$SUT" "$sub" ) > "$C/log" 2>&1
  RC=$?
}
out_value() { # key -> last value of `key=` in $GITHUB_OUTPUT, or "none"
  local m; m=$(sed -n "s/^$1=\(.*\)\$/\1/p" "$C/gho" | tail -n 1)
  printf '%s' "${m:-none}"
}
matched() { out_value matched; }
streakfile() { if [ -f "$C/state/dir/streak" ]; then cat "$C/state/dir/streak"; else printf '<absent>'; fi; }

# One scenario under both BOOTSTRAP settings:
#   expect_fetch <name> <rc_plain> <matched_plain> <rc_boot> <matched_boot> [file_plain file_boot]
# Every run also pins the output contract: exactly one `matched=` line on success, none on failure
# (two lines would let the later one win in Actions), and `restored=` equal to the restored value.
expect_fetch() {
  local name="$1" mode rc_want m_want f_want
  for mode in plain boot; do
    if [ "$mode" = plain ]; then
      runsut fetch BOOTSTRAP=; rc_want="$2"; m_want="$3"; f_want="${6:-}"
    else
      runsut fetch BOOTSTRAP=true; rc_want="$4"; m_want="$5"; f_want="${7:-}"
    fi
    eq "$name ($mode) rc" "$RC" "$rc_want"
    eq "$name ($mode) matched" "$(matched)" "$m_want"
    if [ "$rc_want" = 0 ]; then
      eq "$name ($mode) exactly one matched line" "$(grep -c '^matched=' "$C/gho")" "1"
    else
      eq "$name ($mode) no matched line on failure" "$(grep -c '^matched=' "$C/gho")" "0"
    fi
    if [ -n "$f_want" ]; then
      eq "$name ($mode) value" "$(streakfile)" "$f_want"
      if [ "$f_want" != "<absent>" ]; then eq "$name ($mode) restored output" "$(out_value restored)" "$f_want"; fi
    fi
  done
}

# T1 empty list; T2 only expired; T3 only other-branch; T4 only run ids at or above this run
newcase; setlist
expect_fetch "T1 empty list" 0 false 0 false "<absent>" "<absent>"
newcase; setlist "$(art 11 4000 main 1000 1000 8 true 2026-10-20T06:00:00Z)"
expect_fetch "T2 only expired" 0 false 0 false
newcase; setlist "$(art 11 4000 feature/x 1000 1000 8 false 2026-10-20T06:00:00Z)"
expect_fetch "T3 only other branch" 0 false 0 false
newcase; setlist "$(good 11 5000)" "$(good 12 5001)" "$(good 13 9999)"
mkzip "$C/zip.11" streak 2; mkzip "$C/zip.12" streak 2; mkzip "$C/zip.13" streak 2
expect_fetch "T4 run id equal or higher than this run (own earlier attempt, re-run of an older run)" 0 false 0 false

# T5 highest run id below this one wins, whatever the listing order, created_at or artifact id
newcase; setlist "$(good 11 4001 2026-10-19T06:00:00Z)" "$(good 12 4002 2026-10-18T06:00:00Z)"
mkzip "$C/zip.11" streak 1; mkzip "$C/zip.12" streak 2
expect_fetch "T5 newest run id wins over a later created_at" 0 true 0 true 2 2
newcase; setlist "$(good 12 4002 2026-10-18T06:00:00Z)" "$(good 11 4001 2026-10-19T06:00:00Z)"
mkzip "$C/zip.11" streak 1; mkzip "$C/zip.12" streak 2
expect_fetch "T5b listing order does not decide" 0 true 0 true 2 2
newcase; setlist "$(good 21 4002)" "$(good 22 4001)"
mkzip "$C/zip.21" streak 2; mkzip "$C/zip.22" streak 1
expect_fetch "T5c the newest RUN wins even with the lower artifact id" 0 true 0 true 2 2
newcase
setpages "[$(good 31 4001)]" "[$(good 32 4003)]" "[$(good 33 4002)]"
mkzip "$C/zip.31" streak 1; mkzip "$C/zip.32" streak 3; mkzip "$C/zip.33" streak 2
expect_fetch "T5d the newest eligible artifact on a later page wins (pagination)" 0 true 0 true 3 3

# T6 decoys: each is newer and larger than the real artifact and must be ignored
newcase
setlist "$(good 11 4001)" \
        "$(art 12 4005 feature/x 1000 1000 8 false 2026-10-22T06:00:00Z)" \
        "$(art 13 4006 main 7777 1000 8 false 2026-10-22T06:00:00Z)" \
        "$(art 14 4007 main 1000 1000 5000 false 2026-10-22T06:00:00Z)" \
        "$(art 15 4008 main 1000 999 8 false 2026-10-22T06:00:00Z)" \
        '{"id":16,"name":"rehearsal-skip-monitor-streak","size_in_bytes":8,"expired":false,"created_at":"2026-10-22T06:00:00Z","workflow_run":null}' \
        '{"id":17,"name":"rehearsal-skip-monitor-streak","size_in_bytes":8,"expired":false}'
for i in 11 12 13 14 15 16 17; do mkzip "$C/zip.$i" streak 3; done
mkzip "$C/zip.11" streak 1
expect_fetch "T6 decoys (other branch, fork head repo, oversize, foreign repo id, null workflow_run, no workflow_run)" 0 true 0 true 1 1
# T6b a missing or null field is never read as eligible: every decoy is otherwise valid and newest
newcase
setlist "$(good 11 4001)" \
        "$(good 12 4005 | jq -c 'del(.expired)')" \
        "$(good 13 4006 | jq -c 'del(.size_in_bytes)')" \
        "$(good 14 4007 | jq -c 'del(.workflow_run.head_repository_id)')" \
        "$(good 15 4008 | jq -c 'del(.workflow_run.repository_id)')" \
        "$(good 16 4009 | jq -c '.workflow_run.id = null')" \
        "$(good 17 4010 | jq -c 'del(.workflow_run.head_branch)')" \
        "$(good 18 4011 | jq -c '.workflow_run.id = "4011"')"
for i in 11 12 13 14 15 16 17 18; do mkzip "$C/zip.$i" streak 3; done
mkzip "$C/zip.11" streak 1
expect_fetch "T6b missing or null fields are ineligible" 0 true 0 true 1 1
newcase; setlist "$(good 11 4001 | jq -c '.workflow_run.id = null')"; mkzip "$C/zip.11" streak 2
expect_fetch "T6b2 a null run id is ineligible even when it is the only artifact (null sorts below every number)" 0 false 0 false
# T6c the size bound is inclusive at 4096
newcase; setlist "$(art 11 4001 main 1000 1000 4096 false 2026-10-20T06:00:00Z)"; mkzip "$C/zip.11" streak 2
expect_fetch "T6c size 4096 is eligible" 0 true 0 true 2 2
newcase; setlist "$(art 11 4001 main 1000 1000 4097 false 2026-10-20T06:00:00Z)"; mkzip "$C/zip.11" streak 2
expect_fetch "T6c size 4097 is not" 0 false 0 false

# T7 valid values, including a trailing newline; extra unknown fields in the listing are tolerated
for v in 3 0 12 999999 $'3\n'; do
  newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak "$v"
  want="${v%$'\n'}"
  expect_fetch "T7 value '$(printf %q "$v")'" 0 true 0 true "$want" "$want"
done
# T8 leading zeros are base 10, never octal
for pair in 08:8 007:7 09:9; do
  newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak "${pair%%:*}"
  expect_fetch "T8 value ${pair%%:*}" 0 true 0 true "${pair##*:}" "${pair##*:}"
done

# T9 malformed values: a plain run exits 1; a BOOTSTRAP run discards the corrupt NEWEST artifact
for v in abc "" "1 2" 1234567 1000000 -1 "  4 " $'1\nabc' '::error::PLANTEDVALUE' \
         "$(printf '5'; printf '\n%.0s' {1..40}; printf X)" hex:31002032 hex:310032 ZZPLANT1; do
  newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak "$v"
  expect_fetch "T9 malformed value '$(printf %q "${v:0:16}")'" 1 none 0 false "<absent>" "<absent>"
done
newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak ZZPLANT1
runsut fetch BOOTSTRAP=; lacks "T9a the malformed-value notice never carries the value it read (plain)" "$C/log" "ZZPLANT1"
runsut fetch BOOTSTRAP=true; lacks "T9a the malformed-value notice never carries the value it read (bootstrap)" "$C/log" "ZZPLANT1"
newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak 2 other 9
expect_fetch "T9b two-member archive" 1 none 0 false
# T9c only the literal BOOTSTRAP=true reseeds: false, 1, True, yes behave like unset
for b in false 1 True yes; do
  newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak abc
  runsut fetch "BOOTSTRAP=$b"
  eq "T9c BOOTSTRAP=$b does not discard a corrupt artifact (rc)" "$RC" "1"
  eq "T9c BOOTSTRAP=$b does not discard a corrupt artifact (matched)" "$(matched)" "none"
done
# T9d decompression bomb: a 20 MB bzip2 member in a tiny archive. The read is bounded, so the file-size
# limit (64 KB) is never hit and the run ends in the MALFORMED path, not the unreadable-member path.
newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak bomb:20000000
ULIM=64
expect_fetch "T9d decompression bomb" 1 none 0 false "<absent>" "<absent>"
runsut fetch BOOTSTRAP=
has "T9d the bomb is read through a bounded pipe (malformed, not unreadable)" "$C/log" "malformed streak value"
lacks "T9d the member was not reported unreadable" "$C/log" "member unreadable"
ULIM=unlimited

# T10 listing failure is NEVER masked, by either BOOTSTRAP value, and never reads as "no artifact"
newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak 2; printf '1' > "$C/list.rc"
expect_fetch "T10 listing exits 1" 1 none 1 none
newcase; printf '<html>rate limited</html>\n' > "$C/list.body"
expect_fetch "T10 listing is HTML" 1 none 1 none
newcase; printf '{}\n' > "$C/list.body"
expect_fetch "T10 listing is {}" 1 none 1 none
newcase; : > "$C/list.body"
expect_fetch "T10 listing is empty body" 1 none 1 none
newcase; printf '{"artifacts":["x"]}\n' > "$C/list.body"
expect_fetch "T10d a non-object listing element is an unreadable store" 1 none 1 none
# T10e a hung listing is bounded and fatal (timeout 1s, fake gh sleeps 3s)
newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak 2
runsut fetch BOOTSTRAP=true FAKE_LIST_SLEEP=3 STREAK_LIST_TIMEOUT=1
eq "T10e hung listing rc (bootstrap does not mask it)" "$RC" "1"
has "T10e hung listing names the timeout" "$C/log" "timed out"

# T10c hostile zip members and workflow-command payloads: never extracted, never echoed
for m in '../streak' 'streak/' $'streak\nx' 'other'; do
  newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" "$m" 2
  expect_fetch "T10c member '$(printf %q "$m")'" 1 none 0 false "<absent>" "<absent>"
  case "$m" in *$'\n'*) ;; *) lacks "T10c log has no raw member name" "$C/log" "$m" ;; esac
done
newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak $'::stop-commands::PLANTEDVALUE\n::error::PLANTEDVALUE'
runsut fetch BOOTSTRAP=; lacks "T10c log never carries the raw artifact value (plain)" "$C/log" "PLANTEDVALUE"
runsut fetch BOOTSTRAP=true; lacks "T10c log never carries the raw artifact value (bootstrap)" "$C/log" "PLANTEDVALUE"

# T11 a failed DOWNLOAD is an unreadable store and fatal under both settings (bootstrap does not mask it);
# a body that is not an archive is corrupt content, which bootstrap discards
newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak 2; printf '7' > "$C/dl.rc"
expect_fetch "T11 download exits 7" 1 none 1 none
newcase; setlist "$(good 11 4001)"; printf 'not a zip' > "$C/zip.11"
expect_fetch "T11b download is not a zip" 1 none 0 false

# T12 endpoint shape: only the exact-name listing and the zip download, always paginated
newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak 1; runsut fetch BOOTSTRAP=
has "T12 listing uses the exact-name filter" "$C/argv.log" "api --paginate repos/o/r/actions/artifacts?name=rehearsal-skip-monitor-streak&per_page=100"
eq "T12 only two kinds of request" "$(grep -vcE '^api (--paginate repos/o/r/actions/artifacts\?name=rehearsal-skip-monitor-streak&per_page=100|repos/o/r/actions/artifacts/[0-9]+/zip)$' "$C/argv.log")" "0"
newcase; setlist; runsut fetch BOOTSTRAP=true
has "T12c bootstrap is audited in the log" "$C/log" "bootstrap by tester"

# T13 seal: verdict-aware, with the pre-probe baseline fetch restored (RESTORED)
runsut_seal() { # verdict content-or-@absent restored-or-@unset
  : > "$C/gho"; rm -rf "$C/state"; mkdir -p "$C/state/dir"
  if [ "$2" != "@absent" ]; then printf '%s' "$2" > "$C/state/dir/streak"; fi
  local args=()
  if [ "$3" != "@unset" ]; then args+=("RESTORED=$3"); fi
  ( cd "$C" && env -i PATH="$C/bin:$PATH" HOME="$C" STREAK_FILE="$C/state/dir/streak" VERDICT="$1" \
      "${args[@]}" bash "$SUT" seal ) > "$C/log" 2>&1
  RC=$?
}
seal_case() { # name verdict file-content-or-@absent restored-or-@unset expected-file-or-@fail
  newcase
  runsut_seal "$2" "$3" "$4"
  if [ "$5" = "@fail" ]; then eq "$1 rc" "$RC" "1"; else eq "$1 rc" "$RC" "0"; eq "$1 file" "$(streakfile)" "$5"; fi
}
seal_case "T13 pass+absent" pass @absent 0 0
seal_case "T13 pass+empty" pass "" 0 0
seal_case "T13 pass forces 0 over a surviving file" pass 5 5 0
seal_case "T13 pass+x" pass x 0 @fail
seal_case "T13 fail+absent (a real FAIL cleared the file)" fail @absent 2 0
seal_case "T13 fail keeps an escalation streak" fail 3 2 3
seal_case "T13 broken+absent keeps the restored value" broken @absent 2 2
seal_case "T13 broken+empty keeps the restored value (probe killed mid-write)" broken "" 2 2
seal_case "T13 broken keeps a valid file" broken 4 2 4
seal_case "T13 broken+absent with nothing restored" broken @absent 0 0
seal_case "T13 transient+absent (lost increment)" transient @absent 0 @fail
seal_case "T13 transient+empty" transient "" 0 @fail
seal_case "T13 transient+0 with nothing restored (no increment)" transient 0 0 @fail
seal_case "T13 transient 0->1" transient 1 0 1
seal_case "T13 transient 1->2" transient 2 1 2
seal_case "T13 transient 2->2 (a restored streak with a lost increment)" transient 2 2 @fail
seal_case "T13 transient 2->5 (a jump)" transient 5 2 @fail
seal_case "T13 transient+007 normalises to base 10" transient 007 6 7
seal_case "T13 transient with RESTORED unset reads 0" transient 1 @unset 1
seal_case "T13 RESTORED not a number" transient 1 abc @fail
seal_case "T13 RESTORED not a number, pass verdict" pass 0 abc @fail
seal_case "T13 unknown verdict" weird 1 0 @fail
seal_case "T13 empty verdict" "" 1 0 @fail

# T14 assert: passes only for MATCHED=true or the literal BOOTSTRAP=true
assert_case() { # name matched bootstrap file expected-rc
  newcase; mkdir -p "$C/state/dir"
  if [ "$4" != "@absent" ]; then printf '%s' "$4" > "$C/state/dir/streak"; fi
  local args=()
  if [ "$2" != "@unset" ]; then args+=("MATCHED=$2"); fi
  if [ "$3" != "@unset" ]; then args+=("BOOTSTRAP=$3"); fi
  ( cd "$C" && env -i PATH="$C/bin:$PATH" HOME="$C" STREAK_FILE="$C/state/dir/streak" "${args[@]}" \
      bash "$SUT" assert ) > "$C/log" 2>&1
  RC=$?
  eq "$1" "$RC" "$5"
}
for m in true false @unset; do
  for b in true false 1 True yes @unset; do
    want=1; { [ "$m" = true ] || [ "$b" = true ]; } && want=0
    assert_case "T14 assert MATCHED=$m BOOTSTRAP=$b" "$m" "$b" 3 "$want"
  done
done
assert_case "T14b assert with a non-numeric sealed file" true @unset x 1
assert_case "T14c assert with a missing sealed file" true @unset @absent 1
assert_case "T14d assert prints the restored state" true @unset 3 0
has "T14d assert prints the restored line" "$C/log" "streak state: restored=true value=3"
assert_case "T14e assert on an empty store" false @unset 0 1
has "T14e an empty store says there is no prior generation" "$C/log" "no prior generation"
assert_case "T14f assert when fetch produced no result" @unset @unset 0 1
has "T14f a missing fetch result names the fetch step, not an empty store" "$C/log" "fetch step produced no result"

# unknown or missing subcommand exits non-zero (a no-op that exits 0 is the dispatch mutant)
newcase
( cd "$C" && env -i PATH="$C/bin:$PATH" bash "$SUT" bogus ) > "$C/log" 2>&1; eq "T8x unknown subcommand" "$?" "2"
( cd "$C" && env -i PATH="$C/bin:$PATH" bash "$SUT" ) > "$C/log" 2>&1; eq "T8y no subcommand" "$?" "2"

# T15 end-to-end chain: a restored 2 reaches the REAL probe, which (gh broken) escalates to 3/3; the
# probe's write then passes seal, and the result is 3.
chain() { # restored-value|@none  ->  CHAIN_RC of the probe, log in $C/probe.log
  newcase
  if [ "$1" = "@none" ]; then setlist; else setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak "$1"; fi
  runsut fetch BOOTSTRAP=true
  ( cd "$C" && env -i PATH="$C/bin:$PATH" HOME="$C" GH_TOKEN=fake T5_PROBE_STATE="$C/state/dir/streak" \
      bash "$PROBE" ) > "$C/probe.log" 2>&1
  CHAIN_RC=$?
}
chain 2
eq "T15 restored 2 escalates (rc)" "$CHAIN_RC" "1"
has "T15 restored 2 reaches the real probe as 3/3" "$C/probe.log" "consecutive transient runs: 3/3"
runsut_seal fail "$(cat "$C/state/dir/streak")" 2
eq "T15 the escalation FAIL keeps its streak through seal" "$(streakfile)" "3"
chain @none
eq "T15 no restored state starts at 1/3 (rc)" "$CHAIN_RC" "2"
has "T15 no restored state starts at 1/3" "$C/probe.log" "consecutive transient runs: 1/3"
runsut_seal transient "$(cat "$C/state/dir/streak")" 0
eq "T15 seal accepts the probe's first increment from nothing" "$(streakfile)" "1"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION B — workflow wiring (parsed YAML, exact equality)
# ─────────────────────────────────────────────────────────────────────────────
WIRING="$SANDBOX/wiring.py"
cat > "$WIRING" <<'PY'
import copy, re, sys
import yaml

SF = "${{ runner.temp }}/monitor-state/streak"
STATUS = "${{ !cancelled() }}"
BOOT = "${{ github.event_name == 'workflow_dispatch' && inputs.bootstrap }}"
UPLOAD_IF = ("${{ !cancelled() && github.ref == format('refs/heads/{0}', env.STREAK_BRANCH) "
             "&& steps.fetch.outcome == 'success' && steps.seal.outcome == 'success' }}")
PROBE_LINE = re.compile(r"^\s*timeout 600 bash scripts/followthroughs/t5-skip-persistence-bound-7510\.sh( \\)?$", re.M)
ARMS = [r"^\s*0\) verdict=pass ;;$", r"^\s*1\) verdict=fail ;;$", r"^\s*2\) verdict=transient ;;$",
        r"^\s*\*\) verdict=broken ;;$"]
PROPS = ("P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9")


def load(path):
    with open(path) as fh:
        return yaml.safe_load(fh)


def steps_of(d):
    return d["jobs"]["monitor"]["steps"]


def by_id(d, sid):
    for i, s in enumerate(steps_of(d)):
        if s.get("id") == sid:
            return i, s
    return -1, None


def on_of(d):
    return d.get("on") if d.get("on") is not None else d.get(True)


def check(path, script_path):
    out = []

    def rec(pid, ok, detail=""):
        out.append("%s %s %s" % ("ok" if ok else "bad", pid, detail))

    try:
        d = load(path)
        steps = steps_of(d)
        script = open(script_path).read()
    except Exception as exc:
        return ["bad %s workflow did not parse (%s)" % (p, str(exc).splitlines()[0] if str(exc) else "?") for p in PROPS]

    def sget(sid, key, default=None):
        s = by_id(d, sid)[1] or {}
        return s.get(key, default)

    # P1 no evictable store
    cache = [s.get("uses", "") for s in steps if "actions/cache" in str(s.get("uses", ""))]
    rec("P1", not cache, "cache steps: %s" % cache)

    # P2 order fetch < probe < seal < assert < upload, each id once
    ids = [s.get("id") for s in steps]
    idx = [by_id(d, k)[0] for k in ("fetch", "probe", "seal", "assert", "upload")]
    rec("P2", all(i >= 0 for i in idx) and idx == sorted(idx) and all(ids.count(k) == 1 for k in ("fetch", "probe", "seal", "assert", "upload")),
        "indices=%s" % idx)

    # P3 the state steps always run and cannot fail open
    bad = [k for k in ("fetch", "probe", "seal", "assert") if sget(k, "if") != STATUS or "continue-on-error" in (by_id(d, k)[1] or {})]
    job = d["jobs"]["monitor"]
    bad += ["job" for k in ("if", "continue-on-error") if k in job]
    rec("P3", not bad, "steps with a wrong status function or continue-on-error: %s" % bad)

    # P4 the five STREAK_FILE occurrences equal the one expected, absolute path with no hidden segment
    vals = [(sget("probe", "env") or {}).get("T5_PROBE_STATE")]
    for k in ("fetch", "seal", "assert"):
        vals.append((sget(k, "env") or {}).get("STREAK_FILE"))
    vals.append((sget("upload", "with") or {}).get("path"))
    hidden = any(seg.startswith(".") for v in vals if v for seg in str(v).split("/") if seg not in ("", "."))
    rec("P4", vals == [SF] * 5 and not hidden, "values=%s" % vals)

    # P5 upload gating and strictness, by exact equality
    up = by_id(d, "upload")[1] or {}
    want_with = {"name": "${{ env.STREAK_ARTIFACT_NAME }}", "path": SF, "retention-days": 90,
                 "if-no-files-found": "error", "overwrite": True}
    rec("P5", up.get("if") == UPLOAD_IF and up.get("with") == want_with and "continue-on-error" not in up
        and re.match(r"actions/upload-artifact@[0-9a-f]{40}$", str(up.get("uses", ""))) is not None,
        "if=%r with=%r" % (up.get("if"), up.get("with")))

    # P6 bootstrap: the input shape, and a scheduled run cannot reach BOOTSTRAP=true
    inp = ((on_of(d).get("workflow_dispatch") or {}).get("inputs") or {}).get("bootstrap") or {}
    rec("P6", inp.get("type") == "boolean" and inp.get("default") is False
        and (sget("fetch", "env") or {}).get("BOOTSTRAP") == BOOT and (sget("assert", "env") or {}).get("BOOTSTRAP") == BOOT,
        "input=%r" % inp)

    # P7 the probe invocation is live, bounded, and its verdict map and threshold are untouched
    run = str(sget("probe", "run", ""))
    every_env = "".join(str(s.get("env", "")) + str(s.get("run", "")) for s in steps) + str(d.get("env", ""))
    rec("P7", PROBE_LINE.search(run) is not None and all(re.search(a, run, re.M) for a in ARMS)
        and "T5_TRANSIENT_ESCALATE_AFTER" not in every_env,
        "probe invocation, verdict arms or threshold override")

    # P8 the step skeleton: exact commands, exact input wiring, exact workflow-level settings
    fetch_env = {"GH_TOKEN": "${{ secrets.GITHUB_TOKEN }}", "GITHUB_REPOSITORY_ID": "${{ github.repository_id }}",
                 "STREAK_FILE": SF, "BOOTSTRAP": BOOT}
    seal_env = {"STREAK_FILE": SF, "VERDICT": "${{ steps.probe.outputs.verdict }}",
                "RESTORED": "${{ steps.fetch.outputs.restored }}"}
    assert_env = {"MATCHED": "${{ steps.fetch.outputs.matched }}", "STREAK_FILE": SF, "BOOTSTRAP": BOOT}
    sched = on_of(d).get("schedule")
    rec("P8", sget("fetch", "run") == "bash scripts/monitor-streak-state.sh fetch" and sget("fetch", "env") == fetch_env
        and sget("seal", "run") == "bash scripts/monitor-streak-state.sh seal" and sget("seal", "env") == seal_env
        and sget("assert", "run") == "bash scripts/monitor-streak-state.sh assert" and sget("assert", "env") == assert_env
        and (sget("probe", "env") or {}) == {"GH_TOKEN": "${{ secrets.GITHUB_TOKEN }}", "T5_PROBE_STATE": SF}
        and d.get("env") == {"STREAK_ARTIFACT_NAME": "rehearsal-skip-monitor-streak", "STREAK_BRANCH": "main"}
        and d.get("permissions") == {"contents": "read", "issues": "write", "actions": "read"}
        and sched == [{"cron": "0 6 * * *"}] and "workflow_dispatch" in on_of(d),
        "skeleton differs from the expected step/env/permissions/trigger wiring")

    # P9 the state file's basename is the one zip member the script requires
    m = re.search(r"printf '([A-Za-z0-9._-]+)\\n' > \"\$tmp/members\.want\"", script)
    rec("P9", bool(m) and SF.rsplit("/", 1)[-1] == m.group(1), "member literal=%r" % (m.group(1) if m else None))
    return out


def dump(d, path):
    with open(path, "w") as fh:
        yaml.safe_dump(d, fh, sort_keys=False)


def mutate(name, src, dst):
    d = load(src)
    orig = copy.deepcopy(d)
    steps = steps_of(d)
    i_assert, st_assert = by_id(d, "assert")
    i_up, st_up = by_id(d, "upload")
    st_fetch, st_seal, st_probe = by_id(d, "fetch")[1], by_id(d, "seal")[1], by_id(d, "probe")[1]
    on = on_of(d)
    M = {
        "m1-cache": lambda: steps.append({"name": "x", "uses": "actions/cache/restore@" + "0" * 40}),
        "m1b-plain-cache": lambda: steps.append({"name": "x", "uses": "actions/cache@" + "0" * 40}),
        "m2-order": lambda: steps.insert(i_assert, steps.pop(i_up)),
        "m3-assert-status": lambda: st_assert.__setitem__("if", "${{ true }}"),
        "m3-seal-status": lambda: st_seal.__setitem__("if", "${{ true }}"),
        "m3-fetch-status": lambda: st_fetch.__setitem__("if", "${{ true }}"),
        "m3-probe-status": lambda: st_probe.__setitem__("if", "${{ true }}"),
        "m3b-assert-continue": lambda: st_assert.__setitem__("continue-on-error", True),
        "m3c-job-continue": lambda: d["jobs"]["monitor"].__setitem__("continue-on-error", True),
        "m4-hidden": lambda: st_probe["env"].__setitem__("T5_PROBE_STATE", "${{ runner.temp }}/.monitor-state/streak"),
        "m5-default-true": lambda: on["workflow_dispatch"]["inputs"]["bootstrap"].__setitem__("default", True),
        "m5-no-event-guard": lambda: st_fetch["env"].__setitem__("BOOTSTRAP", "${{ inputs.bootstrap }}"),
        "m5b-assert-bootstrap-or": lambda: st_assert["env"].__setitem__(
            "BOOTSTRAP", st_assert["env"]["BOOTSTRAP"].replace(" }}", " || inputs.bootstrap }}")),
        "m6-no-seal-gate": lambda: st_up.__setitem__("if", st_up["if"].replace(" && steps.seal.outcome == 'success'", "")),
        "m6-no-fetch-gate": lambda: st_up.__setitem__("if", st_up["if"].replace(" && steps.fetch.outcome == 'success'", "")),
        "m6-no-ref-gate": lambda: st_up.__setitem__("if", re.sub(r" && github\.ref == format\([^)]*\)", "", st_up["if"])),
        "m6-continue-on-error": lambda: st_up.__setitem__("continue-on-error", True),
        "m6-warn": lambda: st_up["with"].__setitem__("if-no-files-found", "warn"),
        "m6c-upload-or-true": lambda: st_up.__setitem__("if", st_up["if"].replace(" }}", " || true }}")),
        "m6d-upload-not-schedule": lambda: st_up.__setitem__("if", st_up["if"].replace(" }}", " && github.event_name != 'schedule' }}")),
        "m6e-retention": lambda: st_up["with"].__setitem__("retention-days", 1),
        "m6f-upload-path": lambda: st_up["with"].__setitem__("path", "${{ runner.temp }}/monitor-state/other"),
        "m6g-pin": lambda: st_up.__setitem__("uses", "actions/upload-artifact@v4"),
        "m6b-no-timeout": lambda: st_probe.__setitem__("run", st_probe["run"].replace("timeout 600 bash scripts", "bash scripts")),
        "m6h-commented-probe": lambda: st_probe.__setitem__("run", st_probe["run"].replace("timeout 600 bash scripts", "# timeout 600 bash scripts")),
        "m6i-verdict-arm": lambda: st_probe.__setitem__("run", st_probe["run"].replace("2) verdict=transient ;;", "2) verdict=pass ;;")),
        "m6j-escalation-env": lambda: st_probe["env"].__setitem__("T5_TRANSIENT_ESCALATE_AFTER", "999999"),
        "m7-delete-upload": lambda: steps.pop(i_up),
        "m8-assert-run-true": lambda: st_assert.__setitem__("run", "true"),
        "m8b-matched-hardcoded": lambda: st_assert["env"].__setitem__("MATCHED", "true"),
        "m8c-seal-verdict-pass": lambda: st_seal["env"].__setitem__("VERDICT", "pass"),
        "m8d-seal-no-restored": lambda: st_seal["env"].pop("RESTORED"),
        "m8e-fetch-or-true": lambda: st_fetch.__setitem__("run", st_fetch["run"] + " || true"),
        "m8f-no-schedule": lambda: on.pop("schedule"),
        "m8g-permissions": lambda: d["permissions"].__setitem__("contents", "write"),
        "benign": lambda: steps.append({"name": "Unrelated trailing step", "run": "true"}),
    }
    if name not in M:
        sys.exit("unknown mutation %s" % name)
    M[name]()
    if d == orig:
        sys.exit("mutation %s did NOT land" % name)
    dump(d, dst)


if __name__ == "__main__":
    if sys.argv[1] == "check":
        print("\n".join(check(sys.argv[2], sys.argv[3])))
    elif sys.argv[1] == "mutate":
        mutate(sys.argv[2], sys.argv[3], sys.argv[4])
PY

NPROPS=9
wiring_check() { python3 -I "$WIRING" check "$1" "$SUT" 2>"$SANDBOX/wiring.err"; }

PRISTINE_OUT=$(wiring_check "$WF")
eq "B1 pristine workflow reports exactly $NPROPS property lines" "$(printf '%s\n' "$PRISTINE_OUT" | grep -c '^\(ok\|bad\) P')" "$NPROPS"
for p in P1 P2 P3 P4 P5 P6 P7 P8 P9; do
  line=$(printf '%s\n' "$PRISTINE_OUT" | grep "^[a-z]* $p " || true)
  case "$line" in
    "ok $p "*) pass ;;
    *) fail "B1 property $p is not green on the workflow: ${line:-<no line>}" ;;
  esac
done

# mutation rows: <mutation> <property that must go bad>
mrow() {
  local m="$1" prop="$2" mf="$SANDBOX/mut-$1.yml" out line
  if ! python3 -I "$WIRING" mutate "$m" "$WF" "$mf" 2>"$SANDBOX/mut.err"; then
    fail "B2 mutation $m did not land: $(head -c 200 "$SANDBOX/mut.err")"; return
  fi
  out=$(wiring_check "$mf")
  line=$(printf '%s\n' "$out" | grep "^[a-z]* $prop " || true)
  case "$line" in
    "bad $prop "*) pass ;;
    *) fail "B2 mutation $m left property $prop green: ${line:-<no line>}" ;;
  esac
}
ctl mrow bogus-mutation P1
mrow m1-cache P1
mrow m1b-plain-cache P1
mrow m2-order P2
mrow m7-delete-upload P2
mrow m3-assert-status P3
mrow m3-seal-status P3
mrow m3-fetch-status P3
mrow m3-probe-status P3
mrow m3b-assert-continue P3
mrow m3c-job-continue P3
mrow m4-hidden P4
mrow m6f-upload-path P4
mrow m6-no-seal-gate P5
mrow m6-no-fetch-gate P5
mrow m6-no-ref-gate P5
mrow m6-continue-on-error P5
mrow m6-warn P5
mrow m6c-upload-or-true P5
mrow m6d-upload-not-schedule P5
mrow m6e-retention P5
mrow m6g-pin P5
mrow m5-default-true P6
mrow m5-no-event-guard P6
mrow m5b-assert-bootstrap-or P6
mrow m6b-no-timeout P7
mrow m6h-commented-probe P7
mrow m6i-verdict-arm P7
mrow m6j-escalation-env P7
mrow m8-assert-run-true P8
mrow m8b-matched-hardcoded P8
mrow m8c-seal-verdict-pass P8
mrow m8d-seal-no-restored P8
mrow m8e-fetch-or-true P8
mrow m8f-no-schedule P8
mrow m8g-permissions P8

# must-PASS variant: an unrelated trailing step keeps every property green
python3 -I "$WIRING" mutate benign "$WF" "$SANDBOX/mut-benign.yml" 2>/dev/null
BENIGN_OUT=$(wiring_check "$SANDBOX/mut-benign.yml")
eq "B3 an unrelated trailing step keeps every property green" "$(printf '%s\n' "$BENIGN_OUT" | grep -c '^ok P')" "$NPROPS"

# harness row: a workflow that does not parse reports every property bad, never an empty "all clear"
printf 'not: [valid\n' > "$SANDBOX/broken.yml"
eq "B4 an unparseable workflow reports $NPROPS bad properties" "$(wiring_check "$SANDBOX/broken.yml" | grep -c '^bad P')" "$NPROPS"

# ─────────────────────────────────────────────────────────────────────────────
# verdict
# ─────────────────────────────────────────────────────────────────────────────
printf 'monitor-streak-state: %s passed, %s failed\n' "$passes" "$fails"
EXPECTED_MIN_PASSES=519
if [ "$passes" -lt "$EXPECTED_MIN_PASSES" ]; then
  printf 'FAIL: only %s assertions ran (floor %s): a suite that stopped asserting is not green\n' "$passes" "$EXPECTED_MIN_PASSES" >&2
  exit 1
fi
[ "${#FAILURES[@]}" -eq 0 ] || exit 1
exit 0
