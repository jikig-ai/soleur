#!/usr/bin/env bash
# remeasure-sdk-sandbox-network-cache.sh — re-measure whether an Agent SDK version still caches a per-host
# SandboxNetworkAccess allow for the whole session (#12906 PR-1b; ADR-278; harness from #12897).
#
# Usage:
#   bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh <version|dist-tag> \
#        [--out <verdict.json>] [--markdown <dir>] [--keep-scratch]
#
# It takes up to 10 minutes (the 2026-11-19 run took about 3.5). --out and --markdown are resolved against the caller's
# cwd; any earlier copy of them (verdict.json, <dir>/addendum.md, <dir>/issue-comment.md) is deleted at start, and the
# new ones are written only when the run ends without app-mutated.
#
# SCOPE: evidence only. It never moves the app's SDK pin. It installs the pinned baseline (MEASURED_BASELINE in
# scripts/lib/sandbox-network-cache-verdict.ts) and the candidate into two scratch prefixes under $TMPDIR, runs
# test/helpers/netns-egress-harness.mts (allow-all tap; the classifier's ARMS) once per prefix inside
# `unshare -rnm`, and classifies the two runs side by side. The app's package.json, package-lock.json and installed
# node_modules/@anthropic-ai/claude-agent-sdk* are hashed before and after; any change is exit 1 `app-mutated`.
#
# Containment (per harness run, in its own user + mount + net + pid namespace, before tsx starts): read-only tmpfs
# over $HOME (and $XDG_RUNTIME_DIR when set); the whole mount tree remounted read-only (ro=recursive /); a tmpfs over
# /run (and /var/run when it is not a symlink), read-only once the /etc mountpoints the harness binds are made; a
# private tmpfs over /tmp and /dev/shm; exactly two dirs bound back read-write (the run's home and scratch). It then
# locks that tree in a nested user + mount namespace and probes it: remounting / or the git common dir read-write and
# unmounting /run or /proc must fail, a write must fail in every worktree, the git common dir, $HOME, the scratch root
# and the run dir (and the baseline run dir during the candidate run), succeed in the two bound dirs, and a connect()
# to /run/docker.sock, /var/run/docker.sock and /run/user/<uid>/bus must fail. Any failure is exit 3
# `containment-unavailable`; it never runs uncontained. The baseline's stdout is hashed after its run and re-checked
# before classify (exit 3 `containment-breached` on a change). The app checkout must not live under $HOME (masked).
#
# Accepted residual: filesystem sockets outside /run, /var/run, /tmp, /dev/shm and $HOME stay connectable with the
# operator's own uid and groups, the whole filesystem stays readable, and the runtime suite itself still runs
# uncontained (#12969). Re-evaluate before any run on a shared or CI host, or on a host where an execution-granting
# daemon socket lives outside those paths.
#
# Every exit except --help ends with one line:   REMEASURE verdict=<word> exit=<n> reason=<token> next=<action>
#
# Exit codes (the reason tokens this script and its classifier emit):
#   0  CACHES | RE-ASKS-AFTER-TEARDOWN | MIXED   measured
#   1  ERROR         bad-args, bad-version-arg, setup-missing, low-disk, install-failed, version-mismatch,
#                    harness-crash, classifier-crash, classifier-args, redaction-refused:<what>, publish-failed,
#                    script-aborted, <side>:no-step0, <side>:duplicate-step0, <side>:duplicate-arm,
#                    <side>:parse-step0, <side>:parse-arm, <side>:harness-crash, and app-mutated (overrides every exit)
#   2  INCONCLUSIVE  <side>:<precondition> (e.g. candidate:versions, candidate:sdk-entry), baseline:reading,
#                    candidate-reading:<why> (re-run once)
#   3  UNVERIFIED    unsupported-arch, no-userns, containment-unavailable, containment-breached,
#                    scratch-inside-protected-path, step0:<side>:<probes>
#      REFUSED       release-age-floor, signature-verification-failed, baseline-integrity-mismatch
#   4  LEAK          <side>:<arm>:decoy, <side>:<arm>:gateway-auth
#   --help exits 0 and prints no REMEASURE line.
#
# Verdict-to-action: --help prints it from the classifier (`sandbox-network-cache-verdict.ts table`, its NEXT map).
#
# Any SDK or bundled-CLI bump re-arms CLO gate B-2 (ADR-278 2026-11-18 addendum); this script neither satisfies nor
# re-arms it. The ADR-191 release-age floor (FLOOR_DAYS, equal to min-release-age in apps/web-platform/.npmrc) is
# enforced, never overridden.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$(cd "$SCRIPT_DIR/.." && pwd)"
PKG="@anthropic-ai/claude-agent-sdk"
PKG_X64="@anthropic-ai/claude-agent-sdk-linux-x64"
REGISTRY="https://registry.npmjs.org/"
FLOOR_DAYS=3
MIN_FREE_KB=$((2 * 1024 * 1024))
NSTEPS=11
TSX="$APP/node_modules/.bin/tsx"
HARNESS="$APP/test/helpers/netns-egress-harness.mts"
CLASSIFIER="$APP/scripts/lib/sandbox-network-cache-verdict.ts"
CMD_LINE="bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh $*"
STARTED_AT="$(date -u +%FT%TZ)"

