#!/usr/bin/env bash
# Offline tests for remeasure-sdk-sandbox-network-cache.sh — #12906 PR-1b (Guard 2 of the plan's Guard Contract, plus the
# script-to-classifier wiring).
#
# Run via:  bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.test.sh
# No network and (except the one real-kernel row) no namespaces: `npm`, `unshare`, `timeout`, `uname`, `getconf`, `df`,
# `mount`, `umount` and a `node` wrapper are stubs that come first on PATH and EXIT 64 on any argv the script is not
# supposed to send (logged to a refusal file every row asserts empty; the hygiene row proves a refusal reaches it).
# Each row copies the script and the REAL classifier into a fixture app tree inside a fixture git repo (with a sibling
# worktree) under this suite's own `mktemp -d`; the fixture links the real tsx, and a fixture harness prints synthesized
# NETNS_* records. The stub `mount` models a read-only mount as `chmod a-w` (undone when the stub outer `unshare` exits,
# as a namespace's mounts would be), and refuses every mount once the stub nested `unshare -U -r -n -m` has run (the
# locked tree), so the script's real post-lock probe is what decides containment. The `node` wrapper answers only the
# probe's socket connect, from cfg/connectable. The real-kernel row runs the real INNER and PROBE with a fake harness
# that attacks the locked tree; it prints SKIP (never a pass) where `unshare -rnm true` fails. All fixtures are
# synthesized (cq-test-fixtures-synthesized-only).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_APP="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT_SRC="$SCRIPT_DIR/remeasure-sdk-sandbox-network-cache.sh"
CLASSIFIER_SRC="$SCRIPT_DIR/lib/sandbox-network-cache-verdict.ts"
REAL_TSX="$REAL_APP/node_modules/.bin/tsx"
REAL_NODE="$(command -v node)"

if [[ ! -f "$SUT_SRC" ]]; then
  echo "ERROR: $SUT_SRC not found (RED: the script does not exist yet)" >&2
  exit 1
fi
if [[ ! -x "$REAL_TSX" ]]; then
  echo "ERROR: $REAL_TSX not found; run npm ci in apps/web-platform" >&2
  exit 1
fi

# Git hygiene: a hook-inherited GIT_* location would make the fixture repos operate on the real checkout.
while IFS= read -r v; do
  case "$v" in GIT_*) unset "$v" ;; esac
done < <(compgen -e)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.invalid

# Canonical assert_fixture_dir — byte-identical copy (fixture-scan.py requires
# the verbatim body; see plugins/soleur/test/test-helpers.sh).
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

T="$(mktemp -d -t soleur-remeasure.$$.XXXXXXXX)"
T="$(cd "$T" && pwd -P)"
RK_BASE="" # the real-kernel row's fixture base, outside /tmp (see that row)
RK_RAN=0
trap 'chmod -R u+w "$T" ${RK_BASE:+"$RK_BASE"} 2>/dev/null; rm -rf "$T" ${RK_BASE:+"$RK_BASE"}' EXIT
assert_fixture_dir "$T"

