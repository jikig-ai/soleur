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
# production gets a deploy — a six-state machine whose two green states must
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
# The fixture repos below are built with git_fixture_env (plugins/soleur/AGENTS.md §Test Fixture
# Conventions). Sourcing the helpers arms the #7833 git-location tripwire and enables `set -e`.
# shellcheck source=./test-helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

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
python3 - "$REL" "$BODY" "$W/rpf" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
step = next(s for s in d["jobs"]["resolve-target"]["steps"] if s.get("id") == "resolve")
open(sys.argv[2], "w").write(step["run"])
# The pathspec the empty-lookup diff check uses, READ FROM THE WORKFLOW and never restated
# here: a harness copy would keep L1 green while the workflow's copy drifted (Guard 1 H1).
open(sys.argv[3], "w").write(step.get("env", {}).get("RELEASE_PATH_FILTER", ""))
PY
_n=$(grep -c . "$BODY" 2>/dev/null || echo 0)
if [ "$_n" -ge 100 ]; then pass; echo "  extracted: $_n non-blank lines from the 'Resolve the deploy target' step"; else
  fail "EXTRACTOR: only $_n lines extracted — every row below would exercise a stub of the real thing"
fi
RPF=$(cat "$W/rpf")
if [ -n "$RPF" ]; then pass; echo "  extracted: RELEASE_PATH_FILTER='$RPF'"; else
  fail "EXTRACTOR: step 'resolve' declares no env RELEASE_PATH_FILTER — the empty-lookup diff check has no pathspec to read"
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
# every fixture to the wrong file. The FILTERED search (`?event=push&head_sha=`)
# and the UNFILTERED list (`?per_page=100`, no search params) are two different
# reads and are served from two different fixtures; the filtered one must match
# first because it is the more specific pattern.
case "$url" in
  */zip)            cat "$FIX/artifact.zip"; exit 0 ;;
  */jobs*)          f="$FIX/jobs.json" ;;
  */artifacts*)     f="$FIX/artifacts.json" ;;
  */runs\?*head_sha=*)
    # A SEQUENCE when runs.json.<n> exists: the n-th filtered read gets runs.json.<n>,
    # and any read past the sequence gets runs.json. One counter file per FIXDIR.
    n=0; [ -f "$FIX/.n_filtered" ] && n=$(cat "$FIX/.n_filtered")
    n=$((n + 1)); printf '%s\n' "$n" > "$FIX/.n_filtered"
    if [ -f "$FIX/runs.json.$n" ]; then f="$FIX/runs.json.$n"; else f="$FIX/runs.json"; fi ;;
  */runs\?*)        f="$FIX/runs_all.json" ;;
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

# `sleep` is stubbed so the lookup backoff costs nothing and is COUNTED: every call
# appends one line to $SLEEP_LOG, which run_resolve truncates per row.
cat > "$W/bin/sleep" <<'SLEEPSTUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SLEEP_LOG:?}"
SLEEPSTUB
chmod +x "$W/bin/sleep"

# ── Fixture repository ───────────────────────────────────────────────────────
# The empty-lookup path runs a REAL `git diff <sha>~1 <sha> -- <pathspec>`, so the
# rows that reach it need real commits. One linear source repo; each row gets its
# own DEPTH-1 clone of the commit under test, matching resolve-target's depth-1 CI
# checkout, so the step's lazy `git fetch --depth=2 origin <sha>` runs for real
# against a real `origin`. A stubbed git would replay this harness's reading of
# `:(exclude)` and rename semantics rather than git's.
SRC="$W/src"; mkdir -p "$SRC"
git_fixture_env "$SRC" || { printf 'FATAL: git_fixture_env refused %s\n' "$SRC" >&2; exit 2; }
git -C "$SRC" init -q -b main
commit_file() {  # $1=path $2=message — writes the file, commits, prints the SHA
  mkdir -p "$SRC/$(dirname "$1")"
  printf '%s\n' "$2" > "$SRC/$1"
  git -C "$SRC" add -- "$1"
  git -C "$SRC" commit -q -m "$2"
  git -C "$SRC" rev-parse HEAD
}
SHA_ROOT=$(commit_file apps/web-platform/moved.ts root)
SHA_DOCS=$(commit_file knowledge-base/x.md docs)
SHA_APP=$(commit_file apps/web-platform/x.ts app)
SHA_PDOCS=$(commit_file plugins/soleur/docs/x.md pdocs)
# Sits between pdocs and mvout so that mvout~1 is an ordinary commit; the test/
# exclusion has the same shape as docs/, which L5 covers.
SHA_PTEST=$(commit_file plugins/soleur/test/x.sh ptest)
mkdir -p "$SRC/other"
git -C "$SRC" mv apps/web-platform/moved.ts other/moved.ts
git -C "$SRC" commit -q -m mvout
SHA_MVOUT=$(git -C "$SRC" rev-parse HEAD)
: "$SHA_PTEST"

