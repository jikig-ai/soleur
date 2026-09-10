#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Guard 2 of the #5806 verification plan — THE DECISION LOGIC, EXECUTED.
#
# The plan (knowledge-base/project/plans/2026-09-09-chore-ci-concurrency-and-
# workflow-run-deploy-plan.md § Verification, layer 2) calls this "the only
# pre-merge exercise of the decision logic itself", and it did not ship.
#
# WHY THAT MATTERS MORE THAN THE OTHER GUARDS. `workflow-run-deploy-invariants`
# is STATIC: it parses the YAML and asserts the file SAYS the right things. It
# cannot tell you what `resolve-target` DOES. And what it does is decide whether
# production gets a deploy — a five-state machine whose two green states must
# stay green (docs-only pushes are routine) and whose three fault states must
# fail closed and notify. Before this suite, that decision had never once been
# executed anywhere in CI.
#
# HOW. Extract the step's `run:` body and execute it under the shell Actions
# uses, exactly as ci-test-aggregator-diagnosis.test.sh does for the aggregator.
# `gh` is stubbed to serve fixture JSON per API path (and to write a REAL zip, so
# `unzip` and `jq` stay real). Everything else — the arithmetic, the ordering of
# the trust ladder, the emptiness checks, the exits — is the shipped code.
#
# Provenance: this suite was written AFTER the workflow, on 2026-09-10, because
# review found layer 2 missing. It is not TDD and does not claim to be.
# ═══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
REL="$REPO_ROOT/.github/workflows/web-platform-release.yml"
[ -f "$REL" ] || { printf 'FAIL: %s not found\n' "$REL" >&2; exit 2; }

W=$(mktemp -d -t rtdecision.XXXXXXXX) || { printf 'FAIL: mktemp\n' >&2; exit 2; }
trap 'rm -rf "$W"' EXIT

passes=0; fails=0; FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }

echo "=== Guard 2: resolve-target's decision logic, EXECUTED (#5806 plan layer 2) ==="

# ── INSTRUMENT SELF-TEST ─────────────────────────────────────────────────────
_p0=$passes; _f0=$fails
pass; fail "INSTRUMENT SELF-TEST (expected — proves fail() increments)"
if [ "$passes" -eq $((_p0 + 1)) ] && [ "$fails" -eq $((_f0 + 1)) ]; then
  passes=$_p0; fails=$_f0; FAILURES=(); pass
  echo "  instrument self-test: pass() and fail() both move"
else
  printf 'FATAL: the instrument does not move both counters\n' >&2; exit 2
fi

# ── Extract the step body ────────────────────────────────────────────────────
BODY="$W/resolve.sh"
python3 - "$REL" "$BODY" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
step = next(s for s in d["jobs"]["resolve-target"]["steps"] if s.get("id") == "resolve")
open(sys.argv[2], "w").write(step["run"])
PY
_n=$(grep -c . "$BODY" 2>/dev/null || echo 0)
if [ "$_n" -ge 100 ]; then pass; echo "  extracted: $_n non-blank lines from the 'Resolve the deploy target' step"; else
  fail "EXTRACTOR: only $_n lines extracted — every row below would exercise a stub of the real thing"
fi

# ── The `gh` stub ────────────────────────────────────────────────────────────
# Serves fixture JSON per API path from files the harness writes. It writes a
# REAL zip for the artifact download so `unzip` and `jq` stay real — stubbing
# those too would mean the suite no longer exercises the parsing it claims to.
mkdir -p "$W/bin"
cat > "$W/bin/gh" <<'GHSTUB'
#!/usr/bin/env bash
# args: api <path> [--jq ...] [-H ...]
url=""
for a in "$@"; do
  case "$a" in
    api) continue ;;
    -*) continue ;;
    *) [ -z "$url" ] && url="$a" ;;
  esac