say() { printf '%s\n' "$*" >&2; }
step() { say "[$1/$NSTEPS] $2"; }

# ---- the final line ---------------------------------------------------------------------------------------------
# Before the EXIT trap is armed, finish() prints directly. Afterwards it records the line and the trap prints it, so
# the trap's app-mutated check can still override it and the REMEASURE line is always the last line printed.
TRAP_ARMED=0
F_VERDICT="" F_EXIT="" F_REASON="" F_NEXT=""
print_final() { printf 'REMEASURE verdict=%s exit=%s reason=%s next=%s\n' "$F_VERDICT" "$F_EXIT" "$F_REASON" "$F_NEXT"; }
finish() { # verdict exit reason next
  F_VERDICT="$1" F_EXIT="$2" F_REASON="$3" F_NEXT="$4"
  if [[ "$F_VERDICT" == UNVERIFIED ]]; then echo "UNVERIFIED:sdk-${CAND_LABEL:-unknown}-sandbox-network-allow-cache"; fi
  if [[ "$TRAP_ARMED" == 0 ]]; then print_final; fi
  exit "$2"
}

usage() {
  sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
  echo "Verdict-to-action (from the classifier's NEXT map):"
  "$TSX" --tsconfig "$APP/tsconfig.json" "$CLASSIFIER" table 2>/dev/null | sed 's/^/  /' \
    || echo "  (the classifier did not load; run npm ci in apps/web-platform)"
  printf '  REFUSED\tno finding; wait for the floor (release-age), or file a security issue\n'
}

# ---- arguments ----------------------------------------------------------------------------------------------------
REQ="" OUT="" MD="" KEEP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --out) [[ -n "${2-}" ]] || finish ERROR 1 bad-args "pass a path after --out"; OUT="$(realpath -m -- "$2")"; shift 2 ;;
    --markdown) [[ -n "${2-}" ]] || finish ERROR 1 bad-args "pass a dir after --markdown"; MD="$(realpath -m -- "$2")"; shift 2 ;;
    --keep-scratch) KEEP=1; shift ;;
    -*) finish ERROR 1 bad-args "unknown option $1; see --help" ;;
    *) if [[ -n "$REQ" ]]; then finish ERROR 1 bad-args "pass exactly one version"; fi; REQ="$1"; shift ;;
  esac
done
# A stale record from an earlier run must never read as this run's: delete before any other exit.
[[ -n "$OUT" ]] && rm -f -- "$OUT"
[[ -n "$MD" ]] && rm -f -- "$MD/addendum.md" "$MD/issue-comment.md"
CAND_LABEL="$REQ"
[[ -n "$REQ" ]] || finish ERROR 1 bad-args "pass the candidate version or dist-tag; see --help"
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'
if ! [[ "$REQ" =~ $SEMVER_RE || "$REQ" =~ ^[a-z][a-z0-9-]{0,30}$ ]]; then
  finish ERROR 1 bad-version-arg "pass an exact semver or a dist-tag (no npm: aliases, file: paths or URLs)"
fi

# ---- 1. setup preflight -------------------------------------------------------------------------------------------
step 1 "setup preflight"
if [[ "$(uname -s 2>/dev/null)" != Linux || "$(uname -m 2>/dev/null)" != x86_64 ]] || ! getconf GNU_LIBC_VERSION 2>/dev/null | grep -q '^glibc '; then
  finish UNVERIFIED 3 unsupported-arch "run on a Linux x86_64 glibc host (the CLI lookup mirrors the SDK's linux-x64 path)"
