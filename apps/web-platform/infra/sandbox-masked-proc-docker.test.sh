#!/usr/bin/env bash
# Would-have-caught regression for the #9860 / #10032 sandbox outage class.
#
# THE FAILURE CLASS. A fresh procfs mount inside bubblewrap's nested user namespace is refused (EPERM,
# "bwrap: Can't mount proc on /newroot/proc: Operation not permitted") under docker's DEFAULT masked /proc:
# the masks are init-userns-owned, the new userns inherits them as locked mounts, and the kernel's
# mount_too_revealing check refuses. The #9723 shim spliced exactly such a mount as its cross-tenant mask, so every
# sandboxed spawn failed closed from 2026-10-09. Every shim test that ran on an unmasked host was green, and the
# canary that would have caught it is report-only. PR #10039 changed the shim to DROP procfs mounts (the vendored
# `--tmpfs /proc` is the mask) and measured the fix in an image by hand; nothing in CI did.
#
# WHAT THIS PROVES, in a container carrying the production posture. The posture is DERIVED, not copied: the docker run
# options come from the parsed prod tuple (lib/docker-run-tuple.py), the base image from the Dockerfile's runner ->
# cli-tools lineage, the uid from the Dockerfile's useradd, and the isolation argv from the committed canary fixture
# (sandbox-canary-argv.json). The container carries the committed seccomp profile, the committed `soleur-bwrap`
# AppArmor profile, uid 1001, the Debian bubblewrap the production base installs, docker's DEFAULT masks, NO systempaths
# override.
#   static     the three app-container docker run tuples are a closed set (no appended --cap-add, --pid=host,
#              systempaths=unconfined, -e PATH=...); the base lineage and `ENV PATH` order match what the runner ships;
#              the fixture carries the vendor tail this suite replays. All of it runs before any docker call.
#   control    the historical shape — the vendored tail bind plus a fresh `--proc /proc`, through the REAL bwrap —
#              is REFUSED with "mount proc". This proves the runner really has masks, i.e. that the suite can fail.
#   treatment  the canary replay through the SHIPPED shim passes (the fixture argv, tail bind and all).
#   isolation  through the shim a process started OUTSIDE the sandbox, in the same pid namespace, is ABSENT from the
#              sandbox's /proc and /proc lists no pid directory at all; through the real bwrap with the vendor tail
#              bind the same process is VISIBLE (so the assertion discriminates).
#   recorder   the argv the REAL bwrap receives from the shim carries no argv-requested procfs mount at /proc and
#              exactly one `--tmpfs /proc`: the shim DROPS the vendor bind, it does not cover it.
#   c4 replay  the C4 render sandbox argv (it bypasses the shim, /usr/bin/bwrap absolute) runs under the masks.
#   wrapped    (#10445) a scripted Bash call through the REAL Agent SDK (infra/lib/sdk-bash-probe.mjs) under the same
#              posture. CONTROL (network.allowAllUnixSockets unset): the SDK wraps the command in its `apply-seccomp`
#              helper, whose unshare(CLONE_NEWUSER) our shim filter denies, and the tool_result is
#              `apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted` (the committed RCA reproduction).
#              TREATMENT (knob set, as the production config sets it): the command's own stdout comes back.
#   census     (#10445) every pathname socket visible from inside that sandbox is one of the SDK's own proxy bridge
#              sockets under /tmp; a host runtime socket (docker, dbus) or any other path is a red.
#
# WHAT THE BEHAVIORAL ARMS CANNOT SEPARATE (measured, #10065 measurements.md M3). A cover (`--tmpfs /proc` over the
# kept vendor bind) and a drop give the SAME observations here: the vendor argv starts with a recursive `--ro-bind / /`,
# so the container's procfs sits beneath the tmpfs after either, and no process in an unprivileged bwrap sandbox holds
# a capability that could uncover it (every umount2 attempt is EPERM in every arm, with or without --cap-add; the
# attribution to the vendor's `--cap-drop ALL` is INFERRED, not measured, and holds only for an unelevated bwrap, and no
# positive control exists). The recorder arm is the only discriminator, and it measures the shim's contract, "no
# argv-requested procfs mount", not a kernel-level absence. The vendor's `--cap-drop ALL` is pinned by
# test/sandbox-vendored-argv-tail.test.ts, and the app container tuples keep their posture (infra/lib/docker-run-tuple.py).
#
# NOT COVERED HERE. The outer-wrap spawn (agent-outer-wrap.ts, /usr/bin/bwrap): its table carries the outer-wrap
# elevation expectation, which the suite image's plain Debian bubblewrap does not meet, so `sandbox-canary.mjs --replay-outer` here
# reports sandbox_broken/wrong_elevation_userns, a verdict unrelated to /proc (measured). A weaker assertion would pass
# for the wrong reason, so only the static pins run (test/c4-render-argv-fixture.test.ts, agent-outer-wrap.test.ts).
# The isolation argv omits the fixture's `--unshare-net`: the arm measures /proc visibility and a netns changes
# nothing about it.
#
# NEVER SELF-SKIPS. An unusable environment fails with a literal token and exit 1 (DOCKER_UNAVAILABLE,
# APPARMOR_UNAVAILABLE, SYSCTL_UNAVAILABLE, IMAGE_BUILD_FAILED, CONTAINER_START_FAILED, IMAGE_DRIFT, TUPLE_CHECK,
# FIXTURE_TAIL, BASE_LINEAGE, PATH_ORDER, ELEVATION, USER_DRIFT, DROP_FAILED, SRC_ROOT_REFUSED, MUTATION_UNKNOWN,
# MUTATION_NOT_APPLIED) — the opposite of sandbox-canary-regression.test.sh section B, whose never-fail
# classification is the property that let this class ship.
#
# PRIVILEGED. Loads an AppArmor profile (apparmor_parser) and sets a sysctl, so it is invoked under `sudo` from the
# deploy-script-tests-fixed job (run-registered-suites.sh PRIVILEGED_WHY). On a host without AppArmor a LOCAL dev run
# may set SOLEUR_SANDBOX_DOCKER_APPARMOR=unconfined to measure the docker-mask delta alone; the override is refused
# when CI is set, prints APPARMOR_OVERRIDE, and does not discharge the AppArmor half (CI does).
#
# MUTATION SEAMS (battery only; each must drive the suite RED):
#   SANDBOX_MASKED_PROC_MUTATE =
#     shim-splice | shim-bypass | shim-cover | shim-path | control-unmasked | sleeper-after | no-replay | knob-off
#   SANDBOX_MASKED_PROC_SRC_ROOT = a COPY of apps/web-platform whose Dockerfile, canary fixture and docker run tuples
#     the static arms read (refused when CI is set). The mounted /app, shim and seccomp profile stay the real ones.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SHIM="$SCRIPT_DIR/bwrap-shim/bwrap"
SECCOMP="$SCRIPT_DIR/seccomp-bwrap.json"
APPARMOR_PROFILE="$SCRIPT_DIR/apparmor-soleur-bwrap.profile"
TUPLE_PY="$SCRIPT_DIR/lib/docker-run-tuple.py"
MUTATE="${SANDBOX_MASKED_PROC_MUTATE:-}"
case "$MUTATE" in
  ""|shim-splice|shim-bypass|shim-cover|shim-path|control-unmasked|sleeper-after|no-replay|knob-off) : ;;
  *) echo "FAIL: MUTATION_UNKNOWN: SANDBOX_MASKED_PROC_MUTATE='$MUTATE' is not a seam of this suite (a typo would otherwise run the unmutated baseline and read as a surviving mutant)"; exit 1 ;;
esac
IMG="soleur-masked-proc-regression:$$"
CTR="smp$$"
WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/sandbox-masked-proc.XXXXXXXX")"
# The bounded-apt lib (also used by the image build below) carries the repo's canonical fixture-dir guard: an empty,
# relative or root-like TMPDIR must end the shell before any rm -rf or redirect below is rooted at it.
APT_LIB="${SCRIPT_DIR}/lib/apt-bounded.sh"
[[ -r "$APT_LIB" ]] || { echo "FAIL: IMAGE_BUILD_FAILED: ${APT_LIB} is missing, the apt cycle could not be bounded"; exit 1; }
# shellcheck source=lib/apt-bounded.sh
. "$APT_LIB"
assert_fixture_dir "$WORK"
PASS=0
FAIL=0

pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
die() { echo "$1" >&2; echo "FAIL: $1"; exit 1; }