done
# Order matters: the list query is `/actions/workflows/<file>/runs?...`, the
# single-run read is `/actions/runs/<id>`. Matching the wrong one first sends
# every fixture to the wrong file.
case "$url" in
  */zip)            cat "$FIX/artifact.zip"; exit 0 ;;
  */jobs*)          f="$FIX/jobs.json" ;;
  */artifacts*)     f="$FIX/artifacts.json" ;;
  */runs\?*)        f="$FIX/runs.json" ;;
  */runs)           f="$FIX/runs.json" ;;
  */actions/runs/*) f="$FIX/run.json" ;;
  *) printf 'gh-stub: unhandled url %s\n' "$url" >&2; exit 22 ;;
esac
[ -f "$f" ] || { printf 'gh-stub: fixture %s missing\n' "$f" >&2; exit 23; }
# honour --jq by delegating to real jq, as gh does
jqexpr=""
prev=""
for a in "$@"; do
  [ "$prev" = "--jq" ] && jqexpr="$a"
  prev="$a"
done
if [ -n "$jqexpr" ]; then jq -r "$jqexpr" < "$f"; else cat "$f"; fi
GHSTUB
chmod +x "$W/bin/gh"

# ── Fixture builder ──────────────────────────────────────────────────────────
SHA_OK=1111111111111111111111111111111111111111
mkfix() {  # $1=dir  $2=run_id|""  $3=release conclusion  $4=artifact json|"NONE"|"EXPIRED"
  local d="$1" runid="$2" conc="$3" art="$4"
  mkdir -p "$d"
  if [ -z "$runid" ]; then printf '{"workflow_runs":[]}\n' > "$d/runs.json"
  else printf '{"workflow_runs":[{"id":%s,"status":"completed","conclusion":"success"}]}\n' "$runid" > "$d/runs.json"; fi
  printf '{"status":"completed"}\n' > "$d/run.json"
  printf '{"jobs":[{"name":"release / release","conclusion":"%s"}]}\n' "$conc" > "$d/jobs.json"
  case "$art" in
    NONE)    printf '{"artifacts":[]}\n' > "$d/artifacts.json" ;;
    EXPIRED) printf '{"artifacts":[{"id":9,"name":"release-outputs-web-platform","expired":true}]}\n' > "$d/artifacts.json" ;;
    *)       printf '{"artifacts":[{"id":9,"name":"release-outputs-web-platform","expired":false}]}\n' > "$d/artifacts.json"
             python3 - "$d" "$art" <<'PYZ'
import sys, zipfile, os
d, payload = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(os.path.join(d, "artifact.zip"), "w") as z:
    z.writestr("release-outputs.json", payload)
PYZ
             ;;
  esac
}

# ── The driver ───────────────────────────────────────────────────────────────
# ${VAR-default}, NOT ${VAR:-default}. The colon form substitutes when the
# variable is EMPTY as well as when it is unset — so a fixture setting
# D_VERSION="" to mean "the release published nothing" silently got 1.2.3 back,
# and two arm-parity rows reported a defect in the workflow that was really a
# defect in this driver.
run_resolve() {  # env via caller; sets RC and OUTPUTS
  OUTF="$W/out.$RANDOM"; : > "$OUTF"
  RTMP="$W/rt.$RANDOM"; mkdir -p "$RTMP"
  set +e
  PATH="$W/bin:$PATH" FIX="$FIXDIR" \
  GITHUB_OUTPUT="$OUTF" RUNNER_TEMP="$RTMP" GH_TOKEN=x REPO=o/r OWN_RUN_ID=999 \
  EVENT_NAME="${EVENT_NAME-workflow_run}" \
  WR_HEAD_BRANCH="${WR_HEAD_BRANCH-main}" WR_EVENT="${WR_EVENT-push}" \
  WR_CONCLUSION="${WR_CONCLUSION-success}" WR_HEAD_SHA="${WR_HEAD_SHA-$SHA_OK}" \
  DISPATCH_SHA="${DISPATCH_SHA-$SHA_OK}" \
  D_RESULT="${D_RESULT-success}" D_VERSION="${D_VERSION-1.2.3}" D_TAG="${D_TAG-v1.2.3}" \
  D_RELEASED="${D_RELEASED-true}" D_DOCKER_PUSHED="${D_DOCKER_PUSHED-true}" \
  D_MIRROR_VERIFIED="${D_MIRROR_VERIFIED-true}" \
  bash --noprofile --norc -eo pipefail "$BODY" >"$W/stdout.log" 2>&1
  RC=$?
  set -e
  OUT=$(cat "$OUTF" 2>/dev/null || true)
}
get() { printf '%s' "$OUT" | grep -E "^$1=" | head -1 | cut -d= -f2- ; }

# ── CONTROL: the happy path must DEPLOY, or every row below is unreadable ─────
GOOD_ART=$(printf '{"schema":1,"component":"web-platform","run_id":777,"head_sha":"%s","version":"1.2.3","tag":"v1.2.3","released":true,"docker_pushed":true,"mirror_verified":true}' "$SHA_OK")
FIXDIR="$W/f-happy"; mkfix "$FIXDIR" 777 success "$GOOD_ART"
( EVENT_NAME=workflow_run; run_resolve
  if [ "$(get should_deploy)" = "true" ] && [ "$RC" -eq 0 ]; then exit 0; else
    printf 'CONTROL: happy path did NOT deploy (rc=%s should_deploy=%s skip_reason=%s)\n  %s\n' \
      "$RC" "$(get should_deploy)" "$(get skip_reason)" "$(tr '\n' '|' <"$W/stdout.log" | head -c 400)" >&2
    exit 1
  fi )
if [ $? -eq 0 ]; then pass; else
  printf '\nCONTROL ROW FAILED — every verdict below would be measured against a\nbroken baseline, so this battery is VOID rather than failing.\n' >&2
  printf 'resolve-target-decision.test.sh: CONTROL FAILED\n' >&2
  exit 1
fi

# ── The five states, one row per state, each ALONE ───────────────────────────
# $1=label $2=want_should_deploy $3=want_skip_reason("" = any) $4=want_rc
expect() {
  local label="$1" wsd="$2" wsr="$3" wrc="$4"
  local ok=1
  [ "$(get should_deploy)" = "$wsd" ] || ok=0
  [ -n "$wsr" ] && { [ "$(get skip_reason)" = "$wsr" ] || ok=0; }
  [ "$RC" -eq "$wrc" ] || ok=0
  if [ "$ok" -eq 1 ]; then pass; return 0; fi
  fail "$label — expected should_deploy=$wsd skip_reason=${wsr:-<any>} rc=$wrc; got should_deploy=$(get should_deploy) skip_reason=$(get skip_reason) rc=$RC"
}

# GREEN STATE 1 — no release run for this SHA (docs-only push, on.push.paths declined).
FIXDIR="$W/f-norun"; mkfix "$FIXDIR" "" success NONE
run_resolve
expect "S1 no release run -> CLEAN SKIP, green" false no_release_run 0

# GREEN STATE 2 — the release ran and published nothing (check_changed declined).
EMPTY_ART=$(printf '{"schema":1,"component":"web-platform","run_id":777,"head_sha":"%s","version":"","tag":"","released":false,"docker_pushed":false,"mirror_verified":false}' "$SHA_OK")
FIXDIR="$W/f-empty"; mkfix "$FIXDIR" 777 success "$EMPTY_ART"
run_resolve
expect "S2 published nothing -> CLEAN SKIP, green" false upstream_concluded_unpublished 0

# GREEN STATE 3 — CI was not green on main. No deploy, run stays green.
FIXDIR="$W/f-happy"
WR_CONCLUSION=failure run_resolve
expect "S3 CI not green -> no deploy, run stays green" false ci_not_green 0

# GREEN STATE 4/5 — wrong branch, wrong upstream event.
WR_HEAD_BRANCH=release-x run_resolve
expect "S4 upstream ran on a non-main branch -> clean skip" false not_main 0
WR_EVENT=pull_request run_resolve
expect "S5 upstream was not a push -> clean skip" false not_push 0

# ── The FAULT states: each must fail CLOSED (rc=1) with its own reason ────────
# THE EQUAL-STRENGTH ROW. A release whose job concluded `failure` must not
# deploy, whatever the artifact says — this is the zot-mirror-gate-blocked case
# and the reason the verdict comes from the jobs API rather than the artifact.
FIXDIR="$W/f-relfail"; mkfix "$FIXDIR" 777 failure "$GOOD_ART"
run_resolve
expect "F1 release job concluded failure -> FAIL CLOSED" false release_failed 1

# The artifact is the VALUES channel; its absence must not read as "no release".
FIXDIR="$W/f-noart"; mkfix "$FIXDIR" 777 success NONE
run_resolve
expect "F2 release succeeded but published no artifact -> FAIL CLOSED" false release_outputs_missing 1

FIXDIR="$W/f-expired"; mkfix "$FIXDIR" 777 success EXPIRED
run_resolve
expect "F3 artifact expired -> FAIL CLOSED (evidence aged out, not 'no release')" false release_outputs_expired 1

# Identity: the artifact must describe the SHA the event carried.
WRONG_SHA_ART=$(printf '{"schema":1,"component":"web-platform","run_id":777,"head_sha":"%s","version":"1.2.3","tag":"v1.2.3","released":true,"docker_pushed":true,"mirror_verified":true}' "2222222222222222222222222222222222222222")
FIXDIR="$W/f-idmismatch"; mkfix "$FIXDIR" 777 success "$WRONG_SHA_ART"
run_resolve
expect "F4 artifact head_sha != event head_sha -> FAIL CLOSED (would ship the wrong commit)" false identity_mismatch 1

BAD_SCHEMA_ART=$(printf '{"schema":99,"component":"web-platform","run_id":777,"head_sha":"%s","version":"1.2.3","tag":"v1.2.3","released":true,"docker_pushed":true,"mirror_verified":true}' "$SHA_OK")
FIXDIR="$W/f-schema"; mkfix "$FIXDIR" 777 success "$BAD_SCHEMA_ART"
run_resolve
expect "F5 artifact schema mismatch -> FAIL CLOSED" false schema_mismatch 1

# INCOHERENT: an image was pushed but no version recorded. Before review this
# fell into the CLEAN-SKIP arm and left the run green with no notification.
INCOH_ART=$(printf '{"schema":1,"component":"web-platform","run_id":777,"head_sha":"%s","version":"","tag":"","released":false,"docker_pushed":true,"mirror_verified":true}' "$SHA_OK")
FIXDIR="$W/f-incoh"; mkfix "$FIXDIR" 777 success "$INCOH_ART"
run_resolve
expect "F6 docker_pushed=true with no version -> FAIL CLOSED, not a clean skip" false release_outputs_incomplete 1

# Malformed SHA from the event.
FIXDIR="$W/f-happy"
WR_HEAD_SHA=not-a-sha run_resolve
expect "F7 malformed head_sha -> FAIL CLOSED" false bad_sha 1

# ── The DISPATCH arm ─────────────────────────────────────────────────────────
FIXDIR="$W/f-happy"
EVENT_NAME=workflow_dispatch run_resolve
expect "D1 dispatch with a successful in-run release -> DEPLOY" true "" 0
if [ "$(get head_sha)" = "$SHA_OK" ]; then pass; else
  fail "D1b dispatch head_sha is '$(get head_sha)', expected the DISPATCH_SHA ($SHA_OK) — on this arm there is no upstream event to recover a SHA from"
fi
EVENT_NAME=workflow_dispatch D_RESULT=failure run_resolve
expect "D2 dispatch with a failed in-run release -> FAIL CLOSED" false release_failed 1
# ARM PARITY: the emptiness check the workflow_run arm applies must apply here.
EVENT_NAME=workflow_dispatch D_VERSION="" D_TAG="" D_RELEASED=false D_DOCKER_PUSHED=false run_resolve
expect "D3 dispatch, release published nothing -> CLEAN SKIP (arm parity)" false upstream_concluded_unpublished 0
EVENT_NAME=workflow_dispatch D_VERSION="" D_TAG="" D_DOCKER_PUSHED=true run_resolve
expect "D4 dispatch, incoherent release -> FAIL CLOSED (arm parity)" false release_outputs_incomplete 1

# ── THE OWN-RUN EXCLUSION (second-member row) ────────────────────────────────
# Every fixture above puts ONE run in the list, so dropping
# `select((.id|tostring) != $own)` changes nothing and the mutant SURVIVES —
# measured. But the exclusion is load-bearing exactly because the new topology
# produces TWO runs for the same SHA: the push arm (which published) and this
# workflow_run-arm run (whose `release` job is skipped). Resolve to the wrong one
# and the gate reads "published nothing" for a SHA that DID publish — the deploy
# silently never happens and the run stays green.
#
# OWN_RUN_ID is 999 in the driver, so the fixture offers 999 alongside 777 and
# the resolver must pick 777. `last` after `sort_by(.id)` would pick 999.
FIXDIR="$W/f-tworuns"; mkfix "$FIXDIR" 777 success "$GOOD_ART"
python3 - "$FIXDIR/runs.json" <<'PYR'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["workflow_runs"].append({"id": 999, "status": "completed", "conclusion": "success"})
json.dump(d, open(p, "w"))
PYR
run_resolve
if [ "$(get should_deploy)" = "true" ] && [ "$RC" -eq 0 ]; then pass; else
  fail "X1 with the own run (999) present alongside the push-arm run (777), the resolver did not deploy (should_deploy=$(get should_deploy) skip_reason=$(get skip_reason) rc=$RC). Dropping the own-run exclusion resolves to THIS run, whose release job is skipped, so a SHA that published reads as 'published nothing'"
fi
# And it must have used the PUSH-arm run's artifact, not this run's.
if grep -qF 'release run: 777' "$W/stdout.log" 2>/dev/null; then pass; else
  fail "X1b the resolver did not select run 777 (the push arm). stdout: $(tr '\n' '|' <"$W/stdout.log" | head -c 200)"
fi

# ── Verdict ──────────────────────────────────────────────────────────────────
TOTAL=$((passes + fails))
# DERIVED: 1 instrument + 1 extractor + 1 control + 5 green states
# + 7 fault states + 5 dispatch (D1, D1b, D2, D3, D4)
# + 2 own-run exclusion (X1 deploys anyway, X1b selected the push arm) = 22
MIN_ROWS=22
if [ "$TOTAL" -lt "$MIN_ROWS" ]; then
  printf 'FAIL: assertion floor — %d rows executed, at least %d required. A row was dropped or a fixture stopped running.\n' \
    "$TOTAL" "$MIN_ROWS" >&2
  exit 1
fi
printf '%s: %d rows, %d passed, %d failed\n' "$(basename "${BASH_SOURCE[0]}")" "$TOTAL" "$passes" "$fails"
if [ "$fails" -gt 0 ]; then
  printf '\nfailures:\n' >&2; printf '  - %s\n' "${FAILURES[@]}" >&2
  exit 1
fi
exit 0
