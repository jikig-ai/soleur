#!/usr/bin/env bash
# Offline tests for remeasure-sdk-sandbox-network-cache.sh — #12906 PR-1b (Guard 2 of the plan's Guard Contract, plus the
# script-to-classifier wiring).
#
# Run via:  bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.test.sh
# No network and no namespaces: `npm`, `unshare`, `timeout`, `uname`, `getconf`, `df` and `mount` are stubs that come first
# on PATH and EXIT 64 on any argv the script is not supposed to send (logged to a refusal file every row asserts empty).
# Each row copies the script and the REAL classifier into a fixture app tree inside a fixture git repo (with a sibling
# worktree) under this suite's own `mktemp -d`; the fixture links the real tsx, and a fixture harness prints synthesized
# NETNS_* records. The stub `mount` models a read-only remount as `chmod a-w`, so the script's real write probe is what
# decides containment. All fixtures are synthesized (cq-test-fixtures-synthesized-only).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_APP="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT_SRC="$SCRIPT_DIR/remeasure-sdk-sandbox-network-cache.sh"
CLASSIFIER_SRC="$SCRIPT_DIR/lib/sandbox-network-cache-verdict.ts"
REAL_TSX="$REAL_APP/node_modules/.bin/tsx"

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
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
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
BASE_V="0.3.321"
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

BASE_INT_SDK="$(cd "$REAL_APP" && "$REAL_TSX" "$CLASSIFIER_SRC" baseline-json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.parse(s).integrity.sdk))')"
BASE_INT_X64="$(cd "$REAL_APP" && "$REAL_TSX" "$CLASSIFIER_SRC" baseline-json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.parse(s).integrity.linuxX64))')"
check "the classifier's baseline-json carries both integrity values" test -n "$BASE_INT_SDK" -a -n "$BASE_INT_X64"

