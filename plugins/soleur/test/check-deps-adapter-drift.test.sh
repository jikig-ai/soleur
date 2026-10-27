#!/usr/bin/env bash

# T2.4 — check_deps.sh must detect when the installed adapter at
# ~/.local/share/pencil-adapter/pencil-mcp-adapter.mjs diverges from the
# repo source. A 24-day-stale install is what surfaced as #2630's
# "silent drop" — the installed copy lacked recent error-classification
# fixes, so failures passed through as unclassified text.
#
# The drift check is exposed via `check_deps.sh --check-adapter-drift`,
# which exits 3 on drift (distinct from the general detection exit codes)
# and prints DRIFT plus both sha prefixes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Owning trap installed BEFORE the helper is sourced: test-helpers.sh composes its
# incident-sandbox cleanup over an existing EXIT trap, whereas a trap installed
# afterwards replaces it and leaks the sandbox on every direct run (#8659). The
# `:-` guard keeps it a no-op if the suite exits before allocating the scratch dir
# (e.g. the git-location tripwire's exit 97 inside the source line itself).
trap '[[ -z "${tmp_dir:-}" ]] || rm -rf "$tmp_dir"' EXIT INT TERM HUP
source "$SCRIPT_DIR/test-helpers.sh"

# The trust rule refuses a group-writable package directory, so every fixture tree this suite builds
# must be created under a fixed umask, whatever the caller's (a developer with umask 002 would
# otherwise see every identity row refuse).
umask 022

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CHECK_DEPS="$REPO_ROOT/plugins/soleur/skills/pencil-setup/scripts/check_deps.sh"

echo "=== check_deps.sh adapter drift detection ==="
echo ""

assert_file_exists "$CHECK_DEPS" "check_deps.sh exists"

# ---------------------------------------------------------------------------
# Set up a temp home with a deliberately-drifted adapter copy and run
# the drift check against it. PENCIL_ADAPTER_INSTALL_DIR overrides the
# default ~/.local/share/pencil-adapter so the test stays hermetic.
# ---------------------------------------------------------------------------
tmp_dir=$(mktemp -d)

repo_adapter="$REPO_ROOT/plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs"

scripts_dir="$REPO_ROOT/plugins/soleur/skills/pencil-setup/scripts"
# The runtime set copy_adapter.sh installs: every module plus the dependency manifest pair.
copy_adapter_set() { cp "$scripts_dir"/*.mjs "$scripts_dir/package.json" "$scripts_dir/package-lock.json" "$1/"; }

# Each case gets an isolated install dir so a failure in one case cannot
# cascade through shared state into the next case's assertions.

# --- Case 1: installed adapter matches repo → no drift, exit 0 ---
case1_dir="$tmp_dir/case1"
mkdir -p "$case1_dir"
copy_adapter_set "$case1_dir"
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$case1_dir" bash "$CHECK_DEPS" --check-adapter-drift 2>&1)
rc=$?
set -e
assert_eq "0" "$rc" "matching sha: exit 0"
assert_contains "$out" "OK" "matching sha: prints OK marker"

# --- Case 2: installed adapter differs from repo → drift, exit 3 ---
case2_dir="$tmp_dir/case2"
mkdir -p "$case2_dir"
cp "$repo_adapter" "$case2_dir/pencil-mcp-adapter.mjs"
echo "// drift" >> "$case2_dir/pencil-mcp-adapter.mjs"
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$case2_dir" bash "$CHECK_DEPS" --check-adapter-drift 2>&1)
rc=$?
set -e
assert_eq "3" "$rc" "drifted sha: exit 3"
assert_contains "$out" "DRIFT" "drifted sha: prints DRIFT marker"

# --- Case 2b: a stale SIBLING module next to a fresh adapter is drift too ---
# The save sentinel and the REPL surface table are siblings; hashing only the
# main file reported OK while the guards were stale.
case2b_dir="$tmp_dir/case2b"
mkdir -p "$case2b_dir"
copy_adapter_set "$case2b_dir"
echo "// stale" >> "$case2b_dir/pencil-save-gate.mjs"
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$case2b_dir" bash "$CHECK_DEPS" --check-adapter-drift 2>&1)
rc=$?
set -e
assert_eq "3" "$rc" "stale sibling: exit 3"
assert_contains "$out" "pencil-save-gate.mjs" "stale sibling: names the drifted module"

# --- Case 2c: a MISSING sibling is drift ---
case2c_dir="$tmp_dir/case2c"
mkdir -p "$case2c_dir"
copy_adapter_set "$case2c_dir"
rm "$case2c_dir/pencil-repl-surface.mjs"
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$case2c_dir" bash "$CHECK_DEPS" --check-adapter-drift 2>&1)
rc=$?
set -e
assert_eq "3" "$rc" "missing sibling: exit 3"
assert_contains "$out" "pencil-repl-surface.mjs" "missing sibling: names the missing module"

# --- Case 2d: an unparseable module list is an error, never a clean OK ---
case2d_scripts="$tmp_dir/case2d-scripts"
case2d_dir="$tmp_dir/case2d"
mkdir -p "$case2d_scripts" "$case2d_dir"
cp "$CHECK_DEPS" "$case2d_scripts/check_deps.sh"
cp "$repo_adapter" "$case2d_scripts/pencil-mcp-adapter.mjs"
cp "$repo_adapter" "$case2d_dir/pencil-mcp-adapter.mjs"
echo "# no module list here" > "$case2d_scripts/copy_adapter.sh"
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$case2d_dir" bash "$case2d_scripts/check_deps.sh" --check-adapter-drift 2>&1)
rc=$?
set -e
assert_eq "2" "$rc" "empty module list: exit 2"
assert_contains "$out" "no adapter modules parsed" "empty module list: says why"

# Run a check_deps.sh function (sourced, so no tiers run) under a fake HOME with the credential
# names scrubbed. Prints the function's output and a final `rc=<n>` line. A plain `bash -c`, not
# the suite's shell: errexit must not leak into the sourced script.
in_home() { # <home> <fn> [args...]
  local home="$1"; shift
  env -u PEN_CLI_KEY -u PENCIL_CLI_KEY -u PENCIL_ADAPTER_INSTALL_DIR \
    HOME="$home" NVM_DIR="$home/.nvm" FNM_DIR="$home/.fnm" PATH="$home/fakebin:$PATH" \
    bash -c 'f="$1"; shift; args=("$@"); set --; source "$f"; "${args[@]}"; echo "rc=$?"' _ "$CHECK_DEPS" "$@" </dev/null 2>&1 || true
}
verdict_of() { # extract rc from in_home output: accept (0) | refuse (non-zero)
  case "$(printf '%s\n' "$1" | sed -n 's/^rc=//p' | tail -1)" in 0) echo accept ;; *) echo refuse ;; esac
}

# Hermetic installer fixtures for every --auto path below: a fake HOME whose first PATH entry
# carries a `node` link (find_node22 resolves it, and npm is looked up next to it) and a FAKE npm.
# The fake logs one line per call (args, cwd, how many credential variables it can see), emits
# FAKE_NPM_NOISE lines of output, can fail the engine install, and for the engine prefix rebuilds
# the `good` tree the way a real `npm ci` would. No test below can reach the network or a real
# prefix, and none can leave a credential anywhere but the child it is checking.
TREE="$SCRIPT_DIR/lib/pen-identity-tree.mjs"
cat > "$tmp_dir/fake-npm.sh" <<'FAKE_NPM_EOF'
#!/usr/bin/env bash
echo "ARGS=$* CWD=$PWD UMASK=$(umask) CRED_VARS=$(env | grep -c -E '^(PEN_CLI_KEY|PENCIL_CLI_KEY)=' || true)" >> "$FAKE_NPM_LOG"
if [[ -n "${FAKE_NPM_NOISE:-}" ]]; then for i in $(seq 1 "$FAKE_NPM_NOISE"); do echo "npmnoise $i"; done; fi
case "$PWD" in
  */share/pen-cli.new)
    # the engine, installed into the staging prefix
    [[ -z "${FAKE_NPM_FAIL_ENGINE:-}" ]] || exit 7
    scratch=$(mktemp -d)
    node "$FAKE_TREE_HELPER" "$scratch" good >/dev/null
    rm -rf node_modules
    cp -a "$scratch/.local/share/pen-cli/node_modules" node_modules
    rm -rf "$scratch"
    # a umask-002 npm: group-writable directories whatever the caller asked for
    [[ -z "${FAKE_NPM_GROUP_WRITABLE:-}" ]] || chmod -R g+w node_modules
    ;;
  *)
    # the adapter's own dependencies
    mkdir -p node_modules
    # exits 1 but leaves a perfectly valid-looking tree: only the exit status says it failed
    [[ -z "${FAKE_NPM_FAIL_ADAPTER:-}" ]] || exit 1
    ;;