# Called as `CLONE=$(mkshallow …)`, i.e. in a subshell, so the directory name is
# minted by mktemp rather than by a counter the subshell could not advance.
mkshallow() {  # $1=sha — prints the path of a fresh depth-1 clone holding only that commit
  local d
  d=$(mktemp -d "$W/clone.XXXXXX")
  git init -q "$d"
  git -C "$d" remote add origin "file://$SRC"
  git -C "$d" fetch -q --depth=1 origin "$1"
  printf '%s' "$d"
}
CLONE_APP=$(mkshallow "$SHA_APP")
# The fixture must actually be shallow, or every lazy-deepen row passes without
# the deepen ever running.
if ! git -C "$CLONE_APP" cat-file -e "${SHA_APP}~1^{commit}" 2>/dev/null; then pass; else
  fail "FIXTURE: the depth-1 clone already holds the parent of $SHA_APP — the lazy-deepen rows would pass without deepening"
fi

# ── Fixture builder ──────────────────────────────────────────────────────────
SHA_OK=1111111111111111111111111111111111111111
mkfix() {  # $1=dir  $2=run_id|""  $3=release conclusion  $4=artifact json|"NONE"|"EXPIRED"
  local d="$1" runid="$2" conc="$3" art="$4"
  mkdir -p "$d"
  if [ -z "$runid" ]; then printf '{"workflow_runs":[]}\n' > "$d/runs.json"
  else printf '{"workflow_runs":[{"id":%s,"status":"completed","conclusion":"success"}]}\n' "$runid" > "$d/runs.json"; fi
  # The UNFILTERED list, in the real list shape. Empty unless a row overrides it.
  printf '{"total_count":0,"workflow_runs":[]}\n' > "$d/runs_all.json"
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
#
# EVERY ROW RUNS INSIDE A FIXTURE CLONE (`CLONE`, default: the `app` commit's
# clone), never in this checkout: in the real checkout a fixture SHA is unknown,
# so git would fail rc 128 and every empty-lookup row would read as
# "diff uncomputable" — S1 and L5 are the rows that expose a wrong directory.
run_resolve() {  # env via caller; sets RC and OUTPUTS
  OUTF="$W/out.$RANDOM"; : > "$OUTF"
  RTMP="$W/rt.$RANDOM"; mkdir -p "$RTMP"
  : > "$W/sleep.log"
  set +e
  cd "${CLONE-$CLONE_APP}" || { printf 'FATAL: cannot cd into fixture clone\n' >&2; exit 2; }
  SLEEP_LOG="$W/sleep.log" RELEASE_PATH_FILTER="${RELEASE_PATH_FILTER-$RPF}" \
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
  cd "$REPO_ROOT"
  set -e
  OUT=$(cat "$OUTF" 2>/dev/null || true)
}
# THE LAST EMIT WINS. The Actions runner keeps the LAST value of a repeated
# $GITHUB_OUTPUT key, so that is what a consumer reads — and a swallowed failure
# that falls through into a later emit writes the key TWICE. Reading the first
# value is how that passes; `nsr` counts the skip_reason lines so it cannot.
get() { printf '%s\n' "$OUT" | grep -E "^$1=" | tail -1 | cut -d= -f2- ; }
nsr() { printf '%s\n' "$OUT" | grep -cE '^skip_reason=' || true; }
nsleep() { grep -c . "$W/sleep.log" 2>/dev/null || true; }
has_out() { grep -qE -- "$1" "$W/stdout.log" 2>/dev/null; }
show_out() { tr '\n' '|' <"$W/stdout.log" | head -c 400; }

# Artifact payload for a SHA (the identity check compares it to the event's SHA).
art_for() { printf '{"schema":1,"component":"web-platform","run_id":777,"head_sha":"%s","version":"1.2.3","tag":"v1.2.3","released":true,"docker_pushed":true,"mirror_verified":true}' "$1"; }

# ── CONTROL: the happy path must DEPLOY, or every row below is unreadable ─────
# On a REAL commit (`app`), so that a reordering that runs the diff before the
# lookup (Guard 1 mutation 4) still deploys here and the kill lands on the row
# built for it (L7) rather than voiding the battery.
GOOD_ART=$(art_for "$SHA_OK")
FIXDIR="$W/f-control"; mkfix "$FIXDIR" 777 success "$(art_for "$SHA_APP")"
if ( EVENT_NAME=workflow_run WR_HEAD_SHA=$SHA_APP run_resolve
  if [ "$(get should_deploy)" = "true" ] && [ "$RC" -eq 0 ]; then exit 0; else
    printf 'CONTROL: happy path did NOT deploy (rc=%s should_deploy=%s skip_reason=%s)\n  %s\n' \
      "$RC" "$(get should_deploy)" "$(get skip_reason)" "$(show_out)" >&2
    exit 1
  fi ); then pass; else
  printf '\nCONTROL ROW FAILED — every verdict below would be measured against a\nbroken baseline, so this battery is VOID rather than failing.\n' >&2
  printf 'resolve-target-decision.test.sh: CONTROL FAILED (VOID)\n' >&2
  exit 2
fi
FIXDIR="$W/f-happy"; mkfix "$FIXDIR" 777 success "$GOOD_ART"

# ── The states, one row per state, each ALONE (the empty-lookup rows are below) ─
# $1=label $2=want_should_deploy $3=want_skip_reason("" = any) $4=want_rc
expect() {
  local label="$1" wsd="$2" wsr="$3" wrc="$4"
  local ok=1
  [ "$(get should_deploy)" = "$wsd" ] || ok=0
  [ -n "$wsr" ] && { [ "$(get skip_reason)" = "$wsr" ] || ok=0; }
  [ "$RC" -eq "$wrc" ] || ok=0
  # A skip or a failure must be emitted EXACTLY ONCE: two emits is a swallowed
  # failure that fell through into a later verdict.
  if [ "$wsd" = "false" ] && [ "$(nsr)" -ne 1 ]; then ok=0; fi
  if [ "$ok" -eq 1 ]; then pass; return 0; fi
  fail "$label — expected should_deploy=$wsd skip_reason=${wsr:-<any>} rc=$wrc; got should_deploy=$(get should_deploy) skip_reason=$(get skip_reason) rc=$RC skip_reason_lines=$(nsr). stdout: $(show_out)"
}

# GREEN STATE 1 — no release run for this SHA, and its diff touches no deployable
# path (docs-only push, on.push.paths declined). Only reached after all 4 lookups.
FIXDIR="$W/f-norun"; mkfix "$FIXDIR" "" success NONE
CLONE=$(mkshallow "$SHA_DOCS") WR_HEAD_SHA=$SHA_DOCS run_resolve
expect "S1 no release run, docs-only diff -> CLEAN SKIP, green" false no_release_run 0
if [ "$(nsleep)" -eq 3 ]; then pass; else
  fail "S1b an empty lookup must be retried: expected 3 backoff sleeps between 4 lookups, got $(nsleep). One empty answer from GitHub's run search is not evidence that no run exists"
fi

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

# ── THE API-FAILURE PATH ─────────────────────────────────────────────────────
# No fixture drove `gh` to FAIL, so every row above exercised only the happy
# transport. Row A1 drives the whole path: the stub fails, the retries run, and
# the step must fail CLOSED with a reason rather than die.
#
# WHAT THIS ROW DOES *NOT* COVER, stated so nobody assumes otherwise. The
# errexit-capture idiom in gh_api() is guarded STATICALLY, by
# scripts/lint-workflow-errexit-capture.py (ADR-170), not here — and that is
# correct rather than a gap. A bare `_out=$(gh api ...)` followed by `_rc=$?` is
# fragile in principle, but MEASURED, it is not fatal in this call shape: every
# gh_api call site is inside `$( )`, and bash does not propagate errexit into a
# command substitution there, so the read is reached and the behaviour is
# identical. Writing a row that "kills" that mutation would mean asserting a
# difference that does not exist — a fake kill, which is the defect class this
# whole suite family exists to remove.
#
# The two instruments split the work honestly: the linter sees a fragile idiom
# that would break the moment gh_api is called outside a substitution; A1 sees
# the behaviour — retry, then fail closed with a reason.
FIXDIR="$W/f-apifail"; mkfix "$FIXDIR" 777 success "$GOOD_ART"
mv "$FIXDIR/runs.json" "$FIXDIR/runs.json.disabled"   # the stub exits 23 on a missing fixture
run_resolve
expect "A1 the GitHub API fails -> FAIL CLOSED with a reason, not a dead step" false github_api_unavailable 1
# A1b — and it must have RETRIED rather than given up on the first error.
if grep -qE 'retrying in' "$W/stdout.log"; then pass; else
  fail "A1b gh_api did not retry before failing closed — the class is overwhelmingly transient, and one 5xx should not block a deploy. stdout: $(tr '\n' '|' <"$W/stdout.log" | head -c 200)"
fi
# A1c — the ::error:: annotation must REACH THE LOG. gh_api is called inside
# `x=$( … )`, so an annotation echoed to plain stdout is captured into x and lost:
# the run goes red with no line saying why. fail_closed writes through fd 3.
if has_out '^::error::deploy blocked'; then pass; else
  fail "A1c the fail-closed ::error:: annotation never reached the job log — it was captured by the \$( ) around gh_api. stdout: $(show_out)"
fi

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

# ═══ THE EMPTY LOOKUP (2026-09-24, run 36050118687) ═══════════════════════════
# GitHub's filtered runs search (`?event=push&head_sha=`) answered EMPTY for a SHA
# whose push-arm release had published 13 minutes earlier, and the old code read
# that as "on.push.paths declined it": a GREEN run, no deploy, no notification.
# An empty answer is now read only after 4 lookups over two independently served
# reads (filtered search, then the unfiltered list), and then only through a real
# diff of the SHA against its parent.

# L1 — THE REQUESTED ROW. The diff touches apps/web-platform/** and both reads
# answer [] every time: a release was due and cannot be found. Loud, never green.
FIXDIR="$W/f-L1"; mkfix "$FIXDIR" "" success NONE
CLONE=$(mkshallow "$SHA_APP") WR_HEAD_SHA=$SHA_APP run_resolve
expect "L1 deployable diff + empty lookups -> FAIL CLOSED release_run_missing, never the no_release_run clean skip" false release_run_missing 1
if has_out 'deployable paths \(apps/web-platform/x\.ts'; then pass; else
  fail "L1b release_run_missing was not reached through the diff-TOUCHES-deployable-paths branch (expected 'deployable paths (apps/web-platform/x.ts' in the annotation). stdout: $(show_out)"
fi

# L2 — the filtered search lags for two lookups, then answers. The retry is what
# resolves it; the run deploys and says it was found late.
FIXDIR="$W/f-L2"; mkfix "$FIXDIR" 777 success "$GOOD_ART"
printf '{"workflow_runs":[]}\n' > "$FIXDIR/runs.json.1"
printf '{"workflow_runs":[]}\n' > "$FIXDIR/runs.json.2"
run_resolve
expect "L2 filtered search empty twice then found -> DEPLOY" true "" 0
if [ "$(nsleep)" -eq 2 ]; then pass; else
  fail "L2b expected exactly 2 backoff sleeps before lookup 3 found the run, got $(nsleep)"
fi
if [ "$(get lookup_path)" = "retry_3" ]; then pass; else
  fail "L2c lookup_path is '$(get lookup_path)', expected retry_3 — a run found only on a retry must be visible as such"
fi
if has_out '^::warning::release run 777 found via retry-3'; then pass; else
  fail "L2d no ::warning:: that the run was found only on retry 3 — a persistently lagging search would be masked. stdout: $(show_out)"
fi

# L3 — the filtered search stays empty (the incident's shape: ≥13 min), the
# unfiltered list has the run. The fallback is what resolves it, on lookup 1.
FIXDIR="$W/f-L3"; mkfix "$FIXDIR" "" success "$GOOD_ART"
printf '{"total_count":1,"workflow_runs":[{"id":777,"event":"push","head_branch":"main","head_sha":"%s","status":"completed","conclusion":"success"}]}\n' "$SHA_OK" > "$FIXDIR/runs_all.json"
run_resolve
expect "L3 filtered search always empty, unfiltered list has the run -> DEPLOY" true "" 0
if [ "$(nsleep)" -eq 0 ]; then pass; else
  fail "L3b the unfiltered fallback found the run on lookup 1, yet $(nsleep) backoff sleep(s) ran"
fi
if [ "$(get lookup_path)" = "fallback" ]; then pass; else
  fail "L3c lookup_path is '$(get lookup_path)', expected fallback"
fi
if has_out '^::warning::release run 777 found via unfiltered-fallback'; then pass; else
  fail "L3d no ::warning:: that the run was found only via the unfiltered fallback. stdout: $(show_out)"
fi

# L5 (H2 must-PASS) — a plugins/soleur/docs/ change is EXCLUDED by the pathspec.
# Proves the :(exclude) members are honoured and the guard does not reject everything.
FIXDIR="$W/f-L5"; mkfix "$FIXDIR" "" success NONE
CLONE=$(mkshallow "$SHA_PDOCS") WR_HEAD_SHA=$SHA_PDOCS run_resolve
expect "L5 plugins/soleur/docs-only diff + empty lookups -> CLEAN SKIP (excluded path)" false no_release_run 0

# L6 — the diff cannot be computed (a root commit has no parent). Unprovable is
# not "declined": fail closed, and name git's status.
FIXDIR="$W/f-L6"; mkfix "$FIXDIR" "" success NONE
CLONE=$(mkshallow "$SHA_ROOT") WR_HEAD_SHA=$SHA_ROOT run_resolve
expect "L6 uncomputable diff + empty lookups -> FAIL CLOSED release_run_missing" false release_run_missing 1
if has_out 'git rc=128'; then pass; else
  fail "L6b the uncomputable-diff branch did not name git's status (expected 'git rc=128'). stdout: $(show_out)"
fi

# L7 (H4 must-PASS) — a FOUND run is never overridden by the diff. A docs-only head
# commit still deploys when its push run exists (a rebase-merged PR whose last
# commit is docs-only). Kills a reordering that runs the diff first.
FIXDIR="$W/f-L7"; mkfix "$FIXDIR" 777 success "$(art_for "$SHA_DOCS")"
CLONE=$(mkshallow "$SHA_DOCS") WR_HEAD_SHA=$SHA_DOCS run_resolve
expect "L7 docs-only diff but the push run exists -> DEPLOY (the diff never overrides a found run)" true "" 0
if [ "$(get lookup_path)" = "primary" ] && ! has_out '^::warning::'; then pass; else
  fail "L7b a run found on the first filtered read must report lookup_path=primary with no ::warning:: (got lookup_path='$(get lookup_path)'). stdout: $(show_out)"
fi

# L8 — a move OUT of the app deletes a deployable file, so it is deployable.
FIXDIR="$W/f-L8"; mkfix "$FIXDIR" "" success NONE
CLONE=$(mkshallow "$SHA_MVOUT") WR_HEAD_SHA=$SHA_MVOUT run_resolve
expect "L8 a move out of apps/web-platform + empty lookups -> FAIL CLOSED release_run_missing" false release_run_missing 1
if has_out 'moved\.ts'; then pass; else
  fail "L8b the annotation does not name the moved-out file. stdout: $(show_out)"
fi

# L9 — STANDING: the verdict is driven by the diff's OUTPUT under the workflow's
# pathspec, not by a hardcoded answer. Same app commit as L1, but a pathspec that
# matches nothing, so the same empty lookups now clean-skip. Mutates env, not text.
FIXDIR="$W/f-L9"; mkfix "$FIXDIR" "" success NONE
CLONE=$(mkshallow "$SHA_APP") WR_HEAD_SHA=$SHA_APP RELEASE_PATH_FILTER="nonexistent/" run_resolve
expect "L9 the same app commit under a pathspec that matches nothing -> CLEAN SKIP (the diff drives the verdict)" false no_release_run 0

# A2 — the UNFILTERED read fails outright. On a docs-only commit, a failure that
# were swallowed would fall through to the diff and clean-skip GREEN; it must
# instead fail closed with exactly one verdict.
FIXDIR="$W/f-A2"; mkfix "$FIXDIR" "" success NONE
rm -f "$FIXDIR/runs_all.json"   # the stub exits 23 on a missing fixture
CLONE=$(mkshallow "$SHA_DOCS") WR_HEAD_SHA=$SHA_DOCS run_resolve
expect "A2 the unfiltered read fails -> FAIL CLOSED github_api_unavailable (never a clean skip)" false github_api_unavailable 1
if has_out '^::error::deploy blocked'; then pass; else
  fail "A2b the unfiltered read's fail-closed ::error:: annotation never reached the job log. stdout: $(show_out)"
fi

# X2 — the fallback's select, second members. The unfiltered list offers this
# SHA's own workflow_run-arm run (1000), a push run on a non-main branch at this
# SHA (779), and a newer push run for ANOTHER SHA (778); only 777 qualifies.
FIXDIR="$W/f-X2"; mkfix "$FIXDIR" "" success "$GOOD_ART"
printf '{"total_count":4,"workflow_runs":[{"id":1000,"event":"workflow_run","head_branch":"main","head_sha":"%s","status":"in_progress","conclusion":null},{"id":779,"event":"push","head_branch":"feature","head_sha":"%s","status":"completed","conclusion":"success"},{"id":778,"event":"push","head_branch":"main","head_sha":"2222222222222222222222222222222222222222","status":"completed","conclusion":"success"},{"id":777,"event":"push","head_branch":"main","head_sha":"%s","status":"completed","conclusion":"success"}]}\n' "$SHA_OK" "$SHA_OK" "$SHA_OK" > "$FIXDIR/runs_all.json"
run_resolve
expect "X2 unfiltered fallback among decoy runs -> DEPLOY" true "" 0
if has_out '^release run: 777$'; then pass; else
  fail "X2b the fallback did not select run 777 (the push run on main for this SHA). stdout: $(show_out)"
fi

# ── Verdict ──────────────────────────────────────────────────────────────────
# DERIVED: 1 instrument + 1 extractor + 1 control + 5 green states
# + 7 fault states + 5 dispatch (D1, D1b, D2, D3, D4)
# + 2 own-run exclusion (X1 deploys anyway, X1b selected the push arm)
# + 2 API-failure path (A1 fails closed with a reason, A1b retried first) = 24
# + 26 empty-lookup (2026-09-24): RELEASE_PATH_FILTER extractor, shallow-fixture
#   check, S1b, A1c, L1+L1b, L2+L2b+L2c+L2d, L3+L3b+L3c+L3d, L5, L6+L6b, L7+L7b,
#   L8+L8b, L9, A2+A2b, X2+X2b = 50
#
# THE BINDINGS SIT DIRECTLY ABOVE THE CONDITIONAL, WITH NO COMMENT BETWEEN THEM.
# scripts/guard-vacuity-floor.test.sh builds a mutant by walking BACK from the
# `if` and collecting simple assignments, stopping at the first line that is not
# one. A comment between `TOTAL=` and the `if` severs that walk, the mutant is
# emitted with $TOTAL unbound, it dies under `set -u`, and the floor is counted
# as UNCONSTRUCTIBLE — i.e. this suite's floor would be unguarded, which is the
# exact vacuity this file family exists to prevent. Keep them adjacent.
TOTAL=$((passes + fails))
MIN_ROWS=50
if [ "$TOTAL" -lt "$MIN_ROWS" ]; then
  printf 'FAIL: assertion floor — %d rows executed, at least %d required. A row was dropped or a fixture stopped running.\n' "$TOTAL" "$MIN_ROWS" >&2
  exit 1
fi
printf '%s: %d rows, %d passed, %d failed\n' "$(basename "${BASH_SOURCE[0]}")" "$TOTAL" "$passes" "$fails"
if [ "$fails" -gt 0 ]; then
  printf '\nfailures:\n' >&2; printf '  - %s\n' "${FAILURES[@]}" >&2
  exit 1
fi
exit 0