# ---------------------------------------------------------------------------------------------------------------------------------
# Fixture: $F/repo (git repo; app at apps/web-platform), $F/sib (sibling worktree), $F/home, $F/tmp, $F/xdg, $F/cfg, $F/bin.
# ---------------------------------------------------------------------------------------------------------------------------------
mkfix() {
  F="$(mktemp -d "$T/row.XXXXXX")"
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
  echo '{"name":"@anthropic-ai/claude-agent-sdk","version":"0.3.321"}' >"$A/node_modules/@anthropic-ai/claude-agent-sdk/package.json"
  printf '#!/bin/sh\necho fixture\n' >"$A/node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude"
  cat >"$A/test/helpers/netns-egress-harness.mts" <<HARN
import { readFileSync, writeFileSync, existsSync } from "node:fs";
const entry = process.env.NETNS_SDK_ENTRY ?? "";
const label = entry.includes("/baseline/") ? "baseline" : entry.includes("/candidate/") ? "candidate" : "none";
writeFileSync("$F/cfg/env-" + label + ".json", JSON.stringify({ keys: Object.keys(process.env).sort(), env: process.env, argv: process.argv.slice(2), cwd: process.cwd() }));
const spec = JSON.parse(readFileSync(process.argv[2], "utf8"));
writeFileSync("$F/cfg/spec-" + label + ".json", JSON.stringify(spec));
process.stderr.write("harness stderr ${SENTINEL}\n");
process.stdout.write(readFileSync("$F/cfg/out-" + label, "utf8"));
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
  "view \$P time --json") printf '{"created":"2020-01-01T00:00:00.000Z","modified":"2020-01-01T00:00:00.000Z","0.3.321":"2020-01-01T00:00:00.000Z","%s":"%s"}\n' "\$cand" "\$(cat "\$C/sdk-time")" ;;
  "view \$X time --json") printf '{"created":"2020-01-01T00:00:00.000Z","modified":"2020-01-01T00:00:00.000Z","0.3.321":"2020-01-01T00:00:00.000Z","%s":"%s"}\n' "\$cand" "\$(cat "\$C/x64-time")" ;;
  "install --prefix "*" --ignore-scripts --no-audit --no-fund --save-exact --min-release-age=3 \$P@"*)
    [[ \$# -eq 9 ]] || refuse "install-arity"
    d="\$2" v="\${9#\$P@}"; [[ "\$v" =~ \$semver ]] || refuse "install-version"
    # Writes into its cwd, as a real npm without --prefix would: an install run from the app dir mutates the app.
    t="\$PWD"
    mkdir -p "\$t/node_modules/\$P" "\$t/node_modules/\$X"
    printf '{"name":"%s","version":"%s","claudeCodeVersion":"2.1.%s"}\n' "\$P" "\$v" "\${v##*.}" >"\$t/node_modules/\$P/package.json"
    echo "export const query = 1;" >"\$t/node_modules/\$P/sdk.mjs"
    printf '#!/bin/sh\necho %s\n' "\$v" >"\$t/node_modules/\$X/claude"; chmod +x "\$t/node_modules/\$X/claude"
    if [[ "\$v" == 0.3.321 ]]; then
      is="\$BI_SDK"; ix="\$BI_X64"; [[ -f "\$C/bad-baseline-integrity" ]] && is="sha512-tampered=="
    else is="sha512-candidatesdk=="; ix="sha512-candidatex64=="; fi
    printf '{"packages":{"node_modules/%s":{"integrity":"%s"},"node_modules/%s":{"integrity":"%s"}}}\n' "\$P" "\$is" "\$X" "\$ix" >"\$t/package-lock.json"
    [[ "\$v" != 0.3.321 && -f "\$C/mutate-lock" ]] && echo " " >>"\$A/package-lock.json"
    [[ "\$v" != 0.3.321 && -f "\$C/mutate-sdk" ]] && echo "# changed" >>"\$A/node_modules/\$X/claude"
    exit 0 ;;
  "audit signatures --prefix "*)
    [[ \$# -eq 4 && "\$PWD" == "\$4" ]] || refuse "audit-form"
    [[ -f "\$C/audit-fail" ]] && { echo "1 package has an invalid registry signature"; exit 1; }
    echo "audited 2 packages"; exit 0 ;;
  *) refuse "unmodelled" ;;
esac
STUB
  cat >"$F/bin/unshare" <<STUB
#!/usr/bin/env bash
C="$C"
if [[ "\$*" == "-rnm true" ]]; then [[ -f "\$C/no-userns" ]] && exit 1; exit 0; fi
if [[ "\$1 \$2 \$3 \$4 \$5" == "-rnm --fork --pid --mount-proc --kill-child" ]]; then shift 5; exec "\$@"; fi
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
  # mount: a read-only tmpfs or remount is modelled as chmod a-w; a path listed in cfg/mount-skip is left writable.
  cat >"$F/bin/mount" <<STUB
#!/usr/bin/env bash
C="$C"
printf '%s\n' "\$*" >>"\$C/mount.log"
skip() { grep -qxF -- "\$1" "\$C/mount-skip" 2>/dev/null; }
if [[ \$# -eq 6 && "\$1" == -t && "\$2" == tmpfs && "\$3" == -o && "\$4" == ro,size=64k,mode=0555 && "\$5" == remeasure-* ]]; then
  skip "\$6" || chmod a-w "\$6"; exit 0
fi
if [[ \$# -eq 3 && "\$1" == --bind && "\$2" == "\$3" ]]; then exit 0; fi
if [[ \$# -eq 3 && "\$1" == -o && "\$2" == remount,bind,ro ]]; then skip "\$3" || chmod a-w "\$3"; exit 0; fi
printf 'mount %s\n' "\$*" >>"\$C/refusals"; exit 64
STUB
  chmod +x "$F/bin/"*
}

# run_row <name> [script args...]: runs the fixture copy under a clean env; sets RC, OUT, ERR; asserts the per-row invariants.
run_row() {
  ROW="$1"; shift
  local sut="$A/scripts/remeasure-sdk-sandbox-network-cache.sh"
  case "$sut" in "$T"/*) : ;; *) bad "$ROW: the script under test is not under the suite's mktemp dir ($sut)"; return ;; esac
  env -i PATH="$F/bin:/usr/bin:/bin" HOME="$F/home" TMPDIR="${ROW_TMPDIR:-$F/tmp}" XDG_RUNTIME_DIR="$F/xdg" USER=zzfixtureuser LANG=C.UTF-8 \
    bash "$sut" "$@" >"$F/out" 2>"$F/err"
  RC=$?
  OUT="$(cat "$F/out")"
  ERR="$(cat "$F/err")"
  local last; last="$(tail -n1 "$F/out")"
  check "$ROW: last stdout line is the REMEASURE line" grep -qE '^REMEASURE verdict=\S+ exit=[0-9] reason=\S+ next=' <<<"$last"
  eq "$ROW: REMEASURE exit= matches the process exit" "$RC" "$(sed -n 's/^REMEASURE verdict=[^ ]* exit=\([0-9]\) .*/\1/p' <<<"$last")"
  eq "$ROW: no stub refused an argv" "" "$(cat "$F/cfg/refusals")"
  if [[ -n "${EXPECT_KEPT:-}" ]]; then
    check "$ROW: --keep-scratch keeps the scratch dir" test -n "$(scratch_left "$F/tmp")"
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
check "caches: every protected path was remounted read-only (main, sibling, common dir)" bash -c \
  'grep -qxF -- "-o remount,bind,ro $1" "$3" && grep -qxF -- "-o remount,bind,ro $2" "$3" && grep -qxF -- "-o remount,bind,ro $1/.git" "$3"' _ "$F/repo" "$F/sib" "$F/cfg/mount.log"
check "caches: HOME and XDG_RUNTIME_DIR were masked with a read-only tmpfs" bash -c \
  'grep -qxF -- "-t tmpfs -o ro,size=64k,mode=0555 remeasure-home $1" "$3" && grep -qxF -- "-t tmpfs -o ro,size=64k,mode=0555 remeasure-xdg $2" "$3"' _ "$F/home" "$F/xdg" "$F/cfg/mount.log"
check "caches: --out JSON written" test -s "$F/verdict.json"
eq "caches: JSON requested" "$CAND_V" "$(node -p 'require(process.argv[1]).requested' "$F/verdict.json")"
eq "caches: JSON env carries the candidate integrity" "sha512-candidatesdk==" "$(node -p 'require(process.argv[1]).env.candidateIntegritySdk' "$F/verdict.json")"
check "caches: JSON paths are redacted to <scratch>" bash -c '! grep -q "$0" "$1"' "$F/tmp/remeasure-sdk" "$F/verdict.json"
check "caches: both markdown drafts written with the command" bash -c 'grep -q "remeasure-sdk-sandbox-network-cache.sh $0" "$1/addendum.md" && grep -q "| F2 |" "$1/issue-comment.md"' "$CAND_V" "$F/md"
check "caches: no draft carries the sentinel" bash -c '! grep -rq "$0" "$1"' "$SENTINEL" "$F/md"
check "caches: app package-lock untouched" app_untouched_lock
check "caches: no UNVERIFIED token" no_unverified

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

echo "--- --keep-scratch"
mkfix
EXPECT_KEPT=1 run_row keep "$CAND_V" --keep-scratch
eq "keep: exit 0" 0 "$RC"
check "keep: warns that the kept dir is unredacted" grep -q 'holds unredacted harness transcripts' "$F/err"

echo
echo "remeasure-sdk-sandbox-network-cache.test.sh: $PASS passed, $FAIL failed"
# Anti-vacuity floor: a LOWER BOUND on the assertions that ran (the measured count at the last edit). Reported with printf + exit, not
# through eq/check, so it does not route through the helpers it backstops. Raise it with a new row.
MIN_ASSERTIONS=219
if [[ $((PASS + FAIL)) -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: anti-vacuity floor: only %s assertions ran, floor is %s\n' "$((PASS + FAIL))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
