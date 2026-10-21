#!/usr/bin/env bash
# Guard for the zot mirror step of .github/workflows/build-inngest-config-bundle.yml (#7243).
#
# The defect (#6416 class): the mirror step was gated on `steps.zot_bridge.outcome == 'success'`,
# so a soft-failed Cloudflare-tunnel bridge SKIPPED the step and the mirror step itself produced no
# warning, summary line or output. A bridge failing on every dispatch was indistinguishable from
# one that works.
#
# The fix: the step runs whenever the image build succeeded, receives the bridge result as the
# BRIDGE_OUTCOME env var and degrades loudly (outputs + ::warning:: + summary line, exit 0)
# when the bridge did not succeed or the crane download / checksum / extract / copy fails. The
# step keeps continue-on-error: this workflow has no mirror-only mode and no host reads the zot
# copy yet (an interim contract, marked SOLEUR-DEBT in the comment above the step).
#
# This suite parses the workflow as YAML (structural leg), extracts the REAL `run:` body by step
# name and executes it under `bash -eo pipefail` with argv-validating PATH stubs (behavioural
# leg; the harness passes `-eo pipefail`, so the body's own `set -euo pipefail` line is NOT pinned
# here),
# then proves the guard itself is not vacuous by running the same evaluator over mutated copies
# of the workflow (mutation battery). Each mutant must fail the check it is named for, not just
# any check. Run via: bash plugins/soleur/test/inngest-config-bundle-mirror.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/build-inngest-config-bundle.yml"
STEP_NAME="Mirror bundle GHCR->zot (crane, digest-preserving)"

PASS=0
FAIL=0
fail() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}
pass() {
  echo "  pass: $1"
  PASS=$((PASS + 1))
}

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
SCRATCH_PARENT="${TMPDIR:-/var/tmp}"
TMP=$(mktemp -d "$SCRATCH_PARENT/soleur-bundle-mirror.XXXXXXXX") || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$TMP"
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

# Instrument self-test: both verdict helpers must move their own counter, or every later
# line below would be reporting through a helper that never records anything.
_st=$( PASS=0; FAIL=0; pass x >/dev/null; fail y >/dev/null; echo "$PASS$FAIL" )
if [[ "$_st" != "11" ]]; then
  printf 'FATAL: pass()/fail() did not each move their counter (got %s)\n' "$_st" >&2
  exit 1
fi

[[ -f "$WF" ]] || { echo "FATAL: workflow not found at $WF" >&2; exit 2; }
# The crane pin the stubs enforce comes from a SECOND, independent file: a stub that read the pin from the
# workflow under test would agree with whatever that workflow says.
RR="$REPO_ROOT/.github/workflows/reusable-release.yml"
PIN_VERSION=$(sed -n 's/^ *CRANE_VERSION="\(v[0-9.]*\)"$/\1/p' "$RR" 2>/dev/null) || PIN_VERSION=""
PIN_SHA=$(sed -n 's/^ *CRANE_SHA256="\([0-9a-f]\{64\}\)"$/\1/p' "$RR" 2>/dev/null) || PIN_SHA=""
if [[ -z "$PIN_VERSION" || -z "$PIN_SHA" || "$PIN_VERSION" == *$'\n'* || "$PIN_SHA" == *$'\n'* ]]; then
  echo "FATAL: could not read exactly one CRANE_VERSION and CRANE_SHA256 from $RR" >&2
  exit 2