cleanup() {
  assert_fixture_dir "$WORK"
  docker rm -f "$CTR" "$CTR-build" "$CTR-ctrl" "$CTR-pos" >/dev/null 2>&1 || true
  docker rmi -f "$IMG" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# The static arms read a source root. Default is this tree; the battery points it at a mutated copy.
SRC_ROOT="$APP_DIR"
if [[ -n "${SANDBOX_MASKED_PROC_SRC_ROOT:-}" ]]; then
  [[ -z "${CI:-}" ]] || die "SRC_ROOT_REFUSED: SANDBOX_MASKED_PROC_SRC_ROOT is a battery seam and is refused when CI is set"
  [[ "$SANDBOX_MASKED_PROC_SRC_ROOT" == /* && -d "$SANDBOX_MASKED_PROC_SRC_ROOT" ]] \
    || die "SRC_ROOT_REFUSED: SANDBOX_MASKED_PROC_SRC_ROOT must be an existing absolute directory"
  SRC_ROOT="$SANDBOX_MASKED_PROC_SRC_ROOT"
fi
DOCKERFILE="$SRC_ROOT/Dockerfile"
FIXTURE="$SRC_ROOT/infra/sandbox-canary-argv.json"
C4_FIXTURE="$SRC_ROOT/infra/c4-render-sandbox-argv.json"

for f in "$SHIM" "$SECCOMP" "$APPARMOR_PROFILE" "$DOCKERFILE" "$APP_DIR/scripts/sandbox-canary.mjs" "$FIXTURE" "$C4_FIXTURE" "$APP_DIR/infra/sandbox-canary-argv.json" "$TUPLE_PY"; do
  [[ -f "$f" ]] || die "ERROR missing input $f"
done

echo "=== sandbox masked-/proc docker regression (#9860 / #10032 / #10065) ==="

# ---------------------------------------------------------------------------
# Static arms — no docker daemon needed, so a drifted tuple, lineage, PATH or fixture is red on any runner.
# ---------------------------------------------------------------------------
command -v python3 >/dev/null 2>&1 || die "TUPLE_CHECK: python3 is required to parse the docker run tuples"
command -v jq >/dev/null 2>&1 || die "FIXTURE_TAIL: jq is required to derive the isolation argv from the canary fixture"

# 1. The three app-container docker run tuples are a closed set (canary and prod in ci-deploy.sh, first boot in
#    cloud-init.yml). The helper prints one FAIL line per violation and exits 1.
TUPLE_OUT="$(python3 -I "$TUPLE_PY" check --root "$SRC_ROOT" 2>&1)"
TUPLE_RC=$?
if [[ "$TUPLE_RC" -eq 0 && "$TUPLE_OUT" == "docker-run-tuple:ok tuples=3 "* ]]; then
  pass "static: the three app-container docker run tuples are a closed set (${TUPLE_OUT})"
else
  echo "$TUPLE_OUT"
  die "TUPLE_CHECK: docker-run-tuple.py check rc=$TUPLE_RC: $(printf '%s' "$TUPLE_OUT" | head -c 1200) -- reproduce without docker in one second: python3 -I apps/web-platform/infra/lib/docker-run-tuple.py check"
fi

# 1b. The container's docker options are the PROD tuple's posture, line by line (`--opt value`). The seccomp path is the host
#     path production uses; the suite maps it to its own checkout copy and the apparmor value to the local override. An
#     option this suite does not know how to map is refused rather than dropped.
POSTURE_RAW="$(python3 -I "$TUPLE_PY" posture --tuple prod --root "$SRC_ROOT" 2>"$WORK/posture.err")"
POSTURE_RC=$?
[[ "$POSTURE_RC" -eq 0 && -n "$POSTURE_RAW" ]] || die "TUPLE_CHECK: posture --tuple prod rc=$POSTURE_RC: $(head -c 300 "$WORK/posture.err")"
POSTURE_OPTS=()
POSTURE_SEEN_AA=0
POSTURE_SEEN_SC=0
while IFS= read -r pline; do
  popt="${pline%% *}"
  pval=""
  [[ "$pline" == *" "* ]] && pval="${pline#* }"
  case "$popt $pval" in
    "--init ") POSTURE_OPTS+=(--init) ;;
    "--tmpfs /tmp:"*) POSTURE_OPTS+=(--tmpfs "$pval") ;;
    "--security-opt apparmor="*) POSTURE_OPTS+=(--security-opt "apparmor=@APPARMOR@"); POSTURE_SEEN_AA=$((POSTURE_SEEN_AA + 1)) ;;
    "--security-opt seccomp="*) POSTURE_OPTS+=(--security-opt "seccomp=@SECCOMP@"); POSTURE_SEEN_SC=$((POSTURE_SEEN_SC + 1)) ;;
    *) die "TUPLE_CHECK: the prod tuple posture carries '$pline', which this suite has no mapping for" ;;
  esac
done <<<"$POSTURE_RAW"
[[ "$POSTURE_SEEN_AA" -eq 1 && "$POSTURE_SEEN_SC" -eq 1 ]] \
  || die "TUPLE_CHECK: the prod tuple posture has $POSTURE_SEEN_AA apparmor and $POSTURE_SEEN_SC seccomp entries (expected one each)"
pass "static: the container options are derived from the prod tuple posture (${#POSTURE_OPTS[@]} tokens: $(printf '%s ' "${POSTURE_OPTS[@]}"))"

# 2. Dockerfile stage graph: runner is FROM cli-tools, cli-tools is FROM the pinned image, and every direct-image
#    stage carries that same reference. The suite's base is the lineage runner ships, not the first FROM line.
STAGE_NAMES=()
STAGE_REFS=()
while IFS=$'\t' read -r st_name st_ref; do
  STAGE_NAMES+=("$st_name")
  STAGE_REFS+=("$st_ref")
done < <(awk '
  { line = $0; sub(/^[[:space:]]+/, "", line) }
  toupper(substr(line, 1, 5)) == "FROM " {
    n = split(line, t, /[[:space:]]+/); i = 2
    if (t[i] ~ /^--/) i++
    name = "-"
    if (toupper(t[i + 1]) == "AS" && t[i + 2] != "") name = tolower(t[i + 2])
    print name "\t" t[i]
  }' "$DOCKERFILE")
stage_ref() { # <stage name> -> its FROM reference (empty when the stage does not exist)
  local i
  for i in "${!STAGE_NAMES[@]}"; do
    [[ "${STAGE_NAMES[i]}" == "$1" ]] && { printf '%s' "${STAGE_REFS[i]}"; return 0; }
  done
  return 0
}
is_stage() { [[ -n "$(stage_ref "$1")" ]]; }
(( ${#STAGE_NAMES[@]} > 0 )) || die "BASE_LINEAGE: no FROM instruction was parsed from $DOCKERFILE (the static arms run before any docker call: test/docker-run-tuple-posture.test.ts drives them with a stub docker on any host)"
RUNNER_FROM="$(stage_ref runner)"
[[ -n "$RUNNER_FROM" ]] || die "BASE_LINEAGE: $DOCKERFILE has no stage named runner"
[[ "$RUNNER_FROM" == "cli-tools" ]] || die "BASE_LINEAGE: runner is FROM '$RUNNER_FROM', the shipped lineage is runner -> cli-tools"
BASE="$(stage_ref cli-tools)"
[[ "$BASE" =~ ^[A-Za-z0-9._/-]+:[A-Za-z0-9._-]+@sha256:[0-9a-f]{64}$ ]] \
  || die "BASE_LINEAGE: cli-tools is FROM '$BASE', not a digest-pinned image reference"
for i in "${!STAGE_NAMES[@]}"; do
  if ! is_stage "${STAGE_REFS[i]}" && [[ "${STAGE_REFS[i]}" != "$BASE" ]]; then
    die "BASE_LINEAGE: stage ${STAGE_NAMES[i]} is FROM ${STAGE_REFS[i]} but the runner lineage base is $BASE"
  fi
done
pass "static: the base image follows the runner -> cli-tools lineage ($BASE)"

# 3. PATH order: no ENV instruction in the runner lineage may put /usr/bin before /usr/local/bin. The suite's container
#    is built from the base image and cannot see a runner-stage ENV PATH, so this static arm is what sees it.
BASE_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
path_order_ok() { # <expanded PATH value> — /usr/local/bin must precede /usr/bin when both are present
  local v="$1" i li=-1 ui=-1 idx=0 part
  local -a parts
  IFS=':' read -r -a parts <<<"$v"
  for part in "${parts[@]}"; do
    [[ "$part" == /usr/local/bin && "$li" -lt 0 ]] && li=$idx
    [[ "$part" == /usr/bin && "$ui" -lt 0 ]] && ui=$idx
    idx=$((idx + 1))
  done
  [[ "$ui" -lt 0 ]] && return 0
  [[ "$li" -ge 0 && "$li" -lt "$ui" ]]
}
PATH_ENVS=0
CUR_STAGE=""
while IFS= read -r dline; do
  dline="${dline#"${dline%%[![:space:]]*}"}"
  case "${dline^^}" in
    "FROM "*)
      CUR_STAGE="-"
      read -r -a ftok <<<"$dline"
      fi=1; [[ "${ftok[1]:-}" == --* ]] && fi=2
      [[ "${ftok[fi + 1]:-}" =~ ^[Aa][Ss]$ && -n "${ftok[fi + 2]:-}" ]] && CUR_STAGE="${ftok[fi + 2],,}"
      ;;
    "ENV "*)
      [[ "$CUR_STAGE" == "runner" || "$CUR_STAGE" == "cli-tools" ]] || continue
      rest="${dline#* }"
      pv=""
      if [[ "$rest" =~ ^PATH[[:space:]]+([^=].*)$ ]]; then
        pv="${BASH_REMATCH[1]}"                       # legacy `ENV PATH /a:/b` form
      else
        read -r -a etok <<<"$rest"
        for et in "${etok[@]}"; do
          [[ "$et" == PATH=* ]] && pv="${et#PATH=}"
        done
      fi
      if [[ -n "$pv" ]]; then
        pv="${pv#\"}"; pv="${pv%\"}"
        pv="${pv//\$\{PATH\}/$BASE_PATH}"; pv="${pv//\$PATH/$BASE_PATH}"
        PATH_ENVS=$((PATH_ENVS + 1))
        [[ "$pv" != *'$'* ]] || die "PATH_ORDER: stage $CUR_STAGE sets PATH to '$pv', which carries an unresolved variable (an ARG or ENV expansion cannot be ordered statically; write the literal PATH)"
        path_order_ok "$pv" || die "PATH_ORDER: stage $CUR_STAGE sets PATH to '$pv', /usr/bin precedes /usr/local/bin (the shim at /usr/local/bin/bwrap would be shadowed by the real bwrap)"
      fi
      ;;
  esac
done < <(sed -e ':a' -e '/\\$/{N;s/\\\n//;ba' -e '}' "$DOCKERFILE")
pass "static: no ENV PATH in the runner lineage puts /usr/bin before /usr/local/bin ($PATH_ENVS PATH assignment(s) read)"

# 3b. The production bwrap is UNELEVATED: ADR-075's reasoning (a drop and a cover differ only for a process holding
#     CAP_SYS_ADMIN, and an unelevated bwrap drops its capabilities after setup, INFERRED) and the umount measurement in
#     measurements.md hold only then. A setuid or file-capability bwrap would re-open that question, so a RUN line that
#     elevates it is a red here until the decision is re-made. This is a best-effort scan of the common spellings (setcap,
#     symbolic or octal chmod, install -m, --chmod=, dpkg-statoverride) on a line that names bwrap or a /usr/(local/)bin
#     path; it cannot see an elevation done through a variable or a script. The live arm below stats the suite
#     container's /usr/bin/bwrap, which checks the binary itself rather than the spelling.
ELEV_TARGET_RE='bwrap|/usr/(local/)?s?bin'
ELEV_ACTION_RE='setcap|setfattr|dpkg-statoverride|--chmod=(0*[2-7][0-7]{3}|[ugoa,]*[+=][rwxXtugo,+=-]*s[rwxXtugo,+=-]*)([[:space:]]|$)|chmod([[:space:]]+-[A-Za-z-]+)*[[:space:]]+(0*[2-7][0-7]{3}|[ugoa,]*[+=][rwxXtugo,+=-]*s[rwxXtugo,+=-]*)([[:space:]]|$)|install[^#;&|]*(-m|--mode=?)[[:space:]=]*(0*[2-7][0-7]{3}|[ugoa,]*[+=][rwxXtugo,+=-]*s[rwxXtugo,+=-]*)([[:space:]]|$)'
ELEV_HIT=""
while IFS= read -r dline; do
  dline="${dline#"${dline%%[![:space:]]*}"}"
  [[ "$dline" == \#* ]] && continue
  dline="${dline//[\"\']/}"                       # a quoted mode (chmod "u+s" ...) is the same mode
  if [[ "$dline" =~ $ELEV_TARGET_RE && "$dline" =~ $ELEV_ACTION_RE ]]; then
    ELEV_HIT="$dline"
    break
  fi
done < <(sed -e ':a' -e '/\\$/{N;s/\\\n//;ba' -e '}' "$DOCKERFILE")
[[ -z "$ELEV_HIT" ]] || die "ELEVATION: the Dockerfile elevates bwrap ($(printf '%s' "$ELEV_HIT" | head -c 160)); ADR-075's cap-drop reasoning and the suite's unprivileged-bwrap measurements no longer describe production, re-decide before changing this arm"
pass "static: no Dockerfile RUN line elevates bwrap by a common spelling (setcap, setuid/setgid chmod or install, dpkg-statoverride; best-effort, the live stat arm checks the binary)"

# 4. The uid the suite container runs as is the one the Dockerfile creates, and the last USER is the app user.
APP_UID_ALL="$(sed -n 's/.*useradd.*--uid[ =]\([0-9][0-9]*\).*/\1/p' "$DOCKERFILE")"
[[ "$APP_UID_ALL" =~ ^[0-9]+$ ]] || die "USER_DRIFT: could not read exactly one 'useradd --uid N' from $DOCKERFILE (got '$APP_UID_ALL')"
APP_UID="$APP_UID_ALL"
LAST_USER="$(awk 'toupper($1) == "USER" { u = $2 } END { print u }' "$DOCKERFILE")"
[[ "$LAST_USER" == "soleur" ]] || die "USER_DRIFT: the last USER instruction in the Dockerfile is '$LAST_USER', expected soleur"
pass "static: the container uid ($APP_UID) is the Dockerfile's useradd uid and the last USER is soleur"

# 5. The isolation argv is derived from the committed canary fixture: its own `--ro-bind / /` and `--tmpfs /proc`
#    pairs, then every token from its LAST `--dev` to the end (the vendor tail). The `--cap-add CAP_SETFCAP` pair is
#    removed for the uid-1001 replay (the builder adds it only for euid 0 with setfcap; the fixture was captured as root).
has_seq() { # <array name> <tok>... — the tokens appear consecutively
  local -n _arr="$1"; shift
  local want=("$@") i j ok
  for ((i = 0; i + ${#want[@]} <= ${#_arr[@]}; i++)); do
    ok=1
    for ((j = 0; j < ${#want[@]}; j++)); do
      [[ "${_arr[i + j]}" == "${want[j]}" ]] || { ok=0; break; }
    done
    [[ "$ok" -eq 1 ]] && return 0
  done
  return 1
}
FIX_ARGV=()
while IFS= read -r ftok; do FIX_ARGV+=("$ftok"); done < <(jq -r '.bwrapSetupArgv[]?' "$FIXTURE" 2>"$WORK/jq.err")
(( ${#FIX_ARGV[@]} > 0 )) || die "FIXTURE_TAIL: no bwrapSetupArgv in $FIXTURE ($(head -c 200 "$WORK/jq.err"))"
LAST_DEV=-1
for i in "${!FIX_ARGV[@]}"; do [[ "${FIX_ARGV[i]}" == "--dev" ]] && LAST_DEV=$i; done
(( LAST_DEV >= 0 )) || die "FIXTURE_TAIL: the fixture has no --dev, so there is no vendor tail to replay"
FIX_TAIL=("${FIX_ARGV[@]:LAST_DEV}")
has_seq FIX_ARGV --ro-bind / / || die "FIXTURE_TAIL: the fixture lacks the recursive '--ro-bind / /'"
has_seq FIX_ARGV --tmpfs /proc || die "FIXTURE_TAIL: the fixture lacks the vendor '--tmpfs /proc' pair"
has_seq FIX_TAIL --bind /proc /proc || die "FIXTURE_TAIL: the fixture tail lacks '--bind /proc /proc' (the vendor tail bind the isolation arm must replay)"
for t in "${FIX_TAIL[@]}"; do
  [[ "$t" == *'${'* ]] && die "FIXTURE_TAIL: the fixture tail carries an unsubstituted placeholder ($t)"
done
ISO_ARGV=(--ro-bind / / --tmpfs /proc)
skip=0
for i in "${!FIX_TAIL[@]}"; do
  if [[ "$skip" -gt 0 ]]; then skip=$((skip - 1)); continue; fi
  if [[ "${FIX_TAIL[i]}" == "--cap-add" && "${FIX_TAIL[i + 1]:-}" == "CAP_SETFCAP" ]]; then skip=1; continue; fi
  ISO_ARGV+=("${FIX_TAIL[i]}")
done
pass "static: the isolation argv is derived from the canary fixture (${#ISO_ARGV[@]} tokens, tail from its last --dev)"

# 6. The argv analyzer behind the recorder arm. It is a pure function, so it is driven here with synthetic argv first:
#    every spelling of a procfs mount at /proc must be flagged, and ordinary non-/proc mounts must pass.
norm_path() { # collapse //, /./, .. and a trailing /; a relative or empty path is returned as is
  local p="$1" seg
  local -a segs=() out=()
  [[ "$p" == /* ]] || { printf '%s' "$p"; return 0; }
  IFS='/' read -r -d '' -a segs < <(printf '%s' "$p") || true
  for seg in "${segs[@]}"; do
    case "$seg" in
      ""|.) : ;;
      ..) if (( ${#out[@]} > 0 )); then unset 'out[${#out[@]}-1]'; fi ;;
      *) out+=("$seg") ;;
    esac
  done
  local IFS=/
  printf '/%s' "${out[*]}"
}
under_proc() { [[ "$1" == /proc || "$1" == /proc/* ]]; }   # at or beneath /proc, after normalization
rootish() { # <normalized destination> — "/" or anything that is not an absolute path (bwrap rejects those, so a pass here would be a guess)
  [[ -z "$1" || "$1" != /* || "$1" == / ]]
}
DROP_WHY=""
drop_check() { # <argv token>... — 0 when no procfs mount is requested at /proc and exactly one `--tmpfs /proc` is present
  DROP_WHY=""
  local -a a=("$@")
  local n=${#a[@]} i=0 tok tmpfs_proc=0 src dst tmpfs_at=-1 root_bind_at=-1
  if (( n == 0 )); then DROP_WHY="empty argv (the recorder recorded nothing)"; return 1; fi
  while (( i < n )); do
    tok="${a[i]}"
    case "$tok" in
      --) break ;;
      --proc) DROP_WHY="--proc ${a[i + 1]:-} requested"; return 1 ;;
      --tmpfs)
        if [[ "$(norm_path "${a[i + 1]:-}")" == /proc ]]; then tmpfs_proc=$((tmpfs_proc + 1)); tmpfs_at=$i; fi
        i=$((i + 2)) ;;
      --bind|--ro-bind|--bind-try|--ro-bind-try|--dev-bind|--dev-bind-try)
        src="$(norm_path "${a[i + 1]:-}")"; dst="$(norm_path "${a[i + 2]:-}")"
        if [[ "$src" == /proc || "$dst" == /proc ]]; then DROP_WHY="$tok ${a[i + 1]:-} ${a[i + 2]:-} mounts procfs at /proc"; return 1; fi
        if under_proc "$src" || { under_proc "$dst" && [[ ! "$dst" =~ ^/proc/self/fd/[0-9]+$ ]]; }; then
          DROP_WHY="$tok ${a[i + 1]:-} ${a[i + 2]:-} mounts something at or from under /proc (only the /proc/self/fd/N re-home destination is allowed)"; return 1
        fi
        rootish "$dst" && root_bind_at=$i
        i=$((i + 3)) ;;
      --bind-fd|--ro-bind-fd)
        dst="$(norm_path "${a[i + 2]:-}")"
        if [[ "$dst" == /proc ]]; then DROP_WHY="$tok ${a[i + 1]:-} ${a[i + 2]:-} mounts at /proc"; return 1; fi
        rootish "$dst" && root_bind_at=$i
        i=$((i + 3)) ;;
      --symlink|--file|--bind-data|--ro-bind-data)
        dst="$(norm_path "${a[i + 2]:-}")"
        if [[ "$dst" == /proc ]]; then DROP_WHY="$tok ${a[i + 1]:-} ${a[i + 2]:-} creates an entry at /proc"; return 1; fi
        if [[ "$tok" == --symlink ]] && { under_proc "$(norm_path "${a[i + 1]:-}")" || [[ "$(norm_path "${a[i + 1]:-}")" == / ]]; }; then
          DROP_WHY="--symlink ${a[i + 1]:-} ${a[i + 2]:-} aliases /proc or the root (a later bind through the alias would re-expose procfs)"; return 1
        fi
        i=$((i + 3)) ;;
      --setenv) i=$((i + 3)) ;;
      --dev|--dir|--remount-ro|--chdir|--uid|--gid|--hostname|--unsetenv|--mqueue|--add-seccomp-fd|--seccomp|--json-status-fd|--userns-block-fd|--info-fd|--sync-fd|--block-fd|--cap-add|--cap-drop|--size|--perms|--exec-label|--file-label|--lock-file|--userns|--userns2|--pidns)
        i=$((i + 2)) ;;
      --unshare-all|--unshare-user|--unshare-user-try|--unshare-ipc|--unshare-pid|--unshare-net|--unshare-uts|--unshare-cgroup|--unshare-cgroup-try|--share-net|--new-session|--die-with-parent|--as-pid-1|--disable-userns|--assert-userns-disabled|--clearenv)
        i=$((i + 1)) ;;
      *) DROP_WHY="unmodeled option '$tok' (the analyzer refuses argv it does not model)"; return 1 ;;
    esac
  done
  if (( tmpfs_proc != 1 )); then DROP_WHY="expected exactly one --tmpfs /proc, saw $tmpfs_proc"; return 1; fi
  if (( root_bind_at > tmpfs_at )); then DROP_WHY="--tmpfs /proc comes BEFORE the recursive root bind, so the container procfs is re-exposed over the mask"; return 1; fi
  return 0
}
drop_expect() { # <ok|bad> <label> <argv token>...
  local verdict_want="$1" label="$2"; shift 2
  local got=bad
  drop_check "$@" && got=ok
  # shellcheck disable=SC2128  # DROP_WHY is always a scalar string; shellcheck reads it as an array from the ${a[i + 1]:-} text in its assignments
  if [[ "$got" == "$verdict_want" ]]; then pass "analyzer: $label ($verdict_want${DROP_WHY:+: $DROP_WHY})"; else fail "analyzer: $label expected $verdict_want, got $got (${DROP_WHY:-no reason})"; fi
}
DROP_BASE=(--add-seccomp-fd 10 --unshare-user --unshare-pid --ro-bind / / --tmpfs /proc --dev /dev)
drop_expect ok  "a dropped tail (the shim's output shape)"                     "${DROP_BASE[@]}" -- true
drop_expect ok  "unrelated extra mounts before the tail do not matter"         --ro-bind /etc/hostname /etc/hostname "${DROP_BASE[@]}" -- true
drop_expect bad "a kept vendor tail bind"                                      "${DROP_BASE[@]}" --bind /proc /proc -- true
drop_expect bad "a kept bind whose spelling is /proc/"                         "${DROP_BASE[@]}" --bind /proc/ /proc/ -- true
drop_expect bad "a kept bind whose spelling is //proc"                         "${DROP_BASE[@]}" --bind //proc //proc -- true
drop_expect bad "a --bind-try of /proc"                                        "${DROP_BASE[@]}" --bind-try /proc /proc -- true
drop_expect bad "a --dev-bind of /proc"                                        "${DROP_BASE[@]}" --dev-bind /proc /proc -- true
drop_expect bad "a --ro-bind of /proc"                                         "${DROP_BASE[@]}" --ro-bind /proc /proc -- true
drop_expect bad "a fresh --proc /proc"                                         "${DROP_BASE[@]}" --proc /proc -- true
drop_expect bad "a cover (a second --tmpfs /proc after the vendor bind)"       "${DROP_BASE[@]}" --bind /proc /proc --tmpfs /proc -- true
drop_expect bad "no --tmpfs /proc at all"                                      --unshare-user --ro-bind / / --dev /dev -- true
drop_expect bad "an option the analyzer does not model"                        "${DROP_BASE[@]}" --frobnicate x -- true
drop_expect bad "an empty argv"
drop_expect bad "a bind destination spelled through .."                        "${DROP_BASE[@]}" --bind /x /a/../proc -- true
drop_expect bad "a symlink created at /proc"                                  "${DROP_BASE[@]}" --symlink x /proc -- true
drop_expect bad "an --args payload the analyzer cannot read"                  --args 4 "${DROP_BASE[@]}" -- true
drop_expect bad "the --tmpfs /proc placed before the recursive root bind"     --unshare-user --tmpfs /proc --ro-bind / / --dev /dev -- true
drop_expect ok  "the /proc/self/fd/N re-home destination is allowed"            "${DROP_BASE[@]}" --ro-bind /usr/bin/node /proc/self/fd/5 -- true
drop_expect bad "a bind of a path under /proc after the mask"                  "${DROP_BASE[@]}" --ro-bind /tmp/orig/x /proc/sys -- true
drop_expect bad "a bind whose source is under /proc"                           "${DROP_BASE[@]}" --ro-bind /proc/sys /tmp/x -- true
drop_expect bad "a symlink aliasing /proc"                                     "${DROP_BASE[@]}" --symlink /proc /tmp/b -- true
drop_expect bad "a root bind spelled // after the --tmpfs /proc"              --unshare-user --tmpfs /proc --ro-bind / // --dev /dev -- true
drop_expect bad "a root --ro-bind-fd after the --tmpfs /proc"                 --unshare-user --tmpfs /proc --ro-bind-fd 5 / --dev /dev -- true
drop_expect bad "a relative bind destination after the --tmpfs /proc"         --unshare-user --tmpfs /proc --ro-bind / . --dev /dev -- true
drop_expect bad "an empty bind destination after the --tmpfs /proc"           --unshare-user --tmpfs /proc --ro-bind / "" --dev /dev -- true

# ---------------------------------------------------------------------------
# Environment — every failure is a literal token, never a skip.
# ---------------------------------------------------------------------------
docker info >/dev/null 2>&1 || die "DOCKER_UNAVAILABLE: no usable docker daemon (this suite needs a real daemon; it never skips)"

APPARMOR_OPT_VALUE="soleur-bwrap"
if [[ "${SOLEUR_SANDBOX_DOCKER_APPARMOR:-}" == "unconfined" ]]; then
  [[ -z "${CI:-}" ]] || die "APPARMOR_UNAVAILABLE: SOLEUR_SANDBOX_DOCKER_APPARMOR=unconfined is refused when CI is set (the AppArmor half is CI's job)"
  echo "APPARMOR_OVERRIDE: running with apparmor=unconfined; the docker-mask delta is measured, the AppArmor profile is NOT"
  APPARMOR_OPT_VALUE="unconfined"
else
  [[ -r /sys/kernel/security/apparmor/profiles ]] || die "APPARMOR_UNAVAILABLE: AppArmor is not enabled on this host"
  command -v apparmor_parser >/dev/null 2>&1 || die "APPARMOR_UNAVAILABLE: apparmor_parser not installed"
  if ! apparmor_parser -r "$APPARMOR_PROFILE" 2>"$WORK/aa.err"; then
    if [[ "$(id -u)" != "0" ]] && sudo -n true 2>/dev/null; then
      sudo -n apparmor_parser -r "$APPARMOR_PROFILE" 2>"$WORK/aa.err" || die "APPARMOR_UNAVAILABLE: apparmor_parser -r failed: $(head -c 300 "$WORK/aa.err")"
    else
      die "APPARMOR_UNAVAILABLE: apparmor_parser -r failed: $(head -c 300 "$WORK/aa.err")"
    fi
  fi
  grep -q '^soleur-bwrap ' /sys/kernel/security/apparmor/profiles 2>/dev/null \
    || die "APPARMOR_UNAVAILABLE: profile soleur-bwrap is not loaded after apparmor_parser -r"
fi

# Ubuntu 24.04 restricts unprivileged user namespaces for unconfined processes; only set it when the key exists.
if sysctl -n kernel.apparmor_restrict_unprivileged_userns >/dev/null 2>&1; then
  sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 >/dev/null 2>&1 \
    || { [[ "$(id -u)" != "0" ]] && sudo -n sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 >/dev/null 2>&1; } \
    || die "SYSCTL_UNAVAILABLE: could not set kernel.apparmor_restrict_unprivileged_userns=0"
fi

# ---------------------------------------------------------------------------
# Image — the production base (the runner -> cli-tools lineage digest) plus Debian's bubblewrap and the app uid.
# ---------------------------------------------------------------------------
# Bounded apt (#9395): the image build shares lib/apt-bounded.sh with the git-data suites (one budget of apt seconds,
# expiry routed to FIXTURE_APT_FAILED + exit 100). Never a skip here: any non-zero rc is IMAGE_BUILD_FAILED.
assert_fixture_dir "$WORK"
APT_BUDGET_S=150
gd_apt_state_arm "$WORK/aptstate" "$APT_BUDGET_S" || { echo "IMAGE_BUILD_FAILED: the shared apt budget could not be armed" >&2; exit 2; }
# shellcheck disable=SC2016  # single-quoted on purpose: the script expands inside the container
docker run --name "$CTR-build" -e "APP_UID=$APP_UID" -v "$GD_APT_STATE:/work/apt" "$BASE" bash -c '
  export DEBIAN_FRONTEND=noninteractive
  . /work/apt/apt-bounded.sh || exit 97
  gd_apt_install_bounded --no-install-recommends bubblewrap procps jq openssh-client socat || exit $?
  useradd -m -u "$APP_UID" soleur
' >"$WORK/build.out" 2>&1
BUILD_RC=$?
gd_apt_state_summary
if [[ "$BUILD_RC" -ne 0 ]]; then
  docker rm -f "$CTR-build" >/dev/null 2>&1 || true
  die "IMAGE_BUILD_FAILED: image-build container rc=$BUILD_RC: $(gd_apt_out_tail "$WORK/build.out" 5 | tr '\n' ' ' | head -c 600)"
fi
docker commit --change 'USER soleur' "$CTR-build" "$IMG" >/dev/null 2>&1 \
  || die "IMAGE_BUILD_FAILED: docker commit of the image-build container failed"
docker rm "$CTR-build" >/dev/null 2>&1 || true

BWRAP_VER="$(docker run --rm "$IMG" bwrap --version 2>&1 | head -1)"
case "$BWRAP_VER" in
  "bubblewrap 0.8."*) pass "image carries the production bubblewrap line ($BWRAP_VER)" ;;
  *) die "IMAGE_DRIFT: image bubblewrap is '$BWRAP_VER', production pins 0.8.x via the node:22-slim base" ;;
esac

# The suite mounts the repo shim; production installs it through ONE Dockerfile line. Pin that wire so retargeting
# or deleting the COPY (real bwrap with the vendor tail in prod, suite green) goes red.
if grep -qE '^COPY --from=builder( --chmod=[0-9]+)? /app/infra/bwrap-shim/bwrap /usr/local/bin/bwrap$' "$DOCKERFILE"; then
  pass "the production Dockerfile installs the repo shim at /usr/local/bin/bwrap"
else
  fail "the production Dockerfile no longer COPYs infra/bwrap-shim/bwrap to /usr/local/bin/bwrap — the suite would test a shim prod does not run"
fi

# ---------------------------------------------------------------------------
# The shim the container sees at /usr/local/bin/bwrap. MUTATE=shim-splice swaps in the pre-#10039 behaviour
# (a fresh `--proc /proc` spliced before the command boundary); the treatment arm must then go RED.
# MUTATE=shim-cover swaps in the real shim fronting a stage that COVERS the vendor tail bind (it re-adds `--bind /proc /proc`
# and a second `--tmpfs /proc`);
# every behavioral arm stays green, so only the recorder arm can see it. MUTATE=shim-path puts /usr/bin ahead of
# /usr/local/bin on the container PATH, which the live PATH arm must see.
# ---------------------------------------------------------------------------
assert_fixture_dir "$WORK"
SHIM_MOUNT="$SHIM"
SHIM_TARGET=/usr/local/bin/bwrap
if [[ "$MUTATE" == "shim-splice" ]]; then
  cat > "$WORK/splice-shim" <<'EOS'
#!/usr/bin/bash
out=(); seen=0
for a in "$@"; do
  if [ "$seen" = 0 ] && [ "$a" = "--" ]; then out+=(--proc /proc); seen=1; fi
  out+=("$a")
done
exec /usr/bin/bwrap "${out[@]}"
EOS
  chmod 755 "$WORK/splice-shim"
  SHIM_MOUNT="$WORK/splice-shim"
fi
EXTRA_MOUNTS=()
if [[ "$MUTATE" == "shim-cover" ]]; then
  # A faithful cover: the REAL shim (seccomp fd, fd sweep, neutralization all intact) whose "real bwrap" is a stage that
  # puts the vendor bind back and covers it with a second `--tmpfs /proc`. Every behavioral arm stays green; only the
  # argv the real bwrap finally receives betrays it.
  cat > "$WORK/cover-real" <<'EOS'
#!/usr/bin/bash
out=(); seen=0
for a in "$@"; do
  if [ "$seen" = 0 ] && [ "$a" = "--" ]; then out+=(--bind /proc /proc --tmpfs /proc); seen=1; fi
  out+=("$a")
done
exec "${SOLEUR_BWRAP_REAL:-/usr/bin/bwrap}" "${out[@]}"
EOS
  chmod 755 "$WORK/cover-real"
  sed 's|^REAL=${SOLEUR_BWRAP_REAL:-/usr/bin/bwrap}$|REAL=/usr/local/lib/suite-cover-real|' "$SHIM" > "$WORK/cover-shim"
  chmod 755 "$WORK/cover-shim"
  grep -qF 'REAL=/usr/local/lib/suite-cover-real' "$WORK/cover-shim" || die "MUTATION_NOT_APPLIED: the shim-cover rewrite did not land (the shim's REAL= line moved)"
  SHIM_MOUNT="$WORK/cover-shim"
  EXTRA_MOUNTS=(-v "$WORK/cover-real:/usr/local/lib/suite-cover-real:ro")
fi
[[ "$MUTATE" == "shim-path" ]] && EXTRA_MOUNTS+=(-e "PATH=/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/sbin:/usr/local/bin")

# The recorder stands in for the real bwrap behind the shim (SOLEUR_BWRAP_REAL): it writes the argv it receives
# NUL-separated to the container tmpfs, then execs the real bwrap, so the sandbox still runs.
assert_fixture_dir "$WORK"
cat > "$WORK/rec-bwrap" <<'EOS'
#!/usr/bin/bash
printf '%s\0' "$@" > /tmp/bwrap-recorded.argv
exec /usr/bin/bwrap "$@"
EOS
chmod 755 "$WORK/rec-bwrap"

start_container() { # <name> <extra docker run option...> — the prod tuple's posture (derived above) plus per-arm extras
  local name="$1"; shift
  local -a opts=()
  local o
  for o in "${POSTURE_OPTS[@]}"; do
    o="${o/@APPARMOR@/$APPARMOR_OPT_VALUE}"
    o="${o/@SECCOMP@/$SECCOMP}"
    opts+=("$o")
  done
  docker run -d --name "$name" -u "$APP_UID" "${opts[@]}" "$@" \
    -v "$APP_DIR:/app:ro" -v "$SHIM_MOUNT:$SHIM_TARGET:ro" -v "$WORK/rec-bwrap:/usr/local/lib/suite-rec-bwrap:ro" "${EXTRA_MOUNTS[@]}" -e HOME=/home/soleur \
    "$IMG" sleep 3600 >/dev/null 2>"$WORK/start.err" || die "CONTAINER_START_FAILED: container $name did not start (the image built; check the AppArmor profile, the seccomp path and the memory limits): $(head -c 300 "$WORK/start.err")"
}

# ---------------------------------------------------------------------------
# control — the historical splice shape through the REAL bwrap must be refused under docker's default masks.
# MUTATE=control-unmasked removes the masks, which must turn the control arm (and so the suite) RED.
# ---------------------------------------------------------------------------
echo "control arm (docker default masks; vendored tail bind + a fresh --proc /proc, real bwrap):"
if [[ "$MUTATE" == "control-unmasked" ]]; then
  start_container "$CTR-ctrl" --security-opt systempaths=unconfined
else
  start_container "$CTR-ctrl"
fi
CTRL_OUT="$(docker exec "$CTR-ctrl" /usr/bin/bwrap --unshare-user --unshare-pid --ro-bind / / --tmpfs /proc --dev /dev \
  --bind /proc /proc --proc /proc -- true 2>&1 | head -3)"
if grep -qi "mount proc" <<<"$CTRL_OUT"; then
  pass "control: the historical splice shape is refused under docker's default masks (${CTRL_OUT%%$'\n'*})"
else
  fail "control: the historical splice shape was NOT refused — the runner has no docker masks, so this suite cannot fail (out='$CTRL_OUT')"
fi
docker rm -f "$CTR-ctrl" >/dev/null 2>&1 || true
# Positive control: the SAME argv must succeed once docker's masks are lifted. Without it the refusal above is
# attributable to any EPERM (AppArmor, seccomp) and not to the mask this suite is about.
start_container "$CTR-pos" --security-opt systempaths=unconfined
POS_OUT="$(docker exec "$CTR-pos" /usr/bin/bwrap --unshare-user --unshare-pid --ro-bind / / --tmpfs /proc --dev /dev \
  --bind /proc /proc --proc /proc -- true 2>&1 | head -3)"
if [[ -z "$POS_OUT" ]]; then
  pass "control: the same argv succeeds with docker's masks lifted, so the refusal is the mask and not AppArmor/seccomp"
else
  fail "control: the same argv also fails with the masks lifted (out='$POS_OUT') — the refusal is not attributable to the docker masks"
fi
docker rm -f "$CTR-pos" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# treatment + isolation — the SHIPPED shim, default masks, no override.
# ---------------------------------------------------------------------------
echo "treatment arm (the shipped shim, docker default masks, no systempaths override):"
start_container "$CTR"

# Live PATH arm: the shim must be what `bwrap` resolves to for the app uid (the SDK spawns PATH-resolved bwrap).
LIVE_BWRAP="$(docker exec -u "$APP_UID" "$CTR" bash -c 'command -v bwrap' 2>&1 | tail -1)"
LIVE_FIRST="$(docker exec -u "$APP_UID" "$CTR" bash -c 'type -a bwrap | head -1' 2>&1 | tail -1)"
if [[ "$LIVE_BWRAP" == "/usr/local/bin/bwrap" && "$LIVE_FIRST" == "bwrap is /usr/local/bin/bwrap" ]]; then
  pass "live PATH: bwrap resolves to the shim at /usr/local/bin/bwrap before /usr/bin/bwrap for uid $APP_UID"
else
  fail "PATH_ORDER: for uid $APP_UID 'command -v bwrap' is '$LIVE_BWRAP' and the first 'type -a bwrap' entry is '$LIVE_FIRST' (expected /usr/local/bin/bwrap first)"
fi

# Live elevation arm: the container's real bwrap carries no setuid or setgid bit. (The static arm scans the Dockerfile's
# spellings; this checks the binary the suite runs, through a symlink. File capabilities need getcap, which the image does not carry.)
LIVE_MODE="$(docker exec "$CTR" stat -L -c %a /usr/bin/bwrap 2>&1 | tail -1)"
if [[ "$LIVE_MODE" =~ ^[0-7]{3,4}$ && ! "$LIVE_MODE" =~ ^[2-7][0-7]{3}$ ]]; then
  pass "live elevation: /usr/bin/bwrap has mode $LIVE_MODE (no setuid or setgid bit)"
else
  fail "ELEVATION: /usr/bin/bwrap in the suite container has mode '$LIVE_MODE' (a setuid or setgid bwrap re-opens the cap-drop reasoning, or stat failed)"
fi

# Posture arm: the running container carries what the tuple says. systempaths is consumed client-side by docker, so it
# is never asserted through SecurityOpt; the masks themselves are the proof (control arm) and HostConfig.MaskedPaths
# is the inspect-side confirmation.
INSPECT="$(docker inspect "$CTR" 2>/dev/null)"
INS_CAPADD="$(jq -r '.[0].HostConfig.CapAdd // [] | length' <<<"$INSPECT" 2>/dev/null)"
INS_PID="$(jq -r '.[0].HostConfig.PidMode // ""' <<<"$INSPECT" 2>/dev/null)"
INS_PRIV="$(jq -r '.[0].HostConfig.Privileged' <<<"$INSPECT" 2>/dev/null)"
INS_USER="$(jq -r '.[0].Config.User // ""' <<<"$INSPECT" 2>/dev/null)"
INS_MASKED="$(jq -r '.[0].HostConfig.MaskedPaths // [] | length' <<<"$INSPECT" 2>/dev/null)"
INS_AA="$(jq -r --arg v "apparmor=$APPARMOR_OPT_VALUE" '[.[0].HostConfig.SecurityOpt // [] | .[] | select(. == $v)] | length' <<<"$INSPECT" 2>/dev/null)"
INS_SC="$(jq -r '[.[0].HostConfig.SecurityOpt // [] | .[] | select(startswith("seccomp="))] | length' <<<"$INSPECT" 2>/dev/null)"
if [[ "$INS_CAPADD" == "0" && -z "$INS_PID" && "$INS_PRIV" == "false" && "$INS_USER" == "$APP_UID" && "$INS_MASKED" =~ ^[1-9][0-9]*$ && "$INS_AA" == "1" && "$INS_SC" == "1" ]]; then
  pass "posture: the running container has no added capability, no host pid mode, not privileged, user $APP_UID, $INS_MASKED masked paths, one apparmor and one seccomp entry"
else
  fail "posture: container drifted (CapAdd=$INS_CAPADD PidMode='$INS_PID' Privileged=$INS_PRIV User='$INS_USER' MaskedPaths=$INS_MASKED apparmor=$INS_AA seccomp=$INS_SC)"
fi

# The sibling must be running BEFORE any sandbox spawns (an ordering bug must not pass).
SPID=""
if [[ "$MUTATE" != "sleeper-after" ]]; then
  docker exec -d "$CTR" sleep 900
  SPID="$(docker exec "$CTR" sh -c 'pgrep -x -n sleep' 2>/dev/null | tail -1)"
else
  SPID="999999"
fi
if [[ "$SPID" =~ ^[0-9]+$ ]] && docker exec "$CTR" sh -c "test -d /proc/$SPID"; then
  pass "a sibling process ($SPID) is running in the container pid namespace before the sandbox spawns"
else
  fail "no sibling sleeper is running before the sandbox spawns (pid='$SPID') — the isolation arm cannot discriminate"
fi

if [[ "$MUTATE" == "no-replay" ]]; then
  TREAT_OUT='{"verdict":"pass"}'
else
  TREAT_OUT="$(docker exec "$CTR" node /app/scripts/sandbox-canary.mjs --replay 2>"$WORK/replay.err")"
fi
TREAT_ERR="$(head -c 300 "$WORK/replay.err" 2>/dev/null || true)"
if [[ "$TREAT_OUT" == *'"verdict":"pass"'* ]]; then
  pass "treatment: the canary replay passes through the shipped shim under docker's default masks"
else
  fail "treatment: canary replay did not pass (out=$(printf '%s' "$TREAT_OUT" | head -c 300) err=$TREAT_ERR)"
fi
# Non-vacuity: a bare `"verdict":"pass"` is satisfiable by any stub that prints it (the no-replay mutation did,
# and survived the first battery). The real replay also reports the SDK version it replayed, which only the
# committed fixture knows — read it from there and require both it and the replay's own `reason`.
FIX_SDK="$(sed -n 's/.*"sdkVersion": *"\([^"]*\)".*/\1/p' "$APP_DIR/infra/sandbox-canary-argv.json" | head -1)"
if [[ -n "$FIX_SDK" && "$TREAT_OUT" == *'"reason":"ok"'* && "$TREAT_OUT" == *"\"sdkVersion\":\"$FIX_SDK\""* ]]; then
  pass "non-vacuity: the replay reported its own reason and the fixture's SDK version ($FIX_SDK)"
else
  fail "non-vacuity: the replay output lacks reason=ok and the fixture's sdkVersion '$FIX_SDK' (out=$(printf '%s' "$TREAT_OUT" | head -c 200))"
fi

# Isolation: the vendored argv tail re-binds the container procfs. THROUGH the shim the mask holds; THROUGH the real
# bwrap the sibling is visible — that second observation is what makes the first a discriminating assertion.
# ISO_ARGV is derived from the canary fixture above (the vendor's actual tail), not hand-built.
iso_probe() { # <bwrap binary> <sh -c body> -> last output line
  docker exec -e SPID="$SPID" "$CTR" "$1" "${ISO_ARGV[@]}" -- sh -c "$2" 2>&1 | tail -1
}
SHIM_BIN=/usr/local/bin/bwrap
[[ "$MUTATE" == "shim-bypass" ]] && SHIM_BIN=/usr/bin/bwrap
VIS='if [ -e "/proc/$SPID" ]; then echo VISIBLE; else echo ABSENT; fi'
NPID='ls /proc 2>/dev/null | grep -c "^[0-9]"'
ISO_SHIM="$(iso_probe "$SHIM_BIN" "$VIS")"
ISO_REAL="$(iso_probe /usr/bin/bwrap "$VIS")"
PIDDIRS="$(iso_probe "$SHIM_BIN" "$NPID")"
[[ "$ISO_SHIM" == "ABSENT" ]] \
  && pass "isolation: through the shim the sibling process is ABSENT from the sandbox's /proc" \
  || fail "isolation: through the shim the sibling is '$ISO_SHIM' (expected ABSENT)"
[[ "$PIDDIRS" == "0" ]] \
  && pass "isolation: /proc inside the sandbox lists no pid directory" \
  || fail "isolation: /proc inside the sandbox lists '$PIDDIRS' pid directories (expected 0)"
[[ "$ISO_REAL" == "VISIBLE" ]] \
  && pass "discrimination: through the real bwrap with the vendor tail bind the sibling is VISIBLE (the leak the mask closes)" \
  || fail "discrimination: through the real bwrap the sibling is '$ISO_REAL' (expected VISIBLE; the isolation assertion cannot discriminate)"

# Recorder arm: what the REAL bwrap receives from the shim. A drop leaves no argv-requested procfs mount at /proc and
# exactly one `--tmpfs /proc`; a cover keeps the vendor bind and adds a second `--tmpfs /proc`, which every behavioral
# arm above reads as green. The instrument control is the fixture's own `--dev /dev` tail in the recorded argv: a
# recorder that recorded nothing, or was bypassed, cannot satisfy it.
docker exec -e SOLEUR_BWRAP_REAL=/usr/local/lib/suite-rec-bwrap "$CTR" "$SHIM_BIN" "${ISO_ARGV[@]}" -- true >/dev/null 2>&1
REC_ARGV=()
while IFS= read -r -d '' rtok; do REC_ARGV+=("$rtok"); done < <(docker exec "$CTR" cat /tmp/bwrap-recorded.argv 2>/dev/null)
if has_seq REC_ARGV --dev /dev; then
  pass "recorder: the real bwrap's argv was recorded (${#REC_ARGV[@]} tokens, carrying the fixture's --dev tail)"
else
  fail "DROP_FAILED: the recorder recorded no usable argv (${#REC_ARGV[@]} tokens) — the shim did not reach the recorder"
fi
if drop_check "${REC_ARGV[@]}"; then
  pass "recorder: the shim DROPPED the vendor procfs bind (no argv-requested procfs mount at /proc, exactly one --tmpfs /proc)"
else
  fail "DROP_FAILED: the argv the real bwrap received still requests a procfs mount at /proc or is malformed: $DROP_WHY (the shim's neutralizer lives in infra/bwrap-shim/bwrap; SANDBOX_MASKED_PROC_MUTATE=shim-cover reproduces this failure shape)"
fi

# C4 render replay: the C4 sandbox bypasses the shim (/usr/bin/bwrap absolute), so its argv runs through the REAL bwrap
# here, under the masks, with the same fd setup its launcher uses (fd 9 the committed seccomp filter, fd 3 the
# --json-status-fd). The argv is the committed generated fixture up to its command boundary; the render command itself
# is replaced by a node one-liner, because the question is whether the MOUNT SET survives docker's masks.
C4_ARGV=()
while IFS= read -r -d '' c4tok; do C4_ARGV+=("$c4tok"); done < <(jq -j '(.bwrapArgv | index("--")) as $b | .bwrapArgv[:$b][] | ., "\u0000"' "$C4_FIXTURE" 2>/dev/null)
if (( ${#C4_ARGV[@]} > 20 )) && has_seq C4_ARGV --seccomp 9 && has_seq C4_ARGV --json-status-fd 3; then
  # shellcheck disable=SC2016  # single-quoted on purpose: the script expands inside the container
  C4_OUT="$(docker exec "$CTR" bash -c '
    stage="$(mktemp -d "${TMPDIR:-/tmp}/c4stage.XXXXXX")" && mkdir -p "$stage/src" || exit 70
    args=()
    for a in "$@"; do args+=("${a//\{\{STAGE\}\}/$stage}"); done
    exec 9</app/infra/bwrap-userns-clone3-deny.bpf || exit 71
    exec 3>/tmp/c4-status.json
    /usr/bin/bwrap "${args[@]}" -- /usr/local/bin/node -e "console.log(\"C4_REPLAY_OK\")"
    echo "C4_BWRAP_RC=$?"
    cat /tmp/c4-status.json
  ' c4-replay "${C4_ARGV[@]}" 2>&1)"
  if [[ "$C4_OUT" == *"C4_REPLAY_OK"* && "$C4_OUT" == *"C4_BWRAP_RC=0"* && "$C4_OUT" == *'"exit-code": 0'* ]]; then
    pass "c4 replay: the C4 render sandbox argv runs through the real /usr/bin/bwrap under docker's default masks (exit 0, payload ran)"
  else
    fail "c4 replay: the C4 render argv did not run under the masks (out=$(printf '%s' "$C4_OUT" | head -c 400))"
  fi
else
  fail "c4 replay: the C4 argv fixture yielded ${#C4_ARGV[@]} tokens or lacks --seccomp 9 / --json-status-fd 3 ($C4_FIXTURE)"
fi

# Wrapped-command arms (#10445). The probe drives the real Agent SDK against a local stand-in for the Messages API with
# the PATH-resolved shim, so what comes back is what a hosted Bash call returns under this posture. CONTROL leaves the
# knob unset: the SDK wraps the command in `apply-seccomp`, which our own filter then kills. TREATMENT sets it. The
# MUTATE=knob-off seam runs the treatment with the knob unset, which must turn the suite RED.
sdk_bash() { # <KNOB 0|1> <command> -> the single SDK_BASH_RESULT line
  docker exec -e APP=/app -e KNOB="$1" -e CMD="$2" -e HOME=/home/soleur "$CTR" node /app/infra/lib/sdk-bash-probe.mjs 2>"$WORK/sdkbash.err" \
    | grep -a '^SDK_BASH_RESULT ' | tail -1
}
WRAP_CMD='echo WRAPCMD_OK_10445'
CTRL_WRAP="$(sdk_bash 0 "$WRAP_CMD")"
if [[ "$CTRL_WRAP" == *'"isError":true'* && "$CTRL_WRAP" == *'apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted'* ]]; then
  pass "wrapped control: with the knob unset the SDK's apply-seccomp helper dies with EPERM under the shim filter (the #10445 outage, reproduced)"
else
  fail "wrapped control: the knob-unset arm did not reproduce the helper EPERM, so the treatment below cannot discriminate (out=$(printf '%s' "$CTRL_WRAP" | head -c 300) err=$(head -c 200 "$WORK/sdkbash.err"))"
fi
TREAT_KNOB=1
[[ "$MUTATE" == "knob-off" ]] && TREAT_KNOB=0
TREAT_WRAP="$(sdk_bash "$TREAT_KNOB" "$WRAP_CMD")"
if [[ "$TREAT_WRAP" == *'"isError":false'* && "$TREAT_WRAP" == *'WRAPCMD_OK_10445'* && "$TREAT_WRAP" != *'apply-seccomp'* ]]; then
  pass "wrapped treatment: with the knob set a hosted Bash call returns the command's own stdout through the shim and the production masks"
else
  fail "wrapped treatment: the knob-set Bash call did not return the command's stdout (out=$(printf '%s' "$TREAT_WRAP" | head -c 300) err=$(head -c 200 "$WORK/sdkbash.err"))"
fi

# AF_UNIX-deny variant arms (#10455 a, ADR-075 addendum 2026-10-19). The production run tuple (this container's AppArmor +
# seccomp posture) must let the SDK start Bash under BOTH seccomp artifacts, and the variant must deny socket(AF_UNIX)
# while the base keeps allowing it. Same probe, same shim; only SOLEUR_BWRAP_SECCOMP_BPF differs. A node connect() to a
# path that does not exist reports ENOENT when the AF_UNIX socket was created and EPERM when socket() was denied. The
# container profile also keeps io_uring closed (no ring, so no IORING_OP_SOCKET bypass of the socket() filter); that is
# pinned statically in test/bwrap-userns-seccomp.test.ts.
sdk_bash_sel() { # <KNOB 0|1> <command> <seccomp artifact path> -> the single SDK_BASH_RESULT line
  docker exec -e APP=/app -e KNOB="$1" -e CMD="$2" -e HOME=/home/soleur -e SOLEUR_BWRAP_SECCOMP_BPF="$3" "$CTR" node /app/infra/lib/sdk-bash-probe.mjs 2>"$WORK/sdkbash.err" \
    | grep -a '^SDK_BASH_RESULT ' | tail -1
}
read -r -d '' AFU_CMD <<'AFU_EOF' || true
node -e "const c=require('net').connect('/afunix-probe.sock');c.on('error',e=>{console.log('AFUNIX_'+e.code);process.exit(0)});c.on('connect',()=>{console.log('AFUNIX_CONNECTED');process.exit(0)})"; echo AFUNIX_DONE
AFU_EOF
AFU_VARIANT="$(sdk_bash_sel 1 "$AFU_CMD" /app/infra/bwrap-userns-clone3-unixdeny.bpf)"
if [[ "$AFU_VARIANT" == *'"isError":false'* && "$AFU_VARIANT" == *AFUNIX_DONE* && "$AFU_VARIANT" == *AFUNIX_EPERM* ]]; then
  pass "variant: under the unixdeny artifact Bash starts on the production tuple and socket(AF_UNIX) is EPERM"
else
  fail "variant: the unixdeny artifact either broke Bash start or did not deny socket(AF_UNIX) (out=$(printf '%s' "$AFU_VARIANT" | head -c 300) err=$(head -c 200 "$WORK/sdkbash.err")) - ADR-075 addendum 2026-10-19 flips to descope"
fi
AFU_BASE="$(sdk_bash_sel 1 "$AFU_CMD" /app/infra/bwrap-userns-clone3-deny.bpf)"
if [[ "$AFU_BASE" == *'"isError":false'* && "$AFU_BASE" == *AFUNIX_DONE* && "$AFU_BASE" == *AFUNIX_ENOENT* ]]; then
  pass "variant control: under the base artifact the same probe creates its AF_UNIX socket (ENOENT on connect), so the variant's EPERM is attributable to the artifact"
else
  fail "variant control: the base artifact did not allow socket(AF_UNIX) or Bash did not start (out=$(printf '%s' "$AFU_BASE" | head -c 300))"
fi

# Census: with AF_UNIX no longer blocked inside the inner sandbox, list every pathname socket visible from it. Only the
# SDK's own proxy bridge sockets under /tmp are expected (peer-messaging and transcript dirs are masked). Two
# instrument checks keep a silent census from passing: the listing must END with its sentinel (a failed `find` prints
# nothing and would otherwise read as "no sockets"), and it must contain at least one socket (the current session's
# own bridge socket is among them, so zero means the census did not see the session it ran in). The scan skips only
# /proc and /sys rather than using -xdev, so a socket on a bind mount is listed; abstract-namespace sockets cannot be
# listed from here and are bounded by the per-command --unshare-net (asserted in test/sandbox-wrapped-command-runtime.test.ts).
CENSUS_OUT="$(sdk_bash 1 'find / \( -path /proc -o -path /sys \) -prune -o -type s -print 2>/dev/null; echo CENSUS_END')"
CENSUS_PATHS="$(printf '%s' "$CENSUS_OUT" | sed 's/^SDK_BASH_RESULT //' | jq -r '.content // ""' 2>/dev/null | grep -a '^/' | sort -u)"
CENSUS_N=0
CENSUS_BAD=""
while IFS= read -r cpath; do
  [[ -n "$cpath" ]] || continue
  CENSUS_N=$((CENSUS_N + 1))
  [[ "$cpath" =~ ^/tmp/(claude-http-[0-9a-f]+|claude-socks-[0-9a-f]+|srt-mux-[0-9]+-[0-9a-z]+)\.sock$ ]] || CENSUS_BAD+="$cpath "
done <<<"$CENSUS_PATHS"
if [[ "$CENSUS_OUT" == *CENSUS_END* && "$CENSUS_N" -ge 1 && -z "$CENSUS_BAD" ]]; then
  pass "census: every pathname socket visible from the inner sandbox ($CENSUS_N) is an SDK proxy bridge socket under /tmp (no host runtime or peer-messaging socket)"
else
  fail "census: bad or missing socket listing from the inner sandbox: unexpected='${CENSUS_BAD}' n=$CENSUS_N complete=$([[ "$CENSUS_OUT" == *CENSUS_END* ]] && echo yes || echo no) (a host runtime or peer-messaging socket reachable from a tenant sandbox is the residual ADR-075's 2026-10-16 addendum bounds; n=0 means the census did not see its own session)"
fi

# Environ scan (W1, ADR-272): with the knob set, can a hosted Bash call read ANY process environ carrying the owner's key?
# The probe puts a decoy ANTHROPIC_API_KEY in the CLI's (outside-the-sandbox) environment. The `[i]` keeps the scan's own
# command line from matching its pattern. Non-vacuity: the counters must PRINT (a command that never ran prints none, and
# the empty comparison below would then fail); the matching positive control, a scan that does find the decoy when
# /proc is open, is test/sandbox-credential-deny-runtime.test.ts's shim-less CONTROL arm.
ENV_OUT="$(sdk_bash 1 'echo PIDDIRS=$(ls -d /proc/[0-9]* 2>/dev/null | wc -l); n=0; f=0; for p in /proc/[0-9]*; do if cat $p/environ >/dev/null 2>&1; then n=$((n+1)); grep -qa decoy-api-key-sent[i]nel $p/environ 2>/dev/null && f=$((f+1)); fi; done; echo READABLE=$n; echo DECOY=$f; echo SCAN_END')"
ENV_TXT="$(printf '%s' "$ENV_OUT" | sed 's/^SDK_BASH_RESULT //' | jq -r '.content // ""' 2>/dev/null)"
if [[ "$ENV_TXT" == *SCAN_END* && "$ENV_TXT" == *PIDDIRS=0* && "$ENV_TXT" == *READABLE=0* && "$ENV_TXT" == *DECOY=0* ]]; then
  pass "environ scan: with the knob set no process environ is readable from a hosted Bash call and none carries the decoy (empty /proc)"
else
  fail "environ scan: a process environ is readable from the sandbox or the scan did not run (a W1 regression, ADR-272): $(printf '%s' "$ENV_TXT" | tr '\n' ' ' | head -c 300)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
# Anti-vacuity floor: a literal adjacent to its use (guard-vacuity-floor shape).
MIN_ASSERTIONS=54
if (( PASS + FAIL < MIN_ASSERTIONS )); then
  echo "FAIL: only $((PASS + FAIL)) assertions ran (floor $MIN_ASSERTIONS) — the suite did not exercise its arms"
  exit 1
fi
# The floor is EXACT: adding an assertion without raising the literal, or replacing one with another, must be visible.
if (( PASS + FAIL > MIN_ASSERTIONS )); then
  echo "FAIL: $((PASS + FAIL)) assertions ran but MIN_ASSERTIONS is $MIN_ASSERTIONS — set MIN_ASSERTIONS=$((PASS + FAIL)) deliberately"
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