esac
FAKE_NPM_EOF
make_fake_home() { # <name> -> fake HOME with fakebin/{node,npm}
  local h="$tmp_dir/$1"
  mkdir -p "$h/fakebin"
  ln -s "$(command -v node)" "$h/fakebin/node"
  cp "$tmp_dir/fake-npm.sh" "$h/fakebin/npm"
  chmod 0755 "$h/fakebin/npm"
  # A run that falls through every tier must never reach a REAL editor or Pencil on this machine:
  # a --auto run would otherwise try to install an extension / launch the app. Inert stubs.
  local stub
  for stub in cursor code pencil; do
    printf '#!/bin/sh\necho "STUB %s called: $*" >> "${FAKE_NPM_LOG:-/dev/null}.stubs"\nexit 1\n' "$stub" > "$h/fakebin/$stub"
    chmod 0755 "$h/fakebin/$stub"
  done
  printf '%s' "$h"
}
# Run a command with that HOME, a canary credential in BOTH names, and the fake npm's knobs.
in_fake_home() { # <home> [VAR=val ...] -- cmd args...
  local h="$1" rc=0; shift
  local extra=()
  while [[ "$1" != "--" ]]; do extra+=("$1"); shift; done
  shift
  env -u PEN_CLI_KEY -u PENCIL_CLI_KEY -u PENCIL_ADAPTER_INSTALL_DIR \
    HOME="$h" NVM_DIR="$h/.nvm" FNM_DIR="$h/.fnm" PATH="$h/fakebin:$PATH" \
    FAKE_NPM_LOG="$h/npm.log" FAKE_TREE_HELPER="$TREE" "${extra[@]}" "$@" </dev/null 2>&1 || rc=$?
  echo "rc=${rc:-0}"
}

# --- Case 3: --auto re-copies, installs the adapter's deps AND the engine, then exits 0 ---
# (the new adapter must never be installed ahead of the engine it needs)
home3=$(make_fake_home case3-home)
case3_dir="$home3/.local/share/pencil-adapter"
mkdir -p "$case3_dir"
cp "$repo_adapter" "$case3_dir/pencil-mcp-adapter.mjs"
echo "// drift" >> "$case3_dir/pencil-mcp-adapter.mjs"
out=$(in_fake_home "$home3" PEN_CLI_KEY=synthetic-canary-1 PENCIL_CLI_KEY=synthetic-canary-2 -- bash "$CHECK_DEPS" --check-adapter-drift --auto)
assert_contains "$out" "OK: re-copied adapter" "--auto re-copy: says it re-copied"
installed_sha=$(sha256sum "$case3_dir/pencil-mcp-adapter.mjs" | awk '{print $1}')
repo_sha=$(sha256sum "$repo_adapter" | awk '{print $1}')
assert_eq "$repo_sha" "$installed_sha" "--auto re-copy: installed sha now matches repo"
npm_log3=$(cat "$home3/npm.log" 2>/dev/null || true)
assert_contains "$npm_log3" "CWD=$case3_dir" "--auto drift: adapter dependencies installed in the adapter dir"
assert_contains "$npm_log3" "CWD=$home3/.local/share/pen-cli" "--auto drift: the engine is installed after the adapter copy"
assert_eq "2" "$(printf '%s\n' "$npm_log3" | grep -c 'ARGS=ci --ignore-scripts')" "--auto drift: exactly two npm ci --ignore-scripts runs (adapter deps, engine)"
assert_eq "0" "$(printf '%s\n' "$npm_log3" | grep -c -v 'CRED_VARS=0' || true)" "--auto drift: neither credential name reaches either npm ci"
assert_eq "accept" "$(verdict_of "$(in_home "$home3" detect_headless_cli)")" "--auto drift: the engine installed by the repair passes the identity rule"
# Drift again with the engine now at the pin: only the adapter step runs, the engine is not reinstalled
echo "// drift" >> "$case3_dir/pencil-mcp-adapter.mjs"
: > "$home3/npm.log"
out=$(in_fake_home "$home3" -- bash "$CHECK_DEPS" --check-adapter-drift --auto)
assert_contains "$out" "rc=0" "--auto drift with the engine already at the pin: exit 0"
assert_eq "0" "$(grep -c 'share/pen-cli' "$home3/npm.log" || true)" "--auto drift with the engine at the pin: engine not reinstalled"
# Engine installed at a DIFFERENT version: the repair reinstalls it from the lockfile
home3b=$(make_fake_home case3b-home)
mkdir -p "$home3b/.local/share/pencil-adapter"
cp "$repo_adapter" "$home3b/.local/share/pencil-adapter/pencil-mcp-adapter.mjs"
echo "// drift" >> "$home3b/.local/share/pencil-adapter/pencil-mcp-adapter.mjs"
node "$TREE" "$home3b" version-differs >/dev/null
out=$(in_fake_home "$home3b" -- bash "$CHECK_DEPS" --check-adapter-drift --auto)
assert_contains "$(cat "$home3b/npm.log" 2>/dev/null)" "CWD=$home3b/.local/share/pen-cli" "--auto drift with a pin-drifted engine: engine reinstalled"
# A failing engine install is an error, not a green "re-copied"
home3c=$(make_fake_home case3c-home)
mkdir -p "$home3c/.local/share/pencil-adapter"
cp "$repo_adapter" "$home3c/.local/share/pencil-adapter/pencil-mcp-adapter.mjs"
echo "// drift" >> "$home3c/.local/share/pencil-adapter/pencil-mcp-adapter.mjs"
out=$(in_fake_home "$home3c" FAKE_NPM_FAIL_ENGINE=1 -- bash "$CHECK_DEPS" --check-adapter-drift --auto)
assert_contains "$out" "rc=2" "--auto drift with a failing engine install: exit 2"
assert_contains "$out" "engine" "--auto drift with a failing engine install: names the engine"

# --- Case 3b: drift also covers the dependency manifests (.json), not only .mjs ---
for jf in package-lock.json package.json; do
  d="$tmp_dir/case3-$jf"
  mkdir -p "$d"
  copy_adapter_set "$d"
  echo " " >> "$d/$jf"
  set +e
  out=$(PENCIL_ADAPTER_INSTALL_DIR="$d" bash "$CHECK_DEPS" --check-adapter-drift 2>&1)
  rc=$?
  set -e
  assert_eq "3" "$rc" "stale $jf: exit 3"
  assert_contains "$out" "$jf" "stale $jf: names the drifted manifest"
done