fi
EXPECT_URL="https://github.com/google/go-containerregistry/releases/download/${PIN_VERSION}/go-containerregistry_Linux_x86_64.tar.gz"
python3 -I -c 'import yaml' 2>/dev/null || { echo "FATAL: python3 pyyaml unavailable (isolated mode)" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Structural leg + body extraction (python; verdict lines: OK|BAD <tab> label).
# ---------------------------------------------------------------------------
cat > "$TMP/struct.py" <<'PY'
import re
import sys

import yaml

wf, name, body_out = sys.argv[1:4]
doc = yaml.safe_load(open(wf))
jobs = doc["jobs"]
LEAK = re.compile(r"steps\s*(\.|\[\s*['\"])\s*zot_bridge|tojson\(\s*steps\s*\)", re.I)
GATE = "steps.docker_build.outcome == 'success'"
BRIDGE_USES = "./.github/actions/cf-tunnel-registry-bridge"


def v(ok, n):
    print(("OK" if ok else "BAD") + "\t" + n)


hits = []
for jn, job in jobs.items():
    for i, s in enumerate(job.get("steps", [])):
        if s.get("name") == name:
            hits.append((jn, i))
v(len(hits) == 1, "the mirror step is found exactly once by name (%d steps extracted)" % len(hits))
if len(hits) != 1:
    open(body_out, "w").write("")
    sys.exit(0)
jn, mi = hits[0]
steps = jobs[jn]["steps"]
mirror = steps[mi]
v(mirror.get("id") == "zot_mirror", "the mirror step carries id zot_mirror")
mif = mirror.get("if")
v(mif is None or str(mif).strip() == GATE, "the mirror step gate is absent or exactly the docker_build success test")
leaks = [s.get("name", "?") for j in jobs.values() for s in j.get("steps", []) if LEAK.search(str(s.get("if", "")))]
leaks += ["<job if>" for j in jobs.values() if LEAK.search(str(j.get("if", "")))]
v(not leaks, "no step-level or job-level if: reads steps.zot_bridge in any spelling (%s)" % ",".join(leaks))
bridges = [s for s in steps if str(s.get("uses", "")).lower().startswith(BRIDGE_USES)]
v(len(bridges) >= 1 and all(b.get("continue-on-error") is True for b in bridges),
  "every bridge-action step is continue-on-error: true (an implicit success() would skip the mirror)")
v(mirror.get("continue-on-error") is True, "the mirror step is continue-on-error: true")
v(str((mirror.get("env") or {}).get("BRIDGE_OUTCOME", "")).strip() == "${{ steps.zot_bridge.outcome }}",
  "BRIDGE_OUTCOME is wired from the bridge step outcome, never conclusion")
di = [i for i, s in enumerate(steps) if s.get("id") == "docker_build"]
bi = [i for i, s in enumerate(steps) if s.get("id") == "zot_bridge"]
v(len(di) == 1 and len(bi) == 1 and di[0] < bi[0] < mi,
  "docker_build and the bridge share the mirror's job, in the order docker_build, bridge, mirror")
between = steps[di[0] + 1:mi] if di and di[0] < mi else []
v(all(s.get("continue-on-error") is True for s in between),
  "every step between docker_build and the mirror is continue-on-error: true")
v(mirror.get("shell") in (None, "bash"), "the mirror step shell is absent or bash")
tm = mirror.get("timeout-minutes")
v(isinstance(tm, int) and 0 < tm <= 30, "the mirror step has a timeout-minutes bound of at most 30")
body = mirror.get("run", "")
v(len(re.findall(r"^\s*degraded\(\)\s*\{", body, re.M)) == 1, "degraded() is defined exactly once")

# Producer sign-step pin (#10390): the workflow's cosign invocation must stay on the v3
# `--bundle` contract — the single .sigstore.json (sig + cert + chain) is what the host's
# offline `verify-blob --bundle` consumes. Anchored on the call form inside run bodies, not
# the step name (a rename must not lose the pin) and not a comment (a body grep sees prose).
sign_steps = [
    s
    for j in jobs.values()
    for s in j.get("steps", [])
    if re.search(r"^\s*cosign\s+sign-blob\b", str(s.get("run", "")), re.M)
]
v(len(sign_steps) == 1, "exactly one step invokes cosign sign-blob (%d found)" % len(sign_steps))
sbody = str(sign_steps[0].get("run", "")) if sign_steps else ""
v(len(re.findall(r"^\s*cosign\s+sign-blob\s+--yes\b", sbody, re.M)) == 1,
  "sign-blob runs once with --yes (keyless CI signing is non-interactive)")
v(re.search(r'--bundle\s+"\$\{MANIFEST\}\.sigstore\.json"', sbody) is not None,
  "sign-blob writes <manifest>.sigstore.json via --bundle")
v(not re.search(r"--output-signature\b|--output-certificate\b", sbody),
  "sign-blob carries no removed cosign-2.x --output-signature/--output-certificate flags")

# OCI-image pin (#10390): the host extract runs `docker create` + `docker cp`, and create
# refuses a command-less scratch image ("no command specified") — a bare FROM scratch +
# COPY image is un-pullable-for-extract, which is the exact first-pull failure measured on
# the dedicated host (reason=extract).
asm = [
    s
    for j in jobs.values()
    for s in j.get("steps", [])
    if str(s.get("name", "")).startswith("Assemble bundle tarball")
]
v(len(asm) == 1, "the Assemble-bundle step is found exactly once (%d found)" % len(asm))
abody = str(asm[0].get("run", "")) if asm else ""
v(re.search(r'\\nCMD\s*\[', abody) is not None,
  "the OCI Dockerfile carries a CMD (docker create refuses command-less images)")

# Cosign-verifier staging pin (#10390 defect 2): the host is deny-all-public egress, so its
# `docker run gcr.io/…cosign@sha256:…` verify dies on the daemon-side pull. The producer must
# mirror the pinned verifier image into zot inside this step — after the bundle copy (a cosign
# failure may never starve the owner leg), before mirror_status=ok — and equality-check the
# mirrored digest against the pin. Anchored on call forms in the body, never comments.
v(re.search(r'crane copy "gcr\.io/projectsigstore/cosign@sha256:[0-9a-f]{64}"', body) is not None,
  "the cosign verifier image is copied from the full-digest gcr ref")
v(re.search(r'127\.0\.0\.1:5000/jikig-ai/cosign:v[0-9]', body) is not None,
  "the cosign mirror destination is the zot tag ref jikig-ai/cosign:v*")
v(re.search(r'\|\| degraded cosign_copy ', body) is not None,
  "the cosign copy routes failure through degraded cosign_copy")
v(re.search(r'degraded cosign_digest_mismatch', body) is not None,
  "the cosign zot digest is equality-checked against the pinned digest (cosign_digest_mismatch)")
dm = body.find("digest_mismatch")
cc = body.find('crane copy "gcr.io/projectsigstore/cosign')
ok_i = body.find("mirror_status=ok")
v(dm != -1 and cc != -1 and ok_i != -1 and dm < cc < ok_i,
  "the cosign leg sits after the bundle digest check and before mirror_status=ok")
open(body_out, "w").write(body)
PY

# ---------------------------------------------------------------------------
# Deterministic stubs. They VALIDATE argv (exit 64 + a REFUSE log line on a contract violation,
# which the arms assert is absent) and log every call to $STUB_LOG, never stdout.
# ---------------------------------------------------------------------------
STUBS="$TMP/bin"
mkdir -p "$STUBS"
cat > "$STUBS/curl" <<'STUB'
#!/usr/bin/env bash
echo "curl $*" >> "$STUB_LOG"
if [[ "$#" -ne 6 || "$1" != "-fsSL" || "$2" != "--max-time" || ! "$3" =~ ^[0-9]+$ || "$4" != "-o" || "$5" != "$RUNNER_TEMP/crane.tgz" || "$6" != "$EXPECT_URL" ]]; then
  echo "REFUSE curl $*" >> "$STUB_LOG"
  exit 64
fi
[[ "${STUB_CURL_RC:-0}" == "0" ]] && : > "$5"
exit "${STUB_CURL_RC:-0}"
STUB
cat > "$STUBS/sha256sum" <<'STUB'
#!/usr/bin/env bash
line=""
[ -t 0 ] || line=$(cat)
echo "sha256sum $* <<< $line" >> "$STUB_LOG"
if [[ "$#" -ne 2 || "$1" != "-c" || "$2" != "-" || "$line" != "$PIN_SHA  $RUNNER_TEMP/crane.tgz" || ! -f "$RUNNER_TEMP/crane.tgz" ]]; then
  echo "REFUSE sha256sum $*" >> "$STUB_LOG"
  exit 64
fi
exit "${STUB_SHA_RC:-0}"
STUB
cat > "$STUBS/sudo" <<'STUB'
#!/usr/bin/env bash
echo "sudo $*" >> "$STUB_LOG"
if [[ "$#" -ne 6 || "$1" != "tar" || "$2" != "-xzf" || "$3" != "$RUNNER_TEMP/crane.tgz" \
  || "$4" != "-C" || "$5" != "/usr/local/bin" || "$6" != "crane" || ! -f "$RUNNER_TEMP/crane.tgz" ]]; then
  echo "REFUSE sudo $*" >> "$STUB_LOG"
  exit 64
fi
exit "${STUB_SUDO_RC:-0}"
STUB
cat > "$STUBS/sleep" <<'STUB'
#!/usr/bin/env bash
echo "sleep $*" >> "$STUB_LOG"
exit 0
STUB
cat > "$STUBS/timeout" <<'STUB'
#!/usr/bin/env bash
echo "timeout $*" >> "$STUB_LOG"
if [[ "$#" -lt 2 || ! "$1" =~ ^[0-9]+$ ]]; then
  echo "REFUSE timeout $*" >> "$STUB_LOG"
  exit 64
fi
shift
exec "$@"
STUB
cat > "$STUBS/crane" <<'STUB'
#!/usr/bin/env bash
echo "crane $*" >> "$STUB_LOG"
case "${1:-}" in
  copy)
    if [[ "$#" -ne 3 ]]; then echo "REFUSE crane $*" >> "$STUB_LOG"; exit 64; fi
    if [[ "$2" == "$EXPECT_SRC" && "$3" == "$EXPECT_DST" ]]; then
      n=0
      [[ -f "$STUB_COPY_COUNT" ]] && n=$(cat "$STUB_COPY_COUNT")
      n=$((n + 1))
      echo "$n" > "$STUB_COPY_COUNT"
      [[ "$n" -le "${STUB_CRANE_COPY_FAIL_N:-0}" ]] && exit "${STUB_CRANE_COPY_RC:-1}"
      exit 0
    elif [[ "$2" == "$EXPECT_COSIGN_SRC" && "$3" == "$EXPECT_COSIGN_DST" ]]; then
      n=0
      [[ -f "$STUB_COSIGN_COPY_COUNT" ]] && n=$(cat "$STUB_COSIGN_COPY_COUNT")
      n=$((n + 1))
      echo "$n" > "$STUB_COSIGN_COPY_COUNT"
      [[ "$n" -le "${STUB_CRANE_COSIGN_COPY_FAIL_N:-0}" ]] && exit "${STUB_CRANE_COSIGN_COPY_RC:-1}"
      exit 0
    fi
    echo "REFUSE crane $*" >> "$STUB_LOG"; exit 64 ;;
  digest)
    if [[ "$#" -ne 2 ]]; then echo "REFUSE crane $*" >> "$STUB_LOG"; exit 64; fi
    if [[ "$2" == "$EXPECT_DST" ]]; then
      [[ "${STUB_DIGEST_RC:-0}" == "0" ]] || exit "$STUB_DIGEST_RC"
      printf '%s\n' "${STUB_ZOT_DIGEST-$GOOD_DIGEST}"
      exit 0
    elif [[ "$2" == "$EXPECT_COSIGN_DST" ]]; then
      [[ "${STUB_COSIGN_DIGEST_RC:-0}" == "0" ]] || exit "$STUB_COSIGN_DIGEST_RC"
      printf '%s\n' "${STUB_COSIGN_ZOT_DIGEST-$COSIGN_PIN_DIGEST}"
      exit 0
    fi
    echo "REFUSE crane $*" >> "$STUB_LOG"; exit 64 ;;
  *)
    echo "REFUSE crane $*" >> "$STUB_LOG"; exit 64 ;;
