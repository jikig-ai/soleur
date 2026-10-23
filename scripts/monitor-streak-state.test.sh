#!/usr/bin/env bash
# Suite for scripts/monitor-streak-state.sh and its wiring in
# .github/workflows/scheduled-rehearsal-skip-monitor.yml.
#
# WHY THIS EXISTS. The monitor's consecutive-TRANSIENT counter used to live in the Actions cache,
# which the release pipeline's BuildKit export keeps over its 10 GB cap, so the 192-byte entry was
# evicted daily and the round-trip assertion was red most days. The counter now lives in a workflow
# artifact. A store swap is only as good as its failure behaviour: an unreadable store, an empty
# store and a poisoned store must be three different outcomes, and a run that cannot prove it
# restored a numeric prior streak must go red. This suite pins that.
#
# SECTION A drives the script with a fake `gh` on PATH (numeric JSON ids, as GitHub returns them)
# and the real `unzip` and `jq`. The fake REFUSES (exit 64) any request it did not expect, so a
# fetch that reaches for a repo-wide listing, or drops --paginate, is a failure and not a pass.
# SECTION B parses the workflow with PyYAML (the bare key `on` loads as boolean True) and asserts
# structured properties, never a grep of the text; each mutation row edits the PARSED structure and
# must turn the property that guards it RED. A mutant that does not differ from the pristine
# structure is a harness defect and aborts.
#
# One deliberate reading of the plan: its scenario table says a malformed value exits 1 under both
# BOOTSTRAP values, its outcome table (written after the security and SpecFlow review) says a
# BOOTSTRAP run discards a corrupt NEWEST artifact so the documented reseed path cannot wedge. The
# outcome table is the contract and is what this suite pins; a failed LISTING is never masked.
# shellcheck disable=SC2016  # jq programs and workflow expressions are literal text
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

passes=0
fails=0
# APPEND-ONLY FAILURE LEDGER: the exit status reads this, not `fails == 0` alone, so moving a
# counter cannot silence a real failure.
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

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SUT="$REPO_ROOT/scripts/monitor-streak-state.sh"
PROBE="$REPO_ROOT/scripts/followthroughs/t5-skip-persistence-bound-7510.sh"
WF="$REPO_ROOT/.github/workflows/scheduled-rehearsal-skip-monitor.yml"

for tool in jq unzip python3 timeout; do
  command -v "$tool" >/dev/null 2>&1 || { printf '[FATAL] %s not found\n' "$tool" >&2; exit 2; }
done
python3 -c 'import yaml' 2>/dev/null || { echo "[FATAL] python3 has no PyYAML module" >&2; exit 2; }
[ -r "$PROBE" ] || { printf '[FATAL] probe not readable at %s\n' "$PROBE" >&2; exit 2; }

SANDBOX=$(mktemp -d -t streakstate.XXXXXXXX) || { echo "[FATAL] could not create sandbox" >&2; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT

# ─────────────────────────────────────────────────────────────────────────────
# SECTION A — the script
# ─────────────────────────────────────────────────────────────────────────────
if [ ! -x "$SUT" ]; then
  fail "A0: $SUT is missing or not executable (RED by design until the script exists)"
else
  pass
fi

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
    cat "$d/list.body"
    exit "$(cat "$d/list.rc" 2>/dev/null || echo 0)" ;;
  *) echo "fake gh: unexpected endpoint: $ep" >&2; exit 64 ;;
esac
FAKE
chmod +x "$FAKEGH"

cat > "$SANDBOX/mkzip.py" <<'PY'
import sys, zipfile
out = sys.argv[1]
pairs = sys.argv[2:]
with zipfile.ZipFile(out, "w") as z:
    for i in range(0, len(pairs), 2):
        z.writestr(zipfile.ZipInfo(pairs[i]), pairs[i + 1].encode())
PY
mkzip() { python3 -I "$SANDBOX/mkzip.py" "$@"; } # out member content [member content ...]