# --- copy_adapter.sh: npm ci is keyed on the lockfile hash, and never sees a credential ---
COPY="$scripts_dir/copy_adapter.sh"
home5=$(make_fake_home copy-home)
run_copy() { in_fake_home "$home5" PENCIL_ADAPTER_INSTALL_DIR="$home5/inst" PEN_CLI_KEY=synthetic-canary-1 PENCIL_CLI_KEY=synthetic-canary-2 -- bash "$COPY"; }
count_ci() { grep -c 'ARGS=ci --ignore-scripts' "$home5/npm.log" 2>/dev/null || true; }
run_copy >/dev/null
assert_eq "1" "$(count_ci)" "copy_adapter.sh: first install runs npm ci once"
assert_contains "$(cat "$home5/npm.log")" "CRED_VARS=0" "copy_adapter.sh: npm ci runs without PEN_CLI_KEY / PENCIL_CLI_KEY"
assert_eq "0" "$(grep -c -v 'CRED_VARS=0' "$home5/npm.log" || true)" "copy_adapter.sh: no npm ci run sees a credential"
run_copy >/dev/null
assert_eq "1" "$(count_ci)" "copy_adapter.sh: an unchanged lockfile does not re-run npm ci"
# a node_modules built from an OLDER lockfile: its stamp disagrees with the lockfile now in place
echo "0000-stamp-from-an-older-lockfile" > "$home5/inst/node_modules/.soleur-package-lock.sha256"
run_copy >/dev/null
assert_eq "2" "$(count_ci)" "copy_adapter.sh: a node_modules stamped with another lockfile hash re-runs npm ci (keyed on the lockfile hash)"
run_copy >/dev/null
assert_eq "2" "$(count_ci)" "copy_adapter.sh: the refreshed stamp keeps it quiet"
rm -f "$home5/inst/node_modules"/.soleur-* 2>/dev/null || true
run_copy >/dev/null
assert_eq "3" "$(count_ci)" "copy_adapter.sh: node_modules with no lockfile stamp is re-installed once"
run_copy >/dev/null
assert_eq "3" "$(count_ci)" "copy_adapter.sh: and then stays quiet"

# --- Case 4: install dir absent → exit 0 with NOT_INSTALLED marker ---
case4_dir="$tmp_dir/case4-absent"
# Deliberately do NOT create case4_dir
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$case4_dir" bash "$CHECK_DEPS" --check-adapter-drift 2>&1)
rc=$?
set -e
assert_eq "0" "$rc" "absent install: exit 0"
assert_contains "$out" "NOT_INSTALLED" "absent install: prints NOT_INSTALLED marker"

# ===========================================================================
# @pen.dev/cli install + detection (#11156, plan 1.7). The drift cases above
# are unchanged; below: the pinned lockfile prefix, the identity rule shared
# with the adapter (fixtures/pen-identity-cases.tsv), the Node floor, the
# credential names and the old-engine collision.
# ===========================================================================
CASES="$SCRIPT_DIR/fixtures/pen-identity-cases.tsv"
PEN_VALID_KEY="valid-key"   # the fake engine in lib/pen-identity-tree.mjs accepts exactly this

# --- identity table: every row, plus layout/row coverage in both directions ---
assert_file_exists "$TREE" "pen-identity-tree.mjs helper exists"
assert_file_exists "$CASES" "pen-identity-cases.tsv exists"
node "$TREE" --layouts | sort > "$tmp_dir/layouts.txt"
grep -v -e '^#' -e '^[[:space:]]*$' -e '^layout	' "$CASES" | cut -f1 | sort > "$tmp_dir/rows.txt"
if diff -q "$tmp_dir/layouts.txt" "$tmp_dir/rows.txt" >/dev/null; then
  assert_eq "same" "same" "every identity layout has a row and every row has a layout"
else
  assert_eq "same" "$(diff "$tmp_dir/layouts.txt" "$tmp_dir/rows.txt" | tr '\n' ' ')" "every identity layout has a row and every row has a layout"
fi