PASS=0
FAIL=0
ok() { echo "  pass: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
check() { # name, command...
  local name="$1"; shift
  if "$@"; then ok "$name"; else bad "$name"; fi
}
eq() { # name expected actual
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}

# INSTRUMENT SELF-TEST (ADR-193): drive the helpers once with a must-pass and once with a must-fail input in a subshell and read
# the counters back. Reported with printf + exit, never through the helpers themselves.
st_tally="$( ( PASS=0; FAIL=0; ok a >/dev/null; bad b >/dev/null; echo "$PASS $FAIL" ) )"
st_check_ok="$( ( PASS=0; FAIL=0; check a true >/dev/null; echo "$PASS $FAIL" ) )"
st_check_bad="$( ( PASS=0; FAIL=0; check b false >/dev/null; echo "$PASS $FAIL" ) )"
st_eq_ok="$( ( PASS=0; FAIL=0; eq a x x >/dev/null; echo "$PASS $FAIL" ) )"
st_eq_bad="$( ( PASS=0; FAIL=0; eq b x y >/dev/null; echo "$PASS $FAIL" ) )"
if [[ "$st_tally" != "1 1" || "$st_check_ok" != "1 0" || "$st_check_bad" != "0 1" || "$st_eq_ok" != "1 0" || "$st_eq_bad" != "0 1" ]]; then
  printf 'FATAL: instrument self-test: tally "%s", check ok "%s", check must-fail "%s", eq ok "%s", eq must-fail "%s"\n' \
    "$st_tally" "$st_check_ok" "$st_check_bad" "$st_eq_ok" "$st_eq_bad" >&2
  exit 1
fi

SENTINEL="decoy-api-key-""sentinel"
# One baseline-json call: the pinned version and both integrity values come from the classifier, never restated here.
BJ="$(cd "$REAL_APP" && "$REAL_TSX" "$CLASSIFIER_SRC" baseline-json)"
bj() { node -e 'const v=process.argv[2].split(".").reduce((o,k)=>o[k],JSON.parse(process.argv[1]));process.stdout.write(String(v))' "$BJ" "$1"; }
BASE_V="$(bj version)"
BASE_INT_SDK="$(bj integrity.sdk)"
BASE_INT_X64="$(bj integrity.linuxX64)"
check "the classifier's baseline-json carries the version and both integrity values" test -n "$BASE_V" -a -n "$BASE_INT_SDK" -a -n "$BASE_INT_X64"
eq "the classifier's baseline-json sentinel is the suite's" "$SENTINEL" "$(bj sentinel)"
# The script's floor and the app's npm floor are one number (H1): FLOOR_DAYS equals min-release-age in .npmrc.
eq "FLOOR_DAYS equals min-release-age in apps/web-platform/.npmrc" \
  "$(sed -n 's/^min-release-age=//p' "$REAL_APP/.npmrc")" "$(sed -n 's/^FLOOR_DAYS=//p' "$SUT_SRC")"
CAND_V="0.3.325"
LATEST_V="0.3.330"
iso_ago() { date -u -d "@$(( $(date -u +%s) - $1 ))" +%FT%T.000Z; } # seconds ago
OLD_TS="$(iso_ago $((30 * 86400)))"

# ---------------------------------------------------------------------------------------------------------------------------------
# Synthesized harness outputs (one generator, fresh objects per variant).
# ---------------------------------------------------------------------------------------------------------------------------------
mkdir -p "$T/outs"
cat >"$T/gen.mts" <<'GEN'
const [sdk, cli, variant] = process.argv.slice(2);
const D = "198.51.100.1", CONNECT = `CONNECT ${D}:443 HTTP/1.1`, DEAD = "rc=7 out=000";
const call = (host: string) => ({ tool: "SandboxNetworkAccess", input: { host }, keys: ["host"], behavior: "allow" });
const bash = { tool: "Bash", keys: ["command"], behavior: "allow" };
const fH = variant === "inconclusive" ? [D, D] : [D];
const f2H = [D, "example.test"];
const base = (arm: string, x: Record<string, unknown> = {}) => ({ arm, thrown: "", calls: [bash], gateway: [], decoys: [], initClaudeCodeVersion: cli, ...x });
const gw = [{ line: CONNECT, authOk: true, authPresent: true }];
const arms = [
  base("control", { decoys: [{ addr: D, port: 443 }, { addr: D, port: 80 }, { addr: D, port: 22 }, { addr: "127.0.0.2", port: 41000 }, { addr: "169.254.169.254", port: 80 }] }),
  base("B", { calls: [bash, call("example.test"), call(D)], gateway: [{ line: "CONNECT example.test:443 HTTP/1.1", authOk: true, authPresent: true }, ...gw],
    decoys: variant === "leak" ? [{ addr: D, port: 443 }] : [], stubRequests: [{ k: "SENTINEL" }], toolResult: "R b SENTINEL" }),
  base("D", { toolResult: "D_TURN_RAN" }),
  base("E", { calls: [bash, call(D)], toolResult: `R e-1 ${DEAD}` }),
  base("F", { calls: [bash, ...fH.map(call)], gateway: gw, fStep1: true, fTornDown: true, fPortClosed: true,
    toolResult: `R f-1 rc=0 out=403\nR f-barrier seen=yes\nR f-2 ${DEAD}\nR f-3 ${DEAD}` }),
  base("F2", { calls: [bash, ...f2H.map(call)], gateway: gw, fStep1: true, fTornDown: true, fPortClosed: true,
    toolResult: `R f2-1 rc=0 out=403\nR f2-barrier seen=yes\nR f2-2 ${DEAD}\nR f2-new-host ${DEAD}` }),
];
const step0 = { ok: true, loUp: true, nestedBwrap: true, shimBwrap: true, imports: true, sdkEntry: "x", sdkVersion: sdk, cliPath: "y", cliVersion: cli };
const s = [`NETNS_STEP0 ${JSON.stringify(step0)}`, ...arms.map((a) => `NETNS_ARM ${JSON.stringify(a)}`)].join("\n");
process.stdout.write(s.replaceAll("SENTINEL", ["decoy", "api", "key", "sentinel"].join("-")) + "\n");
GEN
gen() { "$REAL_TSX" "$T/gen.mts" "$@"; }
gen "$BASE_V" 2.1.321 caches >"$T/outs/baseline"
gen "$CAND_V" 2.1.325 caches >"$T/outs/cand-caches"
gen "$CAND_V" 2.1.325 inconclusive >"$T/outs/cand-inconclusive"
gen "$CAND_V" 2.1.325 leak >"$T/outs/cand-leak"
gen "$LATEST_V" 2.1.330 caches >"$T/outs/latest-caches"
check "fixture generator wrote seven records per run" test "$(grep -c '^NETNS_' "$T/outs/cand-caches")" -eq 7


# ---------------------------------------------------------------------------------------------------------------------------------
# Fixture: $F/repo (git repo; app at apps/web-platform), $F/sib (sibling worktree), $F/home, $F/tmp, $F/xdg, $F/cfg, $F/bin.
# ---------------------------------------------------------------------------------------------------------------------------------
mkfix() { # [base dir, default the suite's mktemp dir]
  F="$(mktemp -d "${1:-$T}/row.XXXXXX")"
  assert_fixture_dir "$F"
  A="$F/repo/apps/web-platform"
  mkdir -p "$A/scripts/lib" "$A/test/helpers" "$A/node_modules/.bin" "$F/home" "$F/tmp" "$F/xdg" "$F/cfg" "$F/bin" \
    "$A/node_modules/@anthropic-ai/claude-agent-sdk" "$A/node_modules/@anthropic-ai/claude-agent-sdk-linux-x64"
  cp "$SUT_SRC" "$A/scripts/remeasure-sdk-sandbox-network-cache.sh"
  cp "$CLASSIFIER_SRC" "$A/scripts/lib/sandbox-network-cache-verdict.ts"
  ln -s "$REAL_TSX" "$A/node_modules/.bin/tsx"
  echo '{}' >"$A/tsconfig.json"
  echo '{"name":"fixture-app"}' >"$A/package.json"
  echo '{"lockfileVersion":3}' >"$A/package-lock.json"
  echo "{\"name\":\"@anthropic-ai/claude-agent-sdk\",\"version\":\"$BASE_V\"}" >"$A/node_modules/@anthropic-ai/claude-agent-sdk/package.json"
  printf '#!/bin/sh\necho fixture\n' >"$A/node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude"
  cat >"$A/test/helpers/netns-egress-harness.mts" <<HARN
import { readFileSync, writeFileSync, existsSync, appendFileSync } from "node:fs";
import { join } from "node:path";
const entry = process.env.NETNS_SDK_ENTRY ?? "";
const label = entry.includes("/baseline/") ? "baseline" : entry.includes("/candidate/") ? "candidate" : "none";
writeFileSync("$F/cfg/env-" + label + ".json", JSON.stringify({ keys: Object.keys(process.env).sort(), env: process.env, argv: process.argv.slice(2), cwd: process.cwd() }));
const spec = JSON.parse(readFileSync(process.argv[2], "utf8"));
writeFileSync("$F/cfg/spec-" + label + ".json", JSON.stringify(spec));
process.stderr.write("harness stderr ${SENTINEL}\n");
if (label === "candidate" && existsSync("$F/cfg/tamper-baseline")) appendFileSync(join(spec.scratch, "../../run-baseline/stdout"), "NETNS_TAMPER\\n");
// step0.sdkEntry is what the harness imported: the classifier's sdk-entry precondition realpaths it to the expected entry.
process.stdout.write(readFileSync("$F/cfg/out-" + label, "utf8").replace('"sdkEntry":"x"', '"sdkEntry":' + JSON.stringify(entry)));
if (existsSync("$F/cfg/harness-exit-" + label)) process.exit(Number(readFileSync("$F/cfg/harness-exit-" + label, "utf8")));
HARN
  (cd "$F/repo" && git init -q -b main . && git commit -q --allow-empty -m init && git worktree add -q "$F/sib" -b sib) || { echo "FATAL: fixture git" >&2; exit 2; }
  cp "$T/outs/baseline" "$F/cfg/out-baseline"
  cp "$T/outs/cand-caches" "$F/cfg/out-candidate"
  echo "$CAND_V" >"$F/cfg/cand-version"
  echo "$OLD_TS" >"$F/cfg/sdk-time"
  echo "$OLD_TS" >"$F/cfg/x64-time"
  : >"$F/cfg/refusals"
  : >"$F/cfg/npm.log"
  : >"$F/cfg/mount.log"
  : >"$F/cfg/sock.log"
  : >"$F/cfg/chmod-undo"
  write_stubs
}

write_stubs() {
  local C="$F/cfg"
  # npm: only the hardened environment and the exact view / install / audit argv forms.
  cat >"$F/bin/npm" <<STUB
#!/usr/bin/env bash
C="$C"; A="$A"; BI_SDK="$BASE_INT_SDK"; BI_X64="$BASE_INT_X64"
refuse() { printf 'npm %s | %s\n' "\$*" "\$1" >>"\$C/refusals"; exit 64; }
printf '%s\n' "\$*" >>"\$C/npm.log"
keys="\$(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' | grep -vxE 'PWD|SHLVL|_|OLDPWD' | sort | paste -sd, -)"
[[ "\$keys" == "HOME,PATH,npm_config_cache,npm_config_globalconfig,npm_config_registry,npm_config_userconfig" ]] || refuse "env-keys:\$keys"
[[ "\$npm_config_registry" == "https://registry.npmjs.org/" ]] || refuse "registry"
[[ "\$npm_config_userconfig" == */npm-home/user.npmrc && "\$npm_config_globalconfig" == */npm-home/global.npmrc ]] || refuse "rc-paths"
[[ -f "\$npm_config_userconfig" && ! -s "\$npm_config_userconfig" && -f "\$npm_config_globalconfig" && ! -s "\$npm_config_globalconfig" ]] || refuse "rc-not-empty"
[[ "\$HOME" == */npm-home && "\$npm_config_cache" == */npm-cache ]] || refuse "home-cache"
cand="\$(cat "\$C/cand-version")"
P=@anthropic-ai/claude-agent-sdk; X=@anthropic-ai/claude-agent-sdk-linux-x64
semver='^[0-9]+\.[0-9]+\.[0-9]+\$'
case "\$*" in
  "--version") echo 11.0.0-fixture ;;
  "view \$P@latest version") echo "$LATEST_V" ;;
  "view \$P@"*" version")
    v="\${2#\$P@}"; [[ "\$v" =~ \$semver && \$# -eq 3 ]] || refuse "view-version"; echo "\$v" ;;
  "view \$P@"*" optionalDependencies --json")
    v="\${2#\$P@}"; [[ "\$v" =~ \$semver && \$# -eq 4 ]] || refuse "view-optdeps"; printf '{"%s":"%s"}\n' "\$X" "\$v" ;;
  "view \$P time --json") printf '{"created":"2020-01-01T00:00:00.000Z","modified":"2020-01-01T00:00:00.000Z","$BASE_V":"2020-01-01T00:00:00.000Z","%s":"%s"}\n' "\$cand" "\$(cat "\$C/sdk-time")" ;;
  "view \$X time --json") printf '{"created":"2020-01-01T00:00:00.000Z","modified":"2020-01-01T00:00:00.000Z","$BASE_V":"2020-01-01T00:00:00.000Z","%s":"%s"}\n' "\$cand" "\$(cat "\$C/x64-time")" ;;
  "install --prefix "*" --ignore-scripts --no-audit --no-fund --save-exact --min-release-age=3 \$P@"*)
    [[ \$# -eq 9 ]] || refuse "install-arity"
    d="\$2" v="\${9#\$P@}"; [[ "\$v" =~ \$semver ]] || refuse "install-version"
    # Writes into its cwd, as a real npm without --prefix would: an install run from the app dir mutates the app.
    t="\$PWD"
    mkdir -p "\$t/node_modules/\$P" "\$t/node_modules/\$X"
    printf '{"name":"%s","version":"%s","claudeCodeVersion":"2.1.%s"}\n' "\$P" "\$v" "\${v##*.}" >"\$t/node_modules/\$P/package.json"
    echo "export const query = 1;" >"\$t/node_modules/\$P/sdk.mjs"
    printf '#!/bin/sh\necho %s\n' "\$v" >"\$t/node_modules/\$X/claude"; chmod +x "\$t/node_modules/\$X/claude"
    if [[ "\$v" == "$BASE_V" ]]; then
      is="\$BI_SDK"; ix="\$BI_X64"; [[ -f "\$C/bad-baseline-integrity" ]] && is="sha512-tampered=="
    else is="sha512-candidatesdk=="; ix="sha512-candidatex64=="; fi
    printf '{"packages":{"node_modules/%s":{"integrity":"%s"},"node_modules/%s":{"integrity":"%s"}}}\n' "\$P" "\$is" "\$X" "\$ix" >"\$t/package-lock.json"
    [[ "\$v" != "$BASE_V" && -f "\$C/mutate-lock" ]] && echo " " >>"\$A/package-lock.json"
    [[ "\$v" != "$BASE_V" && -f "\$C/mutate-sdk" ]] && echo "# changed" >>"\$A/node_modules/\$X/claude"
    exit 0 ;;
  "audit signatures --prefix "*)
    [[ \$# -eq 4 && "\$PWD" == "\$4" ]] || refuse "audit-form"
    [[ -f "\$C/audit-fail" ]] && { echo "1 package has an invalid registry signature"; exit 1; }
    echo "audited 2 packages"; exit 0 ;;
  *) refuse "unmodelled" ;;
esac
STUB
  # unshare: the step-2 probe, the outer run namespace (its end undoes every stub chmod, as a namespace's mounts go
  # away with it) and the nested lock namespace (after it, the stub mount refuses everything, as a locked tree does).
  cat >"$F/bin/unshare" <<STUB
#!/usr/bin/env bash
C="$C"
if [[ "\$*" == "-rnm --fork --pid --mount-proc --kill-child true" ]]; then [[ -f "\$C/no-userns" ]] && exit 1; exit 0; fi
if [[ "\${1-} \${2-} \${3-} \${4-} \${5-}" == "-rnm --fork --pid --mount-proc --kill-child" ]]; then
  shift 5; "\$@"; rc=\$?
  while IFS= read -r p; do chmod u+w "\$p" 2>/dev/null; done <"\$C/chmod-undo"
  : >"\$C/chmod-undo"; rm -f "\$C/locked"
  exit "\$rc"
fi
if [[ "\${1-} \${2-} \${3-} \${4-}" == "-U -r -n -m" ]]; then : >"\$C/locked"; shift 4; exec "\$@"; fi
printf 'unshare %s\n' "\$*" >>"\$C/refusals"; exit 64
STUB
  cat >"$F/bin/timeout" <<STUB
#!/usr/bin/env bash
C="$C"
[[ "\$1 \$2 \$3" == "-k 10 600" ]] || { printf 'timeout %s\n' "\$*" >>"\$C/refusals"; exit 64; }
shift 3
if [[ -f "\$C/timeout-124" ]]; then "\$@"; exit 124; fi
exec "\$@"
STUB
  cat >"$F/bin/uname" <<STUB
#!/usr/bin/env bash
case "\$*" in
  -s) echo Linux ;;
  -m) cat "$C/arch" 2>/dev/null || echo x86_64 ;;
  -r) echo 6.0.0-fixture ;;
  *) printf 'uname %s\n' "\$*" >>"$C/refusals"; exit 64 ;;