fi
missing=()
for t in node npm unshare setsid mount umount timeout git sha256sum df realpath readlink stat; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
for f in "$TSX" "$HARNESS" "$CLASSIFIER" "$APP/package.json" "$APP/package-lock.json" "$APP/tsconfig.json"; do
  [[ -e "$f" ]] || missing+=("${f#"$APP"/}")
done
shopt -s nullglob
sdk_dirs=("$APP"/node_modules/@anthropic-ai/claude-agent-sdk*)
shopt -u nullglob
[[ ${#sdk_dirs[@]} -gt 0 ]] || missing+=("node_modules/@anthropic-ai/claude-agent-sdk*")
if [[ ${#missing[@]} -gt 0 ]]; then
  say "missing: ${missing[*]}"
  finish ERROR 1 setup-missing "run npm ci in apps/web-platform"
fi

# ---- 2. namespace check -------------------------------------------------------------------------------------------
# The same flags the harness launch uses below, so a host without PID namespaces is no-userns, not harness-crash.
UNSHARE_RUN=(unshare -rnm --fork --pid --mount-proc --kill-child)
step 2 "user + network + mount + pid namespace check"
if ! "${UNSHARE_RUN[@]}" true >/dev/null 2>&1; then
  finish UNVERIFIED 3 no-userns "record UNVERIFIED and file an issue with the host kernel and userns settings"
fi

# ---- EXIT trap ----------------------------------------------------------------------------------------------------
scratch=""
PRE_HASH=""
app_hash() {
  {
    printf '%s\0' "$APP/package.json" "$APP/package-lock.json"
    find "$APP"/node_modules/@anthropic-ai/ -maxdepth 1 -name 'claude-agent-sdk*' -print0 2>/dev/null \
      | xargs -0 -r -I{} find {} -type f -print0
  } | sort -z | xargs -0 sha256sum 2>&1 | sha256sum | cut -d' ' -f1
}
# Copies the classifier's record from scratch to the requested paths. Runs only from on_exit, after the app-mutated
# check, so an overridden run never leaves a record behind.
publish() {
  if [[ -n "$OUT" && -f "$scratch/verdict.json" ]]; then
    mkdir -p -- "$(dirname -- "$OUT")" && cp -- "$scratch/verdict.json" "$OUT" || return 1
  fi
  if [[ -n "$MD" && -f "$scratch/md/addendum.md" ]]; then
    mkdir -p -- "$MD" && cp -- "$scratch/md/addendum.md" "$scratch/md/issue-comment.md" "$MD/" || return 1
  fi
}
# shellcheck disable=SC2329  # invoked by the EXIT trap
on_exit() {
  local rc=$?
  trap - EXIT
  if [[ -n "$PRE_HASH" && "$(app_hash)" != "$PRE_HASH" ]]; then
    say "app tree changed during the run (package.json, package-lock.json or node_modules/@anthropic-ai/claude-agent-sdk*)"
    F_VERDICT=ERROR F_EXIT=1 F_REASON=app-mutated F_NEXT="restore the app tree with npm ci and file a bug against this script"
    rc=1
  elif [[ -n "$scratch" && -d "$scratch" ]] && ! publish; then
    [[ -n "$OUT" ]] && rm -f -- "$OUT"
    [[ -n "$MD" ]] && rm -f -- "$MD/addendum.md" "$MD/issue-comment.md"
    F_VERDICT=ERROR F_EXIT=1 F_REASON=publish-failed F_NEXT="make the --out / --markdown location writable and re-run"
    rc=1
  fi
  if [[ -n "$scratch" && -d "$scratch" ]]; then
    if [[ "$KEEP" == 1 ]]; then
      say "WARNING: --keep-scratch: $scratch holds unredacted harness transcripts; delete it when done"
    else
      chmod -R u+w "$scratch" 2>/dev/null
      rm -rf "$scratch"
    fi
  fi
  if [[ -z "$F_VERDICT" ]]; then F_VERDICT=ERROR F_EXIT=1 F_REASON=script-aborted F_NEXT="read the stderr above and re-run"; rc=1; fi
  print_final
  exit "$rc"
}
trap on_exit EXIT
TRAP_ARMED=1

# ---- 3. app hash, scratch root, protected paths ---------------------------------------------------------------------
step 3 "hash the app's package files and installed SDK; list the paths to protect"
PRE_HASH="$(app_hash)"

# Scratch root: needed now because every npm call runs with a scratch HOME and cache.
scratch="$(mktemp -d "${TMPDIR:-/tmp}/remeasure-sdk.XXXXXXXX")" || finish ERROR 1 setup-missing "TMPDIR is not writable"
scratch="$(cd "$scratch" && pwd -P)"
mkdir -p "$scratch/npm-home" "$scratch/npm-cache" "$scratch/baseline" "$scratch/candidate"

# Protected paths (the post-lock write probe's list; NUL-separated): every worktree and the git common dir. Fails
# closed when git cannot list them, when the app's own checkout is missing from the list, or when a listed worktree is
# not a directory and git did not mark it prunable.
PROTECTED="$scratch/protected.list"
under() { [[ "$1" == "$2" || "$1" == "$2"/* ]]; }
protect_fail() { finish UNVERIFIED 3 containment-unavailable "$1; record UNVERIFIED and file an issue"; }
own_top="$(git -C "$APP" rev-parse --show-toplevel 2>/dev/null)" || protect_fail "the app is not in a git checkout"
common="$(git -C "$APP" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || protect_fail "git could not name the common dir"
wt_raw="$scratch/worktrees.z"
git -C "$APP" worktree list --porcelain -z >"$wt_raw" 2>/dev/null || protect_fail "git worktree list failed"
: >"$PROTECTED"
own_listed=0 wt="" wt_prunable=0
flush_wt() {
  [[ -n "$wt" ]] || return 0
  if [[ -d "$wt" ]]; then
    printf '%s\0' "$wt" >>"$PROTECTED"
    [[ "$(cd "$wt" && pwd -P)" == "$(cd "$own_top" && pwd -P)" ]] && own_listed=1
  elif [[ "$wt_prunable" != 1 ]]; then
    protect_fail "git lists worktree $wt, which is not a directory and not prunable"
  fi
  wt="" wt_prunable=0
}
while IFS= read -r -d '' field; do
  case "$field" in
    "worktree "*) flush_wt; wt="${field#worktree }" ;;
    prunable|"prunable "*) wt_prunable=1 ;;
    "") flush_wt ;;
  esac
done <"$wt_raw"
flush_wt
[[ "$own_listed" == 1 ]] || protect_fail "git worktree list does not include the app's own checkout"
[[ -d "$common" ]] || protect_fail "the git common dir $common is not a directory"
printf '%s\0' "$common" >>"$PROTECTED"

real_home="$(cd "$HOME" 2>/dev/null && pwd -P || printf '%s' "$HOME")"
inside=""
under "$scratch" "$real_home" && inside="\$HOME"
while IFS= read -r -d '' p; do under "$scratch" "$p" && inside="$p"; done <"$PROTECTED"
if [[ -n "$inside" ]]; then
  finish UNVERIFIED 3 scratch-inside-protected-path "set TMPDIR outside \$HOME, every worktree and the git common dir"
fi
if under "$APP" "$real_home"; then
  finish UNVERIFIED 3 containment-unavailable "the app checkout lives under \$HOME, which the run masks; use a checkout outside \$HOME"
fi

# Two distinct empty rc files: npm refuses to load one path (even /dev/null) as both user and global config.
: > "$scratch/npm-home/user.npmrc"
: > "$scratch/npm-home/global.npmrc"
npmx() { # the hardened npm environment: no ~/.npmrc, no shared cache, explicit registry
  env -i PATH="$PATH" HOME="$scratch/npm-home" npm_config_userconfig="$scratch/npm-home/user.npmrc" \
    npm_config_globalconfig="$scratch/npm-home/global.npmrc" \
    npm_config_cache="$scratch/npm-cache" npm_config_registry="$REGISTRY" npm "$@"
}
# read_json <key>... < file: the value at that key path ("" when absent; objects and arrays as JSON). Each argument is
# one key, so a key may hold dots (a version, "node_modules/<pkg>").
read_json() {
  node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const v=process.argv.slice(1).reduce((o,k)=>o==null?undefined:o[k],JSON.parse(s));process.stdout.write(v==null?"":typeof v==="object"?JSON.stringify(v):String(v))}catch{}})' "$@"
}
# The classifier, under a clean environment (no operator NODE_OPTIONS, tsx or npm settings). USER, LOGNAME and the
# real home (as REMEASURE_IDENTITY_HOME) pass through so its redaction check still knows what must not appear in a record.
classifier() {
  (cd "$APP" && env -i PATH="$PATH" HOME="$scratch/npm-home" USER="${USER:-}" LOGNAME="${LOGNAME:-}" \
    REMEASURE_IDENTITY_HOME="$HOME" \
    "$TSX" --tsconfig "$APP/tsconfig.json" "$CLASSIFIER" "$@")
}

# ---- 4. resolve the version ---------------------------------------------------------------------------------------
step 4 "resolve $PKG@$REQ"
classifier baseline-json >"$scratch/baseline.json" 2>/dev/null
BASE_V="$(read_json version <"$scratch/baseline.json")"
BASE_INT_SDK="$(read_json integrity sdk <"$scratch/baseline.json")"
BASE_INT_X64="$(read_json integrity linuxX64 <"$scratch/baseline.json")"
ARMS_JSON="$(read_json arms <"$scratch/baseline.json")"
SENTINEL="$(read_json sentinel <"$scratch/baseline.json")"
[[ "$BASE_V" =~ $SEMVER_RE && -n "$BASE_INT_SDK" && -n "$BASE_INT_X64" && "$ARMS_JSON" == '['*']' && -n "$SENTINEL" ]] \
  || finish ERROR 1 setup-missing "the classifier's baseline-json did not load; run npm ci in apps/web-platform"
EXACT="$(npmx view "$PKG@$REQ" version 2>/dev/null | tail -n1)"
[[ "$EXACT" =~ $SEMVER_RE ]] || finish ERROR 1 bad-version-arg "npm resolved '$REQ' to no single exact version"
CAND_LABEL="$EXACT"
X64_V="$(npmx view "$PKG@$EXACT" optionalDependencies --json 2>/dev/null | read_json "$PKG_X64")"
[[ "$X64_V" =~ $SEMVER_RE ]] || finish ERROR 1 install-failed "$PKG@$EXACT lists no $PKG_X64 optional dependency"
say "requested=$REQ exact=$EXACT linux-x64=$X64_V baseline=$BASE_V"

# ---- 5. release-age floor -----------------------------------------------------------------------------------------
step 5 "release-age floor (${FLOOR_DAYS} days, ADR-191)"
now="$(date -u +%s)"
clear_at=""
for pv in "$PKG@$EXACT" "$PKG_X64@$X64_V"; do
  p="${pv%@*}" v="${pv##*@}"
  # time["<exact>"], never created/modified. GNU `date -d ""` is today's midnight, so an empty time is checked first.
  ts="$(npmx view "$p" time --json 2>/dev/null | read_json "$v")"
  [[ -n "$ts" ]] || finish ERROR 1 install-failed "no publish time for $p@$v"
  pub="$(date -u -d "$ts" +%s 2>/dev/null)" || finish ERROR 1 install-failed "unreadable publish time for $p@$v"
  ok_at=$((pub + FLOOR_DAYS * 86400))
  if (( now < ok_at )); then
    t="$(date -u -d "@$ok_at" +%FT%TZ)"
    [[ -z "$clear_at" || "$t" > "$clear_at" ]] && clear_at="$t"
  fi
done
if [[ -n "$clear_at" ]]; then
  finish REFUSED 3 release-age-floor "re-run after $clear_at"
fi

# ---- 6. disk ------------------------------------------------------------------------------------------------------
step 6 "scratch disk space"
free_kb="$(df -Pk "$scratch" 2>/dev/null | awk 'NR==2 {print $4}')"
if ! [[ "$free_kb" =~ ^[0-9]+$ ]] || (( free_kb < MIN_FREE_KB )); then
  finish ERROR 1 low-disk "free at least 2 GB under TMPDIR (two SDK installs)"
fi

# ---- 7/8. install, signatures, versions, integrity ------------------------------------------------------------------
install_prefix() { # dir version
  local d="$1" v="$2"
  (cd "$d" && npmx install --prefix "$d" --ignore-scripts --no-audit --no-fund --save-exact --min-release-age="$FLOOR_DAYS" "$PKG@$v") >"$d/install.log" 2>&1 \
    || { tail -n 20 "$d/install.log" >&2; finish ERROR 1 install-failed "read the npm output above and re-run"; }
  (cd "$d" && npmx audit signatures --prefix "$d") >"$d/audit.log" 2>&1 \
    || { tail -n 20 "$d/audit.log" >&2; finish REFUSED 3 signature-verification-failed "file a security issue; do not record a finding"; }
  local got
  got="$(read_json version < "$d/node_modules/$PKG/package.json" 2>/dev/null)"
  [[ "$got" == "$v" && -x "$d/node_modules/$PKG_X64/claude" ]] || finish ERROR 1 version-mismatch "installed $PKG@${got:-none} in $(basename "$d"), expected $v"
}
lock_integrity() { read_json packages "node_modules/$2" integrity < "$1/package-lock.json" 2>/dev/null; } # dir package
cli_of() { read_json claudeCodeVersion < "$1/node_modules/$PKG/package.json" 2>/dev/null; }

step 7 "install baseline $PKG@$BASE_V"
install_prefix "$scratch/baseline" "$BASE_V"
B_INT_SDK="$(lock_integrity "$scratch/baseline" "$PKG")"
B_INT_X64="$(lock_integrity "$scratch/baseline" "$PKG_X64")"
if [[ "$B_INT_SDK" != "$BASE_INT_SDK" || "$B_INT_X64" != "$BASE_INT_X64" ]]; then
  finish REFUSED 3 baseline-integrity-mismatch "file a security issue: published npm bytes never change"
fi
step 8 "install candidate $PKG@$EXACT"
install_prefix "$scratch/candidate" "$EXACT"
C_INT_SDK="$(lock_integrity "$scratch/candidate" "$PKG")"
C_INT_X64="$(lock_integrity "$scratch/candidate" "$PKG_X64")"
BASE_CLI="$(cli_of "$scratch/baseline")"
CAND_CLI="$(cli_of "$scratch/candidate")"
say "versions: baseline sdk=$BASE_V cli=${BASE_CLI:-?}; candidate sdk=$EXACT cli=${CAND_CLI:-?}"
[[ "$BASE_CLI" =~ $SEMVER_RE && "$CAND_CLI" =~ $SEMVER_RE ]] || finish ERROR 1 version-mismatch "an installed SDK has no claudeCodeVersion"

# ---- 9/10. harness runs -------------------------------------------------------------------------------------------
# INNER runs in the run's outer user + mount + net + pid namespace. Each step fails closed with exit 83 and a stderr
# line starting `remeasure-containment:`. It builds the read-only tree, then execs PROBE in a nested user + mount + net
# namespace: mounts inherited into a less-privileged namespace are locked (no umount, no read-write remount), so the
# probe checks the tree the harness will see, then execs the harness.
# shellcheck disable=SC2016
INNER='
set -u
label=$1 home=$2 xdg=$3 scratch=$4 plist=$5 hpath=$6 rundir=$7 entry=$8 tsx=$9 app=${10} harness=${11} common=${12} uid=${13}
fail() { echo "remeasure-containment: $*" >&2; exit 83; }
m() { mount "$@" || fail "mount $* failed"; }
# Hold the scratch root and the app open: the private /tmp below may cover them (they are bound back from the fd).
exec 8<"$scratch" || fail "cannot open the scratch root"
exec 9<"$app" || fail "cannot open the app root"
id_s=$(stat -L -c %d:%i "$scratch") && id_a=$(stat -L -c %d:%i "$app") || fail "cannot stat the scratch or app root"
m -t tmpfs -o ro,size=64k,mode=0555 remeasure-home "$home"
if [ -n "$xdg" ] && [ -d "$xdg" ]; then m -t tmpfs -o ro,size=64k,mode=0555 remeasure-xdg "$xdg"; fi
m -o remount,bind,ro=recursive /
m -o remount,bind,rw /proc
m -t tmpfs -o rw,nosuid,nodev,size=1m,mode=0755 remeasure-run /run
if [ -d /var/run ] && [ ! -L /var/run ]; then m -t tmpfs -o ro,size=64k,mode=0555 remeasure-varrun /var/run; fi
for f in hosts nsswitch.conf resolv.conf; do
  t=$(readlink -m "/etc/$f") || fail "readlink /etc/$f"
  case "$t" in /run/*) [ -e "$t" ] || { mkdir -p "${t%/*}" && : >"$t"; } || fail "cannot make the mountpoint $t" ;; esac
done
m -o remount,bind,ro /run
m -t tmpfs -o rw,nosuid,nodev,mode=1777 remeasure-tmp /tmp
m -t tmpfs -o rw,nosuid,nodev,mode=1777 remeasure-shm /dev/shm
restore() { # dir fd id
  [ "$(stat -L -c %d:%i "$1" 2>/dev/null)" = "$3" ] && return 0
  mkdir -p "$1" || fail "cannot make the mountpoint $1"
  m --no-canonicalize --bind "/proc/self/fd/$2" "$1"
  [ "$(stat -L -c %d:%i "$1" 2>/dev/null)" = "$3" ] || fail "$1 did not come back after the private /tmp"
}
restore "$scratch" 8 "$id_s"
restore "$app" 9 "$id_a"
exec 8<&- 9<&-
for d in "$rundir/home" "$rundir/scratch"; do m --bind "$d" "$d"; m -o remount,bind,rw "$d"; done
exec setsid -w unshare -U -r -n -m bash -c "$PROBE" remeasure-probe "$@" </dev/null
'
# shellcheck disable=SC2016
PROBE='
set -u
label=$1 home=$2 xdg=$3 scratch=$4 plist=$5 hpath=$6 rundir=$7 entry=$8 tsx=$9 app=${10} harness=${11} common=${12} uid=${13}
fail() { echo "remeasure-containment: $*" >&2; exit 83; }
writable() { f="$1/.remeasure-write-probe.$$"; if ( : >"$f" ) 2>/dev/null; then rm -f "$f"; return 0; fi; return 1; }
if mount -o remount,bind,rw / 2>/dev/null; then fail "/ can be remounted read-write"; fi
# A bind onto itself first, so the remount below is refused for the lock, not because the path is no mount point. (A
# common dir under /tmp or /dev/shm is not visible here at all; the private tmpfs covers it.)
if [ -d "$common" ]; then
  mount --bind "$common" "$common" 2>/dev/null || fail "probe: cannot bind the git common dir onto itself"
  if mount -o remount,bind,rw "$common" 2>/dev/null; then fail "the git common dir can be remounted read-write"; fi
fi
if umount /run 2>/dev/null; then fail "/run can be unmounted"; fi
if umount /proc 2>/dev/null; then fail "/proc can be unmounted"; fi
if writable "$home"; then fail "HOME is writable"; fi
if [ -n "$xdg" ] && writable "$xdg"; then fail "XDG_RUNTIME_DIR is writable"; fi
while IFS= read -r -d "" p; do
  [ -d "$p" ] || continue
  if writable "$p"; then fail "$p is writable"; fi
done <"$plist"
if writable "$scratch"; then fail "the scratch root is writable"; fi
if writable "$rundir"; then fail "the run dir (stdout, stderr, spec.json) is writable"; fi
if [ "$label" = candidate ] && writable "$scratch/run-baseline"; then fail "the baseline run dir is writable"; fi
writable "$rundir/home" || fail "the run home is not writable"
writable "$rundir/scratch" || fail "the run scratch is not writable"
# remeasure-socket-probe: exit 0 = connected, 1 = refused or absent, anything else = the probe itself failed.
sock_js="/* remeasure-socket-probe */ const s = require(\"net\").connect(process.argv[1]);
s.on(\"connect\", () => process.exit(0));
s.on(\"error\", (e) => process.exit([\"ENOENT\", \"ECONNREFUSED\", \"EACCES\", \"EPERM\", \"ENOTDIR\", \"ENOTSOCK\"].includes(e.code) ? 1 : 2));
setTimeout(() => process.exit(2), 5000);"
for s in /run/docker.sock /var/run/docker.sock "/run/user/$uid/bus"; do
  PATH="$hpath" node -e "$sock_js" "$s"
  case $? in
    0) fail "$s accepts connections" ;;
    1) : ;;
    *) fail "the socket probe could not run for $s" ;;
  esac
done
cd "$app" || fail "cd app"
exec env -i PATH="$hpath" HOME="$rundir/home" LANG=C.UTF-8 NODE_ENV=test NETNS_SDK_ENTRY="$entry" "$tsx" --tsconfig "$app/tsconfig.json" "$harness" "$rundir/spec.json"
'
# PATH for the harness: the caller's, minus anything under the masked $HOME (no shims from a hidden dir).
HPATH="$(printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r e; do [[ -n "$e" ]] && ! under "$e" "$real_home" && ! under "$e" "$HOME" && printf '%s\n' "$e"; done | paste -sd: -)"
redact_tail() { tail -n 40 "$1" | sed -e "s/$SENTINEL/<redacted>/g" -e "s#$scratch#<scratch>#g" -e "s#$real_home#<home>#g" >&2; }
entry_of() { printf '%s' "$scratch/$1/node_modules/$PKG/sdk.mjs"; }
run_harness() { # label
  local label="$1" d="$scratch/run-$1"
  mkdir -p "$d/home" "$d/scratch"
  printf '{"appRoot":"%s","scratch":"%s","tap":"allow-all","arms":%s}\n' "$APP" "$d/scratch" "$ARMS_JSON" > "$d/spec.json"
  (cd "$APP" && PROBE="$PROBE" timeout -k 10 600 "${UNSHARE_RUN[@]}" \
      bash -c "$INNER" remeasure-inner "$label" "$HOME" "${XDG_RUNTIME_DIR:-}" "$scratch" "$PROTECTED" "$HPATH" "$d" \
        "$(entry_of "$label")" "$TSX" "$APP" "$HARNESS" "$common" "$(id -u)") \
    >"$d/stdout" 2>"$d/stderr"
  local rc=$?
  if [[ "$rc" == 83 ]] && grep -q '^remeasure-containment:' "$d/stderr"; then
    redact_tail "$d/stderr"
    finish UNVERIFIED 3 containment-unavailable "this host cannot build or lock the read-only run tree; record UNVERIFIED and file an issue"
  fi
  if [[ "$rc" != 0 ]]; then
    say "$label harness exited $rc (124 = timed out); stderr tail:"
    redact_tail "$d/stderr"
    finish ERROR 1 harness-crash "fix the cause and re-run"
  fi
}
step 9 "baseline harness run (up to 10 min)"
run_harness baseline
BASE_OUT_SHA="$(sha256sum "$scratch/run-baseline/stdout" | cut -d' ' -f1)"
step 10 "candidate harness run (up to 10 min)"
run_harness candidate

# ---- 11. classify -------------------------------------------------------------------------------------------------
step 11 "classify"
if [[ "$(sha256sum "$scratch/run-baseline/stdout" | cut -d' ' -f1)" != "$BASE_OUT_SHA" ]]; then
  finish UNVERIFIED 3 containment-breached "the baseline's stdout changed during the candidate run; record UNVERIFIED and file a security issue"
fi
ENV_JSON="$scratch/env.json"
node -e '
const [out, ...kv] = process.argv.slice(1); const o = {};
for (let i = 0; i < kv.length; i += 2) o[kv[i]] = kv[i + 1];
require("fs").writeFileSync(out, JSON.stringify(o));
' "$ENV_JSON" \
  startedAt "$STARTED_AT" endedAt "$(date -u +%FT%TZ)" \
  requested "$REQ" exactVersion "$EXACT" linuxX64Version "$X64_V" \
  candidateIntegritySdk "$C_INT_SDK" candidateIntegrityLinuxX64 "$C_INT_X64" \
  nodeVersion "$(node --version 2>/dev/null)" npmVersion "$(npmx --version 2>/dev/null)" \
  kernel "$(uname -r 2>/dev/null | grep -oE '^[0-9]+(\.[0-9]+)*')" \
  bwrap "$(bwrap --version 2>/dev/null | head -n1)" \
  os "$(sed -n 's/^ID=//p' /etc/os-release 2>/dev/null | tr -d '"')"
cargs=(--baseline "$scratch/run-baseline/stdout" --candidate "$scratch/run-candidate/stdout"
  --baseline-sdk "$BASE_V" --baseline-cli "$BASE_CLI" --candidate-sdk "$EXACT" --candidate-cli "$CAND_CLI"
  --baseline-entry "$(entry_of baseline)" --candidate-entry "$(entry_of candidate)"
  --requested "$REQ" --command "$CMD_LINE" --scratch-root "$scratch" --app-root "$APP" --env "$ENV_JSON")
[[ -n "$OUT" ]] && cargs+=(--out "$scratch/verdict.json")
[[ -n "$MD" ]] && cargs+=(--markdown "$scratch/md")
classifier "${cargs[@]}" > "$scratch/classify.out" 2>"$scratch/classify.err"
crc=$?
grep -v '^REMEASURE ' "$scratch/classify.out"
line="$(grep '^REMEASURE ' "$scratch/classify.out" | tail -n1)"
if [[ -z "$line" ]]; then
  redact_tail "$scratch/classify.err"
  finish ERROR 1 classifier-crash "fix the classifier and re-run"
fi
v="$(sed -n 's/^REMEASURE verdict=\([^ ]*\) .*/\1/p' <<<"$line")"
r="$(sed -n 's/^REMEASURE .* reason=\([^ ]*\) next=.*/\1/p' <<<"$line")"
n="$(sed -n 's/^REMEASURE .* next=//p' <<<"$line")"
finish "$v" "$crc" "$r" "$n"