rows=0
while IFS=$'\t' read -r layout _adapter want_cd want_legacy _note; do
  [[ -z "$layout" || "$layout" == \#* || "$layout" == layout ]] && continue
  rows=$((rows + 1))
  home="$tmp_dir/ident-$layout"
  mkdir -p "$home"
  node "$TREE" "$home" "$layout" >/dev/null
  got=$(verdict_of "$(in_home "$home" detect_headless_cli)")
  assert_eq "$want_cd" "$got" "identity row '$layout': detect_headless_cli verdict"
  warn_out=$(in_home "$home" warn_pen_cli_state)
  if [[ "$want_legacy" == "yes" ]]; then
    assert_contains "$warn_out" "@pencil.dev/cli" "identity row '$layout': leftover deprecated package is warned about"
  elif [[ "$warn_out" == *"@pencil.dev/cli"* ]]; then
    assert_eq "no leftover warning" "warned" "identity row '$layout': no leftover warning expected"
  else
    assert_eq "no" "no" "identity row '$layout': no leftover warning"
  fi
done < "$CASES"
if [[ "$rows" -lt 14 ]]; then
  printf '[FATAL] anti-vacuity floor: only %s identity rows ran, expected at least 14\n' "$rows"
  exit 1
fi
assert_eq "ok" "ok" "identity table ran $rows rows (anti-vacuity floor 14)"

# version != pin is accepted but says so
home="$tmp_dir/ident-version-differs"
assert_contains "$(in_home "$home" warn_pen_cli_state)" "0.3.12" "version differing from the pin is reported"

# --- pin and lockfile agree with check_deps.sh ---
pin=$(sed -n 's/^PEN_CLI_VERSION="\([0-9][0-9.]*\)"$/\1/p' "$CHECK_DEPS" | head -1)
assert_eq "0.3.13" "$pin" "check_deps.sh declares PEN_CLI_VERSION=0.3.13"
lock_pair="$scripts_dir/pen-cli"
assert_file_exists "$lock_pair/package.json" "pen-cli/package.json is committed"
assert_file_exists "$lock_pair/package-lock.json" "pen-cli/package-lock.json is committed"
lock_facts=$(node -e '
  const d = process.argv[1];
  const pj = JSON.parse(require("fs").readFileSync(d + "/package.json", "utf8"));
  const lk = JSON.parse(require("fs").readFileSync(d + "/package-lock.json", "utf8"));
  const e = lk.packages["node_modules/@pen.dev/cli"] || {};
  process.stdout.write([pj.dependencies["@pen.dev/cli"], e.version, e.integrity ? "integrity" : "no-integrity"].join(" "));
' "$lock_pair")
assert_eq "$pin $pin integrity" "$lock_facts" "package.json pin, locked version and integrity all match the check_deps.sh pin"

# --- Node floor: numeric compare, 22.18.x refused, 22.19.0 accepted ---
for case in "v22.19.0:0" "22.19.0:0" "v22.19.7:0" "v22.20.0:0" "v22.100.0:0" "v23.0.0:0" "v26.12.1:0" \
            "v22.18.9:1" "v22.18.0:1" "v22.9.0:1" "v22.10.3:1" "v21.99.0:1" "v20.0.0:1" "garbage:1" ":1"; do
  v="${case%:*}"; want="${case##*:}"
  out=$(in_home "$tmp_dir" node_version_ok "$v")
  assert_eq "$want" "$(printf '%s\n' "$out" | sed -n 's/^rc=//p' | tail -1)" "node_version_ok '$v' -> $want"
done
# find_node22 applies it to the node on PATH (fake node reporting 22.18.5, then 22.19.0)
for ver in "22.18.5:refuse" "22.19.0:accept"; do
  fake_home="$tmp_dir/fakenode-${ver%%:*}"
  mkdir -p "$fake_home/fakebin"
  printf '#!/bin/sh\n[ "$1" = "--version" ] && echo "v%s"\n' "${ver%%:*}" > "$fake_home/fakebin/node"
  chmod 0755 "$fake_home/fakebin/node"
  got=$(verdict_of "$(in_home "$fake_home" find_node22)")
  assert_eq "${ver##*:}" "$got" "find_node22 with node v${ver%%:*} -> ${ver##*:}"
done
assert_eq "0" "$(grep -c -E '22\.9\.0|-ge 9\)' "$CHECK_DEPS" || true)" "check_deps.sh carries no leftover 22.9 floor"
assert_eq "0" "$(grep -c 'readlink -f' "$CHECK_DEPS" || true)" "check_deps.sh does not use readlink -f (macOS)"
assert_eq "0" "$(grep -c -E '\.bin/pencil|@pencil\.dev/cli@' "$CHECK_DEPS" || true)" "check_deps.sh neither selects the old bin nor installs the old package"

# --- trace guard covers both credential names ---
for name in PEN_CLI_KEY PENCIL_CLI_KEY; do
  set +e
  out=$(env -u PEN_CLI_KEY -u PENCIL_CLI_KEY "$name=synthetic-not-a-key" PENCIL_ADAPTER_INSTALL_DIR="$tmp_dir/absent-trace" bash -x "$CHECK_DEPS" --check-adapter-drift 2>&1 </dev/null)
  rc=$?
  set -e
  assert_eq "78" "$rc" "bash -x with only $name set is refused (rc 78)"
  assert_contains "$out" "refusing to trace" "bash -x with only $name: refusal message"
done
set +e
env -u PEN_CLI_KEY -u PENCIL_CLI_KEY PEN_CLI_KEY="" PENCIL_CLI_KEY="" PENCIL_ADAPTER_INSTALL_DIR="$tmp_dir/absent-trace" bash -x "$CHECK_DEPS" --check-adapter-drift >/dev/null 2>&1 </dev/null
rc=$?
set -e
assert_eq "0" "$rc" "bash -x with both names empty is not refused"

# --- full runs: auth uses PEN_CLI_KEY, accepts the fallback, empty counts as unset ---
full_run() { # <home> [VAR=val ...]
  local home="$1"; shift
  env -u PEN_CLI_KEY -u PENCIL_CLI_KEY -u PENCIL_ADAPTER_INSTALL_DIR "$@" \
    HOME="$home" NVM_DIR="$home/.nvm" FNM_DIR="$home/.fnm" PATH="$home/fakebin:$PATH" \
    bash "$CHECK_DEPS" </dev/null 2>&1 || true
}
auth_cases=(
  "PEN_CLI_KEY alone|PEN_CLI_KEY=$PEN_VALID_KEY|tier0"
  "PENCIL_CLI_KEY alone (deprecated fallback)|PENCIL_CLI_KEY=$PEN_VALID_KEY|tier0"
  "empty PEN_CLI_KEY with valid fallback|PEN_CLI_KEY= PENCIL_CLI_KEY=$PEN_VALID_KEY|tier0"
  "whitespace PEN_CLI_KEY with valid fallback|PEN_CLI_KEY=_WS_ PENCIL_CLI_KEY=$PEN_VALID_KEY|tier0"
  "both set, PEN_CLI_KEY wins and is wrong|PEN_CLI_KEY=wrong PENCIL_CLI_KEY=$PEN_VALID_KEY|authfail"
  "wrong key|PEN_CLI_KEY=wrong|authfail"
  "no key|NONE=1|authfail"
)
n=0
for row in "${auth_cases[@]}"; do
  n=$((n + 1))
  label="${row%%|*}"; rest="${row#*|}"; envs="${rest%|*}"; want="${rest##*|}"
  home="$tmp_dir/auth-$n"; mkdir -p "$home"
  node "$TREE" "$home" good >/dev/null
  # shellcheck disable=SC2086  # envs is a space-separated list of NAME=value tokens
  envargs=(); for t in $envs; do envargs+=("${t//_WS_/   }"); done
  out=$(full_run "$home" "${envargs[@]}")
  if [[ "$want" == "tier0" ]]; then
    assert_contains "$out" "Headless CLI (Tier 0)" "auth: $label -> headless tier selected"
    assert_contains "$out" "PREFERRED_MODE=headless_cli" "auth: $label -> PREFERRED_MODE=headless_cli"
  else
    if [[ "$out" == *"Headless CLI (Tier 0)"* ]]; then
      assert_eq "not selected" "selected" "auth: $label -> headless tier not selected"
    else
      assert_eq "ok" "ok" "auth: $label -> headless tier not selected"
    fi
    if [[ "$label" == "no key" ]]; then
      assert_contains "$out" "auth failed" "auth: $label -> says auth failed"
    else
      assert_contains "$out" "could not confirm Active (key invalid or engine unreachable)" "auth: $label -> says it could not confirm Active"
    fi
    assert_contains "$out" "PEN_CLI_KEY" "auth: $label -> names PEN_CLI_KEY"
  fi
  # whatever the outcome, the engine child saw the credential under PEN_CLI_KEY only
  if [[ -f "$home/engine-env.log" ]] && grep -q 'PENCIL_CLI_KEY' "$home/engine-env.log"; then
    assert_eq "PEN_CLI_KEY only" "$(cat "$home/engine-env.log")" "auth: $label -> child env never carries PENCIL_CLI_KEY"
  else
    assert_eq "ok" "ok" "auth: $label -> child env never carries PENCIL_CLI_KEY"
  fi
done
# a status reply that is not Active must not pass even on exit 0 (fail-open engine)
home="$tmp_dir/auth-failopen"; mkdir -p "$home"
node "$TREE" "$home" good >/dev/null
printf '%s\n' 'console.log("Status  Expired / Revoked"); process.exit(0);' > "$home/.local/share/pen-cli/node_modules/@pen.dev/cli/dist/index.mjs"
out=$(full_run "$home" "PEN_CLI_KEY=$PEN_VALID_KEY")
if [[ "$out" == *"Headless CLI (Tier 0)"* ]]; then
  assert_eq "not selected" "selected" "exit 0 without 'Active' is not accepted as authenticated"
else
  assert_eq "ok" "ok" "exit 0 without 'Active' is not accepted as authenticated"
fi

# --- a leftover @pencil.dev/cli + stale adapter copy: DRIFT, and never routed to the new engine ---
home="$tmp_dir/legacy-world"; mkdir -p "$home/.local/share/pencil-adapter"
node "$TREE" "$home" legacy-only >/dev/null
copy_adapter_set "$home/.local/share/pencil-adapter"
echo "// stale" >> "$home/.local/share/pencil-adapter/pencil-mcp-adapter.mjs"
set +e
out=$(env -u PEN_CLI_KEY -u PENCIL_CLI_KEY -u PENCIL_ADAPTER_INSTALL_DIR HOME="$home" bash "$CHECK_DEPS" --check-adapter-drift 2>&1 </dev/null)
rc=$?
set -e
assert_eq "3" "$rc" "legacy world + stale adapter: --check-adapter-drift exits 3"
assert_contains "$out" "DRIFT" "legacy world + stale adapter: prints DRIFT"
out=$(full_run "$home" "PEN_CLI_KEY=$PEN_VALID_KEY")
assert_contains "$out" "@pencil.dev/cli" "legacy world: leftover deprecated package warned about in the full run"
if [[ "$out" == *"PREFERRED_MODE=headless_cli"* ]]; then
  assert_eq "not routed" "routed to headless" "legacy world: old engine is never selected as the headless tier"
else
  assert_eq "ok" "ok" "legacy world: old engine is never selected as the headless tier"
fi

# --- no PATH fallback: a foreign `pen` on PATH with nothing installed ---
home="$tmp_dir/path-only"; mkdir -p "$home"
node "$TREE" "$home" path-pen-only >/dev/null
out=$(full_run "$home" "PEN_CLI_KEY=$PEN_VALID_KEY")
if [[ "$out" == *"PREFERRED_MODE=headless_cli"* ]]; then
  assert_eq "not selected" "selected" "a foreign pen on PATH never becomes the headless tier"
else
  assert_eq "ok" "ok" "a foreign pen on PATH never becomes the headless tier"
fi

# --- install: lockfile pair copied to the prefix, npm ci, scripts ignored, credentials unset ---
home="$tmp_dir/install-world"
mkdir -p "$home/fakenode" "$home/.local/node_modules/.bin"
ln -s "$(command -v node)" "$home/fakenode/node"
echo "legacy-marker" > "$home/.local/node_modules/.bin/pencil"
cat > "$home/fakenode/npm" <<'FAKE_NPM'
#!/usr/bin/env bash
{
  echo "ARGS=$*"
  echo "CWD=$PWD"
  echo "CRED_VARS=$(env | grep -c -E '^(PEN_CLI_KEY|PENCIL_CLI_KEY)=' || true)"
  echo "UMASK=$(umask)"
} > "$FAKE_NPM_LOG"
scratch=$(mktemp -d)
node "$FAKE_TREE_HELPER" "$scratch" good >/dev/null
rm -rf node_modules
cp -a "$scratch/.local/share/pen-cli/node_modules" node_modules
rm -rf "$scratch"
FAKE_NPM
chmod 0755 "$home/fakenode/npm"
set +e
out=$(umask 002; env -u PEN_CLI_KEY -u PENCIL_CLI_KEY HOME="$home" NVM_DIR="$home/.nvm" FNM_DIR="$home/.fnm" \
  PEN_CLI_KEY=synthetic-canary-1 PENCIL_CLI_KEY=synthetic-canary-2 \
  FAKE_NPM_LOG="$home/npm.log" FAKE_TREE_HELPER="$TREE" FAKE_NODE="$home/fakenode/node" \
  bash -c 'f="$1"; set --; source "$f"; AUTO_INSTALL=true; find_node22() { echo "$FAKE_NODE"; }; attempt_headless_install; echo "install_rc=$?"; detect_headless_cli; echo "detect_rc=$?"' _ "$CHECK_DEPS" 2>&1 </dev/null)
set -e
assert_contains "$out" "install_rc=0" "install: attempt_headless_install succeeds"
assert_contains "$out" "detect_rc=0" "install: the installed tree is detected"
assert_contains "$(cat "$home/npm.log" 2>/dev/null)" "ARGS=ci --ignore-scripts" "install: npm ci with scripts ignored"
assert_contains "$(cat "$home/npm.log" 2>/dev/null)" "CWD=$home/.local/share/pen-cli" "install: runs inside the pen-cli prefix"
assert_contains "$(cat "$home/npm.log" 2>/dev/null)" "CRED_VARS=0" "install: neither credential name reaches npm"
assert_contains "$(cat "$home/npm.log" 2>/dev/null)" "UMASK=0022" "install: npm ci runs under umask 022 even when the caller's umask is 002"
assert_eq "no group/world write" "$([[ -z "$(find "$home/.local/share/pen-cli/node_modules" -perm /022 ! -type l 2>/dev/null | head -1)" ]] && echo "no group/world write" || echo "writable files left")" "install: nothing under the installed node_modules is group- or world-writable"
if cmp -s "$lock_pair/package.json" "$home/.local/share/pen-cli/package.json" \
   && cmp -s "$lock_pair/package-lock.json" "$home/.local/share/pen-cli/package-lock.json"; then
  assert_eq "ok" "ok" "install: the committed lockfile pair is copied byte-identical"
else
  assert_eq "identical" "different or missing" "install: the committed lockfile pair is copied byte-identical"
fi
assert_eq "legacy-marker" "$(cat "$home/.local/node_modules/.bin/pencil")" "install: the old ~/.local/node_modules/.bin/pencil is left alone"
# a failing npm is reported, not swallowed
printf '#!/usr/bin/env bash\nexit 7\n' > "$home/fakenode/npm"
out=$(env -u PEN_CLI_KEY -u PENCIL_CLI_KEY HOME="$home" NVM_DIR="$home/.nvm" FNM_DIR="$home/.fnm" FAKE_NODE="$home/fakenode/node" \
  bash -c 'f="$1"; set --; source "$f"; AUTO_INSTALL=true; find_node22() { echo "$FAKE_NODE"; }; rm -rf "$HOME/.local/share/pen-cli/node_modules"; attempt_headless_install; echo "install_rc=$?"' _ "$CHECK_DEPS" 2>&1 </dev/null || true)
assert_contains "$out" "install_rc=1" "install: a failing npm ci returns non-zero"
assert_contains "$out" "FAILED" "install: a failing npm ci says FAILED"

# A tree stamped as built from the committed lockfile (what a successful install leaves behind).
stamp_engine() { # <home>
  sha256sum -- "$lock_pair/package-lock.json" | awk '{print $1}' > "$1/.local/share/pen-cli/node_modules/.soleur-package-lock.sha256"
}

# --- pin drift under --auto: an installed version != the pin is "needs install", reinstalled from the lockfile ---
# (the version-differs layout is accepted without --auto, with a warning; --auto is the advice's way out)
home=$(make_fake_home pin-drift-auto)
node "$TREE" "$home" version-differs >/dev/null
out=$(in_fake_home "$home" PEN_CLI_KEY=valid-key -- bash "$CHECK_DEPS" --auto)
assert_contains "$(cat "$home/npm.log" 2>/dev/null)" "ARGS=ci --ignore-scripts CWD=$home/.local/share/pen-cli" "pin drift + --auto: the reinstall path is reached (npm ci in the engine prefix)"
assert_contains "$(grep '"version"' "$home/.local/share/pen-cli/node_modules/@pen.dev/cli/package.json")" "0.3.13" "pin drift + --auto: the installed version is the pin afterwards"
assert_contains "$out" "PREFERRED_MODE=headless_cli" "pin drift + --auto: the headless tier is selected after the reinstall"
assert_contains "$out" "re-installing from the lockfile" "pin drift + --auto: the advisory says it is re-installing"
assert_eq "0" "$(printf '%s\n' "$out" | grep -c 're-run with --auto' || true)" "pin drift + --auto: no 're-run with --auto' advice (it is already running)"
home=$(make_fake_home pin-drift-noauto)
node "$TREE" "$home" version-differs >/dev/null
out=$(in_fake_home "$home" PEN_CLI_KEY=valid-key -- bash "$CHECK_DEPS")
assert_eq "no npm" "$([[ -s "$home/npm.log" ]] && echo "npm ran" || echo "no npm")" "pin drift without --auto: nothing is installed"
assert_contains "$out" "0.3.12" "pin drift without --auto: the drift is reported"
assert_contains "$out" "--auto" "pin drift without --auto: the advice names --auto"
# at the pin: --auto does not reinstall
home=$(make_fake_home pin-ok-auto)
node "$TREE" "$home" good >/dev/null
stamp_engine "$home"
out=$(in_fake_home "$home" PEN_CLI_KEY=valid-key -- bash "$CHECK_DEPS" --auto)
assert_eq "no npm" "$([[ -s "$home/npm.log" ]] && echo "npm ran" || echo "no npm")" "at the pin + --auto: no reinstall"

# --- try_headless_cli_tier says why it skipped and what to do ---
home=$(make_fake_home hint-none)
out=$(in_fake_home "$home" PEN_CLI_KEY=valid-key -- bash "$CHECK_DEPS")
assert_contains "$out" "not installed" "no engine installed: the headless tier says so"
assert_contains "$out" "--auto" "no engine installed: and names --auto"
home=$(make_fake_home hint-ident)
node "$TREE" "$home" name-mismatch >/dev/null
out=$(in_fake_home "$home" PEN_CLI_KEY=valid-key -- bash "$CHECK_DEPS")
assert_contains "$out" "identity check" "engine present but failing the identity rule: the skip says so"
assert_contains "$out" "--auto" "engine failing the identity rule: names --auto (reinstall from the lockfile)"

# --- auth probe: coloured status passes; the child env is minimal; the key is never in an env argv ---
home=$(make_fake_home auth-color)
node "$TREE" "$home" good >/dev/null
printf '%s\n' 'console.log("  Status  \x1b[32m●\x1b[0m \x1b[1mActive\x1b[0m"); process.exit(0);' > "$home/.local/share/pen-cli/node_modules/@pen.dev/cli/dist/index.mjs"
out=$(in_fake_home "$home" PEN_CLI_KEY=valid-key -- bash "$CHECK_DEPS")
assert_contains "$out" "Headless CLI (Tier 0)" "auth: a status reply with ANSI colour around Active is accepted"
home=$(make_fake_home auth-env)
node "$TREE" "$home" good >/dev/null
out=$(in_fake_home "$home" PEN_CLI_KEY=valid-key AWS_SECRET_ACCESS_KEY=canary-unrelated GH_TOKEN=canary-token -- bash "$CHECK_DEPS")
assert_contains "$out" "Headless CLI (Tier 0)" "auth with unrelated secrets in the environment: still succeeds"
assert_eq "ARGS=status KEYS=PEN_CLI_KEY" "$(head -1 "$home/engine-env.log")" "auth: the pen status child sees PEN_CLI_KEY and no other key-like variable"
assert_eq "0" "$(grep -c -E 'env .*PEN_CLI_KEY="\$key"' "$CHECK_DEPS" || true)" "check_deps.sh never hands the key to env as an argument (argv exposure)"
assert_eq "0" "$(grep -c -F '\x1b' "$CHECK_DEPS" || true)" "check_deps.sh has no GNU-only x1b sed escape (macOS)"
assert_eq "0" "$(grep -c -E '(^|[^a-z-])cq-pencil-' "$CHECK_DEPS" || true)" "check_deps.sh cites the retired rule only as ex-cq-..."

# --- npm ci output is bounded ---
home=$(make_fake_home bounded)
out=$(in_fake_home "$home" PEN_CLI_KEY=valid-key FAKE_NPM_NOISE=200 -- bash "$CHECK_DEPS" --auto)
noise=$(printf '%s\n' "$out" | grep -c 'npmnoise' || true)
assert_eq "1" "$([[ "$noise" -gt 0 && "$noise" -le 20 ]] && echo 1 || echo 0)" "npm ci output is bounded to its last 20 lines (saw $noise)"

# --- the leftover-package warning is only true when the installed adapter is in sync ---
home=$(make_fake_home legacy-sync)
node "$TREE" "$home" good-plus-legacy >/dev/null
mkdir -p "$home/.local/share/pencil-adapter"
copy_adapter_set "$home/.local/share/pencil-adapter"
out=$(in_home "$home" warn_pen_cli_state)
assert_contains "$out" "it is not used" "leftover deprecated package + adapter in sync: warned as unused"
echo "// stale" >> "$home/.local/share/pencil-adapter/pencil-mcp-adapter.mjs"
out=$(in_home "$home" warn_pen_cli_state)
assert_eq "0" "$(printf '%s\n' "$out" | grep -c 'it is not used' || true)" "leftover deprecated package + STALE adapter: not claimed unused"
assert_contains "$out" "check-adapter-drift --auto" "leftover deprecated package + STALE adapter: says how to sync the adapter"

# ===========================================================================
# FA2c: trust rule (umask, owner/mode, project roots), engine-first order, staging, lock stamps,
# adapter npm failure, portable sha256.
# ===========================================================================
fresh_engine_home() { # <name> -> fake HOME with the `good` engine, stamped as built from the committed lockfile
  local h; h=$(make_fake_home "$1")
  node "$TREE" "$h" good >/dev/null
  stamp_engine "$h"
  printf '%s' "$h"
}

# --- trust rule: a group- or world-writable package directory is refused, with the exact remedy ---
for mode in g+w o+w; do
  home=$(fresh_engine_home "trust-$mode")
  pkg="$home/.local/share/pen-cli/node_modules/@pen.dev/cli"
  chmod "$mode" "$pkg"
  assert_eq "refuse" "$(verdict_of "$(in_home "$home" detect_headless_cli)")" "package dir $mode: detect_headless_cli refuses"
  out=$(in_fake_home "$home" PEN_CLI_KEY=valid-key -- bash "$CHECK_DEPS")
  assert_contains "$out" "group- or world-writable" "package dir $mode: the skip names the cause"
  assert_contains "$out" "chmod -R go-w $home/.local/share/pen-cli/node_modules" "package dir $mode: the skip names the exact remedy"
  chmod -R go-w "$home/.local/share/pen-cli/node_modules"
  assert_eq "accept" "$(verdict_of "$(in_home "$home" detect_headless_cli)")" "package dir $mode: accepted again after chmod -R go-w"
done

# --- trust rule: --auto repairs a group-writable engine (staging install, umask 022, chmod) ---
home=$(fresh_engine_home trust-auto-heal)
chmod -R g+w "$home/.local/share/pen-cli/node_modules"
out=$(umask 002; in_fake_home "$home" PEN_CLI_KEY=valid-key FAKE_NPM_GROUP_WRITABLE=1 -- bash "$CHECK_DEPS" --auto)
assert_contains "$(cat "$home/npm.log")" "UMASK=0022" "--auto install: npm ci runs under umask 022 even from a umask-002 shell"
assert_eq "accept" "$(verdict_of "$(in_home "$home" detect_headless_cli)")" "--auto install over a group-writable engine: accepted afterwards"
assert_eq "no group/world write" "$([[ -z "$(find "$home/.local/share/pen-cli/node_modules" -perm /022 ! -type l 2>/dev/null | head -1)" ]] && echo "no group/world write" || echo "writable files left")" "--auto install: a npm that creates 775 directories is chmod -R go-w'd afterwards"
assert_contains "$out" "Headless CLI (Tier 0)" "--auto install over a group-writable engine: the headless tier is selected"

# --- trust rule: project roots ($HOME is never exempt; the passwd home is, when a root contains it) ---
proj=$(make_fake_home proj-root)
mkdir -p "$proj/fakehome"
node "$TREE" "$proj/fakehome" good >/dev/null
run_in_root() { # <cwd> <home> [VAR=val ...] -- <fn>
  local cwd="$1" h="$2"; shift 2
  local extra=()
  while [[ "$1" != "--" ]]; do extra+=("$1"); shift; done
  shift
  ( cd "$cwd" && env -u PEN_CLI_KEY -u PENCIL_CLI_KEY -u PENCIL_ADAPTER_INSTALL_DIR -u CLAUDE_PROJECT_DIR HOME="$h" "${extra[@]}" \
      bash -c 'f="$1"; shift; args=("$@"); set --; source "$f"; "${args[@]}"; echo "rc=$?"' _ "$CHECK_DEPS" "$@" </dev/null 2>&1 || true )
}
assert_eq "refuse" "$(verdict_of "$(run_in_root "$proj" "$proj/fakehome" -- detect_headless_cli)")" "HOME inside the working directory: the engine is refused (a project env block can set HOME)"
assert_eq "refuse" "$(verdict_of "$(run_in_root "$proj/fakehome" "$proj/fakehome" -- detect_headless_cli)")" "HOME equal to the working directory: refused"
assert_eq "refuse" "$(verdict_of "$(run_in_root "$tmp_dir" "$proj/fakehome" CLAUDE_PROJECT_DIR="$proj" -- detect_headless_cli)")" "HOME inside CLAUDE_PROJECT_DIR: refused"
assert_contains "$(run_in_root "$proj" "$proj/fakehome" -- _pen_inspect)" "inside the working directory or the project directory" "project-root refusal names the cause"
# outside the project: accepted (the control for the three refusals above)
assert_eq "accept" "$(verdict_of "$(run_in_root "$proj" "$tmp_dir/ident-good" -- detect_headless_cli)")" "HOME outside the working directory: accepted"
# the passwd home is exempt from a root that contains it; a different $HOME never is
exempt_out=$( ( cd "$proj" && env -u CLAUDE_PROJECT_DIR HOME="$proj/fakehome" bash -c 'f="$1"; set --; source "$f"; _passwd_home() { printf "%s" "$HOME"; }; detect_headless_cli; echo "rc=$?"' _ "$CHECK_DEPS" </dev/null 2>&1 ) || true )
# cwd = the HOME itself is a root that contains the home: exempt for the passwd candidate, so the install is found
assert_eq "accept" "$(verdict_of "$exempt_out")" "passwd home inside a project root that contains it (cwd = home): exempt, accepted"
exempt_out=$( ( cd "$proj" && env -u CLAUDE_PROJECT_DIR HOME="$proj/fakehome" bash -c 'f="$1"; set --; source "$f"; _passwd_home() { printf "%s" "/somewhere/else"; }; detect_headless_cli; echo "rc=$?"' _ "$CHECK_DEPS" </dev/null 2>&1 ) || true )
assert_eq "refuse" "$(verdict_of "$exempt_out")" "same layout with a HOME that is NOT the passwd home: no exemption (swapping the candidate rule reds this)"

# --- engine reinstall: staged, so a failed reinstall never removes a working engine ---
home=$(make_fake_home keep-working)
node "$TREE" "$home" version-differs >/dev/null
out=$(in_fake_home "$home" PEN_CLI_KEY=valid-key FAKE_NPM_FAIL_ENGINE=1 -- bash "$CHECK_DEPS" --auto)
assert_contains "$out" "FAILED" "failed reinstall: says FAILED"
assert_contains "$out" "left untouched" "failed reinstall over a working engine: says it was left untouched"
assert_eq "accept" "$(verdict_of "$(in_home "$home" detect_headless_cli)")" "failed reinstall: the working engine is still accepted"
assert_contains "$(grep '"version"' "$home/.local/share/pen-cli/node_modules/@pen.dev/cli/package.json")" "0.3.12" "failed reinstall: the old engine is still the one installed"
assert_eq "no staging dir" "$([[ -e "$home/.local/share/pen-cli.new" ]] && echo "staging dir left" || echo "no staging dir")" "failed reinstall: the staging directory is cleaned up"
assert_contains "$out" "PREFERRED_MODE=headless_cli" "failed reinstall: the tier selection is deterministic (the old engine is used)"
# a stage that installs but fails the identity rule is also not swapped in
home=$(make_fake_home keep-working-2)
node "$TREE" "$home" version-differs >/dev/null
out=$(in_fake_home "$home" PEN_CLI_KEY=valid-key TMPDIR="$tmp_dir" -- bash -c 'f="$1"; set --; cd "$TMPDIR" && source "$f"; AUTO_INSTALL=true; _pen_inspect() { printf "WHY\tsynthetic failure\n"; }; detect_headless_cli() { return 1; }; attempt_headless_install; echo "install_rc=$?"' _ "$CHECK_DEPS")
assert_contains "$out" "install_rc=1" "a staged install that fails the identity rule returns non-zero"
assert_contains "$out" "synthetic failure" "a staged install that fails the identity rule says why"
assert_eq "no staging dir" "$([[ -e "$home/.local/share/pen-cli.new" ]] && echo "staging dir left" || echo "no staging dir")" "failed identity check: the staging directory is cleaned up"
assert_contains "$(grep '"version"' "$home/.local/share/pen-cli/node_modules/@pen.dev/cli/package.json")" "0.3.12" "failed identity check: the existing engine is untouched"

# --- engine reinstall is keyed on the lockfile stamp, not only the version ---
home=$(make_fake_home lock-unstamped)
node "$TREE" "$home" good >/dev/null            # at the pin, but no stamp: built before the stamp existed
out=$(in_fake_home "$home" PEN_CLI_KEY=valid-key -- bash "$CHECK_DEPS" --auto)
assert_contains "$(cat "$home/npm.log" 2>/dev/null)" "CWD=$home/.local/share/pen-cli.new" "unstamped engine at the pin + --auto: reinstalled (lockfile may have changed)"
assert_eq "$(sha256sum "$lock_pair/package-lock.json" | awk '{print $1}')" "$(cat "$home/.local/share/pen-cli/node_modules/.soleur-package-lock.sha256")" "reinstall records the committed lockfile hash as the stamp"
: > "$home/npm.log"
out=$(in_fake_home "$home" PEN_CLI_KEY=valid-key -- bash "$CHECK_DEPS" --auto)
assert_eq "no npm" "$([[ -s "$home/npm.log" ]] && echo "npm ran" || echo "no npm")" "stamped engine at the pin + --auto: no reinstall"
echo "0000-a-stamp-from-another-lockfile" > "$home/.local/share/pen-cli/node_modules/.soleur-package-lock.sha256"
out=$(in_fake_home "$home" PEN_CLI_KEY=valid-key -- bash "$CHECK_DEPS" --auto)
assert_contains "$(cat "$home/npm.log" 2>/dev/null)" "CWD=$home/.local/share/pen-cli.new" "engine stamped with another lockfile hash + --auto: reinstalled"

# --- adapter dependency install failure: copy_adapter.sh exits non-zero, writes no stamp, warns ---
home6=$(make_fake_home copy-fail-home)
run_copy_fail() { in_fake_home "$home6" PENCIL_ADAPTER_INSTALL_DIR="$home6/inst" FAKE_NPM_FAIL_ADAPTER=1 -- bash "$COPY"; }
out=$(run_copy_fail)
assert_contains "$out" "rc=3" "copy_adapter.sh with a failing npm ci: exits 3 (not 0)"
assert_contains "$out" "WARN: npm ci failed" "copy_adapter.sh with a failing npm ci: warns"
assert_eq "no stamp" "$([[ -e "$home6/inst/node_modules/.soleur-package-lock.sha256" ]] && echo "stamp written" || echo "no stamp")" "copy_adapter.sh with a failing npm ci (a valid-looking tree is left behind): no lock stamp written"
assert_eq "is a dir" "$([[ -d "$home6/inst/node_modules" ]] && echo "is a dir" || echo "missing")" "(control) the failing fake npm did leave a node_modules behind"
out=$(run_copy_fail)
assert_contains "$out" "Installing adapter dependencies" "copy_adapter.sh: a failed install is retried next run (node_modules exists but has no stamp)"
out=$(in_fake_home "$home6" PENCIL_ADAPTER_INSTALL_DIR="$home6/inst" -- bash "$COPY")
assert_contains "$out" "rc=0" "copy_adapter.sh: the retry with a working npm succeeds"
assert_eq "stamped" "$([[ -s "$home6/inst/node_modules/.soleur-package-lock.sha256" ]] && echo stamped || echo "no stamp")" "copy_adapter.sh: the successful retry writes the stamp"

# --- drift: the adapter's lock stamp is compared with the lockfile when node_modules exists ---
d="$tmp_dir/stamp-drift"; mkdir -p "$d/node_modules"
copy_adapter_set "$d"
sha256sum "$d/package-lock.json" | awk '{print $1}' > "$d/node_modules/.soleur-package-lock.sha256"
set +e; out=$(PENCIL_ADAPTER_INSTALL_DIR="$d" bash "$CHECK_DEPS" --check-adapter-drift 2>&1); rc=$?; set -e
assert_eq "0" "$rc" "files match and node_modules stamped with the lockfile hash: exit 0"
echo "0000-a-stamp-from-another-lockfile" > "$d/node_modules/.soleur-package-lock.sha256"
set +e; out=$(PENCIL_ADAPTER_INSTALL_DIR="$d" bash "$CHECK_DEPS" --check-adapter-drift 2>&1); rc=$?; set -e
assert_eq "3" "$rc" "files match but node_modules stamped with another lockfile hash: DRIFT (exit 3)"
assert_contains "$out" "node_modules" "stale node_modules stamp: the drift names node_modules"
rm -f "$d/node_modules/.soleur-package-lock.sha256"
set +e; out=$(PENCIL_ADAPTER_INSTALL_DIR="$d" bash "$CHECK_DEPS" --check-adapter-drift 2>&1); rc=$?; set -e
assert_eq "3" "$rc" "files match but node_modules has no stamp: DRIFT (exit 3)"
rm -rf "$d/node_modules"
set +e; out=$(PENCIL_ADAPTER_INSTALL_DIR="$d" bash "$CHECK_DEPS" --check-adapter-drift 2>&1); rc=$?; set -e
assert_eq "0" "$rc" "files match and no node_modules at all: exit 0 (nothing to compare)"

# --- --check-adapter-drift --auto: the adapter's npm ci failing is exit 2 with the cause ---
home7=$(fresh_engine_home auto-adapter-fail)
mkdir -p "$home7/.local/share/pencil-adapter"
cp "$repo_adapter" "$home7/.local/share/pencil-adapter/pencil-mcp-adapter.mjs"
echo "// drift" >> "$home7/.local/share/pencil-adapter/pencil-mcp-adapter.mjs"
out=$(in_fake_home "$home7" FAKE_NPM_FAIL_ADAPTER=1 -- bash "$CHECK_DEPS" --check-adapter-drift --auto)
assert_contains "$out" "rc=2" "--auto drift with a failing adapter npm ci: exit 2"
assert_contains "$out" "npm ci failed" "--auto drift with a failing adapter npm ci: names the cause"
assert_eq "0" "$(grep -c 'share/pen-cli' "$home7/npm.log" || true)" "--auto drift with a healthy engine: the engine is not reinstalled while repairing the adapter"

# --- order: the engine is installed FIRST; when it fails the adapter is left exactly as it was ---
assert_contains "$(cat "$home3c/.local/share/pencil-adapter/pencil-mcp-adapter.mjs" | tail -1)" "// drift" "failed engine install: the installed adapter was NOT updated"
assert_eq "0" "$(grep -c "CWD=$home3c/.local/share/pencil-adapter" "$home3c/npm.log" || true)" "failed engine install: the adapter's dependencies were not installed either"
out3c=$(in_fake_home "$home3c" FAKE_NPM_FAIL_ENGINE=1 -- bash "$CHECK_DEPS" --check-adapter-drift --auto)
assert_contains "$out3c" "the installed adapter was NOT changed" "failed engine install: the error says the adapter was not changed"
# and on success the order in the log is engine then adapter
home8=$(make_fake_home order-ok)
mkdir -p "$home8/.local/share/pencil-adapter"
cp "$repo_adapter" "$home8/.local/share/pencil-adapter/pencil-mcp-adapter.mjs"
echo "// drift" >> "$home8/.local/share/pencil-adapter/pencil-mcp-adapter.mjs"
in_fake_home "$home8" -- bash "$CHECK_DEPS" --check-adapter-drift --auto >/dev/null
assert_eq "engine-then-adapter" "$(grep -o 'CWD=[^ ]*' "$home8/npm.log" | sed -e 's|.*pen-cli.new|engine|' -e 's|.*pencil-adapter|adapter|' | tr '\n' '-' | sed 's/-$//;s/engine-adapter/engine-then-adapter/')" "--auto drift: npm runs for the engine before the adapter"

# --- portable sha256: falls back to shasum when sha256sum is not on PATH ---
# The helper is extracted and run with a PATH holding only awk, shasum and perl (no sha256sum).
nosha="$tmp_dir/nosha-bin"; mkdir -p "$nosha"
for t in awk shasum perl; do
  tp=$(command -v "$t" 2>/dev/null) && ln -sf "$tp" "$nosha/$t"
done
printf 'abc' > "$tmp_dir/sha-input"
want_sha=$(sha256sum "$tmp_dir/sha-input" | awk '{print $1}')
sed -n '/^sha256_of() {/,/^}/p' "$CHECK_DEPS" > "$tmp_dir/sha256_of.sh"
got_sha=$(env PATH="$nosha" "$(command -v bash)" -c 'source "$1"; if command -v sha256sum >/dev/null 2>&1; then echo "sha256sum still on PATH"; fi; sha256_of "$2"' _ "$tmp_dir/sha256_of.sh" "$tmp_dir/sha-input" 2>&1 || true)
assert_eq "$want_sha" "$got_sha" "sha256_of falls back to shasum -a 256 when sha256sum is absent"
assert_eq "$want_sha" "$(bash -c 'source "$1"; sha256_of "$2"' _ "$tmp_dir/sha256_of.sh" "$tmp_dir/sha-input")" "sha256_of with sha256sum present gives the same digest"
assert_eq "1" "$(grep -c 'sha256sum --' "$CHECK_DEPS" || true)" "check_deps.sh calls sha256sum only inside the portable helper"

# --- auth probe: an escape sequence splitting the word Active is stripped before matching ---
home=$(make_fake_home auth-split)
node "$TREE" "$home" good >/dev/null
printf '%s\n' 'console.log("  Status  Act\x1b[0mive"); process.exit(0);' > "$home/.local/share/pen-cli/node_modules/@pen.dev/cli/dist/index.mjs"
out=$(in_fake_home "$home" PEN_CLI_KEY=valid-key -- bash "$CHECK_DEPS")
assert_contains "$out" "Headless CLI (Tier 0)" "auth: Active split by an escape sequence (Act<ESC>[0mive) is accepted"
home=$(make_fake_home auth-split-neg)
node "$TREE" "$home" good >/dev/null
printf '%s\n' 'console.log("  Status  Inact\x1b[0mive"); process.exit(0);' > "$home/.local/share/pen-cli/node_modules/@pen.dev/cli/dist/index.mjs"
out=$(in_fake_home "$home" PEN_CLI_KEY=valid-key -- bash "$CHECK_DEPS")
assert_eq "0" "$(printf '%s\n' "$out" | grep -c 'Headless CLI (Tier 0)' || true)" "auth: a reply that only contains Active inside another word is judged on the stripped text"
assert_eq "1" "$(grep -c 'tmo="timeout 20"' "$CHECK_DEPS" || true)" "check_deps.sh bounds pen status with timeout 20"

# --- the identity skip names the specific cause, not a generic message ---
home=$(make_fake_home cause-generic)
node "$TREE" "$home" declared-bin-missing >/dev/null
out=$(in_fake_home "$home" PEN_CLI_KEY=valid-key -- bash "$CHECK_DEPS")
assert_contains "$out" "the package declares no pen bin" "identity skip: names the specific cause (declared-bin-missing)"

print_results 230
