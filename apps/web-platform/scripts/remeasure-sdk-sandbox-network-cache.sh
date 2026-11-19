#!/usr/bin/env bash
# remeasure-sdk-sandbox-network-cache.sh — re-measure whether an Agent SDK version still caches a per-host
# SandboxNetworkAccess allow for the whole session (#12906 PR-1b; ADR-278; harness from #12897).
#
# Usage:
#   bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh <version|dist-tag> \
#        [--out <verdict.json>] [--markdown <dir>] [--keep-scratch]
#
# SCOPE: evidence only. It never moves the app's SDK pin. It installs the pinned baseline (MEASURED_BASELINE in
# scripts/lib/sandbox-network-cache-verdict.ts) and the candidate into two scratch prefixes under $TMPDIR, runs
# test/helpers/netns-egress-harness.mts (allow-all tap; arms control,B,D,E,F,F2) once per prefix inside
# `unshare -rnm`, and classifies the two runs side by side. The app's package.json, package-lock.json and installed
# node_modules/@anthropic-ai/claude-agent-sdk* are hashed before and after; any change is exit 1 `app-mutated`.
#
# Containment (per harness run, inside its mount namespace, before tsx starts): read-only tmpfs over $HOME and
# $XDG_RUNTIME_DIR; every `git worktree list` path and the git common dir remounted read-only; a write probe that
# must fail in each of those and succeed in the scratch root. Any failure is exit 3 `containment-unavailable`; it
# never runs uncontained. Remaining exposure: /tmp outside scratch and the rest of the user-writable filesystem.
# Consequence: the app checkout must not live under $HOME (the tmpfs would hide it).
#
# Every exit ends with one line:   REMEASURE verdict=<word> exit=<n> reason=<token> next=<action>
#
# Exit codes:
#   0  CACHES | RE-ASKS-AFTER-TEARDOWN | MIXED (a finding)
#   1  ERROR         setup-missing, bad-version-arg, low-disk, install-failed, version-mismatch, harness-crash,
#                    classifier parse reasons, app-mutated (overrides every other exit)
#   2  INCONCLUSIVE  a precondition or the cache reading did not fit (re-run once)
#   3  UNVERIFIED    unsupported-arch, no-userns, containment-unavailable, scratch-inside-protected-path, step0:*
#      REFUSED       release-age-floor, signature-verification-failed, baseline-integrity-mismatch
#   4  LEAK          a decoy hit or an unauthenticated gateway line in a non-control arm
#
# Verdict-to-action:
#   CACHES                  #12906 stays blocked; record the run in ADR-278 and on #12906
#   RE-ASKS-AFTER-TEARDOWN  record the run; it triggers #12906's build and its live-forwarder deny-flip arm; it is
#                           not proof that an allow is revocable
#   MIXED                   record the run; most consistent with a per-command cache; a #12906 trigger like
#                           RE-ASKS-AFTER-TEARDOWN
#   INCONCLUSIVE            re-run once; then record the run and file an issue naming the reason
#   ERROR                   fix the cause and re-run; app-mutated also files a bug against this script
#   LEAK                    separate ADR-278 addendum plus a bug issue against adopting that SDK
#   UNVERIFIED              record UNVERIFIED:sdk-<v>-sandbox-network-allow-cache and file an issue
#   REFUSED                 no finding; wait for the floor (release-age), or file a security issue
#
# Any SDK or bundled-CLI bump re-arms CLO gate B-2 (ADR-278 2026-11-18 addendum); this script neither satisfies nor
# re-arms it. The ADR-191 release-age floor (3 days) is enforced, never overridden.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$(cd "$SCRIPT_DIR/.." && pwd)"
PKG="@anthropic-ai/claude-agent-sdk"
PKG_X64="@anthropic-ai/claude-agent-sdk-linux-x64"
REGISTRY="https://registry.npmjs.org/"
FLOOR_DAYS=3
MIN_FREE_KB=$((2 * 1024 * 1024))
TSX="$APP/node_modules/.bin/tsx"
HARNESS="$APP/test/helpers/netns-egress-harness.mts"
CLASSIFIER="$APP/scripts/lib/sandbox-network-cache-verdict.ts"
CMD_LINE="bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh $*"
STARTED_AT="$(date -u +%FT%TZ)"