esac
STUB
chmod +x "$STUBS"/*

REAL_PATH="$PATH"
# Hermeticity: every network or privileged external the body calls must resolve inside the stub directory,
# or a stub-path mistake would run a real download or a real sudo (rm and echo run for real, scoped by
# RUNNER_TEMP to the arm directory).
for _c in curl sha256sum sudo crane sleep timeout; do
  _r=$(PATH="$STUBS:$REAL_PATH" command -v "$_c" 2>/dev/null) || _r=""
  if [[ "$_r" != "$STUBS/$_c" ]]; then
    printf 'FATAL: %s does not resolve to the stub (got %s)\n' "$_c" "${_r:-nothing}" >&2
    exit 2
  fi
done
GOOD_DIGEST=$(printf 'sha256:%064d' 0 | tr '0' 'a')
OTHER_DIGEST=$(printf 'sha256:%064d' 0 | tr '0' 'b')
EXPECT_SRC="ghcr.io/jikig-ai/soleur-inngest-config:v7"
EXPECT_DST="127.0.0.1:5000/jikig-ai/soleur-inngest-config:v7"
# The pinned cosign verifier image (#10390 defect 2). The full 64-hex literal is the integrity
# anchor — it is asserted whole, never prefix-matched, and lives identically in the workflow src
# leg, the dst equality check, the cloud-init default and these constants.
COSIGN_PIN_DIGEST="sha256:57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870"
EXPECT_COSIGN_SRC="gcr.io/projectsigstore/cosign@${COSIGN_PIN_DIGEST}"
EXPECT_COSIGN_DST="127.0.0.1:5000/jikig-ai/cosign:v3.1.1"

# run_arm <dir> <bridge-outcome|__unset__> [NAME=value knobs...]
# Executes the extracted body exactly as the runner does (bash -eo pipefail), SOURCED so a
# trailing sentinel proves whether degraded() left the shell (exit) or merely the function (return).
# RUNNER_TEMP points at the arm directory so the body's temp-file path is hermetic.
run_arm() {
  local d="$1" bridge="$2"
  shift 2
  mkdir -p "$d"
  assert_fixture_dir "$d"
  : > "$d/gho"
  : > "$d/sum"
  : > "$d/log"
  rm -f "$d/copycount" "$d/cosigncopycount"
  local -a benv=()
  if [[ "$bridge" == "__unset__" ]]; then benv=(-u BRIDGE_OUTCOME); else benv=("BRIDGE_OUTCOME=$bridge"); fi
  local rc=0
  (
    env "${benv[@]}" "$@" IMAGE="ghcr.io/jikig-ai/soleur-inngest-config" VERSION="7" DIGEST="$GOOD_DIGEST" GOOD_DIGEST="$GOOD_DIGEST" EXPECT_DST="$EXPECT_DST" \
      EXPECT_SRC="$EXPECT_SRC" EXPECT_COSIGN_SRC="$EXPECT_COSIGN_SRC" EXPECT_COSIGN_DST="$EXPECT_COSIGN_DST" COSIGN_PIN_DIGEST="$COSIGN_PIN_DIGEST" \
      GITHUB_OUTPUT="$d/gho" GITHUB_STEP_SUMMARY="$d/sum" STUB_LOG="$d/log" STUB_COPY_COUNT="$d/copycount" STUB_COSIGN_COPY_COUNT="$d/cosigncopycount" \
      RUNNER_TEMP="$d" PIN_SHA="$PIN_SHA" EXPECT_URL="$EXPECT_URL" PATH="$STUBS:$REAL_PATH" \
      bash --noprofile --norc -eo pipefail -c 'source "$1"; echo SENTINEL_REACHED' _ "$BODY_FILE" > "$d/stdout" 2>&1
  ) || rc=$?
  echo "$rc" > "$d/rc"
}

# Counting helpers. They print a number and never fail, so a missing file reads as 0.
count_eq() { # whole lines equal to the string
  local n
  n=$(grep -cxF -- "$1" "$2" 2>/dev/null) || true
  echo "${n:-0}"
}
count_has() { # lines containing the string
  local n
  n=$(grep -cF -- "$1" "$2" 2>/dev/null) || true
  echo "${n:-0}"
}
count_pfx() { # lines STARTING with the string (a mid-line occurrence is not a workflow command)
  [[ -n "$1" ]] || { echo 0; return; }
  P="$1" awk 'index($0, ENVIRON["P"]) == 1 { n++ } END { print n + 0 }' "$2" 2>/dev/null || echo 0
}
copies() {
  if [[ -f "$1/copycount" ]]; then cat "$1/copycount"; else echo 0; fi
}
cosign_copies() {
  if [[ -f "$1/cosigncopycount" ]]; then cat "$1/cosigncopycount"; else echo 0; fi
}

# The ONE decision every caller uses: how many verdict lines are not OK. An empty or missing
# verdict file counts as bad, so an evaluate() that did nothing can never read as clean.
bad_count() {
  local n
  [[ -s "$1" ]] || { echo 1; return; }
  n=$(grep -vc "^OK"$'\t' "$1" 2>/dev/null) || true
  echo "${n:-0}"
}
# bad_has <verdicts-file> <label-substring> -> 0 if some BAD line carries the label
bad_has() {
  local bads
  [[ -n "$2" ]] || return 1
  bads=$(grep "^BAD"$'\t' "$1" 2>/dev/null | cut -f2-) || true
  [[ "$bads" == *"$2"* ]]
}

VF=""
BODY_FILE=""
chk() {
  assert_fixture_dir "$VF"
  if [[ "$1" == "1" ]]; then printf 'OK\t%s\n' "$2" >> "$VF"; else printf 'BAD\t%s\n' "$2" >> "$VF"; fi
}
# Reads a finished degrade arm and asserts the whole signal contract.
degraded_ok() { # <dir> <label> <reason> <rc> <expected-crane-copies> <expected-stub-calls: any|none>
  local a="$1" l="$2" r="$3" rc="$4" n="$5" calls="$6" ok=1
  local head="::warning::zot mirror degraded for $EXPECT_DST (reason=$r rc=$rc "
  [[ "$(cat "$a/rc")" == "0" ]] || ok=0
  [[ "$(count_eq "mirror_status=degraded" "$a/gho")" == "1" ]] || ok=0
  [[ "$(count_eq "mirror_reason=$r" "$a/gho")" == "1" ]] || ok=0
  [[ "$(count_eq "mirror_status=ok" "$a/gho")" == "0" ]] || ok=0
  [[ "$(count_pfx "$head" "$a/stdout")" == "1" ]] || ok=0
  [[ "$(count_pfx "::" "$a/stdout")" == "1" ]] || ok=0
  [[ ! -e "$a/crane.tgz" ]] || ok=0
  [[ "$(count_pfx "- zot mirror degraded (reason=$r rc=$rc)" "$a/sum")" == "1" ]] || ok=0
  [[ "$(count_eq "SENTINEL_REACHED" "$a/stdout")" == "0" ]] || ok=0
  [[ "$(copies "$a")" == "$n" ]] || ok=0
  [[ "$(count_has "REFUSE" "$a/log")" == "0" ]] || ok=0
  if [[ "$calls" == "none" ]]; then [[ ! -s "$a/log" ]] || ok=0; fi
  chk "$ok" "$l: exit 0, one anchored warning and summary line, archive removed, reason=$r rc=$rc, $n crane copies, no stub refused, shell left via exit"
}

# evaluate <workflow-file> <out-dir> <step-name> [struct|ok|failure|copyfail] -> writes <out-dir>/verdicts
# The optional 4th argument narrows the run: `struct` stops after the structural leg (mutants that only
# edit structure); an arm name runs only that behavioural arm (mutants named for that arm's checks).
evaluate() {
  local wf="$1" out="$2" name="$3" mode="${4:-full}"
  mkdir -p "$out"
  VF="$out/verdicts"
  BODY_FILE="$out/body.sh"
  assert_fixture_dir "$VF"
  : > "$VF"
  local rc=0
  python3 -I "$TMP/struct.py" "$wf" "$name" "$BODY_FILE" >> "$VF" 2> "$out/struct.err" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    printf 'BAD\tstructural leg crashed (rc=%s): %s\n' "$rc" "$(head -c 300 "$out/struct.err")" >> "$VF"
    return 0
  fi
  [[ "$mode" == "struct" ]] && return 0
  if [[ ! -s "$BODY_FILE" ]]; then
    printf 'BAD\tno step body extracted, behavioural leg cannot run\n' >> "$VF"
    return 0
  fi
  if ! bash -n "$BODY_FILE" 2>/dev/null; then
    printf 'BAD\tthe extracted body is not valid bash\n' >> "$VF"
    return 0
  fi
  local d="$out/arm" ok
  want() { [[ "$mode" == "full" || "$mode" == "$1" ]]; }

  if want ok; then
  run_arm "$d/ok" success
  ok=1
  [[ "$(cat "$d/ok/rc")" == "0" ]] || ok=0
  [[ "$(count_eq "mirror_status=ok" "$d/ok/gho")" == "1" ]] || ok=0
  [[ "$(count_has "mirror_status=degraded" "$d/ok/gho")" == "0" ]] || ok=0
  [[ "$(count_has "mirror_reason" "$d/ok/gho")" == "0" ]] || ok=0
  [[ ! -s "$d/ok/sum" ]] || ok=0
  [[ "$(count_pfx "::" "$d/ok/stdout")" == "0" ]] || ok=0
  [[ "$(copies "$d/ok")" == "1" ]] || ok=0
  [[ "$(count_eq "crane copy $EXPECT_SRC $EXPECT_DST" "$d/ok/log")" == "1" ]] || ok=0
  [[ "$(count_eq "timeout 180 crane copy $EXPECT_SRC $EXPECT_DST" "$d/ok/log")" == "1" ]] || ok=0
  [[ "$(count_eq "timeout 60 crane digest $EXPECT_DST" "$d/ok/log")" == "1" ]] || ok=0
  [[ "$(count_eq "crane digest $EXPECT_DST" "$d/ok/log")" == "1" ]] || ok=0
  [[ "$(cosign_copies "$d/ok")" == "1" ]] || ok=0
  [[ "$(count_eq "crane copy $EXPECT_COSIGN_SRC $EXPECT_COSIGN_DST" "$d/ok/log")" == "1" ]] || ok=0
  [[ "$(count_eq "timeout 180 crane copy $EXPECT_COSIGN_SRC $EXPECT_COSIGN_DST" "$d/ok/log")" == "1" ]] || ok=0
  [[ "$(count_eq "timeout 60 crane digest $EXPECT_COSIGN_DST" "$d/ok/log")" == "1" ]] || ok=0
  [[ "$(count_eq "crane digest $EXPECT_COSIGN_DST" "$d/ok/log")" == "1" ]] || ok=0
  chk "$ok" "bridge success: only mirror_status=ok, no workflow command or summary line, one bounded crane copy of the expected source and destination, one bounded digest lookup, one bounded cosign copy and cosign digest lookup"
  chk "$([[ "$(count_has "REFUSE" "$d/ok/log")" == "0" ]] && echo 1 || echo 0)" \
    "stub contracts: no stub refused its argv or pinned-value contract (bridge success)"
  chk "$([[ ! -e "$d/ok/crane.tgz" ]] && echo 1 || echo 0)" "archive removed after the step (bridge success)"
  fi

  if want failure; then

  run_arm "$d/failure" failure
  degraded_ok "$d/failure" "bridge failure" bridge_down n/a 0 none
  local b
  for b in skipped __unset__; do
    run_arm "$d/b-$b" "$b"
    degraded_ok "$d/b-$b" "bridge '$b'" bridge_down n/a 0 none
  done
  fi

  if want copyfail; then
  run_arm "$d/copyfail" success STUB_CRANE_COPY_FAIL_N=99 STUB_CRANE_COPY_RC=42
  degraded_ok "$d/copyfail" "crane copy failing every time" copy 42 3 any
  chk "$([[ "$(count_eq "sleep 3" "$d/copyfail/log")" == "1" && "$(count_eq "sleep 6" "$d/copyfail/log")" == "1" ]] && echo 1 || echo 0)" \
    "crane copy failing every time: backoff sleeps 3 then 6 between the three attempts"
  fi

  if want digestbad; then
  run_arm "$d/digestbad" success STUB_ZOT_DIGEST="$OTHER_DIGEST"
  degraded_ok "$d/digestbad" "digest mismatch after the copy" digest_mismatch 1 1 any
  fi
  if want digestfail; then
  run_arm "$d/digestfail" success STUB_DIGEST_RC=7
  degraded_ok "$d/digestfail" "crane digest lookup failing" digest_lookup 7 1 any
  fi
  if want digestshape; then
  run_arm "$d/digestshape" success STUB_ZOT_DIGEST="not-a-digest"
  degraded_ok "$d/digestshape" "crane digest returning garbage" digest_lookup 1 1 any
  fi

  if want cosigncopyfail; then
  run_arm "$d/cosigncopyfail" success STUB_CRANE_COSIGN_COPY_FAIL_N=99 STUB_CRANE_COSIGN_COPY_RC=42
  degraded_ok "$d/cosigncopyfail" "cosign copy failing every time" cosign_copy 42 1 any
  chk "$([[ "$(cosign_copies "$d/cosigncopyfail")" == "3" ]] && echo 1 || echo 0)" \
    "cosign copy failing every time: 3 cosign copy attempts, bundle copy still landed first"
  chk "$([[ "$(count_eq "sleep 3" "$d/cosigncopyfail/log")" == "1" && "$(count_eq "sleep 6" "$d/cosigncopyfail/log")" == "1" ]] && echo 1 || echo 0)" \
    "cosign copy failing every time: backoff sleeps 3 then 6 between the three attempts"
  fi

  if want cosigndigestbad; then
  run_arm "$d/cosigndigestbad" success STUB_COSIGN_ZOT_DIGEST="$OTHER_DIGEST"
  degraded_ok "$d/cosigndigestbad" "cosign digest mismatch after the copy" cosign_digest_mismatch 1 1 any
  fi

  if want cosigndigestfail; then
  run_arm "$d/cosigndigestfail" success STUB_COSIGN_DIGEST_RC=7
  degraded_ok "$d/cosigndigestfail" "cosign digest lookup failing" cosign_digest_lookup 7 1 any
  fi

  if [[ "$mode" != "full" ]]; then return 0; fi
  run_arm "$d/copyflaky" success STUB_CRANE_COPY_FAIL_N=2
  ok=1
  [[ "$(cat "$d/copyflaky/rc")" == "0" ]] || ok=0
  [[ "$(count_eq "mirror_status=ok" "$d/copyflaky/gho")" == "1" ]] || ok=0
  [[ "$(count_has "mirror_reason" "$d/copyflaky/gho")" == "0" ]] || ok=0
  [[ ! -s "$d/copyflaky/sum" ]] || ok=0
  [[ "$(count_pfx "::" "$d/copyflaky/stdout")" == "0" ]] || ok=0
  [[ "$(copies "$d/copyflaky")" == "3" ]] || ok=0
  [[ "$(cosign_copies "$d/copyflaky")" == "1" ]] || ok=0
  [[ "$(count_eq "crane copy $EXPECT_COSIGN_SRC $EXPECT_COSIGN_DST" "$d/copyflaky/log")" == "1" ]] || ok=0
  [[ "$(count_eq "timeout 60 crane digest $EXPECT_COSIGN_DST" "$d/copyflaky/log")" == "1" ]] || ok=0
  [[ "$(count_has "REFUSE" "$d/copyflaky/log")" == "0" ]] || ok=0
  chk "$ok" "crane copy failing twice then succeeding: mirror_status=ok after 3 attempts, no warning or summary line"

  run_arm "$d/shabad" success STUB_SHA_RC=3
  degraded_ok "$d/shabad" "checksum mismatch" crane_checksum 3 0 any
  chk "$([[ "$(count_has "sudo " "$d/shabad/log")" == "0" ]] && echo 1 || echo 0)" \
    "checksum mismatch: nothing is extracted (sudo never invoked)"

  run_arm "$d/curlbad" success STUB_CURL_RC=22
  degraded_ok "$d/curlbad" "crane download failing" crane_download 22 0 any
  chk "$([[ "$(count_has "sha256sum" "$d/curlbad/log")" == "0" ]] && echo 1 || echo 0)" \
    "crane download failing: no checksum is attempted on a missing archive"

  run_arm "$d/tarbad" success STUB_SUDO_RC=5
  degraded_ok "$d/tarbad" "crane extract failing" crane_extract 5 0 any
}

# ---------------------------------------------------------------------------
# Mutation helper: apply one named mutation to a copy of the workflow.
# ---------------------------------------------------------------------------
cat > "$TMP/mutate.py" <<'PY'
import re
import sys

name, src, dst = sys.argv[1:4]
s = open(src).read()
MIRROR = "      - name: Mirror bundle GHCR->zot (crane, digest-preserving)\n"
BRIDGE = "      - name: Bridge to zot registry (CF Tunnel)\n"
TEARDOWN = "      - name: Tear down cloudflared registry bridge\n"
BRANCH = re.compile(r'          if \[\[ "\$\{BRIDGE_OUTCOME:-\}" != "success" \]\]; then\n[^\n]*\n          fi\n')


def must_sub(pattern, repl, text, flags=re.S):
    out, n = re.subn(pattern, repl, text, count=1, flags=flags)
    if n != 1:
        sys.exit(3)
    return out


def insert_before(marker, extra, text):
    if text.count(marker) != 1:
        sys.exit(3)
    return text.replace(marker, extra + marker)


if name == "regate-on-bridge":
    s = must_sub(r"(id: zot_mirror\n\s+if: ).*?\n", r"\1steps.zot_bridge.outcome == 'success'\n", s)
elif name == "bridge-loses-continue-on-error":
    s = must_sub(r"(id: zot_bridge\n\s+if: [^\n]*\n)\s+continue-on-error: true\n", r"\1", s)
elif name == "second-gated-step":
    s = insert_before(TEARDOWN, "      - name: Late mirror note\n        if: steps.zot_bridge.outcome == 'success'\n        run: echo noted\n\n", s)
elif name == "second-gated-step-bracket":
    s = insert_before(TEARDOWN, "      - name: Late mirror note\n        if: steps['Zot_Bridge'].outcome == 'success'\n        run: echo noted\n\n", s)
elif name == "env-uses-conclusion":
    s = must_sub(r"(BRIDGE_OUTCOME: \$\{\{ steps\.zot_bridge\.)outcome", r"\1conclusion", s)
elif name == "mirror-before-bridge":
    i_b, i_m, i_t = s.index(BRIDGE), s.index(MIRROR), s.index(TEARDOWN)
    s = s[:i_b] + s[i_m:i_t] + s[i_b:i_m] + s[i_t:]
elif name == "rename-step":
    s = must_sub(re.escape("- name: Mirror bundle GHCR->zot (crane"), "- name: Mirror bundle GHCR to zot (crane", s)
elif name == "hard-step-between":
    s = insert_before(MIRROR, "      - name: Late hard step\n        run: echo hard\n\n", s)
elif name == "rename-docker-build-id":
    s = must_sub(r"id: docker_build\n", "id: build\n", s)
elif name == "shell-sh":
    s = must_sub(r"(id: zot_mirror\n)", r"\1        shell: sh\n", s)
elif name == "delete-bridge-branch":
    s = must_sub(BRANCH.pattern, "", s, 0)
elif name == "degraded-returns":
    s = must_sub(r"(degraded\(\) \{.*?)exit 0", r"\1return 0", s)
elif name == "degraded-exit-1":
    s = must_sub(r"(degraded\(\) \{.*?)exit 0", r"\1exit 1", s)
elif name == "drop-copy-route":
    s = must_sub(r"(retry timeout 180 crane copy [^\n]*?) \|\| degraded copy [^\n]*\n", r"\1\n", s)
elif name == "rc-lost":
    s = must_sub(r'degraded copy "\$\?"', "degraded copy 0", s)
elif name == "install-before-branch":
    m = BRANCH.search(s)
    if not m:
        sys.exit(3)
    s = s.replace(m.group(0), "", 1)
    s = insert_before("          # Each attempt is bounded", m.group(0), s)
elif name == "ok-publishes-degraded":
    s = must_sub(r'(echo "mirror_status=ok" >> "\$GITHUB_OUTPUT"\n)', r'\1          echo "mirror_status=degraded" >> "$GITHUB_OUTPUT"\n', s)
elif name == "checksum-flag-dropped":
    s = must_sub(r"\| sha256sum -c -", "| sha256sum -", s)
elif name == "curl-flag-dropped":
    s = must_sub(r"curl -fsSL --max-time", "curl -sSL --max-time", s)
elif name == "extract-dir-moved":
    s = must_sub(r"-C /usr/local/bin crane", "-C /tmp crane", s)
elif name == "crane-sha-changed":
    s = must_sub(r'(CRANE_SHA256=")c', r"\g<1>d", s)
elif name == "crane-version-changed":
    s = must_sub(r'CRANE_VERSION="v0\.20\.2"', 'CRANE_VERSION="v0.20.3"', s)
elif name == "crane-arch-changed":
    s = must_sub(r"Linux_x86_64", "Linux_arm64", s)
elif name == "download-path-decoupled":
    s = must_sub(r'-o "\$CRANE_TGZ"', '-o "$RUNNER_TEMP/other.tgz"', s)
elif name == "backoff-removed":
    s = must_sub(r"sleep \$\(\(n \* 3\)\)", "true", s)
elif name == "retry-returns-1":
    s = must_sub(r'return "\$rc"; sleep', "return 1; sleep", s)
elif name == "drop-cleanup":
    s = must_sub(r"          trap 'rm -f \"\$CRANE_TGZ\"' EXIT\n", "", s)
elif name == "drop-step-timeout":
    s = must_sub(r"        timeout-minutes: 20\n", "", s)
elif name == "digest-check-dropped":
    s = must_sub(r'          \[\[ "\$ZOT_DIGEST" == "\$\{DIGEST:-\}" \]\] \|\| degraded digest_mismatch[^\n]*\n', "", s)
elif name == "digest-lookup-unrouted":
    s = must_sub(r' \|\| degraded digest_lookup "\$\?" "crane digest lookup failed after the copy"', "", s)
elif name == "digest-shape-unchecked":
    s = must_sub(r'          \[\[ "\$ZOT_DIGEST" =~ \^sha256[^\n]*\n', "", s)
elif name == "curl-timeout-dropped":
    s = must_sub(r"curl -fsSL --max-time 120 -o", "curl -fsSL -o", s)
elif name == "copy-timeout-dropped":
    s = must_sub(r"retry timeout 180 crane copy", "retry crane copy", s)
elif name == "digest-timeout-dropped":
    s = must_sub(r'"\$\(timeout 60 crane digest', '"$(crane digest', s)
elif name == "sign-drops-yes":
    s = must_sub(r"cosign sign-blob --yes", "cosign sign-blob", s)
elif name == "sign-drops-bundle":
    s = must_sub(r'\n            --bundle "\$\{MANIFEST\}\.sigstore\.json" \\', "", s)
elif name == "sign-renames-bundle":
    s = must_sub(r'--bundle "\$\{MANIFEST\}\.sigstore\.json"', '--bundle "${MANIFEST}.sig.json"', s)
elif name == "sign-adds-output-signature":
    s = must_sub(r"(cosign sign-blob --yes \\\n)",
                 "\\1            --output-signature \"${MANIFEST}.sig\" \\\n", s)
elif name == "sign-adds-output-certificate":
    s = must_sub(r"(cosign sign-blob --yes \\\n)",
                 "\\1            --output-certificate \"${MANIFEST}.cert\" \\\n", s)
elif name == "sign-step-deleted":
    s = must_sub(r"      - name: Keyless sign-blob the manifest.*?      - name: Assemble",
                 "      - name: Assemble", s)
elif name == "dockerfile-cmd-dropped":
    s = must_sub(r'CMD \["true"\]\\n', "", s)
elif name == "cosign-copy-dropped":
    s = must_sub(r'          retry timeout 180 crane copy "gcr\.io/projectsigstore/cosign[^\n]*\n', "", s)
elif name == "cosign-copy-route-dropped":
    s = must_sub(r'(retry timeout 180 crane copy "gcr\.io/projectsigstore/cosign[^\n]*?) \|\| degraded cosign_copy [^\n]*\n', r"\1\n", s)
elif name == "cosign-digest-check-dropped":
    s = must_sub(r'          \[\[ "\$COSIGN_ZOT_DIGEST" == "sha256:[^\n]*\|\| degraded cosign_digest_mismatch[^\n]*\n', "", s)
elif name == "cosign-dst-retargeted":
    s = must_sub(r'jikig-ai/cosign:v3\.1\.1', "jikig-ai/cosign-tools:v3.1.1", s)
elif name == "variant-no-if":
    s = must_sub(r"(id: zot_mirror\n)\s+if: [^\n]*\n", r"\1", s)
elif name == "variant-reworded":
    i_m, i_t = s.index(MIRROR), s.index(TEARDOWN)
    seg = re.sub(r"(\n\s+# [^\n]*)", r"\1 (reworded)", s[i_m:i_t])
    seg = must_sub(r"(\n\s+DIGEST: [^\n]*)(\n\s+BRIDGE_OUTCOME: [^\n]*)", r"\2\1", seg)
    s = s[:i_m] + seg + s[i_t:]
else:
    sys.exit(4)
open(dst, "w").write(s)
PY

# ---------------------------------------------------------------------------
# Self-test of the decisions every verdict goes through: they must be able to say no.
# ---------------------------------------------------------------------------
echo "T0: the verdict decisions can say no"
printf 'OK\tx\n' > "$TMP/v-ok"
printf 'OK\tx\nBAD\tthe y check\n' > "$TMP/v-bad"
: > "$TMP/v-empty"
[[ "$(bad_count "$TMP/v-ok")" == "0" ]] && pass "bad_count: an all-OK file is clean" || fail "bad_count: an all-OK file read as bad"
[[ "$(bad_count "$TMP/v-bad")" == "1" ]] && pass "bad_count: one BAD line counts" || fail "bad_count: a BAD line was not counted"
[[ "$(bad_count "$TMP/v-empty")" != "0" ]] && pass "bad_count: an empty verdict file is bad, never clean" || fail "bad_count: an empty verdict file read as clean"
if bad_has "$TMP/v-bad" "the y check"; then pass "bad_has: finds the named BAD label"; else fail "bad_has: missed a present label"; fi
if bad_has "$TMP/v-bad" "no such label"; then fail "bad_has: matched an absent label"; else pass "bad_has: rejects an absent label"; fi
if bad_has "$TMP/v-bad" "x"; then fail "bad_has: matched a label that only an OK line carries"; else pass "bad_has: ignores OK lines"; fi
printf 'prefix ::warning::mid-line\n::warning::at start\n' > "$TMP/v-pfx"
[[ "$(count_pfx "::" "$TMP/v-pfx")" == "1" ]] && pass "count_pfx: only a line-start workflow command counts" || fail "count_pfx: counted a mid-line occurrence"
[[ "$(count_pfx "" "$TMP/v-pfx")" == "0" ]] && pass "count_pfx: an empty prefix counts nothing" || fail "count_pfx: an empty prefix matched lines"
printf 'OK\tx\n\nOKAY\tz\n' > "$TMP/v-odd"
[[ "$(bad_count "$TMP/v-odd")" == "2" ]] && pass "bad_count: a blank line and a non-OK verb both count as bad" || fail "bad_count: a blank line or OKAY read as clean"
if bad_has "$TMP/v-bad" ""; then fail "bad_has: an empty label matched"; else pass "bad_has: rejects an empty label"; fi
if bad_has "$TMP/v-bad" "BAD"; then fail "bad_has: matched the verdict word instead of the label"; else pass "bad_has: matches the label field only"; fi

# ---------------------------------------------------------------------------
# Canonical evaluation
# ---------------------------------------------------------------------------
echo "T1: canonical workflow passes every structural and behavioural check"
evaluate "$WF" "$TMP/canon" "$STEP_NAME"
CANON_RED=0
if [[ "$(bad_count "$TMP/canon/verdicts")" != "0" ]]; then CANON_RED=1; fi
while IFS=$'\t' read -r verdict label; do
  if [[ "$verdict" == "OK" ]]; then pass "$label"; else fail "$label"; fi
done < "$TMP/canon/verdicts"

# ---------------------------------------------------------------------------
# Mutation battery. Every mutation is asserted to CHANGE the workflow before the evaluator
# runs (a pattern that stopped matching would otherwise become a silent no-op that scores as
# "the guard held"), then the SAME evaluator must report a BAD check carrying the label the
# mutation is named for (a mutant that merely breaks the YAML scores nothing).
# row: <name>|<struct|ok|failure|copyfail>|<expected BAD label substring(s), ';'-separated>
# (the kind is the one behavioural arm that carries the label; struct stops after the structural leg)
# ---------------------------------------------------------------------------
echo "T2: mutation battery (each mutant must differ from canonical and fail the check it is named for)"
if [[ "$CANON_RED" -ne 0 ]]; then
  echo "  battery skipped: the canonical workflow is itself RED, so mutant verdicts would be meaningless"
else
  ROWS=(
    "regate-on-bridge|struct|mirror step gate;reads steps.zot_bridge"
    "bridge-loses-continue-on-error|struct|bridge-action step"
    "second-gated-step|struct|reads steps.zot_bridge"
    "second-gated-step-bracket|struct|reads steps.zot_bridge"
    "env-uses-conclusion|struct|BRIDGE_OUTCOME is wired"
    "mirror-before-bridge|struct|share the mirror's job"
    "rename-step|struct|found exactly once"
    "hard-step-between|struct|between docker_build"
    "rename-docker-build-id|struct|share the mirror's job"
    "shell-sh|struct|shell is absent or bash"
    "drop-step-timeout|struct|timeout-minutes bound"
    "delete-bridge-branch|failure|bridge failure"
    "degraded-returns|failure|bridge failure"
    "degraded-exit-1|failure|bridge failure"
    "install-before-branch|failure|bridge failure"
    "drop-copy-route|copyfail|crane copy failing every time"
    "rc-lost|copyfail|crane copy failing every time"
    "retry-returns-1|copyfail|crane copy failing every time"
    "backoff-removed|copyfail|backoff sleeps"
    "ok-publishes-degraded|ok|bridge success"
    "checksum-flag-dropped|ok|stub contracts"
    "curl-flag-dropped|ok|stub contracts"
    "extract-dir-moved|ok|stub contracts"
    "crane-sha-changed|ok|stub contracts"
    "crane-version-changed|ok|stub contracts"
    "crane-arch-changed|ok|stub contracts"
    "download-path-decoupled|ok|stub contracts"
    "drop-cleanup|ok|archive removed"
    "curl-timeout-dropped|ok|stub contracts"
    "copy-timeout-dropped|ok|bridge success"
    "digest-timeout-dropped|ok|bridge success"
    "digest-check-dropped|digestbad|digest mismatch after the copy"
    "digest-lookup-unrouted|digestfail|crane digest lookup failing"
    "digest-shape-unchecked|digestshape|crane digest returning garbage"
    "sign-drops-yes|struct|sign-blob runs once with --yes"
    "sign-drops-bundle|struct|via --bundle"
    "sign-renames-bundle|struct|via --bundle"
    "sign-adds-output-signature|struct|no removed cosign-2.x"
    "sign-adds-output-certificate|struct|no removed cosign-2.x"
    "sign-step-deleted|struct|exactly one step invokes cosign sign-blob"
    "dockerfile-cmd-dropped|struct|carries a CMD"
    "cosign-copy-dropped|struct|cosign verifier image is copied"
    "cosign-copy-route-dropped|cosigncopyfail|cosign copy failing every time"
    "cosign-digest-check-dropped|cosigndigestbad|cosign digest mismatch after the copy"
    "cosign-dst-retargeted|struct|cosign mirror destination"
  )
  for row in "${ROWS[@]}"; do
    IFS='|' read -r m kind expect <<< "$row"
    mwf="$TMP/mut-$m.yml"
    mrc=0
    python3 -I "$TMP/mutate.py" "$m" "$WF" "$mwf" 2>/dev/null || mrc=$?
    if [[ "$mrc" -ne 0 ]]; then
      fail "mutation $m did not apply (rc=$mrc): the battery pattern drifted from the workflow"
      continue
    fi
    if cmp -s "$WF" "$mwf"; then
      fail "mutation $m produced a copy identical to canonical"
      continue
    fi
    evaluate "$mwf" "$TMP/mut-$m.out" "$STEP_NAME" "$kind"
    IFS=';' read -ra labels <<< "$expect"
    for label in "${labels[@]}"; do
      if bad_has "$TMP/mut-$m.out/verdicts" "$label"; then
        pass "mutation $m fails the check named '$label'"
      else
        fail "mutation $m SURVIVED the check named '$label' (bad lines: $(bad_count "$TMP/mut-$m.out/verdicts"))"
      fi
    done
  done

  # Harness row: a wrong step name must fail on the empty extraction, never pass with zero arms.
  evaluate "$WF" "$TMP/wrongname.out" "No such step name"
  if bad_has "$TMP/wrongname.out/verdicts" "found exactly once"; then
    pass "a wrong extractor step name reds the evaluator instead of passing with zero arms"
  else
    fail "a wrong extractor step name left the evaluator GREEN (the guard dispatches nothing)"
  fi

  # Must-pass non-canonical variants: a guard that rejects everything cannot pass these.
  for m in variant-no-if variant-reworded; do
    mwf="$TMP/mut-$m.yml"
    mrc=0
    python3 -I "$TMP/mutate.py" "$m" "$WF" "$mwf" 2>/dev/null || mrc=$?
    if [[ "$mrc" -ne 0 ]] || cmp -s "$WF" "$mwf"; then
      fail "variant $m did not produce a changed copy (rc=$mrc)"
      continue
    fi
    evaluate "$mwf" "$TMP/mut-$m.out" "$STEP_NAME"
    if [[ "$(bad_count "$TMP/mut-$m.out/verdicts")" == "0" ]]; then
      pass "non-canonical variant $m still passes (the guard accepts every contract-legal shape)"
    else
      fail "non-canonical variant $m was REJECTED ($(bad_count "$TMP/mut-$m.out/verdicts") failing checks)"
    fi
  done
fi

echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
# ANTI-VACUITY FLOOR. Equal to the green-run count: raise it in the same edit that adds a case. It sits
# directly above its `if` so guard-vacuity-floor can slice it.
MIN_ASSERTIONS=105
if (( PASS + FAIL < MIN_ASSERTIONS )); then
  echo "FATAL: only $((PASS + FAIL)) assertions ran (floor $MIN_ASSERTIONS); the suite did not execute what it claims to." >&2
  exit 1
fi
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