# art id run_id branch head_repo_id repo_id size expired created_at
art() {
  jq -nc --argjson id "$1" --argjson run "$2" --arg br "$3" --argjson hr "$4" --argjson r "$5" \
     --argjson sz "$6" --argjson ex "$7" --arg cr "$8" \
     '{id:$id,node_id:"x",name:"rehearsal-skip-monitor-streak",size_in_bytes:$sz,url:"u",expired:$ex,created_at:$cr,
       workflow_run:{id:$run,repository_id:$r,head_repository_id:$hr,head_branch:$br}}'
}
GOOD="main 1000 1000 8 false"   # branch head_repo repo size expired (a fully eligible artifact)
# shellcheck disable=SC2086
good() { art "$1" "$2" $GOOD "${3:-2026-10-20T06:00:00Z}"; } # id run_id [created_at]
setlist() { printf '{"total_count":%s,"artifacts":[%s]}\n' "$#" "$(IFS=,; echo "$*")" > "$C/list.body"; }

n=0
newcase() {
  n=$((n + 1)); C="$SANDBOX/case$n"
  mkdir -p "$C/bin" "$C/state"
  cp "$FAKEGH" "$C/bin/gh"
  : > "$C/argv.log"
  printf '0' > "$C/list.rc"
}

# runsut <subcommand> [VAR=value ...]  -- RC, $C/log, $C/gho
runsut() {
  local sub="$1"; shift
  : > "$C/gho"; rm -rf "$C/state"; mkdir -p "$C/state"
  ( cd "$C" && env -i PATH="$C/bin:$PATH" HOME="$C" FAKE_GH_DIR="$C" \
      GH_TOKEN=fake GITHUB_REPOSITORY=o/r GITHUB_REPOSITORY_ID=1000 GITHUB_RUN_ID=5000 \
      GITHUB_REF_NAME=main GITHUB_ACTOR=tester STREAK_ARTIFACT_NAME=rehearsal-skip-monitor-streak \
      STREAK_BRANCH=main STREAK_FILE="$C/state/dir/streak" GITHUB_OUTPUT="$C/gho" \
      "$@" bash "$SUT" "$sub" ) > "$C/log" 2>&1
  RC=$?
}
matched() { # prints true|false|none
  local m; m=$(sed -n 's/^matched=\(true\|false\)$/\1/p' "$C/gho" | tail -n 1)
  printf '%s' "${m:-none}"
}
streakfile() { if [ -f "$C/state/dir/streak" ]; then cat "$C/state/dir/streak"; else printf '<absent>'; fi; }

# One scenario, both BOOTSTRAP settings: expect_fetch <name> <rc_plain> <matched_plain> <rc_boot> <matched_boot> [file_plain file_boot]
expect_fetch() {
  local name="$1"
  runsut fetch BOOTSTRAP=
  eq "$name (plain) rc" "$RC" "$2"
  eq "$name (plain) matched" "$(matched)" "$3"
  [ -n "${6:-}" ] && eq "$name (plain) value" "$(streakfile)" "$6"
  runsut fetch BOOTSTRAP=true
  eq "$name (bootstrap) rc" "$RC" "$4"
  eq "$name (bootstrap) matched" "$(matched)" "$5"
  [ -n "${7:-}" ] && eq "$name (bootstrap) value" "$(streakfile)" "$7"
}

