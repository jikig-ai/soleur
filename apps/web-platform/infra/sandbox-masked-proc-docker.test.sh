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
# WHAT THIS PROVES, in a container carrying the production posture (the committed seccomp profile, the committed
# `soleur-bwrap` AppArmor profile, uid 1001, the Debian bubblewrap the production base installs, docker's DEFAULT
# masks, NO systempaths override):
#   control    the historical shape — the vendored tail bind plus a fresh `--proc /proc`, through the REAL bwrap —
#              is REFUSED with "mount proc". This proves the runner really has masks, i.e. that the suite can fail.
#   treatment  the canary replay through the SHIPPED shim passes (the fixture argv, tail bind and all).
#   isolation  through the shim a process started OUTSIDE the sandbox, in the same pid namespace, is ABSENT from the
#              sandbox's /proc and /proc lists no pid directory at all; through the real bwrap with the vendor tail
#              bind the same process is VISIBLE (so the assertion discriminates).
#
# NEVER SELF-SKIPS. An unusable environment fails with a literal token and exit 1 (DOCKER_UNAVAILABLE,
# APPARMOR_UNAVAILABLE, SYSCTL_UNAVAILABLE, IMAGE_BUILD_FAILED, IMAGE_DRIFT) — the opposite of
# sandbox-canary-regression.test.sh section B, whose never-fail classification is the property that let this class ship.
#
# PRIVILEGED. Loads an AppArmor profile (apparmor_parser) and sets a sysctl, so it is invoked under `sudo` from the
# deploy-script-tests-fixed job (run-registered-suites.sh PRIVILEGED_WHY). On a host without AppArmor a LOCAL dev run
# may set SOLEUR_SANDBOX_DOCKER_APPARMOR=unconfined to measure the docker-mask delta alone; the override is refused
# when CI is set, prints APPARMOR_OVERRIDE, and does not discharge the AppArmor half (CI does).
#
# MUTATION SEAM (battery only): SANDBOX_MASKED_PROC_MUTATE =
#   shim-splice | shim-bypass | control-unmasked | sleeper-after | no-replay
# each of which must drive the suite RED.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SHIM="$SCRIPT_DIR/bwrap-shim/bwrap"
SECCOMP="$SCRIPT_DIR/seccomp-bwrap.json"
APPARMOR_PROFILE="$SCRIPT_DIR/apparmor-soleur-bwrap.profile"
DOCKERFILE="$APP_DIR/Dockerfile"
MUTATE="${SANDBOX_MASKED_PROC_MUTATE:-}"
IMG="soleur-masked-proc-regression:$$"
CTR="smp$$"
WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/sandbox-masked-proc.XXXXXXXX")"
PASS=0
FAIL=0

pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
die() { echo "$1" >&2; echo "FAIL: $1"; exit 1; }

cleanup() {
  docker rm -f "$CTR" "$CTR-build" "$CTR-ctrl" "$CTR-pos" >/dev/null 2>&1 || true
  docker rmi -f "$IMG" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

for f in "$SHIM" "$SECCOMP" "$APPARMOR_PROFILE" "$DOCKERFILE" "$APP_DIR/scripts/sandbox-canary.mjs" "$APP_DIR/infra/sandbox-canary-argv.json"; do
  [[ -f "$f" ]] || die "ERROR missing input $f"
done

echo "=== sandbox masked-/proc docker regression (#9860 / #10032) ==="

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
# Image — the production base (digest read from the Dockerfile) plus Debian's bubblewrap and uid 1001.
# ---------------------------------------------------------------------------
BASE="$(grep -m1 -E '^FROM node:22-slim@sha256:[0-9a-f]{64}' "$DOCKERFILE" | awk '{print $2}')"
[[ -n "$BASE" ]] || die "IMAGE_BUILD_FAILED: could not read the node:22-slim@sha256 base from $DOCKERFILE"
# Bounded apt (#9395): the image build shares lib/apt-bounded.sh with the git-data suites (one budget of apt seconds,
# expiry routed to FIXTURE_APT_FAILED + exit 100). Never a skip here: any non-zero rc is IMAGE_BUILD_FAILED.
APT_LIB="${SCRIPT_DIR}/lib/apt-bounded.sh"
APT_BUDGET_S=150
[[ -r "$APT_LIB" ]] || die "IMAGE_BUILD_FAILED: ${APT_LIB} is missing, the apt cycle could not be bounded"
# shellcheck source=lib/apt-bounded.sh
. "$APT_LIB"
gd_apt_state_arm "$WORK/aptstate" "$APT_BUDGET_S" || { echo "IMAGE_BUILD_FAILED: the shared apt budget could not be armed" >&2; exit 2; }
# shellcheck disable=SC2016  # single-quoted on purpose: the script expands inside the container
docker run --name "$CTR-build" -v "$GD_APT_STATE:/work/apt" "$BASE" bash -c '
  export DEBIAN_FRONTEND=noninteractive
  . /work/apt/apt-bounded.sh || exit 97
  gd_apt_install_bounded --no-install-recommends bubblewrap procps jq openssh-client || exit $?
  useradd -m -u 1001 soleur
' >"$WORK/build.out" 2>&1
BUILD_RC=$?
gd_apt_state_summary
if [[ "$BUILD_RC" -ne 0 ]]; then
  docker rm -f "$CTR-build" >/dev/null 2>&1 || true
  die "IMAGE_BUILD_FAILED: image-build container rc=$BUILD_RC: $(tail -c 400 "$WORK/build.out")"
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
# ---------------------------------------------------------------------------
SHIM_MOUNT="$SHIM"
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

start_container() { # <name> <extra docker run option...> — the production tuple minus any systempaths override
  local name="$1"; shift
  docker run -d --name "$name" --init -u 1001 --tmpfs /tmp:rw,nosuid,nodev,size=256m \
    --security-opt "apparmor=$APPARMOR_OPT_VALUE" --security-opt "seccomp=$SECCOMP" "$@" \
    -v "$APP_DIR:/app:ro" -v "$SHIM_MOUNT:/usr/local/bin/bwrap:ro" -e HOME=/home/soleur \
    "$IMG" sleep 3600 >/dev/null 2>"$WORK/start.err" || die "IMAGE_BUILD_FAILED: container $name did not start: $(head -c 300 "$WORK/start.err")"
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
if printf '%s' "$CTRL_OUT" | grep -qi "mount proc"; then
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
ISO_ARGV=(--unshare-user --unshare-pid --ro-bind / / --tmpfs /proc --dev /dev --bind /proc /proc)
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
  && pass "isolation: /proc inside the sandbox lists no pid directory (no procfs at all)" \
  || fail "isolation: /proc inside the sandbox lists '$PIDDIRS' pid directories (expected 0)"
[[ "$ISO_REAL" == "VISIBLE" ]] \
  && pass "discrimination: through the real bwrap with the vendor tail bind the sibling is VISIBLE (the leak the mask closes)" \
  || fail "discrimination: through the real bwrap the sibling is '$ISO_REAL' (expected VISIBLE; the isolation assertion cannot discriminate)"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
# Anti-vacuity floor: a literal adjacent to its use (guard-vacuity-floor shape).
MIN_ASSERTIONS=10
if (( PASS + FAIL < MIN_ASSERTIONS )); then
  echo "FAIL: only $((PASS + FAIL)) assertions ran (floor $MIN_ASSERTIONS) — the suite did not exercise its arms"
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