say() { printf '%s\n' "$*" >&2; }
step() { say "[$1/11] $2"; }

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

# ---- arguments ----------------------------------------------------------------------------------------------------
REQ="" OUT="" MD="" KEEP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    --out) OUT="${2-}"; shift 2 || finish ERROR 1 bad-args "pass a path after --out" ;;
    --markdown) MD="${2-}"; shift 2 || finish ERROR 1 bad-args "pass a dir after --markdown" ;;
    --keep-scratch) KEEP=1; shift ;;
    -*) finish ERROR 1 bad-args "unknown option $1; see --help" ;;
    *) if [[ -n "$REQ" ]]; then finish ERROR 1 bad-args "pass exactly one version"; fi; REQ="$1"; shift ;;
  esac
done
CAND_LABEL="$REQ"
[[ -n "$REQ" ]] || finish ERROR 1 bad-args "pass the candidate version or dist-tag; see --help"
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'
if ! [[ "$REQ" =~ $SEMVER_RE || "$REQ" =~ ^[a-z][a-z0-9-]{0,30}$ ]]; then
  CAND_LABEL="unknown"
  finish ERROR 1 bad-version-arg "pass an exact semver or a dist-tag (no npm: aliases, file: paths or URLs)"
fi

# ---- 1. setup preflight -------------------------------------------------------------------------------------------
step 1 "setup preflight"
if [[ "$(uname -s 2>/dev/null)" != Linux || "$(uname -m 2>/dev/null)" != x86_64 ]] || ! getconf GNU_LIBC_VERSION 2>/dev/null | grep -q '^glibc '; then
  finish UNVERIFIED 3 unsupported-arch "run on a Linux x86_64 glibc host (the CLI lookup mirrors the SDK's linux-x64 path)"
fi
missing=()
for t in node npm unshare timeout git sha256sum df; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
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
step 2 "user + network namespace check"
if ! unshare -rnm true >/dev/null 2>&1; then
  finish UNVERIFIED 3 no-userns "record UNVERIFIED and file an issue with the host kernel and userns settings"
fi