if [ -x "$SUT" ]; then
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

  # T5 highest run id below this one wins, whatever the listing order or created_at
  newcase; setlist "$(good 11 4001 2026-10-19T06:00:00Z)" "$(good 12 4002 2026-10-18T06:00:00Z)"
  mkzip "$C/zip.11" streak 1; mkzip "$C/zip.12" streak 2
  expect_fetch "T5 newest run id wins over a later created_at" 0 true 0 true 2 2
  newcase; setlist "$(good 12 4002 2026-10-18T06:00:00Z)" "$(good 11 4001 2026-10-19T06:00:00Z)"
  mkzip "$C/zip.11" streak 1; mkzip "$C/zip.12" streak 2
  expect_fetch "T5b listing order does not decide" 0 true 0 true 2 2

  # T6/T10b decoys: each is newer and larger than the real artifact and must be ignored
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
  expect_fetch "T6/T10b decoys (other branch, fork head repo, oversize, foreign repo id, null workflow_run, no workflow_run)" 0 true 0 true 1 1

  # T7 valid values, including a trailing newline; extra unknown fields in the listing are tolerated
  for v in 3 0 12 $'3\n'; do
    newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak "$v"
    want="${v%$'\n'}"
    expect_fetch "T7 value '$(printf %q "$v")'" 0 true 0 true "$want" "$want"
  done
  # T8 leading zeros are base 10, never octal
  for pair in 08:8 007:7 09:9; do
    newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak "${pair%%:*}"
    expect_fetch "T8 value ${pair%%:*}" 0 true 0 true "${pair##*:}" "${pair##*:}"
  done

  # T9 malformed values / shapes: plain run exits 1; a BOOTSTRAP run discards the corrupt NEWEST artifact
  for v in abc "" "1 2" 1234567 -1 "  4 " $'1\nabc' '::error::PLANTEDVALUE'; do
    newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak "$v"
    expect_fetch "T9 malformed value '$(printf %q "$v")'" 1 none 0 false "<absent>" "<absent>"
  done
  newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak 2 other 9
  expect_fetch "T9b two-member archive" 1 none 0 false
  # T9c only the literal BOOTSTRAP=true reseeds: false, 1, True, yes behave like unset (a corrupt
  # NEWEST artifact stays fatal), so a truthy-looking string cannot open the reseed path.
  for b in false 1 True yes; do
    newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak abc
    runsut fetch "BOOTSTRAP=$b"
    eq "T9c BOOTSTRAP=$b does not discard a corrupt artifact (rc)" "$RC" "1"
    eq "T9c BOOTSTRAP=$b does not discard a corrupt artifact (matched)" "$(matched)" "none"
  done

  # T10 listing failure is NEVER masked, by either BOOTSTRAP value, and never reads as "no artifact"
  newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak 2; printf '1' > "$C/list.rc"
  expect_fetch "T10 listing exits 1" 1 none 1 none
  newcase; printf '<html>rate limited</html>\n' > "$C/list.body"
  expect_fetch "T10 listing is HTML" 1 none 1 none
  newcase; printf '{}\n' > "$C/list.body"
  expect_fetch "T10 listing is {}" 1 none 1 none
  newcase; : > "$C/list.body"
  expect_fetch "T10 listing is empty body" 1 none 1 none

  # T10c hostile zip members and workflow-command payloads: never extracted, never echoed
  for m in '../streak' 'streak/' $'streak\nx' 'other'; do
    newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" "$m" 2
    expect_fetch "T10c member '$(printf %q "$m")'" 1 none 0 false "<absent>" "<absent>"
    lacks "T10c member log has no raw member name" "$C/log" "other"
  done
  newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak $'::stop-commands::PLANTEDVALUE\n::error::PLANTEDVALUE'
  runsut fetch BOOTSTRAP=; lacks "T10c log never carries the raw artifact value (plain)" "$C/log" "PLANTEDVALUE"
  runsut fetch BOOTSTRAP=true; lacks "T10c log never carries the raw artifact value (bootstrap)" "$C/log" "PLANTEDVALUE"

  # T11 download failure / missing member: fails closed, bootstrap discards
  newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak 2; printf '7' > "$C/dl.rc"
  expect_fetch "T11 download exits 7" 1 none 0 false
  newcase; setlist "$(good 11 4001)"; printf 'not a zip' > "$C/zip.11"
  expect_fetch "T11b download is not a zip" 1 none 0 false

  # endpoint shape: only the exact-name listing and the zip download, always paginated
  newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak 1; runsut fetch BOOTSTRAP=
  has "T12 listing uses the exact-name filter" "$C/argv.log" "api --paginate repos/o/r/actions/artifacts?name=rehearsal-skip-monitor-streak&per_page=100"
  eq "T12 only two kinds of request" "$(grep -vcE '^api (--paginate repos/o/r/actions/artifacts\?name=rehearsal-skip-monitor-streak&per_page=100|repos/o/r/actions/artifacts/[0-9]+/zip)$' "$C/argv.log")" "0"

  # branch notice and bootstrap notice
  newcase; setlist; runsut fetch BOOTSTRAP= GITHUB_REF_NAME=feature/x
  has "T12b a non-main ref says state is read from main and not written" "$C/log" "::notice::"
  newcase; setlist; runsut fetch BOOTSTRAP=true
  has "T12c bootstrap is audited in the log" "$C/log" "bootstrap by tester"

  # T13 seal: verdict-aware normalisation
  seal_case() { # name verdict file-content-or-@absent expected-file-or-@fail
    newcase; mkdir -p "$C/state/dir"
    runsut_seal "$2" "$3"
    if [ "$4" = "@fail" ]; then eq "$1 rc" "$RC" "1"; else eq "$1 rc" "$RC" "0"; eq "$1 file" "$(streakfile)" "$4"; fi
  }
  runsut_seal() { # verdict content-or-@absent
    : > "$C/gho"; rm -rf "$C/state"; mkdir -p "$C/state/dir"
    if [ "$2" != "@absent" ]; then printf '%s' "$2" > "$C/state/dir/streak"; fi
    ( cd "$C" && env -i PATH="$C/bin:$PATH" HOME="$C" STREAK_FILE="$C/state/dir/streak" VERDICT="$1" \
        bash "$SUT" seal ) > "$C/log" 2>&1
    RC=$?
  }
  seal_case "T13 pass+absent" pass @absent 0
  seal_case "T13 pass+empty" pass "" 0
  seal_case "T13 pass+5" pass 5 5
  seal_case "T13 pass+x" pass x @fail
  seal_case "T13 fail+absent" fail @absent 0
  seal_case "T13 broken+absent" broken @absent 0
  seal_case "T13 transient+absent (a lost increment)" transient @absent @fail
  seal_case "T13 transient+empty" transient "" @fail
  seal_case "T13 transient+0" transient 0 @fail
  seal_case "T13 transient+2" transient 2 2
  seal_case "T13 transient+007 normalises to base 10" transient 007 7
  seal_case "T13 unknown verdict" weird 1 @fail
  seal_case "T13 empty verdict" "" 1 @fail

  # T14 assert: passes only for MATCHED=true or the literal BOOTSTRAP=true
  assert_case() { # name matched bootstrap file expected-rc
    newcase; mkdir -p "$C/state/dir"
    if [ "$4" != "@absent" ]; then printf '%s' "$4" > "$C/state/dir/streak"; fi
    local args=()
    [ "$2" != "@unset" ] && args+=("MATCHED=$2")
    [ "$3" != "@unset" ] && args+=("BOOTSTRAP=$3")
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

  # unknown or missing subcommand exits non-zero (a no-op that exits 0 is the dispatch mutant)
  newcase
  ( cd "$C" && env -i PATH="$C/bin:$PATH" bash "$SUT" bogus ) > "$C/log" 2>&1; eq "T8x unknown subcommand" "$?" "2"
  ( cd "$C" && env -i PATH="$C/bin:$PATH" bash "$SUT" ) > "$C/log" 2>&1; eq "T8y no subcommand" "$?" "2"

  # Harness row (a): edit the SUITE's fake gh to return an empty list for a valid-artifact scenario;
  # the scenario that expects matched=true must go RED, proving the fixtures are consumed.
  newcase; setlist "$(good 11 4001)"; mkzip "$C/zip.11" streak 2
  printf '{"total_count":0,"artifacts":[]}\n' > "$C/list.body"
  runsut fetch BOOTSTRAP=
  if [ "$(matched)" = "true" ]; then fail "H-a fake gh edited to an empty list still produced matched=true: the fixtures are being bypassed"; else pass; fi

  # T15 end-to-end chain: a restored 2 reaches the REAL probe, which (gh broken) escalates to 3/3.
  # shellcheck disable=SC2016
  chain() { # restored-value|@none  ->  RC of the probe, log in $C/probe.log
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
  chain @none
  eq "T15 no restored state starts at 1/3 (rc)" "$CHAIN_RC" "2"
  has "T15 no restored state starts at 1/3" "$C/probe.log" "consecutive transient runs: 1/3"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION B — workflow wiring (parsed YAML)
# ─────────────────────────────────────────────────────────────────────────────
WIRING="$SANDBOX/wiring.py"
cat > "$WIRING" <<'PY'
import copy, re, sys
import yaml

SF = "${{ runner.temp }}/monitor-state/streak"


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


def cond(s):
    return str(s.get("if", "")) if s else ""


def check(path):
    out = []

    def rec(pid, ok, detail=""):
        out.append("%s %s %s" % ("ok" if ok else "bad", pid, detail))

    try:
        d = load(path)
        steps = steps_of(d)
    except Exception as exc:
        for pid in ("P1", "P2", "P3", "P4", "P5", "P6", "P7"):
            out.append("bad %s workflow did not parse (%s)" % (pid, str(exc).splitlines()[0] if str(exc) else "?"))
        return out

    # P1 no evictable store
    cache = [s.get("uses", "") for s in steps if "actions/cache" in str(s.get("uses", ""))]
    rec("P1", not cache, "cache steps: %s" % cache)

    # P2 order fetch < probe < seal < assert < upload
    idx = [by_id(d, k)[0] for k in ("fetch", "probe", "seal", "assert", "upload")]
    rec("P2", all(i >= 0 for i in idx) and idx == sorted(idx), "indices=%s" % idx)

    # P3 !cancelled() on each state step
    miss = [k for k in ("fetch", "probe", "seal", "assert") if "!cancelled()" not in cond(by_id(d, k)[1])]
    rec("P3", not miss, "missing !cancelled(): %s" % miss)

    # P4 the five STREAK_FILE occurrences are equal, absolute and not hidden
    vals = []
    vals.append((by_id(d, "probe")[1] or {}).get("env", {}).get("T5_PROBE_STATE"))
    for k in ("fetch", "seal", "assert"):
        vals.append((by_id(d, k)[1] or {}).get("env", {}).get("STREAK_FILE"))
    vals.append(((by_id(d, "upload")[1] or {}).get("with") or {}).get("path"))
    hidden = any(seg.startswith(".") for v in vals if v for seg in str(v).split("/") if seg not in ("", "."))
    rec("P4", len(set(vals)) == 1 and vals[0] == SF and not hidden, "values=%s" % vals)

    # P5 upload gating and strictness
    _, up = by_id(d, "upload")
    c = cond(up)
    w = (up or {}).get("with") or {}
    p5 = bool(up) and all(t in c for t in (
        "!cancelled()", "steps.fetch.outcome == 'success'", "steps.seal.outcome == 'success'",
        "github.ref == format('refs/heads/{0}', env.STREAK_BRANCH)"))
    p5 = p5 and "continue-on-error" not in up and w.get("if-no-files-found") == "error" \
        and w.get("overwrite") is True and w.get("retention-days") == 90 \
        and w.get("name") == "${{ env.STREAK_ARTIFACT_NAME }}" \
        and re.match(r"actions/upload-artifact@[0-9a-f]{40}$", str(up.get("uses", ""))) is not None
    rec("P5", p5, "if=%r with=%r" % (c, w))

    # P6 bootstrap input shape; a scheduled run cannot reach BOOTSTRAP=true
    inp = (((d.get("on") or d.get(True) or {}).get("workflow_dispatch") or {}).get("inputs") or {}).get("bootstrap") or {}
    be = str(((by_id(d, "fetch")[1] or {}).get("env") or {}).get("BOOTSTRAP", ""))
    ae = str(((by_id(d, "assert")[1] or {}).get("env") or {}).get("BOOTSTRAP", ""))
    ok6 = inp.get("type") == "boolean" and inp.get("default") is False \
        and "github.event_name == 'workflow_dispatch'" in be and "inputs.bootstrap" in be \
        and "github.event_name == 'workflow_dispatch'" in ae and "inputs.bootstrap" in ae
    rec("P6", ok6, "input=%r fetch=%r assert=%r" % (inp, be, ae))

    # P7 probe bounded
    run = str((by_id(d, "probe")[1] or {}).get("run", ""))
    rec("P7", re.search(r"(^|\s)timeout 600 bash scripts/followthroughs/t5-skip-persistence-bound-7510\.sh", run) is not None,
        "probe run lacks `timeout 600`")
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
    if name == "m1-cache":
        steps.append({"name": "x", "uses": "actions/cache/restore@" + "0" * 40})
    elif name == "m2-order":
        steps.insert(i_assert, steps.pop(i_up))
    elif name == "m3-assert-status":
        st_assert["if"] = "${{ true }}"
    elif name == "m3-seal-status":
        by_id(d, "seal")[1]["if"] = "${{ true }}"
    elif name == "m3-fetch-status":
        by_id(d, "fetch")[1]["if"] = "${{ true }}"
    elif name == "m4-hidden":
        by_id(d, "probe")[1]["env"]["T5_PROBE_STATE"] = "${{ runner.temp }}/.monitor-state/streak"
    elif name == "m5-default-true":
        (d.get("on") or d.get(True))["workflow_dispatch"]["inputs"]["bootstrap"]["default"] = True
    elif name == "m5-no-event-guard":
        by_id(d, "fetch")[1]["env"]["BOOTSTRAP"] = "${{ inputs.bootstrap }}"
    elif name == "m6-no-seal-gate":
        st_up["if"] = st_up["if"].replace(" && steps.seal.outcome == 'success'", "")
    elif name == "m6-no-fetch-gate":
        st_up["if"] = st_up["if"].replace(" && steps.fetch.outcome == 'success'", "")
    elif name == "m6-no-ref-gate":
        st_up["if"] = re.sub(r" && github\.ref == format\([^)]*\)", "", st_up["if"])
    elif name == "m6-continue-on-error":
        st_up["continue-on-error"] = True
    elif name == "m6-warn":
        st_up["with"]["if-no-files-found"] = "warn"
    elif name == "m6b-no-timeout":
        p = by_id(d, "probe")[1]
        p["run"] = p["run"].replace("timeout 600 bash scripts", "bash scripts")
    elif name == "m7-delete-upload":
        steps.pop(i_up)
    elif name == "benign":
        steps.append({"name": "Unrelated trailing step", "run": "true"})
    else:
        sys.exit("unknown mutation %s" % name)
    if d == orig:
        sys.exit("mutation %s did NOT land" % name)
    dump(d, dst)


if __name__ == "__main__":
    if sys.argv[1] == "check":
        print("\n".join(check(sys.argv[2])))
    elif sys.argv[1] == "mutate":
        mutate(sys.argv[2], sys.argv[3], sys.argv[4])
PY

NPROPS=7
wiring_check() { python3 -I "$WIRING" check "$1" 2>"$SANDBOX/wiring.err"; }

if [ ! -f "$WF" ]; then
  fail "B0: workflow missing at $WF"
else
  PRISTINE_OUT=$(wiring_check "$WF")
  eq "B1 pristine workflow reports exactly $NPROPS property lines" "$(printf '%s\n' "$PRISTINE_OUT" | grep -c '^\(ok\|bad\) P')" "$NPROPS"
  for p in P1 P2 P3 P4 P5 P6 P7; do
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
    eq "B2 mutation $m still reports $NPROPS property lines" "$(printf '%s\n' "$out" | grep -c '^\(ok\|bad\) P')" "$NPROPS"
    line=$(printf '%s\n' "$out" | grep "^[a-z]* $prop " || true)
    case "$line" in
      "bad $prop "*) pass ;;
      *) fail "B2 mutation $m left property $prop green: ${line:-<no line>}" ;;
    esac
  }
  mrow m1-cache P1
  mrow m2-order P2
  mrow m3-assert-status P3
  mrow m3-seal-status P3
  mrow m3-fetch-status P3
  mrow m4-hidden P4
  mrow m5-default-true P6
  mrow m5-no-event-guard P6
  mrow m6-no-seal-gate P5
  mrow m6-no-fetch-gate P5
  mrow m6-no-ref-gate P5
  mrow m6-continue-on-error P5
  mrow m6-warn P5
  mrow m6b-no-timeout P7
  mrow m7-delete-upload P2

  # must-PASS variant: an unrelated trailing step keeps every property green
  python3 -I "$WIRING" mutate benign "$WF" "$SANDBOX/mut-benign.yml" 2>/dev/null
  BENIGN_OUT=$(wiring_check "$SANDBOX/mut-benign.yml")
  eq "B3 an unrelated trailing step keeps every property green" "$(printf '%s\n' "$BENIGN_OUT" | grep -c '^ok P')" "$NPROPS"

  # harness row: a workflow that does not parse reports every property bad, never an empty "all clear"
  printf 'not: [valid\n' > "$SANDBOX/broken.yml"
  eq "B4 an unparseable workflow reports $NPROPS bad properties" "$(wiring_check "$SANDBOX/broken.yml" | grep -c '^bad P')" "$NPROPS"
fi

# ─────────────────────────────────────────────────────────────────────────────
# verdict
# ─────────────────────────────────────────────────────────────────────────────
EXPECTED_MIN_PASSES=286
printf 'monitor-streak-state: %s passed, %s failed\n' "$passes" "$fails"
if [ "$passes" -lt "$EXPECTED_MIN_PASSES" ]; then
  printf 'FAIL: only %s assertions ran (floor %s): a suite that stopped asserting is not green\n' "$passes" "$EXPECTED_MIN_PASSES" >&2
  exit 1
fi
[ "${#FAILURES[@]}" -eq 0 ] || exit 1
exit 0