esac
STUB
  cat >"$F/bin/getconf" <<STUB
#!/usr/bin/env bash
[[ "\$*" == GNU_LIBC_VERSION ]] || { printf 'getconf %s\n' "\$*" >>"$C/refusals"; exit 64; }
echo "glibc 2.40"
STUB
  cat >"$F/bin/df" <<STUB
#!/usr/bin/env bash
[[ "\$1" == -Pk && \$# -eq 2 ]] || { printf 'df %s\n' "\$*" >>"$C/refusals"; exit 64; }
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "fixturefs 99999999 1 \$(cat "$C/free-kb" 2>/dev/null || echo 99999999) 1% /"
STUB
  # mount: a read-only tmpfs over a fixture path, and ro=recursive / over the fixture's protected paths and scratch
  # dirs, are modelled as chmod a-w (a path listed in cfg/mount-skip is left writable); a read-write rebind is chmod
  # u+w; the system mounts (/proc, /run, /var/run, /tmp, /dev/shm) are no-ops. Locked: only the probe's bind of the
  # common dir succeeds, and its read-write remount succeeds only with cfg/permit-remount.
  cat >"$F/bin/mount" <<STUB
#!/usr/bin/env bash
C="$C"; F="$F"
printf '%s\n' "\$*" >>"\$C/mount.log"
# A scratch path is named in mount-skip relative to the run's scratch root: "scratch", "scratch/run-baseline", ...; a
# "during-candidate:" prefix applies it only once the candidate run dir exists (the candidate run).
skip() {
  grep -qxF -- "\$1" "\$C/mount-skip" 2>/dev/null && return 0
  [[ "\$1" == "\$TMPDIR"/remeasure-sdk.* ]] || return 1
  local b="\${1#"\$TMPDIR"/remeasure-sdk.}" rel=""
  [[ "\$b" == */* ]] && rel="/\${b#*/}"
  grep -qxF -- "scratch\$rel" "\$C/mount-skip" 2>/dev/null && return 0
  compgen -G "\$TMPDIR/remeasure-sdk.*/run-candidate" >/dev/null && grep -qxF -- "during-candidate:scratch\$rel" "\$C/mount-skip" 2>/dev/null
}
ro() { skip "\$1" && return 0; chmod a-w "\$1" && printf '%s\n' "\$1" >>"\$C/chmod-undo"; }
refuse() { printf 'mount %s\n' "\$*" >>"\$C/refusals"; exit 64; }
if [[ -f "\$C/locked" ]]; then
  [[ "\$*" == "-o remount,bind,rw /" ]] && exit 32
  [[ \$# -eq 3 && "\$1" == --bind && "\$2" == "\$3" && "\$2" == "\$F/repo/.git" ]] && exit 0
  [[ \$# -eq 3 && "\$1" == -o && "\$2" == remount,bind,rw && "\$3" == "\$F/repo/.git" ]] || refuse "\$@"
  [[ -f "\$C/permit-remount" ]] && exit 0
  exit 32
fi
case "\$*" in
  "-t tmpfs -o ro,size=64k,mode=0555 remeasure-home "*|"-t tmpfs -o ro,size=64k,mode=0555 remeasure-xdg "*)
    [[ \$# -eq 6 ]] || refuse "\$@"; ro "\$6"; exit 0 ;;
  "-o remount,bind,ro=recursive /")
    for p in "\$F/repo" "\$F/repo/.git" "\$F/sib"; do ro "\$p"; done
    while IFS= read -r -d '' p; do ro "\$p"; done < <(find "\$TMPDIR"/remeasure-sdk.* -type d -print0 2>/dev/null)
    exit 0 ;;
  "-o remount,bind,rw /proc"|"-t tmpfs -o rw,nosuid,nodev,size=1m,mode=0755 remeasure-run /run"|"-o remount,bind,ro /run"|\
  "-t tmpfs -o ro,size=64k,mode=0555 remeasure-varrun /var/run"|\
  "-t tmpfs -o rw,nosuid,nodev,mode=1777 remeasure-tmp /tmp"|"-t tmpfs -o rw,nosuid,nodev,mode=1777 remeasure-shm /dev/shm")
    exit 0 ;;
esac
if [[ \$# -eq 3 && "\$1" == --bind && "\$2" == "\$3" && "\$2" == "\$TMPDIR"/remeasure-sdk.*/run-*/* ]]; then exit 0; fi
if [[ \$# -eq 3 && "\$1" == -o && "\$2" == remount,bind,rw && "\$3" == "\$TMPDIR"/remeasure-sdk.*/run-*/* ]]; then
  skip "\$3" || chmod u+w "\$3"; exit 0
fi
refuse "\$@"
STUB
  # umount: the probe's two attempts, refused as a locked mount refuses them.
  cat >"$F/bin/umount" <<STUB
#!/usr/bin/env bash
C="$C"
[[ -f "\$C/locked" && \$# -eq 1 && ( "\$1" == /run || "\$1" == /proc ) ]] || { printf 'umount %s\n' "\$*" >>"\$C/refusals"; exit 64; }
exit 32
STUB
  # node: every call goes to the real node except the probe's socket connect, answered from cfg/connectable.
  cat >"$F/bin/node" <<STUB
#!/usr/bin/env bash
C="$C"
if [[ "\${1-}" == -e && "\${2-}" == *remeasure-socket-probe* ]]; then
  [[ \$# -eq 3 ]] || { printf 'node socket-probe %s\n' "\$3" >>"\$C/refusals"; exit 64; }
  printf '%s\n' "\$3" >>"\$C/sock.log"
  grep -qxF -- "\$3" "\$C/connectable" 2>/dev/null && exit 0
  exit 1
fi
exec "$REAL_NODE" "\$@"
STUB
  chmod +x "$F/bin/"*
}

# run_row <name> [script args...]: runs the fixture copy under a clean env from ${ROW_CWD:-$F}; sets RC; asserts the per-row
# invariants. ROW_NO_XDG=1 leaves XDG_RUNTIME_DIR unset.
run_row() {
  ROW="$1"; shift
  local sut="$A/scripts/remeasure-sdk-sandbox-network-cache.sh"
  case "$sut" in "$T"/*|"${RK_BASE:-$T}"/*) : ;; *) bad "$ROW: the script under test is not under the suite's mktemp dirs ($sut)"; return ;; esac
  local xdg=(XDG_RUNTIME_DIR="$F/xdg"); [[ -n "${ROW_NO_XDG:-}" ]] && xdg=()
  (cd "${ROW_CWD:-$F}" && env -i PATH="$F/bin:/usr/bin:/bin" HOME="$F/home" TMPDIR="${ROW_TMPDIR:-$F/tmp}" "${xdg[@]}" \
    USER=zzfixtureuser LANG=C.UTF-8 bash "$sut" "$@") >"$F/out" 2>"$F/err"
  RC=$?
  local last; last="$(tail -n1 "$F/out")"
  check "$ROW: last stdout line is the REMEASURE line" grep -qE '^REMEASURE verdict=\S+ exit=[0-9] reason=\S+ next=' <<<"$last"
  eq "$ROW: REMEASURE exit= matches the process exit" "$RC" "$(sed -n 's/^REMEASURE verdict=[^ ]* exit=\([0-9]\) .*/\1/p' <<<"$last")"
  eq "$ROW: no stub refused an argv" "" "$(cat "$F/cfg/refusals")"
  if [[ -n "${EXPECT_KEPT:-}" ]]; then
    check "$ROW: --keep-scratch keeps the scratch dir" test -n "$(scratch_left "${ROW_TMPDIR:-$F/tmp}")"
  elif [[ -z "${ROW_TMPDIR:-}" ]]; then
    eq "$ROW: the scratch dir is gone" "" "$(scratch_left "$F/tmp")"
  fi
  check "$ROW: no output carries the stub sentinel" bash -c '! grep -q "$0" "$1" "$2"' "$SENTINEL" "$F/out" "$F/err"
}
# The script's scratch roots only (tsx keeps its own compile cache in TMPDIR, which is not the script's).
scratch_left() { find "$1" -maxdepth 1 -name 'remeasure-sdk.*' 2>/dev/null; }
reason() { sed -n 's/^REMEASURE .* reason=\([^ ]*\) next=.*/\1/p' <<<"$(tail -n1 "$F/out")"; }
verdict() { sed -n 's/^REMEASURE verdict=\([^ ]*\) .*/\1/p' <<<"$(tail -n1 "$F/out")"; }
no_unverified() { ! grep -q 'UNVERIFIED:' "$F/out"; }
no_install() { ! grep -q '^install ' "$F/cfg/npm.log"; }
no_harness() { [[ ! -e "$F/cfg/env-baseline.json" && ! -e "$F/cfg/env-candidate.json" ]]; }
app_untouched_lock() { [[ "$(cat "$A/package-lock.json")" == '{"lockfileVersion":3}' ]]; }

# ---------------------------------------------------------------------------------------------------------------------------------
echo "--- CACHES: the full path, wiring and environment"
mkfix
run_row caches "$CAND_V" --out "$F/verdict.json" --markdown "$F/md"
eq "caches: exit 0" 0 "$RC"
eq "caches: verdict CACHES" CACHES "$(verdict)"
eq "caches: reason measured" measured "$(reason)"
# TSX_TSCONFIG_PATH is set by tsx itself from --tsconfig (it is in the harness's env, not the script's construction).
eq "caches: harness env keys are exactly the constructed set" "HOME,LANG,NETNS_SDK_ENTRY,NODE_ENV,PATH" \
  "$(node -e 'const k=require(process.argv[1]).keys.filter(x=>!["PWD","SHLVL","_","OLDPWD","TSX_TSCONFIG_PATH"].includes(x));process.stdout.write(k.join(","))' "$F/cfg/env-baseline.json")"
BE="$(node -p 'require(process.argv[1]).env.NETNS_SDK_ENTRY' "$F/cfg/env-baseline.json")"
CE="$(node -p 'require(process.argv[1]).env.NETNS_SDK_ENTRY' "$F/cfg/env-candidate.json")"
check "caches: baseline NETNS_SDK_ENTRY points into the baseline prefix" grep -qE '/remeasure-sdk\.[^/]+/baseline/node_modules/@anthropic-ai/claude-agent-sdk/sdk\.mjs$' <<<"$BE"
check "caches: candidate NETNS_SDK_ENTRY points into the candidate prefix" grep -qE '/remeasure-sdk\.[^/]+/candidate/node_modules/@anthropic-ai/claude-agent-sdk/sdk\.mjs$' <<<"$CE"
eq "caches: the harness HOME is a per-run scratch dir, not the operator HOME" "1" \
  "$(node -p 'const h=require(process.argv[1]).env.HOME; Number(h.endsWith("/run-baseline/home") && !h.startsWith(process.argv[2]))' "$F/cfg/env-baseline.json" "$F/home")"
eq "caches: the harness runs with cwd the app root" "$A" "$(node -p 'require(process.argv[1]).cwd' "$F/cfg/env-candidate.json")"
eq "caches: spec arms and tap" 'allow-all|control,B,D,E,F,F2' "$(node -p 'const s=require(process.argv[1]); s.tap+"|"+s.arms.join(",")' "$F/cfg/spec-candidate.json")"
eq "caches: install argv for both prefixes carries the floor flag and --ignore-scripts" 2 "$(grep -c -- '--ignore-scripts --no-audit --no-fund --save-exact --min-release-age=3 @anthropic-ai/claude-agent-sdk@' "$F/cfg/npm.log")"
eq "caches: npm audit signatures ran once per prefix" 2 "$(grep -c '^audit signatures --prefix ' "$F/cfg/npm.log")"
ml() { grep -cxF -- "$1" "$F/cfg/mount.log"; }
eq "caches: the whole tree was remounted read-only once per run" 2 "$(ml "-o remount,bind,ro=recursive /")"
eq "caches: /proc was made read-write once per run (the nested unshare -r writes uid_map)" 2 "$(ml "-o remount,bind,rw /proc")"
eq "caches: a tmpfs went over /run, then read-only, once per run" "2 2" \
  "$(ml "-t tmpfs -o rw,nosuid,nodev,size=1m,mode=0755 remeasure-run /run") $(ml "-o remount,bind,ro /run")"
eq "caches: private tmpfs over /tmp and /dev/shm once per run" "2 2" \
  "$(ml "-t tmpfs -o rw,nosuid,nodev,mode=1777 remeasure-tmp /tmp") $(ml "-t tmpfs -o rw,nosuid,nodev,mode=1777 remeasure-shm /dev/shm")"
eq "caches: exactly two dirs per run bound back read-write (home, scratch)" "2 4" \
  "$(grep -cE -- '^-o remount,bind,rw .*/run-baseline/(home|scratch)$' "$F/cfg/mount.log") $(grep -c -- '^-o remount,bind,rw .*/run-' "$F/cfg/mount.log")"
check "caches: the mount order is masks, ro=recursive, /run, /tmp, binds (first run)" bash -c '
  n() { grep -nxF -- "$1" "$0" | head -n1 | cut -d: -f1; }
  b="$(grep -nE -- "^--bind .*/run-baseline/home " "$0" | head -n1 | cut -d: -f1)"
  h="$(grep -nE -- "^-t tmpfs -o ro,size=64k,mode=0555 remeasure-home " "$0" | head -n1 | cut -d: -f1)"
  [[ -n "$b" && -n "$h" ]] && (( h < $(n "-o remount,bind,ro=recursive /") && $(n "-o remount,bind,ro=recursive /") < $(n "-o remount,bind,ro /run") && $(n "-o remount,bind,ro /run") < $(n "-t tmpfs -o rw,nosuid,nodev,mode=1777 remeasure-tmp /tmp") && $(n "-t tmpfs -o rw,nosuid,nodev,mode=1777 remeasure-tmp /tmp") < b ))' "$F/cfg/mount.log"
eq "caches: the post-lock probe tried the read-write remount of the git common dir once per run" 2 "$(ml "-o remount,bind,rw $F/repo/.git")"
eq "caches: the probe tried docker.sock, /var/run/docker.sock and the session bus once per run" \
  "/run/docker.sock /var/run/docker.sock /run/user/$(id -u)/bus /run/docker.sock /var/run/docker.sock /run/user/$(id -u)/bus" \
  "$(paste -sd' ' "$F/cfg/sock.log")"
check "caches: HOME and XDG_RUNTIME_DIR were masked with a read-only tmpfs" bash -c \
  'grep -qxF -- "-t tmpfs -o ro,size=64k,mode=0555 remeasure-home $1" "$3" && grep -qxF -- "-t tmpfs -o ro,size=64k,mode=0555 remeasure-xdg $2" "$3"' _ "$F/home" "$F/xdg" "$F/cfg/mount.log"
check "caches: --out JSON written" test -s "$F/verdict.json"
eq "caches: JSON requested" "$CAND_V" "$(node -p 'require(process.argv[1]).requested' "$F/verdict.json")"
eq "caches: JSON env carries the candidate integrity" "sha512-candidatesdk==" "$(node -p 'require(process.argv[1]).env.candidateIntegritySdk' "$F/verdict.json")"
check "caches: JSON paths are redacted to <scratch>" bash -c '! grep -q "$0" "$1"' "$F/tmp/remeasure-sdk" "$F/verdict.json"
check "caches: both markdown drafts written with the command" bash -c 'grep -q "remeasure-sdk-sandbox-network-cache.sh $0" "$1/addendum.md" && grep -qF "| \`F2\` |" "$1/issue-comment.md"' "$CAND_V" "$F/md"
check "caches: no draft carries the sentinel" bash -c '! grep -q "$0" "$1/addendum.md" "$1/issue-comment.md"' "$SENTINEL" "$F/md"
check "caches: app package-lock untouched" app_untouched_lock
check "caches: no UNVERIFIED token" no_unverified
check "caches: addendum.md and issue-comment.md are the same draft" cmp -s "$F/md/addendum.md" "$F/md/issue-comment.md"
eq "caches: JSON env keys (nodeVersion, npmVersion, numeric kernel, os-release ID)" "nodeVersion,npmVersion,kernel=6.0.0,os=$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')" \
  "$(node -p 'const e=require(process.argv[1]).env; ["nodeVersion","npmVersion"].filter(k=>e[k]).join(",")+",kernel="+e.kernel+",os="+e.os' "$F/verdict.json")"
check "caches: the host rows render as code spans" grep -qF -- '- kernel: `6.0.0`' "$F/md/addendum.md"

echo "--- classifier wiring: exit 2 and exit 4 pass through with the classifier's reason"
mkfix; cp "$T/outs/cand-inconclusive" "$F/cfg/out-candidate"
run_row inconclusive "$CAND_V"
eq "inconclusive: exit 2 (must-PASS: app untouched, so not 1)" 2 "$RC"
eq "inconclusive: reason from the classifier" "candidate-reading:incoherent-f-f2" "$(reason)"
mkfix; cp "$T/outs/cand-leak" "$F/cfg/out-candidate"
run_row leak "$CAND_V"
eq "leak: exit 4" 4 "$RC"
eq "leak: verdict LEAK" LEAK "$(verdict)"
eq "leak: reason" "candidate:B:decoy" "$(reason)"

echo "--- dist-tag resolution"
mkfix; echo "$LATEST_V" >"$F/cfg/cand-version"; cp "$T/outs/latest-caches" "$F/cfg/out-candidate"
run_row dist-tag latest --out "$F/verdict.json"
eq "dist-tag: exit 0" 0 "$RC"
eq "dist-tag: requested is the tag" latest "$(node -p 'require(process.argv[1]).requested' "$F/verdict.json")"
eq "dist-tag: the exact version reached the JSON" "$LATEST_V" "$(node -p 'require(process.argv[1]).env.exactVersion' "$F/verdict.json")"
check "dist-tag: the candidate installed the exact version, not the tag" grep -q "@anthropic-ai/claude-agent-sdk@$LATEST_V\$" "$F/cfg/npm.log"

echo "--- release-age floor"
mkfix; iso_ago $((2 * 86400)) >"$F/cfg/sdk-time"
run_row floor-sdk "$CAND_V"
eq "floor-sdk: exit 3" 3 "$RC"; eq "floor-sdk: reason" release-age-floor "$(reason)"; eq "floor-sdk: verdict REFUSED" REFUSED "$(verdict)"
check "floor-sdk: no UNVERIFIED token" no_unverified
check "floor-sdk: no install argv (created/modified are old; only time[exact] counts)" no_install
mkfix; iso_ago $((2 * 86400)) >"$F/cfg/x64-time"
run_row floor-x64 "$CAND_V"
eq "floor-x64: exit 3 release-age-floor" "3 release-age-floor" "$RC $(reason)"
check "floor-x64: no install argv" no_install
mkfix; iso_ago $((3 * 86400 - 60)) >"$F/cfg/sdk-time"
run_row floor-minute-under "$CAND_V"
eq "floor-minute-under: refused" "3 release-age-floor" "$RC $(reason)"
mkfix; iso_ago $((3 * 86400)) >"$F/cfg/sdk-time"
run_row floor-exact "$CAND_V"
eq "floor-exact: a package exactly 3 days old is allowed" 0 "$RC"

echo "--- REFUSED: signatures and baseline integrity"
mkfix; : >"$F/cfg/audit-fail"
run_row audit "$CAND_V"
eq "audit: exit 3 signature-verification-failed" "3 signature-verification-failed" "$RC $(reason)"
eq "audit: verdict REFUSED" REFUSED "$(verdict)"
check "audit: no UNVERIFIED token" no_unverified
check "audit: no harness run" no_harness
mkfix; : >"$F/cfg/bad-baseline-integrity"
run_row integrity "$CAND_V"
eq "integrity: exit 3 baseline-integrity-mismatch" "3 baseline-integrity-mismatch" "$RC $(reason)"
eq "integrity: no candidate install" 0 "$(grep -c "@anthropic-ai/claude-agent-sdk@$CAND_V\$" "$F/cfg/npm.log")"
check "integrity: no harness run" no_harness

echo "--- UNVERIFIED: host limits"
mkfix; : >"$F/cfg/no-userns"
run_row no-userns "$CAND_V"
eq "no-userns: exit 3 no-userns" "3 no-userns" "$RC $(reason)"
check "no-userns: prints the UNVERIFIED token" grep -qx "UNVERIFIED:sdk-$CAND_V-sandbox-network-allow-cache" "$F/out"
mkfix; echo aarch64 >"$F/cfg/arch"
run_row arch "$CAND_V"
eq "arch: exit 3 unsupported-arch" "3 unsupported-arch" "$RC $(reason)"

echo "--- containment"
mkfix; echo "$F/home" >"$F/cfg/mount-skip"
run_row contain-home "$CAND_V"
eq "contain-home: a writable HOME is exit 3 containment-unavailable" "3 containment-unavailable" "$RC $(reason)"
check "contain-home: no harness started" no_harness
mkfix; echo "$F/repo/.git" >"$F/cfg/mount-skip"
run_row contain-common "$CAND_V"
eq "contain-common: a writable git common dir is exit 3 containment-unavailable" "3 containment-unavailable" "$RC $(reason)"
check "contain-common: no harness started" no_harness
mkfix; echo "$F/sib" >"$F/cfg/mount-skip"
run_row contain-sibling "$CAND_V"
eq "contain-sibling (AC8b): a writable sibling worktree is exit 3 containment-unavailable" "3 containment-unavailable" "$RC $(reason)"
check "contain-sibling: no harness started" no_harness
mkfix; : >"$F/cfg/permit-remount"
run_row contain-remount "$CAND_V"
eq "contain-remount: a post-lock read-write remount that succeeds is exit 3 containment-unavailable" "3 containment-unavailable" "$RC $(reason)"
check "contain-remount: the marker line reached stderr" grep -q 'remeasure-containment: the git common dir can be remounted read-write' "$F/err"
check "contain-remount: no harness started" no_harness
mkfix; echo scratch >"$F/cfg/mount-skip"
run_row contain-scratch-root "$CAND_V"
eq "contain-scratch-root: a writable scratch root is exit 3 containment-unavailable" "3 containment-unavailable" "$RC $(reason)"
check "contain-scratch-root: the probe named it" grep -q 'remeasure-containment: the scratch root is writable' "$F/err"
mkfix; echo during-candidate:scratch/run-baseline >"$F/cfg/mount-skip"
run_row contain-run-baseline "$CAND_V"
eq "contain-run-baseline: a baseline run dir writable during the candidate run is exit 3 containment-unavailable" "3 containment-unavailable" "$RC $(reason)"
check "contain-run-baseline: caught by the candidate probe" grep -q 'remeasure-containment: the baseline run dir is writable' "$F/err"
check "contain-run-baseline: the baseline run itself ran (its own run dir was locked)" test -e "$F/cfg/env-baseline.json"
mkfix; echo scratch/run-candidate >"$F/cfg/mount-skip"
run_row contain-run-dir "$CAND_V"
eq "contain-run-dir: a writable run dir (stdout, spec.json) is exit 3 containment-unavailable" "3 containment-unavailable" "$RC $(reason)"
check "contain-run-dir: the probe named it" grep -q 'remeasure-containment: the run dir (stdout, stderr, spec.json) is writable' "$F/err"
mkfix
ROW_NO_XDG=1 run_row contain-no-xdg "$CAND_V"
eq "contain-no-xdg: exit 0" 0 "$RC"
check "contain-no-xdg: XDG_RUNTIME_DIR unset still issues the /run mask" grep -qxF -- "-t tmpfs -o rw,nosuid,nodev,size=1m,mode=0755 remeasure-run /run" "$F/cfg/mount.log"
check "contain-no-xdg: no XDG mask was issued" bash -c '! grep -q remeasure-xdg "$0"' "$F/cfg/mount.log"
mkfix; echo /run/docker.sock >"$F/cfg/connectable"
run_row contain-docker "$CAND_V"
eq "contain-docker: a connectable docker.sock is exit 3 containment-unavailable" "3 containment-unavailable" "$RC $(reason)"
check "contain-docker: no harness started" no_harness
mkfix; echo "/run/user/$(id -u)/bus" >"$F/cfg/connectable"
run_row contain-bus "$CAND_V"
eq "contain-bus: a connectable session bus is exit 3 containment-unavailable" "3 containment-unavailable" "$RC $(reason)"
mkfix; : >"$F/cfg/tamper-baseline"
run_row contain-breach "$CAND_V"
eq "contain-breach: the baseline stdout changed between runs is exit 3 containment-breached" "3 containment-breached" "$RC $(reason)"
eq "contain-breach: verdict UNVERIFIED" UNVERIFIED "$(verdict)"
mkfix; echo 83 >"$F/cfg/harness-exit-candidate"
run_row exit83-no-marker "$CAND_V"
eq "exit83-no-marker: a harness exit 83 without the marker is harness-crash" "1 harness-crash" "$RC $(reason)"
mkfix; (cd "$F/repo" && git worktree add -q "$F/locked" -b locked && git worktree lock "$F/locked") && rm -rf "$F/locked"
run_row wt-locked-missing "$CAND_V"
eq "wt-locked-missing: a listed worktree that is not a dir and not prunable is exit 3 containment-unavailable" "3 containment-unavailable" "$RC $(reason)"
check "wt-locked-missing: no npm call" test ! -s "$F/cfg/npm.log"
mkfix; (cd "$F/repo" && git worktree add -q "$F/gone" -b gone) && rm -rf "$F/gone"
run_row wt-prunable "$CAND_V"
eq "wt-prunable: a prunable missing worktree is skipped, the run proceeds" 0 "$RC"
mkfix; mkdir -p "$F/home/tmp"
ROW_TMPDIR="$F/home/tmp" run_row scratch-in-home "$CAND_V"
eq "scratch-in-home: exit 3 scratch-inside-protected-path" "3 scratch-inside-protected-path" "$RC $(reason)"
eq "scratch-in-home: the scratch dir is gone" "" "$(scratch_left "$F/home/tmp")"
check "scratch-in-home: no npm call" test ! -s "$F/cfg/npm.log"

echo "--- ERROR paths"
mkfix; rm "$A/node_modules/.bin/tsx"
run_row no-tsx "$CAND_V"
eq "no-tsx: exit 1 setup-missing" "1 setup-missing" "$RC $(reason)"
check "no-tsx: no UNVERIFIED token" no_unverified
mkfix; rm -rf "$A"/node_modules/@anthropic-ai/claude-agent-sdk*
run_row empty-glob "$CAND_V"
eq "empty-glob: the app hash can never pass over zero files (setup-missing)" "1 setup-missing" "$RC $(reason)"
for arg in "npm:@evil/sdk@1.0.0" "file:../sdk" "https://example.invalid/sdk.tgz" "git+ssh://example.invalid/x"; do
  mkfix
  run_row "bad-arg $arg" "$arg"
  eq "bad-arg $arg: exit 1 bad-version-arg" "1 bad-version-arg" "$RC $(reason)"
  check "bad-arg $arg: no npm call" test ! -s "$F/cfg/npm.log"
done
mkfix; echo 1000 >"$F/cfg/free-kb"
run_row low-disk "$CAND_V"
eq "low-disk: exit 1 low-disk" "1 low-disk" "$RC $(reason)"
check "low-disk: no install" no_install
mkfix; : >"$F/cfg/sdk-time"
run_row no-publish-time "$CAND_V"
eq "no-publish-time: an empty time[exact] is exit 1 install-failed, not release-age-floor" "1 install-failed" "$RC $(reason)"
check "no-publish-time: names the package" grep -q "next=no publish time for @anthropic-ai/claude-agent-sdk@$CAND_V" "$F/out"
mkfix; : >"$F/cfg/timeout-124"
run_row timeout "$CAND_V"
eq "timeout: exit 1 harness-crash" "1 harness-crash" "$RC $(reason)"
check "timeout: the stderr tail was printed, redacted" grep -q 'harness stderr <redacted>' "$F/err"
mkfix; echo 1 >"$F/cfg/harness-exit-candidate"
run_row harness-nonzero "$CAND_V"
eq "harness-nonzero: exit 1 harness-crash" "1 harness-crash" "$RC $(reason)"

echo "--- app-mutated (Guard 2)"
mkfix; : >"$F/cfg/mutate-lock"
run_row mutate-lock "$CAND_V"
eq "mutate-lock: a touched package-lock.json is exit 1 app-mutated" "1 app-mutated" "$RC $(reason)"
mkfix; : >"$F/cfg/mutate-sdk"
run_row mutate-sdk "$CAND_V"
eq "mutate-sdk: a touched file under the installed linux-x64 package is exit 1 app-mutated" "1 app-mutated" "$RC $(reason)"

echo "--- output files (--out / --markdown)"
mkfix; : >"$F/cfg/mutate-lock"
run_row mutate-out "$CAND_V" --out "$F/verdict.json" --markdown "$F/md"
eq "mutate-out: app-mutated" "1 app-mutated" "$RC $(reason)"
check "mutate-out: app-mutated leaves no verdict.json and no drafts" test ! -e "$F/verdict.json" -a ! -e "$F/md/addendum.md" -a ! -e "$F/md/issue-comment.md"
mkfix; mkdir -p "$F/cwd"
ROW_CWD="$F/cwd" run_row relative-out "$CAND_V" --out rel-verdict.json --markdown rel-md
eq "relative-out: exit 0" 0 "$RC"
check "relative-out: a relative --out lands at the caller's cwd" test -s "$F/cwd/rel-verdict.json" -a -s "$F/cwd/rel-md/addendum.md"
check "relative-out: and not in apps/web-platform" test ! -e "$A/rel-verdict.json" -a ! -e "$A/rel-md"
mkfix; echo stale >"$F/verdict.json"; mkdir -p "$F/md"; echo stale >"$F/md/addendum.md"; echo stale >"$F/md/issue-comment.md"; : >"$F/cfg/no-userns"
run_row stale-out "$CAND_V" --out "$F/verdict.json" --markdown "$F/md"
eq "stale-out: an early exit" "3 no-userns" "$RC $(reason)"
check "stale-out: the stale --out and drafts from before were removed" test ! -e "$F/verdict.json" -a ! -e "$F/md/addendum.md" -a ! -e "$F/md/issue-comment.md"

echo "--- --help"
mkfix
(cd "$F" && env -i PATH="$F/bin:/usr/bin:/bin" HOME="$F/home" LANG=C.UTF-8 bash "$A/scripts/remeasure-sdk-sandbox-network-cache.sh" --help) >"$F/out" 2>"$F/err"
eq "help: exit 0" 0 "$?"
check "help: no REMEASURE line" bash -c '! grep -q "^REMEASURE " "$0"' "$F/out"
check "help: prints the Exit codes block" grep -q '^Exit codes' "$F/out"
check "help: prints the classifier table (CACHES and its NEXT text)" grep -qP '^  CACHES\t#12906 stays blocked; re-run on the next SDK bump$' "$F/out"
eq "help: every classifier verdict plus REFUSED, in precedence order" "ERROR LEAK UNVERIFIED INCONCLUSIVE CACHES RE-ASKS-AFTER-TEARDOWN MIXED REFUSED" \
  "$(grep -P '^  [A-Z-]+\t' "$F/out" | cut -f1 | tr -d ' ' | paste -sd' ')"
check "help: the script header carries no hand-copied verdict-to-action table" bash -c '! grep -q "stays blocked" "$0"' "$SUT_SRC"

echo "--- stub hygiene: a refusal reaches the refusals file"
mkfix
"$F/bin/uname" -v >/dev/null 2>&1; urc=$?
"$F/bin/mount" -o remount,rw / >/dev/null 2>&1; mrc=$?
eq "hygiene: an unmodelled argv exits 64 (uname, mount)" "64 64" "$urc $mrc"
eq "hygiene: both refusals were logged" 2 "$(wc -l <"$F/cfg/refusals" | tr -d ' ')"

echo "--- --keep-scratch"
mkfix
EXPECT_KEPT=1 run_row keep "$CAND_V" --keep-scratch
eq "keep: exit 0" 0 "$RC"
check "keep: warns that the kept dir is unredacted" grep -q 'holds unredacted harness transcripts' "$F/err"

echo "--- real kernel: the real INNER and PROBE, a fake harness that attacks the locked tree"
if ! unshare -rnm true >/dev/null 2>&1; then
  echo "  SKIP: real-kernel containment row (unshare -rnm true fails on this host; no pass recorded)"
else
  # The fixture (app, git common dir, sibling, HOME, XDG) lives under /var/tmp, so the private /tmp does not simply hide
  # it: the masks and the read-only tree are what must stop each attack. The scratch root stays under /tmp, so the
  # fd-held restore of the scratch root after the private /tmp is exercised.
  RK_RAN=1
  RK_BASE="$(mktemp -d /var/tmp/soleur-remeasure-rk.XXXXXXXX)"; RK_BASE="$(cd "$RK_BASE" && pwd -P)"
  assert_fixture_dir "$RK_BASE"
  mkfix "$RK_BASE"
  RK_TMP="$T/rk-tmp"; mkdir -p "$RK_TMP"
  # Real unshare, mount, umount, setsid and node; npm, uname, getconf, df and timeout stay stubs (no network).
  rm -f "$F/bin/unshare" "$F/bin/mount" "$F/bin/umount" "$F/bin/node"
  # A live socket under the operator-side XDG dir: it exists on the host, so only the masks can make it unreachable.
  LIVE_SOCK="$F/xdg/live.sock"
  "$REAL_NODE" -e 'require("net").createServer(c=>c.end()).listen(process.argv[1])' "$LIVE_SOCK" & live_pid=$!
  for _ in $(seq 50); do [[ -S "$LIVE_SOCK" ]] && break; sleep 0.1; done
  check "real-kernel: the live control socket listens before the run" test -S "$LIVE_SOCK"
  cat >"$A/test/helpers/netns-egress-harness.mts" <<HARN
import { readFileSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { connect } from "node:net";
import { join, dirname } from "node:path";
const spec = JSON.parse(readFileSync(process.argv[2], "utf8"));
const entry = process.env.NETNS_SDK_ENTRY ?? "";
const label = entry.includes("/baseline/") ? "baseline" : "candidate";
const runDir = dirname(spec.scratch);
const scratchRoot = dirname(runDir);
const report: Record<string, string> = {};
const refused = (name: string, ok: boolean) => { report[name] = ok ? "refused" : "BREACH"; };
const allowed = (name: string, ok: boolean) => { report[name] = ok ? "allowed" : "BROKEN"; };
const sh = (cmd: string, args: string[]) => spawnSync(cmd, args, { stdio: "ignore" }).status === 0;
const write = (dir: string) => { try { writeFileSync(join(dir, ".attack"), "x"); return true; } catch { return false; } };
const conn = (p: string) => new Promise<boolean>((res) => { const s = connect(p); s.on("connect", () => { s.destroy(); res(true); }); s.on("error", () => res(false)); setTimeout(() => res(true), 3000); });
sh("mount", ["--bind", "$F/repo/.git", "$F/repo/.git"]);
refused("remount-common-rw", !sh("mount", ["-o", "remount,bind,rw", "$F/repo/.git"]));
refused("remount-root-rw", !sh("mount", ["-o", "remount,bind,rw", "/"]));
refused("umount-run", !sh("umount", ["/run"]));
refused("umount-proc", !sh("umount", ["/proc"]));
for (const [n, d] of [["write-app", "$A"], ["write-common", "$F/repo/.git"], ["write-sibling", "$F/sib"], ["write-operator-home", "$F/home"],
  ["write-scratch-root", scratchRoot], ["write-run-dir", runDir], ["write-run-baseline", join(scratchRoot, "run-baseline")], ["write-run", "/run"]] as const) {
  if (n === "write-run-baseline" && label === "baseline") continue;
  refused(n, !write(d));
}
for (const p of ["/run/docker.sock", "/var/run/docker.sock", "/run/user/$(id -u)/bus", "$LIVE_SOCK"]) refused("connect " + p, !(await conn(p)));
allowed("write-run-home", write(process.env.HOME ?? "/nonexistent"));
allowed("write-run-scratch", write(spec.scratch));
allowed("write-private-tmp", write("/tmp"));
writeFileSync(join(spec.scratch, "hosts"), "127.0.0.1 localhost\n");
allowed("bind-etc-hosts", sh("mount", ["--bind", join(spec.scratch, "hosts"), "/etc/hosts"]));
allowed("bind-etc-resolv", sh("mount", ["--bind", join(spec.scratch, "hosts"), "/etc/resolv.conf"]));
writeFileSync(join(spec.scratch, "report.json"), JSON.stringify(report));
if (Object.values(report).some((v) => v === "BREACH" || v === "BROKEN")) { process.stderr.write(JSON.stringify(report) + "\n"); process.exit(1); }
process.stdout.write(readFileSync("$F/cfg/out-" + label, "utf8").replace('"sdkEntry":"x"', '"sdkEntry":' + JSON.stringify(entry)));
HARN
  EXPECT_KEPT=1 ROW_TMPDIR="$RK_TMP" run_row real-kernel "$CAND_V" --keep-scratch
  kill "$live_pid" 2>/dev/null; wait "$live_pid" 2>/dev/null
  eq "real-kernel: every attack refused, the run classifies (exit 0 CACHES)" "0 CACHES" "$RC $(verdict)"
  [[ "$RC" == 0 ]] || { echo "  real-kernel stderr tail:"; tail -n 15 "$F/err" | sed 's/^/    /'; }
  for lbl in baseline candidate; do
    rep="$(find "$RK_TMP" -maxdepth 4 -path "*/run-$lbl/scratch/report.json" 2>/dev/null | head -n1)"
    check "real-kernel: the $lbl fake harness wrote its report" test -s "$rep"
    eq "real-kernel: $lbl attacks refused (2 remounts, 2 umounts, 7 or 8 writes, 4 connects)" "" \
      "$(node -e 'const r=require(process.argv[1]);const bad=Object.entries(r).filter(([k,v])=>v!=="refused"&&v!=="allowed");process.stdout.write(bad.map(x=>x.join("=")).join(","))' "$rep" 2>/dev/null || echo unreadable)"
    eq "real-kernel: $lbl attack count" "$([[ $lbl == baseline ]] && echo 15 || echo 16)" \
      "$(node -e 'const r=require(process.argv[1]);process.stdout.write(String(Object.values(r).filter(v=>v==="refused").length))' "$rep" 2>/dev/null)"
    eq "real-kernel: $lbl positive controls (run home, run scratch, private /tmp, /etc binds)" 5 \
      "$(node -e 'const r=require(process.argv[1]);process.stdout.write(String(Object.values(r).filter(v=>v==="allowed").length))' "$rep" 2>/dev/null)"
  done
  check "real-kernel: no attack file landed in the fixture tree" bash -c '! find "$0" -name .attack -print -quit | grep -q .' "$F"
  check "real-kernel: no attack file landed in the scratch tree" bash -c '! find "$0" -name .attack -not -path "*/run-*/home/*" -not -path "*/run-*/scratch/*" -print -quit | grep -q .' "$RK_TMP"
  chmod -R u+w "$RK_TMP" "$RK_BASE" 2>/dev/null; rm -rf "$RK_TMP" "$RK_BASE"
fi

echo
echo "remeasure-sdk-sandbox-network-cache.test.sh: $PASS passed, $FAIL failed"
# Anti-vacuity floor: a LOWER BOUND on the assertions that ran (the measured count at the last edit). Reported with printf + exit, not
# through eq/check, so it does not route through the helpers it backstops. Raise it with a new row. The real-kernel row adds its
# own 17 only where it ran (a SKIP lowers the floor by exactly that row, never more).
MIN_ASSERTIONS=$((345 + RK_RAN * 17))
if [[ $((PASS + FAIL)) -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: anti-vacuity floor: only %s assertions ran, floor is %s\n' "$((PASS + FAIL))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
# The suite's verdict, also through printf + exit (a bare test as the last command is one edit away from always-true).
if (( FAIL != 0 )); then
  printf 'FATAL: %s assertion(s) failed\n' "$FAIL" >&2
  exit 1
fi
exit 0