# ---- 3. EXIT trap -------------------------------------------------------------------------------------------------
scratch=""
PRE_HASH=""
app_hash() {
  {
    printf '%s\0' "$APP/package.json" "$APP/package-lock.json"
    find "$APP"/node_modules/@anthropic-ai/ -maxdepth 1 -name 'claude-agent-sdk*' -print0 2>/dev/null \
      | xargs -0 -r -I{} find {} -type f -print0
  } | sort -z | xargs -0 sha256sum 2>&1 | sha256sum | cut -d' ' -f1
}
# shellcheck disable=SC2329  # invoked by the EXIT trap
on_exit() {
  local rc=$?
  trap - EXIT
  if [[ -n "$PRE_HASH" && "$(app_hash)" != "$PRE_HASH" ]]; then
    say "app tree changed during the run (package.json, package-lock.json or node_modules/@anthropic-ai/claude-agent-sdk*)"
    F_VERDICT=ERROR F_EXIT=1 F_REASON=app-mutated F_NEXT="restore the app tree with npm ci and file a bug against this script"
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

# ---- 4. app hash --------------------------------------------------------------------------------------------------
step 4 "hash the app's package files and installed SDK"
PRE_HASH="$(app_hash)"

# Scratch root: needed now because every npm call runs with a scratch HOME and cache.
scratch="$(mktemp -d "${TMPDIR:-/tmp}/remeasure-sdk.XXXXXXXX")" || finish ERROR 1 setup-missing "TMPDIR is not writable"
scratch="$(cd "$scratch" && pwd -P)"
mkdir -p "$scratch/npm-home" "$scratch/npm-cache" "$scratch/baseline" "$scratch/candidate"

# Protected paths: $HOME, every worktree, the git common dir.
PROTECTED="$scratch/protected.list"
{
  git -C "$APP" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p'
  git -C "$APP" rev-parse --path-format=absolute --git-common-dir 2>/dev/null
} | awk 'NF && !seen[$0]++' > "$PROTECTED"
[[ -s "$PROTECTED" ]] || finish UNVERIFIED 3 containment-unavailable "the app is not in a git checkout; cannot list paths to protect"
under() { [[ "$1" == "$2" || "$1" == "$2"/* ]]; }
real_home="$(cd "$HOME" 2>/dev/null && pwd -P || printf '%s' "$HOME")"
inside=""
under "$scratch" "$real_home" && inside="\$HOME"
while IFS= read -r p; do under "$scratch" "$p" && inside="$p"; done < "$PROTECTED"
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

# ---- 5. resolve the version ---------------------------------------------------------------------------------------
step 5 "resolve $PKG@$REQ"
BASE_JSON="$("$TSX" --tsconfig "$APP/tsconfig.json" "$CLASSIFIER" baseline-json 2>/dev/null)"
read_json() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const v=process.argv[1].split(".").reduce((o,k)=>o==null?undefined:o[k],JSON.parse(s));process.stdout.write(v==null?"":String(v))}catch{}})' "$1"; }
BASE_V="$(printf '%s' "$BASE_JSON" | read_json version)"
BASE_INT_SDK="$(printf '%s' "$BASE_JSON" | read_json integrity.sdk)"
BASE_INT_X64="$(printf '%s' "$BASE_JSON" | read_json integrity.linuxX64)"
[[ "$BASE_V" =~ $SEMVER_RE && -n "$BASE_INT_SDK" && -n "$BASE_INT_X64" ]] || finish ERROR 1 setup-missing "the classifier's baseline-json did not load; run npm ci in apps/web-platform"
EXACT="$(npmx view "$PKG@$REQ" version 2>/dev/null | tail -n1)"
[[ "$EXACT" =~ $SEMVER_RE ]] || finish ERROR 1 bad-version-arg "npm resolved '$REQ' to no single exact version"
CAND_LABEL="$EXACT"
X64_V="$(npmx view "$PKG@$EXACT" optionalDependencies --json 2>/dev/null | read_json "$PKG_X64")"
[[ "$X64_V" =~ $SEMVER_RE ]] || finish ERROR 1 install-failed "$PKG@$EXACT lists no $PKG_X64 optional dependency"
say "requested=$REQ exact=$EXACT linux-x64=$X64_V baseline=$BASE_V"

# ---- 6. release-age floor -----------------------------------------------------------------------------------------
step 6 "release-age floor (${FLOOR_DAYS} days, ADR-191)"
now="$(date -u +%s)"
clear_at=""
for pv in "$PKG@$EXACT" "$PKG_X64@$X64_V"; do
  p="${pv%@*}" v="${pv##*@}"
  # time["<exact>"], never created/modified. A version key holds dots, so this is a direct key lookup, not read_json.
  ts="$(npmx view "$p" time --json 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(String(JSON.parse(s)[process.argv[1]]??""))}catch{}})' "$v")"
  pub="$(date -u -d "$ts" +%s 2>/dev/null)" || pub=""
  [[ -n "$pub" ]] || finish ERROR 1 install-failed "no publish time for $p@$v"
  ok_at=$((pub + FLOOR_DAYS * 86400))
  if (( now < ok_at )); then
    t="$(date -u -d "@$ok_at" +%FT%TZ)"
    [[ -z "$clear_at" || "$t" > "$clear_at" ]] && clear_at="$t"
  fi
done
if [[ -n "$clear_at" ]]; then
  finish REFUSED 3 release-age-floor "re-run after $clear_at"
fi

# ---- 7. disk ------------------------------------------------------------------------------------------------------
step 7 "scratch dirs and disk"
free_kb="$(df -Pk "$scratch" 2>/dev/null | awk 'NR==2 {print $4}')"
if ! [[ "$free_kb" =~ ^[0-9]+$ ]] || (( free_kb < MIN_FREE_KB )); then
  finish ERROR 1 low-disk "free at least 2 GB under TMPDIR (two SDK installs)"
fi

# ---- 8/9/9b. install, signatures, versions, integrity ---------------------------------------------------------------
install_prefix() { # dir version
  local d="$1" v="$2"
  (cd "$d" && npmx install --prefix "$d" --ignore-scripts --no-audit --no-fund --save-exact --min-release-age=3 "$PKG@$v") >"$d/install.log" 2>&1 \
    || { tail -n 20 "$d/install.log" >&2; finish ERROR 1 install-failed "read the npm output above and re-run"; }
  (cd "$d" && npmx audit signatures --prefix "$d") >"$d/audit.log" 2>&1 \
    || { tail -n 20 "$d/audit.log" >&2; finish REFUSED 3 signature-verification-failed "file a security issue; do not record a finding"; }
  local got
  got="$(read_json version < "$d/node_modules/$PKG/package.json" 2>/dev/null)"
  [[ "$got" == "$v" && -x "$d/node_modules/$PKG_X64/claude" ]] || finish ERROR 1 version-mismatch "installed $PKG@${got:-none} in $(basename "$d"), expected $v"
}
lock_integrity() { # dir package
  node -e 'try{const l=require(process.argv[1]);process.stdout.write(l.packages["node_modules/"+process.argv[2]].integrity||"")}catch{}' "$1/package-lock.json" "$2"
}
cli_of() { read_json claudeCodeVersion < "$1/node_modules/$PKG/package.json" 2>/dev/null; }

step 8 "install baseline $PKG@$BASE_V"
install_prefix "$scratch/baseline" "$BASE_V"
if [[ "$(lock_integrity "$scratch/baseline" "$PKG")" != "$BASE_INT_SDK" || "$(lock_integrity "$scratch/baseline" "$PKG_X64")" != "$BASE_INT_X64" ]]; then
  finish REFUSED 3 baseline-integrity-mismatch "file a security issue: published npm bytes never change"
fi
step 8 "install candidate $PKG@$EXACT"
install_prefix "$scratch/candidate" "$EXACT"
BASE_CLI="$(cli_of "$scratch/baseline")"
CAND_CLI="$(cli_of "$scratch/candidate")"
step 9 "versions: baseline sdk=$BASE_V cli=${BASE_CLI:-?}; candidate sdk=$EXACT cli=${CAND_CLI:-?}"
[[ "$BASE_CLI" =~ $SEMVER_RE && "$CAND_CLI" =~ $SEMVER_RE ]] || finish ERROR 1 version-mismatch "an installed SDK has no claudeCodeVersion"

# ---- 10. harness runs ---------------------------------------------------------------------------------------------
# Runs inside the run's user + mount + net + pid namespace, before tsx: mask, remount, probe, then exec the harness.
# shellcheck disable=SC2016
INNER='
set -u
home=$1 xdg=$2 scratch=$3 plist=$4 hpath=$5 runhome=$6 entry=$7 tsx=$8 app=$9 harness=${10} spec=${11}
fail() { echo "remeasure-containment: $*" >&2; exit 83; }
writable() { f="$1/.remeasure-write-probe.$$"; if ( : > "$f" ) 2>/dev/null; then rm -f "$f"; return 0; fi; return 1; }
mount -t tmpfs -o ro,size=64k,mode=0555 remeasure-home "$home" || fail "tmpfs over HOME failed"
if [ -n "$xdg" ] && [ -d "$xdg" ]; then mount -t tmpfs -o ro,size=64k,mode=0555 remeasure-xdg "$xdg" || fail "tmpfs over XDG_RUNTIME_DIR failed"; fi
while IFS= read -r p; do
  [ -d "$p" ] || continue
  mount --bind "$p" "$p" || fail "bind $p failed"
  mount -o remount,bind,ro "$p" || fail "read-only remount of $p failed"
done < "$plist"
if writable "$home"; then fail "HOME still writable"; fi
if [ -n "$xdg" ] && [ -d "$xdg" ] && writable "$xdg"; then fail "XDG_RUNTIME_DIR still writable"; fi
while IFS= read -r p; do
  [ -d "$p" ] || continue
  if writable "$p"; then fail "$p still writable"; fi
done < "$plist"
writable "$scratch" || fail "scratch not writable"
cd "$app" || fail "cd app"
exec env -i PATH="$hpath" HOME="$runhome" LANG=C.UTF-8 NODE_ENV=test NETNS_SDK_ENTRY="$entry" "$tsx" --tsconfig "$app/tsconfig.json" "$harness" "$spec"
'
# PATH for the harness: the caller's, minus anything under the masked $HOME (no shims from a hidden dir).
HPATH="$(printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r e; do [[ -n "$e" ]] && ! under "$e" "$real_home" && ! under "$e" "$HOME" && printf '%s\n' "$e"; done | paste -sd: -)"
redact_tail() { tail -n 40 "$1" | sed -e 's/decoy-api-key-sentinel/<redacted>/g' -e "s#$scratch#<scratch>#g" -e "s#$real_home#<home>#g" >&2; }
run_harness() { # label
  local label="$1" d="$scratch/run-$1"
  mkdir -p "$d/home" "$d/scratch"
  local entry="$scratch/$label/node_modules/$PKG/sdk.mjs"
  printf '{"appRoot":"%s","scratch":"%s","tap":"allow-all","arms":["control","B","D","E","F","F2"]}\n' "$APP" "$d/scratch" > "$d/spec.json"
  (cd "$APP" && timeout -k 10 600 unshare -rnm --fork --pid --mount-proc --kill-child \
      bash -c "$INNER" remeasure-inner "$HOME" "${XDG_RUNTIME_DIR:-}" "$scratch" "$PROTECTED" "$HPATH" "$d/home" "$entry" "$TSX" "$APP" "$HARNESS" "$d/spec.json") \
    >"$d/stdout" 2>"$d/stderr"
  local rc=$?
  if [[ "$rc" == 83 ]]; then
    redact_tail "$d/stderr"
    finish UNVERIFIED 3 containment-unavailable "this host cannot mask \$HOME or remount the checkout read-only; record UNVERIFIED and file an issue"
  fi
  if [[ "$rc" != 0 ]]; then
    say "$label harness exited $rc (124 = timed out); stderr tail:"
    redact_tail "$d/stderr"
    finish ERROR 1 harness-crash "fix the cause and re-run"
  fi
}
step 10 "baseline harness run (up to 10 min)"
run_harness baseline
step 10 "candidate harness run (up to 10 min)"
run_harness candidate

# ---- 11. classify -------------------------------------------------------------------------------------------------
step 11 "classify"
ENV_JSON="$scratch/env.json"
node -e '
const [out, ...kv] = process.argv.slice(1); const o = {};
for (let i = 0; i < kv.length; i += 2) o[kv[i]] = kv[i + 1];
require("fs").writeFileSync(out, JSON.stringify(o));
' "$ENV_JSON" \
  startedAt "$STARTED_AT" endedAt "$(date -u +%FT%TZ)" \
  requested "$REQ" exactVersion "$EXACT" linuxX64Version "$X64_V" \
  candidateIntegritySdk "$(lock_integrity "$scratch/candidate" "$PKG")" \
  candidateIntegrityLinuxX64 "$(lock_integrity "$scratch/candidate" "$PKG_X64")" \
  node "$(node --version 2>/dev/null)" npm "$(npmx --version 2>/dev/null)" kernel "$(uname -r 2>/dev/null)" \
  bwrap "$(bwrap --version 2>/dev/null | head -n1)" \
  os "$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | tr -d '"')"
cargs=(--baseline "$scratch/run-baseline/stdout" --candidate "$scratch/run-candidate/stdout"
  --baseline-sdk "$BASE_V" --baseline-cli "$BASE_CLI" --candidate-sdk "$EXACT" --candidate-cli "$CAND_CLI"
  --requested "$REQ" --command "$CMD_LINE" --scratch-root "$scratch" --app-root "$APP" --env "$ENV_JSON")
[[ -n "$OUT" ]] && cargs+=(--out "$OUT")
[[ -n "$MD" ]] && cargs+=(--markdown "$MD")
(cd "$APP" && "$TSX" --tsconfig "$APP/tsconfig.json" "$CLASSIFIER" "${cargs[@]}") > "$scratch/classify.out" 2>"$scratch/classify.err"
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
